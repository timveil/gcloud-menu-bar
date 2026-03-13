# GCloud MenuBar

A native macOS menubar app for managing Google Cloud (`gcloud`) authentication and project switching — built with SwiftUI.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

---

## Features

- **Auth status at a glance** — menubar icon changes color (green/orange/red) based on token health
- **Token expiry warnings** — know before your token expires, not after
- **One-click account switching** — see all credentialed accounts, switch instantly
- **One-click project switching** — see all your GCP projects, set active with one click
- **Login / Logout** — triggers `gcloud auth login` in Terminal (full OAuth flow)
- **App Default credentials** — supports `gcloud auth application-default login` too
- **Auto-refresh** — checks token status every 60 seconds in the background

---

## Prerequisites

- macOS 13 Ventura or later
- [Xcode 15+](https://developer.apple.com/xcode/)
- `gcloud` CLI installed (any of the standard locations):
  - `/usr/local/bin/gcloud`
  - `/opt/homebrew/bin/gcloud`
  - `~/google-cloud-sdk/bin/gcloud`

---

## Setup in Xcode

1. **Open the project**
   ```
   File → Open → select the GCloudMenuBar folder
   ```
   Xcode will detect `Package.swift` automatically.

2. **Set the scheme target**
   In the toolbar, select the `GCloudMenuBar` scheme.

3. **Set your Team** (for signing)
   - Click the `GCloudMenuBar` package in the Project Navigator
   - Go to **Signing & Capabilities**
   - Select your Apple ID team

4. **Run**
   Press `⌘R` — the app will appear in your menubar (no Dock icon).

---

## Building a Distributable .app

To create a standalone `.app` you can share or put in `/Applications`:

```bash
# In Xcode: Product → Archive → Distribute App → Direct Distribution
```

Or via command line:
```bash
xcodebuild -scheme GCloudMenuBar \
  -configuration Release \
  -archivePath ./build/GCloudMenuBar.xcarchive \
  archive
```

---

## How It Works

The app shells out to the `gcloud` CLI — no Google APIs are called directly for auth operations. This means:

- It works with whatever `gcloud` version you have installed
- Auth flows happen in Terminal (full OAuth browser redirect)
- Token validity is checked via Google's `tokeninfo` REST endpoint

### Key commands used internally

| Action | Command |
|--------|---------|
| List accounts | `gcloud auth list --format=json` |
| Active project | `gcloud config get-value project` |
| List projects | `gcloud projects list --format=json` |
| Switch account | `gcloud config set account <email>` |
| Switch project | `gcloud config set project <id>` |
| Login | `gcloud auth login` |
| App Default login | `gcloud auth application-default login` |
| Revoke account | `gcloud auth revoke <email> --quiet` |
| Print token | `gcloud auth print-access-token` |

---

## Project Structure

```
GCloudMenuBar/
├── Package.swift
└── Sources/GCloudMenuBar/
    ├── GCloudMenuBarApp.swift   # @main entry point + MenuBarExtra
    ├── GCloudManager.swift      # All CLI interactions + published state
    ├── Models.swift             # GCloudAccount, GCloudProject, AuthStatus
    └── Views/
        └── MenuBarView.swift    # Full SwiftUI UI (accounts, projects, status)
```

---

## Roadmap / Future Ideas

- [ ] macOS Notifications when token is about to expire
- [ ] Support for named `gcloud` configurations (`gcloud config configurations`)
- [ ] Launch at login option
- [ ] Keyboard shortcut to open menubar popover
- [ ] Search/filter for large project lists
- [ ] ADC (Application Default Credentials) status shown separately
- [ ] Menubar icon showing active project initials

---

## Troubleshooting

**"gcloud not found"** — Make sure gcloud is installed and in one of the standard paths. Run `which gcloud` in Terminal to confirm.

**Projects list is empty** — You need `roles/resourcemanager.projectViewer` or higher on the projects. Run `gcloud projects list` in Terminal to confirm access.

**Token shows as expired immediately** — Try running `gcloud auth login` manually to refresh credentials.

---

## License

MIT
