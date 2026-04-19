#!/bin/bash
set -euo pipefail

sed_in_place() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

is_openwrt_package_wrapper() {
  local pkg_dir=$1
  local makefile="$pkg_dir/Makefile"

  [ -f "$makefile" ] || return 1
  grep -qE 'include \$\(TOPDIR\)/rules\.mk|BuildPackage|PKG_SOURCE_(PROTO|URL|DATE|VERSION)' "$makefile"
}

restore_openwrt_boot_package() {
  local pkg_name=$1
  local src_dir="../openwrt_snap/package/boot/$pkg_name"
  local dst_dir="./package/boot/$pkg_name"

  if is_openwrt_package_wrapper "$dst_dir"; then
    return 0
  fi

  if [ ! -d "$src_dir" ]; then
    echo "[BOOT] Unable to restore $pkg_name: $src_dir not found"
    return 1
  fi

  rm -rf "$dst_dir"
  cp -rf "$src_dir" "$dst_dir"
  echo "[BOOT] Restored $pkg_name package wrapper from openwrt_snap"
}

replace_with_custom_package_wrapper() {
  local src_dir=$1
  local dst_dir=$2
  local label=$3

  if [ ! -d "$src_dir" ]; then
    return 1
  fi

  if ! is_openwrt_package_wrapper "$src_dir"; then
    echo "[BOOT] Skipping $label replacement: $src_dir is a source tree, not an OpenWrt package wrapper"
    return 1
  fi

  rm -rf "$dst_dir"
  cp -rf "$src_dir" "$dst_dir"
  echo "[BOOT] Replaced $label with custom OpenWrt package wrapper"
}

configure_package_use_source_dir() {
  local pkg_dir=$1
  local source_dir_rel=$2
  local label=$3
  local makefile="$pkg_dir/Makefile"
  local temp_file

  if [ ! -d "$source_dir_rel" ] || [ ! -f "$makefile" ]; then
    return 1
  fi

  temp_file="$(mktemp)"
  awk -v source_dir="$source_dir_rel" '
    /^USE_SOURCE_DIR:=/ { next }
    /^include \$\(INCLUDE_DIR\)\/package\.mk/ && !inserted {
      print "USE_SOURCE_DIR:=$(TOPDIR)/" source_dir
      inserted=1
    }
    { print }
    END {
      if (!inserted) {
        print "USE_SOURCE_DIR:=$(TOPDIR)/" source_dir
      }
    }
  ' "$makefile" > "$temp_file"
  mv "$temp_file" "$makefile"
  echo "[BOOT] Configured $label wrapper to use local source dir $source_dir_rel"
}

ensure_file_has_line() {
  local file_path=$1
  local line=$2
  local label=$3

  [ -f "$file_path" ] || return 1
  grep -Fqx "$line" "$file_path" || printf '%s\n' "$line" >> "$file_path"
  echo "$label Ensured $(basename "$file_path") contains: $line"
}

disable_mtk_feed() {
  for feed_file in feeds.conf feeds.conf.default; do
    if [ -f "$feed_file" ]; then
      sed_in_place '/^src-\(git\|link\)\(-full\)\? mtk /d' "$feed_file"
    fi
  done

  rm -rf ./feeds/mtk ./feeds/mtk.index
}

mtk_feed_source_dir="./.mtk-feed-source"
mtk_feed_mode="${MTK_FEED_MODE:-auto}"
mtk_feed_branch="${MTK_FEED_BRANCH:-master}"
mtk_feed_version_dir="${MTK_FEED_VERSION_DIR:-24.10}"
mtk_feed_official_url="${MTK_FEED_OFFICIAL_URL:-https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds.git}"
mtk_feed_mirror_url="${MTK_FEED_MIRROR_URL:-https://tea.saymi-labs.top/Learning/mtk-openwrt-feeds}"
mtk_feed_mapping_url="${MTK_FEED_MAPPING_URL:-https://raw.githubusercontent.com/GainStrongService/mtk-openwrt-feeds/master/mtk-openwrt-feeds-commit-sha-mapping-table.md}"
mtk_feed_apply_patches="${MTK_FEED_APPLY_PATCHES:-0}"

configure_mtk_feed_link() {
  local abs_source_dir
  abs_source_dir="$(cd "$mtk_feed_source_dir" && pwd -P)"

  for feed_file in feeds.conf feeds.conf.default; do
    if [ -f "$feed_file" ]; then
      sed_in_place '/^src-\(git\|link\)\(-full\)\? mtk /d' "$feed_file"
      printf 'src-link mtk %s\n' "$abs_source_dir" >> "$feed_file"
    fi
  done
}

resolve_mtk_official_head() {
  git ls-remote "$mtk_feed_official_url" "refs/heads/$mtk_feed_branch" | awk 'NR==1 {print $1}'
}

resolve_mtk_mirror_full_sha() {
  local official_sha=$1
  local official_short mirror_short

  official_short="${official_sha:0:8}"
  mirror_short="$(
    curl -fsSL "$mtk_feed_mapping_url" | awk -F'|' -v sha="$official_short" '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        return s
      }
      trim($2) == sha {
        print trim($3)
        exit
      }
    '
  )"

  if [ -z "$mirror_short" ]; then
    return 1
  fi

  curl -fsSL \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: yaof-bpi-r4-ci' \
    "https://api.github.com/repos/GainStrongService/mtk-openwrt-feeds/commits/$mirror_short" \
    | jq -r '.sha // empty'
}

checkout_mtk_mirror_commit() {
  local target_sha=$1

  rm -rf "$mtk_feed_source_dir"
  git init "$mtk_feed_source_dir" >/dev/null 2>&1
  git -C "$mtk_feed_source_dir" remote add origin "$mtk_feed_mirror_url"
  git -C "$mtk_feed_source_dir" fetch --depth 1 origin "$target_sha" >/dev/null 2>&1
  git -C "$mtk_feed_source_dir" checkout --detach FETCH_HEAD >/dev/null 2>&1
}

prepare_mtk_feed_source() {
  local official_head mirror_sha

  case "$mtk_feed_mode" in
    disabled)
      echo "[MTK] Feed disabled"
      disable_mtk_feed
      return 0
      ;;
    official)
      echo "[MTK] Using official feed: $mtk_feed_official_url@$mtk_feed_branch"
      rm -rf "$mtk_feed_source_dir"
      git clone --depth 1 -b "$mtk_feed_branch" "$mtk_feed_official_url" "$mtk_feed_source_dir"
      ;;
    auto|mirror)
      if [ "$mtk_feed_mode" = "auto" ]; then
        echo "[MTK] Trying official feed: $mtk_feed_official_url@$mtk_feed_branch"
        rm -rf "$mtk_feed_source_dir"
        if git clone --depth 1 -b "$mtk_feed_branch" "$mtk_feed_official_url" "$mtk_feed_source_dir"; then
          echo "[MTK] Official feed clone succeeded"
          configure_mtk_feed_link
          return 0
        fi
        echo "[MTK] Official feed clone failed; falling back to mirror"
      else
        rm -rf "$mtk_feed_source_dir"
      fi

      official_head="$(resolve_mtk_official_head)"
      if [ -z "$official_head" ]; then
        echo "[MTK] Unable to resolve official head from $mtk_feed_official_url@$mtk_feed_branch" >&2
        return 1
      fi
      echo "[MTK] Official head is $official_head"

      if checkout_mtk_mirror_commit "$official_head"; then
        echo "[MTK] Mirror contains matching commit $official_head"
      else
        mirror_sha="$(resolve_mtk_mirror_full_sha "$official_head")"
        if [ -z "$mirror_sha" ]; then
          echo "[MTK] Unable to map official commit $official_head to mirror commit" >&2
          return 1
        fi
        checkout_mtk_mirror_commit "$mirror_sha"
        echo "[MTK] Mirror fallback commit is $mirror_sha"
      fi
      ;;
    *)
      echo "[MTK] Unsupported MTK_FEED_MODE: $mtk_feed_mode" >&2
      return 1
      ;;
  esac

  configure_mtk_feed_link
}

apply_mtk_feed_overlay() {
  local overlay_dir="./feeds/mtk/$mtk_feed_version_dir"
  local patch_dir patch_file

  if [ ! -d "$overlay_dir" ]; then
    echo "[MTK] Overlay directory $overlay_dir not found" >&2
    return 1
  fi

  if [ -d "$overlay_dir/files" ]; then
    echo "[MTK] Applying files overlay from $overlay_dir/files"
    cp -af "$overlay_dir/files/." .
  fi

  if [ "$mtk_feed_apply_patches" != "1" ]; then
    echo "[MTK] Skipping overlay patches from $overlay_dir (set MTK_FEED_APPLY_PATCHES=1 to enable)"
    return 0
  fi

  for patch_dir in patches-base patches-feeds; do
    if [ ! -d "$overlay_dir/$patch_dir" ]; then
      continue
    fi

    while IFS= read -r patch_file; do
      [ -n "$patch_file" ] || continue
      echo "[MTK] Applying patch $patch_file"
      patch -f -p1 -i "$patch_file"
    done <<EOF
$(find "$overlay_dir/$patch_dir" -type f -name '*.patch' | sort)
EOF
  done
}

rewrite_feeds() {
  local pkg_src=$1
  local luci_src=$2
  local routing_src=$3
  local telephony_src=$4
  for feed_file in feeds.conf feeds.conf.default; do
    if [ -f "$feed_file" ]; then
      sed_in_place "s#https://git.openwrt.org/feed/packages.git[^ ]*#$pkg_src#g" "$feed_file"
      sed_in_place "s#https://git.openwrt.org/project/luci.git[^ ]*#$luci_src#g" "$feed_file"
      sed_in_place "s#https://git.openwrt.org/feed/routing.git[^ ]*#$routing_src#g" "$feed_file"
      sed_in_place "s#https://git.openwrt.org/feed/telephony.git[^ ]*#$telephony_src#g" "$feed_file"
    fi
  done
}

rewrite_feeds "https://github.com/openwrt/packages.git;openwrt-24.10" \
              "https://github.com/openwrt/luci.git;openwrt-24.10" \
              "https://github.com/openwrt/routing.git;openwrt-24.10" \
              "https://github.com/openwrt/telephony.git;openwrt-24.10"
disable_mtk_feed

if ! ./scripts/feeds update -a; then
  echo "GitHub 镜像更新失败，尝试切换回官方源..."
  rewrite_feeds "https://git.openwrt.org/feed/packages.git;openwrt-24.10" \
                "https://git.openwrt.org/project/luci.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/routing.git;openwrt-24.10" \
                "https://git.openwrt.org/feed/telephony.git;openwrt-24.10"
  disable_mtk_feed
  ./scripts/feeds update -a
fi

prepare_mtk_feed_source

if [ "$mtk_feed_mode" != "disabled" ]; then
  ./scripts/feeds update mtk
  apply_mtk_feed_overlay
fi

ensure_file_has_line \
  "./target/linux/mediatek/filogic/config-6.6" \
  "# CONFIG_USB_XHCI_MTK_DEBUGFS is not set" \
  "[KERNEL]"

./scripts/feeds install -a

restore_openwrt_boot_package arm-trusted-firmware-mediatek || true
restore_openwrt_boot_package uboot-mediatek || true

if [ -d "../bl-mt798x-dhcpd" ]; then
  echo "[BOOT] Found custom bootloader repo: bl-mt798x-dhcpd"
  atf_custom_applied=0

  if replace_with_custom_package_wrapper \
    "../bl-mt798x-dhcpd/atf-20260123" \
    "./package/boot/arm-trusted-firmware-mediatek" \
    "ATF"; then
    atf_custom_applied=1
  elif configure_package_use_source_dir \
    "./package/boot/arm-trusted-firmware-mediatek" \
    "../bl-mt798x-dhcpd/atf-20260123" \
    "ATF"; then
    atf_custom_applied=1
  fi

  replace_with_custom_package_wrapper \
    "../bl-mt798x-dhcpd/uboot-mtk-20250711" \
    "./package/boot/uboot-mediatek" \
    "U-Boot" || configure_package_use_source_dir \
    "./package/boot/uboot-mediatek" \
    "../bl-mt798x-dhcpd/uboot-mtk-20250711" \
    "U-Boot" || true

  if [ "$atf_custom_applied" -eq 1 ] && [ -n "${BPI_R4_GPT_LAYOUT:-}" ] && [ -f "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ]; then
    mkdir -p ../bl-mt798x-dhcpd/atf-20260123/src/gpt
    cp "../PATCH/gpt/$BPI_R4_GPT_LAYOUT" ../bl-mt798x-dhcpd/atf-20260123/src/gpt/
    echo "[GPT] Injected GPT layout: $BPI_R4_GPT_LAYOUT"
  elif [ -n "${BPI_R4_GPT_LAYOUT:-}" ] && [ "$atf_custom_applied" -ne 1 ]; then
    echo "[GPT] Skipping GPT layout injection because no custom ATF source was applied"
  elif [ -n "${BPI_R4_GPT_LAYOUT:-}" ]; then
    echo "[GPT] Requested GPT layout '$BPI_R4_GPT_LAYOUT' not found, skipping"
  else
    echo "[GPT] No GPT layout requested"
  fi
else
  echo "[BOOT] Custom bootloader repo not found, using default OpenWrt sources"
fi

sed_in_place 's,-SNAPSHOT,,g' include/version.mk
sed_in_place 's,-SNAPSHOT,,g' package/base-files/image-config.in
sed_in_place '/CONFIG_BUILDBOT/d' include/feeds.mk
sed_in_place 's/;)\s*\\/; \\/' include/feeds.mk
sed_in_place 's,CONFIG_WERROR=y,# CONFIG_WERROR is not set,g' target/linux/generic/config-6.6 || true

echo "[MINIMAL] Minimal package preparation complete."
