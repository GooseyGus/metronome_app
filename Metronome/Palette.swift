import SwiftUI

/// A colour scheme for the whole app, with each colour assigned a role.
struct Palette {
    /// The four source colours, shown as stripes on the palette button.
    let swatch: [Color]
    /// Light or dark, so the status bar stays readable.
    let scheme: ColorScheme
    let background: Color
    let text: Color
    let start: Color
    let startText: Color
    let stop: Color
    let stopText: Color
    /// Reset button and +/- circles.
    let control: Color
    let controlText: Color

    init(
        swatch: [UInt32], scheme: ColorScheme,
        background: UInt32, text: UInt32,
        start: UInt32, startText: UInt32,
        stop: UInt32, stopText: UInt32,
        control: UInt32, controlText: UInt32
    ) {
        self.swatch = swatch.map(Color.init(hex:))
        self.scheme = scheme
        self.background = Color(hex: background)
        self.text = Color(hex: text)
        self.start = Color(hex: start)
        self.startText = Color(hex: startText)
        self.stop = Color(hex: stop)
        self.stopText = Color(hex: stopText)
        self.control = Color(hex: control)
        self.controlText = Color(hex: controlText)
    }

    static let all = [
        // Navy
        Palette(
            swatch: [0x0A2947, 0x8B5E3C, 0xD3D4C0, 0xF3E4C9], scheme: .dark,
            background: 0x0A2947, text: 0xF3E4C9,
            start: 0x8B5E3C, startText: 0xF3E4C9,
            stop: 0xD3D4C0, stopText: 0x0A2947,
            control: 0xD3D4C0, controlText: 0x0A2947
        ),
        // Valve: warm charcoal, amber lamp glow and bone, like an old valve amp.
        Palette(
            swatch: [0x1C1A17, 0x3A352F, 0xD9822B, 0xEDE3CF], scheme: .dark,
            background: 0x1C1A17, text: 0xEDE3CF,
            start: 0xD9822B, startText: 0x1C1A17,
            stop: 0xEDE3CF, stopText: 0x1C1A17,
            control: 0x3A352F, controlText: 0xEDE3CF
        ),
        // Harbour: deep sea teal with a rust accent.
        Palette(
            swatch: [0x102B30, 0xC86B3C, 0xCFD2BE, 0xF2E8D5], scheme: .dark,
            background: 0x102B30, text: 0xF2E8D5,
            start: 0xC86B3C, startText: 0xF2E8D5,
            stop: 0xCFD2BE, stopText: 0x102B30,
            control: 0xCFD2BE, controlText: 0x102B30
        ),
        // Forest: pine green and brass.
        Palette(
            swatch: [0x1E2B23, 0x35473B, 0xC9A043, 0xEFE7D4], scheme: .dark,
            background: 0x1E2B23, text: 0xEFE7D4,
            start: 0xC9A043, startText: 0x1E2B23,
            stop: 0xEFE7D4, stopText: 0x1E2B23,
            control: 0x35473B, controlText: 0xEFE7D4
        ),
        // Oxblood: dark burgundy leather and mustard.
        Palette(
            swatch: [0x2E1215, 0x4A2328, 0xD9A55B, 0xF2E6D3], scheme: .dark,
            background: 0x2E1215, text: 0xF2E6D3,
            start: 0xD9A55B, startText: 0x2E1215,
            stop: 0xF2E6D3, stopText: 0x2E1215,
            control: 0x4A2328, controlText: 0xF2E6D3
        ),
        // Olive: army-surplus olive with a burnt orange accent.
        Palette(
            swatch: [0x2A2B1E, 0x45472F, 0xC4622D, 0xEDE6D0], scheme: .dark,
            background: 0x2A2B1E, text: 0xEDE6D0,
            start: 0xC4622D, startText: 0xEDE6D0,
            stop: 0xEDE6D0, stopText: 0x2A2B1E,
            control: 0x45472F, controlText: 0xEDE6D0
        ),
        // Espresso: dark roast brown, caramel and milk.
        Palette(
            swatch: [0x261B16, 0x3E2E25, 0xC07A48, 0xF4EBDD], scheme: .dark,
            background: 0x261B16, text: 0xF4EBDD,
            start: 0xC07A48, startText: 0x261B16,
            stop: 0xD8C3A5, stopText: 0x261B16,
            control: 0x3E2E25, controlText: 0xF4EBDD
        ),
        // Slate
        Palette(
            swatch: [0x37353E, 0x44444E, 0x715A5A, 0xD3DAD9], scheme: .dark,
            background: 0x37353E, text: 0xD3DAD9,
            start: 0x715A5A, startText: 0xD3DAD9,
            stop: 0xD3DAD9, stopText: 0x37353E,
            control: 0x44444E, controlText: 0xD3DAD9
        ),
    ]
}

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
