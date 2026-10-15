import AppKit
import SwiftUI

@main
struct PowerClueApp: App {
    @StateObject private var monitor = MonitorStore()

    var body: some Scene {
        MenuBarExtra {
            MenuDashboard()
                .environmentObject(monitor)
        } label: {
            Image(nsImage: Self.statusBarIcon)
                .accessibilityLabel("PowerClue")
        }
        .menuBarExtraStyle(.window)

        Window("PowerClue", id: "dashboard") {
            DashboardView()
                .environmentObject(monitor)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 760)
        .windowResizability(.contentMinSize)
    }

    private static let statusBarIcon: NSImage = {
        let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "PowerClue")!
        image.isTemplate = true
        return image
    }()
}
