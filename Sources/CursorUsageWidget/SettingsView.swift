import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var onClose: () -> Void

    @AppStorage(WidgetSettings.refreshIntervalMinutes) private var interval = WidgetSettings.defaultInterval
    @AppStorage(WidgetSettings.warningThreshold) private var threshold = WidgetSettings.defaultThreshold
    @AppStorage(WidgetSettings.menuBarFormat) private var format: MenuBarFormat = .compact
    @AppStorage(WidgetSettings.usageSource) private var source: UsageSource = .cursor
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Text("Settings")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Show usage for")
                    .font(.subheadline.weight(.medium))
                Picker("Show usage for", selection: $source) {
                    ForEach(UsageSource.allCases) { item in
                        Text(item.settingsTitle).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            setting("Refresh every \(WidgetSettings.clampedInterval(interval)) min", hint: refreshHint) {
                Slider(value: stepped($interval, clamp: WidgetSettings.clampedInterval), in: 1...60, step: 1)
            }
            setting("Warn at \(WidgetSettings.clampedThreshold(threshold))%", hint: "The menu bar turns amber at this percent and red at 100%.") {
                Slider(value: stepped($threshold, clamp: WidgetSettings.clampedThreshold), in: 0...100, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Menu bar")
                    .font(.subheadline.weight(.medium))
                Picker("Menu bar", selection: $format) {
                    Text("Compact").tag(MenuBarFormat.compact)
                    Text("Detailed").tag(MenuBarFormat.detailed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            LaunchAtLoginToggle()
        }
        .onChange(of: interval) { _, _ in
            store.updateRefreshInterval()
        }
        .onChange(of: source) { _, _ in
            store.sourceChanged()
        }
    }

    private var refreshHint: String {
        switch source {
        case .cursor:
            "How often the menu bar asks Cursor for new usage."
        case .claudeCode:
            "How often the menu bar asks Claude for new usage."
        }
    }

    private func setting<Control: View>(_ title: String, hint: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            control()
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stepped(_ value: Binding<Int>, clamp: @escaping (Int) -> Int) -> Binding<Double> {
        Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = clamp(Int($0.rounded())) }
        )
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: $enabled)
                .font(.subheadline.weight(.medium))
                .onChange(of: enabled) { _, newValue in
                    apply(newValue)
                }
            Text(message ?? "Opens in the menu bar when you log in.")
                .font(.caption)
                .foregroundStyle(message == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func apply(_ shouldEnable: Bool) {
        let currentlyEnabled = SMAppService.mainApp.status == .enabled
        guard shouldEnable != currentlyEnabled else { return }
        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            message = nil
        } catch {
            enabled = SMAppService.mainApp.status == .enabled
            message = "Launch at login needs the app in Applications. \(error.localizedDescription)"
        }
    }
}
