#!/system/bin/sh
# ==============================================================================
# S9 Ghost - Stealth Transparent Proxy Engine (Zero VPN Flag / No tun0)
# Uses Netfilter NAT/TPROXY + dual-stack redsocks2 SOCKS5 TCP/UDP
# Automatically hijacks net.typeblog.socks (SocksDroid) to eliminate tun0 & VPN flag!
# ==============================================================================

umask 022

CONF_DIR="/data/adb/s9_proxy"
mkdir -p "$CONF_DIR" 2>/dev/null
chmod 0770 "$CONF_DIR" 2>/dev/null
chown root:shell "$CONF_DIR" 2>/dev/null
chmod 0750 /data/adb 2>/dev/null
chown root:shell /data/adb 2>/dev/null
if [ -d /data/adb ] && [ "$0" != "/data/adb/stealth_proxy.sh" ]; then
    cp -pf "$0" /data/adb/stealth_proxy.sh 2>/dev/null
    chmod 0755 /data/adb/stealth_proxy.sh 2>/dev/null
    chown root:root /data/adb/stealth_proxy.sh 2>/dev/null
fi
CONF_FILE="$CONF_DIR/redsocks.conf"
PID_FILE="$CONF_DIR/redsocks.pid"
STATE_FILE="$CONF_DIR/stealth_proxy.state"
STATUS_FILE="$CONF_DIR/stealth_proxy.status"
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
        printf '%s\n' "$IPTABLES_OUTPUT" >&2
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
        printf '%s\n' "$IP6TABLES_OUTPUT" >&2
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
    if [ "$TOOL" = "iptables" ]; then
        # CRITICAL: Allow local loopback destination (127.0.0.0/8). Packets redirected
        # by nat REDSOCKS to 127.0.0.1 (redsocks/tcpdns) keep original outdev (wlan0)
        # in filter OUTPUT, so they must match -d 127.0.0.0/8 to avoid being rejected!
        "$TOOL" -A "$CHAIN" -d 127.0.0.0/8 -j ACCEPT || return 1
        # DHCP is required before a Wi-Fi route exists; no app payload is allowed here.
        "$TOOL" -A "$CHAIN" -p udp --sport 68 --dport 67 -j ACCEPT || return 1
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
    iptables -t nat -C REDSOCKS -p tcp -j REDIRECT --to-ports 1081 >/dev/null 2>&1
}

redsocks_is_running() {
    REDSOCKS_PID=$(cat "$PID_FILE" 2>/dev/null)
    case "$REDSOCKS_PID" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ -r "/proc/$REDSOCKS_PID/cmdline" ] || return 1
    tr '\000' ' ' < "/proc/$REDSOCKS_PID/cmdline" | grep -q 'redsocks2' || return 1
    kill -0 "$REDSOCKS_PID" 2>/dev/null
}

kill_redsocks() {
    REDSOCKS_PID=$(cat "$PID_FILE" 2>/dev/null)
    case "$REDSOCKS_PID" in
        ''|*[!0-9]*) ;;
        *)
            if [ -r "/proc/$REDSOCKS_PID/cmdline" ] && \
               tr '\000' ' ' < "/proc/$REDSOCKS_PID/cmdline" | grep -q 'redsocks2'; then
                kill -9 "$REDSOCKS_PID" 2>/dev/null
            fi
            ;;
    esac
    killall -9 redsocks redsocks2 2>/dev/null
    pkill -9 redsocks 2>/dev/null
    pkill -9 redsocks2 2>/dev/null
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
    iptables -t mangle -A "$UDP_OUT_CHAIN" -p udp --dport 53 -j RETURN || return 1
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
        ip6tables -t mangle -A "$UDP6_OUT_CHAIN" -p udp --dport 53 -j RETURN 2>/dev/null || :
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
    if [ "$IPV6_FILTERED" != "1" ]; then
        if [ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ] && [ -w /proc/sys/net/ipv6/conf/default/disable_ipv6 ]; then
            echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 || return 1
            echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 || return 1
        else
            echo "[!] Cannot enforce fail-closed IPv6 policy."
            return 1
        fi
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
        resolve_proxy_config
        if [ "$P_EN" = "1" ] && [ -n "$P_HOST" ] && [ -n "$P_PORT" ]; then
            PASS_SIG=$(printf '%s' "$P_PASS" | cksum 2>/dev/null | cut -d' ' -f1)
            TARGET_SIG="${P_TYPE}://${P_USER}@${P_HOST}:${P_PORT}:${PASS_SIG}"
            CUR_SIG=$(cat "$STATE_FILE" 2>/dev/null)
            # Do not tear down a healthy live proxy just to repeat a TCP probe
            # every guardian tick. A transient probe failure must not remove
            # working redirects/UDP rules and strand Android without a route.
            if [ "$TARGET_SIG" = "$CUR_SIG" ] && redsocks_is_running && \
               tcp_redirects_are_active && \
               iptables -C OUTPUT -j "$LOCK4_CHAIN" >/dev/null 2>&1; then
                kill_vpn_tun0
                exit 0
            fi
            if ! toybox nc -w 3 "$P_HOST" "$P_PORT" </dev/null >/dev/null 2>&1; then
                stop_proxy
                echo "[ERROR] Proxy endpoint $P_HOST:$P_PORT is offline or unreachable."
                exit 1
            fi
            if ! install_fail_closed_guard "$P_HOST" "$P_PORT" "$P_TYPE"; then
                echo "[!] Could not enforce the fail-closed firewall; refusing to change VPN state."
                exit 1
            fi
            kill_vpn_tun0
            exec "$0" start "$P_HOST" "$P_PORT" "$P_USER" "$P_PASS" "$P_TYPE"
        else
            stop_proxy
            exit 0
        fi
        ;;

    daemon)
        while true; do
            if pgrep -f "stealth_proxy.sh (start|auto|stop)" 2>/dev/null | grep -v "$$" >/dev/null 2>&1; then
                sleep 5
                continue
            fi
            resolve_proxy_config
            if [ "$P_EN" = "1" ]; then
                if redsocks_is_running && tcp_redirects_are_active; then
                    sleep 10
                    continue
                fi
                "$0" auto > "$CONF_DIR/stealth_proxy.log" 2>&1
                PROXY_RC=$?
                if [ "$PROXY_RC" -eq 0 ]; then
                    echo ACTIVE > "$STATUS_FILE"
                elif grep -q '^\[LOCKED\]' "$CONF_DIR/stealth_proxy.log" 2>/dev/null; then
                    echo BLOCKED > "$STATUS_FILE"
                else
                    echo ERROR > "$STATUS_FILE"
                fi
            else
                if redsocks_is_running || tcp_redirects_are_active; then
                    stop_proxy >/dev/null 2>&1
                fi
                echo STOPPED > "$STATUS_FILE"
            fi
            chmod 0644 "$STATUS_FILE" 2>/dev/null
            sleep 10
        done
        ;;

    start)
        PROXY_IP="$2"
        PROXY_PORT="$3"
        PROXY_USER="$4"
        PROXY_PASS="$5"
        PROXY_TYPE="${6:-socks5}"

        if [ -z "$PROXY_IP" ] || [ -z "$PROXY_PORT" ]; then
            resolve_proxy_config
            if [ "$P_EN" = "1" ] && [ -n "$P_HOST" ] && [ -n "$P_PORT" ]; then
                PROXY_IP="$P_HOST"
                PROXY_PORT="$P_PORT"
                PROXY_USER="$P_USER"
                PROXY_PASS="$P_PASS"
                PROXY_TYPE="${P_TYPE:-socks5}"
            else
            echo "Usage: $0 start <PROXY_IP> <PROXY_PORT> [USERNAME] [PASSWORD] socks5"
                exit 1
            fi
        fi

        if ! printf '%s\n' "$PROXY_IP" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || \
           ! printf '%s\n' "$PROXY_PORT" | grep -Eq '^[0-9]{1,5}$' || \
           [ "$PROXY_PORT" -lt 1 ] || [ "$PROXY_PORT" -gt 65535 ] || \
           [ "$PROXY_TYPE" != "socks5" ]; then
            install_fail_closed_guard "" "" >/dev/null 2>&1
            echo "[LOCKED] Invalid endpoint or non-SOCKS5 proxy; SOCKS5 is required for dual-stack TCP+UDP forwarding."
            exit 1
        fi

        if ! install_fail_closed_guard "$PROXY_IP" "$PROXY_PORT" "$PROXY_TYPE"; then
            echo "[!] Could not enforce the fail-closed firewall; refusing to start proxy."
            exit 1
        fi
        kill_vpn_tun0
        cleanup_rules
        kill_redsocks
        rm -f "$PID_FILE" "$CONF_FILE" "$STATE_FILE" "$REDSOCKS_LOG" 2>/dev/null

        # Verify proxy endpoint is reachable before redirecting system traffic
        if ! toybox nc -w 3 "$PROXY_IP" "$PROXY_PORT" </dev/null >/dev/null 2>&1; then
            FAILED_PROXY_IP="$PROXY_IP"
            FAILED_PROXY_PORT="$PROXY_PORT"
            stop_proxy >/dev/null 2>&1
            echo "[ERROR] Proxy endpoint $FAILED_PROXY_IP:$FAILED_PROXY_PORT is unreachable."
            exit 1
        fi

        cat <<EOF > "$CONF_FILE"
base {
    log_debug = off;
    log_info = off;
    log = "stderr";
    daemon = off;
    redirector = iptables;
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
    type = socks5;
    autoproxy = 0;
EOF
        if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
            printf '    login = "%s";\n' "$PROXY_USER_ESC" >> "$CONF_FILE"
            printf '    password = "%s";\n' "$PROXY_PASS_ESC" >> "$CONF_FILE"
        fi
        echo "}" >> "$CONF_FILE"

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

        cat <<EOF >> "$CONF_FILE"
tcpdns {
    bind = "127.0.0.1:$TCPDNS4_PORT";
    tcpdns1 = "$TCPDNS_SERVER1";
    tcpdns2 = "$TCPDNS_SERVER2";
    timeout = 5;
}
EOF
        chmod 0600 "$CONF_FILE"
        REDSOCKS_BIN="/system/bin/redsocks2"
        [ ! -x "$REDSOCKS_BIN" ] && REDSOCKS_BIN="/data/adb/redsocks2"
        if ! "$REDSOCKS_BIN" -t -c "$CONF_FILE" >/dev/null 2>&1; then
            echo "[!] redsocks rejected its generated SOCKS5/UDP configuration."
            stop_proxy >/dev/null 2>&1
            exit 1
        fi
        "$REDSOCKS_BIN" -c "$CONF_FILE" >/dev/null 2>&1 &
        REDSOCKS_PID=$!
        echo "$REDSOCKS_PID" > "$PID_FILE"
        chmod 0600 "$PID_FILE"
        sleep 1

        # Purge any leaked logs or temporary files in /data/local/tmp
        rm -f /data/local/tmp/ghost_* /data/local/tmp/redsocks* /data/local/tmp/stealth_proxy* 2>/dev/null

        if ! kill -0 "$REDSOCKS_PID" 2>/dev/null; then
            echo "[!] Failed to start dual-stack SOCKS5 runtime $REDSOCKS_BIN"
            stop_proxy >/dev/null 2>&1
            exit 1
        fi

        if ! setup_socks5_udp_tproxy; then
            echo "[WARN] UDP TPROXY setup failed; continuing with full TCP+DNS proxying."
        fi

        # Redirect TCP through SOCKS. DNS UDP uses local tcpdns, which sends
        # DNS/TCP through redsocks; other UDP remains on the SOCKS5 TPROXY path.
        iptables -t nat -N REDSOCKS 2>/dev/null || iptables -t nat -F REDSOCKS
        iptables -t nat -F REDSOCKS
        iptables -t nat -A REDSOCKS -d 0.0.0.0/8 -j RETURN
        iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
        iptables -t nat -A REDSOCKS -d "$PROXY_IP" -j RETURN
        # Forward ALL DNS queries (UDP 53) to local tcpdns on 1053 first
        iptables -t nat -A REDSOCKS -p udp --dport 53 -j REDIRECT --to-ports "$TCPDNS4_PORT" || {
            echo "[!] IPv4 DNS-to-TCP redirect failed; fail-closed guard remains active."
            stop_proxy >/dev/null 2>&1
            exit 1
        }
        # Forward DNS TCP 53 to redsocks on 1081
        iptables -t nat -A REDSOCKS -p tcp --dport 53 -j REDIRECT --to-ports 1081
        # Then exclude private subnets from being redirected
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
            exit 1
        }

        PASS_SIG=$(printf '%s' "$PROXY_PASS" | cksum 2>/dev/null | cut -d' ' -f1)
        echo "${PROXY_TYPE}://${PROXY_USER}@${PROXY_IP}:${PROXY_PORT}:${PASS_SIG}" > "$STATE_FILE"
        echo ACTIVE > "$STATUS_FILE"
        chmod 0644 "$STATUS_FILE" 2>/dev/null
        echo "[OK] Stealth Transparent Proxy ACTIVE ($PROXY_TYPE://$PROXY_IP:$PROXY_PORT)"
        echo "     - TCP IPv4+IPv6: redirected to SOCKS5 through redsocks2"
        echo "     - UDP IPv4+IPv6: SOCKS5 ASSOCIATE via TPROXY"
        echo "     - Direct application egress: BLOCKED; DHCPv6/NDP/ICMPv6 control exempt"
        ;;

    stop)
        stop_proxy
        echo STOPPED > "$STATUS_FILE"
        chmod 0644 "$STATUS_FILE" 2>/dev/null
        echo "[OK] Proxy stopped; normal direct network restored."
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
