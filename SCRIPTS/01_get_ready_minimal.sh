#!/bin/bash
set -euo pipefail

clone_repo() {
  local repo_url=$1
  local branch_name=$2
  local target_dir=$3
  if [ -d "$target_dir" ]; then
    echo "[MINIMAL] $target_dir already exists, skipping clone."
    return 0
  fi
  git clone -b "$branch_name" --depth 1 "$repo_url" "$target_dir"
}

latest_release="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo 'v[0-9\.]+\-*r*c*[0-9]*.tar.gz' | grep 'v24.10' | sed -n 1p | sed 's/.tar.gz//g')"
openwrt_repo="https://github.com/openwrt/openwrt.git"
mtk_feed_repo="https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds.git"
custom_bootloader_repo="https://github.com/Yuzhii0718/bl-mt798x-dhcpd.git"

# Check if openwrt source exists and is a git repo
if [ ! -d "openwrt/.git" ]; then
  echo "[MINIMAL] openwrt source missing or incomplete. Re-cloning..."

  # 1. Preserve caches if they exist
  for dir in dl staging_dir build_dir; do
    if [ -d "openwrt/$dir" ]; then
      echo "[MINIMAL] Backing up openwrt/$dir..."
      mv "openwrt/$dir" "./_saved_$dir"
    fi
  done

  # 2. Clean and Clone
  rm -rf openwrt
  clone_repo "$openwrt_repo" "$latest_release" openwrt &
  
  # 3. Restore caches
  for dir in dl staging_dir build_dir; do
    if [ -d "./_saved_$dir" ]; then
      echo "[MINIMAL] Restoring openwrt/$dir..."
      mv "./_saved_$dir" "openwrt/$dir"
    fi
  done
  
  # 4. Clone other repos (if missing)
  clone_repo "$openwrt_repo" openwrt-24.10 openwrt_snap &
  clone_repo "$mtk_feed_repo" openwrt-24.10 mtk-feed &
  clone_repo "$custom_bootloader_repo" master bl-mt798x-dhcpd &
  
  wait

  # 5. Setup openwrt base structure
  if [ -d "openwrt" ]; then
    find openwrt/package/* -maxdepth 0 ! -name 'firmware' ! -name 'kernel' ! -name 'base-files' ! -name 'Makefile' -exec rm -rf {} +
    if [ -d "openwrt_snap" ]; then
      rm -rf ./openwrt_snap/package/firmware ./openwrt_snap/package/kernel ./openwrt_snap/package/base-files ./openwrt_snap/package/Makefile
      cp -rf ./openwrt_snap/package/* ./openwrt/package/
      cp -rf ./openwrt_snap/feeds.conf.default ./openwrt/feeds.conf.default
    fi
  fi
else
  echo "[MINIMAL] openwrt source detected."
  # Ensure sub-repos exist
  clone_repo "$openwrt_repo" openwrt-24.10 openwrt_snap
  clone_repo "$mtk_feed_repo" openwrt-24.10 mtk-feed
  clone_repo "$custom_bootloader_repo" master bl-mt798x-dhcpd
fi

echo "[MINIMAL] OpenWrt base, MTK feed, and custom bootloader sources are ready."