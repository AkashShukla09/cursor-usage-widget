import Foundation

public enum UsageLevel: Equatable, Sendable {
    case normal
    case warning
    case critical

    public init(percent: Double, threshold: Int) {
        if percent >= 100 {
            self = .critical
        } else if percent >= Double(WidgetSettings.clampedThreshold(threshold)) {
            self = .warning
        } else {
            self = .normal
        }
    }
}

public enum OtherModelsPool: Equatable, Sendable {
    case included(percent: Double)
    case notIncluded

    var compactText: String {
        switch self {
        case .included(let percent): percent.percentLabel
        case .notIncluded: "n/a"
        }
    }

    var detailedText: String {
        switch self {
        case .included(let percent): percent.percentLabel
        case .notIncluded: "not included"
        }
    }

    var includedPercent: Double? {
        switch self {
        case .included(let percent): percent
        case .notIncluded: nil
        }
    }
}

public struct OnDemandStatus: Equatable, Sendable {
    public let enabled: Bool
    public let usedCents: Double?
    public let limitCents: Double?

    public var panelLabel: String { label(on: "On", off: "Off", joiner: " · ") }
    public var statusLabel: String { label(on: "on", off: "off", joiner: ", ") }

    private func label(on: String, off: String, joiner: String) -> String {
        let state = enabled ? on : off
        guard let usedCents else { return state }
        let used = usedCents.dollarLabel
        guard let limitCents else { return "\(state)\(joiner)\(used)" }
        return "\(state)\(joiner)\(used) of \(limitCents.dollarLabel)"
    }
}

public struct ModelUsageRow: Equatable, Identifiable, Sendable {
    public let modelIntent: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public let totalCents: Double
    public let pool: ModelPool

    public var id: String { modelIntent }

    public var totalTokens: Int {
        [inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens].reduce(0, JSON.saturatingAdd)
    }

    public var compactTokenLabel: String {
        let value = Double(totalTokens)
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return "\(totalTokens)"
    }

    public var tokenDetail: String {
        "In \(inputTokens) · Out \(outputTokens) · Cache read \(cacheReadTokens) · Cache write \(cacheWriteTokens)"
    }

    var statusLine: String {
        "\(modelIntent)\t\(pool.rawValue)\t\(totalCents.dollarLabel)\tin=\(inputTokens)\tout=\(outputTokens)\tcacheRead=\(cacheReadTokens)\tcacheWrite=\(cacheWriteTokens)"
    }

    func adding(_ other: ModelUsageRow) -> ModelUsageRow {
        ModelUsageRow(
            modelIntent: modelIntent,
            inputTokens: JSON.saturatingAdd(inputTokens, other.inputTokens),
            outputTokens: JSON.saturatingAdd(outputTokens, other.outputTokens),
            cacheReadTokens: JSON.saturatingAdd(cacheReadTokens, other.cacheReadTokens),
            cacheWriteTokens: JSON.saturatingAdd(cacheWriteTokens, other.cacheWriteTokens),
            totalCents: totalCents + other.totalCents,
            pool: pool
        )
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let planName: String
    public let cycleStart: Date?
    public let cycleEnd: Date?
    public let isUnlimited: Bool
    public let cursorModelsPercent: Double?
    public let otherModels: OtherModelsPool
    public let onDemand: OnDemandStatus
    public let models: [ModelUsageRow]
    public let modelsUnavailable: Bool
    public let fetchedAt: Date

    public static func placeholderTitle(hasError: Bool) -> String {
        hasError ? "Usage ?" : "Usage …"
    }

    public func menuTitle(format: MenuBarFormat) -> String {
        if isUnlimited { return "Unlimited" }
        guard let cursorModelsPercent else { return Self.placeholderTitle(hasError: false) }
        let cursor = cursorModelsPercent.percentLabel
        switch format {
        case .compact:
            return "C \(cursor)  O \(otherModels.compactText)"
        case .detailed:
            return "Cursor \(cursor) · Other \(otherModels.detailedText)"
        }
    }

    public func level(threshold: Int) -> UsageLevel {
        guard !isUnlimited else { return .normal }
        let levels = includedPercents.map { UsageLevel(percent: $0, threshold: threshold) }
        if levels.contains(.critical) { return .critical }
        if levels.contains(.warning) { return .warning }
        return .normal
    }

    public func rows(in pool: ModelPool) -> [ModelUsageRow] {
        models.filter { $0.pool == pool }
    }

    public func daysRemaining(now: Date = Date()) -> Int? {
        guard let cycleEnd else { return nil }
        let calendar = Self.utcCalendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: cycleEnd)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days)
    }

    public func daysLeftLabel(now: Date = Date()) -> String? {
        guard let days = daysRemaining(now: now) else { return nil }
        switch days {
        case 0: return "Resets today"
        case 1: return "1 day left"
        default: return "\(days) days left"
        }
    }

    public var cycleLabel: String? {
        switch (cycleStart, cycleEnd) {
        case let (start?, end?):
            return "\(shortDate(start)) – \(shortDate(end))"
        case let (nil, end?):
            return "Resets \(shortDate(end))"
        case let (start?, nil):
            return "Started \(shortDate(start))"
        case (nil, nil):
            return nil
        }
    }

    public func statusText(now: Date = Date()) -> String {
        var lines = [
            "Plan: \(planName)",
            "Cycle (UTC): \(isoDay(cycleStart)) to \(isoDay(cycleEnd))",
            "Days left: \(daysRemaining(now: now).map(String.init) ?? "unknown")",
        ]
        if isUnlimited {
            lines.append("Cursor Models: unlimited")
            lines.append("Other Models: unlimited")
        } else {
            lines.append("Cursor Models: \(cursorModelsPercent?.percentLabel ?? "unknown")")
            switch otherModels {
            case .included(let percent):
                lines.append("Other Models: \(percent.percentLabel)")
            case .notIncluded:
                lines.append("Other Models: not included")
            }
        }
        lines.append("On-demand: \(onDemand.statusLabel)")
        if modelsUnavailable {
            lines.append("Models: unavailable")
        } else if models.isEmpty {
            lines.append("Models: none")
        } else {
            lines.append("Models:")
            lines.append(contentsOf: models.map(\.statusLine))
        }
        return lines.joined(separator: "\n")
    }

    private var includedPercents: [Double] {
        [cursorModelsPercent, otherModels.includedPercent].compactMap { $0 }
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private func shortDate(_ date: Date) -> String {
        let parts = Self.utcCalendar.dateComponents([.month, .day], from: date)
        let month = Self.utcCalendar.shortMonthSymbols[(parts.month ?? 1) - 1]
        return "\(month) \(parts.day ?? 1)"
    }

    private func isoDay(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        let parts = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

public extension Double {
    var roundedPercent: Int { JSON.clampedInt(self) }

    var percentLabel: String { "\(roundedPercent)%" }

    var dollarLabel: String {
        let cents = JSON.clampedInt(self)
        let sign = cents < 0 ? "-" : ""
        let absolute: UInt = cents < 0
            ? (cents == Int.min ? UInt(Int.max) + 1 : UInt(-cents))
            : UInt(cents)
        return "\(sign)$\(absolute / 100).\(String(format: "%02d", Int(absolute % 100)))"
    }
}
