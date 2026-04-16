# BPI-R4 Storage / Boot Media Strategy

This repo should treat **SPI-NAND**, **eMMC**, and **SD** as different boot media with different goals.

## 1. SPI-NAND (128MB)

### Goal
- Keep a **self-bootable minimal system** on NAND
- Must include **bootloader / U-Boot chain**
- Must be able to recover, flash, and manage the board without relying on eMMC/SD

### Expected contents
- BL2 / preloader
- U-Boot env
- factory
- FIP (ATF + U-Boot)
- kernel
- rootfs
- rootfs_data / overlay (small)

### Design notes
- NAND should **not** share the same large GPT/A-B layout used for block devices
- NAND layout is boot-medium specific (typically NMBM or full UBI style)
- Keep rootfs lean; extra plugins should live on overlay only if space allows, or preferably on eMMC/SD/external storage

## 2. eMMC (officially common 8GB)

### Goal
- Primary persistent system
- Stable A/B upgrades
- Enough writable space for configs, opkg installs, and service state

### Current repo policy
- Use an **8GB-safe GPT**
- Keep A/B fixed-size
- Keep `rootfs_data` larger than minimal OpenWrt defaults
- Preserve a separate `data` partition

### Layout intent
- kernel_a/rootfs_a
- kernel_b/rootfs_b
- rootfs_data
- data

## 3. SD Card

### Goal
- Convenient A/B testing media
- Reduce repeated reflash / back-and-forth test friction
- Expand user storage automatically on first boot

### Current repo policy
- Use an A/B GPT baseline compatible with small cards
- Keep slot sizes fixed
- Reserve the final `data` partition for **first-boot auto expansion** to the full card size

## 4. GPT files in this repo

### Block-device GPTs
- `PATCH/gpt/bpi-r4-ab.json`
  - current default injected GPT for block-device A/B use
  - now sized to be compatible with common 8GB-class media
- `PATCH/gpt/bpi-r4-emmc-8g-ab.json`
  - explicit 8GB eMMC A/B layout
- `PATCH/gpt/bpi-r4-sd-ab.json`
  - SD A/B baseline layout intended for later first-boot expansion of `data`

### Important
These GPT files are for **block devices** (eMMC / SD). They are **not** the NAND partition definition.

## 5. Immediate follow-up work

1. Wire media-specific image generation more explicitly (eMMC vs SD)
2. Add first-boot auto-expand logic for SD `data`
3. Define NAND-specific boot / partition handling separately from GPT-based media
