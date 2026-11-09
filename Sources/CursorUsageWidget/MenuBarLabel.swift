import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @AppStorage(WidgetSettings.menuBarFormat) private var format: MenuBarFormat = .compact
    @AppStorage(WidgetSettings.warningThreshold) private var threshold = WidgetSettings.defaultThreshold

    var body: some View {
        let title = menuTitle
        let level = menuLevel
        Image(nsImage: MenuBarImage.make(text: title, level: level))
            .accessibilityLabel(title)
    }

    private var menuTitle: String {
        if let snapshot = store.snapshot {
            return snapshot.menuTitle(format: format)
        }
        return UsageSnapshot.placeholderTitle(hasError: store.errorMessage != nil)
    }

    private var menuLevel: UsageLevel {
        store.snapshot?.level(threshold: threshold) ?? .normal
    }
}

enum MenuBarImage {
    static func make(text: String, level: UsageLevel) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let color: NSColor
        switch level {
        case .normal:
            color = .black
        case .warning:
            color = .systemOrange
        case .critical:
            color = .systemRed
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let measured = (text as NSString).size(withAttributes: attributes)
        let size = NSSize(width: max(ceil(measured.width) + 2, 24), height: max(ceil(measured.height), 18))
        let image = NSImage(size: size, flipped: false) { rect in
            let origin = NSPoint(x: 1, y: (rect.height - measured.height) / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
            return true
        }
        image.isTemplate = level == .normal
        return image
    }
}
