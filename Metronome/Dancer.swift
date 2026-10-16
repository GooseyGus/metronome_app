import SwiftUI

/// Easter egg reward: a stick figure dancing in time with the click.
/// With a time signature it changes move every bar; without one it keeps the same
/// move until tapped. While stopped it idles, waiting to dance. On its first arrival
/// it drops in and does a superhero landing. Once every move has been danced, a
/// partner drops in beside it and dances its mirror image.
struct DancerGlyph: View {
    let metronome: Metronome
    let palette: Palette
    let isPlaying: Bool
    let landingTime: Date?
    /// Beats per bar while the time signature is on; nil when it's off.
    let beatsPerBar: Int?
    /// Moves skipped by tapping.
    let moveOffset: Int
    /// When the partner lands, once she's been unlocked.
    let partnerLandingTime: Date?
    /// Reports each move as it starts, so the partner can be unlocked.
    let onMove: (Int) -> Void

    static var moveCount: Int { DanceMove.allCases.count }
    /// How wide the glyph should be, relative to its height.
    static func aspectRatio(withPartner: Bool) -> CGFloat { withPartner ? 2.3 : 1.3 }

    private let partnerColour = Color(hex: 0xF4A3C0)
    /// How long the partner takes to drop in from above before landing.
    static let partnerDropDuration = 0.45

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let phase = metronome.beatPhase() ?? 0
            // Follow the engine's bars, so moves change exactly on the accented downbeat.
            let bar = beatsPerBar == nil ? 0 : metronome.bar(containingBeat: Int(floor(phase)))
            let moveIndex = (bar + moveOffset) % Self.moveCount
            let move = DanceMove.allCases[moveIndex]
            let idleTime = now.timeIntervalSinceReferenceDate

            let dance = isPlaying ? Pose.at(beatPhase: phase, move: move) : Pose.idle(at: idleTime)
            let sinceLanding = landingTime.map { now.timeIntervalSince($0) } ?? .infinity
            let pose = Pose.landing(at: sinceLanding, thenDancing: dance)

            // The partner mirrors the dance; while idle she does her own thing.
            let partnerDance = isPlaying ? dance.mirrored : Pose.idle(at: idleTime + 29).mirrored
            let sincePartnerLanding = partnerLandingTime.map { now.timeIntervalSince($0) }

            Canvas { context, size in
                let unit = size.height
                if let sincePartnerLanding {
                    draw(pose, in: &context, centreX: size.width * 0.28, unit: unit, colour: palette.text)
                    // Drops in from above the glyph, then lands like he did.
                    let drop = max(-sincePartnerLanding / Self.partnerDropDuration, 0)
                    let partnerPose = Pose.landing(at: sincePartnerLanding, thenDancing: partnerDance)
                    draw(partnerPose, in: &context, centreX: size.width * 0.72, unit: unit, colour: partnerColour,
                         isPartner: true, dropOffset: -unit * 1.2 * drop * drop)
                } else {
                    draw(pose, in: &context, centreX: size.width / 2, unit: unit, colour: palette.text)
                }
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

    /// Draws one stick figure. Poses use a unit square, y pointing down, fitted to the height.
    private func draw(
        _ pose: Pose, in context: inout GraphicsContext, centreX: CGFloat, unit: CGFloat, colour: Color,
        isPartner: Bool = false, dropOffset: CGFloat = 0
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
        func ease(_ t: Double) -> Double { (1 - cos(.pi * min(max(t, 0), 1))) / 2 }

        switch time {
        case ..<0: return falling
        case ..<impact: return mix(falling, crouch, time / impact)
        case ..<hold: return crouch
        case ..<rise: return mix(crouch, standing(x: 0.5, bob: 0), ease((time - hold) / (rise - hold)))
        case ..<blend: return mix(standing(x: 0.5, bob: 0), dance, ease((time - rise) / (blend - rise)))
        default: return dance
        }
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

    private static func mix(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
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
        let from = armPoses[(beat + 3) % 4], to = armPoses[beat % 4]
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
        let from = reaches[(beat + 3) % 4], to = reaches[beat % 4]
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
