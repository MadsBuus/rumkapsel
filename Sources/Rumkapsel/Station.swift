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

    /// Shading that keeps the colour the colour it was: brightness moves, hue and saturation stay.
    /// Adding or subtracting the same amount from red, green and blue flattens the ratios between them,
    /// and the ratios are what the eye reads as a hue — a darkened orange comes out red.
    func shaded(_ f: Double) -> RGB {
        let hi = max(r, g, b), lo = min(r, g, b)
        let want = min(1, max(0, hi * f))
        guard hi > 0 else { return RGB(r: want, g: want, b: want) }
        // Past full brightness a colour can only lighten by letting go of saturation, as paint does.
        let over = max(0, hi * f - 1)
        let sat = max(0, (hi - lo) / hi - over * 1.6)
        let k = want * (1 - sat) 
        return RGB(r: k + (r - lo) / max(hi - lo, 1e-9) * (want - k),
                   g: k + (g - lo) / max(hi - lo, 1e-9) * (want - k),
                   b: k + (b - lo) / max(hi - lo, 1e-9) * (want - k))
    }
}

enum Colors {
    /// The rooms the crew idle in: grey, in three steps so they are still told apart from each other.
    static let idle = RGB(r: 0.40, g: 0.405, b: 0.425)
    static let idleDim = RGB(r: 0.33, g: 0.335, b: 0.355)
    static let idleLight = RGB(r: 0.48, g: 0.485, b: 0.505)
    /// What stands in the idle rooms: grey too, in three steps so a couch is not its floor. Only the
    /// plants and the books keep a colour of their own in there.
    static let furniture = RGB(r: 0.46, g: 0.465, b: 0.485)
    static let furnitureDim = RGB(r: 0.36, g: 0.365, b: 0.385)
    static let furnitureLight = RGB(r: 0.55, g: 0.555, b: 0.575)
    static let hangar = RGB(r: 0.27, g: 0.42, b: 0.55)
    /// The dorm and what stands in it: grey like the rest of the idle rooms. The mattress sits a step
    /// lighter than the floor it is on, so it still reads as a bed rather than a patch of floor.
    static let quarters = RGB(r: 0.37, g: 0.375, b: 0.395)
    static let bed = RGB(r: 0.52, g: 0.525, b: 0.545)
    /// Colours handed out to repositories, in order of first sighting.
    /// Classic's: the game's own six, sampled off its screens, then four more dropped into the widest
    /// gaps they leave round the colour wheel. Six is what the game needs and ten is what a desk with ten
    /// repositories on it needs; the four added keep the game's saturation and brightness so they sit
    /// beside the six rather than in front of them. A theme may bring its own — see `Theme.repoColors`.
    static var repos: [RGB] { Theme.forPlan.repoColors }

    /// A house's colours: the dyes a banner could actually be made in, so a field of them reads as a row
    /// of shields rather than a chart.
    static let heraldry: [RGB] = [
        RGB(r: 0.663, g: 0.216, b: 0.212),   // gules, madder red
        RGB(r: 0.271, g: 0.373, b: 0.600),   // azure, woad blue
        RGB(r: 0.824, g: 0.643, b: 0.243),   // or, saffron gold
        RGB(r: 0.290, g: 0.451, b: 0.298),   // vert, a deep forest green
        RGB(r: 0.482, g: 0.267, b: 0.435),   // purpure
        RGB(r: 0.741, g: 0.451, b: 0.216),   // tenné, burnt orange
        RGB(r: 0.361, g: 0.396, b: 0.435),   // a slate grey
        RGB(r: 0.604, g: 0.318, b: 0.298),   // brick
        RGB(r: 0.357, g: 0.545, b: 0.553),   // a faded teal
        RGB(r: 0.549, g: 0.502, b: 0.294),   // olive
    ]

    static let classicRepos: [RGB] = [
        RGB(r: 0.808, g: 0.431, b: 0.212),   // #CE6E36  the game's orange
        RGB(r: 0.835, g: 0.647, b: 0.251),   // #D5A540  its yellow
        RGB(r: 0.522, g: 0.655, b: 0.267),   // #85A744  its green
        RGB(r: 0.326, g: 0.680, b: 0.368),   // #53AD5E
        RGB(r: 0.396, g: 0.655, b: 0.627),   // #65A7A0  its teal
        RGB(r: 0.251, g: 0.459, b: 0.706),   // #4075B4  its blue
        RGB(r: 0.426, g: 0.355, b: 0.740),   // #6D5BBD
        RGB(r: 0.641, g: 0.378, b: 0.700),   // #A360B2
        RGB(r: 0.671, g: 0.329, b: 0.522),   // #AB5485  its magenta
        RGB(r: 0.760, g: 0.319, b: 0.363),   // #C2515D
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
    /// The repository's colour as the palette has it now, not as it was when the room was first drawn.
    var color: RGB
    var cells: [Cell]
    var lastActive: Date
    /// When this office first stood, kept across launches: how old the work in it is. A room restored
    /// from a save older than this was written takes the last it was worked in, which is the most that
    /// save can say.
    var openedAt: Date
    var branch: String?
    var repoRoot: String?
    var worktree: String?

    init(key: String, name: String, repo: String?, color: RGB, cells: [Cell], lastActive: Date, openedAt: Date? = nil) {
        self.key = key; self.name = name; self.repo = repo; self.color = color; self.cells = cells; self.lastActive = lastActive
        self.openedAt = openedAt ?? min(lastActive, Date())
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
    /// How many of the plan's office slots are taken: for the tests, the log and the scene, which
    /// redraws the floor when it changes.
    var spineHalfLength: Int { usedSlots.count }
    /// Slots given out. A slot is never given twice, and never given back while its room stands.
    private var usedSlots: Set<Int> = []
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

    /// The fixed skeleton: the plaza and the two arms that reach the yard and the airlock.
    let plan = Plan()
    /// The station's floor: its hallway and its hundred office slots, drawn offline round the skeleton
    /// above and chosen by the station's name, so two machines sharing a station lay out the same floor.
    private var floorCache: Floorplan?
    var floor: Floorplan {
        if let f = floorCache { return f }
        let f = Floorplan.forStation(name)
        floorCache = f
        return f
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
        reserved.formUnion(floor.allHall)
        reserved.formUnion(dug)   // hallway once dug is hallway for good
        // The plan's base is hallway from the first frame: it joins the plaza to the yard, the airlock
        // and the quarters, so the station is whole before a single office arrives.
        let built = Set(plan.west + plan.south).union(floor.base).union(dug)
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
    private var padOrigin: (x0: Int, r: Int) { padGap > 0 ? (yardX0 - Station.yardWide - padGap, 0) : (yardX0, -4) }
    /// How many columns wide a yard block is: six, of which two are the pallet's lane, leaving four for
    /// the crate rows and a full stride past the slab at either end.
    static let yardWide = 6
    private func yardBlock(_ index: Int) -> [Cell] {
        guard hasPad else { return [] }
        let (x0, r) = index == 2 ? padOrigin : (yardX0, yardRow(index))
        var cells = (0..<Station.yardWide).flatMap { d in (-1...2).map { y in Cell(x: x0 - d, y: y + r) } }
        if index == 2, padGap > 0 {
            // The causeway: two lanes from the deck's west side out to the pad, pad floor the whole way.
            for x in (x0 + 1)...(yardX0 - Station.yardWide) { for y in [0, 1] { cells.append(Cell(x: x, y: y)) } }
        }
        return cells
    }
    private func yardCenter(_ index: Int) -> SIMD2<Double> {
        let (x0, r) = index == 2 ? padOrigin : (yardX0, yardRow(index))
        return SIMD2(Double(x0) - Double(Station.yardWide - 1) / 2, 0.5 + Double(r))
    }
    var storageCells: [Cell] { blocks.storage }
    var storageCenter: SIMD2<Double> { yardCenter(0) }
    var deckCells: [Cell] { blocks.deck }
    var padCells: [Cell] { blocks.pad }
    var padCenter: SIMD2<Double> { yardCenter(2) }
    /// The storage row nearest the deck: the row the deck doorway opens onto.
    var storageNearRow: Int { storageCells.map(\.y).min() ?? 0 }
    /// The aisle a pallet floats in. Every other row of a yard holds crates, so the rows themselves
    /// are no place for it: the first aisle behind the near row is the nearest clear floor.
    var storageAisleRow: Int {
        let rows = Set(storageCells.map(\.y)).sorted()
        return rows.count > 1 ? rows[1] : storageNearRow
    }
    /// The pallet's lane: the doorway's two columns on the crate rows either side of its aisle. The rows
    /// leave them empty. In front, because nothing stands in a doorway and a loaded pallet needs the way
    /// out clear; behind, because that is where the pusher puts its hands on it.
    var palletLane: Set<Cell> {
        guard hasPad, storageAisleRow != storageNearRow else { return [] }
        return Set([storageNearRow, storageAisleRow + 1].flatMap { y in
            palletLaneColumns.map { Cell(x: $0, y: y) }
        }.filter { storageCells.contains($0) })
    }
    /// The two columns wide enough for the slab itself, in the middle of the doorway. The doorway is
    /// wider than they are so that a body can walk past a pallet standing in it.
    var palletLaneColumns: [Int] { [yardX0 - Station.yardWide / 2 + 1, yardX0 - Station.yardWide / 2] }
    /// The columns a doorway between two yard blocks spans: the pallet's lane with a column either side.
    private var yardGateColumns: [Int] { (1...4).map { yardX0 - $0 } }
    /// Where a hover pallet stands in storage: the aisle, on the middle columns of the deck doorway.
    var palletCell: Cell { Cell(x: palletLaneColumns[1], y: storageAisleRow) }
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
        return (3..<5).flatMap { d in (0..<Station.yardWide).map { x in Cell(x: x0 - x, y: r + d) } }
    }
    var deconCenter: SIMD2<Double> { SIMD2(Double(yardX0) - Double(Station.yardWide - 1) / 2, Double(yardRow(0)) + 3.5) }
    /// The hatch in decon's back wall, and which way it faces: into the chamber.
    var deconHatch: (pos: SIMD2<Double>, facing: SIMD2<Double>) { (SIMD2(Double(yardX0) - Double(Station.yardWide - 1) / 2, Double(yardRow(0)) + 4.46), SIMD2(0, -1)) }

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

    /// The floor cell nearest a point: where a body left standing off the floor steps back to, and where
    /// a crate put down off it lands. Nil only on a station with no floor at all.
    func nearestFloor(to p: SIMD2<Double>) -> Cell? {
        walkable.min { a, b in
            let da = (Double(a.x) - p.x) * (Double(a.x) - p.x) + (Double(a.y) - p.y) * (Double(a.y) - p.y)
            let db = (Double(b.x) - p.x) * (Double(b.x) - p.x) + (Double(b.y) - p.y) * (Double(b.y) - p.y)
            return da != db ? da < db : (a.x, a.y) < (b.x, b.y)
        }
    }

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



    /// Creates a room if missing. Returns true when the layout changed.
    func ensureRoom(key: String, name: String, repo: String?, color: RGB, lastActive: Date, openedAt: Date? = nil, shape: [Cell]? = nil, preferredCells: [Cell]? = nil, near: [Cell]? = nil) -> Bool {
        if let r = rooms[key] {
            r.lastActive = max(r.lastActive, lastActive)
            return false
        }
        let cells = preferredCells.flatMap { adopt($0) ? $0 : nil } ?? takeSlot()
        rooms[key] = Room(key: key, name: name, repo: repo, color: color, cells: cells, lastActive: lastActive, openedAt: openedAt)
        for c in cells { occupied[c] = key }
        forgetFloorPlan()
        return true
    }

    @discardableResult
    func ensureFixedRoom(_ place: Place) -> Bool {
        guard case .room(let key) = place else { return false }
        // The quarters are the plan's, not the placement's: the plan puts them near the plaza and lights
        // them before any office opens, so the station can be slept in from the first frame. Their shapes
        // are their own — a dorm is two by four, not whatever tetromino a slot happens to be.
        // Grey floors. A colour on this station means a repository, and the rooms the crew idle in are
        // nobody's repository — giving them hues of their own spends the palette on places that do not
        // need telling apart, and reads as two more projects.
        let named: [String: (plan: String, name: String, color: RGB, shape: [Cell])] = [
            "kind:lounge":   ("lounge",   "lounge",   Colors.idle,        Station.rect(3, 3)),
            "kind:quarters": ("quarters", "sleeping", Colors.idleDim,     Station.rect(2, 4)),
            "kind:bath":     ("bath",     "bath",     Colors.idleLight,   Station.rect(2, 2)),
            "kind:gym":      ("gym",      "gym",      Colors.idle,        Station.rect(3, 2)),
        ]
        guard let it = named[key] else { return false }
        return ensureRoom(key: key, name: it.name, repo: nil, color: it.color, lastActive: .distantFuture,
                          shape: it.shape, preferredCells: floor.quarters[it.plan])
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
        for x in yardGateColumns {
            out.append((Cell(x: x, y: 2), Cell(x: x, y: 3)))     // deck to storage
            if padGap == 0 { out.append((Cell(x: x, y: -1), Cell(x: x, y: -2))) }   // deck to pad
            out.append((Cell(x: x, y: 6), Cell(x: x, y: 7)))     // storage back into decon
        }
        // Deck west onto the causeway, on its two middle rows.
        if padGap > 0 { for y in [0, 1] { out.append((Cell(x: x0 - Station.yardWide + 1, y: y), Cell(x: x0 - Station.yardWide, y: y))) } }
        return out
    }

    /// Walking between a room and the hallway is only allowed through the doorway.
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
        let nr = Room(key: new, name: name, repo: r.repo, color: r.color, cells: r.cells, lastActive: r.lastActive, openedAt: r.openedAt)
        nr.branch = r.branch; nr.repoRoot = r.repoRoot; nr.worktree = r.worktree
        rooms[old] = nil
        rooms[new] = nr
        for c in nr.cells { occupied[c] = new }
        forgetFloorPlan()
    }

    func removeRoom(key: String) {
        guard let r = rooms.removeValue(forKey: key) else { return }
        for c in r.cells { occupied[c] = nil }
        // The slot goes back into the pool. Its hallway stays lit: it was lit because somebody walked
        // there, and a station that unbuilt its corridors every time an office closed would flicker.
        if let i = r.cells.first.flatMap({ floor.slotOf[$0] }), floor.slots[i].cells == r.cells { usedSlots.remove(i) }
        forgetFloorPlan()
    }


    /// Takes a peer's placement as is. Two machines with the same station draw the same floor, so what
    /// arrives is almost always one of our own slots, and taking it is marking the slot and lighting the
    /// hallway that reaches it. Anything else is taken only if the floor it wants is free.
    private func adopt(_ cells: [Cell]) -> Bool {
        guard !cells.isEmpty else { return false }
        if let i = cells.first.flatMap({ floor.slotOf[$0] }), floor.slots[i].cells == cells.sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }),
           !usedSlots.contains(i), cells.allSatisfy({ occupied[$0] == nil }) {
            usedSlots.insert(i); light(floor.slots[i].hall); return true
        }
        let mine = dugSet
        guard cells.allSatisfy({ occupied[$0] == nil && (!isReserved($0) || mine.contains($0)) }) else { return false }
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
        func diggable(_ c: Cell) -> Bool { !walkable.contains(c) && occupied[c] == nil && !room.contains(c) && (!isReserved(c) || floor.allHall.contains(c)) }
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
            ensureRoom(key: r.key, name: r.name, repo: r.repo, color: r.color, lastActive: r.lastActive, openedAt: r.openedAt, preferredCells: cells)
            if let n = rooms[r.key] { n.branch = r.branch; n.repoRoot = r.repoRoot; n.worktree = r.worktree }
        }
        return true
    }

    /// The whole plan, built or not, and the blocks: no room ever stands where hallway will run.
    func isReserved(_ c: Cell) -> Bool { blocks.reserved.contains(c) }

    /// Where a new room goes: the next free slot in the station's floor plan, counting outward in rings
    /// from the monolith. The plan was drawn once, offline, and knows both the shape and the run of
    /// hallway that first reaches the slot, so placing a room is a lookup and lighting the run that
    /// comes with it. Nothing is searched for, and two machines with the same station and the same
    /// rooms take the same slots in the same order.
    private func takeSlot() -> [Cell] {
        for (i, slot) in floor.slots.enumerated() where !usedSlots.contains(i) {
            // A slot whose floor is spoken for — a room read back off disk that sat elsewhere — is
            // passed over, but not struck off: the room standing on it will not stand there for ever,
            // and a slot retired for good is one the station never gets back.
            guard slot.cells.allSatisfy({ occupied[$0] == nil }) else { continue }
            usedSlots.insert(i)
            light(slot.hall)
            return slot.cells
        }
        // More offices at once than the plan holds. Park the extra clear of the station rather than on
        // top of it; it takes a slot as soon as one falls empty.
        let far = (floor.allHall.map(\.x).max() ?? 0) + 4 + 4 * (rooms.count % 8)
        return (0..<2).flatMap { dx in (0..<2).map { dy in Cell(x: far + dx, y: -20 + dy) } }
    }

    /// Hallway the station lights because a slot needed it. Kept in the order it was lit, and saved.
    private func light(_ cells: [Cell]) {
        let known = dugSet
        let fresh = cells.filter { !known.contains($0) }
        guard !fresh.isEmpty else { return }
        dug.append(contentsOf: fresh)
    }


    // MARK: walking round things

    /// Props on the floor, as blocked spots on a finer grid: three steps to a cell side, so a minion
    /// (a fifth of a cell wide) can squeeze past a crate sideways. Set by the controller from the scene.
    var obstacles: Set<Cell> = []
    static let fine = 3
    static func sub(_ p: SIMD2<Double>) -> Cell { Cell(x: Int((p.x * Double(fine)).rounded()), y: Int((p.y * Double(fine)).rounded())) }
    static func cell(ofSub s: Cell) -> Cell { Cell(x: Int((Double(s.x) / Double(fine)).rounded()), y: Int((Double(s.y) / Double(fine)).rounded())) }
    static func point(ofSub s: Cell) -> SIMD2<Double> { SIMD2(Double(s.x) / Double(fine), Double(s.y) / Double(fine)) }

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
    struct SavedRoom: Codable {
        var name: String; var repo: String?; var color: RGB; var cells: [Cell]; var lastActive: Date
        var worktree: String?; var branch: String?; var repoRoot: String?
        var openedAt: Date? = nil
    }

    var saved: Saved {
        Saved(spine: spineHalfLength, hallway: dug, rooms: rooms.mapValues {
            SavedRoom(name: $0.name, repo: $0.repo, color: $0.color, cells: $0.cells, lastActive: $0.lastActive, worktree: $0.worktree,
                      branch: $0.branch, repoRoot: $0.repoRoot, openedAt: $0.openedAt)
        }, stored: storedBoxes, ledger: ledger)
    }

    func restore(_ s: Saved) {
        dug = (s.hallway ?? []).filter { !plan.plaza.contains($0) }
        ledger = s.ledger ?? Ledger()
        ledger.forgetTransit()   // nobody was carrying anything when this launched
        for (key, r) in s.rooms where key != "kind:hangar" && key != "kind:bots" && key != "kind:mail" && !key.hasPrefix("crew:") {
            guard r.cells.allSatisfy({ !isReserved($0) && occupied[$0] == nil }) else { continue }
            let room = Room(key: key, name: r.name, repo: r.repo, color: r.color, cells: r.cells, lastActive: r.lastActive, openedAt: r.openedAt ?? r.lastActive)
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

    static let order = ["work"]

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

    /// Gives every room the colour its repository has now. A room is saved with the colour it was drawn
    /// in, and restoring it from that would pin it to whatever the palette held the day it was first
    /// seen — so a change to the palette would never reach a station that already existed.
    func recolorRooms() {
        for station in stations.values {
            for room in station.rooms.values {
                guard let repo = room.repo else { continue }
                room.color = color(forRepo: repo)
            }
        }
    }

    /// A repository's colour comes from its name, not from the order it was first seen, so it is the
    /// same on every launch and on every station: a hash picks the palette slot, and a name whose slot
    /// another name already holds takes the next free one, names in alphabetical order.
    func color(forRepo repo: String) -> RGB {
        if repoColors[repo] == nil { repoColors[repo] = 0; assignColors() }
        let i = repoColors[repo] ?? 0
        let base = Colors.repos[i % Colors.repos.count]
        // More repositories than the palette has colours, so the second and third to land on a hue take
        // it darker and lighter. The game shades one colour rather than reaching for a new one, and a
        // made-up seventh hue reads worse beside six real ones than a shade of one of them does.
        switch i / Colors.repos.count {
        case 0: return base
        case 1: return base.shaded(0.60)     // darker first: a deep teal is further from mid teal than
        default: return base.shaded(1.42)    // a pale one is, and crate faces lighten what they are given

        }
    }

    private func assignColors() {
        let n = Colors.repos.count
        // Three rounds of the palette: a hue on its own first, then the lighter shade of one, then the
        // darker. A name keeps looking for the emptiest round rather than piling onto the first hue it
        // hashes to, so eight repositories are eight colours and not six with two pairs of twins.
        var taken: [Int: String] = [:]
        for name in repoColors.keys.sorted() {
            var h: UInt64 = 14695981039346656037
            for b in name.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
            let want = Int(h % UInt64(n))
            var slot: Int?
            for round in 0..<3 {
                for step in 0..<n {
                    let i = round * n + (want + step) % n
                    if taken[i] == nil { slot = i; break }
                }
                if slot != nil { break }
            }
            let i = slot ?? want
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

    /// Each station laid out along one row, a few tiles apart. There is one, so it sits at the origin.
    func arrange() {
        var x = 0.0
        for s in ordered {
            let b = s.bounds
            if x > 0 { x += 3 }
            s.offset = SIMD2(x - Double(b.min.x), 0)
            x += Double(b.max.x - b.min.x + 1)
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
    /// Where saving to disk happens, so that it never happens during a frame.
    static let writing = DispatchQueue(label: "rumkapsel.save", qos: .utility)

    /// Whether the saved layout has been read. A save before that has nothing to say and would write an
    /// empty fleet over the layout it is about to load: every office gone, and teammates' offices shuttled back in.
    private var loaded = false

    func save() {
        guard persists, loaded else { return }
        let s = Saved(stations: stations.mapValues(\.saved), repoColors: repoColors)
        // Written away from the frame: a redraw can happen while the station is being assembled.
        // Encoding reads the model, so it stays here; the disk does not.
        guard let json = try? JSONEncoder().encode(s) else { return }
        Fleet.writing.async { try? json.write(to: Fleet.saveURL) }
    }

    func load() {
        loaded = true
        guard persists else { return }
        guard let data = try? Data(contentsOf: Fleet.saveURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        repoColors = saved.repoColors
        assignColors()   // by name, whatever order an older save gave them
        // A private station saved before there was only one is left behind; its sessions come back on the
        // station with their next scan.
        for (name, s) in saved.stations where name != "crew" && name != "private" {
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
        recolorRooms()
    }
}
