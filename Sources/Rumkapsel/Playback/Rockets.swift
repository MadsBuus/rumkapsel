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
    static let sinkSeconds = 3.0, closeSeconds = 1.3
    private static var clearings: [String: Double] = [:]
    static var clearing: Double {
        let look = String(describing: type(of: Looks.current))
        if let t = clearings[look] { return t }
        var t = 0.0
        while t < Looks.current.launchSeconds, Looks.current.launch(at: t).offset.y < 0.3 { t += 0.01 }
        clearings[look] = t
        return t
    }
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

struct ShownRocket: Equatable {
    let repo: String
    let kind: RocketFact.Kind
    var label: String
    var held: Bool
    let slot: Int
    var since: Double
    var dock = 0.0
    var welded: Double
    var fresh = false
    var welding = false
    var venting = false
    var climbing: Double?
    var leaving: Double?

    static let fadeSeconds = 1.2
    static var climbSeconds: Double { Looks.current.launchSeconds }

    var panels: Int { fresh ? Int(welded) : RocketGeometry.panels }
    var tipOffset: Double { RocketGeometry.tipOffset(dock: dock) }
}

extension ShownRocket {
    func lift(at clock: Double) -> (iris: Double, deck: Double) {
        guard let at = climbing else { return (RocketGeometry.iris(dock: dock), RocketGeometry.deck(dock: dock)) }
        let t = clock - at - RocketGeometry.clearing
        return (1 - Timing.clamped((t - RocketGeometry.sinkSeconds) / RocketGeometry.closeSeconds),
                -RocketGeometry.shaftDepth * Timing.clamped(t / RocketGeometry.sinkSeconds))
    }
}

extension StagingFact {
    func welded(at now: Date) -> Double? {
        let full = Double(RocketGeometry.panels)
        guard merged else { return full }
        switch deploy {
        case .running(let since, let usual): return min(full - 1, max(0, now.timeIntervalSince(since)) * (full - 1) / max(20, usual * 0.85))
        case .live: return full
        case .unheard, .failed: return nil
        }
    }

    func progress(at now: Date) -> Double? {
        guard merged, case .running(let since, let usual) = deploy else { return nil }
        return max(0, now.timeIntervalSince(since)) / max(20, usual)
    }

    static let late = 1.5

    func timeLeft(at now: Date) -> String? {
        guard let p = progress(at: now), case .running(_, let usual) = deploy else { return nil }
        let minutes = { (s: Double) in max(1, Int((s / 60).rounded(.up))) }
        if p >= StagingFact.late { return "running late, usually \(minutes(usual)) min" }
        if p >= 1 { return "any moment now" }
        let left = usual * (1 - p)
        return left < 60 ? "under a minute left" : "about \(minutes(left)) min left"
    }
}

extension Simulation {
    func rocketKey(_ station: String, _ id: RocketID) -> String { station + "|" + id }

    func shownRocket(_ key: String) -> (station: Station, id: RocketID, rocket: ShownRocket)? {
        guard let bar = key.firstIndex(of: "|"), let st = fleet.stations[String(key[..<bar])] else { return nil }
        let id = String(key[key.index(after: bar)...])
        return shown[st.name]?.rockets[id].map { (st, id, $0) }
    }

    func shownRockets(_ station: Station) -> [(key: String, rocket: ShownRocket)] {
        (shown[station.name]?.rockets ?? [:]).sorted { $0.key < $1.key }.map { (rocketKey(station.name, $0.key), $0.value) }
    }

    func rocketSpot(_ station: Station, _ r: ShownRocket) -> SIMD2<Double>? {
        let slots = station.hall.padSlots
        return slots.isEmpty ? nil : slots[r.slot % slots.count]
    }

    private func look(_ f: RocketFact) -> (label: String, held: Bool) {
        guard f.kind == .release else { return (f.label, false) }
        let status = f.launched ? Words.current.liftedOff : f.go ? Words.current.cleared : Words.current.holding
        return (f.label + " · " + status, !f.go && !f.launched)
    }

    private func wanted(_ st: Station, _ id: RocketID, _ r: ShownRocket) -> RocketFact? {
        guard r.leaving == nil, let f = st.facts.rockets[id], f.launched || f.slot == r.slot else { return nil }
        return f
    }

    private func arrival(_ st: Station, _ f: RocketFact, slot: Int, snapped: Bool, was: ShownRocket? = nil) -> ShownRocket {
        let (label, held) = look(f)
        let staging = f.kind == .release ? st.facts.staging[f.repo] : nil
        let full = Double(RocketGeometry.panels)
        var r = ShownRocket(repo: f.repo, kind: f.kind, label: label, held: held, slot: slot, since: clock, welded: full)
        if snapped {
            r.dock = f.docked ? 1 : 0
            if let was, was.slot == slot, was.climbing == nil, was.leaving == nil { r.since = was.since; r.welded = was.welded; r.fresh = was.fresh }
            r.welded = staging.map { $0.welded(at: now) ?? r.welded } ?? full
            r.fresh = r.fresh && r.welded < full
        } else if staging?.underway == true {
            r.fresh = true
            r.welded = 0
        }
        return r
    }

    func playRockets(_ st: Station) {
        guard var view = shown[st.name] else { return }
        for id in view.rockets.keys.sorted() {
            guard var r = view.rockets[id] else { continue }
            if let at = r.climbing, clock - at >= ShownRocket.climbSeconds {
                view.rockets[id] = nil
                view.flown.insert(id)
                continue
            }
            if let at = r.leaving, clock - at >= ShownRocket.fadeSeconds {
                view.rockets[id] = nil
                continue
            }
            if let f = wanted(st, id, r) { (r.label, r.held) = look(f) } else if r.climbing == nil, r.leaving == nil, r.dock <= 0 { r.leaving = clock }
            view.rockets[id] = r
        }
        view.flown = view.flown.filter { st.facts.rockets[$0]?.launched == true }
        var held = Set(view.rockets.values.map(\.slot))
        for f in st.facts.rockets.values.sorted(by: { $0.id < $1.id }) where view.rockets[f.id] == nil && !view.flown.contains(f.id) {
            guard let slot = f.slot, !held.contains(slot) else { continue }
            held.insert(slot)
            view.rockets[f.id] = arrival(st, f, slot: slot, snapped: false)
        }
        shown[st.name] = view
        launch(st)
        watchRockets(st)
    }

    func stepRockets(dt: Double) {
        let full = Double(RocketGeometry.panels)
        for st in fleet.stations.values {
            guard var view = shown[st.name], !view.rockets.isEmpty else { continue }
            for (id, var r) in view.rockets {
                let f = wanted(st, id, r)
                let target = f.map { $0.docked || $0.launched } == true ? 1.0 : 0.0
                if r.dock != target {
                    let step = Theme.forPlan.kickRises ? dt / RocketGeometry.dockSeconds : 1
                    r.dock = r.dock < target ? min(target, r.dock + step) : max(target, r.dock - step)
                }
                if r.kind == .release, let s = st.facts.staging[r.repo], s.merged {
                    var running = false
                    switch s.deploy {
                    case .running: running = true; r.welded = s.welded(at: now) ?? r.welded
                    case .live: r.welded = min(full, r.welded + dt * 6)
                    case .unheard, .failed: break
                    }
                    r.welding = running || (s.deploy == .live && r.welded < full)
                } else {
                    r.welded = full
                    r.welding = false
                }
                if r.welded >= full { r.fresh = false }
                r.venting = f.map { $0.go && !$0.launched } == true && r.dock >= 1
                view.rockets[id] = r
            }
            shown[st.name] = view
        }
    }

    private func launch(_ st: Station) {
        for (id, r) in (shown[st.name]?.rockets ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard r.climbing == nil, r.dock >= 1, wanted(st, id, r)?.launched == true else { continue }
            let key = rocketKey(st.name, id)
            if let v = vortices[key] {
                if v.closedAt != nil, !pending(st, id) { climb(st, id) }
                continue
            }
            openVortex(st, id)
            if vortices[key] == nil, !pending(st, id) { climb(st, id) }
        }
    }

    func pending(_ st: Station, _ id: RocketID) -> Bool {
        let view = shown[st.name] ?? Shown()
        return st.facts.aboard(id).contains { view.crates[$0.id] != .aboard(id) }
    }

    private func climb(_ st: Station, _ id: RocketID) {
        shown[st.name]?.rockets[id]?.climbing = clock
        if let repo = shown[st.name]?.rockets[id]?.repo { onEvent(.log("\(repo) \(Words.current.liftingOff)")) }
        StationLog.write("release", "\(rocketKey(st.name, id)) climbs at \(String(format: "%.1f", clock))")
    }

    func snapRockets(_ st: Station) {
        var view = shown[st.name] ?? Shown()
        var rockets: [RocketID: ShownRocket] = [:]
        var held: Set<Int> = []
        for f in st.facts.rockets.values.sorted(by: { $0.id < $1.id }) where !f.launched {
            guard let slot = f.slot, !held.contains(slot) else { continue }
            held.insert(slot)
            rockets[f.id] = arrival(st, f, slot: slot, snapped: true, was: view.rockets[f.id])
        }
        view.rockets = rockets
        view.flown = Set(st.facts.rockets.values.filter(\.launched).map(\.id))
        shown[st.name] = view
    }

    func snapRocket(_ st: Station, _ id: RocketID) {
        guard var view = shown[st.name] else { return }
        vortices[rocketKey(st.name, id)] = nil
        let f = st.facts.rockets[id]
        if let f, !f.launched, let slot = f.slot, !view.rockets.contains(where: { $0.key != id && $0.value.slot == slot }) {
            view.rockets[id] = arrival(st, f, slot: slot, snapped: true, was: view.rockets[id])
        } else {
            view.rockets[id] = nil
            if f?.launched == true { view.flown.insert(id) }
        }
        let crates = Set(st.facts.aboard(id).map(\.id)).union(view.crates.filter { $0.value == .vortex(id) }.map(\.key))
        shown[st.name] = view
        for c in crates.sorted() { snap(st, c) }
    }

    func rocketLag(_ st: Station, _ id: RocketID) -> String? {
        let view = shown[st.name] ?? Shown()
        let r = view.rockets[id]
        guard let f = st.facts.rockets[id] else { return r == nil ? nil : "rocket \(id) is still shown, gone from the facts" }
        if f.launched { return view.flown.contains(id) ? nil : "rocket \(id) has not flown yet" }
        guard let slot = f.slot else { return r == nil ? nil : "rocket \(id) is still shown, its pad given away" }
        guard let r else { return "rocket \(id) is not shown on pad \(slot)" }
        if r.slot != slot || r.leaving != nil { return "rocket \(id) is leaving pad \(r.slot)" }
        if r.dock != (f.docked ? 1 : 0) { return "rocket \(id) is \(f.docked ? "docking" : "undocking")" }
        if r.kind == .release, let w = st.facts.staging[f.repo]?.welded(at: now), r.welded != w { return "rocket \(id)'s tip is being welded" }
        return nil
    }

    private func watchRockets(_ st: Station) {
        let view = shown[st.name] ?? Shown()
        var behind: Set<String> = []
        for id in Set(st.facts.rockets.keys).union(view.rockets.keys).sorted() {
            guard let lag = rocketLag(st, id) else { continue }
            let key = "rocket|\(st.name)|\(id)"
            behind.insert(key)
            let aboard = Set(st.facts.aboard(id).map(\.id))
            if cargo.values.contains(where: { aboard.contains($0.crate) && $0.command.crate?.station == st.name }) { stalls[key] = nil; continue }
            let slot = st.facts.rockets[id]?.slot
            let occupant = view.rockets.first { $0.key != id && $0.value.slot == slot }.map { describe($0.value) } ?? "-"
            let vortex = vortices[rocketKey(st.name, id)].map { "\($0.waiting.count) \($0.flying.count)" } ?? "-"
            let mark = [lag, view.rockets[id].map(describe) ?? "-", occupant, vortex].joined(separator: "|")
            guard let seen = stalls[key], seen.mark == mark else { stalls[key] = (mark, clock); continue }
            var limit = Patience.waitLimit
            if let s = st.facts.staging[st.facts.rockets[id]?.repo ?? ""], case .running(_, let usual) = s.deploy { limit = max(limit, usual) }
            guard clock - seen.since >= limit else { continue }
            stalls[key] = nil
            let before = shown[st.name]
            let open = vortices[rocketKey(st.name, id)] != nil
            snapRocket(st, id)
            guard shown[st.name] != before || open else { continue }
            StationLog.write("playback", "\(st.name) \(lag) and stood still for \(Int(limit)) s: snapped to the facts")
            snapped += 1
        }
        for key in stalls.keys where key.hasPrefix("rocket|\(st.name)|") && !behind.contains(key) { stalls[key] = nil }
    }

    private func describe(_ r: ShownRocket) -> String {
        "\(r.slot) \(Int(r.dock * 100)) \(Int(r.welded)) \(r.climbing.map { "c\(Int(clock - $0))" } ?? "") \(r.leaving.map { "l\(Int((clock - $0) * 10))" } ?? "")"
    }
}
