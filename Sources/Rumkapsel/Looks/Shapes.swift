// Flat organic shapes for looks: a field turned into a mesh wherever it is at or over a level, by marching
// squares, so coastlines, clearings, plots and paths have soft edges instead of the grid's. A row's run of
// full cells is one quad, so a wide area costs little. Noise keyed to world position keeps a world where it
// was when the station round it grows.

import SceneKit
import simd

enum Shapes {
    /// A field sampled every `step` over a rectangle, so several shapes can be cut from one sampling.
    struct Grid {
        let lo: SIMD2<Double>, step: Double, nx: Int, nz: Int
        var values: [Double]
        func point(_ i: Int, _ j: Int) -> SIMD2<Double> { lo + SIMD2(Double(i), Double(j)) * step }
        /// Another field on the same points, worked out from each point and this field's value there.
        func map(_ f: (SIMD2<Double>, Double) -> Double) -> Grid {
            var g = self
            for j in 0...nz { for i in 0...nx { g.values[j * (nx + 1) + i] = f(point(i, j), values[j * (nx + 1) + i]) } }
            return g
        }
    }

    static func sample(from lo: SIMD2<Double>, to hi: SIMD2<Double>, step: Double, field: (SIMD2<Double>) -> Double) -> Grid {
        let nx = max(1, Int(((hi.x - lo.x) / step).rounded(.up))), nz = max(1, Int(((hi.y - lo.y) / step).rounded(.up)))
        let grid = Grid(lo: lo, step: step, nx: nx, nz: nz, values: [Double](repeating: 0, count: (nx + 1) * (nz + 1)))
        return grid.map { p, _ in field(p) }
    }

    /// A flat mesh in the XZ plane, at y 0, covering where `field` is at or over `level`, sampled every `step`
    /// over the rectangle from `lo` to `hi`. Nil when nothing is covered.
    static func fill(from lo: SIMD2<Double>, to hi: SIMD2<Double>, step: Double, level: Double = 0,
                     field: (SIMD2<Double>) -> Double) -> SCNGeometry? {
        fill(sample(from: lo, to: hi, step: step, field: field), level: level)
    }

    /// A flat mesh covering where a sampled field is at or over `level`.
    static func fill(_ grid: Grid, level: Double = 0) -> SCNGeometry? {
        let nx = grid.nx, nz = grid.nz, w = nx + 1
        let v = level == 0 ? grid.values : grid.values.map { $0 - level }
        func at(_ i: Int, _ j: Int) -> SIMD2<Double> { grid.point(i, j) }

        var verts: [SCNVector3] = []
        var index: [Int32] = []
        func vert(_ p: SIMD2<Double>) -> Int32 { verts.append(SCNVector3(p.x, 0, p.y)); return Int32(verts.count - 1) }
        for j in 0..<nz {
            var i = 0
            while i < nx {
                let c = [v[j * w + i], v[j * w + i + 1], v[(j + 1) * w + i + 1], v[(j + 1) * w + i]]
                if c.allSatisfy({ $0 >= 0 }) {
                    var e = i + 1
                    while e < nx, v[j * w + e + 1] >= 0, v[(j + 1) * w + e + 1] >= 0 { e += 1 }
                    let a = vert(at(i, j)), b = vert(at(e, j)), d = vert(at(e, j + 1)), f = vert(at(i, j + 1))
                    index += [a, f, d, a, d, b]   // counter-clockwise seen from above
                    i = e
                    continue
                }
                if c.contains(where: { $0 >= 0 }) {
                    let corners = [at(i, j), at(i + 1, j), at(i + 1, j + 1), at(i, j + 1)]
                    var poly: [SIMD2<Double>] = []
                    for k in 0..<4 {
                        let a = c[k], b = c[(k + 1) % 4]
                        if a >= 0 { poly.append(corners[k]) }
                        if (a >= 0) != (b >= 0) { poly.append(corners[k] + (corners[(k + 1) % 4] - corners[k]) * (a / (a - b))) }
                    }
                    if poly.count >= 3 {
                        let first = vert(poly[0])
                        var prev = vert(poly[1])
                        for q in poly.dropFirst(2) { let cur = vert(q); index += [first, cur, prev]; prev = cur }
                    }
                }
                i += 1
            }
        }
        guard !index.isEmpty else { return nil }
        let normals = [SCNVector3](repeating: SCNVector3(0, 1, 0), count: verts.count)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: index, primitiveType: .triangles)])
    }

    /// A node for a filled shape in one flat colour, lying `y` over the ground.
    static func node(_ geometry: SCNGeometry?, _ color: NSColor, y: Double) -> SCNNode? {
        guard let geometry else { return nil }
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .constant
        m.isDoubleSided = true
        geometry.materials = [m]
        let n = SCNNode(geometry: geometry)
        n.position = SCNVector3(0, y, 0)
        return n
    }

    private static var patches: [String: SCNGeometry] = [:]

    /// A patch over one tile, centred on the origin, that runs on into the neighbours marked in `same` (bits as
    /// `Tile.around`) and stands `inset` in from anything else, its outer corners rounded by `round`. Shared by
    /// every tile with the same neighbours; give each its own material with `copy()`.
    static func patch(same: UInt8, inset: Double, round: Double) -> SCNGeometry? {
        let key = "\(same)|\(inset)|\(round)"
        if let g = patches[key] { return g }
        var others: [SIMD2<Double>] = []
        for (k, (dx, dz)) in Tile.around.enumerated() where same & (1 << k) == 0 { others.append(SIMD2(Double(dx), Double(dz))) }
        let corner = SIMD2<Double>(repeating: 0.5 - round)
        let g = fill(from: SIMD2(-0.5, -0.5), to: SIMD2(0.5, 0.5), step: 1.0 / 16) { p in
            // How far from the nearest square that is not the owner's, its corners rounded, less the inset: the
            // owner's squares run into one another and only its outer edges are drawn in.
            guard !others.isEmpty else { return 1 }
            return others.map { c -> Double in
                let q = simd_abs(p - c) - corner
                return simd_length(simd_max(q, SIMD2(repeating: 0))) + min(max(q.x, q.y), 0) - round
            }.min()! - inset
        }
        if let g { patches[key] = g }
        return g
    }
}

/// Smooth noise keyed to world position: the same place always gives the same value.
enum Noise {
    static func hash(_ x: Int, _ z: Int, seed: Int = 0) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ z &* 668_265_263 &+ seed &* 1_442_695_041))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double((h ^ (h >> 16)) & 0xFF_FFFF) / Double(0xFF_FFFF)
    }

    /// Value noise from 0 to 1, one feature a unit apart.
    static func value(_ p: SIMD2<Double>, seed: Int = 0) -> Double {
        let x0 = Int(floor(p.x)), z0 = Int(floor(p.y))
        let fx = p.x - floor(p.x), fz = p.y - floor(p.y)
        let sx = fx * fx * (3 - 2 * fx), sz = fz * fz * (3 - 2 * fz)
        let a = hash(x0, z0, seed: seed), b = hash(x0 + 1, z0, seed: seed)
        let c = hash(x0, z0 + 1, seed: seed), d = hash(x0 + 1, z0 + 1, seed: seed)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sz
    }

    /// A few octaves of value noise, from 0 to 1, features `scale` apart.
    static func fbm(_ p: SIMD2<Double>, scale: Double, seed: Int = 0) -> Double {
        var sum = 0.0, amp = 0.5, total = 0.0, q = p / scale
        for o in 0..<3 {
            sum += value(q, seed: seed + o * 101) * amp
            total += amp
            amp *= 0.5
            q *= 2.03
        }
        return sum / total
    }
}
