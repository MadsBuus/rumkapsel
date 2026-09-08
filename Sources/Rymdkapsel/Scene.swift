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
    var smoothFacing = 0.0
    var isCrew = false
    var busyUntil = 0.0        // replay seconds, for crew minions
    var bed: Int?
    var pos: SIMD2<Double>
    var path: [Cell] = []
    var nextWanderAt = 0.0
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
    private struct CrewEvent { let at: Date; let kind: String; let login: String; let roomKey: String; let text: String; let n: Int }
    private struct CrewRoomInfo { var repo: String; var branch: String; var prNumber: Int?; var title: String?; var author: String; var url: String?; var state: String; var last: Date }
    private var crewEvents: [CrewEvent] = []
    private var crewCursor = 0
    private var replayStart = Date()
    private var replayWindow: TimeInterval = 1
    private var replayTime = 0.0             // seconds since replayStart
    private var crewBoxes: [String: (count: Int, state: String, color: NSColor)] = [:]
    private var crewRoomInfo: [String: CrewRoomInfo] = [:]
    private var crewSignature = ""
    private let replayLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    private var hangarAnchors: [String: SCNNode] = [:]
    private var shipsInFlight: [String: Int] = [:]
    static let crewWindow: TimeInterval = 24 * 3600
    static let replayLength = 240.0          // seconds of wall clock for one replay
    private var beams: [String: SCNNode] = [:]
    private let infoLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    private let infoBackground = SKSpriteNode(color: Palette.void.withAlphaComponent(0.85), size: CGSize(width: 1, height: 1))
    private let statusLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    private var legendNodes: [SKNode] = []
    private var jobNodes: [SKNode] = []
    private var hudClock = 0.0
    private var legendSignature = ""
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

    static let activeWindow: TimeInterval = 12 * 3600   // a minion sleeps as long as its office stands
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
            guard let n = node?.name else { return }
            if n.hasPrefix("minion:") { self?.enqueue { self?.poke(minionId: String(n.dropFirst(7))) } }
            guard n.hasPrefix("box:") || n.hasPrefix("rocket:") else { return }
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
        github.onUpdate = { [weak self] in self?.enqueue { self?.rebuildMarkers(); self?.rebuildRockets(); self?.rebuildCrew() } }
        view.onKey = { [weak self] key in
            guard let self else { return false }
            switch key {
            case "1": focus(on: "work")
            case "2": focus(on: "private")
            case "3": focus(on: nil)
            case "4": focus(on: "crew")
            case "r": resetView()
            case "g": refreshGitHub()
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
        for n in [staticRoot, labelRoot, minionRoot, propRoot, markerRoot, debrisRoot, beamRoot, rocketRoot] { scene.rootNode.addChildNode(n) }

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
        if station.padCells.contains(c) { return "kind:pad" }
        if station.coreCells.contains(c) || station.isCorridor(c) { return "corridor" }
        return station.room(at: c)?.key
    }

    private func joined(_ station: Station, _ a: Cell, _ b: Cell, _ key: String) -> Bool {
        owner(station, b) == key || openEdges.contains("\(station.name):\(a.x),\(a.y)|\(b.x),\(b.y)")
    }

    @discardableResult
    private func addTile(station: Station, cell: Cell, owner key: String, color: NSColor, name: String) -> SCNNode {
        let g = 0.075
        let l = joined(station, cell, Cell(x: cell.x - 1, y: cell.y), key) ? 0 : g
        let r = joined(station, cell, Cell(x: cell.x + 1, y: cell.y), key) ? 0 : g
        let b = joined(station, cell, Cell(x: cell.x, y: cell.y - 1), key) ? 0 : g
        let f = joined(station, cell, Cell(x: cell.x, y: cell.y + 1), key) ? 0 : g
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
        openEdges = []
        for station in fleet.stations.values {
            for room in station.rooms.values {
                guard let d = station.doorCell(of: room.key), let o = station.doorOutside(of: room.key) else { continue }
                openEdges.insert("\(station.name):\(d.x),\(d.y)|\(o.x),\(o.y)")
                openEdges.insert("\(station.name):\(o.x),\(o.y)|\(d.x),\(d.y)")
            }
        }

        for station in fleet.stations.values {
            for c in station.corridorCells + station.coreCells {
                addTile(station: station, cell: c, owner: "corridor", color: Palette.corridor, name: "station:" + station.name)
            }
            for c in station.hangarCells {
                addTile(station: station, cell: c, owner: "kind:hangar", color: NSColor(Colors.hangar), name: "hangar:" + station.name)
            }
            for c in station.padCells {
                addTile(station: station, cell: c, owner: "kind:pad", color: NSColor(rgb: (0.24, 0.26, 0.32)), name: "pad:" + station.name)
            }
            if station.hasPad {
                let pc = station.padCenter
                let ring = SCNNode(geometry: SCNTube(innerRadius: 0.55, outerRadius: 0.62, height: 0.01))
                ring.geometry!.firstMaterial = flat(NSColor(rgb: (0.45, 0.48, 0.58)))
                ring.position = v3(station.offset.x + pc.x, 0.006, station.offset.y + pc.y)
                staticRoot.addChildNode(ring)
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
                let sketch = room.key.hasPrefix("proj:")   // a session with no branch yet: an unbuilt slot
                let tileColor = sketch ? NSColor(rgb: (0.27, 0.28, 0.33)) : (room.key.hasPrefix("crew:") ? NSColor(room.color).darker(0.14) : NSColor(room.color))
                if sketch {
                    let o = outline(station: station, room: room)
                    o.name = "room:" + key
                    staticRoot.addChildNode(o)
                }
                for c in room.cells {
                    let t = addTile(station: station, cell: c, owner: room.key, color: tileColor, name: "room:" + key)
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
        for (key, o) in outlines where !undelivered.contains(key) { o.removeFromParentNode(); outlines[key] = nil }
        let bridge = fleet.bridgeCells
        if let first = bridge.first, let last = bridge.last {
            let plane = SCNPlane(width: last.x - first.x + 1, height: 2)
            plane.firstMaterial = flat(Palette.corridor)
            let n = SCNNode(geometry: plane)
            n.eulerAngles.x = -.pi / 2
            n.position = v3((first.x + last.x) / 2, 0, 0.5)
            n.name = "bridge"
            staticRoot.addChildNode(n)
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

            if station.hasPad {
                let padLabel = floorText("launch pad", color: NSColor(rgb: (0.55, 0.58, 0.68)), size: 0.38, maxWidth: 5, lines: 1)
                let pc = station.padCenter
                add(padLabel.node, yaw: 0, center: SIMD2(ox + pc.x - 0.9 + padLabel.width / 2, oz + pc.y + 1.55 + padLabel.height / 2))
            }
            if station.hasHangar {
                let hangarLabel = floorText("hangar", color: NSColor(Colors.hangar).lighter(0.25), size: 0.38, maxWidth: 4, lines: 1)
                let hc = station.hangarCenter
                add(hangarLabel.node, yaw: 0, center: SIMD2(ox + hc.x - 0.9 + hangarLabel.width / 2, oz + hc.y + 2.05 + hangarLabel.height / 2))
            }
            let occupied: (Cell) -> Bool = { c in
                station.coreCells.contains(c) || station.hangarCells.contains(c) || station.padCells.contains(c) || station.isCorridor(c) || station.room(at: c) != nil
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
            for room in station.rooms.values where room.branch != nil || room.key.hasPrefix("crew:") {
                let key = roomKey(station, room)
                var count: Int
                var pr: PullRequest?
                if room.key.hasPrefix("crew:") {
                    guard let cb = crewBoxes[key] else { continue }
                    count = min(16, max(1, cb.count))
                    pr = PullRequest(number: 0, title: "", state: cb.state, reviewDecision: "", isDraft: false, url: "")
                } else {
                    pr = room.repoRoot.flatMap { github.pull(branch: room.branch!, repoRoot: $0) }
                    let ahead = room.worktree.flatMap { github.commitsAhead(worktree: $0) } ?? 0
                    count = min(16, 1 + ahead)
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
                let color = status.map { $0.mixed(with: base, 0.15) } ?? base
                let floorShadow = NSColor(room.color).darker(0.16)
                // Deterministic clutter: sizes, turns and shades vary per box, and extras stack on top.
                var seed = UInt64(truncatingIfNeeded: key.hashValue) | 1
                func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
                let cells = room.cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                var placedBoxes: [(pos: SIMD3<Double>, size: Double)] = []
                for i in 0..<count {
                    let size = 0.16 + 0.15 * rnd()
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
                        pos = SIMD3(station.offset.x + Double(cell.x) + (rnd() - 0.5) * 0.7, size / 2, station.offset.y + Double(cell.y) + (rnd() - 0.5) * 0.7)
                    }
                    placedBoxes.append((pos, size))
                    n.position = v3(pos.x, pos.y, pos.z)
                    n.eulerAngles.y = rnd() * 0.9
                    n.name = "box:" + key
                    if undelivered.contains(key) { n.opacity = 0 }
                    markerRoot.addChildNode(n)
                }
            }
        }
    }

    private func rocket(color: NSColor, tall: Bool) -> SCNNode {
        let n = SCNNode()
        let h = tall ? 1.5 : 0.9, r = tall ? 0.17 : 0.12
        let white = lit(NSColor(rgb: (0.92, 0.92, 0.95)))
        let dark = lit(NSColor(rgb: (0.2, 0.21, 0.26)))
        // Body, a slightly wider lower stage, and a nose cone in the repo colour.
        let lower = SCNNode(geometry: SCNCylinder(radius: r, height: h * 0.45))
        lower.geometry!.firstMaterial = white
        lower.position = v3(0, 0.12 + h * 0.225, 0)
        n.addChildNode(lower)
        let band = SCNNode(geometry: SCNCylinder(radius: r * 1.02, height: h * 0.08))
        band.geometry!.firstMaterial = lit(color)
        band.position = v3(0, 0.12 + h * 0.45, 0)
        n.addChildNode(band)
        let upper = SCNNode(geometry: SCNCylinder(radius: r * 0.9, height: h * 0.4))
        upper.geometry!.firstMaterial = white
        upper.position = v3(0, 0.12 + h * 0.49 + h * 0.2, 0)
        n.addChildNode(upper)
        let nose = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: r * 0.9, height: r * 2.6))
        nose.geometry!.firstMaterial = lit(color)
        nose.position = v3(0, 0.12 + h * 0.89 + r * 1.3, 0)
        n.addChildNode(nose)
        // Portholes on the upper stage.
        for k in 0..<3 {
            let port = SCNNode(geometry: SCNSphere(radius: r * 0.18))
            port.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.55, 0.85)))
            let a = Double(k) * 2 * .pi / 3
            port.position = v3(sin(a) * r * 0.86, 0.12 + h * 0.75, cos(a) * r * 0.86)
            n.addChildNode(port)
        }
        // Four swept fins and an engine nozzle.
        for k in 0..<4 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * .pi / 2 + .pi / 4
            let fin = SCNNode(geometry: SCNBox(width: 0.035, height: r * 2.4, length: r * 1.5, chamferRadius: 0))
            fin.geometry!.firstMaterial = lit(color)
            fin.position = v3(0, 0.12 + r * 1.0, r + r * 0.55)
            fin.eulerAngles.x = 0.35
            pivot.addChildNode(fin)
            n.addChildNode(pivot)
        }
        let nozzle = SCNNode(geometry: SCNCone(topRadius: r * 0.55, bottomRadius: r * 0.8, height: 0.14))
        nozzle.geometry!.firstMaterial = dark
        nozzle.position = v3(0, 0.05, 0)
        n.addChildNode(nozzle)
        // Landing legs so it stands on the pad.
        for k in 0..<3 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * 2 * .pi / 3
            let leg = SCNNode(geometry: SCNBox(width: 0.03, height: 0.22, length: 0.03, chamferRadius: 0))
            leg.geometry!.firstMaterial = dark
            leg.position = v3(0, 0.1, r * 1.1)
            leg.eulerAngles.x = 0.5
            pivot.addChildNode(leg)
            n.addChildNode(pivot)
        }
        let flame = SCNNode(geometry: SCNCone(topRadius: r * 0.6, bottomRadius: 0, height: 0.45))
        flame.geometry!.firstMaterial = flat(Palette.pyramid)
        flame.position = v3(0, -0.2, 0)
        flame.name = "flame"
        flame.opacity = 0
        n.addChildNode(flame)
        return n
    }

    /// A red-and-white tape barrier with a gantry ladder: the release is up but not cleared to fly.
    private func holdDecoration(around center: SIMD3<Double>, tall: Bool) -> SCNNode {
        let n = SCNNode()
        let red = flat(NSColor(rgb: (0.9, 0.2, 0.2))), white = flat(NSColor(rgb: (0.95, 0.95, 0.95)))
        let radius = 0.72, postH = 0.32
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            let post = SCNNode(geometry: SCNBox(width: 0.05, height: postH, length: 0.05, chamferRadius: 0))
            post.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.3, 0.35)))
            post.position = v3(center.x + cos(a) * radius, postH / 2, center.z + sin(a) * radius)
            n.addChildNode(post)
            // Tape between this post and the next, striped in short segments.
            let b = a + .pi / 2
            let p0 = SIMD2(center.x + cos(a) * radius, center.z + sin(a) * radius)
            let p1 = SIMD2(center.x + cos(b) * radius, center.z + sin(b) * radius)
            let segs = 6
            for i in 0..<segs {
                let t0 = Double(i) / Double(segs), t1 = Double(i + 1) / Double(segs)
                let m0 = p0 + (p1 - p0) * t0, m1 = p0 + (p1 - p0) * t1
                let mid = (m0 + m1) / 2
                let d = m1 - m0
                let len = (d.x * d.x + d.y * d.y).squareRoot()
                let seg = SCNNode(geometry: SCNBox(width: len, height: 0.06, length: 0.012, chamferRadius: 0))
                seg.geometry!.firstMaterial = i % 2 == 0 ? red : white
                seg.position = v3(mid.x, postH * 0.8, mid.y)
                seg.eulerAngles.y = -atan2(d.y, d.x)
                n.addChildNode(seg)
            }
        }
        // Gantry: a tower with rungs beside the rocket.
        let h = tall ? 1.7 : 1.1
        let tower = SCNNode()
        for dz in [-0.08, 0.08] {
            let rail = SCNNode(geometry: SCNBox(width: 0.04, height: h, length: 0.04, chamferRadius: 0))
            rail.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.55, 0.2)))
            rail.position = v3(0, h / 2, dz)
            tower.addChildNode(rail)
        }
        var y = 0.15
        while y < h {
            let rung = SCNNode(geometry: SCNBox(width: 0.03, height: 0.03, length: 0.2, chamferRadius: 0))
            rung.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.55, 0.2)))
            rung.position = v3(0, y, 0)
            tower.addChildNode(rung)
            y += 0.18
        }
        tower.position = v3(center.x + 0.32, 0, center.z + 0.02)
        n.addChildNode(tower)
        return n
    }

    /// Flame on, a slow climb that carries the rocket out of the frame, then gone.
    private func liftOff(_ node: SCNNode) {
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
            let key = "\(info.station)|\(launch.pr.number)"
            let node = rockets.removeValue(forKey: key) ?? rockets.removeValue(forKey: key + "|hold") ?? {
                let n = rocket(color: NSColor(fleet.color(forRepo: info.repo)), tall: launch.pr.isProduction)
                if let st = fleet.stations[info.station] { n.position = v3(st.offset.x + st.padCenter.x, 0, st.offset.y + st.padCenter.y) }
                rocketRoot.addChildNode(n)
                return n
            }()
            node.childNode(withName: "hold", recursively: false)?.removeFromParentNode()
            liftOff(node)
            logEvent("\(info.repo) launched to \(launch.pr.base): \(launch.pr.title)")
            ringBell(seed: launch.pr.number)
        }
        var live = Set<String>()
        for (root, info) in repoRoots {
            guard let station = fleet.stations[info.station], let open = github.openReleases(repoRoot: root) else { continue }
            let hasProduction = open.contains(where: \.isProduction)
            for pr in open where pr.isProduction || !hasProduction {
                let key = "\(info.station)|\(pr.number)\(pr.untested ? "|hold" : "")"
                live.insert(key)
                if rockets[key] != nil { continue }
                let n = rocket(color: NSColor(fleet.color(forRepo: info.repo)), tall: pr.isProduction)
                if pr.untested {
                    let deco = holdDecoration(around: SIMD3(0, 0, 0), tall: pr.isProduction)
                    deco.name = "hold"
                    n.addChildNode(deco)
                }
                let slot = rockets.values.filter { $0.parent != nil }.count % 4
                let offsets: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(0.45, 0.45), SIMD2(0.45, -0.45), SIMD2(-0.45, 0.45)]
                let pc = station.padCenter + offsets[slot]
                n.position = v3(station.offset.x + pc.x, 0, station.offset.y + pc.y)
                let status = pr.untested ? " · untested, holding on the pad" : " · cleared for launch"
                n.name = "rocket:\(pr.url)|\(info.repo) · \(pr.head) → \(pr.base) · #\(pr.number) \(pr.title)\(status)"
                n.enumerateChildNodes { c, _ in if c.name != "flame" { c.name = n.name } }
                rocketRoot.addChildNode(n)
                rockets[key] = n
                logEvent("\(info.repo): release to \(pr.base) on the pad" + (pr.untested ? " (untested)" : ""))
            }
        }
        for (key, n) in rockets where !live.contains(key) && !n.hasActions { n.removeFromParentNode(); rockets[key] = nil }
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
        replayLabel.fontSize = 11
        replayLabel.fontColor = Palette.dim
        replayLabel.horizontalAlignmentMode = .left
        replayLabel.verticalAlignmentMode = .bottom
        hud.addChild(replayLabel)
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
        for repo in repos {
            let offices = fleet.stations.values.flatMap { $0.rooms.values }.filter { $0.repo == repo }.count
            let workers = active.filter { $0.home.repo == repo && !$0.isSubagent }.count
            signature += "\(repo):\(workers):\(offices);"
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
        if let info = crewRoomInfo[roomKey(station, room)] {
            var line = "by \(info.author) · ⎇ \(info.branch)"
            if let n = info.prNumber { line += " · PR #\(n) \(info.state.lowercased())" }
            if let t = info.title { line += " · " + t }
            parts.append(line)
        }
        if room.key == "kind:bots" { parts.append("dependabot and friends") }
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
        replayLabel.position = CGPoint(x: 14, y: hud.size.height - 90)
        if !crewEvents.isEmpty {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            replayLabel.text = "crew · replaying " + f.string(from: replayStart.addingTimeInterval(replayTime))
        } else { replayLabel.text = "" }
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
        } else if h.hasPrefix("pad:") {
            infoLabel.text = "launch pad · release pull requests wait here; merging launches"
        } else if h.hasPrefix("hangar:") {
            infoLabel.text = "hangar · new offices arrive here by ship"
        } else if h.hasPrefix("station:") {
            infoLabel.text = String(h.dropFirst(8)) + " · the monolith: web research and subagents"
        } else {
            infoLabel.text = ""
        }
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
            let used = Set(minions.values.filter { $0.station == m.station && $0.id != m.id }.compactMap(\.bed))
            m.bed = station.beds.indices.first { !used.contains($0) }   // nil means a spot on the floor
        }
        let cells = station.cells(of: place)
        let target: Cell
        if let b = m.bed, b < station.beds.count { target = station.beds[b].cell }
        else if place == .quarters, let hall = station.doorOutside(of: "kind:quarters") { target = hall }   // no bed left: the hallway
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

    /// A hexagonal crate in the repo colour: the order for a new office.
    private func crate(color: NSColor) -> SCNNode {
        let geo = SCNCylinder(radius: 0.26, height: 0.18)
        geo.radialSegmentCount = 6
        let top = flat(color.lighter(0.16)), side = flat(color.darker(0.06))
        geo.materials = [side, top, top]
        let n = SCNNode(geometry: geo)
        n.eulerAngles.y = .pi / 6
        return n
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

        let box = crate(color: NSColor(room.color))
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
        let start = slot + SIMD3(3.0, 9.0, 12.0)
        let high = slot + SIMD3(0, 5.0, 0)
        let down = slot + SIMD3(0, 0.55, 0)
        let exit = slot + SIMD3(-12.0, 8.0, 5.0)
        ship.position = v3(start.x, start.y, start.z)
        ship.look(at: v3(high.x, high.y, high.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(1, 0, 0))
        anchor.addChildNode(ship)
        let approach = SCNAction.move(to: v3(high.x, high.y, high.z), duration: 3.0); approach.timingMode = .easeOut
        let descend = SCNAction.move(to: v3(down.x, down.y, down.z), duration: 4.5); descend.timingMode = .easeInEaseOut
        let rise = SCNAction.move(to: v3(high.x, high.y, high.z), duration: 2.5); rise.timingMode = .easeIn
        let leave = SCNAction.move(to: v3(exit.x, exit.y, exit.z), duration: 3.0); leave.timingMode = .easeIn
        ship.runAction(.sequence([
            approach,
            .run { n in n.look(at: v3(down.x, down.y, down.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, -1, 0)); n.eulerAngles = SCNVector3(0, Double.pi / 4, 0) },
            descend,
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
        m.errand = .fetch(room: roomKey)
        m.place = .hangar
        walk(m, to: station.hangarCells[min(station.hangarCells.count - 1, slotIndex * 2)])
    }

    /// Archiving: boxes shrink away, whoever is inside steps out into the hallway, and the room
    /// detaches, sinks and fades. The model drops the room at once; only the visuals linger.
    private func archive(station: Station, room: Room, announce: Bool) {
        let key = roomKey(station, room)
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
                    m.path = station.path(from: m.cell, to: hall)
                    m.place = .core   // parked in the hallway until the next scan sends it on
                    m.nextWanderAt = clock + 4
                }
            }
            logEvent("archived: \(room.name)")
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
                case nil: break
                }
                if m.place == .room(m.home.key) { m.place = .room(home.key) }
                changed = true
            }
            if station.ensureRoom(key: home.key, name: home.name, repo: home.repo, color: fleet.color(forRepo: home.repo), lastActive: s.lastModified) {
                changed = true
                if !firstRun {
                    undelivered.insert("\(stationName)|\(home.key)")
                    newRooms[s.id] = home.key
                }
            }
            if let root = s.repoRoot, !repoRoots.values.contains(where: { $0.repo == s.repo }) {
                repoRoots[root] = (s.repo, stationName)
            }
            if let room = station.rooms[home.key] {
                if home.key.hasPrefix("task:") { room.branch = s.branch; room.repoRoot = s.repoRoot; room.worktree = s.cwd }
                if let b = room.branch, let r = room.repoRoot { github.refresh(branch: b, repoRoot: r) }
                if let w = room.worktree { github.refreshCommits(worktree: w) }
            }
            liveRooms[stationName, default: []].insert(home.key)
        }
        for station in fleet.stations.values {
            for room in Array(station.rooms.values) where !room.key.hasPrefix("kind:") && !room.key.hasPrefix("crew:") {
                if liveRooms[station.name]?.contains(room.key) != true || now.timeIntervalSince(room.lastActive) > StationController.roomsWindow {
                    archive(station: station, room: room, announce: !firstRun)
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
        for (root, info) in repoRoots {
            github.refreshReleases(repoRoot: root)
            if info.station == "work" { github.refreshFeed(repoRoot: root) }
        }
        for change in github.takeStateChanges() {
            let who = change.branch.firstMatch(of: #/^gh-(\d+)\//#).map { "#\($0.1)" } ?? change.branch
            logEvent("\(who): \(change.pr.summary)")
            ringBell(seed: change.pr.number)
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
                    case .prompt: if !m.isSubagent { addPyramid(for: m) }
                    case .tool: continue
                    }
                    ringBell(seed: s.id.hashValue &+ event.rawValue.hashValue)
                }
            }
            m.markers = s.eventMarkers
            m.toolCount = s.toolCount
            if m.activity == .waiting || m.activity == .sleeping { clearPyramids(m) }

            if let key = newRooms[s.id], m.errand == nil, !m.isSubagent, fleet.stations[stationName]?.hasHangar == true {
                startDelivery(m, roomKey: key)
            } else if m.errand == nil {
                let place = Place.forActivity(m.activity, home: home.key, isSubagent: m.isSubagent)
                if place != m.place || isNew { send(m, to: place) }
            }
            if m.state == .leaving { m.state = .arriving; send(m, to: m.place) }
        }
        for m in minions.values where !seen.contains(m.id) && m.state != .leaving && !m.isCrew {
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
            outlines.removeValue(forKey: key)?.removeFromParentNode()
            boxes.removeValue(forKey: key)?.removeFromParentNode()
        }
        if changed {
            rebuildStatic()
            if firstRun { restoreView() }
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

    // MARK: crew replay

    private static let trunkBranches: Set<String> = ["develop", "staging", "main", "master", "production"]

    /// Turns the repositories' activity feeds into offices on the crew station and a timeline to replay.
    private func rebuildCrew() {
        let me = github.myLogin() ?? ""
        var feed: [(repo: String, e: FeedEvent)] = []
        for (root, info) in repoRoots where info.station == "work" {
            for e in github.feed(repoRoot: root) ?? [] where e.actor != me { feed.append((info.repo, e)) }
        }
        let signature = "\(feed.count):" + (feed.map { "\($0.e.at.timeIntervalSince1970)" }.max() ?? "")
        guard signature != crewSignature else { return }
        crewSignature = signature
        guard !feed.isEmpty else { return }

        let station = fleet.station("crew")
        let cutoff = Date().addingTimeInterval(-StationController.crewWindow)
        // Rooms: one per teammate branch with activity; bots share one bay.
        var info: [String: CrewRoomInfo] = [:]
        for (repo, e) in feed.sorted(by: { $0.e.at < $1.e.at }) where e.at > cutoff {
            guard !e.isBot, let branch = e.branch, !StationController.trunkBranches.contains(branch) else { continue }
            let key = "crew:\(repo)/\(branch)"
            var r = info[key] ?? CrewRoomInfo(repo: repo, branch: branch, prNumber: nil, title: nil, author: e.actor, url: nil, state: "NONE", last: e.at)
            if let n = e.prNumber { r.prNumber = n }
            if let t = e.title { r.title = t }
            if let u = e.url { r.url = u }
            switch e.kind {
            case "pr_open": r.state = "OPEN"
            case "pr_merge": r.state = "MERGED"
            case "pr_close": r.state = "CLOSED"
            default: break
            }
            r.last = e.at
            info[key] = r
        }
        // Merged, closed or deleted branches are gone: only live work gets an office.
        for (repo, e) in feed where e.kind == "branch_delete" && e.at > cutoff {
            if let b = e.branch { info["crew:\(repo)/\(b)"] = nil }
        }
        info = info.filter { $0.value.state != "MERGED" && $0.value.state != "CLOSED" }
        // Cap per repo by latest activity, so a busy day does not explode the station.
        var keep: Set<String> = []
        for repo in Set(info.values.map(\.repo)) {
            let sorted = info.filter { $0.value.repo == repo }.sorted { $0.value.last > $1.value.last }
            for (k, _) in sorted.prefix(8) { keep.insert(k) }
        }
        info = info.filter { keep.contains($0.key) }

        var changed = false
        for room in Array(station.rooms.values) where room.key.hasPrefix("crew:") && info[room.key] == nil {
            station.removeRoom(key: room.key); changed = true
        }
        crewRoomInfo = [:]
        for (key, r) in info {
            let issue = r.branch.firstMatch(of: #/^gh-(\d+)\//#).map { "#\($0.1) " } ?? ""
            let words = r.branch.split(separator: "/").last.map { $0.replacingOccurrences(of: "-", with: " ") } ?? r.branch
            let name = r.author + " · " + issue + String(words.prefix(22))
            if station.ensureRoom(key: key, name: name, repo: r.repo, color: fleet.color(forRepo: r.repo), lastActive: r.last) { changed = true }
            crewRoomInfo["crew|" + key] = r
        }
        if feed.contains(where: { $0.e.isBot }) {
            if station.ensureRoom(key: "kind:bots", name: "bots", repo: nil, color: RGB(r: 0.36, g: 0.40, b: 0.50), lastActive: .distantFuture, shape: Station.rect(2, 2)) { changed = true }
        }

        // Timeline over what the feed covers, up to a day.
        let times = feed.map(\.e.at).filter { $0 > cutoff }
        replayStart = max(cutoff, times.min() ?? cutoff)
        replayWindow = max(60, Date().timeIntervalSince(replayStart))
        var events: [CrewEvent] = []
        for (repo, e) in feed where e.at > replayStart {
            let roomKey: String
            if e.isBot { roomKey = "kind:bots" }
            else if let b = e.branch, !StationController.trunkBranches.contains(b), info["crew:\(repo)/\(b)"] != nil { roomKey = "crew:\(repo)/\(b)" }
            else if e.kind == "issue_open" { roomKey = info.first { $0.value.author == e.actor }?.key ?? "kind:quarters" }
            else if e.kind == "pr_merge" || e.kind == "pr_open", let b = e.branch, !StationController.trunkBranches.contains(b) { roomKey = "gone" }
            else { continue }
            let who = e.actor
            let n = e.prNumber.map { "#\($0)" } ?? ""
            switch e.kind {
            case "push": events.append(CrewEvent(at: e.at, kind: "commit", login: who, roomKey: roomKey, text: "", n: Int(e.detail) ?? 1))
            case "pr_open": events.append(CrewEvent(at: e.at, kind: "open", login: who, roomKey: roomKey, text: "\(who) opened \(n)", n: 0))
            case "pr_merge": events.append(CrewEvent(at: e.at, kind: "merge", login: who, roomKey: roomKey, text: "\(who) merged \(n)", n: 0))
            case "pr_close": events.append(CrewEvent(at: e.at, kind: "close", login: who, roomKey: roomKey, text: "\(who) closed \(n)", n: 0))
            case "review":
                let verb = e.detail == "approved" ? "approved" : e.detail == "changes_requested" ? "requested changes on" : "reviewed"
                events.append(CrewEvent(at: e.at, kind: "review", login: who, roomKey: roomKey, text: "\(who) \(verb) \(n)", n: 0))
            case "comment": events.append(CrewEvent(at: e.at, kind: "comment", login: who, roomKey: roomKey, text: "", n: 0))
            case "branch_create": events.append(CrewEvent(at: e.at, kind: "create", login: who, roomKey: roomKey, text: "\(who) started \(e.branch ?? "a branch")", n: 0))
            case "branch_delete": events.append(CrewEvent(at: e.at, kind: "delete", login: who, roomKey: roomKey, text: "\(who) archived \(e.branch ?? "a branch")", n: 0))
            case "issue_open": events.append(CrewEvent(at: e.at, kind: "issue", login: who, roomKey: roomKey, text: "\(who) filed \(n) \(e.title ?? "")", n: 0))
            default: break
            }
        }
        crewEvents = events.sorted { $0.at < $1.at }
        crewCursor = 0
        replayTime = 0
        crewBoxes = [:]
        for (key, r) in info { crewBoxes["crew|" + key] = (1, r.state == "MERGED" ? "NONE" : "NONE", NSColor(fleet.color(forRepo: r.repo))) }
        crewBoxes["crew|kind:bots"] = (1, "NONE", NSColor(rgb: (0.55, 0.6, 0.7)))

        // One grey minion per teammate, plus one small bot.
        var logins = Set(feed.filter { !$0.e.isBot && $0.e.at > replayStart }.map(\.e.actor))
        logins.formUnion(info.values.map(\.author))
        for login in logins where minions["crew:" + login] == nil {
            let homeKey = info.first { $0.value.author == login }?.key ?? "kind:quarters"
            let home = Home(key: homeKey, name: login, repo: info[homeKey]?.repo ?? "crew", issue: nil)
            let start = station.cells(of: .quarters).randomElement() ?? station.coreCenter
            let m = Minion(id: "crew:" + login, station: "crew", home: home, cwd: "", toolCount: 0, isSubagent: false, start: start, crew: true)
            m.title = login
            m.activity = .sleeping
            minionRoot.addChildNode(m.node)
            minions[m.id] = m
            send(m, to: .quarters)
        }
        if feed.contains(where: { $0.e.isBot }), minions["crew:bots"] == nil {
            let home = Home(key: "kind:bots", name: "bots", repo: "crew", issue: nil)
            let m = Minion(id: "crew:bots", station: "crew", home: home, cwd: "", toolCount: 0, isSubagent: true, start: station.coreCenter, crew: true)
            m.title = "dependabot"
            m.activity = .sleeping
            minionRoot.addChildNode(m.node)
            minions[m.id] = m
            send(m, to: .room("kind:bots"))
        }
        for m in minions.values where m.isCrew && m.id != "crew:bots" && !logins.contains(String(m.id.dropFirst(5))) { despawn(m) }
        if changed { rebuildStatic(); for m in minions.values where m.errand == nil { send(m, to: m.place) } } else { rebuildMarkers() }
    }

    /// Advances the replay clock and acts out the events as they come due.
    private func tickCrew(dt: Double) {
        guard !crewEvents.isEmpty else { return }
        let speed = replayWindow / StationController.replayLength
        replayTime += dt * speed
        if replayTime > replayWindow + 20 * speed {
            replayTime = 0; crewCursor = 0
            for key in crewBoxes.keys { crewBoxes[key]?.count = 1; crewBoxes[key]?.state = "NONE" }
            rebuildMarkers()
        }
        let now = replayStart.addingTimeInterval(replayTime)
        var markersDirty = false
        let hour = replayWindow / 24
        while crewCursor < crewEvents.count, crewEvents[crewCursor].at <= now {
            let e = crewEvents[crewCursor]; crewCursor += 1
            let key = "crew|" + e.roomKey
            let isBots = e.roomKey == "kind:bots"
            let gone = e.roomKey == "gone"
            let m = minions[isBots ? "crew:bots" : "crew:" + e.login]
            func go(_ activity: Activity, _ place: Place, _ hold: Double) {
                guard let m else { return }
                if gone, case .room = place { m.activity = activity; m.busy = true; m.busyUntil = replayTime + hold; send(m, to: .core); return }
                m.activity = activity; m.busy = true; m.busyUntil = replayTime + hold
                if m.place != place || m.path.isEmpty { send(m, to: place) }
            }
            switch e.kind {
            case "commit":
                crewBoxes[key]?.count += e.n; markersDirty = true
                go(.coding("x"), .room(e.roomKey), hour * 0.6)
            case "open":
                crewBoxes[key]?.state = "OPEN"; markersDirty = true
                if !isBots { logEvent(e.text) }
                go(.shipping, .room(e.roomKey), hour * 0.4)
            case "merge":
                crewBoxes[key]?.state = "MERGED"; markersDirty = true
                if !isBots { logEvent(e.text); ringBell(seed: e.roomKey.hashValue) }
                go(.shipping, .core, hour * 0.4)
            case "close":
                crewBoxes[key]?.state = "CLOSED"; markersDirty = true
                if !isBots { logEvent(e.text) }
            case "review":
                if !isBots { logEvent(e.text) }
                go(.exploring, .room(e.roomKey), hour * 0.4)
            case "comment":
                go(.writing, .room(e.roomKey), hour * 0.3)
            case "create":
                if !isBots { logEvent(e.text) }
                go(.planning, .room(e.roomKey), hour * 0.3)
            case "delete":
                if !isBots { logEvent(e.text) }
                crewBoxes[key]?.count = 1; markersDirty = true
            case "issue":
                if !isBots { logEvent(e.text) }
                if let m { addPyramid(for: m) }
                go(.writing, .room(e.roomKey), hour * 0.3)
            default: break
            }
        }
        if markersDirty { rebuildMarkers() }
        for m in minions.values where m.isCrew && m.busy && replayTime > m.busyUntil {
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
        if let st = fleet.stations["work"] {
            for (i, tall) in [false, true].enumerated() {
                let n = rocket(color: NSColor(fleet.color(forRepo: i == 0 ? "api-node-nest" : "tattoodo-web")), tall: tall)
                let pc = st.padCenter + (i == 0 ? SIMD2(0.45, -0.45) : SIMD2(0, 0))
                n.position = v3(st.offset.x + pc.x, 0, st.offset.y + pc.y)
                n.name = "rocket:https://github.com|demo release"
                if tall { let d = holdDecoration(around: SIMD3(0, 0, 0), tall: true); d.name = "hold"; n.addChildNode(d) }
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
            if clock > 12, let r = rockets["work|1"], !r.hasActions, r.parent != nil {
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
        tickCrew(dt: dt)
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
            let waitingAge = m.activity == .waiting ? clock - m.waitingSince : 0
            let jumping = m.activity == .waiting && waitingAge < 60 && m.errand == nil
            let pacing = m.activity == .waiting && waitingAge >= 60 && m.errand == nil
            let speed = m.busy ? 2.4 : (pacing ? 0.8 : 1.4)
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
                    if let box = boxes[key], box.opacity < 1 { continue }   // shuttle has not set it down yet
                    if let box = boxes[key] {
                        box.removeAllActions()
                        box.removeFromParentNode()
                        box.position = v3(0, m.headHeight + 0.14, 0)
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
                    } else if clock >= m.nextWanderAt, m.activity != .sleeping, m.place != .quarters, !jumping {
                        let choices = station.cells(of: m.place).filter { $0 != m.cell }
                        if let dest = choices.randomElement() { m.path = station.path(from: m.cell, to: dest) }
                        m.nextWanderAt = clock + (pacing ? Double.random(in: 2.5...6) : m.busy ? Double.random(in: 2...5) : Double.random(in: 8...20))
                    }
                case .leaving:
                    m.opacity -= dt * 1.5
                    if m.opacity <= 0 { despawn(m); continue }
                }
            }
            if m.state != .leaving { m.opacity = min(1, m.opacity + dt * 2) }
            if m.path.isEmpty, m.place == .quarters {
                if let b = m.bed, b < station.beds.count {
                    m.pos += (station.beds[b].pos - m.pos) * min(1, dt * 4)
                } else if let hall = station.doorOutside(of: "kind:quarters") {
                    let k = Double(abs(m.id.hashValue) % 5) - 2
                    let spot = SIMD2(Double(hall.x), Double(hall.y)) + SIMD2(k * 0.18, k * 0.1)
                    m.pos += (spot - m.pos) * min(1, dt * 4)
                }
            }
            let resting = m.path.isEmpty && m.state == .settled
            m.setSleeping(resting && m.activity == .sleeping)
            let jump = jumping && resting ? abs(sin(clock * 7 + m.bobPhase)) * 0.14 : 0
            m.node.position = v3(station.offset.x + m.pos.x, jump, station.offset.y + m.pos.y)
            m.node.opacity = m.opacity
            let working = m.busy && resting && !m.isSubagent && m.activity != .waiting
            let inBed = m.bed != nil && m.place == .quarters && m.path.isEmpty
            let wantFacing = inBed ? 0 : (m.path.isEmpty ? Double(rig.eulerAngles.y) : m.facing)
            var delta = wantFacing - m.smoothFacing
            delta = atan2(sin(delta), cos(delta))
            m.smoothFacing += delta * min(1, dt * 12)

            // One little routine per activity, so you can tell at a glance what a minion is up to.
            var tilt = 0.0, roll = 0.0, spin = 0.0
            let t = clock + m.bobPhase
            if working {
                switch m.activity {
                case .coding: tilt = sin(t * 14) * 0.06                       // typing: quick nods
                case .exploring: spin = sin(t * 1.2) * 0.7                    // reading code: scanning left and right
                case .writing: tilt = sin(t * 3) * 0.1                        // writing: slow nods
                case .thinking: roll = sin(t * 2) * 0.12                      // thinking: swaying
                case .planning: tilt = -0.12 + sin(t * 2) * 0.05              // planning: looking up
                case .reading: tilt = -0.18                                   // reading your message: head back
                case .testing: spin = t * 3                                   // testing: pacing in circles
                case .running: tilt = sin(t * 22) * 0.04; roll = cos(t * 19) * 0.04   // running things: jittery
                case .shipping: roll = sin(t * 9) * 0.16                      // shipping: excited wiggle
                case .skill: spin = t * 2                                     // using a skill: a slow spin
                case .delegating: spin = sin(t * 4) * 0.3                     // delegating: glancing about
                case .qa: tilt = -0.25 + sin(t * 1.5) * 0.1; spin = sin(t * 0.8) * 0.4   // QA: looking the rocket up and down
                default: roll = sin(t * 5) * 0.07
                }
            }
            m.node.eulerAngles = SCNVector3(tilt, m.smoothFacing + spin, roll)
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
            for (root, info) in repoRoots {
            github.refreshReleases(repoRoot: root)
            if info.station == "work" { github.refreshFeed(repoRoot: root) }
        }
            logEvent("asking github…")
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
