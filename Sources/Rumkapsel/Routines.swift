import AppKit
import SceneKit

/// The little routine a body plays while it works: one per activity, and four more at the cone.
///
/// The station's tick plays these on the floor; the gallery plays them on a tile. Both read this
/// file, so a tile cannot show a motion the app does not draw. Nothing here touches a station, a
/// node or a clock of its own: facts in, a pose out, and the one-off of the beat named rather than
/// played, for whoever is drawing to put where it stands.
enum Routines {

    /// How a body holds itself for one beat.
    struct Motion {
        var tilt = 0.0, roll = 0.0, spin = 0.0, lean = 0.0
        /// The body up off the floor, when the routine lifts it.
        var lift: Double?
        /// Where the torch points, when the routine aims one.
        var aim: SCNVector3?
        /// The hammer's own pitch, when the routine swings one.
        var hammerPitch: Double?
        /// The scanner's lamp, lit or dark.
        var scanner: Bool?
        /// What happens once on this beat.
        var flash: Flash?
    }

    /// A routine's one-off: named here, drawn by whoever is drawing.
    enum Flash {
        /// The welding arc this frame: lit or dark, and how bright.
        case weld(on: Bool, intensity: Double)
        /// The hammer has just landed on the cone.
        case strike
        /// QA passed one: a tick floats off the head.
        case tick
    }

    // MARK: at the cone

    /// The four tools a body works a cone with, in the order `Body.toolSlot` picks them.
    static let coneTools: [Minion.Tool] = [.goggles, .hammer, .scanner, .flashlight]

    /// Working the cone: welding, hammering, pushing and pulling, or bent over it by torchlight.
    /// `struck` is the caller's memory of whether the hammer is still up from the last beat.
    static func cone(slot: Int, t: Double, struck: inout Bool) -> Motion {
        var m = Motion()
        switch slot {
        case 0:
            m.tilt = 0.32
            let on = Double.random(in: 0...1) < 0.55
            m.flash = .weld(on: on, intensity: on ? Double.random(in: 300...1200) : 0)
        case 1:
            // Quick drop onto the peak, slower lift back: the grip pitches, the body only leans a little.
            let phase = (t * 1.1).truncatingRemainder(dividingBy: 1)
            let swing = phase < 0.25 ? pow(phase / 0.25, 2) : 1 - pow((phase - 0.25) / 0.75, 1.5)
            m.hammerPitch = Minion.hammerRest + (Minion.hammerStrike - Minion.hammerRest) * swing
            m.tilt = swing * 0.14
            if swing > 0.97 && !struck { struck = true; m.flash = .strike }
            if swing < 0.2 { struck = false }
        case 2:
            m.lean = sin(t * 2.5) * 0.05
            m.tilt = 0.12 + sin(t * 2.5) * 0.08
        default:
            // Inspecting the cone by torchlight: the beam wanders over it.
            m.tilt = 0.18 + sin(t * 1.5) * 0.04
            m.aim = SCNVector3(0.35 + sin(t * 1.3) * 0.25, sin(t * 0.9) * 0.45, 0)
        }
        return m
    }

    // MARK: at the desk

    /// What the hands hold for an activity, away from a cone.
    static func tool(for activity: Activity) -> Minion.Tool? {
        switch activity {
        case .testing, .running: return .scanner
        case .exploring: return .flashlight
        case .coding, .reading, .writing, .qa, .planning, .skill: return .tablet
        default: return nil
        }
    }

    /// One little routine per activity, so you can tell at a glance what a body is up to. `clock` is
    /// the raw scene clock, which only the scanner's blink reads; `t` is the body's own tempo-shifted
    /// one, and `dt` is what the last beat took.
    static func working(_ activity: Activity, t: Double, dt: Double, clock: Double) -> Motion {
        var m = Motion()
        m.scanner = tool(for: activity) == .scanner ? Int(clock * 6) % 2 == 0 : nil
        switch activity {
        case .coding: m.tilt = sin(t * 14) * 0.06                       // typing: quick nods
        case .exploring:                                                // reading code: the torch plays over the boxes
            m.tilt = 0.12; m.spin = sin(t * 1.2) * 0.7
            m.aim = SCNVector3(0.3 + sin(t * 1.7) * 0.2, sin(t * 0.8) * 0.3, 0)
        case .writing: m.tilt = 0.2 + sin(t * 3) * 0.06                 // writing: head down over the clipboard, small nods
        case .thinking: m.tilt = -0.18; m.roll = sin(t * 1.4) * 0.14    // thinking: head back, slow sway
        case .planning: m.tilt = -0.12 + sin(t * 2) * 0.05              // planning: looking up
        case .reading: m.tilt = -0.18                                   // reading your message: head back
        case .testing: m.spin = sin(t * 1.6) * 0.6; m.tilt = 0.1        // testing: sweeping the scanner across
        case .running: m.tilt = sin(t * 22) * 0.04; m.roll = cos(t * 19) * 0.04   // running things: jittery
        case .shipping: m.roll = sin(t * 9) * 0.16                      // shipping: excited wiggle
        case .skill: m.tilt = 0.15; m.roll = sin(t * 3) * 0.05          // using a skill: heads-down on the tablet
        case .delegating: m.spin = sin(t * 4) * 0.3                     // delegating: glancing about
        case .qa:
            // QA on the test deck: facing a stack, the scanner sweeping it from the floor to the top,
            // a tick now and then.
            m.tilt = 0.08 + sin(t * 1.4) * 0.22; m.spin = 0
            if Int(t * 2) % 9 == 0 && Int((t - dt) * 2) % 9 != 0 { m.flash = .tick }
        default: m.roll = sin(t * 5) * 0.07
        }
        return m
    }

    // MARK: what a body wears

    /// Everything a body wears or holds, all of it together.
    ///
    /// An outfit is complete: every prop has a value in it, so putting one on replaces the lot.
    /// That is the whole point of it. Props used to be switched on where an activity began and
    /// switched off where that activity was thought to end — and an activity has more ways to end
    /// than the one that was thought of, so the leftovers were worn into the next one: the bath's
    /// pixels over an office desk, a towel long after the drying, the pallet's rod at a console.
    /// Nothing is carried over now, because nothing persists: the kit is worked out again from what
    /// the body is doing on every frame, and there is nothing left to forget to take off.
    struct Outfit: Equatable {
        /// What is in the hands, if anything.
        var tool: Minion.Tool?
        /// The bath's pixels, for a body under the water and nowhere else.
        var pixels = false
        /// The towel off the rail, for as long as the drying lasts.
        var towel = false
    }

    /// The kit for what this body is doing now. `pallet` is what the station's hover pallet is up
    /// to, which only the simulation can say; everything else the body knows for itself.
    static func outfit(_ m: Minion, at clock: Double, pallet: (repo: String, pushing: Bool)?) -> Outfit {
        var kit = Outfit()
        kit.pixels = m.bathing && m.phaseKind == .act && m.path.isEmpty
        kit.towel = m.drying
        kit.tool = hands(m, at: clock, pallet: pallet)
        return kit
    }

    /// What the hands hold, in the order the floor settles it: the errand's own step first, then
    /// the cone's rota, then a fixture, then the day's work, then a book on the couch, and nothing
    /// otherwise.
    ///
    /// The errand is a chain of steps, and each step holds what that step needs rather than what
    /// the errand as a whole is for: walking to the terminal and working it is a tablet, and the
    /// wand only comes out once there is a pallet standing there to load.
    private static func hands(_ m: Minion, at clock: Double, pallet: (repo: String, pushing: Bool)?) -> Minion.Tool? {
        switch m.current?.kind {
        case .dispatch: return .tablet
        case .waitPallet(_, let repo): return pallet?.repo == repo ? .telekinesis : .tablet
        case .loadPallet, .unloadPallet: return .telekinesis
        case .pushPallet: return pallet?.pushing == true ? .hands : nil
        default: break
        }
        let resting = m.path.isEmpty && m.state == .settled
        let working = m.busy && resting && !m.isSubagent && m.activity != .waiting
            && !m.exercising && !m.bathing && !m.onJob
        if working, !m.pyramids.isEmpty, m.nearCone { return coneTools[m.toolSlot(at: clock)] }
        if m.exercising, m.phaseKind == .act, m.path.isEmpty, m.fetchSpot == nil { return nil }   // nothing in the hands on a fixture
        if working { return tool(for: m.activity) }
        if m.place == .lounge, resting, m.couch != nil { return .tablet }   // reading on the couch
        return nil
    }

    // MARK: waiting on you

    /// The impatient little hop of a body waiting on you, in its first minute.
    static func hop(clock: Double, phase: Double) -> Double { abs(sin(clock * 7 + phase)) * 0.14 }

    // MARK: the hands

    /// The two legs a crate travels from wherever the hands took it up onto the arms. `y` is where
    /// the crate starts in the body's own frame, `handsAt` the level it was taken from.
    static func liftLegs(from y: Double, handsAt: Int, headHeight: Double) -> [MotionLeg] {
        let via: SIMD3<Double>
        switch handsAt {
        case 0: via = SIMD3(0, headHeight * 0.45, 0.3)
        case 1: via = SIMD3(0, y, 0.2)
        default: via = SIMD3(0, max(headHeight + 0.2, y), 0.15)
        }
        return [MotionLeg(to: via, seconds: Hands.liftFirst, ease: .easeOut),
                MotionLeg(to: SIMD3(0, headHeight + 0.14, 0), seconds: Hands.liftSecond)]
    }

    /// And the two down onto a slot. Level 0 is set down carefully in front; level 1 slides forward
    /// onto the top at waist height; level 2 goes over the head and slides in; higher, with a hop.
    static func setDownLegs(to target: SIMD3<Double>, level: Int, headHeight: Double) -> [MotionLeg] {
        let via: SIMD3<Double>
        switch level {
        case 0: via = SIMD3(0, headHeight * 0.45, 0.3)
        case 1: via = SIMD3(0, target.y, 0.2)
        default: via = SIMD3(0, max(headHeight + 0.2, target.y), 0.15)
        }
        return [MotionLeg(to: via, seconds: Hands.setDownFirst),
                MotionLeg(to: target, seconds: Hands.setDownSecond, ease: level == 0 ? .easeIn : .easeOut)]
    }

    /// How a body is held over a crate at a level, as `Body.Posture` names it.
    static func posture(handsAt: Int) -> Body.Posture {
        switch handsAt {
        case 0: return .crouch
        case 1: return .waist
        case 2: return .reach
        default: return .jump
        }
    }

    /// The bend a posture puts in the body, on top of whatever routine it is playing. `hop` is how
    /// far up the little jump for a high stack has got, 0 to 1.
    static func hold(_ posture: Body.Posture, tilt: Double, roll: Double, hop: Double = 0) -> (tilt: Double, roll: Double, rise: Double) {
        switch posture {
        case .none: return (tilt, roll, 0)
        case .crouch: return (max(tilt, 0.28), 0, -0.12)   // knees bent, not a bow
        case .waist: return (max(tilt, 0.14), 0, 0)        // waist height: a lean, no crouch
        case .reach: return (min(tilt, -0.18), 0, 0.05)    // up on the toes, head back
        case .jump: return (min(tilt, -0.12), 0, hop * 0.28)
        }
    }
}
