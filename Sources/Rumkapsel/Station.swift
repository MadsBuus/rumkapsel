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
        RGB(r: 0.35, g: 0.78, b: 0.85), RGB(r: 0.94, g: 0.49, b: 0.13), RGB(r: 0.80, g: 0.78, b: 0.25),
        RGB(r: 0.45, g: 0.60, b: 0.95), RGB(r: 0.75, g: 0.55, b: 0.35),
    ]
}

/// Where a session's activity takes place inside its station.
enum Place: Hashable {
    case core
    case room(String)

    static let quarters = Place.room("kind:quarters")
    static let hangar = Place.room("kind:hangar")
    static let pad = Place.room("kind:pad")

    static func forActivity(_ a: Activity, home: String, isSubagent: Bool) -> Place {
        if isSubagent || a == .researching { return .core }
        if a == .sleeping { return .quarters }
        if a == .qa { return .pad }
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
    let name: String
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
    /// The hangar is the 2x3 bay at the outer end of the south corridor arm.
    var hangarCells: [Cell] {
        guard hasHangar else { return [] }
        let y = spineHalfLength + 1
        return (0..<3).flatMap { d in [Cell(x: 0, y: y + d), Cell(x: 1, y: y + d)] }
    }
    var hangarCenter: SIMD2<Double> { SIMD2(0.5, Double(spineHalfLength) + 2.0) }
    /// Landing slots along the bay, in local coordinates.
    var hangarSlots: [SIMD2<Double>] { (0..<3).map { SIMD2(0.5, Double(spineHalfLength) + 1.0 + Double($0)) } }
    /// The launch pad is the 2x2 at the outer end of the west corridor arm.
    var padCells: [Cell] {
        guard hasPad else { return [] }
        let x = -spineHalfLength - 1
        return [Cell(x: x, y: 0), Cell(x: x, y: 1), Cell(x: x - 1, y: 0), Cell(x: x - 1, y: 1)]
    }
    var padCenter: SIMD2<Double> { SIMD2(Double(-spineHalfLength) - 1.5, 0.5) }
    var monolithPosition: SIMD2<Double> { SIMD2(0.5, Double(-spineHalfLength) - 1.5) }
    /// Six beds on the quarters floor, as local positions and the cell they belong to.
    var beds: [(pos: SIMD2<Double>, cell: Cell)] {
        guard let q = rooms["kind:quarters"] else { return [] }
        return q.cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.prefix(8).map { (SIMD2(Double($0.x), Double($0.y)), $0) }
    }

    static func rect(_ w: Int, _ h: Int) -> [Cell] {
        (0..<w).flatMap { x in (0..<h).map { y in Cell(x: x, y: y) } }
    }
    /// Symmetric bars, blocks and T shapes, like the real station.
    private static let baseShapes: [[Cell]] = [
        rect(2, 4), rect(2, 5), rect(3, 3), rect(2, 3), rect(3, 4), rect(2, 6),
        rect(4, 2) + [Cell(x: 1, y: 2), Cell(x: 2, y: 2), Cell(x: 1, y: 3), Cell(x: 2, y: 3)],
        rect(3, 2) + [Cell(x: 1, y: 2), Cell(x: 1, y: 3)],
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
        return out.filter { !coreCells.contains($0) && !hangarCells.contains($0) && !padCells.contains($0) }
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

    private var walkable: Set<Cell> {
        if let w = walkableCache { return w }
        var w = Set(coreCells)
        w.formUnion(hangarCells)
        w.formUnion(padCells)
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
        case .room("kind:pad"): return padCells + [Cell(x: -spineHalfLength, y: 0), Cell(x: -spineHalfLength, y: 1)]
        case .room(let key): return rooms[key]?.cells ?? []
        }
    }

    /// Creates a room if missing. Returns true when the layout changed.
    @discardableResult
    func ensureRoom(key: String, name: String, repo: String?, color: RGB, lastActive: Date, shape: [Cell]? = nil) -> Bool {
        if let r = rooms[key] {
            r.lastActive = max(r.lastActive, lastActive)
            return false
        }
        let cells = placeShape(shape ?? Station.baseShapes[abs(key.hashValue) % Station.baseShapes.count])
        rooms[key] = Room(key: key, name: name, repo: repo, color: color, cells: cells, lastActive: lastActive)
        for c in cells { occupied[c] = key }
        walkableCache = nil
        return true
    }

    @discardableResult
    func ensureFixedRoom(_ place: Place) -> Bool {
        guard case .room(let key) = place, key == "kind:quarters" else { return false }
        return ensureRoom(key: key, name: "sleeping", repo: nil, color: Colors.quarters, lastActive: .distantFuture, shape: Station.rect(2, 4))
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
    private func canStep(from a: Cell, to b: Cell) -> Bool {
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

    private func isReserved(_ c: Cell) -> Bool {
        isSpineLine(c) || coreCells.contains(c) || hangarCells.contains(c) || padCells.contains(c)
    }

    private func placeShape(_ shape: [Cell]) -> [Cell] {
        let variants = rotations(of: shape)
        while true {
            let reach = spineHalfLength + 4
            var anchors: [Cell] = []
            for x in -reach...reach { for y in -reach...reach { anchors.append(Cell(x: x, y: y)) } }
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
                    return cells
                }
            }
            spineHalfLength += 2
            walkableCache = nil
        }
    }

    /// Breadth-first path over walkable cells. Returns cells to visit, excluding `from`.
    func path(from: Cell, to: Cell) -> [Cell] {
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
    }
    struct SavedRoom: Codable { var name: String; var repo: String?; var color: RGB; var cells: [Cell]; var lastActive: Date }

    var saved: Saved {
        Saved(spine: spineHalfLength, rooms: rooms.mapValues {
            SavedRoom(name: $0.name, repo: $0.repo, color: $0.color, cells: $0.cells, lastActive: $0.lastActive)
        })
    }

    func restore(_ s: Saved) {
        spineHalfLength = s.spine
        for (key, r) in s.rooms where key != "kind:hangar" {
            guard r.cells.allSatisfy({ !isReserved($0) && occupied[$0] == nil }) else { continue }
            rooms[key] = Room(key: key, name: r.name, repo: r.repo, color: r.color, cells: r.cells, lastActive: r.lastActive)
            for c in r.cells { occupied[c] = key }
        }
        walkableCache = nil
    }
}

/// The two stations, side by side in the void, plus the repo colour book.
final class Fleet {
    private(set) var stations: [String: Station] = [:]
    private(set) var repoColors: [String: Int] = [:]

    static let order = ["work", "crew", "private"]

    private static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rumkapsel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fleet-v13.json")
    }

    /// GitHub owners whose repositories count as work, from an editable config file.
    static let workOwners: Set<String> = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Rumkapsel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: url), let cfg = try? JSONDecoder().decode([String: [String]].self, from: data), let owners = cfg["workOwners"] {
            return Set(owners.map { $0.lowercased() })
        }
        let defaults = ["workOwners": ["Tattoodo"]]
        if let data = try? JSONSerialization.data(withJSONObject: defaults, options: [.prettyPrinted]) { try? data.write(to: url) }
        return ["tattoodo"]
    }()

    /// Conductor workspaces and any repository owned by a work organisation are work; the rest is private.
    static func stationName(for cwd: String, owner: String? = nil) -> String {
        if cwd.contains("/conductor/") { return "work" }
        if let owner, workOwners.contains(owner) { return "work" }
        return "private"
    }

    func color(forRepo repo: String) -> RGB {
        if let i = repoColors[repo] { return Colors.repos[i % Colors.repos.count] }
        let i = repoColors.count
        repoColors[repo] = i
        return Colors.repos[i % Colors.repos.count]
    }

    func station(_ name: String) -> Station {
        if let s = stations[name] { return s }
        let s = Station(name: name)
        if name == "crew" { s.hasPad = false }
        s.ensureFixedRoom(.quarters)
        stations[name] = s
        return s
    }

    var ordered: [Station] { Fleet.order.compactMap { stations[$0] } }

    /// Lays stations out side by side with their corridors on one line, so work and crew can be bridged.
    func arrange() {
        var x = 0.0
        for (i, s) in ordered.enumerated() {
            let b = s.bounds
            if i > 0 { x += (s.name == "crew" || ordered[i - 1].name == "crew") ? 3 : 6 }
            s.offset = SIMD2(x - Double(b.min.x), 0)
            x += Double(b.max.x - b.min.x + 1)
        }
    }

    /// Corridor tiles bridging the work station's east arm to the crew station's west arm.
    var bridgeCells: [SIMD2<Double>] {
        guard let work = stations["work"], let crew = stations["crew"] else { return [] }
        let from = work.offset.x + Double(work.spineHalfLength) + 1
        let to = crew.offset.x - Double(crew.spineHalfLength) - 1
        guard to >= from else { return [] }
        var out: [SIMD2<Double>] = []
        var x = from
        while x <= to { out.append(SIMD2(x, 0)); out.append(SIMD2(x, 1)); x += 1 }
        return out
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
        let s = Saved(stations: stations.mapValues(\.saved), repoColors: repoColors)
        if let json = try? JSONEncoder().encode(s) { try? json.write(to: Fleet.saveURL) }
    }

    func load() {
        guard let data = try? Data(contentsOf: Fleet.saveURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        repoColors = saved.repoColors
        for (name, s) in saved.stations {
            let station = Station(name: name)
            if name == "crew" { station.hasPad = false }
            station.restore(s)
            station.ensureFixedRoom(.quarters)
            stations[name] = station
        }
    }
}
