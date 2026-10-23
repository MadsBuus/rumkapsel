import Foundation

struct ShownOffice: Equatable {
    enum Phase: Equatable { case ordered(delivery: Int), unfolding(since: Double), fading(since: Double), built, folding(since: Double, from: Double) }

    struct Look: Equatable {
        var remote = false, provisional = false, unchecked = false, live = false, failing = false, dusty = false, dark = false
        var who: String?
    }

    var cells: [Cell]
    var door: Cell?
    var outside: Cell?
    var name: String
    var repo: String?
    var color: RGB
    var branch: String?
    var repoRoot: String?
    var worktree: String?
    var lastActive: Date
    var openedAt: Date
    var look = Look()
    var phase: Phase

    static let fadeSeconds = 2.5, crateFolds = 0.35

    func room(_ key: String) -> Room {
        let r = Room(key: key, name: name, repo: repo, color: color, cells: cells, lastActive: lastActive, openedAt: openedAt)
        r.branch = branch; r.repoRoot = repoRoot; r.worktree = worktree
        return r
    }

    func drawsLike(_ o: ShownOffice) -> Bool {
        var a = self
        a.lastActive = o.lastActive
        return a == o
    }

    var up: Bool {
        if case .ordered = phase { return false }
        return true
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private func reach(_ c: Cell) -> Double { door.map { Double(abs(c.x - $0.x) + abs(c.y - $0.y)) } ?? 0 }
    private var furthest: Double { cells.map(reach).max() ?? 0 }
    private var tilesGone: Double { 1.1 + furthest * 0.1 }

    var seconds: Double {
        switch phase {
        case .unfolding: return 1.3 + furthest * 0.1
        case .fading: return ShownOffice.fadeSeconds
        case .folding: return tilesGone + 2.15
        case .ordered, .built: return 0
        }
    }

    func done(at clock: Double) -> Bool {
        switch phase {
        case .unfolding(let since), .fading(let since), .folding(let since, _): return clock - since >= seconds
        case .ordered, .built: return false
        }
    }

    func standing(at clock: Double) -> Double {
        switch phase {
        case .ordered: return 0
        case .built: return 1
        case .unfolding(let since), .fading(let since): return ShownOffice.clamp((clock - since) / seconds)
        case .folding(let since, let from): return from * (1 - ShownOffice.clamp((clock - since) / tilesGone))
        }
    }

    func tile(_ c: Cell, at clock: Double) -> Double {
        switch phase {
        case .ordered: return 0
        case .built: return 1
        case .fading(let since): return ShownOffice.clamp((clock - since) / ShownOffice.fadeSeconds)
        case .unfolding(let since): return ShownOffice.clamp((clock - since - 0.3 - reach(c) * 0.1) / 0.6)
        case .folding(let since, let from): return from * (1 - ShownOffice.clamp((clock - since - 0.5 - (furthest - reach(c)) * 0.1) / 0.6))
        }
    }

    func label(at clock: Double) -> Double {
        switch phase {
        case .unfolding(let since): return ShownOffice.clamp((clock - since - 0.8 - furthest * 0.1) / 0.5)
        case .folding(let since, let from): return from * (1 - ShownOffice.clamp((clock - since) / 0.4))
        default: return tile(door ?? cells.first ?? Cell(x: 0, y: 0), at: clock)
        }
    }

    func crate(at clock: Double) -> (scale: Double, sink: Double)? {
        guard case .folding(let since, _) = phase else { return nil }
        let t = clock - since - tilesGone + 0.2
        guard t > 0 else { return nil }
        let grow = ShownOffice.clamp(t / 0.35), sink = ShownOffice.clamp((t - 0.75) / 1.6)
        return (0.01 + 0.99 * (1 - (1 - grow) * (1 - grow)), 3 * sink * sink)
    }

    static func folded(_ since: Double, at clock: Double) -> Double {
        let t = clamp((clock - since) / crateFolds)
        return max(0.01, 1 - t * t)
    }
}

struct Delivery: Equatable {
    let id: Int
    let station: String
    var room: String
    let slot: Int
    let who: String?
    let since: Double
    var landed = false
    var gaveUp: Set<String> = []

    static let patience = 10.0
}

extension Simulation {
    var deliveries: [Delivery] { shown.values.flatMap(\.deliveries.values).sorted { $0.id < $1.id } }

    func delivery(_ id: Int) -> Delivery? { shown.values.lazy.compactMap { $0.deliveries[id] }.first }

    func updateDelivery(_ id: Int, _ change: (inout Delivery) -> Void) {
        guard let d = delivery(id), var changed = shown[d.station]?.deliveries[id] else { return }
        change(&changed)
        shown[d.station]?.deliveries[id] = changed
    }

    func factsChanged(_ st: Station, _ effects: [Effect]) {
        if played.insert(st.name).inserted { snap(st); return }
        heard(effects, station: st.name)
        play(st)
    }

    func officesChanged(_ st: Station, _ effects: [Effect]) {
        if played.insert(st.name).inserted { snap(st); return }
        heard(effects, station: st.name)
        playOffices(st)
    }

    func loaded() {
        calms = [:]
        stalls = [:]
        for st in fleet.stations.values {
            played.insert(st.name)
            snap(st)
        }
    }

    func standing(_ st: Station, _ key: String) -> Bool {
        guard !key.hasPrefix("kind:") else { return true }
        guard st.rooms[key] != nil else { return false }
        guard let o = shown[st.name]?.offices[key] else { return false }
        switch o.phase {
        case .folding, .ordered: return false
        default: break
        }
        return st.facts.offices[key] != nil
    }

    func playOffices(_ st: Station) {
        var view = shown[st.name] ?? Shown()
        let before = view
        for (id, since) in view.folds where clock - since >= ShownOffice.crateFolds { view.folds[id] = nil }
        for key in view.offices.keys.sorted() {
            guard let o = view.offices[key] else { continue }
            if case .folding = o.phase {} else if st.facts.offices[key] != nil, let room = st.rooms[key] { view.offices[key] = shot(st, room, o.phase) }
            guard o.done(at: clock) else { continue }
            if case .folding = o.phase {
                view.offices[key] = nil
                view.cubes[key] = nil
                continue
            }
            view.offices[key]?.phase = .built
            cue(.built(st.name + "|" + key))
        }
        for key in st.facts.offices.keys.sorted() where view.offices[key] == nil { arrive(st, key, &view) }
        var dropped: [Int] = []
        for key in view.offices.keys.sorted() where st.facts.offices[key] == nil { leave(st, key, &view, &dropped) }
        stow(st, &view)
        shown[st.name] = view
        for key in view.offices.keys.sorted() where before.offices[key] == nil && standing(st, key) { moveIn(st.name, key) }
        for id in dropped {
            for m in bodies.values where m.station == st.name {
                guard case .deliverOffice(let k)? = m.current?.kind, k == id else { continue }
                dropLoad(m)
                finish(m)
            }
        }
        linger(st)
        if Set(view.offices.keys) != Set(before.offices.keys)
            || view.offices.contains(where: { k, o in !(before.offices[k].map(o.drawsLike) ?? false) }) { cue(.floor) }
        watchOffices(st)
    }

    private func shot(_ st: Station, _ room: Room, _ phase: ShownOffice.Phase) -> ShownOffice {
        let full = st.name + "|" + room.key
        let look = ShownOffice.Look(remote: world.isRemoteOnly(st, room), provisional: world.isProvisional(st, room),
                                    unchecked: world.isUnchecked(st, room), live: world.isLocalLive(st, room),
                                    failing: world.checksFailing(room), dusty: world.isDusty(room), dark: world.peerDim(full),
                                    who: world.occupant(of: full))
        return ShownOffice(cells: room.cells, door: st.doorCell(of: room.key), outside: st.doorOutside(of: room.key), name: room.name,
                           repo: room.repo, color: room.color, branch: room.branch, repoRoot: room.repoRoot, worktree: room.worktree,
                           lastActive: room.lastActive, openedAt: room.openedAt, look: look, phase: phase)
    }

    private func arrive(_ st: Station, _ key: String, _ view: inout Shown) {
        guard let room = st.rooms[key], let fact = st.facts.offices[key] else { return }
        let cells = Set(room.cells)
        if view.offices.contains(where: { st.facts.offices[$0.key] == nil && !cells.isDisjoint(with: $0.value.cells) }) { return }
        var o = shot(st, room, .built)
        switch fact.via {
        case .appear:
            cue(.built(st.name + "|" + key))
        case .fade:
            o.phase = .fading(since: clock)
        case .shuttle(let who):
            if let d = orderDelivery(st, key, who: who) {
                view.deliveries[d.id] = d
                o.phase = .ordered(delivery: d.id)
            } else {
                o.phase = .unfolding(since: clock)
                onEvent(.log("new office: \(room.name)"))
            }
        }
        view.offices[key] = o
    }

    private func leave(_ st: Station, _ key: String, _ view: inout Shown, _ dropped: inout [Int]) {
        guard let o = view.offices[key] else { return }
        let full = st.name + "|" + key
        switch o.phase {
        case .folding:
            return
        case .ordered(let id):
            if let d = view.deliveries[id], !d.landed { return }
            let carried = bodies.values.contains { m in
                if case .deliverOffice(let k)? = m.current?.kind { return k == id && m.hasLoad }
                return false
            }
            view.deliveries[id] = nil
            view.offices[key] = nil
            view.folds[id] = clock
            dropped.append(id)
            onEvent(.log("the office for \(o.name) is gone: " + (carried ? "its crate folds away where it was set down" : Words.current.foldsAway)))
        default:
            if view.crates.values.contains(.office(key)) || cargo.values.contains(where: { $0.roomKey == full }) { return }
            dropOrders(at: .room(key))
            let cells = Set(o.cells)
            var inside = false
            for m in bodies.values where m.station == st.name {
                let within = cells.contains(m.cell)
                guard within || m.place == .room(key) else { continue }
                if m.onJob { inside = inside || within; continue }
                if m.place == .room(key) { m.place = .core; finish(m, to: .core) }
                inside = inside || within
            }
            if inside { return }
            view.offices[key]?.phase = .folding(since: clock, from: o.standing(at: clock))
            cue(.folds(full))
        }
    }

    private func stow(_ st: Station, _ view: inout Shown) {
        for room in st.rooms.values.sorted(by: { $0.key < $1.key }) where room.branch != nil {
            guard let want = world.cubes(room) else { continue }
            guard let have = view.cubes[room.key], want > have else { view.cubes[room.key] = want; continue }
            if ownOrders.values.contains(where: { o in
                if case .stow(let k) = o.command.kind { return k == room.key && bodies[o.body]?.station == st.name }
                return false
            }) { continue }
            guard view.offices[room.key]?.phase == .built,
                  let m = bodies.values.first(where: { $0.station == st.name && $0.home.key == room.key && !$0.isPeer && !$0.isSubagent && $0.state != .leaving })
            else { view.cubes[room.key] = want; continue }
            let at = packageCell(st, room.key) ?? room.cells.first ?? st.coreCenter
            post(.stow(office: room.key), for: m, rank: .yard, at: standCell(st, near: at), place: .room(room.key), announce: true)
        }
    }

    func stowed(_ st: Station, _ office: String) {
        guard let room = st.rooms[office], let n = world.cubes(room) else { return }
        shown[st.name]?.cubes[office] = n
        cue(.redraw)
    }

    func packing(_ st: Station, _ office: String) -> Bool {
        ownOrders.values.contains { o in
            if case .pack(let k) = o.command.kind { return k == office && bodies[o.body]?.station == st.name }
            return false
        }
    }

    func pack(_ st: Station, _ office: String) -> Bool {
        if packing(st, office) { return true }
        guard let room = st.rooms[office],
              let m = bodies.values.first(where: { $0.station == st.name && $0.home.key == office && !$0.isCrew && !$0.isSubagent && !$0.isPeer && $0.state != .leaving })
        else { return false }
        let at = packageCell(st, office) ?? room.cells.first ?? st.coreCenter
        post(.pack(office: office), for: m, rank: .yard, at: standCell(st, near: at), place: .room(office), announce: true)
        return true
    }

    func packed(_ st: Station, _ office: String) {
        for (id, t) in targets(st).sorted(by: { $0.key < $1.key }) where t == .office(office) && shown[st.name]?.crates[id] == nil {
            shown[st.name]?.crates[id] = .office(office)
        }
        cue(.packed(st.name + "|" + office))
        cue(.redraw)
    }

    func moveIn(_ station: String, _ office: String) {
        for m in bodies.values where m.station == station && m.home.key == office && !m.onJob && m.state == .settled { send(m, to: restPlace(m)) }
    }

    func unfold(_ id: Int) {
        guard let d = delivery(id), var view = shown[d.station] else { return }
        view.deliveries[id] = nil
        view.folds[id] = clock
        if case .ordered(id)? = view.offices[d.room]?.phase {
            view.offices[d.room]?.phase = .unfolding(since: clock)
            onEvent(.log("new office: \(view.offices[d.room]?.name ?? d.room)"))
        }
        shown[d.station] = view
        moveIn(d.station, d.room)
        cue(.floor)
    }

    func abandon(_ m: B) {
        guard case .deliverOffice(let id)? = m.current?.kind, delivery(id) != nil else { return }
        loseLoad(m)
        unfold(id)
    }

    func snapOffices(_ st: Station) {
        var view = shown[st.name] ?? Shown()
        let ids = view.deliveries.keys.sorted()
        view.deliveries = [:]
        for id in ids { view.folds[id] = clock }
        view.offices = [:]
        for key in st.facts.offices.keys.sorted() {
            guard let room = st.rooms[key] else { continue }
            view.offices[key] = shot(st, room, .built)
            cue(.built(st.name + "|" + key))
        }
        view.cubes = [:]
        for room in st.rooms.values where room.branch != nil { view.cubes[room.key] = world.cubes(room) }
        shown[st.name] = view
        for id in ids { cancel(id) }
        stalls = stalls.filter { !$0.key.hasPrefix("office|\(st.name)|") }
        linger(st)
        cue(.floor)
    }

    func snapOffice(_ st: Station, _ key: String) {
        guard var view = shown[st.name] else { return }
        let ids = view.deliveries.values.filter { $0.room == key }.map(\.id).sorted()
        for id in ids {
            view.deliveries[id] = nil
            view.folds[id] = clock
        }
        if st.facts.offices[key] != nil, let room = st.rooms[key] {
            view.offices[key] = shot(st, room, .built)
            cue(.built(st.name + "|" + key))
        } else {
            view.offices[key] = nil
        }
        shown[st.name] = view
        for id in ids { cancel(id) }
        linger(st)
        cue(.floor)
    }

    func rekey(_ st: Station, from: String, to: String) {
        if var view = shown[st.name] {
            if let o = view.offices.removeValue(forKey: from) { view.offices[to] = o }
            for (id, d) in view.deliveries where d.room == from { view.deliveries[id]?.room = to }
            for (id, at) in view.crates where at == .office(from) { view.crates[id] = .office(to) }
            if let n = view.cubes.removeValue(forKey: from) { view.cubes[to] = n }
            shown[st.name] = view
        }
        for m in bodies.values where m.station == st.name && m.place == .room(from) { m.place = .room(to) }
        for (cid, job) in cargo where job.roomKey == st.name + "|" + from { cargo[cid]?.roomKey = st.name + "|" + to }
        moveOrders(from: from, to: to)
        linger(st)
        cue(.floor)
    }

    func officeLag(_ st: Station) -> String? {
        let view = shown[st.name] ?? Shown()
        for room in st.rooms.values.sorted(by: { $0.key < $1.key }) where !room.key.hasPrefix("kind:") && st.facts.offices[room.key] == nil {
            return "office \(room.key) is not in the facts"
        }
        for key in Set(st.facts.offices.keys).union(view.offices.keys).sorted() {
            guard let o = view.offices[key] else { return "office \(key) is not shown" }
            if st.facts.offices[key] == nil { return "office \(key) is still shown, \(o.phase)" }
            if o.phase != .built { return "office \(key) is shown \(o.phase)" }
        }
        if let d = view.deliveries.values.min(by: { $0.id < $1.id }) { return "the office for \(d.room) is still on its way" }
        return nil
    }

    private func linger(_ st: Station) {
        let gone = (shown[st.name]?.offices ?? [:]).filter { st.rooms[$0.key] == nil }
        st.linger(Dictionary(uniqueKeysWithValues: gone.map { ($0.key, $0.value.room($0.key)) }))
    }

    private func cancel(_ id: Int) {
        flights.removeAll { if case .flight(.dropCrate(let k), _, _) = $0.command.kind { return k == id }; return false }
        for m in bodies.values {
            guard case .deliverOffice(let k)? = m.current?.kind, k == id else { continue }
            loseLoad(m)
            finish(m)
        }
    }

    private func watchOffices(_ st: Station) {
        let view = shown[st.name] ?? Shown()
        let still = clock - (stirred[st.name]?.at ?? clock) >= Patience.waitLimit
        var behind: Set<String> = []
        for (key, o) in view.offices.sorted(by: { $0.key < $1.key }) {
            let mark: String
            switch o.phase {
            case .ordered(let id):
                let carrier = bodies.values.first { if case .deliverOffice(let k)? = $0.current?.kind { return k == id }; return false }
                let flight = flights.first { if case .flight(.dropCrate(let k), _, _) = $0.command.kind { return k == id }; return false }
                mark = "\(view.deliveries[id]?.landed ?? false)|\(flight?.phase ?? -1)|"
                    + (carrier.map { "\($0.id) \($0.phase) \($0.cell.x),\($0.cell.y) \($0.path.count)" } ?? "-")
            case .folding:
                continue
            case .built, .unfolding, .fading:
                guard st.facts.offices[key] == nil else { continue }
                let full = st.name + "|" + key
                let cells = Set(o.cells)
                let inside = view.crates.filter { $0.value == .office(key) }.map(\.key).sorted().map(\.description)
                let hauls = cargo.values.filter { $0.roomKey == full }.compactMap { $0.carrier.flatMap { bodies[$0] } }
                let people = bodies.values.filter { $0.station == st.name && cells.contains($0.cell) }
                mark = (inside + (hauls + people).map { "\($0.id) \($0.phase) \($0.cell.x),\($0.cell.y) \($0.path.count)" }.sorted()).joined(separator: "|")
            }
            let stall = "office|\(st.name)|\(key)"
            behind.insert(stall)
            guard let seen = stalls[stall], seen.mark == mark else { stalls[stall] = (mark, clock); continue }
            guard still, clock - seen.since >= Patience.waitLimit else { continue }
            StationLog.write("playback", "\(st.name) office \(key) stood still for \(Int(Patience.waitLimit)) s, shown \(o.phase), \(st.facts.offices[key] == nil ? "gone" : "in") the facts: snapped to the facts")
            stalls[stall] = nil
            snapped += 1
            snapOffice(st, key)
        }
        for key in stalls.keys where key.hasPrefix("office|\(st.name)|") && !behind.contains(key) { stalls[key] = nil }
    }
}
