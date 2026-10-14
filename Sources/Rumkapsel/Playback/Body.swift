import Foundation

class Body {
    enum State { case arriving, settled, leaving }

    var id: String
    var freeSince = 0.0
    var couch: Int?
    var nextImpatience = 0.0
    var station: String
    var home: Home
    var state: State = .arriving
    var busy = false
    var activity: Activity = .waiting
    var place: Place = .core
    var current: Command?
    var phase = 0
    var phaseUntil = 0.0
    enum Load: Equatable {
        case crate(CrateRef)
        case office(Int)
    }
    var load: Load?
    var hasLoad: Bool { load != nil }
    struct Landing {
        var pos: SIMD3<Double>
        var yaw: Double?
        var dropped = false
    }
    var landing: Landing?
    var settingDownOn: Spot?
    var fetchSpot: SIMD2<Double>?
    var qaStop = 0
    var strollUntil = 0.0
    var wedged = false
    var owedCones = 0
    var isHauling: Bool {
        switch current?.kind {
        case .carry, .deliverOffice: return true
        default: return false
        }
    }
    var hammerUp = false
    var seatedOnBowl = false
    var seatOffset = SIMD2<Double>(0, 0)

    var seated: Bool { seatedOnBowl || onCouch }

    var onCouch: Bool {
        !onJob && path.isEmpty && state == .settled && isResting && place == .lounge && couch != nil
    }

    var seatSpot: SIMD2<Double> { seatedOnBowl ? seatOffset : SIMD2(0, 0) }
    var drying = false
    var nextFidgetAt = 0.0
    static let seatReach = 0.176
    var wakeUntil = 0.0
    var risingUntil = 0.0
    var beddingUntil = 0.0
    var beddedDown = false
    static let riseSit = 0.55
    var wonderUntil = 0.0
    var blockedBy: String?
    var stallSince = 0.0
    var stallMark = ""
    var waitingOn: String?
    var fixture: Int?
    var shortStretches = 0

    var promptCount = 0
    var toolSeed: Int { Int(stableHash(id) % 4) }
    var pyramidCell: Cell?
    var queued: [Cell] = []
    var cones: [Cell] { (pyramidCell.map { [$0] } ?? []) + queued }
    var nearCone: Bool { pyramidCell.map { abs($0.x - cell.x) + abs($0.y - cell.y) <= 1 } ?? false }
    var toolCount: Int
    var title: String?
    var branch: String?
    var cwd: String
    var markers: [StationEvent: String] = [:]
    let isSubagent: Bool
    var facing = 0.0
    var isCrew = false
    var isPeer = false
    var peerFed: String?
    var sharedCallsign: String?
    var callsign: String { sharedCallsign ?? Callsign.of(id) }
    var busyUntil = 0.0
    var bed: Int?
    var pos: SIMD2<Double>
    var path: [SIMD2<Double>] = []
    var nextWanderAt = 0.0
    var nextBathAt = 0.0
    var nextWorkoutAt = 0.0
    var actFor = 0.0
    var actStartedAt = 0.0
    var idle = IdleClock()
    var napping = false
    var lastReplanAt = -10.0
    var lean = SIMD2<Double>(0, 0)
    var passingId: String?
    var passWalked = 0.0
    var passedId: String?
    var bathDue = 0.0
    var busySince = 0.0
    var wasBusy = false
    var nextChoreAt = 0.0
    var showering = false
    var nextDropAt = 0.0
    var waitingSince = 0.0
    let bobPhase = Double.random(in: 0..<6.28)
    var tempo: Double { 0.82 + bobPhase / 6.28 * 0.42 }
    func toolSlot(at clock: Double) -> Int { (toolSeed + Int((clock + bobPhase * 4) / (5.5 + Double(toolSeed) * 1.7))) % 4 }
    var opacity = 1.0

    init(id: String, station: String, home: Home, cwd: String, toolCount: Int, isSubagent: Bool, start: Cell, crew: Bool = false) {
        self.id = id; self.station = station; self.home = home; self.cwd = cwd; self.toolCount = toolCount; self.isSubagent = isSubagent
        self.isCrew = crew
        pos = SIMD2(Double(start.x), Double(start.y))
    }

    var phaseKind: Command.Phase {
        guard let c = current else { return .settle }
        let p = c.phases
        return p[min(phase, p.count - 1)]
    }
    var onJob: Bool { current?.isJob ?? false }

    var lying: Bool {
        if onBench { return true }
        return beddedDown && risingUntil == 0 && beddingUntil == 0 && !onJob && path.isEmpty && state == .settled
            && (activity == .sleeping || napping) && place == .quarters
    }

    var onBench: Bool {
        exercising && workout == .bench && path.isEmpty && fetchSpot == nil && phaseKind == .act
    }

    var isFree: Bool {
        !onJob && !hasLoad && !isSubagent && !isCrew && !isPeer && !isQA
            && state != .leaving && wakeUntil == 0
            && (current == nil || phaseKind.interruptible)
    }
    var isResting: Bool { current?.isRest ?? true }
    var isQA: Bool { if case .qa = current?.kind { return true }; return false }
    var isChore: Bool { if case .chore = current?.kind { return true }; return false }
    var bathing: Bool { if case .bath = current?.kind { return true }; return false }
    var exercising: Bool { if case .exercise = current?.kind { return true }; return false }
    var choring: Bool { if case .chore = current?.kind { return true }; return false }
    var workout: Command.Workout? { if case .exercise(let k, _, _) = current?.kind { return k }; return nil }
    var fare: Command.Fare? { if case .galley(let f, _, _) = current?.kind { return f }; return nil }
    var atCounter = false
    var mugUntil = 0.0
    var mealUntil = 0.0, mealFor = 0.0
    enum Posture { case none, crouch, waist, reach, jump }
    var handsAt = 0
    var floating = false
    var posture: Posture {
        switch current?.kind {
        case .pack, .stow: if phaseKind == .act { return .crouch }
        default: break
        }
        guard phaseKind == .lift || phaseKind == .setDown, phaseUntil > 0 else { return .none }
        return Routines.posture(handsAt: handsAt)
    }
    var words: String {
        guard let c = current else { return "nothing in particular" }
        switch c.kind {
        case .goTo(let place) where path.isEmpty && state == .settled: return place.hereWords
        case .exercise(let kind, _, _) where phaseKind == .act && path.isEmpty: return kind.doing
        case .galley(let fare, _, _) where phaseKind == .act && path.isEmpty: return fare.doing
        case .bath(let kind, _, _) where phaseKind == .act && path.isEmpty: return kind == .shower ? "in the shower" : "on the toilet"
        default: return c.words
        }
    }

    var cell: Cell { Cell(x: Int(pos.x.rounded()), y: Int(pos.y.rounded())) }

    func isJumping(at clock: Double) -> Bool { activity == .waiting && clock - waitingSince < 60 && !onJob }
    func isPacing(at clock: Double) -> Bool { activity == .waiting && clock - waitingSince >= 60 && !onJob }
}
