# KorpProxy.app

Native macOS menu-bar app that supervises the KorpProxy engine (the Go
`cli-proxy-api` server at the repo root) and will grow a UI for accounts,
models, and logs.

## Architecture

| File | Role |
|------|------|
| `KorpProxyApp.swift` | `@main` app — `MenuBarExtra` + Settings scene |
| `AppState.swift` | Observable app state (status, log tail) |
| `ProxyManager.swift` | Launches/stops/health-checks the engine process |
| `ConfigStore.swift` | Manages `~/Library/Application Support/KorpProxy/` (config.yaml, auths, logs) |
| `ManagementClient.swift` | Async client for the engine's `/v0/management` API (MVP: port ping) |
| `MenuContentView.swift` | Menu-bar dropdown (status, Start/Stop/Restart) |
| `SettingsView.swift` | Settings window (engine info + live log tail) |

The Xcode project, `Info.plist`, and entitlements are **generated** from
`project.yml` via [XcodeGen] and are git-ignored.

## Build & run

```bash
brew install xcodegen          # one-time
cd app
xcodegen generate              # produces KorpProxy.xcodeproj
./scripts/build-engine.sh      # builds the Go engine → app/.engine-bin/ (dev fallback)
open KorpProxy.xcodeproj       # then Run (⌘R) in Xcode
```

In Xcode, set your Signing Team (Automatic) on first run. The app is
unsandboxed (it spawns the engine and binds a local port) so it is **not**
intended for the Mac App Store.

### Engine binary resolution

`ProxyManager` looks for the engine in this order:

1. `KORP_PROXY_BIN` env var (absolute path)
2. bundled `Contents/Resources/korpproxy-server` (release)
3. `app/.engine-bin/korpproxy-server` (dev — produced by `build-engine.sh`)

For release builds, add a Run Script phase that calls
`scripts/build-engine.sh --bundle "$BUILT_PRODUCTS_DIR/KorpProxy.app"`.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
