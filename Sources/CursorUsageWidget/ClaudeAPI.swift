import Foundation

public enum ClaudeAPIError: Error, LocalizedError, Equatable {
    case notSignedIn
    case sessionExpired
    case keychainDenied
    case keychainUnreadable
    case invalidCredentials
    case unrecognizedUsage
    case httpStatus(Int)
    case network

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Claude Code. Run claude, sign in, then refresh."
        case .sessionExpired:
            return "Claude Code session expired. Run `claude` once, then refresh."
        case .keychainDenied:
            return "Keychain access was denied. Allow the app to read the Claude Code credential, then refresh."
        case .keychainUnreadable:
            return "Claude Code’s keychain credential couldn’t be read."
        case .invalidCredentials:
            return "Claude Code’s saved session couldn’t be read. Sign in again."
        case .unrecognizedUsage:
            return "Claude’s usage response didn’t include the limit windows."
        case .httpStatus(let status):
            return "Claude returned HTTP \(status)."
        case .network:
            return "Couldn’t reach Claude. Check your connection and refresh."
        }
    }
}

public enum ClaudeAPI {
    public static func fetchSnapshot(now: Date = Date()) async throws -> ClaudeUsageSnapshot {
        let credentials = try await ClaudeCredentialStore.load(now: now)
        let data = try await ClaudeClient(accessToken: credentials.accessToken).fetchUsage()
        return try ClaudeUsageSnapshot.parse(data, planName: credentials.planName, now: now)
    }
}

private struct ClaudeClient: Sendable {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"

    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private let accessToken: String

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    func fetchUsage() async throws -> Data {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.urlSession.data(for: request)
        } catch {
            throw ClaudeAPIError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.network
        }
        switch http.statusCode {
        case 200:
            return data
        case 401:
            throw ClaudeAPIError.sessionExpired
        default:
            throw ClaudeAPIError.httpStatus(http.statusCode)
        }
    }
}
