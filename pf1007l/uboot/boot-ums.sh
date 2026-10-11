#!/usr/bin/env bash
# Waits for the frame in FEL, warms up DRAM, then runs U-Boot, whose bootcmd exposes the eMMC over USB.
# Windows reads that disk directly; never usbipd-attach it (1f3a:1010), the gadget does not survive the rebind.
# Usage: BUSID=1-13 uboot/boot-ums.sh   (BUSID = usbipd bus ID of the port the frame is plugged into)
d=$(dirname "$0")
BUSID=${BUSID:-1-13}
end=$((SECONDS+1800))

until lsusb -d 1f3a:efe8 >/dev/null 2>&1 && timeout 3 sunxi-fel ver >/dev/null 2>&1; do
    [ $SECONDS -ge $end ] && { echo timeout; exit 1; }
    powershell.exe -NoProfile -Command "usbipd list" 2>/dev/null | grep -q "$BUSID *1f3a:efe8" \
        && powershell.exe -NoProfile -Command "usbipd attach --wsl --busid $BUSID" >/dev/null 2>&1
    sleep 1
done
echo "$(date +%T) FEL ready"

# Cold DRAM init only trains reliably on the second run: warm it with the checkpoint-5 SPL first.
timeout 20 sunxi-fel spl "$d/sunxi-spl-ck5.bin" >/dev/null 2>&1
timeout 5 sunxi-fel ver >/dev/null 2>&1 || { echo "warm-up SPL did not return"; exit 1; }
timeout 120 sunxi-fel uboot "$d/u-boot-sunxi-with-spl.bin" >/dev/null 2>&1
echo "$(date +%T) U-Boot started"

for i in $(seq 1 45); do
    out=$(powershell.exe -NoProfile -Command "Get-Disk | Where-Object FriendlyName -eq 'Linux UMS disk 0' | Select Number,Size,IsReadOnly | Format-Table -AutoSize" 2>/dev/null)
    echo "$out" | grep -q '[0-9]' && { echo "$(date +%T) eMMC visible to Windows:"; echo "$out"; exit 0; }
    sleep 2
done
echo "eMMC disk did not appear in Windows"
exit 1
