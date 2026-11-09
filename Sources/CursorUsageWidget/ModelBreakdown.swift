import Foundation

enum ModelBreakdownParser {
    static func rows(from data: Data) -> [ModelUsageRow]? {
        guard let root = JSON.object(from: data) else { return nil }
        guard let rawRows = root["aggregations"] else {
            let failed = root["error"] != nil || root["code"] != nil || root["message"] != nil
            return failed ? nil : []
        }
        guard let rows = JSON.array(rawRows) else { return nil }

        var combined: [String: ModelUsageRow] = [:]
        for row in rows {
            guard let parsed = makeRow(row) else { continue }
            combined[parsed.modelIntent] = combined[parsed.modelIntent]?.adding(parsed) ?? parsed
        }
        return combined.values.sorted { lhs, rhs in
            if lhs.totalCents == rhs.totalCents { return lhs.modelIntent < rhs.modelIntent }
            return lhs.totalCents > rhs.totalCents
        }
    }

    private static func makeRow(_ value: Any) -> ModelUsageRow? {
        guard let object = JSON.dictionary(value) else { return nil }
        let intent = (JSON.string(object["modelIntent"]) ?? JSON.string(object["model"]) ?? JSON.string(object["modelName"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !intent.isEmpty else { return nil }
        return ModelUsageRow(
            modelIntent: intent,
            inputTokens: JSON.tokenCount(object["inputTokens"]),
            outputTokens: JSON.tokenCount(object["outputTokens"]),
            cacheReadTokens: JSON.tokenCount(object["cacheReadTokens"]),
            cacheWriteTokens: JSON.tokenCount(object["cacheWriteTokens"]),
            totalCents: JSON.double(object["totalCents"]) ?? JSON.double(object["totalCostCents"]) ?? JSON.double(object["chargedCents"]) ?? 0,
            pool: ModelPool.classify(intent)
        )
    }
}
