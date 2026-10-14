import Foundation

enum RocketGeometry {
    static let scale = RocketShape.station
    static let radius = RocketShape.radius * scale
    static let panels = 30
    static let fuller = 1.06
    static func hullRadius(at y: Double) -> Double { RocketShape.r(y / scale) * scale * fuller }
    static func apothem(at y: Double) -> Double { hullRadius(at: y) * cos(.pi / 6) }
    static var hullBase: Double { RocketShape.split * scale }
    static var hullHeight: Double { (RocketShape.panelTop - RocketShape.split) * scale }
    static var standHeight: Double { RocketShape.standDepth * scale }
    static var hatchInTip: SIMD3<Double> {
        let y = RocketShape.hatchHeight * scale
        return SIMD3(apothem(at: y) + 0.01, y, 0)
    }
    static func hatch(offset: Double) -> SIMD3<Double> { hatchInTip + SIMD3(0, offset, 0) }

    static let dockSeconds = 9.0
    static let irisEnd = 0.14, lowerEnd = 0.48, lockEnd = 0.56
    static var shaftDepth: Double { hullBase + 0.35 }
    static var doorRadius: Double { ((RocketShape.finReach + RocketShape.podRadius) * scale + 0.04) / cos(.pi / 6) }
    private static func ease(_ t: Double) -> Double { let k = min(1, max(0, t)); return k * k * (3 - 2 * k) }
    static func iris(dock: Double) -> Double { ease(dock / irisEnd) }
    static func deck(dock: Double) -> Double { -shaftDepth * (1 - ease((dock - lockEnd) / (1 - lockEnd))) }
    static func tipBase(dock: Double) -> Double {
        if dock <= irisEnd { return standHeight }
        if dock < lowerEnd { return standHeight + (-shaftDepth + hullBase - standHeight) * ease((dock - irisEnd) / (lowerEnd - irisEnd)) }
        return deck(dock: dock) + hullBase
    }
    static func tipOffset(dock: Double) -> Double { tipBase(dock: dock) - hullBase }
    static func fold(dock: Double) -> Double { ease((dock - (lowerEnd - 0.1)) / 0.1) }
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
    static func ringMiddle(_ ring: Int, offset: Double = 0) -> Double {
        hullBase + offset + ringHeight * (Double(ring) + 0.5)
    }
}

enum RocketKey {
    static func of(station: String, repo: String, hotfix: Int? = nil) -> String {
        station + "|" + repo + (hotfix.map { "|hotfix#\($0)" } ?? "")
    }
    static func parts(_ key: String) -> (station: String, repo: String, hotfix: Int?) {
        let p = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let hotfix = p.count > 2 && p[2].hasPrefix("hotfix#") ? Int(p[2].dropFirst("hotfix#".count)) : nil
        return (p.first ?? "", p.count > 1 ? p[1] : "", hotfix)
    }
}

final class RocketJob {
    let station: String
    let repo: String
    let hotfix: Int?
    var command: Command
    var phase = 0
    var until = 0.0
    var label = ""
    var untested = false
    var tall = true
    var dock = 0.0
    var docking = false
    var kick: Kick { dock >= 1 ? .docked : dock <= 0 ? .none : docking ? .coming : .going }
    var tipOffset: Double { RocketGeometry.tipOffset(dock: dock) }
    enum Kick: Equatable { case none, coming, docked, going }
    var cargo = 0
    var panels = RocketGeometry.panels
    var fresh = false
    var welded = Double(RocketGeometry.panels)
    var welding = false
    var seam = 0
    var deployRunning = false
    var launch: RocketID?
    var loadSince: Double?

    init(station: String, repo: String, hotfix: Int? = nil, command: Command) {
        self.station = station; self.repo = repo; self.hotfix = hotfix; self.command = command
    }

    var key: String { RocketKey.of(station: station, repo: repo, hotfix: hotfix) }
    static let claimWithin = 5.0

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
    func rocket(station: String, repo: String, hotfix: Int? = nil, label: String, untested: Bool, tall: Bool, cargo: Int, command: Command) {
        guard fleet.stations[station] != nil, case .rocket(let stage, _, _) = command.kind else { return }
        let key = RocketKey.of(station: station, repo: repo, hotfix: hotfix)
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
        let r = RocketJob(station: station, repo: repo, hotfix: hotfix, command: command)
        r.label = label; r.untested = untested; r.tall = tall; r.cargo = cargo
        if tall, world.settling { r.dock = 1; r.docking = true }
        if let b = staging[key], b.deploy != .live {
            r.panels = 0
            r.welded = 0
            r.fresh = true
        }
        rockets[key] = r
        take(r, command)
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
            cue(.liftOff(key: r.key))
            r.until = clock + 15
        default:
            if r.isSteaming { cue(.steam(key: r.key)) }
        }
    }

    func stepKicks(dt: Double) {
        for r in rockets.values {
            r.docking = r.tall || r.stage.rank >= 3
            let target = r.docking ? 1.0 : 0.0
            guard r.dock != target else { continue }
            let step = Theme.forPlan.kickRises ? dt / RocketGeometry.dockSeconds : 1
            r.dock = r.docking ? min(1, r.dock + step) : max(0, r.dock - step)
        }
    }

    func stepRockets() {
        for r in Array(rockets.values) {
            switch r.phaseKind {
            case .load:
                guard r.isLaunching else { advanceRocket(r); continue }
                if r.launch == nil { r.launch = claim(r) }
                if r.launch == nil {
                    r.loadSince = r.loadSince ?? clock
                    if clock - (r.loadSince ?? clock) < RocketJob.claimWithin { continue }
                }
                guard r.kick == .docked else { continue }
                if let v = vortices[r.key] {
                    if v.closedAt != nil, !pending(r) { advanceRocket(r) }
                    continue
                }
                loadCrates(r)
                if vortices[r.key] == nil, !pending(r) { advanceRocket(r) }
            case .climb:
                if clock >= r.until {
                    rockets[r.key] = nil
                    world.releases.hotfixLoads[r.key] = nil
                    world.releases.mergeLaunches.remove(r.key)
                    cue(.rocketGone(key: r.key))
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

    private func claim(_ r: RocketJob) -> RocketID? {
        guard let st = fleet.stations[r.station] else { return nil }
        let taken = Set(rockets.values.compactMap(\.launch))
        let mine: (RocketID) -> Bool
        if let n = r.hotfix {
            let crate = world.releases.hotfixLoads[r.key]?.crate ?? n
            mine = { $0 == "\(r.repo)|hotfix#\(crate)" }
        } else if world.releases.mergeLaunches.contains(r.key) {
            mine = { $0.hasPrefix(r.repo + "|merge#") }
        } else {
            mine = { $0.hasPrefix(r.repo + "|release#") }
        }
        return st.facts.launches.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.first { mine($0.key) && !taken.contains($0.key) }?.key
    }

    private func loadCrates(_ r: RocketJob) {
        guard r.kick == .docked, r.isLaunching, let station = fleet.stations[r.station] else { return }
        openVortex(r, station: station)
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
            if r.stage.rank == 0, r.hotfix == nil { r.cargo = world.cargoWaiting(station: st, repo: r.repo) }
        }
    }

    func rocketSpot(station: Station, key: String) -> SIMD2<Double>? {
        guard let slot = world.releases.padSlotOf[key], !station.hall.padSlots.isEmpty else { return nil }
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
