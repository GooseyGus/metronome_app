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
    @State private var dancerMove = 0
    @State private var movesDanced: Set<Int> = []
    @State private var lastMoveDanced: Int?
    @State private var partnerLandingTime: Date?
    @Environment(\.scenePhase) private var scenePhase
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

    /// Sizes that differ between portrait, the shorter iPhone landscape screen, and iPad.
    private struct Metrics {
        var spacing: CGFloat = 16
        var verticalPadding: CGFloat = 16
        var presetHeight: CGFloat = 40
        var soundHeight: CGFloat = 44
        var tempoFontSize: CGFloat = 88
        var bpmLabelSize: CGFloat = 22
        var stepButtonSize: CGFloat = 80
        var startStopFontSize: CGFloat = 64
        var titleFontSize: CGFloat = 15
        var scale: CGFloat = 1

        static let portrait = Metrics()
        static let landscape = Metrics(
            spacing: 8, verticalPadding: 8, presetHeight: 30, soundHeight: 34,
            tempoFontSize: 60, bpmLabelSize: 16, stepButtonSize: 56, startStopFontSize: 40
        )

        static func forSize(_ size: CGSize) -> Metrics {
            // Only a phone on its side is short enough to need the compact sizes.
            if size.height < 500 { return landscape }
            // Bigger screens (iPad) scale everything up, relative to an iPhone, as far as
            // the height allows. Landscape needs less height, as START/STOP moves to the side.
            let heightAtNormalSize: CGFloat = size.width > size.height ? 520 : 760
            let fit = min(size.width / 393, size.height / heightAtNormalSize)
            let scale = min(max(fit, 1), 1.8)
            return Metrics(
                spacing: 16 * scale, verticalPadding: 16 * scale,
                presetHeight: 40 * scale, soundHeight: 44 * scale,
                tempoFontSize: 88 * scale, bpmLabelSize: 22 * scale,
                stepButtonSize: 80 * scale, startStopFontSize: 64 * scale,
                titleFontSize: 15 * scale, scale: scale
            )
        }
    }

    private var palette: Palette { Palette.all[paletteIndex % Palette.all.count] }

    private var isAtDefaults: Bool {
        tempo == Self.defaultTempo && beatsPerBar == Self.defaultBeats
            && beatUnit == Self.defaultBeatUnit && !accentEnabled && !wobble.dancerUnlocked
    }

    /// BPM counts quarter notes. With the time signature on, it clicks on every
    /// bottom-number note instead, so 6/8 at 120 clicks eighth notes at 240 a minute.
    private var clicksPerMinute: Double {
        accentEnabled ? Double(tempo) * Double(beatUnit) / 4 : Double(tempo)
    }

    var body: some View {
        GeometryReader { geometry in
            // Sideways, START/STOP moves to a column on the right and everything else shifts left.
            let isLandscape = geometry.size.width > geometry.size.height
            let m = Metrics.forSize(geometry.size)
            let fullWidth = geometry.size.width - 32
            let startStopWidth = fullWidth / 4
            let contentWidth = isLandscape ? fullWidth - startStopWidth - 16 : fullWidth
            // One column of a four-column grid (16pt gaps).
            let columnWidth = (contentWidth - 48) / 4
            // The preset grid takes two thirds; the right-hand third lines up above and below it.
            let leftWidth = (contentWidth - gridSpacing) * 2 / 3

            let controls = VStack(spacing: m.spacing) {
                topRow(columnWidth: columnWidth, height: geometry.size.height / 16, titleSize: m.titleFontSize)
                VStack(spacing: gridSpacing) {
                    timeSignatureRow(leftWidth: leftWidth, height: geometry.size.height / 12)
                    presetRow(leftWidth: leftWidth, tileHeight: m.presetHeight)
                }

                Spacer(minLength: 0)

                tempoDisplay(m)
                TempoSlider(value: $tempo, range: tempoRange, color: palette.text) { isSliding = $0 }
                    .wobbly("slider")

                Spacer(minLength: 0)

                soundRow
                    .frame(height: m.soundHeight)
            }

            ZStack {
                Group {
                    if isLandscape {
                        HStack(spacing: 16) {
                            controls
                            // Shrink the label if needed so it fits the narrower column.
                            startStopButton(fontSize: min(m.startStopFontSize, startStopWidth * 0.2))
                                .frame(width: startStopWidth)
                                .wobbly("startStop")
                        }
                    } else {
                        VStack(spacing: m.spacing) {
                            controls
                            startStopButton(fontSize: m.startStopFontSize)
                                .frame(height: geometry.size.height / 4)
                                .wobbly("startStop")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, m.verticalPadding)

                popup
            }
            .environment(\.uiScale, m.scale)
        }
        .environment(wobble)
        .background(palette.background.ignoresSafeArea())
        .preferredColorScheme(palette.scheme)
        .transaction { $0.animation = nil }
        .onAppear {
            metronome.onInterruption = { isRunning = false }
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
        .onChange(of: scenePhase) {
            // Keep playing in the background if running; otherwise let the app sleep.
            if scenePhase == .background { metronome.pauseIfIdle() }
        }
    }

    // MARK: - Rows

    private func topRow(columnWidth: CGFloat, height: CGFloat, titleSize: CGFloat) -> some View {
        HStack {
            // Lit only when there's something to reset.
            tile("RESET", isOn: !isAtDefaults, action: resetAll)
                .opacity(isAtDefaults ? 0.5 : 1)
                .disabled(isAtDefaults)
                .frame(width: columnWidth)
                .wobbly("reset")

            Spacer()

            // While running, the title becomes a little metronome ticking in time.
            // Tapping the dancer changes its move instead of shaking everything.
            PressButton(action: {
                if isRunning && wobble.dancerUnlocked {
                    dancerMove = (dancerMove + 1) % DancerGlyph.moveCount
                } else {
                    wobble.tap()
                }
            }) {
                Group {
                    // Once unlocked, the dancer replaces the title too, idling until START.
                    if wobble.dancerUnlocked {
                        DancerGlyph(
                            metronome: metronome, palette: palette, isPlaying: isRunning,
                            landingTime: wobble.dancerLandingTime,
                            beatsPerBar: accentEnabled ? beatsPerBar : nil, moveOffset: dancerMove,
                            partnerLandingTime: partnerLandingTime, onMove: noteMoveDanced
                        )
                        .frame(width: height * DancerGlyph.aspectRatio(withPartner: partnerLandingTime != nil))
                    } else if isRunning {
                        MetronomeGlyph(metronome: metronome, palette: palette)
                            .frame(width: height * 0.9)
                    } else {
                        CapText(text: "METRONOME APP", size: titleSize, tracking: 3)
                            .foregroundStyle(palette.text)
                            .extraBold(palette.text, amount: 0.4)
                    }
                }
                .frame(maxHeight: .infinity)
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
        .frame(height: height)
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
    private func presetRow(leftWidth: CGFloat, tileHeight: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 4)

        return HStack(spacing: gridSpacing) {
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(presets, id: \.self) { preset in
                    // Not lit mid-drag, so presets don't flash as the slider passes them.
                    tile(String(preset), isOn: !isSliding && tempo == preset) { tempo = preset }
                        .frame(height: tileHeight)
                        .wobbly("preset\(preset)")
                }
            }
            .frame(width: leftWidth)

            tile("TAP TO SET", isOn: false, fontSize: 18, action: tapTempo)
                .wobbly("tap")
        }
        .frame(height: tileHeight * 2 + gridSpacing)
    }

    private func tempoDisplay(_ m: Metrics) -> some View {
        VStack(spacing: 4) {
            HStack {
                stepButton(systemImage: "minus", by: -1, size: m.stepButtonSize)
                    .wobbly("minus")

                Spacer()

                PressButton(action: { editingField = .tempo }) {
                    // Fixed three-digit width, so any tempo sits centred and the layout never shifts.
                    CapText(text: String(tempo), size: m.tempoFontSize, widthOf: "888")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .editableHighlight(palette.text)
                }
                .accessibilityLabel("Tempo, \(tempo) BPM")
                .wobbly("tempo")

                Spacer()

                stepButton(systemImage: "plus", by: 1, size: m.stepButtonSize)
                    .wobbly("plus")
            }

            Text("BPM")
                .font(.analogue(size: m.bpmLabelSize))
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

    private func startStopButton(fontSize: CGFloat) -> some View {
        PressButton(action: toggleRunning) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isRunning ? palette.stop : palette.start)
                .overlay {
                    let color = isRunning ? palette.stopText : palette.startText
                    CapText(text: isRunning ? "STOP" : "START", size: fontSize, tracking: 6)
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
                // Confirming either number switches the time signature on.
                onCommit: { beatsPerBar = $0; accentEnabled = true; editingField = nil },
                onCancel: { editingField = nil }
            )
        case .beatUnit:
            ChoicePad(
                title: "NOTE VALUE", options: beatUnits, selected: beatUnit, palette: palette,
                onSelect: { beatUnit = $0; accentEnabled = true; editingField = nil },
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
                    TileLabel(text: title, size: fontSize)
                        .foregroundStyle(isOn ? palette.startText : palette.controlText)
                }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func stepButton(systemImage: String, by delta: Int, size: CGFloat) -> some View {
        PressButton(repeats: true, action: { step(by: delta) }) {
            Circle()
                .fill(palette.control)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.4, weight: .bold))
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
            if wobble.dancerUnlocked { pickNewDance() }
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
        wobble.resetDancer()
        dancerMove = 0
        movesDanced = []
        lastMoveDanced = nil
        partnerLandingTime = nil
    }

    /// Each START opens with a random dance, never the one they were just doing.
    /// The bar count restarts at START, so the opening move is the offset itself.
    private func pickNewDance() {
        let choices = (0..<DancerGlyph.moveCount).filter { $0 != lastMoveDanced }
        dancerMove = choices.randomElement() ?? 0
    }

    /// Once every move has been danced, a partner drops in to join.
    private func noteMoveDanced(_ move: Int) {
        lastMoveDanced = move
        guard partnerLandingTime == nil else { return }
        movesDanced.insert(move)
        if movesDanced.count == DancerGlyph.moveCount {
            partnerLandingTime = Date().addingTimeInterval(DancerGlyph.partnerDropDuration)
        }
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

/// A tile's label, drawn bigger on larger screens.
private struct TileLabel: View {
    let text: String
    let size: CGFloat
    @Environment(\.uiScale) private var scale

    var body: some View {
        CapText(text: text, size: size * scale, tracking: scale)
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
