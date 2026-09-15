// The classic furniture of the fixed rooms, the default for every look: the lounge, the bath, the gym and
// the beds. Pieces are placed in the world as the room stands; the scene names them and animates the ones
// it moves.

import AppKit
import SceneKit

/// What a fixed room is furnished with. `props` are solid and named for the room, so the pointer finds
/// them; `fixtures` are stood on, lain on and stepped round, named for the gym; `bar`, `bag` and `towel`
/// are the pieces the scene moves, each also among the others.
struct Furnishing {
    var props: [SCNNode] = []
    var fixtures: [SCNNode] = []
    var bar: SCNNode?
    var bag: SCNNode?
    var towel: SCNNode?
}

extension Classic {
    static func lounge(_ lounge: Room, in station: Station) -> Furnishing {
        var f = Furnishing()
        let cx = Double(lounge.cells.map(\.x).reduce(0, +)) / Double(lounge.cells.count)
        let cy = Double(lounge.cells.map(\.y).reduce(0, +)) / Double(lounge.cells.count)
        // A low coffee table: a thin top on two side panels, with a magazine left on it.
        let table = SCNNode(geometry: SCNBox(width: 0.9, height: 0.03, length: 0.4, chamferRadius: 0))
        table.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.42, 0.3)))
        table.position = v3(station.offset.x + cx, 0.2, station.offset.y + cy)
        for lx in [-0.4, 0.4] {
            let panel = SCNNode(geometry: SCNBox(width: 0.03, height: 0.19, length: 0.34, chamferRadius: 0))
            panel.geometry!.firstMaterial = lit(NSColor(rgb: (0.42, 0.32, 0.24)))
            panel.position = v3(lx, -0.1, 0)
            table.addChildNode(panel)
        }
        let magazine = SCNNode(geometry: SCNBox(width: 0.16, height: 0.01, length: 0.22, chamferRadius: 0))
        magazine.geometry!.firstMaterial = flat(NSColor(rgb: (0.85, 0.85, 0.8)))
        magazine.position = v3(0.15, 0.02, 0.02)
        magazine.eulerAngles.y = 0.3
        table.addChildNode(magazine)
        f.props.append(table)
        let lxs = lounge.cells.map(\.x)
        for c in station.couches {
            let along = c.x < Double(lxs.min()!) - 0.1 || c.x > Double(lxs.max()!) + 0.1   // side walls run along z, the far wall along x
            let couch = SCNNode(geometry: SCNBox(width: along ? 0.3 : 0.8, height: 0.18, length: along ? 0.8 : 0.3, chamferRadius: 0.02))
            couch.geometry!.firstMaterial = lit(NSColor(rgb: (0.62, 0.45, 0.4)))
            couch.position = v3(station.offset.x + c.x, 0.09, station.offset.y + c.y)
            let back = SCNNode(geometry: SCNBox(width: along ? 0.08 : 0.8, height: 0.22, length: along ? 0.8 : 0.08, chamferRadius: 0.02))
            back.geometry!.firstMaterial = couch.geometry!.firstMaterial
            back.position = v3(along ? (c.x < cx ? -0.11 : 0.11) : 0, 0.16, along ? 0 : 0.11)
            couch.addChildNode(back)
            f.props.append(couch)
        }
        // A potted plant in one corner and a low shelf in another: somewhere to look at.
        let xs = lounge.cells.map(\.x), ys = lounge.cells.map(\.y)
        // A square pot with a few flat leaves fanned out on a thin stem.
        let pot = SCNNode(geometry: SCNBox(width: 0.2, height: 0.16, length: 0.2, chamferRadius: 0))
        pot.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.5, 0.35)))
        pot.position = v3(station.offset.x + Double(xs.min()!) - 0.28, 0.08, station.offset.y + Double(ys.min()!) - 0.28)
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
        shelf.geometry!.firstMaterial = lit(NSColor(rgb: (0.5, 0.4, 0.32)))
        shelf.position = v3(station.offset.x + Double(xs.max()!), 0.16, station.offset.y + Double(ys.min()!) - 0.32)
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
        // A toilet in one corner and a shower in another, neither in the doorway nor on the sign.
        let fx = station.bathFixtures(bath: bath)
        let sc2 = fx.shower, tk = fx.toiletCorner, sk = fx.showerCorner
        // A WC, square to the walls: a pedestal, the seat on it at Minion.seat, a dark inset
        // for the hole, and the tank standing on the back of the seat against the wall.
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
        // The shower: a nozzle on a short arm off the corner wall, and a drain in the floor below it.
        let arm = SCNNode(geometry: SCNBox(width: 0.04, height: 0.04, length: 0.2, chamferRadius: 0))
        arm.geometry!.firstMaterial = lit(NSColor(rgb: (0.7, 0.72, 0.78)))
        arm.position = v3(station.offset.x + Double(sc2.x) + 0.3 * sk.x, 0.72, station.offset.y + Double(sc2.y) + 0.35 * sk.y)   // clear of a head
        let nozzle = SCNNode(geometry: SCNBox(width: 0.1, height: 0.04, length: 0.1, chamferRadius: 0))
        nozzle.geometry!.firstMaterial = arm.geometry!.firstMaterial
        nozzle.position = v3(0, -0.03, -0.1 * sk.y)
        arm.addChildNode(nozzle)
        f.props.append(arm)
        // The pole the arm comes off: a pipe up the corner wall from the floor, a tap at waist height.
        let pole = SCNNode(geometry: SCNBox(width: 0.04, height: 0.72, length: 0.04, chamferRadius: 0))
        pole.geometry!.firstMaterial = arm.geometry!.firstMaterial
        pole.position = v3(station.offset.x + Double(sc2.x) + 0.3 * sk.x, 0.36, station.offset.y + Double(sc2.y) + 0.45 * sk.y)
        let tap = SCNNode(geometry: SCNBox(width: 0.07, height: 0.03, length: 0.05, chamferRadius: 0))
        tap.geometry!.firstMaterial = arm.geometry!.firstMaterial
        tap.position = v3(0, 0.0, -0.04 * sk.y)   // waist height on the pole, out from the wall
        pole.addChildNode(tap)
        f.props.append(pole)
        // A towel over a rail on the other wall of the corner, at the far end of the tile from the shower
        // so it never lines up with the nozzle in the picture. The scene takes it off the rail by name.
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
        drain.position = v3(station.offset.x + Double(sc2.x) + 0.3 * sk.x, 0.01, station.offset.y + Double(sc2.y) + 0.25 * sk.y)
        f.props.append(drain)
        return f
    }

    static func gym(_ gym: Room, in station: Station) -> Furnishing {
        var f = Furnishing()
        // Four fixtures on the four corner tiles: a treadmill, a bench with a barbell over it, a
        // bag on an arm, and a mat. The middle tiles stay clear to walk through.
        let spots = station.gymSpots(gym: gym)
        let dark = lit(NSColor(rgb: (0.22, 0.23, 0.28)))
        let steel = lit(NSColor(rgb: (0.66, 0.68, 0.74)))
        // Treadmill: a low slab with a rail at its head.
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
        // Bench and barbell: the bar rests on two uprights and rises for the presses.
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
        // The bag: a post in the corner with an arm out, and the bag hanging from it.
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
        let bag = SCNNode()   // pivot at the arm's end: the bag hangs from it and swings about it
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
        // The mat: a dark square on the floor.
        let mat = SCNNode(geometry: SCNBox(width: 0.7, height: 0.012, length: 0.7, chamferRadius: 0))
        mat.geometry!.firstMaterial = flat(NSColor(rgb: (0.26, 0.4, 0.34)))
        mat.position = v3(spots[3].x, 0.006, spots[3].y)
        f.fixtures.append(mat)
        return f
    }

    /// A bed flat on the floor, or the upper bunk: a slab on four thin posts. Centred on the origin; the
    /// scene moves it over its spot and keeps its height.
    static func bed(level: Int, floorTop: Double) -> SCNNode {
        if level == 0 {
            let b = SCNNode(geometry: SCNPlane(width: 0.34, height: 0.72))
            b.geometry!.firstMaterial = flat(NSColor(Colors.bed))
            b.eulerAngles.x = -.pi / 2
            b.position = v3(0, max(0.005, floorTop + 0.004), 0)
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
        return slab
    }
}
