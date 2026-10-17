import SwiftUI

/// The pop-up for recording a new click sound, or editing one: a name, a beat, and
/// optionally a downbeat.
struct RecordSoundView: View {
    /// An existing sound to start from, when editing.
    struct Existing {
        let name: String
        let beat: [Float]
        let downbeat: [Float]?
        let sampleRate: Double
    }

    let palette: Palette
    private let title: String
    let onSave: (_ name: String, _ beat: [Float], _ downbeat: [Float]?, _ sampleRate: Double) -> Void
    let onCancel: () -> Void
    /// When editing, deletes the sound altogether.
    let onDelete: (() -> Void)?

    private enum Slot { case beat, downbeat }

    /// What the share button has brought up.
    private enum SharePrompt {
        /// Nothing to share until there's a beat.
        case needsBeat
        /// The sound, written to a file ready to send.
        case ready(URL)
        /// Sent (or saved) from the share sheet.
        case shared
    }

    @State private var recorder = SoundRecorder()
    @State private var name: String
    @State private var draftName = ""
    @State private var isRenaming = false
    @State private var suggestions = Array(SoundName.suggestions.shuffled().prefix(6))
    @State private var beat: [Float]?
    @State private var downbeat: [Float]?
    @State private var listeningFor: Slot?
    /// The rate the recordings held are at; a new take is converted to match the other.
    @State private var sampleRate: Double?
    @State private var nameSelection: TextSelection?
    /// A recording waiting for the user to confirm removing it.
    @State private var slotToClear: Slot?
    @State private var isConfirmingDelete = false
    @State private var sharePrompt: SharePrompt?
    @FocusState private var isNameFocused: Bool

    init(
        palette: Palette, defaultName: String, existing: Existing? = nil,
        onSave: @escaping (String, [Float], [Float]?, Double) -> Void, onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.palette = palette
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        title = existing == nil ? "NEW SOUND" : "EDIT SOUND"
        _name = State(initialValue: existing?.name ?? defaultName)
        _beat = State(initialValue: existing?.beat)
        _downbeat = State(initialValue: existing?.downbeat)
        _sampleRate = State(initialValue: existing?.sampleRate)
    }

    var body: some View {
        // Tapping outside does nothing, so a stray tap can't throw away a recording.
        let isShared = if case .shared = sharePrompt { true } else { false }
        let isMainScreen = !isRenaming && !isConfirmingDelete && sharePrompt == nil && slotToClear == nil
        PopupCard(
            // Once shared, the card is just the news, without the menu's own title above it.
            title: isShared ? "SHARED \(name.uppercased())" : title, subtitle: nil, palette: palette, onDismiss: {},
            accessory: isMainScreen ? AnyView(shareButton) : nil
        ) {
            if isRenaming {
                renamer
            } else if isConfirmingDelete {
                prompt("DELETE \(name.uppercased())?")
                Text("This can't be undone.").font(.analogue(size: 13)).opacity(0.6)
                HStack(spacing: 10) {
                    cardButton("CANCEL") { isConfirmingDelete = false }
                    cardButton("DELETE", isLit: true) { onDelete?() }
                }
            } else if let sharePrompt {
                sharePromptView(sharePrompt)
            } else if let slotToClear {
                // No warning that it's permanent: CANCEL on the whole sound still gets it back.
                let samples = (slotToClear == .beat ? beat : downbeat) ?? []
                prompt("REMOVE THE \(slotToClear == .beat ? "BEAT" : "DOWNBEAT")?")
                Waveform(levels: Waveform.levels(of: samples), color: palette.text)
                    .padding(.horizontal, 8)
                    .frame(height: 56)
                    .editableHighlight(palette.text)
                    .contentShape(Rectangle())
                    .onTapGesture { recorder.play(samples, recordedAt: sampleRate ?? recorder.sampleRate) }
                    .accessibilityLabel("Recording. Tap to hear it")
                HStack(spacing: 10) {
                    cardButton("CANCEL") { self.slotToClear = nil }
                    cardButton("REMOVE", isLit: true) {
                        if slotToClear == .beat { beat = nil } else { downbeat = nil }
                        recorder.cancel()
                        self.slotToClear = nil
                    }
                }
            } else {
                nameButton
                requirements
                slot(.beat)
                slot(.downbeat)
                Text(recorder.status.message)
                    .font(.analogue(size: 12))
                    .tracking(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(recorder.status.isWarning ? palette.start : palette.text)
                    .frame(height: 30)
                HStack(spacing: 10) {
                    cardButton("CANCEL", action: onCancel)
                    cardButton("SAVE", isLit: true, isEnabled: beat != nil) {
                        if let beat { onSave(name, beat, downbeat, sampleRate ?? recorder.sampleRate) }
                    }
                }
                if onDelete != nil {
                    cardButton("DELETE", isDestructive: true) {
                        recorder.cancel()
                        listeningFor = nil
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .onDisappear { recorder.shutdown() }
    }

    private func prompt(_ text: String) -> some View {
        Text(text)
            .font(.analogue(size: 16))
            .tracking(2)
            .multilineTextAlignment(.center)
    }

    // MARK: - Sharing

    private var shareButton: some View {
        PressButton(action: startSharing) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Share this sound")
    }

    private func startSharing() {
        recorder.cancel()
        listeningFor = nil
        guard let beat else {
            sharePrompt = .needsBeat
            return
        }
        let shared = SharedSound(name: name, beat: beat, downbeat: downbeat, sampleRate: sampleRate ?? recorder.sampleRate)
        if let url = try? shared.writeFile() { sharePrompt = .ready(url) }
    }

    @ViewBuilder private func sharePromptView(_ prompt: SharePrompt) -> some View {
        switch prompt {
        case .needsBeat:
            self.prompt("NOTHING TO SHARE YET")
            Text("A sound needs a beat. Record one, then share it.")
                .font(.analogue(size: 13))
                .multilineTextAlignment(.center)
                .opacity(0.6)
            cardButton("OK", isLit: true) { sharePrompt = nil }
        case .ready(let url):
            self.prompt("SHARE THIS SOUND?")
            if let beat {
                SoundSummary(
                    name: name, beat: beat, downbeat: downbeat,
                    sampleRate: sampleRate ?? recorder.sampleRate, palette: palette, player: recorder
                )
            }
            HStack(spacing: 10) {
                cardButton("CANCEL") {
                    recorder.stopPlaying()
                    sharePrompt = nil
                }
                // Sends it as a small file; opening it on another phone imports it.
                cardButton("SHARE", isLit: true) {
                    recorder.stopPlaying()
                    // Backing out of the share sheet just returns here.
                    ShareSheet.present(url) { sent in if sent { sharePrompt = .shared } }
                }
            }
        case .shared:
            cardButton("OKAY", isLit: true) { sharePrompt = nil }
        }
    }

    // MARK: - Name

    private var nameButton: some View {
        PressButton(action: startRenaming) {
            VStack(spacing: 6) {
                Text("NAME").font(.analogue(size: 11)).tracking(2).opacity(0.6)
                CapText(text: name.uppercased(), size: 22, tracking: 1)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .editableHighlight(palette.text)
        }
        .accessibilityLabel("Name, \(name). Tap to rename")
    }

    private var renamer: some View {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        let isFriendly = SoundName.isFriendly(trimmed)

        return VStack(spacing: 12) {
            TextField("NAME", text: $draftName, selection: $nameSelection)
                .font(.analogue(size: 22))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit { if isFriendly && !trimmed.isEmpty { finishRenaming() } }
                .onChange(of: draftName) {
                    // Capitals only, as names appear everywhere else.
                    let tidied = String(draftName.uppercased().prefix(CustomSounds.maxNameLength))
                    if tidied != draftName { draftName = tidied }
                }
                .padding(10)
                .editableHighlight(palette.text)

            Text(isFriendly ? "OR PICK ONE" : "LET'S KEEP IT FRIENDLY")
                .font(.analogue(size: 11))
                .tracking(2)
                .foregroundStyle(isFriendly ? palette.text.opacity(0.6) : palette.start)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    PressButton(action: { draftName = suggestion.uppercased() }) {
                        Text(suggestion.uppercased())
                            .font(.analogue(size: 11))
                            .tracking(1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity)
                            .editableHighlight(palette.text)
                    }
                }
            }

            HStack(spacing: 10) {
                cardButton("CANCEL") { isRenaming = false }
                cardButton("OK", isLit: true, isEnabled: isFriendly && !trimmed.isEmpty, action: finishRenaming)
            }
        }
    }

    private func startRenaming() {
        recorder.cancel()
        listeningFor = nil
        draftName = name.uppercased()
        // Start with it all selected, so typing replaces it.
        nameSelection = TextSelection(range: draftName.startIndex..<draftName.endIndex)
        isRenaming = true
        isNameFocused = true
    }

    private func finishRenaming() {
        name = draftName.trimmingCharacters(in: .whitespaces)
        isRenaming = false
    }

    // MARK: - Recording

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 6) {
            requirement(1, "SHORT: UNDER HALF A SECOND")
            requirement(2, "LOUD: A CLAP, A CLICK OR A \u{201C}HEY!\u{201D}")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requirement(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 8) {
            CapText(text: String(number), size: 11)
                .foregroundStyle(palette.background)
                .frame(width: 18, height: 18)
                .background(Circle().fill(palette.text))
            Text(text).font(.analogue(size: 12)).tracking(1)
        }
    }

    private func slot(_ slot: Slot) -> some View {
        let samples = slot == .beat ? beat : downbeat
        let isListening = listeningFor == slot
        // The downbeat waits for the beat (unless it's already recorded).
        let isEnabled = slot == .beat || beat != nil || downbeat != nil

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(slot == .beat ? "BEAT" : "DOWNBEAT").font(.analogue(size: 14)).tracking(2)
                if slot == .downbeat {
                    Text("OPTIONAL").font(.analogue(size: 11)).tracking(1).opacity(0.6)
                }
            }
            HStack(spacing: 10) {
                Group {
                    if isListening {
                        Waveform(levels: recorder.levels, color: palette.text)
                    } else if let samples {
                        Waveform(levels: Waveform.levels(of: samples), color: palette.text)
                    } else {
                        Text(slot == .beat ? "TAP REC TO START" : isEnabled ? "TAP REC TO ADD" : "RECORD THE BEAT FIRST")
                            .font(.analogue(size: 11))
                            .tracking(1)
                            .opacity(0.5)
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .editableHighlight(palette.text)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let samples, !isListening { recorder.play(samples, recordedAt: sampleRate ?? recorder.sampleRate) }
                }
                .accessibilityLabel(samples == nil ? "Empty" : "Recorded. Tap to hear it")
                .overlay(alignment: .topLeading) {
                    if samples != nil && !isListening {
                        PressButton(action: { slotToClear = slot }) {
                            DeleteBadge(palette: palette)
                        }
                        .offset(x: -8, y: -8)
                        .accessibilityLabel("Remove recording")
                    }
                }

                recordButton(slot, isListening: isListening, hasRecording: samples != nil)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }

    /// A big round button: REC to start, STOP while listening, REDO once recorded.
    private func recordButton(_ slot: Slot, isListening: Bool, hasRecording: Bool) -> some View {
        PressButton(action: { toggleListening(for: slot) }) {
            ZStack {
                Circle().fill(isListening ? palette.stop : palette.start)
                CapText(text: isListening ? "STOP" : hasRecording ? "REDO" : "REC", size: 12, tracking: 1)
                    .foregroundStyle(isListening ? palette.stopText : palette.startText)
            }
            .frame(width: 56, height: 56)
        }
        .accessibilityLabel(isListening ? "Stop listening" : hasRecording ? "Record again" : "Record")
    }

    private func toggleListening(for slot: Slot) {
        if listeningFor == slot {
            recorder.cancel()
            listeningFor = nil
            return
        }
        listeningFor = slot
        Task {
            await recorder.listen { recorded in
                // Keep both recordings at one rate, converting the new take if need be.
                let other = slot == .beat ? downbeat : beat
                var samples = recorded
                if let held = sampleRate, other != nil, held != recorder.sampleRate {
                    samples = Metronome.resample(recorded, from: recorder.sampleRate, to: held)
                } else {
                    sampleRate = recorder.sampleRate
                }
                if slot == .beat { beat = samples } else { downbeat = samples }
                listeningFor = nil
                recorder.play(samples, recordedAt: sampleRate ?? recorder.sampleRate)
            }
            // Couldn't start (no microphone access): nothing is listening.
            if !recorder.isListening && recorder.status != .accepted { listeningFor = nil }
        }
    }

    private func cardButton(
        _ title: String, isLit: Bool = false, isDestructive: Bool = false, isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        PressButton(action: action) {
            CardButton(title: title, palette: palette, isLit: isLit, isDestructive: isDestructive)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}

/// A full-width rounded button for the bottom of a pop-up card.
private struct CardButton: View {
    let title: String
    let palette: Palette
    var isLit = false
    var isDestructive = false

    var body: some View {
        let fill = isDestructive ? palette.stop : isLit ? palette.start : palette.control
        let ink = isDestructive ? palette.stopText : isLit ? palette.startText : palette.controlText
        RoundedRectangle(cornerRadius: 12)
            .fill(fill)
            .frame(height: 48)
            .overlay { CapText(text: title, size: 16, tracking: 1).foregroundStyle(ink) }
    }
}

/// A sound at a glance: its name, its waveforms (tap to hear them), and a button to
/// hear it in action at 120 BPM in 4/4.
private struct SoundSummary: View {
    let name: String
    let beat: [Float]
    let downbeat: [Float]?
    let sampleRate: Double
    let palette: Palette
    let player: SoundRecorder

    private let bpm = 120.0

    var body: some View {
        VStack(spacing: 10) {
            CapText(text: name.uppercased(), size: 22, tracking: 1)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .editableHighlight(palette.text)
            row("BEAT", beat)
            if let downbeat { row("DOWNBEAT", downbeat) }
            // Coloured like START/STOP: lit to play, the stop colour while it loops.
            let isPlaying = player.isLooping
            PressButton(action: togglePreview) {
                HStack(spacing: 8) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 12, weight: .bold))
                    CapText(text: isPlaying ? "STOP PREVIEW" : "PLAY PREVIEW", size: 14, tracking: 1)
                }
                .foregroundStyle(isPlaying ? palette.stopText : palette.startText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(isPlaying ? palette.stop : palette.start))
            }
            .accessibilityLabel(isPlaying ? "Stop preview" : "Play preview at 120 BPM in 4/4")
        }
        .onDisappear { player.stopPlaying() }
    }

    private func row(_ label: String, _ samples: [Float]) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.analogue(size: 11)).tracking(2).frame(width: 72, alignment: .leading)
            Waveform(levels: Waveform.levels(of: samples), color: palette.text)
                .padding(.horizontal, 8)
                .frame(height: 44)
                .editableHighlight(palette.text)
                .contentShape(Rectangle())
                .onTapGesture { player.play(samples, recordedAt: sampleRate) }
                .accessibilityLabel("\(label.lowercased()). Tap to hear it")
        }
    }

    /// Loops a bar of 4/4 at 120 BPM, or stops it.
    private func togglePreview() {
        if player.isLooping {
            player.stopPlaying()
        } else {
            player.play(Self.bar(beat: beat, downbeat: downbeat, beatsPerSecond: bpm / 60, sampleRate: sampleRate),
                        recordedAt: sampleRate, loops: true)
        }
    }

    /// One bar of 4/4, downbeat first if there is one. Exactly a bar long, with any
    /// tail wrapped round to the start, so it loops in perfect time.
    private static func bar(beat: [Float], downbeat: [Float]?, beatsPerSecond: Double, sampleRate: Double) -> [Float] {
        let beatLength = Int(sampleRate / beatsPerSecond)
        var out = [Float](repeating: 0, count: beatLength * 4)
        for index in 0..<4 {
            let click = index == 0 ? downbeat ?? beat : beat
            for (i, sample) in click.enumerated() { out[(index * beatLength + i) % out.count] += sample }
        }
        return out.map { max(-1, min(1, $0)) }
    }
}

/// Shown when a shared sound is opened: what it is, and whether to add it.
struct ImportSoundView: View {
    let palette: Palette
    let onImport: () -> Void
    let onCancel: () -> Void
    private let name: String
    private let beat: [Float]
    private let downbeat: [Float]?
    private let sampleRate: Double
    @State private var player = SoundRecorder()

    init(sound: SharedSound, palette: Palette, onImport: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.palette = palette
        self.onImport = onImport
        self.onCancel = onCancel
        name = sound.name
        beat = sound.beat
        downbeat = sound.downbeat
        sampleRate = sound.sampleRate
    }

    var body: some View {
        PopupCard(title: "IMPORT THIS SOUND?", subtitle: nil, palette: palette, onDismiss: onCancel) {
            SoundSummary(name: name, beat: beat, downbeat: downbeat, sampleRate: sampleRate, palette: palette, player: player)
            HStack(spacing: 10) {
                PressButton(action: onCancel) { CardButton(title: "CANCEL", palette: palette) }
                PressButton(action: onImport) { CardButton(title: "IMPORT", palette: palette, isLit: true) }
            }
        }
        .onDisappear { player.shutdown() }
    }
}

/// Loudness drawn as bars mirrored about the middle, like a recorder's level meter.
private struct Waveform: View {
    let levels: [Float]
    let color: Color

    /// A recording's loudness in 60 slices.
    static func levels(of samples: [Float]) -> [Float] {
        let slices = 60
        let size = max(samples.count / slices, 1)
        return stride(from: 0, to: samples.count, by: size).map { start in
            samples[start..<min(start + size, samples.count)].map(abs).max() ?? 0
        }
    }

    var body: some View {
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let step = size.width / CGFloat(levels.count)
            let barWidth = max(step * 0.6, 1)
            for (i, level) in levels.enumerated() {
                // Square-rooted so quiet sounds still show.
                let height = max(CGFloat(level.squareRoot()) * size.height, 1.5)
                let bar = CGRect(x: CGFloat(i) * step, y: (size.height - height) / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
        .padding(.vertical, 6)
    }
}

/// The system share sheet, which (unlike `ShareLink`) says whether something was sent.
private enum ShareSheet {
    static func present(_ url: URL, completion: @escaping (_ sent: Bool) -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }

        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        // On iPad it floats in the middle rather than pointing at anything.
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }
}
