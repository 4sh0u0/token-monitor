# Native iPhone and Apple Watch App

A read-only companion for a Token Monitor Hub: an iPhone app (Overview, Limits, Devices, Settings), Home Screen and Lock Screen widgets, a watchOS app, and watch complications. A phone has no local AI-tool logs, so every surface reads the Hub's HTTP API (`GET /api/health`, `GET /api/stats`, `GET /api/stats/stream`; see [docs/API.md](../../docs/API.md)) and nothing is ever posted. The secret is sent as `Authorization: Bearer`, never as `?secret=`.

## Connecting to a Hub

Any Hub from the [Multi-device sync](../../README.md#multi-device-sync) section (Options A to C; iCloud Drive is not a Hub) works, as long as the phone can reach it:

- **Host hub on this device** (the desktop widget): the phone must be on the same network or tailnet. Enter one of the addresses the widget lists and its secret. The Hub runs only while Token Monitor is running.
- **Node hub** (`npm run hub`, port 17321) on an always-on machine: same network or tailnet.
- **Cloudflare Worker**: an `https://` address that works from anywhere, including mobile data.
- **Tailscale**: reaches the first two from outside the home network with the phone's Tailscale app running.

Addresses without a `scheme://` get `http://` when the host is on the local network or a tailnet (loopback, `.local`, `.home.arpa`, unqualified names, RFC 1918, link-local and `100.64.0.0/10` addresses, IPv6 ULA, and Tailscale `*.ts.net` names) and `https://` for everything else, because the Node hub and the Host hub serve plain HTTP and an `https://` guess would only fail the TLS handshake. An explicit scheme is always kept, so a Tailscale Serve or Funnel HTTPS address must be typed with `https://`. A pasted `/api/...` path, query and URL credentials are dropped; a reverse-proxy path prefix is kept.

Plain `http://` to a host that is not local or on a tailnet is allowed but shows a warning in the connection form, because the secret and usage would cross the internet unencrypted. The first request to a LAN Hub makes iOS ask for Local Network access (`NSLocalNetworkUsageDescription` on the iPhone app); if it was declined, the app reports the Hub as unreachable and points to Settings › Privacy & Security › Local Network.

## Requirements

- Xcode 16 or newer: the project uses file-system synchronized groups (`objectVersion 77`). It was created with Xcode 26, and CI builds with the Xcode on GitHub's `macos-latest` image without pinning one.
- iOS 17 and watchOS 10 deployment targets. The iPhone target also builds for iPad, but only an iPhone pairs with the watch.
- Swift language mode 5 everywhere (`SWIFT_VERSION = 5.0`, package tools 5.9): strict concurrency checking would turn the shared Foundation types into build breaks. No third-party dependencies.
- An Apple Developer team to run on a device (see Configuration). Unsigned simulator builds, as in CI, need none.

## Configuration

`Config/Base.xcconfig` holds committed, non-personal placeholders and ends with `#include? "Local.xcconfig"`; both project-level build configurations are based on it, so every target inherits it. Personal values go in `Config/Local.xcconfig`, which is gitignored:

```bash
cp native/ios/Config/Local.xcconfig.example native/ios/Config/Local.xcconfig
# then set TM_BUNDLE_ID, TM_APP_GROUP and DEVELOPMENT_TEAM in it
```

The placeholders (`com.example.tokenmonitor.mobile`, `group.com.example.tokenmonitor`, empty team) build unsigned, which is what CI does. Only the iPhone app's bundle id is configurable; the others are derived from it because an embedded bundle's id must be prefixed by its host's and the watch app's `WKCompanionAppBundleIdentifier` must equal it:

| Scheme and target | Folder | Bundle id |
|---|---|---|
| `TokenMonitor` (iPhone app; embeds the widget and the watch app) | `TokenMonitor/` | `$(TM_BUNDLE_ID)` |
| `TokenMonitorWidget` (Home and Lock Screen widgets) | `TokenMonitorWidget/` | `$(TM_BUNDLE_ID).widget` |
| `TokenMonitorWatch` (watch app; embeds the complications; needs the iPhone app) | `TokenMonitorWatch/` | `$(TM_BUNDLE_ID).watchkitapp` |
| `TokenMonitorWatchWidget` (complications) | `TokenMonitorWatchWidget/` | `$(TM_BUNDLE_ID).watchkitapp.widget` |

`TM_APP_GROUP` must start with `group.`, exist in the Apple Developer account of `DEVELOPMENT_TEAM`, and be enabled for all four App IDs above. The same identifier is the App Group entitlement and `TMAppGroup` Info.plist key of every target, the `UserDefaults` suite and container that hold the Hub URL and the snapshot, and the Keychain access group of the Hub secret (valid on iOS and watchOS without a `keychain-access-groups` entitlement). Changing `TM_APP_GROUP` therefore starts from an empty state. Where the App Group container is unavailable the app keeps working on its own caches directory and standard defaults, but widgets and the watch see nothing of its data, so exercise them with a build signed by your team.

Do not pick the team in Xcode's Signing & Capabilities tab, and do not set the bundle id or App Group in a target's build settings. Xcode writes the team into `project.pbxproj`, where it shadows `Local.xcconfig` and puts personal values in the diff.

## Build and test

```bash
swift test --package-path native/ios/TokenMonitorKit
xcodebuild -project native/ios/TokenMonitor.xcodeproj -scheme TokenMonitor -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project native/ios/TokenMonitor.xcodeproj -scheme TokenMonitorWatch -destination 'generic/platform=watchOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

These are the three steps of the `ios` job in `.github/workflows/ci.yml`. The package tests (XCTest, with fixtures captured from a real Node hub) cover the Foundation-only core and are kept runnable on Linux; CI runs them on macOS. There are no Xcode test targets, and `npm run verify` does not cover the Swift code; only the generated vendor catalog has a Node-side test.

In Xcode, open `native/ios/TokenMonitor.xcodeproj` and run the `TokenMonitor` scheme on an iPhone or simulator, or `TokenMonitorWatch` on a watch or simulator. The two widget schemes debug the extensions, and each widget file carries `#Preview(as:)` timelines that render every supported family in the canvas.

## Architecture

`TokenMonitorKit` (a local Swift package, `native/ios/TokenMonitorKit`) has two products:

- **`TokenMonitorKit`** is Foundation-only and must keep building and testing on Linux: Hub client, lenient models, connection store, snapshot, formatting and the vendor catalog. `Security` and `FoundationNetworking` are imported behind `canImport`, and the SSE stream (`statsStream()`) exists only on Darwin. Decoding is lenient, so an unknown or missing field never fails a whole response.
- **`TokenMonitorUI`** is shared SwiftUI (theme, meters, sparkline, accessory views) for the app, widgets and watch. Every file is wrapped in `#if canImport(SwiftUI)` and takes text as parameters, so localization stays in each target's catalog.

The data path is Hub, then `HubStats` (the full response), then `TokenSnapshot`, a compact projection that is bounded by construction (top tools and models per period, a 30-day trend cap, a few limit windows per provider, masked account emails) and holds no secret. `SnapshotStore` writes it atomically to `token-snapshot.json` in the App Group container, readable after the first unlock. Widgets and complications render the snapshot and go to the Hub only when it is old; the watch app also fetches the Hub itself while it is on screen.

Each snapshot records `hubKey`, the `HubConnection.snapshotKey` of the Hub it came from: a hash of the normalized URL, never derived from the secret. Every reader checks it with `belongs(to:)` or `belongs(toHubKey:)`, so after a Hub switch a snapshot of the previous Hub is treated as missing: the iPhone app stamps and pushes only its current Hub's, the watch ignores a pushed or cached one from another Hub, and widgets and complications discard a fetch whose Hub changed while it was in flight instead of showing or saving it. A snapshot without a `hubKey` (written before the field existed) is shown. The watch, widgets and complications compare against `HubConnectionStore.snapshotKey` or `HubConnection.snapshotKey(for:)`, which need only the saved URL, because the Keychain refuses the secret before the first unlock.

**iPhone app.** While the app is active it holds `GET /api/stats/stream` and applies every `stats` event. Active means the app's combined scene phase, read in `TokenMonitorApp` rather than in a view, so on iPad one window going to the background does not stop updates while another is still on screen. A dropped stream reconnects with capped exponential backoff and jitter; after four consecutive failed attempts it polls `/api/stats` every 30 s and retries the stream every ten polls. If a proxy buffers the stream and no event arrives within 8 s, one plain read fills the screen. Errors only the user can fix (bad address, wrong secret) stop live updates until settings change or the user pulls to refresh. HTTP 503 reads as "The Hub is unavailable" (the Hub or a proxy in front of it is down, or a Cloudflare Worker has no `TOKEN_MONITOR_SECRET`) and keeps retrying. Going to the background closes the stream; the app does no background fetching. Changed numbers rewrite the App Group snapshot and hand it to the watch bridge at most every 20 s, writing the latest numbers when that window ends; the first numbers after launch or a connection change are written at once, and a pending write is flushed when the app goes to the background. Unchanged numbers refresh the snapshot once a minute. A write reloads widget timelines at most every 5 minutes; saving or clearing the connection reloads them at once. Changing the Hub clears the old snapshot on the phone, in widgets and on the watch.

**iOS widgets.** Two widgets: Usage (small, medium, large, and Lock Screen circular, rectangular, inline; period and breakdown are configurable) and AI Tool Limits (small, medium, Lock Screen circular and rectangular; optionally pinned to one provider). A timeline provider shows a cached snapshot younger than 10 minutes as is; an older one triggers one Hub request with a 10 s timeout, falling back to the cache. It asks WidgetKit for the next reload after 15 minutes and marks data as stale when it is older than 30 minutes, from an earlier day, or the Hub reports every device as stale. A period that has rolled over since the fetch (today after midnight, this month after the 1st, in the device's calendar) shows "—" instead of the old totals. Extra entries at the stale moment, at midnight and at upcoming limit resets keep countdowns from running past their reset. Concurrent loads share one fetch (`SnapshotFetchCoalescer`, keyed by the Hub, with a fetch reused for 60 s), because every widget decoding its own copy of `/api/stats` is how an extension exceeds its memory limit. The Limits widget's automatic order is `LimitProvider.sortedByUrgency`: healthy readings first, least left first. The constants are in `WidgetTiming` (`WidgetSupport.swift`). Widgets link into the app with `tokenmonitor://dashboard?period=today|month|allTime`, `limits` and `settings` (the app also routes `devices`).

**Watch app.** Shows the cached snapshot first, then fetches the Hub itself once a minute while on screen (no SSE: a held connection costs more battery than a poll while the screen is on). A snapshot younger than 30 s is not refetched when the app becomes active again, and numbers older than 15 minutes are marked stale. A wrong secret makes it ask the iPhone to sync again.

**Complications.** Two complications, Summary and Quota, in circular, rectangular, inline and corner families. They read the watch-side snapshot, make one best-effort Hub request when it is older than 20 minutes, and ask for a reload after 20 minutes (60 when no Hub is configured), plus an entry at midnight, after which Summary shows "—" until today's numbers arrive. Both complications share that request through the same `SnapshotFetchCoalescer` the iOS widgets use, instead of each decoding its own copy of `/api/stats` in a memory-tight extension, on an ephemeral session without a URL cache that gives up after 15 s. Quota leads with the tightest window, in the iOS Limits widget's order. A window without a meter (a balance-only account) shows its value on a plain disc, here and on the iOS widgets, never as an empty ring that would read as nothing left.

**iPhone to watch.** The watch cannot read the iPhone's Keychain or App Group, so `PhoneSessionBridge` (iPhone app) sends the connection and snapshot over WatchConnectivity and `WatchSessionBridge` (watch app) stores them in the watch's own Keychain item and App Group, which is also what the complications read. Payload keys:

| Key | Meaning |
|---|---|
| `v` | Protocol version (`protocolVersion`, currently 1) |
| `rev` | Milliseconds, strictly increasing across launches; the watch drops anything older than the connection state it already applied |
| `connected` | `false` means the user disconnected the Hub; the watch then clears its copy |
| `hub` | JSON-encoded `HubConnection` (URL and secret) |
| `snapshot` | `TokenSnapshot` JSON |
| `request` = `sync` | Watch-to-phone message asking for the current state; the reply has the same shape |

`updateApplicationContext` carries the connection and snapshot: connection changes go out at once, snapshot-only updates collapse to at most one a minute, and identical content is not resent. `transferCurrentComplicationUserInfo` carries only `v`, `rev` and `snapshot`, and only while WatchConnectivity reports a complication as enabled. It draws on a daily budget of about 50 transfers, so it is spaced 20 minutes apart, or 60 once 10 or fewer remain. A sync request wakes the iPhone app in the background; the watch sends one when it has no connection, after a wrong-secret error, or on Try Again.

## Compatibility surfaces and gotchas

- **Never rename a widget or complication `kind`.** WidgetKit identifies placed widgets and watch-face complications by it, so a rename removes them from users' Home Screens, Lock Screens and watch faces. The kinds are `TokenMonitorUsageWidget` and `TokenMonitorLimitsWidget` (`WidgetKind` in `TokenMonitorWidget/WidgetSupport.swift`), and `com.tokenmonitor.watch.usage` and `com.tokenmonitor.watch.quota` (`ComplicationKind` in `TokenMonitorWatchWidget/ComplicationTimeline.swift`).
- **The WatchConnectivity payload is a contract between phone and watch builds** that can differ in the field. The keys are mirrored in `PhoneSessionBridge.Key` and `WatchSessionBridge.Key`; change both together. The watch ignores, without any error, a payload whose `v` is not exactly its own `protocolVersion`, so bumping it silently stops an older counterpart from syncing; plan the transition before changing a key's meaning.
- **`TokenSnapshot` changes.** Adding a field is safe. Changing a field's meaning needs a `currentSchemaVersion` bump, after which readers ignore newer snapshots instead of misrendering them.
- **The secret lives in the Keychain on both devices** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable after the first unlock, never iCloud-synchronized or restored from a backup to another device; saving moves an item written by an earlier build to that class). WatchConnectivity also retains the last application context, which includes the secret, inside each app's sandbox, and the watch reapplies the retained context at activation. The encoded `HubConnection` (secret included) belongs only on that transfer. Before the first unlock the Keychain refuses reads, so widgets and the watch keep showing the cache and never call the Hub without its secret.
- **ATS is `NSAllowsArbitraryLoads` only**, in all four Info.plists, because users run plain-HTTP Hubs on a LAN or tailnet. Do not add `NSAllowsLocalNetworking`: iOS then ignores `NSAllowsArbitraryLoads`, which those plain-HTTP Hubs rely on.
- **`INFOPLIST_KEY_NSLocalNetworkUsageDescription` in `project.pbxproj`** (Debug and Release) and the English text in `TokenMonitor/InfoPlist.xcstrings` must stay in step.
- **Generated asset symbols are on.** Each target's `AccentColor` (and the widget targets' `WidgetBackground`) color set generates `Color.accent` (and `Color.widgetBackground`), so do not declare same-named `Color` statics in target code or `TokenMonitorUI` (`TMTheme.accent` is fine: it is namespaced).
- **`VendorCatalog+Generated.swift` is generated** from the desktop's vendor, client and limits tables. Do not edit it; after changing those tables run `npm run sync:ios-vendors`. `tests/shared/iosVendorCatalog.test.js` fails on drift.
- **The stream client omits `x-token-monitor-stream: 2`** on purpose: with it the Hub sends `freshness` deltas that must be merged into a held snapshot, while without it every update is a complete `stats` event.
- **WidgetKit and watch refresh intervals are requests, not guarantees.** The system budgets reloads, so a widget can lag well behind its 15 and 20 minute asks; the iOS widgets' 30-minute stale threshold sits well past their ask for that reason.

## Localization

String Catalogs (`Localizable.xcstrings`) sit in each target folder, with `InfoPlist.xcstrings` in the iPhone app for the Local Network prompt. The source language is English, with `ja`, `ko`, `pt-BR`, `zh-Hans` and `zh-Hant` translations. Product and vendor names are not translated.
