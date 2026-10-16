import AVFoundation
import Synchronization

/// Plays a click on every beat. The click is generated on the audio thread by
/// counting samples, so timing is sample-accurate and tempo changes apply instantly.
final class Metronome {
    private let engine = AVAudioEngine()
    private let generator: ClickGenerator
    private let source: AVAudioSourceNode

    init() {
        // .playback keeps the click audible even with the silent switch on.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        // Activate asynchronously; the synchronous setActive can block the main thread.
        session.activate { success, error in
            if !success { print("Failed to activate audio session: \(String(describing: error))") }
        }

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate > 0 ? sampleRate : 44_100, channels: 1)!
        generator = ClickGenerator(sampleRate: format.sampleRate)
        source = AVAudioSourceNode(format: format, renderBlock: generator.makeRenderBlock())
        engine.attach(source)
        try? engine.connectNode(source, to: engine.mainMixerNode, format: format)
    }

    func start(clicksPerMinute: Double) throws {
        generator.setRate(clicksPerMinute)
        // The engine keeps running (outputting silence) after the first start,
        // so later starts are instant.
        if !engine.isRunning { try engine.start() }
        generator.start()
    }

    func stop() {
        generator.stop()
    }

    func setRate(_ clicksPerMinute: Double) {
        generator.setRate(clicksPerMinute)
    }

    func setSound(_ sound: ClickSound) {
        generator.setSound(sound)
    }

    /// With `accented`, the first of every `beats` clicks is pitched up.
    func setBar(beats: Int, accented: Bool) {
        generator.setBar(beats: beats, accented: accented)
    }
}

/// Renders the click. Settings are shared with the main thread through atomics;
/// `framesSinceBeat` and `beatInBar` are only ever touched on the audio thread.
nonisolated final class ClickGenerator: @unchecked Sendable {
    private let sampleRate: Double
    // Indexed by ClickSound.rawValue.
    private let clicks: [[Float]]
    private let accentClicks: [[Float]]
    private let samplesPerBeat = Atomic<Int>(22_050)
    private let soundIndex = Atomic<Int>(0)
    private let beatsPerBar = Atomic<Int>(4)
    private let isAccented = Atomic<Bool>(false)
    private let isPlaying = Atomic<Bool>(false)
    private let restartRequested = Atomic<Bool>(false)
    private var framesSinceBeat = 0
    private var beatInBar = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        clicks = ClickSound.allCases.map { $0.samples(sampleRate: sampleRate, accented: false) }
        accentClicks = ClickSound.allCases.map { $0.samples(sampleRate: sampleRate, accented: true) }
    }

    func setRate(_ clicksPerMinute: Double) {
        samplesPerBeat.store(max(Int(sampleRate * 60 / clicksPerMinute), 1), ordering: .relaxed)
    }

    func setSound(_ sound: ClickSound) {
        soundIndex.store(sound.rawValue, ordering: .relaxed)
    }

    func setBar(beats: Int, accented: Bool) {
        beatsPerBar.store(beats, ordering: .relaxed)
        isAccented.store(accented, ordering: .relaxed)
    }

    func start() {
        restartRequested.store(true, ordering: .releasing)
        isPlaying.store(true, ordering: .releasing)
    }

    func stop() {
        isPlaying.store(false, ordering: .releasing)
    }

    func makeRenderBlock() -> AVAudioSourceNodeRenderBlock {
        { [self] _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let out = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            render(into: out, frameCount: Int(frameCount))
            return noErr
        }
    }

    private func render(into out: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard isPlaying.load(ordering: .acquiring) else {
            out.update(repeating: 0, count: frameCount)
            return
        }
        // Starting plays the first click immediately.
        if restartRequested.exchange(false, ordering: .acquiring) {
            framesSinceBeat = 0
            beatInBar = 0
        }
        let beatLength = samplesPerBeat.load(ordering: .relaxed)
        let sound = soundIndex.load(ordering: .relaxed)
        let beats = beatsPerBar.load(ordering: .relaxed)
        let accented = isAccented.load(ordering: .relaxed)
        for i in 0..<frameCount {
            if framesSinceBeat >= beatLength {
                framesSinceBeat = 0
                beatInBar += 1
            }
            if beatInBar >= beats { beatInBar = 0 }
            let click = accented && beatInBar == 0 ? accentClicks[sound] : clicks[sound]
            out[i] = framesSinceBeat < click.count ? click[framesSinceBeat] : 0
            framesSinceBeat += 1
        }
    }
}
