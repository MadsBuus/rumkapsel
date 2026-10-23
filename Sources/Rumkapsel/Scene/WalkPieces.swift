import AppKit
import SceneKit

struct WalkFloor {
    let name: String
    let offset: SIMD2<Double>
    let walkable: Set<Cell>
    let pad: Set<Cell>
    let gate: Set<[Int]>
    let hangar: Set<Cell>
    let mouthRow: Int?
    let mission: Set<Cell>
    let monolith: Cell
    let steps: Set<[Int]>
    let styles: [Cell: Bulkhead.Style]
    let signs: [Signs.Sign]
    let hull: StationHull

    init(_ st: Station) {
        name = st.name
        offset = st.offset
        walkable = st.walkable
        pad = Set(st.hall.padCells)
        gate = Set(st.hall.padWall.map { [$0.hall.x, $0.hall.y, $0.out.x, $0.out.y] })
        hangar = Set(st.hangarCells)
        mouthRow = st.hangarCells.map(\.y).max()
        mission = Set(st.rooms["kind:mission"]?.cells ?? [])
        monolith = st.plan.monolith
        var steps = Set<[Int]>()
        for c in st.walkable {
            for n in [Cell(x: c.x + 1, y: c.y), Cell(x: c.x, y: c.y + 1)] where st.walkable.contains(n) && st.canStep(from: c, to: n) {
                steps.insert([c.x, c.y, n.x, n.y])
            }
        }
        self.steps = steps
        styles = Bulkhead.styles(of: st)
        signs = Signs.plan(st)
        hull = StationHull(st)
    }

    func canStep(from c: Cell, to n: Cell) -> Bool { steps.contains([c.x, c.y, n.x, n.y]) }
}

struct WalkPieces {
    let walls: SCNNode
    let dome: SCNNode
    let arrows: [Signs.Arrow]
    let hulls: [String: StationHull]
    let signature: Int
    let skins: Int

    static let thickness = 0.07, gap = 0.04
    static let queue = DispatchQueue(label: "rumkapsel.walk", qos: .userInitiated)

    static func build(_ floors: [WalkFloor], tints: [Cell: NSColor], signature: Int, skins: Int) -> WalkPieces {
        var arrows: [Signs.Arrow] = []
        let walls = SCNNode(), dome = SCNNode()
        for f in floors.sorted(by: { $0.name < $1.name }) {
            walls.addChildNode(wallsNode(f, tints: tints))
            for sign in f.signs { walls.addChildNode(signNode(sign, in: f, arrows: &arrows)) }
            for n in domeNodes(f) { dome.addChildNode(n) }
        }
        return WalkPieces(walls: walls, dome: dome, arrows: arrows, hulls: Dictionary(uniqueKeysWithValues: floors.map { ($0.name, $0.hull) }),
                          signature: signature, skins: skins)
    }

    private static func wallsNode(_ st: WalkFloor, tints: [Cell: NSColor]) -> SCNNode {
        var glows: [String: SCNMaterial] = [:]
        func glow(_ c: NSColor?) -> SCNMaterial {
            let base = c ?? Palette.text
            let key = WallPanel.key(base)
            if let m = glows[key] { return m }
            let m = flat(base.blended(withFraction: 0.55, of: .white) ?? base)
            glows[key] = m
            return m
        }
        let shell = lit(NSColor(rgb: (0.86, 0.87, 0.89)))
        let t = thickness, gap = WalkPieces.gap
        let railPost = SCNCylinder(radius: t / 2, height: Walker.railHeight - gap)
        railPost.firstMaterial = shell
        let edge = SCNCylinder(radius: t / 2, height: Walker.wallHeight - gap)
        edge.radialSegmentCount = 16
        edge.firstMaterial = shell
        let walk = st.walkable
        func unwalled(_ c: Cell, _ n: Cell) -> Bool {
            st.gate.contains([c.x, c.y, n.x, n.y]) || (n.y == (st.mouthRow ?? .min) + 1 && c.y == st.mouthRow && st.hangar.contains(c))
                || (st.mission.contains(c) && st.pad.contains(n)) || (st.pad.contains(c) && st.mission.contains(n))
        }
        let root = SCNNode()
        var corners: [Cell: [Bool]] = [:], railCorners: [Cell: [Bool]] = [:]
        func tint(_ c: Cell) -> NSColor? { tints[Cell(x: Int((st.offset.x + Double(c.x)).rounded()), y: Int((st.offset.y + Double(c.y)).rounded()))] }
        var stretches: [(c: Cell, dx: Int, dy: Int)] = []
        for c in walk.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            for (dx, dy) in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
                let n = Cell(x: c.x + dx, y: c.y + dy)
                let floored = walk.contains(n)
                if floored && (dx < 0 || dy < 0 || st.canStep(from: c, to: n)) { continue }
                if n == st.monolith || unwalled(c, n) { continue }
                stretches.append((c, dx, dy))
            }
        }
        for (c, dx, dy) in stretches {
            let n = Cell(x: c.x + dx, y: c.y + dy)
            let floored = walk.contains(n)
            let low = st.pad.contains(c) && (!floored || st.pad.contains(n))
            let h = (low ? Walker.railHeight : Walker.wallHeight) - gap
            let across = dx != 0
            let box = SCNBox(width: across ? t : 1, height: h, length: across ? 1 : t, chamferRadius: 0)
            func side(_ x: Int, _ y: Int) -> Int { x > 0 ? 1 : x < 0 ? 3 : y > 0 ? 0 : 2 }
            var faces = Array(repeating: shell, count: 6)
            if !low {
                faces[side(-dx, -dy)] = Bulkhead.material(Bulkhead.pick(c, dx, dy, st.name), style: st.styles[c] ?? .hallway)
                faces[side(dx, dy)] = Bulkhead.material(Bulkhead.pick(n, -dx, -dy, st.name), style: st.styles[n] ?? .hallway)
            }
            box.materials = faces
            let wall = SCNNode(geometry: box)
            let mid = st.offset + SIMD2(Double(c.x) + Double(dx) * 0.5, Double(c.y) + Double(dy) * 0.5)
            wall.position = v3(mid.x, gap + h / 2, mid.y)
            root.addChildNode(wall)
            let lip = SCNNode(geometry: SCNBox(width: across ? t + 0.012 : 1, height: 0.016, length: across ? 1 : t + 0.012, chamferRadius: 0.008))
            lip.geometry!.firstMaterial = shell
            lip.position = v3(mid.x, gap + h, mid.y)
            root.addChildNode(lip)
            let (px, py) = (dy, dx)
            let ends = [Cell(x: 2 * c.x + dx + px, y: 2 * c.y + dy + py), Cell(x: 2 * c.x + dx - px, y: 2 * c.y + dy - py)]
            guard !low else { for e in ends { railCorners[e, default: []].append(across) }; continue }
            for e in ends { corners[e, default: []].append(across) }
            for (cell, sign) in [(c, -1.0)] + (floored ? [(n, 1.0)] : []) {
                let strip = SCNBox(width: across ? t / 2 : 1, height: 0.012, length: across ? 1 : t / 2, chamferRadius: 0)
                strip.firstMaterial = glow(tint(cell))
                let s = SCNNode(geometry: strip)
                let off = t / 4 * sign
                s.position = v3(mid.x + (across ? off * Double(dx) : 0), 0.008, mid.y + (across ? 0 : off * Double(dy)))
                root.addChildNode(s)
            }
        }
        for (k, ends) in corners where !(ends.count == 2 && ends[0] == ends[1]) {
            let p = SCNNode(geometry: edge)
            p.position = v3(st.offset.x + Double(k.x) / 2, gap + (Walker.wallHeight - gap) / 2, st.offset.y + Double(k.y) / 2)
            root.addChildNode(p)
        }
        for (k, ends) in railCorners where !(ends.count == 2 && ends[0] == ends[1]) && corners[k] == nil {
            let p = SCNNode(geometry: railPost)
            p.position = v3(st.offset.x + Double(k.x) / 2, gap + (Walker.railHeight - gap) / 2, st.offset.y + Double(k.y) / 2)
            root.addChildNode(p)
        }
        let flatWalls = root.flattenedClone()
        flatWalls.categoryBitMask = Pick.scenery
        return flatWalls
    }

    private static func signNode(_ sign: Signs.Sign, in st: WalkFloor, arrows: inout [Signs.Arrow]) -> SCNNode {
        let (n, rolling) = Signs.panel(sign)
        arrows += rolling
        let p = SIMD2(Double(sign.wall.x), Double(sign.wall.y))
        let at = st.offset + SIMD2(Double(sign.cell.x), Double(sign.cell.y)) + p * (0.5 - thickness / 2 - 0.004)
        n.position = v3(at.x, 0.47, at.y)
        n.eulerAngles.y = CGFloat(atan2(-p.x, -p.y))
        n.categoryBitMask = Pick.scenery
        return n
    }

    private static func domeNodes(_ st: WalkFloor) -> [SCNNode] {
        var out: [SCNNode] = []
        let step = 0.25
        let hull = st.hull
        let bare = SCNNode()
        for c in hull.inside where !st.walkable.contains(c) && c != st.monolith {
            let tile = SCNNode(geometry: WallPanel.bareDeck)
            tile.eulerAngles.x = -.pi / 2
            tile.position = v3(st.offset.x + Double(c.x), -0.002, st.offset.y + Double(c.y))
            bare.addChildNode(tile)
        }
        let flatDeck = bare.flattenedClone()
        flatDeck.categoryBitMask = Pick.scenery
        out.append(flatDeck)
        var glass = (v: [SCNVector3](), uv: [CGPoint](), i: [Int32]())
        let n = Int((1 / step).rounded())
        var heights: [SIMD2<Int>: Double] = [:]
        func height(_ k: SIMD2<Int>) -> Double {
            if let h = heights[k] { return h }
            let h = StationHull.height(atDistance: hull.reach(SIMD2(Double(k.x), Double(k.y)) * step - 0.5).distance)
            heights[k] = h
            return h
        }
        for c in hull.inside {
            let door = hull.nearDoor(c)
            for i in 0..<n {
                for j in 0..<n {
                    let gx = c.x * n + i, gy = c.y * n + j
                    let x0 = Double(c.x) - 0.5 + Double(i) * step, y0 = Double(c.y) - 0.5 + Double(j) * step
                    let corners = [SIMD2(x0, y0), SIMD2(x0 + step, y0), SIMD2(x0 + step, y0 + step), SIMD2(x0, y0 + step)]
                    let hs = [SIMD2(gx, gy), SIMD2(gx + 1, gy), SIMD2(gx + 1, gy + 1), SIMD2(gx, gy + 1)].map(height)
                    if door {
                        let near = hull.reach(SIMD2(x0 + step / 2, y0 + step / 2))
                        if near.door, near.distance < step, hs.max()! < StationHull.doorTop * 1.4 { continue }
                    }
                    let world = zip(corners, hs).map { v3(st.offset.x + $0.0.x, $0.1, st.offset.y + $0.0.y) }
                    let base = Int32(glass.v.count)
                    glass.v += world
                    glass.uv += corners.map { CGPoint(x: $0.x + 0.5, y: $0.y + 0.5) }
                    glass.i += [base, base + 1, base + 2, base, base + 2, base + 3]
                }
            }
        }
        let foot = SCNNode()
        for f in hull.feet where !f.door {
            let mid = (f.a + f.b) / 2, along = f.b - f.a
            let across = abs(along.x) < abs(along.y)
            var inward = across ? SIMD2(1.0, 0) : SIMD2(0, 1.0)
            if !hull.covers(mid + inward * 0.25) { inward = -inward }
            let sill = SCNBox(width: across ? 0.07 : 1, height: 0.06, length: across ? 1 : 0.07, chamferRadius: 0)
            sill.firstMaterial = Bulkhead.steel
            let s = SCNNode(geometry: sill)
            let at = mid + inward * 0.035
            s.position = v3(st.offset.x + at.x, 0.03, st.offset.y + at.y)
            foot.addChildNode(s)
        }
        let flatFoot = foot.flattenedClone()
        flatFoot.categoryBitMask = Pick.scenery
        out.append(flatFoot)
        if !glass.v.isEmpty {
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: glass.v), SCNGeometrySource(textureCoordinates: glass.uv)],
                                elements: [SCNGeometryElement(indices: glass.i, primitiveType: .triangles)])
            g.firstMaterial = WallPanel.hullGlass
            let glassNode = SCNNode(geometry: g)
            glassNode.categoryBitMask = Pick.scenery
            glassNode.renderingOrder = 90
            out.append(glassNode)
        }
        return out
    }
}
