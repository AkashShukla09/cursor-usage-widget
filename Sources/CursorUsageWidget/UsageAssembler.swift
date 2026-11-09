import Foundation

public enum UsageAssembler {
    public static func snapshot(
        summaryJSON: Data,
        periodJSON: Data? = nil,
        planJSON: Data? = nil,
        hardLimitJSON: Data? = nil,
        aggregationsJSON: Data? = nil,
        modelBreakdownFailed: Bool = false,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        try snapshot(
            summary: try SummaryDraft.parse(summaryJSON),
            periodJSON: periodJSON,
            planJSON: planJSON,
            hardLimitJSON: hardLimitJSON,
            aggregationsJSON: aggregationsJSON,
            modelBreakdownFailed: modelBreakdownFailed,
            now: now
        )
    }

    static func snapshot(
        summary: SummaryDraft,
        periodJSON: Data?,
        planJSON: Data?,
        hardLimitJSON: Data?,
        aggregationsJSON: Data?,
        modelBreakdownFailed: Bool,
        now: Date
    ) throws -> UsageSnapshot {
        var draft = summary
        if draft.needsPeriodFallback, let periodJSON {
            draft.apply(period: periodJSON)
        }
        draft.apply(plan: planJSON)
        draft.apply(hardLimit: hardLimitJSON)
        let breakdown = parsedModels(aggregationsJSON, failed: modelBreakdownFailed)
        return try draft.makeSnapshot(models: breakdown.rows, modelsUnavailable: breakdown.unavailable, fetchedAt: now)
    }

    private static func parsedModels(_ data: Data?, failed: Bool) -> (rows: [ModelUsageRow], unavailable: Bool) {
        guard !failed, let data else { return ([], failed) }
        guard let rows = ModelBreakdownParser.rows(from: data) else { return ([], true) }
        return (rows, false)
    }
}
