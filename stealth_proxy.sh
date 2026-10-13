#!/system/bin/sh
# ==============================================================================
# S9 Ghost - Stealth Transparent Proxy Engine (Zero VPN Flag / No tun0)
# Uses Netfilter NAT/TPROXY + dual-stack redsocks2 SOCKS5 TCP/UDP
# Automatically hijacks net.typeblog.socks (SocksDroid) to eliminate tun0 & VPN flag!
# ==============================================================================

# Auto elevate to root if running under unprivileged user (e.g. adb shell UID 2000)
if [ "$(id -u)" != "0" ]; then
    if command -v su >/dev/null 2>&1; then
        exec su -c "$0 $*"
    fi
fi

umask 077
echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null
echo $$ > /dev/cpuset/cgroup.procs 2>/dev/null

CONF_DIR="/data/adb/s9_proxy"
mkdir -p "$CONF_DIR" 2>/dev/null
chmod 0700 "$CONF_DIR" 2>/dev/null
chown 0:0 "$CONF_DIR" 2>/dev/null
chmod 0700 /data/adb 2>/dev/null
chown 0:0 /data/adb 2>/dev/null
umount -l /system/etc/init/fastboot_seed.sh 2>/dev/null
rm -f /data/adb/fastboot_seed.sh /data/local/tmp/fastboot_seed.sh /data/adb/stealth_proxy.rules.snapshot "$CONF_DIR/stealth_proxy.rules.snapshot" 2>/dev/null
if [ -d /data/adb ] && [ "$0" != "/data/adb/stealth_proxy.sh" ]; then
    cp -pf "$0" /data/adb/stealth_proxy.sh 2>/dev/null
    chmod 0700 /data/adb/stealth_proxy.sh 2>/dev/null
    chown 0:0 /data/adb/stealth_proxy.sh 2>/dev/null
fi
CONF_FILE="$CONF_DIR/redsocks.conf"
PID_FILE="$CONF_DIR/redsocks.pid"
STATE_FILE="$CONF_DIR/stealth_proxy.state"
STATUS_FILE="$CONF_DIR/stealth_proxy.status"

set_status() {
    local st="$1"
    echo "$st" > "$STATUS_FILE" 2>/dev/null
    chown 0:0 "$STATUS_FILE" 2>/dev/null
    chmod 0644 "$STATUS_FILE" 2>/dev/null
    if [ -f /data/local/tmp/.sp_wait ]; then
        cp -pf "$STATUS_FILE" /data/local/tmp/.sp_res 2>/dev/null
        chmod 0666 /data/local/tmp/.sp_res 2>/dev/null
        rm -f /data/local/tmp/.sp_wait 2>/dev/null
    fi
}

PROXY_MUTEX_DIR="/data/adb/s9_proxy/.lock"
[ -d "/data/adb" ] || PROXY_MUTEX_DIR="/data/local/tmp/.s9_stealth_proxy.lock"
acquire_lock() {
    local tries=0
    while ! mkdir "$PROXY_MUTEX_DIR" 2>/dev/null; do
        tries=$((tries + 1))
        if [ "$tries" -gt 25 ]; then
            rm -rf "$PROXY_MUTEX_DIR" 2>/dev/null
            if mkdir "$PROXY_MUTEX_DIR" 2>/dev/null; then
                break
            else
                echo "[!] Warning: Cannot acquire mutex lock ($PROXY_MUTEX_DIR). Proceeding." >&2
                break
            fi
        fi
        sleep 0.2
    done
}
release_lock() {
    rm -rf "$PROXY_MUTEX_DIR" 2>/dev/null
}

LOCK4_CHAIN="S9_PROXY_LOCK"
LOCK6_CHAIN="S9_PROXY6_LOCK"
PENDING4_CHAIN="S9_PROXY_PENDING"
PENDING6_CHAIN="S9_PROXY6_PENDING"
NAT6_CHAIN="S9_REDSOCKS6"
UDP_OUT_CHAIN="S9_PROXY_UDP_OUT"
UDP_IN_CHAIN="S9_PROXY_UDP_IN"
UDP6_OUT_CHAIN="S9_PROXY6_UDP_OUT"
UDP6_IN_CHAIN="S9_PROXY6_UDP_IN"
TPROXY_MARK="0x40000000"
TPROXY_TABLE="244"
TPROXY_PRIORITY="900"
TPROXY6_MARK="0x20000000"
TPROXY6_TABLE="245"
TPROXY6_PRIORITY="901"
REDUDP_PORT="10054"
REDUDP_PORT6="10055"
REDSOCKS6_PORT="1082"
TCPDNS4_PORT="1053"
TCPDNS6_PORT="1054"
TCPDNS_SERVER1="1.1.1.1:53"
TCPDNS_SERVER2="8.8.8.8:53"
REDSOCKS_LOG="/dev/null"
RULE_DIAG_FILE="/data/adb/stealth_proxy.rules.log"

# Android's netd and vendor services can hold xtables.lock during boot and
# network transitions. Wait for that shared lock instead of failing a proxy
# startup attempt immediately; while waiting, the pending drop guards remain.
IPTABLES_BIN="$(command -v iptables 2>/dev/null)"
IP6TABLES_BIN="$(command -v ip6tables 2>/dev/null)"
iptables() {
    [ -n "$IPTABLES_BIN" ] || return 127
    IPTABLES_OUTPUT=$("$IPTABLES_BIN" -w 30 "$@" 2>&1 1>/dev/null)
    IPTABLES_RC=$?
    if [ -n "$IPTABLES_OUTPUT" ]; then
        case "$IPTABLES_OUTPUT" in
            *"No chain/target/match by that name"*|*"Chain already exists"*|*"Bad rule (does a matching rule exist in that chain?)"*|*"Couldn't find target"*)
                ;;
            *)
                printf '%s\n' "$IPTABLES_OUTPUT" >&2
                ;;
        esac
        case "$IPTABLES_OUTPUT" in
            *"Invalid argument"*|*"Permission denied"*)
                printf '[iptables rc=%s] %s :: %s\n' "$IPTABLES_RC" "$*" "$IPTABLES_OUTPUT" >> "$RULE_DIAG_FILE" 2>/dev/null
                ;;
        esac
    fi
    return "$IPTABLES_RC"
}
ip6tables() {
    [ -n "$IP6TABLES_BIN" ] || return 127
    IP6TABLES_OUTPUT=$("$IP6TABLES_BIN" -w 30 "$@" 2>&1 1>/dev/null)
    IP6TABLES_RC=$?
    if [ -n "$IP6TABLES_OUTPUT" ]; then
        case "$IP6TABLES_OUTPUT" in
            *"No chain/target/match by that name"*|*"Chain already exists"*|*"Bad rule (does a matching rule exist in that chain?)"*|*"Couldn't find target"*)
                ;;
            *)
                printf '%s\n' "$IP6TABLES_OUTPUT" >&2
                ;;
        esac
        case "$IP6TABLES_OUTPUT" in
            *"Invalid argument"*|*"Permission denied"*)
                printf '[ip6tables rc=%s] %s :: %s\n' "$IP6TABLES_RC" "$*" "$IP6TABLES_OUTPUT" >> "$RULE_DIAG_FILE" 2>/dev/null
                ;;
        esac
    fi
    return "$IP6TABLES_RC"
}

kill_vpn_tun0() {
    # Terminate any VpnService / tun2socks processes that create tun0 / TRANSPORT_VPN
    killall -9 libtun2socks.so 2>/dev/null
    pkill -9 -f "libtun2socks.so" 2>/dev/null
    pkill -9 -f "net.typeblog.socks:vpn" 2>/dev/null
    ip link set tun0 down 2>/dev/null
    ip link delete tun0 2>/dev/null
}

cleanup_rules() {
    # Remove every legacy redirect/filter hook, but preserve fail-closed guards.
    while iptables -t nat -D OUTPUT -j REDSOCKS 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null; do :; done
    while iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$TCPDNS4_PORT" 2>/dev/null; do :; done
    iptables -t nat -F REDSOCKS 2>/dev/null
    iptables -t nat -X REDSOCKS 2>/dev/null

    while ip6tables -t nat -D OUTPUT -p tcp -j "$NAT6_CHAIN" 2>/dev/null; do :; done
    while ip6tables -t nat -D OUTPUT -p udp -j "$NAT6_CHAIN" 2>/dev/null; do :; done
    ip6tables -t nat -F "$NAT6_CHAIN" 2>/dev/null
    ip6tables -t nat -X "$NAT6_CHAIN" 2>/dev/null

    while iptables -D OUTPUT -j REDSOCKS_FILTER 2>/dev/null; do :; done
    iptables -F REDSOCKS_FILTER 2>/dev/null
    iptables -X REDSOCKS_FILTER 2>/dev/null

    while ip6tables -D OUTPUT -j REDSOCKS6_FILTER 2>/dev/null; do :; done
    ip6tables -F REDSOCKS6_FILTER 2>/dev/null
    ip6tables -X REDSOCKS6_FILTER 2>/dev/null

    while iptables -t mangle -D OUTPUT -p udp -j "$UDP_OUT_CHAIN" 2>/dev/null; do :; done
    while iptables -t mangle -D PREROUTING -p udp -m mark --mark "$TPROXY_MARK/$TPROXY_MARK" -j "$UDP_IN_CHAIN" 2>/dev/null; do :; done
    iptables -t mangle -F "$UDP_OUT_CHAIN" 2>/dev/null
    iptables -t mangle -X "$UDP_OUT_CHAIN" 2>/dev/null
    iptables -t mangle -F "$UDP_IN_CHAIN" 2>/dev/null
    iptables -t mangle -X "$UDP_IN_CHAIN" 2>/dev/null
    while ip rule del priority "$TPROXY_PRIORITY" fwmark "$TPROXY_MARK/$TPROXY_MARK" table "$TPROXY_TABLE" 2>/dev/null; do :; done
    ip route del local 0.0.0.0/0 dev lo table "$TPROXY_TABLE" 2>/dev/null

    while ip6tables -t mangle -D OUTPUT -p udp -j "$UDP6_OUT_CHAIN" 2>/dev/null; do :; done
    while ip6tables -t mangle -D PREROUTING -p udp -m mark --mark "$TPROXY6_MARK/$TPROXY6_MARK" -j "$UDP6_IN_CHAIN" 2>/dev/null; do :; done
    ip6tables -t mangle -F "$UDP6_OUT_CHAIN" 2>/dev/null
    ip6tables -t mangle -X "$UDP6_OUT_CHAIN" 2>/dev/null
    ip6tables -t mangle -F "$UDP6_IN_CHAIN" 2>/dev/null
    ip6tables -t mangle -X "$UDP6_IN_CHAIN" 2>/dev/null
    while ip -6 rule del priority "$TPROXY6_PRIORITY" fwmark "$TPROXY6_MARK/$TPROXY6_MARK" table "$TPROXY6_TABLE" 2>/dev/null; do :; done
    ip -6 route del local ::/0 dev lo table "$TPROXY6_TABLE" 2>/dev/null
}

setup_guard_chain() {
    TOOL="$1"
    CHAIN="$2"
    PROXY_IP="$3"
    PROXY_PORT="$4"
    PROXY_TYPE="$5"

    "$TOOL" -N "$CHAIN" 2>/dev/null || "$TOOL" -F "$CHAIN" || return 1
    "$TOOL" -F "$CHAIN" || return 1
    # Allow established and related connections
    "$TOOL" -A "$CHAIN" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
    "$TOOL" -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || :
    # Loopback interface
    "$TOOL" -A "$CHAIN" -o lo -j ACCEPT || return 1
    # Immediately reject QUIC / HTTP3 UDP 443 so apps fall back to TCP HTTPS instantly
    # Block WebRTC STUN/TURN (ports 3478, 5349, 19302, 19305) to eliminate WebRTC IP leaks
    if [ "$TOOL" = "ip6tables" ]; then
        "$TOOL" -A "$CHAIN" -p udp --dport 443 -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null || :
        for stun_p in 3478 5349 19302 19305; do
            "$TOOL" -A "$CHAIN" -p udp --dport "$stun_p" -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null || :
        done
    else
        "$TOOL" -A "$CHAIN" -p udp --dport 443 -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || :
        for stun_p in 3478 5349 19302 19305; do
            "$TOOL" -A "$CHAIN" -p udp --dport "$stun_p" -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || :
        done
    fi
    if [ "$TOOL" = "iptables" ]; then
        # CRITICAL: Allow local loopback destination (127.0.0.0/8). Packets redirected
        # by nat REDSOCKS to 127.0.0.1 (redsocks/tcpdns) keep original outdev (wlan0)
        # in filter OUTPUT, so they must match -d 127.0.0.0/8 to avoid being rejected!
        "$TOOL" -A "$CHAIN" -d 127.0.0.0/8 -j ACCEPT || return 1
        # DHCP is required before a Wi-Fi route exists; no app payload is allowed here.
        "$TOOL" -A "$CHAIN" -p udp --sport 68 --dport 67 -j ACCEPT || return 1
        # Block direct DNS to LAN router (192.168.1.1:53) so it cannot bypass tcpdns
        "$TOOL" -A "$CHAIN" -p udp --dport 53 -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || :
        # Allow private LAN subnets and broadcast for gateway/router/ARP communication
        "$TOOL" -A "$CHAIN" -d 10.0.0.0/8 -j ACCEPT || return 1
        "$TOOL" -A "$CHAIN" -d 172.16.0.0/12 -j ACCEPT || return 1
        "$TOOL" -A "$CHAIN" -d 192.168.0.0/16 -j ACCEPT || return 1
        "$TOOL" -A "$CHAIN" -d 224.0.0.0/4 -j ACCEPT || return 1
        "$TOOL" -A "$CHAIN" -d 255.255.255.255/32 -j ACCEPT || return 1
        # SOCKS5 UDP relay traffic may use a provider-selected port, but only
        # to the assigned proxy host; no other UDP destination is permitted.
        if [ "$PROXY_TYPE" = "socks5" ] && [ -n "$PROXY_IP" ]; then
            "$TOOL" -A "$CHAIN" -p udp -d "$PROXY_IP" -j ACCEPT || return 1
        fi
    else
        # IPv6 loopback destination
        "$TOOL" -A "$CHAIN" -d ::1/128 -j ACCEPT || return 1
        # IPv6 control-plane traffic required for SLAAC, NDP, PMTU and DHCPv6.
        "$TOOL" -A "$CHAIN" -p udp --sport 546 --dport 547 -j ACCEPT || return 1
        for icmp6_type in 1 2 3 4 130 131 132 133 134 135 136 143; do
            "$TOOL" -A "$CHAIN" -p ipv6-icmp -m icmp6 --icmpv6-type "$icmp6_type" -j ACCEPT || return 1
        done
        "$TOOL" -A "$CHAIN" -d fe80::/10 -j ACCEPT || return 1
        "$TOOL" -A "$CHAIN" -d ff00::/8 -j ACCEPT || return 1
    fi
    if [ -n "$PROXY_IP" ] && [ -n "$PROXY_PORT" ]; then
        "$TOOL" -A "$CHAIN" -p tcp -d "$PROXY_IP" --dport "$PROXY_PORT" -j ACCEPT || return 1
    fi
    if [ "$TOOL" = "ip6tables" ]; then
        "$TOOL" -A "$CHAIN" -j REJECT --reject-with icmp6-port-unreachable || return 1
    else
        "$TOOL" -A "$CHAIN" -j REJECT --reject-with icmp-port-unreachable || return 1
    fi

    while "$TOOL" -D OUTPUT -j "$CHAIN" 2>/dev/null; do :; done
    "$TOOL" -I OUTPUT 1 -j "$CHAIN" || return 1
    return 0
}

udp4_tproxy_is_active() {
    iptables -t mangle -C OUTPUT -p udp -j "$UDP_OUT_CHAIN" >/dev/null 2>&1 && \
    iptables -t mangle -C PREROUTING -p udp -m mark --mark "$TPROXY_MARK/$TPROXY_MARK" -j "$UDP_IN_CHAIN" >/dev/null 2>&1 && \
    iptables -t mangle -C "$UDP_IN_CHAIN" -p udp -m mark --mark "$TPROXY_MARK/$TPROXY_MARK" \
        -j TPROXY --on-port "$REDUDP_PORT" --tproxy-mark "$TPROXY_MARK/$TPROXY_MARK" >/dev/null 2>&1 && \
    ip rule show 2>/dev/null | grep -F "fwmark $TPROXY_MARK/$TPROXY_MARK lookup $TPROXY_TABLE" >/dev/null 2>&1 && \
    ip route show table "$TPROXY_TABLE" 2>/dev/null | grep -q '^local '
}

udp6_tproxy_is_active() {
    ip6tables -t mangle -C OUTPUT -p udp -j "$UDP6_OUT_CHAIN" >/dev/null 2>&1 && \
    ip6tables -t mangle -C PREROUTING -p udp -m mark --mark "$TPROXY6_MARK/$TPROXY6_MARK" -j "$UDP6_IN_CHAIN" >/dev/null 2>&1 && \
    ip6tables -t mangle -C "$UDP6_IN_CHAIN" -p udp -m mark --mark "$TPROXY6_MARK/$TPROXY6_MARK" \
        -j TPROXY --on-port "$REDUDP_PORT6" --tproxy-mark "$TPROXY6_MARK/$TPROXY6_MARK" >/dev/null 2>&1 && \
    ip -6 rule show 2>/dev/null | grep -F "fwmark $TPROXY6_MARK/$TPROXY6_MARK lookup $TPROXY6_TABLE" >/dev/null 2>&1 && \
    ip -6 route show table "$TPROXY6_TABLE" 2>/dev/null | grep -q '^local '
}

udp_tproxy_is_active() {
    udp4_tproxy_is_active
}

tcp_redirects_are_active() {
    iptables -t nat -C OUTPUT -j REDSOCKS >/dev/null 2>&1 && \
    iptables -t nat -C REDSOCKS -p tcp -j REDIRECT --to-ports 1081 >/dev/null 2>&1 && \
    iptables -t nat -C REDSOCKS -p udp --dport 53 -j REDIRECT --to-ports "$TCPDNS4_PORT" >/dev/null 2>&1
}

redsocks_is_running() {
    REDSOCKS_PID=$(cat "$PID_FILE" 2>/dev/null)
    case "$REDSOCKS_PID" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ -d "/proc/$REDSOCKS_PID" ] || return 1
    grep -E -q 'redsocks2?' "/proc/$REDSOCKS_PID/comm" 2>/dev/null || return 1
    kill -0 "$REDSOCKS_PID" 2>/dev/null
}

kill_redsocks() {
    REDSOCKS_PID=$(cat "$PID_FILE" 2>/dev/null)
    case "$REDSOCKS_PID" in
        ''|*[!0-9]*) ;;
        *)
            if [ -d "/proc/$REDSOCKS_PID" ]; then
                kill -9 "$REDSOCKS_PID" 2>/dev/null
            fi
            ;;
    esac
    killall -9 redsocks redsocks2 2>/dev/null
    pkill -9 redsocks 2>/dev/null
    pkill -9 redsocks2 2>/dev/null
    sleep 0.2
}

setup_socks5_udp_tproxy() {
    [ "$PROXY_TYPE" = "socks5" ] || return 1

    # TPROXY keeps each packet's original destination for SOCKS5 UDP ASSOCIATE.
    # Use separate high fwmark bits, outside Android netd's low fwmark fields.
    ip route replace local 0.0.0.0/0 dev lo table "$TPROXY_TABLE" || return 1
    while ip rule del priority "$TPROXY_PRIORITY" fwmark "$TPROXY_MARK/$TPROXY_MARK" table "$TPROXY_TABLE" 2>/dev/null; do :; done
    ip rule add priority "$TPROXY_PRIORITY" fwmark "$TPROXY_MARK/$TPROXY_MARK" table "$TPROXY_TABLE" || return 1

    iptables -t mangle -N "$UDP_OUT_CHAIN" 2>/dev/null || iptables -t mangle -F "$UDP_OUT_CHAIN" || return 1
    iptables -t mangle -F "$UDP_OUT_CHAIN" || return 1
    iptables -t mangle -A "$UDP_OUT_CHAIN" -d 127.0.0.0/8 -j RETURN || return 1
    iptables -t mangle -A "$UDP_OUT_CHAIN" -d 10.0.0.0/8 -j RETURN || return 1
    iptables -t mangle -A "$UDP_OUT_CHAIN" -d 172.16.0.0/12 -j RETURN || return 1
    iptables -t mangle -A "$UDP_OUT_CHAIN" -d 192.168.0.0/16 -j RETURN || return 1
    iptables -t mangle -A "$UDP_OUT_CHAIN" -p udp -d "$PROXY_IP" -j RETURN || return 1
    # Drop WebRTC STUN/TURN UDP packets in mangle to prevent IP leaks
    for stun_p in 3478 5349 19302 19305; do
        iptables -t mangle -A "$UDP_OUT_CHAIN" -p udp --dport "$stun_p" -j DROP || return 1
    done
    # DNS queries (UDP 53) RETURN from mangle so they reach nat OUTPUT for REDIRECT to 1053
    iptables -t mangle -A "$UDP_OUT_CHAIN" -p udp --dport 53 -j RETURN || return 1
    # Drop UDP port 443 (QUIC/HTTP3) so Google services instantly fallback to TCP HTTPS
    iptables -t mangle -A "$UDP_OUT_CHAIN" -p udp --dport 443 -j DROP || return 1
    iptables -t mangle -A "$UDP_OUT_CHAIN" -p udp -j MARK --set-xmark "$TPROXY_MARK/$TPROXY_MARK" || return 1
    while iptables -t mangle -D OUTPUT -p udp -j "$UDP_OUT_CHAIN" 2>/dev/null; do :; done
    iptables -t mangle -I OUTPUT 1 -p udp -j "$UDP_OUT_CHAIN" || return 1

    iptables -t mangle -N "$UDP_IN_CHAIN" 2>/dev/null || iptables -t mangle -F "$UDP_IN_CHAIN" || return 1
    iptables -t mangle -F "$UDP_IN_CHAIN" || return 1
    iptables -t mangle -A "$UDP_IN_CHAIN" -p udp -m mark --mark "$TPROXY_MARK/$TPROXY_MARK" \
        -j TPROXY --on-port "$REDUDP_PORT" --tproxy-mark "$TPROXY_MARK/$TPROXY_MARK" || return 1
    while iptables -t mangle -D PREROUTING -p udp -m mark --mark "$TPROXY_MARK/$TPROXY_MARK" -j "$UDP_IN_CHAIN" 2>/dev/null; do :; done
    iptables -t mangle -I PREROUTING 1 -p udp -m mark --mark "$TPROXY_MARK/$TPROXY_MARK" -j "$UDP_IN_CHAIN" || return 1

    # IPv6 TPROXY (attempt if supported, don't abort IPv4 proxy if kernel lacks IPv6 TPROXY)
    if command -v ip6tables >/dev/null 2>&1; then
        ip -6 route replace local ::/0 dev lo table "$TPROXY6_TABLE" 2>/dev/null || :
        while ip -6 rule del priority "$TPROXY6_PRIORITY" fwmark "$TPROXY6_MARK/$TPROXY6_MARK" table "$TPROXY6_TABLE" 2>/dev/null; do :; done
        ip -6 rule add priority "$TPROXY6_PRIORITY" fwmark "$TPROXY6_MARK/$TPROXY6_MARK" table "$TPROXY6_TABLE" 2>/dev/null || :

        ip6tables -t mangle -N "$UDP6_OUT_CHAIN" 2>/dev/null || ip6tables -t mangle -F "$UDP6_OUT_CHAIN" 2>/dev/null || :
        ip6tables -t mangle -F "$UDP6_OUT_CHAIN" 2>/dev/null || :
        ip6tables -t mangle -A "$UDP6_OUT_CHAIN" -d ::1/128 -j RETURN 2>/dev/null || :
        ip6tables -t mangle -A "$UDP6_OUT_CHAIN" -p udp --sport 546 --dport 547 -j RETURN 2>/dev/null || :
        for icmp6_type in 1 2 3 4 130 131 132 133 134 135 136 143; do
            ip6tables -t mangle -A "$UDP6_OUT_CHAIN" -p ipv6-icmp -m icmp6 --icmpv6-type "$icmp6_type" -j RETURN 2>/dev/null || :
        done
        for stun_p in 3478 5349 19302 19305; do
            ip6tables -t mangle -A "$UDP6_OUT_CHAIN" -p udp --dport "$stun_p" -j DROP 2>/dev/null || :
        done
        ip6tables -t mangle -A "$UDP6_OUT_CHAIN" -p udp --dport 53 -j DROP 2>/dev/null || :
        ip6tables -t mangle -A "$UDP6_OUT_CHAIN" -p udp --dport 443 -j DROP 2>/dev/null || :
        ip6tables -t mangle -A "$UDP6_OUT_CHAIN" -p udp -j MARK --set-xmark "$TPROXY6_MARK/$TPROXY6_MARK" 2>/dev/null || :
        while ip6tables -t mangle -D OUTPUT -p udp -j "$UDP6_OUT_CHAIN" 2>/dev/null; do :; done
        ip6tables -t mangle -I OUTPUT 1 -p udp -j "$UDP6_OUT_CHAIN" 2>/dev/null || :

        ip6tables -t mangle -N "$UDP6_IN_CHAIN" 2>/dev/null || ip6tables -t mangle -F "$UDP6_IN_CHAIN" 2>/dev/null || :
        ip6tables -t mangle -F "$UDP6_IN_CHAIN" 2>/dev/null || :
        ip6tables -t mangle -A "$UDP6_IN_CHAIN" -p udp -m mark --mark "$TPROXY6_MARK/$TPROXY6_MARK" \
            -j TPROXY --on-port "$REDUDP_PORT6" --tproxy-mark "$TPROXY6_MARK/$TPROXY6_MARK" 2>/dev/null || :
        while ip6tables -t mangle -D PREROUTING -p udp -m mark --mark "$TPROXY6_MARK/$TPROXY6_MARK" -j "$UDP6_IN_CHAIN" 2>/dev/null; do :; done
        ip6tables -t mangle -I PREROUTING 1 -p udp -m mark --mark "$TPROXY6_MARK/$TPROXY6_MARK" -j "$UDP6_IN_CHAIN" 2>/dev/null || :
    fi

    udp4_tproxy_is_active
}

install_fail_closed_guard() {
    GUARD_PROXY_IP="$1"
    GUARD_PROXY_PORT="$2"
    GUARD_PROXY_TYPE="$3"
    PROXY_IP="$GUARD_PROXY_IP"
    PROXY_PORT="$GUARD_PROXY_PORT"
    PROXY_TYPE="$GUARD_PROXY_TYPE"

    command -v iptables >/dev/null 2>&1 || return 1

    # Keep a temporary DROP hook in place while replacing guard rules so a
    # reload never opens a direct-network window.
    iptables -N "$PENDING4_CHAIN" 2>/dev/null || iptables -F "$PENDING4_CHAIN" || return 1
    iptables -F "$PENDING4_CHAIN" || return 1
    iptables -A "$PENDING4_CHAIN" -j DROP || return 1
    while iptables -D OUTPUT -j "$PENDING4_CHAIN" 2>/dev/null; do :; done
    iptables -I OUTPUT 1 -j "$PENDING4_CHAIN" || return 1

    IPV6_FILTERED=0
    if command -v ip6tables >/dev/null 2>&1; then
        if ip6tables -N "$PENDING6_CHAIN" 2>/dev/null || ip6tables -F "$PENDING6_CHAIN" 2>/dev/null; then
            ip6tables -F "$PENDING6_CHAIN" || return 1
            ip6tables -A "$PENDING6_CHAIN" -j DROP || return 1
            while ip6tables -D OUTPUT -j "$PENDING6_CHAIN" 2>/dev/null; do :; done
            ip6tables -I OUTPUT 1 -j "$PENDING6_CHAIN" || return 1
            IPV6_FILTERED=1
        fi
    fi
    if [ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || :
        echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || :
        [ -w /proc/sys/net/ipv6/conf/wlan0/disable_ipv6 ] && echo 1 > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6 2>/dev/null || :
    elif [ "$IPV6_FILTERED" != "1" ]; then
        echo "[!] Cannot enforce fail-closed IPv6 policy."
        return 1
    fi

    setup_guard_chain iptables "$LOCK4_CHAIN" "$GUARD_PROXY_IP" "$GUARD_PROXY_PORT" "$GUARD_PROXY_TYPE" || return 1
    if [ "$IPV6_FILTERED" = "1" ]; then
        setup_guard_chain ip6tables "$LOCK6_CHAIN" "" "" "" || return 1
        while ip6tables -D OUTPUT -j "$PENDING6_CHAIN" 2>/dev/null; do :; done
        ip6tables -F "$PENDING6_CHAIN" 2>/dev/null
        ip6tables -X "$PENDING6_CHAIN" 2>/dev/null
    fi
    while iptables -D OUTPUT -j "$PENDING4_CHAIN" 2>/dev/null; do :; done
    iptables -F "$PENDING4_CHAIN" 2>/dev/null
    iptables -X "$PENDING4_CHAIN" 2>/dev/null
    # setup_guard_chain assigns shell globals; the IPv6 guard uses empty proxy
    # parameters and would otherwise erase the IPv4 endpoint for the caller.
    PROXY_IP="$GUARD_PROXY_IP"
    PROXY_PORT="$GUARD_PROXY_PORT"
    PROXY_TYPE="$GUARD_PROXY_TYPE"
    return 0
}

stop_proxy() {
    kill_vpn_tun0
    cleanup_rules
    kill_redsocks
    # Remove fail-closed lockdown chains so direct internet connectivity is restored
    while iptables -D OUTPUT -j "$LOCK4_CHAIN" 2>/dev/null; do :; done
    iptables -F "$LOCK4_CHAIN" 2>/dev/null
    iptables -X "$LOCK4_CHAIN" 2>/dev/null
    while ip6tables -D OUTPUT -j "$LOCK6_CHAIN" 2>/dev/null; do :; done
    ip6tables -F "$LOCK6_CHAIN" 2>/dev/null
    ip6tables -X "$LOCK6_CHAIN" 2>/dev/null
    [ -w /proc/sys/net/ipv6/conf/wlan0/disable_ipv6 ] && echo 0 > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6 2>/dev/null || :
    [ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ] && echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || :
    [ -w /proc/sys/net/ipv6/conf/default/disable_ipv6 ] && echo 0 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || :
    rm -f "$PID_FILE" "$CONF_FILE" "$STATE_FILE" 2>/dev/null
    rm -f /data/local/tmp/ghost_* /data/local/tmp/redsocks* /data/local/tmp/stealth_proxy* 2>/dev/null
    echo "[OK] Proxy stopped; normal direct network restored."
}

extract_socksdroid_config() {
    PREF_XML="/data/data/net.typeblog.socks/shared_prefs/net.typeblog.socks_preferences.xml"
    [ ! -f "$PREF_XML" ] && return 1
    SD_RUNNING=$(grep 'name="is_running"' "$PREF_XML" 2>/dev/null | sed -n 's/.*value="\([^"]*\)".*/\1/p' | tr -d '\r\n ')
    SD_SVC=$(grep 'name="service_started"' "$PREF_XML" 2>/dev/null | sed -n 's/.*value="\([^"]*\)".*/\1/p' | tr -d '\r\n ')
    if [ "$SD_RUNNING" = "false" ] || [ "$SD_SVC" = "false" ]; then
        return 1
    fi
    SD_IP=$(grep 'name="server_ip"' "$PREF_XML" 2>/dev/null | sed -n 's/.*>\([^<]*\)<\/string>.*/\1/p' | tr -d '\r\n ')
    SD_PORT=$(grep 'name="server_port"' "$PREF_XML" 2>/dev/null | sed -n 's/.*>\([^<]*\)<\/string>.*/\1/p' | tr -d '\r\n ')
    SD_AUTH=$(grep 'name="auth_userpw"' "$PREF_XML" 2>/dev/null | sed -n 's/.*value="\([^"]*\)".*/\1/p' | tr -d '\r\n ')
    SD_USER=""
    SD_PASS=""
    if [ "$SD_AUTH" = "true" ]; then
        SD_USER=$(grep 'name="auth_username"' "$PREF_XML" 2>/dev/null | sed -n 's/.*>\([^<]*\)<\/string>.*/\1/p' | tr -d '\r\n')
        SD_PASS=$(grep 'name="auth_password"' "$PREF_XML" 2>/dev/null | sed -n 's/.*>\([^<]*\)<\/string>.*/\1/p' | tr -d '\r\n')
    fi
    if [ -n "$SD_IP" ] && [ -n "$SD_PORT" ] && [ "$SD_IP" != "127.0.0.1" ]; then
        P_EN="1"
        P_HOST="$SD_IP"
        P_PORT="$SD_PORT"
        P_USER="$SD_USER"
        P_PASS="$SD_PASS"
        P_TYPE="socks5"
        return 0
    fi
    return 1
}

resolve_proxy_config() {
    P_EN="0"
    P_HOST=""
    P_PORT=""
    P_USER=""
    P_PASS=""
    P_TYPE="socks5"
    EXPLICIT_DISABLE="0"

    for p in /data/adb/s9_proxy/ghost_proxy.conf /efs/ghost.conf /data/system/ghost.conf.bak /mnt/vendor/efs/ghost.conf /data/adb/s9_ghost.conf /data/local/tmp/ghost_proxy.conf; do
        if [ -f "$p" ]; then
            if grep -qE '^proxy(\.action=stop|\.enabled=0)' "$p" 2>/dev/null; then
                EXPLICIT_DISABLE="1"
                P_EN="0"
                break
            fi
            if grep -q '^proxy\.enabled=1' "$p" 2>/dev/null; then
                P_EN="1"
                P_HOST=$(grep -E '^proxy\.host=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
                P_PORT=$(grep -E '^proxy\.port=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
                P_USER=$(grep -E '^proxy\.user=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
                P_PASS=$(grep -E '^proxy\.pass=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
                P_TYPE=$(grep -E '^proxy\.type=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
                [ -z "$P_TYPE" ] && P_TYPE="socks5"
                break
            fi
        fi
    done

    if [ "$EXPLICIT_DISABLE" != "1" ] && [ "$P_EN" != "1" ]; then
        extract_socksdroid_config
    fi
}



case "$1" in
    auto)
        acquire_lock
        trap release_lock EXIT INT TERM
        resolve_proxy_config
        if [ "$P_EN" = "1" ] && [ -n "$P_HOST" ] && [ -n "$P_PORT" ]; then
            PASS_SIG=$(printf '%s' "$P_PASS" | cksum 2>/dev/null | cut -d' ' -f1)
            TARGET_SIG="${P_TYPE}://${P_USER}@${P_HOST}:${P_PORT}:${PASS_SIG}"
            CUR_SIG=$(cat "$STATE_FILE" 2>/dev/null)
            if [ "$TARGET_SIG" = "$CUR_SIG" ] && redsocks_is_running && \
               tcp_redirects_are_active && \
               iptables -C OUTPUT -j "$LOCK4_CHAIN" >/dev/null 2>&1; then
                kill_vpn_tun0
                set_status ACTIVE
                start stealth_proxy 2>/dev/null || true
                if ! pgrep -f "stealth_proxy.sh daemon" >/dev/null 2>&1; then
                    nohup /system/bin/sh "$0" daemon >/dev/null 2>&1 &
                fi
                release_lock
                trap - EXIT INT TERM
                exit 0
            fi
            if ! install_fail_closed_guard "$P_HOST" "$P_PORT" "$P_TYPE"; then
                echo "[!] Could not enforce the fail-closed firewall; refusing to change VPN state."
                release_lock
                trap - EXIT INT TERM
                exit 1
            fi
            kill_vpn_tun0
            release_lock
            trap - EXIT INT TERM
            exec "$0" start "$P_HOST" "$P_PORT" "$P_USER" "$P_PASS" "$P_TYPE"
        else
            stop_proxy
            set_status STOPPED
            release_lock
            trap - EXIT INT TERM
            exit 0
        fi
        ;;

    daemon)
        echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null
        echo $$ > /dev/cpuset/cgroup.procs 2>/dev/null
        echo -1000 > /proc/$$/oom_score_adj 2>/dev/null
        renice -n -20 -p $$ 2>/dev/null
        FAIL_COUNT=0
        while true; do
            sleep 15
            [ -d "$PROXY_MUTEX_DIR" ] && continue
            if pgrep -f "stealth_proxy.sh (start|auto|stop)" 2>/dev/null | grep -v "$$" >/dev/null 2>&1; then
                continue
            fi
            resolve_proxy_config
            if [ "$P_EN" = "1" ]; then
                if redsocks_is_running; then
                    FAIL_COUNT=0
                    # Hot-check and re-inject iptables rules if netd cleared them, without killing redsocks
                    if ! tcp_redirects_are_active; then
                        while iptables -t nat -D OUTPUT -j REDSOCKS 2>/dev/null; do :; done
                        iptables -t nat -I OUTPUT 1 -j REDSOCKS 2>/dev/null || :
                        while iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$TCPDNS4_PORT" 2>/dev/null; do :; done
                        iptables -t nat -I PREROUTING 1 -p udp --dport 53 -j REDIRECT --to-ports "$TCPDNS4_PORT" 2>/dev/null || :
                    fi
                    if ! iptables -C OUTPUT -j "$LOCK4_CHAIN" >/dev/null 2>&1; then
                        while iptables -D OUTPUT -j "$LOCK4_CHAIN" 2>/dev/null; do :; done
                        iptables -I OUTPUT 1 -j "$LOCK4_CHAIN" 2>/dev/null || :
                    fi
                    CUR_PID=$(cat "$PID_FILE" 2>/dev/null)
                    if [ -n "$CUR_PID" ] && [ -d "/proc/$CUR_PID" ]; then
                        [ "$(cat /proc/$CUR_PID/oom_score_adj 2>/dev/null)" != "-1000" ] && \
                            echo -1000 > "/proc/$CUR_PID/oom_score_adj" 2>/dev/null
                    fi

                    # Active probe: verify upstream proxy server is actually responding
                    if [ -n "$P_HOST" ] && [ -n "$P_PORT" ]; then
                        if ! toybox nc -w 3 "$P_HOST" "$P_PORT" </dev/null >/dev/null 2>&1; then
                            ENDPOINT_FAILS=$((ENDPOINT_FAILS + 1))
                            if [ "$ENDPOINT_FAILS" -ge 3 ]; then
                                echo "[ALERT] Upstream proxy $P_HOST:$P_PORT is UNREACHABLE / REFUSED!" >> "$CONF_DIR/stealth_proxy.log"
                                set_status DEAD_ENDPOINT
                            fi
                        else
                            ENDPOINT_FAILS=0
                            set_status ACTIVE
                        fi
                    else
                        set_status ACTIVE
                    fi
                    continue
                fi

                # Redsocks process is actually dead
                FAIL_COUNT=$((FAIL_COUNT + 1))
                if [ "$FAIL_COUNT" -ge 2 ]; then
                    FAIL_COUNT=0
                    "$0" auto > "$CONF_DIR/stealth_proxy.log" 2>&1
                    PROXY_RC=$?
                    if [ "$PROXY_RC" -eq 0 ]; then
                        set_status ACTIVE
                    elif grep -q '^\[LOCKED\]' "$CONF_DIR/stealth_proxy.log" 2>/dev/null; then
                        set_status BLOCKED
                    else
                        set_status ERROR
                    fi
                fi
            else
                FAIL_COUNT=0
                if redsocks_is_running || tcp_redirects_are_active; then
                    stop_proxy >/dev/null 2>&1
                fi
                set_status STOPPED
            fi
        done
        ;;

    start)
        acquire_lock
        trap release_lock EXIT INT TERM
        if echo "$2" | grep -q ':'; then
            PROXY_IP=$(echo "$2" | cut -d: -f1)
            PROXY_PORT=$(echo "$2" | cut -d: -f2)
            PROXY_USER="$3"
            PROXY_PASS="$4"
            PROXY_TYPE="${5:-socks5}"
        else
            PROXY_IP="$2"
            PROXY_PORT="$3"
            PROXY_USER="$4"
            PROXY_PASS="$5"
            PROXY_TYPE="${6:-socks5}"
        fi

        if [ -z "$PROXY_IP" ] || [ -z "$PROXY_PORT" ]; then
            resolve_proxy_config
            if [ "$P_EN" = "1" ] && [ -n "$P_HOST" ] && [ -n "$P_PORT" ]; then
                PROXY_IP="$P_HOST"
                PROXY_PORT="$P_PORT"
                PROXY_USER="$P_USER"
                PROXY_PASS="$P_PASS"
                PROXY_TYPE="${P_TYPE:-socks5}"
            else
                echo "Usage: $0 start <PROXY_IP> <PROXY_PORT> [USERNAME] [PASSWORD] [socks5|http]"
                release_lock
                trap - EXIT INT TERM
                exit 1
            fi
        fi

        case "$PROXY_TYPE" in
            http|https|http-connect|http_connect)
                NORMALIZED_PROXY_TYPE="http-connect"
                REDSOCKS_TYPE="http-connect"
                ;;
            socks|socks5|socks5h|"")
                NORMALIZED_PROXY_TYPE="socks5"
                REDSOCKS_TYPE="socks5"
                ;;
            *)
                NORMALIZED_PROXY_TYPE="socks5"
                REDSOCKS_TYPE="socks5"
                ;;
        esac
        PROXY_TYPE="$NORMALIZED_PROXY_TYPE"

        if ! printf '%s\n' "$PROXY_IP" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || \
           ! printf '%s\n' "$PROXY_PORT" | grep -Eq '^[0-9]{1,5}$' || \
           [ "$PROXY_PORT" -lt 1 ] || [ "$PROXY_PORT" -gt 65535 ]; then
            install_fail_closed_guard "" "" >/dev/null 2>&1
            echo "[LOCKED] Invalid IP or port for proxy endpoint."
            release_lock
            trap - EXIT INT TERM
            exit 1
        fi

        mkdir -p "$CONF_DIR" 2>/dev/null
        cat <<EOF > "$CONF_DIR/ghost_proxy.conf"
proxy.enabled=1
proxy.action=start
proxy.host=$PROXY_IP
proxy.port=$PROXY_PORT
proxy.user=$PROXY_USER
proxy.pass=$PROXY_PASS
proxy.type=$PROXY_TYPE
EOF
        chmod 0600 "$CONF_DIR/ghost_proxy.conf" 2>/dev/null

        if ! install_fail_closed_guard "$PROXY_IP" "$PROXY_PORT" "$PROXY_TYPE"; then
            echo "[!] Could not enforce the fail-closed firewall; refusing to start proxy."
            release_lock
            trap - EXIT INT TERM
            exit 1
        fi
        kill_vpn_tun0
        (
            settings put global captive_portal_mode 0
            settings put global captive_portal_detection_enabled 0
            settings put global private_dns_mode off
        ) >/dev/null 2>&1 &
        cleanup_rules
        kill_redsocks
        rm -f "$PID_FILE" "$CONF_FILE" "$STATE_FILE" 2>/dev/null

        cat <<EOF > "$CONF_FILE"
base {
    log_debug = off;
    log_info = off;
    log = "stderr";
    daemon = off;
    redirector = iptables;
    tcp_keepalive_time = 60;
    tcp_keepalive_probes = 5;
    tcp_keepalive_intvl = 10;
    reuseport = off;
}
EOF

        if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
            PROXY_USER_ESC=$(printf '%s' "$PROXY_USER" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')
            PROXY_PASS_ESC=$(printf '%s' "$PROXY_PASS" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')
        else
            PROXY_USER_ESC=""
            PROXY_PASS_ESC=""
        fi

        cat <<EOF >> "$CONF_FILE"
redsocks {
    bind = "127.0.0.1:1081";
    relay = "$PROXY_IP:$PROXY_PORT";
    type = $REDSOCKS_TYPE;
    autoproxy = 0;
    listenq = 1024;
    timeout = 180;
EOF
        if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
            printf '    login = "%s";\n' "$PROXY_USER_ESC" >> "$CONF_FILE"
            printf '    password = "%s";\n' "$PROXY_PASS_ESC" >> "$CONF_FILE"
        fi
        echo "}" >> "$CONF_FILE"

        if [ "$REDSOCKS_TYPE" = "socks5" ]; then
            cat <<EOF >> "$CONF_FILE"
redudp {
    bind = "0.0.0.0:$REDUDP_PORT";
    relay = "$PROXY_IP:$PROXY_PORT";
    type = socks5;
EOF
            if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
                printf '    login = "%s";\n' "$PROXY_USER_ESC" >> "$CONF_FILE"
                printf '    password = "%s";\n' "$PROXY_PASS_ESC" >> "$CONF_FILE"
            fi
            echo "}" >> "$CONF_FILE"
        fi

        cat <<EOF >> "$CONF_FILE"
tcpdns {
    bind = "127.0.0.1:$TCPDNS4_PORT";
    tcpdns1 = "$TCPDNS_SERVER1";
    tcpdns2 = "$TCPDNS_SERVER2";
    timeout = 15;
}
EOF

        chmod 0600 "$CONF_FILE"
        REDSOCKS_BIN="/system/bin/redsocks2"
        [ ! -x "$REDSOCKS_BIN" ] && REDSOCKS_BIN="/data/adb/redsocks2"
        if ! "$REDSOCKS_BIN" -t -c "$CONF_FILE" >/dev/null 2>&1; then
            echo "[!] redsocks rejected its generated configuration."
            stop_proxy >/dev/null 2>&1
            release_lock
            trap - EXIT INT TERM
            exit 1
        fi
        "$REDSOCKS_BIN" -c "$CONF_FILE" >/dev/null 2>&1 &
        REDSOCKS_PID=$!
        echo "$REDSOCKS_PID" > /sys/fs/cgroup/cgroup.procs 2>/dev/null
        echo "$REDSOCKS_PID" > /dev/cpuset/cgroup.procs 2>/dev/null
        echo -1000 > "/proc/$REDSOCKS_PID/oom_score_adj" 2>/dev/null
        renice -n -20 -p "$REDSOCKS_PID" 2>/dev/null
        echo "$REDSOCKS_PID" > "$PID_FILE"
        chmod 0600 "$PID_FILE"
        sleep 1

        # Purge any leaked logs or temporary files in /data/local/tmp
        rm -f /data/local/tmp/ghost_* /data/local/tmp/redsocks* /data/local/tmp/stealth_proxy* 2>/dev/null

        if ! kill -0 "$REDSOCKS_PID" 2>/dev/null; then
            echo "[!] Failed to start proxy runtime $REDSOCKS_BIN"
            stop_proxy >/dev/null 2>&1
            release_lock
            trap - EXIT INT TERM
            exit 1
        fi

        if [ "$REDSOCKS_TYPE" = "socks5" ]; then
            if ! setup_socks5_udp_tproxy; then
                echo "[WARN] UDP TPROXY setup failed; continuing with full TCP proxying."
            fi
        fi

        # Redirect TCP through SOCKS/HTTP proxy and DNS through tcpdns.
        iptables -t nat -N REDSOCKS 2>/dev/null || iptables -t nat -F REDSOCKS
        iptables -t nat -F REDSOCKS
        # Intercept UDP DNS (port 53) and redirect to tcpdns BEFORE private IP bypass
        iptables -t nat -A REDSOCKS -p udp --dport 53 -j REDIRECT --to-ports "$TCPDNS4_PORT"
        iptables -t nat -A REDSOCKS -d 0.0.0.0/8 -j RETURN
        iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
        iptables -t nat -A REDSOCKS -d "$PROXY_IP" -j RETURN
        # Exclude private subnets from being redirected
        iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
        iptables -t nat -A REDSOCKS -d 169.254.0.0/16 -j RETURN
        iptables -t nat -A REDSOCKS -d 172.16.0.0/12 -j RETURN
        iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
        iptables -t nat -A REDSOCKS -d 224.0.0.0/4 -j RETURN
        iptables -t nat -A REDSOCKS -d 240.0.0.0/4 -j RETURN
        # Forward all remaining TCP traffic to redsocks
        iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 1081
        iptables -t nat -C REDSOCKS -p tcp -j REDIRECT --to-ports 1081 || {
            echo "[!] TCP redirect failed; fail-closed output guard remains active."
            stop_proxy >/dev/null 2>&1
            release_lock
            trap - EXIT INT TERM
            exit 1
        }

        while ip6tables -t nat -D OUTPUT -p tcp -j "$NAT6_CHAIN" 2>/dev/null; do :; done
        while ip6tables -t nat -D OUTPUT -p udp -j "$NAT6_CHAIN" 2>/dev/null; do :; done
        ip6tables -t nat -F "$NAT6_CHAIN" 2>/dev/null
        ip6tables -t nat -X "$NAT6_CHAIN" 2>/dev/null

        while iptables -t nat -D OUTPUT -j REDSOCKS 2>/dev/null; do :; done
        iptables -t nat -I OUTPUT 1 -j REDSOCKS || {
            echo "[!] NAT redirect setup failed; fail-closed output guard remains active."
            stop_proxy >/dev/null 2>&1
            release_lock
            trap - EXIT INT TERM
            exit 1
        }

        while iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$TCPDNS4_PORT" 2>/dev/null; do :; done
        iptables -t nat -I PREROUTING 1 -p udp --dport 53 -j REDIRECT --to-ports "$TCPDNS4_PORT" 2>/dev/null || :

        PASS_SIG=$(printf '%s' "$PROXY_PASS" | cksum 2>/dev/null | cut -d' ' -f1)
        echo "${PROXY_TYPE}://${PROXY_USER}@${PROXY_IP}:${PROXY_PORT}:${PASS_SIG}" > "$STATE_FILE"
        chmod 0600 "$STATE_FILE" 2>/dev/null
        set_status ACTIVE
        echo "[OK] Stealth Transparent Proxy ACTIVE ($PROXY_TYPE://$PROXY_IP:$PROXY_PORT)"
        echo "     - TCP IPv4+IPv6: redirected through redsocks2 ($REDSOCKS_TYPE)"
        if [ "$REDSOCKS_TYPE" = "socks5" ]; then
            echo "     - UDP IPv4+IPv6: SOCKS5 ASSOCIATE via TPROXY"
        fi
        echo "     - Direct application egress: BLOCKED; DNS/DHCP control exempt"
        start stealth_proxy 2>/dev/null || true
        if ! pgrep -f "stealth_proxy.sh daemon" >/dev/null 2>&1; then
            nohup /system/bin/sh "$0" daemon >/dev/null 2>&1 &
        fi
        release_lock
        trap - EXIT INT TERM
        exit 0
        ;;

    stop)
        acquire_lock
        trap release_lock EXIT INT TERM
        for cf in "$CONF_DIR/ghost_proxy.conf" /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/adb/s9_ghost.conf /data/local/tmp/ghost_proxy.conf; do
            if [ -f "$cf" ]; then
                sed -i 's/^proxy\.enabled=1/proxy.enabled=0/g' "$cf" 2>/dev/null
                sed -i 's/^proxy\.action=start/proxy.action=stop/g' "$cf" 2>/dev/null
            fi
        done
        stop stealth_proxy 2>/dev/null || true
        pkill -f "stealth_proxy.sh daemon" 2>/dev/null || true
        stop_proxy
        set_status STOPPED
        echo "[OK] Proxy stopped; normal direct network restored."
        release_lock
        trap - EXIT INT TERM
        exit 0
        ;;

    status)
        if redsocks_is_running && tcp_redirects_are_active && iptables -C OUTPUT -j "$LOCK4_CHAIN" >/dev/null 2>&1; then
            echo "[STATUS] Dual-stack SOCKS5 Proxy: ACTIVE (PID: $(cat "$PID_FILE" 2>/dev/null), Target: $(cat "$STATE_FILE" 2>/dev/null))"
            iptables -t nat -L REDSOCKS -n -v 2>/dev/null
            ip6tables -t nat -L "$NAT6_CHAIN" -n -v 2>/dev/null
            iptables -L "$LOCK4_CHAIN" -n -v 2>/dev/null
            ip6tables -L "$LOCK6_CHAIN" -n -v 2>/dev/null
        else
            echo "[STATUS] Dual-stack SOCKS5 Proxy: INACTIVE or fail-closed"
        fi
        exit 0
        ;;

    *)
        echo "Usage:"
        echo "  $0 auto"
        echo "  $0 daemon"
        echo "  $0 start <PROXY_IP> <PROXY_PORT> [USERNAME] [PASSWORD] socks5"
        echo "  $0 stop"
        echo "  $0 status"
        exit 1
        ;;
esac
