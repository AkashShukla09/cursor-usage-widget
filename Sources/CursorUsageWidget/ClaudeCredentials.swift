import Foundation

public struct ClaudeCredentials: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public var planName: String {
        Self.planName(rateLimitTier: rateLimitTier, subscriptionType: subscriptionType)
    }

    public static func parse(_ data: Data, now: Date = Date()) throws -> ClaudeCredentials {
        guard let root = JSON.object(from: data) else {
            throw ClaudeAPIError.invalidCredentials
        }
        let oauth = JSON.dictionary(root["claudeAiOauth"]) ?? root
        let token = JSON.string(oauth["accessToken"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { throw ClaudeAPIError.notSignedIn }
        guard !token.contains(where: \.isNewline) else { throw ClaudeAPIError.invalidCredentials }
        let expiresAt = CursorDateParser.parse(oauth["expiresAt"])
        if let expiresAt, expiresAt <= now {
            throw ClaudeAPIError.sessionExpired
        }
        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: trimmed(JSON.string(oauth["subscriptionType"])),
            rateLimitTier: trimmed(JSON.string(oauth["rateLimitTier"]))
        )
    }

    public static func planName(rateLimitTier: String?, subscriptionType: String?) -> String {
        let tier = rateLimitTier?.lowercased().replacingOccurrences(of: "-", with: "_") ?? ""
        if tier.contains("20x") { return "Max 20x" }
        if tier.contains("5x") { return "Max 5x" }
        if tier.contains("enterprise") { return "Enterprise" }
        if tier.contains("team") { return "Team" }
        if tier.contains("max") { return "Max" }
        if tier.contains("pro") || tier.contains("claude_ai") { return "Pro" }
        if let subscription = displaySubscription(subscriptionType) { return subscription }
        return "Claude"
    }

    private static func displaySubscription(_ raw: String?) -> String? {
        guard let trimmed = trimmed(raw)?.lowercased(), !trimmed.isEmpty else { return nil }
        switch trimmed {
        case "pro": return "Pro"
        case "max": return "Max"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default:
            return trimmed.split(separator: "_").map { part in
                guard let first = part.first else { return "" }
                return first.uppercased() + part.dropFirst()
            }.joined(separator: " ")
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum ClaudeCredentialStore {
    public static let service = "Claude Code-credentials"

    public static func load(now: Date = Date()) async throws -> ClaudeCredentials {
        let raw = try await Task.detached(priority: .userInitiated) {
            try KeychainPassword.read(service: service)
        }.value
        guard let data = raw.data(using: .utf8) else { throw ClaudeAPIError.invalidCredentials }
        return try ClaudeCredentials.parse(data, now: now)
    }
}

private enum KeychainPassword {
    static func read(service: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw ClaudeAPIError.keychainUnreadable
        }
        let killer = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        // The first read can show a keychain prompt, so this waits longer than the sqlite token read.
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: killer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        let stderr = String(data: errorData, encoding: .utf8)?.lowercased() ?? ""
        if process.terminationStatus == 0 {
            let password = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !password.isEmpty else { throw ClaudeAPIError.notSignedIn }
            return password
        }
        if process.terminationStatus == 44 || stderr.contains("could not be found") {
            throw ClaudeAPIError.notSignedIn
        }
        if process.terminationStatus == 128 || stderr.contains("cancel") || stderr.contains("denied") || stderr.contains("interaction") {
            throw ClaudeAPIError.keychainDenied
        }
        throw ClaudeAPIError.keychainUnreadable
    }
}
