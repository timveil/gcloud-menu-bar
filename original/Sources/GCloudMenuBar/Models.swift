import Foundation

// MARK: - Account

struct GCloudAccount: Identifiable, Codable, Equatable {
    var id: String { account }
    let account: String
    let status: String   // "ACTIVE" | "CREDENTIALED"
    var isActive: Bool { status == "ACTIVE" }
}

// MARK: - Project

struct GCloudProject: Identifiable, Codable, Equatable {
    var id: String { projectId }
    let name: String
    let projectId: String
    let projectNumber: String
    let lifecycleState: String

    enum CodingKeys: String, CodingKey {
        case name
        case projectId
        case projectNumber
        case lifecycleState
    }
}

// MARK: - Auth Status

enum AuthStatus: Equatable {
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
}

enum StatusColor {
    case green, yellow, red, gray
}

// MARK: - Token Info (Google tokeninfo API response)

struct TokenInfo: Codable {
    let exp: String?          // Unix timestamp string
    let email: String?
    let scope: String?

    var expiryDate: Date? {
        guard let exp = exp, let ts = TimeInterval(exp) else { return nil }
        return Date(timeIntervalSince1970: ts)
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
