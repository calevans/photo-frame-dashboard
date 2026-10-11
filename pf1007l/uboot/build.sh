#!/usr/bin/env bash
# Rebuilds the two FEL payloads from mainline U-Boot v2025.01 plus frame-a33.patch:
#   u-boot-sunxi-with-spl.bin  SPL + U-Boot whose bootcmd exposes the eMMC over USB (ums)
#   sunxi-spl-ck5.bin          SPL that returns to FEL right after DRAM init (cold-boot warm-up)
# Usage: uboot/build.sh <work-dir>
# Needs: gcc-arm-linux-gnueabihf bison flex swig device-tree-compiler python3-pyelftools
#        python3-setuptools libgnutls28-dev uuid-dev
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=${1:?usage: $0 <work-dir>}
mk="make -s CROSS_COMPILE=arm-linux-gnueabihf-"

mkdir -p "$work"
if [ ! -d "$work/u-boot" ]; then
    git clone -q --depth 1 --branch v2025.01 https://source.denx.de/u-boot/u-boot.git "$work/u-boot"
    git -C "$work/u-boot" apply "$here/frame-a33.patch"
fi
cp "$here/frame_a33_ums_defconfig" "$here/frame_a33_warmup_defconfig" "$work/u-boot/configs/"

cd "$work/u-boot"
$mk O="$work/out-ums" frame_a33_ums_defconfig
$mk O="$work/out-ums" -j"$(nproc)"
$mk O="$work/out-ck5" frame_a33_warmup_defconfig
$mk O="$work/out-ck5" KCFLAGS=-DFRAME_CKPT=5 -j"$(nproc)"

cp "$work/out-ums/u-boot-sunxi-with-spl.bin" "$here/u-boot-sunxi-with-spl.bin"
cp "$work/out-ck5/spl/sunxi-spl.bin" "$here/sunxi-spl-ck5.bin"
sha256sum "$here/u-boot-sunxi-with-spl.bin" "$here/sunxi-spl-ck5.bin"
