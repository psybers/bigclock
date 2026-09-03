import SwiftUI
import AppKit

@main
struct BigClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clockPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true

        let hostingView = NSHostingView(rootView: ContentView())
        panel.contentView = hostingView
        panel.layoutIfNeeded()
        panel.setContentSize(hostingView.fittingSize)
        place(panel: panel)
        panel.orderFrontRegardless()

        clockPanel = panel
    }

    private func place(panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let inset: CGFloat = 48
        let origin = NSPoint(
            x: screenFrame.maxX - panel.frame.width - inset,
            y: screenFrame.maxY - panel.frame.height - inset
        )
        panel.setFrameOrigin(origin)
    }
}
