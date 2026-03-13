# GCloud Menu Bar

A macOS menu bar app that wraps the `gcloud` CLI, giving you at-a-glance auth status, token expiry, account switching, and project switching — all without opening a terminal.

---

## How It Works

On launch the app:

1. Locates your `gcloud` binary (checks common Homebrew and SDK paths, then falls back to `which gcloud`)
2. Fetches your credentialed accounts, active project, and project list in parallel
3. Calls `gcloud auth print-access-token` and hits `https://oauth2.googleapis.com/tokeninfo` to determine token expiry
4. Polls every 60 seconds to keep the expiry display current

The menu bar icon reflects auth state at a glance:

| Icon | Meaning |
|---|---|
| `cloud.fill` (blue) | Authenticated, token valid |
| `exclamationmark.icloud.fill` (yellow) | Token expiring in < 10 minutes |
| `icloud.slash.fill` (red) | Token expired or no account |
| `cloud` (gray) | Checking / unknown |

**Login flow:** clicking Login or Add Account opens a Terminal window running `gcloud auth login`. After the OAuth flow completes in the browser, click **Refresh** in the popover — the app does not auto-poll after login.

---

## Requirements

| Tool | Version | Install |
|---|---|---|
| macOS | 14.0 (Sonoma) or later | — |
| Xcode | 16.x | Mac App Store or [developer.apple.com](https://developer.apple.com/xcode/) |
| xcodegen | any recent | `brew install xcodegen` |
| gcloud CLI | any | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |

xcpretty is optional but makes `make build` output cleaner:

```sh
gem install xcpretty
```

---

## Project Structure

```
/
├── .github/workflows/build.yml        # CI: build on push/PR, release zip on tags
├── .gitignore
├── Assets.xcassets/                   # App icon placeholder (no PNGs yet)
├── ExportOptions.plist                # Developer ID signing config (gitignored)
├── GCloudMenuBar.entitlements         # Hardened runtime + Apple Events entitlements
├── Info.plist                         # Bundle metadata, LSUIElement = true
├── Makefile                           # Developer workflow shortcuts
├── Sources/GCloudMenuBar/
│   ├── GCloudMenuBarApp.swift         # App entry point + MenuBarLabel
│   ├── GCloudManager.swift            # All gcloud CLI interaction (@Observable)
│   ├── Models.swift                   # Data types (Sendable, AuthStatus, TokenInfo)
│   └── Views/MenuBarView.swift        # Popover UI
├── original/                          # Original prototype (reference only)
└── project.yml                        # xcodegen spec → GCloudMenuBar.xcodeproj
```

> `GCloudMenuBar.xcodeproj` is **generated** and gitignored. Never commit it. Run `make generate` to recreate it.

---

## Development Setup

### 1. Clone and install tools

```sh
git clone https://github.com/timveil/gcloud-menu-bar.git
cd gcloud-menu-bar
brew install xcodegen
```

### 2. Generate the Xcode project

```sh
make generate
# or equivalently:
xcodegen generate
```

This reads `project.yml` and writes `GCloudMenuBar.xcodeproj`. Re-run any time you add/remove source files or change build settings in `project.yml`.

### 3. Open in Xcode

```sh
make open
# equivalent to: xcodegen generate && open GCloudMenuBar.xcodeproj
```

### 4. Build and run

- **In Xcode:** `⌘B` to build, `⌘R` to run. The app appears in the menu bar with no Dock icon (`LSUIElement = true`).
- **From the command line (Debug, unsigned):**

```sh
make build
```

### Adding or removing source files

Because `project.yml` uses a directory glob (`Sources/GCloudMenuBar`), you only need to re-run `make generate` after adding or removing `.swift` files. Xcode will pick up the new project automatically if you have auto-refresh enabled, or you can close and reopen it.

---

## Make Targets

```
make generate   Generate GCloudMenuBar.xcodeproj from project.yml
make open       Generate and open in Xcode
make build      Build Debug configuration (unsigned, no signing required)
make archive    Build Release archive to build/GCloudMenuBar.xcarchive
make export     Sign and export .app using ExportOptions.plist (requires team ID)
make clean      Remove the build/ directory
make help       Print this list
```

---

## Local Testing Checklist

After `⌘R` in Xcode or running the Debug build:

- [ ] Menu bar icon appears (no Dock icon, no App Switcher entry)
- [ ] Popover opens on click; shows your active account and token expiry
- [ ] Token expiry countdown updates every 60 seconds
- [ ] Accounts section expands/collapses; Switch and trash buttons work
- [ ] Projects section expands/collapses; Use button switches active project
- [ ] "Login" button opens a new Terminal window running `gcloud auth login`
- [ ] "App Default" button opens Terminal running `gcloud auth application-default login`
- [ ] After completing OAuth in browser, clicking Refresh updates auth status
- [ ] Logging out an account removes it from the list
- [ ] Error banner appears (and can be dismissed) when gcloud is not found

**Simulating expiring-soon state:** temporarily lower the threshold in `GCloudManager.swift`:

```swift
} else if remaining < 600 {   // change to a large number, e.g. 7200, to test yellow state
```

---

## Deployment

Distribution is via **GitHub Releases** (direct download) and optionally **Homebrew Cask**. The app is **not** on the Mac App Store — it uses `Process()` and `NSAppleScript`, which are incompatible with App Store sandboxing.

### Prerequisites

- An Apple Developer account with an active membership
- A **Developer ID Application** certificate installed in your keychain
- Your 10-character **Team ID** (visible at [developer.apple.com/account](https://developer.apple.com/account) → Membership)

### One-time setup: ExportOptions.plist

`ExportOptions.plist` is gitignored because it contains your Team ID. Create it at the repo root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>XXXXXXXXXX</string>   <!-- your 10-char Team ID -->
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>notarizeApp</key>
    <true/>
    <key>stapleApp</key>
    <true/>
</dict>
</plist>
```

### Build, sign, notarize, and staple

```sh
make export
```

This runs three steps in sequence:

1. `make generate` — regenerates the Xcode project
2. `make archive` — builds a Release archive at `build/GCloudMenuBar.xcarchive`
3. `xcodebuild -exportArchive` — signs with your Developer ID certificate, submits to Apple for notarization, and staples the notarization ticket

The final `.app` lands in `build/export/GCloudMenuBar.app`.

> **Note:** notarization requires an internet connection and typically takes 30–120 seconds. If it times out or fails, check `build/export/ExportOptions/` for the notarization log.

### Package for distribution

```sh
ditto -c -k --keepParent build/export/GCloudMenuBar.app GCloudMenuBar.zip
```

Attach the zip to a GitHub Release (see below) or submit the `.app` to a Homebrew Cask tap.

---

## Releasing via GitHub

### 1. Bump the version

Edit `project.yml`:

```yaml
MARKETING_VERSION: "1.1.0"
CURRENT_PROJECT_VERSION: "2"
```

Commit the change:

```sh
git add project.yml
git commit -m "chore: bump version to 1.1.0"
git push
```

### 2. Tag the release

```sh
git tag v1.1.0
git push origin v1.1.0
```

Pushing a `v*` tag triggers the `release` job in `.github/workflows/build.yml`, which:

1. Builds a Release archive (unsigned in CI — see note below)
2. Packages `GCloudMenuBar.app` into `GCloudMenuBar.zip`
3. Creates a GitHub Release with auto-generated release notes and attaches the zip

### CI signing (follow-on step)

The CI release job currently builds **unsigned**. For a fully signed and notarized CI release:

1. Export your Developer ID certificate as a `.p12` file
2. Add these GitHub Actions secrets to the repo:
   - `CERTIFICATES_P12` — base64-encoded `.p12`
   - `CERTIFICATES_P12_PASSWORD` — password for the `.p12`
   - `NOTARIZATION_APPLE_ID` — your Apple ID email
   - `NOTARIZATION_PASSWORD` — an app-specific password from appleid.apple.com
   - `NOTARIZATION_TEAM_ID` — your 10-char Team ID
3. Update the `release` job in `build.yml` to import the cert and use real signing flags

Until then, sign and notarize locally with `make export` and upload the resulting zip to the GitHub Release manually.

---

## Key Technical Decisions

| Decision | Rationale |
|---|---|
| No App Store | `Process()` and `NSAppleScript` require sandbox OFF |
| `@Observable` + `@MainActor` | Swift 6 replacement for `ObservableObject`/Combine; all UI state on main actor |
| `nonisolated` shell via `Task.detached` | Runs subprocesses off the main actor without actor-isolation errors |
| `ContinuousClock` Task loop | Structured concurrency replacement for Combine timer; respects task cancellation |
| `xcodegen` | Keeps `.xcodeproj` out of git; build settings are reviewable in `project.yml` |
| `LSUIElement = true` | Pure menu bar agent — no Dock icon, no App Switcher entry |
| Hardened Runtime ON | Required for Developer ID notarization |
| Sandbox OFF | Required for `Process()` shell execution and `NSAppleScript` |
