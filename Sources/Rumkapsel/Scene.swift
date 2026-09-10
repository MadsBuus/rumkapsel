import AppKit
import SceneKit
import SpriteKit

extension NSColor {
    convenience init(rgb: (Double, Double, Double), alpha: CGFloat = 1) {
        self.init(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
    }
    convenience init(_ c: RGB) { self.init(rgb: c.tuple) }
    func mixed(with other: NSColor, _ t: CGFloat) -> NSColor {
        let a = usingColorSpace(.deviceRGB)!, b = other.usingColorSpace(.deviceRGB)!
        return NSColor(calibratedRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
    }
    func darker(_ f: CGFloat) -> NSColor {
        let c = usingColorSpace(.deviceRGB)!
        return NSColor(calibratedRed: max(0, c.redComponent - f), green: max(0, c.greenComponent - f), blue: max(0, c.blueComponent - f), alpha: 1)
    }
    func lighter(_ f: CGFloat) -> NSColor {
        let c = usingColorSpace(.deviceRGB)!
        return NSColor(calibratedRed: min(1, c.redComponent + f), green: min(1, c.greenComponent + f), blue: min(1, c.blueComponent + f), alpha: 1)
    }
}

enum Palette {
    static let void = NSColor(rgb: (0.055, 0.067, 0.125))
    static let corridor = NSColor(rgb: (0.47, 0.37, 0.31))
    static let core = NSColor(rgb: (0.13, 0.14, 0.18))
    static let minion = NSColor(rgb: (0.96, 0.96, 0.94))
    static let pyramid = NSColor(rgb: (0.98, 0.85, 0.35))
    static let debris = NSColor(rgb: (0.55, 0.6, 0.7))
    static let text = NSColor(rgb: (0.85, 0.87, 0.92))
    static let dim = NSColor(rgb: (0.5, 0.53, 0.6))
}

func v3(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 { SCNVector3(x, y, z) }

func flat(_ color: NSColor) -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = color
    m.lightingModel = .constant
    return m
}

func lit(_ color: NSColor) -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = color
    m.lightingModel = .lambert
    return m
}

/// Text laid flat on the floor, wrapped to a width in world units, pivoted on its centre.
func floorText(_ text: String, color: NSColor, size: Double, maxWidth: Double, lines: Int, bold: Bool = false) -> (node: SCNNode, width: Double, height: Double) {
    let t = SCNText(string: text, extrusionDepth: 0)
    t.font = bold ? (NSFont(name: "HelveticaNeue-Bold", size: 1) ?? NSFont.boldSystemFont(ofSize: 1))
                  : (NSFont(name: "HelveticaNeue-Medium", size: 1) ?? NSFont.systemFont(ofSize: 1, weight: .medium))
    t.flatness = 0.02
    t.isWrapped = true
    t.truncationMode = CATextLayerTruncationMode.end.rawValue
    t.alignmentMode = CATextLayerAlignmentMode.left.rawValue
    let height = Double(lines) * 1.45
    t.containerFrame = CGRect(x: 0, y: 0, width: maxWidth / size, height: height)
    t.firstMaterial = flat(color)
    t.firstMaterial!.isDoubleSided = true
    let bb = t.boundingBox
    let w = min(maxWidth, Double(bb.max.x - bb.min.x) * size)
    let h = height * size
    let inner = SCNNode(geometry: t)
    inner.scale = SCNVector3(size, size, size)
    inner.eulerAngles.x = -.pi / 2
    let outer = SCNNode()
    outer.addChildNode(inner)
    outer.pivot = SCNMatrix4MakeTranslation(w / 2, 0, -h / 2)
    return (outer, w, h)
}

/// Uppercase, letter-spaced signage cut into a floor, pivoted on its centre.
func floorSign(_ text: String, color: NSColor, size: Double) -> (node: SCNNode, width: Double, height: Double) {
    let attributed = NSAttributedString(string: text.uppercased(), attributes: [
        .font: NSFont(name: "Futura-CondensedExtraBold", size: 1) ?? NSFont(name: "HelveticaNeue-CondensedBlack", size: 1) ?? NSFont.boldSystemFont(ofSize: 1),
        .kern: 0,
    ])
    let t = SCNText(string: attributed, extrusionDepth: 0)
    t.flatness = 0.02
    t.firstMaterial = flat(color)
    t.firstMaterial!.isDoubleSided = true
    let bb = t.boundingBox
    let w = Double(bb.max.x - bb.min.x) * size, h = Double(bb.max.y - bb.min.y) * size
    let inner = SCNNode(geometry: t)
    inner.scale = SCNVector3(size, size, size)
    inner.eulerAngles.x = -.pi / 2
    inner.position = v3(-Double(bb.min.x) * size, 0, Double(bb.min.y) * size)
    let outer = SCNNode()
    outer.addChildNode(inner)
    outer.pivot = SCNMatrix4MakeTranslation(w / 2, 0, -h / 2)
    return (outer, w, h)
}

/// SCNView that reports hovers, double-clicks and trackpad gestures.
final class StationView: SCNView {
    var onHover: ((SCNNode?) -> Void)?
    var onDoubleClick: ((SCNNode?) -> Void)?
    var onZoom: ((Double, NSPoint?) -> Void)?
    var onRotate: ((Double, NSPoint?) -> Void)?
    var onPan: ((Double, Double) -> Void)?
    var onTilt: ((Double) -> Void)?
    var onKey: ((String) -> Bool)?
    /// Held WASD keys as a screen-relative direction (x right, y up) and Q/E as a zoom direction (+1 in), zero when none are down.
    var onMove: ((SIMD2<Double>, Double) -> Void)?
    private var heldKeys: Set<String> = []
    var onClick: ((SCNNode?) -> Void)?
    var onContextMenu: ((SCNNode?, NSEvent) -> Void)?
    private var tracking: NSTrackingArea?
    private var downPoint = NSPoint.zero

    override func keyDown(with event: NSEvent) {
        if let chars = event.charactersIgnoringModifiers?.lowercased(), Self.moveKeys[chars] != nil,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if !event.isARepeat { heldKeys.insert(chars); moveChanged() }
            return
        }
        if let chars = event.charactersIgnoringModifiers, onKey?(chars) == true { return }
        super.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) {
        if let chars = event.charactersIgnoringModifiers?.lowercased(), heldKeys.remove(chars) != nil { moveChanged(); return }
        super.keyUp(with: event)
    }
    override func flagsChanged(with event: NSEvent) {
        // A modifier pressed mid-move would swallow the key-up: let go of everything.
        if !heldKeys.isEmpty, !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { heldKeys = []; moveChanged() }
        super.flagsChanged(with: event)
    }
    override func resignFirstResponder() -> Bool {
        if !heldKeys.isEmpty { heldKeys = []; moveChanged() }
        return super.resignFirstResponder()
    }
    private static let moveKeys: [String: SIMD3<Double>] = ["w": SIMD3(0, 1, 0), "s": SIMD3(0, -1, 0), "a": SIMD3(-1, 0, 0), "d": SIMD3(1, 0, 0),
                                                            "e": SIMD3(0, 0, 1), "q": SIMD3(0, 0, -1)]
    private func moveChanged() {
        var v = SIMD3<Double>(0, 0, 0)
        for k in heldKeys { v += Self.moveKeys[k]! }
        onMove?(SIMD2(v.x, v.y), v.z)
    }
    /// The cursor's view location, or nil when it is outside the view.
    private func cursor(_ event: NSEvent) -> NSPoint? {
        let p = convert(event.locationInWindow, from: nil)
        return bounds.contains(p) ? p : nil
    }
    private var dragAllowed = false

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func magnify(with event: NSEvent) { onZoom?(1 + event.magnification, cursor(event)) }
    override func rotate(with event: NSEvent) { onRotate?(Double(event.rotation) * .pi / 180, cursor(event)) }
    override func scrollWheel(with event: NSEvent) {
        // Two fingers slide the view; a mouse wheel reports in lines, so scale it up to feel like pixels.
        let k = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        if event.modifierFlags.contains(.option) { onZoom?(1 - Double(event.scrollingDeltaY) * 0.01, cursor(event)) }
        else { onPan?(Double(event.scrollingDeltaX) * k, Double(event.scrollingDeltaY) * k) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragAllowed else { return }
        onTilt?(Double(event.deltaY))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    private func node(at p: NSPoint) -> SCNNode? {
        hitTest(p, options: [.boundingBoxOnly: true, .firstFoundOnly: true]).first?.node
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?(node(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) { onHover?(nil) }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(node(at: convert(event.locationInWindow, from: nil)), event) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragAllowed = p.y < bounds.height - 32
        downPoint = p
        if event.clickCount == 2 { onDoubleClick?(node(at: p)) }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, hypot(p.x - downPoint.x, p.y - downPoint.y) < 3 { onClick?(node(at: p)) }
        super.mouseUp(with: event)
    }
}

/// One Claude session, walking between the rooms of its station.
final class Minion {
    enum State { case arriving, settled, leaving }
    enum Errand { case fetch(room: String), carry(room: String), pickup(Int), deliver(Int) }

    var id: String
    var freeSince = 0.0        // clock when the worker's session went away; 0 while assigned
    var couch: Int?
    var isTester = false
    var nextImpatience = 0.0
    var station: String
    var home: Home
    var state: State = .arriving
    var busy = false
    var activity: Activity = .waiting
    var place: Place = .core
    var errand: Errand?
    var carried: SCNNode?
    var fetchSpot: SIMD2<Double>?
    var commitDrop = false
    var weldLight: SCNNode?
    var hammerUp = false
    var lying = false
    var wakeUntil = 0.0
    /// Bent over a crate until this clock time: lifting or setting down takes a moment.
    var bendUntil = 0.0
    private(set) var shadow: SCNNode!
    /// The hammer's grip end, so the swing pivots in the hand rather than at the handle's middle.
    private(set) var hammerPivot: SCNNode?
    /// The flashlight's grip, swept about to play its cone over the work.
    private(set) var lightPivot: SCNNode?
    enum Tool { case goggles, tablet, scanner, hammer, flashlight }
    private(set) var tool: Tool?
    private var toolNode: SCNNode?

    var promptCount = 0
    var queuedCones: [SCNNode] = []
    var toolSeed: Int { abs(id.hashValue) % 4 }
    var pyramids: [SCNNode] = []
    var pyramidCell: Cell?
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
    var bathUntil = 0.0
    var bathReturn: Place?
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
            p.renderingOrder = 20
            node.addChildNode(p)
            staticNode = p
        }
        staticNode?.geometry?.firstMaterial?.diffuse.contents = Minion.noise[frame % Minion.noise.count]
    }
    var waitingSince = 0.0
    let bobPhase = Double.random(in: 0..<6.28)
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
        hammerPivot = nil; lightPivot = nil
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
        case .flashlight:
            // A torch held out front, with its cone of light drawn as a soft translucent cone.
            let pivot = SCNNode()
            pivot.position = v3(0.06, h * 0.34, d / 2 + 0.04)
            let barrel = SCNNode(geometry: SCNCylinder(radius: 0.025, height: 0.12))
            barrel.geometry!.firstMaterial = dark
            barrel.eulerAngles.x = .pi / 2
            barrel.position = v3(0, 0, 0.06)
            pivot.addChildNode(barrel)
            let lens = SCNNode(geometry: SCNCylinder(radius: 0.028, height: 0.01))
            lens.geometry!.firstMaterial = flat(NSColor(rgb: (1.0, 0.95, 0.7)))
            lens.eulerAngles.x = .pi / 2
            lens.position = v3(0, 0, 0.125)
            pivot.addChildNode(lens)
            let beamLength = 0.9
            let beam = SCNNode(geometry: SCNCone(topRadius: 0.028, bottomRadius: 0.22, height: beamLength))
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

/// All scene and HUD mutation happens on SceneKit's render thread, via `enqueue`, so the
/// SpriteKit overlay is never touched while it is being drawn.
final class StationController: NSObject, SCNSceneRendererDelegate {
    private let pendingLock = NSLock()
    private var pending: [() -> Void] = []

    func enqueue(_ work: @escaping () -> Void) {
        pendingLock.lock(); pending.append(work); pendingLock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        pendingLock.lock(); let work = pending; pending.removeAll(); pendingLock.unlock()
        for w in work { w() }
        tick(now: time)
    }

    let view: StationView
    let scene = SCNScene()
    let hud: SKScene
    let fleet = Fleet()
    let drone = Drone()
    private let scanner = TranscriptScanner()
    private let github = GitHubResolver()
    private let scanQueue = DispatchQueue(label: "rumkapsel.scan")

    private var minions: [String: Minion] = [:]
    private let staticRoot = SCNNode()
    private let labelRoot = SCNNode()
    private let minionRoot = SCNNode()
    private let propRoot = SCNNode()
    private let markerRoot = SCNNode()
    private let debrisRoot = SCNNode()
    private let rig = SCNNode()
    private let pitchNode = SCNNode()
    private let cameraNode = SCNNode()
    private var roomTiles: [String: [SCNNode]] = [:]
    /// Doorways: pairs of cells whose shared edge has no dark border, keyed "x,y|x,y" in both orders.
    private var openEdges: Set<String> = []
    private var roomLabels: [String: SCNNode] = [:]
    private var floorLabels: [(node: SCNNode, baseYaw: Double)] = []
    /// Rooms whose office has not been delivered yet, keyed by "station|room".
    private var undelivered: Set<String> = []
    private var boxes: [String: SCNNode] = [:]
    private var outlines: [String: SCNNode] = [:]
    private let beamRoot = SCNNode()
    private let rocketRoot = SCNNode()
    private var rockets: [String: SCNNode] = [:]
    private var repoRoots: [String: (repo: String, station: String)] = [:]
    // Crew replay: teammates' last day, looped.
    private struct CrewRoomInfo { var repo: String; var branch: String; var prNumber: Int?; var title: String?; var author: String; var url: String?; var state: String; var last: Date }
    private var crewBoxes: [String: (count: Int, state: String, color: NSColor)] = [:]
    private var lastBoxCount: [String: Int] = [:]
    private var localSignature = ""
    private var crewRoomInfo: [String: CrewRoomInfo] = [:]
    private var crewSeen: Set<String> = []
    private var crewLoaded = false
    private var crewBusyUntil: [String: Date] = [:]
    private var hangarAnchors: [String: SCNNode] = [:]
    private var lastBusy: [String: Double] = [:]
    private var loadedRockets: [String: Int] = [:]          // rocket key -> crates loaded, waiting for ignition
    private var stationAnchors: [String: SCNNode] = [:]     // props that must move with a station when it shifts
    private var knownSpine: [String: Int] = [:]
    // Peers on the local network: their snapshots, the stations built from them, and their minions.
    let peers = PeerHub()
    private var peerSnapshots: [String: (snap: PeerSnapshot, at: Date)] = [:]
    private var peerFirstSeen: [String: Date] = [:]
    /// Peers' claims on offices of the work station, by room key ("work|task:…") then peer name.
    private var peerOffices: [String: [String: PeerSnapshot.Office]] = [:]
    private var peerBoxes: [String: (count: Int, state: String, color: NSColor)] = [:]
    private var pushedByPeer: Set<String> = []
    private var fadeIn: Set<String> = []
    private var held: [String: Date] = [:]        // offices a peer left behind, held for a day
    private var roomCreated: [String: Date] = [:]
    private let peerRoot = SCNNode()
    private var peerMinions: [String: (node: SCNNode, target: SIMD3<Double>)] = [:]
    private var peerColorBook: [String: RGB] = [:]
    private var roomPower: [String: Bool] = [:]
    private var haulingRooms: Set<String> = []
    /// Deck crates on someone's arms, "repo|number": the deck layout skips them until set down.
    private var haulingCrates: Set<String> = []
    private var hauledAt: [String: Date] = [:]
    /// A box being carried from one floor to another by whichever minion is free.
    private struct Haul { let id: Int; let station: String; let box: SCNNode; let from: Cell; let to: Cell; let drop: SIMD3<Double>; let onDone: () -> Void; var carrier: String?; var roomKey: String = "" }
    private var hauls: [Haul] = []
    private var nextHaulId = 1
    private var pendingLaunch: [String: (node: SCNNode, remaining: Int, since: Double)] = [:]
    private var pendingIgnition: [String: Bool] = [:]
    private var lastHaulSchedule = 0.0
    static let powerWindow: TimeInterval = 2 * 3600
    private var shipsInFlight: [String: Int] = [:]
    static let crewRecent: TimeInterval = 30 * 60
    private var beams: [String: SCNNode] = [:]
    private let infoLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    private let infoBackground = SKSpriteNode(color: Palette.void.withAlphaComponent(0.85), size: CGSize(width: 1, height: 1))
    private let statusLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    private let shareDot = SKSpriteNode(color: NSColor(rgb: (0.35, 0.85, 0.5)), size: CGSize(width: 7, height: 7))
    private let shareLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    private var legendNodes: [SKNode] = []
    private var jobNodes: [SKNode] = []
    private var hudClock = 0.0
    private var legendSignature = ""
    private var eventLabels: [(SKLabelNode, Double)] = []
    private var hovered: String?
    private var lastTick = 0.0
    private var clock = 0.0
    private var targetHalf = SIMD2<Double>(6, 6)   // half-extent of the fleet as the default camera sees it
    private var targetFocus = SIMD2<Double>(0, 0)
    private var userZoom = 1.0
    private var userZoomChanged = false
    private var userDriving = 0.0          // seconds left of snappy camera response after a gesture
    private var keyMove = SIMD2<Double>(0, 0)   // WASD held: screen-relative direction, x right and y up
    private var keyZoom = 0.0                    // E/Q held: +1 zooms in, -1 out
    private var userYaw = 0.0
    private var userPitch = -Double.pi / 6
    private var userPan = SIMD2<Double>(0, 0)
    private var focused: String?
    private var lastSavedView = 0.0
    private var debris: [(SCNNode, SIMD2<Double>)] = []
    private var lastPing = 0.0
    private var timer: Timer?
    private var watcher: DirectoryWatcher?
    var viewSize = CGSize(width: 640, height: 440)
    private var didLoadLayout = false
    let demo: Bool
    private var demoClock = 0.0
    private var demoMerged = false
    private var demoStaged = false

    static let activeWindow: TimeInterval = 60 * 60     // a worker stays with a session for an hour of quiet
    static let busyWindow: TimeInterval = 90
    static let replyWindow: TimeInterval = 20
    static let sleepWindow: TimeInterval = 5 * 60
    static let subagentWindow: TimeInterval = 3 * 60
    static let roomsWindow: TimeInterval = 12 * 3600       // for sessions outside Conductor
    static let scanWindow: TimeInterval = 14 * 24 * 3600   // how far back transcripts are read

    init(frame: NSRect, demo: Bool) {
        self.demo = demo
        view = StationView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        hud = SKScene(size: frame.size)
        super.init()
        buildScene()
        buildHUD()
        view.scene = scene
        view.backgroundColor = Palette.void
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.autoresizingMask = [.width, .height]
        view.allowsCameraControl = false
        view.overlaySKScene = hud
        view.onHover = { [weak self] node in let n = node?.name; self?.enqueue { self?.hovered = n } }
        view.onDoubleClick = { [weak self] node in let n = node?.name; self?.enqueue { self?.open(named: n) } }
        view.onClick = { [weak self] node in
            guard let n = node?.name else { return }
            if n.hasPrefix("minion:") { self?.enqueue { self?.poke(minionId: String(n.dropFirst(7))) } }
            if (n.hasPrefix("storage:") || n.hasPrefix("deck:")), n.split(separator: "|").count == 3 { self?.enqueue { self?.openCargo(named: n) } }
            guard n.hasPrefix("box:") || n.hasPrefix("rocket:") else { return }
            self?.enqueue { self?.open(named: n) }
        }
        view.onContextMenu = { [weak self] node, event in self?.showContextMenu(for: node?.name, event: event) }
        view.onZoom = { [weak self] f, point in
            // Zoom about the ground point under the cursor: it stays put on screen while the view scales.
            let ground = point.flatMap { self?.groundPoint(at: $0) }
            self?.enqueue {
                guard let self else { return }
                let before = self.userZoom
                self.userZoom = min(6, max(0.4, self.userZoom * f))
                self.userZoomChanged = true
                guard let g = ground, self.userZoom != before else { return }
                self.userDriving = 0.5
                let focus = self.targetFocus + self.userPan
                self.userPan = g + (focus - g) * (before / self.userZoom) - self.targetFocus
            }
        }
        view.onRotate = { [weak self] r, point in
            // Pivot on the ground point under the cursor: rotate the camera focus around it.
            let ground = point.flatMap { self?.groundPoint(at: $0) }
            self?.enqueue {
                guard let self else { return }
                let before = self.userYaw
                self.userYaw -= r
                self.userDriving = 0.5
                if let g = ground {
                    let focus = self.targetFocus + self.userPan
                    let d = focus - g
                    let a = self.userYaw - before
                    let rotated = SIMD2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a))
                    self.userPan = g + rotated - self.targetFocus
                }
            }
        }
        view.onTilt = { [weak self] dy in
            self?.enqueue { guard let self else { return }; self.userPitch = min(-0.15, max(-Double.pi / 2 + 0.05, self.userPitch - dy * 0.004)) }
        }
        view.onPan = { [weak self] dx, dy in self?.enqueue { self?.pan(byPixels: dx, dy) } }
        view.onMove = { [weak self] dir, zoom in self?.enqueue { self?.keyMove = dir; self?.keyZoom = zoom } }
        github.onUpdate = { [weak self] in self?.enqueue { self?.onGitHubUpdate() } }
        view.onKey = { [weak self] key in
            guard let self else { return false }
            switch key {
            case "0": focus(on: nil)
            case "1", "2", "3", "4": focus(onIndex: Int(key)! - 1)
            case "r": resetView()
            case "g": refreshGitHub()
            default: return false
            }
            return true
        }
        view.delegate = self

        peers.snapshotProvider = { [weak self] g in self?.makeSnapshot(withGitHub: g) }
        peers.onSnapshot = { [weak self] snap in self?.enqueue { self?.receivePeer(snap) } }
        applySharing()
        if demo {
            seedDemo()
        } else {
            rescan()
            let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects").path
            watcher = DirectoryWatcher(path: projects) { [weak self] in self?.rescan() }
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.rescan() }
        }
    }

    // MARK: scene

    private func buildScene() {
        scene.background.contents = Palette.void
        for n in [staticRoot, labelRoot, minionRoot, propRoot, markerRoot, debrisRoot, beamRoot, rocketRoot, peerRoot] { scene.rootNode.addChildNode(n) }

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 8
        camera.zNear = 0.1
        camera.zFar = 400
        cameraNode.camera = camera
        cameraNode.position = v3(0, 0, 120)
        pitchNode.eulerAngles.x = -.pi / 6
        pitchNode.addChildNode(cameraNode)
        rig.eulerAngles.y = .pi / 4
        rig.addChildNode(pitchNode)
        scene.rootNode.addChildNode(rig)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 700
        sun.eulerAngles = v3(-.pi / 3, .pi / 3, 0)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 550
        scene.rootNode.addChildNode(ambient)

        for _ in 0..<110 {
            let size = Double.random(in: 0.05...0.13)
            let n = SCNNode(geometry: SCNPlane(width: size, height: size))
            n.geometry!.firstMaterial = flat(Palette.debris)
            n.opacity = Double.random(in: 0.25...0.7)
            n.eulerAngles.x = -.pi / 2
            n.eulerAngles.z = Double.random(in: 0..<6.28)
            let p = SIMD2(Double.random(in: -40...40), Double.random(in: -40...40))
            n.position = v3(p.x, -0.6, p.y)
            debrisRoot.addChildNode(n)
            debris.append((n, SIMD2(Double.random(in: -0.12...0.12), Double.random(in: -0.12...0.12))))
        }
        // A far, still star field: one point-cloud geometry, faint and small.
        var stars: [SCNVector3] = []
        var starColors: [SCNVector4] = []
        for _ in 0..<700 {
            stars.append(v3(Double.random(in: -90...90), -12, Double.random(in: -90...90)))
            let b = Double.random(in: 0.25...0.7)
            starColors.append(SCNVector4(0.8 * b, 0.85 * b, 1.0 * b, 1))
        }
        let starSource = SCNGeometrySource(vertices: stars)
        let colorData = Data(bytes: starColors, count: starColors.count * MemoryLayout<SCNVector4>.stride)
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: starColors.count, usesFloatComponents: true,
                                            componentsPerVector: 4, bytesPerComponent: MemoryLayout<CGFloat>.size, dataOffset: 0, dataStride: MemoryLayout<SCNVector4>.stride)
        let indices = (0..<stars.count).map { Int32($0) }
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 1.2
        element.minimumPointScreenSpaceRadius = 0.6
        element.maximumPointScreenSpaceRadius = 1.6
        let starGeometry = SCNGeometry(sources: [starSource, colorSource], elements: [element])
        let starMaterial = SCNMaterial()
        starMaterial.lightingModel = .constant
        starMaterial.diffuse.contents = NSColor.white
        starMaterial.blendMode = .add
        starGeometry.firstMaterial = starMaterial
        debrisRoot.addChildNode(SCNNode(geometry: starGeometry))

        for _ in 0..<4 {
            let cluster = SCNNode()
            let count = Int.random(in: 12...20)
            for _ in 0..<count {
                let size = Double.random(in: 0.25...0.4)
                let n = SCNNode(geometry: SCNPlane(width: size, height: size))
                let shade = Double.random(in: 0...1)
                n.geometry!.firstMaterial = flat(NSColor(rgb: (0.55 + 0.25 * shade, 0.22 + 0.15 * shade, 0.40 + 0.15 * shade)))
                n.eulerAngles.x = -.pi / 2
                let a = Double.random(in: 0..<6.28), r = Double.random(in: 0...1.3)
                n.position = v3(cos(a) * r, Double.random(in: -0.15...0.15), sin(a) * r)
                cluster.addChildNode(n)
            }
            let p = SIMD2(Double.random(in: -30...30), Double.random(in: -30...30))
            cluster.position = v3(p.x, -0.4, p.y)
            debrisRoot.addChildNode(cluster)
            debris.append((cluster, SIMD2(Double.random(in: -0.08...0.08), Double.random(in: -0.08...0.08))))
        }
        rebuildStatic()
    }

    private func owner(_ station: Station, _ c: Cell) -> String? {
        if station.hangarCells.contains(c) { return "kind:hangar" }
        if station.storageCells.contains(c) { return "kind:storage" }
        if station.deckCells.contains(c) && !ConfigStore.shared.current.stagingBranch.isEmpty { return "kind:deck" }
        if station.padCells.contains(c) { return "kind:pad" }
        if station.coreCells.contains(c) || station.isCorridor(c) { return "corridor" }
        return station.room(at: c)?.key
    }

    private func joined(_ station: Station, _ a: Cell, _ b: Cell, _ key: String) -> Bool {
        owner(station, b) == key || openEdges.contains("\(station.name):\(a.x),\(a.y)|\(b.x),\(b.y)")
    }

    /// Full-size floor tile; borders are drawn separately as strips so corners meet cleanly.
    @discardableResult
    private func addTile(station: Station, cell: Cell, owner key: String, color: NSColor, name: String, into parent: SCNNode? = nil) -> SCNNode {
        let root = parent ?? staticRoot
        let plane = SCNPlane(width: 1.0, height: 1.0)
        plane.firstMaterial = flat(color)
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = v3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
        n.name = name
        root.addChildNode(n)
        // Dark border toward any neighbouring floor of another owner, extended past the corners.
        let g = 0.075
        let sides: [(Cell, SIMD2<Double>, Bool)] = [
            (Cell(x: cell.x - 1, y: cell.y), SIMD2(-0.5, 0), true), (Cell(x: cell.x + 1, y: cell.y), SIMD2(0.5, 0), true),
            (Cell(x: cell.x, y: cell.y - 1), SIMD2(0, -0.5), false), (Cell(x: cell.x, y: cell.y + 1), SIMD2(0, 0.5), false),
        ]
        for (nb, off, vertical) in sides {
            guard let other = owner(station, nb), other != key, !joined(station, cell, nb, key) else { continue }
            let strip = SCNPlane(width: vertical ? g * 2 : 1 + g * 2, height: vertical ? 1 + g * 2 : g * 2)
            strip.firstMaterial = flat(Palette.void)
            let b = SCNNode(geometry: strip)
            b.eulerAngles.x = -.pi / 2
            b.position = v3(station.offset.x + Double(cell.x) + off.x, 0.002, station.offset.y + Double(cell.y) + off.y)
            b.name = name
            b.opacity = n.opacity
            root.addChildNode(b)
        }
        return n
    }

    private func roomKey(_ station: Station, _ room: Room) -> String { "\(station.name)|\(room.key)" }

    /// Tiles depend on whether a branch is pushed, so relayout when that changes; otherwise just the props.
    private func onGitHubUpdate() {
        let sig = fleet.stations.values.flatMap { st in st.rooms.values.map { r in
            let l = localState(r)
            let checks = r.branch.flatMap { b in r.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0)?.checks } } ?? ""
            return "\(st.name)|\(r.key):\(l.local):\(l.commits > 0):\(checks)"
        } }.sorted().joined()
        if sig != localSignature { localSignature = sig; rebuildStatic() } else { rebuildMarkers() }
        rebuildRockets()
        rebuildCrew()
    }

    private func checksFailing(_ room: Room) -> Bool {
        guard let b = room.branch, let r = room.repoRoot, let pr = github.pull(branch: b, repoRoot: r) else { return false }
        return pr.state == "OPEN" && pr.checks == "failure"
    }

    private func isDusty(_ room: Room) -> Bool {
        !room.key.hasPrefix("kind:") && Date().timeIntervalSince(room.lastActive) > 7 * 24 * 3600
    }

    /// An office GitHub knows about that nobody here has checked out: a teammate's branch or pull request.
    private func isRemoteOnly(_ station: Station, _ room: Room) -> Bool {
        let key = roomKey(station, room)
        return room.worktree == nil && (crewRoomInfo[key] != nil || pushedByPeer.contains(key))
    }

    /// An office that exists only on someone's disk, or is being held for them: drawn as an outline.
    private func isProvisional(_ station: Station, _ room: Room) -> Bool {
        let key = roomKey(station, room)
        return !demo && room.worktree == nil && !room.key.hasPrefix("kind:") && crewRoomInfo[key] == nil && !pushedByPeer.contains(key)
    }

    /// The office key for a teammate's branch: the same key a local checkout of it would get.
    private func crewKey(repo: String, branch: String) -> String { Home.from(repo: repo, branch: branch, cwd: "").key }

    /// A task room whose branch is not on GitHub yet: (unpushed, commits ahead).
    private func localState(_ room: Room) -> (local: Bool, commits: Int) {
        guard room.key.hasPrefix("task:"), let w = room.worktree else { return (false, 0) }
        var pushed = github.branchPushed(worktree: w) ?? true
        if let b = room.branch, let r = room.repoRoot, github.pull(branch: b, repoRoot: r) != nil { pushed = true }
        return (!pushed, github.commitsAhead(worktree: w) ?? 0)
    }

    /// Dashed outline around a room's footprint, the game's look for a room under construction.
    private func outline(station: Station, room: Room) -> SCNNode {
        let group = SCNNode()
        let color = NSColor(room.color)
        let dash = 0.3, gap = 0.18, thick = 0.06
        func addEdge(from a: SIMD2<Double>, to b: SIMD2<Double>) {
            let d = b - a
            let len = (d.x * d.x + d.y * d.y).squareRoot()
            let dir = d / len
            var t = 0.08
            while t + dash <= len + 0.001 {
                let mid = a + dir * (t + dash / 2)
                let n = SCNNode(geometry: SCNPlane(width: dash, height: thick))
                n.geometry!.firstMaterial = flat(color)
                n.eulerAngles = SCNVector3(-Double.pi / 2, 0, 0)
                n.eulerAngles.y = dir.x == 0 ? .pi / 2 : 0
                n.position = v3(station.offset.x + mid.x, 0.012, station.offset.y + mid.y)
                group.addChildNode(n)
                t += dash + gap
            }
        }
        let cells = Set(room.cells)
        for c in room.cells {
            let x = Double(c.x), y = Double(c.y)
            if !cells.contains(Cell(x: c.x, y: c.y - 1)) { addEdge(from: SIMD2(x - 0.5, y - 0.5), to: SIMD2(x + 0.5, y - 0.5)) }
            if !cells.contains(Cell(x: c.x, y: c.y + 1)) { addEdge(from: SIMD2(x - 0.5, y + 0.5), to: SIMD2(x + 0.5, y + 0.5)) }
            if !cells.contains(Cell(x: c.x - 1, y: c.y)) { addEdge(from: SIMD2(x - 0.5, y - 0.5), to: SIMD2(x - 0.5, y + 0.5)) }
            if !cells.contains(Cell(x: c.x + 1, y: c.y)) { addEdge(from: SIMD2(x + 0.5, y - 0.5), to: SIMD2(x + 0.5, y + 0.5)) }
        }
        return group
    }

    private func rebuildStatic() {
        fleet.arrange()
        staticRoot.childNodes.forEach { $0.removeFromParentNode() }
        roomTiles = [:]
        openEdges = []
        for station in fleet.stations.values {
            for room in station.rooms.values {
                guard let d = station.doorCell(of: room.key), let o = station.doorOutside(of: room.key) else { continue }
                openEdges.insert("\(station.name):\(d.x),\(d.y)|\(o.x),\(o.y)")
                openEdges.insert("\(station.name):\(o.x),\(o.y)|\(d.x),\(d.y)")
            }
            for (a, b) in station.yardDoorways {
                openEdges.insert("\(station.name):\(a.x),\(a.y)|\(b.x),\(b.y)")
                openEdges.insert("\(station.name):\(b.x),\(b.y)|\(a.x),\(a.y)")
            }
        }

        for station in fleet.stations.values {
            let anchor = stationAnchors[station.name] ?? { let n = SCNNode(); propRoot.addChildNode(n); stationAnchors[station.name] = n; return n }()
            anchor.position = v3(station.offset.x, 0, station.offset.y)
            let oldSpine = knownSpine[station.name] ?? station.spineHalfLength
            knownSpine[station.name] = station.spineHalfLength
            for c in station.corridorCells + station.coreCells {
                let t = addTile(station: station, cell: c, owner: "corridor", color: Palette.corridor, name: "station:" + station.name)
                // New corridor beyond the old length is built tile by tile, outward.
                let reach = max(abs(c.x), abs(c.y))
                if reach > oldSpine {
                    t.opacity = 0
                    t.runAction(.sequence([.wait(duration: 0.3 * Double(reach - oldSpine)), .fadeIn(duration: 0.5)]))
                }
            }
            for c in station.hangarCells {
                addTile(station: station, cell: c, owner: "kind:hangar", color: NSColor(Colors.hangar), name: "hangar:" + station.name)
            }
            for c in station.padCells {
                addTile(station: station, cell: c, owner: "kind:pad", color: NSColor(rgb: (0.24, 0.26, 0.32)), name: "pad:" + station.name)
            }
            for c in station.storageCells {
                addTile(station: station, cell: c, owner: "kind:storage", color: NSColor(rgb: (0.20, 0.22, 0.30)), name: "storage:" + station.name)
            }
            if !ConfigStore.shared.current.stagingBranch.isEmpty {
                for c in station.deckCells {
                    addTile(station: station, cell: c, owner: "kind:deck", color: NSColor(rgb: (0.22, 0.27, 0.30)), name: "deck:" + station.name)
                }
            }
            if station.hasPad {
                let pc = station.padCenter
                let ring = SCNNode(geometry: SCNTube(innerRadius: 1.45, outerRadius: 1.55, height: 0.01))
                ring.geometry!.firstMaterial = flat(NSColor(rgb: (0.45, 0.48, 0.58)))
                ring.position = v3(station.offset.x + pc.x, 0.006, station.offset.y + pc.y)
                staticRoot.addChildNode(ring)
            }
            if let lounge = station.rooms["kind:lounge"] {
                let cx = Double(lounge.cells.map(\.x).reduce(0, +)) / Double(lounge.cells.count)
                let cy = Double(lounge.cells.map(\.y).reduce(0, +)) / Double(lounge.cells.count)
                let table = SCNNode(geometry: SCNCylinder(radius: 0.3, height: 0.28))
                table.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.42, 0.3)))
                table.position = v3(station.offset.x + cx, 0.14, station.offset.y + cy)
                table.name = "room:" + roomKey(station, lounge)
                staticRoot.addChildNode(table)
                for (k, c) in station.couches.enumerated() {
                    let along = k < 4   // couches on the side walls run along z, the far wall along x
                    let couch = SCNNode(geometry: SCNBox(width: along ? 0.3 : 0.8, height: 0.18, length: along ? 0.8 : 0.3, chamferRadius: 0.02))
                    couch.geometry!.firstMaterial = lit(NSColor(rgb: (0.62, 0.45, 0.4)))
                    couch.position = v3(station.offset.x + c.x, 0.09, station.offset.y + c.y)
                    couch.name = "room:" + roomKey(station, lounge)
                    let back = SCNNode(geometry: SCNBox(width: along ? 0.08 : 0.8, height: 0.22, length: along ? 0.8 : 0.08, chamferRadius: 0.02))
                    back.geometry!.firstMaterial = couch.geometry!.firstMaterial
                    back.position = v3(along ? (c.x < cx ? -0.11 : 0.11) : 0, 0.16, along ? 0 : 0.11)
                    couch.addChildNode(back)
                    staticRoot.addChildNode(couch)
                }
                // A potted plant in one corner and a low shelf in another: somewhere to look at.
                let xs = lounge.cells.map(\.x), ys = lounge.cells.map(\.y)
                let pot = SCNNode(geometry: SCNCylinder(radius: 0.11, height: 0.16))
                pot.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.5, 0.35)))
                pot.position = v3(station.offset.x + Double(xs.min()!) - 0.28, 0.08, station.offset.y + Double(ys.min()!) - 0.28)
                let leaves = SCNNode(geometry: SCNSphere(radius: 0.17))
                leaves.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.62, 0.38)))
                leaves.position = v3(0, 0.2, 0)
                pot.addChildNode(leaves)
                pot.name = "room:" + roomKey(station, lounge)
                staticRoot.addChildNode(pot)
                let shelf = SCNNode(geometry: SCNBox(width: 0.7, height: 0.32, length: 0.2, chamferRadius: 0.01))
                shelf.geometry!.firstMaterial = lit(NSColor(rgb: (0.5, 0.4, 0.32)))
                shelf.position = v3(station.offset.x + Double(xs.max()!), 0.16, station.offset.y + Double(ys.min()!) - 0.32)
                for i in 0..<4 {
                    let book = SCNNode(geometry: SCNBox(width: 0.08, height: 0.2, length: 0.14, chamferRadius: 0))
                    book.geometry!.firstMaterial = lit(NSColor(Colors.repos[i % Colors.repos.count]))
                    book.position = v3(-0.22 + Double(i) * 0.13, 0.26, 0)
                    shelf.addChildNode(book)
                }
                shelf.name = "room:" + roomKey(station, lounge)
                staticRoot.addChildNode(shelf)
            }
            if let bath = station.rooms["kind:bath"] {
                // A toilet in one corner and a shower post in the other.
                let cells = bath.cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                let tc = cells.first!, sc = cells.last!
                let bowl = SCNNode(geometry: SCNCylinder(radius: 0.13, height: 0.2))
                bowl.geometry!.firstMaterial = lit(NSColor(rgb: (0.92, 0.93, 0.95)))
                bowl.position = v3(station.offset.x + Double(tc.x) - 0.22, 0.1, station.offset.y + Double(tc.y) - 0.22)
                let tank = SCNNode(geometry: SCNBox(width: 0.24, height: 0.3, length: 0.1, chamferRadius: 0.01))
                tank.geometry!.firstMaterial = bowl.geometry!.firstMaterial
                tank.position = v3(0, 0.15, -0.14)
                bowl.addChildNode(tank)
                bowl.name = "room:" + roomKey(station, bath)
                staticRoot.addChildNode(bowl)
                let post = SCNNode(geometry: SCNCylinder(radius: 0.025, height: 0.7))
                post.geometry!.firstMaterial = lit(NSColor(rgb: (0.7, 0.72, 0.78)))
                post.position = v3(station.offset.x + Double(sc.x) + 0.3, 0.35, station.offset.y + Double(sc.y) + 0.3)
                let head = SCNNode(geometry: SCNCylinder(radius: 0.09, height: 0.03))
                head.geometry!.firstMaterial = post.geometry!.firstMaterial
                head.position = v3(-0.12, 0.33, -0.12)
                post.addChildNode(head)
                let tray = SCNNode(geometry: SCNBox(width: 0.7, height: 0.03, length: 0.7, chamferRadius: 0))
                tray.geometry!.firstMaterial = flat(NSColor(rgb: (0.62, 0.76, 0.8)))
                tray.position = v3(-0.15, -0.34, -0.15)
                post.addChildNode(tray)
                post.name = "room:" + roomKey(station, bath)
                staticRoot.addChildNode(post)
            }
            if station.hasHangar {
                let hc = station.hangarCenter
                let anchor = hangarAnchors[station.name] ?? { let n = SCNNode(); propRoot.addChildNode(n); hangarAnchors[station.name] = n; return n }()
                anchor.position = v3(station.offset.x + hc.x, 0, station.offset.y + hc.y)
                for slot in station.hangarSlots {
                    let mark = SCNNode(geometry: SCNTube(innerRadius: 0.3, outerRadius: 0.34, height: 0.01))
                    mark.geometry!.firstMaterial = flat(NSColor(Colors.hangar).lighter(0.18))
                    mark.position = v3(station.offset.x + slot.x, 0.006, station.offset.y + slot.y)
                    staticRoot.addChildNode(mark)
                }
            }
            for c in station.corridorCells where (c.x + c.y * 3) % 4 == 0 {
                let d = SCNNode(geometry: SCNPlane(width: 0.12, height: 0.12))
                d.geometry!.firstMaterial = flat(Palette.void)
                d.eulerAngles.x = -.pi / 2
                d.position = v3(station.offset.x + Double(c.x), 0.004, station.offset.y + Double(c.y))
                staticRoot.addChildNode(d)
            }
            let core = SCNNode(geometry: SCNBox(width: 0.7, height: 2.3, length: 0.7, chamferRadius: 0))
            core.geometry!.firstMaterial = lit(Palette.core)
            let mp = station.monolithPosition
            core.position = v3(station.offset.x + mp.x, 1.15, station.offset.y + mp.y)
            core.name = "station:" + station.name
            staticRoot.addChildNode(core)
            let glow = SCNNode(geometry: SCNBox(width: 0.72, height: 0.04, length: 0.72, chamferRadius: 0))
            glow.geometry!.firstMaterial = flat(NSColor(rgb: (0.55, 0.75, 1.0)))
            glow.position = v3(station.offset.x + mp.x, 1.75, station.offset.y + mp.y)
            staticRoot.addChildNode(glow)
            for bed in station.beds {
                if bed.level == 0 {
                    let b = SCNNode(geometry: SCNPlane(width: 0.34, height: 0.72))
                    b.geometry!.firstMaterial = flat(NSColor(Colors.bed))
                    b.eulerAngles.x = -.pi / 2
                    b.position = v3(station.offset.x + bed.pos.x, 0.005, station.offset.y + bed.pos.y)
                    b.name = "room:\(station.name)|kind:quarters"
                    staticRoot.addChildNode(b)
                } else {
                    // The upper bunk: a slab on four thin posts.
                    let slab = SCNNode(geometry: SCNBox(width: 0.36, height: 0.03, length: 0.74, chamferRadius: 0))
                    slab.geometry!.firstMaterial = lit(NSColor(Colors.bed).lighter(0.08))
                    slab.position = v3(station.offset.x + bed.pos.x, 0.34, station.offset.y + bed.pos.y)
                    slab.name = "room:\(station.name)|kind:quarters"
                    for dx in [-0.16, 0.16] { for dz in [-0.35, 0.35] {
                        let post = SCNNode(geometry: SCNBox(width: 0.025, height: 0.34, length: 0.025, chamferRadius: 0))
                        post.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.22, 0.3)))
                        post.position = v3(dx, -0.17, dz)
                        slab.addChildNode(post)
                    } }
                    staticRoot.addChildNode(slab)
                }
            }

            for room in station.rooms.values {
                let key = roomKey(station, room)
                var tiles: [SCNNode] = []
                // Construction progress: no branch = empty grey floor; a local branch starts the tiling,
                // commits add more, and pushing finishes it.
                // Dark while it's just a conversation; lit as soon as a branch exists; power cut when left alone.
                let progress: Double = room.key.hasPrefix("proj:") ? 0 : 1
                let powered = room.key.hasPrefix("kind:") || crewRoomInfo[key] != nil || Date().timeIntervalSince(room.lastActive) < StationController.powerWindow
                roomPower[key] = powered
                let failing = checksFailing(room)
                let dusty = isDusty(room)
                let grey = NSColor(rgb: (0.27, 0.28, 0.33))          // an empty room's floor
                let subfloor = NSColor(rgb: (0.15, 0.16, 0.21))      // where tiles have not been laid yet
                let full = isRemoteOnly(station, room) ? NSColor(room.color).darker(0.14) : NSColor(room.color)
                let provisional = isProvisional(station, room)
                let ordered = room.cells.sorted { (a, b) in
                    let da = abs(a.x - (station.doorCell(of: room.key)?.x ?? a.x)) + abs(a.y - (station.doorCell(of: room.key)?.y ?? a.y))
                    let db = abs(b.x - (station.doorCell(of: room.key)?.x ?? b.x)) + abs(b.y - (station.doorCell(of: room.key)?.y ?? b.y))
                    return da != db ? da < db : (a.y, a.x) < (b.y, b.x)
                }
                let tiled = Int((Double(ordered.count) * progress).rounded())
                let pending = undelivered.contains(key)
                for (i, c) in ordered.enumerated() {
                    if pending {
                        addTile(station: station, cell: c, owner: room.key, color: grey, name: "room:" + key)
                    }
                    var color = progress == 0 ? full.darker(0.32) : (i < tiled ? full : subfloor)
                    if !powered { color = color.darker(0.2) }
                    let t = addTile(station: station, cell: c, owner: room.key, color: color, name: "room:" + key)
                    if pending { t.opacity = 0; t.position.y = 0.003 }
                    else if provisional { t.opacity = 0.38 }
                    tiles.append(t)
                    if failing || dusty {
                        let overlay = SCNNode(geometry: SCNPlane(width: 1, height: 1))
                        overlay.geometry!.firstMaterial = flat(failing ? NSColor(rgb: (0.95, 0.2, 0.2)) : NSColor(rgb: (0.62, 0.62, 0.68)))
                        overlay.eulerAngles.x = -.pi / 2
                        overlay.position = v3(t.position.x, 0.004, t.position.z)
                        overlay.name = "room:" + key
                        if failing {
                            overlay.opacity = 0.15
                            overlay.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.5, duration: 0.7), .fadeOpacity(to: 0.12, duration: 0.9)])))
                        } else {
                            overlay.opacity = 0.28
                        }
                        staticRoot.addChildNode(overlay)
                    }
                }
                roomTiles[key] = tiles
                if provisional, !pending {
                    // A thin frame round each tile's outer edges: reserved, not built.
                    let cellSet = Set(room.cells)
                    for c in room.cells {
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !cellSet.contains(Cell(x: c.x + dx, y: c.y + dy)) {
                            let edge = SCNNode(geometry: SCNBox(width: dx == 0 ? 1.0 : 0.04, height: 0.01, length: dy == 0 ? 1.0 : 0.04, chamferRadius: 0))
                            edge.geometry!.firstMaterial = flat(full.lighter(0.25))
                            edge.position = v3(station.offset.x + Double(c.x) + Double(dx) * 0.48, 0.006, station.offset.y + Double(c.y) + Double(dy) * 0.48)
                            edge.name = "room:" + key
                            staticRoot.addChildNode(edge)
                        }
                    }
                }
                outlines.removeValue(forKey: key)?.removeFromParentNode()
            }
        }
        for (key, o) in outlines where !undelivered.contains(key) { o.removeFromParentNode(); outlines[key] = nil }
        rebuildLabels()
        rebuildMarkers()
        for key in fadeIn {
            for t in roomTiles[key] ?? [] { let o = t.opacity; t.opacity = 0; t.runAction(.fadeOpacity(to: o, duration: 2.5)) }
            if let l = roomLabels[key] { let o = l.opacity; l.opacity = 0; l.runAction(.fadeOpacity(to: o, duration: 2.5)) }
        }
        fadeIn = []

        (targetFocus, targetHalf) = frame(for: Array(fleet.stations.values))
        if let f = focused { focusNow(on: f) }
        fleet.save()
    }

    private static func displayName(_ room: Room) -> String {
        switch room.key {
        case "kind:quarters": return "dorm"
        case "kind:lounge": return "lounge"
        case "kind:bath": return "bath"
        default: return room.name
        }
    }

    /// Dark ink for anything written on a tile, whatever the tile's colour.
    static let inkOnTile = NSColor(rgb: (0.03, 0.03, 0.05))
    /// Floor cells under a room's writing, so boxes and cones keep off the words.
    private var labelCells: [String: Set<Cell>] = [:]

    /// Whose office this is, for the floor: the teammate GitHub names, else the peer who has it checked out.
    private func occupant(of key: String) -> String? {
        if let info = crewRoomInfo[key] { return crewName(info.author) }
        if let peer = peerOffices[key]?.keys.sorted().first { return peer }
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2, let room = fleet.stations[parts[0]]?.rooms[parts[1]], room.worktree != nil, room.key.hasPrefix("task:") {
            return github.myLogin().map(crewName) ?? "me"
        }
        return nil
    }

    /// Lays each room's name flat beside it on the side with free floor, or cut into the tile when boxed in.
    private func rebuildLabels() {
        labelRoot.childNodes.forEach { $0.removeFromParentNode() }
        roomLabels = [:]
        floorLabels = []
        labelCells = [:]
        func reserve(_ key: String, _ center: SIMD2<Double>, _ half: SIMD2<Double>) {
            let lo = center - half, hi = center + half
            for x in Int((lo.x + 0.5).rounded(.down))...Int((hi.x + 0.5).rounded(.down)) {
                for y in Int((lo.y + 0.5).rounded(.down))...Int((hi.y + 0.5).rounded(.down)) { labelCells[key, default: []].insert(Cell(x: x, y: y)) }
            }
        }
        func add(_ node: SCNNode, yaw: Double, center: SIMD2<Double>) {
            node.eulerAngles.y = yaw
            let y = node.position.y > 0 ? Double(node.position.y) : 0.01
            node.position = v3(center.x, y, center.y)
            node.renderingOrder = 10
            labelRoot.addChildNode(node)
            floorLabels.append((node, yaw))
        }
        for station in fleet.stations.values {
            let ox = station.offset.x, oz = station.offset.y
            let name = floorText(station.name, color: Palette.text, size: 1.0, maxWidth: 10, lines: 1)
            let b = station.bounds
            add(name.node, yaw: 0, center: SIMD2(ox + Double(b.min.x) - 0.5 + name.width / 2, oz + Double(b.max.y) + 1.2 + name.height / 2))

            if station.hasPad {
                if !ConfigStore.shared.current.stagingBranch.isEmpty {
                    let deckLabel = floorSign("staging", color: NSColor(rgb: (0.42, 0.52, 0.58)), size: 0.24)
                    deckLabel.node.position.y = 0.012
                    let dc = station.deckCells
                    let dcorner = SIMD2(Double(dc.map(\.x).max()!) + 0.42 - deckLabel.width / 2, Double(dc.map(\.y).max()!) + 0.42 - deckLabel.height / 2)
                    add(deckLabel.node, yaw: 0, center: dcorner + SIMD2(ox, oz))
                }
                let storeLabel = floorSign("storage", color: NSColor(rgb: (0.40, 0.44, 0.56)), size: 0.24)
                storeLabel.node.position.y = 0.012
                let sc = station.storageCells
                let scorner = SIMD2(Double(sc.map(\.x).max()!) + 0.42 - storeLabel.width / 2, Double(sc.map(\.y).max()!) + 0.42 - storeLabel.height / 2)
                add(storeLabel.node, yaw: 0, center: scorner + SIMD2(ox, oz))
                let padLabel = floorSign("launch", color: NSColor(rgb: (0.45, 0.48, 0.58)), size: 0.34)
                padLabel.node.position.y = 0.012
                let pc = station.padCells
                let corner = SIMD2(Double(pc.map(\.x).max()!) + 0.42 - padLabel.width / 2, Double(pc.map(\.y).max()!) + 0.42 - padLabel.height / 2)
                add(padLabel.node, yaw: 0, center: corner + SIMD2(ox, oz))
            }
            if station.hasHangar {
                let hangarLabel = floorSign("bay", color: NSColor(Colors.hangar).lighter(0.18), size: 0.36)
                hangarLabel.node.position.y = 0.012
                let hc = station.hangarCells
                let corner = SIMD2(Double(hc.map(\.x).max()!) + 0.42 - hangarLabel.width / 2, Double(hc.map(\.y).max()!) + 0.42 - hangarLabel.height / 2)
                add(hangarLabel.node, yaw: 0, center: corner + SIMD2(ox, oz))
            }
            let occupied: (Cell) -> Bool = { c in
                station.coreCells.contains(c) || station.hangarCells.contains(c) || station.padCells.contains(c) || station.storageCells.contains(c)
                    || station.deckCells.contains(c) || station.isCorridor(c) || station.room(at: c) != nil
            }
            var placed: [(min: SIMD2<Double>, max: SIMD2<Double>)] = []
            func collides(_ lo: SIMD2<Double>, _ hi: SIMD2<Double>) -> Bool {
                // Tiles are centred on integer coordinates: any tile the text touches counts.
                let x0 = Int((lo.x + 0.25).rounded(.down)), x1 = max(x0, Int((hi.x - 0.25).rounded(.down)))
                let y0 = Int((lo.y + 0.25).rounded(.down)), y1 = max(y0, Int((hi.y - 0.25).rounded(.down)))
                for x in x0...x1 {
                    for y in y0...y1 where occupied(Cell(x: x, y: y)) {
                        return true
                    }
                }
                return placed.contains { !(hi.x <= $0.min.x || lo.x >= $0.max.x || hi.y <= $0.min.y || lo.y >= $0.max.y) }
            }
            enum Side { case south, north, east, west }
            for room in station.rooms.values.sorted(by: { $0.key < $1.key }) {
                let text = StationController.displayName(room)
                if room.key.hasPrefix("kind:") {
                    // Fixed rooms: a short word cut into the middle of the floor.
                    let accent = room.key == "kind:quarters" ? NSColor(Colors.bed) : NSColor(room.color).lighter(0.2)
                    let label = floorSign(text, color: accent, size: 0.36)
                    label.node.position.y = 0.012
                    // Tucked into the far corner of the floor, clear of beds and rings.
                    let maxY = room.cells.map(\.y).max()!
                    let maxX = room.cells.filter { $0.y == maxY }.map(\.x).max()!
                    let corner = SIMD2(Double(maxX) + 0.42 - label.width / 2, Double(maxY) + 0.42 - label.height / 2)
                    add(label.node, yaw: 0, center: corner + SIMD2(ox, oz))
                    label.node.name = "room:" + roomKey(station, room)
                    roomLabels[roomKey(station, room)] = label.node
                    continue
                }
                // 3. Long names get smaller type.
                let size = max(0.3, min(0.46, 6.4 / Double(max(14, text.count))))
                let minX = room.cells.map(\.x).min()!, maxX = room.cells.map(\.x).max()!
                let minY = room.cells.map(\.y).min()!, maxY = room.cells.map(\.y).max()!
                let width = Double(maxX - minX + 1), depth = Double(maxY - minY + 1)
                let charW = 0.5 * size
                let key = roomKey(station, room)
                var node: SCNNode?

                for side in [Side.south, .north, .east, .west] {
                    let along = (side == .south || side == .north) ? width + 1.5 : depth + 1.5
                    let lines = max(1, min(2, Int((Double(text.count) * charW / along).rounded(.up))))
                    let label = floorText(text, color: NSColor(room.color).lighter(0.12), size: size, maxWidth: along, lines: lines)
                    let (w, h) = (label.width, label.height)
                    let center: SIMD2<Double>
                    let yaw: Double
                    let half: SIMD2<Double>
                    switch side {
                    case .south: yaw = 0; center = SIMD2(Double(minX) - 0.45 + w / 2, Double(maxY) + 0.62 + h / 2); half = SIMD2(w / 2, h / 2)
                    case .north: yaw = 0; center = SIMD2(Double(minX) - 0.45 + w / 2, Double(minY) - 0.62 - h / 2); half = SIMD2(w / 2, h / 2)
                    case .east: yaw = .pi / 2; center = SIMD2(Double(maxX) + 0.62 + h / 2, Double(maxY) + 0.45 - w / 2); half = SIMD2(h / 2, w / 2)
                    case .west: yaw = .pi / 2; center = SIMD2(Double(minX) - 0.62 - h / 2, Double(maxY) + 0.45 - w / 2); half = SIMD2(h / 2, w / 2)
                    }
                    let lo = center - half, hi = center + half
                    if collides(lo, hi) { continue }
                    placed.append((lo, hi))
                    add(label.node, yaw: yaw, center: center + SIMD2(ox, oz))
                    node = label.node
                    break
                }
                if node == nil {
                    // Boxed in: cut the name into the tile itself, shrunk until it fits the floor.
                    let horizontal = width >= depth
                    let along = (horizontal ? width : depth) - 0.3
                    let across = (horizontal ? depth : width) - 0.3
                    var size = size * 0.85
                    var lines = max(1, min(3, Int((Double(text.count) * 0.5 * size / along).rounded(.up))))
                    let fitWidth = 3 * along / (Double(text.count) * 0.5)          // three lines at most
                    let fitDepth = across / (Double(lines) * 1.15)                 // stacked lines must fit too
                    size = max(0.16, min(size, fitWidth, fitDepth))
                    lines = max(1, min(3, Int((Double(text.count) * 0.5 * size / along).rounded(.up))))
                    let label = floorText(text, color: StationController.inkOnTile, size: size, maxWidth: along, lines: lines, bold: true)
                    let maxYRow = room.cells.map(\.y).max()!
                    let anchor = room.cells.filter { $0.y == maxYRow }.min { $0.x < $1.x }!
                    let center = horizontal
                        ? SIMD2(ox + Double(anchor.x) - 0.35 + label.width / 2, oz + Double(anchor.y) + 0.35 - label.height / 2)
                        : SIMD2(ox + Double(anchor.x) - 0.35 + label.height / 2, oz + Double(anchor.y) + 0.35 - label.width / 2)
                    label.node.position.y = 0.02
                    add(label.node, yaw: horizontal ? 0 : .pi / 2, center: center)
                    let half = horizontal ? SIMD2(label.width / 2, label.height / 2) : SIMD2(label.height / 2, label.width / 2)
                    reserve(key, center - SIMD2(ox, oz), half)
                    node = label.node
                }
                if let who = occupant(of: key) {
                    let sign = floorSign(who, color: StationController.inkOnTile, size: 0.3)
                    sign.node.position.y = 0.012
                    let maxYRow = room.cells.map(\.y).max()!
                    let cx = room.cells.filter { $0.y == maxYRow }.map(\.x).max()!
                    let corner = SIMD2(Double(cx) + 0.42 - sign.width / 2, Double(maxYRow) + 0.42 - sign.height / 2)
                    add(sign.node, yaw: 0, center: corner + SIMD2(ox, oz))
                    reserve(key, corner, SIMD2(sign.width / 2, sign.height / 2))
                    sign.node.name = "room:" + key
                }
                guard let node else { continue }
                node.name = "room:" + key
                if undelivered.contains(key) { node.opacity = 0 } else if isProvisional(station, room) { node.opacity = 0.55 }
                roomLabels[key] = node
            }
        }
    }

    /// Tells each station what is standing on its floor, so walks thread between the props.
    private func refreshObstacles() {
        var blocked: [String: Set<Cell>] = [:]
        func mark(_ station: String, _ node: SCNNode, offset: SIMD2<Double>) {
            let (lo, hi) = node.boundingBox
            let p = SIMD2(Double(node.position.x) - offset.x, Double(node.position.z) - offset.y)
            let r = Double(max(hi.x - lo.x, hi.z - lo.z)) / 2 * 0.8
            let f = Double(Station.fine)
            for sx in Int(((p.x - r) * f).rounded())...Int(((p.x + r) * f).rounded()) {
                for sy in Int(((p.y - r) * f).rounded())...Int(((p.y + r) * f).rounded()) { blocked[station, default: []].insert(Cell(x: sx, y: sy)) }
            }
        }
        for n in markerRoot.childNodes {
            guard let name = n.name, let colon = name.firstIndex(of: ":"), let bar = name.firstIndex(of: "|"), colon < bar else { continue }
            let stationName = String(name[name.index(after: colon)..<bar])
            guard let st = fleet.stations[stationName] else { continue }
            mark(stationName, n, offset: st.offset)
        }
        for m in minions.values {
            for p in m.pyramids + m.queuedCones { mark(m.station, p, offset: .zero) }
        }
        for st in fleet.stations.values { st.obstacles = blocked[st.name] ?? [] }
    }

    /// An office's floor from the far corners in: boxes go there first, so the doorway stays clear.
    private func farCells(_ station: Station, _ room: Room) -> [Cell] {
        let door = station.doorCell(of: room.key) ?? room.cells.first!
        let written = labelCells[roomKey(station, room)] ?? []
        return room.cells.sorted { a, b in
            let wa = written.contains(a), wb = written.contains(b)
            if wa != wb { return !wa }   // cells under writing come last
            let da = abs(a.x - door.x) + abs(a.y - door.y), db = abs(b.x - door.x) + abs(b.y - door.y)
            return da != db ? da > db : (a.y, a.x) < (b.y, b.x)
        }
    }

    /// Grey boxes pile up in an office as commits land; the pull request state colours them.
    private func rebuildMarkers() {
        markerRoot.childNodes.filter { $0.name != "haul" }.forEach { $0.removeFromParentNode() }   // a crate waiting for its carrier stays
        for station in fleet.stations.values {
            for room in station.rooms.values where room.branch != nil || crewBoxes[roomKey(station, room)] != nil || peerBoxes[roomKey(station, room)] != nil {
                let key = roomKey(station, room)
                var count: Int
                var ghosts = 0                 // uncommitted work: unfinished, translucent boxes
                var pr: PullRequest?
                var packaged = false           // a pull request bundles everything into one strapped package
                var boxOpacity = 1.0
                if room.branch == nil {
                    guard let cb = crewBoxes[key] ?? peerBoxes[key] else { continue }
                    count = min(16, max(1, cb.count))
                    pr = PullRequest(number: 0, title: "", state: cb.state, reviewDecision: "", isDraft: false, url: "")
                } else {
                    let local = localState(room)
                    let dirtyFiles = room.worktree.map { github.dirtyFiles(worktree: $0) } ?? 0
                    if (local.commits == 0 && dirtyFiles == 0) || haulingRooms.contains(key) { continue }   // nothing to show, or on its way to storage
                    pr = room.repoRoot.flatMap { github.pull(branch: room.branch!, repoRoot: $0) }
                    count = min(16, Int(pow(Double(local.commits), 0.7).rounded(.up)))
                    ghosts = min(8, Int(pow(Double(dirtyFiles), 0.6).rounded(.up)))
                    packaged = pr != nil && pr!.state != "CLOSED"
                }
                // No pull request: the room's own tint. With one: the status colour, shaded the same way.
                let base = NSColor(room.color).lighter(0.12)
                let status: NSColor?
                switch (pr?.state, pr?.reviewDecision, pr?.isDraft) {
                case (nil, _, _): status = nil
                case ("MERGED", _, _): status = NSColor(rgb: (0.6, 0.4, 0.9))
                case ("CLOSED", _, _): status = NSColor(rgb: (0.35, 0.35, 0.4))
                case (_, "APPROVED", _): status = NSColor(rgb: (0.45, 0.95, 0.5))
                case (_, "CHANGES_REQUESTED", _): status = NSColor(rgb: (0.95, 0.3, 0.3))
                case (_, _, true): status = NSColor(rgb: (0.6, 0.62, 0.68))
                default: status = NSColor(rgb: (0.4, 0.82, 0.45))
                }
                var color = status.map { $0.mixed(with: base, 0.15) } ?? base
                let failing = checksFailing(room)
                if isDusty(room) { color = color.mixed(with: NSColor(rgb: (0.55, 0.55, 0.6)), 0.55) }
                let floorShadow = NSColor(room.color).darker(0.16)
                if packaged {
                    // One package for the whole pull request, sized by the work in it, strapped in the status colour.
                    let cell = farCells(station, room).first!
                    let size = 0.42 + min(0.28, Double(count) * 0.03)
                    let pkg = Props.package(color: NSColor(room.color).lighter(0.1), band: status ?? NSColor(rgb: (0.55, 0.55, 0.6)), size: size)
                    pkg.position = v3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
                    pkg.name = "box:" + key
                    pkg.opacity = undelivered.contains(key) ? 0 : 1
                    if failing {
                        let shell = SCNNode(geometry: SCNBox(width: size * 1.2, height: size, length: size * 1.2, chamferRadius: 0))
                        shell.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2)))
                        shell.opacity = 0.2
                        shell.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)])))
                        pkg.addChildNode(shell)
                    }
                    markerRoot.addChildNode(pkg)
                    lastBoxCount[key] = 1
                    continue
                }
                // Deterministic clutter: sizes, turns and shades vary per box, and extras stack on top.
                var seed = UInt64(truncatingIfNeeded: key.hashValue) | 1
                func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
                let cells = farCells(station, room)
                var placedBoxes: [(pos: SIMD3<Double>, size: Double)] = []
                for i in 0..<(count + ghosts) {
                    let ghost = i >= count
                    let size = [0.18, 0.26, 0.34][min(2, Int(rnd() * 3))]
                    let shade = CGFloat(rnd() * 0.1 - 0.04)
                    let box = SCNBox(width: size, height: size, length: size, chamferRadius: 0)
                    let tint = color.lighter(shade)
                    // Flat game-style shading: light top, mid and dark sides, no lights involved.
                    let top = flat(tint.lighter(0.14)), mid = flat(tint), dark = flat(tint.darker(0.13))
                    box.materials = [mid, dark, mid, dark, top, top]
                    let n = SCNNode(geometry: box)
                    let shadow = SCNNode(geometry: SCNPlane(width: size * 1.25, height: size * 1.25))
                    shadow.geometry!.firstMaterial = flat(floorShadow)
                    shadow.eulerAngles.x = -.pi / 2
                    shadow.position = v3(size * 0.08, -size / 2 + 0.004, size * 0.08)
                    shadow.name = "box:" + key
                    n.addChildNode(shadow)
                    let pos: SIMD3<Double>
                    if i >= 8, let base = placedBoxes[i - 8] as (pos: SIMD3<Double>, size: Double)? {
                        pos = SIMD3(base.pos.x + (rnd() - 0.5) * 0.06, base.pos.y + base.size / 2 + size / 2, base.pos.z + (rnd() - 0.5) * 0.06)
                    } else {
                        let cell = cells[(i / 3) % cells.count]
                        let room = max(0, 0.86 - size * 1.25)   // keep the box and its shadow inside the tile
                        pos = SIMD3(station.offset.x + Double(cell.x) + (rnd() - 0.5) * room, size / 2, station.offset.y + Double(cell.y) + (rnd() - 0.5) * room)
                    }
                    placedBoxes.append((pos, size))
                    n.position = v3(pos.x, pos.y, pos.z)
                    n.eulerAngles.y = rnd() * 0.9
                    n.name = "box:" + key
                    n.opacity = undelivered.contains(key) ? 0 : (ghost ? 0.38 : boxOpacity)
                    if failing && !ghost {
                        let shell = SCNNode(geometry: SCNBox(width: size * 1.25, height: size * 1.25, length: size * 1.25, chamferRadius: 0))
                        shell.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2)))
                        shell.opacity = 0.2
                        shell.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)])))
                        shell.name = "box:" + key
                        n.addChildNode(shell)
                    }
                    markerRoot.addChildNode(n)
                }
                // More commits than last time while the owner is in: it carries the new box in.
                if let last = lastBoxCount[key], count > last, room.branch != nil,
                   let m = minions.values.first(where: { $0.station == station.name && $0.place == .room(room.key) && $0.errand == nil && $0.carried == nil }) {
                    let carry = SCNNode(geometry: SCNBox(width: 0.24, height: 0.24, length: 0.24, chamferRadius: 0))
                    carry.geometry!.firstMaterial = lit(color)
                    carry.position = v3(0, m.headHeight + 0.14, 0)
                    m.node.addChildNode(carry)
                    m.carried = carry
                    m.commitDrop = true
                    if let dest = room.cells.filter({ $0 != m.cell }).randomElement() { walk(m, to: dest) }
                }
                lastBoxCount[key] = count + ghosts
            }
            // Storage and the test deck come from GitHub: merged pull requests not yet released, per repo.
            if station.hasPad {
                for (root, info) in repoRoots where info.station == station.name {
                    if let c = github.cargo(repoRoot: root) { station.stored[info.repo] = c.storage; station.staged[info.repo] = c.deck }
                }
            }
            let purple = NSColor(rgb: (0.6, 0.4, 0.9))
            for (area, piles, cells, neat) in [("storage", station.stored, station.storageCells, false), ("deck", station.staged, station.deckCells, true)] where station.hasPad && !cells.isEmpty {
                var seed = UInt64(truncatingIfNeeded: (station.name + area).hashValue) | 1
                func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
                // Every other row holds crates; the rows between are aisles to walk down.
                let rows = Set(cells.map(\.y)).sorted()
                let crateRows = Set(rows.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
                let sorted = cells.filter { crateRows.contains($0.y) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                // The deck keeps its two rows apart: tested nearest the pad (north, the lower row number),
                // untested on the far row. Within a row, crates group by repository in stacks of three, so a
                // repository's lineup stands together and loads in one sweep.
                let rowList = crateRows.sorted()
                let testedRow = sorted.filter { $0.y == rowList.first }, untestedRow = sorted.filter { $0.y == rowList.last }
                var nextSlot: [Int: Int] = [:]   // per row group: the first free stack
                func place(_ pkg: SCNNode, group: Int, row: [Cell], slot: Int, level: Int) {
                    let cap = row.count * 2
                    let cell = row[(slot % cap) / 2], side = Double(slot % 2) * 0.5 - 0.25
                    let y = Double(level + 3 * (slot / cap)) * 0.34
                    let jitter = neat ? 0.0 : (rnd() - 0.5) * 0.22
                    pkg.position = v3(station.offset.x + Double(cell.x) + side + jitter, y, station.offset.y + Double(cell.y) + (neat ? 0 : (rnd() - 0.5) * 0.3))
                }
                let cargoByRepo = Dictionary(repoRoots.filter { $0.value.station == station.name }.compactMap { (root, info) -> (String, GitHubResolver.Cargo)? in
                    github.cargo(repoRoot: root).map { (info.repo, $0) } }, uniquingKeysWith: { a, _ in a })
                for (repo, n) in piles.sorted(by: { $0.key < $1.key }) where n > 0 {
                    let c = NSColor(fleet.color(forRepo: repo))
                    let numbers = area == "deck" ? (cargoByRepo[repo]?.deckNumbers ?? []) : (cargoByRepo[repo]?.storageNumbers ?? [])
                    var placedInGroup: [Int: Int] = [:]   // this repository's crates so far, per row group
                    let starts: [Int: Int] = [0: nextSlot[0] ?? 0, 1: nextSlot[1] ?? 0]
                    for k in 0..<min(n, 48) {
                        let size = 0.38
                        let prNumber = k < numbers.count ? numbers[k] : 0
                        let cleared = area == "deck" && (cargoByRepo[repo]?.clearedNumbers.contains(prNumber) ?? false)
                        if area == "deck", haulingCrates.contains("\(repo)|\(prNumber)") { continue }
                        let pkg = Props.package(color: c.lighter(0.1), band: cleared ? NSColor(rgb: (0.45, 0.95, 0.5)) : purple, size: size, approved: cleared)
                        let group = (area == "deck" && rowList.count > 1) ? (cleared ? 0 : 1) : 0
                        let row = area == "deck" && rowList.count > 1 ? (cleared ? testedRow : untestedRow) : sorted
                        let j = placedInGroup[group, default: 0]
                        place(pkg, group: group, row: row, slot: starts[group]! + j / 3, level: j % 3)
                        placedInGroup[group] = j + 1
                        pkg.eulerAngles.y = neat ? 0 : (rnd() - 0.5) * 0.7
                        pkg.name = "\(area):\(station.name)|\(repo)|\(prNumber)"
                        pkg.enumerateChildNodes { c, _ in c.name = pkg.name }
                        markerRoot.addChildNode(pkg)
                    }
                    for (g, count) in placedInGroup where count > 0 { nextSlot[g] = starts[g]! + (count + 2) / 3 }
                }
            }
        }
        refreshObstacles()
    }

    /// Flame on, a slow climb that carries the rocket out of the frame, then gone.
    private func liftOff(_ node: SCNNode) {
        drone.sweep(up: true)
        node.childNode(withName: "flame", recursively: false)?.opacity = 1
        let rise = SCNAction.moveBy(x: 0, y: 40, z: 0, duration: 12)
        rise.timingMode = .easeIn
        let flicker = SCNAction.repeat(.sequence([.scale(to: 1.04, duration: 0.08), .scale(to: 0.98, duration: 0.08)]), count: 8)
        node.runAction(.sequence([flicker, .group([rise, .sequence([.wait(duration: 9), .fadeOut(duration: 3)])]), .removeFromParentNode()]))
    }

    /// Rockets on the pad for open release pull requests; a merged one lifts off.
    private func rebuildRockets() {
        for launch in github.takeLaunches() {
            guard let info = repoRoots[launch.repoRoot] else { continue }
            if !launch.pr.isProduction {
                if let st = fleet.stations[info.station] { stageCargo(station: st, repo: info.repo) }
                ringBell(seed: launch.pr.number)
                continue
            }
            let key = "\(info.station)|\(launch.pr.number)"
            let existing = rockets.keys.first { $0.hasPrefix(key + "|") || $0 == key }
            let node = existing.flatMap { rockets.removeValue(forKey: $0) } ?? {
                let n = Props.rocket(color: NSColor(fleet.color(forRepo: info.repo)), tall: launch.pr.isProduction)
                if let st = fleet.stations[info.station] { n.position = v3(st.offset.x + st.padCenter.x, 0, st.offset.y + st.padCenter.y) }
                rocketRoot.addChildNode(n)
                return n
            }()
            node.childNode(withName: "hold", recursively: false)?.removeFromParentNode()
            let pk = info.station + "|" + info.repo
            if loadedRockets[pk] != nil { loadedRockets[pk] = nil; liftOff(node) }
            else if let st = fleet.stations[info.station] { loadRocket(station: st, rocket: node, repo: info.repo) } else { liftOff(node) }
            logEvent("\(info.repo) launched to \(launch.pr.base): \(launch.pr.title)")
            ringBell(seed: launch.pr.number)
        }
        var live = Set<String>()
        for (root, info) in repoRoots {
            guard let station = fleet.stations[info.station], let open = github.openReleases(repoRoot: root) else { continue }
            let hasProduction = open.contains(where: \.isProduction)
            let stagingIsDeck = !ConfigStore.shared.current.stagingBranch.isEmpty
            for pr in open where pr.isProduction || (!hasProduction && !stagingIsDeck) {
                let cargoBucket = max((stagingIsDeck ? station.staged : station.stored)[info.repo] ?? 0, loadedRockets[info.station + "|" + info.repo] ?? 0) / 3
                let key = "\(info.station)|\(pr.number)\(pr.untested ? "|hold" : "")|c\(cargoBucket)"
                live.insert(key)
                if rockets[key] != nil { continue }
                let cargoPile = stagingIsDeck ? station.staged : station.stored
                let n = Props.rocket(color: NSColor(fleet.color(forRepo: info.repo)), tall: pr.isProduction, cargo: max(cargoPile[info.repo] ?? 0, loadedRockets[info.station + "|" + info.repo] ?? 0))
                if pr.untested {
                    let deco = Props.holdDecoration(around: SIMD3(0, 0, 0), tall: pr.isProduction)
                    deco.name = "hold"
                    n.addChildNode(deco)
                }
                let slot = rockets.values.filter { $0.parent != nil }.count % 4
                let offsets: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(1.3, 0), SIMD2(-1.3, 0), SIMD2(0, 1.2)]
                let pc = station.padCenter + offsets[slot]
                n.position = v3(station.offset.x + pc.x, 0, station.offset.y + pc.y)
                let status = pr.untested ? " · untested, holding on the pad" : " · cleared for launch"
                n.name = "rocket:\(pr.url)|\(info.repo) · \(pr.head) → \(pr.base) · #\(pr.number) \(pr.title)\(status)"
                let pk = info.station + "|" + info.repo
                if pr.isProduction, !pr.untested {
                    if loadedRockets[pk] != nil { addSteam(to: n) }
                    else if pendingLaunch[pk] == nil { DispatchQueue.main.async { [weak self] in self?.enqueue { self?.loadRocket(station: station, rocket: n, repo: info.repo, thenLaunch: false) } } }
                }
                n.enumerateChildNodes { c, _ in if c.name != "flame" { c.name = n.name } }
                rocketRoot.addChildNode(n)
                rockets[key] = n
                logEvent("\(info.repo): release to \(pr.base) on the pad" + (pr.untested ? " (untested)" : ""))
            }
        }
        for (key, n) in rockets where !live.contains(key) && !n.hasActions { n.removeFromParentNode(); rockets[key] = nil }
        rebuildDueRings()
    }

    private let ringRoot = SCNNode()
    /// Cargo waiting with no rocket yet: a faint ring in the repo colour on the pad, a release is due.
    private func rebuildDueRings() {
        if ringRoot.parent == nil { propRoot.addChildNode(ringRoot) }
        ringRoot.childNodes.forEach { $0.removeFromParentNode() }
        for station in fleet.stations.values where station.hasPad {
            let pile = ConfigStore.shared.current.stagingBranch.isEmpty ? station.stored : station.staged
            let waiting = pile.filter { $0.value > 0 }.map(\.key).sorted()
            let withRocket = Set(repoRoots.filter { $0.value.station == station.name }.compactMap { (root, info) -> String? in
                (github.openReleases(repoRoot: root)?.contains(where: \.isProduction) == true) ? info.repo : nil
            })
            for (i, repo) in waiting.filter({ !withRocket.contains($0) }).enumerated() {
                let radius = 1.62 + Double(i) * 0.12
                let ring = SCNNode(geometry: SCNTube(innerRadius: radius, outerRadius: radius + 0.05, height: 0.008))
                ring.geometry!.firstMaterial = flat(NSColor(fleet.color(forRepo: repo)))
                ring.opacity = 0.3
                ring.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.6, duration: 1.6), .fadeOpacity(to: 0.25, duration: 1.6)])))
                let pc = station.padCenter
                ring.position = v3(station.offset.x + pc.x, 0.009, station.offset.y + pc.y)
                ring.name = "pad:" + station.name
                ringRoot.addChildNode(ring)
            }
        }
    }

    // MARK: hud

    private func buildHUD() {
        hud.scaleMode = .resizeFill
        hud.backgroundColor = .clear
        hud.isUserInteractionEnabled = false
        infoLabel.fontSize = 13
        infoLabel.fontColor = Palette.text
        infoLabel.horizontalAlignmentMode = .left
        infoLabel.verticalAlignmentMode = .bottom
        infoBackground.anchorPoint = CGPoint(x: 0, y: 0)
        hud.addChild(infoBackground)
        hud.addChild(infoLabel)
        shareLabel.fontSize = 10
        shareLabel.fontColor = Palette.dim
        shareLabel.horizontalAlignmentMode = .right
        shareLabel.verticalAlignmentMode = .top
        hud.addChild(shareDot)
        hud.addChild(shareLabel)
        statusLabel.fontSize = 10
        statusLabel.fontColor = Palette.dim
        statusLabel.horizontalAlignmentMode = .right
        statusLabel.verticalAlignmentMode = .bottom
        hud.addChild(statusLabel)
    }

    /// Top: repos in their colours with counts. Bottom: jobs with one tiny minion per worker, like the game.
    private func layoutLegend(active: [Minion], busy: Int, waiting: Int, asleep: Int) {
        let withOffices = Set(fleet.stations.values.flatMap { $0.rooms.values.compactMap(\.repo) })
        let withRockets = Set(repoRoots.filter { github.openReleases(repoRoot: $0.key)?.isEmpty == false }.map(\.value.repo))
        let repos = fleet.repoColors.keys.filter { withOffices.contains($0) || withRockets.contains($0) }
            .sorted { fleet.repoColors[$0]! < fleet.repoColors[$1]! }
        guard !repos.isEmpty else { return }
        var signature = "\(hud.size.width)|\(busy)|\(waiting)|\(asleep)|"
        let rootOf = Dictionary(repoRoots.map { ($0.value.repo, $0.key) }, uniquingKeysWith: { a, _ in a })
        for repo in repos {
            let offices = fleet.stations.values.flatMap { $0.rooms.values }.filter { $0.repo == repo }.count
            let workers = active.filter { $0.home.repo == repo && !$0.isSubagent }.count
            let loading = rootOf[repo].map { github.isBusy(repoRoot: $0) } ?? false
            signature += "\(repo):\(workers):\(offices):\(loading);"
        }
        guard signature != legendSignature else { return }
        legendSignature = signature
        legendNodes.forEach { $0.removeFromParent() }; legendNodes = []
        jobNodes.forEach { $0.removeFromParent() }; jobNodes = []
        let slot = hud.size.width / CGFloat(repos.count)
        for (i, repo) in repos.enumerated() {
            let x = slot * (CGFloat(i) + 0.5)
            let name = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
            name.fontSize = 14
            name.fontColor = NSColor(fleet.color(forRepo: repo)).lighter(0.15)
            name.text = repo
            name.horizontalAlignmentMode = .center
            name.verticalAlignmentMode = .top
            name.position = CGPoint(x: x, y: hud.size.height - 34)
            let offices = fleet.stations.values.flatMap { $0.rooms.values }.filter { $0.repo == repo }.count
            let workers = active.filter { $0.home.repo == repo && !$0.isSubagent }.count
            let counts = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
            counts.fontSize = 10
            counts.fontColor = Palette.dim
            counts.text = "\(workers) minions · \(offices) offices"
            counts.horizontalAlignmentMode = .center
            counts.verticalAlignmentMode = .top
            counts.position = CGPoint(x: x, y: hud.size.height - 52)
            hud.addChild(name); hud.addChild(counts)
            legendNodes.append(name); legendNodes.append(counts)
            // A small spinner beside the title while this repository is being refreshed from GitHub.
            if rootOf[repo].map({ github.isBusy(repoRoot: $0) }) == true {
                let spinner = SKSpriteNode(color: name.fontColor ?? Palette.dim, size: CGSize(width: 7, height: 7))
                spinner.position = CGPoint(x: x + name.frame.width / 2 + 12, y: hud.size.height - 41)
                spinner.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1.1)))
                spinner.alpha = 0.85
                hud.addChild(spinner); legendNodes.append(spinner)
            }
        }
        let jobs: [(String, Int, NSColor)] = [
            ("working", busy, NSColor(rgb: (0.35, 0.78, 0.85))),
            ("waiting", waiting, Palette.pyramid),
            ("sleeping", asleep, NSColor(Colors.quarters).lighter(0.25)),
        ]
        var x: CGFloat = hud.size.width - 16
        for (title, count, color) in jobs.reversed() {
            let icons = min(count, 8)
            let iconsWidth = CGFloat(icons) * 8
            for k in 0..<icons {
                let r = SKSpriteNode(color: Palette.minion, size: CGSize(width: 4, height: 9))
                r.position = CGPoint(x: x - iconsWidth + CGFloat(k) * 8 + 4, y: 14)
                hud.addChild(r); jobNodes.append(r)
            }
            x -= iconsWidth + 6
            let l = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
            l.fontSize = 12
            l.fontColor = color
            l.text = "\(title) \(count)"
            l.horizontalAlignmentMode = .right
            l.verticalAlignmentMode = .bottom
            l.position = CGPoint(x: x, y: 9)
            hud.addChild(l); jobNodes.append(l)
            x -= l.frame.width + 22
        }
    }

    private func logEvent(_ text: String) {
        let l = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
        l.fontSize = 11
        l.fontColor = Palette.text
        l.horizontalAlignmentMode = .left
        l.verticalAlignmentMode = .top
        l.text = text
        hud.addChild(l)
        eventLabels.insert((l, clock), at: 0)
        while eventLabels.count > 5 { eventLabels.removeLast().0.removeFromParent() }
    }

    private func roomInfo(station: Station, room: Room) -> String {
        var parts = [room.name]
        if room.key.hasPrefix("proj:") { parts.append("no branch yet · /start-issue or /grab-issue builds the office") }
        let local = localState(room)
        if local.local { parts.append(local.commits == 0 ? "local branch, nothing committed · a research session" : "local branch, \(local.commits) commits not pushed") }
        if let info = crewRoomInfo[roomKey(station, room)] {
            var line = "by \(crewName(info.author)) · ⎇ \(info.branch)"
            if let n = info.prNumber { line += " · PR #\(n) \(info.state.lowercased())" }
            if let t = info.title { line += " · " + t }
            parts.append(line)
        }
        if let claims = peerOffices[roomKey(station, room)], !claims.isEmpty {
            let who = claims.keys.sorted().joined(separator: ", ")
            parts.append((pushedByPeer.contains(roomKey(station, room)) ? "checked out by " : "local branch on ") + who)
        } else if isProvisional(station, room) && room.worktree == nil {
            parts.append("held for a while · nobody is working here right now")
        }
        if room.key == "kind:bots" { parts.append("dependabot and friends") }
        if room.key == "kind:lounge" { parts.append("waiting on you for a while · they chat here before bed") }
        if let branch = room.branch, let root = room.repoRoot {
            parts.append("⎇ " + branch)
            if let pr = github.pull(branch: branch, repoRoot: root) { parts.append(pr.summary); parts.append(pr.title) }
            if let w = room.worktree, let n = github.commitsAhead(worktree: w) { parts.append("\(n) commits") }
            if let w = room.worktree, github.dirtyFiles(worktree: w) > 0 { parts.append("\(github.dirtyFiles(worktree: w)) files uncommitted") }
        }
        let here = minions.values.filter { $0.station == station.name && $0.place == .room(room.key) && $0.state != .leaving }
        let workspaces = Set(here.map { URL(fileURLWithPath: $0.cwd).lastPathComponent }).sorted()
        if !workspaces.isEmpty { parts.append(workspaces.joined(separator: ", ")) }
        return parts.joined(separator: "   ")
    }

    private func updateInfo() {
        let active = minions.values.filter { $0.state != .leaving }
        let busy = active.filter(\.busy).count
        let waiting = active.filter { $0.activity == .waiting }.count
        let asleep = active.filter { $0.activity == .sleeping }.count
        statusLabel.text = ""
        infoLabel.position = CGPoint(x: 14, y: 12)

        if clock - hudClock > 0.5 {
            hudClock = clock
            layoutLegend(active: active, busy: busy, waiting: waiting, asleep: asleep)
            // Sharing indicator: green dot when broadcasting, with how many stations are in range.
            let sharing = peers.isRunning
            shareDot.isHidden = !sharing
            shareLabel.isHidden = !sharing
            if sharing {
                // Grey without a network, amber while looking, green once someone answers.
                let n = peerSnapshots.count
                let up = peers.networkUp
                let status = !up ? "no network" : n > 0 ? "\(n) peer\(n == 1 ? "" : "s") in range" : "nobody in range"
                shareLabel.text = "sharing as \(peers.name) · " + status
                shareDot.color = !up ? NSColor(rgb: (0.45, 0.46, 0.5)) : n > 0 ? NSColor(rgb: (0.35, 0.85, 0.5)) : NSColor(rgb: (0.9, 0.7, 0.3))
                shareLabel.position = CGPoint(x: hud.size.width - 14, y: hud.size.height - 14)
                shareDot.position = CGPoint(x: hud.size.width - 14 - shareLabel.frame.width - 10, y: hud.size.height - 19)
                shareDot.alpha = n > 0 && up ? 0.7 + 0.3 * sin(clock * 2) : 0.8
            }
        }

        var y = hud.size.height - 70
        eventLabels.removeAll { l, t in
            let age = clock - t
            if age > 14 { l.removeFromParent(); return true }
            l.alpha = age < 11 ? 1 : (14 - age) / 3
            l.position = CGPoint(x: 12, y: y)
            y -= 15
            return false
        }

        defer {
            let hasText = !(infoLabel.text ?? "").isEmpty
            infoBackground.isHidden = !hasText
            if hasText {
                let f = infoLabel.frame.insetBy(dx: -8, dy: -5)
                infoBackground.position = f.origin
                infoBackground.size = f.size
            }
        }
        guard let hRaw = hovered else { infoLabel.text = ""; return }
        let h = hRaw.hasPrefix("box:") ? "room:" + hRaw.dropFirst(4) : hRaw
        if h.hasPrefix("room:") {
            let parts = h.dropFirst(5).split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2, let station = fleet.stations[parts[0]], let r = station.rooms[parts[1]] {
                infoLabel.text = roomInfo(station: station, room: r)
            }
        } else if h.hasPrefix("minion:") {
            if let m = minions[String(h.dropFirst(7))] {
                var parts: [String] = []
                if let t = m.title { parts.append(t) }
                parts.append(m.activity.label)
                parts.append(m.home.name)
                if let b = m.branch { parts.append("⎇ " + b) }
                parts.append(URL(fileURLWithPath: m.cwd).lastPathComponent)
                parts.append("\(m.toolCount) tool calls")
                if m.isSubagent { parts.append("subagent") }
                infoLabel.text = parts.joined(separator: "   ")
            }
        } else if h.hasPrefix("rocket:") {
            infoLabel.text = String(h.dropFirst(7).split(separator: "|", maxSplits: 1).last ?? "")
        } else if (h.hasPrefix("storage:") || h.hasPrefix("deck:")), h.split(separator: "|").count == 3, let n = Int(h.split(separator: "|")[2]), n > 0 {
            let parts = h.split(separator: "|")
            infoLabel.text = "\(parts[1]) · PR #\(n) · \(h.hasPrefix("deck:") ? "on staging, waiting for production" : "merged, waiting for staging") · click to open"
        } else if h.hasPrefix("storage:") {
            let name = String(h.dropFirst(8).split(separator: "|").first ?? "")
            let parts = (fleet.stations[name]?.stored ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
            infoLabel.text = "storage · " + (parts.isEmpty ? "empty" : parts.joined(separator: " · ")) + " · waiting for a release"
        } else if h.hasPrefix("peer:") {
            infoLabel.text = "\(h.dropFirst(5))'s station · shared on the local network"
        } else if h.hasPrefix("deck:") {
            let qa = minions.values.filter { $0.activity == .qa && $0.state != .leaving }.map { $0.home.name }
            if !qa.isEmpty { infoLabel.text = "test deck · QA in progress: " + qa.joined(separator: ", "); return }
            let name = String(h.dropFirst(5).split(separator: "|").first ?? "")
            let parts = (fleet.stations[name]?.staged ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
            infoLabel.text = "test deck · " + (parts.isEmpty ? "nothing on staging" : parts.joined(separator: " · ") + " on staging, in QA")
        } else if h.hasPrefix("pad:") {
            let name = String(h.dropFirst(4))
            let due = (ConfigStore.shared.current.stagingBranch.isEmpty ? fleet.stations[name]?.stored : fleet.stations[name]?.staged)?.filter { $0.value > 0 }.map { "\($0.value) \($0.key)" }.sorted() ?? []
            infoLabel.text = "launch pad · release pull requests wait here; merging launches" + (due.isEmpty ? "" : " · cargo waiting: " + due.joined(separator: ", "))
        } else if h.hasPrefix("hangar:") {
            infoLabel.text = "hangar · new offices arrive here by ship"
        } else if h.hasPrefix("station:") {
            infoLabel.text = String(h.dropFirst(8)) + " · the monolith: web research and subagents"
        } else {
            infoLabel.text = ""
        }
    }

    /// A crate in storage or on the deck opens its pull request.
    private func openCargo(named name: String) {
        let parts = name.split(separator: "|").map(String.init)
        guard parts.count == 3, let n = Int(parts[2]), n > 0 else { return }
        let repo = parts[1]
        if let item = github.projectItems()?.first(where: { $0.repo == repo && $0.number == n }), let url = URL(string: item.url) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            return
        }
        guard let root = repoRoots.first(where: { $0.value.repo == repo })?.key, let owner = github.nameWithOwner(repoRoot: root),
              let url = URL(string: "https://github.com/\(owner)/pull/\(n)") else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }

    private func open(named raw: String?) {
        if let raw, raw.hasPrefix("rocket:"), let u = URL(string: String(raw.dropFirst(7).split(separator: "|", maxSplits: 1).first ?? "")) {
            DispatchQueue.main.async { NSWorkspace.shared.open(u) }
            return
        }
        guard let raw, raw.hasPrefix("room:") || raw.hasPrefix("box:") else { return }
        let name = raw.hasPrefix("box:") ? "room:" + raw.dropFirst(4) : raw
        let parts = name.dropFirst(5).split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]] else { return }
        if let info = crewRoomInfo[roomKey(station, room)], let u = info.url.flatMap(URL.init(string:)) {
            DispatchQueue.main.async { NSWorkspace.shared.open(u) }
            return
        }
        guard let branch = room.branch, let root = room.repoRoot else { return }
        if localState(room).local { logEvent("\(room.name): not on github yet"); return }
        var url: URL?
        if let pr = github.pull(branch: branch, repoRoot: root), let u = URL(string: pr.url) {
            url = u
        } else if let owner = github.nameWithOwner(repoRoot: root) {
            if let m = branch.firstMatch(of: #/^gh-(\d+)\//#) {
                url = URL(string: "https://github.com/\(owner)/issues/\(m.1)")
            } else {
                url = URL(string: "https://github.com/\(owner)/tree/\(branch)")
            }
        }
        if let url { DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
    }

    // MARK: minions and props

    private func spawnMinion(_ s: SessionInfo, station: String, home: Home) -> Minion {
        let st = fleet.stations[station]
        let start = s.isSubagent ? (st?.coreCenter ?? Cell(x: 0, y: 0)) : (st?.hangarCells.first ?? st?.cells(of: .quarters).randomElement() ?? Cell(x: 0, y: 0))
        let m = Minion(id: s.id, station: station, home: home, cwd: s.cwd, toolCount: s.toolCount, isSubagent: s.isSubagent, start: start)
        m.markers = s.eventMarkers
        m.promptCount = s.promptCount
        minionRoot.addChildNode(m.node)
        minions[s.id] = m
        return m
    }

    private func despawn(_ m: Minion) {
        if let key = carriedRoom(of: m) { reveal(key) }
        m.carried?.removeFromParentNode()
        m.pyramids.forEach { $0.removeFromParentNode() }
        m.queuedCones.forEach { $0.removeFromParentNode() }
        m.weldLight?.removeFromParentNode()
        m.node.removeFromParentNode()
        minions[m.id] = nil
    }

    private func carriedRoom(of m: Minion) -> String? {
        switch m.errand {
        case .fetch(let r), .carry(let r): return "\(m.station)|\(r)"
        default: return nil
        }
    }

    private func send(_ m: Minion, to place: Place) {
        guard let station = fleet.stations[m.station] else { return }
        if place != .quarters { m.bed = nil }
        var place = place
        if place == .quarters, m.bed == nil {
            let used = Set(minions.values.filter { $0.station == m.station && $0.id != m.id }.compactMap(\.bed))
            m.bed = station.beds.indices.first { !used.contains($0) }
            if m.bed == nil { place = .lounge }   // every bed taken: the lounge
        }
        if place != .lounge { m.couch = nil }
        if place == .lounge, m.couch == nil {
            let used = Set(minions.values.filter { $0.station == m.station && $0.id != m.id }.compactMap(\.couch))
            m.couch = station.couches.indices.first { !used.contains($0) }
        }
        let cells = station.cells(of: place)
        let target: Cell
        if let b = m.bed, b < station.beds.count { target = station.beds[b].cell }
        else if place == .lounge, let c = m.couch, c < station.couches.count, let lounge = station.rooms["kind:lounge"] {
            let spot = station.couches[c]
            target = lounge.cells.min { a, b in hypot(Double(a.x) - spot.x, Double(a.y) - spot.y) < hypot(Double(b.x) - spot.x, Double(b.y) - spot.y) } ?? lounge.cells[0]
        }
        else if let t = cells.randomElement() { target = t }
        else { return }
        m.place = place
        m.path = station.path(from: m.pos, to: target)
        m.nextWanderAt = clock + Double.random(in: 1...3)
    }

    private func walk(_ m: Minion, to cell: Cell) {
        guard let station = fleet.stations[m.station] else { return }
        m.path = station.path(from: m.pos, to: cell)
    }

    /// A new worker arrives by shuttle: it stays invisible until the ship has set down, then steps out.
    private func arriveByShuttle(_ m: Minion) {
        guard let station = fleet.stations[m.station], station.hasHangar, let anchor = hangarAnchors[m.station] else { return }
        let slotIndex = (shipsInFlight[m.station] ?? 0) % station.hangarSlots.count
        shipsInFlight[m.station, default: 0] += 1
        let slot = station.hangarSlots[slotIndex]
        m.pos = slot
        m.opacity = 0
        m.node.opacity = 0
        m.wakeUntil = clock + 8.5   // held until the ship lands
        let ship = shuttle(color: NSColor(fleet.color(forRepo: m.home.repo)))
        let local = SIMD3(slot.x - station.hangarCenter.x, 0, slot.y - station.hangarCenter.y)
        let corners: [SIMD3<Double>] = [SIMD3(12, 9, 12), SIMD3(-12, 9, 12), SIMD3(12, 9, -12), SIMD3(-12, 9, -12)]
        let start = local + corners.randomElement()!, high = local + SIMD3(0, 5, 0), down = local + SIMD3(0, 0.55, 0), exit = local + corners.randomElement()!
        ship.position = v3(start.x, start.y, start.z)
        anchor.addChildNode(ship)
        let approach = SCNAction.move(to: v3(high.x, high.y, high.z), duration: 3.0); approach.timingMode = .easeOut
        let descend = SCNAction.move(to: v3(down.x, down.y, down.z), duration: 4.5); descend.timingMode = .easeInEaseOut
        let rise = SCNAction.move(to: v3(high.x, high.y, high.z), duration: 2.5); rise.timingMode = .easeIn
        let leave = SCNAction.move(to: v3(exit.x, exit.y, exit.z), duration: 3.0); leave.timingMode = .easeIn
        ship.runAction(.sequence([approach, descend, .wait(duration: 0.6), .run { [weak self] _ in self?.enqueue { m.opacity = 1; m.wakeUntil = 0 } }, .wait(duration: 1.0), rise, leave,
                                  .run { [weak self] _ in self?.enqueue { self?.shipsInFlight[m.station, default: 1] -= 1 } }, .removeFromParentNode()]))
        logEvent("shuttle inbound: a new worker for \(m.home.name)")
        drone.sweep(up: false)
    }

    /// The shuttle body, wings in a repo colour.
    private func shuttle(color: NSColor) -> SCNNode {
        let ship = SCNNode()
        let hull = SCNNode(geometry: SCNBox(width: 0.7, height: 0.14, length: 0.4, chamferRadius: 0.03))
        hull.geometry!.firstMaterial = lit(NSColor(rgb: (0.85, 0.86, 0.9)))
        ship.addChildNode(hull)
        let cockpit = SCNNode(geometry: SCNBox(width: 0.2, height: 0.1, length: 0.2, chamferRadius: 0.02))
        cockpit.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.75, 1.0)))
        cockpit.position = v3(0.16, 0.11, 0)
        ship.addChildNode(cockpit)
        for side in [-1.0, 1.0] {
            let wing = SCNNode(geometry: SCNBox(width: 0.28, height: 0.05, length: 0.34, chamferRadius: 0))
            wing.geometry!.firstMaterial = lit(color)
            wing.position = v3(-0.14, 0, side * 0.34)
            ship.addChildNode(wing)
        }
        for side in [-1.0, 1.0] {
            let skid = SCNNode(geometry: SCNBox(width: 0.5, height: 0.03, length: 0.03, chamferRadius: 0))
            skid.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.3, 0.35)))
            skid.position = v3(0, -0.14, side * 0.16)
            ship.addChildNode(skid)
        }
        return ship
    }

    /// A shuttle descends slowly onto a free hangar slot, sets down a crate, and lifts away.
    /// Everything is parented to the hangar anchor, so a station shifting underneath does not misalign it.
    private func startDelivery(_ m: Minion, roomKey: String) {
        guard let station = fleet.stations[m.station], station.hasHangar, let room = station.rooms[roomKey],
              let anchor = hangarAnchors[m.station] else { return }
        let key = "\(station.name)|\(roomKey)"
        let slotIndex = (shipsInFlight[m.station] ?? 0) % station.hangarSlots.count
        shipsInFlight[m.station, default: 0] += 1
        let slotLocal = station.hangarSlots[slotIndex] - station.hangarCenter
        let slot = SIMD3(slotLocal.x, 0, slotLocal.y)

        let box = Props.crate(color: NSColor(room.color))
        box.position = v3(slot.x, 0.09, slot.z)
        box.opacity = 0
        box.name = "room:" + key
        anchor.addChildNode(box)
        boxes[key] = box

        let ship = SCNNode()
        let hull = SCNNode(geometry: SCNBox(width: 0.7, height: 0.14, length: 0.4, chamferRadius: 0.03))
        hull.geometry!.firstMaterial = lit(NSColor(rgb: (0.85, 0.86, 0.9)))
        ship.addChildNode(hull)
        let cockpit = SCNNode(geometry: SCNBox(width: 0.2, height: 0.1, length: 0.2, chamferRadius: 0.02))
        cockpit.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.75, 1.0)))
        cockpit.position = v3(0.16, 0.11, 0)
        ship.addChildNode(cockpit)
        for side in [-1.0, 1.0] {
            let wing = SCNNode(geometry: SCNBox(width: 0.28, height: 0.05, length: 0.34, chamferRadius: 0))
            wing.geometry!.firstMaterial = lit(NSColor(room.color))
            wing.position = v3(-0.14, 0, side * 0.34)
            ship.addChildNode(wing)
        }
        for side in [-1.0, 1.0] {
            let skid = SCNNode(geometry: SCNBox(width: 0.5, height: 0.03, length: 0.03, chamferRadius: 0))
            skid.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.3, 0.35)))
            skid.position = v3(0, -0.14, side * 0.16)
            ship.addChildNode(skid)
        }
        let corners: [SIMD3<Double>] = [SIMD3(12, 9, 12), SIMD3(-12, 9, 12), SIMD3(12, 9, -12), SIMD3(-12, 9, -12)]
        let start = slot + corners.randomElement()!
        let high = slot + SIMD3(0, 5.0, 0)
        let down = slot + SIMD3(0, 0.55, 0)
        let exit = slot + corners.randomElement()! * SIMD3(1, 0.9, 1) + SIMD3(0, 0, 0)
        let restYaw = Double.random(in: 0..<(2 * .pi))
        let drift = Double.random(in: -0.6...0.6)
        ship.position = v3(start.x, start.y, start.z)
        ship.look(at: v3(high.x, high.y, high.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(1, 0, 0))
        anchor.addChildNode(ship)
        let approach = SCNAction.move(to: v3(high.x, high.y, high.z), duration: 3.0); approach.timingMode = .easeOut
        let descend = SCNAction.move(to: v3(down.x, down.y, down.z), duration: 4.5); descend.timingMode = .easeInEaseOut
        let settleYaw = SCNAction.rotateTo(x: 0, y: restYaw + drift, z: 0, duration: 4.5, usesShortestUnitArc: true); settleYaw.timingMode = .easeInEaseOut
        let rise = SCNAction.move(to: v3(high.x, high.y, high.z), duration: 2.5); rise.timingMode = .easeIn
        let leave = SCNAction.move(to: v3(exit.x, exit.y, exit.z), duration: 3.0); leave.timingMode = .easeIn
        ship.runAction(.sequence([
            approach,
            .run { n in n.eulerAngles = SCNVector3(0, restYaw, 0) },
            .group([descend, settleYaw]),
            .wait(duration: 0.8),
            .run { _ in
                box.opacity = 1
                box.position = v3(slot.x, 0.42, slot.z)
                let drop = SCNAction.move(to: v3(slot.x, 0.09, slot.z), duration: 0.5); drop.timingMode = .easeIn
                box.runAction(drop)
            },
            .wait(duration: 1.2),
            rise,
            .run { n in n.look(at: v3(exit.x, exit.y, exit.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(1, 0, 0)) },
            leave,
            .run { [weak self] _ in self?.enqueue { self?.shipsInFlight[m.station, default: 1] -= 1 } },
            .removeFromParentNode(),
        ]))
        logEvent("shuttle inbound: \(room.name)")
        drone.sweep(up: false)
        m.errand = .fetch(room: roomKey)
        m.place = .hangar
        m.fetchSpot = station.hangarSlots[slotIndex] + SIMD2(-0.3, 0)
        walk(m, to: station.hangarCells[min(station.hangarCells.count - 1, slotIndex * 2)])
    }

    /// Archiving: boxes shrink away, whoever is inside steps out into the hallway, and the room
    /// detaches, sinks and fades. The model drops the room at once; only the visuals linger.
    private func archive(station: Station, room: Room, announce: Bool, reason: String = "") {
        let key = roomKey(station, room)
        cancelHauls(roomKey: key)
        for m in minions.values where m.station == station.name && m.home.key == room.key { clearPyramids(m) }
        stationAnchors[station.name]?.childNodes.filter { $0.name == "room:" + key }.forEach { $0.removeFromParentNode() }
        haulingRooms.remove(key)
        undelivered.remove(key)
        outlines.removeValue(forKey: key)?.removeFromParentNode()
        boxes.removeValue(forKey: key)?.removeFromParentNode()
        if announce {
            let ghost = SCNNode()
            for t in roomTiles[key] ?? [] { t.removeFromParentNode(); ghost.addChildNode(t) }
            if let l = roomLabels[key] { l.removeFromParentNode(); ghost.addChildNode(l); roomLabels[key] = nil }
            for b in markerRoot.childNodes where b.name == "box:" + key {
                b.runAction(.sequence([.scale(to: 0.01, duration: 0.5), .removeFromParentNode()]))
            }
            propRoot.addChildNode(ghost)
            let sink = SCNAction.moveBy(x: 0, y: -4, z: 0, duration: 2.2)
            sink.timingMode = .easeIn
            ghost.runAction(.sequence([.wait(duration: 0.6), .group([sink, .sequence([.wait(duration: 0.8), .fadeOut(duration: 1.4)])]), .removeFromParentNode()]))
            if let hall = station.doorOutside(of: room.key) {
                for m in minions.values where m.station == station.name && m.place == .room(room.key) {
                    m.path = station.path(from: m.pos, to: hall)
                    m.place = .core   // parked in the hallway until the next scan sends it on
                    m.nextWanderAt = clock + 4
                }
            }
            logEvent("archived: \(room.name)" + (reason.isEmpty ? "" : " · \(reason)"))
        }
        roomTiles[key] = nil
        station.removeRoom(key: room.key)
    }

    private func reveal(_ key: String) {
        boxes.removeValue(forKey: key)?.removeFromParentNode()
        if let o = outlines.removeValue(forKey: key) { o.runAction(.sequence([.fadeOut(duration: 0.4), .removeFromParentNode()])) }
        guard undelivered.remove(key) != nil else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.6
        roomTiles[key]?.forEach { $0.opacity = 1 }
        roomLabels[key]?.opacity = 1
        markerRoot.childNodes.filter { $0.name == "box:" + key }.forEach { $0.opacity = 1 }
        SCNTransaction.commit()
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]] {
            logEvent("new office: \(room.name)")
        }
    }

    private func addPyramid(for m: Minion, queued: Bool = false) {
        guard let station = fleet.stations[m.station], case .room(let key) = Place.forActivity(.reading, home: m.home.key, isSubagent: false),
              !key.hasPrefix("kind:") else { return }   // prompts only land in an office
        // Cones land on clear floor, nearest the door: the crates hold the far corners.
        let cells = station.cells(of: .room(key))
        let written = labelCells["\(m.station)|\(key)"] ?? []
        let clear = cells.filter { c in !station.obstacles.contains(Cell(x: c.x * Station.fine, y: c.y * Station.fine)) && !written.contains(c) }
        let door = station.doorCell(of: key) ?? cells.first!
        let nearDoor = (clear.isEmpty ? cells : clear).sorted { (abs($0.x - door.x) + abs($0.y - door.y)) < (abs($1.x - door.x) + abs($1.y - door.y)) }
        guard let cell = nearDoor.prefix(2).randomElement() else { return }
        let tint = station.rooms[key].map { NSColor($0.color).lighter(0.22) } ?? Palette.pyramid
        if !queued, m.pyramids.count >= 5, let old = m.pyramids.first {
            old.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]))
            m.pyramids.removeFirst()
        }
        let floorColor = station.rooms[key].map { NSColor($0.color) } ?? Palette.corridor
        let n = Props.pyramid(color: tint, size: 0.32, floor: floorColor)
        let ox = Double.random(in: -0.25...0.25), oz = Double.random(in: -0.25...0.25)
        n.position = v3(Double(cell.x) + ox, -0.35, Double(cell.y) + oz)
        let rise = SCNAction.move(to: v3(Double(cell.x) + ox, 0, Double(cell.y) + oz), duration: 0.5)
        rise.timingMode = .easeOut
        n.runAction(rise)
        n.name = "room:\(station.name)|\(key)"
        let anchor = stationAnchors[station.name] ?? { let a = SCNNode(); a.position = v3(station.offset.x, 0, station.offset.y); propRoot.addChildNode(a); stationAnchors[station.name] = a; return a }()
        anchor.addChildNode(n)
        if queued {
            n.opacity = 0.35
            m.queuedCones.append(n)
            return
        }
        m.pyramids.append(n)
        m.pyramidCell = cell
        refreshObstacles()
        if m.errand == nil { m.place = .room(key); walk(m, to: cell) }
    }

    private func clearPyramids(_ m: Minion) {
        for p in m.pyramids { p.runAction(.sequence([.fadeOut(duration: 0.8), .removeFromParentNode()])) }
        m.pyramids = []
        m.pyramidCell = nil
        refreshObstacles()
    }

    private func ringBell(seed: Int) {
        guard clock - lastPing > 0.25 else { return }
        lastPing = clock
        drone.ping(seed: seed)
    }

    // MARK: scanning

    private var scanQueued = false
    private func rescan() {
        pendingLock.lock()
        if scanQueued { pendingLock.unlock(); return }
        scanQueued = true
        pendingLock.unlock()
        scanQueue.async { [scanner] in
            self.pendingLock.lock(); self.scanQueued = false; self.pendingLock.unlock()
            let result = scanner.scan(roomsWithin: StationController.scanWindow)
            self.enqueue { self.apply(result) }
        }
    }

    private func apply(_ result: ScanResult) {
        let now = Date()
        var changed = false
        let firstRun = !didLoadLayout
        if firstRun {
            didLoadLayout = true
            fleet.load()
            changed = true
        }

        // Every session touched today keeps its office alive; archived worktrees lose theirs.
        var newRooms: [String: String] = [:]   // session id -> room key
        let cfg = ConfigStore.shared.current
        for s in result.sessions where s.cwdExists && Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) != "hidden"
            && (Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) == "work" || now.timeIntervalSince(s.lastModified) < StationController.roomsWindow) {
            let stationName = Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo)
            let station = fleet.station(stationName)
            let home = Home.from(repo: s.repo, branch: s.branch, cwd: s.cwd)
            if let m = minions[s.id], m.home.key != home.key, station.rooms[home.key] == nil, station.rooms[m.home.key] != nil,
               !minions.values.contains(where: { $0.id != s.id && $0.home.key == m.home.key && $0.station == stationName }) {
                let oldKey = "\(stationName)|\(m.home.key)", newKey = "\(stationName)|\(home.key)"
                let promoted = m.home.key.hasPrefix("proj:") && home.key.hasPrefix("task:")
                station.renameRoom(from: m.home.key, to: home.key, name: home.name)
                if promoted, !firstRun, m.errand == nil {
                    undelivered.insert(newKey)
                    newRooms[s.id] = home.key
                    logEvent("\(home.name): branch created, office ordered")
                }
                if undelivered.remove(oldKey) != nil { undelivered.insert(newKey) }
                if let o = outlines.removeValue(forKey: oldKey) { outlines[newKey] = o }
                if let b = boxes.removeValue(forKey: oldKey) { boxes[newKey] = b }
                switch m.errand {
                case .fetch: m.errand = .fetch(room: home.key)
                case .carry: m.errand = .carry(room: home.key)
                default: break
                }
                if m.place == .room(m.home.key) { m.place = .room(home.key) }
                changed = true
            }
            if let r = station.rooms[home.key], r.worktree == nil, r.name != home.name { r.name = home.name; changed = true }
            if station.ensureRoom(key: home.key, name: home.name, repo: home.repo, color: fleet.color(forRepo: home.repo), lastActive: s.lastModified) {
                changed = true
                roomCreated["\(stationName)|\(home.key)"] = now
                if !firstRun {
                    undelivered.insert("\(stationName)|\(home.key)")
                    newRooms[s.id] = home.key
                }
            }
            if let root = s.repoRoot, !repoRoots.values.contains(where: { $0.repo == s.repo }) {
                repoRoots[root] = (s.repo, stationName)
            }
            if let room = station.rooms[home.key] {
                room.worktree = s.cwd
                if home.key.hasPrefix("task:") { room.branch = s.branch; room.repoRoot = s.repoRoot }
                if let b = room.branch, let r = room.repoRoot { github.refresh(branch: b, repoRoot: r) }
                if let w = room.worktree { github.refreshCommits(worktree: w) }
            }
        }
        for station in fleet.stations.values {
            for room in Array(station.rooms.values) where !room.key.hasPrefix("kind:") {
                let gone = room.worktree.map { !FileManager.default.fileExists(atPath: $0) } ?? false
                let merged = room.branch.flatMap { b in room.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }.map { $0.state == "MERGED" || $0.state == "CLOSED" } ?? false
                if merged, station.hasPad, hauledAt[roomKey(station, room)] == nil { haulMergedBoxes(station: station, room: room) }
                let cleared = merged && (!station.hasPad || (hauledAt[roomKey(station, room)].map { now.timeIntervalSince($0) > 60 } ?? false && !hauls.contains { $0.roomKey == roomKey(station, room) }))
                // Nobody's: no checkout here, no peer claiming it, nothing on GitHub once GitHub has answered.
                // An office a peer left behind is held for a day so their return does not move it.
                let key = roomKey(station, room)
                let unclaimed = room.worktree == nil && crewRoomInfo[key] == nil && peerOffices[key] == nil && crewLoaded
                    && (cfg.project == nil || github.projectItems() != nil)
                let orphan = unclaimed && (held[key].map { now.timeIntervalSince($0) > StationController.holdWindow } ?? true)
                if gone || cleared || orphan {
                    archive(station: station, room: room, announce: !firstRun, reason: gone ? "worktree gone" : cleared ? "merged and hauled" : "nobody's")
                    changed = true
                }
            }
        }

        // Every Conductor repo with a checkout under ~/dev counts as a work repo for releases,
        // even with no session today, so a release on the pad never depends on someone working.
        if firstRun {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let workspaces = home.appendingPathComponent("conductor/workspaces")
            if let repos = try? FileManager.default.contentsOfDirectory(atPath: workspaces.path) {
                for repo in repos {
                    let root = home.appendingPathComponent("dev/\(repo)").path
                    if FileManager.default.fileExists(atPath: root + "/.git"), !repoRoots.values.contains(where: { $0.repo == repo }) {
                        repoRoots[root] = (repo, "work")
                        _ = fleet.color(forRepo: repo)
                    }
                }
            }
        }
        github.intervalMinutes = cfg.githubMinutes
        if let p = cfg.project { github.refreshProject(owner: p.owner, number: p.number) }
        for (root, info) in repoRoots {
            github.refreshReleases(repoRoot: root)
            if info.station == "work" { github.refreshFeed(repoRoot: root); github.refreshOpenPRs(repoRoot: root) }
        }
        handleProjectMoves()
        for change in github.takeStateChanges() {
            let who = change.branch.firstMatch(of: #/^gh-(\d+)\//#).map { "#\($0.1)" } ?? change.branch
            logEvent("\(who): \(change.pr.summary)")
            ringBell(seed: change.pr.number)
        }
        for station in fleet.stations.values where station.hasPad {
            for room in station.rooms.values where room.branch != nil {
                if let pr = room.repoRoot.flatMap({ github.pull(branch: room.branch!, repoRoot: $0) }), pr.state == "MERGED" { haulMergedBoxes(station: station, room: room) }
            }
        }
        var seen = Set<String>()
        let liveSessions = result.sessions.filter { s in
            Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) != "hidden"
                && now.timeIntervalSince(s.lastModified) < (s.isSubagent ? StationController.subagentWindow : StationController.activeWindow)
        }
        let liveIds = Set(liveSessions.map(\.id))
        // Workers whose session ended are free for reuse; they rest until someone needs them.
        for m in minions.values where !m.isCrew && !m.isSubagent && !liveIds.contains(m.id) && m.freeSince == 0 { m.freeSince = clock; m.busy = false; m.activity = .sleeping; clearPyramids(m) }
        for s in liveSessions {
            seen.insert(s.id)
            let stationName = Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo)
            let home = Home.from(repo: s.repo, branch: s.branch, cwd: s.cwd)
            var isNew = minions[s.id] == nil
            var reused = false
            if isNew && !s.isSubagent {
                // A free worker on this station takes the new session before the shuttle brings another.
                if let free = minions.values.filter({ $0.station == stationName && !$0.isCrew && !$0.isSubagent && $0.freeSince > 0 && $0.errand == nil })
                    .min(by: { $0.freeSince < $1.freeSince }) {
                    minions[free.id] = nil
                    free.id = s.id
                    free.node.name = "minion:" + s.id
                    free.node.enumerateChildNodes { c, _ in c.name = "minion:" + s.id }
                    free.freeSince = 0
                    free.isTester = false
                    free.markers = s.eventMarkers
                    free.promptCount = s.promptCount
                    free.toolCount = s.toolCount
                    free.cwd = s.cwd
                    free.state = .arriving
                    minions[s.id] = free
                    isNew = false
                    reused = true
                }
            }
            let m = minions[s.id] ?? spawnMinion(s, station: stationName, home: home)
            m.freeSince = 0
            if isNew && !s.isSubagent && newRooms[s.id] == nil && !firstRun { arriveByShuttle(m) }
            _ = reused
            if m.station != stationName { despawn(m); continue }
            m.home = home
            let idle = now.timeIntervalSince(s.lastModified)
            m.busy = idle < StationController.busyWindow
            if idle > Double(cfg.sleepMinutes) * 60 || !s.cwdExists {
                m.activity = .sleeping
            } else if idle > StationController.replyWindow, s.activity == .writing || s.activity == .waiting {
                m.activity = .waiting
            } else if !m.busy {
                m.activity = .waiting
            } else {
                m.activity = s.activity
            }
            if m.activity == .waiting, m.waitingSince == 0 { m.waitingSince = clock }
            if m.activity != .waiting { m.waitingSince = 0 }
            m.title = s.title
            m.branch = s.branch
            m.cwd = s.cwd
            let who = home.issue.map { "#\($0)" } ?? URL(fileURLWithPath: s.cwd).lastPathComponent
            if !isNew {
                for (event, marker) in s.eventMarkers where m.markers[event] != marker {
                    switch event {
                    case .prOpened: logEvent("\(who) opened a pull request")
                    case .merged: logEvent("\(who) merged")
                    case .pushed: logEvent("\(who) pushed")
                    case .committed: logEvent("\(who) committed")
                    case .skill: if case .skill(let name) = s.activity { logEvent("\(who) used /\(name)") }
                    case .prompt:
                        if !m.isSubagent {
                            // One cone per message that arrived since last time; a queued cone lights up when picked up.
                            let newPrompts = max(1, s.promptCount - m.promptCount)
                            for _ in 0..<min(newPrompts, 5) {
                                if let q = m.queuedCones.first { q.removeFromParentNode(); m.queuedCones.removeFirst() }
                                addPyramid(for: m)
                            }
                        }
                    case .tool: continue
                    }
                    ringBell(seed: s.id.hashValue &+ event.rawValue.hashValue)
                }
            }
            m.markers = s.eventMarkers
            m.toolCount = s.toolCount
            m.promptCount = s.promptCount
            if !m.isSubagent {
                // Bounded: the cone can fail to place (no room yet), which must never spin the render thread.
                let want = min(5, s.queuedCount)
                var attempts = 0
                while m.queuedCones.count < want && attempts < 5 {
                    let before = m.queuedCones.count
                    addPyramid(for: m, queued: true)
                    attempts += 1
                    if m.queuedCones.count == before { break }
                }
                while m.queuedCones.count > s.queuedCount, let q = m.queuedCones.popLast() { q.removeFromParentNode() }
            }
            if m.activity == .waiting || m.activity == .sleeping { clearPyramids(m) }

            if let key = newRooms[s.id], m.errand == nil, !m.isSubagent, fleet.stations[stationName]?.hasHangar == true {
                startDelivery(m, roomKey: key)
            } else if m.errand == nil {
                let place = Place.forActivity(m.activity, home: home.key, isSubagent: m.isSubagent)
                if place != m.place || isNew { send(m, to: place) }
            }
            if m.state == .leaving { m.state = .arriving; send(m, to: m.place) }
        }
        for m in minions.values where !seen.contains(m.id) && m.state != .leaving && m.isSubagent {
            m.state = .leaving; m.path = []
        }
        for station in fleet.stations.values {
            // A standing crew of two, always present, so the station is never empty.
            let workers = minions.values.filter { $0.station == station.name && !$0.isSubagent && !$0.isCrew && $0.state != .leaving }
            if workers.count < 2, !station.rooms.isEmpty {
                for k in workers.count..<2 {
                    let home = Home(key: "kind:lounge", name: "standby", repo: station.rooms.values.first { $0.repo != nil }?.repo ?? "crew", issue: nil)
                    let start = station.cells(of: .lounge).randomElement() ?? station.coreCenter
                    let m = Minion(id: "standby:\(station.name):\(k):\(Int(clock))", station: station.name, home: home, cwd: "", toolCount: 0, isSubagent: false, start: start)
                    m.freeSince = clock - 1
                    m.activity = .waiting
                    minionRoot.addChildNode(m.node)
                    minions[m.id] = m
                    send(m, to: .lounge)
                }
            }
            let busyRecently = minions.values.contains { $0.station == station.name && $0.busy && !$0.isCrew } || (lastBusy[station.name].map { clock - $0 < 3600 } ?? false)
            if minions.values.contains(where: { $0.station == station.name && $0.busy && !$0.isCrew }) { lastBusy[station.name] = clock }
            let hour = Calendar.current.component(.hour, from: now)
            let night = !busyRecently || hour >= 22 || hour < 7
            let free = minions.values.filter { $0.station == station.name && $0.freeSince > 0 && $0.state != .leaving && !$0.isSubagent }
                .sorted { $0.freeSince < $1.freeSince }
            for (i, m) in free.enumerated() where !m.isTester {
                let longIdle = clock - m.freeSince > 20 * 60 && i >= 2          // keep a couple on standby, let the rest go
                let restPlace: Place = night ? .quarters : .lounge
                if longIdle || (i >= station.beds.count + station.couches.count) {
                    m.state = .leaving
                    if let key = carriedRoom(of: m) { reveal(key); m.errand = nil; m.carried?.removeFromParentNode(); m.carried = nil }
                } else if m.errand == nil && m.place != restPlace && !(m.place == .lounge && restPlace == .quarters && m.bed == nil && night == false) {
                    m.activity = night ? .sleeping : .waiting
                    send(m, to: restPlace)
                }
            }
            assignTester(station: station, free: free)
        }
        // Offices that appeared without a minion to deliver them just show up.
        let pending = Set(minions.values.compactMap { m in carriedRoom(of: m) ?? newRooms[m.id].map { "\(m.station)|\($0)" } })
        for key in undelivered where !pending.contains(key) {
            changed = true
            undelivered.remove(key)
            outlines.removeValue(forKey: key)?.removeFromParentNode()
            boxes.removeValue(forKey: key)?.removeFromParentNode()
        }
        if changed {
            rebuildStatic()
            if firstRun, !viewPinned { restoreView() }
            for m in minions.values where m.errand == nil { send(m, to: m.place) }
            for m in minions.values {
                if case .fetch = m.errand, let station = fleet.stations[m.station], let c = station.hangarCells.randomElement() {
                    walk(m, to: c)
                } else if case .carry(let r) = m.errand, let station = fleet.stations[m.station], let door = station.doorCell(of: r) {
                    walk(m, to: door)
                }
            }
        }
    }

    // MARK: peers

    func applySharing() {
        let cfg = ConfigStore.shared.current
        if cfg.shareOnLAN {
            if !peers.isRunning { github.holdUntil = Date().addingTimeInterval(Double.random(in: 3...12)) }
            peers.start(name: cfg.shareName.isEmpty ? NSUserName() : cfg.shareName)
        } else { peers.stop() }
    }

    /// Our own claim for the others: offices we have checked out ourselves in repositories ticked
    /// for sharing. Nothing learned from GitHub or from another peer goes back out.
    private func makeSnapshot(withGitHub: Bool) -> PeerSnapshot? {
        let cfg = ConfigStore.shared.current
        guard let station = fleet.stations["work"] else { return nil }
        var offices: [PeerSnapshot.Office] = []
        for r in station.rooms.values where r.worktree != nil && !r.key.hasPrefix("kind:") && (r.repo.map { cfg.shared(repo: $0) } ?? false) {
            let key = roomKey(station, r)
            offices.append(PeerSnapshot.Office(key: r.key, name: r.name, repo: r.repo ?? "", branch: r.branch, color: r.color, cells: r.cells,
                                               pushed: r.branch != nil && !localState(r).local,
                                               startedAt: roomCreated[key] ?? .distantPast, lastActive: r.lastActive,
                                               boxes: lastBoxCount[key] ?? 0, dim: r.key.hasPrefix("proj:") || !(roomPower[key] ?? true)))
        }
        let ms = minions.values.filter { $0.station == station.name && !$0.isCrew && $0.state != .leaving && cfg.shared(repo: $0.home.repo) && station.rooms[$0.home.key]?.worktree != nil }.map {
            PeerSnapshot.Minion(id: $0.id.hashValue.description, office: $0.home.key, asleep: $0.activity == .sleeping, busy: $0.busy)
        }
        var knowledge: [GitHubResolver.Knowledge]?
        var board: GitHubResolver.ProjectKnowledge?
        if withGitHub {
            knowledge = repoRoots.filter { $0.value.station == "work" && cfg.shared(repo: $0.value.repo) }.compactMap { github.knowledge(repoRoot: $0.key, repo: $0.value.repo) }
            if let p = cfg.project { board = github.projectKnowledge(owner: p.owner, number: p.number) }
        }
        return PeerSnapshot(version: PeerSnapshot.current, name: peers.name, since: peers.since, offices: offices, minions: ms, github: knowledge, project: board)
    }

    /// A peer's claim lands on our work station: its offices get the same key here, adopting the
    /// peer's floor plan when that floor is free. A whole peer arriving fades in; one new checkout
    /// on a peer we already follow earns a shuttle, like a new session of our own.
    private func receivePeer(_ snap: PeerSnapshot) {
        let now = Date()
        let isNewPeer = peerFirstSeen[snap.name] == nil
        if isNewPeer { peerFirstSeen[snap.name] = now; logEvent("\(snap.name) is in range") }
        let bulk = isNewPeer || now.timeIntervalSince(peerFirstSeen[snap.name]!) < 15
        peerSnapshots[snap.name] = (snap, now)
        let station = fleet.station("work")
        let sk = station.name + "|"
        var changed = false
        var deliveries: [String] = []
        let cfg = ConfigStore.shared.current
        let mine = Set(peerOffices.filter { $0.value[snap.name] != nil }.map(\.key))
        var live: Set<String> = []
        for o in snap.offices where cfg.repos[o.repo]?.station != "hidden" && !isKicked(sk + o.key) {
            let key = sk + o.key
            live.insert(key)
            peerOffices[key, default: [:]][snap.name] = o
            if o.pushed { pushedByPeer.insert(key) }
            if o.boxes > 0 { peerBoxes[key] = (o.boxes, "NONE", NSColor(o.color)) } else { peerBoxes[key] = nil }
            if let r = station.rooms[o.key] {
                r.lastActive = max(r.lastActive, o.lastActive, now)
                if r.worktree == nil, crewRoomInfo[key] == nil, r.name != o.name { r.name = o.name; changed = true }
                continue
            }
            let color = fleet.color(forRepo: o.repo)
            guard station.ensureRoom(key: o.key, name: o.name, repo: o.repo, color: color, lastActive: now, preferredCells: o.cells) else { continue }
            changed = true
            if !bulk, now.timeIntervalSince(o.startedAt) < 3 * 60 {
                undelivered.insert(key); deliveries.append(o.key)
                logEvent("\(snap.name) started \(o.name)")
            } else {
                fadeIn.insert(key)
            }
        }
        for key in mine where !live.contains(key) {
            peerOffices[key]?[snap.name] = nil
            if peerOffices[key]?.isEmpty == true { peerOffices[key] = nil; peerBoxes[key] = nil }
        }
        if changed {
            rebuildStatic()
            for m in minions.values where m.errand == nil { send(m, to: m.place) }
        } else if !snap.offices.isEmpty {
            rebuildMarkers()
        }
        for roomKey in deliveries {
            let free = minions.values.filter { $0.station == station.name && !$0.isCrew && !$0.isSubagent && $0.errand == nil && $0.carried == nil && !$0.busy }
                .min(by: { $0.freeSince > $1.freeSince })
            if let m = free { startDelivery(m, roomKey: roomKey) } else { reveal(sk + roomKey) }
        }

        // Their minions stand in the office they claim here, wherever we happened to put it.
        for m in snap.minions {
            let id = "\(snap.name)/\(m.id)"
            let cells: [Cell]
            if m.asleep { cells = station.cells(of: .quarters) } else { cells = station.rooms[m.office]?.cells ?? [] }
            guard !cells.isEmpty else { continue }
            var seed = UInt64(truncatingIfNeeded: id.hashValue) | 1
            func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
            let cell = cells[Int(rnd() * Double(cells.count)) % cells.count]
            let target = SIMD3(station.offset.x + Double(cell.x) + (rnd() - 0.5) * 0.5, 0, station.offset.y + Double(cell.y) + (rnd() - 0.5) * 0.5)
            if let existing = peerMinions[id] {
                peerMinions[id] = (existing.node, target)
            } else {
                let n = SCNNode(geometry: SCNBox(width: 0.22, height: 0.5, length: 0.11, chamferRadius: 0.01))
                n.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.62, 0.78)))
                n.position = v3(target.x, 0.25, target.z)
                n.name = "peer:" + snap.name
                peerRoot.addChildNode(n)
                peerMinions[id] = (n, target)
            }
            peerMinions[id]?.node.eulerAngles.x = m.asleep ? -.pi / 2 : 0
        }
        // Their GitHub answers for repositories we also watch save us a poll; same for the board.
        if let b = snap.project, let p = cfg.project, b.owner == p.owner, b.number == p.number { github.adoptProject(b.items, at: b.at); handleProjectMoves() }
        for k in snap.github ?? [] where cfg.shared(repo: k.repo) {
            for (root, info) in repoRoots where info.repo == k.repo && info.station == "work" { github.adopt(k, repoRoot: root) }
        }
        let liveMinions = Set(snap.minions.map { "\(snap.name)/\($0.id)" })
        for (id, pm) in peerMinions where id.hasPrefix(snap.name + "/") && !liveMinions.contains(id) { pm.node.removeFromParentNode(); peerMinions[id] = nil }
    }

    /// A peer has gone quiet: its figures leave, its offices stay held until their hold runs out.
    private func dropPeer(_ name: String) {
        peerSnapshots[name] = nil; peerFirstSeen[name] = nil
        for (id, pm) in peerMinions where id.hasPrefix(name + "/") { pm.node.removeFromParentNode(); peerMinions[id] = nil }
        for (key, claims) in peerOffices where claims[name] != nil {
            peerOffices[key]?[name] = nil
            if peerOffices[key]?.isEmpty == true { peerOffices[key] = nil; peerBoxes[key] = nil; held[key] = Date() }
        }
        logEvent("\(name) is out of range")
        rebuildMarkers()
    }

    // MARK: hauling and power

    private func addHaul(station: Station, box: SCNNode, from: Cell, to: Cell, drop: SIMD3<Double>, roomKey: String = "", onDone: @escaping () -> Void) {
        hauls.append(Haul(id: nextHaulId, station: station.name, box: box, from: from, to: to, drop: drop, onDone: onDone, carrier: nil, roomKey: roomKey))
        nextHaulId += 1
    }

    /// Drops every haul tied to a room, freeing whoever was carrying.
    private func cancelHauls(roomKey: String) {
        for h in hauls where h.roomKey == roomKey {
            h.box.removeFromParentNode()
            if let c = h.carrier, let m = minions[c] { m.errand = nil; m.carried = nil; send(m, to: Place.forActivity(m.activity, home: m.home.key, isSubagent: m.isSubagent)) }
        }
        hauls.removeAll { $0.roomKey == roomKey }
    }

    /// Merged: the office's package is carried to the storage bay in one trip.
    private func haulMergedBoxes(station: Station, room: Room) {
        let key = roomKey(station, room)
        guard station.hasPad, !haulingRooms.contains(key) else { return }
        hauledAt[key] = Date()   // even with nothing to carry, the office is now free to clear
        guard let pkg = markerRoot.childNodes.first(where: { $0.name == "box:" + key }) else { return }
        haulingRooms.insert(key)
        logEvent("\(room.name): merged, package to storage")
        let repo = room.repo ?? "work"
        let dest = station.storageCells.randomElement() ?? Station.rect(1, 1)[0]
        let fromCell = Cell(x: Int((Double(pkg.position.x) - station.offset.x).rounded()), y: Int((Double(pkg.position.z) - station.offset.y).rounded()))
        pkg.name = "haul"
        addHaul(station: station, box: pkg, from: fromCell, to: dest, drop: SIMD3(station.offset.x + Double(dest.x), 0.16, station.offset.y + Double(dest.y)), roomKey: key) { [weak self] in
            guard let self else { return }
            station.stored[repo, default: 0] += 1
            pkg.removeFromParentNode()
            rebuildMarkers()
            rebuildRockets()
            fleet.save()
        }
    }

    /// A staging release merged: the repo's storage boxes are carried to the test deck.
    private func stageCargo(station: Station, repo: String) {
        let boxes = markerRoot.childNodes.filter { $0.name == "storage:\(station.name)|\(repo)" }
        guard !boxes.isEmpty else { return }
        logEvent("\(repo): deployed to staging, moving to the test deck")
        for (i, b) in boxes.enumerated() {
            let dest = station.deckCells[i % station.deckCells.count]
            let fromCell = Cell(x: Int((Double(b.position.x) - station.offset.x).rounded()), y: Int((Double(b.position.z) - station.offset.y).rounded()))
            b.name = "haul"
            addHaul(station: station, box: b, from: fromCell, to: dest, drop: SIMD3(station.offset.x + Double(dest.x), 0.12, station.offset.y + Double(dest.y))) { [weak self] in
                guard let self else { return }
                station.stored[repo] = max(0, (station.stored[repo] ?? 1) - 1)
                station.staged[repo, default: 0] += 1
                b.removeFromParentNode()
                rebuildMarkers()
                rebuildRockets()
                fleet.save()
            }
        }
    }

    /// Steam venting from a loaded rocket waiting for ignition.
    private func addSteam(to rocket: SCNNode) {
        guard rocket.childNode(withName: "steam", recursively: false) == nil else { return }
        let emitter = SCNNode(); emitter.name = "steam"
        rocket.addChildNode(emitter)
        let puff = SCNAction.run { [weak self] _ in
            guard let self else { return }
            enqueue {
                let p = SCNNode(geometry: SCNSphere(radius: 0.08))
                p.geometry!.firstMaterial = flat(NSColor(rgb: (0.85, 0.88, 0.95)))
                p.opacity = 0.7
                p.position = v3(Double.random(in: -0.25...0.25), 0.05, Double.random(in: -0.25...0.25))
                emitter.addChildNode(p)
                p.runAction(.sequence([.group([.moveBy(x: CGFloat(Double.random(in: -0.4...0.4)), y: 0.5, z: CGFloat(Double.random(in: -0.4...0.4)), duration: 1.6), .scale(to: 2.2, duration: 1.6), .fadeOut(duration: 1.6)]), .removeFromParentNode()]))
            }
        }
        emitter.runAction(.repeatForever(.sequence([puff, .wait(duration: 0.25)])))
    }

    /// Cleared to launch: the deck (or storage, without a staging branch) is loaded into the rocket, which then steams until ignition.
    private func loadRocket(station: Station, rocket: SCNNode, repo: String, thenLaunch: Bool = true) {
        let source = ConfigStore.shared.current.stagingBranch.isEmpty ? "storage" : "deck"
        let boxes = markerRoot.childNodes.filter { ($0.name ?? "").hasPrefix("\(source):\(station.name)|\(repo)|") }
        guard !boxes.isEmpty else { if thenLaunch { liftOff(rocket) } else { addSteam(to: rocket) }; return }
        pendingLaunch[station.name + "|" + repo] = (rocket, boxes.count, clock)
        pendingIgnition[station.name + "|" + repo] = thenLaunch
        logEvent("\(repo): cleared, loading the rocket")
        let padCell = station.padCells.first ?? Station.rect(1, 1)[0]
        let pc = station.padCenter
        for b in boxes {
            let fromCell = Cell(x: Int((Double(b.position.x) - station.offset.x).rounded()), y: Int((Double(b.position.z) - station.offset.y).rounded()))
            b.name = "haul"
            addHaul(station: station, box: b, from: fromCell, to: padCell, drop: SIMD3(station.offset.x + pc.x, 0.6, station.offset.y + pc.y)) { [weak self] in
                guard let self else { return }
                if source == "deck" { station.staged[repo] = max(0, (station.staged[repo] ?? 1) - 1) } else { station.stored[repo] = max(0, (station.stored[repo] ?? 1) - 1) }
                b.runAction(.sequence([.scale(to: 0.01, duration: 0.3), .removeFromParentNode()]))
                let pk = station.name + "|" + repo
                if var p = pendingLaunch[pk] {
                    p.remaining -= 1
                    pendingLaunch[pk] = p
                    if p.remaining <= 0 {
                        pendingLaunch[pk] = nil
                        if pendingIgnition[pk] ?? true { liftOff(p.node) } else { loadedRockets[pk] = boxes.count; addSteam(to: p.node); logEvent("\(repo): loaded and steaming, waiting for the release to merge") }
                        pendingIgnition[pk] = nil
                        fleet.save()
                    }
                }
            }
        }
    }

    /// Gives waiting hauls to free minions on the same station.
    private func scheduleHauls() {
        for i in hauls.indices where hauls[i].carrier == nil {
            let h = hauls[i]
            guard let station = fleet.stations[h.station] else { continue }
            let free = minions.values.filter { $0.station == h.station && $0.errand == nil && $0.carried == nil && !$0.isSubagent && $0.state != .leaving }
            guard let m = free.min(by: { abs($0.cell.x - h.from.x) + abs($0.cell.y - h.from.y) < abs($1.cell.x - h.from.x) + abs($1.cell.y - h.from.y) }) else { continue }
            hauls[i].carrier = m.id
            m.errand = .pickup(h.id)
            m.bed = nil
            m.path = station.path(from: m.pos, to: h.from)
        }
        for (name, p) in pendingLaunch where clock - p.since > 90 {   // never let a stuck haul ground a launch
            pendingLaunch[name] = nil
            if pendingIgnition[name] ?? true { liftOff(p.node) } else { loadedRockets[name] = p.remaining; addSteam(to: p.node) }
            pendingIgnition[name] = nil
        }
    }

    /// Lights flicker on when a dark office gets activity, and dim when it is left alone.
    private func updatePower() {
        for station in fleet.stations.values {
            for room in station.rooms.values where !room.key.hasPrefix("kind:") && crewRoomInfo[roomKey(station, room)] == nil {
                let key = roomKey(station, room)
                let powered = Date().timeIntervalSince(room.lastActive) < StationController.powerWindow
                    || minions.values.contains { $0.station == station.name && $0.place == .room(room.key) && $0.busy }
                guard powered != (roomPower[key] ?? powered) else { continue }
                roomPower[key] = powered
                let full = NSColor(room.color)
                let base = room.key.hasPrefix("proj:") ? full.darker(0.32) : full
                let color = powered ? base : base.darker(0.2)
                for t in roomTiles[key] ?? [] {
                    t.geometry?.firstMaterial?.diffuse.contents = color
                    let flicker = SCNAction.sequence([.fadeOpacity(to: 0.35, duration: 0.05), .fadeOpacity(to: 1, duration: 0.08), .fadeOpacity(to: 0.5, duration: 0.05), .fadeOpacity(to: 1, duration: 0.12), .fadeOpacity(to: 0.7, duration: 0.05), .fadeOpacity(to: 1, duration: 0.1)])
                    t.runAction(flicker)
                }
                if powered { logEvent("\(room.name): lights on") }
            }
        }
    }

    // MARK: crew

    private static let trunkBranches: Set<String> = ["develop", "staging", "main", "master", "production"]

    private func crewName(_ login: String) -> String { ConfigStore.shared.current.crewNames[login] ?? login }
    private(set) var seenLogins: Set<String> = []

    /// Crew station: an office per open teammate pull request, boxes per push, and minions that
    /// react only to what just happened in the repositories' activity feeds.
    private func rebuildCrew() {
        let me = github.myLogin() ?? ""
        let now = Date()
        let cfg = ConfigStore.shared.current
        let station = fleet.station("work")
        let sk = station.name + "|"
        guard cfg.showCrew else {
            guard !crewRoomInfo.isEmpty || minions.values.contains(where: \.isCrew) else { return }
            for m in minions.values where m.isCrew { despawn(m) }
            for room in Array(station.rooms.values) where isRemoteOnly(station, room) { archive(station: station, room: room, announce: false, reason: "crew hidden") }
            crewRoomInfo = [:]; crewBoxes = [:]
            rebuildStatic()
            return
        }
        var changed = false
        var open: [(repo: String, pr: OpenPR)] = []
        var feed: [(repo: String, e: FeedEvent)] = []
        for (root, info) in repoRoots where info.station == "work" && cfg.crewEnabled(repo: info.repo) {
            for pr in github.teamOpenPRs(repoRoot: root) ?? [] where pr.author != me && !StationController.trunkBranches.contains(pr.branch) { open.append((info.repo, pr)) }
            for e in github.feed(repoRoot: root) ?? [] where e.actor != me { feed.append((info.repo, e)) }
        }
        // Issues the board says are in development, assigned to someone else: offices too, even before a pull request.
        var boardOffices: [(repo: String, item: ProjectItem, login: String)] = []
        if cfg.project != nil, !me.isEmpty, let items = github.projectItems() {   // not before GitHub has said who I am
            let workRepos = Set(repoRoots.values.filter { $0.station == "work" && cfg.crewEnabled(repo: $0.repo) }.map(\.repo))
            // The column says an office is solid; it does not make one. An issue needs a sign of work:
            // a linked pull request, a branch seen in the feed, or a room a session or peer already claims.
            var branched: Set<String> = []   // "repo#N" with a gh-N/… branch pushed in the last two weeks
            let recent = now.addingTimeInterval(-14 * 24 * 3600)
            for (repo, e) in feed where e.at > recent { if let b = e.branch, let m = b.firstMatch(of: #/^gh-(\d+)\//#) { branched.insert("\(repo)#\(m.1)") } }
            for it in items where it.status == cfg.statuses.development && workRepos.contains(it.repo) {
                let key = "task:\(it.repo)#\(it.number)"
                guard let login = it.assignees.first, login != me else { continue }
                if open.contains(where: { $0.repo == it.repo && crewKey(repo: $0.repo, branch: $0.pr.branch) == key }) { continue }
                let working = !it.prURLs.isEmpty || branched.contains("\(it.repo)#\(it.number)") || peerOffices[sk + key] != nil || station.rooms[key]?.worktree != nil
                guard working else { continue }
                boardOffices.append((it.repo, it, login))
            }
        }
        guard !open.isEmpty || !feed.isEmpty || !boardOffices.isEmpty else { return }

        // Offices for open pull requests; a new one arrives by shuttle, a gone one is archived.
        var liveKeys = Set(open.filter { !$0.pr.isBot }.map { crewKey(repo: $0.repo, branch: $0.pr.branch) })
        liveKeys.formUnion(boardOffices.map { "task:\($0.repo)#\($0.item.number)" })
        for room in Array(station.rooms.values) where crewRoomInfo[sk + room.key] != nil && !liveKeys.contains(room.key) {
            let key = sk + room.key
            let author = crewRoomInfo[key]?.author ?? ""
            // A teammate's office that we also have checked out stays: the local scan decides its fate.
            guard room.worktree == nil else { crewRoomInfo[key] = nil; crewBoxes[key] = nil; continue }
            // Its crate goes to storage on someone's arms first; the office clears once that is done.
            if hauledAt[key] == nil, station.hasPad {
                haulMergedBoxes(station: station, room: room)
                if crewLoaded, let m = minions["crew:" + author] { m.activity = .shipping; m.busy = true; crewBusyUntil[m.id] = now.addingTimeInterval(240); send(m, to: .core) }
            }
            guard !station.hasPad || !hauls.contains(where: { $0.roomKey == key }) else { continue }
            crewRoomInfo[key] = nil; crewBoxes[key] = nil
            archive(station: station, room: room, announce: crewLoaded, reason: "pull request closed")
            changed = true
        }
        var pendingDeliveries: [(login: String, key: String)] = []
        for (repo, pr) in open where !pr.isBot && !isKicked(sk + Home.from(repo: repo, branch: pr.branch, cwd: "").key) {
            let home = Home.from(repo: repo, branch: pr.branch, cwd: "")
            let key = home.key
            let name = home.name
            if let r = station.rooms[key], r.worktree == nil, r.name != name { r.name = name; changed = true }
            if station.ensureRoom(key: key, name: name, repo: repo, color: fleet.color(forRepo: repo), lastActive: now) {
                changed = true
                if crewLoaded { undelivered.insert(sk + key); pendingDeliveries.append((pr.author, key)); logEvent("\(crewName(pr.author)) opened #\(pr.number) \(pr.title.prefix(40))") }
            }
            crewRoomInfo[sk + key] = CrewRoomInfo(repo: repo, branch: pr.branch, prNumber: pr.number, title: pr.title, author: pr.author, url: pr.url, state: "OPEN", last: pr.createdAt)
            let pushes = feed.filter { $0.repo == repo && $0.e.kind == "push" && $0.e.branch == pr.branch && $0.e.at > pr.createdAt }.map { Int($0.e.detail) ?? 1 }.reduce(0, +)
            crewBoxes[sk + key] = (1 + pushes, "OPEN", NSColor(fleet.color(forRepo: repo)))
        }
        for (repo, it, login) in boardOffices where !isKicked(sk + "task:\(repo)#\(it.number)") {
            let key = "task:\(repo)#\(it.number)"
            let name = "#\(it.number) " + String(it.title.prefix(22))
            if let r = station.rooms[key], r.worktree == nil, r.name != name { r.name = name; changed = true }
            if station.ensureRoom(key: key, name: name, repo: repo, color: fleet.color(forRepo: repo), lastActive: now) {
                changed = true
                if crewLoaded { undelivered.insert(sk + key); pendingDeliveries.append((login, key)); logEvent("\(crewName(login)) started #\(it.number) \(it.title.prefix(40))") }
            }
            let prNumber = it.prURLs.first.flatMap { Int($0.split(separator: "/").last ?? "") }
            crewRoomInfo[sk + key] = CrewRoomInfo(repo: repo, branch: "gh-\(it.number)", prNumber: prNumber, title: it.title, author: login, url: it.url, state: "OPEN", last: now)
            crewBoxes[sk + key] = (1, "NONE", NSColor(fleet.color(forRepo: repo)))
        }
        let botCount = open.filter(\.pr.isBot).count
        if botCount > 0 {
            if station.ensureRoom(key: "kind:bots", name: "bots", repo: nil, color: RGB(r: 0.36, g: 0.40, b: 0.50), lastActive: .distantFuture, shape: Station.rect(2, 2)) { changed = true }
            crewBoxes[sk + "kind:bots"] = (botCount, "NONE", NSColor(rgb: (0.55, 0.6, 0.7)))
        }

        // One grey minion per teammate with an open PR or recent activity.
        var logins = Set(open.filter { !$0.pr.isBot }.map(\.pr.author))
        logins.formUnion(boardOffices.map(\.login))
        logins.formUnion(feed.filter { !$0.e.isBot && now.timeIntervalSince($0.e.at) < 2 * 3600 }.map(\.e.actor))
        seenLogins.formUnion(feed.filter { !$0.e.isBot }.map(\.e.actor)); seenLogins.formUnion(logins)
        for login in logins where minions["crew:" + login] == nil {
            let homeKey = open.first { $0.pr.author == login }.map { crewKey(repo: $0.repo, branch: $0.pr.branch) } ?? "kind:quarters"
            let home = Home(key: homeKey, name: login, repo: open.first { $0.pr.author == login }?.repo ?? "crew", issue: nil)
            let start = station.cells(of: .quarters).randomElement() ?? station.coreCenter
            let m = Minion(id: "crew:" + login, station: station.name, home: home, cwd: "", toolCount: 0, isSubagent: false, start: start, crew: true)
            m.title = crewName(login)
            m.activity = .sleeping
            minionRoot.addChildNode(m.node)
            minions[m.id] = m
            send(m, to: .quarters)
        }
        for m in minions.values where m.isCrew && m.id != "crew:bots" && !logins.contains(String(m.id.dropFirst(5))) { despawn(m) }
        if botCount > 0, minions["crew:bots"] == nil {
            let m = Minion(id: "crew:bots", station: station.name, home: Home(key: "kind:bots", name: "bots", repo: "crew", issue: nil), cwd: "", toolCount: 0, isSubagent: true, start: station.coreCenter, crew: true)
            m.title = "dependabot"; m.activity = .sleeping
            minionRoot.addChildNode(m.node); minions[m.id] = m
            send(m, to: .room("kind:bots"))
        }
        if changed { rebuildStatic(); for m in minions.values where m.errand == nil { send(m, to: m.place) } } else { rebuildMarkers() }
        for d in pendingDeliveries {
            if let m = minions["crew:" + d.login], m.errand == nil { startDelivery(m, roomKey: d.key) } else { reveal(sk + d.key) }
        }

        // What just happened: only fresh events move minions and make the log.
        for (repo, e) in feed.sorted(by: { $0.e.at < $1.e.at }) where !e.isBot {
            let id = "\(repo)|\(e.at.timeIntervalSince1970)|\(e.actor)|\(e.kind)|\(e.branch ?? "")"
            guard !crewSeen.contains(id) else { continue }
            crewSeen.insert(id)
            let fresh = now.timeIntervalSince(e.at) < StationController.crewRecent
            guard fresh else { continue }
            let roomKey = e.branch.map { crewKey(repo: repo, branch: $0) } ?? ""
            let hasRoom = station.rooms[roomKey] != nil
            guard let m = minions["crew:" + e.actor], m.errand == nil else { continue }
            let n = e.prNumber.map { "#\($0)" } ?? (e.branch ?? "")
            switch e.kind {
            case "push" where hasRoom:
                m.activity = .coding("x"); m.busy = true; crewBusyUntil[m.id] = now.addingTimeInterval(20 * 60)
                if m.place != .room(roomKey) { send(m, to: .room(roomKey)) }
                if crewLoaded { logEvent("\(crewName(e.actor)) pushed to \(n)") }
            case "review" where hasRoom:
                m.activity = .exploring; m.busy = true; crewBusyUntil[m.id] = now.addingTimeInterval(10 * 60)
                send(m, to: .room(roomKey))
                let verb = e.detail == "approved" ? "approved" : e.detail == "changes_requested" ? "requested changes on" : "reviewed"
                logEvent("\(crewName(e.actor)) \(verb) \(n)")
            case "comment" where hasRoom:
                m.activity = .writing; m.busy = true; crewBusyUntil[m.id] = now.addingTimeInterval(8 * 60)
                send(m, to: .room(roomKey))
            case "branch_create":
                m.activity = .planning; m.busy = true; crewBusyUntil[m.id] = now.addingTimeInterval(10 * 60)
                send(m, to: .core)
                logEvent("\(crewName(e.actor)) started \(e.branch ?? "a branch")")
            case "issue_open":
                logEvent("\(crewName(e.actor)) filed \(n) \(e.title?.prefix(40) ?? "")")
                addPyramid(for: m)
            default: break
            }
        }
        // Only count as loaded once every work repo has answered, so existing PRs never look new.
        if repoRoots.filter({ $0.value.station == "work" }).allSatisfy({ github.teamOpenPRs(repoRoot: $0.key) != nil }) { crewLoaded = true }
    }

    /// Status moves on the board are the station's cues: a crate to the deck, a tick from QA, a launch.
    private func handleProjectMoves() {
        let st = ConfigStore.shared.current.statuses
        var staged: Set<String> = []
        for (item, from) in github.takeProjectMoves() {
            guard let info = repoRoots.values.first(where: { $0.repo == item.repo }), let station = fleet.stations[info.station] else { continue }
            let label = "#\(item.number) \(item.title.prefix(36))"
            switch item.status {
            case st.deck where from == st.storage || from == nil:
                if !staged.contains(item.repo) { staged.insert(item.repo); stageCargo(station: station, repo: item.repo) }
            case st.cleared:
                logEvent("\(label): passed QA, ready to ship")
                if let crate = markerRoot.childNodes.first(where: { $0.name == "deck:\(station.name)|\(item.repo)|\(item.number)" }) {
                    // Someone carries it across the aisle to the tested row; the layout redraws it there once set down.
                    let rows = Set(station.deckCells.map(\.y)).sorted()
                    let testedY = rows.first ?? 0   // the row nearest the pad
                    let dest = station.deckCells.filter { $0.y == testedY }.min { $0.x < $1.x } ?? station.deckCells[0]
                    let fromCell = Cell(x: Int((Double(crate.position.x) - station.offset.x).rounded()), y: Int((Double(crate.position.z) - station.offset.y).rounded()))
                    let id = "\(item.repo)|\(item.number)"
                    haulingCrates.insert(id)
                    crate.name = "haul"
                    addHaul(station: station, box: crate, from: fromCell, to: dest, drop: SIMD3(station.offset.x + Double(dest.x), 0.12, station.offset.y + Double(dest.y))) { [weak self] in
                        guard let self else { return }
                        haulingCrates.remove(id)
                        crate.removeFromParentNode()
                        drone.ping(seed: item.number)
                        rebuildMarkers()
                    }
                }
            case st.shipped where from != nil:
                logEvent("\(label): shipped")
            case st.storage where from == st.development:
                logEvent("\(label): merged, ready for staging")
            case st.development where from != nil && from != st.development:
                logEvent("\(label): in development")
            default: break
            }
        }
        if !staged.isEmpty { rebuildMarkers() }
    }

    /// When the deck holds cargo and nothing is cleared to launch, one free worker walks the rows, impatient.
    private func assignTester(station: Station, free: [Minion]) {
        var cargoOnDeck = station.staged.values.reduce(0, +) > 0
        if ConfigStore.shared.current.project != nil {
            // With a board, QA is done once every crate on the deck is marked ready to ship.
            cargoOnDeck = repoRoots.contains { root, info in
                info.station == station.name && (github.cargo(repoRoot: root).map { $0.deckNumbers.count > $0.clearedNumbers.count } ?? false)
            }
        }
        let cleared = loadedRockets.keys.contains { $0.hasPrefix(station.name + "|") }
        let wanted = cargoOnDeck && !cleared && !station.deckCells.isEmpty
        let current = minions.values.first { $0.station == station.name && $0.isTester }
        if wanted, current == nil, let m = free.first(where: { $0.errand == nil }) {
            m.isTester = true
            m.activity = .qa
            m.busy = true
            send(m, to: .room("kind:deck"))
            logEvent("staging ready for QA · \(m.home.name) walks the rows")
        } else if !wanted, let m = current {
            m.isTester = false
            m.busy = false
            m.activity = .waiting
            m.setTool(nil)
            send(m, to: .lounge)
        }
    }

    /// Crew minions rest once their last activity is old.
    private func tickCrewRest() {
        let now = Date()
        for m in minions.values where m.isCrew && m.busy {
            if let until = crewBusyUntil[m.id], now < until { continue }
            m.busy = false; m.activity = .sleeping
            clearPyramids(m)
            send(m, to: m.id == "crew:bots" ? .room("kind:bots") : .quarters)
        }
    }

    // MARK: demo

    private func seedDemo() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let acts: [(String, String, Activity, String)] = [
            ("api-node-nest", "\(home)/conductor/workspaces/api-node-nest/bismarck", .coding("src"), "gh-5158/drop-the-services-pilot-gate-on-the-offerings-routes"),
            ("api-node-nest", "\(home)/conductor/workspaces/api-node-nest/regina", .testing, "gh-5140/settlement-redesign"),
            ("api-node-nest", "\(home)/conductor/workspaces/api-node-nest/bismarck", .researching, "gh-5158/drop-the-services-pilot-gate-on-the-offerings-routes"),
            ("tattoodo-web", "\(home)/conductor/workspaces/tattoodo-web/damascus", .coding("app"), "gh-455/booking-flow"),
            ("tattoodo-web", "\(home)/conductor/workspaces/tattoodo-web/oslo", .shipping, "gh-450/hero"),
            ("app-ios", "\(home)/conductor/workspaces/app-ios/lima", .waiting, "gh-298/onboarding"),
            ("app-ios", "\(home)/conductor/workspaces/app-ios/quito", .sleeping, "gh-290/crash-fix"),
            ("rymdkapsel", "\(home)/dev/rymdkapsel", .researching, "main"),
            ("madplan", "\(home)/dev/madplan", .thinking, "main"),
        ]
        for (i, a) in acts.enumerated() {
            let stationName = a.1.contains("/conductor/") ? "work" : "private"
            let station = fleet.station(stationName)
            let h = Home.from(repo: a.0, branch: a.3, cwd: a.1)
            station.ensureRoom(key: h.key, name: h.name, repo: h.repo, color: fleet.color(forRepo: h.repo), lastActive: Date())
            let s = SessionInfo(id: "demo-\(i)", cwd: a.1, repo: a.0, repoRoot: nil, owner: nil, lastModified: Date(), activity: a.2, area: nil,
                                title: nil, branch: a.3, toolCount: 0, isSubagent: i == 2, cwdExists: true, promptCount: 0, queuedCount: 0, eventMarkers: [:])
            let m = spawnMinion(s, station: stationName, home: h)
            m.busy = a.2 != .waiting && a.2 != .sleeping
            m.activity = a.2
            m.branch = a.3
            m.place = Place.forActivity(a.2, home: h.key, isSubagent: m.isSubagent)
        }
        rebuildStatic()
        for m in minions.values { send(m, to: m.place) }
        logEvent("#450 opened a pull request")
        if let st = fleet.stations["work"] {
            for (i, tall) in [false, true].enumerated() {
                let n = Props.rocket(color: NSColor(fleet.color(forRepo: i == 0 ? "api-node-nest" : "tattoodo-web")), tall: tall)
                let pc = st.padCenter + (i == 0 ? SIMD2(0.45, -0.45) : SIMD2(0, 0))
                n.position = v3(st.offset.x + pc.x, 0, st.offset.y + pc.y)
                n.name = "rocket:https://github.com|demo release"
                if tall { let d = Props.holdDecoration(around: SIMD3(0, 0, 0), tall: true); d.name = "hold"; n.addChildNode(d) }
                rocketRoot.addChildNode(n)
                rockets["work|\(i)"] = n
            }
        }
    }

    private func tickDemo(dt: Double) {
        demoClock += dt
        if demoClock > 3.0 {
            demoClock = 0
            if let m = minions.values.filter({ $0.busy && !$0.isSubagent && $0.errand == nil }).randomElement() {
                m.toolCount += 1
                if m.toolCount % 2 == 0 { addPyramid(for: m) } else { clearPyramids(m) }
                ringBell(seed: m.id.hashValue)
            }
            // Demo: a merge sends #450's boxes to storage, then a release loads them into the rocket.
            if clock > 7, !demoMerged, let st = fleet.stations["work"], let room = st.rooms["task:tattoodo-web#450"] {
                demoMerged = true
                let key = roomKey(st, room)
                for (i, c) in room.cells.prefix(3).enumerated() {
                    let b = SCNNode(geometry: SCNBox(width: 0.26, height: 0.26, length: 0.26, chamferRadius: 0))
                    b.geometry!.firstMaterial = lit(NSColor(rgb: (0.6, 0.4, 0.9)))
                    b.position = v3(st.offset.x + Double(c.x) + Double(i) * 0.1 - 0.2, 0.13, st.offset.y + Double(c.y))
                    b.name = "box:" + key
                    markerRoot.addChildNode(b)
                }
                haulMergedBoxes(station: st, room: room)
            }
            if clock > 16, !demoStaged, let st = fleet.stations["work"], (st.stored["tattoodo-web"] ?? 0) > 0 { demoStaged = true; stageCargo(station: st, repo: "tattoodo-web") }
            if clock > 30, let r = rockets["work|1"], !r.hasActions, r.parent != nil, pendingLaunch["work|tattoodo-web"] == nil, let st = fleet.stations["work"] {
                r.childNode(withName: "hold", recursively: false)?.removeFromParentNode()
                loadRocket(station: st, rocket: r, repo: "tattoodo-web")
                logEvent("tattoodo-web launched to production: release 2.14")
                rockets["work|1"] = nil
            }
            if false, let r = rockets["work|1"], !r.hasActions, r.parent != nil {
                liftOff(r)
                logEvent("tattoodo-web launched to production: release 2.14")
            }
            if clock > 6, !minions.keys.contains("demo-new") {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let cwd = "\(home)/conductor/workspaces/tattoodo-web/lagos"
                let station = fleet.station("work")
                let h = Home.from(repo: "tattoodo-web", branch: "gh-470/artist-search", cwd: cwd)
                station.ensureRoom(key: h.key, name: h.name, repo: h.repo, color: fleet.color(forRepo: h.repo), lastActive: Date())
                undelivered.insert("work|\(h.key)")
                rebuildStatic()
                for mm in minions.values where mm.errand == nil { send(mm, to: mm.place) }
                let s = SessionInfo(id: "demo-new", cwd: cwd, repo: "tattoodo-web", repoRoot: nil, owner: nil, lastModified: Date(), activity: .coding("app"), area: nil,
                                    title: nil, branch: "gh-470/artist-search", toolCount: 0, isSubagent: false, cwdExists: true, promptCount: 0, queuedCount: 0, eventMarkers: [:])
                let m = spawnMinion(s, station: "work", home: h)
                m.busy = true; m.activity = .coding("app")
                startDelivery(m, roomKey: h.key)
            }
        }
    }

    // MARK: tick

    private func tick(now: TimeInterval) {
        let dt = min(0.1, max(0, now - lastTick))
        lastTick = now
        clock += dt
        if demo { tickDemo(dt: dt) }
        if Int(clock) % 5 == 0 && Int(clock - dt) % 5 != 0 { tickCrewRest(); updatePower() }
        if clock - lastHaulSchedule > 0.5 { lastHaulSchedule = clock; scheduleHauls(); refreshObstacles() }
        for (id, pm) in peerMinions {
            let p = SIMD3(Double(pm.node.position.x), 0, Double(pm.node.position.z))
            let d = pm.target - p
            let step = min(1, dt * 2)
            pm.node.position.x += CGFloat(d.x * step); pm.node.position.z += CGFloat(d.z * step)
            _ = id
        }
        if Int(clock) % 5 == 0 && Int(clock - dt) % 5 != 0 {
            for name in peerSnapshots.filter({ Date().timeIntervalSince($0.value.at) > 20 }).map(\.key) { dropPeer(name) }
        }
        if Int(clock) % 2 == 0 && Int(clock - dt) % 2 != 0 {
            var load: [Int: Int] = [:]
            for m in minions.values where m.busy && !m.isCrew && !m.isSubagent && m.state != .leaving {
                if let i = fleet.repoColors[m.home.repo] { load[i % Colors.repos.count, default: 0] += 1 }
            }
            drone.setWorkload(load)
        }
        if hud.size != viewSize { hud.size = viewSize }
        if keyMove != .zero {
            // Held WASD: a steady slide, a bit under the view's height per second.
            let speed = Double(viewSize.height) * 0.7 * dt
            pan(byPixels: -keyMove.x * speed, keyMove.y * speed)
        }
        if keyZoom != 0 {
            // Held E/Q: doubles or halves the zoom in about a second.
            userZoom = min(6, max(0.4, userZoom * exp(keyZoom * dt * 0.7)))
            userZoomChanged = true
        }

        let k = 1 - exp(-dt * 2)
        let focus = targetFocus + userPan
        let kp = userDriving > 0 ? 1 - exp(-dt * 25) : k
        if userDriving > 0 { userDriving -= dt }
        rig.position.x += (focus.x - Double(rig.position.x)) * kp
        rig.position.z += (focus.y - Double(rig.position.z)) * kp
        let ky = 1 - exp(-dt * 10)
        rig.eulerAngles.y += (Double.pi / 4 + userYaw - Double(rig.eulerAngles.y)) * ky
        pitchNode.eulerAngles.x += (userPitch - Double(pitchNode.eulerAngles.x)) * ky
        let wantScale = fitScale(half: targetHalf) / userZoom
        let scaleK = abs(userZoom - 1) > 0.001 || userZoomChanged ? 1 - exp(-dt * 14) : k
        cameraNode.camera!.orthographicScale += (wantScale - cameraNode.camera!.orthographicScale) * scaleK
        userZoomChanged = false

        for (n, vel) in debris {
            var p = SIMD2(Double(n.position.x), Double(n.position.z)) + vel * dt
            let c = targetFocus
            if p.x > c.x + 40 { p.x -= 80 } else if p.x < c.x - 40 { p.x += 80 }
            if p.y > c.y + 40 { p.y -= 80 } else if p.y < c.y - 40 { p.y += 80 }
            n.position.x = p.x; n.position.z = p.y
        }

        for m in Array(minions.values) {
            guard let station = fleet.stations[m.station] else { despawn(m); continue }
            let waitingAge = m.activity == .waiting ? clock - m.waitingSince : 0
            let jumping = m.activity == .waiting && waitingAge < 60 && m.errand == nil
            let pacing = m.activity == .waiting && waitingAge >= 60 && m.errand == nil
            let speed = m.busy ? 2.4 : (pacing ? 0.8 : 1.4)
            if m.lying, !m.path.isEmpty {
                if m.wakeUntil == 0 { m.wakeUntil = clock + 1.1; m.setSleeping(false); m.bed = nil }
            }
            if m.wakeUntil > 0 {
                if clock < m.wakeUntil { m.node.opacity = m.opacity; continue } else { m.wakeUntil = 0 }
            }
            if let target = m.path.first {
                let d = target - m.pos
                let dist = (d.x * d.x + d.y * d.y).squareRoot()
                let step = speed * dt
                if dist <= step { m.pos = target; m.path.removeFirst() } else { m.pos += d / dist * step }
                m.facing = atan2(d.x, d.y)
            } else {
                if m.commitDrop, let c = m.carried {
                    m.commitDrop = false
                    m.carried = nil
                    let world = c.worldPosition
                    c.removeFromParentNode()
                    c.position = world
                    propRoot.addChildNode(c)
                    let down = SCNAction.move(to: v3(world.x, 0.12, world.z), duration: 0.35); down.timingMode = .easeIn
                    c.runAction(.sequence([down, .run { [weak self] _ in self?.drone.thud() }, .wait(duration: 0.4), .fadeOut(duration: 0.3), .removeFromParentNode()]))
                }
                switch m.errand {
                case .fetch(let r):
                    let key = "\(m.station)|\(r)"
                    if let box = boxes[key], box.opacity < 1 { continue }   // shuttle has not set it down yet
                    if let spot = m.fetchSpot {
                        let d = spot - m.pos
                        if (d.x * d.x + d.y * d.y).squareRoot() > 0.04 { m.pos += d * min(1, dt * 5); m.facing = atan2(d.x, d.y); continue }
                        m.fetchSpot = nil
                    }
                    if let box = boxes[key] {
                        box.removeAllActions()
                        let world = box.worldPosition
                        box.removeFromParentNode()
                        m.node.addChildNode(box)
                        box.position = m.node.convertPosition(world, from: nil)
                        let lift = SCNAction.move(to: v3(0, m.headHeight + 0.14, 0), duration: 0.5); lift.timingMode = .easeOut
                        box.runAction(lift)
                        m.carried = box
                    }
                    m.errand = .carry(room: r)
                    if let door = station.doorCell(of: r) { walk(m, to: door) } else { m.errand = nil; reveal(key) }
                    continue
                case .carry(let r):
                    m.carried?.removeFromParentNode()
                    m.carried = nil
                    m.errand = nil
                    reveal("\(m.station)|\(r)")
                    send(m, to: Place.forActivity(m.activity, home: m.home.key, isSubagent: m.isSubagent))
                    continue
                case .pickup(let id):
                    guard let h = hauls.first(where: { $0.id == id }) else { m.errand = nil; m.bendUntil = 0; continue }
                    // Face the crate, bend down and take hold before straightening up with it.
                    let toBox = SIMD2(Double(h.box.worldPosition.x) - station.offset.x, Double(h.box.worldPosition.z) - station.offset.y) - m.pos
                    if (toBox.x * toBox.x + toBox.y * toBox.y).squareRoot() > 0.05 { m.facing = atan2(toBox.x, toBox.y) }
                    if m.bendUntil == 0 { m.bendUntil = clock + 0.9; continue }
                    if clock < m.bendUntil - 0.45 { continue }
                    if m.carried == nil {
                        let world = h.box.worldPosition
                        h.box.removeAllActions()
                        h.box.removeFromParentNode()
                        m.node.addChildNode(h.box)
                        h.box.position = m.node.convertPosition(world, from: nil)
                        let lift = SCNAction.move(to: v3(0, m.headHeight + 0.14, 0), duration: 0.45); lift.timingMode = .easeInEaseOut
                        h.box.runAction(lift)
                        m.carried = h.box
                    }
                    if clock < m.bendUntil { continue }
                    m.bendUntil = 0
                    m.errand = .deliver(id)
                    walk(m, to: h.to)
                    continue
                case .deliver(let id):
                    guard let idx = hauls.firstIndex(where: { $0.id == id }) else { m.errand = nil; m.carried = nil; m.bendUntil = 0; continue }
                    // Bend and set the crate down squarely, then a beat before straightening up.
                    let h = hauls[idx]
                    let toSpot = SIMD2(h.drop.x - station.offset.x, h.drop.z - station.offset.y) - m.pos
                    if (toSpot.x * toSpot.x + toSpot.y * toSpot.y).squareRoot() > 0.05 { m.facing = atan2(toSpot.x, toSpot.y) }
                    if m.bendUntil == 0 {
                        m.bendUntil = clock + 1.0
                        let world = h.box.worldPosition
                        h.box.removeFromParentNode()
                        h.box.position = world
                        propRoot.addChildNode(h.box)
                        let down = SCNAction.move(to: v3(h.drop.x, h.drop.y, h.drop.z), duration: 0.55); down.timingMode = .easeInEaseOut
                        h.box.runAction(.sequence([down, .run { [weak self] _ in self?.drone.thud() }]))
                        m.carried = nil
                        continue
                    }
                    if clock < m.bendUntil { continue }
                    m.bendUntil = 0
                    hauls.remove(at: idx)
                    h.onDone()
                    m.errand = nil
                    send(m, to: Place.forActivity(m.activity, home: m.home.key, isSubagent: m.isSubagent))
                    continue
                case nil:
                    break
                }
                switch m.state {
                case .arriving:
                    m.state = .settled
                case .settled:
                    if m.isTester, clock >= m.nextWanderAt {
                        let choices = station.deckCells.filter { $0 != m.cell }
                        if let dest = choices.randomElement() { m.path = station.path(from: m.pos, to: dest) }
                        m.nextWanderAt = clock + Double.random(in: 1.5...3.5)
                        m.setTool(.scanner)
                        if clock >= m.nextImpatience {
                            m.nextImpatience = clock + Double.random(in: 5...9)
                            m.node.runAction(.sequence([.moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08)]))
                        }
                    }
                    if m.nextBathAt == 0 { m.nextBathAt = clock + Double.random(in: 90...400) }
                    let settled = m.path.isEmpty
                    if m.place == .bath {
                        if settled {
                            m.setStatic(true, frame: Int(clock * 12))
                            if m.showering, clock >= m.nextDropAt {
                                // Pixel water from the shower head, falling past the shoulders.
                                m.nextDropAt = clock + 0.07
                                let drop = SCNNode(geometry: SCNBox(width: 0.035, height: 0.06, length: 0.035, chamferRadius: 0))
                                drop.geometry!.firstMaterial = flat(NSColor(rgb: (0.62, 0.82, 0.95)))
                                drop.position = v3(m.node.position.x + Double.random(in: -0.14...0.14), m.headHeight + 0.3, m.node.position.z + Double.random(in: -0.14...0.14))
                                propRoot.addChildNode(drop)
                                let fall = SCNAction.move(to: v3(drop.position.x, 0.02, drop.position.z), duration: 0.35); fall.timingMode = .easeIn
                                drop.runAction(.sequence([fall, .fadeOut(duration: 0.1), .removeFromParentNode()]))
                            }
                        }
                        if clock >= m.bathUntil, settled {
                            m.setStatic(false, frame: 0)
                            send(m, to: m.bathReturn ?? Place.forActivity(m.activity, home: m.home.key, isSubagent: m.isSubagent))
                            m.bathReturn = nil
                        }
                    } else if clock >= m.nextBathAt, !m.busy, m.errand == nil, m.carried == nil, !m.isSubagent, m.activity != .sleeping, settled, station.rooms["kind:bath"] != nil {
                        // Off to the bath for a moment, then back to wherever it was.
                        m.nextBathAt = clock + Double.random(in: 300...900)
                        m.bathUntil = clock + Double.random(in: 7...12)
                        m.bathReturn = m.place
                        send(m, to: .bath)
                        // Toilet in the near corner, shower in the far one: pick one and walk to it, facing the fixture.
                        if let bath = station.rooms["kind:bath"] {
                            let cells = bath.cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                            m.showering = Bool.random()
                            let spot = m.showering ? cells.last! : cells.first!
                            m.path = station.path(from: m.pos, to: spot)
                            m.facing = m.showering ? .pi / 4 : -.pi * 3 / 4
                        }
                    }
                    if let pc = m.pyramidCell, m.errand == nil, m.place == .room(m.home.key) {
                        if m.cell != pc { walk(m, to: pc) }
                    } else if clock >= m.nextWanderAt, m.activity != .sleeping, m.place != .quarters, !(m.place == .lounge && m.couch != nil), !jumping {
                        let choices = station.cells(of: m.place).filter { $0 != m.cell }
                        if let dest = choices.randomElement() { m.path = station.path(from: m.pos, to: dest) }
                        m.nextWanderAt = clock + (pacing ? Double.random(in: 2.5...6) : m.busy ? Double.random(in: 2...5) : Double.random(in: 8...20))
                    }
                case .leaving:
                    m.opacity -= dt * 1.5
                    if m.opacity <= 0 { despawn(m); continue }
                }
            }
            if m.state != .leaving { m.opacity = min(1, m.opacity + dt * 2) }
            var bunkLift = 0.0
            if m.path.isEmpty, m.place == .lounge, let c = m.couch, c < station.couches.count {
                m.pos += (station.couches[c] - m.pos) * min(1, dt * 4)
            }
            if m.path.isEmpty, m.place == .quarters {
                if let b = m.bed, b < station.beds.count {
                    m.pos += (station.beds[b].pos - m.pos) * min(1, dt * 4)
                    bunkLift = station.beds[b].level == 1 ? 0.36 : 0
                }
            }
            let resting = m.path.isEmpty && m.state == .settled
            if resting && m.activity == .sleeping && m.place == .quarters { m.setSleeping(true) }
            let jump = jumping && resting && m.place != .lounge ? abs(sin(clock * 7 + m.bobPhase)) * 0.14 : 0
            m.node.position = v3(station.offset.x + m.pos.x, jump + bunkLift, station.offset.y + m.pos.y)
            m.shadow.position.y = CGFloat(0.003 - jump)   // the shadow stays on the floor while the body hops
            m.node.opacity = m.opacity
            let working = m.busy && resting && !m.isSubagent && m.activity != .waiting
            let inBed = m.bed != nil && m.place == .quarters && m.path.isEmpty
            let wantFacing = inBed ? 0 : (m.path.isEmpty ? Double(rig.eulerAngles.y) : m.facing)
            if !(working && !m.pyramids.isEmpty && m.pyramidCell == m.cell) && !(m.place == .lounge && resting) {
                var delta = wantFacing - m.smoothFacing
                delta = atan2(sin(delta), cos(delta))
                m.smoothFacing += delta * min(1, dt * 12)
            }

            // One little routine per activity, so you can tell at a glance what a minion is up to.
            var tilt = 0.0, roll = 0.0, spin = 0.0, lean = 0.0
            let t = clock + m.bobPhase
            let atCone = working && !m.pyramids.isEmpty && m.pyramidCell == m.cell
            if atCone, let cone = m.pyramids.last {
                // Stand a step back from the cone and face it.
                let conePos = SIMD2(Double(cone.position.x), Double(cone.position.z))
                let mates = minions.values.filter { $0.station == m.station && $0.pyramidCell == m.pyramidCell && !$0.pyramids.isEmpty }.map(\.id).sorted()
                let slot = Double(mates.firstIndex(of: m.id) ?? 0)
                let angle = .pi + slot * 2 * .pi / 3
                let spot = conePos + SIMD2(cos(angle) * 0.4, sin(angle) * 0.4)
                let d = spot - m.pos
                if (d.x * d.x + d.y * d.y).squareRoot() > 0.02 { m.pos += d * min(1, dt * 4) }
                let toCone = conePos - m.pos
                m.smoothFacing = atan2(toCone.x, toCone.y)
            }
            if atCone {
                // Working the cone: welding, hammering, pushing and pulling, or bent over it.
                let tool = (m.toolSeed + Int(clock / 7)) % 4
                let cone = m.pyramids.last
                m.setTool([Minion.Tool.goggles, .hammer, .scanner, .flashlight][tool])
                switch tool {
                case 0:
                    tilt = 0.32
                    if m.weldLight == nil {
                        let l = SCNNode()
                        l.light = SCNLight(); l.light!.type = .omni; l.light!.color = NSColor(rgb: (1.0, 0.85, 0.55)); l.light!.attenuationEndDistance = 2.5
                        let spark = SCNNode(geometry: SCNPlane(width: 0.08, height: 0.08))
                        spark.geometry!.firstMaterial = flat(NSColor(rgb: (1.0, 0.95, 0.8)))
                        spark.constraints = [SCNBillboardConstraint()]
                        l.addChildNode(spark)
                        propRoot.addChildNode(l)
                        m.weldLight = l
                    }
                    if let l = m.weldLight, let cone {
                        l.position = v3(cone.position.x + CGFloat(station.offset.x), 0.25, cone.position.z + CGFloat(station.offset.y))
                        let on = Double.random(in: 0...1) < 0.55
                        l.light?.intensity = on ? Double.random(in: 300...1200) : 0
                        l.opacity = on ? 1 : 0
                    }
                case 1:
                    // Quick drop onto the peak, slower lift back: the grip pitches, the body only leans a little.
                    let phase = (t * 1.1).truncatingRemainder(dividingBy: 1)
                    let swing = phase < 0.25 ? pow(phase / 0.25, 2) : 1 - pow((phase - 0.25) / 0.75, 1.5)
                    m.hammerPivot?.eulerAngles.x = Minion.hammerRest + (Minion.hammerStrike - Minion.hammerRest) * swing
                    tilt = swing * 0.14
                    if swing > 0.97 && !m.hammerUp { m.hammerUp = true; drone.thud(); cone?.runAction(.sequence([.scale(to: 0.85, duration: 0.05), .scale(to: 1, duration: 0.25)])) }
                    if swing < 0.2 { m.hammerUp = false }
                case 2:
                    lean = sin(t * 2.5) * 0.05
                    tilt = 0.12 + sin(t * 2.5) * 0.08
                default:
                    // Inspecting the cone by torchlight: the beam wanders over it.
                    tilt = 0.18 + sin(t * 1.5) * 0.04
                    m.lightPivot?.eulerAngles = SCNVector3(0.35 + sin(t * 1.3) * 0.25, sin(t * 0.9) * 0.45, 0)
                }
            }
            if !atCone || (m.toolSeed + Int(clock / 7)) % 4 != 0, let l = m.weldLight { l.removeFromParentNode(); m.weldLight = nil }
            if !working { m.setTool(nil) }
            if m.place == .lounge, resting, let lounge = station.rooms["kind:lounge"] {
                let cx = Double(lounge.cells.map(\.x).reduce(0, +)) / Double(lounge.cells.count)
                let cy = Double(lounge.cells.map(\.y).reduce(0, +)) / Double(lounge.cells.count)
                let toTable = SIMD2(cx, cy) - m.pos
                m.smoothFacing = atan2(toTable.x, toTable.y)
                tilt = (m.couch != nil ? -0.22 : 0) + sin(t * 2.2) * 0.05   // sat back on a couch, or standing at the table
                roll = sin(t * 1.3) * 0.04
            }
            if working && !atCone {
                switch m.activity {
                case .testing, .running: m.setTool(.scanner); m.blinkScanner(Int(clock * 6) % 2 == 0)
                case .exploring: m.setTool(.flashlight)
                case .coding, .reading, .writing, .qa, .planning, .skill: m.setTool(.tablet)
                default: m.setTool(nil)
                }
                switch m.activity {
                case .coding: tilt = sin(t * 14) * 0.06                       // typing: quick nods
                case .exploring:                                              // reading code: the torch plays over the boxes
                    tilt = 0.12; spin = sin(t * 1.2) * 0.7
                    m.lightPivot?.eulerAngles = SCNVector3(0.3 + sin(t * 1.7) * 0.2, sin(t * 0.8) * 0.3, 0)
                case .writing: tilt = 0.2 + sin(t * 3) * 0.06                 // writing: head down over the clipboard, small nods
                case .thinking: tilt = -0.18; roll = sin(t * 1.4) * 0.14      // thinking: head back, slow sway
                case .planning: tilt = -0.12 + sin(t * 2) * 0.05              // planning: looking up
                case .reading: tilt = -0.18                                   // reading your message: head back
                case .testing: spin = sin(t * 1.6) * 0.6; tilt = 0.1         // testing: sweeping the scanner across
                case .running: tilt = sin(t * 22) * 0.04; roll = cos(t * 19) * 0.04   // running things: jittery
                case .shipping: roll = sin(t * 9) * 0.16                      // shipping: excited wiggle
                case .skill: tilt = 0.15; roll = sin(t * 3) * 0.05           // using a skill: heads-down on the tablet
                case .delegating: spin = sin(t * 4) * 0.3                     // delegating: glancing about
                case .qa:
                    // QA on the test deck: peering down at the staged boxes, a green tick popping up now and then.
                    tilt = 0.28 + sin(t * 1.2) * 0.08; spin = sin(t * 0.6) * 0.5
                    if Int(t * 2) % 9 == 0 && Int((t - dt) * 2) % 9 != 0 {
                        let tick = SCNNode(geometry: SCNSphere(radius: 0.07))
                        tick.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.9, 0.45)))
                        tick.position = v3(m.node.position.x, m.headHeight + 0.2, m.node.position.z)
                        propRoot.addChildNode(tick)
                        tick.runAction(.sequence([.group([.moveBy(x: 0, y: 0.5, z: 0, duration: 0.9), .sequence([.wait(duration: 0.5), .fadeOut(duration: 0.4)])]), .removeFromParentNode()]))
                        drone.ping(seed: m.id.hashValue)
                    }
                default: roll = sin(t * 5) * 0.07
                }
            }
            if m.bendUntil > clock { tilt = max(tilt, 0.5); roll = 0 }
            m.node.eulerAngles = SCNVector3(0, m.smoothFacing + spin, 0)
            m.tilt.eulerAngles = SCNVector3(tilt, 0, roll)
            if lean != 0 { m.node.position.x += CGFloat(sin(m.smoothFacing) * lean); m.node.position.z += CGFloat(cos(m.smoothFacing) * lean) }
        }

        updateBeams()
        let camYaw = Double(rig.eulerAngles.y)
        for (node, base) in floorLabels {
            let flipped = cos(base - camYaw) < 0
            let want = base + (flipped ? Double.pi : 0)
            if abs(Double(node.eulerAngles.y) - want) > 0.001 { node.eulerAngles.y = want }
        }
        for (key, label) in roomLabels where !undelivered.contains(key) {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let occupied = minions.values.contains { $0.station == parts[0] && $0.place == .room(parts[1]) && $0.state != .leaving }
            let want = occupied || hovered == "room:" + key ? 1.0 : 0.5
            label.opacity += (want - Double(label.opacity)) * min(1, dt * 6)
        }
        updateInfo()
        if clock - lastSavedView > 2 { lastSavedView = clock; saveView() }
    }

    /// Lightning from the monolith into each researching minion: a jagged bolt redrawn every frame.
    private func updateBeams() {
        var live = Set<String>()
        for m in minions.values where m.place == .core && m.path.isEmpty && m.state == .settled && m.opacity > 0.5 && m.activity != .sleeping {
            guard let station = fleet.stations[m.station] else { continue }
            live.insert(m.id)
            let mp = station.monolithPosition
            let from = SIMD3(station.offset.x + mp.x, 1.9, station.offset.y + mp.y)
            let to = SIMD3(station.offset.x + m.pos.x, m.headHeight * 0.8, station.offset.y + m.pos.y)
            let bolt = beams[m.id] ?? {
                let group = SCNNode()
                for _ in 0..<5 {
                    let n = SCNNode(geometry: SCNBox(width: 0.03, height: 0.03, length: 1, chamferRadius: 0))
                    n.geometry!.firstMaterial = flat(NSColor(rgb: (0.75, 0.88, 1.0)))
                    group.addChildNode(n)
                }
                beamRoot.addChildNode(group)
                beams[m.id] = group
                return group
            }()
            var points = [from]
            for k in 1..<5 {
                let t = Double(k) / 5
                let jitter = 0.14
                points.append(from + (to - from) * t + SIMD3(Double.random(in: -jitter...jitter), Double.random(in: -jitter...jitter), Double.random(in: -jitter...jitter)))
            }
            points.append(to)
            for (i, seg) in bolt.childNodes.enumerated() {
                let a = points[i], b = points[i + 1]
                let d = b - a
                let len = max(0.001, (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
                let mid = (a + b) / 2
                seg.position = v3(mid.x, mid.y, mid.z)
                seg.scale = SCNVector3(1, 1, len)
                seg.look(at: v3(b.x, b.y, b.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
            }
            bolt.opacity = Double.random(in: 0.35...1.0)
        }
        for (id, n) in beams where !live.contains(id) { n.removeFromParentNode(); beams[id] = nil }
    }

    /// How long an office is held for whoever last had it checked out, refreshed by their work.
    static let holdWindow: TimeInterval = 24 * 3600

    // MARK: kicking

    /// Offices thrown off the station, by room key: peers and GitHub may not put them back for a day.
    private var kicked: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: "kicked") as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue.filter { Date().timeIntervalSince($0.value) < StationController.holdWindow }, forKey: "kicked") }
    }

    private func isKicked(_ key: String) -> Bool { kicked[key].map { Date().timeIntervalSince($0) < StationController.holdWindow } ?? false }

    /// Right-click on an office that a peer or GitHub put here: offer to kick it.
    private func showContextMenu(for name: String?, event: NSEvent) {
        guard let name, name.hasPrefix("room:") || name.hasPrefix("box:") else { return }
        let key = String(name.dropFirst(name.hasPrefix("room:") ? 5 : 4))
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]], !room.key.hasPrefix("kind:") else { return }
        let menu = NSMenu()
        if room.worktree == nil {
            let item = NSMenuItem(title: "Kick \(room.name)", action: #selector(kickOffice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            menu.addItem(item)
        } else {
            menu.addItem(withTitle: "\(room.name) is your own checkout", action: nil, keyEquivalent: "")
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func kickOffice(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        enqueue { [self] in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]] else { return }
            var k = kicked; k[key] = Date(); kicked = k
            crewRoomInfo[key] = nil; crewBoxes[key] = nil; peerOffices[key] = nil; peerBoxes[key] = nil; pushedByPeer.remove(key)
            for m in minions.values where m.isCrew && m.home.key == room.key { m.activity = .sleeping; m.busy = false; send(m, to: .quarters) }
            archive(station: station, room: room, announce: false)
            logEvent("kicked \(room.name) off the station")
            rebuildStatic()
            for m in minions.values where m.errand == nil { send(m, to: m.place) }
        }
    }

    private var viewPinned = false   // set from the command line: never overridden by the remembered view
    func setView(yawDegrees: Double, pitchDegrees: Double, zoom: Double) {
        viewPinned = true
        enqueue { [self] in
            userYaw = yawDegrees * .pi / 180; userPitch = pitchDegrees * .pi / 180; userZoom = zoom
            rig.eulerAngles.y = .pi / 4 + userYaw; pitchNode.eulerAngles.x = userPitch
        }
    }

    /// Clicking a minion re-asks GitHub about its repo: its branch's PR, commits and releases.
    private func poke(minionId: String) {
        guard let m = minions[minionId], let station = fleet.stations[m.station] else { return }
        let room = station.rooms[m.home.key]
        let root = room?.repoRoot ?? repoRoots.first { $0.value.repo == m.home.repo }?.key
        guard let root else { return }
        github.invalidate(repoRoot: root)
        for r in station.rooms.values where r.repoRoot == root {
            if let b = r.branch { github.refresh(branch: b, repoRoot: root) }
            if let w = r.worktree { github.refreshCommits(worktree: w) }
        }
        github.refreshReleases(repoRoot: root)
        logEvent("asking github about \(m.home.repo)…")
        // A little hop so the click feels acknowledged.
        m.node.runAction(.sequence([.moveBy(x: 0, y: 0.25, z: 0, duration: 0.12), .moveBy(x: 0, y: -0.25, z: 0, duration: 0.12)]))
    }

    /// Settings changed: rebuild the fleet from scratch on the next scan.
    func applyConfigChange() {
        applySharing()
        enqueue { [self] in
            for m in Array(minions.values) { despawn(m) }
            fleet.removeAllStations()
            repoRoots = [:]
            crewLoaded = false
            didLoadLayout = false
            rebuildStatic()
            rescan()
        }
    }

    var knownRepos: [String] { fleet.repoColors.keys.sorted() }

    /// A line in the station log from outside the scene, such as an update notice.
    func announce(_ text: String) {
        enqueue { [self] in logEvent(text); ringBell(seed: text.hashValue) }
    }

    /// Re-asks GitHub about every office, branch and release right now.
    func refreshGitHub() {
        enqueue { [self] in
            github.invalidate()
            for station in fleet.stations.values {
                for room in station.rooms.values {
                    if let b = room.branch, let r = room.repoRoot { github.refresh(branch: b, repoRoot: r) }
                    if let w = room.worktree { github.refreshCommits(worktree: w) }
                }
            }
            github.intervalMinutes = ConfigStore.shared.current.githubMinutes
        for (root, info) in repoRoots {
            github.refreshReleases(repoRoot: root)
            if info.station == "work" { github.refreshFeed(repoRoot: root); github.refreshOpenPRs(repoRoot: root) }
        }
            logEvent("asking github…")
        }
    }

    func resetView() {
        enqueue { [self] in userZoom = 1; userYaw = 0; userPitch = -.pi / 6; userPan = .zero; focused = nil }
    }

    /// Slides the view by a screen offset: dx to the right, dy down (as drags and scrolls report it).
    private func pan(byPixels dx: Double, _ dy: Double) {
        focused = nil
        userDriving = 0.5
        let yaw = Double.pi / 4 + userYaw
        let unitsPerPixel = 2 * cameraNode.camera!.orthographicScale / Double(max(1, viewSize.height))
        let right = SIMD2(cos(yaw), -sin(yaw))
        let forward = SIMD2(-sin(yaw), -cos(yaw))
        userPan -= (right * dx - forward * dy) * unitsPerPixel
    }

    /// The point on the floor plane under a view location, in world x/z.
    private func groundPoint(at p: NSPoint) -> SIMD2<Double>? {
        let near = view.unprojectPoint(SCNVector3(p.x, p.y, 0))
        let far = view.unprojectPoint(SCNVector3(p.x, p.y, 1))
        let dy = Double(far.y - near.y)
        guard abs(dy) > 1e-6 else { return nil }
        let t = -Double(near.y) / dy
        return SIMD2(Double(near.x) + Double(far.x - near.x) * t, Double(near.z) + Double(far.z - near.z) * t)
    }

    /// Orthographic half-height that fits a footprint of the given span at the current aspect.
    /// Where the default isometric camera should look to centre these stations, and the half-extent
    /// they cover on screen (in ground units across, and along the view before the tilt foreshortens it).
    /// Each station's own footprint is projected, so an L-shaped fleet isn't framed by its empty corner.
    private func frame(for stations: [Station]) -> (focus: SIMD2<Double>, half: SIMD2<Double>) {
        let yaw = Double.pi / 4
        var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
        for st in stations {
            let b = st.bounds
            for (x, z) in [(Double(b.min.x), Double(b.min.y)), (Double(b.max.x) + 1, Double(b.min.y)),
                           (Double(b.min.x), Double(b.max.y) + 1), (Double(b.max.x) + 1, Double(b.max.y) + 1)] {
                let wx = x + st.offset.x, wz = z + st.offset.y
                let u = wx * cos(yaw) - wz * sin(yaw), v = wx * sin(yaw) + wz * cos(yaw)
                lo = pointwiseMin(lo, SIMD2(u, v)); hi = pointwiseMax(hi, SIMD2(u, v))
            }
        }
        guard lo.x.isFinite else { return (SIMD2(0, 0), SIMD2(6, 6)) }
        let c = (lo + hi) / 2
        return (SIMD2(c.x * cos(yaw) + c.y * sin(yaw), -c.x * sin(yaw) + c.y * cos(yaw)), (hi - lo) / 2)
    }

    /// Orthographic half-height that fits a projected half-extent at the default tilt.
    private func fitScale(half: SIMD2<Double>) -> Double {
        let aspect = max(0.6, Double(viewSize.width / max(1, viewSize.height)))
        let pitch = -Double.pi / 6
        return max(half.y * abs(sin(pitch)) + 3.0, (half.x + 1.5) / aspect)
    }

    /// Pans and zooms onto one station, or back to the whole fleet.
    func focus(on stationName: String?) {
        enqueue { [self] in focusNow(on: stationName) }
    }

    /// Focuses the Nth station: your own in fleet order, then peers' as they sit in the void.
    func focus(onIndex i: Int) {
        enqueue { [self] in
            let names = fleet.ordered.map(\.name)
            guard names.indices.contains(i) else { return }
            focusNow(on: names[i])
        }
    }

    private func focusNow(on stationName: String?) {
        focused = stationName
        guard let name = stationName, let station = fleet.stations[name] else {
            userPan = .zero; userZoom = 1; userZoomChanged = true; return
        }
        let (center, half) = frame(for: [station])
        userPan = center - targetFocus
        userZoom = min(6, max(0.4, fitScale(half: targetHalf) / fitScale(half: half)))
        userZoomChanged = true
    }

    private func saveView() {
        let d = UserDefaults.standard
        d.set(userYaw, forKey: "view.yaw"); d.set(userPitch, forKey: "view.pitch"); d.set(userZoom, forKey: "view.zoom")
        d.set(userPan.x, forKey: "view.panx"); d.set(userPan.y, forKey: "view.pany")
        d.set(focused ?? "", forKey: "view.focus")
    }

    private func restoreView() {
        let d = UserDefaults.standard
        guard d.object(forKey: "view.zoom") != nil else { return }
        if d.integer(forKey: "view.layout") != 21 {   // the fleet was laid out differently: forget the old pan
            d.set(21, forKey: "view.layout"); d.removeObject(forKey: "view.panx"); d.removeObject(forKey: "view.pany")
        }
        userYaw = d.double(forKey: "view.yaw"); userPitch = d.double(forKey: "view.pitch")
        rig.eulerAngles.y = .pi / 4 + userYaw; pitchNode.eulerAngles.x = userPitch
        let f = d.string(forKey: "view.focus") ?? ""
        if !f.isEmpty, fleet.stations[f] != nil {
            focusNow(on: f)
        } else {
            userZoom = d.double(forKey: "view.zoom"); userPan = SIMD2(d.double(forKey: "view.panx"), d.double(forKey: "view.pany"))
            // A remembered pan from an older layout can point at empty space: drop it if it left the fleet.
            let b = fleet.worldBounds
            let p = targetFocus + userPan
            if p.x < b.min.x - 4 || p.x > b.max.x + 4 || p.y < b.min.y - 4 || p.y > b.max.y + 4 { userPan = .zero }
        }
        cameraNode.camera!.orthographicScale = fitScale(half: targetHalf) / userZoom
        rig.position.x = targetFocus.x + userPan.x; rig.position.z = targetFocus.y + userPan.y
    }

    /// Renders the current frame to a PNG, used for self-checks.
    func snapshot(to path: String) {
        let image = view.snapshot()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
