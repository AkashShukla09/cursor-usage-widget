import Foundation

public enum ProviderSnapshot: Equatable, Sendable {
    case cursor(UsageSnapshot)
    case claude(ClaudeUsageSnapshot)

    public var fetchedAt: Date {
        switch self {
        case .cursor(let snapshot): snapshot.fetchedAt
        case .claude(let snapshot): snapshot.fetchedAt
        }
    }

    public var planName: String {
        switch self {
        case .cursor(let snapshot): snapshot.planName
        case .claude(let snapshot): snapshot.planName
        }
    }

    public func menuTitle(format: MenuBarFormat) -> String {
        switch self {
        case .cursor(let snapshot): snapshot.menuTitle(format: format)
        case .claude(let snapshot): snapshot.menuTitle(format: format)
        }
    }

    public func level(threshold: Int) -> UsageLevel {
        switch self {
        case .cursor(let snapshot): snapshot.level(threshold: threshold)
        case .claude(let snapshot): snapshot.level(threshold: threshold)
        }
    }
}

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var snapshot: ProviderSnapshot?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errorMessage: String?

    private var loop: Task<Void, Never>?
    private var requestGeneration = 0

    public init() {
        WidgetSettings.registerDefaults()
        startLoop(refreshImmediately: true)
    }

    public func refresh() {
        Task { await load() }
    }

    public func updateRefreshInterval() {
        startLoop(refreshImmediately: false)
    }

    public func sourceChanged() {
        requestGeneration += 1
        snapshot = nil
        errorMessage = nil
        isRefreshing = true
        startLoop(refreshImmediately: true)
    }

    private func startLoop(refreshImmediately: Bool) {
        loop?.cancel()
        loop = Task { [weak self] in
            guard let self else { return }
            if refreshImmediately {
                await self.load()
            }
            while !Task.isCancelled {
                let minutes = WidgetSettings.interval()
                let nanoseconds = UInt64(minutes) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanoseconds)
                if Task.isCancelled { break }
                await self.load()
            }
        }
    }

    private func load() async {
        let generation = requestGeneration
        let source = WidgetSettings.source()
        isRefreshing = true
        defer {
            if requestGeneration == generation {
                isRefreshing = false
            }
        }
        do {
            let snapshot = try await fetch(source)
            guard !Task.isCancelled, requestGeneration == generation else { return }
            self.snapshot = snapshot
            self.errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requestGeneration == generation else { return }
            self.errorMessage = error.localizedDescription
        }
    }

    private func fetch(_ source: UsageSource) async throws -> ProviderSnapshot {
        switch source {
        case .cursor:
            return .cursor(try await CursorAPI.fetchSnapshot())
        case .claudeCode:
            return .claude(try await ClaudeAPI.fetchSnapshot())
        }
    }
}
