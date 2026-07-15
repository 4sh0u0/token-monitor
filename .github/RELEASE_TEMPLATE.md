# English

**Open-source build.** macOS is signed and notarized; Windows is unsigned (SmartScreen may appear); Linux AppImages need executable permission — see notes below.

## What's changed

<!-- app-update-notes:en:start -->
### Fixed
- **Live usage updates:** Fixed severe stuttering and temporary unresponsiveness when refreshing usage with large session histories. Session archive processing now scales linearly; in a real 568-session case, processing time dropped from about 1.1 seconds to 13 milliseconds. (#156)
<!-- app-update-notes:en:end -->

## Download

- **macOS Apple Silicon** — [Token-Monitor-0.28.1-arm64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.28.1/Token-Monitor-0.28.1-arm64.dmg)
- **Windows Installer** — [Token-Monitor-Setup-0.28.1.exe](https://github.com/Javis603/token-monitor/releases/download/v0.28.1/Token-Monitor-Setup-0.28.1.exe) (recommended)
- **Windows Portable** — [Token-Monitor-0.28.1.exe](https://github.com/Javis603/token-monitor/releases/download/v0.28.1/Token-Monitor-0.28.1.exe) (no install required)
- **Linux x64** — [Token-Monitor-0.28.1.AppImage](https://github.com/Javis603/token-monitor/releases/download/v0.28.1/Token-Monitor-0.28.1.AppImage)

<details>
<summary><strong>First launch and other notes</strong></summary>

### First launch

**macOS:** open the `.dmg`, drag Token Monitor to Applications.

**Windows:** SmartScreen → More info → Run anyway.

**Linux:** mark the AppImage executable, then run it:

```bash
chmod +x "Token Monitor"*.AppImage
./"Token Monitor"*.AppImage
```

### Other notes

Other platforms are not pre-built — run from source per the [README](https://github.com/Javis603/token-monitor#readme). The macOS `.zip` is the same app repackaged; ignore it unless you specifically need it.

### tokscale dependency

Tokscale is bundled with this app. See **Settings → Tokscale** for the exact version
and the option to download a newer version directly from npm. Tokscale is MIT,
open-source: https://github.com/junhoyeo/tokscale

</details>

---

# 中文

**这是开源构建。** macOS 已签名并 notarize；Windows 尚未签名（可能跳出 SmartScreen）；Linux AppImage 需要先赋予执行权限，说明见下方。

## 更新内容

<!-- app-update-notes:zh:start -->
### 修复
- **实时用量更新：** 修复了历史会话较多时，刷新用量可能导致应用严重卡顿或短暂无响应的问题。会话归档现改为线性处理；在包含 568 个会话的实际案例中，处理时间由约 1.1 秒降至 13 毫秒。（#156）
<!-- app-update-notes:zh:end -->

## 下载

- **macOS Apple Silicon** — [Token-Monitor-0.28.1-arm64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.28.1/Token-Monitor-0.28.1-arm64.dmg)
- **Windows 安装版** — [Token-Monitor-Setup-0.28.1.exe](https://github.com/Javis603/token-monitor/releases/download/v0.28.1/Token-Monitor-Setup-0.28.1.exe)（推荐）
- **Windows 便携版** — [Token-Monitor-0.28.1.exe](https://github.com/Javis603/token-monitor/releases/download/v0.28.1/Token-Monitor-0.28.1.exe)（免安装）
- **Linux x64** — [Token-Monitor-0.28.1.AppImage](https://github.com/Javis603/token-monitor/releases/download/v0.28.1/Token-Monitor-0.28.1.AppImage)

<details>
<summary><strong>首次启动与其他说明</strong></summary>

### 首次启动

**macOS：** 打开 `.dmg`，把 Token Monitor 拖到 Applications。

**Windows：** SmartScreen → 更多信息 → 仍要运行。

**Linux：** 先给 AppImage 执行权限，然后运行：

```bash
chmod +x "Token Monitor"*.AppImage
./"Token Monitor"*.AppImage
```

### 其他说明

其他平台暂不提供预构建版本，请参考 [README](https://github.com/Javis603/token-monitor#readme) 从源码运行。macOS 的 `.zip` 只是同一个 app 的重新打包版本，除非你明确需要，否则可以忽略。

### tokscale 依赖

Tokscale 已随应用内置。你可以在 **设置 → Tokscale** 查看确切版本，
也可以直接从 npm 下载更新版本。Tokscale 是 MIT 开源项目：
https://github.com/junhoyeo/tokscale

</details>
