import SwiftUI

struct ContentView: View {
    private enum Field { case tempo, beats, beatUnit }
    private enum ImportProblem { case full, unreadable }

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
    @State private var customSounds = CustomSounds()
    @State private var isRecordingSound = false
    /// How much to enlarge pop-ups, matching the controls (bigger on iPad).
    @State private var popupScale: CGFloat = 1
    @State private var soundToEdit: CustomSound?
    /// A shared sound that's been opened, waiting to be imported.
    @State private var soundToImport: SharedSound?
    @State private var importProblem: ImportProblem?
    /// Set to scroll the sound row, e.g. to a newly recorded sound.
    @State private var soundRowTarget: String?
    @Environment(\.scenePhase) private var scenePhase
    // Settings remembered between launches.
    @AppStorage("tempo") private var tempo = defaultTempo
    @AppStorage("paletteIndex") private var paletteIndex = 0
    @AppStorage("soundChoice") private var soundChoice = SoundChoice.builtIn(.classic)
    @AppStorage("accentEnabled") private var accentEnabled = false
    @AppStorage("beatsPerBar") private var beatsPerBar = defaultBeats
    @AppStorage("beatUnit") private var beatUnit = defaultBeatUnit

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

                soundRow(width: contentWidth)
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
            }
            .environment(\.uiScale, m.scale)
            .onChange(of: m.scale, initial: true) { popupScale = m.scale }
        }
        // The keyboard (for naming a sound) floats over the controls instead of squashing
        // them; the pop-up, laid over the top, still moves up out of its way.
        .ignoresSafeArea(.keyboard)
        .overlay { popup.environment(\.uiScale, popupScale) }
        .environment(wobble)
        .background(palette.background.ignoresSafeArea())
        .preferredColorScheme(palette.scheme)
        .transaction { $0.animation = nil }
        .onAppear {
            metronome.onInterruption = { isRunning = false }
            applySound()
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
        .onChange(of: soundChoice) {
            applySound()
        }
        // Opening a shared .metrosound file (from Messages, AirDrop, Files...).
        .onOpenURL { url in
            guard url.pathExtension == SharedSound.fileExtension else { return }
            if customSounds.isFull {
                importProblem = .full
            } else if let sound = SharedSound.read(from: url) {
                if isRunning { toggleRunning() }
                soundToImport = sound
            } else {
                importProblem = .unreadable
            }
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
                            move: dancerMove, clicksPerMinute: clicksPerMinute,
                            partnerLandingTime: partnerLandingTime, onMove: noteMoveDanced
                        )
                        .frame(width: height * DancerGlyph.aspectRatio(withPartner: partnerLandingTime != nil))
                    } else if isRunning {
                        MetronomeGlyph(metronome: metronome, palette: palette, clicksPerMinute: clicksPerMinute)
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
            .opacity(accentAvailable ? 1 : 0.4)
            .disabled(!accentAvailable)
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

    /// Every click sound in a row that scrolls sideways, then the user's own, then a
    /// button to record another. Three fit at once, with the next peeking in to show
    /// there are more.
    private func soundRow(width: CGFloat) -> some View {
        let tileWidth = (width - 8 * 3) / 3.4
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ClickSound.allCases) { option in
                        let choice = SoundChoice.builtIn(option)
                        soundTile(option.name.uppercased(), isOn: soundChoice == choice, minWidth: tileWidth) {
                            soundChoice = choice
                        }
                        .id(choice.rawValue)
                        .wobbly("sound\(option.rawValue)")
                    }
                    // A thin rule sets the user's own sounds apart from the built-in ones.
                    Capsule()
                        .fill(palette.text.opacity(0.3))
                        .frame(width: 2)
                        .padding(.vertical, 8)
                        .wobbly("soundDivider")
                    ForEach(customSounds.all) { custom in
                        customSoundTile(custom, minWidth: tileWidth)
                            .id(SoundChoice.custom(custom.id).rawValue)
                            .wobbly("custom-\(custom.id)")
                    }
                    if !customSounds.isFull {
                        addSoundTile(width: tileWidth * 0.6)
                            .id("add")
                            .wobbly("addSound")
                    }
                }
            }
            // Let knocked-off tiles tumble down the screen rather than vanish at the
            // row's edge, and leave room for the delete badges.
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(soundChoice.rawValue, anchor: .center) }
            .onChange(of: soundRowTarget) {
                guard let soundRowTarget else { return }
                withAnimation { proxy.scrollTo(soundRowTarget, anchor: .center) }
                self.soundRowTarget = nil
            }
        }
    }

    /// Like `tile`, but sized to fit its name and selected on release, so dragging
    /// across the row scrolls it instead of picking whatever the finger landed on.
    /// `isRecorded` marks the user's own sounds with a small dot, like a recording light.
    private func soundTile(
        _ title: String, isOn: Bool, isRecorded: Bool = false, minWidth: CGFloat, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 7) {
            if isRecorded {
                Circle()
                    .fill(isOn ? palette.startText : palette.start)
                    .frame(width: 7, height: 7)
            }
            TileLabel(text: title, size: 16)
        }
        .foregroundStyle(isOn ? palette.startText : palette.controlText)
        .padding(.horizontal, 14)
        .frame(minWidth: minWidth, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(isOn ? palette.start : palette.control))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// A recorded sound. Holding it or double tapping it opens it for editing.
    private func customSoundTile(_ custom: CustomSound, minWidth: CGFloat) -> some View {
        let choice = SoundChoice.custom(custom.id)
        return soundTile(custom.name.uppercased(), isOn: soundChoice == choice, isRecorded: true, minWidth: minWidth) {
            soundChoice = choice
        }
        .onLongPressGesture(minimumDuration: 0.15) { edit(custom) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { edit(custom) })
        .accessibilityAction(named: "Edit") { edit(custom) }
    }

    private func edit(_ custom: CustomSound) {
        if isRunning { toggleRunning() }
        soundToEdit = custom
    }

    /// A faint box with a plus, for recording a new sound.
    private func addSoundTile(width: CGFloat) -> some View {
        ZStack {
            Capsule().frame(width: 18, height: 3)
            Capsule().frame(width: 3, height: 18)
        }
        .foregroundStyle(palette.text)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .editableHighlight(palette.text)
        .contentShape(Rectangle())
        .onTapGesture {
            if isRunning { toggleRunning() }
            isRecordingSound = true
        }
        .accessibilityLabel("Record a new sound")
        .accessibilityAddTraits(.isButton)
    }

    /// Plays the chosen sound, falling back to Classic if a recording's gone missing.
    private func applySound() {
        switch soundChoice {
        case .builtIn(let sound):
            metronome.setSound(sound)
        case .custom(let id):
            guard let custom = customSounds.sound(id), let samples = customSounds.samples(for: id) else {
                soundChoice = .builtIn(.classic)
                return
            }
            metronome.setCustomSound(beat: samples.beat, downbeat: samples.downbeat, recordedAt: custom.sampleRate)
        }
        if !accentAvailable { accentEnabled = false }
    }

    /// A recorded sound without a downbeat has nothing to accent with, so the time signature stays off.
    private var accentAvailable: Bool {
        guard case .custom(let id) = soundChoice else { return true }
        return customSounds.sound(id)?.hasDownbeat ?? true
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
        if let importProblem {
            PopupCard(
                title: importProblem == .full ? "TOO MANY SOUNDS" : "CAN'T IMPORT THIS",
                subtitle: importProblem == .full
                    ? "You have \(CustomSounds.limit). Delete one, then import this sound."
                    : "This file isn't a sound this app can read.",
                palette: palette, onDismiss: { self.importProblem = nil }
            ) {
                tile("OK", isOn: true) { self.importProblem = nil }
                    .frame(height: 48)
            }
        } else if let soundToImport {
            ImportSoundView(
                sound: soundToImport, palette: palette,
                onImport: {
                    let sound = customSounds.add(
                        name: soundToImport.name, beat: soundToImport.beat,
                        downbeat: soundToImport.downbeat, sampleRate: soundToImport.sampleRate
                    )
                    soundChoice = .custom(sound.id)
                    self.soundToImport = nil
                    soundRowTarget = SoundChoice.custom(sound.id).rawValue
                },
                onCancel: { self.soundToImport = nil }
            )
        } else if isRecordingSound {
            RecordSoundView(
                palette: palette, defaultName: customSounds.nextDefaultName,
                onSave: { name, beat, downbeat, rate in
                    let sound = customSounds.add(name: name, beat: beat, downbeat: downbeat, sampleRate: rate)
                    soundChoice = .custom(sound.id)
                    isRecordingSound = false
                    soundRowTarget = SoundChoice.custom(sound.id).rawValue
                },
                onCancel: { isRecordingSound = false }
            )
        } else if let soundToEdit, let samples = customSounds.samples(for: soundToEdit.id) {
            RecordSoundView(
                palette: palette, defaultName: soundToEdit.name,
                existing: .init(
                    name: soundToEdit.name, beat: samples.beat, downbeat: samples.downbeat,
                    sampleRate: soundToEdit.sampleRate
                ),
                onSave: { name, beat, downbeat, rate in
                    customSounds.update(soundToEdit.id, name: name, beat: beat, downbeat: downbeat, sampleRate: rate)
                    self.soundToEdit = nil
                    // The choice hasn't changed, so pick up the new recordings by hand.
                    if soundChoice == .custom(soundToEdit.id) { applySound() }
                },
                onCancel: { self.soundToEdit = nil },
                onDelete: { delete(soundToEdit) }
            )
        } else {
            fieldPopup
        }
    }

    @ViewBuilder private var fieldPopup: some View {
        switch editingField {
        case .tempo:
            Keypad(
                title: "TEMPO (BPM)", value: tempo, range: tempoRange, palette: palette,
                onCommit: { tempo = $0; editingField = nil },
                onCancel: { editingField = nil }
            )
        case .beats:
            Keypad(
                title: "BEATS PER BAR", value: beatsPerBar, range: beatsRange, denominator: beatUnit, palette: palette,
                // Confirming either number switches the time signature on.
                onCommit: { beatsPerBar = $0; accentEnabled = accentAvailable; editingField = nil },
                onCancel: { editingField = nil }
            )
        case .beatUnit:
            ChoicePad(
                title: "NOTE VALUE", options: beatUnits, selected: beatUnit, numerator: beatsPerBar, palette: palette,
                onSelect: { beatUnit = $0; accentEnabled = accentAvailable; editingField = nil },
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

    /// Removes a recorded sound; the ones after it close up the gap.
    private func delete(_ custom: CustomSound) {
        customSounds.delete(custom.id)
        if soundChoice == .custom(custom.id) { soundChoice = .builtIn(.classic) }
        soundToEdit = nil
    }

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
        if let last = tapTimes.last, let first = tapTimes.first {
            let gap = now.timeIntervalSince(last)
            // Over a minute apart is slower than 1 BPM, so start a fresh measurement.
            if gap > 60 {
                tapTimes.removeAll()
            } else if tapTimes.count >= 2 {
                // A gap far off the tapped tempo means a new tempo: measure from the last tap.
                let average = last.timeIntervalSince(first) / Double(tapTimes.count - 1)
                if gap > average * 2 || gap < average / 2 { tapTimes = [last] }
            }
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
