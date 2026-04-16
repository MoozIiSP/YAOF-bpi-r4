<p align="center">
  <img width="768" src="https://raw.githubusercontent.com/QiuSimons/Others/master/YAOF.png" alt="YAOF">
</p>

<p align="center">
  <a href="https://github.com/MoozIiSP/YAOF-bpi-r4/releases">
    <img alt="Latest Release" src="https://img.shields.io/github/v/release/MoozIiSP/YAOF-bpi-r4?style=for-the-badge&label=Release">
  </a>
  <a href="https://github.com/MoozIiSP/YAOF-bpi-r4/blob/mt7988-24.10/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/MoozIiSP/YAOF-bpi-r4?style=for-the-badge">
  </a>
  <a href="https://github.com/MoozIiSP/YAOF-bpi-r4/actions/workflows/BPI-R4-OpenWrt.yml">
    <img alt="BPI-R4 Build" src="https://img.shields.io/github/actions/workflow/status/MoozIiSP/YAOF-bpi-r4/BPI-R4-OpenWrt.yml?branch=mt7988-24.10&style=for-the-badge&label=BPI-R4">
  </a>
  <a href="https://github.com/MoozIiSP/YAOF-bpi-r4/actions/workflows/BPI-R4-PRO-OpenWrt.yml">
    <img alt="BPI-R4-PRO Build" src="https://img.shields.io/github/actions/workflow/status/MoozIiSP/YAOF-bpi-r4/BPI-R4-PRO-OpenWrt.yml?branch=mt7988-24.10&style=for-the-badge&label=BPI-R4-PRO">
  </a>
</p>

<h1 align="center">YAOF for Banana Pi BPI-R4</h1>
<p align="center"><strong>OpenWrt 24.10 · MT7988 / Filogic 880 · WiFi 7 · 10G · VPN-friendly</strong></p>

> 本仓库是面向 **Banana Pi BPI-R4** 的 YAOF 分支，聚焦 **OpenWrt 24.10 + Kernel 6.6**，优先保证 MTK WiFi / 交换 / 10G 相关稳定性。

---

## ⚠️ 声明

- **请勿用于商业用途**。
- 本仓库衍生于 [QiuSimons/YAOF](https://github.com/QiuSimons/YAOF)，感谢原作者与 OpenWrt / ImmortalWrt / 社区维护者的工作。
- 这里的取舍是 **BPI-R4 定向优化**，不是全平台通用仓库。

---

## 🎯 项目定位

这个仓库当前主要服务于以下目标：

- **设备**：Banana Pi **BPI-R4**
- **分支路线**：`24.10` / `mt7988-24.10`
- **内核策略**：锁定 **6.6**，优先 MTK 驱动稳定性，不盲目追新内核
- **网络场景**：WiFi 7、10G SFP+、多 WAN、VPN、旁路/分流、家宽路由强化
- **构建方式**：GitHub Actions

如果你在找的是 R2S / R4S / x86 的通用版本，这里不是那个仓库；这里已经明显偏向 **BPI-R4 专用**。

---

## ✨ 特性

### 基础

- 基于原生 **OpenWrt 24.10** 编译
- 默认管理地址：`192.168.1.1`
- 内置升级能力可用，物理 Reset 可用
- 保留较强的可扩展性，适合继续装包与二次定制

### 性能 / 网络

- 默认启用 **SFE**，兼顾 UDP 入站与 SQM 兼容性
- 集成 **BBRv3**、**LRNG**
- 面向 MT7988/Filogic 880 做了定向优化
- 对 10G / 高并发 / VPN 使用场景更友好

### 常用预置

- **MosDNS**（广告过滤 + DNS 分流）
- **PassWall / OpenClash / HomeProxy / Nikki / Dae**
- **SQM / UPNP / DDNS / Zerotier / Tailscale / FRP**
- **Watchcat / Filemanager / Argon / 微信推送 / WOL / NATMapT**

### 其他

- 支持直接 `opkg` 安装大量 `kmod-*`
- 保留 Docker 相关辅助思路，但当前主线重点不是 Docker 场景
- 如遇奇怪问题，可 SSH 后执行：

```bash
fuck
```

等待机器重启后再确认问题是否消失。

---

## 🧩 硬件侧重点

BPI-R4 典型关注点包括：

- **MT7988A / Filogic 880**
- **WiFi 7 / MT7996**
- **10G SFP+**
- **多千兆口交换 / VLAN / 路由混合场景**
- **Cloudflare / Tailscale / ZeroTier / 代理栈**

本仓库的策略更偏向：

- 先把 **能稳定跑** 放在第一位
- 再追求无线与网络吞吐
- 最后才考虑激进升级内核/驱动

---

## 📦 固件下载

请前往 Releases 页面下载与你设备匹配的固件：

- [Releases / 发布页](https://github.com/MoozIiSP/YAOF-bpi-r4/releases)

建议优先关注：

- `BPI-R4`
- `24.10.x`
- `sysupgrade`
- `factory`（如果某次发布有提供）

> 如果某个发布同时出现多个镜像，优先按发布说明选择，不要盲刷不匹配的产物。

---

## 🏗️ 仓库结构

```text
.
├── PATCH/                  # 内核/系统/网络相关补丁
├── SCRIPTS/                # 构建脚本
│   ├── 01_get_ready.sh
│   ├── 02_prepare_package.sh
│   └── BPI-R4/02_target_only.sh
├── SEED/                   # 目标机型 seed 配置
│   ├── BPI-R4/config.seed
│   ├── BPI-R4-NAND/config.seed
│   └── BPI-R4-PRO/config.seed
├── .github/workflows/      # GitHub Actions
├── docs/                   # 介质策略、验证模板、发布说明模板
├── tests/                  # 仓库级验证测试
└── tools/                  # 介质布局 / 发布产物验证工具
```

其中：

- `SEED/BPI-R4/config.seed` 是当前主力配置
- `SEED/BPI-R4-NAND/config.seed` 是 SPI-NAND 最小可启动系统配置
- `SCRIPTS/BPI-R4/02_target_only.sh` 包含 BPI-R4 定向处理
- `docs/bpi-r4-storage-layout.md` 记录 NAND / eMMC / SD 的介质分工与分区策略
- `docs/bpi-r4-validation-checklist.md` 提供 SD / eMMC / SPI-NAND 的上板验证清单
- `docs/bpi-r4-test-report-template.md` 提供真实硬件验证结果沉淀模板
- `docs/bpi-r4-release-notes-template.md` 约束每次 release 的刷写 / 回退 / 已知问题说明
- `docs/bpi-r4-dev-test-loop.md` 约束从编译到烧录再到日志分析的闭环
- `docs/bpi-r4-pro-status.md` 明确 `BPI-R4-PRO` 当前仍为实验性状态
- `tools/validate_bpi_r4_bundles.py` 校验 SD / eMMC / SPI-NAND 发布包内容
- `tools/validate_bpi_r4_layouts.py` 校验 eMMC/SD GPT 布局与 8GB-safe 边界
- `tools/collect_bpi_r4_runtime_report.sh` 用于上板后采集运行证据
- `tools/analyze_bpi_r4_runtime_report.py` 用于把采集日志归类成可行动的优化项

---

## 🔨 本地构建

推荐环境：

- Ubuntu 24.04 / 22.04
- 8 GB+ 内存
- 50 GB+ 可用磁盘

基础流程：

```bash
git clone -b mt7988-24.10 https://github.com/MoozIiSP/YAOF-bpi-r4.git
cd YAOF-bpi-r4

bash SCRIPTS/01_get_ready.sh
bash SCRIPTS/02_prepare_package.sh
bash SCRIPTS/BPI-R4/02_target_only.sh

cd openwrt
make defconfig
make -j"$(nproc)"
```

### 构建说明

- 当前路线偏向 **OpenWrt 24.10 / Kernel 6.6**
- 不建议随手切到 6.12+ 再期待 MTK WiFi 仍然稳定
- 如果你想继续魔改，请优先理解 `PATCH/` 与 `SEED/` 的关系

---

## 🚀 CI / 自动构建

当前仓库已包含：

- `BPI-R4-OpenWrt.yml`
- `BPI-R4-PRO-OpenWrt.yml`
- `OpenWrt-Matrix.yml`

可通过 GitHub Actions 手动触发构建。

对于 `BPI-R4`，流水线会分别产出：

- `BPI-R4-SD`
- `BPI-R4-EMMC`
- `BPI-R4-SNAND`

其中：

- `BPI-R4-SD`：A/B 测试镜像，首启自动扩最后的 `data` 分区
- `BPI-R4-EMMC`：8GB-safe 的主力 eMMC A/B 布局
- `BPI-R4-SNAND`：最小可启动 NAND 系统，强调 boot / recovery / overlay

建议上板前同时阅读：

- `docs/bpi-r4-storage-layout.md`
- `docs/bpi-r4-validation-checklist.md`
- `docs/bpi-r4-test-report-template.md`
- `docs/bpi-r4-release-notes-template.md`
- `docs/bpi-r4-dev-test-loop.md`

CI 会在发布前额外执行：

- `tools/validate_bpi_r4_layouts.py`
- `tools/validate_bpi_r4_bundles.py`
- `tests/test_validate_bpi_r4_layouts.py`
- `tests/test_validate_bpi_r4_bundles.py`

并把 JSON 验证结果一并附加到 release artifacts，便于核对布局、打包和发布说明是否一致。

---

## 📝 发布与验证流程

推荐每次 tag 都遵循下面这套闭环：

1. CI 产出 `SD / EMMC / SNAND` 三套 bundle
2. CI 生成 `bundle/layout` 两份 JSON 验证报告
3. 发布说明按 `docs/bpi-r4-release-notes-template.md` 填充
4. 真机验证结果按 `docs/bpi-r4-test-report-template.md` 沉淀
5. 上板后在设备上执行：

```sh
sh tools/collect_bpi_r4_runtime_report.sh ./bpi-r4-validation-report
```

把采集结果附到对应 release / test report。

---

## 🧪 支持状态

- `BPI-R4`：主维护目标，要求介质级验证闭环
- `BPI-R4-PRO`：当前仍为**实验性**，详见 `docs/bpi-r4-pro-status.md`

---

## 🛠️ 使用建议

适合以下用户：

- 已经明确自己在玩 **BPI-R4**
- 想要一套更偏实战的 OpenWrt 固件
- 看重 **WiFi 7 / 10G / VPN / 分流**
- 能接受这个仓库是“面向单板定制”而不是“通用发行版”

不太适合：

- 需要全平台统一维护的人
- 追求最新内核、最新驱动、最新一切的人
- 想要完全零维护、零折腾体验的人

---

## 🙏 鸣谢

- [QiuSimons/YAOF](https://github.com/QiuSimons/YAOF)
- [OpenWrt](https://github.com/openwrt/openwrt)
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [frank-w](https://github.com/frank-w)
- MediaTek / Filogic 相关社区维护者
- 各类 LuCI 插件与第三方包维护者

---

## 📝 当前已补齐的维护配套

当前仓库已经补齐这些以前悬空的事项：

1. GitHub Topics 已配置：`bananapi`, `bpi-r4`, `filogic`, `mediatek`, `mt7988`, `openwrt`, `router-firmware`, `wifi7`
2. Release 说明模板已补：`docs/bpi-r4-release-notes-template.md`
3. 真机测试报告模板已补：`docs/bpi-r4-test-report-template.md`
4. CI 已补发布前校验：bundle 内容 + GPT 布局 + 8GB-safe 边界
5. `BPI-R4-PRO` 状态已单独标记为实验性，避免误判为已完成维护

<p align="center"><strong>为 BPI-R4 做定向优化，而不是做一份什么都想兼顾的固件。</strong></p>
