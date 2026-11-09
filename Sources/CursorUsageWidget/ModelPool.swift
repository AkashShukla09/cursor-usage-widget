import Foundation

public enum ModelPool: String, Equatable, Hashable, Sendable {
    case cursor
    case other
    case auto

    public static let displayOrder: [ModelPool] = [.cursor, .other, .auto]

    public var sectionTitle: String {
        switch self {
        case .cursor: "Cursor"
        case .other: "Other"
        case .auto: "Auto"
        }
    }

    /// Grok 4.7, 4.6, 4.5, and Composer 2.5 belong to the Cursor Models pool.
    /// Auto and router rows stay separate because a routed request can draw from either pool.
    public static func classify(_ modelIntent: String) -> ModelPool {
        let normalized = modelIntent.lowercased().map { character in
            character == "_" || character == " " ? "-" : character
        }
        let name = String(normalized)
        if isAuto(name) { return .auto }
        if isCursorModel(name) { return .cursor }
        return .other
    }

    private static func isAuto(_ value: String) -> Bool {
        switch value {
        case "auto", "default", "cursor-auto", "cursor-router", "agent-router":
            return true
        default:
            return value.hasPrefix("auto-")
        }
    }

    private static func isCursorModel(_ value: String) -> Bool {
        let compact = value.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ".", with: "")
        return compact.contains("grok47")
            || compact.contains("grok46")
            || compact.contains("grok45")
            || compact.contains("composer25")
    }
}
