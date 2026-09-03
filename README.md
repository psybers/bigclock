# BigClock

BigClock is a native macOS application built with Swift and SwiftUI.

## Project status

This repository currently contains the first floating clock implementation:

- Native macOS app target (no cross-platform framework)
- Deployment target: macOS 14+
- Accessory/menu-bar style app configuration (`LSUIElement = true`, so no Dock icon)
- Menu bar status item with clock icon and utility actions
- Borderless transparent floating clock panel implemented with AppKit + SwiftUI
- Large yellow local-time display (`h:mm`) that updates from system time every minute
- Drag-to-move support by dragging the clock text
- Window placement persistence across launches, including display-aware restoration

## Build

Open `/home/runner/work/bigclock/bigclock/BigClock.xcodeproj` in Xcode and build the `BigClock` scheme.
