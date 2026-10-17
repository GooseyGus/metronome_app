import AVFoundation
import Synchronization

/// Listens to the microphone for one short, sharp sound (a clap, a click, a "hey!"),
/// keeps it if it's short enough, and says why if it isn't. Also plays recordings back.
@Observable
final class SoundRecorder {
    enum Status {
        case idle, listening, noSound, tooQuiet, tooLong, accepted, noPermission, failed

        var message: String {
            switch self {
            case .idle: ""
            case .listening: "LISTENING… MAKE A SHORT, SHARP SOUND"
            case .noSound: "NO SOUND DETECTED"
            case .tooQuiet: "TOO QUIET: GET CLOSER OR BE LOUDER"
            case .tooLong: "TOO LONG: KEEP IT UNDER HALF A SECOND"
            case .accepted: "GOT IT! TAP THE WAVE TO HEAR IT"
            case .noPermission: "MICROPHONE ACCESS IS OFF: TURN IT ON IN SETTINGS"
            case .failed: "COULDN'T START THE MICROPHONE"
            }
        }

        /// Whether this is a problem the user should fix.
        var isWarning: Bool {
            switch self {
            case .noSound, .tooQuiet, .tooLong, .noPermission, .failed: true
            case .idle, .listening, .accepted: false
            }
        }
    }

    static let historyLength = 90

    private(set) var status = Status.idle
    /// Recent loudness from 0 to 1, oldest first, for the live waveform.
    private(set) var levels = [Float](repeating: 0, count: historyLength)
    private(set) var sampleRate = 48_000.0
    /// Whether a preview is playing round and round (until `stopPlaying`).
    private(set) var isLooping = false
    var isListening: Bool { detector?.isArmed == true }

    private var engine: AVAudioEngine?
    private var detector: Detector?
    /// Plays recordings back, separately from the microphone so it works without it.
    private var previewEngine: AVAudioEngine?
    private let previewPlayer = AVAudioPlayerNode()
    private var onCapture: (([Float]) -> Void)?
    private var lastHeard = Date()
    private var statusChanged = Date()
    private var watchdog: Task<Void, Never>?

    /// Starts listening, and calls `onCapture` with the sound once one is accepted.
    func listen(onCapture: @escaping ([Float]) -> Void) async {
        guard await AVAudioApplication.requestRecordPermission() else {
            setStatus(.noPermission)
            return
        }
        if engine == nil {
            do { try startEngine() } catch {
                setStatus(.failed)
                return
            }
        }
        self.onCapture = onCapture
        levels = [Float](repeating: 0, count: Self.historyLength)
        lastHeard = Date()
        setStatus(.listening)
        detector?.arm()
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.checkSilence()
            }
        }
    }

    func cancel() {
        detector?.disarm()
        watchdog?.cancel()
        setStatus(.idle)
    }

    /// Plays samples once, or with `loops`, over and over until stopped.
    func play(_ samples: [Float], recordedAt rate: Double, loops: Bool = false) {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }

        let engine = previewEngine ?? AVAudioEngine()
        if previewEngine == nil {
            engine.attach(previewPlayer)
            previewEngine = engine
        }
        // Reconnect at this recording's rate; the mixer converts it for the speaker.
        if previewPlayer.outputFormat(forBus: 0).sampleRate != rate || !engine.isRunning {
            previewPlayer.stop()
            engine.connect(previewPlayer, to: engine.mainMixerNode, format: format)
            do { try engine.start() } catch { return }
        }
        previewPlayer.stop()
        previewPlayer.scheduleBuffer(buffer, at: nil, options: loops ? .loops : [])
        previewPlayer.play()
        isLooping = loops
    }

    func stopPlaying() {
        previewPlayer.stop()
        isLooping = false
    }

    /// Turns the microphone off and puts the audio back how the metronome likes it.
    func shutdown() {
        cancel()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        detector = nil
        stopPlaying()
        previewEngine?.stop()
        Metronome.usePlaybackSession()
    }

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
        sampleRate = format.sampleRate

        let detector = Detector(sampleRate: format.sampleRate) { [weak self] update in
            Task { @MainActor in self?.apply(update) }
        }
        detector.install(on: input, format: format)
        try engine.start()

        self.engine = engine
        self.detector = detector
    }

    private func apply(_ update: Detector.Update) {
        levels = Array((levels + update.levels).suffix(Self.historyLength))
        guard status != .idle, status != .accepted else { return }
        if let captured = update.captured {
            watchdog?.cancel()
            setStatus(.accepted)
            onCapture?(Self.tidy(captured, sampleRate: sampleRate))
        } else if update.tooLong {
            lastHeard = Date()
            setStatus(.tooLong)
        } else if update.tooQuiet {
            lastHeard = Date()
            // A "too long" stays up a moment, rather than flicking straight to "too quiet".
            if status != .tooLong || Date().timeIntervalSince(statusChanged) > 1.5 { setStatus(.tooQuiet) }
        } else if update.heardSomething {
            lastHeard = Date()
            if status == .noSound { setStatus(.listening) }
        }
    }

    /// Clears warnings once they've had time to be read, and notices long silences.
    private func checkSilence() {
        let now = Date()
        if (status == .tooQuiet || status == .tooLong) && now.timeIntervalSince(statusChanged) > 2 {
            setStatus(.listening)
        }
        if status == .listening && now.timeIntervalSince(lastHeard) > 3 {
            setStatus(.noSound)
        }
    }

    private func setStatus(_ new: Status) {
        if new != status { statusChanged = Date() }
        status = new
    }

    /// Fades the very ends so it never clicks, and brings it up to full volume.
    private static func tidy(_ samples: [Float], sampleRate: Double) -> [Float] {
        let fadeIn = Int(sampleRate * 0.002), fadeOut = Int(sampleRate * 0.02)
        let peak = max(samples.map(abs).max() ?? 1, 0.001)
        return samples.enumerated().map { i, sample in
            let start = min(Float(i) / Float(fadeIn), 1)
            let end = min(Float(samples.count - i) / Float(fadeOut), 1)
            return sample / peak * 0.98 * start * end
        }
    }
}

/// Watches the microphone on the audio thread, in windows of about 10 ms.
/// Everything but the armed flag is only touched on that thread.
private nonisolated final class Detector: @unchecked Sendable {
    struct Update: Sendable {
        var levels: [Float] = []
        var heardSomething = false
        var tooQuiet = false
        var tooLong = false
        var captured: [Float]?
    }

    private enum Phase { case waiting, capturing, coolingDown }

    /// Loud enough to count as the sound (peak, full scale is 1).
    private let trigger: Float = 0.12
    /// Loud enough to notice, but not to count.
    private let noticeable: Float = 0.025

    private let windowLength: Int
    private let preRollLength: Int
    private let maxLength: Int
    private let silenceToEnd: Int
    private let silenceToReset: Int
    private let report: @Sendable (Update) -> Void

    private let armed = Atomic<Bool>(false)
    private let restart = Atomic<Bool>(false)
    private var phase = Phase.waiting
    private var window: [Float] = []
    private var preRoll: [Float] = []
    private var capture: [Float] = []
    private var capturePeak: Float = 0
    private var quietRun = 0

    init(sampleRate: Double, report: @escaping @Sendable (Update) -> Void) {
        windowLength = Int(sampleRate * 0.01)
        preRollLength = Int(sampleRate * 0.015)
        maxLength = Int(sampleRate * 0.5)
        silenceToEnd = Int(sampleRate * 0.08)
        silenceToReset = Int(sampleRate * 0.3)
        self.report = report
        window.reserveCapacity(windowLength)
    }

    var isArmed: Bool { armed.load(ordering: .relaxed) }

    func arm() {
        restart.store(true, ordering: .relaxed)
        armed.store(true, ordering: .releasing)
    }

    func disarm() {
        armed.store(false, ordering: .releasing)
    }

    func install(on input: AVAudioInputNode, format: AVAudioFormat) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [self] buffer, _ in
            process(buffer)
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard armed.load(ordering: .acquiring), let channel = buffer.floatChannelData?[0] else { return }
        if restart.exchange(false, ordering: .acquiring) {
            phase = .waiting
            window.removeAll(keepingCapacity: true)
            preRoll = []
            capture = []
            quietRun = 0
        }
        var update = Update()
        for i in 0..<Int(buffer.frameLength) {
            window.append(channel[i])
            if window.count == windowLength {
                handleWindow(&update)
                window.removeAll(keepingCapacity: true)
                if update.captured != nil { break }
            }
        }
        report(update)
    }

    private func handleWindow(_ update: inout Update) {
        let peak = window.map(abs).max() ?? 0
        update.levels.append(min(peak, 1))

        switch phase {
        case .waiting:
            if peak >= trigger {
                // Keep a sliver from just before, so the sound's attack isn't clipped.
                phase = .capturing
                capture = preRoll + window
                capturePeak = peak
                quietRun = 0
                update.heardSomething = true
            } else {
                if peak >= noticeable { update.tooQuiet = true }
                preRoll = Array((preRoll + window).suffix(preRollLength))
            }
        case .capturing:
            capture += window
            capturePeak = max(capturePeak, peak)
            if peak < max(noticeable, capturePeak * 0.1) { quietRun += window.count } else { quietRun = 0 }
            let soundLength = capture.count - quietRun
            if soundLength > maxLength {
                // Too long: wait for quiet before listening again.
                update.tooLong = true
                phase = .coolingDown
                capture = []
                quietRun = 0
            } else if quietRun >= silenceToEnd {
                // Done: keep a little of the tail as it fades.
                update.captured = Array(capture.prefix(soundLength + silenceToEnd / 4))
                armed.store(false, ordering: .releasing)
                phase = .waiting
            }
        case .coolingDown:
            if peak < noticeable * 2 { quietRun += window.count } else {
                quietRun = 0
                update.tooLong = true
            }
            if quietRun >= silenceToReset {
                phase = .waiting
                preRoll = []
                quietRun = 0
            }
        }
    }
}
