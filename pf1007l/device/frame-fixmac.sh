#!/system/bin/sh
# The AIC8800 has no MAC in efuse and its driver picks a random one each load, which breaks DHCP reservations.
# Pin it, and keep pinning it in case Wi-Fi is toggled and the driver comes back with a new random address.
MAC=88:00:33:77:71:70

while true; do
    if [ -e /sys/class/net/wlan0/address ]; then
        cur=$(cat /sys/class/net/wlan0/address)
        if [ "$cur" != "$MAC" ]; then
            ip link set wlan0 down
            ip link set wlan0 address $MAC
            ip link set wlan0 up
            log -t frame-fixmac "wlan0 $cur -> $MAC"
        fi
    fi
    sleep 10
done
