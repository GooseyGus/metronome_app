import SwiftUI

struct ContentView: View {
    private enum Field { case tempo, beats, beatUnit }

    @State private var tempo = defaultTempo
    @State private var isRunning = false
    @State private var metronome = Metronome()
    @State private var wobble = Wobble()
    @State private var editingField: Field?
    @State private var tapTimes: [Date] = []
    @State private var isSliding = false
    // The palette is the only setting remembered between launches.
    @AppStorage("paletteIndex") private var paletteIndex = 0
    @State private var sound = ClickSound.classic
    @State private var accentEnabled = false
    @State private var beatsPerBar = defaultBeats
    @State private var beatUnit = defaultBeatUnit

    private static let defaultTempo = 120
    private static let defaultBeats = 4
    private static let defaultBeatUnit = 4
    private let tempoRange = 1...300
    private let beatsRange = 1...99
    private let beatUnits: [ChoicePad.Option] = [
        .init(value: 1, name: "Whole"), .init(value: 2, name: "Half"),
        .init(value: 4, name: "Quarter"), .init(value: 8, name: "Eighth"),
        .init(value: 16, name: "16th"), .init(value: 32, name: "32nd"),
        .init(value: 64, name: "64th"),
    ]
    private let presets = [30, 60, 72, 90, 120, 140, 180, 240]
    private let gridSpacing: CGFloat = 8
    private let tempoFontSize: CGFloat = 88
    private let stepButtonSize: CGFloat = 80

    private var palette: Palette { Palette.all[paletteIndex % Palette.all.count] }

    private var isAtDefaults: Bool {
        tempo == Self.defaultTempo && beatsPerBar == Self.defaultBeats
            && beatUnit == Self.defaultBeatUnit && !accentEnabled
    }

    /// BPM counts quarter notes. With the time signature on, it clicks on every
    /// bottom-number note instead, so 6/8 at 120 clicks eighth notes at 240 a minute.
    private var clicksPerMinute: Double {
        accentEnabled ? Double(tempo) * Double(beatUnit) / 4 : Double(tempo)
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - 32
            // One column of a four-column grid (16pt gaps).
            let columnWidth = (contentWidth - 48) / 4
            // The preset grid takes two thirds; the right-hand third lines up above and below it.
            let leftWidth = (contentWidth - gridSpacing) * 2 / 3

            VStack(spacing: 16) {
                topRow(columnWidth: columnWidth)
                    .frame(height: geometry.size.height / 16)
                VStack(spacing: gridSpacing) {
                    timeSignatureRow(leftWidth: leftWidth, height: geometry.size.height / 12)
                    presetRow(leftWidth: leftWidth)
                }

                Spacer(minLength: 0)

                tempoDisplay
                TempoSlider(value: $tempo, range: tempoRange, color: palette.text) { isSliding = $0 }
                    .wobbly("slider")

                Spacer(minLength: 0)

                soundRow
                    .frame(height: 44)
                startStopButton
                    .frame(height: geometry.size.height / 4)
                    .wobbly("startStop")
            }
            .padding()
        }
        .environment(wobble)
        .background(palette.background.ignoresSafeArea())
        .overlay { popup }
        .preferredColorScheme(palette.scheme)
        .transaction { $0.animation = nil }
        .onAppear {
            metronome.setSound(sound)
            metronome.setBar(beats: beatsPerBar, accented: accentEnabled)
            metronome.setRate(clicksPerMinute)
        }
        .onChange(of: clicksPerMinute) {
            metronome.setRate(clicksPerMinute)
        }
        .onChange(of: beatsPerBar) {
            metronome.setBar(beats: beatsPerBar, accented: accentEnabled)
        }
        .onChange(of: accentEnabled) {
            metronome.setBar(beats: beatsPerBar, accented: accentEnabled)
        }
        .onChange(of: sound) {
            metronome.setSound(sound)
        }
    }

    // MARK: - Rows

    private func topRow(columnWidth: CGFloat) -> some View {
        HStack {
            // Lit only when there's something to reset.
            tile("RESET", isOn: !isAtDefaults, action: resetAll)
                .opacity(isAtDefaults ? 0.5 : 1)
                .disabled(isAtDefaults)
                .frame(width: columnWidth)
                .wobbly("reset")

            Spacer()

            PressButton(action: wobble.tap) {
                CapText(text: "METRONOME APP", size: 15, tracking: 3)
                    .foregroundStyle(palette.text)
                    .extraBold(palette.text, amount: 0.4)
                    .padding(.vertical, 12)
            }
            .wobbly("title", fallsLast: true)

            Spacer()

            PressButton(action: nextPalette) {
                // Shows the current palette as four stripes.
                HStack(spacing: 0) {
                    ForEach(palette.swatch.indices, id: \.self) { i in
                        Rectangle().fill(palette.swatch[i])
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.text, lineWidth: 1))
            }
            .frame(width: columnWidth)
            .accessibilityLabel("Change colour palette")
            .wobbly("palette")
        }
    }

    /// The time signature above the presets, and its on/off toggle above tap tempo.
    /// The digits are sized to fill the row's height.
    private func timeSignatureRow(leftWidth: CGFloat, height: CGFloat) -> some View {
        let fontSize = height * 0.7 / Font.analogueCapHeightRatio

        return HStack(spacing: gridSpacing) {
            HStack(spacing: gridSpacing) {
                // Top number: any whole number, typed on the keypad.
                PressButton(action: { editingField = .beats }) {
                    CapText(text: String(beatsPerBar), size: fontSize, widthOf: "88")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .editableHighlight(palette.text)
                }
                .accessibilityLabel("Beats per bar, \(beatsPerBar)")
                .wobbly("beats")

                CapText(text: "/", size: fontSize)
                    .wobbly("slash")

                // Bottom number: powers of two only, so pick from a list.
                PressButton(action: { editingField = .beatUnit }) {
                    CapText(text: String(beatUnit), size: fontSize, widthOf: "88")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .editableHighlight(palette.text)
                }
                .accessibilityLabel("Note value, \(beatUnit)")
                .wobbly("beatUnit")
            }
            .foregroundStyle(palette.text)
            .opacity(accentEnabled ? 1 : 0.4)
            .frame(width: leftWidth)

            tile(accentEnabled ? "ON" : "OFF", isOn: accentEnabled) {
                accentEnabled.toggle()
            }
            .accessibilityLabel("Time signature")
            .wobbly("accent")
        }
        .frame(height: height)
    }

    /// Presets in two rows of four (two thirds), and tap tempo (one third).
    private func presetRow(leftWidth: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 4)

        return HStack(spacing: gridSpacing) {
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(presets, id: \.self) { preset in
                    // Not lit mid-drag, so presets don't flash as the slider passes them.
                    tile(String(preset), isOn: !isSliding && tempo == preset) { tempo = preset }
                        .frame(height: 40)
                        .wobbly("preset\(preset)")
                }
            }
            .frame(width: leftWidth)

            tile("TAP TO SET", isOn: false, fontSize: 18, action: tapTempo)
                .wobbly("tap")
        }
        .frame(height: 40 * 2 + gridSpacing)
    }

    private var tempoDisplay: some View {
        VStack(spacing: 4) {
            HStack {
                stepButton(systemImage: "minus", by: -1)
                    .wobbly("minus")

                Spacer()

                PressButton(action: { editingField = .tempo }) {
                    // Fixed three-digit width, so any tempo sits centred and the layout never shifts.
                    CapText(text: String(tempo), size: tempoFontSize, widthOf: "888")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .editableHighlight(palette.text)
                }
                .accessibilityLabel("Tempo, \(tempo) BPM")
                .wobbly("tempo")

                Spacer()

                stepButton(systemImage: "plus", by: 1)
                    .wobbly("plus")
            }

            Text("BPM")
                .font(.analogue(size: 22))
                .tracking(4)
                .wobbly("bpm")
        }
        .foregroundStyle(palette.text)
    }

    private var soundRow: some View {
        HStack(spacing: 8) {
            ForEach(ClickSound.allCases) { option in
                tile(option.name.uppercased(), isOn: sound == option) {
                    sound = option
                }
                .wobbly("sound\(option.rawValue)")
            }
        }
    }

    private var startStopButton: some View {
        PressButton(action: toggleRunning) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isRunning ? palette.stop : palette.start)
                .overlay {
                    let color = isRunning ? palette.stopText : palette.startText
                    CapText(text: isRunning ? "STOP" : "START", size: 64, tracking: 6)
                        .foregroundStyle(color)
                        .extraBold(color, amount: 1.2)
                }
        }
    }

    @ViewBuilder private var popup: some View {
        switch editingField {
        case .tempo:
            Keypad(
                title: "TEMPO (BPM)", value: tempo, range: tempoRange, palette: palette,
                onCommit: { tempo = $0; editingField = nil },
                onCancel: { editingField = nil }
            )
        case .beats:
            Keypad(
                title: "BEATS PER BAR", value: beatsPerBar, range: beatsRange, palette: palette,
                onCommit: { beatsPerBar = $0; editingField = nil },
                onCancel: { editingField = nil }
            )
        case .beatUnit:
            ChoicePad(
                title: "NOTE VALUE", options: beatUnits, selected: beatUnit, palette: palette,
                onSelect: { beatUnit = $0; editingField = nil },
                onCancel: { editingField = nil }
            )
        case nil:
            EmptyView()
        }
    }

    // MARK: - Pieces

    /// A rounded button that shows the start colour while it's on.
    private func tile(
        _ title: String, isOn: Bool, fontSize: CGFloat = 16, action: @escaping () -> Void
    ) -> some View {
        PressButton(action: action) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isOn ? palette.start : palette.control)
                .overlay {
                    CapText(text: title, size: fontSize, tracking: 1)
                        .foregroundStyle(isOn ? palette.startText : palette.controlText)
                }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func stepButton(systemImage: String, by delta: Int) -> some View {
        PressButton(repeats: true, action: { step(by: delta) }) {
            Circle()
                .fill(palette.control)
                .frame(width: stepButtonSize, height: stepButtonSize)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(palette.controlText)
                }
        }
        .accessibilityLabel(delta > 0 ? "Increase tempo" : "Decrease tempo")
    }

    // MARK: - Actions

    private func toggleRunning() {
        if isRunning {
            metronome.stop()
            isRunning = false
        } else {
            do {
                try metronome.start(clicksPerMinute: clicksPerMinute)
                isRunning = true
            } catch {
                print("Failed to start audio: \(error)")
            }
        }
    }

    private func step(by delta: Int) {
        tempo = clamped(tempo + delta, to: tempoRange)
    }

    private func resetAll() {
        tempo = Self.defaultTempo
        beatsPerBar = Self.defaultBeats
        beatUnit = Self.defaultBeatUnit
        accentEnabled = false
    }

    private func nextPalette() {
        paletteIndex = (paletteIndex + 1) % Palette.all.count
    }

    /// Sets the tempo from the average gap between the last few taps.
    private func tapTempo() {
        let now = Date()
        // A long pause starts a fresh measurement.
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2 {
            tapTimes.removeAll()
        }
        tapTimes = Array((tapTimes + [now]).suffix(5))

        guard tapTimes.count >= 2, let first = tapTimes.first else { return }
        let interval = now.timeIntervalSince(first) / Double(tapTimes.count - 1)
        tempo = clamped(Int((60 / interval).rounded()), to: tempoRange)
    }

    private func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension View {
    /// A faint rounded box marking something you can tap to edit.
    func editableHighlight(_ color: Color) -> some View {
        background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
    }

    /// DIN Alternate only comes in one weight, so thicken it by redrawing it slightly offset.
    func extraBold(_ color: Color, amount: CGFloat) -> some View {
        shadow(color: color, radius: 0, x: amount, y: 0)
            .shadow(color: color, radius: 0, x: -amount, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: amount / 2)
    }
}

extension Font {
    static let analogueName = "DINAlternate-Bold"

    /// How tall capital letters and digits are, as a fraction of the font size.
    static let analogueCapHeightRatio: CGFloat = UIFont(name: analogueName, size: 100).map { $0.capHeight / 100 } ?? 0.7

    /// DIN Alternate: the plain, engineered lettering of gauges and hardware panels.
    static func analogue(size: CGFloat) -> Font {
        .custom(analogueName, size: size)
    }
}

#Preview {
    ContentView()
}
