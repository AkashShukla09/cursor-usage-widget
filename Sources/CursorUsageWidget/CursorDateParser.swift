import Foundation

enum CursorDateParser {
    static func parse(_ value: Any?) -> Date? {
        if let number = JSON.double(value) {
            return date(fromUnix: number)
        }
        guard let string = JSON.string(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        if let number = Double(string) {
            return date(fromUnix: number)
        }
        return isoDate(from: string)
    }

    private static func isoDate(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: string)
    }

    private static func date(fromUnix number: Double) -> Date? {
        guard number > 0 else { return nil }
        if number > 1_000_000_000_000 { return Date(timeIntervalSince1970: number / 1000) }
        if number > 1_000_000_000 { return Date(timeIntervalSince1970: number) }
        return nil
    }
}
