import AppKit
import SwiftUI

public struct CursorUsageApp: App {
    @StateObject private var store = UsageStore()

    public init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    public var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
