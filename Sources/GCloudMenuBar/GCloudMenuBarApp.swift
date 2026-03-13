import SwiftUI

@main
struct GCloudMenuBarApp: App {

    @State private var manager = GCloudManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(manager)
        } label: {
            MenuBarLabel(status: manager.authStatus)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Dynamic Menu Bar Label

struct MenuBarLabel: View {
    let status: AuthStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(status.color.swiftUIColor)
        }
        .help(helpText)
    }

    private var iconName: String {
        switch status {
        case .authenticated:  return "cloud.fill"
        case .expiringSoon:   return "exclamationmark.icloud.fill"
        case .expired:        return "icloud.slash.fill"
        case .noAccount:      return "icloud.slash.fill"
        case .unknown:        return "cloud"
        }
    }

    private var helpText: String {
        switch status {
        case .authenticated(let d): return "GCloud: Authenticated — \(d.relativeString)"
        case .expiringSoon(let d):  return "GCloud: Token expiring \(d.relativeString)!"
        case .expired:              return "GCloud: Token expired — click to re-login"
        case .noAccount:            return "GCloud: No account — click to login"
        case .unknown:              return "GCloud Auth"
        }
    }
}
