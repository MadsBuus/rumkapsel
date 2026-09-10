// The props that run commands: shuttles flying in, rockets on the pad.

import AppKit
import SceneKit

/// One shuttle flight. Its command's phases are the flight itself: approach, descend, unload, rise,
/// leave. Each phase runs its own SCNAction and the tick moves to the next when its time is up.
final class Shuttle {
    let node: SCNNode
    let station: String
    let command: Command
    /// The flight path, in the hangar anchor's own space, so a station shifting does not misalign it.
    let high: SIMD3<Double>, down: SIMD3<Double>, exit: SIMD3<Double>
    /// Where the ship comes to rest facing, and the drift it settles into. Nil keeps its heading.
    let restYaw: Double?, drift: Double
    /// How far into the unload phase the cargo comes out, and how long the ship waits after.
    let unloadAt: Double, unloadFor: Double
    /// Setting the cargo down: the worker steps out, or the crate lands in the bay.
    let onUnload: () -> Void
    var phase = 0
    var until = 0.0
    private var unloaded = false

    init(node: SCNNode, station: String, command: Command, high: SIMD3<Double>, down: SIMD3<Double>,
         exit: SIMD3<Double>, restYaw: Double?, drift: Double, unloadAt: Double, unloadFor: Double,
         onUnload: @escaping () -> Void) {
        self.node = node; self.station = station; self.command = command
        self.high = high; self.down = down; self.exit = exit
        self.restYaw = restYaw; self.drift = drift
        self.unloadAt = unloadAt; self.unloadFor = unloadFor; self.onUnload = onUnload
    }

    var phaseKind: Command.Phase {
        let p = command.phases
        return p[min(phase, p.count - 1)]
    }

    /// How long each phase of a flight lasts. The unload phase holds the ship still over its slot.
    private var duration: Double {
        switch phaseKind {
        case .approach: return 3.0
        case .descend: return 4.5
        case .unload: return unloadAt + unloadFor
        case .rise: return 2.5
        default: return 3.0
        }
    }

    /// Starts the phase in hand.
    func begin(at clock: Double) {
        until = clock + duration
        switch phaseKind {
        case .approach:
            let a = SCNAction.move(to: v3(high.x, high.y, high.z), duration: 3.0)
            a.timingMode = .easeOut
            node.runAction(a)
        case .descend:
            let d = SCNAction.move(to: v3(down.x, down.y, down.z), duration: 4.5)
            d.timingMode = .easeInEaseOut
            guard let restYaw else { node.runAction(d); return }
            node.eulerAngles = SCNVector3(0, restYaw, 0)
            let turn = SCNAction.rotateTo(x: 0, y: restYaw + drift, z: 0, duration: 4.5, usesShortestUnitArc: true)
            turn.timingMode = .easeInEaseOut
            node.runAction(.group([d, turn]))
        case .unload:
            break
        case .rise:
            let r = SCNAction.move(to: v3(high.x, high.y, high.z), duration: 2.5)
            r.timingMode = .easeIn
            node.runAction(r)
        default:
            if restYaw != nil { node.look(at: v3(exit.x, exit.y, exit.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(1, 0, 0)) }
            let l = SCNAction.move(to: v3(exit.x, exit.y, exit.z), duration: 3.0)
            l.timingMode = .easeIn
            node.runAction(l)
        }
    }

    /// One frame of the flight. Returns false once the ship is gone.
    func advance(at clock: Double) -> Bool {
        if phaseKind == .unload, !unloaded, clock >= until - unloadFor { unloaded = true; onUnload() }
        guard clock >= until else { return true }
        guard phase + 1 < command.phases.count else { node.removeFromParentNode(); return false }
        phase += 1
        begin(at: clock)
        return true
    }
}

/// One repository's rocket. It runs one command at a time — standing by, loading, steaming, lifting
/// off — and a stage only ever moves forward.
final class Rocket {
    let station: String
    let repo: String
    var node: SCNNode
    var command: Command
    var phase = 0
    /// The clock the phase in hand began: a stuck haul may not ground a launch forever.
    var since = 0.0
    /// When the climb is over and the actor is done.
    var until = 0.0
    var label = ""
    var untested = false
    /// A production rocket is the tall one.
    var tall = true
    /// How much cargo the prop was drawn for, so it is only redrawn when that changes.
    var cargoShown = -1

    init(station: String, repo: String, node: SCNNode, command: Command) {
        self.station = station; self.repo = repo; self.node = node; self.command = command
    }

    var key: String { station + "|" + repo }

    var stage: Command.RocketStage {
        if case .rocket(let s, _, _) = command.kind { return s }
        return .standBy
    }

    var phaseKind: Command.Phase {
        let p = command.phases
        return p[min(phase, p.count - 1)]
    }

    /// Loading or steaming: the yard may not take its crates back and QA is over.
    var isBusy: Bool { stage.rank >= 1 }
    var isSteaming: Bool { if case .steam = stage { return true }; return false }
    var isLaunching: Bool { if case .launch = stage { return true }; return false }
}
