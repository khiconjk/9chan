#!/system/bin/sh
# ==============================================================================
# S9 Ghost - Stealth Transparent Proxy Engine (Zero VPN Flag / No tun0)
# Uses Kernel Netfilter NAT (iptables) + redsocks + dnstc + Anti-QUIC/WebRTC
# Automatically hijacks net.typeblog.socks (SocksDroid) to eliminate tun0 & VPN flag!
# ==============================================================================

CONF_DIR="/data/local/tmp"
CONF_FILE="$CONF_DIR/redsocks.conf"
PID_FILE="$CONF_DIR/redsocks.pid"
STATE_FILE="$CONF_DIR/stealth_proxy.state"

kill_vpn_tun0() {
    # Terminate any VpnService / tun2socks processes that create tun0 / TRANSPORT_VPN
    killall -9 libtun2socks.so 2>/dev/null
    pkill -9 -f "libtun2socks.so" 2>/dev/null
    pkill -9 -f "net.typeblog.socks:vpn" 2>/dev/null
    ip link set tun0 down 2>/dev/null
    ip link delete tun0 2>/dev/null
}

cleanup_rules() {
    # Remove IPv4 NAT rules
    iptables -t nat -D OUTPUT -j REDSOCKS 2>/dev/null
    iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null
    iptables -t nat -F REDSOCKS 2>/dev/null
    iptables -t nat -X REDSOCKS 2>/dev/null

    # Remove IPv4 Filter (Anti-QUIC & Anti-WebRTC) rules
    iptables -D OUTPUT -j REDSOCKS_FILTER 2>/dev/null
    iptables -F REDSOCKS_FILTER 2>/dev/null
    iptables -X REDSOCKS_FILTER 2>/dev/null

    # Remove IPv6 Filter (Anti-IPv6 Leak) rules
    ip6tables -D OUTPUT -j REDSOCKS6_FILTER 2>/dev/null
    ip6tables -F REDSOCKS6_FILTER 2>/dev/null
    ip6tables -X REDSOCKS6_FILTER 2>/dev/null
}

stop_proxy() {
    kill_vpn_tun0
    cleanup_rules
    killall -9 redsocks 2>/dev/null
    pkill -9 redsocks 2>/dev/null
    rm -f "$PID_FILE" "$CONF_FILE" "$STATE_FILE" 2>/dev/null
}

extract_socksdroid_config() {
    PREF_XML="/data/data/net.typeblog.socks/shared_prefs/net.typeblog.socks_preferences.xml"
    [ ! -f "$PREF_XML" ] && return 1
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

    for p in /data/local/tmp/ghost_proxy.conf /efs/ghost.conf /mnt/vendor/efs/ghost.conf /data/adb/s9_ghost.conf; do
        if [ -f "$p" ] && grep -q '^proxy\.enabled=1' "$p" 2>/dev/null; then
            P_EN="1"
            P_HOST=$(grep -E '^proxy\.host=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
            P_PORT=$(grep -E '^proxy\.port=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
            P_USER=$(grep -E '^proxy\.user=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
            P_PASS=$(grep -E '^proxy\.pass=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
            P_TYPE=$(grep -E '^proxy\.type=' "$p" | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
            [ -z "$P_TYPE" ] && P_TYPE="socks5"
            break
        fi
    done

    if [ "$P_EN" != "1" ] || [ -z "$P_HOST" ] || [ -z "$P_PORT" ]; then
        extract_socksdroid_config
    fi
}

case "$1" in
    auto)
        kill_vpn_tun0
        resolve_proxy_config
        if [ "$P_EN" = "1" ] && [ -n "$P_HOST" ] && [ -n "$P_PORT" ]; then
            if ! toybox nc -z -w 2 "$P_HOST" "$P_PORT" >/dev/null 2>&1; then
                stop_proxy
                echo "[!] Proxy endpoint $P_HOST:$P_PORT is offline. Keeping tun0 killed & direct wlan0 active."
                exit 0
            fi
            TARGET_SIG="${P_TYPE}://${P_USER}@${P_HOST}:${P_PORT}"
            CUR_SIG=$(cat "$STATE_FILE" 2>/dev/null)
            if [ "$TARGET_SIG" = "$CUR_SIG" ] && pidof redsocks >/dev/null 2>&1 && iptables -t nat -L REDSOCKS >/dev/null 2>&1; then
                exit 0
            fi
            exec "$0" start "$P_HOST" "$P_PORT" "$P_USER" "$P_PASS" "$P_TYPE"
        else
            stop_proxy
            exit 0
        fi
        ;;

    daemon)
        # Background guardian: eliminates any tun0/VpnService and syncs redsocks automatically
        while true; do
            if pidof libtun2socks.so >/dev/null 2>&1 || pgrep -f "libtun2socks" >/dev/null 2>&1 || ip link show tun0 >/dev/null 2>&1; then
                kill_vpn_tun0
                "$0" auto >/dev/null 2>&1
            fi
            sleep 3
        done
        ;;

    start)
        PROXY_IP="$2"
        PROXY_PORT="$3"
        PROXY_USER="$4"
        PROXY_PASS="$5"
        PROXY_TYPE="${6:-socks5}"

        if [ -z "$PROXY_IP" ] || [ -z "$PROXY_PORT" ]; then
            echo "Usage: $0 start <PROXY_IP> <PROXY_PORT> [USERNAME] [PASSWORD] [socks5|http-connect]"
            exit 1
        fi

        stop_proxy

        # Verify proxy endpoint is reachable before redirecting system traffic
        if ! toybox nc -z -w 2 "$PROXY_IP" "$PROXY_PORT" >/dev/null 2>&1; then
            echo "[!] Proxy endpoint $PROXY_IP:$PROXY_PORT is unreachable/offline. Keeping tun0 killed & direct wlan0 active."
            exit 0
        fi

        cat <<EOF > "$CONF_FILE"
base {
    log_debug = off;
    log_info = off;
    log = stderr;
    daemon = on;
    redirector = iptables;
    lte_interface_name = wlan0;
}
redsocks {
    local_ip = 127.0.0.1;
    local_port = 1081;
    ip = $PROXY_IP;
    port = $PROXY_PORT;
    type = $PROXY_TYPE;
EOF

        if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
            echo "    login = \"$PROXY_USER\";" >> "$CONF_FILE"
            echo "    password = \"$PROXY_PASS\";" >> "$CONF_FILE"
        fi

        echo "}" >> "$CONF_FILE"

        chmod 644 "$CONF_FILE"
        REDSOCKS_BIN="/data/adb/redsocks"
        [ ! -x "$REDSOCKS_BIN" ] && REDSOCKS_BIN="/system/bin/redsocks"
        "$REDSOCKS_BIN" -c "$CONF_FILE"
        sleep 1

        if ! pidof redsocks >/dev/null 2>&1; then
            echo "[!] Failed to start $REDSOCKS_BIN"
            exit 1
        fi

        # 1. IPv4 NAT Chain (REDSOCKS): Transparent TCP + Clean DNS (8.8.8.8)
        iptables -t nat -N REDSOCKS 2>/dev/null || iptables -t nat -F REDSOCKS
        iptables -t nat -A REDSOCKS -p udp --dport 53 -j DNAT --to-destination 8.8.8.8:53
        iptables -t nat -A REDSOCKS -d 0.0.0.0/8 -j RETURN
        iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
        iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
        iptables -t nat -A REDSOCKS -d 169.254.0.0/16 -j RETURN
        iptables -t nat -A REDSOCKS -d 172.16.0.0/12 -j RETURN
        iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
        iptables -t nat -A REDSOCKS -d 224.0.0.0/4 -j RETURN
        iptables -t nat -A REDSOCKS -d 240.0.0.0/4 -j RETURN
        iptables -t nat -A REDSOCKS -d "$PROXY_IP" -j RETURN

        # Redirect all remaining TCP traffic (including TCP 53 DNS & TCP 80/443) to redsocks (127.0.0.1:1081)
        iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 1081
        iptables -t nat -A OUTPUT -j REDSOCKS

        # 2. IPv4 Filter Chain (REDSOCKS_FILTER): Block QUIC/HTTP3 (UDP 443/80) & WebRTC STUN UDP leaks
        iptables -N REDSOCKS_FILTER 2>/dev/null || iptables -F REDSOCKS_FILTER
        iptables -A REDSOCKS_FILTER -d 127.0.0.0/8 -j RETURN
        iptables -A REDSOCKS_FILTER -d 192.168.0.0/16 -j RETURN
        iptables -A REDSOCKS_FILTER -d 10.0.0.0/8 -j RETURN
        iptables -A REDSOCKS_FILTER -d "$PROXY_IP" -j RETURN
        iptables -A REDSOCKS_FILTER -p udp --dport 443 -j REJECT --reject-with icmp-port-unreachable
        iptables -A REDSOCKS_FILTER -p udp --dport 80 -j REJECT --reject-with icmp-port-unreachable
        iptables -A REDSOCKS_FILTER -p udp --dport 3478 -j REJECT --reject-with icmp-port-unreachable
        iptables -A REDSOCKS_FILTER -p udp --dport 5349 -j REJECT --reject-with icmp-port-unreachable
        iptables -A REDSOCKS_FILTER -p udp --dport 19302:19309 -j REJECT --reject-with icmp-port-unreachable
        iptables -A OUTPUT -j REDSOCKS_FILTER

        # 3. IPv6 Filter Chain (REDSOCKS6_FILTER): Block IPv6 bypass while IPv4 Proxy is active
        ip6tables -N REDSOCKS6_FILTER 2>/dev/null || ip6tables -F REDSOCKS6_FILTER
        ip6tables -A REDSOCKS6_FILTER -o lo -j RETURN
        ip6tables -A REDSOCKS6_FILTER -p tcp -j REJECT
        ip6tables -A REDSOCKS6_FILTER -p udp --dport 53 -j REJECT
        ip6tables -A REDSOCKS6_FILTER -p udp --dport 443 -j REJECT
        ip6tables -A OUTPUT -j REDSOCKS6_FILTER

        echo "${PROXY_TYPE}://${PROXY_USER}@${PROXY_IP}:${PROXY_PORT}" > "$STATE_FILE"
        echo "[OK] Stealth Transparent Proxy ACTIVE ($PROXY_TYPE://$PROXY_IP:$PROXY_PORT)"
        echo "     - Interface: wlan0 native (Zero VPN flag, No tun0/ppp0)"
        echo "     - Protection: Anti-QUIC (UDP 443), Anti-DNS Leak (dnstc->TCP), Anti-WebRTC, Anti-IPv6 Leak"
        ;;

    stop)
        stop_proxy
        echo "[OK] Stealth Transparent Proxy STOPPED."
        ;;

    status)
        if pidof redsocks >/dev/null 2>&1; then
            echo "[STATUS] Stealth Transparent Proxy: ACTIVE (PID: $(pidof redsocks), Target: $(cat $STATE_FILE 2>/dev/null))"
            iptables -t nat -L REDSOCKS -n -v 2>/dev/null
            iptables -L REDSOCKS_FILTER -n -v 2>/dev/null
        else
            echo "[STATUS] Stealth Transparent Proxy: INACTIVE"
        fi
        ;;

    *)
        echo "Usage:"
        echo "  $0 auto"
        echo "  $0 daemon"
        echo "  $0 start <PROXY_IP> <PROXY_PORT> [USERNAME] [PASSWORD] [socks5|http-connect]"
        echo "  $0 stop"
        echo "  $0 status"
        exit 1
        ;;
esac
