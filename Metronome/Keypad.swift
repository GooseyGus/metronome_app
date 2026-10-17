import SwiftUI

/// A pop-up number pad that floats over the screen without moving anything.
/// The current value starts selected, so the first digit typed replaces it.
struct Keypad: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    /// When set, the value is shown as the top of a time signature over this.
    var denominator: Int?
    let palette: Palette
    let onCommit: (Int) -> Void
    let onCancel: () -> Void

    private enum Key: Hashable { case digit(Int), delete, ok }

    @State private var entry = ""
    @State private var isValueSelected = true

    private let keys: [Key] = (1...9).map(Key.digit) + [.delete, .digit(0), .ok]
    private var maxDigits: Int { String(range.upperBound).count }

    var body: some View {
        PopupCard(title: title, subtitle: "\(range.lowerBound)–\(range.upperBound)", palette: palette, onDismiss: onCancel) {
            let field = CapText(
                text: isValueSelected ? String(value) : entry,
                size: denominator == nil ? 56 : 40,
                widthOf: String(repeating: "8", count: maxDigits)
            )
            .padding(denominator == nil ? 12 : 8)
            .foregroundStyle(isValueSelected ? palette.startText : palette.text)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isValueSelected ? palette.start : palette.text.opacity(0.12))
            )
            if let denominator {
                TimeSignature(top: field, bottom: FractionPart(value: denominator), palette: palette)
            } else {
                field
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(keys, id: \.self, content: keyButton)
            }
        }
    }

    private func keyButton(_ key: Key) -> some View {
        PressButton(action: { press(key) }) {
            RoundedRectangle(cornerRadius: 12)
                .fill(key == .ok ? palette.start : palette.control)
                .frame(height: 56)
                .overlay {
                    Group {
                        switch key {
                        case .digit(let digit):
                            CapText(text: String(digit), size: 28)
                        case .delete:
                            Image(systemName: "delete.left").font(.system(size: 22, weight: .bold))
                        case .ok:
                            CapText(text: "OK", size: 22)
                        }
                    }
                    .foregroundStyle(key == .ok ? palette.startText : palette.controlText)
                }
        }
        .accessibilityLabel(accessibilityName(key))
    }

    private func press(_ key: Key) {
        switch key {
        case .digit(let digit):
            if isValueSelected {
                entry = String(digit)
                isValueSelected = false
            } else if entry.count < maxDigits {
                entry += String(digit)
            }
        case .delete:
            if isValueSelected {
                entry = ""
                isValueSelected = false
            } else {
                entry = String(entry.dropLast())
            }
        case .ok:
            // OK always confirms, keeping the current value if nothing new was typed.
            let typed = isValueSelected ? value : Int(entry) ?? value
            onCommit(min(max(typed, range.lowerBound), range.upperBound))
        }
    }

    private func accessibilityName(_ key: Key) -> String {
        switch key {
        case .digit(let digit): String(digit)
        case .delete: "Delete"
        case .ok: "Done"
        }
    }
}

/// A pop-up list of fixed choices, styled like the keypad. The current choice is lit.
struct ChoicePad: View {
    struct Option {
        let value: Int
        let name: String
    }

    let title: String
    let options: [Option]
    let selected: Int
    /// When set, the choice is shown as the bottom of a time signature under this.
    var numerator: Int?
    let palette: Palette
    let onSelect: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        PopupCard(title: title, subtitle: nil, palette: palette, onDismiss: onCancel) {
            if let numerator {
                TimeSignature(
                    top: FractionPart(value: numerator),
                    bottom: CapText(text: String(selected), size: 40, widthOf: "88")
                        .padding(8)
                        .foregroundStyle(palette.startText)
                        .background(RoundedRectangle(cornerRadius: 10).fill(palette.start)),
                    palette: palette
                )
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(options, id: \.value) { option in
                    let isSelected = option.value == selected
                    PressButton(action: { onSelect(option.value) }) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? palette.start : palette.control)
                            .frame(height: 64)
                            .overlay {
                                CapText(text: String(option.value), size: 26)
                                    .foregroundStyle(isSelected ? palette.startText : palette.controlText)
                            }
                    }
                    .accessibilityLabel("\(option.value), \(option.name)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

/// A time signature stacked as it's written on the stave, one number over the other,
/// so the number being changed can be seen in place.
private struct TimeSignature<Top: View, Bottom: View>: View {
    let top: Top
    let bottom: Bottom
    let palette: Palette

    var body: some View {
        VStack(spacing: 6) {
            top
            Capsule().fill(palette.text.opacity(0.3)).frame(width: 64, height: 2)
            bottom
        }
    }
}

/// The other half of the time signature, shown but not being changed.
private struct FractionPart: View {
    let value: Int

    var body: some View {
        CapText(text: String(value), size: 40, widthOf: "88")
            .padding(8)
            .opacity(0.5)
    }
}

/// Dims the screen and floats a titled card over it, without moving anything
/// underneath. Tapping outside the card dismisses it.
struct PopupCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let palette: Palette
    let onDismiss: () -> Void
    /// A small button at the right-hand end of the title.
    var accessory: AnyView?
    @ViewBuilder let content: Content
    @Environment(\.uiScale) private var scale
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 16) {
                    // An empty title leaves the card to its content, with no gap above.
                    if !title.isEmpty {
                        VStack(spacing: 4) {
                            Text(title)
                                .font(.analogue(size: 16))
                                .tracking(3)
                                .frame(maxWidth: .infinity)
                                // Level with the title.
                                .overlay(alignment: .trailing) { accessory }
                            if let subtitle {
                                Text(subtitle)
                                    .font(.analogue(size: 13))
                                    .opacity(0.6)
                            }
                        }
                    }
                    content
                }
                .padding(20)
                .frame(width: 300)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(palette.text)
                .background(RoundedRectangle(cornerRadius: 20).fill(palette.background))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(palette.text.opacity(0.3)))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                .scaleEffect(fitScale(availableHeight: geometry.size.height))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// Bigger on iPad, and shrunk if needed to fit short screens like a phone on its side.
    private func fitScale(availableHeight: CGFloat) -> CGFloat {
        let preferred = min(scale, 1.5)
        guard cardHeight > 0 else { return preferred }
        return min(preferred, (availableHeight - 16) / cardHeight)
    }
}
