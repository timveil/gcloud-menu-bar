import SwiftUI
import UniformTypeIdentifiers

private enum Layout {
    static let menuWidth: CGFloat = 320
    static let scrollMaxHeight: CGFloat = 220
}

// MARK: - Root Menubar View

struct MenuBarView: View {
    @Environment(GCloudManager.self) private var manager
    @State private var showAccounts: Bool = false
    @State private var showProjects: Bool = false
    @State private var showUpdates: Bool = false
    @State private var showConsole: Bool = false
    @State private var projectSearch: String = ""
    @State private var collapsedGroups: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            statusCard
            if manager.errorMessage != nil {
                Divider()
                errorBanner
            }
            Divider()
            accountSection
            Divider()
            projectSection
            if !manager.componentsNeedingUpdate.isEmpty {
                Divider()
                updatesSection
            }
            Divider()
            consoleSection
            Divider()
            footerSection
        }
        .frame(width: Layout.menuWidth)
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

    // MARK: - Status Card

    /// Single always-visible card showing the three key pieces of local auth state.
    private var statusCard: some View {
        VStack(spacing: 0) {
            cliCredentialsRow
            Divider().padding(.leading, 46)
            adcCredentialsRow
            Divider().padding(.leading, 46)
            activeProjectRow
        }
    }

    // Row 1 — gcloud CLI credentials
    private var cliCredentialsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: manager.authStatus.sfSymbol)
                .foregroundColor(manager.authStatus.color.swiftUIColor)
                .font(.title3)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                statusLabel("CLI Credentials")
                Text(cliAuthTitle)
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1).truncationMode(.middle)
                Text(manager.authStatus.label)
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            authActionButton
                .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(manager.authStatus.isExpiringSoon ? Color.yellow.opacity(0.05) : Color.clear)
    }

    // Row 2 — Application Default Credentials
    private var adcCredentialsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: manager.adcInfo != nil ? "key.fill" : "key.slash")
                .foregroundColor(manager.adcInfo != nil ? adcStatusColor : .secondary)
                .font(.title3)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                statusLabel("App Default Credentials (ADC)")
                if let adc = manager.adcInfo {
                    HStack(spacing: 5) {
                        Text(adc.email ?? adc.typeLabel)
                            .font(.subheadline).fontWeight(.medium)
                            .lineLimit(1).truncationMode(.middle)
                        Text(adc.typeLabel)
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(3)
                    }
                    if let expires = adc.expiresAt {
                        Text("Token expires \(expires.relativeString)")
                            .font(.caption2)
                            .foregroundColor(adcExpiryColor(expires))
                    }
                } else {
                    Text("Not configured")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text("Used by Google Cloud SDKs and client libraries")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            if manager.adcInfo == nil {
                Button("Login") { manager.login(applicationDefault: true) }
                    .buttonStyle(PrimaryButtonStyle(color: .blue))
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .help("Used by Google Cloud SDKs and client libraries when running code locally. Separate from gcloud CLI auth.")
    }

    // Row 3 — Active project
    private var activeProjectRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundColor(manager.activeProject.isEmpty ? .secondary : .blue)
                .font(.title3)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                statusLabel("Active Project")
                if manager.activeProject.isEmpty {
                    Text("None selected")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.secondary)
                } else if let details = manager.activeProjectDetails {
                    Text(details.name.isEmpty ? details.projectId : details.name)
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    Text(details.projectId)
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let org = manager.activeProjectOrgName {
                            Label(org, systemImage: "building.2")
                                .font(.caption2).foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        if !manager.activeRegion.isEmpty {
                            Label(manager.activeRegion, systemImage: "globe")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        if !manager.activeZone.isEmpty {
                            Label(manager.activeZone, systemImage: "mappin.circle")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text(manager.activeProject)
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    Text("Loading project details…")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func statusLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.3)
    }

    private var cliAuthTitle: String {
        switch manager.authStatus {
        case .authenticated, .expiringSoon: return manager.activeAccount.isEmpty ? "Authenticated" : manager.activeAccount
        case .expired:   return "Token Expired"
        case .noAccount: return "Not Logged In"
        case .unknown:   return "Checking…"
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

    private var adcStatusColor: Color {
        guard let expires = manager.adcInfo?.expiresAt else { return .green }
        let remaining = expires.timeIntervalSinceNow
        if remaining < 0 { return .red }
        if remaining < 600 { return .orange }
        return .green
    }

    private func adcExpiryColor(_ date: Date) -> Color {
        let remaining = date.timeIntervalSinceNow
        if remaining < 0 { return .red }
        if remaining < 600 { return .orange }
        return .secondary
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = manager.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(error, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy error message")
                    Button {
                        manager.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
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
                Divider().padding(.leading, 14)
                // Login actions — one per auth type, clearly labelled with the command
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Button("Add Account") { manager.login() }
                            .buttonStyle(PrimaryButtonStyle(color: .blue, compact: true))
                        Text("gcloud auth login")
                            .font(.caption2).foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Button("Set App Default") { manager.login(applicationDefault: true) }
                            .buttonStyle(PrimaryButtonStyle(color: .teal, compact: true))
                        Text("gcloud auth application-default login")
                            .font(.caption2).foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 175, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Text("Both open Terminal for a browser-based OAuth flow. Click Refresh when complete.")
                    .font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal, 14).padding(.bottom, 8)
            }
        }
    }

    // MARK: - Projects

    private var totalProjectCount: Int {
        manager.projectGroups.reduce(0) { $0 + $1.projects.count }
    }

    private var filteredProjectGroups: [ProjectGroup] {
        guard !projectSearch.isEmpty else { return manager.projectGroups }
        let query = projectSearch.lowercased()
        return manager.projectGroups.compactMap { group in
            let matches = group.projects.filter {
                $0.name.lowercased().contains(query) || $0.projectId.lowercased().contains(query)
            }
            guard !matches.isEmpty else { return nil }
            return ProjectGroup(id: group.id, orgName: group.orgName, projects: matches)
        }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Projects",
                count: totalProjectCount,
                isExpanded: $showProjects
            )
            if showProjects {
                if !manager.projectGroups.isEmpty {
                    projectSearchField
                }
                if filteredProjectGroups.isEmpty {
                    emptyRow(text: projectSearch.isEmpty ? "No projects found" : "No matching projects")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filteredProjectGroups) { group in
                                projectGroupView(group)
                            }
                        }
                    }
                    .frame(maxHeight: Layout.scrollMaxHeight)
                }
            }
        }
        .onChange(of: showProjects) { _, isShowing in
            if !isShowing {
                collapsedGroups.removeAll()
                projectSearch = ""
            }
        }
    }

    @ViewBuilder
    private func projectGroupView(_ group: ProjectGroup) -> some View {
        let isCollapsed = projectSearch.isEmpty && collapsedGroups.contains(group.id)
        orgHeader(group, count: group.projects.count, isCollapsed: isCollapsed)
        if !isCollapsed {
            ForEach(group.projects) { project in
                ProjectRow(project: project)
            }
        }
    }

    private var projectSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundColor(.secondary)
            TextField("Filter projects…", text: $projectSearch)
                .font(.caption)
                .textFieldStyle(.plain)
            if !projectSearch.isEmpty {
                Button {
                    projectSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func orgHeader(_ group: ProjectGroup, count: Int, isCollapsed: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if collapsedGroups.contains(group.id) {
                    collapsedGroups.remove(group.id)
                } else {
                    collapsedGroups.insert(group.id)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "building.2")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(group.orgName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Console

    /// Visually distinct from action sections — this is a read-only log, not a control.
    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Command History",
                count: manager.commandLog.count,
                isExpanded: $showConsole,
                accessory: AnyView(
                    HStack(spacing: 8) {
                        Button("Export") { exportConsoleLogs() }
                            .buttonStyle(LinkButtonStyle())
                            .opacity(manager.commandLog.isEmpty ? 0 : 1)
                        Button("Clear") { manager.clearCommandLog() }
                            .buttonStyle(LinkButtonStyle())
                            .opacity(manager.commandLog.isEmpty ? 0 : 1)
                    }
                )
            )
            if showConsole {
                if manager.commandLog.isEmpty {
                    emptyRow(text: "No commands run yet")
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(manager.commandLog.reversed()) { entry in
                                ConsoleEntryRow(entry: entry)
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .frame(maxHeight: Layout.scrollMaxHeight)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - SDK Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "SDK Updates",
                count: manager.componentsNeedingUpdate.count,
                isExpanded: $showUpdates,
                accessory: AnyView(
                    Button("Update") { manager.triggerComponentUpdate() }
                        .buttonStyle(LinkButtonStyle())
                        .help(manager.isHomebrewInstall
                            ? "Opens Terminal to run 'brew upgrade google-cloud-sdk'"
                            : "Opens Terminal to run 'gcloud components update'")
                )
            )
            if showUpdates {
                ForEach(manager.componentsNeedingUpdate) { component in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(component.name)
                                .font(.caption).lineLimit(1)
                            if let current = component.currentVersionString,
                               let latest = component.latestVersionString {
                                Text("\(current) → \(latest)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 5)
                }
                Text(manager.isHomebrewInstall
                     ? "Managed by Homebrew — use 'Update' above to upgrade."
                     : "Click 'Update' to open Terminal and update all components.")
                    .font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal, 14).padding(.bottom, 6)
            }
        }
    }

    // MARK: - Helpers

    private func exportConsoleLogs() {
        let panel = NSSavePanel()
        panel.title = "Export Console Log"
        panel.nameFieldStringValue = "gcloud-console-\(ISO8601DateFormatter().string(from: Date())).log"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try manager.formattedConsoleLog().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            manager.errorMessage = "Failed to export log: \(error.localizedDescription)"
        }
    }

    private func sectionHeader(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        accessory: AnyView? = nil
    ) -> some View {
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
                if let accessory {
                    accessory
                        .padding(.trailing, 4)
                }
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

    var secondaryText: String {
        guard let parent = project.parent, parent.type == "folder" else {
            return project.projectId
        }
        let folderLabel = manager.folderNames[parent.id] ?? "Folder \(parent.id)"
        return "\(project.projectId) · \(folderLabel)"
    }

    var body: some View {
        CloudRow(
            isActive: isActive,
            activeColor: .blue,
            primaryText: project.name.isEmpty ? project.projectId : project.name,
            secondaryText: secondaryText
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

// MARK: - Console Entry Row

struct ConsoleEntryRow: View {
    let entry: CommandLogEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.succeeded ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Text(entry.command)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    let copyText = "$ \(entry.command)\n\(entry.output)\nexit \(entry.exitCode)"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy command and output")
            }

            if !entry.output.isEmpty {
                let truncates = entry.output.contains("\n")
                              ? entry.output.components(separatedBy: "\n").count > 3
                              : entry.output.count > 150
                Text(entry.output)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .textSelection(.enabled)
                if truncates {
                    Button { expanded.toggle() } label: {
                        Text(expanded ? "Show less" : "Show more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("exit \(entry.exitCode)")
                .font(.caption2)
                .foregroundColor(entry.succeeded ? .green : .red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(entry.succeeded ? Color.clear : Color.red.opacity(0.03))
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
