import AVFoundation
import Darwin
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

    /// How many beats have been heard since START, including the fraction of the
    /// current beat, so visuals can follow the audio exactly. Nil until the first sound.
    func beatPhase() -> Double? {
        // Compensate for the delay between rendering audio and hearing it.
        let latency = AVAudioSession.sharedInstance().outputLatency
        return generator.beatPhase(atSeconds: HostClock.now - latency)
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
    // Where the beat was at the start of the latest buffer, and when that buffer plays.
    private let phaseBits = Atomic<UInt64>(0)
    private let phaseHostTime = Atomic<UInt64>(0)
    private var framesSinceBeat = 0
    private var beatInBar = 0
    private var beatsSinceStart = 0

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
        phaseHostTime.store(0, ordering: .releasing)
        restartRequested.store(true, ordering: .releasing)
        isPlaying.store(true, ordering: .releasing)
    }

    func stop() {
        isPlaying.store(false, ordering: .releasing)
    }

    func beatPhase(atSeconds seconds: Double) -> Double? {
        let hostTime = phaseHostTime.load(ordering: .acquiring)
        guard hostTime != 0 else { return nil }
        let phase = Double(bitPattern: phaseBits.load(ordering: .relaxed))
        let elapsed = seconds - HostClock.seconds(hostTime)
        return phase + elapsed * sampleRate / Double(samplesPerBeat.load(ordering: .relaxed))
    }

    func makeRenderBlock() -> AVAudioSourceNodeRenderBlock {
        { [self] _, timestamp, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let out = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            let hostTimeValid = timestamp.pointee.mFlags.contains(.hostTimeValid)
            let hostTime = hostTimeValid ? timestamp.pointee.mHostTime : mach_absolute_time()
            render(into: out, frameCount: Int(frameCount), hostTime: hostTime)
            return noErr
        }
    }

    private func render(into out: UnsafeMutablePointer<Float>, frameCount: Int, hostTime: UInt64) {
        guard isPlaying.load(ordering: .acquiring) else {
            out.update(repeating: 0, count: frameCount)
            return
        }
        // Starting plays the first click immediately.
        if restartRequested.exchange(false, ordering: .acquiring) {
            framesSinceBeat = 0
            beatInBar = 0
            beatsSinceStart = 0
        }
        let beatLength = samplesPerBeat.load(ordering: .relaxed)

        let phase = Double(beatsSinceStart) + Double(min(framesSinceBeat, beatLength)) / Double(beatLength)
        phaseBits.store(phase.bitPattern, ordering: .relaxed)
        phaseHostTime.store(hostTime, ordering: .releasing)

        let sound = soundIndex.load(ordering: .relaxed)
        let beats = beatsPerBar.load(ordering: .relaxed)
        let accented = isAccented.load(ordering: .relaxed)
        for i in 0..<frameCount {
            if framesSinceBeat >= beatLength {
                framesSinceBeat = 0
                beatInBar += 1
                beatsSinceStart += 1
            }
            if beatInBar >= beats { beatInBar = 0 }
            let click = accented && beatInBar == 0 ? accentClicks[sound] : clicks[sound]
            out[i] = framesSinceBeat < click.count ? click[framesSinceBeat] : 0
            framesSinceBeat += 1
        }
    }
}

/// Converts the system's host clock (used in audio timestamps) to seconds.
nonisolated enum HostClock {
    private static let ticksPerSecond: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return 1e9 * Double(info.denom) / Double(info.numer)
    }()

    static var now: Double { seconds(mach_absolute_time()) }

    static func seconds(_ hostTime: UInt64) -> Double {
        Double(hostTime) / ticksPerSecond
    }
}
