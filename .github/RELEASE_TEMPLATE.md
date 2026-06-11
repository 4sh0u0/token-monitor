# English

**Open-source build, not paid-signed.** macOS and Windows will ask you to confirm on first launch — instructions below.

## What's changed

### Added
- Added Cline usage support, including collection, charts, tool labels, and Discord Rich Presence assets.
- Added Antigravity CLI (`agy` / `antigravity-cli`) limit detection, merged with the existing Antigravity 2.0 detection.

### Improved
- Status cards now lead with the active incident title and show the affected-component count when a provider reports degraded service.
- Moved Settings to the footer by default, with an Appearance option to place the Settings button back in the title bar.
- Refined tray menu-bar behavior with a hover grace delay, steadier title-bar controls, and a configurable title-bar position.

### Fixed
- Fixed Windows frameless-window corners and removed the DWM system border around the widget.
- Fixed Claude usage fallback on Windows when the Claude CLI usage command is available but the primary data path is missing.

## Which file should I download?

- **macOS (Apple Silicon, M1 and later)** — the `.dmg` file
- **Windows 10/11** — `Token Monitor Setup ….exe` (installer, recommended)
- **Windows portable** — `Token Monitor ….exe` (runs without installing)

Intel Macs and Linux are not pre-built — run from source per the [README](https://github.com/Javis603/token-monitor#readme). The macOS `.zip` is the same app repackaged; ignore it unless you specifically need it.

## First-launch unlock

**macOS:** right-click `Token Monitor.app` → Open (once). If you see "Token Monitor" can't be opened or is damaged:

```bash
xattr -dr com.apple.quarantine "/Applications/Token Monitor.app"
```

**Windows:** SmartScreen → More info → Run anyway.

## tokscale dependency

Tokscale is bundled with this app. See **Settings → Tokscale** for the exact version
and the option to download a newer version directly from npm. Tokscale is MIT,
open-source: https://github.com/junhoyeo/tokscale

---

# 中文

**这是开源构建，不是付费签名版本。** macOS 和 Windows 首次启动时会要求你手动确认，操作说明见下方。

## 更新内容

### 新增
- 新增 Cline 用量支持，包含收集、图表、工具名称，以及 Discord Rich Presence 图标。
- 新增 Antigravity CLI（`agy` / `antigravity-cli`）限制侦测，会和既有的 Antigravity 2.0 侦测合并呈现。

### 改进
- Status 卡片现在会优先显示进行中的事件标题，并在服务降级时显示受影响组件数量。
- 设置按钮默认移到底部，也可以在外观设置中放回标题栏。
- 改进托盘菜单栏行为，加入 hover 宽限时间，让标题栏控制更稳定，并可调整标题栏位置。

### 修复
- 修复 Windows 无边框窗口圆角，并移除小组件周围的 DWM 系统边框。
- 修复 Windows 上 Claude 主要资料路径缺失时，无法回退读取 Claude CLI 用量的问题。

## 应该下载哪个文件？

- **macOS（苹果芯片，M1 及之后机型）** — 下载 `.dmg` 安装包
- **Windows 10/11** — 下载 `Token Monitor Setup ….exe`（安装版，推荐）
- **Windows 便携版** — 下载 `Token Monitor ….exe`（无需安装，直接运行）

Intel Mac 和 Linux 暂不提供预构建版本，请参考 [README](https://github.com/Javis603/token-monitor#readme) 从源码运行。macOS 的 `.zip` 只是同一个 app 的重新打包版本，除非你明确需要，否则可以忽略。

## 首次启动放行

**macOS：** 右键 `Token Monitor.app` → 打开（只需要一次）。如果看到「Token Monitor」未开启 或 已损坏：

```bash
xattr -dr com.apple.quarantine "/Applications/Token Monitor.app"
```

**Windows：** SmartScreen → 更多信息 → 仍要运行。

## tokscale 依赖

Tokscale 已随应用内置。你可以在 **设置 → Tokscale** 查看确切版本，
也可以直接从 npm 下载更新版本。Tokscale 是 MIT 开源项目：
https://github.com/junhoyeo/tokscale
