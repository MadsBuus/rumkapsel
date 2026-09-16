import Foundation

/// A hash that is the same in every run, for the little disorder that must not change between launches:
/// Swift's own `hashValue` is seeded afresh per process. FNV-1a over the UTF-8 bytes.
func stableHash(_ text: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

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
    static let gym = Place.room("kind:gym")
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
    var hasHangar = true { didSet { forgetFloorPlan() } }
    var hasPad = true { didSet { forgetFloorPlan() } }
    private(set) var rooms: [String: Room] = [:]
    /// The hallway dug beyond the plaza and the fixed arms, in the order it was dug: the long arms built
    /// on, the alleys off them and the links between them. Every cell of it exists because a room needed
    /// it. Saved with the station.
    private(set) var dug: [Cell] = [] { didSet { forgetFloorPlan() } }
    private var dugSet: Set<Cell> { Set(dug) }
    /// How far the north arm is built, in steps: for the tests and the log.
    var spineHalfLength: Int { plan.north.prefix { dugSet.contains($0) }.count }
    private var occupied: [Cell: String] = [:]
    private var walkableCache: Set<Cell>?
    /// Which yard block or the corridor each cell is in, and the doorways through the yard: read on
    /// every step of every route, built once per floor plan.
    private var yardAreaCache: [Cell: String]?
    private var doorwaysCache: [(Cell, Cell)]?
    private var doorCache: [String: Cell] = [:]
    /// Couch and bed spots: read for every resting minion every tick, built once per floor plan.
    private var couchCache: [SIMD2<Double>]?
    private var bedCache: [(pos: SIMD2<Double>, cell: Cell, level: Int)]?
    private func forgetFloorPlan() { blocksCache = nil; walkableCache = nil; yardAreaCache = nil; doorwaysCache = nil; doorCache = [:]; couchCache = nil; bedCache = nil }
    /// World-space offset of this station's local grid.
    var offset = SIMD2<Double>(0, 0)

    /// The floor plan drawn from the station's name: the plaza, the four arms, the alleys. Built once;
    /// everything below reads it. How much of the north and east arms is built is `spineHalfLength`.
    private var planCache: Plan?
    var plan: Plan {
        if let p = planCache { return p }
        let p = Plan(seed: stableHash(name))
        planCache = p
        return p
    }

    /// The fixed parts of the floor, built once per floor plan: read on every step of every route,
    /// every placement and every walk, so never as fresh arrays each time.
    private struct Blocks {
        var core: [Cell], airlock: [Cell], hangar: [Cell], storage: [Cell], deck: [Cell], pad: [Cell], decon: [Cell], corridor: [Cell]
        /// The hallway that is built so far, plaza included: what a room may have its door on.
        var hallway: Set<Cell>
        /// Every cell no room may take: the whole plan, built or not, and the blocks.
        var reserved: Set<Cell>
        /// Steps along the hallway from the plaza, for every built hallway cell.
        var hallDistance: [Cell: Int]
    }
    private var blocksCache: Blocks?
    private var blocks: Blocks {
        if let b = blocksCache { return b }
        let core = plan.plaza, airlock = makeAirlockCells(), hangar = makeHangarCells()
        let storage = yardBlock(0), deck = yardBlock(1), pad = yardBlock(2), decon = makeDeconCells()
        var reserved = Set(core)
        for cells in [airlock, hangar, storage, deck, pad, decon] { reserved.formUnion(cells) }
        reserved.formUnion(plan.everyHallwayCell)
        reserved.formUnion(dug)   // hallway once dug is hallway for good
        let built = Set(plan.west + plan.south).union(dug)
        var hallway = Set(core)
        hallway.formUnion(built)
        // Steps from the plaza along the built hallway: what "nearest the middle" means on a wandering line.
        var dist: [Cell: Int] = [:]
        var queue = core.filter { $0 != plan.monolith }
        for c in queue { dist[c] = 0 }
        var head = 0
        while head < queue.count {
            let c = queue[head]; head += 1
            for n in c.neighbours where hallway.contains(n) && n != plan.monolith && dist[n] == nil { dist[n] = dist[c]! + 1; queue.append(n) }
        }
        let b = Blocks(core: core, airlock: airlock, hangar: hangar, storage: storage, deck: deck, pad: pad, decon: decon,
                       corridor: built.sorted { ($0.y, $0.x) < ($1.y, $1.x) }, hallway: hallway, reserved: reserved, hallDistance: dist)
        blocksCache = b
        return b
    }

    /// The plaza: three by three of hallway floor with the monolith on the middle tile.
    var coreCells: [Cell] { blocks.core }
    var monolithCell: Cell { plan.monolith }
    /// Where a body stands when sent to the monolith: the tile south of it.
    var coreCenter: Cell { Cell(x: plan.monolith.x, y: plan.monolith.y + 1) }
    /// The airlock: a passage one wide that carries the south arm's line on through the hull, the bay
    /// hanging outside its far end. The inner door is on its hallway side, the hatch on its bay side.
    var airlockCells: [Cell] { blocks.airlock }
    /// How many tiles the airlock runs, so the bay stands off the station rather than against it.
    static let airlockLength = 5
    private func makeAirlockCells() -> [Cell] {
        guard hasHangar, let end = plan.south.last else { return [] }
        return (1...Station.airlockLength).map { Cell(x: end.x, y: end.y + $0) }
    }
    /// The chamber's inner cell, just past the inner door: where a leaver waits for the cycle.
    var airlockInner: [Cell] { airlockCells.prefix(1).map { $0 } }
    /// The hatch: where the chamber's outer cell opens onto the bay.
    var airlockHatches: [(inside: Cell, bay: Cell)] { airlockCells.suffix(1).map { ($0, Cell(x: $0.x, y: $0.y + 1)) } }
    /// The bay: five wide and three deep across the far end of the airlock. The ships land on the back row,
    /// two tiles apart, so nobody at one slot is ever within a tile of the next; the middle row is where
    /// a carrier stands to wait for its crate; the front row is the way in from the hatch.
    var hangarCells: [Cell] { blocks.hangar }
    private func makeHangarCells() -> [Cell] {
        guard hasHangar, let end = plan.south.last else { return [] }
        let y = end.y + Station.airlockLength + 1   // past the airlock's hatch
        return (-2...2).flatMap { dx in (0..<3).map { d in Cell(x: end.x + dx, y: y + d) } }
    }
    var hangarCenter: SIMD2<Double> {
        guard let end = plan.south.last else { return .zero }
        return SIMD2(Double(end.x), Double(end.y + Station.airlockLength) + 2)
    }
    /// Landing slots across the bay's back row, two tiles apart.
    var hangarSlots: [SIMD2<Double>] {
        guard let end = plan.south.last else { return [] }
        return [-2, 0, 2].map { SIMD2(Double(end.x + $0), Double(end.y + Station.airlockLength) + 3) }
    }
    /// Where a carrier stands to wait for a slot's crate: the middle row, a tile in front of the slot.
    func bayStand(slot: Int) -> Cell {
        guard let end = plan.south.last else { return coreCenter }
        return Cell(x: end.x + (min(2, max(0, slot)) - 1) * 2, y: end.y + Station.airlockLength + 2)
    }
    /// The yard sits along the station's west side in three 4x4 blocks: storage to the south-west,
    /// the test deck at the end of the west arm, and the launch pad to the north-west. `yardX0` is the
    /// deck's east column, the one the west arm's last cell opens onto.
    private var yardX0: Int { (plan.west.last?.x ?? -2) - 1 }
    /// How far the pad stands off the deck: hard by it in the classic plan, a causeway's length away on
    /// the ground, as a launch complex keeps its distance from the buildings.
    private var padGap: Int { Theme.forPlan.padGap }
    private func yardRow(_ index: Int) -> Int { [4, 0, -4][index] }
    /// The pad block's east column and top row: north of the deck in the classic plan; on the ground,
    /// west of it out toward the sea, with the causeway between.
    private var padOrigin: (x0: Int, r: Int) { padGap > 0 ? (yardX0 - 4 - padGap, 0) : (yardX0, -4) }
    private func yardBlock(_ index: Int) -> [Cell] {
        guard hasPad else { return [] }
        let (x0, r) = index == 2 ? padOrigin : (yardX0, yardRow(index))
        var cells = (0..<4).flatMap { d in (-1...2).map { y in Cell(x: x0 - d, y: y + r) } }
        if index == 2, padGap > 0 {
            // The causeway: two lanes from the deck's west side out to the pad, pad floor the whole way.
            for x in (x0 + 1)...(yardX0 - 4) { for y in [0, 1] { cells.append(Cell(x: x, y: y)) } }
        }
        return cells
    }
    private func yardCenter(_ index: Int) -> SIMD2<Double> {
        let (x0, r) = index == 2 ? padOrigin : (yardX0, yardRow(index))
        return SIMD2(Double(x0) - 1.5, 0.5 + Double(r))
    }
    var storageCells: [Cell] { blocks.storage }
    var storageCenter: SIMD2<Double> { yardCenter(0) }
    var deckCells: [Cell] { blocks.deck }
    var padCells: [Cell] { blocks.pad }
    var padCenter: SIMD2<Double> { yardCenter(2) }
    /// The storage row nearest the deck. Crates stack from the far wall, so this row is the pallet's.
    var storageNearRow: Int { storageCells.map(\.y).min() ?? 0 }
    /// Where a hover pallet stands in storage: the near row, on the column of a deck doorway.
    var palletCell: Cell { Cell(x: yardX0 - 2, y: storageNearRow) }
    /// The console on the wall by the storage doorway: the cell it hangs in, and which way it faces.
    var storageConsole: (cell: Cell, facing: SIMD2<Double>) {
        (Cell(x: yardX0, y: storageNearRow), SIMD2(0, -1))
    }

    /// Decon: a chamber two cells deep at the back of storage, on its south side, the yard's fourth
    /// block. Anything from outside waits in it until someone clears it into storage. Its hatch is in
    /// the back wall, the row nearest it is where the objects stand, and the row by storage is the aisle.
    var deconCells: [Cell] { blocks.decon }
    private func makeDeconCells() -> [Cell] {
        guard hasPad else { return [] }
        let x0 = yardX0, r = yardRow(0)
        return (3..<5).flatMap { d in (0..<4).map { x in Cell(x: x0 - x, y: r + d) } }
    }
    var deconCenter: SIMD2<Double> { SIMD2(Double(yardX0) - 1.5, Double(yardRow(0)) + 3.5) }
    /// The hatch in decon's back wall, and which way it faces: into the chamber.
    var deconHatch: (pos: SIMD2<Double>, facing: SIMD2<Double>) { (SIMD2(Double(yardX0) - 1.5, Double(yardRow(0)) + 4.46), SIMD2(0, -1)) }

    /// Every crate this station knows: the source's word and the station's, per crate. The counts
    /// below are read off it and kept nowhere.
    var ledger = Ledger()
    /// Merged crates belonging to storage, per repository: standing there, or out of it on a pallet or on someone's arms.
    var stored: [String: Int] { ledger.counts(in: .storage) }
    var storedBoxes: Int { stored.values.reduce(0, +) }
    /// Crates belonging to the deck, per repository.
    var staged: [String: Int] { ledger.counts(in: .deck) }
    var monolithPosition: SIMD2<Double> { SIMD2(Double(plan.monolith.x), Double(plan.monolith.y)) }
    /// Eight flat beds, one per dorm tile.
    var beds: [(pos: SIMD2<Double>, cell: Cell, level: Int)] {
        if let b = bedCache { return b }
        guard let q = rooms["kind:quarters"] else { return [] }
        // Nothing sits in a doorway: a sleeper on the door cell would shut the room to everyone else.
        let door = doorCell(of: "kind:quarters")
        let b = q.cells.filter { $0 != door }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.prefix(8).map { (SIMD2(Double($0.x), Double($0.y)), $0, 0) }
        bedCache = b
        return b
    }
    /// Couch spots along the lounge walls where free workers sit.
    var couches: [SIMD2<Double>] {
        if let c = couchCache { return c }
        guard let l = rooms["kind:lounge"] else { return [] }
        let xs = l.cells.map(\.x), ys = l.cells.map(\.y)
        let minX = Double(xs.min()!), maxX = Double(xs.max()!), minY = Double(ys.min()!), maxY = Double(ys.max()!)
        let door = doorCell(of: "kind:lounge")
        let spots = [SIMD2(minX - 0.22, minY), SIMD2(minX - 0.22, maxY), SIMD2(maxX + 0.22, minY), SIMD2(maxX + 0.22, maxY), SIMD2(minX, maxY + 0.22), SIMD2(maxX, maxY + 0.22)]
        // Nothing parked across the doorway.
        let c = spots.filter { s in door.map { hypot(s.x - Double($0.x), s.y - Double($0.y)) > 0.6 } ?? true }
        couchCache = c
        return c
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

    /// The hallway built so far, plaza aside: the arms and their alleys, one tile wide.
    var corridorCells: [Cell] { blocks.corridor }
    /// Steps along the hallway from the plaza; nil off the hallway.
    func hallDistance(of c: Cell) -> Int? { blocks.hallDistance[c] }
    /// In what order a hallway cell was dug, 0 for the plaza and the fixed arms: for the fade-in of new floor.
    func digOrder(of c: Cell) -> Int { (dug.firstIndex(of: c) ?? -1) + 1 }
    var dugCount: Int { dug.count }

    func room(at cell: Cell) -> Room? {
        guard let key = occupied[cell] else { return nil }
        return rooms[key]
    }

    /// Built hallway floor, the plaza's ring included and the monolith's own tile not.
    func isCorridor(_ c: Cell) -> Bool { c != plan.monolith && blocks.hallway.contains(c) }

    var walkable: Set<Cell> {
        if let w = walkableCache { return w }
        var w = Set(coreCells)
        w.remove(plan.monolith)   // the monolith stands on its tile; the walk goes round it on the plaza
        w.formUnion(hangarCells)
        w.formUnion(airlockCells)
        w.formUnion(padCells)
        w.formUnion(storageCells)
        w.formUnion(deckCells)
        w.formUnion(deconCells)
        w.formUnion(corridorCells)
        for r in rooms.values { w.formUnion(r.cells) }
        walkableCache = w
        return w
    }

    var allCells: [Cell] { Array(walkable) }

    func cells(of place: Place) -> [Cell] {
        switch place {
        case .core: return coreCells.filter { $0 != plan.monolith }
        case .room("kind:hangar"): return hangarCells
        case .room("kind:airlock"): return airlockCells
        case .room("kind:pad"): return padCells
        case .room("kind:storage"): return storageCells
        case .room("kind:deck"): return deckCells.isEmpty ? padCells : deckCells
        case .room(let key): return rooms[key]?.cells ?? []
        }
    }

    /// Tuning of the digging (`placeShape`): how far an arm is cheap to build on, and what a step of it costs after.
    static var armEasyReach = 6, armDearStep = 2, passageBonus = 16

    /// Creates a room if missing. Returns true when the layout changed.
    @discardableResult
    /// The shape a room takes when nothing else says: by its key through the stable hash, so it is the same
    /// on every launch and on every machine.
    static func shape(forKey key: String) -> [Cell] { baseShapes[Int(stableHash(key) % UInt64(baseShapes.count))] }

    func ensureRoom(key: String, name: String, repo: String?, color: RGB, lastActive: Date, shape: [Cell]? = nil, preferredCells: [Cell]? = nil, near: [Cell]? = nil) -> Bool {
        if let r = rooms[key] {
            r.lastActive = max(r.lastActive, lastActive)
            return false
        }
        let cells = preferredCells.flatMap { adopt($0) ? $0 : nil } ?? placeShape(shape ?? Station.shape(forKey: key), near: near)
        rooms[key] = Room(key: key, name: name, repo: repo, color: color, cells: cells, lastActive: lastActive)
        for c in cells { occupied[c] = key }
        forgetFloorPlan()
        return true
    }

    @discardableResult
    func ensureFixedRoom(_ place: Place) -> Bool {
        guard case .room(let key) = place else { return false }
        // The living quarters cluster: the lounge first, then the dorm and the bath beside it.
        let beside = (rooms["kind:lounge"]?.cells ?? []) + (rooms["kind:quarters"]?.cells ?? []) + (rooms["kind:bath"]?.cells ?? [])
        if key == "kind:gym" { return ensureRoom(key: key, name: "gym", repo: nil, color: RGB(r: 0.38, g: 0.52, b: 0.42), lastActive: .distantFuture, shape: Station.rect(3, 2), near: beside.isEmpty ? nil : beside) }
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
        // The gym is part of the cluster too: against the lounge, the dorm or the bath.
        if rooms["kind:gym"] != nil, !["kind:lounge", "kind:quarters", "kind:bath"].contains(where: { touching("kind:gym", $0) }) {
            removeRoom(key: "kind:gym"); ensureFixedRoom(.gym)
        }
    }

    /// The room cell that touches the corridor: the doorway, and where a carried box gets set down.
    func doorCell(of key: String) -> Cell? {
        if let d = doorCache[key] { return d }
        guard let r = rooms[key] else { return nil }
        let candidates = r.cells.filter { $0.neighbours.contains(where: isCorridor) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let d = candidates.first ?? r.cells.first
        if let d { doorCache[key] = d }
        return d
    }

    /// The corridor cell just outside a room's doorway.
    func doorOutside(of key: String) -> Cell? {
        guard let d = doorCell(of: key) else { return nil }
        return d.neighbours.first(where: isCorridor)
    }

    /// Walking between a room and the hallway is only allowed through the doorway.
    /// Which yard block, or the corridor, a cell belongs to; nil for rooms and the void.
    private func yardArea(_ c: Cell) -> String? {
        if let areas = yardAreaCache { return areas[c] }
        var areas: [Cell: String] = [:]
        for (name, cells) in [("corridor", corridorCells + coreCells), ("pad", padCells), ("deck", deckCells),
                              ("storage", storageCells), ("decon", deconCells), ("hangar", hangarCells), ("airlock", airlockCells)] {
            for cell in cells { areas[cell] = name }   // later names win, so the blocks outrank the corridor
        }
        yardAreaCache = areas
        return areas[c]
    }

    /// Doorways through the yard: the corridor into the deck, and the deck into storage and the pad.
    var yardDoorways: [(Cell, Cell)] {
        if let d = doorwaysCache { return d }
        let d = computeYardDoorways()
        doorwaysCache = d
        return d
    }

    private func computeYardDoorways() -> [(Cell, Cell)] {
        guard hasPad, let armEnd = plan.west.last else { return [] }
        let x0 = yardX0
        // The one place the hallway meets the yard: the west arm's last cell onto the deck.
        var out: [(Cell, Cell)] = [(armEnd, Cell(x: x0, y: armEnd.y))]
        // Corridor into the airlock, airlock out onto the bay: the only way to the outside.
        for a in airlockInner { out.append((Cell(x: a.x, y: a.y - 1), a)) }
        for h in airlockHatches { out.append((h.inside, h.bay)) }
        for x in [x0 - 1, x0 - 2] {
            out.append((Cell(x: x, y: 2), Cell(x: x, y: 3)))     // deck to storage
            if padGap == 0 { out.append((Cell(x: x, y: -1), Cell(x: x, y: -2))) }   // deck to pad
        }
        if padGap > 0 { for y in [0, 1] { out.append((Cell(x: x0 - 3, y: y), Cell(x: x0 - 4, y: y))) } }   // deck west onto the causeway
        for x in [x0 - 1, x0 - 2] { out.append((Cell(x: x, y: 6), Cell(x: x, y: 7))) }   // storage back into decon
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
        forgetFloorPlan()
    }

    func removeRoom(key: String) {
        guard let r = rooms.removeValue(forKey: key) else { return }
        for c in r.cells { occupied[c] = nil }
        forgetFloorPlan()
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

    /// Takes a peer's placement as is when the floor is free: against our hallway, or with the shortest
    /// dig through free floor to reach it, up to twelve tiles. False when the floor is taken or too far.
    private func adopt(_ cells: [Cell]) -> Bool {
        let mine = dugSet
        guard !cells.isEmpty, cells.allSatisfy({ occupied[$0] == nil && (!isReserved($0) || mine.contains($0)) }) else { return false }
        // Their floor over hallway we dug: that hallway is given back, if what is left is still one piece
        // from the plaza and every room keeps its door. The plan's own arms and alleys are never given back.
        let overlap = cells.filter(mine.contains)
        if !overlap.isEmpty {
            let remaining = dug.filter { !overlap.contains($0) }
            var hall = Set(plan.plaza + plan.west + plan.south).union(remaining)
            hall.remove(plan.monolith)
            var seen: Set<Cell> = [coreCenter]; var queue = [coreCenter]; var head = 0
            while head < queue.count { let c = queue[head]; head += 1; for n in c.neighbours where hall.contains(n) && !seen.contains(n) { seen.insert(n); queue.append(n) } }
            guard seen.count == hall.count else { return false }
            guard rooms.values.allSatisfy({ r in r.cells.contains { c in c.neighbours.contains(where: hall.contains) } }) else { return false }
            dug = remaining
        }
        if cells.contains(where: { $0.neighbours.contains(where: isCorridor) }) { return true }
        // A passage from the room's edge to the built hallway, through floor nobody has.
        let room = Set(cells)
        let hall = blocks.hallway
        func diggable(_ c: Cell) -> Bool { !walkable.contains(c) && occupied[c] == nil && !room.contains(c) && (!isReserved(c) || plan.everyHallwayCell.contains(c)) }
        var prev: [Cell: Cell?] = [:]
        var queue: [Cell] = []
        for c in cells.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) { for n in c.neighbours where diggable(n) && prev[n] == nil { prev[n] = .some(nil); queue.append(n) } }
        var head = 0
        while head < queue.count {
            let p = queue[head]; head += 1
            var len = 1; var q = p; while let back = prev[q], let b = back { len += 1; q = b }
            if p.neighbours.contains(where: { hall.contains($0) && $0 != plan.monolith }) {
                var path = [p]; var q = p; while let back = prev[q], let b = back { path.append(b); q = b }
                dug.append(contentsOf: path.reversed())
                return true
            }
            guard len < 12 else { continue }
            for n in p.neighbours where prev[n] == nil && diggable(n) { prev[n] = .some(p); queue.append(n) }
        }
        return false
    }

    /// A peer's placements of rooms we hold elsewhere win the tie: ours go, all of them first, since one
    /// often stands where another of theirs belongs; then theirs are adopted, or a room is placed afresh
    /// when their floor is taken here by something else. Returns true when the floor changed.
    @discardableResult
    func replaceRooms(_ theirs: [(key: String, cells: [Cell])]) -> Bool {
        let disputed = theirs.filter { t in rooms[t.key].map { r in r.cells != t.cells } == true }
        guard !disputed.isEmpty else { return false }
        var kept: [(Room, [Cell])] = []
        for (key, cells) in disputed { if let r = rooms[key] { kept.append((r, cells)); removeRoom(key: key) } }
        for (r, cells) in kept.sorted(by: { $0.0.key < $1.0.key }) {
            ensureRoom(key: r.key, name: r.name, repo: r.repo, color: r.color, lastActive: r.lastActive, preferredCells: cells)
            if let n = rooms[r.key] { n.branch = r.branch; n.repoRoot = r.repoRoot; n.worktree = r.worktree }
        }
        return true
    }

    /// The whole plan, built or not, and the blocks: no room ever stands where hallway will run.
    func isReserved(_ c: Cell) -> Bool { blocks.reserved.contains(c) }

    /// Where a new room goes, and what hallway is dug for it. Every candidate is a place for the room with
    /// the hallway as it is, or with one dig added: the next few cells of a long arm, or an alley off any
    /// hallway cell, one to three tiles into free floor, or on until it meets other hallway and so links
    /// two arms without the plaza. A candidate is judged by the room's walk from its door to the bay and to
    /// the deck, plus the digging, less what a link saves between the two ends it joins. The least wins;
    /// ties go to the fewest steps from the plaza, then to the lowest cell. Deterministic throughout, so
    /// two machines with the same rooms dig the same hallway.
    private func placeShape(_ shape: [Cell], near: [Cell]? = nil) -> [Cell] {
        let variants = rotations(of: shape)
        for _ in 0..<6 {
            if let cells = placeOnce(variants, near: near) { return cells }
            // Boxed in: build both long arms on three cells and look again.
            for arm in [plan.north, plan.east] {
                let built = arm.prefix { blocks.hallway.contains($0) }.count
                dug.append(contentsOf: arm[built..<min(arm.count, built + 3)])
            }
        }
        // Give up gracefully: park the room in a free spot far out along the east arm.
        let far = Cell(x: (plan.east.last?.x ?? 0) + 3, y: 2)
        return variants[0].map { $0 + far }
    }

    private func placeOnce(_ variants: [[Cell]], near: [Cell]?) -> [Cell]? {
        let hall = blocks.hallway
        let hallInOrder = hall.sorted { ($0.y, $0.x) < ($1.y, $1.x) }   // the same order on every machine
        // Steps from the bay door, the deck door and the plaza, through the hallway as built.
        func distances(from starts: [Cell]) -> [Cell: Int] {
            var d: [Cell: Int] = [:]
            var queue = starts.filter { hall.contains($0) }
            for c in queue { d[c] = 0 }
            var head = 0
            while head < queue.count {
                let c = queue[head]; head += 1
                for n in c.neighbours where hall.contains(n) && n != plan.monolith && d[n] == nil { d[n] = d[c]! + 1; queue.append(n) }
            }
            return d
        }
        let toBay = distances(from: [plan.south.last ?? plan.monolith])
        let toDeck = distances(from: [plan.west.last ?? plan.monolith])
        let toPlaza = blocks.hallDistance
        func cost(_ c: Cell) -> Int? {
            guard let b = toBay[c], let k = toDeck[c] else { return nil }
            return b + k
        }
        /// Free floor a dig may take: not built, not a room, not a block. An unbuilt cell of an arm may be
        /// dug early by an alley crossing it; it is hallway either way.
        func diggable(_ c: Cell) -> Bool { !walkable.contains(c) && occupied[c] == nil && (!isReserved(c) || plan.everyHallwayCell.contains(c)) }
        /// Free floor a room may take.
        func roomable(_ c: Cell) -> Bool { !isReserved(c) && occupied[c] == nil }

        // A dig is scored in half steps: a room's walk counts one per step, the digging half a step per
        // cell, and every free tile the dig opens a door onto counts half a step back, since the rooms
        // that come after share it. `lb` is the least any room on it could score.
        struct Dig { var cells: [Cell]; var costs: [Cell: Int]; var saves: Int; var lb: Int }
        func dig(_ cells: [Cell], _ costs: [Cell: Int], saves: Int) -> Dig {
            var frontage = Set<Cell>()
            for c in cells { for n in c.neighbours where roomable(n) && !hall.contains(n) && !cells.contains(n) { frontage.insert(n) } }
            let saves = saves + frontage.count
            return Dig(cells: cells, costs: costs, saves: saves, lb: 2 * (costs.values.min() ?? 0) + cells.count - saves)
        }
        var digs: [Dig] = [Dig(cells: [], costs: [:], saves: 0, lb: 0)]
        // The long arms built on, one to eight cells.
        for arm in [plan.north, plan.east] {
            let built = arm.prefix { hall.contains($0) }.count
            guard built < arm.count else { continue }
            let base = built > 0 ? arm[built - 1] : arm[0].neighbours.first { hall.contains($0) }
            guard let base, let c0 = cost(base) else { continue }
            var cells: [Cell] = []
            var costs: [Cell: Int] = [:]
            // Past six steps an arm costs more to build on than an alley: growth turns inward before it runs out.
            let dear = built >= Station.armEasyReach ? Station.armDearStep : 2
            for i in built..<min(arm.count, built + 8) {
                guard occupied[arm[i]] == nil else { break }
                cells.append(arm[i]); costs[arm[i]] = c0 + dear * (i - built + 1)
                digs.append(dig(cells, costs, saves: 0))
            }
        }
        // The plan's own alleys, off a built arm cell: dug whole, at the arm's price.
        for a in plan.alleys where hall.contains(a.base) && !hall.contains(a.cells[0]) {
            guard let c0 = cost(a.base), a.cells.allSatisfy({ occupied[$0] == nil }) else { continue }
            var costs: [Cell: Int] = [:]
            for (j, c) in a.cells.enumerated() { costs[c] = c0 + 2 * (j + 1) }
            digs.append(dig(a.cells, costs, saves: 0))
        }
        // Alleys off every hallway cell: straight, one to six tiles into free floor, or straight then a
        // turn, on until they meet other hallway and so link two parts of it without the plaza. An alley
        // keeps a tile clear on both sides of every cell but the last, so rooms fit along it.
        let nearSet = near.map(Set.init) ?? []
        let dirs = [Cell(x: 1, y: 0), Cell(x: -1, y: 0), Cell(x: 0, y: 1), Cell(x: 0, y: -1)]
        /// Cells of one straight leg from `from` along `d`, and whether it met other hallway at its end.
        func leg(from: Cell, along d: Cell, upTo n: Int, taken: [Cell]) -> (cells: [Cell], met: Cell?) {
            var out: [Cell] = []
            var p = from + d
            for _ in 0..<n {
                guard diggable(p) else { break }
                let met = p.neighbours.first { $0 != p + (d * -1) && hall.contains($0) && $0 != plan.monolith && !taken.contains($0) && !out.contains($0) }
                out.append(p)
                if met != nil { return (out, met) }
                // Two tiles clear on either side, so the strip between this and the next alley holds a room.
                let sides = [1, 2, -1, -2].map { Cell(x: p.x + $0 * d.y, y: p.y + $0 * d.x) }
                guard !sides.contains(where: { hall.contains($0) || taken.contains($0) }) else { out.removeLast(); break }
                p = p + d
            }
            return (out, nil)
        }
        func linked(_ cells: [Cell], from h: Cell, c0: Int, met: Cell) -> Dig? {
            guard let cm = cost(met) else { return nil }
            var costs: [Cell: Int] = [:]
            for (j, c) in cells.enumerated() { costs[c] = min(c0 + 2 * (j + 1), cm + 2 * (cells.count - j)) }
            // A second way round is worth having in itself: four steps' worth, plus whatever walk it cuts out.
            let there = toPlaza[h] ?? 0, back = toPlaza[met] ?? 0
            return dig(cells, costs, saves: Station.passageBonus + 2 * max(0, there + back - cells.count))
        }
        for h in hallInOrder where h != plan.monolith {
            guard let c0 = cost(h) else { continue }
            // Dead-end alleys, straight, one to six.
            for d in dirs {
                let first = leg(from: h, along: d, upTo: 6, taken: [])
                if let met = first.met {
                    if let l = linked(first.cells, from: h, c0: c0, met: met) { digs.append(l) }
                    continue
                }
                var cells: [Cell] = []
                var costs: [Cell: Int] = [:]
                for (i, c) in first.cells.enumerated() {
                    cells.append(c); costs[c] = c0 + 2 * (i + 1)
                    digs.append(dig(cells, costs, saves: 0))
                }
            }
            // Links: the shortest passage through free floor from here to any hallway cell that is far
            // away by walking, up to ten tiles, a tile clear of all other hallway on the way. What it
            // saves is the walk it cuts out between its two ends.
            let walkFrom = distances(from: [h])
            var prev: [Cell: Cell] = [:]
            var queue: [Cell] = []
            for n in h.neighbours where diggable(n) && !n.neighbours.contains(where: { $0 != h && hall.contains($0) }) { prev[n] = h; queue.append(n) }
            var head = 0
            var found = 0
            while head < queue.count, found < 3 {
                let p = queue[head]; head += 1
                var len = 0; var q = p; while q != h { len += 1; q = prev[q]! }
                if len >= 10 { continue }
                for n in p.neighbours where prev[n] == nil && n != h && diggable(n) {
                    let beside = n.neighbours.filter { hall.contains($0) && $0 != plan.monolith }
                    // Far enough that this is a way of its own, not a bulge in the wall beside it.
                    if let g = beside.first(where: { (walkFrom[$0] ?? 0) >= len + 3 }) {
                        // Meets far hallway: a link from h to g through n.
                        var path = [n]; var q = p; while q != h { path.append(q); q = prev[q]! }
                        path.reverse()
                        if let l = linked(path, from: h, c0: c0, met: g) { digs.append(l); found += 1 }
                        prev[n] = p
                        continue
                    }
                    guard beside.isEmpty else { continue }   // brushing hallway that is not far: not a passage
                    prev[n] = p
                    queue.append(n)
                }
            }
        }
        digs.sort { $0.lb < $1.lb }
        // Every room that has a door on the hallway plus one dig; the best by cost.
        var best: (score: Int, tie: (Int, Int, Int), cells: [Cell], dig: [Cell])?
        for dig in digs {
            if let best, dig.lb >= best.score { break }   // nothing on this dig or after it can do better
            let digSet = Set(dig.cells)
            let frontage: [Cell] = dig.cells.isEmpty ? hallInOrder : dig.cells
            func doorCost(_ cells: [Cell]) -> (Int, Int)? {
                var bestDoor: (Int, Int)?
                for c in cells {
                    for n in c.neighbours {
                        let k: Int? = digSet.contains(n) ? dig.costs[n] : (hall.contains(n) && n != plan.monolith ? cost(n) : nil)
                        guard let k else { continue }
                        let steps = digSet.contains(n) ? (toPlaza[n] ?? 0) : (toPlaza[n] ?? 0)
                        if bestDoor == nil || (k, steps) < bestDoor! { bestDoor = (k, steps) }
                    }
                }
                return bestDoor
            }
            var anchorsSeen = Set<[Cell]>()
            for f in frontage {
                for v in variants {
                    // Every placement of this variant that touches `f`: slide the shape so each of its cells sits beside f.
                    for cell in v {
                        for side in f.neighbours {
                            let anchor = Cell(x: side.x - cell.x, y: side.y - cell.y)
                            let cells = v.map { $0 + anchor }
                            guard !anchorsSeen.contains(cells) else { continue }
                            anchorsSeen.insert(cells)
                            guard cells.allSatisfy({ roomable($0) && !digSet.contains($0) && !nearSet.contains($0) }) else { continue }
                            guard !dig.cells.isEmpty || cells.contains(where: { $0.neighbours.contains(where: isCorridor) }) else { continue }
                            if !nearSet.isEmpty { guard cells.contains(where: { $0.neighbours.contains(where: nearSet.contains) }) else { continue } }
                            guard flatTowards(cells, hallway: hall.union(digSet)) else { continue }
                            guard let (door, steps) = doorCost(cells) else { continue }
                            let score = 2 * door + dig.cells.count - dig.saves
                            let tie = (steps, anchor.x, anchor.y)
                            if best == nil || (score, tie.0, tie.1, tie.2) < (best!.score, best!.tie.0, best!.tie.1, best!.tie.2) {
                                best = (score, tie, cells, dig.cells)
                            }
                        }
                    }
                }
            }
        }
        guard let best else { return nil }
        if ProcessInfo.processInfo.environment["RK_DEBUG_PLACE"] != nil {
            let links = digs.filter { $0.cells.count >= 4 && $0.cells.last.map { l in l.neighbours.contains { hall.contains($0) } } == true }
            let lbs = links.prefix(4).map { "len \($0.cells.count) lb \($0.lb) saves \($0.saves) from \($0.cells.first!.x),\($0.cells.first!.y)" }.joined(separator: " | ")
            FileHandle.standardError.write("place: \(digs.count) digs, \(links.count) links; best score \(best.score) dig \(best.dig.count) cells; links: \(lbs)\n".data(using: .utf8)!)
        }
        if !best.dig.isEmpty { dug.append(contentsOf: best.dig) }
        return best.cells
    }

    /// A room shows a straight wall to the hallway: a T with its notch against the corridor
    /// would leave a dark closet between the room, the hallway and its neighbours.
    private func flatTowardsCorridor(_ cells: [Cell]) -> Bool { flatTowards(cells, hallway: blocks.hallway) }

    private func flatTowards(_ cells: [Cell], hallway: Set<Cell>) -> Bool {
        let set = Set(cells)
        let minX = cells.map(\.x).min()!, maxX = cells.map(\.x).max()!
        let minY = cells.map(\.y).min()!, maxY = cells.map(\.y).max()!
        for (dx, dy) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
            guard cells.contains(where: { let n = Cell(x: $0.x + dx, y: $0.y + dy); return hallway.contains(n) && n != plan.monolith }) else { continue }
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
        var hallway: [Cell]?
        var rooms: [String: SavedRoom]
        var stored: Int?
        var ledger: Ledger?
    }
    struct SavedRoom: Codable { var name: String; var repo: String?; var color: RGB; var cells: [Cell]; var lastActive: Date; var worktree: String?; var branch: String?; var repoRoot: String? }

    var saved: Saved {
        Saved(spine: spineHalfLength, hallway: dug, rooms: rooms.mapValues {
            SavedRoom(name: $0.name, repo: $0.repo, color: $0.color, cells: $0.cells, lastActive: $0.lastActive, worktree: $0.worktree, branch: $0.branch, repoRoot: $0.repoRoot)
        }, stored: storedBoxes, ledger: ledger)
    }

    func restore(_ s: Saved) {
        dug = (s.hallway ?? []).filter { !plan.plaza.contains($0) }
        ledger = s.ledger ?? Ledger()
        ledger.forgetTransit()   // nobody was carrying anything when this launched
        for (key, r) in s.rooms where key != "kind:hangar" && key != "kind:bots" && key != "kind:mail" && !key.hasPrefix("crew:") {
            guard r.cells.allSatisfy({ !isReserved($0) && occupied[$0] == nil }) else { continue }
            let room = Room(key: key, name: r.name, repo: r.repo, color: r.color, cells: r.cells, lastActive: r.lastActive)
            room.worktree = r.worktree; room.branch = r.branch; room.repoRoot = r.repoRoot
            rooms[key] = room
            for c in r.cells { occupied[c] = key }
        }
        forgetFloorPlan()
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
        let dir = AppSupport.root
            .appendingPathComponent("Rumkapsel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fleet-v22.json")
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
        s.ensureFixedRoom(.gym)
        stations[name] = s
        return s
    }

    var ordered: [Station] { Fleet.order.compactMap { stations[$0] } }

    /// How far apart stations are laid when each is a world of its own: far enough that one never shows beside another.
    static let worldGap = 400.0

    /// Work sits on the top row; private sits below work, keeping the whole fleet squarish rather than a long strip.
    /// Under a theme of separate worlds each station stands alone instead, a world's gap from the next.
    func arrange() {
        if Theme.forPlan.separateWorlds {
            for (i, s) in ordered.enumerated() {
                let b = s.bounds
                s.offset = SIMD2(Double(i) * Fleet.worldGap - Double(b.min.x), -Double(b.min.y))
            }
            return
        }
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
        let showPrivate = ConfigStore.shared.current.showPrivate
        for (name, s) in saved.stations where name != "crew" && (name != "private" || showPrivate) {
            let station = Station(name: name)
            station.restore(s)
            station.ensureFixedRoom(.quarters)
            station.ensureFixedRoom(.lounge)
            station.ensureFixedRoom(.bath)
            station.ensureFixedRoom(.gym)
            station.clusterQuarters()
            station.removeRoom(key: "kind:airlock")   // from before the airlock had its place in the corridor's line
            stations[name] = station
        }
    }
}
