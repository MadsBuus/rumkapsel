import AppKit
import SceneKit

enum MissionRoom {
    enum Style: String, CaseIterable { case apollo, nasa, spacex, bridge, ops }

    static let width = 5.0, depth = 3.0
    static let aisle = 4.35
    private static let wall = Walker.wallHeight

    static func build(_ style: Style) -> SCNNode {
        let room = SCNNode()
        let p = Palette.of(style)
        room.addChildNode(box(width, 0.02, depth, lit(p.floor), at: v3(width / 2, -0.01, depth / 2)))
        for x in stride(from: 1.0, to: width, by: 1) {
            room.addChildNode(box(0.008, 0.002, depth, flat(p.seam), at: v3(x, 0.001, depth / 2)))
        }
        room.addChildNode(box(width, wall, 0.07, lit(p.wall), at: v3(width / 2, wall / 2, 0)))
        room.addChildNode(box(0.07, wall, depth, lit(p.wall), at: v3(0, wall / 2, depth / 2)))
        windowWall(room, p)
        switch style {
        case .apollo: apollo(room, p)
        case .nasa: nasa(room, p)
        case .spacex: spacex(room, p)
        case .bridge: bridge(room, p)
        case .ops: ops(room, p)
        }
        return room
    }

    // MARK: Apollo, 1960s: tiered rows of consoles before a wall of projection screens

    private static func apollo(_ room: SCNNode, _ p: Palette) {
        let front = SCNNode()
        front.position = v3(width / 2, 0, 0.05)
        room.addChildNode(front)
        front.addChildNode(screen(1.5, 0.42, Screens.map(trajectory: true), at: v3(0, 0.45, 0.02)))
        for side in [-1.0, 1.0] {
            front.addChildNode(screen(0.62, 0.26, Screens.plot(p.glow, rows: 3), at: v3(side * 1.18, 0.52, 0.02)))
            front.addChildNode(screen(0.62, 0.14, Screens.table(p.glow), at: v3(side * 1.18, 0.27, 0.02)))
        }
        front.addChildNode(screen(1.5, 0.06, Screens.clock("T+ 04:12:36"), at: v3(0, 0.17, 0.02)))
        for (i, z) in [0.95, 1.65, 2.35].enumerated() {
            let rise = Double(i) * 0.05
            if rise > 0 { room.addChildNode(box(aisle - 0.05, rise, 0.7, lit(p.trim), at: v3((aisle - 0.05) / 2 + 0.035, rise / 2, z + 0.12))) }
            let seats = i == 0 ? 3 : 4
            for k in 0..<seats {
                let x = 0.55 + Double(k) * 0.98 + (i == 0 ? 0.49 : 0)
                let console = apolloConsole(p)
                console.position = v3(x, rise, z)
                room.addChildNode(console)
                if (k + i) % 2 == 0 { room.addChildNode(seated(at: v3(x, rise, z + 0.33), facing: 0)) }
            }
        }
    }

    static func apolloConsole(_ p: Palette) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(box(0.86, 0.2, 0.26, lit(p.console), at: v3(0, 0.1, 0), chamfer: 0.01))
        let slope = box(0.86, 0.012, 0.16, lit(p.console.blended(withFraction: 0.2, of: .white)!), at: v3(0, 0.215, 0.05))
        slope.eulerAngles.x = 0.35
        n.addChildNode(slope)
        n.addChildNode(box(0.86, 0.16, 0.12, lit(p.console), at: v3(0, 0.3, -0.07), chamfer: 0.01))
        for k in 0..<3 {
            let x = -0.27 + Double(k) * 0.27
            n.addChildNode(box(0.17, 0.12, 0.006, flat(NSColor(rgb: (0.05, 0.08, 0.06))), at: v3(x, 0.31, -0.008)))
            n.addChildNode(screen(0.14, 0.09, Screens.table(p.glow), at: v3(x, 0.31, -0.012), bezel: 0.004))
        }
        let colors = [NSColor(rgb: (0.92, 0.35, 0.3)), NSColor(rgb: (0.95, 0.82, 0.35)), NSColor(rgb: (0.92, 0.93, 0.9)), NSColor(rgb: (0.4, 0.8, 0.55))]
        for r in 0..<2 {
            for c in 0..<11 {
                let key = box(0.028, 0.008, 0.02, flat(colors[(r * 3 + c * 7) % colors.count]), at: v3(-0.35 + Double(c) * 0.07, 0.226 + Double(r) * 0.012, 0.03 + Double(r) * 0.035))
                key.eulerAngles.x = 0.35
                n.addChildNode(key)
            }
        }
        return n
    }

    // MARK: Modern NASA: curved desks, several flat monitors per seat, a wide video wall

    private static func nasa(_ room: SCNNode, _ p: Palette) {
        let front = SCNNode()
        front.position = v3(width / 2, 0, 0.05)
        room.addChildNode(front)
        for k in 0..<6 {
            let x = -1.9 + Double(k) * 0.76
            let image: NSImage = k == 2 || k == 3 ? Screens.map(trajectory: k == 2) : k % 2 == 0 ? Screens.plot(p.glow, rows: 2) : Screens.table(p.glow)
            front.addChildNode(screen(0.74, 0.4, image, at: v3(x, 0.47, 0.02), bezel: 0.008))
        }
        front.addChildNode(screen(3.8, 0.05, Screens.clock("GMT 294:13:42:07     MET 004/02:11:36"), at: v3(0, 0.2, 0.02), bezel: 0.006))
        for (i, z) in [1.15, 2.1].enumerated() {
            let rise = Double(i) * 0.04
            if rise > 0 { room.addChildNode(box(aisle - 0.05, rise, 0.85, lit(p.floor.blended(withFraction: 0.12, of: .white)!), at: v3((aisle - 0.05) / 2 + 0.035, rise / 2, z + 0.1))) }
            let arc = SCNNode()
            arc.position = v3(aisle / 2, rise, z - 2.6)
            room.addChildNode(arc)
            for k in 0..<4 {
                let a = (Double(k) - 1.5) * 0.19
                let desk = nasaDesk(p)
                desk.position = v3(sin(a) * 2.6, 0, cos(a) * 2.6)
                desk.eulerAngles.y = CGFloat(a)
                arc.addChildNode(desk)
                if k != 1 || i == 1 { arc.addChildNode(seated(at: v3(sin(a) * 2.92, 0, cos(a) * 2.92), facing: a)) }
            }
        }
    }

    private static func nasaDesk(_ p: Palette) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(box(0.82, 0.19, 0.26, lit(p.console), at: v3(0, 0.095, 0), chamfer: 0.012))
        n.addChildNode(box(0.86, 0.02, 0.32, lit(p.trim), at: v3(0, 0.2, 0.02), chamfer: 0.008))
        for k in 0..<3 {
            let x = -0.25 + Double(k) * 0.25
            let mon = screen(0.21, 0.13, k == 1 ? Screens.plot(p.glow, rows: 2) : Screens.table(p.glow), at: v3(x, 0.3, -0.06), bezel: 0.008)
            mon.eulerAngles.y = CGFloat(-Double(k - 1) * 0.25)
            n.addChildNode(mon)
            n.addChildNode(box(0.02, 0.06, 0.02, lit(p.dark), at: v3(x, 0.24, -0.07)))
        }
        n.addChildNode(box(0.18, 0.006, 0.06, lit(p.dark), at: v3(0, 0.213, 0.09)))
        return n
    }

    // MARK: SpaceX: a bright open floor, long straight rows, stacked monitors, screens hung overhead

    private static func spacex(_ room: SCNNode, _ p: Palette) {
        for (k, x) in [0.95, 2.5, 4.05].enumerated() {
            let hang = screen(1.3, 0.4, k == 1 ? Screens.map(trajectory: true) : Screens.camera(), at: v3(x, 0.98, 0.3), bezel: 0.012)
            hang.eulerAngles.x = 0.15
            room.addChildNode(hang)
            for side in [-1.0, 1.0] { room.addChildNode(box(0.006, 0.32, 0.006, flat(p.dark), at: v3(x + side * 0.6, 1.36, 0.28))) }
        }
        for (r, z) in [1.0, 1.75, 2.5].enumerated() {
            room.addChildNode(box(aisle - 0.3, 0.014, 0.3, lit(p.trim), at: v3(aisle / 2, 0.2, z)))
            for x in [0.3, aisle / 2, aisle - 0.3] { room.addChildNode(box(0.02, 0.2, 0.24, lit(p.dark), at: v3(x, 0.1, z))) }
            for k in 0..<5 {
                let x = 0.6 + Double(k) * 0.76
                for (row, y) in [0.29, 0.42].enumerated() {
                    room.addChildNode(screen(0.29, 0.12, row == 0 ? Screens.table(p.glow) : Screens.plot(p.glow, rows: 2), at: v3(x - 0.155, y, z - 0.09), bezel: 0.006))
                    room.addChildNode(screen(0.29, 0.12, row == 0 ? Screens.plot(p.glow, rows: 1) : Screens.table(p.glow), at: v3(x + 0.155, y, z - 0.09), bezel: 0.006))
                }
                room.addChildNode(box(0.02, 0.2, 0.02, lit(p.dark), at: v3(x, 0.31, z - 0.11)))
                if (k + r) % 3 != 0 { room.addChildNode(seated(at: v3(x, 0, z + 0.27), facing: 0)) }
            }
        }
    }

    // MARK: A starship bridge: a captain's chair on a dais facing one great viewscreen

    private static func bridge(_ room: SCNNode, _ p: Palette) {
        room.addChildNode(screen(3.6, 0.58, Screens.viewscreen(), at: v3(width / 2, 0.38, 0.06), bezel: 0.02))
        let ring = SCNNode()
        ring.position = v3(width / 2, 0, 2.1)
        room.addChildNode(ring)
        for k in 0..<7 where k != 3 {
            let a = (Double(k) - 3) * 0.33
            let seg = box(0.5, 0.18, 0.18, lit(p.console), at: v3(sin(a) * 1.25, 0.09, -cos(a) * 1.25), chamfer: 0.03)
            seg.eulerAngles.y = CGFloat(-a)
            ring.addChildNode(seg)
            let strip = box(0.44, 0.006, 0.12, flat(p.glow), at: v3(sin(a) * 1.25, 0.184, -cos(a) * 1.25))
            strip.eulerAngles.y = CGFloat(-a)
            ring.addChildNode(strip)
            if k % 2 == 1 { ring.addChildNode(seated(at: v3(sin(a) * 0.98, 0, -cos(a) * 0.98), facing: -a)) }
        }
        let dais = SCNNode(geometry: faceted(SCNCylinder(radius: 0.42, height: 0.05), 12))
        dais.geometry!.firstMaterial = lit(p.trim)
        dais.position = v3(width / 2, 0.025, 2.35)
        room.addChildNode(dais)
        let chair = SCNNode()
        chair.addChildNode(box(0.32, 0.06, 0.3, lit(p.dark), at: v3(0, 0.2, 0.03), chamfer: 0.02))
        chair.addChildNode(box(0.32, 0.36, 0.06, lit(p.dark), at: v3(0, 0.38, 0.17), chamfer: 0.02))
        for side in [-1.0, 1.0] { chair.addChildNode(box(0.05, 0.05, 0.26, lit(p.trim), at: v3(side * 0.18, 0.27, 0.03), chamfer: 0.01)) }
        chair.position = v3(width / 2, 0.05, 2.35)
        room.addChildNode(chair)
        room.addChildNode(seated(at: v3(width / 2, 0.05, 2.33), facing: 0, chair: false))
        for x in [0.4, width - 0.4] {
            room.addChildNode(box(0.26, 0.42, 0.56, lit(p.console), at: v3(x, 0.21, 1.15), chamfer: 0.02))
            let panel = screen(0.44, 0.22, Screens.plot(p.glow, rows: 2), at: v3(x + (x < 1 ? 0.135 : -0.135), 0.33, 1.15), bezel: 0.006)
            panel.eulerAngles.y = CGFloat(x < 1 ? Double.pi / 2 : -Double.pi / 2)
            room.addChildNode(panel)
        }
    }

    // MARK: Operations: a round holo table in the middle, an annunciator board and launch boards on the wall

    static let repos: [(name: String, color: NSColor)] = [
        ("api-node-nest", NSColor(rgb: (0.95, 0.55, 0.25))), ("tattoodo-web", NSColor(rgb: (0.72, 0.45, 0.9))),
        ("backend-api", NSColor(rgb: (0.35, 0.75, 0.95))), ("app-ios", NSColor(rgb: (0.45, 0.85, 0.5))), ("app-android", NSColor(rgb: (0.95, 0.8, 0.3))),
    ]

    private static func ops(_ room: SCNNode, _ p: Palette) {
        let front = SCNNode()
        front.position = v3(aisle / 2, 0, 0.05)
        room.addChildNode(front)
        front.addChildNode(screen(1.6, 0.4, Screens.annunciator(repos), at: v3(0, 0.36, 0.02), bezel: 0.025))
        for side in [-1.0, 1.0] {
            front.addChildNode(screen(1.0, 0.3, Screens.flapBoard(side < 0 ? Array(repos.prefix(3)) : Array(repos.suffix(2)), launches: side < 0),
                                      at: v3(side * 1.4, 0.44, 0.02), bezel: 0.02))
        }
        let face = SCNNode(geometry: SCNPlane(width: 0.13, height: 0.13))
        let m = SCNMaterial(); m.diffuse.contents = Screens.nixieClock(); m.emission.contents = Screens.nixieClock(); m.lightingModel = .constant
        face.geometry!.firstMaterial = m
        face.position = v3(aisle / 2, 0.64, 0.08)
        room.addChildNode(face)

        let table = v3(aisle / 2, 0, 1.55)
        let base = SCNNode(geometry: faceted(SCNCylinder(radius: 0.5, height: 0.22), 32))
        base.geometry!.firstMaterial = lit(p.console)
        base.position = v3(Double(table.x), 0.11, Double(table.z))
        room.addChildNode(base)
        let rim = SCNNode(geometry: faceted(SCNTube(innerRadius: 0.46, outerRadius: 0.53, height: 0.03), 32))
        rim.geometry!.firstMaterial = flat(NSColor(rgb: (0.45, 0.95, 1.0)))
        rim.position = v3(Double(table.x), 0.235, Double(table.z))
        room.addChildNode(rim)
        let glass = SCNNode(geometry: faceted(SCNCylinder(radius: 0.46, height: 0.006), 32))
        glass.geometry!.firstMaterial = lit(NSColor(rgb: (0.05, 0.12, 0.16)))
        glass.position = v3(Double(table.x), 0.236, Double(table.z))
        room.addChildNode(glass)
        let lift = 0.3
        let map = hologram()
        map.position = v3(Double(table.x), 0.24 + lift, Double(table.z))
        room.addChildNode(map)
        for k in 0..<12 {
            let a = Double(k) / 12 * .pi * 2
            let ray = SCNNode(geometry: SCNCylinder(radius: 0.003, height: lift + 0.1))
            ray.geometry!.firstMaterial = holo(NSColor(rgb: (0.4, 0.9, 1.0)), 0.35)
            ray.position = v3(Double(table.x) + sin(a) * 0.46, 0.24 + (lift + 0.1) / 2, Double(table.z) + cos(a) * 0.46)
            room.addChildNode(ray)
        }
        for k in 0..<3 {
            let a = Double(k) * 2.1 + 0.6
            room.addChildNode(standing(at: v3(Double(table.x) + sin(a) * 0.68, 0, Double(table.z) + cos(a) * 0.68), facing: a))
        }

        for (k, z) in [0.85, 2.45].enumerated() {
            for j in 0..<2 {
                let x = j == 0 ? 0.62 : aisle - 0.62
                let console = opsConsole(p, color: repos[(k * 2 + j) % repos.count].color)
                console.position = v3(x, 0, z)
                room.addChildNode(console)
                if (k + j) % 2 == 1 { room.addChildNode(seated(at: v3(x, 0, z + 0.33), facing: 0)) }
            }
        }
    }

    static func opsConsole(_ p: Palette, color: NSColor) -> SCNNode {
        let n = apolloConsole(p)
        let strip = box(0.82, 0.012, 0.04, flat(color), at: v3(0, 0.386, -0.07))
        n.addChildNode(strip)
        return n
    }

    static func hologram() -> SCNNode {
        let n = SCNNode()
        let cyan = NSColor(rgb: (0.4, 0.9, 1.0))
        let station = SCNNode(geometry: faceted(SCNCylinder(radius: 0.06, height: 0.03), 6))
        station.geometry!.firstMaterial = holo(cyan, 0.9)
        station.position = v3(0, 0.1, 0)
        n.addChildNode(station)
        let planets: [(Double, Double, Double, NSColor)] = [(0.22, 0.4, 0.035, NSColor(rgb: (0.95, 0.6, 0.3))), (0.33, 2.2, 0.05, NSColor(rgb: (0.75, 0.5, 0.95))),
                                                            (0.4, 4.1, 0.03, NSColor(rgb: (0.4, 0.85, 0.95))), (0.28, 5.3, 0.025, NSColor(rgb: (0.5, 0.9, 0.55)))]
        for (r, a, size, color) in planets {
            let orbit = SCNNode(geometry: SCNTorus(ringRadius: r, pipeRadius: 0.002))
            orbit.geometry!.firstMaterial = holo(cyan, 0.45)
            orbit.position = v3(0, 0.1, 0)
            n.addChildNode(orbit)
            let planet = SCNNode(geometry: SCNSphere(radius: size))
            planet.geometry!.firstMaterial = holo(color, 0.95)
            planet.position = v3(sin(a) * r, 0.1, cos(a) * r)
            n.addChildNode(planet)
        }
        for (a, r, lift) in [(0.4, 0.22, 0.12), (2.2, 0.33, 0.2)] {
            let arc = SCNNode()
            for i in 0...10 {
                let t = Double(i) / 10
                let dot = SCNNode(geometry: SCNSphere(radius: 0.008))
                dot.geometry!.firstMaterial = holo(NSColor(rgb: (1, 0.85, 0.4)), 0.9)
                dot.position = v3(sin(a) * r * t, 0.1 + sin(t * .pi) * lift, cos(a) * r * t)
                arc.addChildNode(dot)
            }
            n.addChildNode(arc)
        }
        return n
    }

    static func holo(_ color: NSColor, _ alpha: Double) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.emission.contents = color
        m.lightingModel = .constant
        m.transparency = CGFloat(alpha)
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    static func standing(at: SCNVector3, facing yaw: Double) -> SCNNode {
        let n = SCNNode()
        let w = 0.22, h = 0.5, d = 0.11
        let body = box(w, h, d, lit(NSColor(rgb: (0.93, 0.93, 0.95))), at: v3(0, h / 2, 0), chamfer: 0.01)
        body.addChildNode(box(w * 0.5, h * 0.1, 0.012, flat(NSColor(rgb: (0.28, 0.75, 0.85))), at: v3(0, h * 0.3, -d / 2 - 0.004)))
        n.addChildNode(body)
        n.position = at
        n.eulerAngles.y = CGFloat(yaw)
        return n
    }

    // MARK: shared pieces

    private static func windowWall(_ room: SCNNode, _ p: Palette) {
        let x = width
        room.addChildNode(box(0.07, 0.14, depth, lit(p.wall), at: v3(x, 0.07, depth / 2)))
        room.addChildNode(box(0.07, 0.08, depth, lit(p.wall), at: v3(x, wall - 0.04, depth / 2)))
        for z in stride(from: 0.0, through: depth, by: 1.0) { room.addChildNode(box(0.07, wall, 0.06, lit(p.wall), at: v3(x, wall / 2, z))) }
        let glass = box(0.01, wall - 0.22, depth, flat(NSColor(rgb: (0.55, 0.75, 0.95))), at: v3(x, 0.14 + (wall - 0.22) / 2, depth / 2))
        glass.geometry!.firstMaterial!.transparency = 0.22
        room.addChildNode(glass)
    }

    static func seated(at: SCNVector3, facing yaw: Double, chair: Bool = true) -> SCNNode {
        let n = SCNNode()
        let w = 0.22, h = 0.5, d = 0.11, seat = Minion.seat
        let suit = lit(NSColor(rgb: (0.93, 0.93, 0.95)))
        let dark = lit(NSColor(rgb: (0.16, 0.17, 0.2)))
        if chair {
            n.addChildNode(box(0.24, 0.03, 0.24, dark, at: v3(0, seat - 0.015, 0.03), chamfer: 0.01))
            n.addChildNode(box(0.03, seat - 0.03, 0.03, lit(NSColor(rgb: (0.3, 0.31, 0.35))), at: v3(0, (seat - 0.03) / 2, 0.03)))
            n.addChildNode(box(0.24, 0.22, 0.03, dark, at: v3(0, seat + 0.13, 0.16), chamfer: 0.01))
        }
        let body = box(w, h * 0.62, d, suit, at: v3(0, seat + h * 0.31, 0.07), chamfer: 0.01)
        body.addChildNode(box(w * 0.5, h * 0.05, 0.012, flat(NSColor(rgb: (0.28, 0.75, 0.85))), at: v3(0, h * 0.18, -d / 2 - 0.004)))
        n.addChildNode(body)
        n.addChildNode(box(w, d, d * 2.2, suit, at: v3(0, seat + d / 2, -0.05), chamfer: 0.01))
        n.addChildNode(box(w, seat, d, suit, at: v3(0, seat / 2, -0.15), chamfer: 0.01))
        n.position = at
        n.eulerAngles.y = CGFloat(yaw)
        return n
    }

    static func screen(_ w: Double, _ h: Double, _ image: NSImage, at: SCNVector3, bezel: Double = 0.02) -> SCNNode {
        let frame = box(w + bezel * 2, h + bezel * 2, 0.02, lit(NSColor(rgb: (0.1, 0.11, 0.13))), at: at)
        let face = SCNNode(geometry: SCNPlane(width: w, height: h))
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.emission.contents = image
        m.lightingModel = .constant
        face.geometry!.firstMaterial = m
        face.position = v3(0, 0, 0.011)
        frame.addChildNode(face)
        return frame
    }

    static func box(_ w: Double, _ h: Double, _ d: Double, _ m: SCNMaterial, at: SCNVector3, chamfer: Double = 0) -> SCNNode {
        let n = SCNNode(geometry: SCNBox(width: w, height: h, length: d, chamferRadius: chamfer))
        n.geometry!.firstMaterial = m
        n.position = at
        return n
    }

    struct Palette {
        var floor, seam, wall, console, trim, dark, glow: NSColor
        static func of(_ s: Style) -> Palette {
            switch s {
            case .apollo:
                return Palette(floor: NSColor(rgb: (0.33, 0.35, 0.36)), seam: NSColor(rgb: (0.27, 0.29, 0.3)), wall: NSColor(rgb: (0.48, 0.5, 0.5)),
                               console: NSColor(rgb: (0.52, 0.58, 0.6)), trim: NSColor(rgb: (0.4, 0.43, 0.44)), dark: NSColor(rgb: (0.16, 0.17, 0.18)),
                               glow: NSColor(rgb: (0.45, 0.95, 0.6)))
            case .nasa:
                return Palette(floor: NSColor(rgb: (0.26, 0.28, 0.33)), seam: NSColor(rgb: (0.22, 0.24, 0.28)), wall: NSColor(rgb: (0.36, 0.38, 0.43)),
                               console: NSColor(rgb: (0.5, 0.52, 0.56)), trim: NSColor(rgb: (0.6, 0.45, 0.32)), dark: NSColor(rgb: (0.1, 0.11, 0.13)),
                               glow: NSColor(rgb: (0.55, 0.8, 1.0)))
            case .spacex:
                return Palette(floor: NSColor(rgb: (0.78, 0.79, 0.8)), seam: NSColor(rgb: (0.7, 0.71, 0.73)), wall: NSColor(rgb: (0.88, 0.89, 0.9)),
                               console: NSColor(rgb: (0.92, 0.92, 0.93)), trim: NSColor(rgb: (0.95, 0.95, 0.96)), dark: NSColor(rgb: (0.13, 0.14, 0.16)),
                               glow: NSColor(rgb: (0.6, 0.85, 1.0)))
            case .ops:
                return Palette(floor: NSColor(rgb: (0.28, 0.3, 0.32)), seam: NSColor(rgb: (0.23, 0.25, 0.27)), wall: NSColor(rgb: (0.44, 0.46, 0.47)),
                               console: NSColor(rgb: (0.52, 0.58, 0.6)), trim: NSColor(rgb: (0.4, 0.43, 0.44)), dark: NSColor(rgb: (0.14, 0.15, 0.16)),
                               glow: NSColor(rgb: (0.45, 0.95, 0.6)))
            case .bridge:
                return Palette(floor: NSColor(rgb: (0.12, 0.14, 0.2)), seam: NSColor(rgb: (0.2, 0.5, 0.65)), wall: NSColor(rgb: (0.2, 0.22, 0.3)),
                               console: NSColor(rgb: (0.28, 0.3, 0.4)), trim: NSColor(rgb: (0.55, 0.58, 0.68)), dark: NSColor(rgb: (0.1, 0.11, 0.16)),
                               glow: NSColor(rgb: (0.35, 0.9, 1.0)))
            }
        }
    }
}

enum Screens {
    private static func draw(_ w: Int, _ h: Int, _ body: (CGContext, CGFloat, CGFloat) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()
        if let c = NSGraphicsContext.current?.cgContext { body(c, CGFloat(w), CGFloat(h)) }
        image.unlockFocus()
        return image
    }

    static func map(trajectory: Bool) -> NSImage {
        draw(512, 256) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.03, 0.08, 0.16)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            c.setStrokeColor(NSColor(rgb: (0.15, 0.3, 0.45)).cgColor); c.setLineWidth(1)
            for x in stride(from: 0, to: w, by: 32) { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: h)) }
            for y in stride(from: 0, to: h, by: 32) { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: w, y: y)) }
            c.strokePath()
            c.setFillColor(NSColor(rgb: (0.18, 0.42, 0.32)).cgColor)
            for (x, y, rw, rh) in [(60.0, 120.0, 110.0, 70.0), (110.0, 40.0, 60.0, 80.0), (230.0, 110.0, 90.0, 80.0), (260.0, 40.0, 60.0, 70.0), (340.0, 120.0, 130.0, 70.0), (420.0, 40.0, 50.0, 40.0)] {
                c.fillEllipse(in: CGRect(x: x, y: y, width: rw, height: rh))
            }
            c.setStrokeColor(NSColor(rgb: (0.98, 0.85, 0.3)).cgColor); c.setLineWidth(3)
            c.move(to: CGPoint(x: 0, y: h * 0.5))
            for x in stride(from: 0, through: w, by: 8) { c.addLine(to: CGPoint(x: x, y: h * 0.5 + CGFloat(sin(Double(x / w) * .pi * 2)) * h * 0.3)) }
            c.strokePath()
            if trajectory {
                c.setFillColor(NSColor(rgb: (1, 0.4, 0.3)).cgColor)
                c.fillEllipse(in: CGRect(x: w * 0.62 - 7, y: h * 0.5 + CGFloat(sin(0.62 * Double.pi * 2)) * h * 0.3 - 7, width: 14, height: 14))
            }
        }
    }

    static func plot(_ glow: NSColor, rows: Int) -> NSImage {
        draw(256, 160) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.02, 0.05, 0.06)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            for r in 0..<rows {
                let base = h * (CGFloat(r) + 0.5) / CGFloat(rows)
                c.setStrokeColor(glow.cgColor); c.setLineWidth(2)
                c.move(to: CGPoint(x: 6, y: base))
                for x in stride(from: CGFloat(6), through: w - 6, by: 6) {
                    c.addLine(to: CGPoint(x: x, y: base + CGFloat(sin(Double(x) * 0.07 + Double(r) * 1.7) * 9 + sin(Double(x) * 0.23) * 4)))
                }
                c.strokePath()
            }
        }
    }

    static func table(_ glow: NSColor) -> NSImage {
        draw(256, 160) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.02, 0.05, 0.06)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(glow.withAlphaComponent(0.85).cgColor)
            for row in 0..<9 {
                for col in 0..<4 {
                    let len = CGFloat(18 + (row * 7 + col * 13) % 34)
                    c.fill(CGRect(x: 10 + CGFloat(col) * 62, y: h - 18 - CGFloat(row) * 16, width: len, height: 7))
                }
            }
        }
    }

    static func clock(_ text: String) -> NSImage {
        draw(1024, 64) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.03, 0.02, 0.02)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor(rgb: (1, 0.45, 0.25))]
            let s = NSAttributedString(string: text, attributes: attrs)
            let size = s.size()
            s.draw(at: NSPoint(x: (w - size.width) / 2, y: (h - size.height) / 2))
        }
    }

    static func annunciator(_ repos: [(name: String, color: NSColor)]) -> NSImage {
        draw(1024, 300) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.06, 0.06, 0.07)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let lamps = [NSColor(rgb: (0.3, 0.95, 0.45)), NSColor(rgb: (1, 0.75, 0.2)), NSColor(rgb: (1, 0.3, 0.25)), NSColor(rgb: (0.2, 0.22, 0.25))]
            let rowH = h / CGFloat(repos.count)
            for (r, repo) in repos.enumerated() {
                let y = h - rowH * CGFloat(r + 1)
                c.setFillColor(repo.color.cgColor); c.fill(CGRect(x: 8, y: y + 6, width: 210, height: rowH - 12))
                let label = NSAttributedString(string: repo.name.uppercased(), attributes: [.font: NSFont.monospacedSystemFont(ofSize: 22, weight: .heavy), .foregroundColor: NSColor.black])
                label.draw(at: NSPoint(x: 16, y: y + (rowH - 26) / 2))
                for k in 0..<6 {
                    let lamp = lamps[r == 0 && k == 2 ? 2 : (r * 3 + k) % 5 == 1 ? 1 : (r + k) % 4 == 3 ? 3 : 0]
                    c.setFillColor(lamp.cgColor)
                    c.fill(CGRect(x: 240 + CGFloat(k) * 128, y: y + 8, width: 116, height: rowH - 16))
                }
            }
        }
    }

    static func flapBoard(_ repos: [(name: String, color: NSColor)], launches: Bool) -> NSImage {
        draw(768, 230) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.05, 0.05, 0.06)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let title = NSAttributedString(string: launches ? "LAUNCHES" : "ON THE PAD", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 26, weight: .black), .foregroundColor: NSColor(rgb: (1, 0.85, 0.35))])
            title.draw(at: NSPoint(x: 14, y: h - 38))
            let lines = launches ? ["#5806  LANDED  15:40", "#14163 LIFTOFF 15:31", "#39    BOARDING"] : ["RELEASE  5 CRATES", "HOTFIX   1 CRATE"]
            for (i, repo) in repos.enumerated() {
                let y = h - 80 - CGFloat(i) * 48
                c.setFillColor(repo.color.cgColor); c.fill(CGRect(x: 14, y: y, width: 12, height: 34))
                for k in 0..<22 {
                    c.setFillColor(NSColor(rgb: (0.13, 0.13, 0.15)).cgColor)
                    c.fill(CGRect(x: 34 + CGFloat(k) * 33, y: y, width: 30, height: 34))
                }
                let text = String((repo.name.uppercased() + "  " + lines[i % lines.count]).prefix(22))
                for (k, ch) in text.enumerated() {
                    let s = NSAttributedString(string: String(ch), attributes: [.font: NSFont.monospacedSystemFont(ofSize: 24, weight: .bold), .foregroundColor: NSColor(rgb: (0.95, 0.95, 0.9))])
                    s.draw(at: NSPoint(x: 39 + CGFloat(k) * 33, y: y + 3))
                }
            }
        }
    }

    static func nixieClock() -> NSImage {
        draw(256, 256) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.04, 0.03, 0.02)).cgColor); c.fillEllipse(in: CGRect(x: 0, y: 0, width: w, height: h))
            let s = NSAttributedString(string: "T-02:14", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor(rgb: (1, 0.55, 0.2))])
            let size = s.size()
            s.draw(at: NSPoint(x: (w - size.width) / 2, y: (h - size.height) / 2))
        }
    }

    static func camera() -> NSImage {
        draw(512, 256) { c, w, h in
            let g = CGGradient(colorsSpace: nil, colors: [NSColor(rgb: (0.35, 0.55, 0.8)).cgColor, NSColor(rgb: (0.75, 0.82, 0.9)).cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.3), options: [])
            c.setFillColor(NSColor(rgb: (0.3, 0.32, 0.3)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.3))
            c.setFillColor(NSColor(rgb: (0.95, 0.95, 0.97)).cgColor); c.fill(CGRect(x: w * 0.47, y: h * 0.3, width: w * 0.06, height: h * 0.55))
            c.setFillColor(NSColor(rgb: (1, 0.75, 0.35)).cgColor); c.fillEllipse(in: CGRect(x: w * 0.44, y: h * 0.12, width: w * 0.12, height: h * 0.2))
        }
    }

    static func viewscreen() -> NSImage {
        draw(1024, 200) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.01, 0.01, 0.03)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            var seed: UInt64 = 7
            for _ in 0..<220 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat((seed >> 33) % 1024), y = CGFloat((seed >> 13) % 200)
                c.setFillColor(NSColor(white: 1, alpha: CGFloat((seed >> 5) % 100) / 120).cgColor)
                c.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
            let g = CGGradient(colorsSpace: nil, colors: [NSColor(rgb: (0.35, 0.6, 0.9)).cgColor, NSColor(rgb: (0.08, 0.15, 0.35)).cgColor] as CFArray, locations: [0, 1])!
            c.saveGState()
            c.addEllipse(in: CGRect(x: w * 0.58, y: -h * 0.6, width: h * 1.5, height: h * 1.5)); c.clip()
            c.drawRadialGradient(g, startCenter: CGPoint(x: w * 0.62, y: h * 0.4), startRadius: 0, endCenter: CGPoint(x: w * 0.66, y: h * 0.15), endRadius: h * 0.9, options: [])
            c.restoreGState()
        }
    }
}
