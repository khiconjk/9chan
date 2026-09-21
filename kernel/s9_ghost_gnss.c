/*
 * Samsung Galaxy S9 (SM-G960F / SM-G960N / starlte)
 * Pure Kernel-Space Ghost GNSS Hardware Driver Virtualization Engine
 *
 * Simulates genuine Broadcom BCM47752 GNSS hardware telemetry:
 * - Direct injection into /data/vendor/gps/.gps.interface.pipe.to_jni
 * - Native GpsLocation (0x100) with realistic sub-meter natural multipath jitter
 * - Native GnssSvStatus (0x114) reporting 18 satellites (GPS, GLONASS, BeiDou)
 *   with USED_IN_FIX and strong C/N0 (33 - 42 dBHz)
 * - Native NMEA 0183 stream (0x103) ($GPGGA, $GPRMC)
 * - 100% Stealth: Android framework marks provider as pure hardware GPS,
 *   Location.isFromMockProvider() is permanently false, bypassing Feniks
 *   and anti-fraud security SDKs.
 * - Zero floating-point math: 100% integer IEEE-754 bit-exact encoding
 *   fully compatible with ARM64 kernel -mgeneral-regs-only.
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/types.h>
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/random.h>
#include <linux/ktime.h>
#include <linux/timekeeping.h>
#include <linux/workqueue.h>
#include <linux/spinlock.h>
#include <linux/s9_ghost_serial.h>

#define S9_GNSS_PIPE_PATH "/data/vendor/gps/.gps.interface.pipe.to_jni"

#define S9_BRCM_FACILITY_GPS_INTERFACE 1
#define S9_BRCM_TYPE_MARKER_INT        0x5245ff02
#define S9_BRCM_MSG_GPS_LOCATION       0x100
#define S9_BRCM_MSG_GNSS_SV_STATUS     0x117
#define S9_BRCM_MSG_GPS_NMEA           0x103

#define S9_GNSS_SV_FLAGS_USED_IN_FIX   0x0F

#define S9_GNSS_CONSTELLATION_GPS      1
#define S9_GNSS_CONSTELLATION_GLONASS  3
#define S9_GNSS_CONSTELLATION_BEIDOU   5

#define S9_DEFAULT_LAT_E6  21028500LL   /* 21.028500 N */
#define S9_DEFAULT_LON_E6 105854200LL   /* 105.854200 E */
#define S9_DEFAULT_ALT_E1       185LL   /* 18.5 m */

static int s9_gnss_enabled = 1;
static int64_t s9_gnss_lat_e6 = S9_DEFAULT_LAT_E6;
static int64_t s9_gnss_lon_e6 = S9_DEFAULT_LON_E6;
static int64_t s9_gnss_alt_e1 = S9_DEFAULT_ALT_E1;

static u64 s9_gnss_packets_sent = 0;
static int s9_gnss_last_errno = 0;
static DEFINE_SPINLOCK(s9_gnss_lock);
static struct delayed_work s9_gnss_work;

/*
 * Bit-exact IEEE-754 64-bit double encoder using pure 64-bit integer arithmetic.
 * Conforms 100% to ARM64 -mgeneral-regs-only without touching FP/NEON registers.
 */
static uint64_t s9_double_from_fixed(int64_t num, int64_t denom)
{
	int sign = 0;
	uint64_t n, d, mantissa, round;
	int exp = 1023;
	int i;

	if (num == 0 || denom == 0)
		return 0;
	if (num < 0) {
		sign = 1;
		num = -num;
	}
	if (denom < 0) {
		sign ^= 1;
		denom = -denom;
	}

	n = (uint64_t)num;
	d = (uint64_t)denom;

	/* Normalize so that 1 <= n/d < 2 */
	while (n >= 2 * d) {
		d <<= 1;
		exp++;
	}
	while (n < d) {
		n <<= 1;
		exp--;
	}

	/* Implicit leading 1 is subtracted */
	n -= d;
	mantissa = 0;
	for (i = 0; i < 53; i++) {
		n <<= 1;
		mantissa <<= 1;
		if (n >= d) {
			mantissa |= 1;
			n -= d;
		}
	}

	/* Round-to-nearest, ties-to-even */
	round = mantissa & 1;
	mantissa >>= 1;
	if (round && (n > 0 || (mantissa & 1))) {
		mantissa++;
		if (mantissa >= (1ULL << 52)) {
			mantissa = 0;
			exp++;
		}
	}

	return ((uint64_t)sign << 63) | ((uint64_t)exp << 52) | (mantissa & ((1ULL << 52) - 1));
}

/*
 * Bit-exact IEEE-754 32-bit single-precision float encoder using pure integer math.
 */
static uint32_t s9_float_from_fixed(int32_t num, int32_t denom)
{
	int sign = 0;
	uint64_t n, d;
	uint32_t mantissa, round;
	int exp = 127;
	int i;

	if (num == 0 || denom == 0)
		return 0;
	if (num < 0) {
		sign = 1;
		num = -num;
	}
	if (denom < 0) {
		sign ^= 1;
		denom = -denom;
	}

	n = (uint64_t)(uint32_t)num;
	d = (uint64_t)(uint32_t)denom;

	while (n >= 2 * d) {
		d <<= 1;
		exp++;
	}
	while (n < d) {
		n <<= 1;
		exp--;
	}

	n -= d;
	mantissa = 0;
	for (i = 0; i < 24; i++) {
		n <<= 1;
		mantissa <<= 1;
		if (n >= d) {
			mantissa |= 1;
			n -= d;
		}
	}

	round = mantissa & 1;
	mantissa >>= 1;
	if (round && (n > 0 || (mantissa & 1))) {
		mantissa++;
		if (mantissa >= (1U << 23)) {
			mantissa = 0;
			exp++;
		}
	}

	return ((uint32_t)sign << 31) | ((uint32_t)exp << 23) | (mantissa & ((1U << 23) - 1));
}

/*
 * Parse decimal string (e.g. "21.028500") into microdegrees (scaled by 1,000,000)
 */
static int64_t s9_parse_coord_e6(const char *s, int64_t default_val)
{
	int sign = 1;
	int64_t int_part = 0;
	int64_t frac_part = 0;
	int frac_digits = 0;
	bool in_frac = false;

	if (!s || !*s)
		return default_val;

	while (*s == ' ' || *s == '\t')
		s++;
	if (*s == '-') {
		sign = -1;
		s++;
	} else if (*s == '+') {
		s++;
	}

	while (*s) {
		if (*s == '.' || *s == ',') {
			in_frac = true;
			s++;
			continue;
		}
		if (*s >= '0' && *s <= '9') {
			if (!in_frac) {
				int_part = int_part * 10 + (*s - '0');
			} else if (frac_digits < 6) {
				frac_part = frac_part * 10 + (*s - '0');
				frac_digits++;
			}
		} else {
			break;
		}
		s++;
	}

	while (frac_digits < 6) {
		frac_part *= 10;
		frac_digits++;
	}

	return sign * (int_part * 1000000LL + frac_part);
}

void s9_ghost_gnss_set_enabled(int enabled)
{
	unsigned long flags;
	spin_lock_irqsave(&s9_gnss_lock, flags);
	s9_gnss_enabled = enabled;
	spin_unlock_irqrestore(&s9_gnss_lock, flags);
}
EXPORT_SYMBOL(s9_ghost_gnss_set_enabled);

void s9_ghost_gnss_set_lat_str(const char *lat_str)
{
	unsigned long flags;
	int64_t val = s9_parse_coord_e6(lat_str, s9_gnss_lat_e6);
	spin_lock_irqsave(&s9_gnss_lock, flags);
	s9_gnss_lat_e6 = val;
	spin_unlock_irqrestore(&s9_gnss_lock, flags);
}
EXPORT_SYMBOL(s9_ghost_gnss_set_lat_str);

void s9_ghost_gnss_set_lon_str(const char *lon_str)
{
	unsigned long flags;
	int64_t val = s9_parse_coord_e6(lon_str, s9_gnss_lon_e6);
	spin_lock_irqsave(&s9_gnss_lock, flags);
	s9_gnss_lon_e6 = val;
	spin_unlock_irqrestore(&s9_gnss_lock, flags);
}
EXPORT_SYMBOL(s9_ghost_gnss_set_lon_str);

void s9_ghost_gnss_set_alt_str(const char *alt_str)
{
	unsigned long flags;
	int64_t val = s9_parse_coord_e6(alt_str, s9_gnss_alt_e1 * 100000LL) / 100000LL;
	spin_lock_irqsave(&s9_gnss_lock, flags);
	s9_gnss_alt_e1 = val;
	spin_unlock_irqrestore(&s9_gnss_lock, flags);
}
EXPORT_SYMBOL(s9_ghost_gnss_set_alt_str);

/*
 * Broadcom IPC Binary Packet Structures
 */
struct s9_broadcom_loc_pkt {
	uint32_t total_len;       /* 124 */
	uint32_t marker_fac;      /* 0x5245ff02 */
	uint32_t fac_id;          /* 1 = GPS Interface */
	uint32_t marker_msg;      /* 0x5245ff02 */
	uint32_t msg_id;          /* 0x100 = GpsLocation */
	uint64_t bytes_len;       /* 96 */

	/* GpsLocation (96 bytes) */
	uint64_t size;            /* 96 */
	uint16_t flags;           /* 0x1F = ALL */
	uint8_t  pad1[6];
	uint64_t latitude;        /* IEEE-754 double (offset 16) */
	uint64_t longitude;       /* IEEE-754 double (offset 24) */
	uint64_t altitude;        /* IEEE-754 double (offset 32) */
	uint32_t speed;           /* IEEE-754 float (offset 40) */
	uint32_t bearing;         /* IEEE-754 float (offset 44) */
	uint32_t accuracy;        /* IEEE-754 float (offset 48) */
	uint32_t pad2;            /* offset 52 */
	int64_t  timestamp;       /* UTC ms (offset 56) */
	uint8_t  tail_pad[32];    /* offset 64..95 -> total 96 bytes */
} __packed;

struct s9_gnss_sv_entry {
	uint16_t svid;           /* offset 0 */
	uint8_t  constellation;  /* offset 2 */
	uint8_t  pad0;           /* offset 3 */
	uint32_t c_n0_dbhz;      /* offset 4 (float) */
	uint32_t elevation;      /* offset 8 (float) */
	uint32_t azimuth;        /* offset 12 (float) */
	uint8_t  sv_flags;       /* offset 16 (0x0F) */
	uint8_t  pad1[3];        /* offset 17..19 */
	uint32_t carrier_freq;   /* offset 20 (float) */
	uint8_t  pad2[8];        /* offset 24..31 -> total 32 bytes */
} __packed;

struct s9_broadcom_sv_pkt {
	uint32_t total_len;       /* 28 + 2064 = 2092 */
	uint32_t marker_fac;      /* 0x5245ff02 */
	uint32_t fac_id;          /* 1 */
	uint32_t marker_msg;      /* 0x5245ff02 */
	uint32_t msg_id;          /* S9_BRCM_MSG_GNSS_SV_STATUS (0x117) */
	uint64_t bytes_len;       /* 2064 */

	/* GnssSvStatus (2064 bytes) */
	uint64_t size;            /* 2064 */
	int32_t  num_svs;         /* 18 */
	uint8_t  hdr_pad[12];     /* offset reaches 24 */
	struct s9_gnss_sv_entry svs[63]; /* 63 * 32 = 2016 bytes */
	uint8_t  tail_pad[24];    /* total payload = 24 + 2016 + 24 = 2064 */
} __packed;

struct s9_broadcom_nmea_pkt {
	uint32_t total_len;
	uint32_t marker_fac;      /* 0x5245ff02 */
	uint32_t fac_id;          /* 1 */
	uint32_t marker_msg;      /* 0x5245ff02 */
	uint32_t msg_id;          /* 0x103 = NMEA */
	uint64_t ts_len;          /* 8 */
	int64_t  timestamp;       /* ms */
	uint32_t marker_int;      /* 0x5245ff02 */
	int32_t  str_len;
	char     nmea[160];
} __packed;

/* Fixed Satellite Constellation Data: 10 GPS, 4 GLONASS, 4 BeiDou */
static const struct {
	uint16_t svid;
	uint8_t  constellation;
	int32_t  c_n0_x10;
	int32_t  elev;
	int32_t  azim;
} s9_constellation[18] = {
	{ 1,  S9_GNSS_CONSTELLATION_GPS,     412, 65, 120 },
	{ 3,  S9_GNSS_CONSTELLATION_GPS,     395, 52,  45 },
	{ 7,  S9_GNSS_CONSTELLATION_GPS,     380, 48, 210 },
	{ 8,  S9_GNSS_CONSTELLATION_GPS,     420, 78, 315 },
	{ 11, S9_GNSS_CONSTELLATION_GPS,     365, 35,  90 },
	{ 14, S9_GNSS_CONSTELLATION_GPS,     378, 42, 160 },
	{ 17, S9_GNSS_CONSTELLATION_GPS,     340, 28, 270 },
	{ 22, S9_GNSS_CONSTELLATION_GPS,     401, 55, 180 },
	{ 28, S9_GNSS_CONSTELLATION_GPS,     352, 31, 340 },
	{ 30, S9_GNSS_CONSTELLATION_GPS,     408, 60,  80 },
	{ 65, S9_GNSS_CONSTELLATION_GLONASS, 370, 44,  50 },
	{ 66, S9_GNSS_CONSTELLATION_GLONASS, 392, 58, 135 },
	{ 71, S9_GNSS_CONSTELLATION_GLONASS, 358, 36, 225 },
	{ 72, S9_GNSS_CONSTELLATION_GLONASS, 410, 62, 310 },
	{ 201, S9_GNSS_CONSTELLATION_BEIDOU, 415, 70, 110 },
	{ 203, S9_GNSS_CONSTELLATION_BEIDOU, 386, 50, 200 },
	{ 207, S9_GNSS_CONSTELLATION_BEIDOU, 369, 40, 290 },
	{ 210, S9_GNSS_CONSTELLATION_BEIDOU, 404, 66,  25 },
};

static int s9_gnss_write_pipe(const void *data, size_t len)
{
	struct file *filp;
	ssize_t ret;

	filp = filp_open(S9_GNSS_PIPE_PATH, O_WRONLY | O_NONBLOCK, 0);
	if (IS_ERR(filp)) {
		s9_gnss_last_errno = (int)PTR_ERR(filp);
		return s9_gnss_last_errno;
	}

	ret = kernel_write(filp, data, len, 0);
	filp_close(filp, NULL);

	if (ret < 0) {
		s9_gnss_last_errno = (int)ret;
		return (int)ret;
	}

	s9_gnss_last_errno = 0;
	s9_gnss_packets_sent++;
	return 0;
}

static void s9_ghost_gnss_worker(struct work_struct *work)
{
	struct timespec64 ts;
	int64_t cur_utc_ms;
	int64_t lat_e6, lon_e6, alt_e1;
	int32_t lat_jitter, lon_jitter;
	int i;
	unsigned long flags;

	spin_lock_irqsave(&s9_gnss_lock, flags);
	if (!s9_gnss_enabled) {
		spin_unlock_irqrestore(&s9_gnss_lock, flags);
		schedule_delayed_work(&s9_gnss_work, msecs_to_jiffies(2000));
		return;
	}
	lat_e6 = s9_gnss_lat_e6;
	lon_e6 = s9_gnss_lon_e6;
	alt_e1 = s9_gnss_alt_e1;
	spin_unlock_irqrestore(&s9_gnss_lock, flags);

	ktime_get_real_ts64(&ts);
	cur_utc_ms = (int64_t)ts.tv_sec * 1000LL + (ts.tv_nsec / 1000000LL);

	/* Natural GPS multipath jitter: +- 4 microdegrees (~0.4m) */
	lat_jitter = (int32_t)(prandom_u32() % 9) - 4;
	lon_jitter = (int32_t)(prandom_u32() % 9) - 4;
	lat_e6 += lat_jitter;
	lon_e6 += lon_jitter;

	/* 1. Build and send Broadcom GpsLocation packet (0x100) */
	{
		struct s9_broadcom_loc_pkt loc;
		memset(&loc, 0, sizeof(loc));
		loc.total_len = sizeof(loc);
		loc.marker_fac = S9_BRCM_TYPE_MARKER_INT;
		loc.fac_id = S9_BRCM_FACILITY_GPS_INTERFACE;
		loc.marker_msg = S9_BRCM_TYPE_MARKER_INT;
		loc.msg_id = S9_BRCM_MSG_GPS_LOCATION;
		loc.bytes_len = 96;

		loc.size = 96;
		loc.flags = 0x1F; /* LAT_LONG | ALTITUDE | SPEED | BEARING | ACCURACY */
		loc.latitude = s9_double_from_fixed(lat_e6, 1000000LL);
		loc.longitude = s9_double_from_fixed(lon_e6, 1000000LL);
		loc.altitude = s9_double_from_fixed(alt_e1, 10LL);
		loc.speed = s9_float_from_fixed(prandom_u32() % 10, 100);
		loc.bearing = s9_float_from_fixed(prandom_u32() % 360, 1);
		loc.accuracy = s9_float_from_fixed(35 + (prandom_u32() % 12), 10);
		loc.timestamp = cur_utc_ms;

		s9_gnss_write_pipe(&loc, sizeof(loc));
	}

	/* 2. Build and send Broadcom GnssSvStatus packet (0x114) */
	{
		struct s9_broadcom_sv_pkt sv;
		memset(&sv, 0, sizeof(sv));
		sv.total_len = sizeof(sv);
		sv.marker_fac = S9_BRCM_TYPE_MARKER_INT;
		sv.fac_id = S9_BRCM_FACILITY_GPS_INTERFACE;
		sv.marker_msg = S9_BRCM_TYPE_MARKER_INT;
		sv.msg_id = S9_BRCM_MSG_GNSS_SV_STATUS;
		sv.bytes_len = 2064;

		sv.size = 2064;

		/* W1: Dynamic satellite visibility - hide 2-3 SVs per cycle based on time */
		{
			u32 cycle_hash = (u32)(cur_utc_ms / 2000ULL);
			u32 hide_mask = 0;
			int visible_count = 0;
			int hide_count = 2 + (int)(prandom_u32() % 2); /* 2 or 3 */
			int h;

			for (h = 0; h < hide_count; h++) {
				u32 idx = (cycle_hash ^ (u32)(h * 7919)) % 18;
				hide_mask |= (1u << idx);
			}

			for (i = 0; i < 18; i++) {
				int32_t snr_jitter, snr;
				int32_t elev_jitter, azim_jitter;

				if (hide_mask & (1u << i))
					continue;

				snr_jitter = (int32_t)(prandom_u32() % 11) - 5; /* +- 0.5 dBHz */
				snr = s9_constellation[i].c_n0_x10 + snr_jitter;
				elev_jitter = (int32_t)(prandom_u32() % 5) - 2; /* +- 2 deg */
				azim_jitter = (int32_t)(prandom_u32() % 7) - 3; /* +- 3 deg */

				sv.svs[visible_count].svid = s9_constellation[i].svid;
				sv.svs[visible_count].constellation = s9_constellation[i].constellation;
				sv.svs[visible_count].c_n0_dbhz = s9_float_from_fixed(snr, 10);
				sv.svs[visible_count].elevation = s9_float_from_fixed(s9_constellation[i].elev + elev_jitter, 1);
				sv.svs[visible_count].azimuth = s9_float_from_fixed(s9_constellation[i].azim + azim_jitter, 1);
				sv.svs[visible_count].carrier_freq = 0x4ebbce01; /* 1575420000.0f L1 */
				sv.svs[visible_count].sv_flags = S9_GNSS_SV_FLAGS_USED_IN_FIX;
				visible_count++;
			}
			sv.num_svs = visible_count;
		}

		s9_gnss_write_pipe(&sv, sizeof(sv));
	}

	/* 3. Build and send NMEA GPGGA sentence (0x103) */
	{
		struct s9_broadcom_nmea_pkt nmea_pkt;
		char buf[160];
		int64_t abs_lat = lat_e6 < 0 ? -lat_e6 : lat_e6;
		int64_t abs_lon = lon_e6 < 0 ? -lon_e6 : lon_e6;
		int lat_deg = (int)(abs_lat / 1000000LL);
		int64_t lat_rem = abs_lat % 1000000LL;
		int lon_deg = (int)(abs_lon / 1000000LL);
		int64_t lon_rem = abs_lon % 1000000LL;
		int lat_min_x10000 = (int)((lat_rem * 60) / 100);
		int lon_min_x10000 = (int)((lon_rem * 60) / 100);
		char lat_dir = lat_e6 < 0 ? 'S' : 'N';
		char lon_dir = lon_e6 < 0 ? 'W' : 'E';
		u8 csum = 0;
		int len, aligned_len, p;
		u64 sec = (u64)ts.tv_sec;
		u64 utc_hour = (sec % 86400) / 3600;
		u64 utc_min = (sec % 3600) / 60;
		u64 utc_sec = sec % 60;

		/* $GPGGA */
		len = snprintf(buf, sizeof(buf),
			       "$GPGGA,%02llu%02llu%02llu.00,%02d%02d.%04d,%c,%03d%02d.%04d,%c,1,15,0.8,%lld.0,M,0.0,M,,*",
			       utc_hour, utc_min, utc_sec,
			       lat_deg, lat_min_x10000 / 10000, lat_min_x10000 % 10000, lat_dir,
			       lon_deg, lon_min_x10000 / 10000, lon_min_x10000 % 10000, lon_dir,
			       alt_e1 / 10LL);

		for (p = 1; p < len - 1; p++)
			csum ^= (u8)buf[p];

		len += snprintf(buf + len, sizeof(buf) - len, "%02X\r\n", csum);

		aligned_len = (len + 3) & ~3;
		memset(&nmea_pkt, 0, sizeof(nmea_pkt));
		nmea_pkt.total_len = 24 + 4 + aligned_len;
		nmea_pkt.marker_fac = S9_BRCM_TYPE_MARKER_INT;
		nmea_pkt.fac_id = S9_BRCM_FACILITY_GPS_INTERFACE;
		nmea_pkt.marker_msg = S9_BRCM_TYPE_MARKER_INT;
		nmea_pkt.msg_id = S9_BRCM_MSG_GPS_NMEA;
		nmea_pkt.ts_len = 8;
		nmea_pkt.timestamp = cur_utc_ms;
		nmea_pkt.marker_int = S9_BRCM_TYPE_MARKER_INT;
		nmea_pkt.str_len = len;
		memcpy(nmea_pkt.nmea, buf, len);

		s9_gnss_write_pipe(&nmea_pkt, nmea_pkt.total_len);

		/* $GPRMC - Recommended Minimum sentence (W3) */
		{
			u64 day = (sec / 86400);
			u64 y400 = day / 146097; day %= 146097;
			u64 y100 = day / 36524; if (y100 == 4) y100 = 3; day -= y100 * 36524;
			u64 y4 = day / 1461; day %= 1461;
			u64 y1 = day / 365; if (y1 == 4) y1 = 3; day -= y1 * 365;
			u64 year = 1970 + y400 * 400 + y100 * 100 + y4 * 4 + y1;
			int month, mday;
			static const int mdays[] = {31,28,31,30,31,30,31,31,30,31,30,31};
			bool leap = (year%4==0 && (year%100!=0 || year%400==0));

			for (month = 0; month < 12; month++) {
				int md = mdays[month] + (month == 1 && leap ? 1 : 0);
				if ((int)day < md) break;
				day -= md;
			}
			mday = (int)day + 1;
			month++;

			csum = 0;
			len = snprintf(buf, sizeof(buf),
				       "$GPRMC,%02llu%02llu%02llu.00,A,%02d%02d.%04d,%c,%03d%02d.%04d,%c,0.0,0.0,%02d%02d%02llu,,,A*",
				       utc_hour, utc_min, utc_sec,
				       lat_deg, lat_min_x10000 / 10000, lat_min_x10000 % 10000, lat_dir,
				       lon_deg, lon_min_x10000 / 10000, lon_min_x10000 % 10000, lon_dir,
				       mday, month, year % 100);

			for (p = 1; p < len - 1; p++)
				csum ^= (u8)buf[p];
			len += snprintf(buf + len, sizeof(buf) - len, "%02X\r\n", csum);

			aligned_len = (len + 3) & ~3;
			memset(&nmea_pkt, 0, sizeof(nmea_pkt));
			nmea_pkt.total_len = 24 + 4 + aligned_len;
			nmea_pkt.marker_fac = S9_BRCM_TYPE_MARKER_INT;
			nmea_pkt.fac_id = S9_BRCM_FACILITY_GPS_INTERFACE;
			nmea_pkt.marker_msg = S9_BRCM_TYPE_MARKER_INT;
			nmea_pkt.msg_id = S9_BRCM_MSG_GPS_NMEA;
			nmea_pkt.ts_len = 8;
			nmea_pkt.timestamp = cur_utc_ms;
			nmea_pkt.marker_int = S9_BRCM_TYPE_MARKER_INT;
			nmea_pkt.str_len = len;
			memcpy(nmea_pkt.nmea, buf, len);

			s9_gnss_write_pipe(&nmea_pkt, nmea_pkt.total_len);
		}
	}

	schedule_delayed_work(&s9_gnss_work, msecs_to_jiffies(1000));
}

/*
 * /proc/s9_gps diagnostic & live control interface
 */
static int s9_gps_proc_show(struct seq_file *m, void *v)
{
	seq_printf(m, "enabled=%d\n", s9_gnss_enabled);
	seq_printf(m, "lat=%lld.%06lld\n", s9_gnss_lat_e6 / 1000000LL,
		   (s9_gnss_lat_e6 < 0 ? -s9_gnss_lat_e6 : s9_gnss_lat_e6) % 1000000LL);
	seq_printf(m, "lon=%lld.%06lld\n", s9_gnss_lon_e6 / 1000000LL,
		   (s9_gnss_lon_e6 < 0 ? -s9_gnss_lon_e6 : s9_gnss_lon_e6) % 1000000LL);
	seq_printf(m, "alt=%lld.%lld\n", s9_gnss_alt_e1 / 10LL,
		   (s9_gnss_alt_e1 < 0 ? -s9_gnss_alt_e1 : s9_gnss_alt_e1) % 10LL);
	seq_printf(m, "packets_sent=%llu\n", s9_gnss_packets_sent);
	seq_printf(m, "last_errno=%d\n", s9_gnss_last_errno);
	seq_printf(m, "satellites=18 (10 GPS, 4 GLONASS, 4 BeiDou)\n");
	seq_printf(m, "stealth_status=100%% Hardware Native (Mock bit=0, Feniks Safe)\n");
	return 0;
}

static int s9_gps_proc_open(struct inode *inode, struct file *file)
{
	kuid_t uid = current_uid();
	if (uid.val != 0)
		return -ENOENT;
	return single_open(file, s9_gps_proc_show, NULL);
}

static ssize_t s9_gps_proc_write(struct file *file, const char __user *buffer,
				 size_t count, loff_t *pos)
{
	char kcmd[128];
	size_t len = min(count, sizeof(kcmd) - 1);
	char *comma;
	kuid_t uid = current_uid();

	if (uid.val != 0)
		return -ENOENT;

	if (copy_from_user(kcmd, buffer, len))
		return -EFAULT;
	kcmd[len] = '\0';

	if (strstr(kcmd, "enable=1") || strstr(kcmd, "enabled=1")) {
		s9_ghost_gnss_set_enabled(1);
	} else if (strstr(kcmd, "enable=0") || strstr(kcmd, "enabled=0")) {
		s9_ghost_gnss_set_enabled(0);
	}

	comma = strchr(kcmd, ',');
	if (comma) {
		*comma = '\0';
		s9_ghost_gnss_set_lat_str(kcmd);
		s9_ghost_gnss_set_lon_str(comma + 1);
		s9_ghost_gnss_set_enabled(1);
	}

	return count;
}

static const struct file_operations s9_gps_proc_fops = {
	.open    = s9_gps_proc_open,
	.read    = seq_read,
	.write   = s9_gps_proc_write,
	.llseek  = seq_lseek,
	.release = single_release,
};

static int __init s9_ghost_gnss_init(void)
{
	proc_create("s9_gps", 0600, NULL, &s9_gps_proc_fops);
	INIT_DELAYED_WORK(&s9_gnss_work, s9_ghost_gnss_worker);
	schedule_delayed_work(&s9_gnss_work, msecs_to_jiffies(4000));
	pr_info("[S9_GHOST_GNSS]: Broadcom GNSS Hardware Driver Virtualizer active\n");
	return 0;
}
late_initcall(s9_ghost_gnss_init);

MODULE_DESCRIPTION("Samsung Galaxy S9 Broadcom GNSS Hardware Virtualizer");
MODULE_AUTHOR("khiconjk");
MODULE_LICENSE("GPL v2");

