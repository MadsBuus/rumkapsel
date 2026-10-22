import AppKit
import SceneKit

final class Minion: Body {
    var carried: SCNNode?
    var arcStarted = false
    var stowing: (cube: SCNNode, box: SCNNode)?
    var weldLight: SCNNode?
    private(set) var shadow: SCNNode!
    private(set) var hammerPivot: SCNNode?
    private(set) var lightPivot: SCNNode?
    enum Tool { case goggles, tablet, scanner, hammer, flashlight, clipboard, telekinesis, hands }
    private(set) var wandTip: SCNNode?
    private(set) var wandLight: SCNNode?
    private(set) var tool: Tool?
    private var toolNode: SCNNode?
    private let hold = SCNNode()

    var queuedCones: [SCNNode] = []
    var pyramids: [SCNNode] = []
    let node = SCNNode()
    private let body: SCNNode
    let tilt: SCNNode
    private let bodyHeight: Double
    private let bodyDepth: Double
    var smoothFacing = 0.0
    var drawnLean = SIMD2<Double>(0, 0)
    private var posed: Pose = .standing
    private var posedSeat = SIMD2<Double>(0, 0)
    private let legs = SCNNode()
    private let visor: SCNNode
    private let figure: SCNNode?
    private var suitKey = ""
    private let look: Look
    private var staticNode: SCNNode?
    var staticSeen = true
    private var towelNode: SCNNode?
    private var mugNode: SCNNode?
    private var mugSteam: [SCNNode] = []
    private var mealNode: SCNNode?
    private var meal: (bowl: SCNNode, food: SCNNode, spoon: SCNNode, steam: [SCNNode], crumbs: [SCNNode])?
    private var jetpackNode: SCNNode?
    private static let noise: [NSImage] = (0..<4).map { _ in
        let n = 5
        let img = NSImage(size: NSSize(width: n, height: n))
        img.lockFocus()
        for x in 0..<n { for y in 0..<n {
            NSColor(white: CGFloat.random(in: 0.25...0.9), alpha: 1).setFill()
            NSRect(x: x, y: y, width: 1, height: 1).fill()
        } }
        img.unlockFocus()
        return img
    }
    func setStatic(_ on: Bool, frame: Int) {
        if !on { retire(staticNode); staticNode = nil; return }
        if staticNode == nil {
            let p = SCNNode(geometry: SCNPlane(width: 0.34, height: 0.2))
            p.geometry!.firstMaterial = flat(.white)
            p.geometry!.firstMaterial?.diffuse.magnificationFilter = .nearest
            p.constraints = [SCNBillboardConstraint()]
            p.position = staticSpot
            p.renderingOrder = 20
            p.geometry!.firstMaterial?.readsFromDepthBuffer = false
            p.geometry!.firstMaterial?.writesToDepthBuffer = false
            node.addChildNode(p)
            arrive(p)
            staticNode = p
        }
        staticNode?.geometry?.firstMaterial?.diffuse.contents = Minion.noise[frame % Minion.noise.count]
        staticNode?.isHidden = !staticSeen
    }
    private var staticSpot: SCNVector3 {
        guard case .seated(let h, _) = posed else { return v3(0, bodyHeight * 0.3, 0) }
        return v3(posedSeat.x, h + bodyDepth * 0.4, posedSeat.y + bodyDepth * 0.9)
    }
    static let seat = 0.2
    static let seatedTorso = 0.62
    static let couchSeat = 0.18
    static let bedSeat = 0.18
    var seatHeight: Double { sittingOn ?? (seatedOnBowl ? Minion.seat : Minion.couchSeat) }

    func currentPose(at clock: Double) -> Pose {
        let onEdge = Pose.seated(height: Minion.bedSeat, at: SIMD2(0, 0))
        if onBench { return .flat(height: Minion.seat) }
        if beddingUntil > clock {
            return beddingUntil - clock > Minion.riseSit ? onEdge : .flat(height: Minion.bedSeat)
        }
        if lying { return .flat(height: Minion.bedSeat) }
        if risingUntil > clock {
            return risingUntil - clock > Minion.riseSit ? onEdge : .standing
        }
        if seated { return .seated(height: seatHeight, at: seatSpot) }
        return .standing
    }

    static let bedEdge = 0.17
    override init(id: String, station: String, home: Home, cwd: String, toolCount: Int, isSubagent: Bool, start: Cell, crew: Bool = false) {
        let h = isSubagent ? 0.34 : 0.5
        let w = isSubagent ? 0.16 : 0.22
        let d = isSubagent ? 0.08 : 0.11
        let body = SCNNode(geometry: SCNBox(width: w, height: h, length: d, chamferRadius: 0.01))
        body.geometry!.firstMaterial = lit(crew ? NSColor(rgb: (0.62, 0.64, 0.7)) : Palette.minion)
        body.position = v3(0, h / 2, 0)
        let visor = SCNNode(geometry: SCNBox(width: w * 0.5, height: h * 0.1, length: 0.012, chamferRadius: 0))
        visor.geometry!.firstMaterial = flat(Palette.core)
        visor.position = v3(0, h * 0.3, d / 2 + 0.004)
        body.addChildNode(visor)
        let thighs = SCNNode(geometry: SCNBox(width: w, height: d, length: d * 2.6, chamferRadius: 0.01))
        thighs.geometry!.firstMaterial = body.geometry!.firstMaterial
        thighs.position = v3(0, d / 2, d * 0.8)
        let shins = SCNNode(geometry: SCNBox(width: w, height: Minion.seat + d, length: d, chamferRadius: 0.01))
        shins.geometry!.firstMaterial = body.geometry!.firstMaterial
        shins.position = v3(0, (d - Minion.seat) / 2, d * 1.6)
        legs.addChildNode(thighs); legs.addChildNode(shins)
        legs.opacity = 0
        let look = Looks.current
        let figure = isSubagent ? nil : look.figure(id: id, crew: crew, height: h)
        if isSubagent {
            body.geometry = nil
            visor.isHidden = true
            body.addChildNode(Probe.build())
        } else if let figure {
            body.geometry = nil
            visor.isHidden = true
            body.addChildNode(figure)
            look.pose(figure: figure, height: h, torso: h)
        }
        body.addChildNode(hold)
        let tiltNode = SCNNode()
        tiltNode.addChildNode(body)
        tiltNode.addChildNode(legs)
        node.addChildNode(tiltNode)
        let shadow = SCNNode(geometry: SCNPlane(width: w * 1.6, height: d * 3.2))
        shadow.geometry!.firstMaterial = flat(Palette.void)
        shadow.opacity = 0.35
        shadow.eulerAngles.x = -.pi / 2
        shadow.position = v3(0.03, 0.003, 0.02)
        shadow.name = "minion:" + id
        node.addChildNode(shadow)
        self.shadow = shadow
        self.tilt = tiltNode
        self.body = body
        self.bodyHeight = h
        self.bodyDepth = d
        self.visor = visor
        self.figure = figure
        self.look = look
        super.init(id: id, station: station, home: home, cwd: cwd, toolCount: toolCount, isSubagent: isSubagent, start: start, crew: crew)
        node.name = "minion:" + id
        body.name = node.name
        figure?.name = node.name
        visor.name = node.name
        legs.name = node.name; thighs.name = node.name; shins.name = node.name
        node.opacity = 0
        opacity = -Double.random(in: 0...0.9)
    }

    var headHeight: Double { bodyHeight }

    static let hammerRest = -1.05, hammerStrike = 0.55

    func setTool(_ t: Tool?) {
        guard t != tool else { return }
        tool = t
        retire(toolNode)
        toolNode = nil
        hammerPivot = nil; lightPivot = nil; wandTip = nil; wandLight = nil
        guard let t else { return }
        let n = SCNNode()
        let dark = lit(NSColor(rgb: (0.2, 0.21, 0.26)))
        let w = 0.22, h = bodyHeight, d = bodyDepth
        if let own = Looks.current.tool(t, height: h, depth: d) {
            n.addChildNode(own)
            hammerPivot = own.childNode(withName: "swing", recursively: true)
            lightPivot = own.childNode(withName: "aim", recursively: true)
            wandTip = own.childNode(withName: "wandTip", recursively: true)
            wandLight = own.childNode(withName: "wandLight", recursively: true)
            n.name = node.name
            hold.addChildNode(n)
            arrive(n)
            toolNode = n
            return
        }
        switch t {
        case .goggles:
            let band = SCNNode(geometry: SCNBox(width: w * 0.9, height: h * 0.12, length: 0.025, chamferRadius: 0))
            band.geometry!.firstMaterial = dark
            band.position = v3(0, h * 0.34, d / 2 + 0.015)
            for side in [-1.0, 1.0] {
                let lens = SCNNode(geometry: SCNBox(width: 0.07, height: 0.05, length: 0.015, chamferRadius: 0))
                lens.geometry!.firstMaterial = flat(NSColor(rgb: (0.45, 0.85, 0.75)))
                lens.position = v3(side * 0.05, 0, 0.02)
                band.addChildNode(lens)
            }
            n.addChildNode(band)
        case .tablet:
            let slab = SCNNode(geometry: SCNBox(width: 0.18, height: 0.012, length: 0.13, chamferRadius: 0))
            slab.geometry!.firstMaterial = dark
            slab.position = v3(0, h * 0.26, d / 2 + 0.09)
            slab.eulerAngles.x = -0.35
            let screen = SCNNode(geometry: SCNBox(width: 0.15, height: 0.004, length: 0.1, chamferRadius: 0))
            screen.geometry!.firstMaterial = flat(NSColor(rgb: (0.55, 0.85, 1.0)))
            screen.position = v3(0, 0.008, 0)
            slab.addChildNode(screen)
            n.addChildNode(slab)
        case .scanner:
            let grip = SCNNode(geometry: SCNBox(width: 0.05, height: 0.05, length: 0.2, chamferRadius: 0))
            grip.geometry!.firstMaterial = dark
            grip.position = v3(0.06, h * 0.3, d / 2 + 0.11)
            let tip = SCNNode(geometry: SCNBox(width: 0.06, height: 0.06, length: 0.03, chamferRadius: 0))
            tip.geometry!.firstMaterial = flat(NSColor(rgb: (0.4, 1.0, 0.8)))
            tip.position = v3(0, 0, 0.11)
            tip.name = "tip"
            grip.addChildNode(tip)
            n.addChildNode(grip)
        case .hammer:
            let pivot = SCNNode()
            pivot.position = v3(0.07, h * 0.42, d / 2 + 0.04)
            pivot.eulerAngles.x = Minion.hammerRest
            let handle = SCNNode(geometry: SCNBox(width: 0.03, height: 0.03, length: 0.26, chamferRadius: 0))
            handle.geometry!.firstMaterial = lit(NSColor(rgb: (0.6, 0.45, 0.3)))
            handle.position = v3(0, 0, 0.13)
            let head = SCNNode(geometry: SCNBox(width: 0.08, height: 0.1, length: 0.06, chamferRadius: 0))
            head.geometry!.firstMaterial = dark
            head.position = v3(0, 0, 0.12)
            handle.addChildNode(head)
            pivot.addChildNode(handle)
            n.addChildNode(pivot)
            hammerPivot = pivot
        case .hands:
            for side in [-1.0, 1.0] {
                let hand = SCNNode(geometry: SCNBox(width: 0.06, height: 0.06, length: 0.1, chamferRadius: 0))
                hand.geometry!.firstMaterial = lit(NSColor(rgb: (0.72, 0.74, 0.8)))
                hand.position = v3(side * w * 0.28, h * 0.4, d / 2 + 0.07)
                n.addChildNode(hand)
            }
        case .clipboard:
            let board = SCNNode(geometry: SCNBox(width: 0.15, height: 0.19, length: 0.012, chamferRadius: 0))
            board.geometry!.firstMaterial = lit(NSColor(rgb: (0.45, 0.34, 0.24)))
            board.position = v3(w / 2 + 0.05, h * 0.24, d / 2 + 0.02)
            board.eulerAngles = SCNVector3(0.25, -0.5, 0.15)
            let paper = SCNNode(geometry: SCNBox(width: 0.12, height: 0.15, length: 0.004, chamferRadius: 0))
            paper.geometry!.firstMaterial = flat(NSColor(rgb: (0.9, 0.9, 0.86)))
            paper.position = v3(0, -0.01, 0.009)
            board.addChildNode(paper)
            let clip = SCNNode(geometry: SCNBox(width: 0.07, height: 0.025, length: 0.012, chamferRadius: 0))
            clip.geometry!.firstMaterial = flat(NSColor(rgb: (0.62, 0.65, 0.72)))
            clip.position = v3(0, 0.08, 0.012)
            board.addChildNode(clip)
            n.addChildNode(board)
        case .telekinesis:
            let pivot = SCNNode()
            pivot.position = v3(0.07, h * 0.36, d / 2 + 0.04)
            pivot.eulerAngles.x = -0.5
            let shaft = SCNNode(geometry: faceted(SCNCylinder(radius: 0.022, height: 0.2), 5))
            shaft.geometry!.firstMaterial = dark
            shaft.eulerAngles.x = .pi / 2
            shaft.position = v3(0, 0, 0.1)
            pivot.addChildNode(shaft)
            let tip = SCNNode(geometry: faceted(SCNCone(topRadius: 0, bottomRadius: 0.04, height: 0.09), 5))
            tip.geometry!.firstMaterial = flat(NSColor(rgb: (0.62, 0.9, 1.0)))
            tip.eulerAngles.x = .pi / 2
            tip.position = v3(0, 0, 0.23)
            tip.opacity = 0.45
            pivot.addChildNode(tip)
            let light = SCNNode()
            light.light = SCNLight()
            light.light!.type = .omni
            light.light!.color = NSColor(rgb: (0.62, 0.9, 1.0))
            light.light!.intensity = 0
            light.light!.attenuationEndDistance = 2.0
            light.position = v3(0, 0, 0.24)
            pivot.addChildNode(light)
            n.addChildNode(pivot)
            wandTip = tip
            wandLight = light
        case .flashlight:
            let pivot = SCNNode()
            pivot.position = v3(0.06, h * 0.34, d / 2 + 0.04)
            let barrel = SCNNode(geometry: faceted(SCNCylinder(radius: 0.025, height: 0.12), 4))
            barrel.geometry!.firstMaterial = dark
            barrel.eulerAngles.x = .pi / 2
            barrel.position = v3(0, 0, 0.06)
            pivot.addChildNode(barrel)
            let lens = SCNNode(geometry: faceted(SCNCylinder(radius: 0.028, height: 0.01), 4))
            lens.geometry!.firstMaterial = flat(NSColor(rgb: (1.0, 0.95, 0.7)))
            lens.eulerAngles.x = .pi / 2
            lens.position = v3(0, 0, 0.125)
            pivot.addChildNode(lens)
            let beamLength = 0.9
            let beam = SCNNode(geometry: faceted(SCNCone(topRadius: 0.028, bottomRadius: 0.22, height: beamLength)))
            beam.geometry!.firstMaterial = flat(NSColor(rgb: (1.0, 0.95, 0.75)))
            beam.geometry!.firstMaterial?.transparency = 0.18
            beam.geometry!.firstMaterial?.writesToDepthBuffer = false
            beam.geometry!.firstMaterial?.isDoubleSided = true
            beam.eulerAngles.x = -.pi / 2
            beam.position = v3(0, 0, 0.13 + beamLength / 2)
            pivot.addChildNode(beam)
            let light = SCNNode()
            light.light = SCNLight()
            light.light!.type = .spot
            light.light!.color = NSColor(rgb: (1.0, 0.95, 0.75))
            light.light!.intensity = 900
            light.light!.spotInnerAngle = 12
            light.light!.spotOuterAngle = 32
            light.light!.attenuationEndDistance = 2.2
            light.eulerAngles.y = .pi
            light.position = v3(0, 0, 0.13)
            pivot.addChildNode(light)
            n.addChildNode(pivot)
            lightPivot = pivot
        }
        n.name = node.name
        hold.addChildNode(n)
        arrive(n)
        toolNode = n
    }

    func setWand(lifting: Bool) {
        wandTip?.opacity = lifting ? 1 : 0.45
        wandLight?.light?.intensity = lifting ? 420 : 0
    }

    func blinkScanner(_ on: Bool) {
        toolNode?.childNodes.first?.childNode(withName: "tip", recursively: false)?.opacity = on ? 1 : 0.25
    }

    enum Pose: Equatable {
        case standing
        case seated(height: Double, at: SIMD2<Double>)
        case flat(height: Double)
    }

    func mirror(station: Station, clock: Double, dt: Double, outfit: Routines.Outfit, hover: Double = 0) {
        setPose(currentPose(at: clock))
        wear(outfit, clock: clock, dt: dt)
        let resting = path.isEmpty && state == .settled
        let hop = isJumping(at: clock) && resting && place != .lounge && using == nil && !bathing && fare == nil ? Routines.hop(clock: clock, phase: bobPhase) : 0
        drawnLean += (lean - drawnLean) * min(1, dt * 8)
        node.position = v3(station.offset.x + pos.x + drawnLean.x, hover + hop, station.offset.y + pos.y + drawnLean.y)
        shadow.position.y = CGFloat(0.003 - hop - hover)
        let up = CGFloat(max(0.4, 1 - hover * 0.9))
        shadow.scale = SCNVector3(up, up, up)
        node.opacity = opacity
    }

    private func wear(_ o: Routines.Outfit, clock: Double, dt: Double) {
        setTool(o.tool)
        setStatic(o.pixels, frame: Int(clock * 12))
        setTowel(o.towel)
        setJetpack(o.jetpack, clock: clock)
        setMug(o.mug, clock: clock)
        setMeal(o.meal, clock: clock)
        if isSubagent { Probe.show(body, scanning: o.scan, carrying: o.shard, clock: clock, phase: bobPhase) }
        stepFades(dt)
    }

    static let fadeSeconds = 0.22
    private var fading: [(node: SCNNode, left: Double, out: Bool)] = []

    private func retire(_ node: SCNNode?) {
        guard let node else { return }
        fading.removeAll { $0.node === node }
        fading.append((node, Minion.fadeSeconds, true))
    }

    private func arrive(_ node: SCNNode) {
        node.opacity = 0
        fading.append((node, Minion.fadeSeconds, false))
    }

    func stepFades(_ dt: Double) {
        guard !fading.isEmpty else { return }
        for i in fading.indices { fading[i].left -= dt }
        for f in fading where f.left <= 0 && f.out { f.node.removeFromParentNode() }
        for f in fading where f.left <= 0 && !f.out { f.node.opacity = 1 }
        fading.removeAll { $0.left <= 0 }
        for f in fading {
            let through = max(0, min(1, f.left / Minion.fadeSeconds))
            f.node.opacity = CGFloat(f.out ? through : 1 - through)
        }
    }

    var showsBathPixels: Bool { staticNode != nil }
    var showsTowel: Bool { towelNode != nil }
    var holding: Tool? { tool }

    func setPose(_ p: Pose) {
        guard p != posed else { return }
        let was = posed
        posed = p
        body.removeAllActions()

        let torso = bodyHeight * Minion.seatedTorso
        let seat: SIMD2<Double>, boxHeight: Double, pitch: Double, at: SCNVector3
        switch p {
        case .standing:
            seat = SIMD2(0, 0); boxHeight = bodyHeight; pitch = 0
            at = v3(0, bodyHeight / 2, 0)
        case .seated(let height, let offset):
            seat = offset; boxHeight = torso; pitch = -0.1
            let back = offset.y - Minion.seatReach
            at = v3(offset.x, height + torso / 2, back)
            legs.position = v3(offset.x, height, back)
        case .flat(let height):
            seat = SIMD2(0, 0); boxHeight = bodyHeight; pitch = -.pi / 2
            at = v3(0, height + bodyDepth / 2, 0)
        }
        posedSeat = seat
        let sitting = boxHeight == torso

        let t = Minion.poseSeconds(from: was, to: p)
        let move = SCNAction.group([.rotateTo(x: pitch, y: 0, z: 0, duration: t, usesShortestUnitArc: true),
                                    .move(to: at, duration: t)])
        move.timingMode = .easeOut
        body.runAction(move)

        hold.runAction(.move(to: v3(0, (boxHeight - bodyHeight) / 2, 0), duration: t))
        visor.runAction(.move(to: v3(0, boxHeight * 0.3, bodyDepth / 2 + 0.004), duration: t))
        SCNTransaction.begin()
        SCNTransaction.animationDuration = t
        if let figure {
            look.pose(figure: figure, height: bodyHeight, torso: boxHeight)
        } else {
            (body.geometry as? SCNBox)?.height = boxHeight
            legs.opacity = sitting ? 1 : 0
        }
        SCNTransaction.commit()
        staticNode?.runAction(.move(to: staticSpot, duration: t))
        shadow.runAction(.move(to: v3(0.03 + seat.x, 0.003, 0.02 + seat.y), duration: t))
    }

    private static func poseSeconds(from: Pose, to: Pose) -> Double {
        if case .flat = from, case .seated = to { return 0.45 }
        if case .flat = to { return 0.7 }
        if case .standing = to { return 0.45 }
        return 0.5
    }

    func setTowel(_ on: Bool) {
        if !on { retire(towelNode); towelNode = nil; return }
        guard towelNode == nil else { return }
        let t = SCNNode(geometry: SCNBox(width: 0.3, height: 0.05, length: bodyDepth + 0.1, chamferRadius: 0.004))
        t.geometry!.firstMaterial = lit(NSColor(rgb: (0.93, 0.56, 0.46)))
        t.position = v3(0, bodyHeight / 2 - 0.01, 0)
        let stripe = SCNNode(geometry: SCNBox(width: 0.31, height: 0.02, length: 0.05, chamferRadius: 0))
        stripe.geometry!.firstMaterial = flat(NSColor(rgb: (0.98, 0.9, 0.82)))
        stripe.position = v3(0, 0.02, 0)
        t.addChildNode(stripe)
        body.addChildNode(t)
        arrive(t)
        towelNode = t
    }

    func setMug(_ on: Bool, clock: Double) {
        guard on else { retire(mugNode); mugNode = nil; return }
        let mug = mugNode ?? {
            let m = Kitchen.mug()
            mugSteam = Kitchen.steam(over: Kitchen.mugHeight / 2)
            mugSteam.forEach(m.addChildNode)
            m.name = node.name
            hold.addChildNode(m)
            arrive(m)
            mugNode = m
            return m
        }()
        let cycle = (clock * 0.11 + bobPhase).truncatingRemainder(dividingBy: 1)
        let sip = cycle < 0.12 ? sin(cycle / 0.12 * .pi) : 0
        mug.position = v3(0.16 - sip * 0.1, bodyHeight * (0.1 + sip * 0.26), bodyDepth / 2 + 0.06 - sip * 0.02)
        mug.eulerAngles.x = CGFloat(-sip * 0.6)
        Kitchen.rise(mugSteam, over: Kitchen.mugHeight / 2, at: clock + bobPhase)
    }

    func setMeal(_ left: Double?, clock: Double) {
        guard let left else { retire(mealNode); mealNode = nil; meal = nil; return }
        if meal == nil {
            let holder = SCNNode()
            let parts = Kitchen.bowl()
            holder.addChildNode(parts.bowl)
            let spoon = SCNNode(geometry: SCNBox(width: 0.014, height: 0.012, length: 0.08, chamferRadius: 0.003))
            spoon.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.77, 0.82)))
            holder.addChildNode(spoon)
            let steam = Kitchen.steam(over: 0.04)
            steam.forEach(parts.bowl.addChildNode)
            let crumbs = (0..<3).map { i -> SCNNode in
                let c = SCNNode(geometry: SCNBox(width: 0.012, height: 0.012, length: 0.012, chamferRadius: 0))
                c.geometry!.firstMaterial = lit(i == 1 ? NSColor(rgb: (0.4, 0.75, 0.38)) : NSColor(rgb: (0.93, 0.6, 0.25)))
                holder.addChildNode(c)
                return c
            }
            holder.name = node.name
            hold.addChildNode(holder)
            arrive(holder)
            mealNode = holder
            meal = (parts.bowl, parts.food, spoon, steam, crumbs)
        }
        guard let meal, let holder = mealNode else { return }
        holder.position = v3(0, bodyHeight * 0.08, bodyDepth / 2 + 0.07)
        let food = CGFloat(max(0.02, Timing.clamped((left - 0.2) / 0.8)))
        meal.food.scale = SCNVector3(food, food, food)
        let bowl = CGFloat(max(0.02, Timing.clamped(left / 0.2)))
        meal.bowl.scale = SCNVector3(bowl, bowl, bowl)
        let cycle = (clock / 2.8 + bobPhase).truncatingRemainder(dividingBy: 1)
        let up = cycle < 0.5 ? sin(cycle / 0.5 * .pi) : 0
        meal.spoon.position = v3(0.02, 0.03 + up * bodyHeight * 0.24, 0.01 + up * 0.02)
        meal.spoon.eulerAngles.x = CGFloat(0.3 - up * 0.9)
        for (i, c) in meal.crumbs.enumerated() {
            let k = Timing.clamped((cycle - 0.45 - Double(i) * 0.04) / 0.3)
            c.isHidden = k <= 0 || k >= 1 || left < 0.05
            c.position = v3(0.02 + Double(i - 1) * 0.015, 0.03 + bodyHeight * 0.2 * (1 - k) - k * 0.12, 0.03)
            c.opacity = CGFloat(1 - k)
        }
        Kitchen.rise(meal.steam, over: 0.04, at: clock + bobPhase)
        meal.steam.forEach { $0.isHidden = left < 0.35 }
    }

    func setJetpack(_ thrust: Double?, clock: Double) {
        guard let thrust else { retire(jetpackNode); jetpackNode = nil; return }
        let pack = jetpackNode ?? {
            let p = Looks.current.jetpack(height: bodyHeight, depth: bodyDepth) ?? Minion.jetpack(height: bodyHeight)
            p.position = v3(0, 0, -bodyDepth / 2)
            body.addChildNode(p)
            arrive(p)
            jetpackNode = p
            return p
        }()
        var k = 0
        pack.enumerateChildNodes { c, _ in
            guard c.name == "flame" else { return }
            let flicker = 0.75 + 0.25 * sin(clock * 47 + Double(k) * 2.1) * sin(clock * 31 + Double(k))
            let s = CGFloat(thrust * flicker)
            c.scale = SCNVector3(max(0.01, s * 0.8 + 0.2), max(0.01, s), max(0.01, s * 0.8 + 0.2))
            c.isHidden = thrust <= 0
            k += 1
        }
        pack.childNode(withName: "exhaust", recursively: true)?.light?.intensity = CGFloat(thrust * (250 + 120 * sin(clock * 40)))
    }

    static func jetpack(height h: Double) -> SCNNode {
        let n = SCNNode()
        let steel = lit(NSColor(rgb: (0.55, 0.57, 0.62))), dark = lit(NSColor(rgb: (0.25, 0.26, 0.3)))
        let pack = SCNNode(geometry: SCNBox(width: 0.15, height: h * 0.42, length: 0.06, chamferRadius: 0.008))
        pack.geometry!.firstMaterial = steel
        pack.position = v3(0, h * 0.06, -0.03)
        n.addChildNode(pack)
        let flameMaterial = flat(NSColor(rgb: (1.0, 0.72, 0.3)))
        flameMaterial.emission.contents = NSColor(rgb: (1.0, 0.55, 0.15))
        for x in [-0.045, 0.045] {
            let thruster = SCNNode(geometry: faceted(SCNCylinder(radius: 0.03, height: h * 0.36)))
            thruster.geometry!.firstMaterial = dark
            thruster.position = v3(x, h * 0.02, -0.075)
            n.addChildNode(thruster)
            let nozzle = SCNNode(geometry: faceted(SCNCone(topRadius: 0.022, bottomRadius: 0.032, height: 0.03)))
            nozzle.geometry!.firstMaterial = dark
            nozzle.position = v3(x, h * 0.02 - h * 0.18 - 0.015, -0.075)
            n.addChildNode(nozzle)
            let flame = SCNNode()
            flame.name = "flame"
            flame.position = v3(x, h * 0.02 - h * 0.18 - 0.03, -0.075)
            let cone = SCNNode(geometry: faceted(SCNCone(topRadius: 0.032, bottomRadius: 0, height: 0.24)))
            cone.geometry!.firstMaterial = flameMaterial
            cone.position = v3(0, -0.12, 0)
            flame.addChildNode(cone)
            n.addChildNode(flame)
        }
        let glow = SCNNode()
        glow.name = "exhaust"
        glow.light = SCNLight()
        glow.light!.type = .omni
        glow.light!.color = NSColor(rgb: (1.0, 0.6, 0.25))
        glow.light!.attenuationEndDistance = 0.9
        glow.light!.intensity = 0
        glow.position = v3(0, -h * 0.3, -0.075)
        n.addChildNode(glow)
        return n
    }

    func fidget() {
        guard case .seated = posed, !body.hasActions else { return }
        let side = Bool.random() ? 0.08 : -0.08
        let over = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(side), duration: 0.18); over.timingMode = .easeInEaseOut
        let back = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(-side), duration: 0.28); back.timingMode = .easeInEaseOut
        body.runAction(.sequence([over, .wait(duration: 0.3), back]))
    }
}

extension Minion {
    func wearSuit(badge: NSColor) {
        if isSubagent {
            body.childNode(withName: "stripe", recursively: true)?.geometry?.firstMaterial = lit(badge)
            return
        }
        guard figure == nil, let box = body.geometry as? SCNBox else { return }
        let kind: Suit.Kind = isPeer ? .neighbour : isCrew ? .crew : .white
        let key = Suit.key(badge, kind)
        guard suitKey != key else { return }
        suitKey = key
        box.chamferRadius = 0
        box.materials = Suit.materials(kind)
        for part in legs.childNodes { part.geometry?.firstMaterial = Suit.materials(kind)[4] }
        visor.geometry?.firstMaterial = Suit.visor
        let p = Suit.patch, w = Double(box.width), h = Double(box.height), d = Double(box.length)
        let patch = body.childNode(withName: "patch", recursively: false) ?? {
            let plane = SCNPlane(width: w * (p.x1 - p.x0), height: h * (p.y1 - p.y0))
            plane.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: 3.5)]
            let n = SCNNode(geometry: plane)
            n.name = "patch"
            n.position = v3(w * ((p.x0 + p.x1) / 2 - 0.5), h * (0.5 - (p.y0 + p.y1) / 2), d / 2 + 0.001)
            body.addChildNode(n)
            return n
        }()
        patch.geometry?.firstMaterial = flat(Suit.patchColor(badge, kind))
    }
}
