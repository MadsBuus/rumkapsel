// One worker: its body, its tools, its poses. The state the simulation runs on is the `Body` it is.

import AppKit
import SceneKit

/// One Claude session, walking between the rooms of its station: a `Body` with a figure on it.
final class Minion: Body {
    /// The node drawn on the arms for the body's load, and whether its set-down arc has begun.
    var carried: SCNNode?
    var arcStarted = false
    /// The cube on the head for a stow, and the box on the floor it stands in for.
    var stowing: (cube: SCNNode, box: SCNNode)?
    var weldLight: SCNNode?
    private(set) var shadow: SCNNode!
    /// The hammer's grip end, so the swing pivots in the hand rather than at the handle's middle.
    private(set) var hammerPivot: SCNNode?
    /// The flashlight's grip, swept about to play its cone over the work.
    private(set) var lightPivot: SCNNode?
    enum Tool { case goggles, tablet, scanner, hammer, flashlight, clipboard, telekinesis, hands }
    /// The wand's tip and the little light in it, lit only while a crate is in the air.
    private(set) var wandTip: SCNNode?
    private(set) var wandLight: SCNNode?
    private(set) var tool: Tool?
    private var toolNode: SCNNode?
    /// What a body holds hangs here rather than on the box itself. Sitting shortens the box from the
    /// top down, so the mount drops by what the top drops and every tool follows without knowing why.
    private let hold = SCNNode()

    var queuedCones: [SCNNode] = []
    var pyramids: [SCNNode] = []
    let node = SCNNode()
    private let body: SCNNode
    let tilt: SCNNode
    private let bodyHeight: Double
    private let bodyDepth: Double
    var smoothFacing = 0.0
    /// The lean as drawn, eased toward the body's lean.
    var drawnLean = SIMD2<Double>(0, 0)
    /// What the figure is posed as right now, against what the body says it should be.
    private var posed: Pose = .standing
    private var posedSeat = SIMD2<Double>(0, 0)   // where the body sits, in the figure's own frame, zero when standing
    private let legs = SCNNode()                   // thighs out and shins down, the bend of a sit; unseen while standing
    private let visor: SCNNode
    /// The look's own figure in the box's place, when it has one; the box and its visor are then not drawn.
    private let figure: SCNNode?
    /// The look the figure came from, which poses it on a seat.
    private let look: Look
    private var staticNode: SCNNode?
    private var towelNode: SCNNode?
    /// A few frames of grey noise: the discreet blur over whoever is in the bath.
    private static let noise: [NSImage] = (0..<4).map { _ in
        let n = 5   // five fat pixels a side: coarse on purpose
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
        if !on { staticNode?.removeFromParentNode(); staticNode = nil; return }
        if staticNode == nil {
            // A small patch of pixels over the proper place, nothing more.
            let p = SCNNode(geometry: SCNPlane(width: 0.34, height: 0.2))   // wider than the body: pixel pants
            p.geometry!.firstMaterial = flat(.white)
            p.geometry!.firstMaterial?.diffuse.magnificationFilter = .nearest
            p.constraints = [SCNBillboardConstraint()]
            p.position = staticSpot
            // Drawn last and without depth, so the body's own faces never hide it.
            p.renderingOrder = 20
            p.geometry!.firstMaterial?.readsFromDepthBuffer = false
            p.geometry!.firstMaterial?.writesToDepthBuffer = false
            node.addChildNode(p)
            staticNode = p
        }
        staticNode?.geometry?.firstMaterial?.diffuse.contents = Minion.noise[frame % Minion.noise.count]
    }
    /// Where the pixels go: over the lap, which moves onto the seat with the body, and forward over the thighs.
    private var staticSpot: SCNVector3 {
        guard case .seated(let h, _) = posed else { return v3(0, bodyHeight * 0.3, 0) }
        return v3(posedSeat.x, h + bodyDepth * 0.4, posedSeat.y + bodyDepth * 0.9)
    }
    /// The top of the bowl, where a sitter's thighs rest.
    static let seat = 0.2
    /// How much of its height a body keeps as torso once it sits; the legs make up the rest.
    static let seatedTorso = 0.62
    /// The top of a couch, lower than the bowl. Read by both the prop and the pose.
    static let couchSeat = 0.18
    /// The top of a bunk's mattress: what a sleeper lies on, and sits on to get up, so it stands at a
    /// seat's height like the couch does rather than at a doormat's.
    static let bedSeat = 0.18
    /// How high the seat under this body is, by which seat it is on.
    var seatHeight: Double { seatedOnBowl ? Minion.seat : Minion.couchSeat }

    /// The one pose this body is in, from what it is doing. Flat beats sitting: a body on the bench is
    /// both on a seat and on its back, and it is its back that shows.
    ///
    /// Getting up off a bunk is the one pose that is two: nobody rises from flat on their back straight
    /// onto their feet. It swings round to sit on the edge of the mattress first, and stands from there.
    func currentPose(at clock: Double) -> Pose {
        let onEdge = Pose.seated(height: Minion.bedSeat, at: SIMD2(0, 0))
        if onBench { return .flat(height: Minion.seat) }
        // Into bed: sit on the edge, then stretch out along it. Out of bed: the same, backwards.
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

    /// How far off the middle of the bunk its edge is: where a sitter puts itself on the way up.
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
        // The legs of a sit: thighs level from the torso's foot forward, shins from their end down to the floor.
        let thighs = SCNNode(geometry: SCNBox(width: w, height: d, length: d * 2.6, chamferRadius: 0.01))
        thighs.geometry!.firstMaterial = body.geometry!.firstMaterial
        thighs.position = v3(0, d / 2, d * 0.8)
        let shins = SCNNode(geometry: SCNBox(width: w, height: Minion.seat + d, length: d, chamferRadius: 0.01))
        shins.geometry!.firstMaterial = body.geometry!.firstMaterial
        shins.position = v3(0, (d - Minion.seat) / 2, d * 1.6)
        legs.addChildNode(thighs); legs.addChildNode(shins)
        legs.opacity = 0
        // A look's own figure stands in for the box, hung from the box's middle so every pose that
        // turns or moves the body carries it along.
        let look = Looks.current
        let figure = look.figure(id: id, crew: crew, height: h)
        if let figure {
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
        opacity = -Double.random(in: 0...0.9)   // a moment of its own before it begins to show
    }

    var headHeight: Double { bodyHeight }

    /// Where the hammer rests (about one o'clock seen from the side) and where it lands, as pitches of its grip.
    static let hammerRest = -1.05, hammerStrike = 0.55

    /// Hold a tool: goggles, a tablet, a scanner or a hammer. Everything is flat-shaded boxes, held out
    /// in front along the body's facing direction, so it moves with the body's tilt. Nil puts it away.
    func setTool(_ t: Tool?) {
        guard t != tool else { return }
        tool = t
        toolNode?.removeFromParentNode()
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
            // A dark slab propped up from the belly, screen glowing back at the face, far edge raised.
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
            // A handheld scanner pointing forward with a bright tip.
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
            // Held at the grip: at rest it points up and a little forward, and swings down onto the work.
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
            // Both hands out at chest height: what you put on a heavy thing to shove it.
            for side in [-1.0, 1.0] {
                let hand = SCNNode(geometry: SCNBox(width: 0.06, height: 0.06, length: 0.1, chamferRadius: 0))
                hand.geometry!.firstMaterial = lit(NSColor(rgb: (0.72, 0.74, 0.8)))
                hand.position = v3(side * w * 0.28, h * 0.4, d / 2 + 0.07)
                n.addChildNode(hand)
            }
        case .clipboard:
            // A flat board held at the side, paper clipped to it.
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
            // A short faceted wand, held out front. Its tip lights while a crate is in the air.
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
            // A torch held out front, with its cone of light drawn as a soft translucent cone.
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
            light.eulerAngles.y = .pi   // a light shines down its -z; the torch points along +z
            light.position = v3(0, 0, 0.13)
            pivot.addChildNode(light)
            n.addChildNode(pivot)
            lightPivot = pivot
        }
        n.name = node.name
        hold.addChildNode(n)
        toolNode = n
    }

    /// The wand at work: the tip brightens and throws a little light while a crate is in the air.
    func setWand(lifting: Bool) {
        wandTip?.opacity = lifting ? 1 : 0.45
        wandLight?.light?.intensity = lifting ? 420 : 0
    }

    /// Blink the scanner tip, if held.
    func blinkScanner(_ on: Bool) {
        toolNode?.childNodes.first?.childNode(withName: "tip", recursively: false)?.opacity = on ? 1 : 0.25
    }

    /// How a body is held. Standing, sat on a seat of some height, or flat on its back — one answer,
    /// because they are not things that can be true at once. Everything hung on the body follows from
    /// this: the box's height, the face, whatever is held, the legs, the blur and the shadow.
    enum Pose: Equatable {
        case standing
        case seated(height: Double, at: SIMD2<Double>)
        case flat(height: Double)
    }

    /// Copies what the body is onto the figure you see: its pose, where it stands, how solid it is.
    /// This is not work the body does — it is the picture catching up to the facts — so it runs for
    /// every body every frame, whatever else that frame skips. It lives here rather than in the scene,
    /// so the gallery and the station draw a minion the one way.
    func mirror(station: Station, clock: Double, dt: Double) {
        setPose(currentPose(at: clock))
        // What is drawn follows the order in hand, never a flag the last order left behind.
        setStatic(bathing && phaseKind == .act && path.isEmpty, frame: Int(clock * 12))
        let resting = path.isEmpty && state == .settled
        let hop = isJumping(at: clock) && resting && place != .lounge && !bathing ? abs(sin(clock * 7 + bobPhase)) * 0.14 : 0   // nobody hops in the shower
        // The lean is drawing only: the body is on its line, the figure a shoulder to the side of it, eased in and out.
        drawnLean += (lean - drawnLean) * min(1, dt * 8)
        node.position = v3(station.offset.x + pos.x + drawnLean.x, hop, station.offset.y + pos.y + drawnLean.y)
        shadow.position.y = CGFloat(0.003 - hop)   // the shadow stays on the floor while the body hops
        node.opacity = opacity
    }

    /// Puts the figure into a pose. The only thing that moves the body node, so no two poses can fight
    /// over it, and the one place to look for what any of them does.
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
            // A sitter's feet stay where it was standing and the rest of it goes back: the shins reach
            // forward of the body, so the body sits that far behind the spot. Standing again is the
            // way back, the torso coming up over the feet.
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

        // The box shortens from the top down, so whatever is held drops by what the crown drops.
        hold.runAction(.move(to: v3(0, (boxHeight - bodyHeight) / 2, 0), duration: t))
        // The face keeps its place on the box: a third of the way up, whatever its height.
        visor.runAction(.move(to: v3(0, boxHeight * 0.3, bodyDepth / 2 + 0.004), duration: t))
        // The box shortens into a torso as the legs come out, and back to full height as they go.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = t
        if let figure {
            look.pose(figure: figure, height: bodyHeight, torso: boxHeight)   // legs of its own
        } else {
            (body.geometry as? SCNBox)?.height = boxHeight
            legs.opacity = sitting ? 1 : 0
        }
        SCNTransaction.commit()
        staticNode?.runAction(.move(to: staticSpot, duration: t))
        shadow.runAction(.move(to: v3(0.03 + seat.x, 0.003, 0.02 + seat.y), duration: t))
    }

    /// How long a change of pose takes: lying down is slower than sitting, standing up quicker than
    /// going down. Swinging round to sit on the edge of a bunk is quicker still, because the standing
    /// up has to follow it inside the moment the body is given to get up in.
    private static func poseSeconds(from: Pose, to: Pose) -> Double {
        if case .flat = from, case .seated = to { return 0.45 }
        if case .flat = to { return 0.7 }
        if case .standing = to { return 0.45 }
        return 0.5
    }


    /// A small shuffle on the seat: a lean to one side, held a beat, and back. Nothing while a pose is still settling.
    /// A towel over the shoulders, draped across the top of the body, or none.
    func setTowel(_ on: Bool) {
        if !on { towelNode?.removeFromParentNode(); towelNode = nil; return }
        guard towelNode == nil else { return }
        let t = SCNNode(geometry: SCNBox(width: 0.3, height: 0.05, length: bodyDepth + 0.1, chamferRadius: 0.004))
        t.geometry!.firstMaterial = lit(NSColor(rgb: (0.93, 0.56, 0.46)))
        t.position = v3(0, bodyHeight / 2 - 0.01, 0)
        let stripe = SCNNode(geometry: SCNBox(width: 0.31, height: 0.02, length: 0.05, chamferRadius: 0))
        stripe.geometry!.firstMaterial = flat(NSColor(rgb: (0.98, 0.9, 0.82)))
        stripe.position = v3(0, 0.02, 0)
        t.addChildNode(stripe)
        body.addChildNode(t)
        towelNode = t
    }

    func fidget() {
        guard case .seated = posed, !body.hasActions else { return }
        let side = Bool.random() ? 0.08 : -0.08
        let over = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(side), duration: 0.18); over.timingMode = .easeInEaseOut
        let back = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(-side), duration: 0.28); back.timingMode = .easeInEaseOut
        body.runAction(.sequence([over, .wait(duration: 0.3), back]))
    }

}
