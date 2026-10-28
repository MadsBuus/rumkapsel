import AppKit
import SceneKit

enum Poster: String, CaseIterable {
    case yard, mission, rocket, crew, lounge, galley, bath, decon, shapes

    static func file(_ p: Poster) -> String { "poster-\(p.rawValue).jpg" }

    var title: String {
        switch self {
        case .yard: return "Pack, test, ship"
        case .mission: return "Eyes on the needles"
        case .rocket: return "Merge when it vents"
        case .crew: return "No cone? Your turn"
        case .lounge: return "Leisure is mandatory"
        case .galley: return "Printed fresh"
        case .bath: return "Squeaky clean, super keen"
        case .decon: return "Unknown objects"
        case .shapes: return "What's what"
        }
    }

    var lines: [String] {
        switch self {
        case .yard: return [
            "A merged pull request is a crate in storage.",
            "A staging release carries it to the testing rows, and a tester's tick to the cleared rows.",
            "The rocket takes everything on staging, tested or not. While it waits, arrows run from the untested crates.",
        ]
        case .mission: return [
            "Each repository has one status, the most urgent thing true of it: failing, holding, testing, ready, flying or calm.",
            "The busy ones get a gauge each, most urgent first; the calm ones sit small along the bottom.",
            "The alarm screen shows no signal until a source feeds it. Press M to stand on the bridge.",
        ]
        case .rocket: return [
            "The tip is the staging release: a drone welds it while staging deploys, its nose lamp blinking amber, then a green flash as staging goes live.",
            "The kick stage is the production release, raised under the tip when the release opens.",
            "It vents only when everything it ships is tested and it waits for nothing but the merge.",
        ]
        case .crew: return [
            "Every session is a minion. At work, its cone is the message it is working on.",
            "With no cone it is waiting for you, and paces its office.",
            "Quiet long enough, it rests: a couch by day, a bed by night.",
        ]
        case .lounge: return [
            "Hover a minion to hear what it is doing.",
            "A resting minion's bubble offers its next thing: the gym, a nap, a book, the shower, the toilet, a coffee or a bite.",
            "A busy one says it is busy, and with what.",
        ]
        case .galley: return [
            "The station keeps your clock.",
            "The galley prints a bite from 11 to 14 and 18 to 20, a coffee otherwise, and after desk work a minion now and then goes for one.",
            "Night is 22 to 07: the quiet ones sleep in the dorm.",
        ]
        case .bath: return [
            "A shower comes after twenty minutes or more of work: two to three minutes of water, then the towel.",
            "A pee comes after every second shorter stretch.",
            "Never while busy, carrying or in bed; work calling, it leaves at once.",
        ]
        case .decon: return [
            "A bot's pull request is not work: it drops into decon, small and dark, where you can see it pile up.",
            "Merged, it is carried into storage and ships like any crate, counted as tested.",
            "Closed, it is ejected and forgotten.",
        ]
        case .shapes: return [
            "A cube is a commit. A ghost cube is work not committed yet.",
            "A crate is a pull request. Its light blinks while checks run, then turns red or green.",
            "A cone is the message a minion is working on. A session waiting for you has none.",
        ]
        }
    }

    var setup: (words: String, tab: Int)? {
        switch self {
        case .yard, .rocket: return ("Its staging and how it ships, in Settings", 1)
        case .mission: return ("Feed the alarm screen: Monitors, in Settings", 4)
        case .crew: return ("When a quiet minion sleeps, in Settings", 0)
        case .shapes: return ("Your repositories, in Settings", 1)
        case .lounge, .galley, .bath, .decon: return nil
        }
    }

    private func room(_ st: Station) -> (inside: [Cell], area: Set<Cell>) {
        func fixed(_ key: String) -> (inside: [Cell], area: Set<Cell>) {
            let cells = st.rooms[key]?.cells ?? []
            return (cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }, Set(cells))
        }
        switch self {
        case .yard, .rocket, .decon: return ([], [])
        case .mission: return fixed("kind:mission")
        case .crew: return fixed("kind:quarters")
        case .lounge: return fixed("kind:lounge")
        case .galley: return fixed("kind:galley")
        case .bath: return fixed("kind:bath")
        case .shapes: return ([], Set(st.coreCells).subtracting([st.plan.monolith]))
        }
    }

    struct Spot: Hashable {
        let poster: Poster
        let cell: Cell
        let wall: SIMD2<Int>
    }

    static let reach = 6, apart = 2
    static let order: [Poster] = [.mission, .galley, .bath, .lounge, .crew, .shapes]
    static let backWall: [Poster] = [.rocket, .yard, .decon]

    static func hang(_ st: Station) -> [Spot] {
        let walk = st.walkable
        let hall = (st.corridorCells + st.coreCells).filter { $0 != st.plan.monolith }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let signs = Set(Signs.plan(st).map { [$0.cell.x, $0.cell.y, $0.wall.x, $0.wall.y] })
        let fixedRooms = st.rooms.filter { $0.key.hasPrefix("kind:") }
        let fixed = Set(fixedRooms.flatMap(\.value.cells) + st.hall.cells + st.hall.deconCells)
        var taken = Set(st.furniture(Looks.theme, offices: []).map(Station.cell(ofSub:)))
        for (key, room) in fixedRooms {
            for f in st.fixtures(in: key) { taken.insert(Cell(x: Int(f.at.x.rounded()), y: Int(f.at.y.rounded()))) }
            guard let door = st.doorCell(of: key) else { continue }
            taken.insert(door)
            if let far = room.cells.max(by: { (abs($0.x - door.x) + abs($0.y - door.y), $0.y, $0.x) < (abs($1.x - door.x) + abs($1.y - door.y), $1.y, $1.x) }) { taken.insert(far) }
        }
        let walls = [SIMD2(-1, 0), SIMD2(0, -1)]
        func shut(_ c: Cell, _ d: SIMD2<Int>) -> Bool {
            let n = Cell(x: c.x + d.x, y: c.y + d.y)
            return n != st.plan.monolith && !(walk.contains(n) && st.canStep(from: c, to: n)) && !signs.contains([c.x, c.y, d.x, d.y])
        }
        var spots: [Spot] = []
        func free(_ c: Cell) -> Bool { spots.allSatisfy { abs($0.cell.x - c.x) + abs($0.cell.y - c.y) >= apart } }
        for poster in order {
            let (inside, area) = poster.room(st)
            guard !area.isEmpty else { continue }
            var best: (score: [Int], spot: Spot)?
            func consider(_ score: [Int], _ c: Cell, _ d: SIMD2<Int>) {
                if best.map({ score.lexicographicallyPrecedes($0.score) }) ?? true { best = (score, Spot(poster: poster, cell: c, wall: d)) }
            }
            for c in inside where !taken.contains(c) && free(c) {
                for (k, d) in walls.enumerated() where shut(c, d) && !area.contains(Cell(x: c.x + d.x, y: c.y + d.y)) {
                    consider([0, k], c, d)
                }
            }
            if best == nil {
                for c in hall where free(c) {
                    let distance = area.map { abs($0.x - c.x) + abs($0.y - c.y) }.min() ?? .max
                    guard distance <= reach else { continue }
                    for (k, d) in walls.enumerated() where shut(c, d) && fixed.contains(Cell(x: c.x + d.x, y: c.y + d.y)) {
                        consider([1, area.contains(Cell(x: c.x + d.x, y: c.y + d.y)) ? 0 : 1, distance, k], c, d)
                    }
                }
            }
            if let best { spots.append(best.spot) }
        }
        return spots
    }

    static let root: URL? = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Posters"), FileManager.default.fileExists(atPath: r.path) { return r }
        return FileManager.default.fileExists(atPath: sourceRoot.path) ? sourceRoot : nil
    }()
    static let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Posters")

    private static var images: [Poster: NSImage] = [:]
    private static var wallImages: [Poster: NSImage] = [:]
    var wallImage: NSImage? {
        if let i = Poster.wallImages[self] { return i }
        guard let full = image else { return nil }
        let size = NSSize(width: 600, height: 800)
        let small = NSImage(size: size, flipped: false) { r in full.draw(in: r); return true }
        guard let tiff = small.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let i = NSImage(size: size)
        i.addRepresentation(rep)
        Poster.wallImages[self] = i
        return i
    }
    var image: NSImage? {
        if let i = Poster.images[self] { return i }
        guard let root = Poster.root, let i = NSImage(contentsOf: root.appendingPathComponent(Poster.file(self))) else { return nil }
        Poster.images[self] = i
        return i
    }
}

enum PosterOnWall {
    static let width = 0.36, height = 0.48, lift = 0.25

    static func node(_ spot: Poster.Spot, offset: SIMD2<Double>) -> SCNNode {
        let n = SCNNode()
        let face = PosterFace.node(spot.poster, width: width, height: height)
        face.position = v3(0, lift + height / 2, 0.012)
        n.addChildNode(face)
        let frame = SCNNode(geometry: SCNBox(width: width + 0.03, height: height + 0.03, length: 0.02, chamferRadius: 0.004))
        frame.geometry!.firstMaterial = Bulkhead.steel
        frame.position = v3(0, lift + height / 2, 0)
        n.addChildNode(frame)
        let p = SIMD2(Double(spot.wall.x), Double(spot.wall.y))
        let at = offset + SIMD2(Double(spot.cell.x), Double(spot.cell.y)) + p * (0.5 - WalkPieces.thickness / 2 - 0.03)
        n.position = v3(at.x, 0, at.y)
        n.eulerAngles.y = CGFloat(atan2(-p.x, -p.y))
        n.name = "poster:" + spot.poster.rawValue
        n.enumerateChildNodes { c, _ in c.name = n.name }
        return n
    }
}

enum PosterRow {
    static let width = 0.5, height = 0.667, gap = 0.16, lift = 0.62

    static func node(_ st: Station, offset: SIMD2<Double>) -> SCNNode? {
        let back = st.hall.backWall
        guard let x = back.first?.x, let y0 = back.map(\.y).min(), let y1 = back.map(\.y).max() else { return nil }
        let n = row()
        let at = offset + SIMD2(Double(x) - 0.5 + WalkPieces.thickness / 2 + 0.03, Double(y0 + y1) / 2)
        n.position = v3(at.x, 0, at.y)
        n.eulerAngles.y = .pi / 2
        return n
    }

    static func row() -> SCNNode {
        let n = SCNNode()
        let posters = Poster.backWall, pitch = width + gap
        for (i, poster) in posters.enumerated() {
            let along = (Double(posters.count - 1) / 2 - Double(i)) * pitch
            let frame = SCNNode(geometry: SCNBox(width: width + 0.03, height: height + 0.03, length: 0.02, chamferRadius: 0.004))
            frame.geometry!.firstMaterial = Bulkhead.steel
            frame.position = v3(along, lift + height / 2, 0)
            let face = PosterFace.node(poster, width: width, height: height)
            face.position = v3(along, lift + height / 2, 0.012)
            for part in [frame, face] {
                part.name = "poster:" + poster.rawValue
                n.addChildNode(part)
            }
        }
        return n
    }
}

enum PosterFace {
    static let rows = 32, every = 45.0, spread = 50.0, lasts = 0.6, chance = 0.6

    static func node(_ poster: Poster, width: Double, height: Double) -> SCNNode {
        let picture = strips(width: width, height: height)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = poster.wallImage ?? Palette.void
        m.diffuse.mipFilter = .linear
        let k = Double(Poster.allCases.firstIndex(of: poster) ?? 0)
        m.setValue(NSNumber(value: (k * 0.618034).truncatingRemainder(dividingBy: 1)), forKey: "seed")
        m.shaderModifiers = [
            .geometry: """
                #pragma arguments
                float seed;
                #pragma varyings
                float glitch;
                float roll;
                #pragma body
                float period = \(every) + seed * \(spread);
                float t = scn_frame.time + seed * 977.0;
                float cycle = floor(t / period);
                float u = t - cycle * period;
                float on = step(fract(sin(cycle * 12.9898 + seed * 78.233) * 43758.5453), \(chance)) * step(u, \(lasts));
                float g = on * sin(clamp(u / \(lasts), 0.0, 1.0) * 3.14159);
                float row = _geometry.texcoords[1].x;
                float tick = floor(scn_frame.time * 12.0);
                float tear = fract(sin(row * 3.7 + tick * 17.13 + seed * 91.7) * 43758.5453) - 0.5;
                _geometry.texcoords[0].x += tear * step(0.6, abs(tear) * 2.0) * 0.08 * g;
                out.glitch = g;
                out.roll = fract(scn_frame.time * 1.7);
                """,
            .fragment: """
                #pragma body
                float g = in.glitch;
                if (g > 0.001) {
                    float y = _surface.diffuseTexcoord.y;
                    float lines = 1.0 - 0.45 * g * step(0.5, fract(y * 220.0));
                    float flick = 1.0 + g * (fract(sin(floor(scn_frame.time * 30.0) * 7.31) * 43758.5453) - 0.5) * 0.7;
                    float bar = g * 0.35 * smoothstep(0.06, 0.0, abs(y - (1.0 - in.roll)));
                    float3 c = _output.color.rgb * lines * flick + bar;
                    _output.color.rgb = mix(c, c * float3(0.8, 1.05, 1.1), g);
                }
                """]
        picture.firstMaterial = m
        return SCNNode(geometry: picture)
    }

    private static func strips(width: Double, height: Double) -> SCNGeometry {
        var at: [SCNVector3] = [], uv: [CGPoint] = [], band: [CGPoint] = [], index: [Int32] = []
        for r in 0..<rows {
            let v0 = Double(r) / Double(rows), v1 = Double(r + 1) / Double(rows), base = Int32(at.count)
            for (x, v) in [(-0.5, v0), (0.5, v0), (0.5, v1), (-0.5, v1)] {
                at.append(v3(x * width, (0.5 - v) * height, 0))
                uv.append(CGPoint(x: x + 0.5, y: v))
                band.append(CGPoint(x: Double(r), y: 0))
            }
            index += [base, base + 2, base + 1, base, base + 3, base + 2]
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: at), SCNGeometrySource(textureCoordinates: uv), SCNGeometrySource(textureCoordinates: band)],
                           elements: [SCNGeometryElement(indices: index, primitiveType: .triangles)])
    }
}
