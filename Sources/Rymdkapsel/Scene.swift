import AppKit
import SceneKit
import SpriteKit

extension NSColor {
    convenience init(rgb: (Double, Double, Double), alpha: CGFloat = 1) {
        self.init(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
    }
    convenience init(_ c: RGB) { self.init(rgb: c.tuple) }
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

private func v3(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 { SCNVector3(x, y, z) }

private func flat(_ color: NSColor) -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = color
    m.lightingModel = .constant
    return m
}

private func lit(_ color: NSColor) -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = color
    m.lightingModel = .lambert
    return m
}

/// Text laid flat on the floor, wrapped to a width in world units, pivoted on its centre.
private func floorText(_ text: String, color: NSColor, size: Double, maxWidth: Double, lines: Int) -> (node: SCNNode, width: Double, height: Double) {
    let t = SCNText(string: text, extrusionDepth: 0)
    t.font = NSFont(name: "HelveticaNeue-Medium", size: 1) ?? NSFont.systemFont(ofSize: 1, weight: .medium)
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

/// SCNView that reports hovers, double-clicks and trackpad gestures.
final class StationView: SCNView {
    var onHover: ((SCNNode?) -> Void)?
    var onDoubleClick: ((SCNNode?) -> Void)?
    var onZoom: ((Double) -> Void)?
    var onRotate: ((Double) -> Void)?
    var onPan: ((Double, Double) -> Void)?
    var onTilt: ((Double) -> Void)?
    var onKey: ((String) -> Bool)?
    var onClick: ((SCNNode?) -> Void)?
    private var tracking: NSTrackingArea?
    private var downPoint = NSPoint.zero

    override func keyDown(with event: NSEvent) {
        if let chars = event.charactersIgnoringModifiers, onKey?(chars) == true { return }
        super.keyDown(with: event)
    }
    private var dragAllowed = false

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func magnify(with event: NSEvent) { onZoom?(1 + event.magnification) }
    override func rotate(with event: NSEvent) { onRotate?(Double(event.rotation) * .pi / 180) }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) { onZoom?(1 - Double(event.scrollingDeltaY) * 0.01) }
        else { onTilt?(Double(event.scrollingDeltaY)) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragAllowed else { return }
        onPan?(Double(event.deltaX), Double(event.deltaY))
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
    enum Errand { case fetch(room: String), carry(room: String) }

    let id: String
    var station: String
    var home: Home
    var state: State = .arriving
    var busy = false
    var activity: Activity = .waiting
    var place: Place = .core
    var errand: Errand?
    var carried: SCNNode?
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
    private let bodyHeight: Double
    private let bodyDepth: Double
    var facing = 0.0
    var bed: Int?
    var pos: SIMD2<Double>
    var path: [Cell] = []
    var nextWanderAt = 0.0
    let bobPhase = Double.random(in: 0..<6.28)
    var opacity = 0.0

    init(id: String, station: String, home: Home, cwd: String, toolCount: Int, isSubagent: Bool, start: Cell) {
        self.id = id; self.station = station; self.home = home; self.cwd = cwd; self.toolCount = toolCount; self.isSubagent = isSubagent
        pos = SIMD2(Double(start.x), Double(start.y))

        let h = isSubagent ? 0.34 : 0.5
        let w = isSubagent ? 0.16 : 0.22
        let d = isSubagent ? 0.08 : 0.11
        let body = SCNNode(geometry: SCNBox(width: w, height: h, length: d, chamferRadius: 0.01))
        body.geometry!.firstMaterial = lit(Palette.minion)
        body.position = v3(0, h / 2, 0)
        let visor = SCNNode(geometry: SCNBox(width: w * 0.5, height: h * 0.1, length: 0.012, chamferRadius: 0))
        visor.geometry!.firstMaterial = flat(Palette.core)
        visor.position = v3(0, h * 0.3, d / 2 + 0.004)
        body.addChildNode(visor)
        node.addChildNode(body)
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

    /// Tip over onto the back in the dorm, or stand back up.
    func setSleeping(_ asleep: Bool) {
        let target = asleep ? -Double.pi / 2 : 0
        guard abs(Double(body.eulerAngles.x) - target) > 0.001 else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.6
        body.eulerAngles.x = target
        body.position = asleep ? v3(0, bodyDepth / 2, 0) : v3(0, bodyHeight / 2, 0)
        SCNTransaction.commit()
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
    private let scanQueue = DispatchQueue(label: "rymdkapsel.scan")

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
    private var roomLabels: [String: SCNNode] = [:]
    private var floorLabels: [(node: SCNNode, baseYaw: Double)] = []
    /// Rooms whose office has not been delivered yet, keyed by "station|room".
    private var undelivered: Set<String> = []
    private var boxes: [String: SCNNode] = [:]
    private var outlines: [String: SCNNode] = [:]
    private let beamRoot = SCNNode()
    private var beams: [String: SCNNode] = [:]
    private let infoLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    private let infoBackground = SKShapeNode()
    private let statusLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    private var legendNodes: [SKNode] = []
    private var jobNodes: [SKNode] = []
    private var hudClock = 0.0
    private var eventLabels: [(SKLabelNode, Double)] = []
    private var hovered: String?
    private var lastTick = 0.0
    private var clock = 0.0
    private var targetSpan = 12.0
    private var targetFocus = SIMD2<Double>(0, 0)
    private var userZoom = 1.0
    private var userZoomChanged = false
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

    static let activeWindow: TimeInterval = 45 * 60
    static let busyWindow: TimeInterval = 90
    static let replyWindow: TimeInterval = 20
    static let sleepWindow: TimeInterval = 5 * 60
    static let subagentWindow: TimeInterval = 3 * 60
    static let roomsWindow: TimeInterval = 12 * 3600

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
            guard let n = node?.name, n.hasPrefix("box:") else { return }
            self?.enqueue { self?.open(named: n) }
        }
        view.onZoom = { [weak self] f in self?.enqueue { guard let self else { return }; self.userZoom = min(6, max(0.4, self.userZoom * f)); self.userZoomChanged = true } }
        view.onRotate = { [weak self] r in self?.enqueue { self?.userYaw -= r } }
        view.onTilt = { [weak self] dy in
            self?.enqueue { guard let self else { return }; self.userPitch = min(-0.15, max(-Double.pi / 2 + 0.05, self.userPitch - dy * 0.004)) }
        }
        view.onPan = { [weak self] dx, dy in
            self?.enqueue {
                guard let self else { return }
                self.focused = nil
                let yaw = Double.pi / 4 + self.userYaw
                let unitsPerPixel = 2 * self.cameraNode.camera!.orthographicScale / Double(max(1, self.viewSize.height))
                let right = SIMD2(cos(yaw), -sin(yaw))
                let forward = SIMD2(-sin(yaw), -cos(yaw))
                self.userPan -= (right * dx - forward * dy) * unitsPerPixel
            }
        }
        github.onUpdate = { [weak self] in self?.enqueue { self?.rebuildMarkers() } }
        view.onKey = { [weak self] key in
            guard let self else { return false }
            switch key {
            case "1": focus(on: "work")
            case "2": focus(on: "private")
            case "3": focus(on: nil)
            case "r": resetView()
            default: return false
            }
            return true
        }
        view.delegate = self

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
        for n in [staticRoot, labelRoot, minionRoot, propRoot, markerRoot, debrisRoot, beamRoot] { scene.rootNode.addChildNode(n) }

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
        if station.coreCells.contains(c) || station.isCorridor(c) { return "corridor" }
        return station.room(at: c)?.key
    }

    @discardableResult
    private func addTile(station: Station, cell: Cell, owner key: String, color: NSColor, name: String) -> SCNNode {
        let g = 0.075
        let l = owner(station, Cell(x: cell.x - 1, y: cell.y)) == key ? 0 : g
        let r = owner(station, Cell(x: cell.x + 1, y: cell.y)) == key ? 0 : g
        let b = owner(station, Cell(x: cell.x, y: cell.y - 1)) == key ? 0 : g
        let f = owner(station, Cell(x: cell.x, y: cell.y + 1)) == key ? 0 : g
        let x0 = Double(cell.x) - 0.5 + l, x1 = Double(cell.x) + 0.5 - r
        let z0 = Double(cell.y) - 0.5 + b, z1 = Double(cell.y) + 0.5 - f
        let plane = SCNPlane(width: x1 - x0, height: z1 - z0)
        plane.firstMaterial = flat(color)
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = v3(station.offset.x + (x0 + x1) / 2, 0, station.offset.y + (z0 + z1) / 2)
        n.name = name
        staticRoot.addChildNode(n)
        return n
    }

    private func roomKey(_ station: Station, _ room: Room) -> String { "\(station.name)|\(room.key)" }

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

        for station in fleet.stations.values {
            for c in station.corridorCells + station.coreCells {
                addTile(station: station, cell: c, owner: "corridor", color: Palette.corridor, name: "station:" + station.name)
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
                let b = SCNNode(geometry: SCNPlane(width: 0.34, height: 0.72))
                b.geometry!.firstMaterial = flat(NSColor(Colors.bed))
                b.eulerAngles.x = -.pi / 2
                b.position = v3(station.offset.x + bed.pos.x, 0.005, station.offset.y + bed.pos.y)
                b.name = "room:\(station.name)|kind:quarters"
                staticRoot.addChildNode(b)
            }

            for room in station.rooms.values {
                let key = roomKey(station, room)
                var tiles: [SCNNode] = []
                for c in room.cells {
                    let t = addTile(station: station, cell: c, owner: room.key, color: NSColor(room.color), name: "room:" + key)
                    if undelivered.contains(key) { t.opacity = 0 }
                    tiles.append(t)
                }
                roomTiles[key] = tiles
                outlines.removeValue(forKey: key)?.removeFromParentNode()
                if undelivered.contains(key) {
                    let o = outline(station: station, room: room)
                    propRoot.addChildNode(o)
                    outlines[key] = o
                }
            }
        }
        rebuildLabels()
        rebuildMarkers()

        let b = fleet.worldBounds
        targetFocus = (b.min + b.max) / 2
        targetSpan = (b.max.x - b.min.x) + (b.max.y - b.min.y) + 3
        if let f = focused { focusNow(on: f) }
        fleet.save()
    }

    private static func displayName(_ room: Room) -> String {
        switch room.key {
        case "kind:hangar": return "hangar"
        case "kind:quarters": return "sleeping"
        default: return room.name
        }
    }

    /// Lays each room's name flat beside it on the side with free floor, or cut into the tile when boxed in.
    private func rebuildLabels() {
        labelRoot.childNodes.forEach { $0.removeFromParentNode() }
        roomLabels = [:]
        floorLabels = []
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

            let occupied: (Cell) -> Bool = { c in
                station.coreCells.contains(c) || station.isCorridor(c) || station.room(at: c) != nil
            }
            var placed: [(min: SIMD2<Double>, max: SIMD2<Double>)] = []
            func collides(_ lo: SIMD2<Double>, _ hi: SIMD2<Double>) -> Bool {
                for x in Int((lo.x + 0.5).rounded(.down))...Int((hi.x - 0.5).rounded(.up)) {
                    for y in Int((lo.y + 0.5).rounded(.down))...Int((hi.y - 0.5).rounded(.up)) where occupied(Cell(x: x, y: y)) {
                        return true
                    }
                }
                return placed.contains { !(hi.x <= $0.min.x || lo.x >= $0.max.x || hi.y <= $0.min.y || lo.y >= $0.max.y) }
            }
            enum Side { case south, north, east, west }
            for room in station.rooms.values.sorted(by: { $0.key < $1.key }) {
                let text = StationController.displayName(room)
                let size = room.key.hasPrefix("kind:") ? 0.38 : 0.46
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
                    // Boxed in: cut the name into the tile itself.
                    let horizontal = width >= depth
                    let along = (horizontal ? width : depth) - 0.3
                    let lines = max(1, min(2, Int((Double(text.count) * charW * 0.85 / along).rounded(.up))))
                    let label = floorText(text, color: .black, size: size * 0.85, maxWidth: along, lines: lines)
                    let maxYRow = room.cells.map(\.y).max()!
                    let anchor = room.cells.filter { $0.y == maxYRow }.min { $0.x < $1.x }!
                    let center = horizontal
                        ? SIMD2(ox + Double(anchor.x) - 0.35 + label.width / 2, oz + Double(anchor.y) + 0.35 - label.height / 2)
                        : SIMD2(ox + Double(anchor.x) - 0.35 + label.height / 2, oz + Double(anchor.y) + 0.35 - label.width / 2)
                    label.node.position.y = 0.02
                    add(label.node, yaw: horizontal ? 0 : .pi / 2, center: center)
                    node = label.node
                }
                guard let node else { continue }
                node.name = "room:" + key
                if undelivered.contains(key) { node.opacity = 0 }
                roomLabels[key] = node
            }
        }
    }

    /// Grey boxes pile up in an office as commits land; the pull request state colours them.
    private func rebuildMarkers() {
        markerRoot.childNodes.forEach { $0.removeFromParentNode() }
        for station in fleet.stations.values {
            for room in station.rooms.values where room.branch != nil {
                let key = roomKey(station, room)
                let pr = room.repoRoot.flatMap { github.pull(branch: room.branch!, repoRoot: $0) }
                let ahead = room.worktree.flatMap { github.commitsAhead(worktree: $0) } ?? 0
                let count = min(12, 1 + ahead)
                let color: NSColor
                switch (pr?.state, pr?.reviewDecision, pr?.isDraft) {
                case (nil, _, _): color = NSColor(rgb: (0.55, 0.55, 0.58))
                case ("MERGED", _, _): color = NSColor(rgb: (0.6, 0.4, 0.9))
                case ("CLOSED", _, _): color = NSColor(rgb: (0.35, 0.35, 0.4))
                case (_, "APPROVED", _): color = NSColor(rgb: (0.5, 0.95, 0.55))
                case (_, "CHANGES_REQUESTED", _): color = NSColor(rgb: (0.9, 0.3, 0.3))
                case (_, _, true): color = NSColor(rgb: (0.6, 0.65, 0.7))
                default: color = NSColor(rgb: (0.38, 0.78, 0.45))
                }
                let s = 0.26
                let slots: [SIMD2<Double>] = [SIMD2(-0.24, -0.24), SIMD2(0.24, -0.24), SIMD2(-0.24, 0.24), SIMD2(0.24, 0.24)]
                let cells = room.cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                for i in 0..<count {
                    let cell = cells[(i / 4) % cells.count]
                    let o = slots[i % 4]
                    let n = SCNNode(geometry: SCNBox(width: s, height: s, length: s, chamferRadius: 0))
                    n.geometry!.firstMaterial = lit(color)
                    n.position = v3(station.offset.x + Double(cell.x) + o.x, s / 2, station.offset.y + Double(cell.y) + o.y)
                    n.name = "box:" + key
                    if undelivered.contains(key) { n.opacity = 0 }
                    markerRoot.addChildNode(n)
                }
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
        infoBackground.fillColor = Palette.void.withAlphaComponent(0.85)
        infoBackground.strokeColor = Palette.dim.withAlphaComponent(0.5)
        infoBackground.lineWidth = 1
        hud.addChild(infoBackground)
        hud.addChild(infoLabel)
        statusLabel.fontSize = 10
        statusLabel.fontColor = Palette.dim
        statusLabel.horizontalAlignmentMode = .right
        statusLabel.verticalAlignmentMode = .bottom
        hud.addChild(statusLabel)
    }

    /// Top: repos in their colours with counts. Bottom: jobs with one tiny minion per worker, like the game.
    private func layoutLegend(active: [Minion], busy: Int, waiting: Int, asleep: Int) {
        legendNodes.forEach { $0.removeFromParent() }; legendNodes = []
        jobNodes.forEach { $0.removeFromParent() }; jobNodes = []
        let repos = fleet.repoColors.keys.sorted { fleet.repoColors[$0]! < fleet.repoColors[$1]! }
        guard !repos.isEmpty else { return }
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
                let r = SKShapeNode(rectOf: CGSize(width: 4, height: 9))
                r.fillColor = Palette.minion; r.strokeColor = .clear
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
        if let branch = room.branch, let root = room.repoRoot {
            parts.append("⎇ " + branch)
            if let pr = github.pull(branch: branch, repoRoot: root) { parts.append(pr.summary); parts.append(pr.title) }
            if let w = room.worktree, let n = github.commitsAhead(worktree: w) { parts.append("\(n) commits") }
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
        if clock - hudClock > 0.5 { hudClock = clock; layoutLegend(active: active, busy: busy, waiting: waiting, asleep: asleep) }

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
                infoBackground.path = CGPath(roundedRect: f, cornerWidth: 4, cornerHeight: 4, transform: nil)
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
        } else if h.hasPrefix("station:") {
            infoLabel.text = String(h.dropFirst(8)) + " · the monolith: web research and subagents"
        } else {
            infoLabel.text = ""
        }
    }

    private func open(named raw: String?) {
        guard let raw, raw.hasPrefix("room:") || raw.hasPrefix("box:") else { return }
        let name = raw.hasPrefix("box:") ? "room:" + raw.dropFirst(4) : raw
        let parts = name.dropFirst(5).split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]],
              let branch = room.branch, let root = room.repoRoot else { return }
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
        let start = s.isSubagent ? (st?.coreCenter ?? Cell(x: 0, y: 0)) : (st?.cells(of: .quarters).randomElement() ?? Cell(x: 0, y: 0))
        let m = Minion(id: s.id, station: station, home: home, cwd: s.cwd, toolCount: s.toolCount, isSubagent: s.isSubagent, start: start)
        m.markers = s.eventMarkers
        minionRoot.addChildNode(m.node)
        minions[s.id] = m
        return m
    }

    private func despawn(_ m: Minion) {
        if let key = carriedRoom(of: m) { reveal(key) }
        m.carried?.removeFromParentNode()
        m.pyramids.forEach { $0.removeFromParentNode() }
        m.node.removeFromParentNode()
        minions[m.id] = nil
    }

    private func carriedRoom(of m: Minion) -> String? {
        switch m.errand {
        case .fetch(let r), .carry(let r): return "\(m.station)|\(r)"
        case nil: return nil
        }
    }

    private func send(_ m: Minion, to place: Place) {
        guard let station = fleet.stations[m.station] else { return }
        if place != .quarters { m.bed = nil }
        if place == .quarters, m.bed == nil {
            let used = Set(minions.values.filter { $0.station == m.station }.compactMap(\.bed))
            m.bed = station.beds.indices.first { !used.contains($0) }
        }
        let cells = station.cells(of: place)
        let target: Cell
        if let b = m.bed, b < station.beds.count { target = station.beds[b].cell }
        else if let t = cells.randomElement() { target = t }
        else { return }
        m.place = place
        m.path = station.path(from: m.cell, to: target)
        m.nextWanderAt = clock + Double.random(in: 1...3)
    }

    private func walk(_ m: Minion, to cell: Cell) {
        guard let station = fleet.stations[m.station] else { return }
        m.path = station.path(from: m.cell, to: cell)
    }

    /// Drops a box of the repo colour into the hangar and sends the minion to fetch it.
    private func startDelivery(_ m: Minion, roomKey: String) {
        guard let station = fleet.stations[m.station], let room = station.rooms[roomKey],
              let hangarCell = station.cells(of: .hangar).randomElement() else { return }
        let key = "\(station.name)|\(roomKey)"
        let s = 0.3
        let box = SCNNode(geometry: SCNBox(width: s, height: s, length: s, chamferRadius: 0))
        box.geometry!.firstMaterial = lit(NSColor(room.color))
        box.position = v3(station.offset.x + Double(hangarCell.x), 4, station.offset.y + Double(hangarCell.y))
        box.name = "room:" + key
        propRoot.addChildNode(box)
        box.runAction(.move(to: v3(station.offset.x + Double(hangarCell.x), s / 2, station.offset.y + Double(hangarCell.y)), duration: 0.7))
        boxes[key] = box
        m.errand = .fetch(room: roomKey)
        m.place = .hangar
        walk(m, to: hangarCell)
    }

    private func reveal(_ key: String) {
        guard undelivered.remove(key) != nil else { return }
        boxes.removeValue(forKey: key)?.removeFromParentNode()
        if let o = outlines.removeValue(forKey: key) { o.runAction(.sequence([.fadeOut(duration: 0.4), .removeFromParentNode()])) }
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

    private func addPyramid(for m: Minion) {
        guard let station = fleet.stations[m.station], case .room(let key) = Place.forActivity(.reading, home: m.home.key, isSubagent: false),
              let cell = station.cells(of: .room(key)).randomElement() else { return }
        if m.pyramids.count >= 3, let old = m.pyramids.first {
            old.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]))
            m.pyramids.removeFirst()
        }
        let n = SCNNode(geometry: SCNPyramid(width: 0.26, height: 0.26, length: 0.26))
        n.geometry!.firstMaterial = lit(Palette.pyramid)
        let ox = Double.random(in: -0.25...0.25), oz = Double.random(in: -0.25...0.25)
        n.position = v3(station.offset.x + Double(cell.x) + ox, 0, station.offset.y + Double(cell.y) + oz)
        n.scale = SCNVector3(0.01, 0.01, 0.01)
        n.runAction(.scale(to: 1, duration: 0.25))
        propRoot.addChildNode(n)
        m.pyramids.append(n)
        m.pyramidCell = cell
        if m.errand == nil { m.place = .room(key); walk(m, to: cell) }
    }

    private func clearPyramids(_ m: Minion) {
        for p in m.pyramids { p.runAction(.sequence([.fadeOut(duration: 0.8), .removeFromParentNode()])) }
        m.pyramids = []
        m.pyramidCell = nil
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
            let result = scanner.scan(roomsWithin: StationController.roomsWindow)
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
        var liveRooms: [String: Set<String>] = [:]
        var newRooms: [String: String] = [:]   // session id -> room key
        for s in result.sessions where s.cwdExists {
            let stationName = Fleet.stationName(for: s.cwd)
            let station = fleet.station(stationName)
            let home = Home.from(repo: s.repo, branch: s.branch, cwd: s.cwd)
            if station.ensureRoom(key: home.key, name: home.name, repo: home.repo, color: fleet.color(forRepo: home.repo), lastActive: s.lastModified) {
                changed = true
                if !firstRun {
                    undelivered.insert("\(stationName)|\(home.key)")
                    newRooms[s.id] = home.key
                }
            }
            if let room = station.rooms[home.key] {
                if home.key.hasPrefix("task:") { room.branch = s.branch; room.repoRoot = s.repoRoot; room.worktree = s.cwd }
                if let b = room.branch, let r = room.repoRoot { github.refresh(branch: b, repoRoot: r) }
                if let w = room.worktree { github.refreshCommits(worktree: w) }
            }
            liveRooms[stationName, default: []].insert(home.key)
        }
        for station in fleet.stations.values {
            for room in Array(station.rooms.values) where !room.key.hasPrefix("kind:") {
                if liveRooms[station.name]?.contains(room.key) != true || now.timeIntervalSince(room.lastActive) > StationController.roomsWindow {
                    station.removeRoom(key: room.key); changed = true
                    undelivered.remove("\(station.name)|\(room.key)")
                    if !firstRun { logEvent("archived: \(room.name)") }
                }
            }
        }

        var seen = Set<String>()
        for s in result.sessions where now.timeIntervalSince(s.lastModified) < (s.isSubagent ? StationController.subagentWindow : StationController.activeWindow) {
            seen.insert(s.id)
            let stationName = Fleet.stationName(for: s.cwd)
            let home = Home.from(repo: s.repo, branch: s.branch, cwd: s.cwd)
            let isNew = minions[s.id] == nil
            let m = minions[s.id] ?? spawnMinion(s, station: stationName, home: home)
            if m.station != stationName { despawn(m); continue }
            m.home = home
            let idle = now.timeIntervalSince(s.lastModified)
            m.busy = idle < StationController.busyWindow
            if idle > StationController.sleepWindow || !s.cwdExists {
                m.activity = .sleeping
            } else if idle > StationController.replyWindow, s.activity == .writing || s.activity == .waiting {
                m.activity = .waiting
            } else if !m.busy {
                m.activity = .waiting
            } else {
                m.activity = s.activity
            }
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
                    case .prompt: if !m.isSubagent { addPyramid(for: m) }
                    case .tool: continue
                    }
                    ringBell(seed: s.id.hashValue &+ event.rawValue.hashValue)
                }
            }
            m.markers = s.eventMarkers
            m.toolCount = s.toolCount
            if m.activity == .waiting || m.activity == .sleeping { clearPyramids(m) }

            if let key = newRooms[s.id], m.errand == nil, !m.isSubagent {
                startDelivery(m, roomKey: key)
            } else if m.errand == nil {
                let place = Place.forActivity(m.activity, home: home.key, isSubagent: m.isSubagent)
                if place != m.place || isNew { send(m, to: place) }
            }
            if m.state == .leaving { m.state = .arriving; send(m, to: m.place) }
        }
        for m in minions.values where !seen.contains(m.id) && m.state != .leaving {
            m.state = .leaving
            if let key = carriedRoom(of: m) { reveal(key); m.errand = nil; m.carried?.removeFromParentNode(); m.carried = nil }
            clearPyramids(m)
            if m.isSubagent { m.path = [] } else { send(m, to: .quarters) }
        }
        // Offices that appeared without a minion to deliver them just show up.
        let pending = Set(minions.values.compactMap { m in carriedRoom(of: m) ?? newRooms[m.id].map { "\(m.station)|\($0)" } })
        for key in undelivered where !pending.contains(key) {
            changed = true
            undelivered.remove(key)
        }
        if changed {
            rebuildStatic()
            if firstRun { restoreView() }
            for m in minions.values where m.errand == nil { send(m, to: m.place) }
            for m in minions.values {
                if case .fetch(let r) = m.errand, let station = fleet.stations[m.station], let c = station.cells(of: .hangar).randomElement() {
                    boxes["\(m.station)|\(r)"]?.position = v3(station.offset.x + Double(c.x), 0.15, station.offset.y + Double(c.y))
                    walk(m, to: c)
                } else if case .carry(let r) = m.errand, let station = fleet.stations[m.station], let door = station.doorCell(of: r) {
                    walk(m, to: door)
                }
            }
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
            let stationName = Fleet.stationName(for: a.1)
            let station = fleet.station(stationName)
            let h = Home.from(repo: a.0, branch: a.3, cwd: a.1)
            station.ensureRoom(key: h.key, name: h.name, repo: h.repo, color: fleet.color(forRepo: h.repo), lastActive: Date())
            let s = SessionInfo(id: "demo-\(i)", cwd: a.1, repo: a.0, repoRoot: nil, lastModified: Date(), activity: a.2, area: nil,
                                title: nil, branch: a.3, toolCount: 0, isSubagent: i == 2, cwdExists: true, eventMarkers: [:])
            let m = spawnMinion(s, station: stationName, home: h)
            m.busy = a.2 != .waiting && a.2 != .sleeping
            m.activity = a.2
            m.branch = a.3
            m.place = Place.forActivity(a.2, home: h.key, isSubagent: m.isSubagent)
        }
        rebuildStatic()
        for m in minions.values { send(m, to: m.place) }
        logEvent("#450 opened a pull request")
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
            if clock > 6, !minions.keys.contains("demo-new") {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let cwd = "\(home)/conductor/workspaces/tattoodo-web/lagos"
                let station = fleet.station("work")
                let h = Home.from(repo: "tattoodo-web", branch: "gh-470/artist-search", cwd: cwd)
                station.ensureRoom(key: h.key, name: h.name, repo: h.repo, color: fleet.color(forRepo: h.repo), lastActive: Date())
                undelivered.insert("work|\(h.key)")
                rebuildStatic()
                for mm in minions.values where mm.errand == nil { send(mm, to: mm.place) }
                let s = SessionInfo(id: "demo-new", cwd: cwd, repo: "tattoodo-web", repoRoot: nil, lastModified: Date(), activity: .coding("app"), area: nil,
                                    title: nil, branch: "gh-470/artist-search", toolCount: 0, isSubagent: false, cwdExists: true, eventMarkers: [:])
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
        if hud.size != viewSize { hud.size = viewSize }

        let k = 1 - exp(-dt * 2)
        let focus = targetFocus + userPan
        rig.position.x += (focus.x - Double(rig.position.x)) * k
        rig.position.z += (focus.y - Double(rig.position.z)) * k
        let ky = 1 - exp(-dt * 10)
        rig.eulerAngles.y += (Double.pi / 4 + userYaw - Double(rig.eulerAngles.y)) * ky
        pitchNode.eulerAngles.x += (userPitch - Double(pitchNode.eulerAngles.x)) * ky
        let wantScale = fitScale(span: targetSpan) / userZoom
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
            let restless = m.activity == .waiting && m.errand == nil
            let speed = m.busy ? 2.4 : (restless ? 1.1 : 1.4)
            if let next = m.path.first {
                let target = SIMD2(Double(next.x), Double(next.y))
                let d = target - m.pos
                let dist = (d.x * d.x + d.y * d.y).squareRoot()
                let step = speed * dt
                if dist <= step { m.pos = target; m.path.removeFirst() } else { m.pos += d / dist * step }
                m.facing = atan2(d.x, d.y)
            } else {
                switch m.errand {
                case .fetch(let r):
                    let key = "\(m.station)|\(r)"
                    if let box = boxes[key] {
                        box.removeAllActions()
                        box.removeFromParentNode()
                        box.position = v3(0, m.headHeight + 0.18, 0)
                        m.node.addChildNode(box)
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
                case nil:
                    break
                }
                switch m.state {
                case .arriving:
                    m.state = .settled
                case .settled:
                    if let pc = m.pyramidCell, m.errand == nil, m.place == .room(m.home.key) {
                        if m.cell != pc { walk(m, to: pc) }
                    } else if clock >= m.nextWanderAt, m.activity != .sleeping, m.place != .quarters {
                        let choices = station.cells(of: m.place).filter { $0 != m.cell }
                        if let dest = choices.randomElement() { m.path = station.path(from: m.cell, to: dest) }
                        m.nextWanderAt = clock + (restless ? Double.random(in: 0.6...1.6) : m.busy ? Double.random(in: 1.2...3) : Double.random(in: 8...20))
                    }
                case .leaving:
                    m.opacity -= dt * 1.5
                    if m.opacity <= 0 { despawn(m); continue }
                }
            }
            if m.state != .leaving { m.opacity = min(1, m.opacity + dt * 2) }
            if m.path.isEmpty, let b = m.bed, b < station.beds.count, m.place == .quarters {
                m.pos += (station.beds[b].pos - m.pos) * min(1, dt * 4)
            }
            let resting = m.path.isEmpty && m.state == .settled
            m.setSleeping(resting && m.activity == .sleeping)
            let bob = m.busy && m.path.isEmpty && !m.isSubagent ? abs(sin(clock * 9 + m.bobPhase)) * 0.06 : 0
            m.node.position = v3(station.offset.x + m.pos.x, bob, station.offset.y + m.pos.y)
            m.node.opacity = m.opacity
            let fidget = restless && resting ? sin(clock * 6 + m.bobPhase) * 0.35 : 0
            let inBed = m.bed != nil && m.place == .quarters && m.path.isEmpty
            let wantFacing = inBed ? 0 : (m.path.isEmpty ? Double(rig.eulerAngles.y) : m.facing) + fidget
            var delta = wantFacing - Double(m.node.eulerAngles.y)
            delta = atan2(sin(delta), cos(delta))
            m.node.eulerAngles.y += delta * min(1, dt * 12)
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

    func setView(yawDegrees: Double, pitchDegrees: Double, zoom: Double) {
        enqueue { [self] in
            userYaw = yawDegrees * .pi / 180; userPitch = pitchDegrees * .pi / 180; userZoom = zoom
            rig.eulerAngles.y = .pi / 4 + userYaw; pitchNode.eulerAngles.x = userPitch
        }
    }

    func resetView() {
        enqueue { [self] in userZoom = 1; userYaw = 0; userPitch = -.pi / 6; userPan = .zero; focused = nil }
    }

    /// Orthographic half-height that fits a footprint of the given span at the current aspect.
    private func fitScale(span: Double) -> Double {
        let aspect = max(0.6, Double(viewSize.width / max(1, viewSize.height)))
        return max(span / (4 * 2.0.squareRoot()) + 3.0, span / (2 * 2.0.squareRoot()) / aspect + 1.2)
    }

    /// Pans and zooms onto one station, or back to the whole fleet.
    func focus(on stationName: String?) {
        enqueue { [self] in focusNow(on: stationName) }
    }

    private func focusNow(on stationName: String?) {
        focused = stationName
        guard let name = stationName, let station = fleet.stations[name] else {
            userPan = .zero; userZoom = 1; userZoomChanged = true; return
        }
        let b = station.bounds
        let center = SIMD2(Double(b.min.x + b.max.x) / 2, Double(b.min.y + b.max.y) / 2) + station.offset
        userPan = center - targetFocus
        let span = Double(b.max.x - b.min.x) + Double(b.max.y - b.min.y) + 3
        userZoom = min(6, max(0.4, fitScale(span: targetSpan) / fitScale(span: span)))
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
        userYaw = d.double(forKey: "view.yaw"); userPitch = d.double(forKey: "view.pitch")
        rig.eulerAngles.y = .pi / 4 + userYaw; pitchNode.eulerAngles.x = userPitch
        let f = d.string(forKey: "view.focus") ?? ""
        if !f.isEmpty, fleet.stations[f] != nil {
            focusNow(on: f)
        } else {
            userZoom = d.double(forKey: "view.zoom"); userPan = SIMD2(d.double(forKey: "view.panx"), d.double(forKey: "view.pany"))
        }
        cameraNode.camera!.orthographicScale = fitScale(span: targetSpan) / userZoom
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
