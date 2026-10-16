import SwiftUI

/// A pop-up number pad that floats over the screen without moving anything.
/// The current value starts selected, so the first digit typed replaces it.
struct Keypad: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
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
            CapText(
                text: isValueSelected ? String(value) : entry,
                size: 56,
                widthOf: String(repeating: "8", count: maxDigits)
            )
            .padding(12)
            .foregroundStyle(isValueSelected ? palette.startText : palette.text)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isValueSelected ? palette.start : palette.text.opacity(0.12))
            )

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
            if !isValueSelected, let typed = Int(entry) {
                onCommit(min(max(typed, range.lowerBound), range.upperBound))
            } else {
                onCancel()
            }
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
    let palette: Palette
    let onSelect: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        PopupCard(title: title, subtitle: nil, palette: palette, onDismiss: onCancel) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(options, id: \.value) { option in
                    let isSelected = option.value == selected
                    PressButton(action: { onSelect(option.value) }) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? palette.start : palette.control)
                            .frame(height: 64)
                            .overlay {
                                VStack(spacing: 8) {
                                    CapText(text: String(option.value), size: 26)
                                    CapText(text: option.name.uppercased(), size: 9, tracking: 1)
                                }
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

/// Dims the screen and floats a titled card over it, without moving anything
/// underneath. Tapping outside the card dismisses it.
struct PopupCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let palette: Palette
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.analogue(size: 16))
                        .tracking(3)
                    if let subtitle {
                        Text(subtitle)
                            .font(.analogue(size: 13))
                            .opacity(0.6)
                    }
                }
                content
            }
            .padding(20)
            .frame(width: 300)
            .foregroundStyle(palette.text)
            .background(RoundedRectangle(cornerRadius: 20).fill(palette.background))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(palette.text.opacity(0.3)))
        }
    }
}
