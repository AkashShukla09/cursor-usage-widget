import Foundation

public enum MenuBarFormat: String, CaseIterable, Identifiable, Sendable {
    case compact
    case detailed

    public var id: String { rawValue }
}

public enum UsageSource: String, CaseIterable, Identifiable, Sendable {
    case cursor
    case claudeCode

    public var id: String { rawValue }

    public var settingsTitle: String {
        switch self {
        case .cursor: "Cursor"
        case .claudeCode: "Claude Code"
        }
    }
}

public enum WidgetSettings {
    public static let refreshIntervalMinutes = "refreshIntervalMinutes"
    public static let warningThreshold = "warningThreshold"
    public static let menuBarFormat = "menuBarFormat"
    public static let usageSource = "usageSource"
    public static let defaultInterval = 15
    public static let defaultThreshold = 80

    public static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            refreshIntervalMinutes: defaultInterval,
            warningThreshold: defaultThreshold,
            menuBarFormat: MenuBarFormat.compact.rawValue,
            usageSource: UsageSource.cursor.rawValue,
        ])
    }

    public static func clampedInterval(_ minutes: Int) -> Int {
        min(60, max(1, minutes))
    }

    public static func clampedThreshold(_ percent: Int) -> Int {
        min(100, max(0, percent))
    }

    public static func interval(in defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: refreshIntervalMinutes) as? NSNumber
        return clampedInterval(stored?.intValue ?? defaultInterval)
    }

    public static func source(in defaults: UserDefaults = .standard) -> UsageSource {
        let raw = defaults.string(forKey: usageSource) ?? ""
        return UsageSource(rawValue: raw) ?? .cursor
    }
}
