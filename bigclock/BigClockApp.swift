import SwiftUI
import AppKit
import CoreGraphics

@MainActor
@main
struct BigClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(preferences: appDelegate.preferences)
        }
    }
}

/// Invisible helper view used purely to capture SwiftUI's `openSettings` environment action
/// so it can be invoked from an AppKit `NSMenuItem`, which doesn't support `SettingsLink`.
private struct OpenSettingsAccessor: View {
    let onCapture: (@escaping () -> Void) -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                onCapture { openSettings() }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let preferences = ClockPreferences()
    private var clockPanel: NSPanel?
    private var statusItem: NSStatusItem?
    private let placementStore = ClockWindowPlacementStore()
    private var settingsAccessorWindow: NSWindow?
    private var openSettingsAction: (() -> Void)?

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
        panel.delegate = self
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveClockPlacement()
    }

    func windowDidMove(_ notification: Notification) {
        guard
            let clockPanel,
            let panel = notification.object as? NSPanel,
            panel === clockPanel
        else {
            return
        }

        saveClockPlacement(for: panel)
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
        panel.setFrameOrigin(clampedOrigin(for: panel.frame.size, proposedOrigin: origin, in: visibleFrame))
        saveClockPlacement(for: panel)
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

        installOpenSettingsAccessor()
    }

    /// SwiftUI only exposes `openSettings` via the `Environment`, so we host an invisible
    /// view once to capture that action and reuse it from the AppKit menu item below.
    private func installOpenSettingsAccessor() {
        let hostingView = NSHostingView(
            rootView: OpenSettingsAccessor { [weak self] action in
                self?.openSettingsAction = action
            }
        )
        hostingView.frame = .zero
        let window = NSWindow(contentViewController: NSViewController())
        window.contentViewController?.view = hostingView
        settingsAccessorWindow = window
    }

    @objc
    private func showPreferences(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction?()
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
        let placement = placementStore.load()
        let matchedScreen = placement.flatMap { screen(matching: $0) }
        let targetScreen = matchedScreen ?? NSScreen.main
        guard let visibleFrame = targetScreen?.visibleFrame else { return }

        let origin: NSPoint
        if let placement, matchedScreen != nil {
            origin = restoredOrigin(for: panel.frame.size, placement: placement, in: visibleFrame)
        } else {
            origin = defaultOrigin(for: panel.frame.size, in: visibleFrame)
        }

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
            newOrigin = clampedOrigin(for: frameSize, proposedOrigin: newOrigin, in: visibleFrame)
        }

        let newFrame = NSRect(origin: newOrigin, size: frameSize)
        panel.setFrame(newFrame, display: true, animate: false)
        saveClockPlacement(for: panel)
    }

    private func saveClockPlacement() {
        guard let panel = clockPanel else { return }
        saveClockPlacement(for: panel)
    }

    private func saveClockPlacement(for panel: NSPanel) {
        guard let screen = containingScreen(for: panel) else { return }

        let visibleFrame = screen.visibleFrame
        let clamped = clampedOrigin(for: panel.frame.size, proposedOrigin: panel.frame.origin, in: visibleFrame)
        let clampedFrame = NSRect(origin: clamped, size: panel.frame.size)

        let horizontalFraction = visibleFrame.width > 0
            ? Double((clampedFrame.midX - visibleFrame.minX) / visibleFrame.width)
            : 0.5
        let verticalFraction = visibleFrame.height > 0
            ? Double((clampedFrame.midY - visibleFrame.minY) / visibleFrame.height)
            : 0.5

        placementStore.save(
            ClockWindowPlacement(
                displayUUID: screen.displayUUIDString,
                displayID: screen.displayID,
                horizontalFraction: min(max(horizontalFraction, 0), 1),
                verticalFraction: min(max(verticalFraction, 0), 1)
            )
        )
    }

    private func screen(matching placement: ClockWindowPlacement) -> NSScreen? {
        if let displayUUID = placement.displayUUID,
           let screen = NSScreen.screens.first(where: { $0.displayUUIDString == displayUUID }) {
            return screen
        }

        if let displayID = placement.displayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return screen
        }

        return nil
    }

    private func restoredOrigin(for panelSize: NSSize, placement: ClockWindowPlacement, in visibleFrame: NSRect) -> NSPoint {
        let horizontalFraction = min(max(placement.horizontalFraction, 0), 1)
        let verticalFraction = min(max(placement.verticalFraction, 0), 1)
        let proposedCenter = NSPoint(
            x: visibleFrame.minX + (CGFloat(horizontalFraction) * visibleFrame.width),
            y: visibleFrame.minY + (CGFloat(verticalFraction) * visibleFrame.height)
        )
        let proposedOrigin = NSPoint(
            x: proposedCenter.x - (panelSize.width / 2),
            y: proposedCenter.y - (panelSize.height / 2)
        )

        return clampedOrigin(for: panelSize, proposedOrigin: proposedOrigin, in: visibleFrame)
    }

    private func defaultOrigin(for panelSize: NSSize, in visibleFrame: NSRect) -> NSPoint {
        let inset: CGFloat = 48
        let proposedOrigin = NSPoint(
            x: visibleFrame.maxX - panelSize.width - inset,
            y: visibleFrame.maxY - panelSize.height - inset
        )

        return clampedOrigin(for: panelSize, proposedOrigin: proposedOrigin, in: visibleFrame)
    }

    private func clampedOrigin(for panelSize: NSSize, proposedOrigin: NSPoint, in visibleFrame: NSRect) -> NSPoint {
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)

        return NSPoint(
            x: min(max(proposedOrigin.x, visibleFrame.minX), maxX),
            y: min(max(proposedOrigin.y, visibleFrame.minY), maxY)
        )
    }
}

private struct ClockWindowPlacement: Codable {
    let displayUUID: String?
    let displayID: UInt32?
    let horizontalFraction: Double
    let verticalFraction: Double
}

private struct ClockWindowPlacementStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> ClockWindowPlacement? {
        guard
            let data = userDefaults.data(forKey: Keys.placement),
            let placement = try? JSONDecoder().decode(ClockWindowPlacement.self, from: data)
        else {
            return nil
        }

        return placement
    }

    func save(_ placement: ClockWindowPlacement) {
        guard let data = try? JSONEncoder().encode(placement) else { return }
        userDefaults.set(data, forKey: Keys.placement)
    }

    private enum Keys {
        static let placement = "clockWindowPlacement"
    }
}

private extension NSScreen {
    var displayID: UInt32? {
        guard
            let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return nil
        }

        return screenNumber.uint32Value
    }

    var displayUUIDString: String? {
        guard
            let displayID,
            let displayUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else {
            return nil
        }

        return CFUUIDCreateString(nil, displayUUID) as String
    }
}
