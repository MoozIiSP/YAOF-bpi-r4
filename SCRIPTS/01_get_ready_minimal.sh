#!/bin/bash
set -euo pipefail

clone_repo() {
  local repo_url=$1
  local branch_name=$2
  local target_dir=$3
  git clone -b "$branch_name" --depth 1 "$repo_url" "$target_dir"
}

latest_release="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo 'v[0-9\.]+\-*r*c*[0-9]*.tar.gz' | grep 'v24.10' | sed -n 1p | sed 's/.tar.gz//g')"
openwrt_repo="https://github.com/openwrt/openwrt.git"
mtk_feed_repo="https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds.git"
custom_bootloader_repo="https://github.com/Yuzhii0718/bl-mt798x-dhcpd.git"

rm -rf openwrt openwrt_snap mtk-feed bl-mt798x-dhcpd

clone_repo "$openwrt_repo" "$latest_release" openwrt &
clone_repo "$openwrt_repo" openwrt-24.10 openwrt_snap &
clone_repo "$mtk_feed_repo" openwrt-24.10 mtk-feed &
clone_repo "$custom_bootloader_repo" master bl-mt798x-dhcpd &
wait

find openwrt/package/* -maxdepth 0 ! -name 'firmware' ! -name 'kernel' ! -name 'base-files' ! -name 'Makefile' -exec rm -rf {} +
rm -rf ./openwrt_snap/package/firmware ./openwrt_snap/package/kernel ./openwrt_snap/package/base-files ./openwrt_snap/package/Makefile
cp -rf ./openwrt_snap/package/* ./openwrt/package/
cp -rf ./openwrt_snap/feeds.conf.default ./openwrt/feeds.conf.default

echo "[MINIMAL] OpenWrt base, MTK feed, and custom bootloader sources are ready."