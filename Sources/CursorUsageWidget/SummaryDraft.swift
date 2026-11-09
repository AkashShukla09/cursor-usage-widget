import Foundation

struct SummaryDraft {
    var planName: String
    var cycleStart: Date?
    var cycleEnd: Date?
    var isUnlimited: Bool
    var cursorPercent: Double?
    var otherModels: OtherPoolSignal
    var onDemandEnabled: Bool?
    var onDemandUsedCents: Double?
    var onDemandLimitCents: Double?

    var needsPeriodFallback: Bool {
        if isUnlimited { return false }
        return cursorPercent == nil || otherModels == .unknown
    }

    static func parse(_ data: Data) throws -> SummaryDraft {
        guard let root = JSON.object(from: data) else {
            throw CursorAPIError.unrecognizedUsage
        }
        var draft = SummaryDraft(
            planName: displayPlanName(JSON.string(root["membershipType"])),
            cycleStart: CursorDateParser.parse(root["billingCycleStart"]),
            cycleEnd: CursorDateParser.parse(root["billingCycleEnd"]),
            isUnlimited: JSON.bool(root["isUnlimited"]) ?? false,
            cursorPercent: nil,
            otherModels: .unknown,
            onDemandEnabled: nil,
            onDemandUsedCents: nil,
            onDemandLimitCents: nil
        )
        draft.applyOnDemand(from: root)
        draft.absorbPools(
            plan: JSON.dictionary(JSON.dictionary(root["individualUsage"])?["plan"]),
            autoMessage: JSON.string(root["autoModelSelectedDisplayMessage"]),
            namedMessage: JSON.string(root["namedModelSelectedDisplayMessage"])
        )
        return draft
    }

    func aggregationWindow(periodJSON: Data?, now: Date) -> (start: Int64, end: Int64) {
        let period = periodJSON.flatMap { JSON.object(from: $0) }
        let start = cycleStart
            ?? CursorDateParser.parse(period?["billingCycleStart"])
            ?? now.addingTimeInterval(-30 * 24 * 60 * 60)
        let end = cycleEnd
            ?? CursorDateParser.parse(period?["billingCycleEnd"])
            ?? now
        return (milliseconds(start), milliseconds(end))
    }

    mutating func apply(period data: Data) {
        guard let root = JSON.object(from: data) else { return }
        if cycleStart == nil {
            cycleStart = CursorDateParser.parse(root["billingCycleStart"])
        }
        if cycleEnd == nil {
            cycleEnd = CursorDateParser.parse(root["billingCycleEnd"])
        }
        let plan = JSON.dictionary(root["planUsage"]) ?? JSON.dictionary(JSON.dictionary(root["individualUsage"])?["plan"])
        absorbPools(
            plan: plan,
            autoMessage: JSON.string(root["autoModelSelectedDisplayMessage"]),
            namedMessage: JSON.string(root["namedModelSelectedDisplayMessage"])
        )
    }

    mutating func apply(plan data: Data?) {
        guard let data, let root = JSON.object(from: data) else { return }
        let info = JSON.dictionary(root["planInfo"]) ?? root
        if let name = JSON.string(info["planName"])?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            planName = name
        }
        if cycleEnd == nil {
            cycleEnd = CursorDateParser.parse(info["billingCycleEnd"])
        }
        if cycleStart == nil {
            cycleStart = CursorDateParser.parse(info["billingCycleStart"])
        }
    }

    mutating func apply(hardLimit data: Data?) {
        guard let data, let root = JSON.object(from: data) else { return }
        if JSON.bool(root["noUsageBasedAllowed"]) == true {
            onDemandEnabled = false
        }
        guard onDemandLimitCents == nil else { return }
        if let cents = JSON.nonNegative(root["hardLimitCents"]) ?? JSON.nonNegative(root["hardLimitInCents"]) {
            onDemandLimitCents = cents
            return
        }
        if let dollars = JSON.nonNegative(root["hardLimit"]) {
            onDemandLimitCents = (dollars * 100).rounded()
        }
    }

    func makeSnapshot(models: [ModelUsageRow], modelsUnavailable: Bool, fetchedAt: Date) throws -> UsageSnapshot {
        var resolved = self
        if resolved.otherModels == .unknown {
            resolved.otherModels = .notIncluded
        }
        guard resolved.isUnlimited || resolved.cursorPercent != nil else {
            throw CursorAPIError.unrecognizedUsage
        }
        return UsageSnapshot(
            planName: resolved.planName,
            cycleStart: resolved.cycleStart,
            cycleEnd: resolved.cycleEnd,
            isUnlimited: resolved.isUnlimited,
            cursorModelsPercent: resolved.isUnlimited ? nil : resolved.cursorPercent,
            otherModels: resolved.otherModels.pool(unlimited: resolved.isUnlimited),
            onDemand: OnDemandStatus(
                enabled: resolved.onDemandEnabled ?? false,
                usedCents: resolved.onDemandUsedCents,
                limitCents: resolved.onDemandLimitCents
            ),
            models: models,
            modelsUnavailable: modelsUnavailable,
            fetchedAt: fetchedAt
        )
    }

    private mutating func applyOnDemand(from root: [String: Any]) {
        let individual = JSON.dictionary(root["individualUsage"])
        let team = JSON.dictionary(root["teamUsage"])
        let source = JSON.dictionary(individual?["onDemand"]) ?? JSON.dictionary(team?["onDemand"])
        guard let source else { return }
        onDemandEnabled = JSON.bool(source["enabled"]) ?? false
        onDemandUsedCents = JSON.nonNegative(source["used"])
        onDemandLimitCents = JSON.nonNegative(source["limit"])
    }

    private mutating func absorbPools(plan: [String: Any]?, autoMessage: String?, namedMessage: String?) {
        if cursorPercent == nil {
            cursorPercent = JSON.nonNegative(plan?["autoPercentUsed"])
        }
        if otherModels == .unknown, let plan {
            if let percent = JSON.nonNegative(plan["apiPercentUsed"]) {
                otherModels = .included(percent)
            } else if plan.keys.contains("apiPercentUsed") || cursorPercent != nil || plan.keys.contains("autoPercentUsed") {
                otherModels = .notIncluded
            }
        }
        if cursorPercent == nil, let percent = autoMessage.flatMap(Self.percent(in:)) {
            cursorPercent = percent
        }
        if otherModels == .unknown, let namedMessage {
            otherModels = Self.percent(in: namedMessage).map(OtherPoolSignal.included) ?? .notIncluded
        }
    }

    private static func percent(in message: String) -> Double? {
        guard let percentIndex = message.firstIndex(of: "%") else { return nil }
        let before = message[..<percentIndex]
        let start = before.lastIndex(where: { !$0.isNumber && $0 != "." }).map { before.index(after: $0) } ?? before.startIndex
        guard let value = Double(before[start...]), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func displayPlanName(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Cursor" }
        return trimmed.split { $0 == "_" || $0 == "-" || $0 == " " }.map { part in
            guard let first = part.first else { return "" }
            return first.uppercased() + part.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

enum OtherPoolSignal: Equatable {
    case included(Double)
    case notIncluded
    case unknown

    func pool(unlimited: Bool) -> OtherModelsPool {
        if unlimited { return .notIncluded }
        switch self {
        case .included(let percent):
            return .included(percent: percent)
        case .notIncluded, .unknown:
            return .notIncluded
        }
    }
}
