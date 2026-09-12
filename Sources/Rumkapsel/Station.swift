import Foundation

struct Cell: Hashable, Codable {
    var x: Int
    var y: Int
    static func + (a: Cell, b: Cell) -> Cell { Cell(x: a.x + b.x, y: a.y + b.y) }
    var neighbours: [Cell] { [Cell(x: x + 1, y: y), Cell(x: x - 1, y: y), Cell(x: x, y: y + 1), Cell(x: x, y: y - 1)] }
}

struct RGB: Codable, Equatable {
    var r: Double, g: Double, b: Double
    var tuple: (Double, Double, Double) { (r, g, b) }
}

enum Colors {
    static let hangar = RGB(r: 0.27, g: 0.42, b: 0.55)
    static let quarters = RGB(r: 0.46, g: 0.34, b: 0.44)
    static let bed = RGB(r: 0.33, g: 0.23, b: 0.32)
    /// Colours handed out to repositories, in order of first sighting.
    static let repos: [RGB] = [
        RGB(r: 0.83, g: 0.35, b: 0.55), RGB(r: 0.25, g: 0.65, b: 0.60), RGB(r: 0.94, g: 0.65, b: 0.10),
        RGB(r: 0.35, g: 0.78, b: 0.85), RGB(r: 0.94, g: 0.49, b: 0.13), RGB(r: 0.60, g: 0.62, b: 0.95),
        RGB(r: 0.80, g: 0.78, b: 0.25), RGB(r: 0.75, g: 0.55, b: 0.35), RGB(r: 0.45, g: 0.60, b: 0.95),
        RGB(r: 0.78, g: 0.42, b: 0.32), RGB(r: 0.30, g: 0.45, b: 0.80), RGB(r: 0.92, g: 0.80, b: 0.55),
    ]
}

/// Where a session's activity takes place inside its station.
enum Place: Hashable {
    case core
    case room(String)

    static let quarters = Place.room("kind:quarters")
    static let lounge = Place.room("kind:lounge")
    static let bath = Place.room("kind:bath")
    static let airlock = Place.room("kind:airlock")
    static let hangar = Place.room("kind:hangar")
    static let pad = Place.room("kind:pad")

    static func forActivity(_ a: Activity, home: String, isSubagent: Bool, night: Bool = true) -> Place {
        if isSubagent || a == .researching { return .core }
        if a == .sleeping { return night ? .quarters : .lounge }   // quiet by day: a read on the couch; by night: bed
        if a == .qa { return .room("kind:deck") }
        return .room(home)
    }
}

/// A task (branch) or project a session works on; the minion's home room.
struct Home {
    let key: String
    let name: String
    let repo: String
    let issue: Int?

    static func from(repo: String, branch: String?, cwd: String) -> Home {
        if let branch, let m = branch.firstMatch(of: #/^gh-(\d+)\/(.*)$/#), let n = Int(m.1) {
            let words = m.2.split(separator: "-").joined(separator: " ")
            return Home(key: "task:\(repo)#\(n)", name: "#\(n) " + shorten(words, to: 22), repo: repo, issue: n)
        }
        if let branch, !["main", "master", "develop", "HEAD", ""].contains(branch) {
            let slug = branch.split(separator: "/").last.map(String.init) ?? branch
            return Home(key: "task:\(repo)/\(branch)", name: shorten(slug.replacingOccurrences(of: "-", with: " "), to: 26), repo: repo, issue: nil)
        }
        return Home(key: "proj:\(repo)", name: repo, repo: repo, issue: nil)
    }

    /// Cuts at a word boundary near the limit, without a trailing ellipsis noise.
    private static func shorten(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let words = text.split(separator: " ")
        var out = ""
        for w in words {
            if out.isEmpty { out = String(w); continue }
            if out.count + 1 + w.count > limit { break }
            out += " " + w
        }
        return String(out.prefix(limit))
    }
}

final class Room {
    let key: String
    var name: String
    let repo: String?
    let color: RGB
    var cells: [Cell]
    var lastActive: Date
    var branch: String?
    var repoRoot: String?
    var worktree: String?

    init(key: String, name: String, repo: String?, color: RGB, cells: [Cell], lastActive: Date) {
        self.key = key; self.name = name; self.repo = repo; self.color = color; self.cells = cells; self.lastActive = lastActive
    }
}

/// One station: a corridor cross with tetromino rooms snapped against it.
final class Station {
    let name: String
    var hasHangar = true
    var hasPad = true
    private(set) var rooms: [String: Room] = [:]
    private(set) var spineHalfLength = 2
    private var occupied: [Cell: String] = [:]
    private var walkableCache: Set<Cell>?
    /// World-space offset of this station's local grid.
    var offset = SIMD2<Double>(0, 0)

    /// The monolith sits in a 2x2 block at the end of the north corridor arm.
    var coreCells: [Cell] {
        let y = -spineHalfLength - 1
        return [Cell(x: 0, y: y - 1), Cell(x: 1, y: y - 1), Cell(x: 0, y: y), Cell(x: 1, y: y)]
    }
    var coreCenter: Cell { Cell(x: 0, y: -spineHalfLength - 1) }
    /// The hangar is the 4x2 bay across the outer end of the south corridor arm, wider than it is long.
    /// The airlock: a 2x2 chamber that carries the corridor's line on past its south end, before the
    /// bay. The inner door is on its corridor side, the hatch on its bay side.
    var airlockCells: [Cell] { hasHangar ? (1...2).flatMap { d in (0...1).map { x in Cell(x: x, y: spineHalfLength + d) } } : [] }
    /// The chamber's inner row, just past the inner door: where a leaver waits for the cycle.
    var airlockInner: [Cell] { airlockCells.filter { $0.y == spineHalfLength + 1 } }
    /// The hatch: where the chamber's outer row opens onto the bay.
    var airlockHatches: [(inside: Cell, bay: Cell)] { airlockCells.filter { $0.y == spineHalfLength + 2 }.map { ($0, Cell(x: $0.x, y: $0.y + 1)) } }
    var hangarCells: [Cell] {
        guard hasHangar else { return [] }
        let y = spineHalfLength + 3   // past the airlock
        return (-1...2).flatMap { x in (0..<2).map { d in Cell(x: x, y: y + d) } }
    }
    var hangarCenter: SIMD2<Double> { SIMD2(0.5, Double(spineHalfLength) + 3.5) }
    /// Landing slots across the bay, in local coordinates.
    var hangarSlots: [SIMD2<Double>] { (0..<3).map { SIMD2(-0.5 + Double($0), Double(spineHalfLength) + 3.5) } }
    /// The yard sits along the station's west side in three 4x4 blocks: storage to the south-west,
    /// the test deck at the end of the west arm, and the launch pad to the north-west.
    private func yardRow(_ index: Int) -> Int { [4, 0, -4][index] }
    private func yardBlock(_ index: Int) -> [Cell] {
        guard hasPad else { return [] }
        let x0 = -spineHalfLength - 1
        let r = yardRow(index)
        return (0..<4).flatMap { d in (-1...2).map { y in Cell(x: x0 - d, y: y + r) } }
    }
    private func yardCenter(_ index: Int) -> SIMD2<Double> { SIMD2(Double(-spineHalfLength) - 2.5, 0.5 + Double(yardRow(index))) }
    var storageCells: [Cell] { yardBlock(0) }
    var storageCenter: SIMD2<Double> { yardCenter(0) }
    var deckCells: [Cell] { yardBlock(1) }
    var padCells: [Cell] { yardBlock(2) }
    var padCenter: SIMD2<Double> { yardCenter(2) }
    /// The storage row nearest the deck. Crates stack from the far wall, so this row is the pallet's.
    var storageNearRow: Int { storageCells.map(\.y).min() ?? 0 }
    /// Where a hover pallet stands in storage: the near row, on the column of a deck doorway.
    var palletCell: Cell { Cell(x: -spineHalfLength - 3, y: storageNearRow) }
    /// The console on the wall by the storage doorway: the cell it hangs in, and which way it faces.
    var storageConsole: (cell: Cell, facing: SIMD2<Double>) {
        (Cell(x: -spineHalfLength - 1, y: storageNearRow), SIMD2(0, -1))
    }

    /// Every crate this station knows: the source's word and the station's, per crate. The counts
    /// below are read off it and kept nowhere.
    var ledger = Ledger()
    /// Merged crates belonging to storage, per repository: standing there, or out of it on a pallet or on someone's arms.
    var stored: [String: Int] { ledger.counts(in: .storage) }
    var storedBoxes: Int { stored.values.reduce(0, +) }
    /// Crates belonging to the deck, per repository.
    var staged: [String: Int] { ledger.counts(in: .deck) }
    var monolithPosition: SIMD2<Double> { SIMD2(0.5, Double(-spineHalfLength) - 1.5) }
    /// Eight flat beds, one per dorm tile.
    var beds: [(pos: SIMD2<Double>, cell: Cell, level: Int)] {
        guard let q = rooms["kind:quarters"] else { return [] }
        return q.cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.prefix(8).map { (SIMD2(Double($0.x), Double($0.y)), $0, 0) }
    }
    /// Couch spots along the lounge walls where free workers sit.
    var couches: [SIMD2<Double>] {
        guard let l = rooms["kind:lounge"] else { return [] }
        let xs = l.cells.map(\.x), ys = l.cells.map(\.y)
        let minX = Double(xs.min()!), maxX = Double(xs.max()!), minY = Double(ys.min()!), maxY = Double(ys.max()!)
        let door = doorCell(of: "kind:lounge")
        let spots = [SIMD2(minX - 0.22, minY), SIMD2(minX - 0.22, maxY), SIMD2(maxX + 0.22, minY), SIMD2(maxX + 0.22, maxY), SIMD2(minX, maxY + 0.22), SIMD2(maxX, maxY + 0.22)]
        // Nothing parked across the doorway.
        return spots.filter { s in door.map { hypot(s.x - Double($0.x), s.y - Double($0.y)) > 0.6 } ?? true }
    }

    static func rect(_ w: Int, _ h: Int) -> [Cell] {
        (0..<w).flatMap { x in (0..<h).map { y in Cell(x: x, y: y) } }
    }
    /// Symmetric bars, blocks and T shapes, like the real station.
    private static let baseShapes: [[Cell]] = [
        rect(2, 3), rect(2, 4), rect(3, 3), rect(2, 2), rect(3, 2), rect(2, 5),
        rect(3, 2) + [Cell(x: 1, y: 2), Cell(x: 1, y: 3)],
        rect(3, 1) + [Cell(x: 1, y: 1), Cell(x: 1, y: 2)],
    ]

    init(name: String) {
        self.name = name
    }

    /// A two-wide corridor cross.
    var corridorCells: [Cell] {
        var out = Set<Cell>()
        for i in -spineHalfLength...spineHalfLength {
            out.insert(Cell(x: i, y: 0)); out.insert(Cell(x: i, y: 1))
            out.insert(Cell(x: 0, y: i)); out.insert(Cell(x: 1, y: i))
        }
        return out.filter { !coreCells.contains($0) && !hangarCells.contains($0) && !padCells.contains($0) && !storageCells.contains($0) && !deckCells.contains($0) }
    }

    /// The corridor axes are never built on, however far they extend.
    func isSpineLine(_ c: Cell) -> Bool { c.x == 0 || c.x == 1 || c.y == 0 || c.y == 1 }

    func room(at cell: Cell) -> Room? {
        guard let key = occupied[cell] else { return nil }
        return rooms[key]
    }

    func isCorridor(_ c: Cell) -> Bool {
        ((c.x == 0 || c.x == 1) && abs(c.y) <= spineHalfLength) || ((c.y == 0 || c.y == 1) && abs(c.x) <= spineHalfLength)
    }

    var walkable: Set<Cell> {
        if let w = walkableCache { return w }
        var w = Set(coreCells)
        w.formUnion(hangarCells)
        w.formUnion(airlockCells)
        w.formUnion(padCells)
        w.formUnion(storageCells)
        w.formUnion(deckCells)
        w.formUnion(corridorCells)
        for r in rooms.values { w.formUnion(r.cells) }
        walkableCache = w
        return w
    }

    var allCells: [Cell] { Array(walkable) }

    func cells(of place: Place) -> [Cell] {
        switch place {
        case .core: return coreCells + [Cell(x: 0, y: -spineHalfLength), Cell(x: 1, y: -spineHalfLength)]
        case .room("kind:hangar"): return hangarCells
        case .room("kind:airlock"): return airlockCells
        case .room("kind:pad"): return padCells
        case .room("kind:storage"): return storageCells
        case .room("kind:deck"): return deckCells.isEmpty ? padCells : deckCells
        case .room(let key): return rooms[key]?.cells ?? []
        }
    }

    /// Creates a room if missing. Returns true when the layout changed.
    @discardableResult
    func ensureRoom(key: String, name: String, repo: String?, color: RGB, lastActive: Date, shape: [Cell]? = nil, preferredCells: [Cell]? = nil, near: [Cell]? = nil) -> Bool {
        if let r = rooms[key] {
            r.lastActive = max(r.lastActive, lastActive)
            return false
        }
        let cells = preferredCells.flatMap { fits($0) ? $0 : nil } ?? placeShape(shape ?? Station.baseShapes[abs(key.hashValue) % Station.baseShapes.count], near: near)
        rooms[key] = Room(key: key, name: name, repo: repo, color: color, cells: cells, lastActive: lastActive)
        for c in cells { occupied[c] = key }
        walkableCache = nil
        return true
    }

    @discardableResult
    func ensureFixedRoom(_ place: Place) -> Bool {
        guard case .room(let key) = place else { return false }
        // The living quarters cluster: the lounge first, then the dorm and the bath beside it.
        let beside = (rooms["kind:lounge"]?.cells ?? []) + (rooms["kind:quarters"]?.cells ?? [])
        if key == "kind:quarters" { return ensureRoom(key: key, name: "sleeping", repo: nil, color: Colors.quarters, lastActive: .distantFuture, shape: Station.rect(2, 4), near: beside.isEmpty ? nil : beside) }
        if key == "kind:lounge" { return ensureRoom(key: key, name: "lounge", repo: nil, color: RGB(r: 0.40, g: 0.36, b: 0.30), lastActive: .distantFuture, shape: Station.rect(3, 3)) }
        if key == "kind:bath" { return ensureRoom(key: key, name: "bath", repo: nil, color: RGB(r: 0.52, g: 0.66, b: 0.70), lastActive: .distantFuture, shape: Station.rect(2, 2), near: beside.isEmpty ? nil : beside) }
        return false
    }

    /// Whether two rooms share a wall.
    func touching(_ a: String, _ b: String) -> Bool {
        guard let ra = rooms[a], let rb = rooms[b] else { return false }
        let set = Set(rb.cells)
        return ra.cells.contains { $0.neighbours.contains(where: set.contains) }
    }

    /// Restored layouts from before the cluster rule: put the dorm and bath back beside the lounge.
    func clusterQuarters() {
        guard rooms["kind:lounge"] != nil else { return }
        if !touching("kind:quarters", "kind:lounge") || !(touching("kind:bath", "kind:lounge") || touching("kind:bath", "kind:quarters")) {
            removeRoom(key: "kind:quarters"); removeRoom(key: "kind:bath")
            ensureFixedRoom(.quarters); ensureFixedRoom(.bath)
        }
    }

    /// The room cell that touches the corridor: the doorway, and where a carried box gets set down.
    func doorCell(of key: String) -> Cell? {
        guard let r = rooms[key] else { return nil }
        let candidates = r.cells.filter { $0.neighbours.contains(where: isCorridor) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        return candidates.first ?? r.cells.first
    }

    /// The corridor cell just outside a room's doorway.
    func doorOutside(of key: String) -> Cell? {
        guard let d = doorCell(of: key) else { return nil }
        return d.neighbours.first(where: isCorridor)
    }

    /// Walking between a room and the hallway is only allowed through the doorway.
    /// Which yard block, or the corridor, a cell belongs to; nil for rooms and the void.
    private func yardArea(_ c: Cell) -> String? {
        if airlockCells.contains(c) { return "airlock" }
        if hangarCells.contains(c) { return "hangar" }
        if storageCells.contains(c) { return "storage" }
        if deckCells.contains(c) { return "deck" }
        if padCells.contains(c) { return "pad" }
        if isCorridor(c) || coreCells.contains(c) { return "corridor" }
        return nil
    }

    /// Doorways through the yard: the corridor into the deck, and the deck into storage and the pad.
    var yardDoorways: [(Cell, Cell)] {
        guard hasPad else { return [] }
        let x0 = -spineHalfLength - 1
        var out: [(Cell, Cell)] = [(Cell(x: x0, y: 0), Cell(x: x0 + 1, y: 0)), (Cell(x: x0, y: 1), Cell(x: x0 + 1, y: 1))]
        // Corridor into the airlock, airlock out onto the bay: the only way to the outside.
        for a in airlockInner { out.append((Cell(x: a.x, y: a.y - 1), a)) }
        for h in airlockHatches { out.append((h.inside, h.bay)) }
        for x in [x0 - 1, x0 - 2] {
            out.append((Cell(x: x, y: 2), Cell(x: x, y: 3)))     // deck to storage
            out.append((Cell(x: x, y: -1), Cell(x: x, y: -2)))   // deck to pad
        }
        return out
    }

    private func canStep(from a: Cell, to b: Cell) -> Bool {
        if let ya = yardArea(a), let yb = yardArea(b), ya != yb {
            return yardDoorways.contains { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }
        }
        let ra = room(at: a)?.key, rb = room(at: b)?.key
        if ra == rb { return true }
        if let ra, rb == nil { return doorCell(of: ra) == a && doorOutside(of: ra) == b }
        if let rb, ra == nil { return doorCell(of: rb) == b && doorOutside(of: rb) == a }
        return false
    }

    /// Renames a room in place, keeping its floor.
    func renameRoom(from old: String, to new: String, name: String) {
        guard let r = rooms[old], rooms[new] == nil else { return }
        let nr = Room(key: new, name: name, repo: r.repo, color: r.color, cells: r.cells, lastActive: r.lastActive)
        nr.branch = r.branch; nr.repoRoot = r.repoRoot; nr.worktree = r.worktree
        rooms[old] = nil
        rooms[new] = nr
        for c in nr.cells { occupied[c] = new }
    }

    func removeRoom(key: String) {
        guard let r = rooms.removeValue(forKey: key) else { return }
        for c in r.cells { occupied[c] = nil }
        walkableCache = nil
    }

    private func rotations(of shape: [Cell]) -> [[Cell]] {
        var out: [[Cell]] = []
        var cur = shape
        for _ in 0..<4 {
            let minX = cur.map(\.x).min()!, minY = cur.map(\.y).min()!
            let norm = cur.map { Cell(x: $0.x - minX, y: $0.y - minY) }.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            if !out.contains(norm) { out.append(norm) }
            cur = cur.map { Cell(x: -$0.y, y: $0.x) }
        }
        return out
    }

    /// Whether a peer's placement can be adopted as is: free floor, against our corridor.
    private func fits(_ cells: [Cell]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { !isReserved($0) && occupied[$0] == nil && abs($0.x) <= spineHalfLength + 4 && abs($0.y) <= spineHalfLength + 4 }
            && cells.contains { $0.neighbours.contains(where: isCorridor) }
    }

    private func isReserved(_ c: Cell) -> Bool {
        isSpineLine(c) || coreCells.contains(c) || airlockCells.contains(c) || hangarCells.contains(c) || padCells.contains(c) || storageCells.contains(c) || deckCells.contains(c)
    }

    private func placeShape(_ shape: [Cell], near: [Cell]? = nil) -> [Cell] {
        let variants = rotations(of: shape)
        var rounds = 0
        while rounds < 40 {   // bounded: a station can never wedge the render thread
            rounds += 1
            let reach = spineHalfLength + 4
            var anchors: [Cell] = []
            for x in -reach...reach { for y in -reach...reach { anchors.append(Cell(x: x, y: y)) } }
            if let near, !near.isEmpty {
                // Beside the given rooms: closest to their floor first, then the usual order.
                let set = Set(near)
                func gap(_ c: Cell) -> Int { near.map { abs($0.x - c.x) + abs($0.y - c.y) }.min()! }
                anchors.sort {
                    let ga = gap($0), gb = gap($1)
                    if ga != gb { return ga < gb }
                    return (max(abs($0.x), abs($0.y)), $0.x, $0.y) < (max(abs($1.x), abs($1.y)), $1.x, $1.y)
                }
                for anchor in anchors {
                    for v in variants {
                        let cells = v.map { $0 + anchor }
                        guard cells.allSatisfy({ !isReserved($0) && occupied[$0] == nil && !set.contains($0) }) else { continue }
                        guard cells.contains(where: { $0.neighbours.contains(where: isCorridor) }) else { continue }
                        guard cells.contains(where: { $0.neighbours.contains(where: set.contains) }) else { continue }
                        guard flatTowardsCorridor(cells) else { continue }
                        return cells
                    }
                }
                // Nothing beside them fits: fall through to the usual search.
            }
            anchors.sort {
                let a = max(abs($0.x), abs($0.y)), b = max(abs($1.x), abs($1.y))
                if a != b { return a < b }
                let sa = abs($0.x) + abs($0.y), sb = abs($1.x) + abs($1.y)
                if sa != sb { return sa < sb }
                return ($0.x, $0.y) < ($1.x, $1.y)
            }
            for anchor in anchors {
                for v in variants {
                    let cells = v.map { $0 + anchor }
                    guard cells.allSatisfy({ !isReserved($0) && occupied[$0] == nil }) else { continue }
                    guard cells.contains(where: { $0.neighbours.contains(where: isCorridor) }) else { continue }
                    guard flatTowardsCorridor(cells) else { continue }
                    return cells
                }
            }
            spineHalfLength += 2
            walkableCache = nil
        }
        // Give up gracefully: park the room in a free spot far out along the east arm.
        let far = Cell(x: spineHalfLength + 2, y: 2)
        return variants[0].map { $0 + far }
    }

    /// A room shows a straight wall to the hallway: a T with its notch against the corridor
    /// would leave a dark closet between the room, the hallway and its neighbours.
    private func flatTowardsCorridor(_ cells: [Cell]) -> Bool {
        let set = Set(cells)
        let minX = cells.map(\.x).min()!, maxX = cells.map(\.x).max()!
        let minY = cells.map(\.y).min()!, maxY = cells.map(\.y).max()!
        for (dx, dy) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
            guard cells.contains(where: { isCorridor(Cell(x: $0.x + dx, y: $0.y + dy)) }) else { continue }
            // The whole edge line facing that direction must be part of the room.
            let edge: [Cell]
            if dx == 0 {
                let y = dy > 0 ? maxY : minY
                edge = (minX...maxX).map { Cell(x: $0, y: y) }
            } else {
                let x = dx > 0 ? maxX : minX
                edge = (minY...maxY).map { Cell(x: x, y: $0) }
            }
            if !edge.allSatisfy({ set.contains($0) }) { return false }
        }
        return true
    }

    /// Breadth-first path over walkable cells. Returns cells to visit, excluding `from`.
    // MARK: walking round things

    /// Props on the floor, as blocked spots on a finer grid: three steps to a cell side, so a minion
    /// (a fifth of a cell wide) can squeeze past a crate sideways. Set by the controller from the scene.
    var obstacles: Set<Cell> = []
    static let fine = 3
    static func sub(_ p: SIMD2<Double>) -> Cell { Cell(x: Int((p.x * Double(fine)).rounded()), y: Int((p.y * Double(fine)).rounded())) }
    static func cell(ofSub s: Cell) -> Cell { Cell(x: Int((Double(s.x) / Double(fine)).rounded()), y: Int((Double(s.y) / Double(fine)).rounded())) }
    static func point(ofSub s: Cell) -> SIMD2<Double> { SIMD2(Double(s.x) / Double(fine), Double(s.y) / Double(fine)) }

    /// Waypoints from a position to a cell, threading between crates, boxes and pyramids. Ends on the
    /// cell's centre when that is clear, else on the clearest spot in it. Falls back to wading through
    /// on the coarse grid only when nothing is passable at all.
    /// A lane along a wall: a spot whose next spot over lies where a walk may not go. Kept off unless
    /// nothing else leads through, so walks run down the middle and never brush the walls.
    private func isEdge(_ s: Cell) -> Bool {
        let cc = Station.cell(ofSub: s)
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let n = Cell(x: s.x + dx, y: s.y + dy)
            let nc = Station.cell(ofSub: n)
            if nc == cc { continue }
            if !walkable.contains(nc) || !canStep(from: cc, to: nc) { return true }
        }
        return false
    }

    /// Waypoints from a position to a cell. `avoiding` are spots taken right now by things that move,
    /// other minions mostly; they block like props do. Inner lanes first, wall lanes only if that fails.
    func path(from: SIMD2<Double>, to: Cell, avoiding: Set<Cell> = []) -> [SIMD2<Double>] {
        if let inner = route(from: from, to: to, avoiding: avoiding, edges: false) { return inner }
        return route(from: from, to: to, avoiding: avoiding, edges: true) ?? []
    }

    private func route(from: SIMD2<Double>, to: Cell, avoiding: Set<Cell>, edges: Bool) -> [SIMD2<Double>]? {
        let obstacles = self.obstacles.union(avoiding)
        guard walkable.contains(to) else { return [] }
        let start = Station.sub(from)
        func spots(in c: Cell) -> [Cell] {
            let centre = Cell(x: c.x * Station.fine, y: c.y * Station.fine)
            return (-1...1).flatMap { dx in (-1...1).map { dy in Cell(x: centre.x + dx, y: centre.y + dy) } }
        }
        // A cell with something standing on its middle (a crate, a pallet's edge) is no destination:
        // settle for the nearest cell whose middle is free, so nobody ends up wedged against a thing.
        var target = to
        if obstacles.contains(Cell(x: to.x * Station.fine, y: to.y * Station.fine)) {
            // Only within the same room (or the same open floor): never send someone next door instead.
            let owner = room(at: to)?.key
            var seen: Set<Cell> = [to]; var ring = [to]
            search: while !ring.isEmpty {
                var next: [Cell] = []
                for c in ring {
                    for n in c.neighbours where walkable.contains(n) && !seen.contains(n) && canStep(from: c, to: n) && room(at: n)?.key == owner {
                        if !obstacles.contains(Cell(x: n.x * Station.fine, y: n.y * Station.fine)) { target = n; break search }
                        seen.insert(n); next.append(n)
                    }
                }
                ring = next
            }
        }
        let centre = Cell(x: target.x * Station.fine, y: target.y * Station.fine)
        let free = spots(in: target).filter { !obstacles.contains($0) }
        let goals: Set<Cell> = !obstacles.contains(centre) ? [centre] : (free.isEmpty ? [centre] : Set(free))
        if goals.contains(start) { return [] }
        var prev: [Cell: Cell] = [start: start]
        var queue = [start]
        var head = 0
        var found: Cell?
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        func open(_ s: Cell) -> Bool {
            walkable.contains(Station.cell(ofSub: s)) && (!obstacles.contains(s) || goals.contains(s)) && (edges || goals.contains(s) || !isEdge(s))
        }
        while head < queue.count, head < 12000 {
            let c = queue[head]; head += 1
            if goals.contains(c) { found = c; break }
            let cc = Station.cell(ofSub: c)
            for (dx, dy) in steps {
                let n = Cell(x: c.x + dx, y: c.y + dy)
                guard prev[n] == nil, open(n) else { continue }
                let nc = Station.cell(ofSub: n)
                if cc != nc && !canStep(from: cc, to: nc) { continue }
                if dx != 0 && dy != 0 {   // no cutting corners round a crate or through a wall
                    let a = Cell(x: c.x + dx, y: c.y), b = Cell(x: c.x, y: c.y + dy)
                    guard open(a), open(b), canStep(from: cc, to: Station.cell(ofSub: a)), canStep(from: cc, to: Station.cell(ofSub: b)) else { continue }
                }
                prev[n] = c
                queue.append(n)
            }
        }
        guard let end = found else {
            if !edges { return nil }   // try again with the wall lanes allowed
            return coarsePath(from: Station.cell(ofSub: start), to: to).map { SIMD2(Double($0.x), Double($0.y)) }
        }
        var subs: [Cell] = []
        var cur = end
        while cur != start { subs.append(cur); cur = prev[cur]! }
        subs.reverse()
        // Merge straight runs so the walk is a few clean legs rather than a stutter of tiny steps.
        var out: [SIMD2<Double>] = []
        var last = start
        var dir = Cell(x: 0, y: 0)
        for s in subs {
            let d = Cell(x: s.x - last.x, y: s.y - last.y)
            if d == dir, !out.isEmpty { out[out.count - 1] = Station.point(ofSub: s) } else { out.append(Station.point(ofSub: s)) }
            dir = d; last = s
        }
        return out
    }

    func coarsePath(from: Cell, to: Cell) -> [Cell] {
        guard from != to, walkable.contains(to) else { return [] }
        var prev: [Cell: Cell] = [from: from]
        var queue = [from]
        var head = 0
        while head < queue.count {
            let c = queue[head]; head += 1
            if c == to { break }
            for n in c.neighbours where walkable.contains(n) && prev[n] == nil && canStep(from: c, to: n) {
                prev[n] = c
                queue.append(n)
            }
        }
        guard prev[to] != nil else { return [] }
        var out: [Cell] = []
        var cur = to
        while cur != from { out.append(cur); cur = prev[cur]! }
        return out.reversed()
    }

    var bounds: (min: Cell, max: Cell) {
        let cells = allCells
        return (Cell(x: cells.map(\.x).min() ?? 0, y: cells.map(\.y).min() ?? 0),
                Cell(x: cells.map(\.x).max() ?? 0, y: cells.map(\.y).max() ?? 0))
    }

    // MARK: persistence

    struct Saved: Codable {
        var spine: Int
        var rooms: [String: SavedRoom]
        var stored: Int?
        /// From before the ledger: counts kept on the station. Read by nothing now.
        var storedByRepo: [String: Int]?
        var stagedByRepo: [String: Int]?
        var ledger: Ledger?
    }
    struct SavedRoom: Codable { var name: String; var repo: String?; var color: RGB; var cells: [Cell]; var lastActive: Date; var worktree: String?; var branch: String?; var repoRoot: String? }

    var saved: Saved {
        Saved(spine: spineHalfLength, rooms: rooms.mapValues {
            SavedRoom(name: $0.name, repo: $0.repo, color: $0.color, cells: $0.cells, lastActive: $0.lastActive, worktree: $0.worktree, branch: $0.branch, repoRoot: $0.repoRoot)
        }, stored: storedBoxes, ledger: ledger)
    }

    func restore(_ s: Saved) {
        spineHalfLength = s.spine
        ledger = s.ledger ?? Ledger()
        for (key, r) in s.rooms where key != "kind:hangar" && !key.hasPrefix("crew:") {
            guard r.cells.allSatisfy({ !isReserved($0) && occupied[$0] == nil }) else { continue }
            let room = Room(key: key, name: r.name, repo: r.repo, color: r.color, cells: r.cells, lastActive: r.lastActive)
            room.worktree = r.worktree; room.branch = r.branch; room.repoRoot = r.repoRoot
            rooms[key] = room
            for c in r.cells { occupied[c] = key }
        }
        walkableCache = nil
    }
}

/// The two stations, side by side in the void, plus the repo colour book.
final class Fleet {
    private(set) var stations: [String: Station] = [:]
    private(set) var repoColors: [String: Int] = [:]
    /// The simulator runs on a made-up fleet: it must not read or write the saved layout.
    var persists = true

    static let order = ["work", "private"]

    private static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rumkapsel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fleet-v20.json")
    }

    static func stationName(for cwd: String, owner: String?, repo: String) -> String {
        ConfigStore.shared.current.station(cwd: cwd, owner: owner, repo: repo)
    }

    func removeAllStations() { stations = [:] }
    func removeStation(named name: String) { stations[name] = nil }

    /// A repository's colour comes from its name, not from the order it was first seen, so it is the
    /// same on every launch and on every station: a hash picks the palette slot, and a name whose slot
    /// another name already holds takes the next free one, names in alphabetical order.
    func color(forRepo repo: String) -> RGB {
        if repoColors[repo] == nil { repoColors[repo] = 0; assignColors() }
        return Colors.repos[(repoColors[repo] ?? 0) % Colors.repos.count]
    }

    private func assignColors() {
        let n = Colors.repos.count
        var taken: [Int: String] = [:]
        for name in repoColors.keys.sorted() {
            var h: UInt64 = 14695981039346656037
            for b in name.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
            var i = Int(h % UInt64(n))
            var tries = 0
            while taken[i] != nil, tries < n { i = (i + 1) % n; tries += 1 }
            taken[i] = name
            repoColors[name] = i
        }
    }

    func station(_ name: String) -> Station {
        if let s = stations[name] { return s }
        let s = Station(name: name)
        s.ensureFixedRoom(.quarters)
        s.ensureFixedRoom(.lounge)
        s.ensureFixedRoom(.bath)
        stations[name] = s
        return s
    }

    var ordered: [Station] { Fleet.order.compactMap { stations[$0] } }

    /// Work sits on the top row; private sits below work, keeping the whole fleet squarish rather than a long strip.
    func arrange() {
        var x = 0.0
        var rowMaxY = 0.0
        for s in ordered where s.name != "private" {
            let b = s.bounds
            if x > 0 { x += 3 }
            s.offset = SIMD2(x - Double(b.min.x), 0)
            x += Double(b.max.x - b.min.x + 1)
            rowMaxY = max(rowMaxY, Double(b.max.y))
        }
        if let p = stations["private"] {
            let b = p.bounds
            let anchor = stations["work"] ?? ordered.first
            let ax = anchor.map { $0.offset.x + Double($0.bounds.min.x) } ?? 0
            p.offset = SIMD2(ax - Double(b.min.x) + 4, rowMaxY + 6 - Double(b.min.y))
        }
    }

    var worldBounds: (min: SIMD2<Double>, max: SIMD2<Double>) {
        var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
        for s in stations.values {
            let b = s.bounds
            lo = pointwiseMin(lo, SIMD2(Double(b.min.x), Double(b.min.y)) + s.offset)
            hi = pointwiseMax(hi, SIMD2(Double(b.max.x), Double(b.max.y)) + s.offset)
        }
        if lo.x == .infinity { return (SIMD2(-3, -3), SIMD2(3, 3)) }
        return (lo, hi)
    }

    private struct Saved: Codable { var stations: [String: Station.Saved]; var repoColors: [String: Int] }

    func save() {
        guard persists else { return }
        let s = Saved(stations: stations.mapValues(\.saved), repoColors: repoColors)
        if let json = try? JSONEncoder().encode(s) { try? json.write(to: Fleet.saveURL) }
    }

    func load() {
        guard persists else { return }
        guard let data = try? Data(contentsOf: Fleet.saveURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        repoColors = saved.repoColors
        assignColors()   // by name, whatever order an older save gave them
        for (name, s) in saved.stations where name != "crew" {
            let station = Station(name: name)
            station.restore(s)
            station.ensureFixedRoom(.quarters)
            station.ensureFixedRoom(.lounge)
            station.ensureFixedRoom(.bath)
            station.clusterQuarters()
            station.removeRoom(key: "kind:airlock")   // from before the airlock had its place in the corridor's line
            stations[name] = station
        }
    }
}
