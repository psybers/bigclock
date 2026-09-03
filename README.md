# BigClock

BigClock is a native macOS application built with Swift and SwiftUI.

## Project status

This repository currently contains the initial Xcode project scaffold:

- Native macOS app target (no cross-platform framework)
- Deployment target: macOS 13+
- SwiftUI app lifecycle with AppKit-compatible macOS app target
- Accessory/menu-bar style app configuration (`LSUIElement = true`, so no Dock icon)
- No clock, menu-bar, or preferences features implemented yet

## Build

Open `/home/runner/work/bigclock/bigclock/BigClock.xcodeproj` in Xcode and build the `BigClock` scheme.
