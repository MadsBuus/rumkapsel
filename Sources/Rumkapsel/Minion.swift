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
    private var posedOnBench = false
    private var posedSeated = false
    private var posedLying = false
    private var posedSeat = SIMD2<Double>(0, 0)   // where the body sits, in the figure's own frame, zero when standing
    private let legs = SCNNode()                   // thighs out and shins down, the bend of a sit; unseen while standing
    private let visor: SCNNode
    private var staticNode: SCNNode?
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
    private var staticSpot: SCNVector3 { posedSeated ? v3(posedSeat.x, Minion.seat + bodyDepth * 0.4, posedSeat.y + bodyDepth * 0.9) : v3(0, bodyHeight * 0.3, 0) }
    /// The top of the bowl, where a sitter's thighs rest.
    static let seat = 0.2
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
        super.init(id: id, station: station, home: home, cwd: cwd, toolCount: toolCount, isSubagent: isSubagent, start: start, crew: crew)
        node.name = "minion:" + id
        body.name = node.name
        visor.name = node.name
        legs.name = node.name; thighs.name = node.name; shins.name = node.name
        node.opacity = 0
    }

    var headHeight: Double { bodyHeight }

    /// Hold a tool: goggles, a tablet, a scanner or a hammer. Everything is flat-shaded boxes, held out
    /// in front along the body's facing direction, so it moves with the body's tilt. Nil puts it away.
    /// Where the hammer rests (about one o'clock seen from the side) and where it lands, as pitches of its grip.
    static let hammerRest = -1.05, hammerStrike = 0.55

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
            // A dark slab held nearly flat in front, screen glowing, top edge toward the chest.
            let slab = SCNNode(geometry: SCNBox(width: 0.18, height: 0.012, length: 0.13, chamferRadius: 0))
            slab.geometry!.firstMaterial = dark
            slab.position = v3(0, h * 0.28, d / 2 + 0.09)
            slab.eulerAngles.x = 0.35
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
        body.addChildNode(n)
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

    /// Flat on the back on the bench, arms up, or off it again.
    func setBench(_ on: Bool) {
        guard on != posedOnBench else { return }
        posedOnBench = on
        body.removeAllActions()
        if on {
            body.runAction(.group([.rotateTo(x: -.pi / 2, y: 0, z: 0, duration: 0.5, usesShortestUnitArc: true), .move(to: v3(0, 0.2 + bodyDepth / 2, 0), duration: 0.5)]))
        } else {
            body.runAction(.group([.rotateTo(x: 0, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true), .move(to: v3(0, bodyHeight / 2, 0), duration: 0.4)]))
        }
    }

    /// Sit down on the bowl, its middle at `offset` in the figure's own frame (x across, z ahead, so
    /// behind when negative): the body bends into a sit, the torso upright on the seat, thighs out
    /// in front and shins down to the floor. Or straighten and stand back up onto the spot.
    func setSeated(_ on: Bool, at offset: SIMD2<Double> = SIMD2(0, 0)) {
        guard on != posedSeated else { return }
        posedSeated = on
        posedSeat = on ? offset : SIMD2(0, 0)
        body.removeAllActions()
        let torso = bodyHeight * 0.62
        let pose: SCNAction
        if on {
            pose = .group([.rotateTo(x: -0.1, y: 0, z: 0, duration: 0.5, usesShortestUnitArc: true),
                           .move(to: v3(offset.x, Minion.seat + torso / 2, offset.y), duration: 0.5)])
            legs.position = v3(offset.x, Minion.seat, offset.y)
        } else {
            pose = .group([.rotateTo(x: 0, y: 0, z: 0, duration: 0.45, usesShortestUnitArc: true),
                           .move(to: v3(0, bodyHeight / 2, 0), duration: 0.45)])
        }
        pose.timingMode = .easeOut
        body.runAction(pose)
        // The face keeps its place on the shorter box: a third of the way up, as on the full one.
        visor.runAction(.move(to: v3(0, (on ? torso : bodyHeight) * 0.3, bodyDepth / 2 + 0.004), duration: on ? 0.5 : 0.45))
        // The box itself shortens into a torso as the legs come out, and back to full height as they go.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = on ? 0.5 : 0.45
        (body.geometry as? SCNBox)?.height = on ? torso : bodyHeight
        legs.opacity = on ? 1 : 0
        SCNTransaction.commit()
        staticNode?.runAction(.move(to: staticSpot, duration: 0.5))
        // The shadow goes with the body onto the seat, and back to the spot.
        shadow.runAction(.move(to: v3(0.03 + posedSeat.x, 0.003, 0.02 + posedSeat.y), duration: on ? 0.5 : 0.45))
    }

    /// A small shuffle on the seat: a lean to one side, held a beat, and back. Nothing while a pose is still settling.
    func fidget() {
        guard posedSeated, !body.hasActions else { return }
        let side = Bool.random() ? 0.08 : -0.08
        let over = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(side), duration: 0.18); over.timingMode = .easeInEaseOut
        let back = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(-side), duration: 0.28); back.timingMode = .easeInEaseOut
        body.runAction(.sequence([over, .wait(duration: 0.3), back]))
    }

    /// Tip over onto the back in the dorm, or stand back up.
    func setSleeping(_ asleep: Bool) {
        guard asleep != posedLying else { return }
        posedLying = asleep
        body.removeAllActions()
        if asleep {
            body.runAction(.group([.rotateTo(x: -.pi / 2, y: 0, z: 0, duration: 0.7, usesShortestUnitArc: true), .move(to: v3(0, bodyDepth / 2, 0), duration: 0.7)]))
        } else {
            // Sit up first, then straighten, then the legs can go.
            let sitUp = SCNAction.rotateTo(x: -0.75, y: 0, z: 0, duration: 0.5, usesShortestUnitArc: true); sitUp.timingMode = .easeOut
            let stand = SCNAction.group([.rotateTo(x: 0, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true), .move(to: v3(0, bodyHeight / 2, 0), duration: 0.4)])
            body.runAction(.sequence([sitUp, .wait(duration: 0.15), stand]))
        }
    }
}
