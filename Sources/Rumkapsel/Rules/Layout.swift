import Foundation
import simd

struct YardGeometry: Equatable {
    var grids: [Zone: [[Cell]]]
    var offset: SIMD2<Double>
    var pads: Int

    init(hall: Hall, offset: SIMD2<Double>) {
        let back = hall.deconCells.map(\.y).max()
        let row = hall.deconCells.filter { $0.y == back }.sorted { $0.x < $1.x }
        grids = [.waiting: hall.storageGrid, .testing: hall.stagedGrid, .cleared: hall.clearedGrid, .decon: row.isEmpty ? [] : [row]]
        self.offset = offset
        pads = hall.padSlots.count
    }

    static let classic = YardGeometry(hall: Hall(entrance: Cell(x: -2, y: 0), padGap: 0), offset: .zero)

    var deconColumns: Int { (grids[.decon]?.first?.count ?? 0) * 2 }
}

extension Station {
    var yard: YardGeometry { YardGeometry(hall: hall, offset: offset) }
}

struct YardSpot: Equatable {
    let zone: Zone
    let column: Int
    let level: Int
    let cell: Cell
    let pos: SIMD3<Double>
    let yaw: Double
}

enum Layout {
    static let bandOrder = [3, 1, 2, 0]
    static let high = 3, deconHigh = 12, deconDrawn = 12

    static func band(_ column: Int) -> Int { (column / 2) % 4 }
    static func columns(_ band: Int) -> [Int] { [0, 1].flatMap { row in [0, 1].map { side in (row * 4 + band) * 2 + side } } }

    static func homes(_ f: Facts) -> [String: Int] { f.homes }

    static func newHome(_ repo: String, _ f: Facts) -> Int {
        let held = Set(f.homes.values)
        if let free = bandOrder.first(where: { !held.contains($0) }) { return free }
        func load(_ b: Int) -> Int { f.homes.filter { $0.value == b }.keys.reduce(0) { $0 + f.rowCrates(of: $1) } }
        return bandOrder.min { load($0) < load($1) }!
    }

    static func spots(_ f: Facts, _ g: YardGeometry) -> [CrateID: YardSpot] {
        var out: [CrateID: YardSpot] = [:]
        for zone in Zone.allCases {
            guard let grid = g.grids[zone], let width = grid.first?.count, width > 0 else { continue }
            let stacks = Dictionary(grouping: f.crates.values.filter { $0.zone == zone && $0.column != nil }) { $0.column! }
            for (column, stack) in stacks {
                let tile = column / 2
                let cell = grid[min(tile / width, grid.count - 1)][tile % width]
                let side = column % 2 == 0 ? -0.25 : 0.25
                for (level, c) in stack.sorted(by: { $0.seq < $1.seq }).enumerated() {
                    let (jx, jz, yaw) = zone == .waiting ? jitter(repo: c.id.repo, number: c.id.number) : (0, 0, 0)
                    let pos = SIMD3(g.offset.x + Double(cell.x) + side + jx, Double(level) * zone.stackStep, g.offset.y + Double(cell.y) + jz)
                    out[c.id] = YardSpot(zone: zone, column: column, level: level, cell: cell, pos: pos, yaw: yaw)
                }
            }
        }
        return out
    }

    static func pickColumn(_ repo: String, _ zone: Zone, _ f: Facts, _ g: YardGeometry, avoiding: Int? = nil) -> Int? {
        if zone == .decon { return deconColumn(repo, f, g, avoiding: avoiding) }
        guard g.grids[zone]?.isEmpty == false else { return nil }
        let here = stacks(zone, f)
        let home = f.homes[repo] ?? newHome(repo, f)
        let mine = Set(here.filter { $0.value.has(repo) }.map { band($0.key) }).subtracting([home])
        let others = Set(f.homes.filter { $0.key != repo }.values).union(here.filter { $0.value.hasOther(than: repo) }.map { band($0.key) })
        func nearest(_ bands: [Int]) -> [Int] {
            bands.sorted { (abs($0 - home), bandOrder.firstIndex(of: $0)!) < (abs($1 - home), bandOrder.firstIndex(of: $1)!) }
        }
        let rest = bandOrder.filter { $0 != home && !mine.contains($0) }
        let tries = [home] + mine.sorted() + nearest(rest.filter { !others.contains($0) }) + nearest(rest.filter { others.contains($0) })
        for b in tries { if let c = open(b, for: repo, here, avoiding: avoiding) { return c } }
        return nil
    }

    static func homeColumn(_ repo: String, _ zone: Zone, _ f: Facts) -> Int? {
        guard zone.isRow, let home = f.homes[repo] else { return nil }
        return open(home, for: repo, stacks(zone, f), avoiding: nil)
    }

    static func relayout(_ f: inout Facts, yard g: YardGeometry) {
        let order = f.crates.values.filter { $0.zone != nil }.sorted { $0.seq < $1.seq }.map(\.id)
        var out = f
        out.homes = [:]
        for id in order { out.crates[id] = nil }
        for id in order {
            guard var c = f.crates[id], let zone = c.zone else { continue }
            c.column = nil
            out.crates[id] = c
            if zone.isRow, out.homes[id.repo] == nil { out.homes[id.repo] = newHome(id.repo, out) }
            let column = pickColumn(id.repo, zone, out, g)
            out.crates[id]?.column = column
        }
        f = out
    }

    static func jitter(repo: String, number: Int) -> (Double, Double, Double) {
        var seed = stableHash("\(repo)#\(number)") | 1
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        return ((rnd() - 0.5) * 0.22, (rnd() - 0.5) * 0.3, (rnd() - 0.5) * 0.7)
    }

    private struct Stack {
        var height = 0
        var repos: [String] = []
        func has(_ r: String) -> Bool { repos.contains(r) }
        func hasOther(than r: String) -> Bool { repos.contains { $0 != r } }
    }
    private typealias Stacks = [Int: Stack]

    private static func stacks(_ zone: Zone, _ f: Facts) -> Stacks {
        var out: Stacks = [:]
        for c in f.crates.values where c.zone == zone {
            guard let column = c.column else { continue }
            out[column, default: Stack()].height += 1
            if out[column]?.has(c.id.repo) == false { out[column]?.repos.append(c.id.repo) }
        }
        return out
    }

    private static func open(_ band: Int, for repo: String, _ stacks: Stacks, avoiding: Int?) -> Int? {
        func key(_ c: Int) -> (Int, Int) {
            let s = stacks[c]
            return (s?.hasOther(than: repo) == true ? 1 : 0, s?.height ?? 0)
        }
        return columns(band).filter { $0 != avoiding && (stacks[$0]?.height ?? 0) < high }.min { key($0) < key($1) }
    }

    private static func deconColumn(_ repo: String, _ f: Facts, _ g: YardGeometry, avoiding: Int?) -> Int? {
        let cap = g.deconColumns
        let here = f.crates.values.filter { $0.zone == .decon && $0.column != nil }
        guard cap > 0, here.count < deconDrawn else { return nil }
        func height(_ c: Int) -> Int { here.filter { $0.column == c }.count }
        func lowest(_ columns: [Int]) -> Int? { columns.filter { height($0) < deconHigh }.min { (height($0), $0) < (height($1), $1) } }
        let tiles = Set(here.filter { $0.id.repo == repo }.map { $0.column! / 2 })
        let mine = tiles.sorted().flatMap { [$0 * 2, $0 * 2 + 1] }.filter { $0 < cap && $0 != avoiding }
        if let c = lowest(mine) { return c }
        let taken = Set(here.map { $0.column! / 2 })
        if let tile = (0..<cap / 2).first(where: { !taken.contains($0) && $0 * 2 != avoiding }) { return tile * 2 }
        return lowest(Array(0..<cap).filter { $0 != avoiding })
    }
}
