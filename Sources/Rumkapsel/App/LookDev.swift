import AppKit
import SceneKit
import Metal

enum LookDev {
    static func run(out: String, shot: String) -> Never {
        if shot == "crates" { crates(out: out) }
        if shot == "rockets" { rockets(out: out) }
        if shot == "signs" { signs(out: out) }
        if shot.hasPrefix("epic") { epic(out: out, shot: shot) }
        if shot == "poster:row" { image(out: out, PosterArt.object(PosterRow.row(), yaw: 0.35, pitch: -0.25, pixels: 1100, margin: 1.05)) }
        if shot.hasPrefix("poster:"), let p = Poster(rawValue: String(shot.dropFirst(7))) { poster(out: out, p) }
        if shot.hasPrefix("wall") {
            let parts = shot.split(separator: ":")
            let style = parts.count > 1 ? Bulkhead.Style(rawValue: String(parts[1])) ?? .hallway : .hallway
            walls(out: out, close: parts[0] == "wall-close", style: style)
        }
        let scene = SCNScene()
        scene.background.contents = NSColor(rgb: (0.015, 0.02, 0.035))
        scene.lightingEnvironment.contents = FlightCraft.environment
        let (lifter, tip) = FlightCraft.build(color: NSColor(rgb: (0.86, 0.38, 0.42)), repo: "web", release: "#9002")
        FlightCraft.mountCameras(lifter: lifter, tip: tip)
        scene.rootNode.addChildNode(lifter)
        scene.rootNode.addChildNode(tip)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1600
        sun.look(at: SCNVector3(-1, -0.3, -0.6))
        scene.rootNode.addChildNode(sun)
        let bounce = SCNNode(); bounce.light = SCNLight(); bounce.light!.type = .ambient; bounce.light!.intensity = 260
        scene.rootNode.addChildNode(bounce)

        let eye = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = 58; cam.zNear = 0.005; cam.zFar = 200
        FlightCraft.film(cam)
        eye.camera = cam
        switch shot {
        case "hull":
            eye.position = SCNVector3(0.42, 1.72, 0.32)
            eye.look(at: SCNVector3(0, 1.66, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        case "wide":
            eye.position = SCNVector3(2.4, 1.5, 1.9)
            eye.look(at: SCNVector3(0, 1.2, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        default:
            let name = shot + " cam"
            guard let mount = (tip.childNode(withName: name, recursively: true) ?? lifter.childNode(withName: name, recursively: true)) else {
                FileHandle.standardError.write("no shot \(shot)\n".data(using: .utf8)!); exit(1)
            }
            eye.simdTransform = mount.simdWorldTransform
        }
        scene.rootNode.addChildNode(eye)
        render(scene, from: eye, to: out)
    }

    private static func rockets(out: String) -> Never {
        let scene = SCNScene()
        scene.background.contents = NSColor(rgb: (0.06, 0.07, 0.1))
        let color = NSColor(rgb: (0.86, 0.38, 0.42))
        var row: [SCNNode] = [Props.rocket(color: color, tall: false), Props.rocket(color: color, tall: true)]
        for n in row { Props.nameRocket(n, repo: "tattoodo-web", color: color) }
        let flight = SCNNode()
        let (lifter, tip) = FlightCraft.build(color: color, repo: "tattoodo-web", release: "#9002")
        flight.addChildNode(lifter); flight.addChildNode(tip)
        flight.scale = SCNVector3(RocketGeometry.scale, RocketGeometry.scale, RocketGeometry.scale)
        row.append(flight)
        for out in [0.0, 1.0] {
            let alone = FlightCraft.build(color: color, repo: "tattoodo-web", release: "#9002").tip
            FlightCraft.feet(alone, out: out)
            let holder = SCNNode()
            holder.addChildNode(alone)
            holder.scale = SCNVector3(RocketGeometry.scale, RocketGeometry.scale, RocketGeometry.scale)
            holder.position = SCNVector3(0, (RocketShape.standDepth - RocketShape.split) * RocketGeometry.scale + (out == 0 ? 0.25 : 0), 0)
            let place = SCNNode()
            place.addChildNode(holder)
            row.append(place)
        }
        for (i, rocket) in row.enumerated() {
            rocket.position = SCNVector3(-1.6 + Double(i) * 0.8, 0, 0)
            scene.rootNode.addChildNode(rocket)
        }
        let floor = SCNNode(geometry: SCNPlane(width: 6, height: 2))
        floor.geometry!.firstMaterial = lit(NSColor(rgb: (0.2, 0.21, 0.24)))
        floor.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(floor)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1100
        sun.look(at: SCNVector3(-1, -0.8, -0.6))
        scene.rootNode.addChildNode(sun)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient; fill.light!.intensity = 450
        scene.rootNode.addChildNode(fill)
        let eye = SCNNode()
        eye.camera = SCNCamera()
        eye.camera!.fieldOfView = 40
        eye.position = SCNVector3(0, 1.3, 4.6)
        eye.look(at: SCNVector3(0, 1.0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(eye)
        render(scene, from: eye, to: out)
    }

    private static func poster(out: String, _ poster: Poster) -> Never { image(out: out, PosterArt.draw(poster)) }

    private static func image(out: String, _ image: NSImage) -> Never {
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: out))
        exit(0)
    }

    private static func render(_ scene: SCNScene, from eye: SCNNode, to out: String) -> Never {
        let image = PosterArt.snapshot(scene, from: eye, size: CGSize(width: 1600, height: 1000))
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: out))
        exit(0)
    }

    private static func signs(out: String) -> Never {
        Bulkhead.prepareNow()
        let scene = SCNScene()
        scene.background.contents = NSColor(rgb: (0.015, 0.02, 0.035))
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 700
        sun.eulerAngles = v3(-.pi / 3, .pi / 3, 0)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 550
        scene.rootNode.addChildNode(ambient)
        let floor = SCNNode(geometry: SCNPlane(width: 6, height: 3))
        floor.geometry!.firstMaterial = flat(NSColor(rgb: (0.42, 0.33, 0.27)))
        floor.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(floor)
        let sign = Signs.Sign(cell: Cell(x: 0, y: 0), wall: SIMD2(0, -1), ways: [(.left, ["Launch", "Storage", "Staging", "Bath"]), (.back, ["Dorm", "Gym"]),
                                                                               (.right, ["Monolith"])])
        let box = SCNBox(width: 1, height: Walker.wallHeight, length: 0.07, chamferRadius: 0)
        var faces = Array(repeating: Bulkhead.steel, count: 6)
        faces[0] = Bulkhead.material(0, style: .hallway)
        box.materials = faces
        let wall = SCNNode(geometry: box)
        wall.position = v3(0, Walker.wallHeight / 2, -0.5)
        scene.rootNode.addChildNode(wall)
        let (panel, arrows) = Signs.panel(sign)
        Signs.roll(arrows, at: 0.3)
        panel.position = v3(0, 0.47, -0.5 + 0.039)
        scene.rootNode.addChildNode(panel)
        let eye = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = 68; cam.zNear = 0.02; cam.zFar = 50
        FlightCraft.film(cam)
        cam.exposureOffset = -0.45
        cam.bloomThreshold = 1.4
        eye.camera = cam
        eye.position = v3(0, 0.42, 0.55)
        eye.look(at: v3(0, 0.42, -0.5), up: v3(0, 1, 0), localFront: v3(0, 0, -1))
        scene.rootNode.addChildNode(eye)
        render(scene, from: eye, to: out)
    }

    private static func epic(out: String, shot: String) -> Never {
        Bulkhead.prepareNow()
        let scene = SCNScene()
        scene.background.contents = NSColor(rgb: (0.015, 0.02, 0.035))
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 700
        sun.eulerAngles = v3(-.pi / 3, .pi / 3, 0)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 550
        scene.rootNode.addChildNode(ambient)
        let repo = NSColor(Colors.repos[1])
        let world = World(demo: true)
        let station = world.fleet.station("work")
        let key = "task:web#5770"
        _ = station.ensureRoom(key: key, name: "#5770", repo: "web", color: Colors.repos[1], lastActive: Date())
        let epic = OfficeFact.Epic(shipped: 7)
        station.show(epics: [key: epic])
        guard let room = station.rooms[key], let console = station.planningConsole(key), let seat = console.place(0) else { exit(1) }
        let o = station.offset
        func flat(_ c: Cell) -> SIMD2<Double> { SIMD2(o.x + Double(c.x), o.y + Double(c.y)) }
        let cells = Set(room.cells)
        let door = station.doorCell(of: key), outside = station.doorOutside(of: key)
        let behind = -SIMD2(sin(console.yaw), cos(console.yaw))
        for c in room.cells {
            let tile = SCNNode(geometry: SCNBox(width: 0.96, height: 0.02, length: 0.96, chamferRadius: 0.01))
            tile.geometry!.firstMaterial = lit(repo.blended(withFraction: 0.72, of: NSColor(rgb: (0.2, 0.2, 0.22)))!)
            tile.position = v3(flat(c).x, -0.01, flat(c).y)
            scene.rootNode.addChildNode(tile)
            for (k, d) in [(0, 1), (0, -1), (1, 0), (-1, 0)].enumerated() {
                let n = Cell(x: c.x + d.0, y: c.y + d.1)
                guard !cells.contains(n), !(c == door && n == outside), shot != "epic-far" else { continue }
                let toward = SIMD2(Double(d.0), Double(d.1))
                guard simd_dot(toward, behind) > 0.1 else { continue }
                let mid = (flat(c) + flat(n)) / 2
                let box = SCNBox(width: d.0 == 0 ? 1 : 0.07, height: Walker.wallHeight, length: d.0 == 0 ? 0.07 : 1, chamferRadius: 0)
                var faces = Array(repeating: Bulkhead.steel, count: 6)
                for f in 0..<4 { faces[f] = Bulkhead.material(k + f, style: .office) }
                box.materials = faces
                let wall = SCNNode(geometry: box)
                wall.position = v3(mid.x, Walker.wallHeight / 2, mid.y)
                scene.rootNode.addChildNode(wall)
            }
        }
        if let outside {
            let hall = SCNNode(geometry: SCNBox(width: 0.96, height: 0.02, length: 0.96, chamferRadius: 0.01))
            hall.geometry!.firstMaterial = lit(NSColor(rgb: (0.42, 0.33, 0.27)))
            hall.position = v3(flat(outside).x, -0.012, flat(outside).y)
            scene.rootNode.addChildNode(hall)
        }
        let f = Classic.epic(room, in: station, epic: epic, color: repo)
        for n in f.props + f.fixtures { scene.rootNode.addChildNode(n) }
        let sat = seat.sitting(10, of: 20)
        if !shot.hasSuffix("-work"), let chair = f.chairs.values.first { Classic.recline(chair, by: Minion.recline) }
        let m = Minion(id: "resident", station: "look", home: Home(key: "x", name: "x", repo: "x", issue: nil), cwd: "", toolCount: 0,
                       isSubagent: false, start: Cell(x: 0, y: 0))
        m.wearSuit(badge: repo)
        m.node.opacity = 1
        m.setPose(shot.hasSuffix("-work") ? .seated(height: Seat.height) : .reclined(height: Seat.height), atOnce: true)
        m.node.position = v3(o.x + sat.pos.x, 0, o.y + sat.pos.y)
        m.node.eulerAngles.y = CGFloat(sat.facing)
        scene.rootNode.addChildNode(m.node)
        if let cell = station.farCells(room).first {
            let crate = Props.package(color: repo, band: NSColor(rgb: (0.4, 0.82, 0.45)), size: Zone.waiting.crateSize, mine: true, number: 5778,
                                      title: "Station rental tables", who: "Mads")
            crate.position = v3(flat(cell).x, 0, flat(cell).y)
            scene.rootNode.addChildNode(crate)
        }
        let mid = room.cells.reduce(SIMD2<Double>(0, 0)) { $0 + flat($1) } / Double(room.cells.count)
        let aim = SIMD2(o.x + console.at.x, o.y + console.at.y)

        let eye = SCNNode()
        let cam = SCNCamera()
        cam.zNear = 0.02; cam.zFar = 200
        let inward = SIMD2(sin(console.yaw), cos(console.yaw))
        if shot == "epic-side" {
            cam.fieldOfView = 40
            let side = SIMD2(inward.y, -inward.x)
            eye.position = v3(aim.x + side.x * 2.2, 0.5, aim.y + side.y * 2.2)
            eye.look(at: v3(aim.x, 0.25, aim.y), up: v3(0, 1, 0), localFront: v3(0, 0, -1))
        } else if shot == "epic-far" {
            cam.usesOrthographicProjection = true
            cam.orthographicScale = 2.2
            let pitch = Double.pi / 5, yaw = Double.pi / 4, d = 40.0
            eye.position = v3(mid.x + d * cos(pitch) * sin(yaw), d * sin(pitch), mid.y + d * cos(pitch) * cos(yaw))
            eye.look(at: v3(mid.x, 0.2, mid.y), up: v3(0, 1, 0), localFront: v3(0, 0, -1))
        } else {
            cam.fieldOfView = 46
            FlightCraft.film(cam)
            cam.exposureOffset = -0.3
            cam.bloomThreshold = 1.4
            let from = aim + inward * 2.6 + SIMD2(inward.y, -inward.x) * 1.0
            eye.position = v3(from.x, 1.6, from.y)
            eye.look(at: v3(aim.x + inward.x * 0.5, 0.3, aim.y + inward.y * 0.5), up: v3(0, 1, 0), localFront: v3(0, 0, -1))
        }
        eye.camera = cam
        scene.rootNode.addChildNode(eye)
        render(scene, from: eye, to: out)
    }

    private static func crates(out: String) -> Never {
        let scene = SCNScene()
        scene.background.contents = NSColor(rgb: (0.015, 0.02, 0.035))
        let floor = SCNNode(geometry: SCNPlane(width: 6, height: 3))
        floor.geometry!.firstMaterial = flat(NSColor(rgb: (0.42, 0.33, 0.27)))
        floor.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(floor)
        let kinds: [Detail.Kind] = Detail.crates
        let titles = ["Stop paying the referrer booking reward from PHP", "Dismiss the new-admin wall per page load only",
                      "Newsroom image uploads store absolute CDN URLs", "Booking flow keeps the artist's deposit rules",
                      "Artist search ranks by recent work", "Settlement exports in the partner's currency"]
        for (k, kind) in kinds.enumerated() {
            let image = Detail.fresh(kind)
            let c = Props.package(color: NSColor(rgb: (0.93, 0.5, 0.2)), band: NSColor(rgb: (0.4, 0.82, 0.45)), size: 0.38, number: 455 + k,
                                  title: titles[k], who: ["Mads", "Kim", "Don", "Mads", "Kim", "Don"][k])
            c.enumerateChildNodes { n, _ in
                guard let b = n.geometry as? SCNBox, b.width > 0.3, b.height > 0.25 else { return }
                for m in b.materials { m.multiply.contents = image }
            }
            c.position = v3(Double(k % 3) * 0.62 - 0.62, 0, Double(k / 3) * 0.75 - 0.6)
            c.eulerAngles.y = -0.35
            scene.rootNode.addChildNode(c)
            let label = SCNNode(geometry: SCNText(string: kind.rawValue, extrusionDepth: 0))
            (label.geometry as! SCNText).font = NSFont.systemFont(ofSize: 1)
            label.geometry!.firstMaterial = flat(.white)
            label.scale = SCNVector3(0.06, 0.06, 0.06)
            label.position = v3(Double(k % 3) * 0.62 - 0.72, 0.005, Double(k / 3) * 0.75 - 0.26)
            label.eulerAngles.x = -.pi / 2
            scene.rootNode.addChildNode(label)
        }
        let eye = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = 50; cam.zNear = 0.02; cam.zFar = 50
        FlightCraft.film(cam)
        cam.exposureOffset = -0.45
        eye.camera = cam
        eye.position = v3(0, 0.75, 1.65)
        eye.look(at: v3(0, 0.1, -0.3), up: v3(0, 1, 0), localFront: v3(0, 0, -1))
        scene.rootNode.addChildNode(eye)
        render(scene, from: eye, to: out)
    }

    private static func walls(out: String, close: Bool, style: Bulkhead.Style) -> Never {
        Bulkhead.prepareNow()
        let scene = SCNScene()
        scene.background.contents = NSColor(rgb: (0.015, 0.02, 0.035))
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 700
        sun.eulerAngles = v3(-.pi / 3, .pi / 3, 0)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 550
        scene.rootNode.addChildNode(ambient)
        let floor = SCNNode(geometry: SCNPlane(width: 12, height: 3))
        floor.geometry!.firstMaterial = lit(NSColor(rgb: (0.42, 0.33, 0.27)))
        floor.eulerAngles.x = -.pi / 2
        floor.position = v3(2, 0, 0)
        scene.rootNode.addChildNode(floor)
        let t = 0.07, length = 5
        for side in [-1.0, 1.0] {
            for k in 0..<length where !(side > 0 && k == 3) {
                let box = SCNBox(width: 1, height: Walker.wallHeight, length: t, chamferRadius: 0)
                let variant = (k * 3 + (side > 0 ? 1 : 0)) % Bulkhead.count
                var faces = Array(repeating: Bulkhead.steel, count: 6)
                faces[side > 0 ? 2 : 0] = Bulkhead.material(variant, style: style)
                faces[side > 0 ? 0 : 2] = Bulkhead.material((variant + 2) % Bulkhead.count, style: style)
                box.materials = faces
                let wall = SCNNode(geometry: box)
                wall.position = v3(Double(k) + 0.5, Walker.wallHeight / 2, side * 0.5)
                scene.rootNode.addChildNode(wall)
                let cap = Bulkhead.cap(length: 1, thickness: t, across: false)
                cap.position = v3(Double(k) + 0.5, 0, side * 0.5)
                scene.rootNode.addChildNode(cap)
            }
            for x in [0.0, 3.0, 4.0, 5.0] where side > 0 || x == 0 || x == 5 {
                let p = Bulkhead.pilaster(seed: Int(x) * 5)
                p.position = v3(x, 0, side * 0.5)
                scene.rootNode.addChildNode(p)
            }
        }
        let eye = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = 68; cam.zNear = 0.02; cam.zFar = 200
        FlightCraft.film(cam)
        cam.exposureOffset = -0.45
        cam.bloomThreshold = 1.4
        eye.camera = cam
        if close {
            eye.position = v3(1.2, 0.42, 0.05)
            eye.look(at: v3(2.0, 0.36, -0.5), up: v3(0, 1, 0), localFront: v3(0, 0, -1))
        } else {
            eye.position = v3(-0.4, 0.4, 0.08)
            eye.look(at: v3(4, 0.3, -0.05), up: v3(0, 1, 0), localFront: v3(0, 0, -1))
        }
        scene.rootNode.addChildNode(eye)
        render(scene, from: eye, to: out)
    }
}
