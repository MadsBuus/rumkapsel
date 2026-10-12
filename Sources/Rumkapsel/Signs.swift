import AppKit
import SceneKit

enum Signs {
    enum Turn: Int, Comparable {
        case left, back, right
        static func < (a: Turn, b: Turn) -> Bool { a.rawValue < b.rawValue }
        var arrow: String { ["←", "↓", "→"][rawValue] }
    }

    struct Sign {
        let cell: Cell
        let wall: SIMD2<Int>
        let ways: [(turn: Turn, places: [String])]
    }

    static func places(_ st: Station) -> [(name: String, cells: Set<Cell>)] {
        let v = Words.current
        var out: [(String, Set<Cell>)] = [
            (v.bay, Set(st.hangarCells)), (v.pad, Set(st.hall.padCells)), (v.storage, Set(st.hall.storageCells)),
            (v.deck, Set(st.hall.deckCells)), (v.monolith, Set(st.coreCells)),
        ]
        for (key, name) in [("kind:quarters", v.dorm), ("kind:lounge", v.lounge), ("kind:bath", v.bath), ("kind:gym", v.gym)] {
            if let room = st.rooms[key] { out.append((name, Set(room.cells))) }
        }
        return out.filter { !$0.1.isEmpty }.map { (name: $0.0.prefix(1).uppercased() + $0.0.dropFirst(), cells: $0.1) }
    }

    static let spacing = 4

    static func plan(_ st: Station) -> [Sign] {
        let walk = st.walkable
        let hall = Set(st.corridorCells + st.coreCells).subtracting([st.plan.monolith])
        let core = Set(st.coreCells).subtracting([st.plan.monolith])
        let steps = [SIMD2(1, 0), SIMD2(-1, 0), SIMD2(0, 1), SIMD2(0, -1)]
        func at(_ c: Cell, _ d: SIMD2<Int>) -> Cell { Cell(x: c.x + d.x, y: c.y + d.y) }
        func open(_ c: Cell, _ d: SIMD2<Int>) -> Bool { let n = at(c, d); return walk.contains(n) && st.canStep(from: c, to: n) }
        func wall(_ c: Cell, _ d: SIMD2<Int>) -> Bool { !open(c, d) && at(c, d) != st.plan.monolith }
        func arms(_ c: Cell) -> Int { steps.filter { open(c, $0) && hall.contains(at(c, $0)) }.count }
        func doors(_ c: Cell) -> Int { steps.filter { open(c, $0) }.count }
        let home = Words.current.monolith.prefix(1).uppercased() + Words.current.monolith.dropFirst()
        let places = places(st).filter { $0.name != home }
        let plazaCells = core

        func turn(_ w: SIMD2<Int>, facing d: SIMD2<Int>) -> Turn? {
            w == SIMD2(d.y, -d.x) ? .left : w == SIMD2(-d.y, d.x) ? .right : w == SIMD2(-d.x, -d.y) ? .back : nil
        }
        func step(_ a: Cell, _ b: Cell) -> SIMD2<Int> { SIMD2(b.x - a.x, b.y - a.y) }

        var parent: [Cell: Cell] = [:], seen = plazaCells, frontier = plazaCells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        while !frontier.isEmpty {
            var next: [Cell] = []
            for c in frontier {
                for d in steps where open(c, d) && !seen.contains(at(c, d)) { seen.insert(at(c, d)); parent[at(c, d)] = c; next.append(at(c, d)) }
            }
            frontier = next
        }
        func depth(_ x: Cell) -> Int { var n = 0, y = x; while let up = parent[y] { y = up; n += 1 }; return n }
        var routes: [(name: String, path: [Cell])] = []
        for p in places {
            guard var c = p.cells.filter({ seen.contains($0) }).min(by: { (depth($0), $0.y, $0.x) < (depth($1), $1.y, $1.x) }) else { continue }
            var path = [c]
            while let up = parent[c] { path.append(up); c = up }
            routes.append((p.name, path.reversed()))
        }
        let main = Set(routes.flatMap(\.path))

        var plazaSigns: [Sign] = [], forks: [Sign] = [], backs: [Sign] = []
        var leaving: [Cell: [SIMD2<Int>: [String]]] = [:]
        for r in routes {
            guard let k = r.path.firstIndex(where: { !core.contains($0) }), k > 0 else { continue }
            leaving[r.path[k - 1], default: [:]][step(r.path[k - 1], r.path[k]), default: []].append(r.name)
        }
        for e in leaving.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            for d in steps {
                guard let names = leaving[e]?[d] else { continue }
                for side in [SIMD2(d.y, -d.x), SIMD2(-d.y, d.x)] where core.contains(at(e, side)) && wall(at(e, side), d) {
                    guard let t = turn(SIMD2(-side.x, -side.y), facing: d) else { continue }
                    plazaSigns.append(Sign(cell: at(e, side), wall: d, ways: [(turn: t, places: names)]))
                    break
                }
            }
        }
        for j in hall.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) where !core.contains(j) && (main.contains(j) ? arms(j) : doors(j)) >= 3 {
            guard let up = parent[j] else { continue }
            let back = step(j, up), coming = SIMD2(-back.x, -back.y)
            let walls = [coming, SIMD2(coming.y, -coming.x), SIMD2(-coming.y, coming.x)].filter { wall(j, $0) }
            if main.contains(j) {
                var onward: [SIMD2<Int>: [String]] = [:]
                for r in routes { if let i = r.path.firstIndex(of: j), i + 1 < r.path.count { onward[step(j, r.path[i + 1]), default: []].append(r.name) } }
                guard onward.count >= 2 else { continue }
                for d in walls {
                    var ways: [Turn: [String]] = [:]
                    for (w, names) in onward { if let t = turn(w, facing: d) { ways[t, default: []] += names } }
                    if let t = turn(back, facing: d) { ways[t, default: []].append(home) }
                    guard ways.count >= 2 else { continue }
                    forks.append(Sign(cell: j, wall: d, ways: ways.sorted { $0.key < $1.key }.map { (turn: $0.key, places: $0.value) }))
                    break
                }
            } else {
                for d in steps where wall(j, d) {
                    guard let t = turn(back, facing: d), t != .back else { continue }
                    backs.append(Sign(cell: j, wall: d, ways: [(turn: t, places: [home])]))
                    break
                }
            }
        }
        var out = plazaSigns + forks
        for s in backs where out.allSatisfy({ abs($0.cell.x - s.cell.x) + abs($0.cell.y - s.cell.y) >= spacing }) { out.append(s) }
        return out
    }
}

enum SignArt {
    static let red = NSColor(rgb: (1.0, 0.24, 0.16)), amber = NSColor(rgb: (1.0, 0.68, 0.18))
    static let train = 2.4

    static func lines(_ sign: Signs.Sign) -> [(turn: Signs.Turn?, text: String)] {
        sign.ways.flatMap { way in
            Swift.stride(from: 0, to: way.places.count, by: 2).map { k in
                (turn: way.turn, text: way.places[k..<min(k + 2, way.places.count)].joined(separator: " · ").uppercased())
            }
        }
    }

    static func image(_ lines: [(turn: Signs.Turn?, text: String)], width: Double, height: Double) -> NSImage {
        let pw = 1024, ph = Int(1024 * height / width)
        let face = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        return Textures.draw(pw, ph) { ctx, w, h in
            let row = h / (CGFloat(lines.count) + 0.9)
            let room = w - row * (train + 0.35) - w * 0.15
            var size = row * 0.58
            let widest = lines.map { NSAttributedString(string: $0.text, attributes: [.font: NSFont(descriptor: face.fontDescriptor, size: size) ?? face,
                                                                                    .kern: size * 0.06]).size().width }.max() ?? 0
            if widest > room { size *= room / widest }
            let type = NSFont(descriptor: face.fontDescriptor, size: size) ?? face
            let screen = NSRect(x: 0, y: 0, width: w, height: h)
            ctx.saveGState()
            NSBezierPath(roundedRect: screen, xRadius: 10, yRadius: 10).addClip()
            let dark = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [NSColor(rgb: (0.07, 0.06, 0.06)).cgColor, NSColor(rgb: (0.01, 0.01, 0.01)).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(dark, startCenter: CGPoint(x: screen.midX, y: screen.midY), startRadius: 0,
                                   endCenter: CGPoint(x: screen.midX, y: screen.midY), endRadius: screen.width * 0.62, options: [.drawsAfterEndLocation])
            func glow(_ c: NSColor) -> NSShadow {
                let g = NSShadow(); g.shadowColor = c.withAlphaComponent(0.85); g.shadowBlurRadius = size * 0.35; g.shadowOffset = .zero
                return g
            }
            for (k, line) in lines.enumerated() {
                let y = row * (0.4 + CGFloat(k)), x0 = w * 0.05
                NSAttributedString(string: line.text, attributes: [.font: type, .foregroundColor: red, .kern: size * 0.06, .shadow: glow(red)])
                    .draw(at: NSPoint(x: x0 + row * (train + 0.35), y: y + row * 0.14))
            }
            NSColor(white: 0, alpha: 0.38).setFill()
            var sy = screen.minY
            while sy < screen.maxY { NSBezierPath(rect: NSRect(x: screen.minX, y: sy, width: screen.width, height: 2)).fill(); sy += 5 }
            ctx.restoreGState()
        }
    }
}

extension Signs {
    struct Arrow { let node: SCNNode; let from: SIMD2<Double>; let to: SIMD2<Double>; let phase: Double }

    static func panel(_ sign: Sign) -> (node: SCNNode, arrows: [Arrow]) {
        let lines = SignArt.lines(sign)
        let width = 0.5, height = 0.05 + 0.055 * Double(lines.count)
        let image = SignArt.image(lines, width: width, height: height)
        let plane = SCNPlane(width: width, height: height)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.emission.contents = image
        m.diffuse.mipFilter = .linear
        m.transparencyMode = .aOne
        plane.firstMaterial = m
        plane.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: 5)]
        let node = SCNNode(geometry: plane)
        node.renderingOrder = 50
        var arrows: [Arrow] = []
        let row = height / (Double(lines.count) + 0.9), glyph = row * 0.9
        let x0 = -width / 2 + width * 0.04, span = row * SignArt.train
        for (k, line) in lines.enumerated() {
            guard let turn = line.turn else { continue }
            let y = height / 2 - row * (0.4 + Double(k) + 0.48)
            for i in 0..<3 {
                let face = SCNPlane(width: glyph, height: glyph)
                face.firstMaterial = arrowFace(turn)
                face.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: 5)]
                let a = SCNNode(geometry: face)
                a.renderingOrder = 51
                node.addChildNode(a)
                let left = SIMD2(x0 + glyph / 2, y), right = SIMD2(x0 + span - glyph / 2, y)
                switch turn {
                case .left: arrows.append(Arrow(node: a, from: right, to: left, phase: Double(i) / 3))
                case .right: arrows.append(Arrow(node: a, from: left, to: right, phase: Double(i) / 3))
                case .back:
                    let x = x0 + glyph / 2 + (span - glyph) * Double(i) / 2
                    arrows.append(Arrow(node: a, from: SIMD2(x, y + row * 0.2), to: SIMD2(x, y - row * 0.2), phase: Double(i) / 3))
                }
            }
        }
        roll(arrows, at: 0)
        return (node, arrows)
    }

    static func roll(_ arrows: [Arrow], at clock: Double) {
        for a in arrows {
            let t = (clock * 0.8 + a.phase).truncatingRemainder(dividingBy: 1)
            let p = a.from + (a.to - a.from) * t
            a.node.position = v3(p.x, p.y, 0.001)
            a.node.opacity = CGFloat(sin(.pi * t))
        }
    }

    private static var arrowFaces: [Turn: SCNMaterial] = [:]
    private static func arrowFace(_ turn: Turn) -> SCNMaterial {
        if let m = arrowFaces[turn] { return m }
        let image = Textures.draw(128, 128) { _, w, h in
            let glow = NSShadow(); glow.shadowColor = SignArt.amber.withAlphaComponent(0.85); glow.shadowBlurRadius = 12; glow.shadowOffset = .zero
            let arrow = NSAttributedString(string: turn.arrow, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 92, weight: .heavy),
                                                                            .foregroundColor: SignArt.amber, .shadow: glow])
            let a = arrow.size()
            arrow.draw(at: NSPoint(x: (w - a.width) / 2, y: (h - a.height) / 2))
        }
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.emission.contents = image
        m.transparencyMode = .aOne
        m.writesToDepthBuffer = false
        arrowFaces[turn] = m
        return m
    }
}
