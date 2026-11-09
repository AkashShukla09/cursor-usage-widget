import CursorUsageLib
import XCTest

final class UsageParsingTests: XCTestCase {
    func testBothPoolsAndOnDemand() throws {
        let snapshot = try UsageAssembler.snapshot(
            summaryJSON: Data(bothPoolsJSON.utf8),
            planJSON: Data(#"{"planInfo":{"planName":"Pro Plus"}}"#.utf8),
            now: date("2026-09-20T00:00:00Z")
        )
        XCTAssertEqual(snapshot.planName, "Pro Plus")
        XCTAssertEqual(snapshot.cursorModelsPercent ?? -1, 42.4, accuracy: 0.001)
        guard case .included(let other) = snapshot.otherModels else {
            return XCTFail("expected Other Models to be included")
        }
        XCTAssertEqual(other, 18.2, accuracy: 0.001)
        XCTAssertTrue(snapshot.onDemand.enabled)
        XCTAssertEqual(snapshot.onDemand.usedCents ?? -1, 1785, accuracy: 0.001)
        XCTAssertEqual(snapshot.onDemand.limitCents ?? -1, 5000, accuracy: 0.001)
        XCTAssertEqual(snapshot.menuTitle(format: .compact), "C 42%  O 18%")
        XCTAssertEqual(snapshot.menuTitle(format: .detailed), "Cursor 42% · Other 18%")
        XCTAssertEqual(snapshot.level(threshold: 80), .normal)
    }

    func testNumericPoolsWinOverDisplayMessages() throws {
        let json = """
        {
          "billingCycleEnd": "2026-10-05T00:00:00.000Z",
          "membershipType": "pro",
          "autoModelSelectedDisplayMessage": "You've used 99% of your included total usage",
          "namedModelSelectedDisplayMessage": "You've used 99% of your included API usage",
          "individualUsage": {
            "plan": { "autoPercentUsed": 42.4, "apiPercentUsed": 18.2, "totalPercentUsed": 30 }
          }
        }
        """
        let snapshot = try UsageAssembler.snapshot(summaryJSON: Data(json.utf8))
        XCTAssertEqual(snapshot.cursorModelsPercent ?? -1, 42.4, accuracy: 0.001)
        guard case .included(let other) = snapshot.otherModels else {
            return XCTFail("expected included pool")
        }
        XCTAssertEqual(other, 18.2, accuracy: 0.001)
    }

    func testStartPlanOmitsOtherModelsPool() throws {
        let snapshot = try UsageAssembler.snapshot(summaryJSON: Data(startPlanJSON.utf8))
        XCTAssertEqual(snapshot.planName, "Start")
        XCTAssertEqual(snapshot.cursorModelsPercent ?? -1, 12.4, accuracy: 0.001)
        XCTAssertEqual(snapshot.otherModels, .notIncluded)
        XCTAssertFalse(snapshot.onDemand.enabled)
        XCTAssertEqual(snapshot.menuTitle(format: .compact), "C 12%  O n/a")
        XCTAssertEqual(snapshot.menuTitle(format: .detailed), "Cursor 12% · Other not included")
        XCTAssertEqual(snapshot.level(threshold: 80), .normal)
    }

    func testZeroApiPercentIsIncluded() throws {
        let json = """
        {
          "billingCycleEnd": "2026-10-05T00:00:00.000Z",
          "membershipType": "pro",
          "individualUsage": {
            "plan": { "autoPercentUsed": 10, "apiPercentUsed": 0, "totalPercentUsed": 8 }
          }
        }
        """
        let snapshot = try UsageAssembler.snapshot(summaryJSON: Data(json.utf8))
        XCTAssertEqual(snapshot.otherModels, .included(percent: 0))
        XCTAssertEqual(snapshot.menuTitle(format: .compact), "C 10%  O 0%")
    }

    func testTeamDisplayMessagesWhenPlanObjectIsMissing() throws {
        let json = """
        {
          "billingCycleEnd": "2026-10-01T00:00:00.000Z",
          "membershipType": "enterprise",
          "autoModelSelectedDisplayMessage": "You've used 42% of your included total usage",
          "namedModelSelectedDisplayMessage": "You've used 7% of your included API usage",
          "teamUsage": { "onDemand": { "enabled": true, "used": 250, "limit": null } }
        }
        """
        let snapshot = try UsageAssembler.snapshot(summaryJSON: Data(json.utf8))
        XCTAssertEqual(snapshot.planName, "Enterprise")
        XCTAssertEqual(snapshot.cursorModelsPercent ?? -1, 42, accuracy: 0.001)
        XCTAssertEqual(snapshot.otherModels, .included(percent: 7))
        XCTAssertTrue(snapshot.onDemand.enabled)
        XCTAssertEqual(snapshot.onDemand.usedCents ?? -1, 250, accuracy: 0.001)
        XCTAssertNil(snapshot.onDemand.limitCents)
    }

    func testNullIndividualOnDemandFallsBackToTeam() throws {
        let json = """
        {
          "billingCycleEnd": "2026-10-05T00:00:00.000Z",
          "membershipType": "enterprise",
          "individualUsage": {
            "plan": { "autoPercentUsed": 10, "apiPercentUsed": 20, "totalPercentUsed": 12 },
            "onDemand": null
          },
          "teamUsage": { "onDemand": { "enabled": true, "used": 250, "limit": 1000 } }
        }
        """
        let snapshot = try UsageAssembler.snapshot(summaryJSON: Data(json.utf8))
        XCTAssertTrue(snapshot.onDemand.enabled)
        XCTAssertEqual(snapshot.onDemand.usedCents ?? -1, 250, accuracy: 0.001)
        XCTAssertEqual(snapshot.onDemand.limitCents ?? -1, 1000, accuracy: 0.001)
    }

    func testPeriodUsageFillsMissingPools() throws {
        let summary = """
        {
          "billingCycleStart": "2026-09-05T00:00:00.000Z",
          "billingCycleEnd": "2026-10-05T00:00:00.000Z",
          "membershipType": "pro"
        }
        """
        let period = """
        {
          "planUsage": { "autoPercentUsed": 9.5, "apiPercentUsed": 1.2, "totalPercentUsed": 8 }
        }
        """
        let snapshot = try UsageAssembler.snapshot(
            summaryJSON: Data(summary.utf8),
            periodJSON: Data(period.utf8)
        )
        XCTAssertEqual(snapshot.cursorModelsPercent ?? -1, 9.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.otherModels, .included(percent: 1.2))
    }

    func testHardLimitFillsOnDemandCapInDollars() throws {
        let summary = """
        {
          "billingCycleEnd": "2026-10-05T00:00:00.000Z",
          "membershipType": "ultra",
          "individualUsage": {
            "plan": { "autoPercentUsed": 4, "apiPercentUsed": 80, "totalPercentUsed": 20 },
            "onDemand": { "enabled": true, "used": 250, "limit": null }
          }
        }
        """
        let snapshot = try UsageAssembler.snapshot(
            summaryJSON: Data(summary.utf8),
            hardLimitJSON: Data(#"{"hardLimit":50,"noUsageBasedAllowed":false}"#.utf8)
        )
        XCTAssertEqual(snapshot.onDemand.limitCents ?? -1, 5000, accuracy: 0.001)
        XCTAssertTrue(snapshot.onDemand.enabled)
        XCTAssertEqual(snapshot.level(threshold: 80), .warning)
    }

    func testHardLimitDisablesOnDemand() throws {
        let summary = """
        {
          "billingCycleEnd": "2026-10-05T00:00:00.000Z",
          "membershipType": "pro",
          "individualUsage": {
            "plan": { "autoPercentUsed": 1, "apiPercentUsed": 2, "totalPercentUsed": 1 },
            "onDemand": { "enabled": true, "used": 100, "limit": null }
          }
        }
        """
        let snapshot = try UsageAssembler.snapshot(
            summaryJSON: Data(summary.utf8),
            hardLimitJSON: Data(#"{"noUsageBasedAllowed":true}"#.utf8)
        )
        XCTAssertFalse(snapshot.onDemand.enabled)
        XCTAssertEqual(snapshot.onDemand.usedCents ?? -1, 100, accuracy: 0.001)
    }

    func testOverAllowanceStaysAbove100() throws {
        let json = """
        {
          "billingCycleEnd": "2026-10-05T00:00:00.000Z",
          "membershipType": "pro",
          "individualUsage": {
            "plan": { "autoPercentUsed": 142.7, "apiPercentUsed": 5, "totalPercentUsed": 80 }
          }
        }
        """
        let snapshot = try UsageAssembler.snapshot(summaryJSON: Data(json.utf8))
        XCTAssertEqual(snapshot.cursorModelsPercent ?? -1, 142.7, accuracy: 0.001)
        XCTAssertEqual(142.7.roundedPercent, 143)
        XCTAssertEqual(snapshot.menuTitle(format: .compact), "C 143%  O 5%")
        XCTAssertEqual(snapshot.level(threshold: 80), .critical)
    }

    func testHugeTokenAndCentFieldsDoNotTrap() throws {
        let aggregations = """
        {
          "aggregations": [
            {
              "modelIntent": "composer-2.5",
              "inputTokens": 1e30,
              "outputTokens": 1e30,
              "cacheReadTokens": 1e30,
              "cacheWriteTokens": 1e30,
              "totalCents": 1e30
            }
          ]
        }
        """
        let snapshot = try UsageAssembler.snapshot(
            summaryJSON: Data(bothPoolsJSON.utf8),
            aggregationsJSON: Data(aggregations.utf8)
        )
        let row = try XCTUnwrap(snapshot.models.first)
        XCTAssertEqual(row.inputTokens, Int.max)
        XCTAssertEqual(row.totalTokens, Int.max)
        XCTAssertFalse(row.compactTokenLabel.isEmpty)
        XCTAssertFalse(snapshot.statusText().isEmpty)
        XCTAssertEqual(1e30.roundedPercent, Int.max)
        XCTAssertEqual(Double.nan.roundedPercent, 0)
        XCTAssertTrue(1e30.dollarLabel.hasPrefix("$"))
    }

    func testModelClassificationAndBreakdown() throws {
        let snapshot = try UsageAssembler.snapshot(
            summaryJSON: Data(bothPoolsJSON.utf8),
            aggregationsJSON: Data(aggregationsJSON.utf8)
        )
        XCTAssertFalse(snapshot.modelsUnavailable)
        XCTAssertEqual(snapshot.models.map(\.modelIntent), ["composer-2.5", "Grok 4.7", "claude-opus", "auto"])
        XCTAssertEqual(snapshot.models.map(\.pool), [.cursor, .cursor, .other, .auto])
        XCTAssertEqual(snapshot.models[0].inputTokens, 1000)
        XCTAssertEqual(snapshot.models[0].outputTokens, 2000)
        XCTAssertEqual(snapshot.models[0].cacheReadTokens, 10)
        XCTAssertEqual(snapshot.models[0].cacheWriteTokens, 5)
        XCTAssertEqual(snapshot.models[0].totalCents, 120.5, accuracy: 0.001)
    }

    func testFailedModelBreakdownDoesNotHidePools() throws {
        let snapshot = try UsageAssembler.snapshot(
            summaryJSON: Data(bothPoolsJSON.utf8),
            modelBreakdownFailed: true
        )
        XCTAssertEqual(snapshot.cursorModelsPercent ?? -1, 42.4, accuracy: 0.001)
        XCTAssertTrue(snapshot.modelsUnavailable)
        XCTAssertTrue(snapshot.models.isEmpty)
    }

    func testMissingPoolsWithoutFallbackThrows() {
        let json = #"{"billingCycleEnd":"2026-10-05T00:00:00.000Z","membershipType":"pro"}"#
        XCTAssertThrowsError(try UsageAssembler.snapshot(summaryJSON: Data(json.utf8)))
    }

    func testDaysLeftFollowsUTCCycle() throws {
        let snapshot = try UsageAssembler.snapshot(summaryJSON: Data(bothPoolsJSON.utf8))
        let now = date("2026-10-04T20:00:00Z")
        XCTAssertEqual(snapshot.daysRemaining(now: now), 1)
        XCTAssertEqual(snapshot.daysLeftLabel(now: now), "1 day left")
        XCTAssertTrue(snapshot.statusText(now: now).contains("Days left: 1"))
    }

    func testStatusReport() throws {
        let snapshot = try UsageAssembler.snapshot(
            summaryJSON: Data(bothPoolsJSON.utf8),
            aggregationsJSON: Data(aggregationsJSON.utf8),
            now: date("2026-10-01T12:00:00Z")
        )
        let report = snapshot.statusText(now: date("2026-10-01T12:00:00Z"))
        XCTAssertTrue(report.contains("Plan: Pro"))
        XCTAssertTrue(report.contains("Cycle (UTC): 2026-09-05 to 2026-10-05"))
        XCTAssertTrue(report.contains("Days left: 4"))
        XCTAssertTrue(report.contains("Cursor Models: 42%"))
        XCTAssertTrue(report.contains("Other Models: 18%"))
        XCTAssertTrue(report.contains("On-demand: on, $17.85 of $50.00"))
        XCTAssertTrue(report.contains("composer-2.5\tcursor\t$1.21\tin=1000\tout=2000\tcacheRead=10\tcacheWrite=5"))
        XCTAssertTrue(report.contains("auto\tauto\t$0.05"))
    }

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)!
    }

    private let bothPoolsJSON = """
    {
      "billingCycleStart": "2026-09-05T00:00:00.000Z",
      "billingCycleEnd": "2026-10-05T00:00:00.000Z",
      "membershipType": "pro",
      "isUnlimited": false,
      "individualUsage": {
        "plan": {
          "enabled": true,
          "autoPercentUsed": 42.4,
          "apiPercentUsed": 18.2,
          "totalPercentUsed": 30.1
        },
        "onDemand": { "enabled": true, "used": 1785, "limit": 5000 }
      }
    }
    """

    private let startPlanJSON = """
    {
      "billingCycleStart": "2026-09-01T00:00:00.000Z",
      "billingCycleEnd": "2026-10-01T00:00:00.000Z",
      "membershipType": "start",
      "isUnlimited": false,
      "individualUsage": {
        "plan": { "enabled": true, "autoPercentUsed": 12.4, "totalPercentUsed": 12.4 },
        "onDemand": { "enabled": false, "used": 0, "limit": null }
      }
    }
    """

    private let aggregationsJSON = """
    {
      "aggregations": [
        {
          "modelIntent": "composer-2.5",
          "inputTokens": "1000",
          "outputTokens": "2000",
          "cacheReadTokens": "10",
          "cacheWriteTokens": "5",
          "totalCents": 120.5
        },
        { "modelIntent": "Grok 4.7", "inputTokens": 10, "outputTokens": 10, "totalCents": 80 },
        { "modelIntent": "claude-opus", "inputTokens": 10, "outputTokens": 20, "totalCents": 50 },
        { "modelIntent": "auto", "inputTokens": "1", "outputTokens": "1", "totalCents": 5 }
      ]
    }
    """
}

final class ModelPoolTests: XCTestCase {
    func testCursorModels() {
        for intent in [
            "grok-4.7",
            "grok-4.6",
            "Grok 4.5",
            "grok-4.7-xhigh",
            "cursor-grok-4.6-high-fast",
            "cursor-grok-4.5-high",
            "composer-2.5",
            "composer-2.5-fast",
            "Composer 2.5",
        ] {
            XCTAssertEqual(ModelPool.classify(intent), .cursor, intent)
        }
    }

    func testOtherModels() {
        for intent in ["claude-4.6-opus", "gpt-5.6", "composer-2", "premium"] {
            XCTAssertEqual(ModelPool.classify(intent), .other, intent)
        }
    }

    func testAutoAndRouterStaySeparate() {
        for intent in ["auto", "Auto", "default", "auto-fast", "auto-smart", "cursor-router"] {
            XCTAssertEqual(ModelPool.classify(intent), .auto, intent)
        }
    }
}

final class TokenProviderTests: XCTestCase {
    func testUserIDFromJWTSubject() throws {
        let jwt = makeJWT(subject: "auth0|user_abc")
        XCTAssertEqual(try CursorSession.userID(fromJWT: jwt), "user_abc")
        let session = try CursorSession(storedValue: jwt)
        XCTAssertEqual(session.userId, "user_abc")
        XCTAssertEqual(session.accessToken, jwt)
        XCTAssertEqual(session.cookieValue, "user_abc%3A%3A\(jwt)")
    }

    func testCombinedAndPercentEncodedStorage() throws {
        let jwt = makeJWT(subject: "user_xyz")
        let combined = try CursorSession(storedValue: "user_xyz::\(jwt)")
        XCTAssertEqual(combined.userId, "user_xyz")
        XCTAssertEqual(combined.accessToken, jwt)
        let encoded = try CursorSession(storedValue: "user_xyz%3A%3A\(jwt)")
        XCTAssertEqual(encoded, combined)
    }

    func testRejectsHeaderLineBreaks() {
        XCTAssertThrowsError(try CursorSession(storedValue: "user_abc::aa.bb\ncc"))
        XCTAssertThrowsError(try CursorSession(storedValue: "user_abc\r::aa.bb"))
    }

    func testReadsTokenFromDatabaseAndDropsStaleCopies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("state.vscdb")
        let jwt = makeJWT(subject: "google-oauth2|user_db")
        try runSQLite(database: database, sql: """
        CREATE TABLE ItemTable (key TEXT, value TEXT);
        INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', '\(jwt)');
        """)
        let stale = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-16 * 60)],
            ofItemAtPath: stale.path
        )
        defer { try? FileManager.default.removeItem(at: stale) }

        let session = try TokenProvider.loadSession(databaseURL: database)
        XCTAssertEqual(session.userId, "user_db")
        XCTAssertEqual(session.accessToken, jwt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testSettingsClamps() {
        XCTAssertEqual(WidgetSettings.clampedInterval(0), 1)
        XCTAssertEqual(WidgetSettings.clampedInterval(15), 15)
        XCTAssertEqual(WidgetSettings.clampedInterval(90), 60)
        XCTAssertEqual(WidgetSettings.clampedThreshold(-5), 0)
        XCTAssertEqual(WidgetSettings.clampedThreshold(80), 80)
        XCTAssertEqual(WidgetSettings.clampedThreshold(140), 100)
    }

    private func makeJWT(subject: String) -> String {
        func encode(_ string: String) -> String {
            Data(string.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(#"{"alg":"none","typ":"JWT"}"#)).\(encode(#"{"sub":"\#(subject)"}"#)).x"
    }

    private func runSQLite(database: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
