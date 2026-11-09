import CursorUsageLib
import XCTest

final class ClaudeUsageParsingTests: XCTestCase {
    func testFullResponse() throws {
        let snapshot = try ClaudeUsageSnapshot.parse(
            Data(fullJSON.utf8),
            planName: "Max 20x",
            now: date("2026-11-01T11:46:00Z")
        )
        XCTAssertEqual(snapshot.planName, "Max 20x")
        XCTAssertEqual(snapshot.windows.map(\.title), ["Session", "Week", "Week (Opus)", "Week (Sonnet)"])
        XCTAssertEqual(snapshot.windows[0].percent, 42.4, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[1].percent, 18.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[0].resetLabel(now: date("2026-11-01T11:46:00Z")), "Resets in 2h 14m")
        XCTAssertEqual(snapshot.menuTitle(format: .compact), "S 42%  W 18%  Opus 7%  Sonnet 3%")
        XCTAssertEqual(snapshot.menuTitle(format: .detailed), "Session 42% · Week 18% · Opus 7% · Sonnet 3%")
        XCTAssertEqual(snapshot.level(threshold: 80), .normal)
        XCTAssertEqual(snapshot.extraUsage.panelLabel, "On · $12.50 of $50.00")
        XCTAssertTrue(snapshot.statusText().contains("Plan: Max 20x"))
        XCTAssertTrue(snapshot.statusText().contains("Extra usage: on, $12.50 of $50.00"))
    }

    func testNullOpusAndSonnetWindows() throws {
        let json = """
        {
          "five_hour": { "utilization": 10, "resets_at": "2026-11-01T14:00:00Z" },
          "seven_day": { "utilization": 4, "resets_at": "2026-11-07T19:00:00Z" },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null }
        }
        """
        let snapshot = try ClaudeUsageSnapshot.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(snapshot.extraUsage, .off)
        XCTAssertEqual(snapshot.extraUsage.panelLabel, "Off")
    }

    func testExtraUsageDisabled() throws {
        let json = """
        {
          "five_hour": { "utilization": 1, "resets_at": "2026-11-01T14:00:00Z" },
          "seven_day": { "utilization": 2, "resets_at": "2026-11-07T19:00:00Z" },
          "extra_usage": { "is_enabled": false, "monthly_limit": 5000, "used_credits": 0, "currency": "USD" }
        }
        """
        let snapshot = try ClaudeUsageSnapshot.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.extraUsage, .off)
        XCTAssertEqual(snapshot.extraUsage.statusLabel, "off")
    }

    func testMissingSessionUsesNotAvailable() throws {
        let json = """
        {
          "five_hour": null,
          "seven_day": { "utilization": 0, "resets_at": "2026-11-07T19:00:00Z" },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "limits": [
            {
              "kind": "weekly_all",
              "percent": 0,
              "resets_at": "2026-11-07T19:00:00Z"
            },
            {
              "kind": "weekly_scoped",
              "percent": 0,
              "resets_at": "2026-11-07T19:00:00Z",
              "scope": { "model": { "display_name": "Fable" } }
            }
          ],
          "extra_usage": { "is_enabled": false }
        }
        """
        let snapshot = try ClaudeUsageSnapshot.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.map(\.title), ["Week", "Week (Fable)"])
        XCTAssertEqual(snapshot.menuTitle(format: .compact), "W 0%  Fable 0%")
        XCTAssertEqual(snapshot.menuTitle(format: .detailed), "Week 0% · Fable 0%")
    }

    func testLimitsArrayFillsMissingWindows() throws {
        let json = """
        {
          "limits": [
            { "kind": "session", "percent": 12, "resets_at": "2026-11-01T14:00:00Z" },
            { "kind": "weekly_all", "percent": 3, "resets_at": "2026-11-07T19:00:00Z" }
          ]
        }
        """
        let snapshot = try ClaudeUsageSnapshot.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(snapshot.menuTitle(format: .compact), "S 12%  W 3%")
        XCTAssertEqual(snapshot.extraUsage, .unavailable)
    }

    func testHighestWindowSetsTheLevel() throws {
        let json = """
        {
          "five_hour": { "utilization": 10, "resets_at": "2026-11-01T14:00:00Z" },
          "seven_day": { "utilization": 12, "resets_at": "2026-11-07T19:00:00Z" },
          "seven_day_opus": { "utilization": 100, "resets_at": "2026-11-07T19:00:00Z" }
        }
        """
        let snapshot = try ClaudeUsageSnapshot.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.level(threshold: 80), .critical)
    }

    func testMalformedUsageThrows() {
        XCTAssertThrowsError(try ClaudeUsageSnapshot.parse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? ClaudeAPIError, .unrecognizedUsage)
        }
        XCTAssertThrowsError(try ClaudeUsageSnapshot.parse(Data("[]".utf8))) { error in
            XCTAssertEqual(error as? ClaudeAPIError, .unrecognizedUsage)
        }
        XCTAssertThrowsError(try ClaudeUsageSnapshot.parse(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? ClaudeAPIError, .unrecognizedUsage)
        }
    }

    func testCredentialPlanName() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "token-value",
            "refreshToken": "ignored",
            "expiresAt": 9000000000000,
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_20x"
          }
        }
        """
        let credentials = try ClaudeCredentials.parse(Data(json.utf8), now: date("2026-11-01T00:00:00Z"))
        XCTAssertEqual(credentials.accessToken, "token-value")
        XCTAssertEqual(credentials.planName, "Max 20x")
        XCTAssertEqual(ClaudeCredentials.planName(rateLimitTier: "default_claude_max_5x", subscriptionType: "max"), "Max 5x")
        XCTAssertEqual(ClaudeCredentials.planName(rateLimitTier: "default_claude_ai", subscriptionType: nil), "Pro")
        XCTAssertEqual(ClaudeCredentials.planName(rateLimitTier: nil, subscriptionType: "pro"), "Pro")
    }

    func testExpiredCredentialThrows() {
        let json = #"{"claudeAiOauth":{"accessToken":"token-value","expiresAt":1500000000000}}"#
        XCTAssertThrowsError(try ClaudeCredentials.parse(Data(json.utf8), now: date("2026-11-01T00:00:00Z"))) { error in
            XCTAssertEqual(error as? ClaudeAPIError, .sessionExpired)
        }
    }

    func testMissingCredentialThrows() {
        XCTAssertThrowsError(try ClaudeCredentials.parse(Data(#"{"mcpOAuth":{}}"#.utf8))) { error in
            XCTAssertEqual(error as? ClaudeAPIError, .notSignedIn)
        }
        XCTAssertThrowsError(try ClaudeCredentials.parse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? ClaudeAPIError, .invalidCredentials)
        }
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private let fullJSON = """
    {
      "five_hour": { "utilization": 42.4, "resets_at": "2026-11-01T14:00:00Z" },
      "seven_day": { "utilization": 18.2, "resets_at": "2026-11-07T19:00:00Z" },
      "seven_day_opus": { "utilization": 7, "resets_at": "2026-11-07T19:00:00Z" },
      "seven_day_sonnet": { "utilization": 3.2, "resets_at": null },
      "extra_usage": {
        "is_enabled": true,
        "monthly_limit": 5000,
        "used_credits": 1250,
        "utilization": 25,
        "currency": "USD"
      }
    }
    """
}
