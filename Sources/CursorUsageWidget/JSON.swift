import Foundation

enum JSON {
    static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    static func nonNegative(_ value: Any?) -> Double? {
        guard let double = double(value), double >= 0 else { return nil }
        return double
    }

    static func tokenCount(_ value: Any?) -> Int {
        guard let double = nonNegative(value), double > 0 else { return 0 }
        return clampedInt(double)
    }

    static func clampedInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if let exact = Int(exactly: rounded) {
            return exact
        }
        return rounded > 0 ? .max : .min
    }

    static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return sum }
        return (lhs < 0 && rhs < 0) ? .min : .max
    }
}
