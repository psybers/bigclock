import SwiftUI
import AppKit

@MainActor
final class ClockPreferences: ObservableObject {
    static let fontSizeRange: ClosedRange<Double> = 20...300
    static let opacityRange: ClosedRange<Double> = 0.1...1.0

    @Published var fontFamily: String {
        didSet {
            let validated = Self.validatedFontFamily(fontFamily)
            guard validated == fontFamily else {
                fontFamily = validated
                return
            }
            persistIfNeeded()
        }
    }

    @Published var fontSize: Double {
        didSet {
            let validated = Self.validatedFontSize(fontSize)
            guard validated == fontSize else {
                fontSize = validated
                return
            }
            persistIfNeeded()
        }
    }

    @Published var textColor: NSColor {
        didSet {
            let normalized = Self.normalizedColor(textColor)
            guard !normalized.isEqual(textColor) else {
                persistIfNeeded()
                return
            }
            textColor = normalized
        }
    }

    @Published var textOpacity: Double {
        didSet {
            let validated = Self.validatedOpacity(textOpacity)
            guard validated == textOpacity else {
                textOpacity = validated
                return
            }
            persistIfNeeded()
        }
    }

    var availableFontFamilies: [String] {
        Self.availableFontFamilies
    }

    var clockFont: NSFont {
        NSFontManager.shared.font(
            withFamily: fontFamily,
            traits: [],
            weight: 5,
            size: CGFloat(fontSize)
        ) ?? .systemFont(ofSize: CGFloat(fontSize))
    }

    private let userDefaults: UserDefaults
    private var isLoading = true

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedFontFamily = userDefaults.string(forKey: Keys.fontFamily)
        let storedFontSize = userDefaults.object(forKey: Keys.fontSize) as? Double
        let storedOpacity = userDefaults.object(forKey: Keys.textOpacity) as? Double
        let storedColorData = userDefaults.data(forKey: Keys.textColor)

        fontFamily = Self.validatedFontFamily(storedFontFamily ?? Self.defaultFontFamily)
        fontSize = Self.validatedFontSize(storedFontSize ?? Self.defaultFontSize)
        textColor = Self.decodedColor(from: storedColorData) ?? Self.defaultTextColor
        textOpacity = Self.validatedOpacity(storedOpacity ?? Self.defaultTextOpacity)

        isLoading = false
        persistIfNeeded()
    }

    private func persistIfNeeded() {
        guard !isLoading else { return }

        userDefaults.set(fontFamily, forKey: Keys.fontFamily)
        userDefaults.set(fontSize, forKey: Keys.fontSize)
        userDefaults.set(textOpacity, forKey: Keys.textOpacity)

        if let colorData = try? NSKeyedArchiver.archivedData(
            withRootObject: Self.normalizedColor(textColor),
            requiringSecureCoding: true
        ) {
            userDefaults.set(colorData, forKey: Keys.textColor)
        }
    }

    private static func decodedColor(from data: Data?) -> NSColor? {
        guard
            let data,
            let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else {
            return nil
        }

        return normalizedColor(color)
    }

    private static func normalizedColor(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }

    private static func validatedFontFamily(_ candidate: String) -> String {
        if availableFontFamilies.contains(candidate) {
            return candidate
        }

        return availableFontFamilies.first(where: { $0 == "Helvetica" }) ?? availableFontFamilies.first ?? "Helvetica"
    }

    private static func validatedFontSize(_ candidate: Double) -> Double {
        min(max(candidate, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    private static func validatedOpacity(_ candidate: Double) -> Double {
        min(max(candidate, opacityRange.lowerBound), opacityRange.upperBound)
    }

    private static let availableFontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
    private static let defaultFontSize = 160.0
    private static let defaultTextColor = NSColor.systemYellow
    private static let defaultTextOpacity = 0.8
    private static let defaultFontFamily = validatedFontFamily(NSFont.systemFont(ofSize: CGFloat(defaultFontSize)).familyName ?? "")

    private enum Keys {
        static let fontFamily = "fontFamily"
        static let fontSize = "fontSize"
        static let textColor = "textColor"
        static let textOpacity = "textOpacity"
    }
}

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
    @ObservedObject var preferences: ClockPreferences
    let onIdealSizeChange: (CGSize) -> Void

    @StateObject private var viewModel = ClockViewModel()

    var body: some View {
        ZStack {
            Text(viewModel.displayTime)
                .font(Font(preferences.clockFont))
                .foregroundStyle(
                    Color(nsColor: preferences.textColor)
                        .opacity(preferences.textOpacity)
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .fixedSize()

            WindowDragOverlay()
        }
        .background(Color.clear)
        .onAppear {
            viewModel.start()
            updateIdealSize()
        }
        .onChange(of: viewModel.displayTime) { _, _ in updateIdealSize() }
        .onChange(of: preferences.fontFamily) { _, _ in updateIdealSize() }
        .onChange(of: preferences.fontSize) { _, _ in updateIdealSize() }
    }

    private func updateIdealSize() {
        let textSize = (viewModel.displayTime as NSString).size(withAttributes: [.font: preferences.clockFont])
        let idealSize = CGSize(
            width: ceil(textSize.width + 48),
            height: ceil(textSize.height + 32)
        )
        onIdealSizeChange(idealSize)
    }
}

struct PreferencesView: View {
    @ObservedObject var preferences: ClockPreferences

    var body: some View {
        Form {
            Picker("Font Family", selection: $preferences.fontFamily) {
                ForEach(preferences.availableFontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }

            HStack {
                Slider(
                    value: $preferences.fontSize,
                    in: ClockPreferences.fontSizeRange,
                    step: 1
                )
                Text("\(Int(preferences.fontSize.rounded())) pt")
                    .monospacedDigit()
                    .frame(width: 72, alignment: .trailing)
            }
            .accessibilityLabel("Font Size")

            ColorPicker(
                "Text Color",
                selection: Binding(
                    get: { Color(nsColor: preferences.textColor) },
                    set: { preferences.textColor = NSColor($0) }
                ),
                supportsOpacity: false
            )

            HStack {
                Slider(
                    value: $preferences.textOpacity,
                    in: ClockPreferences.opacityRange,
                    step: 0.01
                )
                Text("\(Int((preferences.textOpacity * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            .accessibilityLabel("Text Opacity")
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
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
