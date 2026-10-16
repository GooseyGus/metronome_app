import Foundation

/// The click sounds, synthesised in code so no audio files are needed.
nonisolated enum ClickSound: Int, CaseIterable, Identifiable {
    case classic, wood, electric

    var id: Self { self }

    var name: String {
        switch self {
        case .classic: "Classic"
        case .wood: "Wood"
        case .electric: "Electric"
        }
    }

    /// One click's samples. Accented clicks (the first beat of a bar) are pitched up.
    func samples(sampleRate: Double, accented: Bool) -> [Float] {
        let pitch = accented ? 1.5 : 1.0
        let duration = 0.05
        return (0..<Int(sampleRate * duration)).map { i in
            let t = Double(i) / sampleRate
            // Taper to zero so the click never ends on an audible pop.
            return Float(sample(at: t, pitch: pitch) * (1 - t / duration))
        }
    }

    private func sample(at t: Double, pitch: Double) -> Double {
        switch self {
        case .classic:
            // A short decaying sine tick.
            return sin(2 * .pi * 1_500 * pitch * t) * exp(-t * 150) * 0.8
        case .wood:
            // A few inharmonic partials with a fast decay, like a struck wood block.
            let partials: [(frequency: Double, level: Double)] = [(800, 1), (1_910, 0.5), (3_270, 0.25)]
            let tone = partials.reduce(0) { $0 + sin(2 * .pi * $1.frequency * pitch * t) * $1.level }
            return tone * exp(-t * 90) * 0.5
        case .electric:
            // A square-wave beep.
            let square: Double = sin(2 * .pi * 1_000 * pitch * t) >= 0 ? 1 : -1
            return square * exp(-t * 60) * 0.3
        }
    }
}
