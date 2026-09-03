import SwiftUI
import AppKit

@MainActor
final class ClockViewModel: ObservableObject {
    @Published private(set) var displayTime: String = ClockViewModel.formatter.string(from: Date())
    private var timer: Timer?

    func start() {
        displayTime = Self.formatter.string(from: Date())
        scheduleInitialMinuteBoundaryUpdate()
    }

    deinit {
        timer?.invalidate()
    }

    private func scheduleInitialMinuteBoundaryUpdate() {
        timer?.invalidate()

        let now = Date()
        let nextMinute = Calendar.autoupdatingCurrent.date(
            bySetting: .second,
            value: 0,
            of: now.addingTimeInterval(60)
        ) ?? now.addingTimeInterval(60)

        let delay = max(0.1, nextMinute.timeIntervalSince(now))
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.updateFromSystemTime()
            self?.startMinuteTimer()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func startMinuteTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateFromSystemTime()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateFromSystemTime() {
        displayTime = Self.formatter.string(from: Date())
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "h:mm"
        return formatter
    }()
}

struct ContentView: View {
    @StateObject private var viewModel = ClockViewModel()

    var body: some View {
        ZStack {
            Text(viewModel.displayTime)
                .font(.system(size: 160))
                .foregroundStyle(.yellow.opacity(0.8))
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .fixedSize()

            WindowDragOverlay()
        }
        .background(Color.clear)
        .onAppear {
            viewModel.start()
        }
    }
}

struct WindowDragOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {
    }
}

final class DragView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
