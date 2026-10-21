import Foundation
import simd

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

    var oklab: SIMD3<Double> {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(self.r), g = lin(self.g), b = lin(self.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    func distance(to other: RGB) -> Double { simd_distance(oklab, other.oklab) }

    func shaded(_ f: Double) -> RGB {
        let hi = max(r, g, b), lo = min(r, g, b)
        let want = min(1, max(0, hi * f))
        guard hi > 0 else { return RGB(r: want, g: want, b: want) }
        let over = max(0, hi * f - 1)
        let sat = max(0, (hi - lo) / hi - over * 1.6)
        let k = want * (1 - sat) 
        return RGB(r: k + (r - lo) / max(hi - lo, 1e-9) * (want - k),
                   g: k + (g - lo) / max(hi - lo, 1e-9) * (want - k),
                   b: k + (b - lo) / max(hi - lo, 1e-9) * (want - k))
    }
}

enum Colors {
    static let idle = RGB(r: 0.40, g: 0.405, b: 0.425)
    static let idleDim = RGB(r: 0.33, g: 0.335, b: 0.355)
    static let idleLight = RGB(r: 0.48, g: 0.485, b: 0.505)
    static let furniture = RGB(r: 0.46, g: 0.465, b: 0.485)
    static let furnitureDim = RGB(r: 0.36, g: 0.365, b: 0.385)
    static let furnitureLight = RGB(r: 0.55, g: 0.555, b: 0.575)
    static let hangar = RGB(r: 0.27, g: 0.42, b: 0.55)
    static let quarters = RGB(r: 0.37, g: 0.375, b: 0.395)
    static let bed = RGB(r: 0.52, g: 0.525, b: 0.545)
    static var repos: [RGB] { Theme.forPlan.repoColors }

    static let heraldry: [RGB] = [
        RGB(r: 0.663, g: 0.216, b: 0.212),
        RGB(r: 0.271, g: 0.373, b: 0.600),
        RGB(r: 0.824, g: 0.643, b: 0.243),
        RGB(r: 0.290, g: 0.451, b: 0.298),
        RGB(r: 0.482, g: 0.267, b: 0.435),
        RGB(r: 0.741, g: 0.451, b: 0.216),
        RGB(r: 0.361, g: 0.396, b: 0.435),
        RGB(r: 0.604, g: 0.318, b: 0.298),
        RGB(r: 0.357, g: 0.545, b: 0.553),
        RGB(r: 0.549, g: 0.502, b: 0.294),
    ]

    static let classicRepos: [RGB] = [
        RGB(r: 0.966, g: 0.526, b: 0.458),
        RGB(r: 0.745, g: 0.290, b: 0.388),
        RGB(r: 0.888, g: 0.601, b: 0.214),
        RGB(r: 0.730, g: 0.339, b: 0.007),
        RGB(r: 0.692, g: 0.698, b: 0.223),
        RGB(r: 0.571, g: 0.452, b: 0.022),
        RGB(r: 0.383, g: 0.765, b: 0.480),
        RGB(r: 0.348, g: 0.532, b: 0.039),
        RGB(r: 0.088, g: 0.766, b: 0.738),
        RGB(r: 0.079, g: 0.550, b: 0.401),
        RGB(r: 0.145, g: 0.729, b: 0.947),
        RGB(r: 0.015, g: 0.524, b: 0.612),
        RGB(r: 0.545, g: 0.650, b: 0.992),
        RGB(r: 0.103, g: 0.479, b: 0.797),
        RGB(r: 0.776, g: 0.566, b: 0.927),
        RGB(r: 0.471, g: 0.392, b: 0.786),
        RGB(r: 0.924, g: 0.516, b: 0.718),
        RGB(r: 0.654, g: 0.320, b: 0.630),
    ]
}

enum Place: Hashable {
    case core
    case room(String)

    static let quarters = Place.room("kind:quarters")
    static let lounge = Place.room("kind:lounge")
    static let bath = Place.room("kind:bath")
    static let gym = Place.room("kind:gym")
    static let galley = Place.room("kind:galley")
    static let mission = Place.room("kind:mission")
    static let hangar = Place.room("kind:hangar")
    static let pad = Place.room("kind:pad")

    static func forActivity(_ a: Activity, home: String, isSubagent: Bool, night: Bool = true) -> Place {
        if a == .researching { return .core }
        if isSubagent { return .room(home) }
        if a == .sleeping { return night ? .quarters : .lounge }
        if a == .qa { return .room("kind:deck") }
        return .room(home)
    }
}

struct Home {
    let key: String
    let name: String
    let repo: String
    let issue: Int?

    static func from(repo: String, branch: String?, cwd: String) -> Home { Work(repo: repo, branch: branch).home }
}

final class Room {
    let key: String
    var name: String
    let repo: String?
    var color: RGB
    var cells: [Cell]
    var lastActive: Date
    var openedAt: Date
    var branch: String?
    var repoRoot: String?
    var worktree: String?

    init(key: String, name: String, repo: String?, color: RGB, cells: [Cell], lastActive: Date, openedAt: Date? = nil) {
        self.key = key; self.name = name; self.repo = repo; self.color = color; self.cells = cells; self.lastActive = lastActive
        self.openedAt = openedAt ?? lastActive
    }
}

final class Station {
    let name: String
    var hasHangar = true { didSet { forgetFloorPlan() } }
    var hasPad = true { didSet { forgetFloorPlan() } }
    private(set) var rooms: [String: Room] = [:]
    private(set) var lingering: [String: Room] = [:]
    private var lingeringAt: [Cell: String] = [:]
    private(set) var dug: [Cell] = [] { didSet { forgetFloorPlan() } }
    private var dugSet: Set<Cell> { Set(dug) }
    var spineHalfLength: Int { usedSlots.count }
    private var usedSlots: Set<Int> = []
    private var occupied: [Cell: String] = [:]
    private var walkableCache: Set<Cell>?
    private var yardAreaCache: [Cell: String]?
    private var doorwaysCache: [(Cell, Cell)]?
    private var doorCache: [String: Cell] = [:]
    private var couchCache: [SIMD2<Double>]?
    private var bedCache: [(pos: SIMD2<Double>, cell: Cell, level: Int)]?
    private func forgetFloorPlan() { blocksCache = nil; walkableCache = nil; yardAreaCache = nil; doorwaysCache = nil; doorCache = [:]; couchCache = nil; bedCache = nil }
    var offset = SIMD2<Double>(0, 0)

    let plan = Plan()
    private var floorCache: Floorplan?
    var floor: Floorplan {
        if let f = floorCache { return f }
        let f = Floorplan.forStation(name)
        floorCache = f
        return f
    }

    private struct Blocks {
        var core: [Cell], hangar: [Cell], bayMargin: [Cell], hall: Hall, corridor: [Cell]
        var hallway: Set<Cell>
        var reserved: Set<Cell>
        var hallDistance: [Cell: Int]
    }
    private var blocksCache: Blocks?
    private var blocks: Blocks {
        if let b = blocksCache { return b }
        let core = plan.plaza, hangar = makeHangarCells()
        let bayMargin = hangar.map(\.y).min().map { top in hangar.filter { $0.y == top }.map { Cell(x: $0.x, y: top - 1) }.filter { !plan.south.contains($0) } } ?? []
        let hall = hasPad ? Hall(entrance: plan.west.last ?? Cell(x: -2, y: 0), padGap: Theme.forPlan.padGap) : .none
        var reserved = Set(core)
        for cells in [hangar, bayMargin, hall.cells, hall.padCells, hall.deconCells] { reserved.formUnion(cells) }
        reserved.formUnion(floor.allHall)
        reserved.formUnion(dug)
        let built = Set(plan.west + plan.south).union(floor.base).union(dug)
        var hallway = Set(core)
        hallway.formUnion(built)
        var dist: [Cell: Int] = [:]
        var queue = core.filter { $0 != plan.monolith }
        for c in queue { dist[c] = 0 }
        var head = 0
        while head < queue.count {
            let c = queue[head]; head += 1
            for n in c.neighbours where hallway.contains(n) && n != plan.monolith && dist[n] == nil { dist[n] = dist[c]! + 1; queue.append(n) }
        }
        let b = Blocks(core: core, hangar: hangar, bayMargin: bayMargin, hall: hall,
                       corridor: built.sorted { ($0.y, $0.x) < ($1.y, $1.x) }, hallway: hallway, reserved: reserved, hallDistance: dist)
        blocksCache = b
        return b
    }

    var coreCells: [Cell] { blocks.core }
    var monolithCell: Cell { plan.monolith }
    var coreCenter: Cell { Cell(x: plan.monolith.x, y: plan.monolith.y + 1) }
    static let hullDepth = 5.0
    var bayMargin: [Cell] { blocks.bayMargin }
    var bayDoor: (inside: Cell, bay: Cell)? {
        guard hasHangar, let end = plan.south.last else { return nil }
        return (end, Cell(x: end.x, y: end.y + 1))
    }
    var hangarCells: [Cell] { blocks.hangar }
    private func makeHangarCells() -> [Cell] {
        guard hasHangar, let end = plan.south.last else { return [] }
        let y = end.y + 1
        return (-3...3).flatMap { dx in (0..<4).map { d in Cell(x: end.x + dx, y: y + d) } }
    }
    var bayMouth: BayMouth {
        BayMouth(z: Double(hangarCells.map(\.y).max() ?? (plan.south.last?.y ?? 0)) + 0.5, height: Station.mouthHeight)
    }
    static let fieldTop = 1.6, mouthHeight = 0.85
    var hangarCenter: SIMD2<Double> {
        guard let end = plan.south.last else { return .zero }
        return SIMD2(Double(end.x), Double(end.y) + 2.5)
    }
    static let hive = 1.3
    static let hiveRow = 1.3 * 0.866
    static let hexRadius = 0.70

    static func honeycomb(front: [Double], back: [Double], toward: Double) -> [SIMD2<Double>] {
        front.map { SIMD2($0 * hive, toward * hiveRow / 2) } + back.map { SIMD2($0 * hive, -toward * hiveRow / 2) }
    }
    static let restOnSkids = 0.24, restOverCrate = 0.55
    static let bayKeepOff = 0.62

    static let baySlotOffsets = Station.honeycomb(front: [0, 1, -1, 2, -2], back: [0.5, -0.5, 1.5, -1.5], toward: -1)
    static let bayRadius = Station.hexRadius
    var hangarSlots: [SIMD2<Double>] {
        guard hasHangar, let x0 = hangarCells.map(\.x).min(), let x1 = hangarCells.map(\.x).max(),
              let y0 = hangarCells.map(\.y).min(), let y1 = hangarCells.map(\.y).max() else { return [] }
        let c = hangarCenter, r = Station.bayRadius
        return Station.baySlotOffsets.map { c + $0 }.filter { p in
            p.x - r >= Double(x0) - 0.5 && p.x + r <= Double(x1) + 0.5 && p.y - r >= Double(y0) - 0.5 && p.y + r <= Double(y1) + 0.5
        }
    }
    func bayStand(slot: Int) -> Cell {
        let slots = hangarSlots
        guard slot >= 0, slot < slots.count else { return coreCenter }
        let at = slots[slot]
        func offBy(_ c: Cell, _ p: SIMD2<Double>) -> Double { pow(Double(c.x) - p.x, 2) + pow(Double(c.y) - p.y, 2) }
        let lanes = hangarCells.filter { c in slots.allSatisfy { offBy(c, $0) > pow(Station.bayKeepOff + 0.15, 2) } }
        return (lanes.isEmpty ? hangarCells : lanes).min { offBy($0, at) < offBy($1, at) } ?? coreCenter
    }
    var hall: Hall { blocks.hall }

    var facts = Facts()
    var migrated = false
    var stored: [String: Int] { counts([.waiting]) }
    var storedBoxes: Int { stored.values.reduce(0, +) }
    var staged: [String: Int] { counts([.testing, .cleared]) }
    private func counts(_ zones: Set<Zone>) -> [String: Int] {
        var out: [String: Int] = [:]
        for c in facts.crates.values where c.zone.map(zones.contains) == true { out[c.id.repo, default: 0] += 1 }
        return out
    }
    var monolithPosition: SIMD2<Double> { SIMD2(Double(plan.monolith.x), Double(plan.monolith.y)) }
    var beds: [(pos: SIMD2<Double>, cell: Cell, level: Int)] {
        if let b = bedCache { return b }
        guard let q = rooms["kind:quarters"] else { return [] }
        let door = doorCell(of: "kind:quarters")
        let b = q.cells.filter { $0 != door }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.prefix(8).map { (SIMD2(Double($0.x), Double($0.y)), $0, 0) }
        bedCache = b
        return b
    }
    var couches: [SIMD2<Double>] {
        if let c = couchCache { return c }
        guard let l = rooms["kind:lounge"] else { return [] }
        let xs = l.cells.map(\.x), ys = l.cells.map(\.y)
        let minX = Double(xs.min()!), maxX = Double(xs.max()!), minY = Double(ys.min()!), maxY = Double(ys.max()!)
        let door = doorCell(of: "kind:lounge")
        let spots = [SIMD2(minX - 0.22, minY), SIMD2(minX - 0.22, maxY), SIMD2(maxX + 0.22, minY), SIMD2(maxX + 0.22, maxY), SIMD2(minX, maxY + 0.22), SIMD2(maxX, maxY + 0.22)]
        let galley = self.galley?.opening
        let c = spots.filter { s in door.map { hypot(s.x - Double($0.x), s.y - Double($0.y)) > 0.6 } ?? true }
            .filter { s in galley.map { hypot(s.x - $0.x, s.y - $0.y) > 0.6 } ?? true }
        couchCache = c
        return c
    }

    static func rect(_ w: Int, _ h: Int) -> [Cell] {
        (0..<w).flatMap { x in (0..<h).map { y in Cell(x: x, y: y) } }
    }

    static func largestRect(in cells: Set<Cell>) -> (lo: Cell, hi: Cell)? {
        guard let x0 = cells.map(\.x).min(), let x1 = cells.map(\.x).max(),
              let y0 = cells.map(\.y).min(), let y1 = cells.map(\.y).max() else { return nil }
        var up = [Int](repeating: 0, count: x1 - x0 + 1)
        var best: (area: Int, lo: Cell, hi: Cell)?
        for y in y0...y1 {
            for x in x0...x1 { up[x - x0] = cells.contains(Cell(x: x, y: y)) ? up[x - x0] + 1 : 0 }
            for a in 0..<up.count {
                var tall = Int.max
                for b in a..<up.count {
                    tall = min(tall, up[b])
                    if tall == 0 { break }
                    let area = (b - a + 1) * tall
                    if area >= (best?.area ?? 1) { best = (area, Cell(x: x0 + a, y: y - tall + 1), Cell(x: x0 + b, y: y)) }
                }
            }
        }
        return best.map { ($0.lo, $0.hi) }
    }

    init(name: String) {
        self.name = name
    }

    var corridorCells: [Cell] { blocks.corridor }
    func hallDistance(of c: Cell) -> Int? { blocks.hallDistance[c] }
    func digOrder(of c: Cell) -> Int { (dug.firstIndex(of: c) ?? -1) + 1 }
    var dugCount: Int { dug.count }
    var dugCells: [Cell] { dug }

    func room(at cell: Cell) -> Room? {
        if let key = occupied[cell] { return rooms[key] }
        return lingeringAt[cell].flatMap { lingering[$0] }
    }

    func linger(_ shown: [String: Room]) {
        guard Set(shown.keys) != Set(lingering.keys) || shown.contains(where: { lingering[$0.key]?.cells != $0.value.cells }) else { return }
        lingering = shown
        lingeringAt = [:]
        for (key, r) in shown { for c in r.cells { lingeringAt[c] = key } }
        forgetFloorPlan()
    }

    func isCorridor(_ c: Cell) -> Bool { c != plan.monolith && blocks.hallway.contains(c) }

    var walkable: Set<Cell> {
        if let w = walkableCache { return w }
        var w = Set(coreCells)
        w.remove(plan.monolith)
        w.formUnion(hangarCells)
        w.formUnion(hall.cells)
        w.formUnion(hall.deconCells)
        w.formUnion(corridorCells)
        for r in rooms.values { w.formUnion(r.cells) }
        for r in lingering.values { w.formUnion(r.cells) }
        walkableCache = w
        return w
    }

    var allCells: [Cell] { Array(walkable) }

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
        case .room("kind:pad"): return hall.padCells
        case .room("kind:storage"): return hall.walkwayCells
        case .room("kind:deck"): return hall.aisleCells.isEmpty ? hall.padCells : hall.aisleCells
        case .room(let key): return (rooms[key] ?? lingering[key])?.cells ?? []
        }
    }

    func ensureRoom(key: String, name: String, repo: String?, color: RGB, lastActive: Date, openedAt: Date? = nil, shape: [Cell]? = nil, preferredCells: [Cell]? = nil, near: [Cell]? = nil) -> Bool {
        if let r = rooms[key] {
            r.lastActive = max(r.lastActive, lastActive)
            return false
        }
        let cells = preferredCells.flatMap { adopt($0, dig: Station.opensInto[key] == nil) ? $0 : nil } ?? takeSlot(repo: repo)
        rooms[key] = Room(key: key, name: name, repo: repo, color: color, cells: cells, lastActive: lastActive, openedAt: openedAt)
        for c in cells { occupied[c] = key }
        forgetFloorPlan()
        return true
    }

    @discardableResult
    func ensureFixedRoom(_ place: Place) -> Bool {
        guard case .room(let key) = place else { return false }
        let named: [String: (plan: String, name: String, color: RGB, shape: [Cell])] = [
            "kind:lounge":   ("lounge",   "lounge",   Colors.idle,        Station.rect(3, 3)),
            "kind:quarters": ("quarters", "sleeping", Colors.idleDim,     Station.rect(2, 4)),
            "kind:bath":     ("bath",     "bath",     Colors.idleLight,   Station.rect(2, 2)),
            "kind:gym":      ("gym",      "gym",      Colors.idle,        Station.rect(3, 2)),
            "kind:galley":   ("galley",   "galley",   Colors.idleLight,   Station.rect(1, 1)),
            "kind:mission":  ("mission",  "mission control", Colors.idleDim, Station.rect(5, 3)),
        ]
        guard let it = named[key] else { return false }
        if key == "kind:mission", !hasPad || floor.quarters["mission"] == nil { return false }
        if let into = Station.opensInto[key] {
            guard let cells = floor.quarters[it.plan], let host = rooms[into],
                  cells.allSatisfy({ occupied[$0] == nil && !isReserved($0) && !isCorridor($0) }),
                  cells.contains(where: { $0.neighbours.contains(where: host.cells.contains) }) else { return false }
        }
        return ensureRoom(key: key, name: it.name, repo: nil, color: it.color, lastActive: .distantFuture, openedAt: .distantPast,
                          shape: it.shape, preferredCells: floor.quarters[it.plan])
    }

    func touching(_ a: String, _ b: String) -> Bool {
        guard let ra = rooms[a], let rb = rooms[b] else { return false }
        let set = Set(rb.cells)
        return ra.cells.contains { $0.neighbours.contains(where: set.contains) }
    }

    func clusterQuarters() {
        guard rooms["kind:lounge"] != nil else { return }
        if !touching("kind:quarters", "kind:lounge") || !(touching("kind:bath", "kind:lounge") || touching("kind:bath", "kind:quarters")) {
            removeRoom(key: "kind:quarters"); removeRoom(key: "kind:bath")
            ensureFixedRoom(.quarters); ensureFixedRoom(.bath)
        }
        if rooms["kind:gym"] != nil, !["kind:lounge", "kind:quarters", "kind:bath"].contains(where: { touching("kind:gym", $0) }) {
            removeRoom(key: "kind:gym"); ensureFixedRoom(.gym)
        }
        if rooms["kind:galley"] != nil, !touching("kind:galley", "kind:lounge") {
            removeRoom(key: "kind:galley"); ensureFixedRoom(.galley)
        }
    }

    static let opensInto = ["kind:galley": "kind:lounge"]

    var thresholds: Set<Cell> { Set(Station.opensInto.keys.compactMap { doorOutside(of: $0) }) }

    private func entrance(of key: String) -> (Cell) -> Bool {
        guard let into = Station.opensInto[key] else { return isCorridor }
        return { [self] in room(at: $0)?.key == into }
    }

    func doorCell(of key: String) -> Cell? {
        if let d = doorCache[key] { return d }
        guard let r = rooms[key] ?? lingering[key] else { return nil }
        let candidates = r.cells.filter { $0.neighbours.contains(where: entrance(of: key)) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let d = candidates.first ?? r.cells.first
        if let d { doorCache[key] = d }
        return d
    }

    func doorOutside(of key: String) -> Cell? {
        guard let d = doorCell(of: key) else { return nil }
        return d.neighbours.first(where: entrance(of: key))
    }

    private func yardArea(_ c: Cell) -> String? {
        if let areas = yardAreaCache { return areas[c] }
        var areas: [Cell: String] = [:]
        for (name, cells) in [("corridor", corridorCells + coreCells), ("pad", hall.padCells), ("hall", hall.cells),
                              ("decon", hall.deconCells), ("hangar", hangarCells)] {
            for cell in cells { areas[cell] = name }
        }
        yardAreaCache = areas
        return areas[c]
    }

    var yardDoorways: [(Cell, Cell)] {
        if let d = doorwaysCache { return d }
        let d = computeYardDoorways()
        doorwaysCache = d
        return d
    }

    private func computeYardDoorways() -> [(Cell, Cell)] {
        var out: [(Cell, Cell)] = []
        if let door = bayDoor { out.append(door) }
        guard hasPad, let armEnd = plan.west.last else { return out }
        out.append((armEnd, Cell(x: armEnd.x - 1, y: armEnd.y)))
        if let decon = hall.deconDoorway { out.append(decon) }
        return out
    }

    func canStep(from a: Cell, to b: Cell) -> Bool {
        if let ya = yardArea(a), let yb = yardArea(b), ya != yb {
            return yardDoorways.contains { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }
        }
        let ra = room(at: a)?.key, rb = room(at: b)?.key
        if ra == rb { return true }
        if let ra, doorCell(of: ra) == a, doorOutside(of: ra) == b { return true }
        if let rb, doorCell(of: rb) == b, doorOutside(of: rb) == a { return true }
        return false
    }

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
        if let i = r.cells.first.flatMap({ floor.slotOf[$0] }), floor.slots[i].cells == r.cells { usedSlots.remove(i) }
        forgetFloorPlan()
    }

    private func adopt(_ cells: [Cell], dig: Bool = true) -> Bool {
        guard !cells.isEmpty else { return false }
        if let i = cells.first.flatMap({ floor.slotOf[$0] }), floor.slots[i].cells == cells.sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }),
           !usedSlots.contains(i), cells.allSatisfy({ occupied[$0] == nil }) {
            usedSlots.insert(i); lightWay(to: floor.slots[i]); return true
        }
        let mine = dugSet
        guard cells.allSatisfy({ occupied[$0] == nil && (!isReserved($0) || mine.contains($0)) }) else { return false }
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
        if !dig || cells.contains(where: { $0.neighbours.contains(where: isCorridor) }) { return true }
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

    @discardableResult
    func replaceRooms(_ theirs: [(key: String, cells: [Cell])]) -> [String] {
        let disputed = theirs.filter { t in rooms[t.key].map { r in r.cells != t.cells } == true }
        guard !disputed.isEmpty else { return [] }
        var kept: [(Room, [Cell])] = []
        for (key, cells) in disputed { if let r = rooms[key] { kept.append((r, cells)); removeRoom(key: key) } }
        for (r, cells) in kept.sorted(by: { $0.0.key < $1.0.key }) {
            ensureRoom(key: r.key, name: r.name, repo: r.repo, color: r.color, lastActive: r.lastActive, openedAt: r.openedAt, preferredCells: cells)
            if let n = rooms[r.key] { n.branch = r.branch; n.repoRoot = r.repoRoot; n.worktree = r.worktree }
        }
        return disputed.filter { t in rooms[t.key]?.cells == t.cells }.map(\.key)
    }

    func relayOffices() {
        let offices = rooms.values.filter { !$0.key.hasPrefix("kind:") }.sorted { ($0.openedAt, $0.key) < ($1.openedAt, $1.key) }
        for r in offices { removeRoom(key: r.key) }
        dug = []
        for r in offices {
            ensureRoom(key: r.key, name: r.name, repo: r.repo, color: r.color, lastActive: r.lastActive, openedAt: r.openedAt)
            if let n = rooms[r.key] { n.branch = r.branch; n.repoRoot = r.repoRoot; n.worktree = r.worktree }
        }
    }

    func isReserved(_ c: Cell) -> Bool { blocks.reserved.contains(c) }

    private func takeSlot(repo: String?) -> [Cell] {
        let free = floor.slots.indices.filter { i in !usedSlots.contains(i) && floor.slots[i].cells.allSatisfy { occupied[$0] == nil } }
        let byRepo = OfficePlacement.current == .byRepo ? repo.flatMap { slot(forRepo: $0, among: free) } : nil
        if let i = byRepo ?? free.first {
            usedSlots.insert(i)
            lightWay(to: floor.slots[i])
            return floor.slots[i].cells
        }
        let far = (floor.allHall.map(\.x).max() ?? 0) + 4 + 4 * (rooms.count % 8)
        return (0..<2).flatMap { dx in (0..<2).map { dy in Cell(x: far + dx, y: -20 + dy) } }
    }

    private func slot(forRepo repo: String, among free: [Int]) -> Int? {
        let offices = rooms.values.filter { $0.repo != nil && !$0.key.hasPrefix("kind:") }
        let own = offices.filter { $0.repo == repo }.flatMap(\.cells)
        let others = offices.filter { $0.repo != repo }.flatMap(\.cells)
        func gap(_ i: Int, _ to: [Cell]) -> Int {
            floor.slots[i].cells.flatMap { c in to.map { abs($0.x - c.x) + abs($0.y - c.y) } }.min() ?? .max
        }
        if !own.isEmpty {
            return free.min { (gap($0, own), floor.slots[$0].ring, $0) < (gap($1, own), floor.slots[$1].ring, $1) }
        }
        func cost(_ i: Int) -> Int { floor.slots[i].ring * Station.newRepoRingCost - min(gap(i, others), Station.newRepoClearance) }
        return free.min { (cost($0), $0) < (cost($1), $1) }
    }

    static let newRepoRingCost = 2
    static let newRepoClearance = 6

    private func light(_ cells: [Cell]) {
        let known = dugSet
        let fresh = cells.filter { !known.contains($0) }
        guard !fresh.isEmpty else { return }
        dug.append(contentsOf: fresh)
    }

    private func lightWay(to slot: Floorplan.Slot) {
        let lit = blocks.hallway.subtracting([plan.monolith])
        let run = Set(slot.hall)
        var reached = Set<Cell>(), queue = slot.hall.filter { $0.neighbours.contains(where: lit.contains) }, head = 0
        reached.formUnion(queue)
        while head < queue.count {
            let c = queue[head]; head += 1
            for n in c.neighbours where run.contains(n) && !reached.contains(n) { reached.insert(n); queue.append(n) }
        }
        let floorAfter = lit.union(run)
        if reached.count == run.count, slot.cells.contains(where: { $0.neighbours.contains(where: floorAfter.contains) }) {
            light(slot.hall); return
        }
        let room = Set(slot.cells)
        if slot.cells.contains(where: { $0.neighbours.contains(where: lit.contains) }) { return }
        var prev: [Cell: Cell] = [:], seen = lit
        var walk = lit.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        head = 0
        while head < walk.count {
            let c = walk[head]; head += 1
            if !lit.contains(c), c.neighbours.contains(where: room.contains) {
                var path = [c], q = c
                while let p = prev[q], !lit.contains(p) { path.append(p); q = p }
                light(Array(path.reversed())); return
            }
            for n in c.neighbours where floor.allHall.contains(n) && !seen.contains(n) { seen.insert(n); prev[n] = c; walk.append(n) }
        }
        light(slot.hall)
    }

    func spareHallway() -> [Cell] {
        let mine = dugSet
        guard !mine.isEmpty else { return [] }
        var queue = blocks.hallway.filter { !mine.contains($0) && $0 != plan.monolith }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        var prev: [Cell: Cell] = [:], seen = Set(queue), head = 0
        while head < queue.count {
            let c = queue[head]; head += 1
            for n in c.neighbours where mine.contains(n) && !seen.contains(n) { seen.insert(n); prev[n] = c; queue.append(n) }
        }
        var needed = Set<Cell>()
        for key in Set(rooms.keys).union(lingering.keys).sorted() {
            guard var c = doorOutside(of: key), mine.contains(c) else { continue }
            guard seen.contains(c) else { return [] }
            while mine.contains(c), needed.insert(c).inserted, let p = prev[c] { c = p }
        }
        return dug.filter { !needed.contains($0) }
    }

    func giveBack(_ cells: [Cell]) {
        let gone = Set(cells)
        dug.removeAll { gone.contains($0) }
    }

    // MARK: walking round things

    var obstacles: Set<Cell> = []
    var written: [String: Set<Cell>] = [:]
    static let fine = 3
    static func sub(_ p: SIMD2<Double>) -> Cell { Cell(x: Int((p.x * Double(fine)).rounded()), y: Int((p.y * Double(fine)).rounded())) }
    static func cell(ofSub s: Cell) -> Cell { Cell(x: Int((Double(s.x) / Double(fine)).rounded()), y: Int((Double(s.y) / Double(fine)).rounded())) }
    static func point(ofSub s: Cell) -> SIMD2<Double> { SIMD2(Double(s.x) / Double(fine), Double(s.y) / Double(fine)) }

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
        var target = to
        if obstacles.contains(Cell(x: to.x * Station.fine, y: to.y * Station.fine)) {
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
                if dx != 0 && dy != 0 {
                    let a = Cell(x: c.x + dx, y: c.y), b = Cell(x: c.x, y: c.y + dy)
                    guard open(a), open(b), canStep(from: cc, to: Station.cell(ofSub: a)), canStep(from: cc, to: Station.cell(ofSub: b)) else { continue }
                }
                prev[n] = c
                queue.append(n)
            }
        }
        guard let end = found else {
            if !edges { return nil }
            return coarsePath(from: Station.cell(ofSub: start), to: to).map { SIMD2(Double($0.x), Double($0.y)) }
        }
        var subs: [Cell] = []
        var cur = end
        while cur != start { subs.append(cur); cur = prev[cur]! }
        subs.reverse()
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
        var ledger: LegacyLedger?
        var facts: Facts?
        var placement: String?
        var unreadable: String?

        enum CodingKeys: String, CodingKey { case spine, hallway, rooms, stored, ledger, facts, placement }
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
        }, stored: storedBoxes, ledger: nil, facts: facts.persisted, placement: OfficePlacement.current.rawValue)
    }

    func restore(_ s: Saved, relayout: Bool = false) {
        dug = relayout ? [] : (s.hallway ?? []).filter { !plan.plaza.contains($0) }
        facts = s.facts ?? Facts.migrate(s.ledger ?? LegacyLedger(crates: [:]), yard: yard)
        migrated = s.facts?.scheme != Facts.scheme
        if facts.scheme != Facts.scheme { facts.scheme = Facts.scheme; Layout.relayout(&facts, yard: yard) }
        let kept = s.rooms.filter { key, _ in key != "kind:hangar" && key != "kind:bots" && key != "kind:mail" && !key.hasPrefix("crew:") }
        if relayout {
            let offices = kept.filter { !$0.key.hasPrefix("kind:") }
                .sorted { ($0.value.openedAt ?? $0.value.lastActive, $0.key) < ($1.value.openedAt ?? $1.value.lastActive, $1.key) }
            restoreRooms(kept.filter { $0.key.hasPrefix("kind:") })
            for (key, r) in offices {
                ensureRoom(key: key, name: r.name, repo: r.repo, color: r.color, lastActive: r.lastActive, openedAt: r.openedAt ?? r.lastActive)
                if let room = rooms[key] { room.worktree = r.worktree; room.branch = r.branch; room.repoRoot = r.repoRoot }
            }
        } else {
            restoreRooms(kept)
        }
        forgetFloorPlan()
    }

    private func restoreRooms(_ saved: [String: SavedRoom]) {
        for (key, r) in saved {
            guard r.cells.allSatisfy({ !isReserved($0) && occupied[$0] == nil }) else { continue }
            let room = Room(key: key, name: r.name, repo: r.repo, color: r.color, cells: r.cells, lastActive: r.lastActive, openedAt: r.openedAt ?? r.lastActive)
            room.worktree = r.worktree; room.branch = r.branch; room.repoRoot = r.repoRoot
            rooms[key] = room
            for c in r.cells { occupied[c] = key }
        }
    }
}

extension Station.Saved {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spine = try c.decode(Int.self, forKey: .spine)
        hallway = try c.decodeIfPresent([Cell].self, forKey: .hallway)
        rooms = try c.decode([String: Station.SavedRoom].self, forKey: .rooms)
        stored = try c.decodeIfPresent(Int.self, forKey: .stored)
        ledger = try? c.decodeIfPresent(LegacyLedger.self, forKey: .ledger)
        do { facts = try c.decodeIfPresent(Facts.self, forKey: .facts) } catch { facts = nil; unreadable = "\(error)" }
        placement = try c.decodeIfPresent(String.self, forKey: .placement)
    }
}

final class Fleet {
    private(set) var stations: [String: Station] = [:]
    private(set) var repoColors: [String: Int] = [:]
    var persists = true

    static let order = ["work"]

    static let saveName = "fleet-v25.json"

    private static var saveURL: URL {
        let dir = AppSupport.root
            .appendingPathComponent("Rumkapsel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(saveName)
    }

    static func stationName(for cwd: String, owner: String?, repo: String) -> String {
        ConfigStore.shared.current.station(cwd: cwd, owner: owner, repo: repo)
    }

    func removeAllStations() { stations = [:] }
    func removeStation(named name: String) { stations[name] = nil }

    func recolorRooms() {
        for station in stations.values {
            for room in station.rooms.values {
                guard let repo = room.repo else { continue }
                room.color = color(forRepo: repo)
            }
        }
    }

    func color(forRepo repo: String) -> RGB {
        if let own = ConfigStore.shared.current.repos[repo]?.color { return own }
        guard !repo.isEmpty else { return Colors.idle }
        return Fleet.color(slot: repoColors[repo] ?? handOut(repo))
    }

    private func handOut(_ repo: String) -> Int {
        let cfg = ConfigStore.shared.current
        let onFloor = Set(stations.values.flatMap { $0.rooms.values.compactMap(\.repo) })
        let holders = repoColors.filter { cfg.repos[$0.key]?.color == nil }
        let n = Colors.repos.count
        var free = (0..<n).filter { i in !holders.values.contains(i) }
        if free.isEmpty {
            let idle = holders.filter { !onFloor.contains($0.key) }
            for r in idle.keys { repoColors[r] = nil }
            free = idle.values.filter { $0 < n }.sorted()
        }
        if free.isEmpty { free = Array(0..<(n * 3)) }
        let used = onFloor.filter { $0 != repo }.compactMap { r in cfg.repos[r]?.color ?? repoColors[r].map(Fleet.color(slot:)) }
        func room(_ i: Int) -> Double { used.map { Fleet.color(slot: i).distance(to: $0) }.min() ?? .infinity }
        let pick = free.max { a, b in (room(a), -a) < (room(b), -b) } ?? 0
        repoColors[repo] = pick
        Fleet.publish(repoColors)
        return pick
    }

    func adopt(_ slots: [String: Int]) -> Bool {
        let n = Colors.repos.count * 3
        let wanted = slots.filter { !$0.key.isEmpty && $0.value >= 0 && $0.value < n && repoColors[$0.key] != $0.value }
        guard !wanted.isEmpty else { return false }
        let taken = Set(slots.values)
        for (r, i) in repoColors where slots[r] == nil && taken.contains(i) { repoColors[r] = nil }
        for (r, i) in wanted { repoColors[r] = i }
        Fleet.publish(repoColors)
        recolorRooms()
        return true
    }

    func resetColors() {
        repoColors = [:]
        Fleet.publish(repoColors)
        recolorRooms()
    }

    static let paletteVersion = 2
    private static let handedOutLock = NSLock()
    private static var handedOut: [String: Int] = [:]
    private static func publish(_ slots: [String: Int]) { handedOutLock.lock(); handedOut = slots; handedOutLock.unlock() }
    static func handedOut(repo: String) -> RGB? {
        handedOutLock.lock(); defer { handedOutLock.unlock() }
        return handedOut[repo].map(color(slot:))
    }

    static func color(slot i: Int) -> RGB {
        let base = Colors.repos[i % Colors.repos.count]
        switch i / Colors.repos.count % 3 {
        case 0: return base
        case 1: return base.shaded(0.60)
        default: return base.shaded(1.42)
        }
    }

    func station(_ name: String) -> Station {
        station(name, fixed: [.quarters, .lounge, .bath, .gym, .galley, .mission])
    }

    @discardableResult
    func station(_ name: String, fixed: [Place]) -> Station {
        if let s = stations[name] { return s }
        let s = Station(name: name)
        let inner = fixed.filter { if case .room(let k) = $0 { return Station.opensInto[k] != nil }; return false }
        for place in fixed.filter({ !inner.contains($0) }) + inner { s.ensureFixedRoom(place) }
        stations[name] = s
        return s
    }

    var ordered: [Station] { Fleet.order.compactMap { stations[$0] } }

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

    private struct Saved: Codable { var stations: [String: Station.Saved]; var repoColors: [String: Int]; var palette: Int? }
    static let writing = DispatchQueue(label: "rumkapsel.save", qos: .utility)

    private var loaded = false

    func save() {
        guard persists, loaded else { return }
        let s = Saved(stations: stations.mapValues(\.saved), repoColors: repoColors, palette: Fleet.paletteVersion)
        guard let json = try? JSONEncoder().encode(s) else { return }
        Fleet.writing.async { try? json.write(to: Fleet.saveURL) }
    }

    func load(alone: Bool) {
        loaded = true
        guard persists else { return }
        guard let data = try? Data(contentsOf: Fleet.saveURL) else { return }
        let saved: Saved
        do { saved = try JSONDecoder().decode(Saved.self, from: data) } catch { return keepUnreadable(data, why: "\(error)") }
        for (name, s) in saved.stations.sorted(by: { $0.key < $1.key }) {
            if let why = s.unreadable { keepUnreadable(data, why: "\(name)'s facts: \(why)") }
        }
        repoColors = saved.palette == Fleet.paletteVersion ? saved.repoColors : [:]
        Fleet.publish(repoColors)
        for (name, s) in saved.stations where name != "crew" && name != "private" {
            let station = Station(name: name)
            station.restore(s, relayout: alone || (s.placement ?? OfficePlacement.rings.rawValue) != OfficePlacement.current.rawValue)
            station.ensureFixedRoom(.quarters)
            station.ensureFixedRoom(.lounge)
            station.ensureFixedRoom(.bath)
            station.ensureFixedRoom(.gym)
            station.clusterQuarters()
            station.ensureFixedRoom(.galley)
            station.ensureFixedRoom(.mission)
            station.removeRoom(key: "kind:airlock")
            stations[name] = station
        }
        recolorRooms()
    }

    private func keepUnreadable(_ data: Data, why: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = Fleet.saveURL.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? data.write(to: aside)
        StationLog.write("facts", "the save could not be read (\(why)); kept it as \(aside.lastPathComponent)")
    }
}
