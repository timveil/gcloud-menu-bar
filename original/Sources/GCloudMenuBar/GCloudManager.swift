import Foundation
import AppKit
import Combine

@MainActor
final class GCloudManager: ObservableObject {

    // MARK: - Published State

    @Published var accounts: [GCloudAccount] = []
    @Published var activeAccount: String = ""
    @Published var activeProject: String = ""
    @Published var projects: [GCloudProject] = []
    @Published var authStatus: AuthStatus = .unknown
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isGCloudInstalled: Bool = true

    // MARK: - Private

    private var refreshTimer: AnyCancellable?
    private let tokenRefreshInterval: TimeInterval = 60   // check every 60s
    private var gcloudPath: String = "/usr/bin/gcloud"

    // MARK: - Init

    init() {
        Task { await bootstrap() }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        gcloudPath = await resolveGCloudPath() ?? ""
        isGCloudInstalled = !gcloudPath.isEmpty
        guard isGCloudInstalled else { return }
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
        refreshTimer = Timer.publish(every: tokenRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.refreshAuthStatus() }
            }
    }

    // MARK: - Public API

    func refresh() async {
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

    func login() {
        runInTerminal("\(gcloudPath) auth login")
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refresh()
        }
    }

    func loginApplicationDefault() {
        runInTerminal("\(gcloudPath) auth application-default login")
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refresh()
        }
    }

    func logout(account: String) async {
        _ = await shell([gcloudPath, "auth", "revoke", account, "--quiet"])
        await refresh()
    }

    func switchAccount(to account: String) async {
        _ = await shell([gcloudPath, "config", "set", "account", account])
        activeAccount = account
        await refreshAuthStatus()
    }

    func switchProject(to projectId: String) async {
        _ = await shell([gcloudPath, "config", "set", "project", projectId])
        activeProject = projectId
    }

    // MARK: - Fetch Helpers

    private func fetchAccounts() async -> [GCloudAccount] {
        let (out, code) = await shell([gcloudPath, "auth", "list", "--format=json"])
        guard code == 0, let data = out.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([GCloudAccount].self, from: data)) ?? []
    }

    private func fetchActiveProject() async -> String {
        let (out, _) = await shell([gcloudPath, "config", "get-value", "project"])
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchProjects() async -> [GCloudProject] {
        let (out, code) = await shell([gcloudPath, "projects", "list", "--format=json"])
        guard code == 0, let data = out.data(using: .utf8) else { return [] }
        let raw = (try? JSONDecoder().decode([[String: String]].self, from: data)) ?? []
        return raw.compactMap { dict in
            guard let name   = dict["name"],
                  let pid    = dict["projectId"],
                  let pnum   = dict["projectNumber"],
                  let state  = dict["lifecycleState"] else { return nil }
            return GCloudProject(name: name, projectId: pid, projectNumber: pnum, lifecycleState: state)
        }
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

    // MARK: - Shell Execution

    private func shell(_ args: [String]) async -> (String, Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe    = Pipe()

                // Build a clean environment with common PATH locations
                var env = ProcessInfo.processInfo.environment
                let extraPaths = "/usr/local/bin:/opt/homebrew/bin:\(NSHomeDirectory())/google-cloud-sdk/bin"
                env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
                process.environment = env

                process.executableURL    = URL(fileURLWithPath: args[0])
                process.arguments        = Array(args.dropFirst())
                process.standardOutput   = pipe
                process.standardError    = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ("", 1))
                    return
                }

                process.waitUntilExit()
                let data   = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, process.terminationStatus))
            }
        }
    }

    /// Opens a new Terminal window and runs the given command interactively
    private func runInTerminal(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}
