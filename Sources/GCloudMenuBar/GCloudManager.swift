import Foundation
import AppKit
import Observation

@Observable @MainActor
final class GCloudManager {

    // MARK: - Observable State

    var accounts: [GCloudAccount] = []
    var activeAccount: String = ""
    var activeProject: String = ""
    var projects: [GCloudProject] = []
    var authStatus: AuthStatus = .unknown
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var isGCloudInstalled: Bool = true

    // MARK: - Private

    private var refreshTask: Task<Void, Never>?
    private let tokenRefreshInterval: TimeInterval = 60   // check every 60s
    private var gcloudPath: String = "/usr/bin/gcloud"

    // MARK: - Init

    init() {
        Task { [weak self] in await self?.bootstrap() }
    }

    deinit { refreshTask?.cancel() }

    // MARK: - Bootstrap

    private func bootstrap() async {
        gcloudPath = await resolveGCloudPath() ?? ""
        isGCloudInstalled = !gcloudPath.isEmpty
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
                try? await Task.sleep(for: .seconds(tokenRefreshInterval))
                await self?.refreshAuthStatus()
            }
        }
    }

    // MARK: - Public API

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        async let accts = fetchAccounts()
        async let proj  = fetchActiveProject()
        async let projs = fetchProjects()

        let (fetchedAccounts, fetchedProject, fetchedProjects) = await (accts, proj, projs)

        accounts      = fetchedAccounts
        activeProject = fetchedProject
        projects      = fetchedProjects
        activeAccount = fetchedAccounts.first(where: { $0.isActive })?.account ?? ""

        await refreshAuthStatus()
        isLoading = false
    }

    func login(applicationDefault: Bool = false) {
        let command = applicationDefault
            ? "\(gcloudPath) auth application-default login"
            : "\(gcloudPath) auth login"
        runInTerminal(command)
        // No auto-refresh — user clicks Refresh after OAuth flow completes
    }

    func logout(account: String) async {
        _ = await shell([gcloudPath, "auth", "revoke", account, "--quiet"])
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

    private func fetchAccounts() async -> [GCloudAccount] {
        await shellDecode([gcloudPath, "auth", "list", "--format=json"]) ?? []
    }

    private func fetchActiveProject() async -> String {
        let (out, _) = await shell([gcloudPath, "config", "get-value", "project"])
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchProjects() async -> [GCloudProject] {
        await shellDecode([gcloudPath, "projects", "list", "--format=json"]) ?? []
    }

    func refreshAuthStatus() async {
        guard !activeAccount.isEmpty else {
            authStatus = .noAccount
            return
        }
        // Get access token
        let (token, code) = await shell([gcloudPath, "auth", "print-access-token", "--account=\(activeAccount)"])
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
        let (out, code) = await shell(args)
        guard code == 0, let data = out.data(using: .utf8) else {
            if code != 0 { errorMessage = "Command failed (exit \(code)): \(args.joined(separator: " "))" }
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func setGCloudConfig(setting: String, value: String) async {
        _ = await shell([gcloudPath, "config", "set", setting, value])
    }

    // MARK: - Shell Execution

    nonisolated private func shell(_ args: [String]) async -> (String, Int32) {
        await Task.detached(priority: .userInitiated) { @Sendable in
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

            let sema = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in sema.signal() }

            do {
                try process.run()
            } catch {
                return ("", 1)
            }

            if sema.wait(timeout: .now() + 15) == .timedOut {
                process.terminate()
                return ("", 124)
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
        }.value
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
