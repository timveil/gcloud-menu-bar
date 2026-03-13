# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

`GCloudMenuBar.xcodeproj` is **generated and gitignored** — never edit it directly and never commit it.

```sh
make generate          # regenerate .xcodeproj from project.yml (required after any file add/remove or build setting change)
make open              # generate + open in Xcode
make build             # Debug build, unsigned, via xcodebuild (CLI)
make archive           # Release archive → build/GCloudMenuBar.xcarchive
make export            # Sign + notarize via ExportOptions.plist (requires team ID)
make clean             # rm -rf build/
```

There are no unit tests and no linter configured. Build warnings are treated as meaningful — the project compiles with `SWIFT_STRICT_CONCURRENCY: complete` (Swift 6 mode), so any new concurrency warning is a real issue.

## Architecture

This is a single-target macOS menu bar app. There is no SPM manifest — the build system is xcodegen (`project.yml`) generating a plain `.xcodeproj`.

### Data flow

```
GCloudMenuBarApp  (@main, App)
  └─ @State GCloudManager  (@Observable @MainActor)
       └─ injected via .environment(manager)
            └─ MenuBarView  (@Environment(GCloudManager.self))
                 ├─ AccountRow  (@Environment(GCloudManager.self))
                 └─ ProjectRow  (@Environment(GCloudManager.self))
```

`GCloudManager` is the single source of truth. All state lives there as plain `var` properties (no `@Published` — `@Observable` handles observation automatically). Views read state directly via `@Environment`; they never hold their own copies.

### GCloudManager lifecycle

1. `init` fires `Task { [weak self] in await bootstrap() }`
2. `bootstrap` resolves the gcloud binary path, calls `refresh()`, then starts a `ContinuousClock` Task loop that calls `refreshAuthStatus()` every 60 seconds
3. `refresh()` is rate-limited by an `isLoading` guard; it fetches accounts, active project, and projects in parallel via `async let`, then calls `refreshAuthStatus()`
4. `refreshAuthStatus()` calls `gcloud auth print-access-token` then hits `https://oauth2.googleapis.com/tokeninfo` to get the real expiry date
5. Login opens a Terminal window via `NSAppleScript` — there is **no auto-refresh after login**; the user must click Refresh

### Shell execution pattern

All `gcloud` CLI calls go through two helpers:

- `shell(_ args: [String]) async -> (String, Int32)` — `nonisolated`, runs via `Task.detached { @Sendable in }` with a `DispatchSemaphore` timeout of 15 seconds. Returns stdout+stderr merged and the exit code.
- `shellDecode<T: Decodable>(_ args: [String]) async -> T?` — calls `shell`, guards on exit code 0, then `JSONDecoder().decode`. Sets `errorMessage` on non-zero exit.

`shell` is `nonisolated` so it can be called from the `@MainActor`-isolated class without actor-hopping warnings under Swift 6 strict concurrency.

### Key constraints

- **Sandbox is OFF** (`ENABLE_APP_SANDBOX: NO`) — required for `Process()` and `NSAppleScript`. This is intentional and must never be changed; it is why the app cannot be distributed on the Mac App Store.
- **Hardened Runtime is ON** (`ENABLE_HARDENED_RUNTIME: YES`) — required for Developer ID notarization. The `com.apple.security.automation.apple-events` entitlement is needed to allow NSAppleScript under hardened runtime.
- **`LSUIElement = true`** in `Info.plist` — suppresses Dock icon and App Switcher entry.
- `AuthStatus` is an enum with associated `Date` values. Always use `authStatus.isExpiringSoon` (not `== .expiringSoon(expiresAt: Date())`) to check for the expiring-soon case — the associated date makes direct equality useless.
- `StatusColor` is a project-internal type mapped to `SwiftUI.Color` in the `StatusColor.swiftUIColor` extension in `MenuBarView.swift`. `.yellow` maps to `Color.yellow` (not `.orange`).

### Adding a new source file

1. Create the file under `Sources/GCloudMenuBar/`
2. Run `make generate` — xcodegen picks it up via the directory glob in `project.yml`
