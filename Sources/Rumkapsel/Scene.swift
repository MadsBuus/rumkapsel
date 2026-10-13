import AppKit
import QuartzCore
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
    func dimmed(_ f: CGFloat) -> NSColor { shaded(value: f) }
    func darker(_ f: CGFloat) -> NSColor { shaded(value: 1 - f) }
    func lighter(_ f: CGFloat) -> NSColor {
        let c = usingColorSpace(.deviceRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let want = b + f
        let over = max(0, want - 1)
        return NSColor(calibratedHue: h, saturation: max(0, s - over * 1.6), brightness: min(1, want), alpha: 1)
    }

    private func shaded(value f: CGFloat) -> NSColor {
        let c = usingColorSpace(.deviceRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(calibratedHue: h, saturation: s, brightness: max(0, min(1, b * f)), alpha: 1)
    }
}

enum Palette {
    static let void = NSColor(rgb: (0.055, 0.067, 0.125))
    static let corridor = NSColor(rgb: (0.494, 0.400, 0.353))
    static let core = NSColor(rgb: (0.13, 0.14, 0.18))
    static let padFloor = NSColor(rgb: (0.105, 0.115, 0.140))
    static let labFloor = NSColor(rgb: (0.365, 0.400, 0.467))
    static let storageFloor = NSColor(rgb: (0.247, 0.275, 0.337))
    static let walkFloor = NSColor(rgb: (0.290, 0.320, 0.384))
    static let deconFloor = NSColor(rgb: (0.204, 0.208, 0.243))
    static let minion = NSColor(rgb: (0.96, 0.96, 0.94))
    static let pyramid = NSColor(rgb: (0.98, 0.85, 0.35))
    static let debris = NSColor(rgb: (0.55, 0.6, 0.7))
    static let alien = NSColor(rgb: (0.58, 0.6, 0.66))
    static let alienLight = NSColor(rgb: (0.5, 0.95, 0.55))
    static let mine = NSColor(rgb: (0.95, 0.96, 0.93))
    static let text = NSColor(rgb: (0.85, 0.87, 0.92))
    static let dim = NSColor(rgb: (0.5, 0.53, 0.6))
}

func v3(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 { SCNVector3(x, y, z) }

enum Pick {
    static let normal = 1
    static let scenery = 2
    static let planet = 16
    static let onboard = 32
    static let colony = 64
    static let launching = 128
    static let air = 256
}

enum Backdrop {
    static let drawn = !CommandLine.arguments.contains("--no-stars")
}

func faceted<G: SCNGeometry>(_ g: G, _ sides: Int = 6) -> G {
    (g as? SCNCylinder)?.radialSegmentCount = sides
    (g as? SCNCone)?.radialSegmentCount = sides
    (g as? SCNTube)?.radialSegmentCount = sides
    return g
}

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

final class StationController: NSObject, SCNSceneRendererDelegate {
    let pendingLock = NSLock()
    var pending: [() -> Void] = []

    func enqueue(_ work: @escaping () -> Void) {
        pendingLock.lock(); pending.append(work); pendingLock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let frameBegan = CACurrentMediaTime()
        frameNo &+= 1
        phases = []
        tilesBuilt = 0
        pendingLock.lock(); let work = pending; pending.removeAll(); pendingLock.unlock()
        timed("handoff") { for w in work { w() } }
        let now = CACurrentMediaTime()
        guard Trace.frames else {
            if sim != nil { advanceSimulated(to: now) } else { tick(now: now) }
            return
        }
        let gap = now - lastFrameAt
        lastFrameAt = now
        let began = frameBegan
        if sim != nil { advanceSimulated(to: now) } else { tick(now: now) }
        let spent = CACurrentMediaTime() - began
        if gap > Trace.slowFrame || spent > Trace.slowWork {
            let worst = phases.filter { $0.seconds > 0.002 }.sorted { $0.seconds > $1.seconds }
                .map { String(format: "%@ %.0fms", $0.name, $0.seconds * 1000) }.joined(separator: " ")
            FileHandle.standardError.write(String(format: "frame gap %.0fms work %.0fms tiles %d  %@\n",
                                                  gap * 1000, spent * 1000, tilesBuilt, worst).data(using: .utf8)!)
        }
    }

    enum Trace {
        static let frames = ProcessInfo.processInfo.environment["RK_FRAMES"] != nil
        static let slowFrame = 0.05, slowWork = 0.02
    }
    private var phases: [(name: String, seconds: Double)] = []
    private var lastFrameAt = CACurrentMediaTime()
    private var frameNo = 0
    private var lastFloorFrame = -1
    private var lastGitHubFrame = -1
    var tilesBuilt = 0
    var tileCache: [String: SCNGeometry] = [:]
    var owners: [String: [Cell: String]] = [:]
    var tileCacheLook: Theme = Looks.theme

    @discardableResult func timed<T>(_ name: String, _ body: () -> T) -> T {
        guard Trace.frames else { return body() }
        let t0 = CACurrentMediaTime()
        defer { phases.append((name, CACurrentMediaTime() - t0)) }
        return body()
    }

    let view: StationView
    let scene = SCNScene()
    let hud: SKScene
    let simulation: Simulation<Minion>
    var world: World { simulation.world }
    let drone = Drone()
    private let scanner = TranscriptScanner()
    private let scanQueue = DispatchQueue(label: "rumkapsel.scan")
    var fleet: Fleet { world.fleet }
    var github: GitHubResolver { world.github }

    var minions: [String: Minion] {
        get { simulation.bodies }
        set { simulation.bodies = newValue }
    }
    let staticRoot = SCNNode()
    let labelRoot = SCNNode()
    let minionRoot = SCNNode()
    let propRoot = SCNNode()
    let markerRoot = SCNNode()
    private let debrisRoot = SCNNode()
    let groundRoot = SCNNode()
    var viewYaw: Double { Looks.current.viewYaw }
    let rig = SCNNode()
    let pitchNode = SCNNode()
    let cameraNode = SCNNode()
    var roomTiles: [String: [SCNNode]] = [:]
    var openEdges: Set<String> = []
    var roomLabels: [String: SCNNode] = [:]
    var floorLabels: [(node: SCNNode, baseYaw: Double)] = []
    var undelivered: Set<String> { world.truth.pendingOffices }
    var packing: Set<String> = []
    var stowHeld: Set<String> = []
    var newestCube: [String: SCNNode] = [:]
    var boxes: [String: SCNNode] = [:]
    var outlines: [String: SCNNode] = [:]
    let beamRoot = SCNNode()
    let rocketRoot = SCNNode()
    var rocketViews: [String: RocketView] = [:]
    var sparks: [Spark] = []
    var undocking: [(node: SCNNode, since: Double)] = []
    var shuttleViews: [ObjectIdentifier: ShuttleView] = [:]
    var lastBoxCount: [String: Int] = [:]
    var markerSignatures: [String: String] = [:]
    var packages: [String: SCNNode] = [:]
    var packageBuilt: [String: String] = [:]
    var packageCells: [String: Cell] = [:]
    var crateMotions: [ObjectIdentifier: CrateMotion] = [:]
    var furnitureObstacles: [String: Set<Cell>] = [:]
    var furnitureObstaclesAt = -1
    private var localSignature = ""
    private var pendingCrewDeliveries: [(login: String, key: String)] = []
    var hangarAnchors: [String: SCNNode] = [:]
    var gymProps: [String: (bar: SCNNode, bag: SCNNode)] = [:]
    private var lastBusy: [String: Double] = [:]
    var stationAnchors: [String: SCNNode] = [:]
    var knownSpine: [String: Int] = [:]
    var knownHall: [String: [Cell]] = [:]
    let peers = PeerHub()
    var fadeIn: Set<String> = []
    private let peerRoot = SCNNode()
    var peerFigures: Int { minions.values.filter(\.isPeer).count }
    private var peerColorBook: [String: RGB] = [:]
    var roomPower: [String: Bool] = [:]
    var roomLight: [String: OfficeLight] = [:]
    var cargo: [Int: Cargo] {
        get { simulation.cargo }
        set { simulation.cargo = newValue }
    }
    var cargoNodes: [Int: SCNNode] = [:]
    var droneRacks: [String: SCNNode] = [:]
    var fields: [String: HangarField] = [:]
    var padFields: [String: HangarField] = [:]
    var vortexViews: [String: VortexView] = [:]
    var padRings: [String: SCNNode] = [:]
    var droneViews: [String: DroneView] = [:]
    var puffs: [Puff] = []
    private var lastHaulSchedule = 0.0
    static let powerWindow: TimeInterval = 2 * 3600
    var beams: [String: SCNNode] = [:]
    let infoLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    let infoBackground = SKSpriteNode(color: Palette.void.withAlphaComponent(0.85), size: CGSize(width: 1, height: 1))
    let statusLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    let followLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    let bubbleLabel = SKLabelNode(fontNamed: "HelveticaNeue")
    let bubblePlate = SKSpriteNode(color: Palette.void.withAlphaComponent(0.9), size: CGSize(width: 1, height: 1))
    var bubbleIcons: [SKSpriteNode] = []
    var hatchLights: [String: SCNNode] = [:]
    private var askedGitHubAt = Date.distantPast
    var incoming: Set<String> = []
    let bubbleLock = NSLock()
    var bubbleHits: (minion: String, plate: CGRect, hold: CGRect, icons: [CGRect])?
    var bubbleCursor: CGPoint?
    let shareDot = SKSpriteNode(color: NSColor(rgb: (0.35, 0.85, 0.5)), size: CGSize(width: 7, height: 7))
    let shareLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    var legendNodes: [SKNode] = []
    var jobNodes: [SKNode] = []
    var hudClock = 0.0
    var legendSignature = ""
    var eventLabels: [(SKLabelNode, Double)] = []
    var mission: Mission?
    var walker: Walker?
    var rehearsals = 0
    let missionCamera = SCNNode()
    let missionCraft = SCNNode()
    var hiddenRockets: [SCNNode] = []
    var missionView: SCNView?
    var missionScreen: MissionScreen?
    var missionUserSmall = false, missionUserOpened = false
    var missionSize = 0
    var missionOrbit = SIMD2<Double>(0, 0)
    var queuedMissions: [Mission] = []
    var missionShown = ""
    let planetRoot = SCNNode()
    var planets: [String: SCNNode] = [:]
    var spaceLogButton: SpaceLogButton?
    var spaceLogPanel: SpaceLogPanel?
    var spaceLogClock = -100.0
    var spaceLogOpen = false
    var spaceLogDrawnAt = 0.0
    var spaceLogCorner: CGFloat = 0
    var hovered: String?
    var following: String?
    private var lastTick = 0.0
    var liveTimeScale = 1.0
    var visitLog: [(kind: String, lasted: Double, planned: Double)] { simulation.visitLog }
    var clock: Double {
        get { simulation.clock }
        set { simulation.clock = newValue }
    }
    var targetHalf = SIMD2<Double>(6, 6)
    var targetFocus = SIMD2<Double>(0, 0)
    var userZoom = 1.0
    var userZoomChanged = false
    var userDriving = 0.0
    var userTookView = false
    let fpsLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
    private var fpsFrames = 0, fpsMark = 0.0, fpsWorst = 0.0
    private var keyMove = SIMD2<Double>(0, 0)
    private var keyZoom = 0.0
    var userYaw = 0.0
    var userPitch = -Double.pi / 6
    var userPan = SIMD2<Double>(0, 0)
    var focused: String?
    private var lastSavedView = 0.0
    private var debris: [(SCNNode, SIMD2<Double>)] = []
    var lastPing = 0.0
    private var timer: Timer?
    private var watcher: DirectoryWatcher?
    var viewSize = CGSize(width: 640, height: 440)
    let demo: Bool
    var sim: SimHooks? {
        get { simulation.hooks }
        set { simulation.hooks = newValue }
    }
    var headless = false
    var now: Date { simulation.now }
    var demoClock = 0.0
    var demoMerged = false
    var demoStaged = false

    static let activeWindow: TimeInterval = 60 * 60
    static let busyWindow: TimeInterval = 90
    static let replyWindow: TimeInterval = 20
    static let sleepWindow: TimeInterval = 5 * 60
    static let subagentWindow: TimeInterval = 3 * 60
    static let scanWindow: TimeInterval = 14 * 24 * 3600

    static let inkOnTile = NSColor(rgb: (0.03, 0.03, 0.05))
    var labelCells: [String: Set<Cell>] = [:]

    let padHexRoot = SCNNode()
    let berthRoot = SCNNode()
    var berthHexes: [String: [SCNNode]] = [:]
    var berthLit: [String: BerthLight] = [:]

    var viewPinned = false

    init(frame: NSRect, demo: Bool, simulated: Bool = false) {
        self.demo = demo
        let world = World(demo: demo || simulated)
        world.simulated = simulated
        world.waitsForGitHub = !simulated
        world.fleet.persists = !simulated
        world.github.frozen = simulated
        simulation = Simulation(world: world)
        if simulated { simulation.hooks = SimHooks() }
        view = StationView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        hud = SKScene(size: frame.size)
        super.init()
        buildScene()
        buildHUD()
        view.scene = scene
        view.backgroundColor = Palette.void
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        view.autoresizingMask = [.width, .height]
        view.allowsCameraControl = false
        view.overlaySKScene = hud
        view.onHover = { [weak self] node in let n = node?.name; self?.enqueue { self?.hovered = n } }
        view.hudTakesPoint = { [weak self] p in self?.spaceLogTakes(point: p) == true || self?.missionTakes(point: p) == true || self?.bubbleTakes(point: p) == true }
        view.onHUDClick = { [weak self] p in self?.bubbleClick(at: p) ?? false }
        view.onDoubleClick = { [weak self] node, floor in
            let n = node?.name ?? ""
            self?.enqueue {
                if n.hasPrefix("minion:") { self?.poke(minionId: String(n.dropFirst(7))) }
                else if ["room:", "box:", "rocket:"].contains(where: n.hasPrefix) { self?.open(named: n) }
                else if let floor, self?.walker == nil { self?.stepIn(at: floor) }
            }
        }
        view.onClick = { [weak self] node in
            if let self, missionView != nil, missionSize > 0 { DispatchQueue.main.async { self.setMissionSize(0) } }
            let n = node?.name ?? ""
            if n.hasPrefix("minion:") {
                let id = String(n.dropFirst(7))
                self?.enqueue { if self?.walker != nil { self?.ride(minionId: id) } else { self?.follow(minionId: id) } }
                return
            }
            self?.enqueue { self?.following = nil }
            guard !n.isEmpty else { return }
            if (n.hasPrefix("storage:") || n.hasPrefix("deck:") || n.hasPrefix("decon:")), n.split(separator: "|").count == 3 { self?.enqueue { self?.openCargo(named: n) } }
            guard n.hasPrefix("box:") || n.hasPrefix("rocket:") else { return }
            self?.enqueue { self?.open(named: n) }
        }
        view.onContextMenu = { [weak self] node, event in self?.showContextMenu(for: node?.name, event: event) }
        view.onZoom = { [weak self] f, point in
            let ground = point.flatMap { self?.groundPoint(at: $0) }
            self?.enqueue {
                guard let self, self.walker == nil else { return }
                let before = self.userZoom
                self.userZoom = min(6, max(0.4, self.userZoom * f))
                self.userZoomChanged = true
                self.userTookView = true
                guard let g = ground, self.userZoom != before else { return }
                self.userDriving = 0.5
                let focus = self.targetFocus + self.userPan
                self.userPan = g + (focus - g) * (before / self.userZoom) - self.targetFocus
            }
        }
        view.onRotate = { [weak self] r, point in
            let ground = point.flatMap { self?.groundPoint(at: $0) }
            self?.enqueue {
                guard let self, self.walker == nil else { return }
                let before = self.userYaw
                self.userYaw -= r
                self.userDriving = 0.5
                self.userTookView = true
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
            self?.enqueue { guard let self else { return }; self.userTookView = true; self.userPitch = min(-0.15, max(-Double.pi / 2 + 0.05, self.userPitch - dy * 0.004)) }
        }
        view.onPan = { [weak self] dx, dy in
            self?.enqueue {
                guard let self else { return }
                if self.walker != nil { self.walkLook(SIMD2(dx, dy) * 0.004) } else { self.pan(byPixels: dx, dy) }
            }
        }
        view.onLook = { [weak self] dx, dy in
            guard let self, self.walker != nil else { return false }
            self.enqueue { self.walkLook(SIMD2(-dx, -dy) * 0.005) }
            return true
        }
        view.onMove = { [weak self] dir, zoom in self?.enqueue { self?.keyMove = dir; self?.keyZoom = zoom; if dir != .zero || zoom != 0 { self?.userTookView = true } } }
        github.onUpdate = { [weak self] in self?.enqueue { self?.onGitHubUpdate() } }
        view.onHold = { [weak self] held in
            guard let self else { return }
            if let w = self.walker { w.thrusting = held; self.liveTimeScale = 1 } else { self.liveTimeScale = held ? 4 : 1 }
        }
        view.onKey = { [weak self] key in
            guard let self else { return false }
            switch key {
            case "0": following = nil; focus(on: nil)
            case "1", "2", "3", "4": following = nil; focus(onIndex: Int(key)! - 1)
            case "r": following = nil; resetView()
            case "f": toggleWalk()
            case "\u{1b}":
                following = nil
                enqueue { self.walkEscape() }
                if spaceLogPanel?.isHidden == false { toggleSpaceLog() }
            case "l": toggleSpaceLog()
            case "g": refreshGitHub()
            default: return false
            }
            return true
        }
        view.delegate = self

        world.hasPackage = { [weak self] key in self?.markerRoot.childNodes.contains { $0.name == "box:" + key } ?? false }
        simulation.onEvent = { [weak self] event in self?.handle(event) }
        simulation.onLog = { [weak self] text in self?.logEvent(text) }
        peers.onSnapshot = { [weak self] snap in self?.enqueue { self?.receivePeer(snap) } }
        if !simulated { applySharing() }
        if !simulated && !demo { installSpaceLog() }
        if !simulated { Bulkhead.prepare() }
        if demo {
            seedDemo()
        } else if !simulated {
            rescan()
            let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects").path
            watcher = DirectoryWatcher(path: projects) { [weak self] in self?.rescan() }
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.rescan() }
        }
    }

    // MARK: scene

    private func buildScene() {
        Looks.use(ConfigStore.shared.current.theme)
        for n in [groundRoot, staticRoot, labelRoot, minionRoot, propRoot, markerRoot, debrisRoot, beamRoot, rocketRoot, peerRoot] { scene.rootNode.addChildNode(n) }

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 8
        camera.zNear = 0.1
        camera.zFar = 400
        camera.categoryBitMask = ~(Pick.onboard | Pick.colony)
        cameraNode.camera = camera
        cameraNode.position = v3(0, 0, 120)
        pitchNode.eulerAngles.x = -.pi / 6
        pitchNode.addChildNode(cameraNode)
        rig.eulerAngles.y = viewYaw
        rig.addChildNode(pitchNode)
        scene.rootNode.addChildNode(rig)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 700
        sun.eulerAngles = v3(-.pi / 3, .pi / 3, 0)
        sun.light!.categoryBitMask = ~(Pick.planet | Pick.colony | Pick.onboard)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 550
        ambient.light!.categoryBitMask = ~(Pick.planet | Pick.colony | Pick.onboard)
        scene.rootNode.addChildNode(ambient)
        buildBackdrop()
        rebuildStatic()
    }

    private func buildBackdrop() {
        debrisRoot.childNodes.forEach { $0.removeFromParentNode() }
        scene.background.contents = Looks.current.background
        debris = []
        guard Backdrop.drawn else { return }
        debris = Looks.current.backdrop(into: debrisRoot)
    }

    func roomKey(_ station: Station, _ room: Room) -> String { "\(station.name)|\(room.key)" }

    func onGitHubUpdate() {
        if !headless {
            guard lastGitHubFrame != frameNo else { return }
            lastGitHubFrame = frameNo
        }
        let sig = fleet.stations.values.flatMap { st in st.rooms.values.map { r in
            let l = world.localState(r)
            let checks = r.branch.flatMap { b in r.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0)?.checks } } ?? ""
            return "\(st.name)|\(r.key):\(l.local):\(l.commits > 0):\(checks)"
        } }.sorted().joined()
        timed("github") { handle(world.applyGitHub(now: now, timed: { n, b in self.timed(n, b) })) }
        if world.placementsLeft { enqueue { [weak self] in self?.onGitHubUpdate() } }
        reconcileYards()
        if sig != localSignature { localSignature = sig; layoutDirty = true } else { markersDirty = true }
        refreshRockets()
        flushScene()
        flushDeliveries()
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

    func apply(_ result: ScanResult) {
        let now = self.now
        var homes: [String: World.MinionHome] = [:]
        for m in minions.values { homes[m.id] = World.MinionHome(station: m.station, key: m.home.key, idle: !m.onJob) }
        newRooms = [:]
        let events = timed("scan") { world.applyScan(result, now: now, minionHomes: homes) }
        let firstRun = events.contains { if case .worldLoaded = $0 { return true }; return false }
        handle(events)
        let cfg = ConfigStore.shared.current
        var seen = Set<String>()
        let liveSessions = result.sessions.filter { s in
            Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) != "hidden"
                && now.timeIntervalSince(s.lastModified) < (s.isSubagent ? StationController.subagentWindow : StationController.activeWindow)
        }
        let liveIds = Set(liveSessions.map(\.id))
        for m in minions.values where !m.isCrew && !m.isSubagent && !liveIds.contains(m.id) && m.freeSince == 0 { m.freeSince = clock; m.busy = false; m.activity = .sleeping; clearPyramids(m) }
        for s in liveSessions {
            seen.insert(s.id)
            let stationName = Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo)
            let home = world.homeFor(s, station: stationName)
            var isNew = minions[s.id] == nil
            var reused = false
            if isNew && !s.isSubagent {
                if let free = minions.values.filter({ $0.station == stationName && !$0.isCrew && !$0.isSubagent && $0.freeSince > 0 && !$0.onJob })
                    .min(by: { $0.freeSince < $1.freeSince }) {
                    minions[free.id] = nil
                    free.id = s.id
                    free.node.name = "minion:" + s.id
                    free.node.enumerateChildNodes { c, _ in c.name = "minion:" + s.id }
                    free.freeSince = 0
                    if free.isQA { free.current = nil }
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
            if isNew && !s.isSubagent && newRooms[s.id] == nil && !firstRun { simulation.arriveByShuttle(m) }
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
                    let root = s.repoRoot
                    switch event {
                    case .prOpened:
                        logEvent("\(who) opened a pull request")
                        if let root { github.expect("openPRs:" + root); if let b = s.branch { github.expect("pull:" + root + "@" + b) }; github.expect("projectDelta", every: 10) }
                    case .merged:
                        logEvent("\(who) merged")
                        if let root { github.expect("openPRs:" + root); if let b = s.branch { github.expect("pull:" + root + "@" + b) }; github.expect("releases:" + root, for: 300, every: 30); github.expect("projectDelta", every: 10) }
                    case .pushed:
                        logEvent("\(who) pushed")
                        if let root { if let b = s.branch { github.expect("pull:" + root + "@" + b, for: 180, every: 30) }; github.expect("feed:" + root, every: 20) }
                    case .committed: logEvent("\(who) committed")
                    case .skill: if case .skill(let name) = s.activity { logEvent("\(who) used /\(name)") }
                    case .prompt: break
                    case .tool: continue
                    }
                    ringBell(seed: s.id.hashValue &+ event.rawValue.hashValue)
                }
            }
            m.markers = s.eventMarkers
            m.toolCount = s.toolCount
            m.promptCount = s.promptCount
            if !m.isSubagent {
                let want = min(5, s.queuedCount)
                var attempts = 0
                while m.queuedCones.count < want && attempts < 5 {
                    let before = m.queuedCones.count
                    addPyramid(for: m, queued: true)
                    attempts += 1
                    if m.queuedCones.count == before { break }
                }
                while m.queuedCones.count > s.queuedCount, let q = m.queuedCones.popLast() { q.removeFromParentNode() }
                arrangeQueuedCones(m)
            }
            if m.activity == .waiting || m.activity == .sleeping { clearPyramids(m) }

            if let key = newRooms[s.id], !m.onJob, !m.isSubagent, fleet.stations[stationName]?.hasHangar == true {
                simulation.startDelivery(m, roomKey: key)
            } else if !m.onJob {
                let place = restPlace(m)
                if place != m.place || isNew { send(m, to: place) }
            }
            if m.state == .leaving { m.state = .arriving; send(m, to: m.place) }
        }
        for m in minions.values where !seen.contains(m.id) && m.state != .leaving && m.isSubagent {
            m.state = .leaving; m.path = []
        }
        for station in fleet.stations.values {
            let workers = minions.values.filter { $0.station == station.name && !$0.isSubagent && !$0.isCrew && $0.state != .leaving }
            if workers.count < 2, !station.cells(of: .lounge).isEmpty {
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
            if minions.values.contains(where: { $0.station == station.name && $0.busy && !$0.isCrew }) { lastBusy[station.name] = clock }
            let night = isNight(station)
            let free = minions.values.filter { $0.station == station.name && $0.freeSince > 0 && $0.state != .leaving && !$0.isSubagent }
                .sorted { $0.freeSince < $1.freeSince }
            for (i, m) in free.enumerated() where !m.isQA {
                let longIdle = clock - m.freeSince > 20 * 60 && i >= 2
                let restPlace: Place = night ? .quarters : .lounge
                if longIdle || (i >= station.beds.count + station.couches.count) {
                    dismiss(m)
                    if let key = carriedRoom(of: m) { reveal(key); simulation.loseLoad(m) }
                } else if !m.onJob && !m.bathing && !m.isChore && m.place != restPlace && m.place != .bath && !(m.place == .lounge && restPlace == .quarters && m.bed == nil && night == false) {
                    m.activity = night ? .sleeping : .waiting
                    send(m, to: restPlace)
                }
            }
        }
        let pending = Set(minions.values.compactMap { m in newRooms[m.id].map { "\(m.station)|\($0)" } })
        for key in undelivered where !pending.contains(key) && world.truth.delivery(for: key) == nil {
            layoutDirty = true
            world.truth.officeDelivered(key)
            outlines.removeValue(forKey: key)?.removeFromParentNode()
            boxes.removeValue(forKey: key)?.removeFromParentNode()
        }
        if layoutDirty {
            flushScene(firstRun: firstRun)
            simulation.replanDeliveries()
        } else {
            flushScene()
        }
    }

    // MARK: peers

    func applySharing() {
        let cfg = ConfigStore.shared.current
        let name = cfg.shareName.isEmpty ? NSUserName() : cfg.shareName
        if cfg.shareOnLAN {
            if peers.isRunning, peers.name == name { return }
            peers.start(name: name)
        } else { peers.stop() }
    }

    private func makeSnapshot(withGitHub: Bool) -> PeerSnapshot? {
        let cfg = ConfigStore.shared.current
        guard let station = fleet.stations["work"] else { return nil }
        var offices: [PeerSnapshot.Office] = []
        for r in station.rooms.values where r.worktree != nil && !r.key.hasPrefix("kind:") && (r.repo.map { cfg.shared(repo: $0) } ?? false)
            && now.timeIntervalSince(r.lastActive) < World.roomsWindow {
            let key = roomKey(station, r)
            let pr = r.branch.flatMap { b in r.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }
            offices.append(PeerSnapshot.Office(key: r.key, name: r.name, repo: r.repo ?? "", branch: r.branch, color: r.color, cells: r.cells,
                                               pushed: r.branch != nil && !world.localState(r).local,
                                               startedAt: world.roomCreated[key] ?? .distantPast, lastActive: r.lastActive,
                                               boxes: lastBoxCount[key] ?? 0, dim: r.key.hasPrefix("proj:") || !(roomPower[key] ?? true),
                                               pull: pr?.number, pullState: pr?.state, review: pr?.reviewDecision, checks: pr?.checks))
        }
        let ms = minions.values.filter { $0.station == station.name && !$0.isCrew && $0.state != .leaving && cfg.shared(repo: $0.home.repo) && station.rooms[$0.home.key]?.worktree != nil }.map {
            PeerSnapshot.Minion(id: String(stableHash($0.id)), office: $0.home.key, asleep: $0.activity == .sleeping, busy: $0.busy,
                                activity: $0.activity.label, waiting: $0.activity == .waiting, cones: $0.pyramids.count + $0.queuedCones.count)
        }
        var knowledge: [GitHubResolver.Knowledge]?
        var board: GitHubResolver.ProjectKnowledge?
        if withGitHub {
            knowledge = world.repoRoots.filter { $0.value.station == "work" && cfg.shared(repo: $0.value.repo) }.compactMap { github.knowledge(repoRoot: $0.key, repo: $0.value.repo) }
            if let p = cfg.project { board = github.projectKnowledge(owner: p.owner, number: p.number) }
        }
        return PeerSnapshot(version: PeerSnapshot.current, name: peers.name, since: peers.since, offices: offices, minions: ms, github: knowledge, project: board, twoWay: true)
    }

    func receivePeer(_ snap: PeerSnapshot) {
        world.peerName = peers.name
        timed("peer") { handle(world.applyPeer(snap, now: now)) }
        flushScene()
        flushDeliveries()
        placePeerMinions(snap)
    }

    private func placePeerMinions(_ snap: PeerSnapshot) {
        let station = fleet.station("work")
        for m in snap.minions {
            if let crew = minions.values.first(where: { $0.isCrew && !$0.isPeer && $0.home.key == m.office }) {
                crew.peerFed = snap.name
                drive(crew, by: m, station: station)
                removePeerFigure("peer:\(snap.name)/\(m.id)")
                continue
            }
            let id = "peer:\(snap.name)/\(m.id)"
            let home = Home(key: m.office, name: snap.name, repo: "", issue: nil)
            let figure: Minion
            if let existing = minions[id] {
                figure = existing
            } else {
                let start = station.cells(of: .quarters).randomElement() ?? station.coreCenter
                figure = Minion(id: id, station: station.name, home: home, cwd: "", toolCount: 0,
                                isSubagent: false, start: start, crew: true)
                figure.isPeer = true
                figure.title = snap.name
                figure.node.opacity = 1
                minionRoot.addChildNode(figure.node)
                minions[id] = figure
            }
            drive(figure, by: m, station: station)
        }
        let live = Set(snap.minions.map { "peer:\(snap.name)/\($0.id)" })
        for id in minions.keys where id.hasPrefix("peer:\(snap.name)/") && !live.contains(id) { removePeerFigure(id) }
        let claimed = Set(snap.minions.map(\.office))
        for b in minions.values where b.peerFed == snap.name && !b.isPeer && !claimed.contains(b.home.key) { handBack(b) }
    }

    private func drive(_ b: Minion, by m: PeerSnapshot.Minion, station: Station) {
        b.busy = m.busy && !m.asleep
        b.activity = m.asleep ? .sleeping : (m.waiting == true ? .waiting : .coding(""))
        let want: Place = m.asleep ? restPlace(b) : (station.rooms[m.office] != nil ? .room(m.office) : .lounge)
        if b.place != want || b.path.isEmpty && b.state == .arriving { send(b, to: want) }
        let cones = m.asleep ? 0 : (m.cones ?? 0)
        guard b.pyramids.count + b.queuedCones.count != cones else { return }
        clearPyramids(b)
        b.queuedCones.forEach { $0.removeFromParentNode() }
        b.queuedCones = []
        guard cones > 0 else { return }
        addPyramid(for: b)
        for _ in 1..<max(1, cones) { addPyramid(for: b, queued: true) }
    }

    private func handBack(_ b: Minion) {
        b.peerFed = nil
        b.busy = false
        b.activity = .sleeping
        clearPyramids(b)
        send(b, to: .quarters)
    }

    private func removePeerFigure(_ id: String) {
        guard let m = minions[id] else { return }
        despawn(m)
    }

    func dropPeer(_ name: String) {
        for id in minions.keys where id.hasPrefix("peer:\(name)/") { removePeerFigure(id) }
        for b in minions.values where b.peerFed == name { handBack(b) }
        handle(world.dropPeer(name))
        flushScene()
    }

    // MARK: events

    private var layoutDirty = false
    private var drawnUnchecked: [String: Bool] = [:]
    private var wasLooking = true
    var lastRebuildAt = CACurrentMediaTime()

    var settlesView = true
    var floorSettling: Bool { settlesView && (world.stillLooking || CACurrentMediaTime() - lastRebuildAt < 1.5) }

    static let unlitOffice = 0.75
    var settlingHalf: SIMD2<Double> { SIMD2(20, 20) }

    private func lightRooms() {
        for st in fleet.stations.values {
            for room in st.rooms.values where !room.key.hasPrefix("kind:") {
                let key = roomKey(st, room)
                let unchecked = world.isUnchecked(st, room)
                guard drawnUnchecked[key] != unchecked else { continue }
                drawnUnchecked[key] = unchecked
                guard !unchecked, let tiles = roomTiles[key] else { continue }
                for t in tiles {
                    t.removeAllActions()
                    t.runAction(.fadeOpacity(to: 1, duration: 0.9))
                }
            }
        }
    }
    var markersDirty = false
    private var newRooms: [String: String] = [:]
    private var peerDeliveries: [String] = []

    func flushScene(firstRun: Bool = false) {
        timed("yards") { reconcileYards() }
        timed("lights") { lightRooms() }
        if wasLooking, !floorSettling {
            wasLooking = false
            if !userTookView { focusNow(on: focused) }
            timed("settle") { for st in fleet.stations.values { resettle(st) } }
        }
        if layoutDirty {
            if !headless {
                guard lastFloorFrame != frameNo else { return }
                lastFloorFrame = frameNo
            }
            layoutDirty = false; markersDirty = false
            timed("floor") { rebuildStatic() }
            if firstRun, !viewPinned, !world.simulated { restoreView() }
            if !floorSettling { timed("settle") { for st in fleet.stations.values { resettle(st) } } }
            refreshRockets()
        } else if markersDirty {
            markersDirty = false
            timed("markers") { rebuildMarkers() }
        }
    }

    private func flushDeliveries() {
        let station = fleet.station("work")
        for roomKey in peerDeliveries {
            let free = minions.values.filter { $0.station == station.name && !$0.isCrew && !$0.isSubagent && !$0.onJob && !$0.hasLoad && !$0.busy }
                .min(by: { $0.freeSince > $1.freeSince })
            if let m = free { simulation.startDelivery(m, roomKey: roomKey) } else { reveal(station.name + "|" + roomKey) }
        }
        peerDeliveries = []
        for d in pendingCrewDeliveries {
            if let m = minions["crew:" + d.login], !m.onJob { simulation.startDelivery(m, roomKey: d.key) } else { reveal(station.name + "|" + d.key) }
        }
        pendingCrewDeliveries = []
    }

    func handle(_ events: [WorldEvent]) { for e in events { handle(e) } }

    private func promptLanded(station: String, key: String, minionId: String, count: Int) {
        guard let m = minions[minionId], !m.isSubagent, count > 0 else { return }
        if let q = m.queuedCones.first { q.removeFromParentNode(); m.queuedCones.removeFirst() }
        addPyramid(for: m)
        arrangeQueuedCones(m)
    }

    func handle(_ event: WorldEvent) {
        sim?.onEvent?(event)
        if sim == nil { StationLog.write("event", SimulatorModel.describe(event)) }
        switch event {
        case .worldLoaded:
            break
        case .log(let text):
            logEvent(text)
        case .chime(let seed):
            ringBell(seed: seed)
        case .layoutChanged:
            layoutDirty = true
        case .markersChanged:
            markersDirty = true
        case .officeOpened(let station, let key, let source, let arrival):
            let full = station + "|" + key
            switch arrival {
            case .appear: break
            case .fade: fadeIn.insert(full)
            case .shuttle:
                world.truth.officeOrdered(full)
                switch source {
                case .session(let id): newRooms[id] = key
                case .peer: peerDeliveries.append(key)
                case .github(let who), .board(let who): pendingCrewDeliveries.append((who, key))
                }
            }
        case .officeRenamed(let station, let from, let to, let name, let session, let promoted):
            let oldKey = "\(station)|\(from)", newKey = "\(station)|\(to)"
            if promoted {
                world.truth.officeOrdered(newKey)
                newRooms[session] = to
                logEvent("\(name): branch created, office ordered")
            }
            world.truth.renameOffice(from: oldKey, to: newKey)
            if let o = outlines.removeValue(forKey: oldKey) { outlines[newKey] = o }
            if let b = boxes.removeValue(forKey: oldKey) { boxes[newKey] = b }
            if let m = minions[session], m.place == .room(from) { m.place = .room(to) }
        case .officeArchived(let station, let key, let roomKey, let name, let hall, let announce, let reason):
            archive(station: station, key: key, roomKey: roomKey, name: name, hall: hall, announce: announce, reason: reason)
        case .officeMerged(let stationName, let key, let repo, let number):
            guard let station = fleet.stations[stationName], let room = station.rooms[key] else { return }
            haulMergedBoxes(station: station, key: stationName + "|" + key, roomName: room.name, repo: repo, number: number)
        case .carryToDeck(let stationName, let repo, let commands):
            guard let station = fleet.stations[stationName] else { return }
            stageCargo(station: station, repo: repo, commands: commands)
        case .crateCleared(let stationName, let repo, let number):
            guard let station = fleet.stations[stationName] else { return }
            carryAcrossDeck(station: station, repo: repo, number: number)
        case .crewRoster(let members):
            setCrewRoster(members)
        case .deconArrived(let stationName, let repo, let numbers):
            hatchBlink(station: stationName)
            for n in numbers { incoming.insert("decon:\(stationName)|\(repo)|\(n)") }
        case .deconCleared(let stationName, let repo, let number):
            guard let station = fleet.stations[stationName] else { return }
            haulCleared(station: station, repo: repo, number: number)
        case .crewActivity(let a):
            playCrew(a)
        case .stagingOpened(let stationName, let repo, let number):
            simulation.stagingOpened(station: stationName, repo: repo, number: number)
        case .stagingMerged(let stationName, let repo, let number):
            logEvent("\(repo): staging release #\(number) merged")
            simulation.stagingMerged(station: stationName, repo: repo, number: number)
            if let st = fleet.stations[stationName] { stageCargo(station: st, repo: repo) }
        case .stagingClosed(let stationName, let repo, let number):
            logEvent("\(repo): staging release #\(number) closed, not merged")
            simulation.stagingClosed(station: stationName, repo: repo, number: number)
        case .releaseOpened, .releaseMerged(_, _, _, _, _, true):
            break
        case .releaseMerged(let stationName, let repo, _, _, _, false):
            if ConfigStore.shared.current.project == nil, let st = fleet.stations[stationName] { stageCargo(station: st, repo: repo) }
        case .rocketCommand(let stationName, let repo, let label, let untested, let tall, let cargo, let command):
            simulation.rocket(station: stationName, repo: repo, label: label, untested: untested, tall: tall, cargo: cargo, command: command)
        case .prompt(let stationName, let key, let minionId, let count):
            promptLanded(station: stationName, key: key, minionId: minionId, count: count)
        case .crewHidden:
            for m in minions.values where m.isCrew && !m.isPeer { despawn(m) }
        case .boardMoved(let item, let from, let to):
            guard let info = world.repoRoots.values.first(where: { $0.repo == item.repo }), let station = fleet.stations[info.station] else { return }
            let st = ConfigStore.shared.current.statuses
            let label = "#\(item.number) \(item.title.prefix(36))"
            switch to {
            case .deck where from == st.storage:
                logEvent("\(label): on staging, to the deck")
                markersDirty = true
            case .cleared:
                logEvent("\(label): passed QA, ready to ship")
            case .shipped where from != nil:
                logEvent("\(label): shipped")
            case .storage where from == st.development:
                logEvent("\(label): merged, ready for staging")
            case .development where from != nil && from != st.development:
                logEvent("\(label): in development")
            default: break
            }
        case .pullRequestOpened(let repo, let number, let author, let roomKey):
            logEvent("\(world.crewName(author)) opened #\(number) \(repo)")
            if let m = minions.values.first(where: { !$0.isCrew && !$0.isSubagent && !$0.isPeer && $0.home.key == roomKey }),
               let st = fleet.stations[m.station], let room = st.rooms[roomKey] {
                let key = m.station + "|" + roomKey
                packing.insert(key)
                markerRoot.childNodes.filter { $0.name == "box:" + key }.forEach { $0.opacity = 0 }
                simulation.post(.pack(office: roomKey), for: m, rank: .yard, at: standCell(st, near: packageCell(st, room)), place: .room(roomKey), announce: true)
            }
        case .issueStarted(let repo, let number, let author, _):
            logEvent("\(world.crewName(author)) started #\(number) \(repo)")
        case .deployStarted(let stationName, let repo, true, let expected, let release, let elapsed):
            beginMission(station: stationName, repo: repo, expected: expected, release: release, elapsed: elapsed)
        case .deployEnded(_, let repo, true, let outcome):
            endMission(repo: repo, outcome: outcome)
        case .deployStarted(let stationName, let repo, false, let expected, _, let elapsed):
            simulation.stagingDeploy(station: stationName, repo: repo, outcome: nil, usual: expected, elapsed: elapsed)
        case .deployEnded(let stationName, let repo, false, let outcome):
            simulation.stagingDeploy(station: stationName, repo: repo, outcome: outcome)
        case .pullRequestClosed(let repo, let author, _):
            if let m = minions["crew:" + author], !m.onJob {
                react(m, .shipping, place: .core, minutes: 4, words: "\(world.crewName(author)) shipping \(repo)")
            }
        case .peerArrived(let name):
            logEvent("\(name) is in range")
        case .peerLeft(let name):
            logEvent("\(name) is out of range")
        }
    }

    // MARK: tick

    private var timers: [(at: Double, run: () -> Void)] = []
    func after(_ seconds: Double, _ run: @escaping () -> Void) { timers.append((clock + seconds, run)) }

    func tick(now: TimeInterval) {
        let dt = min(0.1, max(0, now - lastTick))
        lastTick = now
        var budget = dt * (sim == nil ? liveTimeScale : 1)
        while budget > 1e-9 {
            let step = min(budget, 1.0 / 30.0)
            budget -= step
            stepStation(dt: step)
        }
        if !headless { tickView(dt: dt) }
        offerSnapshot(now: now)
    }

    private var lastOffer: TimeInterval = 0
    private var offers = 0
    private func offerSnapshot(now: TimeInterval) {
        guard peers.isRunning, now - lastOffer >= 3 else { return }
        lastOffer = now
        offers += 1
        if let snap = makeSnapshot(withGitHub: offers % 10 == 1) { peers.offer(snap) }
    }

    private func stepStation(dt: Double) {
        clock += dt
        if !timers.isEmpty {
            let due = timers.filter { $0.at <= clock }
            timers.removeAll { $0.at <= clock }
            due.forEach { $0.run() }
        }
        if demo { tickDemo(dt: dt) }
        if Int(clock) != Int(clock - dt) { updatePower() }
        stepMission()
        if clock - lastHaulSchedule > 0.5 {
            lastHaulSchedule = clock
            simulation.assignOrders()
            simulation.stepRockets()
            simulation.reconcileBodies()
            if simulation.contractHallways() { layoutDirty = true }
            flushScene()
            timed("obstacles") { refreshObstacles() }
            simulation.replanBlockedWalks()
        }
        simulation.stepShuttles()
        simulation.stepTips(dt: dt)
        simulation.stepVortices()
        simulation.stepDrones(dt: dt)
        drawShuttles(dt: dt)
        tickHangars()
        tickUndocking()
        updateBerths()
        tickHullLamps()
        drawRockets()
        tickSparks(dt: dt)
        turnPlanets(dt: dt)
        drawDrones(dt: dt)
        tickPuffs(dt: dt)
        tickPadFields()
        drawVortices()
        tickCrateMotions()
        if Int(clock) % 5 == 0 && Int(clock - dt) % 5 != 0 {
            for name in world.stalePeers(olderThan: World.peerQuiet) { dropPeer(name) }
        }
        if Int(clock) % 2 == 0 && Int(clock - dt) % 2 != 0 {
            var load: [Int: Int] = [:]
            for m in minions.values where m.busy && !m.isCrew && !m.isSubagent && m.state != .leaving {
                if let i = fleet.repoColors[m.home.repo] { load[i % Colors.repos.count, default: 0] += 1 }
            }
            drone.setWorkload(load)
        }
        tickMinions(dt: dt)
    }

    private func tickView(dt: Double) {
        if hud.size != viewSize { hud.size = viewSize }
        let seen = (view.window?.occlusionState.contains(.visible) ?? true) && !headless
        let want = !seen ? 8 : (walker != nil || userDriving > 0 || keyMove != .zero || keyZoom != 0 ? 60 : 30)
        if view.preferredFramesPerSecond != want { view.preferredFramesPerSecond = want }
        fpsFrames += 1
        fpsWorst = max(fpsWorst, dt)
        let wall = CACurrentMediaTime()
        if wall - fpsMark >= 0.5 {
            let rate = Double(fpsFrames) / max(0.05, wall - fpsMark)
            fpsLabel.text = String(format: "%.0f fps of %d · slowest %.0f ms", rate, want, fpsWorst * 1000)
            fpsLabel.position = CGPoint(x: 84, y: hud.size.height - 9)
            fpsFrames = 0; fpsMark = wall; fpsWorst = 0
        }
        if !tickWalk(dt: dt, move: keyMove, turn: keyZoom) {
        if keyMove != .zero {
            let speed = Double(viewSize.height) * 0.7 * dt
            pan(byPixels: -keyMove.x * speed, keyMove.y * speed)
        }
        if keyZoom != 0 {
            userZoom = min(6, max(0.4, userZoom * exp(keyZoom * dt * 0.7)))
            userZoomChanged = true
        }

        if let id = following {
            if let m = minions[id], m.state != .leaving || m.opacity > 0.05 {
                userPan = SIMD2(Double(m.node.position.x), Double(m.node.position.z)) - targetFocus
            } else { following = nil }
        }
        let k = 1 - exp(-dt * 2)
        let focus = targetFocus + userPan
        let kp = userDriving > 0 ? 1 - exp(-dt * 25) : k
        if userDriving > 0 { userDriving -= dt }
        if floorSettling {
            rig.position.x = focus.x; rig.position.z = focus.y
        } else {
            rig.position.x += (focus.x - Double(rig.position.x)) * kp
            rig.position.z += (focus.y - Double(rig.position.z)) * kp
        }
        let ky = 1 - exp(-dt * 10)
        rig.eulerAngles.y += (viewYaw + userYaw - Double(rig.eulerAngles.y)) * ky
        pitchNode.eulerAngles.x += (userPitch - Double(pitchNode.eulerAngles.x)) * ky
        if floorSettling {
            cameraNode.camera!.orthographicScale = fitScale(half: settlingHalf) / userZoom
        } else {
            let wantScale = fitScale(half: targetHalf) / userZoom
            let scaleK = abs(userZoom - 1) > 0.001 || userZoomChanged ? 1 - exp(-dt * 14) : k
            cameraNode.camera!.orthographicScale += (wantScale - cameraNode.camera!.orthographicScale) * scaleK
        }
        userZoomChanged = false
        }

        for (n, vel) in debris {
            var p = SIMD2(Double(n.position.x), Double(n.position.z)) + vel * dt
            let c = targetFocus
            if p.x > c.x + 40 { p.x -= 80 } else if p.x < c.x - 40 { p.x += 80 }
            if p.y > c.y + 40 { p.y -= 80 } else if p.y < c.y - 40 { p.y += 80 }
            n.position.x = p.x; n.position.z = p.y
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
        fadeOverlay()
        updateBubble()
        if sim == nil, clock - lastSavedView > 2 { lastSavedView = clock; saveView() }
    }

    func applyConfigChange(from old: AppConfig, to new: AppConfig) {
        applySharing()
        var renamed = old
        renamed.shareName = new.shareName
        guard renamed != new else { return }
        enqueue { [self] in
            let cfg = ConfigStore.shared.current
            if Looks.theme != cfg.theme {
                Looks.use(cfg.theme)
                buildBackdrop()
                for v in rocketViews.values { v.node.removeFromParentNode() }
                rocketViews = [:]
                for v in shuttleViews.values { v.node.removeFromParentNode() }
                shuttleViews = [:]
            }
            for m in Array(minions.values) { despawn(m) }
            world.reset()
            world.fleet.recolorRooms()
            github.intervalMinutes = cfg.githubMinutes
            layoutDirty = true
            rebuildStatic()
            rescan()
        }
    }

    var knownRepos: [String] { world.knownRepos }
    var repoDetails: [String: RepoDetail] {
        var out: [String: RepoDetail] = [:]
        for (root, info) in world.repoRoots.sorted(by: { $0.key < $1.key }) where out[info.repo] == nil {
            let p = github.detectedPipeline(repoRoot: root)
            out[info.repo] = RepoDetail(path: root, remote: github.nameWithOwner(repoRoot: root), detected: p.source == "settings" ? nil : p,
                                        workflow: world.workflow(repo: info.repo))
        }
        return out
    }
    var seenPeople: [String: SeenPerson] { world.seenPeople }

    func refreshGitHub() {
        guard Date().timeIntervalSince(askedGitHubAt) > 3 else { return }
        askedGitHubAt = Date()
        enqueue { [self] in
            github.invalidate()
            for station in fleet.stations.values {
                for room in station.rooms.values {
                    if let b = room.branch, let r = room.repoRoot { github.refresh(branch: b, repoRoot: r) }
                    if let w = room.worktree { github.refreshCommits(worktree: w) }
                }
            }
            github.intervalMinutes = ConfigStore.shared.current.githubMinutes
        for (root, info) in world.repoRoots {
            github.refreshReleases(repoRoot: root)
            if info.station == "work" { github.refreshFeed(repoRoot: root); github.refreshOpenPRs(repoRoot: root) }
        }
            logEvent("asking github…")
        }
    }

    func quiesce() {
        timer?.invalidate(); timer = nil
        watcher = nil
        drone.isEnabled = false
        view.isPlaying = false
        view.delegate = nil
        view.scene = nil
    }

    func snapshot(to path: String) {
        let image = composedSnapshot()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    func composedSnapshot() -> NSImage {
        let image = view.snapshot()
        let overlays = view.subviews.filter { !$0.isHidden }
        if !overlays.isEmpty {
            image.lockFocus()
            let scale = image.size.width / max(1, view.bounds.width)
            for v in overlays {
                let at = NSRect(x: v.frame.minX * scale, y: v.frame.minY * scale, width: v.frame.width * scale, height: v.frame.height * scale)
                if let pip = v as? SCNView { pip.snapshot().draw(in: at, from: .zero, operation: .sourceOver, fraction: 1); continue }
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                rep.draw(in: NSRect(x: v.frame.minX * scale, y: v.frame.minY * scale, width: v.frame.width * scale, height: v.frame.height * scale),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            image.unlockFocus()
        }
        return image
    }
}
