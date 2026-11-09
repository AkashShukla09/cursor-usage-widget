import Foundation

public struct ClaudeLimitWindow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let percent: Double
    public let resetsAt: Date?

    /// Short label for the menu bar: S and W for session and week, the model name for per-model weeks.
    public func menuName(format: MenuBarFormat) -> String {
        switch id {
        case "five_hour":
            return format == .compact ? "S" : "Session"
        case "seven_day":
            return format == .compact ? "W" : "Week"
        default:
            let prefix = "Week ("
            if title.hasPrefix(prefix), title.hasSuffix(")") {
                return String(title.dropFirst(prefix.count).dropLast())
            }
            return title
        }
    }

    public func resetLabel(now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 90 { return "Resets soon" }
        if remaining < 24 * 60 * 60 {
            let totalMinutes = Int((remaining / 60).rounded(.down))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if hours > 0, minutes > 0 { return "Resets in \(hours)h \(minutes)m" }
            if hours > 0 { return "Resets in \(hours)h" }
            return "Resets in \(max(minutes, 1))m"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE H:mm"
        return "Resets \(formatter.string(from: resetsAt))"
    }
}

public enum ClaudeExtraUsage: Equatable, Sendable {
    case off
    case unavailable
    case on(usedCents: Double?, limitCents: Double?, currency: String?)

    public var panelLabel: String { label(on: "On", off: "Off", unavailable: "Unavailable", joiner: " · ") }
    public var statusLabel: String { label(on: "on", off: "off", unavailable: "unavailable", joiner: ", ") }

    private func label(on: String, off: String, unavailable: String, joiner: String) -> String {
        switch self {
        case .off:
            return off
        case .unavailable:
            return unavailable
        case .on(let usedCents, let limitCents, let currency):
            guard let usedCents else { return on }
            let used = Self.amount(usedCents, currency: currency)
            guard let limitCents else { return "\(on)\(joiner)\(used)" }
            return "\(on)\(joiner)\(used) of \(Self.amount(limitCents, currency: currency))"
        }
    }

    private static func amount(_ cents: Double, currency: String?) -> String {
        let code = currency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        if code.isEmpty || code == "USD" { return cents.dollarLabel }
        let major = cents / 100
        return "\(code) \(String(format: "%.2f", major))"
    }
}

public struct ClaudeUsageSnapshot: Equatable, Sendable {
    public let planName: String
    public let windows: [ClaudeLimitWindow]
    public let extraUsage: ClaudeExtraUsage
    public let fetchedAt: Date

    public static func parse(_ data: Data, planName: String = "Claude", now: Date = Date()) throws -> ClaudeUsageSnapshot {
        guard let root = JSON.object(from: data) else {
            throw ClaudeAPIError.unrecognizedUsage
        }
        let limits = JSON.array(root["limits"])?.compactMap(JSON.dictionary) ?? []
        var windows: [ClaudeLimitWindow] = []
        append(
            windows: &windows,
            explicit: window(id: "five_hour", title: "Session", value: root["five_hour"]),
            fallback: limitWindow(id: "five_hour", title: "Session", kind: "session", limits: limits)
        )
        append(
            windows: &windows,
            explicit: window(id: "seven_day", title: "Week", value: root["seven_day"]),
            fallback: limitWindow(id: "seven_day", title: "Week", kind: "weekly_all", limits: limits)
        )
        if let opus = window(id: "seven_day_opus", title: "Week (Opus)", value: root["seven_day_opus"]) {
            windows.append(opus)
        }
        if let sonnet = window(id: "seven_day_sonnet", title: "Week (Sonnet)", value: root["seven_day_sonnet"]) {
            windows.append(sonnet)
        }
        for item in limits where JSON.string(item["kind"]) == "weekly_scoped" {
            guard let name = scopeName(item), let percent = JSON.nonNegative(item["percent"]) else { continue }
            let title = "Week (\(name))"
            if windows.contains(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) { continue }
            windows.append(ClaudeLimitWindow(
                id: "weekly_scoped:\(name)",
                title: title,
                percent: percent,
                resetsAt: CursorDateParser.parse(item["resets_at"])
            ))
        }
        guard !windows.isEmpty else { throw ClaudeAPIError.unrecognizedUsage }
        return ClaudeUsageSnapshot(
            planName: planName,
            windows: windows,
            extraUsage: extraUsage(from: root["extra_usage"]),
            fetchedAt: now
        )
    }

    public func menuTitle(format: MenuBarFormat) -> String {
        let parts = windows.map { "\($0.menuName(format: format)) \($0.percent.percentLabel)" }
        switch format {
        case .compact:
            return parts.joined(separator: "  ")
        case .detailed:
            return parts.joined(separator: " · ")
        }
    }

    public func level(threshold: Int) -> UsageLevel {
        let levels = windows.map { UsageLevel(percent: $0.percent, threshold: threshold) }
        if levels.contains(.critical) { return .critical }
        if levels.contains(.warning) { return .warning }
        return .normal
    }

    public func statusText() -> String {
        var lines = ["Plan: \(planName)"]
        for window in windows {
            var line = "\(window.title): \(window.percent.percentLabel)"
            if let resetsAt = window.resetsAt {
                line += " · resets \(Self.isoString(resetsAt))"
            }
            lines.append(line)
        }
        lines.append("Extra usage: \(extraUsage.statusLabel)")
        return lines.joined(separator: "\n")
    }

    private static func append(windows: inout [ClaudeLimitWindow], explicit: ClaudeLimitWindow?, fallback: ClaudeLimitWindow?) {
        if let explicit {
            windows.append(explicit)
        } else if let fallback {
            windows.append(fallback)
        }
    }

    private static func window(id: String, title: String, value: Any?) -> ClaudeLimitWindow? {
        guard let object = JSON.dictionary(value), let percent = JSON.nonNegative(object["utilization"]) else {
            return nil
        }
        return ClaudeLimitWindow(
            id: id,
            title: title,
            percent: percent,
            resetsAt: CursorDateParser.parse(object["resets_at"])
        )
    }

    private static func limitWindow(id: String, title: String, kind: String, limits: [[String: Any]]) -> ClaudeLimitWindow? {
        guard let item = limits.first(where: { JSON.string($0["kind"]) == kind }),
              let percent = JSON.nonNegative(item["percent"])
        else { return nil }
        return ClaudeLimitWindow(
            id: id,
            title: title,
            percent: percent,
            resetsAt: CursorDateParser.parse(item["resets_at"])
        )
    }

    private static func scopeName(_ item: [String: Any]) -> String? {
        let scope = JSON.dictionary(item["scope"])
        let model = JSON.dictionary(scope?["model"])
        let surface = JSON.dictionary(scope?["surface"])
        let name = JSON.string(model?["display_name"]) ?? JSON.string(surface?["display_name"])
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func extraUsage(from value: Any?) -> ClaudeExtraUsage {
        guard let object = JSON.dictionary(value) else { return .unavailable }
        guard JSON.bool(object["is_enabled"]) == true else { return .off }
        return .on(
            usedCents: JSON.nonNegative(object["used_credits"]),
            limitCents: JSON.nonNegative(object["monthly_limit"]),
            currency: JSON.string(object["currency"])
        )
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
