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
    private let preferences = ClockPreferences()
    private var clockPanel: NSPanel?
    private var preferencesWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

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

        let hostingView = NSHostingView(
            rootView: ContentView(
                preferences: preferences,
                onIdealSizeChange: { [weak self] size in
                    self?.resizeClockPanel(to: size)
                }
            )
        )
        panel.contentView = hostingView
        panel.layoutIfNeeded()
        panel.setContentSize(hostingView.fittingSize)
        place(panel: panel)
        panel.orderFrontRegardless()

        clockPanel = panel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc
    private func showPreferences(_ sender: Any?) {
        let window = preferencesWindow ?? makePreferencesWindow()
        preferencesWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(sender)
    }

    @objc
    private func centerClockOnScreen(_ sender: Any?) {
        guard
            let panel = clockPanel,
            let screen = containingScreen(for: panel)
        else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (panel.frame.width / 2),
            y: visibleFrame.midY - (panel.frame.height / 2)
        )
        panel.setFrameOrigin(origin)
    }

    @objc
    private func quitApplication(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "clock",
                accessibilityDescription: "BigClock"
            )
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Preferences",
            action: #selector(showPreferences(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Center on Screen",
            action: #selector(centerClockOnScreen(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit",
            action: #selector(quitApplication(_:)),
            keyEquivalent: ""
        )

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func makePreferencesWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: PreferencesView(preferences: preferences)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.toolbarStyle = .preference
        return window
    }

    private func containingScreen(for panel: NSPanel) -> NSScreen? {
        let panelFrame = panel.frame
        let bestScreen = NSScreen.screens.max { lhs, rhs in
            intersectionArea(of: lhs.visibleFrame, with: panelFrame) < intersectionArea(of: rhs.visibleFrame, with: panelFrame)
        }

        return bestScreen ?? panel.screen ?? NSScreen.main
    }

    private func intersectionArea(of lhs: NSRect, with rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
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

    private func resizeClockPanel(to contentSize: CGSize) {
        guard
            let panel = clockPanel,
            panel.contentRect(forFrameRect: panel.frame).size != contentSize
        else {
            return
        }

        let currentFrame = panel.frame
        let centerPoint = NSPoint(x: currentFrame.midX, y: currentFrame.midY)
        let frameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size

        var newOrigin = NSPoint(
            x: centerPoint.x - (frameSize.width / 2),
            y: centerPoint.y - (frameSize.height / 2)
        )

        if let visibleFrame = containingScreen(for: panel)?.visibleFrame {
            newOrigin.x = min(max(newOrigin.x, visibleFrame.minX), visibleFrame.maxX - frameSize.width)
            newOrigin.y = min(max(newOrigin.y, visibleFrame.minY), visibleFrame.maxY - frameSize.height)
        }

        let newFrame = NSRect(origin: newOrigin, size: frameSize)
        panel.setFrame(newFrame, display: true, animate: false)
    }
}
