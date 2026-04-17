#!/bin/bash
set -euo pipefail
clear

sed -i 's,-mcpu=generic,-march=armv8-a+crc+crypto,g' include/target.mk

latest_version="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo 'v[0-9\\.]+\\-*r*c*[0-9]*.tar.gz' | grep 'v24.10' | sed -n 1p | sed 's/v//g' | sed 's/.tar.gz//g')"
wget -q https://downloads.openwrt.org/releases/${latest_version}/targets/mediatek/filogic/profiles.json
jq -r '.linux_kernel.vermagic' profiles.json > .vermagic
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

find ./ -name '*.orig' -delete
find ./ -name '*.rej' -delete

echo "[MINIMAL] Target-only preparation complete."