import Foundation

public enum CursorAPIError: Error, LocalizedError, Equatable {
    case notAuthenticated
    case unrecognizedUsage
    case httpStatus(Int)
    case network

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in to Cursor. Open Cursor, sign in, then refresh."
        case .unrecognizedUsage:
            return "Cursor’s usage response didn’t include the model pools."
        case .httpStatus(let status):
            return "Cursor returned HTTP \(status)."
        case .network:
            return "Couldn’t reach Cursor. Check your connection and refresh."
        }
    }
}

public enum CursorAPI {
    public static func fetchSnapshot(now: Date = Date()) async throws -> UsageSnapshot {
        let session = try await SessionStore.shared.session()
        do {
            return try await CursorClient(credentials: session).fetchSnapshot(now: now)
        } catch CursorAPIError.notAuthenticated {
            await SessionStore.shared.invalidate()
            let reloaded = try await SessionStore.shared.session(forceReload: true)
            return try await CursorClient(credentials: reloaded).fetchSnapshot(now: now)
        }
    }
}

private actor SessionStore {
    static let shared = SessionStore()

    private var cached: CursorSession?

    func session(forceReload: Bool = false) throws -> CursorSession {
        if !forceReload, let cached { return cached }
        let loaded = try TokenProvider.loadSession()
        cached = loaded
        return loaded
    }

    func invalidate() {
        cached = nil
    }
}

private struct CursorClient: Sendable {
    private static let summaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    private static let aggregatedURL = URL(string: "https://cursor.com/api/dashboard/get-aggregated-usage-events")!
    private static let periodURL = URL(string: "https://cursor.com/api/dashboard/get-current-period-usage")!
    private static let rpcBase = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/")!
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"

    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private let credentials: CursorSession

    init(credentials: CursorSession) {
        self.credentials = credentials
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        let summary = try SummaryDraft.parse(try await dashboard(Self.summaryURL))
        let period = summary.needsPeriodFallback ? try await currentPeriod() : nil

        async let planData = optionalRPC("GetPlanInfo")
        async let hardLimitData = optionalRPC("GetHardLimit")
        async let modelResult = aggregatedEvents(window: summary.aggregationWindow(periodJSON: period, now: now))
        let models = try await modelResult

        return try UsageAssembler.snapshot(
            summary: summary,
            periodJSON: period,
            planJSON: try await planData,
            hardLimitJSON: try await hardLimitData,
            aggregationsJSON: models.data,
            modelBreakdownFailed: models.failed,
            now: now
        )
    }

    private func aggregatedEvents(window: (start: Int64, end: Int64)) async throws -> (data: Data?, failed: Bool) {
        let rpcBody: [String: Any] = [
            "startDate": String(window.start),
            "endDate": String(window.end),
        ]
        if let data = try await ignoringOptionalFailure({ try await self.rpc("GetAggregatedUsageEvents", body: rpcBody) }),
           hasAggregations(data) {
            return (data, false)
        }
        let restBody: [String: Any] = [
            "teamId": -1,
            "startDate": window.start,
            "endDate": window.end,
        ]
        if let data = try await ignoringOptionalFailure({ try await self.dashboard(Self.aggregatedURL, body: restBody) }),
           hasAggregations(data) {
            return (data, false)
        }
        return (nil, true)
    }

    private func currentPeriod() async throws -> Data? {
        if let data = try await optionalRPC("GetCurrentPeriodUsage") { return data }
        return try await ignoringOptionalFailure { try await dashboard(Self.periodURL, body: [:]) }
    }

    private func dashboard(_ url: URL, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/dashboard?tab=usage", forHTTPHeaderField: "Referer")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await send(request)
    }

    private func optionalRPC(_ method: String, body: [String: Any] = [:]) async throws -> Data? {
        try await ignoringOptionalFailure { try await rpc(method, body: body) }
    }

    private func ignoringOptionalFailure(_ operation: () async throws -> Data) async throws -> Data? {
        do {
            return try await operation()
        } catch CursorAPIError.notAuthenticated {
            throw CursorAPIError.notAuthenticated
        } catch {
            return nil
        }
    }

    private func rpc(_ method: String, body: [String: Any] = [:]) async throws -> Data {
        var request = URLRequest(url: Self.rpcBase.appendingPathComponent(method))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private var cookieHeader: String {
        "WorkosCursorSessionToken=\(credentials.cookieValue)"
    }

    private func hasAggregations(_ data: Data) -> Bool {
        JSON.object(from: data)?["aggregations"] != nil
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.urlSession.data(for: request)
        } catch {
            throw CursorAPIError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw CursorAPIError.network
        }
        switch http.statusCode {
        case 200:
            return data
        case 401, 403:
            throw CursorAPIError.notAuthenticated
        default:
            throw CursorAPIError.httpStatus(http.statusCode)
        }
    }
}
