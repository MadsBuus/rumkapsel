// One worker as the simulation knows it: where it is, what it holds, what it is doing and on what
// clock. No SceneKit here. `Minion` is a `Body` with a figure on it; the walk step and the rules
// run on bodies alone, so they can be stepped and tested without a picture.

import Foundation

class Body {
    enum State { case arriving, settled, leaving }

    var id: String
    var freeSince = 0.0        // clock when the worker's session went away; 0 while assigned
    var couch: Int?
    var nextImpatience = 0.0
    var station: String
    var home: Home
    var state: State = .arriving
    var busy = false
    var activity: Activity = .waiting
    var place: Place = .core
    /// The one job in hand, and how far into its phases the actor is. Everything a minion does is
    /// one of these: a carry, a delivery, somewhere to be, the bath, a chore, QA, leaving.
    var current: Command?
    var phase = 0
    /// At most one waits for the next interruptible phase.
    var pending: Command?
    /// When the phase in hand runs out: a crouch, a shower, a chore.
    var phaseUntil = 0.0
    /// What is on the arms, if anything: a crate by its number, or a new office's crate by its key.
    /// The scene draws it as a node on the figure from the moment it is set until `landing` says
    /// where it went.
    enum Load: Equatable {
        case crate(CrateRef)
        case office(String)
    }
    var load: Load?
    var hasLoad: Bool { load != nil }
    /// Where the load left the arms this frame: squarely on its slot, or on the floor behind after a
    /// drop. Nil when it simply went away. The scene puts the node there and clears it.
    struct Landing {
        var pos: SIMD3<Double>
        var yaw: Double?
        var dropped = false
    }
    var landing: Landing?
    /// The slot the load is going down onto, from the moment the set-down begins: the scene draws the
    /// arc from it. Nil while nothing is being set down.
    var settingDownOn: Spot?
    var fetchSpot: SIMD2<Double>?
    /// Which stack the QA walker is inspecting next.
    var qaStop = 0
    /// Until then the walk is a stroll, whatever the state: the way out of a closed office is not a hurry.
    var strollUntil = 0.0
    /// The simulator's wedge: not another step, whatever the command. For proving the station catches up.
    var wedged = false
    /// Prompts that came in before the office had unfolded: their cones land with the reveal.
    var owedCones = 0
    /// A carrier, deliverer or pusher walks at one pace whoever it is.
    var isHauling: Bool {
        switch current?.kind {
        case .carry, .deliverOffice, .pushPallet, .loadPallet, .unloadPallet: return true
        default: return false
        }
    }
    var hammerUp = false
    /// The poses the simulation decides and the scene draws: flat on the back in bed or on the bench,
    /// sat on the bowl (its middle at `seatOffset` in the body's own frame), or on the bench itself.
    var lying = false
    var seated = false
    var seatOffset = SIMD2<Double>(0, 0)
    var onBench = false
    var nextFidgetAt = 0.0
    var wakeUntil = 0.0
    /// A change of orders is visible: standing a beat, head up, before going.
    var wonderUntil = 0.0
    /// Who stood in the way on the last step, for the log.
    var blockedBy: String?
    /// A stall watch: since when the minion has stood still in the same phase of the same command,
    /// and whether the log has been told. Standing still through a phase that should move is a bug,
    /// and the log names it rather than leaving a body in a corner.
    var stallSince = 0.0
    var stallMark = ""
    /// The fact the command in hand is waiting on this tick, named by the command's own code; nil
    /// when it should be moving. Cleared at the top of every tick.
    var waitingOn: String?
    /// Which bath fixture is held: 0 the bowl, 1 the shower.
    var fixture: Int?
    /// Short stretches of work so far: every other one earns a pee.
    var shortStretches = 0

    var promptCount = 0
    var toolSeed: Int { abs(id.hashValue) % 4 }
    var pyramidCell: Cell?
    /// On the cone's cell or the one beside it: close enough to work it when its own cell is covered.
    var nearCone: Bool { pyramidCell.map { abs($0.x - cell.x) + abs($0.y - cell.y) <= 1 } ?? false }
    var toolCount: Int
    var title: String?
    var branch: String?
    var cwd: String
    var markers: [StationEvent: String] = [:]
    let isSubagent: Bool
    var facing = 0.0
    var isCrew = false
    var busyUntil = 0.0        // replay seconds, for crew minions
    var bed: Int?
    var pos: SIMD2<Double>
    var path: [SIMD2<Double>] = []
    var nextWanderAt = 0.0
    var nextBathAt = 0.0
    /// When the next turn in the gym is due, on the station clock; 0 until the lounge gets dull.
    var nextWorkoutAt = 0.0
    /// How long the visit in hand lasts once the minion is there, and when it got there. The clock starts on
    /// arrival, never when the walk began: the walk is not the visit.
    var actFor = 0.0
    var actStartedAt = 0.0
    /// A lounger's one idle clock: when it runs out, one thing to do is picked.
    var idle = IdleClock()
    /// Sent to bed from its bubble: it lies down whatever its session is up to, until it is sent elsewhere.
    var napping = false
    /// When this walk was last planned again because the floor changed under it: at most once a second.
    var lastReplanAt = -10.0
    /// How far the figure is drawn off the body's line while passing someone: a shoulder to the right. Drawing only.
    var lean = SIMD2<Double>(0, 0)
    var bathDue = 0.0          // clock when a visit is owed, 0 when none
    var busySince = 0.0
    var wasBusy = false
    var nextChoreAt = 0.0
    var showering = false
    var nextDropAt = 0.0
    var waitingSince = 0.0
    let bobPhase = Double.random(in: 0..<6.28)
    /// Everyone moves at their own pace, so a row of workers never nods in unison.
    var tempo: Double { 0.82 + bobPhase / 6.28 * 0.42 }
    /// Which tool is out at the cone right now: the rota runs on the minion's own clock and stint length.
    func toolSlot(at clock: Double) -> Int { (toolSeed + Int((clock + bobPhase * 4) / (5.5 + Double(toolSeed) * 1.7))) % 4 }
    /// Solid unless inside a shuttle: the arrival sets it to 0 and back to 1 as the worker steps out.
    var opacity = 1.0

    init(id: String, station: String, home: Home, cwd: String, toolCount: Int, isSubagent: Bool, start: Cell, crew: Bool = false) {
        self.id = id; self.station = station; self.home = home; self.cwd = cwd; self.toolCount = toolCount; self.isSubagent = isSubagent
        self.isCrew = crew
        pos = SIMD2(Double(start.x), Double(start.y))
    }

    /// The phase in hand.
    var phaseKind: Command.Phase {
        guard let c = current else { return .settle }
        let p = c.phases
        return p[min(phase, p.count - 1)]
    }
    /// Carrying, delivering or leaving: holding something, not free for anything else.
    var onJob: Bool { current?.isJob ?? false }
    /// Resting: only then do the couch and the bed pull.
    var isResting: Bool { current?.isRest ?? true }
    var isQA: Bool { if case .qa = current?.kind { return true }; return false }
    var isChore: Bool { if case .chore = current?.kind { return true }; return false }
    var bathing: Bool { if case .bath = current?.kind { return true }; return false }
    var exercising: Bool { if case .exercise = current?.kind { return true }; return false }
    var workout: Command.Workout? { if case .exercise(let k, _, _) = current?.kind { return k }; return nil }
    /// How the body is held over a crate, decided by how high the crate is.
    enum Posture { case none, crouch, waist, reach, jump }
    /// The level the hands are working at: 0 on the floor, 1 waist height, 2 and up a reach.
    var handsAt = 0
    var posture: Posture {
        switch current?.kind {
        case .pack, .stow: if phaseKind == .act { return .crouch }   // on the knees over the package or the cube
        default: break
        }
        guard phaseKind == .lift || phaseKind == .setDown, phaseUntil > 0 else { return .none }
        switch handsAt {
        case 0: return .crouch
        case 1: return .waist
        case 2: return .reach
        default: return .jump
        }
    }
    /// What it would say if you asked.
    var words: String { current?.words ?? "nothing in particular" }

    var cell: Cell { Cell(x: Int(pos.x.rounded()), y: Int(pos.y.rounded())) }

    /// Waiting on you: hopping for the first minute, pacing after that. Not while on a job.
    func isJumping(at clock: Double) -> Bool { activity == .waiting && clock - waitingSince < 60 && !onJob }
    func isPacing(at clock: Double) -> Bool { activity == .waiting && clock - waitingSince >= 60 && !onJob }
}
