import AppKit
import SceneKit

struct KenneyLook: Look {
    var background: NSColor { Kit.sky }
    var hangsPosters: Bool { false }
    var viewYaw: Double { .pi / 4 + .pi }
    var floorTop: Double { Kit.plateTop }
    var dotsHallway: Bool { false }
    var rimsOffices: Bool { false }

    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] { [] }
    var hangarField: Bool { false }
    func hullWall(width: Double, depth: Double, doorway: Double, doorTop: Double) -> SCNNode? { nil }
    var detailsFloors: Bool { false }

    static let reach = 13.0, fade = 5.0

    private static var coast: (key: String, node: SCNNode)?

    func ground(under stations: [Station], into root: SCNNode) {
        guard let fp = fleetFootprint(stations), let cape = Cape(stations) else { return }
        let grid = 8.0, reach = Self.reach, fade = Self.fade
        func down(_ v: Double) -> Double { (v / grid).rounded(.down) * grid }
        func up(_ v: Double) -> Double { (v / grid).rounded(.up) * grid }
        let known = (lo: SIMD2(down(fp.lo.x), down(fp.lo.y)), hi: SIMD2(up(fp.hi.x), up(fp.hi.y)))
        let margin = reach + fade + 2
        let lo = known.lo - SIMD2(repeating: margin), hi = known.hi + SIMD2(repeating: margin)
        func unexplored(_ p: SIMD2<Double>) -> Double {
            let past = simd_length(simd_max(simd_max(known.lo - p, p - known.hi), SIMD2(repeating: 0)))
            return past + (Noise.fbm(p, scale: 9, seed: 41) - 0.5) * 4
        }
        let shore = down(cape.shore)
        let key = "\(known.lo.x),\(known.lo.y),\(known.hi.x),\(known.hi.y),\(shore)"
        let coast = Self.coast?.key == key ? Self.coast!.node : {
            let holder = SCNNode()
            let lawnFrom = max(lo.x, shore - 8)
            let lawn = SCNNode(geometry: SCNPlane(width: hi.x - lawnFrom, height: hi.y - lo.y))
            lawn.geometry!.firstMaterial = lit(Kit.grass)
            lawn.eulerAngles.x = -.pi / 2
            lawn.position = v3((lawnFrom + hi.x) / 2, -0.06, (lo.y + hi.y) / 2)
            holder.addChildNode(lawn)
            let land = Shapes.sample(from: lo, to: hi, step: 0.5) { p in p.x - cape.shoreline(p.y) }
            let bands: [(Shapes.Grid, NSColor, Double)] = [
                (land.map { _, d in -d }, Kit.water, -0.05),
                (land.map { _, d in min(-d, 2.6 + d) }, Kit.water.lighter(0.18), -0.045),
                (land.map { _, d in min(0.5 - d, 0.5 + d) }, NSColor(rgb: (0.93, 0.97, 0.99)), -0.04),
                (land.map { _, d in min(d, 1.5 - d) }, NSColor(rgb: (0.89, 0.83, 0.66)), -0.043),
            ]
            for (grid, color, y) in bands {
                if let n = Shapes.node(Shapes.fill(grid), color, y: y) { holder.addChildNode(n) }
            }
            let fog = Shapes.sample(from: lo, to: hi, step: 0.5) { p in unexplored(p) }
            for (k, level) in [reach, reach + fade * 0.35, reach + fade * 0.7, reach + fade].enumerated() {
                guard let n = Shapes.node(Shapes.fill(fog, level: level), Kit.sky, y: -0.02 + Double(k) * 0.002) else { continue }
                n.opacity = k == 3 ? 1 : 0.34
                holder.addChildNode(n)
            }
            Self.coast = (key, holder)
            return holder
        }()
        root.addChildNode(coast)

        let palms = ["tree_palm", "tree_palmTall", "tree_palmBend", "tree_palmDetailedShort"]
        let scrub = ["grass", "grass", "grass", "grass", "grass", "grass_large", "grass_large", "grass_large",
                     "plant_bush", "plant_bushLarge", "flower_yellowA", "flower_redA", "rock_smallA", "rock_smallB"]
        for z in Int(lo.y.rounded())...Int(hi.y.rounded()) {
            let edge = cape.shoreline(Double(z))
            for x in Int(max(lo.x, cape.shore - 2).rounded())...Int(hi.x.rounded()) {
                let p = SIMD2(Double(x), Double(z))
                guard unexplored(p) < reach - 1 else { continue }
                guard let home = cape.nearest(p), !home.claims(p, within: 1.4) else { continue }
                let cell = home.cell(p)
                let h = Noise.hash(cell.x, cell.y, seed: home.seed)
                let d = p.x - edge
                guard d > 1.4 else { continue }
                let q = SIMD2(Double(cell.x), Double(cell.y))
                let grove = Noise.fbm(q, scale: 26, seed: 9)
                let onSand = d < 8 && grove > 0.47
                let density = onSand ? (grove - 0.47) * 2.4
                                     : max(0, Noise.fbm(q, scale: 23, seed: 3) - 0.50) * 2.6
                guard h < density else { continue }
                let pick = Noise.hash(cell.x, cell.y, seed: home.seed + 31)
                let names = onSand ? palms : (pick < 0.03 ? ["rock_largeA"] : scrub)
                let name = names[min(names.count - 1, Int(pick * Double(names.count)))]
                guard let n = Kit.node(name, from: .nature, tint: Kit.scrubTint) else { continue }
                let s = 0.7 + 0.4 * Noise.hash(cell.x, cell.y, seed: home.seed + 57)
                n.scale = SCNVector3(s, s, s)
                n.eulerAngles.y = 2 * .pi * Noise.hash(cell.x, cell.y, seed: home.seed + 83)
                let jitter = SIMD2(Noise.hash(cell.x, cell.y, seed: home.seed + 11) - 0.5,
                                   Noise.hash(cell.x, cell.y, seed: home.seed + 19) - 0.5) * 0.7
                n.position = v3(p.x + jitter.x, -0.03, p.y + jitter.y)
                root.addChildNode(n)
            }
        }
    }

    static let concrete = NSColor(rgb: (0.66, 0.67, 0.66))
    static let kerb = NSColor(rgb: (0.46, 0.47, 0.48))
    static let padPaint = NSColor(rgb: (0.34, 0.35, 0.38))
    static let hazard = NSColor(rgb: (0.82, 0.68, 0.26))
    static let bayPaint = NSColor(rgb: (0.52, 0.55, 0.62))
    static let deckPaint = NSColor(rgb: (0.42, 0.55, 0.52))
    static let paintLine = NSColor(rgb: (0.92, 0.93, 0.92))
    static let steel = NSColor(rgb: (0.72, 0.74, 0.76))

    private func slab(_ cells: [Cell], of station: Station, grow: Double, _ color: NSColor, y: Double) -> SCNNode? {
        guard !cells.isEmpty else { return nil }
        let own = Set(cells)
        let from = grow >= 0 ? cells : own.flatMap { c in
            Tile.around.map { Cell(x: c.x + $0.0, y: c.y + $0.1) }
        }.filter { !own.contains($0) }
        let pts = Array(Set(from)).map { SIMD2(Double($0.x), Double($0.y)) }
        guard !pts.isEmpty else { return nil }
        let cx = cells.map(\.x), cz = cells.map(\.y)
        let pad = max(grow, 0) + 1
        let lo = SIMD2(Double(cx.min()!) - pad, Double(cz.min()!) - pad)
        let hi = SIMD2(Double(cx.max()!) + pad, Double(cz.max()!) + pad)
        let round = 0.28, half = SIMD2<Double>(repeating: 0.5 - round)
        let geometry = Shapes.fill(from: lo, to: hi, step: 0.25) { p in
            var near = Double.infinity
            for c in pts {
                let q = simd_abs(p - c) - half
                near = min(near, simd_length(simd_max(q, SIMD2(repeating: 0))) + min(max(q.x, q.y), 0) - round)
            }
            return grow >= 0 ? grow - near : near + grow
        }
        guard let n = Shapes.node(geometry, color, y: 0) else { return nil }
        n.position = v3(station.offset.x, y, station.offset.y)
        return n
    }

    func output(_ station: Station, deckInUse: Bool) -> SetPiece? {
        guard station.hasPad else { return nil }
        var piece = SetPiece()
        let deck = deckInUse ? station.hall.deckCells : []
        let parts: [(Area, [Cell], NSColor)] = [(.decon, station.hall.deconCells, Self.hazard),
                                                (.storage, station.hall.storageCells, Self.bayPaint),
                                                (.deck, deck, Self.deckPaint),
                                                (.pad, station.hall.padCells, Self.padPaint)]
        for (i, (area, cells, _)) in parts.enumerated() {
            if let k = slab(cells, of: station, grow: 0.5, Self.kerb, y: -0.004) { piece.add(k, as: area) }
            if let a = slab(cells, of: station, grow: 0.36, Self.concrete, y: Kit.plateTop + Double(i) * 0.0004) {
                piece.add(a, as: area)
            }
        }
        for (area, cells, color) in parts {
            if let n = slab(cells, of: station, grow: -0.14, color, y: Kit.plateTop + 0.003) { piece.add(n, as: area) }
        }
        if let ring = slab(station.hall.padCells, of: station, grow: 0.06, Self.paintLine, y: Kit.plateTop + 0.0035),
           let inner = slab(station.hall.padCells, of: station, grow: -0.1, Self.padPaint, y: Kit.plateTop + 0.004) {
            piece.add(ring, as: .pad)
            piece.add(inner, as: .pad)
        }
        let px = station.hall.padCells.map(\.x), pz = station.hall.padCells.map(\.y)
        let trench = SCNNode(geometry: SCNPlane(width: 1.15, height: 1.15))
        trench.geometry!.firstMaterial = flat(NSColor(rgb: (0.16, 0.16, 0.18)))
        trench.eulerAngles.x = -.pi / 2
        trench.eulerAngles.z = .pi / 4
        trench.position = v3(station.offset.x + station.hall.padCenter.x, Kit.plateTop + 0.005, station.offset.y + station.hall.padCenter.y)
        piece.add(trench, as: .pad)
        let gantry = Self.gantry()
        gantry.position = v3(station.offset.x + Double(px.min()!) - 0.75, 0, station.offset.y + station.hall.padCenter.y)
        piece.add(gantry, as: .pad)
        for (dx, dz) in [(Double(px.min()!) - 0.95, Double(pz.min()!) - 0.95), (Double(px.max()!) + 0.95, Double(pz.min()!) - 0.95)] {
            let mast = Self.floodlight()
            mast.position = v3(station.offset.x + dx, 0, station.offset.y + dz)
            piece.add(mast, as: .pad)
        }
        return piece
    }

    private static func gantry() -> SCNNode {
        let n = SCNNode()
        let frame = lit(steel), dark = lit(NSColor(rgb: (0.5, 0.52, 0.55)))
        let height = 2.4, span = 0.34
        for (sx, sz) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let leg = SCNNode(geometry: SCNBox(width: 0.07, height: height, length: 0.07, chamferRadius: 0))
            leg.geometry!.firstMaterial = frame
            leg.position = v3(sx * span, height / 2, sz * span)
            n.addChildNode(leg)
        }
        for level in 1...4 {
            let y = height * Double(level) / 4.5
            for turned in [false, true] {
                let rail = SCNNode(geometry: SCNBox(width: turned ? 0.05 : span * 2, height: 0.05, length: turned ? span * 2 : 0.05, chamferRadius: 0))
                rail.geometry!.firstMaterial = dark
                rail.position = v3(turned ? span : 0, y, turned ? 0 : span)
                n.addChildNode(rail)
                let far = rail.clone()
                far.position = v3(turned ? -span : 0, y, turned ? 0 : -span)
                n.addChildNode(far)
            }
        }
        let head = SCNNode(geometry: SCNBox(width: span * 2.3, height: 0.2, length: span * 2.3, chamferRadius: 0))
        head.geometry!.firstMaterial = frame
        head.position = v3(0, height + 0.1, 0)
        n.addChildNode(head)
        let arm = SCNNode(geometry: SCNBox(width: 1.5, height: 0.09, length: 0.16, chamferRadius: 0))
        arm.geometry!.firstMaterial = dark
        arm.position = v3(0.85, height - 0.35, 0)
        n.addChildNode(arm)
        return n
    }

    private static func floodlight() -> SCNNode {
        let n = SCNNode()
        let post = SCNNode(geometry: SCNBox(width: 0.08, height: 1.35, length: 0.08, chamferRadius: 0))
        post.geometry!.firstMaterial = lit(steel)
        post.position = v3(0, 0.675, 0)
        n.addChildNode(post)
        for i in -1...1 {
            let lamp = SCNNode(geometry: SCNBox(width: 0.16, height: 0.12, length: 0.08, chamferRadius: 0))
            lamp.geometry!.firstMaterial = flat(NSColor(rgb: (0.96, 0.95, 0.8)))
            lamp.position = v3(Double(i) * 0.18, 1.37, 0)
            n.addChildNode(lamp)
        }
        return n
    }

    func tileDetail(_ tile: Tile) -> SCNNode? {
        guard let plate = Kit.platform(open: tile.open, color: tile.color) else { return nil }
        plate.eulerAngles.x = .pi / 2
        plate.position = SCNVector3(0, 0, Kit.plateTop - 0.05)
        return plate
    }

    func tint(tile: SCNNode, _ color: NSColor) { Kit.tint(tile: tile, color) }

    func input(_ station: Station) -> SetPiece? {
        guard station.hasHangar, !station.hangarCells.isEmpty else { return nil }
        var piece = SetPiece()
        for (area, cells) in [(Area.bay, station.hangarCells)] {
            if let k = slab(cells, of: station, grow: 0.5, Self.kerb, y: -0.004) { piece.add(k, as: area) }
            if let a = slab(cells, of: station, grow: 0.36, Self.concrete, y: Kit.plateTop) { piece.add(a, as: area) }
        }
        if let apron = slab(station.hangarCells, of: station, grow: -0.14, Self.bayPaint, y: Kit.plateTop + 0.003) {
            piece.add(apron, as: .bay)
        }
        return piece
    }

    func doorFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
        guard let gate = Kit.gate(yaw: facing.x == 0 ? 0 : .pi / 2) else { return Classic.doorFrame(facing: facing) }
        return (gate, 0.9)
    }

    func monolith() -> SCNNode { Kit.tower() ?? Classic.monolith() }

    func figure(id: String, crew: Bool, height: Double) -> SCNNode? { Kit.astronaut(crew: crew, height: height) }

    func pose(figure: SCNNode, height: Double, torso: Double) {
        let s = height / Kit.astronautHeight
        figure.scale = SCNVector3(s, s * torso / height, s)
        figure.position = v3(0, -torso / 2, -0.03)
    }

    func shuttle(color: NSColor) -> SCNNode { Kit.craft(color: color) ?? Classic.shuttle(color: color) }
    var berthHexHeight: Double { Kit.plateTop + 0.004 }

    var rocketFollowsLoad: Bool { true }

    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        Kit.rocketProp(color: color, tall: tall, cargo: cargo) ?? Classic.rocket(color: color, tall: tall, cargo: cargo)
    }

    func dress(station: Station) -> [SCNNode] {
        var props: [SCNNode] = []
        for (i, c) in Dressing.padCorners(station).enumerated() {
            guard let barrel = Kit.prop("machine_barrel", scale: 0.8, yaw: Double(i) * .pi / 2 + 0.4, color: NSColor(rgb: (0.75, 0.62, 0.25))) else { continue }
            barrel.position = v3(Double(c.x), 0, Double(c.y))
            props.append(barrel)
        }
        if let c = Dressing.bayParking(station), let rover = Kit.prop("rover", scale: 1.5, yaw: 0.6, color: NSColor(Colors.hangar).lighter(0.25)) {
            rover.position = v3(Double(c.x), 0, Double(c.y))
            props.append(rover)
        }
        return props
    }

    func crate(color: NSColor) -> SCNNode? {
        let n = SCNNode()
        let body = SCNNode(geometry: SCNBox(width: 0.5, height: 0.26, length: 0.34, chamferRadius: 0.01))
        body.geometry!.firstMaterial = lit(color.darker(0.06))
        body.position = v3(0, 0.13, 0)
        n.addChildNode(body)
        for k in -2...2 {
            let rib = SCNNode(geometry: SCNBox(width: 0.02, height: 0.24, length: 0.35, chamferRadius: 0))
            rib.geometry!.firstMaterial = lit(color.lighter(0.1))
            rib.position = v3(Double(k) * 0.1, 0.13, 0)
            n.addChildNode(rib)
        }
        for (sx, sz) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let casting = SCNNode(geometry: SCNBox(width: 0.07, height: 0.07, length: 0.07, chamferRadius: 0))
            casting.geometry!.firstMaterial = lit(NSColor(rgb: (0.72, 0.74, 0.78)))
            casting.position = v3(sx * 0.215, 0.235, sz * 0.135)
            n.addChildNode(casting)
        }
        return n
    }

    func hold(tall: Bool) -> SCNNode? {
        let n = SCNNode()
        let radius = 0.8
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + .pi / 4
            let post = SCNNode(geometry: SCNBox(width: 0.06, height: 0.4, length: 0.06, chamferRadius: 0))
            post.geometry!.firstMaterial = lit(NSColor(rgb: (0.72, 0.74, 0.78)))
            post.position = v3(cos(a) * radius, 0.2, sin(a) * radius)
            n.addChildNode(post)
            let lamp = SCNNode(geometry: SCNBox(width: 0.08, height: 0.05, length: 0.08, chamferRadius: 0.01))
            lamp.geometry!.firstMaterial = flat(NSColor(rgb: (0.98, 0.76, 0.2)))
            lamp.position = v3(cos(a) * radius, 0.44, sin(a) * radius)
            n.addChildNode(lamp)
            let b = Double(k + 1) / 4 * 2 * .pi + .pi / 4
            let from = SIMD2(cos(a) * radius, sin(a) * radius), to = SIMD2(cos(b) * radius, sin(b) * radius)
            let mid = (from + to) / 2
            for y in [0.18, 0.32] {
                let rail = SCNNode(geometry: SCNBox(width: simd_distance(from, to), height: 0.03, length: 0.03, chamferRadius: 0))
                rail.geometry!.firstMaterial = lit(NSColor(rgb: (0.84, 0.86, 0.88)))
                rail.eulerAngles.y = atan2(-(to.y - from.y), to.x - from.x)
                rail.position = v3(mid.x, y, mid.y)
                n.addChildNode(rail)
            }
        }
        return n
    }

    func dress(office room: Room, in station: Station, sign: OfficeSign) -> SCNNode? {
        guard !station.isEpic(room.key), let wall = station.officeWall(room) else { return nil }
        let d = wall.out
        guard let desk = Kit.prop("desk_computer", scale: 0.8, yaw: atan2(-d.x, -d.y), color: NSColor(room.color)) else { return nil }
        let at = station.desk(room, theme: .kenney) ?? SIMD2(Double(wall.cell.x), Double(wall.cell.y))
        desk.position = v3(at.x, Kit.plateTop, at.y)
        return desk
    }
}

private struct Cape {
    struct Home {
        let offset: SIMD2<Double>
        let floor: Set<Cell>
        let lo: SIMD2<Double>, hi: SIMD2<Double>
        let seed: Int

        func cell(_ p: SIMD2<Double>) -> Cell {
            Cell(x: Int((p.x - offset.x).rounded()), y: Int((p.y - offset.y).rounded()))
        }

        func claims(_ p: SIMD2<Double>, within margin: Double) -> Bool {
            let c = cell(p), r = Int(margin.rounded(.up))
            for dz in -r...r {
                for dx in -r...r where floor.contains(Cell(x: c.x + dx, y: c.y + dz)) {
                    let at = offset + SIMD2(Double(c.x + dx), Double(c.y + dz))
                    if simd_length(simd_max(simd_abs(p - at) - SIMD2(0.5, 0.5), SIMD2(repeating: 0))) < margin { return true }
                }
            }
            return false
        }

        func reach(to p: SIMD2<Double>) -> Double {
            let q = simd_max(simd_max(lo - p, p - hi), SIMD2(repeating: 0))
            return simd_length(q)
        }
    }

    let homes: [Home]
    let shore: Double
    private let phase: Double

    init?(_ stations: [Station]) {
        var homes: [Home] = []
        var shore = Double.infinity
        for st in stations {
            let floor = Set(st.allCells)
            guard let b = floor.isEmpty ? nil : st.bounds else { continue }
            homes.append(Home(offset: st.offset, floor: floor,
                              lo: st.offset + SIMD2(Double(b.min.x), Double(b.min.y)),
                              hi: st.offset + SIMD2(Double(b.max.x), Double(b.max.y)),
                              seed: abs(st.name.hashValue % 9973)))
            let west = st.hasPad ? st.hall.padCells.map(\.x).min() ?? b.min.x : b.min.x
            shore = min(shore, st.offset.x + Double(west) - 4)
        }
        guard !homes.isEmpty, shore.isFinite else { return nil }
        self.homes = homes
        self.shore = shore
        phase = homes.min { $0.lo.x < $1.lo.x }?.offset.y ?? 0
    }

    func shoreline(_ z: Double) -> Double {
        let t = z - phase
        return shore + (Noise.fbm(SIMD2(0, t), scale: 58) - 0.5) * 17 + (Noise.fbm(SIMD2(0, t), scale: 16, seed: 5) - 0.5) * 6
    }

    func nearest(_ p: SIMD2<Double>) -> Home? {
        homes.min { $0.reach(to: p) < $1.reach(to: p) }
    }
}
