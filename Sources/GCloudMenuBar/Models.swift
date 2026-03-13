import Foundation

// MARK: - Account

struct GCloudAccount: Identifiable, Codable, Equatable, Sendable {
    var id: String { account }
    let account: String
    let status: String   // "ACTIVE" | "CREDENTIALED"
    var isActive: Bool { status == "ACTIVE" }
}

// MARK: - Project

struct GCloudProject: Identifiable, Codable, Equatable, Sendable {
    struct Parent: Codable, Equatable, Sendable {
        let type: String   // "organization" | "folder"
        let id: String     // numeric ID only
    }
    var id: String { projectId }
    let name: String
    let projectId: String
    let projectNumber: String
    let lifecycleState: String
    let parent: Parent?

    enum CodingKeys: String, CodingKey {
        case name
        case projectId
        case projectNumber
        case lifecycleState
        case parent
    }
}

// MARK: - Resource Hierarchy

struct GCloudOrganization: Identifiable, Codable, Sendable {
    let name: String          // "organizations/12345"
    let displayName: String
    var id: String { name }
    var numericId: String { name.components(separatedBy: "/").last ?? name }
}

// Response shape for `gcloud resource-manager folders describe FOLDER_ID --format=json`
struct GCloudFolderInfo: Codable, Sendable {
    let name: String          // "folders/67890"
    let displayName: String
    let parent: String        // "organizations/12345" or "folders/XXXXX"
    var numericId: String { name.components(separatedBy: "/").last ?? name }
    var parentNumericId: String { parent.components(separatedBy: "/").last ?? parent }
    var parentIsOrg: Bool { parent.hasPrefix("organizations/") }
}

// Grouping of projects by their root organization, used for display
struct ProjectGroup: Identifiable, Sendable {
    let id: String        // org numeric ID, or "none"
    let orgName: String   // org display name, e.g. "acme.com"; "No Organization" when unparented
    let projects: [GCloudProject]
}

// MARK: - Auth Status

enum AuthStatus: Equatable, Sendable {
    case unknown
    case authenticated(expiresAt: Date)
    case expiringSoon(expiresAt: Date)   // < 10 min remaining
    case expired
    case noAccount

    var label: String {
        switch self {
        case .unknown:              return "Checking…"
        case .authenticated(let d): return "Expires \(d.relativeString)"
        case .expiringSoon(let d):  return "Expiring \(d.relativeString)"
        case .expired:              return "Token Expired"
        case .noAccount:            return "Not Logged In"
        }
    }

    var color: StatusColor {
        switch self {
        case .authenticated:  return .green
        case .expiringSoon:   return .yellow
        case .expired:        return .red
        case .noAccount:      return .red
        case .unknown:        return .gray
        }
    }

    var sfSymbol: String {
        switch self {
        case .authenticated:  return "checkmark.shield.fill"
        case .expiringSoon:   return "exclamationmark.shield.fill"
        case .expired:        return "xmark.shield.fill"
        case .noAccount:      return "person.slash.fill"
        case .unknown:        return "shield.fill"
        }
    }

    var isExpiringSoon: Bool {
        if case .expiringSoon = self { return true }
        return false
    }
}

enum StatusColor: Sendable {
    case green, yellow, red, gray
}

// MARK: - Token Info (Google tokeninfo API response)

struct TokenInfo: Codable, Sendable {
    let exp: String?          // Unix timestamp string
    let email: String?
    let scope: String?

    var expiryDate: Date? {
        guard let exp = exp, let ts = TimeInterval(exp) else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}

// MARK: - Command Log

struct CommandLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let command: String    // full args joined by space
    let output: String     // stdout + stderr, trimmed
    let exitCode: Int32
    var succeeded: Bool { exitCode == 0 }
}

// MARK: - Application Default Credentials

struct ADCInfo: Sendable {
    enum CredentialType: Sendable {
        case userAccount
        case serviceAccount
        case externalAccount
        case impersonatedServiceAccount
        case unknown(String)
    }
    let credentialType: CredentialType
    let email: String?
    let expiresAt: Date?

    var typeLabel: String {
        switch credentialType {
        case .userAccount:               return "User Account"
        case .serviceAccount:            return "Service Account"
        case .externalAccount:           return "External Account"
        case .impersonatedServiceAccount: return "Impersonated Service Account"
        case .unknown(let s):            return s
        }
    }

    var detailLabel: String {
        switch credentialType {
        case .userAccount:
            let base = email ?? "User Account"
            if let expiresAt {
                return "\(base) · expires \(expiresAt.relativeString)"
            }
            return base
        case .serviceAccount:
            return email ?? "Service Account"
        case .impersonatedServiceAccount:
            return email.map { "Impersonating \($0)" } ?? "Impersonated Service Account"
        case .externalAccount:
            return email ?? "External Account"
        case .unknown(let s):
            return s
        }
    }
}

// MARK: - Active Config (gcloud config list --format=json)

struct GCloudConfig: Codable, Sendable {
    struct CoreSection: Codable, Sendable {
        let account: String?
        let project: String?
    }
    struct ComputeSection: Codable, Sendable {
        let region: String?
        let zone: String?
    }
    let core: CoreSection?
    let compute: ComputeSection?
}

// MARK: - SDK Components (gcloud components list --format=json)

struct GCloudComponent: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    struct State: Codable, Sendable {
        let name: String  // "Installed", "Update Available", "Not Installed"
        let tag: String   // "installed", "update_available", "not_installed"
    }
    let state: State
    let currentVersionString: String?
    let latestVersionString: String?

    var needsUpdate: Bool {
        state.tag.lowercased().contains("update")
    }
}

// MARK: - Date Helper

extension Date {
    var relativeString: String {
        let diff = timeIntervalSinceNow
        if diff < 0 { return "now" }
        let min = Int(diff / 60)
        let hr  = min / 60
        if hr > 0  { return "in \(hr)h \(min % 60)m" }
        if min > 0 { return "in \(min)m" }
        return "in <1m"
    }
}
