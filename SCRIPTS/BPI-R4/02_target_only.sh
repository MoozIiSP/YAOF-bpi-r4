#!/bin/bash
set -euo pipefail
clear

sed_in_place() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

resolve_profiles_url() {
  local release_repo
  local version_number

  release_repo="$(sed -n 's#^VERSION_REPO:=.*,\(https://downloads\.openwrt\.org/releases/[^)]*\)).*$#\1#p' include/version.mk | tail -n 1)"

  if [ -z "$release_repo" ]; then
    version_number="$(sed -n 's#^VERSION_NUMBER:=.*,\([^)]*\)).*$#\1#p' include/version.mk | tail -n 1)"
    if [ -n "$version_number" ]; then
      release_repo="https://downloads.openwrt.org/releases/$version_number"
    fi
  fi

  if [ -z "$release_repo" ]; then
    echo "[TARGET] Failed to resolve OpenWrt release repo from include/version.mk" >&2
    return 1
  fi

  printf '%s/targets/mediatek/filogic/profiles.json\n' "${release_repo%/}"
}

# 使用特定的优化
sed_in_place 's,-mcpu=generic,-march=armv8-a+crc+crypto,g' include/target.mk

#Vermagic
profiles_url="$(resolve_profiles_url)"
echo "[TARGET] Downloading vermagic from $profiles_url"
wget -O profiles.json "$profiles_url"
jq -er '.linux_kernel.vermagic' profiles.json > .vermagic
sed_in_place -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

# 预配置一些插件
cp -rf ../PATCH/files ./files

find ./ -name '*.orig' -delete
find ./ -name '*.rej' -delete

#exit 0
