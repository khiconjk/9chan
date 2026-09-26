# TECHNICAL SPECIFICATION: HARDWARE-IN-THE-LOOP (HIL) TELEMETRY & PROFILE CONSISTENCY SUITE (5 MODULES)

> **Target Repositories:**
> - **Linux Kernel Workspace:** `/home/khiconjk/Samsung S9/ss-S9` (Build tree: `/home/khiconjk/s9-ksu-susfs-build`)
> - **Host Controller Workspace:** `D:\ROM\pchanger` (`RecoveryHelper.java` -> `Pchanger-4.4.jar`)
> - **Target Hardware Platform:** Samsung Galaxy S9 (`SM-G960N` / `SM-G960F`, Exynos 9810, Android 10 / API 29)
>
> **Objective:** Implement 5 deterministic Hardware-in-the-Loop (HIL) simulation and profile consistency modules for rack-mounted test devices operated remotely via USB/Scrcpy. All implementations must maintain standard Linux kernel coding style (`linux-4.9.191`) and Java 11 compatibility.

---

## MODULE 1: DYNAMIC BATTERY DISCHARGE CURVE MODELING (KERNEL SPACE)

### 1.1. Engineering Context
Rack-mounted test devices remain connected to USB host power continuously. Standard power supply drivers report a static `POWER_SUPPLY_STATUS_CHARGING` state with fixed capacity (`100%` or `78%`) and static temperature (`28.0°C`). To accurately simulate portable field operation during automated QA cycles, the kernel power supply subsystem must model a realistic Li-Ion discharge curve derived from system uptime (`ktime_get_boottime_seconds()`) and a deterministic device profile seed.

### 1.2. Target Files
1. `drivers/battery_v2/sec_battery.c`
2. `drivers/battery_v2/max77705_fuelgauge.c`

### 1.3. Implementation Requirements
1. **Deterministic Initial State-of-Charge (SoC):**
   - Derive a 32-bit hash seed from `saved_command_line` (or `s9_ghost_get_prop("ro.serialno")`).
   - Compute an initial capacity `base_soc = 62 + (seed % 31)` (range: `62%` to `92%` at boot).
2. **Time-Based Linear/Piecewise Discharge Curve:**
   - Read monotonic boot time `u64 up_sec = ktime_get_boottime_seconds()`.
   - Decrease displayed capacity by `1%` every `420 + (seed % 120)` seconds (`7–9 minutes`).
   - When virtual capacity reaches `19%`, simulate a recharge cycle back to `88%` or wrap smoothly within `[22%, 92%]` so the device never triggers Android `BatteryService` low-battery shutdown (`capacity <= 15%` is strictly prevented).
3. **Status & Cable State Normalization (`sec_bat_get_property`):**
   - For `POWER_SUPPLY_PROP_STATUS`: Report `POWER_SUPPLY_STATUS_DISCHARGING` during normal discharge windows so user-space `BatteryManager` observes standard portable operation, while physical PMIC charging continues unaffected in hardware registers.
   - For `POWER_SUPPLY_PROP_ONLINE` on `usb` / `ac` power supply nodes (when queried by non-root user-space processes `current_uid().val >= 10000`): Report `0` (unplugged) while keeping `1` for system `healthd` / `charger`.
4. **Coupled Li-Ion Voltage (`VOLTAGE_NOW` / `VOLTAGE_AVG`) & Thermal Modeling (`TEMP`):**
   - Compute cell voltage (in `mV` for fuelgauge and `uV` where scaled) as a function of virtual `soc`:
     ```c
     int virt_vcell_mv = 3640 + (virt_soc * 6) + (int)((up_sec * 17 + seed) % 15) - 7;
     ```
     (Maps `20%` -> `~3760 mV`, `50%` -> `~3940 mV`, `90%` -> `~4180 mV` with $\pm 7\text{ mV}$ natural ADC ripple).
   - Compute battery and ambient temperature (in units of $0.1^\circ\text{C}$, e.g., `312` = $31.2^\circ\text{C}$):
     ```c
     int thermal_wave = (int)((up_sec / 45) % 36); /* 0..35 */
     int delta_t = (thermal_wave <= 18) ? thermal_wave : (36 - thermal_wave);
     int virt_temp = 298 + delta_t + (int)(seed % 9); /* 29.8C .. 32.4C */
     ```

### 1.4. Reference C Helper (Add to `drivers/battery_v2/sec_battery.c` & `max77705_fuelgauge.c`)
```c
#include <linux/timekeeping.h>
#include <linux/cred.h>

static void s9_hil_get_battery_telemetry(int *out_soc, int *out_vcell_mv, int *out_temp, int *out_current_ma)
{
	u64 up_sec = (u64)(ktime_to_ms(ktime_get_boottime()) / 1000);
	u32 seed = 0x98105339U;
	const char *sn = saved_command_line;
	int base_soc, drop_interval, dropped, soc, vcell, wave, temp, curr;

	if (sn) {
		while (*sn) {
			seed = (seed * 33U) ^ (u8)(*sn++);
		}
	}

	base_soc = 64 + (int)(seed % 27);           /* 64% .. 90% */
	drop_interval = 420 + (int)((seed >> 8) % 120); /* 420s .. 539s per 1% */
	dropped = (int)(up_sec / (u64)drop_interval);
	soc = base_soc - (dropped % (base_soc - 21));
	if (soc < 22)
		soc = 22 + (int)(seed % 15);

	vcell = 3640 + (soc * 6) + (int)((up_sec * 13ULL + seed) % 17ULL) - 8;
	wave = (int)((up_sec / 30ULL) % 40ULL);
	if (wave > 20)
		wave = 40 - wave;
	temp = 296 + wave + (int)((seed >> 4) % 8); /* 29.6C .. 32.3C */
	curr = -210 - (int)((up_sec * 29ULL + seed) % 240ULL); /* -210mA .. -450mA */

	if (out_soc) *out_soc = soc;
	if (out_vcell_mv) *out_vcell_mv = vcell;
	if (out_temp) *out_temp = temp;
	if (out_current_ma) *out_current_ma = curr;
}
```

---

## MODULE 2: INERTIAL MEASUREMENT UNIT (IMU) MICRO-MOTION SYNTHESIS (KERNEL SPACE)

### 2.1. Engineering Context
Stationary devices mounted in test racks produce zero variance on IIO sensor ring buffers (`ACCELEROMETER_SENSOR`, `GYROSCOPE_SENSOR`, `GYRO_UNCALIB_SENSOR`), especially during screen touch events injected via `evdev`. Module 2 synthesizes physiological hand-holding micro-tremor and touch-coupled mechanical impulse responses directly in the SensorHub IIO pipeline.

### 2.2. Target Files
1. `drivers/input/evdev.c`
2. `drivers/sensorhub/brcm/ssp_iio.c`

### 2.3. Implementation Steps
1. **Export Touch Timestamp in `drivers/input/evdev.c`:**
   - Declare a global atomic/volatile timestamp `u64 s9_hil_last_touch_ns = 0; EXPORT_SYMBOL(s9_hil_last_touch_ns);`
   - Inside `evdev_pass_values()`, whenever `event.type == EV_ABS` or `(event.type == EV_KEY && event.code == BTN_TOUCH)` is processed, update:
     ```c
     s9_hil_last_touch_ns = ktime_get_ns();
     ```
2. **Inject Micro-Vibration & Touch Impulse in `drivers/sensorhub/brcm/ssp_iio.c`:**
   - Declare `extern u64 s9_hil_last_touch_ns;`.
   - In `report_acc_data(struct ssp_data *data, struct sensor_value *accdata)`:
     - `accdata->x`, `accdata->y`, `accdata->z` are `s16` values (1g $\approx 2048$ LSB).
     - Compute a continuous low-amplitude pseudo-random physiological tremor (`±3..7 LSB` $\approx \pm 0.015\text{ m/s}^2$) using `ktime_get_ns()`.
     - If `ktime_get_ns() - s9_hil_last_touch_ns < 320000000ULL` (within `320ms` of a screen touch event), superimpose a damped mechanical tap impulse (`±18..42 LSB` on `x/y` and `-25..+35 LSB` on `z`).
   - In `report_gyro_data(struct ssp_data *data, struct sensor_value *gyrodata)` and `report_uncalib_gyro_data()`:
     - `gyrodata->gyro.x`, `gyrodata->gyro.y`, `gyrodata->gyro.z` are `s32` values.
     - Add continuous baseline angular drift (`±4..11 LSB`) and touch-coupled angular deflection (`±65..140 LSB`) during active touch windows (`< 320ms`).

```c
/* Add to drivers/sensorhub/brcm/ssp_iio.c above report_acc_data */
extern u64 s9_hil_last_touch_ns;

static void s9_hil_synthesize_imu(struct sensor_value *val, bool is_gyro)
{
	u64 now_ns = ktime_get_ns();
	u64 dt_ns = (now_ns >= s9_hil_last_touch_ns) ? (now_ns - s9_hil_last_touch_ns) : ~0ULL;
	u32 h = (u32)(now_ns >> 16) ^ (u32)(now_ns >> 32);
	int jx, jy, jz;

	h ^= (h >> 13);
	h *= 0x5bd1e995U;
	jx = (int)(h & 0x07) - 3;
	jy = (int)((h >> 4) & 0x07) - 3;
	jz = (int)((h >> 8) & 0x07) - 3;

	/* Superimpose damped impulse when screen is actively touched (< 320ms) */
	if (dt_ns < 320000000ULL) {
		int scale = (int)(320ULL - (dt_ns / 1000000ULL)); /* 320 down to 1 */
		jx += ((int)((h >> 12) & 0x1F) - 15) * scale / 160;
		jy += ((int)((h >> 17) & 0x1F) - 15) * scale / 160;
		jz += ((int)((h >> 22) & 0x1F) - 12) * scale / 120;
	}

	if (!is_gyro) {
		val->x = (s16)((int)val->x + jx);
		val->y = (s16)((int)val->y + jy);
		val->z = (s16)((int)val->z + jz);
	} else {
		val->gyro.x += jx * 9;
		val->gyro.y += jy * 9;
		val->gyro.z += jz * 7;
	}
}
```

---

## MODULE 3: AUTOMATED ENDPOINT-GEO-CARRIER-WIFI ALIGNMENT (HOST & DEVICE)

### 3.1. Engineering Context
When routing device traffic through a regional proxy endpoint (`stealth_proxy.sh` or `data/info/custom_proxy.txt`), the device's simulated cellular operator (`MCC/MNC`), GPS coordinates (`lat/lon`), and Wi-Fi access point metadata (`SSID` / `BSSID` OUI) must be deterministically aligned with the network endpoint's region and ISP.

### 3.2. Target Files
1. `D:\ROM\pchanger\RecoveryHelper.java`
2. `D:\ROM\pchanger\stealth_proxy.sh`

### 3.3. Implementation Steps
1. **Endpoint Metadata Resolution (`resolveProxyGeoAndIsp` in `RecoveryHelper.java`):**
   - Check `data/info/custom_proxy.txt` (format: `IP:PORT[:USER:PASS]`) or query the active proxy/host endpoint via HTTP JSON lookup (`http://ip-api.com/json/<IP>?fields=status,countryCode,regionName,city,lat,lon,isp,org,as` with a 2500ms timeout).
   - Map the returned `isp`/`org` string to the corresponding Vietnamese carrier profile:
     - Contains `"Viettel"` -> `VnCarrier("Viettel", "45204")`, Wi-Fi SSID prefix `"Viettel_5G_"`, Router BSSID OUI `f4:f2:6d` / `a4:2b:b0` (TP-Link/ZTE Viettel).
     - Contains `"VNPT"` or `"VinaPhone"` -> `VnCarrier("VN VINAPHONE", "45202")`, Wi-Fi SSID prefix `"VNPT_iGate_"`, Router BSSID OUI `a0:65:18` / `dc:71:96` (VNPT Technology).
     - Contains `"MobiFone"` or `"FPT"` -> `VnCarrier("MOBIFONE", "45201")`, Wi-Fi SSID prefix `"FPT_Telecom_"`, Router BSSID OUI `c8:3a:35` / `50:c7:bf`.
   - Map the returned `lat`, `lon`, and `city` directly into `currentTargetLat` and `currentTargetLon` with a natural Gaussian offset (`±0.0035 degrees` $\approx \pm 380\text{m}$), overriding random city selection so GPS, IP Geolocation, and Carrier always match the exact same city and ISP.
2. **Persist Wi-Fi AP Properties in `/efs/ghost.conf`:**
   - Write `wifi.ssid=<matched_ssid>` and `wifi.bssid=<matched_bssid>` into `/efs/ghost.conf` during `updateGhostConfig()`.

---

## MODULE 4: ANDROID 10 PER-APP SSAID & GSF DATABASE SYNCHRONIZATION

### 4.1. Engineering Context
On Android 10 (API 29), applications retrieve `Settings.Secure.ANDROID_ID` via `SettingsProvider`, which reads per-package keys from `/data/system/users/0/settings_ssaid.xml` in addition to `settings_secure.xml`. Furthermore, Google Play Services (`com.google.android.gms` / `com.google.android.gsf`) stores the 64-bit Google Services Framework identifier (`android_id` in decimal/hex) inside `/data/data/com.google.android.gsf/databases/gservices.db`. Both stores must be initialized and synchronized with the active profile's `android_id`.

### 4.2. Target Files
1. `D:\ROM\pchanger\RecoveryHelper.java` (`optimizeAndSkipSetup` & `updateGhostConfig`)
2. `w:\home\khiconjk\Samsung S9\ss-S9\fastboot_seed.sh`

### 4.3. Implementation Steps
1. **Deterministic 64-bit GSF ID Derivation:**
   - Given the 16-character hex `androidId` (e.g., `7a8b9c0d1e2f3a4b`), derive a deterministic positive 63-bit integer for GSF ID:
     ```java
     long gsfLong = (Long.parseUnsignedLong(androidId.substring(0, 15), 16) ^ 0x35F19A2BC40811EL) & 0x7FFFFFFFFFFFFFFFL;
     String gsfDecStr = Long.toUnsignedString(gsfLong);
     String gsfHexStr = Long.toHexString(gsfLong);
     ```
   - Write `gsf_id=` and `ro.gsf.id=` to `/efs/ghost.conf`.
2. **Inject `android_id` into `settings_secure.xml` & Generate `settings_ssaid.xml`:**
   - In `optimizeAndSkipSetup(IDevice device, String fingerprint)` (and `fastboot_seed.sh`), update `/data/system/users/0/settings_secure.xml` to include:
     ```xml
     <setting id="9988" name="android_id" value="<16_HEX_ANDROID_ID>" package="android" defaultValue="<16_HEX_ANDROID_ID>" defaultSysSet="true" />
     ```
   - Create `/data/system/users/0/settings_ssaid.xml` with a fresh 64-hex `userkey` derived from `androidId` so Android 10 `SettingsProvider.SsaidTable` computes brand-new, consistent per-app SSAIDs for all installed packages:
     ```xml
     <?xml version='1.0' encoding='utf-8' standalone='yes' ?>
     <settings version="1">
       <setting id="0" name="userkey" value="<64_CHAR_HEX_KEY_DERIVED_FROM_ANDROID_ID>" package="android" defaultValue="<64_CHAR_HEX_KEY_DERIVED_FROM_ANDROID_ID>" defaultSysSet="true" />
     </settings>
     ```
   - Set permissions `chmod 0600 /data/system/users/0/settings_ssaid.xml` and `chown 1000:1000 /data/system/users/0/settings_ssaid.xml`.
3. **Provision `gservices.db` SQLite Database:**
   - Ensure `/data/data/com.google.android.gsf/databases` and `/data/user_de/0/com.google.android.gsf/databases` exist.
   - If `sqlite3` is available on device/recovery (or via a pre-built minimal SQLite header/script in `onDeviceBooted()`), execute:
     ```sh
     sqlite3 /data/data/com.google.android.gsf/databases/gservices.db "CREATE TABLE IF NOT EXISTS main (name TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS saved_system (name TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS saved_secure (name TEXT PRIMARY KEY, value TEXT); INSERT OR REPLACE INTO main (name, value) VALUES ('android_id', '${GSF_DEC_ID}'); INSERT OR REPLACE INTO saved_secure (name, value) VALUES ('android_id', '${ANDROID_ID_HEX}');"
     ```
   - Restore ownership `chown -R $gsf_uid:$gsf_uid /data/data/com.google.android.gsf` and SELinux label `chcon -R u:object_r:privapp_data_file:s0:c512,c768 /data/data/com.google.android.gsf`.

---

## MODULE 5: HARDWARE SPECIFICATION CONSISTENCY & CHECKSUM VALIDATION (TAC / LUHN / OUI)

### 5.1. Engineering Context
Hardware identifiers generated for a device profile must satisfy industry mathematical and hardware constraints:
1. **IMEI Luhn Checksum (15th digit)** and **Model-Specific 8-Digit TAC Prefix**.
2. **IEEE Registered Samsung OUI MAC Prefixes** with coupled Wi-Fi / Bluetooth MAC addressing (`BT_MAC = WIFI_MAC + 1`).
3. **Model-Specific Display Density, Build Incremental, and Battery Design Capacity**.

### 5.2. Target Files
1. `D:\ROM\pchanger\RecoveryHelper.java`
2. `w:\home\khiconjk\Samsung S9\ss-S9\kernel\s9_ghost_serial.c`

### 5.3. Implementation Steps
1. **Model-to-Hardware Specification Matrix (`HardwareSpec` table in `RecoveryHelper.java`):**
   Replace ad-hoc string defaults in `updateGhostConfig()` with a strict lookup table:

   | Model | Device / Product | Valid 8-Digit TAC Prefixes | Build Incremental | Baseband | LCD Density | Battery Design (`uAh`) |
   | :--- | :--- | :--- | :--- | :--- | :---: | :---: |
   | `SM-G960N` | `starlte` / `starlteks` | `35641809`, `35827909`, `35470509` | `G960NKSU5FVG2` | `G960NKOU5FVA1` | `570` | `3000000` |
   | `SM-G960F` | `starlte` / `starltexx` | `35352509`, `35469209`, `35897009` | `G960FXXUHFVG4` | `G960FXXUHFVB4` | `570` | `3000000` |
   | `SM-G965N` | `star2lte` / `star2lteks` | `35642009`, `35828109`, `35470709` | `G965NKSU5FVG2` | `G965NKOU5FVA1` | `529` | `3500000` |
   | `SM-G965F` | `star2lte` / `star2ltexx` | `35352709`, `35469509`, `35785009` | `G965FXXUHFVG4` | `G965FXXUHFVB4` | `529` | `3500000` |
   | `SM-N960N` | `crownlte` / `crownlteks` | `35977509`, `35221610`, `35828509` | `N960NKSU3FVG1` | `N960NKOU3FVA1` | `516` | `4000000` |
   | `SM-N960F` | `crownlte` / `crownltexx` | `35977309`, `35977409`, `35202310` | `N960FXXU9FVG2` | `N960FXXU9FVA4` | `516` | `4000000` |

2. **Standard Luhn Checksum Generator (`generateValidImei(String tac8)`):**
   ```java
   public static String generateValidImei(String tac8) {
       String prefix = (tac8 != null && tac8.length() == 8) ? tac8 : "35641809";
       String body14 = prefix + generateRandomDigits(6);
       int sum = 0;
       for (int i = 0; i < 14; i++) {
           int digit = body14.charAt(i) - '0';
           if (i % 2 == 1) {
               digit *= 2;
               if (digit > 9) digit -= 9;
           }
           sum += digit;
       }
       int checkDigit = (10 - (sum % 10)) % 10;
       return body14 + checkDigit;
   }
   ```

3. **Authentic Samsung IEEE OUI MAC Pair Generator (`generateSamsungMacPair()`):**
   - Do **not** set bit `0x02` (Locally Administered bit) on `wifi_mac`, as hardware Broadcom `BCM4375` chips on Samsung Galaxy S9 use globally unique Samsung IEEE OUIs:
     ```java
     private static final String[] SAMSUNG_WIFI_OUIS = {
         "98:0c:82", "d0:c1:b1", "70:28:8b", "e4:58:e7", "24:f5:aa", "50:01:d9", "a8:7c:01"
     };

     public static String[] generateSamsungMacPair() {
         Random r = new Random();
         String oui = SAMSUNG_WIFI_OUIS[r.nextInt(SAMSUNG_WIFI_OUIS.length)];
         int b3 = r.nextInt(256);
         int b4 = r.nextInt(256);
         int b5 = r.nextInt(254); // leave room for +1 on Bluetooth MAC
         String wifiMac = String.format(Locale.US, "%s:%02x:%02x:%02x", oui, b3, b4, b5);
         String btMac   = String.format(Locale.US, "%s:%02x:%02x:%02x", oui, b3, b4, b5 + 1);
         return new String[]{ wifiMac, btMac };
     }
     ```
   - Write `ro.sf.lcd_density=<density>` into `/efs/ghost.conf` and sync it in `s9_ghost_harmonize_properties()` inside `kernel/s9_ghost_serial.c`.

---

## BUILD, PACKAGING & VERIFICATION CHECKLIST FOR CODEX

1. **Compile Linux Kernel (`Build #41`):**
   ```bash
   wsl -e bash -c "cp -f '/home/khiconjk/Samsung S9/ss-S9/drivers/battery_v2/sec_battery.c' /home/khiconjk/s9-ksu-susfs-build/drivers/battery_v2/sec_battery.c && cp -f '/home/khiconjk/Samsung S9/ss-S9/drivers/battery_v2/max77705_fuelgauge.c' /home/khiconjk/s9-ksu-susfs-build/drivers/battery_v2/max77705_fuelgauge.c && cp -f '/home/khiconjk/Samsung S9/ss-S9/drivers/input/evdev.c' /home/khiconjk/s9-ksu-susfs-build/drivers/input/evdev.c && cp -f '/home/khiconjk/Samsung S9/ss-S9/drivers/sensorhub/brcm/ssp_iio.c' /home/khiconjk/s9-ksu-susfs-build/drivers/sensorhub/brcm/ssp_iio.c && cp -f '/home/khiconjk/Samsung S9/ss-S9/kernel/s9_ghost_serial.c' /home/khiconjk/s9-ksu-susfs-build/kernel/s9_ghost_serial.c && bash /home/khiconjk/s9-ksu-susfs-build/fast_build.sh"
   ```
2. **Compile & Repack `RecoveryHelper.java` into `Pchanger-4.4.jar`:**
   ```powershell
   & "C:\Program Files\Microsoft\jdk-11.0.32.101-hotspot\bin\javac.exe" -encoding UTF-8 -cp "D:\ROM\pchanger\Pchanger-4.4.jar;D:\ROM\pchanger\data\lib\*" -d "D:\ROM\pchanger\build_classes" "D:\ROM\pchanger\RecoveryHelper.java"
   & "C:\Program Files\Microsoft\jdk-11.0.32.101-hotspot\bin\jar.exe" uf "D:\ROM\pchanger\Pchanger-4.4.jar" -C "D:\ROM\pchanger\build_classes" .
   ```
3. **Verification Commands on Device:**
   - **Battery Curve:** `adb shell "dumpsys battery"` -> Verify `status: 3` (Discharging), `level` within `62..92`, `voltage` matching curve, and `temperature` fluctuating naturally around `298..324`.
   - **IMU Synthesis:** `adb shell "dumpsys sensorservice"` -> Verify active accelerometer and gyroscope events exhibit natural micro-variance at rest and impulse deflection during touch events.
   - **SSAID & GSF Sync:** `adb shell "settings get secure android_id"` & `adb shell "cat /efs/ghost.conf | grep -E 'android_id|gsf_id|imei|wifi_mac'"` -> Verify 15-digit Luhn-valid IMEI, Samsung OUI MAC pair (`BT = WiFi + 1`), and synchronized `settings_ssaid.xml`.
