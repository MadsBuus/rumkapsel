import AppKit
import SceneKit

enum Routines {
    struct Motion {
        var tilt = 0.0, roll = 0.0, spin = 0.0, lean = 0.0
        var lift: Double?
        var aim: SCNVector3?
        var hammerPitch: Double?
        var scanner: Bool?
        var flash: Flash?
    }

    enum Flash {
        case weld(on: Bool, intensity: Double)
        case strike
        case tick
    }

    // MARK: at the cone

    static let coneTools: [Minion.Tool] = [.goggles, .hammer, .scanner, .flashlight]

    static func cone(slot: Int, t: Double, struck: inout Bool) -> Motion {
        var m = Motion()
        switch slot {
        case 0:
            m.tilt = 0.32
            let on = Double.random(in: 0...1) < 0.55
            m.flash = .weld(on: on, intensity: on ? Double.random(in: 300...1200) : 0)
        case 1:
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
            m.tilt = 0.18 + sin(t * 1.5) * 0.04
            m.aim = SCNVector3(0.35 + sin(t * 1.3) * 0.25, sin(t * 0.9) * 0.45, 0)
        }
        return m
    }

    // MARK: at the desk

    static func tool(for activity: Activity) -> Minion.Tool? {
        switch activity {
        case .testing, .running: return .scanner
        case .exploring: return .flashlight
        case .coding, .reading, .writing, .qa, .planning, .skill: return .tablet
        default: return nil
        }
    }

    static func working(_ activity: Activity, t: Double, dt: Double, clock: Double) -> Motion {
        var m = Motion()
        m.scanner = tool(for: activity) == .scanner ? Int(clock * 6) % 2 == 0 : nil
        switch activity {
        case .coding: m.tilt = sin(t * 14) * 0.06
        case .exploring:
            m.tilt = 0.12; m.spin = sin(t * 1.2) * 0.7
            m.aim = SCNVector3(0.3 + sin(t * 1.7) * 0.2, sin(t * 0.8) * 0.3, 0)
        case .writing: m.tilt = 0.2 + sin(t * 3) * 0.06
        case .thinking: m.tilt = -0.18; m.roll = sin(t * 1.4) * 0.14
        case .planning: m.tilt = -0.12 + sin(t * 2) * 0.05
        case .reading: m.tilt = -0.18
        case .testing: m.spin = sin(t * 1.6) * 0.6; m.tilt = 0.1
        case .running: m.tilt = sin(t * 22) * 0.04; m.roll = cos(t * 19) * 0.04
        case .shipping: m.roll = sin(t * 9) * 0.16
        case .skill: m.tilt = 0.15; m.roll = sin(t * 3) * 0.05
        case .delegating: m.spin = sin(t * 4) * 0.3
        case .qa:
            m.tilt = 0.08 + sin(t * 1.4) * 0.22; m.spin = 0
            if Int(t * 2) % 9 == 0 && Int((t - dt) * 2) % 9 != 0 { m.flash = .tick }
        default: m.roll = sin(t * 5) * 0.07
        }
        return m
    }

    // MARK: what a body wears

    struct Outfit: Equatable {
        var tool: Minion.Tool?
        var pixels = false
        var towel = false
        var jetpack: Double?
        var mug = false
        var meal: Double?
        var scan = false
        var shard = false
    }

    static func outfit(_ m: Minion, at clock: Double) -> Outfit {
        var kit = Outfit()
        kit.pixels = m.bathing && m.phaseKind == .act && m.path.isEmpty
        kit.towel = m.drying
        kit.tool = hands(m, at: clock)
        if m.isSubagent {
            kit.scan = m.path.isEmpty && m.state == .settled && m.place == .room(m.home.key) && m.activity != .researching
            kit.shard = m.carrying
            return kit
        }
        let free = !m.onJob && !m.lying && !m.bathing && !m.exercising && m.place != .quarters
        kit.mug = free && clock < m.mugUntil
        if free, clock < m.mealUntil, m.mealFor > 0 { kit.meal = (m.mealUntil - clock) / m.mealFor; kit.tool = nil }
        return kit
    }

    private static func hands(_ m: Minion, at clock: Double) -> Minion.Tool? {
        let resting = m.path.isEmpty && m.state == .settled
        let working = m.busy && resting && !m.isSubagent && m.activity != .waiting
            && !m.exercising && !m.bathing && !m.onJob
        if working, !m.pyramids.isEmpty, m.nearCone { return coneTools[m.toolSlot(at: clock)] }
        if m.exercising, m.phaseKind == .act, m.path.isEmpty, m.fetchSpot == nil { return nil }
        if working { return tool(for: m.activity) }
        if m.place == .lounge, resting, m.couch != nil { return .tablet }
        return nil
    }

    // MARK: waiting on you

    static func hop(clock: Double, phase: Double) -> Double { abs(sin(clock * 7 + phase)) * 0.14 }

    // MARK: the hands

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

    static func floatLegs(from: SIMD3<Double>, to: SIMD3<Double>, headHeight: Double, toss: Bool) -> [MotionLeg] {
        let overhead = SIMD3(0, headHeight + 0.25, 0.1)
        let start = toss ? overhead : from
        let end = toss ? to : SIMD3(0, headHeight + 0.14, 0)
        let apex = SIMD3((start.x + end.x) / 2, max(start.y, end.y, 1.0) + 0.45, (start.z + end.z) / 2)
        let drift = [MotionLeg(to: apex, seconds: Hands.floatSeconds * 0.5, ease: .easeOut),
                     MotionLeg(to: end, seconds: Hands.floatSeconds * 0.5, ease: .easeInOut)]
        return toss ? [MotionLeg(to: overhead, seconds: Hands.setDownFirst, ease: .easeOut)] + drift : drift
    }

    static func posture(handsAt: Int) -> Body.Posture {
        switch handsAt {
        case 0: return .crouch
        case 1: return .waist
        case 2: return .reach
        default: return .jump
        }
    }

    static func hold(_ posture: Body.Posture, tilt: Double, roll: Double, hop: Double = 0) -> (tilt: Double, roll: Double, rise: Double) {
        switch posture {
        case .none: return (tilt, roll, 0)
        case .crouch: return (max(tilt, 0.28), 0, -0.12)
        case .waist: return (max(tilt, 0.14), 0, 0)
        case .reach: return (min(tilt, -0.18), 0, 0.05)
        case .jump: return (min(tilt, -0.12), 0, hop * 0.28)
        }
    }
}
