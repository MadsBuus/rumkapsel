import Foundation

struct Anchor: Equatable {
    enum Use: Equatable { case sit(height: Double), stand, spot }
    enum Faces: Equatable { case fixture, away }
    let at: SIMD2<Double>
    let use: Use
    var faces: Faces = .fixture
}

enum FixtureKind: String {
    case console, holoTable, couch, counter, coffeeMachine, foodPrinter
    case treadmill, bench, bag, mat
    case bowl, shower, towelRail

    var size: SIMD2<Double> {
        switch self {
        case .console: return SIMD2(0.86, 0.26)
        case .holoTable: return SIMD2(1.06, 1.06)
        case .couch: return SIMD2(0.8, 0.3)
        case .counter: return SIMD2(0.32, 0.26)
        case .coffeeMachine: return SIMD2(0.17, 0.22)
        case .foodPrinter: return SIMD2(0.22, 0.22)
        case .treadmill: return SIMD2(0.42, 0.72)
        case .bench: return SIMD2(0.28, 0.7)
        case .bag: return SIMD2(0.2, 0.2)
        case .mat: return SIMD2(0.7, 0.7)
        case .bowl: return SIMD2(0.24, 0.37)
        case .shower: return SIMD2(0.1, Hands.arm + 0.07)
        case .towelRail: return SIMD2(0.24, 0.06)
        }
    }

    var swivels: Bool { self == .console }

    var anchors: [Anchor] {
        switch self {
        case .console:
            return [Anchor(at: SIMD2(0, size.y / 2 + Seat.knees), use: .sit(height: Seat.height))]
        case .holoTable:
            return [0.0, 0.85, -0.85].map { Anchor(at: SIMD2(sin($0), cos($0)) * size.x / 2, use: .stand) }
        case .couch:
            return [Anchor(at: SIMD2(0, Seat.reach), use: .sit(height: Seat.couch), faces: .away)]
        case .counter:
            return []
        case .coffeeMachine, .foodPrinter:
            return [Anchor(at: SIMD2(0, 0), use: .stand)]
        case .treadmill:
            return [Anchor(at: SIMD2(0, -0.05), use: .spot)]
        case .bench:
            return [Anchor(at: SIMD2(0, -0.18), use: .sit(height: Seat.height))]
        case .bag:
            return [Anchor(at: SIMD2(0, 0.28), use: .spot)]
        case .mat:
            return [Anchor(at: SIMD2(-0.05, -0.05), use: .spot)]
        case .bowl:
            return [Anchor(at: SIMD2(0, Seat.reach), use: .sit(height: Seat.height), faces: .away)]
        case .shower, .towelRail:
            return [Anchor(at: SIMD2(0, 0), use: .stand)]
        }
    }

    var doing: String {
        switch self {
        case .console: return "watching the boards in \(Words.current.theMission)"
        case .holoTable: return "studying the holo table"
        case .couch: return "resting on \(Words.current.theCouch)"
        case .counter: return "leaning on the counter"
        case .coffeeMachine: return "waiting on \(Words.current.coffee)"
        case .foodPrinter: return "waiting on \(Words.current.bite)"
        case .treadmill: return "running on the treadmill"
        case .bench: return "pressing on the bench"
        case .bag: return "boxing the bag"
        case .mat: return "doing jumping jacks on the mat"
        case .bowl: return "on the toilet"
        case .shower: return "in the shower"
        case .towelRail: return "drying off"
        }
    }

    var going: String {
        switch self {
        case .console: return "sit at a console"
        case .holoTable: return "watch the holo table"
        case .couch: return "rest on \(Words.current.theCouch)"
        case .counter: return "lean on the counter"
        case .coffeeMachine: return "get \(Words.current.coffee)"
        case .foodPrinter: return "get \(Words.current.bite)"
        case .treadmill: return "go for a run on the treadmill"
        case .bench: return "do a few presses on the bench"
        case .bag: return "go a round on the bag"
        case .mat: return "do jumping jacks on the mat"
        case .bowl: return "use the toilet"
        case .shower: return "take a shower"
        case .towelRail: return "dry off"
        }
    }
}

enum Seat {
    static let height = 0.2, knees = 0.2, reach = 0.176, couch = 0.18
    static let width = 0.24, depth = reach + 0.07, back = 0.03
    static var size: SIMD2<Double> { SIMD2(width, depth + back) }
    static var middle: Double { (depth + back) / 2 - 0.005 }
    static var footprint: Double { max(size.x, size.y) / 2 * 0.8 }
    static let sitDown = 0.5, swivel = 0.9
}

struct PlacedFixture: Equatable {
    let kind: FixtureKind
    let at: SIMD2<Double>
    let yaw: Double

    var front: SIMD2<Double> { SIMD2(sin(yaw), cos(yaw)) }
    var across: SIMD2<Double> { SIMD2(cos(yaw), -sin(yaw)) }
    func point(_ p: SIMD2<Double>) -> SIMD2<Double> { at + across * p.x + front * p.y }

    struct Place: Equatable {
        let at: SIMD2<Double>
        let outward: SIMD2<Double>
        let facing: Double
        let use: Anchor.Use
        var swivels = false
        var chair: SIMD2<Double> { at + outward * Seat.middle }
        var stand: SIMD2<Double> { swivels ? chair + outward * (Seat.footprint + 1 / Double(Station.fine)) : at + outward * Seat.knees }

        struct Sitting { let pos: SIMD2<Double>; let facing: Double; let chair: Double; let down: Bool }

        func sitting(_ t: Double, of total: Double) -> Sitting {
            let k = max(0, min(t, total - t))
            guard swivels else {
                let e = ease(min(1, k / Seat.sitDown))
                return Sitting(pos: stand + (at - stand) * e, facing: facing + .pi * (1 - e), chair: facing + .pi, down: k >= Seat.sitDown || t < total / 2)
            }
            let out = facing + .pi
            if k < Seat.swivel {
                return Sitting(pos: stand, facing: facing, chair: out + .pi * ease(k / Seat.swivel), down: false)
            }
            if k < Seat.swivel + Seat.sitDown {
                let e = ease((k - Seat.swivel) / Seat.sitDown)
                return Sitting(pos: stand + (chair + outward * Seat.middle - stand) * e, facing: facing + .pi * e, chair: out + .pi, down: t < total / 2)
            }
            let f = out - .pi * ease(min(1, (k - Seat.swivel - Seat.sitDown) / Seat.swivel))
            return Sitting(pos: chair + SIMD2(sin(f), cos(f)) * Seat.middle, facing: f, chair: f + .pi, down: true)
        }

        private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
    }

    func place(_ i: Int) -> Place? {
        guard kind.anchors.indices.contains(i) else { return nil }
        let a = kind.anchors[i]
        let at = point(a.at)
        let out = at - self.at
        let n = (out.x * out.x + out.y * out.y).squareRoot()
        let outward = n > 0.001 ? out / n : front
        let facing = a.faces == .away ? atan2(outward.x, outward.y) : atan2(-outward.x, -outward.y)
        return Place(at: at, outward: outward, facing: facing, use: a.use, swivels: kind.swivels)
    }
}

struct FixtureRef: Hashable {
    let room: String
    let fixture: Int
    let anchor: Int
}

enum RoomLayout {
    struct Placed { let kind: FixtureKind; let at: SIMD2<Double>; let yaw: Double }

    static func of(_ key: String) -> [Placed] {
        switch key {
        case "kind:mission":
            return [Placed(kind: .console, at: SIMD2(0.95, 0.35), yaw: 0),
                    Placed(kind: .console, at: SIMD2(4.05, 0.35), yaw: 0),
                    Placed(kind: .console, at: SIMD2(4.78, 1.6), yaw: -.pi / 2),
                    Placed(kind: .holoTable, at: SIMD2(2.5, 1.5), yaw: 0)]
        case "kind:galley":
            let counter = FixtureKind.counter.size
            return [-1.0, 0, 1].map { Placed(kind: .counter, at: SIMD2($0 * counter.x, counter.y / 2 - 0.5), yaw: 0) }
                + [Placed(kind: .coffeeMachine, at: SIMD2(0.2, -Hands.arm), yaw: 0), Placed(kind: .foodPrinter, at: SIMD2(-0.2, -Hands.arm), yaw: 0)]
        default:
            return []
        }
    }
}

extension Station {
    func roomOrigin(_ key: String) -> SIMD2<Double>? {
        guard let room = rooms[key], !room.cells.isEmpty else { return nil }
        return SIMD2(Double(room.cells.map(\.x).min()!) - 0.5, Double(room.cells.map(\.y).min()!) - 0.5)
    }

    func fixtures(in key: String) -> [PlacedFixture] {
        guard let origin = roomOrigin(key) else { return [] }
        if key == "kind:lounge", let lounge = rooms[key] {
            let xs = lounge.cells.map(\.x)
            let west = Double(xs.min()!) - 0.1, east = Double(xs.max()!) + 0.1
            return couches.map { c in PlacedFixture(kind: .couch, at: c, yaw: c.x < west ? .pi / 2 : c.x > east ? -.pi / 2 : .pi) }
        }
        if key == "kind:galley", let galley {
            let yaw = atan2(-galley.back.x, -galley.back.y), across = SIMD2(-galley.back.y, galley.back.x)
            return RoomLayout.of(key).map { PlacedFixture(kind: $0.kind, at: galley.middle + across * $0.at.x - galley.back * $0.at.y, yaw: yaw + $0.yaw) }
        }
        if key == "kind:gym", let gym = rooms[key] { return gymFixtures(gym) }
        if key == "kind:bath", let bath = rooms[key] { return bathFixtures(bath) }
        if key == "kind:mission", !hasPad { return [] }
        return RoomLayout.of(key).map { PlacedFixture(kind: $0.kind, at: origin + $0.at, yaw: $0.yaw) }
    }

    private func gymFixtures(_ gym: Room) -> [PlacedFixture] {
        let door = doorCell(of: gym.key)
        let maxY = gym.cells.map(\.y).max()!
        let sign = Cell(x: gym.cells.filter { $0.y == maxY }.map(\.x).max()!, y: maxY)
        var tiles = gym.cells.filter { $0 != door && $0 != sign }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        while tiles.count < 4, let more = gym.cells.first(where: { !tiles.contains($0) }) { tiles.append(more) }
        let mid = SIMD2(Double(gym.cells.map(\.x).reduce(0, +)), Double(gym.cells.map(\.y).reduce(0, +))) / Double(gym.cells.count)
        return zip([FixtureKind.treadmill, .bench, .bag, .mat], tiles).map { kind, tile in
            let at = SIMD2(Double(tile.x), Double(tile.y))
            guard kind == .bag else { return PlacedFixture(kind: kind, at: at, yaw: 0) }
            let inward = SIMD2(at.x >= mid.x ? -1.0 : 1, at.y >= mid.y ? -1.0 : 1)
            return PlacedFixture(kind: kind, at: at, yaw: atan2(inward.x, inward.y))
        }
    }

    func place(_ ref: FixtureRef) -> PlacedFixture.Place? {
        let all = fixtures(in: ref.room)
        guard all.indices.contains(ref.fixture) else { return nil }
        return all[ref.fixture].place(ref.anchor)
    }

    func anchors(in key: String) -> [FixtureRef] {
        fixtures(in: key).enumerated().flatMap { i, f in f.kind.anchors.indices.map { FixtureRef(room: key, fixture: i, anchor: $0) } }
    }

    private func bathFixtures(_ bath: Room) -> [PlacedFixture] {
        let door = doorCell(of: bath.key)
        let maxY = bath.cells.map(\.y).max()!
        let sign = Cell(x: bath.cells.filter { $0.y == maxY }.map(\.x).max()!, y: maxY)
        var tiles = bath.cells.filter { $0 != door && $0 != sign }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        while tiles.count < 2, let more = bath.cells.first(where: { !tiles.contains($0) }) { tiles.append(more) }
        let mid = SIMD2(bath.cells.map { Double($0.x) }.reduce(0, +), bath.cells.map { Double($0.y) }.reduce(0, +)) / Double(bath.cells.count)
        func middle(_ c: Cell) -> SIMD2<Double> { SIMD2(Double(c.x), Double(c.y)) }
        func corner(_ c: Cell) -> SIMD2<Double> {
            let d = middle(c) - mid
            return SIMD2(d.x < 0 ? -1 : 1, d.y < 0 ? -1 : 1)
        }
        let toilet = corner(tiles[0]), shower = corner(tiles[1])
        return [PlacedFixture(kind: .bowl, at: middle(tiles[0]) + toilet * 0.22, yaw: atan2(0, -toilet.y)),
                PlacedFixture(kind: .shower, at: middle(tiles[1]) + SIMD2(0.3, 0.45) * shower, yaw: atan2(0, -shower.y)),
                PlacedFixture(kind: .towelRail, at: middle(tiles[1]) + SIMD2(0.46, -0.3) * shower, yaw: atan2(-shower.x, 0))]
    }
}
