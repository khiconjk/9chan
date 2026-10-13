#!/system/bin/sh
# ==============================================================================
# S9 GHOST ON-DEVICE SYNC ENGINE (Shell Edition)
# Runs as root directly on Android OS
# ==============================================================================

CONF="/efs/ghost.conf"
[ ! -f "$CONF" ] && exit 1

# 1. Trigger Kernel reload
echo reload > /proc/s9_serial 2>/dev/null

# 2. Hardware USB & MAC Sync
SER=$(grep -E '^serialno=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
if [ -n "$SER" ]; then
    echo "$SER" > /config/usb_gadget/g1/strings/0x409/serialnumber 2>/dev/null
fi

WMAC=$(grep -E '^wifi_mac=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
if [ -n "$WMAC" ]; then
    echo -n "$WMAC" > /efs/wifi/.mac.info 2>/dev/null
    echo -n "$WMAC" > /data/vendor/conn/.mac.info 2>/dev/null
    settings put global wifi_connected_mac_randomization_enabled 0 2>/dev/null
fi

# 3. Telephony & Cellular Locks
cmd phone set-allowed-network-types-for-users -s 0 01000001000000000000 2>/dev/null
setprop gsm.operator.numeric 45204 2>/dev/null
setprop gsm.sim.operator.numeric 45204 2>/dev/null
setprop gsm.operator.alpha Viettel 2>/dev/null
setprop gsm.sim.operator.alpha Viettel 2>/dev/null
setprop ril.rejectedPlmn "" 2>/dev/null
setprop ril.simoperator 45204 2>/dev/null

PCODE=$(grep -E '^ril\.product_code=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
[ -n "$PCODE" ] && setprop ril.product_code "$PCODE" 2>/dev/null

SWVER=$(grep -E '^ril\.sw_ver=' "$CONF" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ')
[ -n "$SWVER" ] && setprop ril.sw_ver "$SWVER" 2>/dev/null

echo "S9 Ghost On-Device Sync Complete."
