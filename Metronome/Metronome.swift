import AVFoundation
import Darwin
import Synchronization

/// Plays a click on every beat. The click is generated on the audio thread by
/// counting samples, so timing is sample-accurate and tempo changes apply instantly.
final class Metronome {
    private let engine = AVAudioEngine()
    private let generator: ClickGenerator
    private let source: AVAudioSourceNode
    private var observers: [NSObjectProtocol] = []
    private var idlePause: Task<Void, Never>?
    /// The delay between rendering audio and hearing it, read when the route might have
    /// changed rather than every frame: asking the audio session costs time.
    private var outputLatency = AVAudioSession.sharedInstance().outputLatency

    /// Called when something else (like a phone call) stops the click.
    var onInterruption: () -> Void = {}

    /// The rate the click is generated at; recordings are converted to match.
    let sampleRate: Double
    /// Built-in sounds, rendered the first time each is chosen.
    private var builtInClicks: [ClickSound: ClickGenerator.Clicks] = [:]

    init() {
        Self.usePlaybackSession()
        let session = AVAudioSession.sharedInstance()

        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: outputRate > 0 ? outputRate : 44_100, channels: 1)!
        sampleRate = format.sampleRate
        generator = ClickGenerator(sampleRate: format.sampleRate)
        source = AVAudioSourceNode(format: format, renderBlock: generator.makeRenderBlock())
        engine.attach(source)
        try? engine.connectNode(source, to: engine.mainMixerNode, format: format)

        let center = NotificationCenter.default
        // A phone call, alarm or Siri takes over the audio: stop and let the UI know.
        observers.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
                self?.onInterruption()
            }
        })
        // Plugging in or removing headphones stops the engine; restart it if we were playing.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.outputLatency = AVAudioSession.sharedInstance().outputLatency
                guard self.generator.isActive else { return }
                try? self.engine.start()
            }
        })
    }

    /// Stops the silent engine while nothing's playing, e.g. in the background,
    /// so the app isn't kept awake. START restarts it.
    func pauseIfIdle() {
        if !generator.isActive { engine.pause() }
    }

    func start(clicksPerMinute: Double) throws {
        idlePause?.cancel()
        generator.setRate(clicksPerMinute)
        // The engine keeps running (outputting silence) for a while after stopping,
        // so starting again soon after is instant.
        if !engine.isRunning { try engine.start() }
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        generator.start()
    }

    func stop() {
        generator.stop()
        // Running silence keeps the audio hardware awake, so let it rest after a while.
        idlePause?.cancel()
        idlePause = Task {
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { pauseIfIdle() }
        }
    }

    /// How many beats have been heard since START, including the fraction of the
    /// current beat, so visuals can follow the audio exactly. Nil until the first sound.
    func beatPhase() -> Double? {
        // Compensate for the delay between rendering audio and hearing it.
        generator.beatPhase(atSeconds: HostClock.now - outputLatency)
    }

    func setRate(_ clicksPerMinute: Double) {
        generator.setRate(clicksPerMinute)
    }

    /// Sets up audio for playing only, as normal (recording a sound switches it).
    static func usePlaybackSession() {
        // .playback keeps the click audible even with the silent switch on;
        // mixing lets it play over music or video instead of stopping them.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        // Activate asynchronously; the synchronous setActive can block the main thread.
        session.activate { success, error in
            if !success { print("Failed to activate audio session: \(String(describing: error))") }
        }
    }

    func setSound(_ sound: ClickSound) {
        if builtInClicks[sound] == nil {
            builtInClicks[sound] = ClickGenerator.Clicks(
                normal: sound.samples(sampleRate: sampleRate, variant: .normal),
                accent: sound.samples(sampleRate: sampleRate, variant: .accent),
                alternate: sound.samples(sampleRate: sampleRate, variant: .alternate)
            )
        }
        generator.setClicks(builtInClicks[sound]!)
    }

    /// Plays a recorded sound, with its own downbeat if one was recorded.
    func setCustomSound(beat: [Float], downbeat: [Float]?, recordedAt rate: Double) {
        let normal = Self.resample(beat, from: rate, to: sampleRate)
        let accent = downbeat.map { Self.resample($0, from: rate, to: sampleRate) } ?? normal
        generator.setClicks(ClickGenerator.Clicks(normal: normal, accent: accent, alternate: normal))
    }

    /// Converts samples between rates, interpolating linearly; fine for short clicks.
    nonisolated static func resample(_ samples: [Float], from source: Double, to target: Double) -> [Float] {
        guard source != target, !samples.isEmpty else { return samples }
        let step = source / target
        let count = Int(Double(samples.count) / step)
        return (0..<count).map { i in
            let position = Double(i) * step
            let index = Int(position)
            let next = min(index + 1, samples.count - 1)
            let fraction = Float(position - Double(index))
            return samples[index] + (samples[next] - samples[index]) * fraction
        }
    }

    /// With `accented`, the first of every `beats` clicks is pitched up.
    /// The next click starts a fresh bar.
    func setBar(beats: Int, accented: Bool) {
        generator.setBar(beats: beats, accented: accented)
    }
}

/// Renders the click. Settings are shared with the main thread through atomics;
/// the beat counters and the clicks playing are only ever touched on the audio thread.
nonisolated final class ClickGenerator: @unchecked Sendable {
    private let sampleRate: Double
    /// One sound's three clicks: ordinary beats, the downbeat, and every other beat.
    struct Clicks: Sendable {
        var normal, accent, alternate: [Float]
    }

    /// A newly chosen sound, waiting for the audio thread to pick it up on the next beat.
    private let pendingClicks = Mutex<Clicks?>(nil)
    private let samplesPerBeat = Atomic<Int>(22_050)
    private let beatsPerBar = Atomic<Int>(4)
    private let isAccented = Atomic<Bool>(false)
    private let isPlaying = Atomic<Bool>(false)
    private let restartRequested = Atomic<Bool>(false)
    private let barRestartRequested = Atomic<Bool>(false)
    // Where the beat was at the start of the latest buffer, and when that buffer plays.
    private let phaseBits = Atomic<UInt64>(0)
    private let phaseHostTime = Atomic<UInt64>(0)
    private var framesSinceBeat = 0
    private var beatInBar = 0
    private var beatsSinceStart = 0
    // The sound in use, the click sounding now, and the one before ringing on underneath it.
    private var clicks = Clicks(normal: [], accent: [], alternate: [])
    private var click: [Float] = []
    private var tail: [Float] = []
    private var tailFrame = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func setRate(_ clicksPerMinute: Double) {
        samplesPerBeat.store(max(Int(sampleRate * 60 / clicksPerMinute), 1), ordering: .relaxed)
    }

    func setClicks(_ clicks: Clicks) {
        pendingClicks.withLock { $0 = clicks }
    }

    func setBar(beats: Int, accented: Bool) {
        beatsPerBar.store(beats, ordering: .relaxed)
        isAccented.store(accented, ordering: .relaxed)
        barRestartRequested.store(true, ordering: .releasing)
    }

    func start() {
        phaseHostTime.store(0, ordering: .releasing)
        restartRequested.store(true, ordering: .releasing)
        isPlaying.store(true, ordering: .releasing)
    }

    func stop() {
        isPlaying.store(false, ordering: .releasing)
    }

    var isActive: Bool {
        isPlaying.load(ordering: .acquiring)
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
            barRestartRequested.store(false, ordering: .relaxed)
            tail = []
            click = nextClick(accented: isAccented.load(ordering: .relaxed))
        }
        let beatLength = samplesPerBeat.load(ordering: .relaxed)

        let phase = Double(beatsSinceStart) + Double(min(framesSinceBeat, beatLength)) / Double(beatLength)
        phaseBits.store(phase.bitPattern, ordering: .relaxed)
        phaseHostTime.store(hostTime, ordering: .releasing)

        let beats = beatsPerBar.load(ordering: .relaxed)
        let accented = isAccented.load(ordering: .relaxed)
        for i in 0..<frameCount {
            if framesSinceBeat >= beatLength {
                // Let a long sound ring on under the next click instead of cutting it off.
                tail = click
                tailFrame = framesSinceBeat
                framesSinceBeat = 0
                beatsSinceStart += 1
                // A changed time signature starts a fresh bar on this click.
                if barRestartRequested.exchange(false, ordering: .acquiring) {
                    beatInBar = 0
                } else {
                    beatInBar += 1
                    if beatInBar >= beats { beatInBar = 0 }
                }
                click = nextClick(accented: accented)
            }
            var sample = framesSinceBeat < click.count ? click[framesSinceBeat] : 0
            if tailFrame < tail.count {
                sample += tail[tailFrame]
                tailFrame += 1
            }
            out[i] = min(max(sample, -1), 1)
            framesSinceBeat += 1
        }
    }

    private func nextClick(accented: Bool) -> [Float] {
        // Never wait on the main thread here: if it's mid-change, pick it up next beat.
        if let chosen = pendingClicks.withLockIfAvailable({ pending in pending.take() }) ?? nil {
            clicks = chosen
        }
        if accented && beatInBar == 0 { return clicks.accent }
        return beatsSinceStart % 2 == 1 ? clicks.alternate : clicks.normal
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
