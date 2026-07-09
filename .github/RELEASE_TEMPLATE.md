# English

**Open-source build.** macOS builds are signed and notarized. Windows signing is still being prepared, so Windows may show SmartScreen on first launch. Linux AppImage downloads may need executable permission — instructions below.

## What's changed

### Added
- **App Updates:** Settings now includes App Updates backed by GitHub releases, with check, download, dismiss, and restart-to-install flows on supported packaged builds. (#99)
- **Codex local account switching:** On the Limits page, hover a Codex account email and click Switch to make it this device's local Codex account; restart Codex for the change to take effect. (#92)
- **Z.ai Team Account:** AI Tool Limits can track GLM Team Coding Plan quota with the required BigModel organization and project credentials. (#94)
- **Linux start at login:** AppImage builds now support the Startup -> Start at login setting, with a note when moving or renaming the AppImage would break the autostart entry. (#82)

### Improved
- **Codex account cards:** Managed Codex account chips stay compact on hover, and switching accounts refreshes only the selected Codex account instead of disturbing the rest of the provider list. (#101)

## Which file should I download?

- **macOS (Apple Silicon, M1 and later)** — the `.dmg` file
- **Windows 10/11** — `Token Monitor Setup ….exe` (installer, recommended)
- **Windows portable** — `Token Monitor ….exe` (runs without installing)
- **Linux x64** — the `.AppImage` file

Other platforms are not pre-built — run from source per the [README](https://github.com/Javis603/token-monitor#readme). The macOS `.zip` is the same app repackaged; ignore it unless you specifically need it.

## First launch

**macOS:** open the `.dmg`, drag Token Monitor to Applications, then launch normally.

**Windows:** SmartScreen → More info → Run anyway.

**Linux:** mark the AppImage executable, then run it:

```bash
chmod +x "Token Monitor"*.AppImage
./"Token Monitor"*.AppImage
```

## tokscale dependency

Tokscale is bundled with this app. See **Settings → Tokscale** for the exact version
and the option to download a newer version directly from npm. Tokscale is MIT,
open-source: https://github.com/junhoyeo/tokscale

---

# 中文

**这是开源构建。** macOS 构建已签名并 notarize。Windows 签名还在准备中，所以 Windows 首次启动时可能会显示 SmartScreen；Linux AppImage 下载后可能需要先赋予执行权限，操作说明见下方。

## 更新内容

### 新增
- **应用更新：** 设置中新增 App Updates，可基于 GitHub releases 检查更新，并在支持的打包版本上下载、忽略或重启安装更新。（#99）
- **Codex 本机账号切换：** 在额度页悬停对应 Codex 账号的 email，点击「切换账号」即可将它设为本机 Codex 账号；切换后需要重启 Codex 才会生效。（#92）
- **Z.ai 团队账号：** AI 工具额度现在可追踪 GLM 团队 Coding Plan 额度，并支持填写所需的 BigModel organization / project 凭证。（#94）
- **Linux 登录时启动：** AppImage 版本现在支持「启动 -> 登录时启动」，并会提示移动或重命名 AppImage 后自启项会失效。（#82）

### 改进
- **Codex 账号卡片：** 受管 Codex 账号的悬浮标签现在更紧凑；切换账号后只刷新选中的 Codex 账号，不会影响其他 provider 列表。（#101）

## 应该下载哪个文件？

- **macOS（苹果芯片，M1 及之后机型）** — 下载 `.dmg` 安装包
- **Windows 10/11** — 下载 `Token Monitor Setup ….exe`（安装版，推荐）
- **Windows 便携版** — 下载 `Token Monitor ….exe`（无需安装，直接运行）
- **Linux x64** — 下载 `.AppImage` 文件

其他平台暂不提供预构建版本，请参考 [README](https://github.com/Javis603/token-monitor#readme) 从源码运行。macOS 的 `.zip` 只是同一个 app 的重新打包版本，除非你明确需要，否则可以忽略。

## 首次启动

**macOS：** 打开 `.dmg`，把 Token Monitor 拖到 Applications，然后正常启动即可。

**Windows：** SmartScreen → 更多信息 → 仍要运行。

**Linux：** 先给 AppImage 执行权限，然后运行：

```bash
chmod +x "Token Monitor"*.AppImage
./"Token Monitor"*.AppImage
```

## tokscale 依赖

Tokscale 已随应用内置。你可以在 **设置 → Tokscale** 查看确切版本，
也可以直接从 npm 下载更新版本。Tokscale 是 MIT 开源项目：
https://github.com/junhoyeo/tokscale
