import Foundation

struct OfficeMarks {
    var count: Int
    var ghosts = 0
    var pull: PullRequest?
    var package: Cell?
    var number: Int?
    var pile: [Cube] = []
    var packaged: Bool { package != nil }
}

struct Cube: Equatable {
    let pos: SIMD3<Double>
    let size: Double
    let shade: Double
    let yaw: Double

    static let sizes = [0.18, 0.26, 0.34]

    static func pile(_ key: String, count: Int, cells: [Cell]) -> [Cube] {
        var seed = stableHash(key) | 1
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        var pile: [Cube] = []
        for i in 0..<count {
            let size = sizes[min(2, Int(rnd() * 3))]
            let shade = rnd() * 0.1 - 0.04
            let pos: SIMD3<Double>
            if i >= 8 {
                let base = pile[i - 8]
                pos = SIMD3(base.pos.x + (rnd() - 0.5) * 0.06, base.pos.y + base.size / 2 + size / 2, base.pos.z + (rnd() - 0.5) * 0.06)
            } else {
                let cell = cells[(i / 3) % cells.count]
                let room = max(0, 0.86 - size * 1.25)
                pos = SIMD3(Double(cell.x) + (rnd() - 0.5) * room, size / 2, Double(cell.y) + (rnd() - 0.5) * room)
            }
            pile.append(Cube(pos: pos, size: size, shade: shade, yaw: rnd() * 0.9))
        }
        return pile
    }
}

extension Station {
    func farCells(_ room: Room) -> [Cell] {
        let door = doorCell(of: room.key) ?? room.cells.first!
        let written = self.written[room.key] ?? []
        let console = consoleCells(room.key)
        func near(_ c: Cell) -> Int { console.map { abs($0.x - c.x) + abs($0.y - c.y) }.min() ?? 0 }
        return room.cells.sorted { a, b in
            if console.contains(a) != console.contains(b) { return console.contains(b) }
            if !console.isEmpty, (a == door) != (b == door) { return b == door }
            if !console.isEmpty, (near(a) <= 1) != (near(b) <= 1) { return near(a) <= 1 }
            let wa = written.contains(a), wb = written.contains(b)
            if wa != wb { return !wa }
            if near(a) != near(b) { return near(a) < near(b) }
            let da = abs(a.x - door.x) + abs(a.y - door.y), db = abs(b.x - door.x) + abs(b.y - door.y)
            return da != db ? da > db : (a.y, a.x) < (b.y, b.x)
        }
    }
}

extension Simulation {
    func marks(_ st: Station, _ key: String) -> OfficeMarks? {
        guard let o = shown[st.name]?.offices[key] else { return nil }
        let full = st.name + "|" + key
        if case .folding = o.phase { return marked[full] }
        let room = o.room(key)
        guard var marks = fresh(st, room) else { marked[full] = nil; return nil }
        if marks.package == nil { marks.pile = Cube.pile(full, count: marks.count + marks.ghosts, cells: st.farCells(room)) }
        marked[full] = marks
        return marks
    }

    private func fresh(_ st: Station, _ room: Room) -> OfficeMarks? {
        let full = st.name + "|" + room.key
        guard let branch = room.branch else {
            let peer = world.crewRoomInfo[full] == nil ? world.peerPull(full) : nil
            let number = world.crewPull(full) ?? peer?.pull
            let left = crateLeft(st, room, pull: number)
            guard let boxes = world.crewBoxes[full] ?? world.peerBoxes[full], !left || st.isEpic(room.key) else { return nil }
            let closed = world.isClosed(full)
            var pr = PullRequest(number: number ?? 0, title: "", state: closed ? "CLOSED" : (peer?.pullState ?? (number != nil ? "OPEN" : boxes.state)),
                                 reviewDecision: peer?.review ?? "", isDraft: false, url: "")
            pr.checks = peer?.checks ?? ""
            return OfficeMarks(count: min(16, max(1, boxes.count)), pull: left ? nil : pr, package: !left && (number != nil || closed) ? package(st, room) : nil,
                               number: crate(st, room, pull: number))
        }
        let local = world.localState(room)
        let dirty = room.worktree.map { world.github.git.dirtyFiles(worktree: $0) } ?? 0
        let pr = room.repoRoot.flatMap { world.github.pulls.pull(branch: branch, repoRoot: $0) }
        let left = crateLeft(st, room, pull: pr?.number)
        guard local.commits > 0 || dirty > 0, !left || st.isEpic(room.key) else { return nil }
        return OfficeMarks(count: world.cubes(room) ?? 0, ghosts: min(8, Int(pow(Double(dirty), 0.6).rounded(.up))), pull: left ? nil : pr,
                           package: !left && pr != nil ? package(st, room) : nil,
                           number: crate(st, room, pull: pr?.number))
    }

    private func packed(_ room: Room, pull: Int?) -> WorkBook.Record? {
        guard let repo = room.repo else { return nil }
        return pull.flatMap { world.works.find(repo: repo, pull: $0) }.flatMap { $0.epic != nil ? $0 : nil } ?? world.works.find(officeKey: room.key, repo: repo)
    }

    private func crate(_ st: Station, _ room: Room, pull: Int?) -> Int? {
        packed(room, pull: pull).flatMap { $0.epic != nil ? $0.number : nil } ?? world.taskNumber(room) ?? pull
    }

    private func crateLeft(_ st: Station, _ room: Room, pull: Int?) -> Bool {
        guard let repo = room.repo, let r = packed(room, pull: pull), let n = r.number else { return false }
        if r.stage.map({ $0 >= .stored }) == true { return true }
        guard let at = shown[st.name]?.crates[CrateID(repo: repo, number: n)] else { return false }
        return at != .office(room.key)
    }

    func packageCell(_ st: Station, _ key: String) -> Cell? {
        guard let room = st.rooms[key] ?? st.lingering[key] else { return nil }
        return package(st, room)
    }

    private func package(_ st: Station, _ room: Room) -> Cell {
        let full = st.name + "|" + room.key
        if let held = packageCells[full], room.cells.contains(held), !st.consoleCells(room.key).contains(held) { return held }
        let coned = Set(bodies.values.filter { $0.station == st.name }.flatMap(\.cones))
        let cells = st.farCells(room)
        let cell = cells.first { !coned.contains($0) } ?? cells.first!
        packageCells[full] = cell
        return cell
    }

    func crated(_ st: Station, _ key: String) -> Set<Cell> {
        guard let marks = marks(st, key) else { return [] }
        return Set(marks.pile.map { Cell(x: Int($0.pos.x.rounded()), y: Int($0.pos.z.rounded())) } + (marks.package.map { [$0] } ?? []))
    }
}
