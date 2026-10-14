import Foundation
import simd

struct Shown: Equatable {
    enum At: Equatable {
        case office(String)
        case row(YardSpot)
        case parked(Spot)
        case hands(String)
        case vortex(RocketID)
        case aboard(RocketID)
        case falling(to: YardSpot, from: SIMD3<Double>, since: Double)

        var zone: Zone? {
            switch self {
            case .row(let s), .falling(let s, _, _): return s.zone
            case .parked(let p): return Zone(area: p.area)
            default: return nil
            }
        }
    }
    var crates: [CrateID: At] = [:]
    var offices: [String: ShownOffice] = [:]
    var deliveries: [Int: Delivery] = [:]
    var cubes: [String: Int] = [:]
    var folds: [Int: Double] = [:]
    var rockets: [RocketID: ShownRocket] = [:]
    var flown: Set<RocketID> = []

    var grounded: Shown {
        var s = self
        s.rockets = [:]
        return s
    }
}

enum MoveKind: Equatable { case haul, carry, park, hold }

enum Target: Equatable {
    case office(String), row(YardSpot), aboard(RocketID)

    var at: Shown.At {
        switch self {
        case .office(let k): return .office(k)
        case .row(let s): return .row(s)
        case .aboard(let r): return .aboard(r)
        }
    }
}

struct Calm: Equatable {
    let facts: Facts
    let view: Shown
    let jobs: Set<Int>
}

struct Slot: Hashable { let zone: Zone; let column: Int; let level: Int }

enum Pitch: Hashable {
    case column(Zone, Int), cell(Cell)

    static func of(_ s: YardSpot) -> Pitch { .column(s.zone, s.column) }

    static func of(_ p: Spot, in g: YardGeometry) -> [Pitch] {
        for zone in Zone.allCases {
            guard let grid = g.grids[zone], let width = grid.first?.count else { continue }
            for (r, row) in grid.enumerated() {
                guard let i = row.firstIndex(of: p.cell) else { continue }
                let tile = r * width + i, dx = p.pos.x - g.offset.x - Double(p.cell.x)
                if abs(dx) < 0.1 { return [.column(zone, tile * 2), .column(zone, tile * 2 + 1)] }
                return [.column(zone, tile * 2 + (dx < 0 ? 0 : 1))]
            }
        }
        return [.cell(p.cell)]
    }
}

extension YardSpot {
    var slot: Slot { Slot(zone: zone, column: column, level: level) }
    func lowered(to level: Int) -> YardSpot {
        YardSpot(zone: zone, column: column, level: level, cell: cell, pos: SIMD3(pos.x, Double(level) * Hands.level, pos.z), yaw: yaw)
    }
}

extension Zone {
    var area: Spot.Area {
        switch self {
        case .waiting: return .storage
        case .testing: return .deck
        case .cleared: return .tested
        case .decon: return .decon
        }
    }

    init?(area: Spot.Area) {
        switch area {
        case .storage: self = .waiting
        case .deck: self = .testing
        case .tested: self = .cleared
        case .decon: self = .decon
        case .office, .pad: return nil
        }
    }
}

extension Simulation {
    private struct Move {
        var from: Spot
        var aim: Spot
        var spot: YardSpot?
        var kind: MoveKind
        var rank: Rank
        var room = ""
        var parkIn: Zone?
    }

    private struct Ground {
        var held: [Slot: CrateID] = [:]
        var rows: Set<Slot> = []
        var parked: [Pitch: CrateID] = [:]

        init(_ view: Shown, _ g: YardGeometry? = nil) {
            for (id, at) in view.crates.sorted(by: { $0.key < $1.key }) {
                switch at {
                case .row(let s):
                    rows.insert(s.slot)
                    if held[s.slot] == nil { held[s.slot] = id }
                case .falling(let to, _, _): if held[to.slot] == nil { held[to.slot] = id }
                case .parked(let p): for pitch in g.map({ Pitch.of(p, in: $0) }) ?? [] where parked[pitch] == nil { parked[pitch] = id }
                default: break
                }
            }
        }

        func below(_ s: YardSpot) -> Slot { Slot(zone: s.zone, column: s.column, level: s.level - 1) }

        func free(_ s: YardSpot, for id: CrateID) -> Bool {
            (held[s.slot] ?? id) == id && (parked[Pitch.of(s)] ?? id) == id && (s.level == 0 || rows.contains(below(s)))
        }
    }

    func targets(_ st: Station) -> [CrateID: Target] {
        let spots = Layout.spots(st.facts, st.yard)
        var out: [CrateID: Target] = [:]
        for c in st.facts.crates.values {
            switch c.place {
            case .office(let k): out[c.id] = .office(k)
            case .aboard(let r): if st.hasPad { out[c.id] = .aboard(r) }
            default: if st.hasPad, let s = spots[c.id] { out[c.id] = .row(s) }
            }
        }
        return out
    }

    func play() {
        for st in fleet.stations.values.sorted(by: { $0.name < $1.name }) { play(st) }
    }

    func play(_ st: Station) {
        if played.insert(st.name).inserted { snap(st); return }
        playCrates(st)
        playOffices(st)
        playRockets(st)
    }

    private func calm(_ st: Station) -> Calm {
        let jobs = Set(cargo.filter { $0.value.command.crate?.station == st.name }.keys)
            .union(ownOrders.filter { if case .pack = $0.value.command.kind { return bodies[$0.value.body]?.station == st.name }; return false }.keys)
        return Calm(facts: st.facts, view: (shown[st.name] ?? Shown()).grounded, jobs: jobs)
    }

    private func playCrates(_ st: Station) {
        let targets = self.targets(st)
        var view = shown[st.name] ?? Shown()
        let before = view
        for (id, at) in view.crates {
            if case .falling(let to, _, let since) = at, clock - since >= Hands.settleSeconds { view.crates[id] = .row(to) }
        }
        shown[st.name] = view
        if calms[st.name] == calm(st) {
            watch(st, targets)
            return
        }
        var ground = Ground(view, st.yard)
        var moves: [CrateID: Move] = [:]
        for id in Set(targets.keys).union(view.crates.keys).sorted() { diff(id, st, targets[id], &view, &ground, &moves) }
        for id in targets.keys.sorted() where view.crates[id] == nil {
            guard case .row(let s)? = targets[id],
                  let spot = parkSpot(st, s.zone, near: standing(st, id.repo, s), taken: taken(st, view, targets), repo: id.repo) else { continue }
            view.crates[id] = .parked(spot)
            cue(.appear(st.name, id))
        }
        settle(&view)
        shown[st.name] = view
        reaimLifted(st, view, targets)
        let blocked = order(st, view, targets, &moves)
        hire(st, view, moves, blocked)
        if shown[st.name] != before { cue(.redraw) }
        calms[st.name] = calm(st)
        watch(st, targets)
    }

    func skip() {
        for st in fleet.stations.values {
            played.insert(st.name)
            snap(st)
        }
    }

    func snap(_ st: Station) {
        for (cid, job) in cargo where job.command.crate?.station == st.name { callOff(cid) }
        for (key, v) in vortices where v.station == st.name { vortices[key] = nil }
        stalls = stalls.filter { !$0.key.hasPrefix(st.name + "|") && !$0.key.hasPrefix("rocket|\(st.name)|") }
        var view = shown[st.name] ?? Shown()
        let fresh = targets(st).mapValues(\.at)
        for id in view.crates.keys where fresh[id] == nil { cue(.vanish(st.name, id)) }
        view.crates = fresh
        shown[st.name] = view
        snapOffices(st)
        snapRockets(st)
        cue(.redraw)
    }

    func snap(_ st: Station, _ id: CrateID) {
        guard var view = shown[st.name] else { return }
        let targets = self.targets(st)
        var aimed: [Slot: CrateID] = [:]
        for (c, t) in targets.sorted(by: { $0.key < $1.key }) { if case .row(let s) = t, aimed[s.slot] == nil { aimed[s.slot] = c } }
        var todo = [id], done: Set<CrateID> = []
        while let c = todo.popLast() {
            guard done.insert(c).inserted else { continue }
            letGo(st, c)
            if targets[c] == nil, view.crates[c] != nil { cue(.vanish(st.name, c)) }
            view.crates[c] = targets[c]?.at
            guard case .row(let t)? = targets[c] else { continue }
            let ground = Ground(view, st.yard)
            for (o, at) in view.crates.sorted(by: { $0.key < $1.key }) where o != c && !done.contains(o) {
                switch at {
                case .row(let s) where s.slot == t.slot: todo.append(o)
                case .falling(let to, _, _) where to.slot == t.slot: todo.append(o)
                case .parked(let p) where Pitch.of(p, in: st.yard).contains(Pitch.of(t)): todo.append(o)
                default: break
                }
            }
            if t.level > 0, ground.held[ground.below(t)] == nil, let b = aimed[ground.below(t)] { todo.append(b) }
        }
        settle(&view)
        shown[st.name] = view
        cue(.redraw)
    }

    private func letGo(_ st: Station, _ id: CrateID) {
        for (cid, job) in cargo where job.command.crate?.station == st.name && job.crate == id { callOff(cid) }
        for v in vortices.values where v.station == st.name {
            v.waiting.removeAll { $0.crate.repo == id.repo && $0.crate.number == id.number }
            v.flying.removeAll { $0.crate.repo == id.repo && $0.crate.number == id.number }
        }
    }

    func heard(_ effects: [Effect], station name: String) {
        guard let st = fleet.stations[name] else { return }
        for e in effects {
            switch e {
            case .log(let text): onEvent(.log(text))
            case .quiet(.crate(let id)): snap(st, id)
            case .quiet(.office(let key)): snapOffice(st, key)
            case .quiet(.rocket(let id)): snapRocket(st, id)
            case .renamed(.crate(let from), to: .crate(let to)): snap(st, from); snap(st, to)
            case .renamed(.office(let from), to: .office(let to)): rekey(st, from: from, to: to)
            case .renamed: break
            case .hatch: cue(.hatch(name))
            }
        }
    }

    func lag() -> String? {
        for st in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            let view = shown[st.name] ?? Shown()
            let targets = self.targets(st)
            for id in Set(targets.keys).union(view.crates.keys).sorted() where view.crates[id] != targets[id]?.at {
                return "\(id) shown \(describe(view.crates[id])), fact \(describe(targets[id]?.at))"
            }
            if let lag = officeLag(st) { return lag }
            for id in Set(st.facts.rockets.keys).union(view.rockets.keys).sorted() { if let lag = rocketLag(st, id) { return lag } }
        }
        if let job = cargo.values.min(by: { $0.command.id < $1.command.id }) { return "still carrying: \(job.command.words)" }
        return nil
    }

    func describe(_ at: Shown.At?) -> String {
        switch at {
        case nil: return "nowhere"
        case .office(let k)?: return "in \(k)"
        case .row(let s)?: return "\(s.zone.rawValue) c\(s.column) L\(s.level)"
        case .parked(let p)?: return "parked at \(p.cell.x),\(p.cell.y)"
        case .hands(let who)?: return "in \(who)'s hands"
        case .vortex(let r)?: return "in the vortex to \(r)"
        case .aboard(let r)?: return "aboard \(r)"
        case .falling(let to, _, _)?: return "falling to \(to.zone.rawValue) c\(to.column) L\(to.level)"
        }
    }

    func standing(_ st: Station, _ repo: String, _ s: YardSpot) -> Spot {
        Spot(area: s.zone.area, station: st.name, owner: repo, label: repo, cell: s.cell, pos: s.pos, level: s.level, yaw: s.yaw)
    }

    func stillAt(_ job: Cargo, _ from: Spot) -> Bool {
        guard let st = job.command.crate?.station else { return false }
        switch shown[st]?.crates[job.crate] {
        case .row(let s)?: return simd_distance(s.pos, from.pos) < 0.05
        case .parked(let p)?: return simd_distance(p.pos, from.pos) < 0.05
        case .office?: return from.area == .office
        default: return false
        }
    }

    private func diff(_ id: CrateID, _ st: Station, _ want: Target?, _ view: inout Shown, _ ground: inout Ground, _ moves: inout [CrateID: Move]) {
        switch (view.crates[id], want) {
        case (nil, nil), (.hands?, _), (.vortex?, _):
            return
        case (nil, .row(let s)?):
            if let k = st.facts.offices.first(where: { $0.value.crate == id })?.key, let o = shown[st.name]?.offices[k] {
                if o.phase == .built, !pack(st, k) { view.crates[id] = .office(k) }
                return
            }
            guard ground.free(s, for: id) else { return }
            ground.held[s.slot] = id
            ground.rows.insert(s.slot)
            if s.zone == .decon {
                view.crates[id] = .falling(to: s, from: s.pos + SIMD3(0, 1.2, 0), since: clock)
            } else {
                view.crates[id] = .row(s)
                cue(.appear(st.name, id))
            }
        case (nil, .office(let k)?):
            guard shown[st.name]?.offices[k]?.phase == .built else { return }
            if !pack(st, k) { view.crates[id] = .office(k) }
        case (nil, let w?):
            view.crates[id] = w.at
        case (_, nil):
            view.crates[id] = nil
        case (.falling?, _), (.aboard?, _), (.row?, .aboard?), (.parked?, .aboard?):
            return
        case (.office(let k)?, .office(let to)?):
            if k != to { view.crates[id] = .office(to) }
        case (.row?, .office(let k)?), (.parked?, .office(let k)?):
            view.crates[id] = .office(k)
        case (.office(let k)?, .row(let t)?):
            guard let from = officeSpot(st, k, id) else {
                guard ground.free(t, for: id) else { return }
                ground.held[t.slot] = id
                ground.rows.insert(t.slot)
                view.crates[id] = .row(t)
                return
            }
            moves[id] = Move(from: from, aim: standing(st, id.repo, t), spot: t, kind: .haul, rank: .yard, room: st.name + "|" + k)
        case (.office(let k)?, .aboard(let r)?):
            guard let from = officeSpot(st, k, id) else { view.crates[id] = .aboard(r); return }
            moves[id] = Move(from: from, aim: from, spot: nil, kind: .haul, rank: .yard, room: st.name + "|" + k, parkIn: .waiting)
        case (.row(let s)?, .row(let t)?):
            if s.slot == t.slot { if s != t { view.crates[id] = .row(t) }; return }
            if s.zone == t.zone, s.column == t.column, t.level < s.level { return }
            moves[id] = Move(from: standing(st, id.repo, s), aim: standing(st, id.repo, t), spot: t, kind: .carry, rank: rank(s.zone, t.zone))
        case (.parked(let p)?, .row(let t)?):
            moves[id] = Move(from: p, aim: standing(st, id.repo, t), spot: t, kind: .carry, rank: rank(Zone(area: p.area), t.zone))
        }
    }

    private func rank(_ from: Zone?, _ to: Zone) -> Rank {
        if from == .testing, to == .cleared { return .release }
        return from == to ? .tidy : .yard
    }

    private func officeSpot(_ st: Station, _ key: String, _ id: CrateID) -> Spot? {
        if let job = cargo.values.first(where: { $0.crate == id && $0.command.crate?.station == st.name }),
           case .carry(_, let from, _) = job.command.kind { return from }
        let office = shown[st.name]?.offices[key]
        guard let name = st.rooms[key]?.name ?? office?.name,
              let cell = packageCell(st, key) ?? st.doorCell(of: key) ?? office?.door ?? office?.cells.first else { return nil }
        return Spot(area: .office, station: st.name, owner: key, label: name, cell: cell,
                    pos: SIMD3(st.offset.x + Double(cell.x), 0, st.offset.y + Double(cell.y)))
    }

    func settle(_ name: String) {
        guard var view = shown[name] else { return }
        settle(&view)
        shown[name] = view
    }

    private func settle(_ view: inout Shown) {
        var held = Ground(view).held
        let stacked = view.crates.compactMap { id, at -> (id: CrateID, spot: YardSpot)? in
            if case .row(let s) = at, s.level > 0 { return (id, s) }
            return nil
        }.sorted { ($0.spot.level, $0.id) < ($1.spot.level, $1.id) }
        for (id, s) in stacked {
            var level = s.level
            while level > 0, held[Slot(zone: s.zone, column: s.column, level: level - 1)] == nil { level -= 1 }
            guard level < s.level else { continue }
            let to = s.lowered(to: level)
            if held[s.slot] == id { held[s.slot] = nil }
            held[to.slot] = id
            view.crates[id] = .falling(to: to, from: s.pos, since: clock)
        }
    }

    private func taken(_ st: Station, _ view: Shown, _ targets: [CrateID: Target], except id: CrateID? = nil) -> Set<Pitch> {
        var out: Set<Pitch> = []
        for t in targets.values { if case .row(let s) = t { out.insert(Pitch.of(s)) } }
        for (c, at) in view.crates where c != id {
            switch at {
            case .row(let s), .falling(let s, _, _): out.insert(Pitch.of(s))
            case .parked(let p): out.formUnion(Pitch.of(p, in: st.yard))
            default: break
            }
        }
        for job in cargo.values where job.command.crate?.station == st.name && job.crate != id && job.spot == nil {
            out.formUnion(Pitch.of(job.aim, in: st.yard))
        }
        return out
    }

    private func parkSpot(_ st: Station, _ zone: Zone, near: Spot, taken: Set<Pitch>, repo: String) -> Spot? {
        let g = st.yard
        var options: [(zone: Zone, cell: Cell, pos: SIMD2<Double>)] = []
        for z in [zone] + Zone.allCases.filter({ $0.isRow && $0 != zone }) {
            guard let grid = g.grids[z], let width = grid.first?.count else { continue }
            for (r, row) in grid.enumerated() {
                for (i, cell) in row.enumerated() {
                    for side in 0...1 where !taken.contains(.column(z, (r * width + i) * 2 + side)) {
                        options.append((z, cell, SIMD2(Double(cell.x) + (side == 0 ? -0.25 : 0.25), Double(cell.y))))
                    }
                }
            }
            if !options.isEmpty { break }
        }
        if options.isEmpty {
            options = (st.hall.aisleCells + st.hall.walkwayCells).filter { !taken.contains(.cell($0)) }.map { (zone, $0, SIMD2(Double($0.x), Double($0.y))) }
        }
        let at = SIMD2(near.pos.x - g.offset.x, near.pos.z - g.offset.y)
        guard let best = options.min(by: { a, b in
            (simd_distance(a.pos, at), a.pos.x, a.pos.y) < (simd_distance(b.pos, at), b.pos.x, b.pos.y)
        }) else { return nil }
        return Spot(area: best.zone.area, station: st.name, owner: repo, label: repo, cell: best.cell,
                    pos: SIMD3(g.offset.x + best.pos.x, 0, g.offset.y + best.pos.y))
    }

    private func reaimLifted(_ st: Station, _ view: Shown, _ targets: [CrateID: Target]) {
        for (cid, job) in cargo.sorted(by: { $0.key < $1.key }) where job.command.crate?.station == st.name && job.kind != .park {
            guard case .hands(let who)? = view.crates[job.crate] else { continue }
            if let m = bodies[who], m.phaseKind == .setDown, m.phaseUntil > 0 { continue }
            var aim = job.aim
            if case .row(let t)? = targets[job.crate] {
                cargo[cid]?.spot = t
                aim = standing(st, job.crate.repo, t)
            } else {
                cargo[cid]?.spot = nil
                if job.spot != nil || job.aim.pos.y > 0.01 {
                    let zone = Zone(area: job.aim.area) ?? .waiting
                    aim = parkSpot(st, zone, near: job.aim, taken: taken(st, view, targets, except: job.crate), repo: job.crate.repo) ?? aim
                }
            }
            guard aim != job.aim else { continue }
            cargo[cid]?.aim = aim
            if let m = bodies[who], m.current?.id == cid, m.phaseKind == .haul { walk(m, to: standCell(st, near: aim.cell)) }
        }
    }

    private func order(_ st: Station, _ view: Shown, _ targets: [CrateID: Target], _ moves: inout [CrateID: Move]) -> [CrateID: Set<CrateID>] {
        let ground = Ground(view, st.yard)
        var aimed: [Slot: CrateID] = [:]
        for (id, t) in targets.sorted(by: { $0.key < $1.key }) { if case .row(let s) = t, aimed[s.slot] == nil { aimed[s.slot] = id } }
        func settled(_ c: CrateID) -> Bool {
            if case .row(let s)? = view.crates[c], case .row(let t)? = targets[c] { return s.slot == t.slot }
            return false
        }
        func falls(_ c: CrateID, _ s: YardSpot) -> Bool {
            if case .row(let t)? = targets[c] { return t.zone == s.zone && t.column == s.column && t.level < s.level }
            return false
        }
        var stacks: [Pitch: [(id: CrateID, spot: YardSpot, falling: Bool)]] = [:]
        for (c, at) in view.crates {
            switch at {
            case .row(let o): stacks[Pitch.of(o), default: []].append((c, o, false))
            case .falling(let o, _, _): stacks[Pitch.of(o), default: []].append((c, o, true))
            default: break
            }
        }
        var lifts: [CrateID: Set<CrateID>] = [:]
        func lift(_ id: CrateID) -> Set<CrateID> {
            if let known = lifts[id] { return known }
            guard case .row(let s)? = view.crates[id], s.zone != .decon else { return [] }
            let out = Set((stacks[Pitch.of(s)] ?? []).filter { $0.id != id && $0.spot.level > s.level && ($0.falling || !falls($0.id, $0.spot)) }.map(\.id))
            lifts[id] = out
            return out
        }
        func down(_ id: CrateID, _ t: YardSpot?) -> Set<CrateID> {
            guard let t else { return [] }
            var out: Set<CrateID> = []
            if let o = ground.held[t.slot], o != id { out.insert(o) }
            if let o = ground.parked[Pitch.of(t)], o != id { out.insert(o) }
            guard t.level > 0 else { return out }
            let below = ground.below(t)
            if let b = ground.held[below], settled(b) { return out }
            if let b = aimed[below] ?? ground.held[below], b != id { out.insert(b) }
            return out
        }
        var holds: Set<CrateID> = []
        var lifted: [CrateID: YardSpot?] = [:]
        for job in cargo.values where job.command.crate?.station == st.name {
            if case .hands? = view.crates[job.crate] { lifted[job.crate] = job.spot }
        }
        func blockers(_ id: CrateID) -> Set<CrateID> {
            guard let m = moves[id] else { return [] }
            return holds.contains(id) ? lift(id) : lift(id).union(down(id, m.spot))
        }
        func aboard(_ c: CrateID) -> Bool { if case .aboard? = targets[c] { return true }; return false }
        var taken = self.taken(st, view, targets)
        func parkAim(_ id: CrateID, _ from: Spot, _ zone: Zone) -> Spot? {
            if let job = cargo.values.first(where: { $0.crate == id && $0.command.crate?.station == st.name && $0.spot == nil }),
               job.aim.pos.y < 0.01, job.aim.cell != from.cell { return job.aim }
            guard let spot = parkSpot(st, zone, near: from, taken: taken, repo: id.repo) else { return nil }
            taken.formUnion(Pitch.of(spot, in: st.yard))
            return spot
        }
        var mayHold = !cargo.values.contains { $0.kind == .hold && $0.command.crate?.station == st.name && lifted[$0.crate] != nil }
        for _ in 0..<64 {
            var changed = false
            for id in moves.keys.sorted() {
                for b in blockers(id).sorted() where moves[b] == nil && !aboard(b) {
                    guard case .row(let s)? = view.crates[b] else { continue }
                    let from = standing(st, b.repo, s)
                    if let aim = parkAim(b, from, s.zone) {
                        moves[b] = Move(from: from, aim: aim, spot: nil, kind: .park, rank: .tidy)
                    } else if mayHold, case .row(let t)? = targets[b] {
                        moves[b] = Move(from: from, aim: standing(st, b.repo, t), spot: t, kind: .hold, rank: .tidy)
                        holds.insert(b)
                        mayHold = false
                    } else { continue }
                    changed = true
                }
            }
            var edges: [CrateID: Set<CrateID>] = [:]
            for id in moves.keys { edges[id] = blockers(id).filter { moves[$0] != nil || lifted[$0] != nil } }
            for (id, spot) in lifted { edges[id] = down(id, spot).filter { moves[$0] != nil || lifted[$0] != nil } }
            if let loop = cycle(edges) {
                let members = Set(loop)
                let free = loop.filter { !holds.contains($0) && lifted[$0] == nil && lift($0).isDisjoint(with: members) }
                let standing = free.filter { if case .row? = view.crates[$0] { return true }; return false }
                if let c = standing.min() ?? free.min() {
                    holds.insert(c)
                    changed = true
                }
            }
            if !changed { break }
        }
        for id in moves.keys.sorted() {
            guard let zone = moves[id]?.parkIn, let m = moves[id], let aim = parkAim(id, m.from, zone) else { continue }
            moves[id]?.aim = aim
        }
        var blocked: [CrateID: Set<CrateID>] = [:]
        for id in moves.keys { blocked[id] = blockers(id) }
        var carried: [(rank: Rank, blockers: Set<CrateID>)] = []
        for job in cargo.values where job.command.crate?.station == st.name {
            guard case .hands? = view.crates[job.crate] else { continue }
            blocked[job.crate] = down(job.crate, job.spot)
            carried.append((job.rank, blocked[job.crate] ?? []))
        }
        for _ in 0...moves.count {
            var raised = false
            func raise(_ b: CrateID, to rank: Rank) { if let r = moves[b]?.rank, r < rank { moves[b]?.rank = rank; raised = true } }
            for (id, m) in moves { for b in blocked[id] ?? [] { raise(b, to: m.rank) } }
            for c in carried { for b in c.blockers { raise(b, to: c.rank) } }
            if !raised { break }
        }
        return blocked
    }

    private func cycle(_ edges: [CrateID: Set<CrateID>]) -> [CrateID]? {
        var state: [CrateID: Bool] = [:]
        var path: [CrateID] = []
        func visit(_ n: CrateID) -> [CrateID]? {
            state[n] = false
            path.append(n)
            for m in (edges[n] ?? []).sorted() {
                if state[m] == false, let i = path.firstIndex(of: m) { return Array(path[i...]) }
                if state[m] == nil, let found = visit(m) { return found }
            }
            path.removeLast()
            state[n] = true
            return nil
        }
        for n in edges.keys.sorted() where state[n] == nil { if let found = visit(n) { return found } }
        return nil
    }

    private func hire(_ st: Station, _ view: Shown, _ moves: [CrateID: Move], _ blocked: [CrateID: Set<CrateID>]) {
        var have: [CrateID: Int] = [:]
        for (cid, job) in cargo.sorted(by: { $0.key < $1.key }) where job.command.crate?.station == st.name { have[job.crate] = cid }
        for (crate, cid) in have.sorted(by: { $0.key < $1.key }) {
            if case .hands? = view.crates[crate] { cargo[cid]?.blockedBy = blocked[crate] ?? []; continue }
            guard let m = moves[crate] else { callOff(cid); continue }
            update(cid, st, m, blocked[crate] ?? [])
        }
        for (crate, m) in moves.sorted(by: { $0.key < $1.key }) where have[crate] == nil {
            let ref = CrateRef(station: st.name, repo: crate.repo, number: crate.number)
            let zone = m.spot?.zone ?? Zone(area: m.aim.area) ?? .waiting
            let command = Command.carry(ref, from: m.from, to: zone, words: words(ref, m, zone))
            cargo[command.id] = Cargo(command: command, carrier: nil, roomKey: m.room, aim: m.aim, postedAt: clock, rank: m.rank,
                                      crate: crate, kind: m.kind, blockedBy: blocked[crate] ?? [], spot: m.spot)
        }
    }

    private func words(_ ref: CrateRef, _ m: Move, _ zone: Zone) -> String {
        switch m.kind {
        case .park: return "putting \(ref.words) aside"
        case .hold: return "holding \(ref.words) up while the pile is sorted"
        default: return "carrying \(ref.words) to \(zone.words)"
        }
    }

    private func update(_ cid: Int, _ st: Station, _ m: Move, _ blocked: Set<CrateID>) {
        guard var job = cargo[cid], case .carry(let ref, let from, let to) = job.command.kind else { return }
        let zone = m.spot?.zone ?? Zone(area: m.aim.area) ?? .waiting
        let words = words(ref, m, zone)
        if from != m.from || to != zone || job.command.words != words {
            job.command = job.command.carrying(from: m.from, to: zone, words: words)
            if let who = job.carrier, let b = bodies[who], b.current?.id == cid {
                b.current = job.command
                if from != m.from, b.phaseKind == .walk || b.phaseKind == .approach { b.path = route(b, to: standCell(st, near: m.from.cell)) }
            }
        }
        job.aim = m.aim
        job.spot = m.spot
        job.kind = m.kind
        job.rank = m.rank
        job.roomKey = m.room
        job.blockedBy = blocked
        cargo[cid] = job
    }

    func callOff(_ cid: Int) {
        guard let job = cargo.removeValue(forKey: cid), let who = job.carrier, let m = bodies[who], m.current?.id == cid else { return }
        loseLoad(m)
        finish(m)
    }

    private func watch(_ st: Station, _ targets: [CrateID: Target]) {
        let view = shown[st.name] ?? Shown()
        if stirred[st.name]?.view != view.grounded { stirred[st.name] = (view.grounded, clock) }
        let still = clock - (stirred[st.name]?.at ?? clock) >= Patience.waitLimit
        var behind: Set<String> = []
        var carriers: [CrateID: String] = [:]
        for job in cargo.values where job.command.crate?.station == st.name { if let who = job.carrier { carriers[job.crate] = who } }
        for id in Set(targets.keys).union(view.crates.keys).sorted() where view.crates[id] != targets[id]?.at {
            let key = "\(st.name)|\(id)"
            behind.insert(key)
            let carrier = carriers[id].flatMap { bodies[$0] }
            let mark = describe(view.crates[id]) + "|" + describe(targets[id]?.at) + "|"
                + (carrier.map { "\($0.id) \($0.phase) \($0.cell.x),\($0.cell.y) \($0.path.count)" } ?? "-")
            guard let seen = stalls[key], seen.mark == mark else { stalls[key] = (mark, clock); continue }
            guard still, clock - seen.since >= Patience.waitLimit else { continue }
            StationLog.write("playback", "\(st.name) \(id) stood still for \(Int(Patience.waitLimit)) s, shown \(describe(view.crates[id])), fact \(describe(targets[id]?.at)): snapped to the facts")
            stalls[key] = nil
            snapped += 1
            snap(st, id)
        }
        for key in stalls.keys where key.hasPrefix(st.name + "|") && !behind.contains(key) { stalls[key] = nil }
    }
}
