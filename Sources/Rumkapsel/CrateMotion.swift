// The one way a crate's picture moves: a tween on the station clock, applied each tick. No scene
// action ever moves a crate, so a headless step moves them too, and nothing can move one twice.
import Foundation
import SceneKit

/// One leg of a crate's journey: where it ends up, how long it takes, how it eases.
struct MotionLeg {
    enum Ease { case linear, easeIn, easeOut, easeInOut }
    var to: SIMD3<Double>
    var seconds: Double
    var ease: Ease = .easeInOut
    var scale: Double? = nil   // end scale, when the leg shrinks or grows the crate
}

/// A crate node under way: its legs, when it started, and what to do when it lands. Positions are in
/// the node's parent's space, so a crate on the arms travels with the minion.
final class CrateMotion {
    let node: SCNNode
    let legs: [MotionLeg]
    let start: Double
    let from: SIMD3<Double>
    let yaw: (from: Double, to: Double)?
    let onDone: (() -> Void)?
    var total: Double { legs.reduce(0) { $0 + $1.seconds } }

    init(node: SCNNode, legs: [MotionLeg], start: Double, yawTo: Double?, onDone: (() -> Void)?) {
        self.node = node; self.legs = legs; self.start = start
        from = SIMD3(Double(node.position.x), Double(node.position.y), Double(node.position.z))
        yaw = yawTo.map { (Double(node.eulerAngles.y), $0) }
        self.onDone = onDone
    }

    private static func ease(_ t: Double, _ e: MotionLeg.Ease) -> Double {
        switch e {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }

    /// Places the node for this moment. True once the last leg is done.
    func apply(at clock: Double) -> Bool {
        var elapsed = max(0, clock - start)
        var at = from
        var scale = Double(node.scale.x)
        var done = true
        for leg in legs {
            if elapsed >= leg.seconds {
                elapsed -= leg.seconds; at = leg.to; if let s = leg.scale { scale = s }
                continue
            }
            let t = CrateMotion.ease(leg.seconds > 0 ? elapsed / leg.seconds : 1, leg.ease)
            let p = at + (leg.to - at) * t
            if let s = leg.scale { scale = scale + (s - scale) * t }
            at = p
            done = false
            break
        }
        node.position = SCNVector3(at.x, at.y, at.z)
        node.scale = SCNVector3(scale, scale, scale)
        if let yaw {
            let t = min(1, total > 0 ? (clock - start) / total : 1)
            node.eulerAngles.y = CGFloat(yaw.from + (yaw.to - yaw.from) * CrateMotion.ease(t, .easeInOut))
        }
        return done
    }
}

extension StationController {
    /// Starts a crate on its way. Any motion it already had is replaced; nothing else may move it.
    func moveCrate(_ node: SCNNode, legs: [MotionLeg], yawTo: Double? = nil, onDone: (() -> Void)? = nil) {
        crateMotions[ObjectIdentifier(node)] = CrateMotion(node: node, legs: legs, start: clock, yawTo: yawTo, onDone: onDone)
    }

    /// Whether a crate is under way.
    func crateMoving(_ node: SCNNode) -> Bool { crateMotions[ObjectIdentifier(node)] != nil }

    /// Every tick: place every crate under way, and finish the ones that have landed.
    func tickCrateMotions() {
        for (id, motion) in crateMotions where motion.apply(at: clock) {
            crateMotions[id] = nil
            motion.onDone?()
        }
    }

    /// A crate stops where it is; its picture is left exactly where the last tick put it.
    func stopCrate(_ node: SCNNode) { crateMotions[ObjectIdentifier(node)] = nil }
}
