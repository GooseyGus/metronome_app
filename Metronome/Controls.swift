import CoreText
import SwiftUI

/// A button that fires the moment it's touched (not on release) with no highlight
/// animation, so it reacts instantly. With `repeats`, holding it keeps firing.
struct PressButton<Label: View>: View {
    private let repeats: Bool
    private let action: () -> Void
    private let label: Label
    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    init(repeats: Bool = false, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.repeats = repeats
        self.action = action
        self.label = label()
    }

    var body: some View {
        label
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        action()
                        if repeats { startRepeating() }
                    }
                    .onEnded { _ in
                        isPressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func startRepeating() {
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }
}

/// A slider that tracks the finger exactly and stops the moment you let go (no momentum).
struct TempoSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let color: Color
    /// Called with true when a drag starts and false when the finger lifts.
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false
    private let thumbSize: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let travel = geometry.size.width - thumbSize
            let span = CGFloat(range.upperBound - range.lowerBound)
            let fraction = CGFloat(value - range.lowerBound) / span

            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.25)).frame(height: 6)
                Capsule().fill(color).frame(width: thumbSize / 2 + travel * fraction, height: 6)
                Circle().fill(color).frame(width: thumbSize, height: thumbSize).offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let position = min(max((drag.location.x - thumbSize / 2) / travel, 0), 1)
                        value = range.lowerBound + Int((position * span).rounded())
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 44)
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        }
    }
}

/// Text drawn from the font's glyph outlines, in a box exactly as tall as a capital
/// letter or digit. Unlike `Text`, which centres its whole line box (including space
/// above and below the letters), this centres the letters themselves.
/// Intended for capitals and digits.
struct CapText: View {
    let text: String
    let size: CGFloat
    var tracking: CGFloat = 0
    /// Reserve the width of this text instead (e.g. "888"), so the box never resizes.
    var widthOf: String?

    var body: some View {
        let metrics = GlyphShape.metrics(widthOf ?? text, size: size, tracking: tracking)
        GlyphShape(text: text, size: size, tracking: tracking)
            .frame(width: metrics.width, height: metrics.capHeight)
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}

private struct GlyphShape: Shape {
    let text: String
    let size: CGFloat
    let tracking: CGFloat

    static func line(_ text: String, size: CGFloat, tracking: CGFloat) -> (CTLine, CTFont) {
        let font = CTFontCreateWithName(Font.analogueName as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: tracking]
        return (CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), font)
    }

    static func metrics(_ text: String, size: CGFloat, tracking: CGFloat) -> (width: CGFloat, capHeight: CGFloat) {
        let (line, font) = line(text, size: size, tracking: tracking)
        // Tracking is added after every letter; drop the last one so the text stays centred.
        let width = CTLineGetTypographicBounds(line, nil, nil, nil) - (text.isEmpty ? 0 : tracking)
        return (max(width, 0), CTFontGetCapHeight(font))
    }

    func path(in rect: CGRect) -> Path {
        let (line, font) = Self.line(text, size: size, tracking: tracking)
        let glyphs = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var ids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &ids)
            CTRunGetPositions(run, CFRange(), &positions)
            for (id, position) in zip(ids, positions) {
                guard let outline = CTFontCreatePathForGlyph(font, id, nil) else { continue }
                glyphs.addPath(outline, transform: CGAffineTransform(translationX: position.x, y: position.y))
            }
        }
        // Centre horizontally; put the baseline on the bottom edge, flipping CoreText's upward y axis.
        let width = Self.metrics(text, size: size, tracking: tracking).width
        let transform = CGAffineTransform(translationX: rect.midX - width / 2, y: rect.maxY).scaledBy(x: 1, y: -1)
        return Path(glyphs).applying(transform)
    }
}
