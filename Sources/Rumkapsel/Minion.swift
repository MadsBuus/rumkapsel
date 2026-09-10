// One worker: its body, its tools, its poses.

import AppKit
import SceneKit

/// One Claude session, walking between the rooms of its station.
final class Minion {
    enum State { case arriving, settled, leaving }

    var id: String
    var freeSince = 0.0        // clock when the worker's session went away; 0 while assigned
    var couch: Int?
    var nextImpatience = 0.0
    var station: String
    var home: Home
    var state: State = .arriving
    var busy = false
    var activity: Activity = .waiting
    var place: Place = .core
    /// The one job in hand, and how far into its phases the actor is. Everything a minion does is
    /// one of these: a carry, a delivery, somewhere to be, the bath, a chore, QA, leaving.
    var current: Command?
    var phase = 0
    /// At most one waits for the next interruptible phase.
    var pending: Command?
    /// When the phase in hand runs out: a crouch, a shower, a chore.
    var phaseUntil = 0.0
    var carried: SCNNode?
    var fetchSpot: SIMD2<Double>?
    /// Which stack the QA walker is inspecting next.
    var qaStop = 0
    /// A carrier, deliverer or pusher walks at one pace whoever it is.
    var isHauling: Bool {
        switch current?.kind {
        case .carry, .deliverOffice, .pushPallet, .loadPallet, .unloadPallet: return true
        default: return false
        }
    }
    var commitDrop = false
    var weldLight: SCNNode?
    var hammerUp = false
    var lying = false
    var wakeUntil = 0.0
    /// A change of orders is visible: standing a beat, head up, before going.
    var wonderUntil = 0.0
    /// How long someone has stood in the way.
    var blockedFor = 0.0
    /// Which bath fixture is held: 0 the bowl, 1 the shower.
    var fixture: Int?
    /// Short stretches of work so far: every other one earns a pee.
    var shortStretches = 0
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

    var promptCount = 0
    var queuedCones: [SCNNode] = []
    var toolSeed: Int { abs(id.hashValue) % 4 }
    var pyramids: [SCNNode] = []
    var pyramidCell: Cell?
    /// On the cone's cell or the one beside it: close enough to work it when its own cell is covered.
    var nearCone: Bool { pyramidCell.map { abs($0.x - cell.x) + abs($0.y - cell.y) <= 1 } ?? false }
    var toolCount: Int
    var title: String?
    var branch: String?
    var cwd: String
    var markers: [StationEvent: String] = [:]
    let isSubagent: Bool
    let node = SCNNode()
    private let body: SCNNode
    let tilt: SCNNode
    private let bodyHeight: Double
    private let bodyDepth: Double
    var facing = 0.0
    var smoothFacing = 0.0
    var isCrew = false
    var busyUntil = 0.0        // replay seconds, for crew minions
    var bed: Int?
    var pos: SIMD2<Double>
    var path: [SIMD2<Double>] = []
    var nextWanderAt = 0.0
    var nextBathAt = 0.0
    var bathDue = 0.0          // clock when a visit is owed, 0 when none
    var busySince = 0.0
    var wasBusy = false
    var nextChoreAt = 0.0
    var showering = false
    var nextDropAt = 0.0
    private var staticNode: SCNNode?
    /// A few frames of grey noise: the discreet blur over whoever is in the bath.
    private static let noise: [NSImage] = (0..<4).map { _ in
        let n = 10
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
            let p = SCNNode(geometry: SCNPlane(width: 0.2, height: 0.15))
            p.geometry!.firstMaterial = flat(.white)
            p.geometry!.firstMaterial?.diffuse.magnificationFilter = .nearest
            p.constraints = [SCNBillboardConstraint()]
            p.position = v3(0, bodyHeight * 0.3, 0)
            // Drawn last and without depth, so the body's own faces never hide it.
            p.renderingOrder = 20
            p.geometry!.firstMaterial?.readsFromDepthBuffer = false
            p.geometry!.firstMaterial?.writesToDepthBuffer = false
            node.addChildNode(p)
            staticNode = p
        }
        staticNode?.geometry?.firstMaterial?.diffuse.contents = Minion.noise[frame % Minion.noise.count]
    }
    var waitingSince = 0.0
    let bobPhase = Double.random(in: 0..<6.28)
    /// Everyone moves at their own pace, so a row of workers never nods in unison.
    var tempo: Double { 0.82 + bobPhase / 6.28 * 0.42 }
    /// Which tool is out at the cone right now: the rota runs on the minion's own clock and stint length.
    func toolSlot(at clock: Double) -> Int { (toolSeed + Int((clock + bobPhase * 4) / (5.5 + Double(toolSeed) * 1.7))) % 4 }
    var opacity = 0.0

    init(id: String, station: String, home: Home, cwd: String, toolCount: Int, isSubagent: Bool, start: Cell, crew: Bool = false) {
        self.id = id; self.station = station; self.home = home; self.cwd = cwd; self.toolCount = toolCount; self.isSubagent = isSubagent
        self.isCrew = crew
        pos = SIMD2(Double(start.x), Double(start.y))

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
        let tiltNode = SCNNode()
        tiltNode.addChildNode(body)
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
        node.name = "minion:" + id
        body.name = node.name
        visor.name = node.name
        node.opacity = 0
    }

    /// The phase in hand.
    var phaseKind: Command.Phase {
        guard let c = current else { return .settle }
        let p = c.phases
        return p[min(phase, p.count - 1)]
    }
    /// Carrying, delivering or leaving: holding something, not free for anything else.
    var onJob: Bool { current?.isJob ?? false }
    /// Resting: only then do the couch and the bed pull.
    var isResting: Bool { current?.isRest ?? true }
    var isQA: Bool { if case .qa = current?.kind { return true }; return false }
    var isChore: Bool { if case .chore = current?.kind { return true }; return false }
    var bathing: Bool { if case .bath = current?.kind { return true }; return false }
    /// How the body is held over a crate, decided by how high the crate is.
    enum Posture { case none, crouch, waist, reach, jump }
    /// The level the hands are working at: 0 on the floor, 1 waist height, 2 and up a reach.
    var handsAt = 0
    var posture: Posture {
        guard phaseKind == .lift || phaseKind == .setDown, phaseUntil > 0 else { return .none }
        switch handsAt {
        case 0: return .crouch
        case 1: return .waist
        case 2: return .reach
        default: return .jump
        }
    }
    /// What it would say if you asked.
    var words: String { current?.words ?? "nothing in particular" }

    var cell: Cell { Cell(x: Int(pos.x.rounded()), y: Int(pos.y.rounded())) }
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

    /// Tip over onto the back in the dorm, or stand back up.
    func setSleeping(_ asleep: Bool) {
        guard asleep != lying else { return }
        lying = asleep
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
