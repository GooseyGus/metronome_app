import SwiftUI

/// Easter egg reward: a stick figure dancing in time with the click. It keeps the
/// same move until tapped, and while stopped it idles, waiting to dance. Shaken, it
/// teeters; knocked off, it flails; whenever it drops back in, it does a superhero
/// landing. Once every move has been danced, a partner drops in beside it and dances
/// its mirror image. From then on she lands gracefully and he lands in a heap.
/// Very fast tempos wear them out until they stop to pant; very slow ones bore them.
struct DancerGlyph: View {
    @Environment(Wobble.self) private var wobble
    let metronome: Metronome
    let palette: Palette
    let isPlaying: Bool
    let landingTime: Date?
    /// Which move to dance, chosen at START and by tapping.
    let move: Int
    let clicksPerMinute: Double
    /// When the partner lands, once she's been unlocked.
    let partnerLandingTime: Date?
    /// Reports each move as it starts, so the partner can be unlocked.
    let onMove: (Int) -> Void

    static var moveCount: Int { DanceMove.allCases.count }
    /// How wide the glyph should be, relative to its height.
    static func aspectRatio(withPartner: Bool) -> CGFloat { withPartner ? 2.3 : 1.3 }

    private let partnerColour = Color(hex: 0xF4A3C0)
    private let sweatColour = Color(hex: 0x8FD3FF)
    @State private var stamina = Stamina()
    /// How long the partner takes to drop in from above before landing.
    static let partnerDropDuration = 0.45
    /// Room above the figures, relative to their height, so raised hands aren't cut off.
    private static let headroom = 0.08

    var body: some View {
        // Idling is slow and gentle, so half the frame rate does; shaking and dancing get the lot.
        TimelineView(.animation(minimumInterval: isPlaying || wobble.isAnimating ? nil : 1 / 30)) { context in
            let now = context.date
            let moveIndex = move % Self.moveCount
            let (pose, partnerPose) = poses(at: now, moveIndex: moveIndex)
            let sweat = stamina.sweat
            let time = now.timeIntervalSinceReferenceDate
            let sincePartnerLanding = partnerLandingTime.map { now.timeIntervalSince($0) }

            GeometryReader { geometry in
                let headroom = geometry.size.height * Self.headroom
                Canvas { context, size in
                    let unit = size.height - headroom
                    context.translateBy(x: 0, y: headroom)
                    drawFigures(pose, partnerPose, sincePartnerLanding: sincePartnerLanding, sweat: sweat,
                                time: time, in: &context, width: size.width, unit: unit)
                }
                // Reach up past the frame, keeping the figures full height.
                .padding(.top, -headroom)
            }
            .onChange(of: moveIndex, initial: true) {
                if isPlaying { onMove(moveIndex) }
            }
            .onChange(of: isPlaying) {
                if isPlaying { onMove(moveIndex) }
            }
        }
        .accessibilityLabel(isPlaying ? "Dancing to the beat" : "Waiting to dance")
    }

    /// Draws him, and her beside him once she's arrived.
    private func drawFigures(
        _ pose: Pose, _ partnerPose: Pose, sincePartnerLanding: Double?, sweat: Double, time: Double,
        in context: inout GraphicsContext, width: CGFloat, unit: CGFloat
    ) {
        guard let sincePartnerLanding else {
            draw(pose, in: &context, centreX: width / 2, unit: unit, colour: palette.text, sweat: sweat, time: time)
            return
        }
        draw(pose, in: &context, centreX: width * 0.28, unit: unit, colour: palette.text, sweat: sweat, time: time)
        // Drops in from above the glyph, then lands.
        let drop = max(-sincePartnerLanding / Self.partnerDropDuration, 0)
        draw(partnerPose, in: &context, centreX: width * 0.72, unit: unit, colour: partnerColour,
             isPartner: true, dropOffset: -unit * 1.2 * drop * drop, sweat: sweat, time: time + 0.37)
    }

    /// Where each of them is at `now`: his pose, and hers for when she's there.
    private func poses(at now: Date, moveIndex: Int) -> (Pose, Pose) {
        // Just after START the heard beat can sit a hair before zero; moves index by beat.
        let phase = max(metronome.beatPhase() ?? 0, 0)
        let idleTime = now.timeIntervalSinceReferenceDate

        // Shaking throws them off balance, leaning against the title's tilt.
        let instability = wobble.instability(at: now)
        let lean = wobble.motion(for: "title", at: now).angle / 6
        let move = Pose.at(beatPhase: phase, move: DanceMove.allCases[moveIndex])
        // Too slow and they fidget; too fast for too long and they stop to catch their breath.
        stamina.update(at: now, isDancing: isPlaying, clicksPerMinute: clicksPerMinute)
        let boredom = Pose.boredom(atClicksPerMinute: clicksPerMinute)
        let resting = stamina.restAmount(at: now)
        func danced(_ move: Pose, offset: Double, mirrored: Bool) -> Pose {
            let fidgeting = Pose.fidgeting(move, at: idleTime + offset, amount: boredom)
            let panting = Pose.panting(at: idleTime + offset)
            return Pose.mix(fidgeting, mirrored ? panting.mirrored : panting, resting)
        }
        let dance = isPlaying ? danced(move, offset: 0, mirrored: false) : Pose.idle(at: idleTime)
        let steady = Pose.teetering(dance, at: idleTime, lean: lean, instability: instability)
        let sinceLanding = landingTime.map { now.timeIntervalSince($0) } ?? .infinity
        // Knocked off since the last landing: flailing on the way down.
        var sinceFall: Double?
        if let fall = wobble.dancerFallTime, landingTime.map({ fall > $0 }) ?? true {
            sinceFall = now.timeIntervalSince(fall)
        }

        var pose = partnerLandingTime == nil
            ? Pose.landing(at: sinceLanding, thenDancing: steady)
            : Pose.clumsyLanding(at: sinceLanding, thenDancing: steady)
        if let sinceFall { pose = Pose.flailing(at: sinceFall) }

        // The partner mirrors the dance; while idle she does her own thing.
        let partnerDance = isPlaying ? danced(move.mirrored, offset: 3.3, mirrored: true) : Pose.idle(at: idleTime + 29).mirrored
        let partnerSteady = Pose.teetering(partnerDance, at: idleTime + 0.3, lean: lean, instability: instability)
        // Whenever they're knocked off again, she lands alongside him.
        let sincePartnerLanding = partnerLandingTime.map { min(now.timeIntervalSince($0), sinceLanding) } ?? .infinity
        var partnerPose = Pose.gracefulLanding(at: sincePartnerLanding, thenDancing: partnerSteady)
        // While he's down she winces and watches him.
        partnerPose = Pose.mix(partnerPose, Pose.concerned(at: idleTime), Pose.concern(whileHeIsDownFor: sinceLanding))
        if let sinceFall { partnerPose = Pose.flailing(at: sinceFall + 0.4).mirrored }
        return (pose, partnerPose)
    }

    /// Draws one stick figure. Poses use a unit square, y pointing down, fitted to the height.
    private func draw(
        _ pose: Pose, in context: inout GraphicsContext, centreX: CGFloat, unit: CGFloat, colour: Color,
        isPartner: Bool = false, dropOffset: CGFloat = 0, sweat: Double = 0, time: Double = 0
    ) {
        let originX = centreX - unit / 2
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: originX + p.x * unit, y: p.y * unit + dropOffset) }
        func limb(_ points: CGPoint...) -> Path {
            Path { path in
                path.move(to: point(points[0]))
                for p in points.dropFirst() { path.addLine(to: point(p)) }
            }
        }
        func circle(_ centre: CGPoint, radius: CGFloat) -> Path {
            let c = point(centre)
            return Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }

        let style = StrokeStyle(lineWidth: max(unit * 0.07, 1.5), lineCap: .round, lineJoin: .round)
        let ink = GraphicsContext.Shading.color(colour)

        // A small floor shadow keeps the figure grounded as it moves.
        let shadow = CGRect(x: originX + (pose.hip.x - 0.22) * unit, y: unit * 0.95, width: unit * 0.44, height: unit * 0.05)
        context.fill(Path(ellipseIn: shadow), with: .color(colour.opacity(0.25)))

        context.stroke(limb(pose.hip, pose.leftKnee, pose.leftFoot), with: ink, style: style)
        context.stroke(limb(pose.hip, pose.rightKnee, pose.rightFoot), with: ink, style: style)
        context.stroke(limb(pose.neck, pose.hip), with: ink, style: style)
        context.stroke(limb(pose.neck, pose.leftElbow, pose.leftHand), with: ink, style: style)
        context.stroke(limb(pose.neck, pose.rightElbow, pose.rightHand), with: ink, style: style)

        if isPartner {
            // A flared skirt from the waist, and a ponytail.
            var skirt = Path()
            skirt.move(to: point(CGPoint(x: pose.hip.x - 0.05, y: pose.hip.y - 0.1)))
            skirt.addLine(to: point(CGPoint(x: pose.hip.x + 0.05, y: pose.hip.y - 0.1)))
            skirt.addLine(to: point(CGPoint(x: pose.hip.x + 0.15, y: pose.hip.y + 0.16)))
            skirt.addLine(to: point(CGPoint(x: pose.hip.x - 0.15, y: pose.hip.y + 0.16)))
            skirt.closeSubpath()
            context.fill(skirt, with: ink)
            let away: Double = pose.head.x >= pose.neck.x ? -1 : 1
            context.fill(circle(CGPoint(x: pose.head.x + away * 0.1, y: pose.head.y - 0.02), radius: unit * 0.05), with: ink)
        }
        context.fill(circle(pose.head, radius: unit * 0.1), with: ink)

        // Beads of sweat flicking off either side of the head.
        guard sweat > 0.01 else { return }
        let drops = 4
        for k in 0..<drops {
            let phase = (time * 1.4 + Double(k) / Double(drops)).truncatingRemainder(dividingBy: 1)
            let side: Double = k % 2 == 0 ? 1 : -1
            let centre = point(CGPoint(
                x: pose.head.x + side * (0.1 + 0.12 * phase),
                y: pose.head.y - 0.06 - 0.1 * phase + 0.35 * phase * phase
            ))
            let r = unit * 0.022
            var bead = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
            bead.move(to: CGPoint(x: centre.x - r * 0.8, y: centre.y - r * 0.5))
            bead.addLine(to: CGPoint(x: centre.x, y: centre.y - r * 2.2))
            bead.addLine(to: CGPoint(x: centre.x + r * 0.8, y: centre.y - r * 0.5))
            context.fill(bead, with: .color(sweatColour.opacity(sweat * (1 - phase))))
        }
    }
}

/// How worn out they get dancing fast. At 300 clicks a minute they tire in about 20
/// seconds, stop to catch their breath, then go again, tiring quicker the second time.
private final class Stamina {
    private static let restDuration = 6.0
    private var tiredness = 0.0
    private var restStart: Date?
    private var lastUpdate: Date?

    func update(at now: Date, isDancing: Bool, clicksPerMinute: Double) {
        let elapsed = min(max(now.timeIntervalSince(lastUpdate ?? now), 0), 0.25)
        lastUpdate = now
        if let restStart {
            if !isDancing {
                self.restStart = nil
            } else if now.timeIntervalSince(restStart) >= Self.restDuration {
                self.restStart = nil
                tiredness = 0.5
            }
            return
        }
        // Nothing below 200; one unit of strain at 300.
        let strain = (clicksPerMinute - 200) / 100
        if isDancing && strain > 0 {
            tiredness += elapsed * strain / 20
        } else {
            tiredness = max(tiredness - elapsed / 20, 0)
        }
        if tiredness >= 1 && isDancing { restStart = now }
    }

    /// How far into catching their breath they are: easing in, holding, easing out.
    func restAmount(at now: Date) -> Double {
        guard let restStart else { return 0 }
        let t = now.timeIntervalSince(restStart)
        return Pose.ease(t / 0.5) * (1 - Pose.ease((t - (Self.restDuration - 0.6)) / 0.6))
    }

    /// Building up as they tire, and pouring off them while they rest.
    var sweat: Double {
        restStart != nil ? 1 : min(max((tiredness - 0.35) / 0.5, 0), 1)
    }
}

private enum DanceMove: CaseIterable {
    case moonwalk, discoPoint, bounce, runningMan, windmill
    case beesKnees, floss, robot, sprinkler, twist
}

/// Things to do while waiting for the music.
private enum IdleStep {
    case rest, hips, scratch, checkWatch, sit, stand, stretch, reach, tapFoot, lookAround, yawn, wave, shuffle

    /// The routine, about a minute long. Each activity moves at normal speed;
    /// the long rests between them are what make it feel unhurried.
    static let routine: [(step: IdleStep, duration: Double)] = [
        (.rest, 4), (.hips, 2), (.rest, 3), (.scratch, 2.5), (.rest, 4),
        (.checkWatch, 2), (.rest, 3), (.sit, 4), (.stand, 1), (.rest, 4),
        (.stretch, 2), (.reach, 1.5), (.rest, 4), (.tapFoot, 2.5), (.rest, 3),
        (.lookAround, 3), (.yawn, 2), (.rest, 4), (.wave, 2), (.rest, 4), (.shuffle, 3), (.rest, 3),
    ]

    /// How long it takes to blend in from the previous step.
    var blend: Double {
        switch self {
        case .sit, .stand: 0.7
        default: 0.4
        }
    }

    func pose(at t: Double) -> Pose {
        switch self {
        case .rest:
            // Standing still, just breathing.
            Pose.standing(x: 0.5, bob: 0.005 * sin(t * 1.5))
        case .hips:
            // Shifting weight from foot to foot.
            Pose.handsOnHips(x: 0.5 + 0.02 * sin(t * 2), bob: 0)
        case .scratch:
            {
                var pose = Pose.handsOnHips(x: 0.5, bob: 0)
                pose.head.x -= 0.02
                pose.rightElbow = CGPoint(x: 0.68, y: 0.18)
                pose.rightHand = CGPoint(x: 0.56, y: 0.05 + 0.015 * sin(t * 25))
                return pose
            }()
        case .checkWatch:
            {
                // Raises a wrist and glances down at it.
                var pose = Pose.standing(x: 0.5, bob: 0)
                pose.head = CGPoint(x: 0.45, y: 0.14)
                pose.leftElbow = CGPoint(x: 0.36, y: 0.44)
                pose.leftHand = CGPoint(x: 0.5, y: 0.38)
                return pose
            }()
        case .sit:
            {
                var pose = Pose.sitting
                pose.head.y += 0.01 * sin(t * 3)
                return pose
            }()
        case .stand:
            Pose.standing(x: 0.5, bob: 0)
        case .stretch:
            {
                // Leaning back with arms up behind the head.
                let lean = sin(min(t / 1.2, 1) * .pi / 2)
                var pose = Pose.standing(x: 0.5, bob: 0)
                pose.neck.x -= 0.03 * lean
                pose.head = CGPoint(x: 0.5 - 0.04 * lean, y: 0.14)
                pose.leftElbow = CGPoint(x: 0.34, y: 0.16)
                pose.leftHand = CGPoint(x: 0.22, y: 0.06)
                pose.rightElbow = CGPoint(x: 0.4, y: 0.12)
                pose.rightHand = CGPoint(x: 0.3, y: 0.02)
                return pose
            }()
        case .reach:
            {
                // On tiptoes, arms up in a wide V so they stay clear of the head.
                var pose = Pose.standing(x: 0.5, bob: -0.02)
                pose.leftElbow = CGPoint(x: 0.38, y: 0.14)
                pose.leftHand = CGPoint(x: 0.3, y: 0.0)
                pose.rightElbow = CGPoint(x: 0.62, y: 0.14)
                pose.rightHand = CGPoint(x: 0.7, y: 0.0)
                pose.leftFoot.y = 0.95
                pose.rightFoot.y = 0.95
                return pose
            }()
        case .tapFoot:
            {
                // Hands on hips, impatiently tapping one foot.
                var pose = Pose.handsOnHips(x: 0.5, bob: 0)
                pose.rightFoot = CGPoint(x: 0.6, y: 0.97 - 0.04 * max(sin(t * 7), 0))
                return pose
            }()
        case .lookAround:
            {
                // Looks one way, then the other, then back.
                var pose = Pose.standing(x: 0.5, bob: 0)
                pose.head.x += 0.04 * sin(t * 2.5)
                return pose
            }()
        case .yawn:
            {
                // A slow yawn: head tipped back, one hand to the mouth.
                var pose = Pose.standing(x: 0.5, bob: 0)
                pose.head = CGPoint(x: 0.48, y: 0.12)
                pose.rightElbow = CGPoint(x: 0.66, y: 0.3)
                pose.rightHand = CGPoint(x: 0.56, y: 0.17)
                return pose
            }()
        case .wave:
            {
                // A friendly wave.
                var pose = Pose.standing(x: 0.5, bob: 0)
                pose.rightElbow = CGPoint(x: 0.68, y: 0.24)
                pose.rightHand = CGPoint(x: 0.7 + 0.05 * sin(t * 10), y: 0.06)
                return pose
            }()
        case .shuffle:
            // A little practice twist, at two beats a second.
            Pose.at(beatPhase: t * 2, move: .twist)
        }
    }
}

/// Joint positions in a unit square (y down), for one moment of a dance.
private struct Pose {
    var head, neck, hip: CGPoint
    var leftElbow, leftHand, rightElbow, rightHand: CGPoint
    var leftKnee, leftFoot, rightKnee, rightFoot: CGPoint

    static func at(beatPhase phase: Double, move: DanceMove) -> Pose {
        let beat = Int(floor(phase))
        let fraction = phase - floor(phase)
        // Eases from 0 to 1 across each beat, landing exactly on the click.
        let ease = (1 - cos(.pi * fraction)) / 2
        let isEven = beat % 2 == 0
        // Swings 0 → 1 on even beats and 1 → 0 on odd beats.
        let swing = isEven ? ease : 1 - ease
        // Rises and falls once per beat, to lift whichever leg is passing the other.
        let lift = sin(.pi * fraction)
        // Snaps quickly into place just after each click, for sharp, jerky moves.
        let snap = min(fraction * 6, 1)

        switch move {
        case .moonwalk: return moonwalk(beat: beat, fraction: fraction, swing: swing, lift: lift, isEven: isEven)
        case .discoPoint: return discoPoint(swing: swing)
        case .bounce: return bounce(fraction: fraction, swing: swing)
        case .runningMan: return runningMan(swing: swing, lift: lift, isEven: isEven)
        case .windmill: return windmill(fraction: fraction)
        case .beesKnees: return beesKnees(swing: swing)
        case .floss: return floss(swing: swing)
        case .robot: return robot(beat: beat, snap: snap)
        case .sprinkler: return sprinkler(beat: beat, snap: snap, lift: lift)
        case .twist: return twist(swing: swing, lift: lift)
        }
    }

    /// Loops through the idle routine, blending smoothly from each step into the next.
    static func idle(at time: Double) -> Pose {
        let routine = IdleStep.routine
        let loopLength = routine.reduce(0) { $0 + $1.duration }
        var local = time.truncatingRemainder(dividingBy: loopLength)
        for (index, entry) in routine.enumerated() {
            guard local >= entry.duration else {
                let previous = routine[(index + routine.count - 1) % routine.count]
                let from = previous.step.pose(at: previous.duration)
                let to = entry.step.pose(at: local)
                let t = min(local / entry.step.blend, 1)
                return mix(from, to, (1 - cos(.pi * t)) / 2)
            }
            local -= entry.duration
        }
        return routine[0].step.pose(at: 0)
    }

    fileprivate static func handsOnHips(x: Double, bob: Double) -> Pose {
        var pose = standing(x: x, bob: bob)
        pose.leftElbow = CGPoint(x: x - 0.16, y: 0.44 + bob)
        pose.leftHand = CGPoint(x: x - 0.06, y: 0.58 + bob)
        pose.rightElbow = CGPoint(x: x + 0.16, y: 0.44 + bob)
        pose.rightHand = CGPoint(x: x + 0.06, y: 0.58 + bob)
        return pose
    }

    fileprivate static let sitting = Pose(
        head: CGPoint(x: 0.5, y: 0.48), neck: CGPoint(x: 0.5, y: 0.6), hip: CGPoint(x: 0.5, y: 0.93),
        // Hands resting on the knees.
        leftElbow: CGPoint(x: 0.4, y: 0.68), leftHand: CGPoint(x: 0.35, y: 0.73),
        rightElbow: CGPoint(x: 0.6, y: 0.68), rightHand: CGPoint(x: 0.65, y: 0.73),
        leftKnee: CGPoint(x: 0.36, y: 0.72), leftFoot: CGPoint(x: 0.28, y: 0.97),
        rightKnee: CGPoint(x: 0.64, y: 0.72), rightFoot: CGPoint(x: 0.72, y: 0.97)
    )

    /// Falls with arms up, slams into a superhero landing (one knee down, fist on the
    /// floor), holds it, then stands and blends into the dance.
    static func landing(at time: Double, thenDancing dance: Pose) -> Pose {
        let impact = 0.12, hold = 0.9, rise = 1.3, blend = 1.6

        switch time {
        case ..<0: return falling
        case ..<impact: return mix(falling, crouch, time / impact)
        case ..<hold: return crouch
        case ..<rise: return mix(crouch, standing(x: 0.5, bob: 0), ease((time - hold) / (rise - hold)))
        case ..<blend: return mix(standing(x: 0.5, bob: 0), dance, ease((time - rise) / (blend - rise)))
        default: return dance
        }
    }

    /// No superhero flair: lands in a heap on his back, lies there with a feeble kick,
    /// sits up rubbing his spinning head, then slowly gets back up.
    static func clumsyLanding(at time: Double, thenDancing dance: Pose) -> Pose {
        let impact = 0.1, lie = 1.8, sit = 2.3, dazed = 3.0, rise = 3.6, blend = 4.0
        let upright = standing(x: 0.5, bob: 0)

        switch time {
        case ..<0: return falling
        case ..<impact: return mix(falling, sprawled, time / impact)
        case ..<lie:
            var pose = sprawled
            let kick = time > 0.8 && time < 1.5 ? max(sin((time - 0.8) * 9), 0) : 0
            pose.leftKnee.y -= 0.04 * kick
            pose.leftFoot.y -= 0.07 * kick
            return pose
        case ..<sit: return mix(sprawled, dizzy(at: time), ease((time - lie) / (sit - lie)))
        case ..<dazed: return dizzy(at: time)
        case ..<rise: return mix(dizzy(at: time), upright, ease((time - dazed) / (rise - dazed)))
        case ..<blend: return mix(upright, dance, ease((time - rise) / (blend - rise)))
        default: return dance
        }
    }

    /// Drops with toes pointed, sinks softly into a plié and rises into a "ta-da".
    static func gracefulLanding(at time: Double, thenDancing dance: Pose) -> Pose {
        let impact = 0.15, rise = 0.55, hold = 1.8, blend = 2.2

        switch time {
        case ..<0: return pointedFall
        case ..<impact: return mix(pointedFall, plie, ease(time / impact))
        case ..<rise: return mix(plie, taDa, ease((time - impact) / (rise - impact)))
        case ..<hold: return taDa
        case ..<blend: return mix(taDa, dance, ease((time - hold) / (blend - hold)))
        default: return dance
        }
    }

    /// How much she's watching him after he lands in a heap: from just after she's
    /// struck her pose, until he's back on his feet.
    static func concern(whileHeIsDownFor time: Double) -> Double {
        ease((time - 1.5) / 0.4) * (1 - ease((time - 3.2) / 0.4))
    }

    /// Wincing at him, off to her left: leaning in for a look, hand to her cheek.
    static func concerned(at t: Double) -> Pose {
        var pose = standing(x: 0.5, bob: 0.01)
        pose.head = CGPoint(x: 0.42, y: 0.16 + 0.005 * sin(t * 3))
        pose.neck = CGPoint(x: 0.46, y: 0.28)
        pose.leftElbow = CGPoint(x: 0.3, y: 0.38)
        pose.leftHand = CGPoint(x: 0.31, y: 0.22)
        pose.rightElbow = CGPoint(x: 0.64, y: 0.44)
        pose.rightHand = CGPoint(x: 0.56, y: 0.58)
        return pose
    }

    /// Arms windmilling and legs kicking, as it's knocked off the screen.
    static func flailing(at t: Double) -> Pose {
        var pose = standing(x: 0.5, bob: 0)
        let spin = t * 16
        pose.leftHand = CGPoint(x: 0.3 + 0.14 * cos(spin), y: 0.24 + 0.14 * sin(spin))
        pose.rightHand = CGPoint(x: 0.7 - 0.14 * cos(spin + 1), y: 0.24 + 0.14 * sin(spin + 1))
        pose.leftElbow = mix(pose.neck, pose.leftHand, 0.5)
        pose.leftElbow.x -= 0.04
        pose.rightElbow = mix(pose.neck, pose.rightHand, 0.5)
        pose.rightElbow.x += 0.04
        let kick = sin(t * 18)
        pose.leftKnee = CGPoint(x: 0.44 - 0.04 * kick, y: 0.76 - 0.05 * max(kick, 0))
        pose.leftFoot = CGPoint(x: 0.4 - 0.08 * kick, y: 0.94 - 0.08 * max(kick, 0))
        pose.rightKnee = CGPoint(x: 0.56 + 0.04 * kick, y: 0.76 - 0.05 * max(-kick, 0))
        pose.rightFoot = CGPoint(x: 0.6 + 0.08 * kick, y: 0.94 - 0.08 * max(-kick, 0))
        return pose
    }

    /// Thrown off balance: knees bent, arms out and flapping, leaning against the
    /// tilt (`lean` from -1 to 1). Light shaking blends a little of it in; heavier
    /// shaking (`instability` past 1) makes the flapping and leaning bigger.
    static func teetering(_ pose: Pose, at t: Double, lean: Double, instability: Double) -> Pose {
        guard instability > 0.01 else { return pose }
        let amount = min(instability * 1.3, 1)
        let scale = 0.9 + 0.4 * min(max(instability - 0.8, 0), 2)
        let flap = sin(t * 22) * scale
        let shift = -lean * 0.06 * scale
        var wobbly = standing(x: 0.5, bob: 0.03 * scale)
        wobbly.head.x += shift * 1.5
        wobbly.neck.x += shift
        wobbly.leftElbow = CGPoint(x: 0.36 + shift, y: 0.32 + 0.04 * flap)
        wobbly.leftHand = CGPoint(x: 0.2 + shift, y: 0.28 + 0.1 * flap)
        wobbly.rightElbow = CGPoint(x: 0.64 + shift, y: 0.32 - 0.04 * flap)
        wobbly.rightHand = CGPoint(x: 0.8 + shift, y: 0.28 - 0.1 * flap)
        wobbly.leftKnee = CGPoint(x: 0.4, y: 0.78)
        wobbly.leftFoot = CGPoint(x: 0.38, y: 0.97)
        wobbly.rightKnee = CGPoint(x: 0.6, y: 0.78)
        wobbly.rightFoot = CGPoint(x: 0.62, y: 0.97)
        return mix(pose, wobbly, amount)
    }

    /// Bent over with hands on knees, chest heaving, catching their breath.
    static func panting(at t: Double) -> Pose {
        let heave = 0.012 * sin(t * 9)
        return Pose(
            head: CGPoint(x: 0.36, y: 0.33 + heave), neck: CGPoint(x: 0.43, y: 0.42 + heave), hip: CGPoint(x: 0.6, y: 0.6),
            leftElbow: CGPoint(x: 0.39, y: 0.6 + heave / 2), leftHand: CGPoint(x: 0.49, y: 0.73),
            rightElbow: CGPoint(x: 0.52, y: 0.61 + heave / 2), rightHand: CGPoint(x: 0.62, y: 0.73),
            leftKnee: CGPoint(x: 0.5, y: 0.77), leftFoot: CGPoint(x: 0.46, y: 0.97),
            rightKnee: CGPoint(x: 0.64, y: 0.77), rightFoot: CGPoint(x: 0.68, y: 0.97)
        )
    }

    /// How bored a tempo makes them: not at all from 30 clicks a minute, completely by 15.
    static func boredom(atClicksPerMinute clicksPerMinute: Double) -> Double {
        min(max((30 - clicksPerMinute) / 15, 0), 1)
    }

    /// Bored stiff by a very slow beat: every few seconds they break off to check the
    /// time, scratch, tap a foot, yawn or look around, then go back to the dance.
    static func fidgeting(_ dance: Pose, at t: Double, amount: Double) -> Pose {
        guard amount > 0 else { return dance }
        let fidgets: [IdleStep] = [.checkWatch, .scratch, .tapFoot, .yawn, .lookAround]
        let cycle = 6.5
        let local = t.truncatingRemainder(dividingBy: cycle)
        let step = fidgets[Int(t / cycle) % fidgets.count]
        let weight = ease((local - 0.8) / 0.5) * (1 - ease((local - 4.8) / 0.5))
        return mix(dance, step.pose(at: local), weight * amount)
    }

    /// Eases from 0 to 1 as `t` goes from 0 to 1, clamped either side.
    fileprivate static func ease(_ t: Double) -> Double { (1 - cos(.pi * min(max(t, 0), 1))) / 2 }

    /// Sitting up, rubbing his head as it spins.
    private static func dizzy(at t: Double) -> Pose {
        var pose = sitting
        pose.head.x += 0.03 * cos(t * 6)
        pose.head.y += 0.015 * sin(t * 6)
        pose.rightElbow = CGPoint(x: 0.7, y: 0.5)
        pose.rightHand = CGPoint(x: 0.61, y: 0.44)
        return pose
    }

    /// Flat on his back, limbs everywhere.
    private static let sprawled = Pose(
        head: CGPoint(x: 0.14, y: 0.86), neck: CGPoint(x: 0.27, y: 0.9), hip: CGPoint(x: 0.6, y: 0.92),
        leftElbow: CGPoint(x: 0.3, y: 0.78), leftHand: CGPoint(x: 0.22, y: 0.68),
        rightElbow: CGPoint(x: 0.4, y: 0.95), rightHand: CGPoint(x: 0.5, y: 0.97),
        leftKnee: CGPoint(x: 0.74, y: 0.8), leftFoot: CGPoint(x: 0.88, y: 0.94),
        rightKnee: CGPoint(x: 0.76, y: 0.93), rightFoot: CGPoint(x: 0.94, y: 0.95)
    )

    private static let pointedFall = Pose(
        head: CGPoint(x: 0.5, y: 0.14), neck: CGPoint(x: 0.5, y: 0.28), hip: CGPoint(x: 0.5, y: 0.58),
        leftElbow: CGPoint(x: 0.4, y: 0.18), leftHand: CGPoint(x: 0.36, y: 0.04),
        rightElbow: CGPoint(x: 0.6, y: 0.18), rightHand: CGPoint(x: 0.64, y: 0.04),
        leftKnee: CGPoint(x: 0.48, y: 0.76), leftFoot: CGPoint(x: 0.49, y: 0.94),
        rightKnee: CGPoint(x: 0.52, y: 0.76), rightFoot: CGPoint(x: 0.51, y: 0.94)
    )

    /// Knees softly bent, arms held out to the sides.
    private static var plie: Pose {
        var pose = standing(x: 0.5, bob: 0.05)
        pose.leftElbow = CGPoint(x: 0.36, y: 0.36)
        pose.leftHand = CGPoint(x: 0.22, y: 0.34)
        pose.rightElbow = CGPoint(x: 0.64, y: 0.36)
        pose.rightHand = CGPoint(x: 0.78, y: 0.34)
        pose.leftKnee = CGPoint(x: 0.42, y: 0.79)
        pose.rightKnee = CGPoint(x: 0.58, y: 0.79)
        return pose
    }

    /// Up on her toes, arms raised in a V.
    private static var taDa: Pose {
        var pose = standing(x: 0.5, bob: -0.02)
        pose.leftElbow = CGPoint(x: 0.38, y: 0.14)
        pose.leftHand = CGPoint(x: 0.3, y: 0.0)
        pose.rightElbow = CGPoint(x: 0.62, y: 0.14)
        pose.rightHand = CGPoint(x: 0.7, y: 0.0)
        pose.leftFoot.y = 0.95
        pose.rightFoot.y = 0.95
        return pose
    }

    private static let falling = Pose(
        head: CGPoint(x: 0.5, y: 0.14), neck: CGPoint(x: 0.5, y: 0.28), hip: CGPoint(x: 0.5, y: 0.58),
        leftElbow: CGPoint(x: 0.36, y: 0.16), leftHand: CGPoint(x: 0.3, y: 0.0),
        rightElbow: CGPoint(x: 0.64, y: 0.16), rightHand: CGPoint(x: 0.7, y: 0.0),
        leftKnee: CGPoint(x: 0.42, y: 0.74), leftFoot: CGPoint(x: 0.36, y: 0.86),
        rightKnee: CGPoint(x: 0.58, y: 0.74), rightFoot: CGPoint(x: 0.64, y: 0.86)
    )

    private static let crouch = Pose(
        head: CGPoint(x: 0.42, y: 0.5), neck: CGPoint(x: 0.47, y: 0.62), hip: CGPoint(x: 0.6, y: 0.76),
        leftElbow: CGPoint(x: 0.4, y: 0.8), leftHand: CGPoint(x: 0.32, y: 0.97),
        rightElbow: CGPoint(x: 0.66, y: 0.6), rightHand: CGPoint(x: 0.82, y: 0.52),
        leftKnee: CGPoint(x: 0.44, y: 0.78), leftFoot: CGPoint(x: 0.44, y: 0.97),
        rightKnee: CGPoint(x: 0.66, y: 0.97), rightFoot: CGPoint(x: 0.84, y: 0.97)
    )

    fileprivate static func mix(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        Pose(
            head: mix(a.head, b.head, t), neck: mix(a.neck, b.neck, t), hip: mix(a.hip, b.hip, t),
            leftElbow: mix(a.leftElbow, b.leftElbow, t), leftHand: mix(a.leftHand, b.leftHand, t),
            rightElbow: mix(a.rightElbow, b.rightElbow, t), rightHand: mix(a.rightHand, b.rightHand, t),
            leftKnee: mix(a.leftKnee, b.leftKnee, t), leftFoot: mix(a.leftFoot, b.leftFoot, t),
            rightKnee: mix(a.rightKnee, b.rightKnee, t), rightFoot: mix(a.rightFoot, b.rightFoot, t)
        )
    }

    /// Glides backwards for two beats then forwards for two, feet alternating heel-toe.
    private static func moonwalk(beat: Int, fraction: Double, swing: Double, lift: Double, isEven: Bool) -> Pose {
        let progress = (Double(beat % 4) + fraction) / 4
        let glide = progress < 0.5 ? progress * 2 : 2 - progress * 2
        let x = 0.62 - glide * 0.24
        var pose = standing(x: x, bob: 0)
        // One leg straight and sliding back, the other bent with the heel raised.
        let bent = (knee: CGPoint(x: x + 0.07, y: 0.77), foot: CGPoint(x: x + 0.01, y: 0.95))
        let straight = (knee: CGPoint(x: x - 0.03, y: 0.77), foot: CGPoint(x: x - 0.08, y: 0.97))
        pose.leftKnee = mix(bent.knee, straight.knee, swing)
        pose.leftFoot = mix(bent.foot, straight.foot, swing)
        pose.rightKnee = mix(straight.knee, bent.knee, swing)
        pose.rightFoot = mix(straight.foot, bent.foot, swing)
        liftLeg(&pose, left: !isEven, by: lift * 0.07)
        // Arms swing in opposition, each staying on its own side.
        pose.leftElbow = CGPoint(x: x - 0.09, y: 0.42)
        pose.leftHand = CGPoint(x: x - 0.08 - 0.08 * swing, y: 0.56 - 0.04 * swing)
        pose.rightElbow = CGPoint(x: x + 0.09, y: 0.42)
        pose.rightHand = CGPoint(x: x + 0.08 + 0.08 * (1 - swing), y: 0.56 - 0.04 * (1 - swing))
        return pose
    }

    /// Points to the sky on one beat and across the hips on the next, hips swaying.
    private static func discoPoint(swing: Double) -> Pose {
        let x = 0.5 + (swing - 0.5) * 0.08
        var pose = standing(x: x, bob: 0)
        pose.rightElbow = mix(CGPoint(x: x + 0.16, y: 0.16), CGPoint(x: x - 0.02, y: 0.48), swing)
        pose.rightHand = mix(CGPoint(x: x + 0.32, y: 0.0), CGPoint(x: x - 0.18, y: 0.66), swing)
        pose.leftElbow = CGPoint(x: x - 0.16, y: 0.42)
        pose.leftHand = CGPoint(x: x - 0.06, y: 0.56)
        pose.leftKnee = CGPoint(x: x - 0.1, y: 0.77)
        pose.leftFoot = CGPoint(x: x - 0.16, y: 0.97)
        pose.rightKnee = CGPoint(x: x + 0.1, y: 0.77)
        pose.rightFoot = CGPoint(x: x + 0.16, y: 0.97)
        return pose
    }

    /// Dips on every click with both arms waving overhead.
    private static func bounce(fraction: Double, swing: Double) -> Pose {
        let x = 0.5
        let dip = 0.06 * (1 - sin(.pi * fraction))
        var pose = standing(x: x, bob: dip)
        let wave = (swing - 0.5) * 0.12
        pose.leftElbow = CGPoint(x: x - 0.17 + wave, y: 0.2 + dip)
        pose.leftHand = CGPoint(x: x - 0.26 + wave * 2, y: 0.02 + dip)
        pose.rightElbow = CGPoint(x: x + 0.17 + wave, y: 0.2 + dip)
        pose.rightHand = CGPoint(x: x + 0.26 + wave * 2, y: 0.02 + dip)
        pose.leftKnee = CGPoint(x: x - 0.12 - dip, y: 0.77)
        pose.leftFoot = CGPoint(x: x - 0.12, y: 0.97)
        pose.rightKnee = CGPoint(x: x + 0.12 + dip, y: 0.77)
        pose.rightFoot = CGPoint(x: x + 0.12, y: 0.97)
        return pose
    }

    /// Alternately lifts each knee while the arms pump.
    private static func runningMan(swing: Double, lift: Double, isEven: Bool) -> Pose {
        let x = 0.5
        var pose = standing(x: x, bob: 0)
        let up = (knee: CGPoint(x: x + 0.12, y: 0.64), foot: CGPoint(x: x + 0.04, y: 0.82))
        let down = (knee: CGPoint(x: x - 0.04, y: 0.78), foot: CGPoint(x: x - 0.1, y: 0.97))
        pose.leftKnee = mix(up.knee, down.knee, swing)
        pose.leftFoot = mix(up.foot, down.foot, swing)
        pose.rightKnee = mix(down.knee, up.knee, swing)
        pose.rightFoot = mix(down.foot, up.foot, swing)
        liftLeg(&pose, left: isEven, by: lift * 0.08)
        // Fists pump up and down in opposition, one each side.
        pose.leftElbow = CGPoint(x: x - 0.13, y: 0.4)
        pose.leftHand = CGPoint(x: x - 0.1, y: 0.26 + 0.24 * swing)
        pose.rightElbow = CGPoint(x: x + 0.13, y: 0.4)
        pose.rightHand = CGPoint(x: x + 0.1, y: 0.5 - 0.24 * swing)
        return pose
    }

    /// Squats with knees wide, one hand on a knee, the other arm circling once per beat.
    private static func windmill(fraction: Double) -> Pose {
        let x = 0.5
        var pose = squat(x: x, depth: 0.05, kneeSpread: 0.15)
        // Straight up on each click, all the way round by the next.
        let angle = -Double.pi / 2 + 2 * .pi * fraction
        let reach = 0.26
        // Circle from a shoulder beside the neck, so the arm clears the head.
        let shoulder = CGPoint(x: pose.neck.x + 0.12, y: pose.neck.y + 0.02)
        pose.rightHand = CGPoint(x: shoulder.x + cos(angle) * reach, y: shoulder.y + sin(angle) * reach)
        pose.rightElbow = mix(shoulder, pose.rightHand, 0.5)
        pose.leftElbow = CGPoint(x: x - 0.16, y: 0.5)
        pose.leftHand = mix(pose.leftKnee, pose.hip, 0.1)
        return pose
    }

    /// The same pose facing the other way.
    var mirrored: Pose {
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.x, y: p.y) }
        return Pose(
            head: flip(head), neck: flip(neck), hip: flip(hip),
            leftElbow: flip(rightElbow), leftHand: flip(rightHand),
            rightElbow: flip(leftElbow), rightHand: flip(leftHand),
            leftKnee: flip(rightKnee), leftFoot: flip(rightFoot),
            rightKnee: flip(leftKnee), rightFoot: flip(leftFoot)
        )
    }

    /// The Charleston "bee's knees": knees swing together and apart, and the hands
    /// swap knees each time they meet.
    private static func beesKnees(swing: Double) -> Pose {
        let x = 0.5
        var pose = squat(x: x, depth: 0.04, kneeSpread: 0.02 + 0.14 * swing)
        pose.leftFoot = CGPoint(x: x - 0.1, y: 0.97)
        pose.rightFoot = CGPoint(x: x + 0.1, y: 0.97)
        let onOwn = (left: pose.leftKnee, right: pose.rightKnee)
        // Crossed over while the knees are together, on their own knees when apart.
        pose.leftHand = mix(onOwn.right, onOwn.left, swing)
        pose.rightHand = mix(onOwn.left, onOwn.right, swing)
        pose.leftHand.y -= 0.03
        pose.rightHand.y -= 0.03
        pose.leftElbow = CGPoint(x: x - 0.12, y: 0.48)
        pose.rightElbow = CGPoint(x: x + 0.12, y: 0.48)
        return pose
    }

    /// Straight arms swing from side to side as the hips swing the other way.
    private static func floss(swing: Double) -> Pose {
        let x = 0.5
        let side = (swing - 0.5) * 0.36
        var pose = standing(x: x, bob: 0)
        pose.hip.x = x - side * 0.4
        pose.leftHand = CGPoint(x: x + side - 0.04, y: 0.62)
        pose.rightHand = CGPoint(x: x + side + 0.04, y: 0.62)
        pose.leftElbow = mix(pose.neck, pose.leftHand, 0.5)
        pose.rightElbow = mix(pose.neck, pose.rightHand, 0.5)
        pose.leftKnee = CGPoint(x: pose.hip.x - 0.06, y: 0.77)
        pose.rightKnee = CGPoint(x: pose.hip.x + 0.06, y: 0.77)
        return pose
    }

    /// Clicks between stiff right-angled arm positions, one per beat.
    private static func robot(beat: Int, snap: Double) -> Pose {
        let x = 0.5
        let armPoses: [(leftElbow: CGPoint, leftHand: CGPoint, rightElbow: CGPoint, rightHand: CGPoint)] = [
            (CGPoint(x: x - 0.16, y: 0.3), CGPoint(x: x - 0.16, y: 0.12), CGPoint(x: x + 0.16, y: 0.3), CGPoint(x: x + 0.16, y: 0.46)),
            (CGPoint(x: x - 0.16, y: 0.3), CGPoint(x: x - 0.16, y: 0.46), CGPoint(x: x + 0.16, y: 0.3), CGPoint(x: x + 0.16, y: 0.12)),
            (CGPoint(x: x - 0.14, y: 0.42), CGPoint(x: x - 0.02, y: 0.42), CGPoint(x: x + 0.16, y: 0.3), CGPoint(x: x + 0.3, y: 0.3)),
            (CGPoint(x: x - 0.16, y: 0.3), CGPoint(x: x - 0.3, y: 0.3), CGPoint(x: x + 0.14, y: 0.42), CGPoint(x: x + 0.02, y: 0.42)),
        ]
        let from = armPoses[(beat % 4 + 7) % 4], to = armPoses[(beat % 4 + 4) % 4]
        var pose = standing(x: x, bob: 0)
        pose.leftElbow = mix(from.leftElbow, to.leftElbow, snap)
        pose.leftHand = mix(from.leftHand, to.leftHand, snap)
        pose.rightElbow = mix(from.rightElbow, to.rightElbow, snap)
        pose.rightHand = mix(from.rightHand, to.rightHand, snap)
        // The head ticks side to side too.
        pose.head.x = x + (beat % 2 == 0 ? 0.02 : -0.02) * snap
        return pose
    }

    /// One hand behind the head, the other arm stepping across in jerks, then
    /// sweeping back, with a little knee bounce on each step.
    private static func sprinkler(beat: Int, snap: Double, lift: Double) -> Pose {
        let x = 0.5
        let reaches = [0.32, 0.24, 0.16, 0.08]
        let from = reaches[(beat % 4 + 7) % 4], to = reaches[(beat % 4 + 4) % 4]
        let reach = from + (to - from) * snap
        var pose = squat(x: x, depth: 0.03 * lift, kneeSpread: 0.08)
        pose.leftElbow = CGPoint(x: x - 0.15, y: pose.neck.y - 0.06)
        pose.leftHand = CGPoint(x: x - 0.03, y: pose.head.y - 0.02)
        pose.rightHand = CGPoint(x: x + reach, y: pose.neck.y + 0.04)
        pose.rightElbow = mix(pose.neck, pose.rightHand, 0.5)
        return pose
    }

    /// Knees bent and swivelling from side to side, arms swinging against them.
    private static func twist(swing: Double, lift: Double) -> Pose {
        let x = 0.5
        let lean = (swing - 0.5) * 0.16
        var pose = squat(x: x, depth: 0.04 + 0.02 * lift, kneeSpread: 0.06)
        pose.hip.x = x + lean * 0.5
        pose.leftKnee.x += lean
        pose.rightKnee.x += lean
        pose.leftFoot = CGPoint(x: x - 0.08, y: 0.97)
        pose.rightFoot = CGPoint(x: x + 0.08, y: 0.97)
        pose.leftElbow = CGPoint(x: x - 0.12 - lean, y: 0.44)
        pose.leftHand = CGPoint(x: x - 0.16 - lean * 1.5, y: 0.34)
        pose.rightElbow = CGPoint(x: x + 0.12 - lean, y: 0.44)
        pose.rightHand = CGPoint(x: x + 0.16 - lean * 1.5, y: 0.34)
        return pose
    }

    /// Knees bent and apart, with the upper body lowered by `depth`.
    private static func squat(x: Double, depth: Double, kneeSpread: Double) -> Pose {
        var pose = standing(x: x, bob: depth)
        pose.leftKnee = CGPoint(x: x - kneeSpread, y: 0.77)
        pose.rightKnee = CGPoint(x: x + kneeSpread, y: 0.77)
        // Feet a little narrower than the knees, for a bow-legged squat.
        let feet = max(kneeSpread * 0.75, 0.1)
        pose.leftFoot = CGPoint(x: x - feet, y: 0.97)
        pose.rightFoot = CGPoint(x: x + feet, y: 0.97)
        return pose
    }

    /// Raises a leg's knee forward and its foot off the floor, so passing legs don't overlap.
    private static func liftLeg(_ pose: inout Pose, left: Bool, by amount: Double) {
        if left {
            pose.leftKnee.x += amount
            pose.leftKnee.y -= amount
            pose.leftFoot.y -= amount
        } else {
            pose.rightKnee.x += amount
            pose.rightKnee.y -= amount
            pose.rightFoot.y -= amount
        }
    }

    /// Upright, arms by the sides; `bob` lowers the upper body.
    fileprivate static func standing(x: Double, bob: Double) -> Pose {
        Pose(
            head: CGPoint(x: x, y: 0.12 + bob),
            neck: CGPoint(x: x, y: 0.26 + bob),
            hip: CGPoint(x: x, y: 0.58 + bob),
            leftElbow: CGPoint(x: x - 0.08, y: 0.42 + bob), leftHand: CGPoint(x: x - 0.1, y: 0.56 + bob),
            rightElbow: CGPoint(x: x + 0.08, y: 0.42 + bob), rightHand: CGPoint(x: x + 0.1, y: 0.56 + bob),
            leftKnee: CGPoint(x: x - 0.06, y: 0.77), leftFoot: CGPoint(x: x - 0.08, y: 0.97),
            rightKnee: CGPoint(x: x + 0.06, y: 0.77), rightFoot: CGPoint(x: x + 0.08, y: 0.97)
        )
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
