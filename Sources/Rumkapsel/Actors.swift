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
    /// The phase in hand: where it started, when, and where it is going. The flight is drawn from
    /// these on the station clock, so it pauses, steps and speeds with everything else.
    private var startedAt = 0.0
    private var from = SIMD3<Double>(0, 0, 0), to = SIMD3<Double>(0, 0, 0)
    private var yawFrom = 0.0, yawTo = 0.0, turning = false

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
        startedAt = clock
        from = SIMD3(Double(node.position.x), Double(node.position.y), Double(node.position.z))
        to = from
        turning = false
        switch phaseKind {
        case .approach: to = high
        case .descend:
            to = down
            if let restYaw {
                node.eulerAngles = SCNVector3(0, restYaw, 0)
                yawFrom = restYaw; yawTo = restYaw + drift; turning = true
            }
        case .unload: break
        case .rise: to = high
        default:
            if restYaw != nil { node.look(at: v3(exit.x, exit.y, exit.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(1, 0, 0)) }
            to = exit
        }
    }

    /// Where the ship is along the phase: eased the way each leg wants it.
    private func place(at clock: Double) {
        guard duration > 0, phaseKind != .unload else { return }
        let t = min(1, max(0, (clock - startedAt) / duration))
        let e: Double
        switch phaseKind {
        case .approach: e = 1 - (1 - t) * (1 - t)                 // ease out
        case .descend: e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2   // ease in, ease out
        default: e = t * t                                        // ease in
        }
        let p = from + (to - from) * e
        node.position = v3(p.x, p.y, p.z)
        if turning { node.eulerAngles.y = CGFloat(yawFrom + (yawTo - yawFrom) * e) }
    }

    /// One frame of the flight. Returns false once the ship is gone.
    func advance(at clock: Double) -> Bool {
        place(at: clock)
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
    /// Every crate handed a carry into this rocket, by `CrateRef.key`. The load is over when all of
    /// them have been set down on the pad and not one moment before: a rocket never launches empty.
    var assigned: Set<String> = []
    /// The carries ordered aboard that have not set their crate down yet, by command id.
    var pending: Set<Int> = []
    /// The last time the station said out loud that it is still waiting for cargo.
    var moaned = 0.0

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

/// One station's hover pallet. It has no command of its own: the dispatcher's does the talking, and
/// the pallet carries the crates, bobs where it stands and floats them on and off by magic.
final class Pallet {
    let station: String
    let repo: String
    let number: Int
    let node: SCNNode
    /// The dark patch on the floor under it. Its own node, because it must not bob with the slab.
    let shadow: SCNNode
    /// The blinking light on the corner, found once when the prop is built.
    let beacon: SCNNode?
    /// Which minion is running the errand.
    var dispatcher: String
    /// Where it hovers, in the station's own coordinates, and the phase of its bob.
    var spot: SIMD2<Double>
    let bobPhase = Double.random(in: 0..<6.28)
    /// The way to the deck, leg by leg: each one an axis-aligned target for the pallet's centre.
    var route: [SIMD2<Double>] = []
    /// The leg in hand: where it started and when the pushing began, for the ease-in.
    var legFrom = SIMD2<Double>(0, 0)
    var legAt = 0.0
    /// True while hands are actually on it and it is creeping along a leg.
    var pushing = false
    /// Crates still to lift, top of each stack first, and where each one goes.
    var toLoad: [(crate: CrateRef, node: SCNNode, slot: StationTruth.PalletSlot)] = []
    /// What stands on it now, in the order it was loaded.
    var aboard: [(crate: CrateRef, node: SCNNode)] = []
    /// The crate in the air right now, if any. One at a time, and the wand glows while it flies.
    var flight: Flight?
    /// When the pallet faded in, so its opacity can ride the station's own clock.
    var bornAt = 0.0

    /// A crate on its way through the air, moved by the tick rather than by an action, so it lands
    /// whether or not anything is drawing frames.
    struct Flight {
        let node: SCNNode
        let from: SIMD3<Double>, to: SIMD3<Double>
        let fromYaw: Double, toYaw: Double
        let at: Double
        let seconds: Double
        let land: () -> Void
    }
    /// The clock the next crate leaves the ground.
    var nextAt = 0.0
    /// Asked for while it was still loading: push it out, or empty it back into storage.
    var wantsPush = false
    var wantsBack = false
    /// Where it is in its errand, mirrored into station truth.

    init(station: String, repo: String, number: Int, node: SCNNode, shadow: SCNNode, dispatcher: String, spot: SIMD2<Double>) {
        self.station = station; self.repo = repo; self.number = number
        self.node = node; self.shadow = shadow; self.dispatcher = dispatcher; self.spot = spot
        self.beacon = node.childNode(withName: "beacon", recursively: true)
    }

    var isEmpty: Bool { aboard.isEmpty && toLoad.isEmpty && flight == nil }
    var isSettled: Bool { toLoad.isEmpty && flight == nil }
}
