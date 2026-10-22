import Foundation

struct Anchor: Equatable {
    enum Use: Equatable { case sit(height: Double), stand }
    let at: SIMD2<Double>
    let use: Use
}

enum FixtureKind: String {
    case console, holoTable

    var size: SIMD2<Double> {
        switch self {
        case .console: return SIMD2(0.86, 0.26)
        case .holoTable: return SIMD2(1.06, 1.06)
        }
    }

    var anchors: [Anchor] {
        switch self {
        case .console:
            return [Anchor(at: SIMD2(0, size.y / 2 + Seat.knees), use: .sit(height: Seat.height))]
        case .holoTable:
            return [0.0, 0.85, -0.85].map { Anchor(at: SIMD2(sin($0), cos($0)) * size.x / 2, use: .stand) }
        }
    }

    var doing: String {
        switch self {
        case .console: return "watching the boards in \(Words.current.theMission)"
        case .holoTable: return "studying the holo table"
        }
    }

    var going: String {
        switch self {
        case .console: return "sit at a console"
        case .holoTable: return "watch the holo table"
        }
    }
}

enum Seat {
    static let height = 0.2, knees = 0.2, reach = 0.176
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
        var chair: SIMD2<Double> { at + outward * Seat.middle }
        var stand: SIMD2<Double> { chair + outward * (Seat.footprint + 1 / Double(Station.fine)) }

        struct Sitting { let pos: SIMD2<Double>; let facing: Double; let chair: Double; let down: Bool }

        func sitting(_ t: Double, of total: Double) -> Sitting {
            let k = max(0, min(t, total - t))
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
        return Place(at: at, outward: outward, facing: atan2(-outward.x, -outward.y), use: a.use)
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
            return [Placed(kind: .console, at: SIMD2(1.45, 0.35), yaw: 0),
                    Placed(kind: .console, at: SIMD2(3.55, 0.35), yaw: 0),
                    Placed(kind: .console, at: SIMD2(4.78, 1.25), yaw: -.pi / 2),
                    Placed(kind: .holoTable, at: SIMD2(2.5, 1.5), yaw: 0)]
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
        if key == "kind:mission", !hasPad { return [] }
        return RoomLayout.of(key).map { PlacedFixture(kind: $0.kind, at: origin + $0.at, yaw: $0.yaw) }
    }

    func place(_ ref: FixtureRef) -> PlacedFixture.Place? {
        let all = fixtures(in: ref.room)
        guard all.indices.contains(ref.fixture) else { return nil }
        return all[ref.fixture].place(ref.anchor)
    }

    func anchors(in key: String) -> [FixtureRef] {
        fixtures(in: key).enumerated().flatMap { i, f in f.kind.anchors.indices.map { FixtureRef(room: key, fixture: i, anchor: $0) } }
    }
}
