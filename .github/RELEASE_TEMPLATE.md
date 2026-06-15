# English

**Open-source build, not paid-signed.** macOS and Windows will ask you to confirm on first launch — instructions below.

## What's changed

### Added
- Codex Accounts in Settings -> Accounts can now add isolated managed Codex logins, so Token Monitor can track multiple Codex accounts without disturbing the live Codex CLI session.
- AI Tool Limits now has a default-off Show active account option that marks the Codex account signed in on this device, including when synced account rows are visible.

### Improved
- The refresh button now shows in-progress, success, failure, and last-refreshed feedback.
- Bundled tokscale was updated to 3.1.3.

### Fixed
- Hubs without a shared secret no longer serve private data beyond localhost. Worker hubs now require `TOKEN_MONITOR_SECRET` before private data routes respond.

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
- 设置 -> 账号 中新增 Codex 账号，可添加独立的受管 Codex 登录，让 Token Monitor 追踪多个 Codex 账号，同时不影响当前 Codex CLI 会话。
- AI 工具限制新增默认关闭的“显示使用中账号”选项，可标记本机当前登录的 Codex 账号；同步账号行可见时也会正确显示。

### 改进
- 刷新按钮现在会显示刷新中、成功、失败和上次刷新时间反馈。
- 内置 tokscale 已更新到 3.1.3。

### 修复
- 未设置共享密钥的 Hub 不再向 localhost 之外提供私有数据。Worker Hub 现在必须设置 `TOKEN_MONITOR_SECRET` 后，私有数据接口才会响应。

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
