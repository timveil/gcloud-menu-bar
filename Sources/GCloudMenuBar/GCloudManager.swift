import Foundation
import AppKit
import Observation

@Observable @MainActor
final class GCloudManager {

    // MARK: - Observable State

    var accounts: [GCloudAccount] = []
    var activeAccount: String = ""
    var activeProject: String = ""
    var projectGroups: [ProjectGroup] = []
    var folderNames: [String: String] = [:]   // folder numeric ID → display name
    var authStatus: AuthStatus = .unknown
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var isGCloudInstalled: Bool = true
    var adcInfo: ADCInfo? = nil
    var activeRegion: String = ""
    var activeZone: String = ""
    var componentsNeedingUpdate: [GCloudComponent] = []
    var isHomebrewInstall: Bool = false

    // MARK: - Private

    nonisolated(unsafe) private var refreshTask: Task<Void, Never>?
    private let tokenRefreshInterval: TimeInterval = 60   // check every 60s
    private var gcloudPath: String = "/usr/bin/gcloud"
    var commandLog: [CommandLogEntry] = []
    private let maxLogEntries = 100

    // MARK: - Init

    init() {
        Task { [weak self] in await self?.bootstrap() }
    }

    deinit { refreshTask?.cancel() }

    // MARK: - Bootstrap

    private func bootstrap() async {
        gcloudPath = await resolveGCloudPath() ?? ""
        isGCloudInstalled = !gcloudPath.isEmpty
        isHomebrewInstall = gcloudPath.lowercased().contains("homebrew")
                         || gcloudPath.lowercased().contains("/cellar/")
        guard isGCloudInstalled else {
            errorMessage = "gcloud CLI not found. Install it from cloud.google.com/sdk."
            return
        }
        await refresh()
        startTimer()
    }

    private func resolveGCloudPath() async -> String? {
        let candidates = [
            "/usr/local/bin/gcloud",
            "/opt/homebrew/bin/gcloud",
            "\(NSHomeDirectory())/google-cloud-sdk/bin/gcloud",
            "/usr/bin/gcloud"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        // Fallback: try `which gcloud`
        let (out, _) = await shell(["/bin/zsh", "-l", "-c", "which gcloud"])
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    // MARK: - Timer

    private func startTimer() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.tokenRefreshInterval))
                await self.refreshAuthStatus()
            }
        }
    }

    // MARK: - Public API

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // Phase 1: safe to run regardless of auth state
        async let accts     = fetchAccounts()
        async let proj      = fetchActiveProject()
        async let cfg       = fetchConfig()
        async let adcStatus = fetchADCStatus()
        async let comps     = fetchComponentUpdates()
        async let orgs      = fetchOrganizations()

        let (fetchedAccounts, fetchedProject, fetchedConfig, fetchedADC, fetchedComps, fetchedOrgs) =
            await (accts, proj, cfg, adcStatus, comps, orgs)

        accounts                = fetchedAccounts
        activeProject           = fetchedProject
        activeAccount           = fetchedAccounts.first(where: { $0.isActive })?.account ?? ""
        activeRegion            = fetchedConfig?.compute?.region ?? ""
        activeZone              = fetchedConfig?.compute?.zone ?? ""
        adcInfo                 = fetchedADC
        componentsNeedingUpdate = fetchedComps

        // Phase 2: project list only when authenticated
        let rawProjects = fetchedAccounts.isEmpty ? [] : await fetchProjects()

        // Phase 3: resolve any folder parents to build the org-grouped display
        let orgNameMap = Dictionary(uniqueKeysWithValues: fetchedOrgs.map { ($0.numericId, $0.displayName) })
        let uniqueFolderIds = Set(rawProjects.compactMap { p -> String? in
            guard let parent = p.parent, parent.type == "folder" else { return nil }
            return parent.id
        })
        var resolvedFolderNames: [String: String] = [:]
        var resolvedFolderOrgs: [String: String] = [:]   // folder ID → parent org ID
        for folderId in uniqueFolderIds {
            if let info = await fetchFolderInfo(id: folderId) {
                resolvedFolderNames[folderId] = info.displayName
                if info.parentIsOrg { resolvedFolderOrgs[folderId] = info.parentNumericId }
            }
        }
        folderNames   = resolvedFolderNames
        projectGroups = buildProjectGroups(
            projects: rawProjects,
            orgNameMap: orgNameMap,
            folderOrgIds: resolvedFolderOrgs,
            folderNames: resolvedFolderNames
        )

        await refreshAuthStatus()
        isLoading = false
    }

    func triggerComponentUpdate() {
        if isHomebrewInstall {
            runInTerminal("brew upgrade google-cloud-sdk")
        } else {
            runInTerminal("\(gcloudPath) components update")
        }
    }

    func login(applicationDefault: Bool = false) {
        let command = applicationDefault
            ? "\(gcloudPath) auth application-default login"
            : "\(gcloudPath) auth login"
        runInTerminal(command)
        // No auto-refresh — user clicks Refresh after OAuth flow completes
    }

    func logout(account: String) async {
        _ = await loggedShell([gcloudPath, "auth", "revoke", account, "--quiet"])
        await refresh()
    }

    func switchAccount(to account: String) async {
        await setGCloudConfig(setting: "account", value: account)
        activeAccount = account
        await refreshAuthStatus()
    }

    func switchProject(to projectId: String) async {
        await setGCloudConfig(setting: "project", value: projectId)
        activeProject = projectId
    }

    // MARK: - Fetch Helpers

    private func fetchConfig() async -> GCloudConfig? {
        await shellDecode([gcloudPath, "config", "list", "--format=json"])
    }

    private func fetchADCStatus() async -> ADCInfo? {
        // Parse the ADC credentials file — present whenever ADC is configured
        let adcPath = "\(NSHomeDirectory())/.config/gcloud/application_default_credentials.json"
        guard let fileData = FileManager.default.contents(atPath: adcPath),
              let creds = try? JSONDecoder().decode(ADCFileCredentials.self, from: fileData) else {
            return nil
        }

        let credType: ADCInfo.CredentialType
        switch creds.type {
        case "authorized_user":               credType = .userAccount
        case "service_account":               credType = .serviceAccount
        case "external_account":              credType = .externalAccount
        case "impersonated_service_account":  credType = .impersonatedServiceAccount
        default:                              credType = .unknown(creds.type)
        }

        // Service / impersonated accounts carry their email in the file — no network call needed
        switch credType {
        case .serviceAccount, .impersonatedServiceAccount:
            return ADCInfo(credentialType: credType, email: creds.clientEmail, expiresAt: nil)
        default:
            break
        }

        // For user / external accounts get the token and hit tokeninfo for email + expiry
        let (token, code) = await loggedShell([gcloudPath, "auth", "application-default", "print-access-token"])
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code == 0, !cleanToken.isEmpty,
              let url = URL(string: "https://oauth2.googleapis.com/tokeninfo?access_token=\(cleanToken)") else {
            return ADCInfo(credentialType: credType, email: nil, expiresAt: nil)
        }

        if let (data, _) = try? await URLSession.shared.data(from: url),
           let info = try? JSONDecoder().decode(TokenInfo.self, from: data) {
            return ADCInfo(credentialType: credType, email: info.email, expiresAt: info.expiryDate)
        }
        return ADCInfo(credentialType: credType, email: nil, expiresAt: nil)
    }

    private func fetchComponentUpdates() async -> [GCloudComponent] {
        let args = [gcloudPath, "components", "list",
                    "--filter=state.tag=update_available", "--format=json"]
        return await shellDecode(args) ?? []
    }

    func formattedConsoleLog() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return commandLog.map { e in
            "=== \(fmt.string(from: e.timestamp)) ===\n$ \(e.command)\nexit \(e.exitCode)\n\n\(e.output)"
        }.joined(separator: "\n\n")
    }

    private func fetchAccounts() async -> [GCloudAccount] {
        await shellDecode([gcloudPath, "auth", "list", "--format=json"]) ?? []
    }

    private func fetchActiveProject() async -> String {
        let (out, _) = await loggedShell([gcloudPath, "config", "get-value", "project"])
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchProjects() async -> [GCloudProject] {
        await shellDecode([gcloudPath, "projects", "list", "--format=json"]) ?? []
    }

    // gcloud organizations list exits 0 with [] when the account has no org; not an error
    private func fetchOrganizations() async -> [GCloudOrganization] {
        let (out, code) = await loggedShell([gcloudPath, "organizations", "list", "--format=json"])
        guard code == 0, let data = out.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([GCloudOrganization].self, from: data)) ?? []
    }

    // Non-zero exit (permission denied) is expected and not an error for the app
    private func fetchFolderInfo(id: String) async -> GCloudFolderInfo? {
        let (out, code) = await loggedShell([
            gcloudPath, "resource-manager", "folders", "describe", id, "--format=json"
        ])
        guard code == 0, let data = out.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GCloudFolderInfo.self, from: data)
    }

    private func buildProjectGroups(
        projects: [GCloudProject],
        orgNameMap: [String: String],
        folderOrgIds: [String: String],
        folderNames: [String: String]
    ) -> [ProjectGroup] {
        var grouped: [String: (orgName: String, projects: [GCloudProject])] = [:]

        for project in projects {
            let orgId: String
            let orgName: String
            if let parent = project.parent {
                switch parent.type {
                case "organization":
                    orgId  = parent.id
                    orgName = orgNameMap[parent.id] ?? "Organization \(parent.id)"
                case "folder":
                    // Walk one level up: folder → org
                    let parentOrgId = folderOrgIds[parent.id] ?? ""
                    orgId   = parentOrgId.isEmpty ? "folder-\(parent.id)" : parentOrgId
                    orgName = parentOrgId.isEmpty
                        ? (folderNames[parent.id] ?? "Folder \(parent.id)")
                        : (orgNameMap[parentOrgId] ?? "Organization \(parentOrgId)")
                default:
                    orgId   = "none"
                    orgName = "No Organization"
                }
            } else {
                orgId   = "none"
                orgName = "No Organization"
            }

            if grouped[orgId] == nil { grouped[orgId] = (orgName: orgName, projects: []) }
            grouped[orgId]!.projects.append(project)
        }

        return grouped
            .map { id, value in
                ProjectGroup(
                    id: id,
                    orgName: value.orgName,
                    projects: value.projects.sorted { $0.name.lowercased() < $1.name.lowercased() }
                )
            }
            .sorted { a, b in
                if a.id == "none" { return false }
                if b.id == "none" { return true }
                return a.orgName.lowercased() < b.orgName.lowercased()
            }
    }

    func refreshAuthStatus() async {
        guard !activeAccount.isEmpty else {
            authStatus = .noAccount
            return
        }
        // Get access token
        let (token, code) = await loggedShell([gcloudPath, "auth", "print-access-token", "--account=\(activeAccount)"])
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard code == 0, !cleanToken.isEmpty else {
            authStatus = .expired
            return
        }

        // Hit Google's tokeninfo endpoint to get expiry
        guard let url = URL(string: "https://oauth2.googleapis.com/tokeninfo?access_token=\(cleanToken)") else {
            authStatus = .authenticated(expiresAt: Date().addingTimeInterval(3600))
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let info = try JSONDecoder().decode(TokenInfo.self, from: data)
            if let expiry = info.expiryDate {
                let remaining = expiry.timeIntervalSinceNow
                if remaining < 0 {
                    authStatus = .expired
                } else if remaining < 600 {   // < 10 min
                    authStatus = .expiringSoon(expiresAt: expiry)
                } else {
                    authStatus = .authenticated(expiresAt: expiry)
                }
            } else {
                authStatus = .expired
            }
        } catch {
            // tokeninfo failed — token may be invalid
            authStatus = .expired
        }
    }

    // MARK: - Shell Helpers

    private func shellDecode<T: Decodable>(_ args: [String]) async -> T? {
        let (out, code) = await loggedShell(args)
        guard code == 0, let data = out.data(using: .utf8) else {
            if code != 0 { errorMessage = "Command failed (exit \(code)): \(args.joined(separator: " "))" }
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func setGCloudConfig(setting: String, value: String) async {
        _ = await loggedShell([gcloudPath, "config", "set", setting, value])
    }

    // Logs the result of a shell call to commandLog, capped at maxLogEntries.
    private func loggedShell(_ args: [String]) async -> (String, Int32) {
        let result = await shell(args)
        let entry = CommandLogEntry(
            timestamp: Date(),
            command: args.joined(separator: " "),
            output: result.0.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: result.1
        )
        if commandLog.count >= maxLogEntries { commandLog.removeFirst() }
        commandLog.append(entry)
        return result
    }

    // MARK: - Shell Execution

    nonisolated private func shell(_ args: [String]) async -> (String, Int32) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe    = Pipe()

            // Build a clean environment with common PATH locations
            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/usr/local/bin:/opt/homebrew/bin:\(NSHomeDirectory())/google-cloud-sdk/bin"
            env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            process.environment = env

            process.executableURL  = URL(fileURLWithPath: args[0])
            process.arguments      = Array(args.dropFirst())
            process.standardOutput = pipe
            process.standardError  = pipe

            // Termination handler resumes the continuation exactly once,
            // whether the process exits naturally or is killed by the timeout below.
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ("", 1))
                return
            }

            // 15-second timeout: terminate the process; the termination handler
            // fires and resumes the continuation with whatever exit code results.
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                if process.isRunning { process.terminate() }
            }
        }
    }

    // MARK: - Private Types

    // Used only by fetchADCStatus() to parse ~/.config/gcloud/application_default_credentials.json
    private struct ADCFileCredentials: Codable {
        let type: String
        let clientEmail: String?
        enum CodingKeys: String, CodingKey {
            case type
            case clientEmail = "client_email"
        }
    }

    /// Opens a new Terminal window and runs the given command interactively.
    /// The command string is escaped to prevent AppleScript injection.
    private func runInTerminal(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        if NSAppleScript(source: script)?.executeAndReturnError(&error) == nil {
            errorMessage = "AppleScript error: \(error?["NSAppleScriptErrorMessage"] as? String ?? "unknown")"
        }
    }
}
