import Foundation

public struct CursorSession: Equatable, Sendable {
    public let userId: String
    public let accessToken: String

    public var cookieValue: String {
        "\(userId)%3A%3A\(accessToken)"
    }

    public init(storedValue: String) throws {
        let decoded = storedValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .removingPercentEncoding ?? storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if decoded.contains("::") {
            let parts = decoded.components(separatedBy: "::")
            let userId = parts[0]
            let accessToken = parts.dropFirst().joined(separator: "::")
            guard !userId.isEmpty, accessToken.split(separator: ".").count >= 2 else {
                throw TokenProviderError.invalidToken
            }
            try self.init(userId: userId, accessToken: accessToken)
            return
        }
        try self.init(userId: try Self.userID(fromJWT: decoded), accessToken: decoded)
    }

    private init(userId: String, accessToken: String) throws {
        if userId.contains(where: \.isHeaderUnsafe) || accessToken.contains(where: \.isHeaderUnsafe) {
            throw TokenProviderError.invalidToken
        }
        self.userId = userId
        self.accessToken = accessToken
    }

    public static func userID(fromJWT jwt: String) throws -> String {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { throw TokenProviderError.invalidToken }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - (payload.count % 4)) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String,
              !subject.isEmpty
        else {
            throw TokenProviderError.invalidToken
        }
        guard let separator = subject.lastIndex(of: "|") else { return subject }
        let userId = String(subject[subject.index(after: separator)...])
        guard !userId.isEmpty else { throw TokenProviderError.invalidToken }
        return userId
    }
}

public enum TokenProviderError: Error, LocalizedError, Equatable {
    case databaseNotFound
    case tokenNotFound
    case invalidToken
    case databaseUnreadable

    public var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Cursor isn’t installed or hasn’t been opened yet."
        case .tokenNotFound:
            return "You’re not signed in to Cursor."
        case .invalidToken:
            return "Cursor’s saved session couldn’t be read. Sign in to Cursor again."
        case .databaseUnreadable:
            return "Cursor’s session database couldn’t be read."
        }
    }
}

public enum TokenProvider {
    public static let defaultDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")

    public static func loadSession(databaseURL: URL = defaultDatabaseURL) throws -> CursorSession {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw TokenProviderError.databaseNotFound
        }
        removeStaleCopies()
        let raw: String
        if let readonly = try? SQLiteTokenReader.read(databaseURL: databaseURL, readonly: true) {
            raw = readonly
        } else {
            let copy = try DatabaseCopy(original: databaseURL)
            defer { copy.remove() }
            raw = try copy.readToken()
        }
        guard !raw.isEmpty else { throw TokenProviderError.tokenNotFound }
        return try CursorSession(storedValue: raw)
    }

    private static func removeStaleCopies() {
        let temp = FileManager.default.temporaryDirectory
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: temp,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-15 * 60)
        for directory in directories where directory.lastPathComponent.hasPrefix("cursor-usage-") {
            let modified = (try? directory.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast
            guard modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

private extension Character {
    var isHeaderUnsafe: Bool { self == "\r" || self == "\n" }
}

private enum SQLiteTokenReader {
    static let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"

    static func read(databaseURL: URL, readonly: Bool) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = readonly
            ? ["-readonly", databaseURL.path, query]
            : [databaseURL.path, query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw TokenProviderError.databaseUnreadable
        }
        let killer = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: killer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        guard process.terminationStatus == 0 else { throw TokenProviderError.databaseUnreadable }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct DatabaseCopy {
    let directory: URL
    let database: URL

    init(original: URL) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-usage-\(UUID().uuidString)", isDirectory: true)
        database = directory.appendingPathComponent(original.lastPathComponent)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try FileManager.default.copyItem(at: original, to: database)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.path)
        } catch {
            remove()
            throw TokenProviderError.databaseUnreadable
        }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: original.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
            let destination = directory.appendingPathComponent(original.lastPathComponent + suffix)
            try? FileManager.default.copyItem(at: sidecar, to: destination)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func readToken() throws -> String {
        try SQLiteTokenReader.read(databaseURL: database, readonly: false)
    }
}
