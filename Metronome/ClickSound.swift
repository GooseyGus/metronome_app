import AVFoundation

/// The click sounds: most synthesised in code, some recorded (bundled in Sounds/).
nonisolated enum ClickSound: Int, CaseIterable, Identifiable {
    // The chosen sound is remembered by its number, so numbers never change;
    // the order here is the order they appear in.
    case classic = 0, wood = 1, woodblock = 9, jamBlock = 10, agogo = 11, shaker = 12
    case electric = 2, clave = 3, marimba = 4, snap = 5, clap = 6, cowbell = 7, hiHat = 8

    /// Which click to play: the downbeat (with a time signature on), or an ordinary
    /// beat, every other one of which is `alternate`, for sounds that go tick-tock.
    enum Variant {
        case normal, accent, alternate
    }

    var id: Self { self }

    var name: String {
        switch self {
        case .classic: "Classic"
        case .wood: "Wood"
        case .woodblock: "Woodblock"
        case .jamBlock: "Jam Block"
        case .agogo: "Agogo"
        case .shaker: "Shaker"
        case .electric: "Electric"
        case .clave: "Clave"
        case .marimba: "Marimba"
        case .snap: "Snap"
        case .clap: "Clap"
        case .cowbell: "Cowbell"
        case .hiHat: "Hi-hat"
        }
    }

    /// How loud (RMS) recorded sounds are made, about as loud as Classic and Wood.
    private static let recordedLoudness: Float = 0.2

    /// Recorded sounds: the files for an ordinary beat and for the downbeat.
    private var recording: (beat: String, downbeat: String)? {
        switch self {
        case .woodblock: ("woodblock_low", "woodblock_high")
        case .jamBlock: ("jamblock_low", "jamblock_high")
        case .agogo: ("agogo_low", "agogo_high")
        case .shaker: ("shaker_low", "shaker_high")
        default: nil
        }
    }

    /// One click's samples, at full volume.
    func samples(sampleRate: Double, variant: Variant) -> [Float] {
        if let recording, let recorded = Self.load(variant == .accent ? recording.downbeat : recording.beat, sampleRate: sampleRate) {
            // Recorded already sounding right: just a fade, so one cut off while still
            // ringing doesn't end with a snap, and levelled to the same loudness as the
            // others (as loud as the peak allows, for the quieter ones).
            let fade = Int(sampleRate * 0.03)
            let peak = max(recorded.map(abs).max() ?? 1, 0.001)
            let rms = max((recorded.reduce(0) { $0 + $1 * $1 } / Float(recorded.count)).squareRoot(), 0.0001)
            let gain = min(0.98 / peak, Self.recordedLoudness / rms)
            return recorded.enumerated().map { i, sample in
                sample * gain * min(Float(recorded.count - i) / Float(fade), 1)
            }
        }
        let raw = render(sampleRate: sampleRate, variant: variant)
        let duration = Double(raw.count)
        // Taper to zero so the click never ends on an audible pop, then gently
        // saturate and bring the peak up to full scale: louder and punchier, so it
        // cuts through over an instrument, without harsh clipping.
        let shaped = raw.enumerated().map { i, x in tanh(x * (1 - Double(i) / duration) * drive) }
        let peak = shaped.map(abs).max() ?? 1
        return shaped.map { Float($0 / max(peak, 0.001) * 0.98) }
    }

    /// How hard each sound is saturated: plenty for clicks, very little for tuned ones.
    private var drive: Double {
        switch self {
        case .classic, .wood, .woodblock, .jamBlock, .agogo, .shaker, .electric: 2.5
        case .snap, .clap: 2
        case .clave: 1.8
        case .cowbell: 1.6
        case .hiHat: 1.5
        case .marimba: 1.1
        }
    }

    private func render(sampleRate: Double, variant: Variant) -> [Double] {
        // Accented downbeats are pitched up a fifth, unless the sound says otherwise.
        let pitch = variant == .accent ? 1.5 : 1.0
        var noise = Noise(seed: UInt64(rawValue + 1))
        func samples(_ duration: Double, _ sample: (Double) -> Double) -> [Double] {
            (0..<Int(sampleRate * duration)).map { sample(Double($0) / sampleRate) }
        }
        func tone(_ frequency: Double, _ t: Double) -> Double { sin(2 * .pi * frequency * t) }

        switch self {
        case .classic:
            // A short decaying sine tick.
            return samples(0.06) { t in tone(1_500 * pitch, t) * exp(-t * 90) }
        // Normally recorded; if a file's missing, the nearest synthesised sound stands in.
        case .woodblock, .jamBlock:
            return ClickSound.wood.render(sampleRate: sampleRate, variant: variant)
        case .agogo:
            return ClickSound.cowbell.render(sampleRate: sampleRate, variant: variant)
        case .shaker:
            return ClickSound.hiHat.render(sampleRate: sampleRate, variant: variant)
        case .wood:
            // A few inharmonic partials with a fast decay, like a struck wood block.
            let partials: [(frequency: Double, level: Double)] = [(800, 1), (1_910, 0.5), (3_270, 0.25)]
            return samples(0.06) { t in
                partials.reduce(0) { $0 + tone($1.frequency * pitch, t) * $1.level } * exp(-t * 60) * 0.6
            }
        case .electric:
            // A square-wave beep.
            return samples(0.06) { t in (tone(1_000 * pitch, t) >= 0 ? 1 : -1) * exp(-t * 45) * 0.6 }
        case .clave:
            // Two hardwood sticks: one bright, ringing mode, with a crack of noise on contact.
            return samples(0.09) { t in
                tone(2_500 * pitch, t) * exp(-t * 45)
                    + tone(5_300 * pitch, t) * exp(-t * 90) * 0.3
                    + noise.next() * exp(-t * 800) * 0.3
            }
        case .marimba:
            // A soft mallet on a wooden bar: a warm fundamental, its fourth harmonic
            // fading faster, and a brief knock from the mallet.
            let f = 1_047 * pitch
            return samples(0.4) { t in
                let attack = min(t / 0.001, 1)
                return attack * (tone(f, t) * exp(-t * 14)
                    + tone(f * 3.93, t) * exp(-t * 40) * 0.35
                    + tone(f * 9.2, t) * exp(-t * 150) * 0.2)
            }
        case .snap:
            // Finger snaps: a dry crack of skin with a short, bright knock from the
            // palm. The downbeat is a hand clap.
            if variant == .accent { return ClickSound.clap.render(sampleRate: sampleRate, variant: .normal) }
            var crack = Biquad.highPass(1_800, q: 0.7, sampleRate: sampleRate)
            var knock = Biquad.bandPass(2_400, q: 2, sampleRate: sampleRate)
            return samples(0.05) { t in
                let n = noise.next()
                return crack.process(n) * exp(-t * 900) * 1.2
                    + knock.process(n) * exp(-t * 220) * 2.5
                    + tone(2_350, t) * exp(-t * 260) * 0.25
            }
        case .clap:
            // One person's clap: a few layers of skin landing a split second apart and
            // a short room ring. The downbeat is a bigger, roomier group clap with a thump.
            let group = variant == .accent
            var bright = Biquad.bandPass(group ? 1_100 : 1_400, q: 1.1, sampleRate: sampleRate)
            var body = Biquad.bandPass(group ? 600 : 800, q: 0.8, sampleRate: sampleRate)
            let hands = group ? [0, 0.006, 0.011, 0.019, 0.026, 0.034, 0.045] : [0, 0.009, 0.017]
            let roomStart = hands[hands.count - 1], roomDecay = group ? 9.0 : 28.0
            return samples(group ? 0.35 : 0.18) { t in
                let slaps = min(hands.reduce(0) { $0 + (t >= $1 ? exp(-(t - $1) * 140) : 0) }, 1.3)
                let room = t >= roomStart ? exp(-(t - roomStart) * roomDecay) * 0.45 : 0
                let n = noise.next()
                let thump = group ? tone(150, t) * exp(-t * 30) * 0.5 : 0
                return (bright.process(n) * 2.5 + body.process(n) * 1.2) * (slaps + room) + thump
            }
        case .cowbell:
            // A real cowbell: a stick's click, then a clangy, inharmonic ring from the
            // metal, with a slightly detuned pair at the bottom for its shimmer.
            // The downbeat rings a major third higher.
            let p = variant == .accent ? 1.26 : 1.0
            let modes: [(frequency: Double, level: Double, decay: Double)] = [
                (587, 1, 7), (593, 0.6, 7), (845, 0.8, 9), (1_185, 0.35, 14),
                (1_640, 0.25, 18), (2_450, 0.2, 25), (3_380, 0.12, 35),
            ]
            var stick = Biquad.bandPass(4_000, q: 1, sampleRate: sampleRate)
            return samples(0.45) { t in
                let attack = min(t / 0.0007, 1)
                let ring = modes.reduce(0) { $0 + tone($1.frequency * p, t) * $1.level * exp(-t * $1.decay) }
                return attack * ring + stick.process(noise.next()) * exp(-t * 400) * 1.5
            }
        case .hiHat:
            // Bright, high-passed noise: closed on ordinary beats, open on the downbeat.
            var high = Biquad.highPass(7_000, q: 0.7, sampleRate: sampleRate)
            let open = variant == .accent
            return samples(open ? 0.25 : 0.06) { t in
                high.process(noise.next()) * exp(-t * (open ? 14 : 90))
            }
        }
    }
}

extension ClickSound {
    /// Reads a bundled recording as mono samples at `sampleRate`.
    fileprivate static func load(_ name: String, sampleRate: Double) -> [Float]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData
        else { return nil }
        let count = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
        // Stereo recordings are mixed down; the click comes out of one source anyway.
        let mono = (0..<count).map { i in
            (0..<channelCount).reduce(Float(0)) { $0 + channels[$1][i] } / Float(channelCount)
        }
        return Metronome.resample(mono, from: file.processingFormat.sampleRate, to: sampleRate)
    }
}

/// Repeatable white noise from -1 to 1, so each sound comes out the same every time.
private nonisolated struct Noise {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(Int64(bitPattern: state) >> 11) / Double(1 << 52)
    }
}

/// A standard two-pole filter, for shaping noise.
private nonisolated struct Biquad {
    let b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func bandPass(_ frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * .pi * frequency / sampleRate, alpha = sin(w) / (2 * q), a0 = 1 + alpha
        return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
    }

    static func highPass(_ frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * .pi * frequency / sampleRate, alpha = sin(w) / (2 * q), a0 = 1 + alpha
        let b = (1 + cos(w)) / 2 / a0
        return Biquad(b0: b, b1: -2 * b, b2: b, a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        (x2, x1, y2, y1) = (x1, x, y1, y)
        return y
    }
}
