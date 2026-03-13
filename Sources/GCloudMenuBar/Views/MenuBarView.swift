import SwiftUI

// MARK: - Root Menubar View

struct MenuBarView: View {
    @Environment(GCloudManager.self) private var manager
    @State private var showAccounts: Bool = false
    @State private var showProjects: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            authStatusSection
            if manager.errorMessage != nil {
                Divider()
                errorBanner
            }
            Divider()
            accountSection
            Divider()
            projectSection
            Divider()
            footerSection
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud.fill")
                .font(.title2)
                .foregroundColor(.blue)
            Text("GCloud Auth")
                .font(.headline)
            Spacer()
            if manager.isLoading {
                ProgressView().scaleEffect(0.7)
            }
            Button {
                Task { await manager.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Auth Status

    private var authStatusSection: some View {
        HStack(spacing: 10) {
            Image(systemName: manager.authStatus.sfSymbol)
                .foregroundColor(manager.authStatus.color.swiftUIColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline).fontWeight(.medium)
                Text(manager.authStatus.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            authActionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(manager.authStatus.isExpiringSoon ? Color.yellow.opacity(0.05) : Color.clear)
    }

    private var statusTitle: String {
        switch manager.authStatus {
        case .authenticated, .expiringSoon: return manager.activeAccount.isEmpty ? "Authenticated" : manager.activeAccount
        case .expired:    return "Token Expired — refresh after login"
        case .noAccount:  return "Not Logged In — refresh after login"
        case .unknown:    return "Checking…"
        }
    }

    @ViewBuilder
    private var authActionButton: some View {
        switch manager.authStatus {
        case .expired, .noAccount:
            Button("Login") { manager.login() }
                .buttonStyle(PrimaryButtonStyle(color: .blue))
        case .expiringSoon:
            Button("Refresh") { manager.login() }
                .buttonStyle(PrimaryButtonStyle(color: .orange))
        case .authenticated:
            if !manager.activeAccount.isEmpty {
                Button("Logout") {
                    Task { await manager.logout(account: manager.activeAccount) }
                }
                .buttonStyle(PrimaryButtonStyle(color: .red))
            }
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = manager.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer()
                Button {
                    manager.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
    }

    // MARK: - Accounts

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Accounts",
                count: manager.accounts.count,
                isExpanded: $showAccounts
            )
            if showAccounts {
                if manager.accounts.isEmpty {
                    emptyRow(text: "No accounts found")
                } else {
                    ForEach(manager.accounts) { account in
                        AccountRow(account: account)
                    }
                }
                HStack(spacing: 8) {
                    Button("+ Add Account") { manager.login() }
                        .buttonStyle(LinkButtonStyle())
                    Button("+ App Default") { manager.login(applicationDefault: true) }
                        .buttonStyle(LinkButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Projects

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Projects",
                count: manager.projects.count,
                isExpanded: $showProjects
            )
            if showProjects {
                if manager.projects.isEmpty {
                    emptyRow(text: "No projects found")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(manager.projects) { project in
                                ProjectRow(project: project)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("Active project: ")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(manager.activeProject.isEmpty ? "none" : manager.activeProject)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, count: Int, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyRow(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
    }
}

// MARK: - Shared Row Component

struct CloudRow<Action: View>: View {
    let isActive: Bool
    let activeColor: Color
    let primaryText: String
    let secondaryText: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isActive ? activeColor : Color.gray.opacity(0.35))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(primaryText)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)
                if let secondary = secondaryText {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            action()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isActive ? activeColor.opacity(0.05) : Color.clear)
    }
}

// MARK: - Account Row

struct AccountRow: View {
    let account: GCloudAccount
    @Environment(GCloudManager.self) private var manager

    var body: some View {
        CloudRow(
            isActive: account.isActive,
            activeColor: .green,
            primaryText: account.account,
            secondaryText: account.isActive ? "Active" : nil
        ) {
            if !account.isActive {
                Button("Switch") {
                    Task { await manager.switchAccount(to: account.account) }
                }
                .buttonStyle(PrimaryButtonStyle(color: .blue, compact: true))
            }
            Button {
                Task { await manager.logout(account: account.account) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Revoke credentials for \(account.account)")
        }
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: GCloudProject
    @Environment(GCloudManager.self) private var manager

    var isActive: Bool { project.projectId == manager.activeProject }

    var body: some View {
        CloudRow(
            isActive: isActive,
            activeColor: .blue,
            primaryText: project.name.isEmpty ? project.projectId : project.name,
            secondaryText: project.projectId
        ) {
            if !isActive {
                Button("Use") {
                    Task { await manager.switchProject(to: project.projectId) }
                }
                .buttonStyle(PrimaryButtonStyle(color: .blue, compact: true))
            } else {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }
}

// MARK: - Custom Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption2 : .caption)
            .fontWeight(.medium)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 3 : 5)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1.0))
            .foregroundColor(.white)
            .cornerRadius(5)
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.blue.opacity(configuration.isPressed ? 0.5 : 1.0))
    }
}

// MARK: - Color Extension

extension StatusColor {
    var swiftUIColor: Color {
        switch self {
        case .green:  return .green
        case .yellow: return .yellow
        case .red:    return .red
        case .gray:   return .gray
        }
    }
}
