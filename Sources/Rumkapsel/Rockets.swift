import Foundation

enum RocketGeometry {
    static let height = 1.5, radius = 0.17
    static let panels = 30
    static var hullRadius: Double { radius * 0.9 }
    static var apothem: Double { hullRadius * cos(.pi / 6) }
    static var hullBase: Double { 0.12 + height * 0.49 }
    static var hullHeight: Double { height * 0.4 }
    static let cradleTop = 0.3
    static var hatchInTip: SIMD3<Double> { SIMD3(apothem + 0.01, 0.12 + height * 0.6, 0) }
    static func tipDrop(lift: Double) -> Double { (cradleTop - hullBase) * (1 - min(1, max(0, lift))) }
    static func hatch(lift: Double) -> SIMD3<Double> { hatchInTip + SIMD3(0, tipDrop(lift: lift), 0) }
    static var kickGrip: Double { hullBase * 0.55 }
    static let platingSpan = 0.7
    static func facing(side k: Int) -> SIMD2<Double> {
        let a = .pi / 2 + Double(k) * .pi / 3
        return SIMD2(sin(a), cos(a))
    }
    static func side(facing way: SIMD2<Double>) -> Int {
        side(facing: way, among: Array(0..<6)) ?? 0
    }
    static func side(facing way: SIMD2<Double>, among sides: [Int]) -> Int? {
        sides.max { a, b in
            let fa = facing(side: a), fb = facing(side: b)
            return fa.x * way.x + fa.y * way.y < fb.x * way.x + fb.y * way.y
        }
    }
    static var rings: Int { panels / 6 }
    static var ringHeight: Double { hullHeight / Double(rings) }
    static func ringMiddle(_ ring: Int, lift: Double) -> Double {
        hullBase + tipDrop(lift: lift) + ringHeight * (Double(ring) + 0.5)
    }
}

final class RocketJob {
    let station: String
    let repo: String
    var command: Command
    var phase = 0
    var until = 0.0
    var label = ""
    var untested = false
    var tall = true
    var kick = Kick.none
    var kickSince = -1.0
    var kickAt: SIMD3<Double>?
    var kickWay: SIMD2<Double>?
    var lift = 0.0
    enum Kick: Equatable { case none, coming, docked, going }
    var cargo = 0
    var panels = RocketGeometry.panels
    var fresh = false
    var welded = Double(RocketGeometry.panels)
    var welding = false
    var seam = 0
    var deployRunning = false

    init(station: String, repo: String, command: Command) {
        self.station = station; self.repo = repo; self.command = command
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

    var isBusy: Bool { stage.rank >= 1 }
    var isSteaming: Bool { if case .steam = stage { return true }; return false }
    var isVenting: Bool { isSteaming && kick == .docked }
    var isLaunching: Bool { if case .launch = stage { return true }; return false }
}

extension Simulation {
    func rocket(station: String, repo: String, label: String, untested: Bool, tall: Bool, cargo: Int, command: Command) {
        guard fleet.stations[station] != nil, case .rocket(let stage, _, _) = command.kind else { return }
        let key = station + "|" + repo
        if let r = rockets[key] {
            r.label = label
            if r.stage.rank < 3 { r.cargo = cargo; r.untested = untested; r.tall = tall }
            if stage == .standBy, (1...2).contains(r.stage.rank) {
                take(r, command)
                return
            }
            guard stage.rank > r.stage.rank else { return }
            take(r, command)
            return
        }
        let r = RocketJob(station: station, repo: repo, command: command)
        r.label = label; r.untested = untested; r.tall = tall; r.cargo = cargo
        if tall { r.kick = .docked; r.lift = 1 }
        if let b = staging[key], b.deploy != .live {
            r.panels = 0
            r.welded = 0
            r.fresh = true
        }
        rockets[key] = r
        take(r, command)
    }

    func landed(_ crate: CrateRef, in yard: Yard) {
        guard let station = fleet.stations[crate.station] else { return }
        world.landed(station: station, repo: crate.repo, number: crate.number, in: yard, at: now)
        if yard == .storage, world.shipsOnMerge(station: station.name, repo: crate.repo) { launchOnMerge(station: station, repo: crate.repo) }
    }

    func launchOnMerge(station: Station, repo: String) {
        let key = station.name + "|" + repo
        guard rockets[key] == nil else { return }
        world.releases.mergeLaunches.insert(key)
        rocket(station: station.name, repo: repo, label: "rocket:\(world.waitingURL(repo: repo))|\(repo) · deployed on merge", untested: false, tall: true, cargo: 1,
               command: .rocket(.launch, station: station.name, repo: repo))
    }

    private func take(_ r: RocketJob, _ command: Command) {
        r.command = command
        r.phase = 0
        var empty = false
        if case .rocket(.load(0), _, _) = command.kind { empty = true }
        issue(command, by: "rocket", announce: !empty)
        beginRocketPhase(r)
    }

    private func beginRocketPhase(_ r: RocketJob) {
        switch r.phaseKind {
        case .load:
            cue(.rocketLoading(key: r.key))
            loadCrates(r)
        case .climb:
            world.clearPad(station: r.station, repo: r.repo)
            if world.releases.mergeLaunches.contains(r.key) { world.forgetShipped(station: r.station, repo: r.repo) }
            cue(.liftOff(key: r.key))
            r.until = clock + 15
            fleet.save()
        default:
            if r.isSteaming { cue(.steam(key: r.key)) }
        }
    }

    func stepRockets() {
        for r in Array(rockets.values) {
            switch r.phaseKind {
            case .load:
                guard r.isLaunching else { advanceRocket(r); continue }
                if let v = vortices[r.key] {
                    if v.closedAt != nil { advanceRocket(r) }
                    continue
                }
                loadCrates(r)
                if vortices[r.key] == nil { advanceRocket(r) }
            case .climb:
                if clock >= r.until {
                    rockets[r.key] = nil
                    cue(.rocketGone(key: r.key))
                    if world.releases.mergeLaunches.remove(r.key) != nil, let st = fleet.stations[r.station],
                       st.ledger.crates(of: r.repo).contains(where: { $0.placed == .storage }) {
                        launchOnMerge(station: st, repo: r.repo)
                    }
                }
            default: continue
            }
        }
    }

    private func advanceRocket(_ r: RocketJob) {
        if r.phase + 1 < r.command.phases.count {
            r.phase += 1
            beginRocketPhase(r)
            return
        }
        take(r, .rocket(.steam, station: r.station, repo: r.repo))
    }

    private func loadSource(_ r: RocketJob) -> Yard { world.stagingIsDeck(station: r.station, repo: r.repo) ? .deck : .storage }

    private func loadCrates(_ r: RocketJob) {
        guard let station = fleet.stations[r.station] else { return }
        let yard = loadSource(r)
        let repo = r.repo
        let standing = station.ledger.crates(of: repo).filter { $0.stands(in: yard) }.map(\.number)
        func shipped(_ n: Int) -> Bool? { world.works.find(repo: repo, crate: n).map { r in r.stage.map { $0 >= .shipped } ?? true } }
        var launching = false
        if case .rocket(.launch, _, _) = r.command.kind { launching = world.works.records(repo: repo).contains { r in r.stage.map { $0 >= .shipped } ?? false } }
        let numbers = launching ? standing.filter { shipped($0) ?? true } : standing
        guard !numbers.isEmpty, r.isLaunching else { return }
        openVortex(r, station: station, from: yard, crates: numbers)
    }

    func refreshRockets() {
        let live = world.padKeys()
        for (key, r) in rockets {
            guard let st = fleet.stations[r.station] else { continue }
            if !live.contains(key), !r.isBusy {
                rockets[key] = nil
                cue(.rocketGone(key: key))
                continue
            }
            if r.stage.rank == 0 { r.cargo = world.cargoWaiting(station: st, repo: r.repo) }
        }
    }

    func rocketSpot(station: Station, repo: String) -> SIMD2<Double>? {
        guard let slot = world.releases.padSlotOf[station.name + "|" + repo], !station.hall.padSlots.isEmpty else { return nil }
        return station.hall.padSlots[slot % station.hall.padSlots.count]
    }

    func stepTips(dt: Double) {
        let full = Double(RocketGeometry.panels)
        for r in rockets.values {
            let b = staging[r.key].flatMap { $0.merged ? $0 : nil }
            let running = b?.deploy == .running
            let live = b?.deploy == .live
            let pace = (full - 1) / max(20, (b?.deployUsual ?? Deployments.fallback) * 0.85)
            if running, !r.deployRunning, let b { r.welded = max(r.fresh ? r.welded : 0, min(full - 1, (clock - b.deploySince) * pace)) }
            r.deployRunning = running
            if b == nil { r.welded = full }
            else if running, r.welded < full - 1 { r.welded = min(full - 1, r.welded + dt * pace) }
            else if live { r.welded = min(full, r.welded + dt * 6) }
            if r.welded >= full { r.fresh = false }
            r.panels = r.fresh ? Int(r.welded) : RocketGeometry.panels
            r.welding = b != nil && (running || (live && r.welded < full))
        }
    }
}
