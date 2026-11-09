import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: UsageStore
    @AppStorage(WidgetSettings.warningThreshold) private var threshold = WidgetSettings.defaultThreshold
    @AppStorage(WidgetSettings.usageSource) private var source: UsageSource = .cursor
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(onClose: { showingSettings = false }, store: store)
            } else {
                usagePage
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var usagePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch store.snapshot {
            case .cursor(let snapshot):
                pools(snapshot)
                onDemand(snapshot.onDemand)
                modelBreakdown(snapshot)
            case .claude(let snapshot):
                claudeWindows(snapshot)
                claudeExtraUsage(snapshot.extraUsage)
            case nil:
                if store.isRefreshing {
                    loading("Loading usage…")
                } else {
                    loading(store.errorMessage ?? "Usage isn’t available yet.")
                }
            }
            if store.snapshot != nil, let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(headerTitle)
                    .font(.headline)
                Spacer()
                if case .cursor(let snapshot) = store.snapshot, let label = snapshot.daysLeftLabel() {
                    Text(label)
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            switch store.snapshot {
            case .cursor(let snapshot):
                if let cycle = snapshot.cycleLabel {
                    Text(cycle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .claude:
                Text("Claude Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case nil where source == .claudeCode:
                Text("Claude Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
    }

    private var headerTitle: String {
        switch store.snapshot {
        case .cursor(let snapshot):
            snapshot.planName
        case .claude(let snapshot):
            snapshot.planName
        case nil:
            source == .claudeCode ? "Claude Code Usage" : "Cursor Usage"
        }
    }

    private func claudeWindows(_ snapshot: ClaudeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(snapshot.windows) { window in
                claudeRow(window)
            }
        }
    }

    private func claudeRow(_ window: ClaudeLimitWindow) -> some View {
        let level = UsageLevel(percent: window.percent, threshold: threshold)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: window.id == "five_hour" ? "hourglass" : "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(window.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(window.percent.percentLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(level.tint)
            }
            UsageBar(percent: window.percent, level: level)
            if let reset = window.resetLabel() {
                Text(reset)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func claudeExtraUsage(_ status: ClaudeExtraUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extra usage")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(status.panelLabel)
                .font(.subheadline.monospacedDigit())
        }
    }

    private func pools(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PoolMeter.meters(for: snapshot)) { meter in
                poolRow(meter)
            }
        }
    }

    private func poolRow(_ meter: PoolMeter) -> some View {
        let level = meter.level(threshold: threshold)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: meter.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(meter.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(meter.valueText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(meter.percent == nil ? Color.secondary : level.tint)
            }
            if let percent = meter.percent, !meter.isUnlimited {
                UsageBar(percent: percent, level: level)
            }
        }
    }

    private func onDemand(_ status: OnDemandStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On-demand")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(status.panelLabel)
                .font(.subheadline.monospacedDigit())
        }
    }

    private func modelBreakdown(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Models")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if snapshot.modelsUnavailable {
                caption("Per-model breakdown is unavailable right now.")
            } else if snapshot.models.isEmpty {
                caption("No model usage in this billing cycle.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ModelPool.displayOrder, id: \.self) { pool in
                            modelSection(pool, rows: snapshot.rows(in: pool))
                        }
                        if !snapshot.rows(in: .auto).isEmpty {
                            Text("Auto can draw from either pool. The bars above come from Cursor.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: min(CGFloat(snapshot.models.count) * 28, 220), maxHeight: 220)
            }
        }
    }

    @ViewBuilder
    private func modelSection(_ pool: ModelPool, rows: [ModelUsageRow]) -> some View {
        if !rows.isEmpty {
            Text(pool.sectionTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.modelIntent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(row.compactTokenLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help(row.tokenDetail)
                    Text(row.totalCents.dollarLabel)
                        .font(.caption.monospacedDigit())
                        .layoutPriority(1)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let fetchedAt = store.snapshot?.fetchedAt {
                Text(fetchedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: store.refresh) {
                if store.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Refresh")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isRefreshing)
            Button("Settings") { showingSettings = true }
                .buttonStyle(.borderless)
                .controlSize(.small)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    private func loading(_ text: String) -> some View {
        HStack(spacing: 8) {
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: store.isRefreshing ? .center : .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct PoolMeter: Identifiable {
    let title: String
    let systemImage: String
    let percent: Double?
    let isUnlimited: Bool
    let isNotIncluded: Bool

    var id: String { title }

    var valueText: String {
        if isUnlimited { return "Unlimited" }
        if isNotIncluded { return "Not included" }
        return percent?.percentLabel ?? "Unavailable"
    }

    func level(threshold: Int) -> UsageLevel {
        guard let percent, !isUnlimited else { return .normal }
        return UsageLevel(percent: percent, threshold: threshold)
    }

    static func meters(for snapshot: UsageSnapshot) -> [PoolMeter] {
        let cursor = PoolMeter(
            title: "Cursor Models",
            systemImage: "sparkles",
            percent: snapshot.isUnlimited ? nil : snapshot.cursorModelsPercent,
            isUnlimited: snapshot.isUnlimited,
            isNotIncluded: false
        )
        let otherPercent: Double?
        let otherMissing: Bool
        switch snapshot.otherModels {
        case .included(let percent):
            otherPercent = snapshot.isUnlimited ? nil : percent
            otherMissing = false
        case .notIncluded:
            otherPercent = nil
            otherMissing = !snapshot.isUnlimited
        }
        let other = PoolMeter(
            title: "Other Models",
            systemImage: "cpu",
            percent: otherPercent,
            isUnlimited: snapshot.isUnlimited,
            isNotIncluded: otherMissing
        )
        return [cursor, other]
    }
}

private struct UsageBar: View {
    var percent: Double
    var level: UsageLevel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(level.bar)
                    .frame(width: geo.size.width * min(max(percent, 0) / 100, 1))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("\(percent.percentLabel) percent")
    }
}

private extension UsageLevel {
    var tint: Color {
        switch self {
        case .normal: .primary
        case .warning: .orange
        case .critical: .red
        }
    }

    var bar: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}
