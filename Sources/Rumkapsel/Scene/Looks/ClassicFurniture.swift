import AppKit
import SceneKit

struct Furnishing {
    var props: [SCNNode] = []
    var fixtures: [SCNNode] = []
    var bar: SCNNode?
    var bag: SCNNode?
    var towel: SCNNode?
    var kitchen: Kitchen?
    var chairs: [FixtureRef: SCNNode] = [:]
    var faces: MissionFaces?
}

struct MissionFaces { let annunciator: SCNMaterial; let blink: SCNNode; let clock: SCNMaterial; let errors: SCNMaterial; let errorsNode: SCNNode; let feeds: [SCNMaterial]; let wall: SIMD3<Double> }

struct Kitchen {
    var lamp: SCNNode
    var cup: SCNNode
    var stream: SCNNode
    var window: SCNNode
    var meal: SCNNode
    var head: SCNNode
    var steam: [SCNNode]
    static let mealIn = SCNVector3(0, 0.05, -0.01), mealOut = SCNVector3(0, 0.012, 0.13)

    static let mugHeight = 0.08, counterTop = 0.26

    static func mug() -> SCNNode {
        let m = SCNNode(geometry: SCNBox(width: 0.07, height: mugHeight, length: 0.07, chamferRadius: 0.007))
        m.geometry!.firstMaterial = lit(NSColor(rgb: (0.94, 0.94, 0.92)))
        let handle = SCNNode(geometry: SCNBox(width: 0.016, height: 0.045, length: 0.028, chamferRadius: 0))
        handle.geometry!.firstMaterial = m.geometry!.firstMaterial
        handle.position = v3(-0.042, 0, 0)
        m.addChildNode(handle)
        return m
    }

    static func bowl() -> (bowl: SCNNode, food: SCNNode) {
        let bowl = SCNNode(geometry: SCNBox(width: 0.08, height: 0.03, length: 0.08, chamferRadius: 0.006))
        bowl.geometry!.firstMaterial = lit(NSColor(rgb: (0.78, 0.62, 0.42)))
        let food = SCNNode()
        food.position = v3(0, 0.02, 0)
        let noodles = SCNNode(geometry: SCNBox(width: 0.062, height: 0.018, length: 0.062, chamferRadius: 0.005))
        noodles.geometry!.firstMaterial = lit(NSColor(rgb: (0.93, 0.6, 0.25)))
        let greens = SCNNode(geometry: SCNBox(width: 0.024, height: 0.016, length: 0.024, chamferRadius: 0))
        greens.geometry!.firstMaterial = lit(NSColor(rgb: (0.4, 0.75, 0.38)))
        greens.position = v3(0.014, 0.012, -0.01)
        food.addChildNode(noodles); food.addChildNode(greens)
        bowl.addChildNode(food)
        return (bowl, food)
    }

    static func steam(over top: Double) -> [SCNNode] {
        (0..<3).map { _ in
            let puff = SCNNode(geometry: SCNBox(width: 0.018, height: 0.018, length: 0.018, chamferRadius: 0.004))
            puff.geometry!.firstMaterial = Props.glowing(NSColor(white: 0.95, alpha: 1), alpha: 0.5)
            puff.position = v3(0, top, 0)
            return puff
        }
    }

    static func rise(_ steam: [SCNNode], over top: Double, at clock: Double) {
        for (i, puff) in steam.enumerated() {
            let k = (clock * 0.7 + Double(i) / Double(steam.count)).truncatingRemainder(dividingBy: 1)
            puff.position = v3(sin(clock * 2.3 + Double(i) * 2) * 0.012, top + k * 0.14, cos(clock * 1.9 + Double(i)) * 0.01)
            puff.opacity = CGFloat(sin(k * .pi) * 0.9)
            let s = CGFloat(0.6 + k)
            puff.scale = SCNVector3(s, s, s)
        }
    }
}

extension Classic {
    static func lounge(_ lounge: Room, in station: Station) -> Furnishing {
        var f = Furnishing()
        let spots = station.loungeSpots(lounge: lounge)
        let table = SCNNode(geometry: SCNBox(width: 0.9, height: 0.03, length: 0.4, chamferRadius: 0))
        table.geometry!.firstMaterial = lit(NSColor(Colors.furniture))
        table.position = v3(spots.table.x, 0.2, spots.table.y)
        for lx in [-0.4, 0.4] {
            let panel = SCNNode(geometry: SCNBox(width: 0.03, height: 0.19, length: 0.34, chamferRadius: 0))
            panel.geometry!.firstMaterial = lit(NSColor(Colors.furnitureDim))
            panel.position = v3(lx, -0.1, 0)
            table.addChildNode(panel)
        }
        let magazine = SCNNode(geometry: SCNBox(width: 0.16, height: 0.01, length: 0.22, chamferRadius: 0))
        magazine.geometry!.firstMaterial = flat(NSColor(rgb: (0.85, 0.85, 0.8)))
        magazine.position = v3(0.15, 0.02, 0.02)
        magazine.eulerAngles.y = 0.3
        table.addChildNode(magazine)
        f.props.append(table)
        for fixture in station.fixtures(in: lounge.key) where fixture.kind == .couch {
            let size = fixture.kind.size
            let couch = SCNNode(geometry: SCNBox(width: size.x, height: Seat.couch, length: size.y, chamferRadius: 0.02))
            couch.geometry!.firstMaterial = lit(NSColor(Colors.furnitureLight))
            couch.position = v3(station.offset.x + fixture.at.x, Seat.couch / 2, station.offset.y + fixture.at.y)
            couch.eulerAngles.y = CGFloat(fixture.yaw)
            let back = SCNNode(geometry: SCNBox(width: size.x, height: 0.22, length: 0.08, chamferRadius: 0.02))
            back.geometry!.firstMaterial = couch.geometry!.firstMaterial
            back.position = v3(0, 0.16, -0.11)
            couch.addChildNode(back)
            f.props.append(couch)
        }
        let pot = SCNNode(geometry: SCNBox(width: 0.2, height: 0.16, length: 0.2, chamferRadius: 0))
        pot.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.5, 0.35)))
        pot.position = v3(spots.pot.x, 0.08, spots.pot.y)
        let stem = SCNNode(geometry: SCNBox(width: 0.03, height: 0.3, length: 0.03, chamferRadius: 0))
        stem.geometry!.firstMaterial = lit(NSColor(rgb: (0.25, 0.45, 0.28)))
        stem.position = v3(0, 0.22, 0)
        pot.addChildNode(stem)
        for (i, (w, yaw, tiltZ)) in [(0.22, 0.0, 0.6), (0.2, 2.1, 0.5), (0.24, 4.2, 0.7), (0.16, 1.0, -0.2)].enumerated() {
            let leaf = SCNNode(geometry: SCNBox(width: w, height: 0.02, length: 0.09, chamferRadius: 0))
            leaf.geometry!.firstMaterial = lit(NSColor(rgb: (0.3 + Double(i) * 0.03, 0.62, 0.38)))
            leaf.pivot = SCNMatrix4MakeTranslation(-w / 2, 0, 0)
            leaf.position = v3(0, 0.3 + Double(i) * 0.03, 0)
            leaf.eulerAngles = SCNVector3(0, yaw, tiltZ)
            pot.addChildNode(leaf)
        }
        f.props.append(pot)
        let shelf = SCNNode(geometry: SCNBox(width: 0.7, height: 0.32, length: 0.2, chamferRadius: 0.01))
        shelf.geometry!.firstMaterial = lit(NSColor(Colors.furniture))
        shelf.position = v3(spots.shelf.x, 0.16, spots.shelf.y)
        for i in 0..<4 {
            let book = SCNNode(geometry: SCNBox(width: 0.08, height: 0.2, length: 0.14, chamferRadius: 0))
            book.geometry!.firstMaterial = lit(NSColor(Colors.repos[i % Colors.repos.count]))
            book.position = v3(-0.22 + Double(i) * 0.13, 0.26, 0)
            shelf.addChildNode(book)
        }
        f.props.append(shelf)
        return f
    }

    static func bath(_ bath: Room, in station: Station) -> Furnishing {
        var f = Furnishing()
        let fx = station.bathFixtures(bath: bath)
        let tk = fx.toiletCorner, sk = fx.showerCorner
        let porcelain = lit(NSColor(rgb: (0.92, 0.93, 0.95)))
        let spot = station.bowlSpot(bath: bath)
        let bowl = SCNNode(geometry: SCNBox(width: 0.16, height: Minion.seat - 0.06, length: 0.16, chamferRadius: 0.01))
        bowl.geometry!.firstMaterial = porcelain
        bowl.position = v3(spot.x, (Minion.seat - 0.06) / 2, spot.y)
        let seat = SCNNode(geometry: SCNBox(width: 0.24, height: 0.06, length: 0.28, chamferRadius: 0.01))
        seat.geometry!.firstMaterial = porcelain
        seat.position = v3(0, Minion.seat - 0.03 - bowl.position.y, -0.02 * tk.y)
        bowl.addChildNode(seat)
        let hole = SCNNode(geometry: SCNBox(width: 0.12, height: 0.006, length: 0.14, chamferRadius: 0))
        hole.geometry!.firstMaterial = flat(NSColor(rgb: (0.55, 0.6, 0.66)))
        hole.position = v3(0, 0.032, -0.03 * tk.y)
        seat.addChildNode(hole)
        let tank = SCNNode(geometry: SCNBox(width: 0.24, height: 0.3, length: 0.1, chamferRadius: 0.01))
        tank.geometry!.firstMaterial = porcelain
        tank.position = v3(0, Minion.seat + 0.15 - bowl.position.y, 0.16 * tk.y)
        bowl.addChildNode(tank)
        let button = SCNNode(geometry: SCNBox(width: 0.05, height: 0.012, length: 0.04, chamferRadius: 0))
        button.geometry!.firstMaterial = lit(NSColor(rgb: (0.7, 0.72, 0.78)))
        button.position = v3(0.06, 0.156, 0)
        tank.addChildNode(button)
        f.props.append(bowl)
        let arm = SCNNode(geometry: SCNBox(width: 0.04, height: 0.04, length: 0.2, chamferRadius: 0))
        arm.geometry!.firstMaterial = lit(NSColor(rgb: (0.7, 0.72, 0.78)))
        let armAt = station.showerArm(bath: bath)
        arm.position = v3(armAt.x, 0.72, armAt.y)
        let nozzle = SCNNode(geometry: SCNBox(width: 0.1, height: 0.04, length: 0.1, chamferRadius: 0))
        nozzle.geometry!.firstMaterial = arm.geometry!.firstMaterial
        nozzle.position = v3(0, -0.03, -0.1 * sk.y)
        arm.addChildNode(nozzle)
        f.props.append(arm)
        let pole = SCNNode(geometry: SCNBox(width: 0.04, height: 0.72, length: 0.04, chamferRadius: 0))
        pole.geometry!.firstMaterial = arm.geometry!.firstMaterial
        let poleAt = station.showerPole(bath: bath)
        pole.position = v3(poleAt.x, 0.36, poleAt.y)
        let tap = SCNNode(geometry: SCNBox(width: 0.07, height: 0.03, length: 0.05, chamferRadius: 0))
        tap.geometry!.firstMaterial = arm.geometry!.firstMaterial
        tap.position = v3(0, 0.0, -0.04 * sk.y)
        pole.addChildNode(tap)
        f.props.append(pole)
        let railAt = station.towelRail(bath: bath)
        let rail = SCNNode(geometry: SCNBox(width: 0.02, height: 0.02, length: 0.24, chamferRadius: 0))
        rail.geometry!.firstMaterial = arm.geometry!.firstMaterial
        rail.position = v3(railAt.x, 0.46, railAt.y)
        let towel = SCNNode(geometry: SCNBox(width: 0.035, height: 0.24, length: 0.18, chamferRadius: 0.004))
        towel.geometry!.firstMaterial = lit(NSColor(rgb: (0.93, 0.56, 0.46)))
        towel.position = v3(-0.03 * sk.x, -0.09, 0)
        rail.addChildNode(towel)
        let stripe = SCNNode(geometry: SCNBox(width: 0.04, height: 0.03, length: 0.18, chamferRadius: 0))
        stripe.geometry!.firstMaterial = lit(NSColor(rgb: (0.98, 0.9, 0.82)))
        stripe.position = v3(0, -0.06, 0)
        towel.addChildNode(stripe)
        f.props.append(rail)
        f.towel = towel
        let drain = SCNNode(geometry: SCNBox(width: 0.14, height: 0.006, length: 0.14, chamferRadius: 0))
        drain.geometry!.firstMaterial = flat(NSColor(rgb: (0.28, 0.36, 0.4)))
        let drainAt = station.showerNozzle(bath: bath)
        drain.position = v3(drainAt.x, 0.01, drainAt.y)
        f.props.append(drain)
        return f
    }

    static func gym(_ gym: Room, in station: Station) -> Furnishing {
        var f = Furnishing()
        let spots = station.gymSpots(gym: gym)
        let dark = lit(NSColor(rgb: (0.22, 0.23, 0.28)))
        let steel = lit(NSColor(rgb: (0.66, 0.68, 0.74)))
        let tread = SCNNode(geometry: SCNBox(width: 0.42, height: 0.06, length: 0.72, chamferRadius: 0.01))
        tread.geometry!.firstMaterial = dark
        tread.position = v3(spots[0].x, 0.03, spots[0].y)
        let rail = SCNNode(geometry: SCNBox(width: 0.42, height: 0.04, length: 0.04, chamferRadius: 0))
        rail.geometry!.firstMaterial = steel
        rail.position = v3(0, 0.42, 0.34)
        let post = SCNNode(geometry: SCNBox(width: 0.04, height: 0.4, length: 0.04, chamferRadius: 0))
        post.geometry!.firstMaterial = steel
        post.position = v3(0, 0.2, 0.34)
        tread.addChildNode(rail); tread.addChildNode(post)
        f.fixtures.append(tread)
        let bench = SCNNode(geometry: SCNBox(width: 0.28, height: 0.2, length: 0.7, chamferRadius: 0.01))
        bench.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.32, 0.3)))
        bench.position = v3(spots[1].x, 0.1, spots[1].y)
        f.fixtures.append(bench)
        for side in [-1.0, 1.0] {
            let up = SCNNode(geometry: SCNBox(width: 0.04, height: 0.6, length: 0.04, chamferRadius: 0))
            up.geometry!.firstMaterial = steel
            up.position = v3(spots[1].x + side * 0.36, 0.3, spots[1].y - 0.18)
            f.fixtures.append(up)
        }
        let bar = SCNNode(geometry: SCNBox(width: 0.9, height: 0.035, length: 0.035, chamferRadius: 0))
        bar.geometry!.firstMaterial = steel
        bar.position = v3(spots[1].x, 0.62, spots[1].y - 0.18)
        for side in [-1.0, 1.0] {
            let disc = SCNNode(geometry: SCNBox(width: 0.05, height: 0.2, length: 0.2, chamferRadius: 0.01))
            disc.geometry!.firstMaterial = dark
            disc.position = v3(side * 0.4, 0, 0)
            bar.addChildNode(disc)
        }
        f.fixtures.append(bar)
        f.bar = bar
        let out = station.gymOutward(gym: gym, at: spots[2])
        let bagPost = SCNNode(geometry: SCNBox(width: 0.06, height: 1.1, length: 0.06, chamferRadius: 0))
        bagPost.geometry!.firstMaterial = steel
        bagPost.position = v3(spots[2].x + out.x * 0.3, 0.55, spots[2].y + out.y * 0.3)
        let bagArm = SCNNode(geometry: SCNBox(width: 0.34, height: 0.04, length: 0.04, chamferRadius: 0))
        bagArm.geometry!.firstMaterial = steel
        bagArm.position = v3(-out.x * 0.15, 0.53, -out.y * 0.15)
        bagArm.eulerAngles.y = atan2(-out.x, -out.y) + .pi / 2
        bagPost.addChildNode(bagArm)
        f.fixtures.append(bagPost)
        let bag = SCNNode()
        bag.position = v3(spots[2].x, 1.08, spots[2].y)
        let sack = SCNNode(geometry: SCNBox(width: 0.2, height: 0.42, length: 0.2, chamferRadius: 0.02))
        sack.geometry!.firstMaterial = lit(NSColor(rgb: (0.72, 0.28, 0.26)))
        sack.position = v3(0, -0.36, 0)
        let chain = SCNNode(geometry: SCNBox(width: 0.02, height: 0.16, length: 0.02, chamferRadius: 0))
        chain.geometry!.firstMaterial = steel
        chain.position = v3(0, -0.08, 0)
        bag.addChildNode(sack); bag.addChildNode(chain)
        f.fixtures.append(bag)
        f.bag = bag
        let mat = SCNNode(geometry: SCNBox(width: 0.7, height: 0.012, length: 0.7, chamferRadius: 0))
        mat.geometry!.firstMaterial = flat(NSColor(Colors.furnitureLight))
        mat.position = v3(spots[3].x, 0.006, spots[3].y)
        f.fixtures.append(mat)
        return f
    }

    static func galley(_ room: Room, in station: Station) -> Furnishing {
        var f = Furnishing()
        func place(_ n: SCNNode, _ fixture: PlacedFixture, _ y: Double, at spot: SIMD2<Double>? = nil) {
            let at = spot ?? fixture.at
            n.position = v3(station.offset.x + at.x, y, station.offset.y + at.y)
            n.eulerAngles.y = CGFloat(fixture.yaw)
        }
        func box(_ w: Double, _ h: Double, _ d: Double, _ m: SCNMaterial, _ at: SCNVector3, chamfer: Double = 0) -> SCNNode {
            let n = SCNNode(geometry: SCNBox(width: w, height: h, length: d, chamferRadius: chamfer))
            n.geometry!.firstMaterial = m
            n.position = at
            return n
        }
        let top = Kitchen.counterTop
        let steel = lit(NSColor(rgb: (0.7, 0.72, 0.78))), dark = lit(NSColor(rgb: (0.2, 0.21, 0.25)))
        let fixtures = station.fixtures(in: room.key)
        let counters = fixtures.filter { $0.kind == .counter }
        for counter in counters {
            let size = counter.kind.size
            let unit = box(size.x, top, size.y, lit(NSColor(Colors.furnitureDim)), SCNVector3Zero)
            unit.addChildNode(box(size.x, 0.024, size.y + 0.02, lit(NSColor(Colors.furnitureLight)), v3(0, top / 2 + 0.012, 0.01)))
            place(unit, counter, top / 2)
            f.props.append(unit)
        }
        guard let coffeeAt = fixtures.first(where: { $0.kind == .coffeeMachine }), let printerAt = fixtures.first(where: { $0.kind == .foodPrinter }) else { return f }

        let machine = SCNNode()
        machine.addChildNode(box(0.17, 0.2, 0.14, steel, v3(0, 0.1, -0.02), chamfer: 0.01))
        machine.addChildNode(box(0.17, 0.025, 0.14, dark, v3(0, 0.212, -0.02)))
        machine.addChildNode(box(0.07, 0.07, 0.07, lit(NSColor(rgb: (0.42, 0.27, 0.18))), v3(0.03, 0.26, -0.04)))
        let head = box(0.11, 0.035, 0.08, dark, v3(0, 0.15, 0.08))
        machine.addChildNode(head)
        machine.addChildNode(box(0.12, 0.012, 0.07, dark, v3(0, 0.006, 0.085)))
        let lamp = box(0.026, 0.018, 0.006, flat(NSColor(rgb: (0.3, 0.32, 0.36))), v3(0.055, 0.185, 0.053))
        machine.addChildNode(lamp)
        let cup = Kitchen.mug()
        cup.position = v3(0, 0.012 + Kitchen.mugHeight / 2, 0.085)
        cup.eulerAngles.y = .pi / 2
        cup.isHidden = true
        machine.addChildNode(cup)
        let steam = Kitchen.steam(over: Kitchen.mugHeight / 2)
        steam.forEach(cup.addChildNode)
        let stream = box(0.012, 0.04, 0.012, flat(NSColor(rgb: (0.36, 0.22, 0.12))), v3(0, 0.112, 0.085))
        stream.isHidden = true
        machine.addChildNode(stream)
        place(machine, coffeeAt, top + 0.024)
        f.fixtures.append(machine)

        let printer = SCNNode()
        printer.addChildNode(box(0.22, 0.2, 0.17, lit(NSColor(rgb: (0.86, 0.87, 0.9))), v3(0, 0.1, -0.01), chamfer: 0.012))
        let window = box(0.15, 0.1, 0.006, flat(NSColor(rgb: (0.16, 0.18, 0.22))), v3(0, 0.09, 0.076))
        window.geometry!.firstMaterial!.transparency = 0.55
        printer.addChildNode(window)
        printer.addChildNode(box(0.04, 0.022, 0.006, flat(NSColor(rgb: (0.4, 0.95, 0.75))), v3(0.075, 0.172, 0.076)))
        printer.addChildNode(box(0.16, 0.01, 0.06, dark, v3(0, 0.005, 0.1)))
        let meal = Kitchen.bowl().bowl
        meal.position = Kitchen.mealIn
        meal.isHidden = true
        printer.addChildNode(meal)
        place(printer, printerAt, top + 0.024)
        f.fixtures.append(printer)

        let rack = SCNNode()
        for side in [-1.0, 1.0] {
            let mug = Kitchen.mug()
            mug.position = v3(side * 0.04, Kitchen.mugHeight / 2, 0)
            mug.eulerAngles.y = CGFloat(side * 0.4)
            rack.addChildNode(mug)
        }
        let middle = counters[counters.count / 2]
        place(rack, middle, top + 0.024, at: middle.point(SIMD2(0, -0.06)))
        f.fixtures.append(rack)

        f.kitchen = Kitchen(lamp: lamp, cup: cup, stream: stream, window: window, meal: meal, head: head, steam: steam)
        return f
    }

    static func mission(_ room: Room, in station: Station) -> Furnishing {
        var f = Furnishing()
        guard let origin = station.roomOrigin(room.key) else { return f }
        let p = MissionRoom.Palette.ops
        let o = station.offset
        func at(_ n: SCNNode, _ spot: SIMD2<Double>, _ y: Double = 0, yaw: Double = 0) -> SCNNode {
            n.position = v3(o.x + spot.x, y, o.y + spot.y)
            n.eulerAngles.y = CGFloat(yaw)
            return n
        }
        for (i, fixture) in station.fixtures(in: room.key).enumerated() {
            switch fixture.kind {
            case .couch:
                break
            case .console:
                f.props.append(at(MissionRoom.console(fixture.kind.size, p), fixture.at, yaw: fixture.yaw))
            case .counter, .coffeeMachine, .foodPrinter:
                break
            case .holoTable:
                let r = fixture.kind.size.x / 2
                let table = SCNNode(geometry: faceted(SCNCylinder(radius: r - 0.03, height: 0.22), 32))
                table.geometry!.firstMaterial = lit(p.console)
                let rim = SCNNode(geometry: faceted(SCNTube(innerRadius: r - 0.07, outerRadius: r, height: 0.03), 32))
                rim.geometry!.firstMaterial = flat(NSColor(rgb: (0.45, 0.95, 1.0)))
                rim.position = v3(0, 0.125, 0)
                table.addChildNode(rim)
                let glass = SCNNode(geometry: faceted(SCNCylinder(radius: r - 0.07, height: 0.006), 32))
                glass.geometry!.firstMaterial = lit(NSColor(rgb: (0.05, 0.12, 0.16)))
                glass.position = v3(0, 0.126, 0)
                table.addChildNode(glass)
                f.props.append(at(table, fixture.at, 0.11))
                let lift = 0.06
                let map = MissionRoom.hologram()
                map.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 60)))
                f.fixtures.append(at(map, fixture.at, 0.24 + lift))
                for k in 0..<12 {
                    let a = Double(k) / 12 * .pi * 2
                    let ray = SCNNode(geometry: SCNCylinder(radius: 0.003, height: lift + 0.1))
                    ray.geometry!.firstMaterial = MissionRoom.holo(NSColor(rgb: (0.4, 0.9, 1.0)), 0.35)
                    f.fixtures.append(at(ray, fixture.at + SIMD2(sin(a), cos(a)) * (r - 0.07), 0.24 + (lift + 0.1) / 2))
                }
            }
            for k in fixture.kind.anchors.indices {
                guard let seat = fixture.place(k), case .sit(let height) = seat.use else { continue }
                let chair = at(chair(height: height), seat.chair, yaw: seat.facing + .pi)
                f.props.append(chair)
                f.chairs[FixtureRef(room: room.key, fixture: i, anchor: k)] = chair
            }
        }
        let low = 0.46, high = 1.06, wall = Walker.wallHeight, north = origin.y
        let frame = lit(NSColor(rgb: (0.42, 0.45, 0.48)))
        for x in [0.1, 4.9] { f.fixtures.append(at(MissionRoom.box(0.05, high + 0.04, 0.05, frame, at: SCNVector3Zero), SIMD2(origin.x + x, north + 0.04), (high + 0.04) / 2)) }
        for y in [high + 0.015, low - 0.04] { f.fixtures.append(at(MissionRoom.box(4.85, 0.035, 0.035, frame, at: SCNVector3Zero), SIMD2(origin.x + 2.5, north + 0.04), y)) }
        func face(_ n: SCNNode) -> SCNMaterial { n.childNodes.first!.geometry!.firstMaterial! }
        let annunciator = MissionRoom.screen(1.6, 0.42, Screens.annunciator([]), at: SCNVector3Zero, bezel: 0.025)
        let blink = SCNNode(geometry: SCNPlane(width: 1.6, height: 0.42))
        let bm = SCNMaterial(); bm.lightingModel = .constant; bm.writesToDepthBuffer = false
        blink.geometry!.firstMaterial = bm
        blink.position = v3(0, 0, 0.0125)
        blink.isHidden = true
        annunciator.addChildNode(blink)
        f.fixtures.append(at(annunciator, SIMD2(origin.x + 1.0, north + 0.06), low + 0.24))
        let feeds = [2.3, 3.1].map { x -> SCNNode in
            let crt = MissionRoom.screen(0.68, 0.42, Screens.noSignal(""), at: SCNVector3Zero, bezel: 0.04)
            f.fixtures.append(at(crt, SIMD2(origin.x + x, north + 0.06), low + 0.24))
            return crt
        }
        let errors = MissionRoom.screen(1.1, 0.42, Screens.noSignal("Errors and alarms"), at: SCNVector3Zero, bezel: 0.03)
        f.fixtures.append(at(errors, SIMD2(origin.x + 4.2, north + 0.06), low + 0.24))
        let clock = SCNNode(geometry: SCNPlane(width: 0.13, height: 0.13))
        let m = SCNMaterial(); m.diffuse.contents = Screens.nixieClock(nil); m.emission.contents = Screens.nixieClock(nil); m.lightingModel = .constant
        clock.geometry!.firstMaterial = m
        f.fixtures.append(at(clock, SIMD2(origin.x + 2.7, north + 0.07), high - 0.08))
        f.faces = MissionFaces(annunciator: face(annunciator), blink: blink, clock: m, errors: face(errors), errorsNode: errors, feeds: feeds.map(face), wall: SIMD3(o.x + origin.x + 2.5, low + 0.24, o.y + north))
        let sill = 0.14, beam = 0.08, depth = 3.0, west = origin.x
        f.fixtures.append(at(MissionRoom.box(0.07, sill, depth, Bulkhead.steel, at: SCNVector3Zero), SIMD2(west, north + depth / 2), sill / 2))
        f.fixtures.append(at(MissionRoom.box(0.07, beam, depth, Bulkhead.steel, at: SCNVector3Zero), SIMD2(west, north + depth / 2), wall - beam / 2))
        for k in 0...3 { f.fixtures.append(at(MissionRoom.box(0.07, wall, 0.06, Bulkhead.steel, at: SCNVector3Zero), SIMD2(west, north + Double(k)), wall / 2)) }
        let pane = MissionRoom.box(0.01, wall - sill - beam, depth, flat(NSColor(rgb: (0.55, 0.75, 0.95))), at: SCNVector3Zero)
        pane.geometry!.firstMaterial!.transparency = 0.18
        f.fixtures.append(at(pane, SIMD2(west, north + depth / 2), sill + (wall - sill - beam) / 2))
        return f
    }

    static func chair(height: Double) -> SCNNode {
        let chair = SCNNode()
        let dark = lit(NSColor(rgb: (0.16, 0.17, 0.2)))
        let under = -Seat.back / 2
        chair.addChildNode(MissionRoom.box(Seat.width, 0.03, Seat.depth, dark, at: v3(0, height - 0.015, under), chamfer: 0.01))
        chair.addChildNode(MissionRoom.box(0.03, height - 0.03, 0.03, lit(NSColor(rgb: (0.3, 0.31, 0.35))), at: v3(0, (height - 0.03) / 2, under)))
        chair.addChildNode(MissionRoom.box(Seat.width, 0.24, Seat.back, dark, at: v3(0, height + 0.14, Seat.depth / 2), chamfer: 0.01))
        return chair
    }

    static func bed(level: Int, floorTop: Double) -> SCNNode {
        if level == 0 {
            let b = SCNNode(geometry: SCNBox(width: 0.34, height: Minion.bedSeat, length: 0.72, chamferRadius: 0.02))
            b.geometry!.firstMaterial = lit(NSColor(Colors.bed).lighter(0.1))
            b.position = v3(0, max(0.005, floorTop + 0.004) + Minion.bedSeat / 2, 0)
            dress(b, top: Minion.bedSeat / 2)
            return b
        }
        let slab = SCNNode(geometry: SCNBox(width: 0.36, height: 0.03, length: 0.74, chamferRadius: 0))
        slab.geometry!.firstMaterial = lit(NSColor(Colors.bed).lighter(0.08))
        slab.position = v3(0, 0.34, 0)
        for dx in [-0.16, 0.16] { for dz in [-0.35, 0.35] {
            let post = SCNNode(geometry: SCNBox(width: 0.025, height: 0.34, length: 0.025, chamferRadius: 0))
            post.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.22, 0.3)))
            post.position = v3(dx, -0.17, dz)
            slab.addChildNode(post)
        } }
        dress(slab, top: 0.015)
        return slab
    }

    private static func dress(_ mattress: SCNNode, top: Double) {
        let head = -0.36, foot = 0.36
        let pillow = SCNNode(geometry: SCNBox(width: 0.24, height: 0.035, length: 0.14, chamferRadius: 0.012))
        pillow.geometry!.firstMaterial = lit(NSColor(Colors.bed).lighter(0.4))
        pillow.position = v3(0, top + 0.018, head + 0.11)
        mattress.addChildNode(pillow)
        let from = head + 0.24
        let covers = SCNNode(geometry: SCNBox(width: 0.355, height: 0.03, length: foot - from, chamferRadius: 0.008))
        covers.geometry!.firstMaterial = lit(NSColor(Colors.bed).darker(0.22))
        covers.position = v3(0, top + 0.014, (from + foot) / 2)
        mattress.addChildNode(covers)
    }
}
