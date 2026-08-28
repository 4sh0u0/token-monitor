# English

## What's changed

<!-- app-update-notes:en:start -->
### Added
- **Cursor auto-detection and multi-account support:** Automatically detect the locally signed-in Cursor desktop account, combine token usage from multiple saved accounts, and manage limits per account. (#523)
- **Volcengine Agent Plan:** Show 5-hour, daily, weekly, and monthly quotas alongside the Coding Plan, with optional credentials when the Agent Plan is on another account. (#490, #532)
- **Grok limits in WSL:** Show Grok limits on Windows when the active login is inside a running WSL distribution. (#530)

### Fixed
- **Windows startup:** Fix an issue that could prevent recent versions from starting normally on some Windows systems. (#522)
- **Trae CN Credits:** Show balances for untouched credit packs and ignore feature-only entitlements without a credit limit. (#515)
- **Device ID reset:** Clearing a custom Device ID returns to the automatic hostname-based ID after restart, keeping the local device matched in sync views. (#441)
<!-- app-update-notes:en:end -->

## Download

- **macOS Apple Silicon** — [Token-Monitor-0.49.0-arm64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-arm64.dmg)
- **macOS Intel** — [Token-Monitor-0.49.0-x64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-x64.dmg)
- **Windows Installer** — [Token-Monitor-Setup-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-Setup-0.49.0.exe) (recommended)
- **Windows Portable** — [Token-Monitor-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.exe) (no install required)
- **Linux x64** — [Token-Monitor-0.49.0.AppImage](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.AppImage)

<details>
<summary><strong>First launch and other notes</strong></summary>

### First launch

**macOS:** the app is Developer ID-signed and notarized by Apple. Open the `.dmg`, then drag Token Monitor to Applications.

**Windows:** both executables are signed ([how to verify](https://github.com/Javis603/token-monitor/blob/main/docs/code-signing.md#verify-a-download)).

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

## 更新内容

<!-- app-update-notes:zh:start -->
### 新增
- **Cursor 自动检测与多账号：** 自动检测本机 Cursor 桌面版已登录的账号，合并追踪多个已保存账号的 Token 用量，并分别管理各账号的额度。（#523）
- **Volcengine Agent Plan：** 在 Coding Plan 之外显示 5 小时、每日、每周和每月额度；若 Agent Plan 位于其他账号，也可单独设置凭证。（#490, #532）
- **WSL 中的 Grok 额度：** Windows 上的 Grok 登录位于正在运行的 WSL 发行版中时，也能显示额度。（#530）

### 修复
- **Windows 启动：** 修复近期版本在部分 Windows 系统上可能无法正常启动的问题。（#522）
- **Trae CN Credits：** 未使用的积分包可正常显示余额，并忽略没有积分额度的功能权益。（#515）
- **设备 ID 重置：** 清空自定义设备 ID 后，重启时会恢复为按主机名自动生成的 ID，确保同步视图继续匹配本机设备。（#441）
<!-- app-update-notes:zh:end -->

## 下载

- **macOS Apple Silicon** — [Token-Monitor-0.49.0-arm64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-arm64.dmg)
- **macOS Intel** — [Token-Monitor-0.49.0-x64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-x64.dmg)
- **Windows 安装版** — [Token-Monitor-Setup-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-Setup-0.49.0.exe)（推荐）
- **Windows 便携版** — [Token-Monitor-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.exe)（免安装）
- **Linux x64** — [Token-Monitor-0.49.0.AppImage](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.AppImage)

<details>
<summary><strong>首次启动与其他说明</strong></summary>

### 首次启动

**macOS：** 应用已使用 Developer ID 签名并通过 Apple 公证。打开 `.dmg`，然后把 Token Monitor 拖到 Applications。

**Windows：** 两个可执行文件均已签名（[查看验证方法](https://github.com/Javis603/token-monitor/blob/main/docs/code-signing.md#verify-a-download)）。

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

---

<details>
<summary><strong>Full Changelog:</strong> <a href="https://github.com/Javis603/token-monitor/compare/v0.48.0...v0.49.0">v0.48.0...v0.49.0</a></summary>

<!-- github-generated-release-notes -->

</details>

<details>
<summary>繁體中文 · 한국어 · 日本語</summary>

<details>
<summary><strong>繁體中文</strong></summary>

## 繁體中文

## 更新內容

<!-- app-update-notes:zh-TW:start -->
### 新增
- **Cursor 自動偵測與多帳號：** 自動偵測本機 Cursor 桌面版已登入的帳號、合併追蹤多個已儲存帳號的 Token 用量，並分別管理各帳號的額度。（#523）
- **Volcengine Agent Plan：** 在 Coding Plan 之外顯示 5 小時、每日、每週與每月額度；若 Agent Plan 位於其他帳號，也可另行設定憑證。（#490, #532）
- **WSL 中的 Grok 額度：** Windows 上的 Grok 登入位於正在執行的 WSL 發行版時，也能顯示額度。（#530）

### 修復
- **Windows 啟動：** 修復近期版本在部分 Windows 系統上可能無法正常啟動的問題。（#522）
- **Trae CN Credits：** 未使用的點數包可正常顯示餘額，並忽略沒有點數額度的功能權益。（#515）
- **裝置 ID 重設：** 清除自訂裝置 ID 後，重新啟動時會恢復為依主機名稱自動產生的 ID，讓同步檢視繼續正確對應本機裝置。（#441）
<!-- app-update-notes:zh-TW:end -->

## 下載

- **macOS Apple Silicon** — [Token-Monitor-0.49.0-arm64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-arm64.dmg)
- **macOS Intel** — [Token-Monitor-0.49.0-x64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-x64.dmg)
- **Windows 安裝版** — [Token-Monitor-Setup-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-Setup-0.49.0.exe)（推薦）
- **Windows 便攜版** — [Token-Monitor-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.exe)（免安裝）
- **Linux x64** — [Token-Monitor-0.49.0.AppImage](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.AppImage)

</details>

<details>
<summary><strong>한국어</strong></summary>

## 한국어

## 업데이트 내용

<!-- app-update-notes:ko:start -->
### 추가
- **Cursor 자동 감지 및 다중 계정:** 로컬 Cursor 데스크톱 앱에 로그인된 계정을 자동으로 감지하고 여러 저장 계정의 토큰 사용량을 합산해 추적하며, 계정별 한도를 관리할 수 있습니다. (#523)
- **Volcengine Agent Plan:** Coding Plan과 함께 5시간·일일·주간·월간 할당량을 표시하며, Agent Plan이 다른 계정에 있으면 별도 자격 증명을 설정할 수 있습니다. (#490, #532)
- **WSL의 Grok 한도:** Windows에서 실행 중인 WSL 배포판에 Grok 로그인이 있으면 해당 한도를 표시합니다. (#530)

### 수정
- **Windows 시작:** 일부 Windows 시스템에서 최근 버전이 정상적으로 시작되지 않을 수 있는 문제를 수정했습니다. (#522)
- **Trae CN Credits:** 사용하지 않은 크레딧 팩의 잔액을 표시하고 크레딧 한도가 없는 기능 전용 권한은 제외합니다. (#515)
- **기기 ID 재설정:** 사용자 지정 기기 ID를 지우면 재시작 후 호스트명 기반 자동 ID로 돌아가 동기화 화면에서 로컬 기기를 계속 올바르게 찾습니다. (#441)
<!-- app-update-notes:ko:end -->

## 다운로드

- **macOS Apple Silicon** — [Token-Monitor-0.49.0-arm64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-arm64.dmg)
- **macOS Intel** — [Token-Monitor-0.49.0-x64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-x64.dmg)
- **Windows 설치 버전** — [Token-Monitor-Setup-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-Setup-0.49.0.exe) (권장)
- **Windows 포터블 버전** — [Token-Monitor-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.exe) (설치 필요 없음)
- **Linux x64** — [Token-Monitor-0.49.0.AppImage](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.AppImage)

</details>

<details>
<summary><strong>日本語</strong></summary>

## 日本語

## 更新内容

<!-- app-update-notes:ja:start -->
### 追加
- **Cursorの自動検出と複数アカウント：** ローカルのCursorデスクトップアプリでサインイン中のアカウントを自動検出し、保存済みの複数アカウントのトークン使用量を合算して追跡しながら、アカウントごとの上限を管理できます。（#523）
- **Volcengine Agent Plan：** Coding Planと並べて5時間・日次・週次・月次の割り当てを表示し、Agent Planが別アカウントにある場合は専用の認証情報も設定できます。（#490, #532）
- **WSLのGrok上限：** Windowsで実行中のWSLディストリビューションにGrokのログイン情報がある場合も上限を表示します。（#530）

### 修正
- **Windowsの起動：** 一部のWindows環境で最近のバージョンが正常に起動しないことがある問題を修正しました。（#522）
- **Trae CN Credits：** 未使用のクレジットパックの残高を表示し、クレジット上限のない機能専用権限は除外します。（#515）
- **デバイスIDのリセット：** カスタムのデバイスIDを消去すると、再起動後にホスト名ベースの自動IDへ戻り、同期画面でローカルデバイスを正しく照合できます。（#441）
<!-- app-update-notes:ja:end -->

## ダウンロード

- **macOS Apple Silicon** — [Token-Monitor-0.49.0-arm64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-arm64.dmg)
- **macOS Intel** — [Token-Monitor-0.49.0-x64.dmg](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0-x64.dmg)
- **Windows インストーラー** — [Token-Monitor-Setup-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-Setup-0.49.0.exe)（推奨）
- **Windows ポータブル版** — [Token-Monitor-0.49.0.exe](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.exe)（インストール不要）
- **Linux x64** — [Token-Monitor-0.49.0.AppImage](https://github.com/Javis603/token-monitor/releases/download/v0.49.0/Token-Monitor-0.49.0.AppImage)

</details>

</details>
