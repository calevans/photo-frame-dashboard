# PF1007L photo frame -> web dashboard kiosk

How to turn a Humblestead/AiMOR **PF1007L** 10.1" photo frame into a full-screen web dashboard with root ADB over Wi-Fi.
It is tested on one unit and was done from a Windows PC with WSL2 (Ubuntu 22.04). No soldering and no opening the case.

The rest of this repo covers Rockchip frames. This one is an Allwinner A33, so the unlock path is entirely different;
the post-root steps (vendor apps, WebView 106) follow the BIUFRAME notes in [../docs/biuframe.md](../docs/biuframe.md).

**End state:** the frame boots your custom logo, then a WebView kiosk app (home screen, no status/nav/address bars, no on-screen exit)
showing one URL. Vendor apps and the OTA updater are disabled, and root ADB listens on TCP 5555 at a stable MAC/IP.

## Rules for agents

- Confirm with the owner before every write to the frame (eMMC sectors, `/system`, packages).
- Back up before writing, and verify every write by reading it back (hash compare).
- Keep a log of every device change and its undo (each step below names the `.bak` it keeps).
- `backups/` holds the full eMMC image, including the AiMOR device credentials (`vuid_cert.txt`). Never commit it or share it.

## Hardware facts

| Item | Value |
| --- | --- |
| SoC | Allwinner A33 (quad Cortex-A7). `sunxi-fel ver` reports `soc=00001667(A33)` |
| RAM | 1 GB DDR3, 16-bit bus. **Byte lane 0 comes out of reset disabled** (see U-Boot patch) |
| eMMC | **16 GB** (15,758,000,128 bytes). The box and AiMOR UI claim 32 GB |
| Wi-Fi | AIC8800 (`aic8800_fdrv`), 2.4 GHz. No MAC in efuse, so the driver randomizes the last 2 bytes each load |
| Display | 800×1280 panel, used rotated as 1280×800 landscape |
| Ports | Power button, RESET pinhole, microSD slot, one USB-C (power + data, device mode) |
| Firmware | `AEEZO/astar_m86_8723cs:6.0.1/MOB30R/20260113:eng/test-keys`, Android 6.0.1, SELinux disabled |
| Stock USB | `1f3a:1000` mass-storage gadget with no media; ADB is off |
| Stock network | Only TCP 8086 is open (AiMOR's silent custom protocol) |

The vendor firmware already ships root ADB (`ro.secure=0`, `ro.debuggable=1`, `ro.adb.secure=0`). One line in `/system/build.prop`
(`persist.sys.usb.config=mass_storage`) switches it off. The unlock exists to flip that one line.

## Repository layout

| Path | What |
| --- | --- |
| `uboot/` | `frame-a33.patch` and defconfigs, `build.sh` (builds the FEL payloads `u-boot-sunxi-with-spl.bin` and `sunxi-spl-ck5.bin` from mainline v2025.01), `boot-ums.sh`, `fel-sdboot.sunxi` (from sunxi-tools) |
| `write-sd.ps1` | Writes `fel-sdboot.sunxi` to a microSD card |
| `backup-emmc.ps1`, `verify-backup.ps1` | Full eMMC image + verification while U-Boot exposes it |
| `patch-sector.ps1`, `patch/` | The one-sector `build.prop` edit that enables ADB (`-Restore` undoes it) |
| `device/` | `frame-fixmac.sh`, installed on the frame to pin the Wi-Fi MAC |
| `kiosk/` | The WebView kiosk app (`build.sh`). Set the dashboard URL in the `URL` constant in `MainActivity.java` |
| `apks/` | Git-ignored. Download WebView 106 here (URL and hash in step 6) |
| `tools/make-bootanimation.php` | Builds a stored (uncompressed) `bootanimation.zip` from one PNG |
| `backups/` | Git-ignored. eMMC image and SD card header backup (private) |

## Host setup (one time)

WSL packages:

```
sudo apt install -y sunxi-tools adb \
  gcc-arm-linux-gnueabihf bison flex swig device-tree-compiler python3-pyelftools python3-setuptools libgnutls28-dev uuid-dev \
  default-jdk-headless aapt apksigner dalvik-exchange zipalign android-sdk-platform-23
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1f3a", ATTR{idProduct}=="efe8", MODE="0666"' | sudo tee /etc/udev/rules.d/61-sunxi-fel.rules
sudo udevadm control --reload
```

The cross-compiler line is only needed to rebuild U-Boot, and the Java/Android line only to build the kiosk.

Windows, Administrator PowerShell ([usbipd-win](https://github.com/dorssel/usbipd-win) 4+):

```
usbipd policy add --effect Allow --operation AutoBind --hardware-id 1f3a:efe8   # FEL -> WSL
usbipd policy add --effect Allow --operation AutoBind --hardware-id 1f3a:1001   # Android ADB -> WSL
Get-StorageSetting | Select NewDiskPolicy        # note the value so you can restore it afterwards
Set-StorageSetting -NewDiskPolicy OfflineAll     # stop Windows auto-mounting the frame's partitions
```

Plug the frame's USB-C directly into the PC. It powers from USB. `usbipd list` shows its bus ID (e.g. `1-13`).

## Procedure

### 1. FEL card

The A33 boot ROM checks the microSD slot before the eMMC. `fel-sdboot.sunxi` (from sunxi-tools) at the 8 KiB offset makes it drop into
FEL mode and stay there. FEL entered via the RESET button alone times out after a second or two, which is too short to use through usbipd.

1. Put any microSD card in the PC (its contents survive; only bytes 8 KiB to 16 KiB change). Find it with `Get-Disk`.
2. `powershell -ExecutionPolicy Bypass -File <repo>\write-sd.ps1 -DiskNumber <n> -ExpectSize <bytes>`
3. Put the card in the frame. From now on, **RESET with the card in = FEL** (`1f3a:efe8`). Card out + RESET = normal boot.

### 2. Expose the eMMC over USB

Build the payloads once with `uboot/build.sh <work-dir>`. Then run `BUSID=<bus id> uboot/boot-ums.sh` and press RESET. The script attaches FEL to WSL, runs the warm-up SPL (the first DRAM init after
power-on fails to train; a second run succeeds), then loads U-Boot. U-Boot's `ums` presents the eMMC as `Linux UMS disk 0`.
Windows reads it directly.

- **Never let usbipd attach `1f3a:1010`** (U-Boot's disk). The rebind resets the gadget and it never recovers. Don't run
  `usbipd attach --auto-attach` on the bus ID; attach FEL only, as the script does.
- Cancel every "format this disk" prompt. The MBR mislabels the ext4 `/data` partition as FAT32.
- If the disk drops, U-Boot either falls back to FEL (`ums` exited, then `go 0xffff0020`) or the 16 s watchdog resets it into FEL.
  Rerun the script; RESET is only needed if FEL is unresponsive.

### 3. Back up

Administrator PowerShell, while the disk is up:

```
powershell -ExecutionPolicy Bypass -File <repo>\backup-emmc.ps1   # marks the disk read-only, images to backups\emmc-full.img, then re-reads to compare SHA-256
```

About 5.7 MB/s, so roughly 45 min per pass. If pass 2 is interrupted, run `verify-backup.ps1` instead: it compares everything before `/data`
(2.08 GB, ~7 min) with the image and can resume with `-Start`. Then check the filesystems read-only in WSL:
`e2fsck -fn` on the system partition. Expect only "padding at end of inode bitmap" (normal for Android images).

### 4. Enable ADB (one sector)

```
powershell -ExecutionPolicy Bypass -File <repo>\patch-sector.ps1
```

It changes `mass_storage` to `adb\n#padding` in place (12 bytes, same file length, no ext4 metadata change; `/system` has no dm-verity and
no metadata_csum). It refuses to write unless the live sector matches `patch/sector-orig.bin`, and verifies by readback.

**Different firmware build?** Re-derive the sector from your backup before patching:

```
# Allwinner partition table ("softw411") at byte 20971520; partition starts are relative to sector 40960. system = MBR partition 7.
fdisk -l backups/emmc-full.img                       # system start sector, e.g. 237568
dd if=backups/emmc-full.img of=system.img bs=512 skip=<start> count=<sectors>
debugfs -R 'stat /build.prop' system.img             # EXTENTS: (0):<block>
debugfs -R 'cat /build.prop' system.img | grep -bo 'persist.sys.usb.config=mass_storage'   # <offset>
# byte = start*512 + block*4096 + offset + 23  ->  sector = byte/512, in-sector offset = byte%512
```

Then rebuild `patch/sector-orig.bin`, `sector-adb.bin` and `sector-number.txt` the same way.
Also confirm no `/data/property/persist.sys.usb.config` exists (`debugfs` on the `/data` partition), since that would override `build.prop`.

### 5. First boot with ADB

Card out, RESET. The frame boots AiMOR as usual but enumerates as `1f3a:1001`. `usbipd attach --wsl --busid <id>`, then
`adb devices` lists it and `adb shell id` returns `uid=0(root)` (no authorization prompt).

### 6. Provision over ADB

All of this runs as root via `adb shell`. Wrap each `/system` change in `mount -o remount,rw /system` and `mount -o remount,ro /system`,
and keep a `.bak` of every file you change.

**ADB over Wi-Fi:** `cp -p /system/build.prop /system/build.prop.bak; echo service.adb.tcp.port=5555 >> /system/build.prop`, reboot.

**Stable MAC.** The AIC8800 driver ignores `MAC_ADDR=` in its userconfig ("invalid cmd"), so pin it at runtime:
- Pick a MAC (keep the `88:00:33:77` prefix the driver uses) and set it in `device/frame-fixmac.sh`.
- Install the script as `/system/bin/frame-fixmac.sh` (0750 root:shell).
- Append `exec /system/bin/sh /system/bin/frame-fixmac.sh` to `/system/bin/install-recovery.sh`. Init runs that file as root on every
  boot (service `flash_recovery`). It must be `exec`, not `&`: init kills backgrounded children.
- Android re-initializes Wi-Fi once during boot, so expect two corrections in `logcat -s frame-fixmac` and two brief Wi-Fi bounces.
  Reserve the MAC in DHCP.

**Vendor apps.** For each of `com.yhk.qeota` (OTA updater, do it first), `com.DeviceTest` and `com.android.gl2jni` (factory leftovers):
`am force-stop <pkg>; pm disable <pkg>; pm hide <pkg>`. Disable `com.efercro.os.aimor` (AiMOR, the stock home app) only after the kiosk
is installed, or the frame has no home screen.

**WebView 44 -> 106** (the newest that supports Android 6): download
`https://raw.githubusercontent.com/LineageOS/android_external_chromium-webview_prebuilt_arm/4b0ae494a7dd/webview.apk`
and check SHA-256 `e2edc1f89ec1608b169da9e7ffc037190b70c7825f0be29694f4cae719980580`.
- Copy it over `/system/app/webview/webview.apk` (keep the `.bak`) and `rm -rf /system/app/webview/oat`.
- Unzip `lib/armeabi-v7a/*.so` into `/system/app/webview/lib/arm/` (dirs 0755, files 0644, root). Android 6 does not extract native
  libraries for `/system` apps, and WebView 106 stores them compressed.
- Reboot and confirm `dumpsys package com.android.webview` reports `106.0.5249.126`.

**Kiosk.** Set `URL` in `kiosk/src/com/calevans/frame/MainActivity.java`, then run `kiosk/build.sh` (signing key goes to
`~/.android/frame-kiosk.keystore`), `adb install -r kiosk/build/frame-kiosk.apk`, disable/hide AiMOR, and reboot. The app:
- registers as HOME, runs immersive full-screen, keeps the screen on, and is locked to landscape
- shows black while offline and loads the URL as soon as connectivity returns (10 s retry fallback)
- has deliberately no exit gesture. Use ADB for maintenance

**Boot graphics.** Start from a 1280×800 PNG.
- Logo, shown by the bootloader: `convert in.png -resize 1280x800^ -gravity center -extent 1280x800 -rotate 90 -type TrueColor -alpha off BMP3:bootlogo.bmp`
  (800×1280, 24-bit, 3,072,054 bytes), then copy it over `/bootloader/bootlogo.bmp`. That partition is the FAT one mounted at `/bootloader`.
- Animation: `php tools/make-bootanimation.php in-1280x800.png bootanimation.zip`, then copy it over `/system/media/bootanimation.zip`
  (0644 root).

## Gotchas

- Use `adb exec-out` (not `adb shell`) for binary reads or byte compares. `shell` turns `\n` into `\r\n`.
- Toybox `sed -i` on the frame mangles replacements containing `&`. Rebuild files from their `.bak` plus `echo >>` instead.
- `grep -r /` on the frame hangs in `/proc`.
- After an `adb reboot`, run `adb disconnect` / `adb connect` again; the old TCP session reports "device offline".
- Don't set the WebView background colour. Pages without their own background show it, so black means black-on-black text.
- `screencap` works for checking what the kiosk shows. To inspect the page, temporarily add `WebView.setWebContentsDebuggingEnabled(true)`
  and `adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>`, then `curl localhost:9222/json`.
- A Windows auto-mount of the `/bootloader` partition leaves a `System Volume Information` folder there. Delete it.
- An AiMOR/YHK OTA could overwrite `/system` and undo all of this. Disable `com.yhk.qeota` early and never press "Check for updates".

## U-Boot patch (`uboot/frame-a33.patch` on v2025.01, base: Sinlinx SinA33 config)

| Change | Why |
| --- | --- |
| `dram_sun8i_a33.c`: after training, if DX0 is disabled, copy DX1GCR0 into DX0GCR0 and retrain | Lane 0 comes up disabled on this board, so every even byte read as 0 |
| `sun8i-a33-sinlinx-sina33.dts`: eMMC `bus-width = <4>`, `max-frequency = <26000000>` | 8-bit high-speed hung U-Boot mid-transfer |
| `f_mass_storage.c`: drop the `ctrlc()` abort | Console RX floats; noise could read as Ctrl+C |
| `frame_ckpt(n)` hooks in SPL (active only with `-DFRAME_CKPT=n`) | Return to FEL at a checkpoint. Checkpoint 5 (after DRAM init) is the warm-up SPL |
| Config: DRAM 456 MHz, `SUNXI_NO_PMIC`, CPU 408 MHz, video off, stdin=nulldev, watchdog 16 s, bootcmd `ums 0 mmc 1` then return to FEL | Leaves the unknown PMIC wiring alone; the eMMC is `mmc 1` |

`uboot/build.sh <work-dir>` rebuilds both binaries from a fresh clone. Rebuilt this way, the warm-up SPL was byte-identical to the
hardware-tested one apart from its embedded build timestamp, and the U-Boot image came out at the same size.

## Recovery

- **Undo any provisioning step:** restore the `.bak` that step kept, or `pm unhide` / `pm enable` the package.
- **Undo ADB:** run `patch-sector.ps1 -Restore` under U-Boot (step 2), or restore `/system/build.prop.bak`.
- **Last resort:** write `backups/emmc-full.img` back through U-Boot `ums` with a raw-disk write from an Administrator PowerShell
  (the reverse of `backup-emmc.ps1`).
