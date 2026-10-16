import SwiftUI

/// Easter egg: tapping the title makes every component shiver, like a coffee cup
/// when something heavy walks past. Each tap adds a quick ripple that dies out fast.
/// Keep tapping and components get knocked off the screen one by one; ten taps in a
/// row clears everything, with the title last. Once tapping stops, fallen components
/// drop back in from above.
@Observable
final class Wobble {
    private struct Traits {
        var strength: Double
        var frequency: Double
        var phase: Double
        var spin: Double
        var returnDelay: Double
        /// How many taps in a row knock this component off.
        var fallsAtTap: Int
    }

    private struct Fall {
        let start: Date
        /// Fixed once the component starts dropping back in, so a new tap can't yank it away.
        var returnStart: Date?
    }

    private(set) var isAnimating = false
    /// Set once every component has been knocked off in one streak; swaps the
    /// running metronome for a dancer until RESET.
    private(set) var dancerUnlocked = false
    /// When the dancer touches down after its first fall, for its landing animation.
    private(set) var dancerLandingTime: Date?
    /// Everything's been cleared, but the title is still on its way off the screen.
    private var dancerPending = false
    private var taps: [Date] = []
    private var traits: [String: Traits] = [:]
    private var fallsLast: Set<String> = []
    private var streak = 0
    private var falls: [String: Fall] = [:]
    private var animationTask: Task<Void, Never>?

    /// Each tap's ripple builds over `attack` seconds and fades with time constant `decay`.
    private let attack = 0.04
    private let decay = 0.3
    private let degreesPerTap = 1.5
    private let maxDegrees = 6.0
    /// Taps closer together than this count as one streak.
    private let streakGap = 0.6
    private let tapsToClearEverything = 10
    /// Fallen components come back this long after the last tap.
    private let quietPeriod = 1.2
    private let minimumTimeAway = 0.8
    private let dropDuration = 0.45
    private let settleDuration = 0.6

    func register(_ id: String, fallsLast: Bool) {
        if fallsLast { self.fallsLast.insert(id) }
        if traits[id] == nil { traits[id] = randomTraits(for: id) }
    }

    func tap() {
        let now = Date()
        // Once things have settled, the next shake picks new strengths,
        // so it's not the same components falling first every time.
        if level(at: now) < 0.02 && falls.isEmpty {
            for id in traits.keys { traits[id] = randomTraits(for: id) }
        }
        // Lock in anything already dropping back, before this tap delays the rest.
        for (id, fall) in falls where fall.returnStart == nil {
            let start = returnStart(for: id, fall: fall)
            if start <= now { falls[id]?.returnStart = start }
        }

        if let last = taps.last, now.timeIntervalSince(last) < streakGap {
            streak += 1
        } else {
            streak = 1
        }
        taps = taps.filter { now.timeIntervalSince($0) < decay * 8 } + [now]

        for (id, trait) in traits where falls[id] == nil && streak >= trait.fallsAtTap {
            falls[id] = Fall(start: now)
        }
        if streak >= tapsToClearEverything && !dancerUnlocked { dancerPending = true }
        startAnimating()
    }

    func resetDancer() {
        dancerUnlocked = false
        dancerPending = false
        dancerLandingTime = nil
    }

    /// Swaps in the dancer only once the title has left the screen and starts dropping back.
    private func revealDancerIfReturning(at now: Date) {
        guard let id = fallsLast.first else { return }
        let start = falls[id].map { returnStart(for: id, fall: $0) } ?? now
        guard start <= now else { return }
        dancerPending = false
        dancerUnlocked = true
        dancerLandingTime = start.addingTimeInterval(dropDuration)
    }

    /// Rotation (degrees) and offset for a component at a moment in time.
    func motion(for id: String, at date: Date) -> (angle: Double, x: Double, y: Double) {
        guard let trait = traits[id] else { return (0, 0, 0) }

        if let fall = falls[id] {
            let back = returnStart(for: id, fall: fall)
            if date < back {
                // Tumble off the bottom of the screen.
                let elapsed = date.timeIntervalSince(fall.start)
                return (trait.spin * elapsed * 220, trait.spin * elapsed * 40, min(1_500 * elapsed * elapsed, 3_000))
            }
            let elapsed = date.timeIntervalSince(back)
            if elapsed < dropDuration {
                // Fall back in from above the screen, accelerating like it's dropped.
                let progress = elapsed / dropDuration
                return (0, 0, -2_000 * (1 - progress * progress))
            }
            // A small shiver on landing.
            let landed = elapsed - dropDuration
            return (sin(landed * 45) * 6 * exp(-landed * 8), 0, 0)
        }

        // A continuous clock, so new taps add to the motion instead of restarting it.
        let t = date.timeIntervalSinceReferenceDate
        let amplitude = min(ripple(at: date) * trait.strength * degreesPerTap, maxDegrees)
        let swing = sin(t * trait.frequency + trait.phase)
        return (swing * amplitude, swing * amplitude * 0.3, 0)
    }

    /// How strongly things are shaking: each tap rises smoothly then fades.
    private func ripple(at date: Date) -> Double {
        taps.reduce(0) { total, tap in
            let dt = date.timeIntervalSince(tap)
            return dt < 0 ? total : total + (1 - exp(-dt / attack)) * exp(-dt / decay)
        }
    }

    /// The shaking's peak level.
    private func level(at date: Date) -> Double {
        taps.reduce(0) { $0 + exp(-date.timeIntervalSince($1) / decay) }
    }

    private func returnStart(for id: String, fall: Fall) -> Date {
        if let locked = fall.returnStart { return locked }
        let lastTap = taps.last ?? fall.start
        let earliest = max(fall.start.addingTimeInterval(minimumTimeAway), lastTap.addingTimeInterval(quietPeriod))
        return earliest.addingTimeInterval(traits[id]?.returnDelay ?? 0)
    }

    /// Runs the per-frame animation only while something is moving.
    private func startAnimating() {
        isAnimating = true
        guard animationTask == nil else { return }
        animationTask = Task {
            while true {
                try? await Task.sleep(for: .milliseconds(100))
                let now = Date()
                if dancerPending { revealDancerIfReturning(at: now) }
                let settled = dropDuration + settleDuration
                falls = falls.filter { id, fall in
                    now.timeIntervalSince(returnStart(for: id, fall: fall)) < settled
                }
                if ripple(at: now) < 0.01 && falls.isEmpty { break }
            }
            taps.removeAll()
            isAnimating = false
            animationTask = nil
        }
    }

    private func randomTraits(for id: String) -> Traits {
        Traits(
            strength: .random(in: 0.6...1.3),
            frequency: .random(in: 40...60),
            phase: .random(in: 0...(2 * .pi)),
            spin: Bool.random() ? 1 : -1,
            returnDelay: .random(in: 0...0.5),
            fallsAtTap: fallsLast.contains(id) ? tapsToClearEverything : .random(in: 3...(tapsToClearEverything - 1))
        )
    }
}

extension View {
    /// Lets this component join in the title's wobble easter egg.
    /// With `fallsLast`, it's the final component to be knocked off.
    func wobbly(_ id: String, fallsLast: Bool = false) -> some View {
        modifier(Wobbly(id: id, fallsLast: fallsLast))
    }
}

private struct Wobbly: ViewModifier {
    @Environment(Wobble.self) private var wobble
    let id: String
    let fallsLast: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !wobble.isAnimating)) { context in
            let motion = wobble.motion(for: id, at: context.date)
            content
                .rotationEffect(.degrees(motion.angle))
                .offset(x: motion.x, y: motion.y)
        }
        .onAppear { wobble.register(id, fallsLast: fallsLast) }
    }
}
