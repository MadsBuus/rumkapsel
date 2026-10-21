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
    static let padFloor = NSColor(rgb: (0.270, 0.292, 0.345))
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
        writeTally(now)
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
        let t0 = CACurrentMediaTime()
        defer {
            let spent = CACurrentMediaTime() - t0
            tallied(name, spent)
            if Trace.frames { phases.append((name, spent)) }
        }
        return body()
    }

    private func tallied(_ name: String, _ spent: Double) {
        var t = tally[name] ?? (0, 0, 0)
        t.count += 1; t.total += spent; t.worst = max(t.worst, spent)
        tally[name] = t
    }

    private var tally: [String: (count: Int, total: Double, worst: Double)] = [:]
    private var tallySince = CACurrentMediaTime()

    private func writeTally(_ now: TimeInterval) {
        guard now - tallySince >= 60 else { return }
        tallySince = now
        let line = tally.filter { $0.value.worst > 0.001 }.sorted { $0.value.total > $1.value.total }
            .map { String(format: "%@ %d× avg %.1fms max %.0fms", $0.key, $0.value.count, $0.value.total / Double($0.value.count) * 1000, $0.value.worst * 1000) }
            .joined(separator: " · ")
        tally = [:]
        if sim == nil, !line.isEmpty { StationLog.write("timing", line) }
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
    var foldCrates: [String: SCNNode] = [:]
    var ownerSigns: [String: SCNNode] = [:]
    var officeParts: [String: [(node: SCNNode, base: Double?)]] = [:]
    var newestCube: [String: SCNNode] = [:]
    var boxes: [Int: SCNNode] = [:]
    let beamRoot = SCNNode()
    let rocketRoot = SCNNode()
    var rocketViews: [String: RocketView] = [:]
    var sparks: [Spark] = []
    var undocking: [(node: SCNNode, since: Double, from: SCNVector3?)] = []
    var shuttleViews: [ObjectIdentifier: ShuttleView] = [:]
    var lastBoxCount: [String: Int] = [:]
    var markerSignatures: [String: String] = [:]
    var packages: [String: SCNNode] = [:]
    var packageBuilt: [String: String] = [:]
    var crateMotions: [ObjectIdentifier: CrateMotion] = [:]
    private var localSignature = ""
    var hangarAnchors: [String: SCNNode] = [:]
    var gymProps: [String: (bar: SCNNode, bag: SCNNode)] = [:]
    var kitchens: [String: Kitchen] = [:]
    private var lastBusy: [String: Double] = [:]
    var stationAnchors: [String: SCNNode] = [:]
    var knownSpine: [String: Int] = [:]
    var knownHall: [String: [Cell]] = [:]
    let peers = PeerHub()
    private let peerRoot = SCNNode()
    var peerFigures: Int { minions.values.filter(\.isPeer).count }
    private var peerColorBook: [String: RGB] = [:]
    var roomPower: [String: Bool] = [:]
    var roomLight: [String: OfficeLight] = [:]
    var cargo: [Int: Cargo] {
        get { simulation.cargo }
        set { simulation.cargo = newValue }
    }
    var crateNodes: [String: SCNNode] = [:]
    var crateLooks: [String: String] = [:]
    var appearing: Set<String> = []
    var droneRacks: [String: SCNNode] = [:]
    var fields: [String: HangarField] = [:]
    var padFields: [String: HangarField] = [:]
    var vortexViews: [String: VortexView] = [:]
    var padRings: [String: SCNNode] = [:]
    var padsDrawn = ""
    var droneViews: [String: DroneView] = [:]
    var puffs: [Puff] = []
    static let powerWindow: TimeInterval = 2 * 3600
    var beams: [String: SCNNode] = [:]
    let infoLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    let infoBackground = SKSpriteNode(color: Palette.void.withAlphaComponent(0.85), size: CGSize(width: 1, height: 1))
    let statusLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    let followLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    let bubbleLabel = SKLabelNode(fontNamed: "HelveticaNeue")
    let bubbleName = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    let bubblePlate = SKSpriteNode(color: Palette.void.withAlphaComponent(0.9), size: CGSize(width: 1, height: 1))
    var bubbleIcons: [SKSpriteNode] = []
    var hatchLights: [String: SCNNode] = [:]
    private var askedGitHubAt = Date.distantPast
    let bubbleLock = NSLock()
    var bubbleHits: (minion: String, plate: CGRect, hold: CGRect, icons: [CGRect])?
    var bubbleCursor: CGPoint?
    var legendNodes: [SKNode] = []
    var jobNodes: [SKNode] = []
    var hudClock = 0.0
    var legendSignature = ""
    var eventLabels: [(SKLabelNode, Double)] = []
    var flights: [MissionFeed] = []
    var loadingFlights: [Mission] = []
    var missions: [Mission] { flights.map(\.mission) + loadingFlights }
    var walker: Walker?
    var rehearsals = 0
    let planetRoot = SCNNode()
    var planets: [String: SCNNode] = [:]
    var spaceLogButton: SpaceLogButton?
    var spaceLogPanel: SpaceLogPanel?
    var spaceLogClock = -100.0
    var spaceLogOpen = false
    var spaceLogDrawnAt = 0.0
    var spaceLogCorner: CGFloat = 0
    var neighboursButton: NeighboursButton?
    var neighboursPanel: NeighboursPanel?
    var neighboursOpen = false
    var storyPanel: CrateStoryPanel?
    var storyOf: (station: String, id: CrateID)?
    var storyClock = 0.0
    var setupCard: SetupCard?
    var cardFacts: SetupCardFacts?
    var answeredCards: Set<String> = []
    var onChangeRepo: ((String) -> Void)?
    let setupLabel = SKLabelNode()
    let setupPlate = SKSpriteNode()
    var setupProblems: [String] = []
    var hovered: String?
    var following: String?
    private var lastTick = 0.0
    private var lastWall: Date?
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
    var demoLaunched = false

    static let activeWindow: TimeInterval = 60 * 60
    static let busyWindow: TimeInterval = 90
    static let replyWindow: TimeInterval = 20
    static let sleepWindow: TimeInterval = 5 * 60
    static let subagentWindow: TimeInterval = 3 * 60
    static let scanWindow: TimeInterval = 14 * 24 * 3600

    static let inkOnTile = NSColor(rgb: (0.03, 0.03, 0.05))

    let padHexRoot = SCNNode()
    let padLiftRoot = SCNNode()
    var padLifts: [String: PadLiftView] = [:]
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
        simulation.live = !simulated
        view = StationView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        hud = SKScene(size: frame.size)
        super.init()
        simulation.onBeat = { [weak self] in self?.beat(contracted: $0) }
        simulation.onStep = { [weak self] in self?.drawStation(dt: $0) }
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
        view.hudTakesPoint = { [weak self] p in self?.spaceLogTakes(point: p) == true || self?.storyTakes(point: p) == true || self?.cardTakes(point: p) == true || self?.missionTakes(point: p) == true || self?.bubbleTakes(point: p) == true }
        view.onHUDClick = { [weak self] p in self?.bubbleClick(at: p) ?? false }
        view.onDoubleClick = { [weak self] node, floor in
            let n = node?.name ?? ""
            self?.enqueue {
                if n.hasPrefix("minion:") { self?.poke(minionId: String(n.dropFirst(7))) }
                else if ["room:", "box:", "rocket:"].contains(where: n.hasPrefix) { self?.open(named: n) }
                else if let (_, id) = StationController.crate(named: n) { self?.openCrate(id) }
                else if let floor, self?.walker == nil { self?.stepIn(at: floor) }
            }
        }
        view.onClick = { [weak self] node in
            if let self { DispatchQueue.main.async { for f in self.flights where f.size > 0 { self.setSize(f, 0) } } }
            let n = node?.name ?? ""
            if StationController.crate(named: n) == nil && !n.hasPrefix("box:") { self?.closeStory() }
            if n.hasPrefix("minion:") {
                let id = String(n.dropFirst(7))
                self?.enqueue { if self?.walker != nil { self?.ride(minionId: id) } else { self?.follow(minionId: id) } }
                return
            }
            self?.enqueue { self?.following = nil }
            guard !n.isEmpty else { return }
            if StationController.crate(named: n) != nil || n.hasPrefix("box:") {
                self?.enqueue {
                    if let (station, id) = self?.storyCrate(named: n) { self?.openStory(station, id) } else { self?.open(named: n) }
                }
                return
            }
            guard n.hasPrefix("rocket:") else { return }
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
        github.front = NSApp.isActive
        for (name, front) in [(NSApplication.didBecomeActiveNotification, true), (NSApplication.didResignActiveNotification, false)] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.github.front = front }
        }
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
                if neighboursPanel?.isHidden == false { toggleNeighbours() }
                if storyPanel?.isHidden == false { closeStory() }
            case "l": toggleSpaceLog()
            case "n": toggleNeighbours()
            case "g": refreshGitHub()
            default: return false
            }
            return true
        }
        view.delegate = self

        simulation.onEvent = { [weak self] event in self?.handle(event) }
        simulation.onLog = { [weak self] text in self?.logEvent(text) }
        peers.onSnapshot = { [weak self] snap in self?.enqueue { self?.receivePeer(snap) } }
        if !simulated { applySharing() }
        if !simulated && !demo { installSpaceLog(); installNeighbours() }
        installStory()
        installCard()
        if !simulated { Bulkhead.prepare() }
        if demo {
            seedDemo()
        } else if !simulated {
            rescan()
            let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects").path
            watcher = DirectoryWatcher(path: projects) { [weak self] _ in self?.rescan() }
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
            let checks = r.branch.flatMap { b in r.repoRoot.flatMap { github.pulls.pull(branch: b, repoRoot: $0)?.checks } } ?? ""
            return "\(st.name)|\(r.key):\(l.local):\(l.commits > 0):\(checks)"
        } }.sorted().joined()
        timed("github") { handle(world.applyGitHub(now: now, timed: { n, b in self.timed(n, b) })) }
        if world.placementsLeft { enqueue { [weak self] in self?.onGitHubUpdate() } }
        handle(world.reconcileYards())
        if sig != localSignature { localSignature = sig; layoutDirty = true } else { markersDirty = true }
        refreshRockets()
        flushScene()
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
            let t0 = CACurrentMediaTime()
            let result = scanner.scan(roomsWithin: StationController.scanWindow)
            let spent = CACurrentMediaTime() - t0
            self.enqueue { self.tallied("transcripts", spent); self.apply(result) }
        }
    }

    func apply(_ result: ScanResult) {
        let now = self.now
        var homes: [String: World.MinionHome] = [:]
        for m in minions.values { homes[m.id] = World.MinionHome(station: m.station, key: m.home.key, idle: !m.onJob) }
        let events = timed("scan") { world.applyScan(result, now: now, minionHomes: homes) }
        let firstRun = events.contains { if case .worldLoaded = $0 { return true }; return false }
        let ordered = Set(events.compactMap { e -> String? in
            if case .office(_, .opened(_, _, .shuttle(let who?)), _) = e { return who }
            return nil
        })
        handle(events)
        github.worked = result.sessions.map(\.lastModified).max() ?? .distantPast
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
            if isNew && !s.isSubagent && !ordered.contains(s.id) && !firstRun { simulation.arriveByShuttle(m) }
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
                        if let root { github.ring(repoRoot: root) }
                    case .merged:
                        logEvent("\(who) merged")
                        if let root { github.ring(repoRoot: root) }
                    case .pushed:
                        logEvent("\(who) pushed")
                        if let root { github.ring(repoRoot: root) }
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
                while m.queued.count < want && attempts < 5 {
                    let before = m.queued.count
                    addPyramid(for: m, queued: true)
                    attempts += 1
                    if m.queued.count == before { break }
                }
                if m.queued.count > s.queuedCount { m.queued.removeLast(m.queued.count - s.queuedCount) }
                arrangeQueuedCones(m)
                drawCones(m)
            }
            if m.activity == .waiting || m.activity == .sleeping { clearPyramids(m) }

            if !m.onJob {
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
                } else if !m.onJob && !m.bathing && !m.isChore && m.place != restPlace && m.place != .bath && !(m.place == .lounge && restPlace == .quarters && m.bed == nil && night == false) {
                    m.activity = night ? .sleeping : .waiting
                    send(m, to: restPlace)
                }
            }
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

    func makeSnapshot(withGitHub: Bool) -> PeerSnapshot? {
        let cfg = ConfigStore.shared.current
        guard let station = fleet.stations["work"] else { return nil }
        var offices: [PeerSnapshot.Office] = []
        for r in station.rooms.values where r.worktree != nil && !r.key.hasPrefix("kind:") && (r.repo.map { cfg.shared(repo: $0) } ?? false)
            && now.timeIntervalSince(r.lastActive) < World.roomsWindow {
            let key = roomKey(station, r)
            let pr = r.branch.flatMap { b in r.repoRoot.flatMap { github.pulls.pull(branch: b, repoRoot: $0) } }
            offices.append(PeerSnapshot.Office(key: r.key, name: r.name, repo: r.repo ?? "", branch: r.branch, color: r.color, cells: r.cells,
                                               pushed: r.branch != nil && !world.localState(r).local,
                                               startedAt: world.roomCreated[key] ?? .distantPast, lastActive: r.lastActive,
                                               boxes: lastBoxCount[key] ?? 0, dim: r.key.hasPrefix("proj:") || !(roomPower[key] ?? true),
                                               pull: pr?.number, pullState: pr?.state, review: pr?.reviewDecision, checks: pr?.checks))
        }
        let ms = minions.values.filter { $0.station == station.name && !$0.isCrew && $0.state != .leaving && cfg.shared(repo: $0.home.repo) && station.rooms[$0.home.key]?.worktree != nil }.map {
            PeerSnapshot.Minion(id: String(stableHash($0.id)), office: $0.home.key, asleep: $0.activity == .sleeping, busy: $0.busy,
                                activity: $0.activity.label, waiting: $0.activity == .waiting, cones: $0.cones.count,
                                doing: doing($0), callsign: $0.callsign)
        }
        var knowledge: [PullSource.Knowledge]?
        var board: GitHubResolver.ProjectKnowledge?
        if withGitHub {
            knowledge = world.repoRoots.filter { $0.value.station == "work" && cfg.shared(repo: $0.value.repo) }.compactMap { github.pulls.knowledge(repoRoot: $0.key, repo: $0.value.repo) }
            if let p = cfg.project { board = github.projectKnowledge(owner: p.owner, number: p.number) }
        }
        let colors = fleet.repoColors.filter { cfg.shared(repo: $0.key) && cfg.repos[$0.key]?.color == nil }
        return PeerSnapshot(version: PeerSnapshot.current, name: peers.name, since: peers.since, offices: offices.sorted { $0.key < $1.key },
                            minions: ms.sorted { $0.id < $1.id }, github: knowledge, project: board, twoWay: true,
                            colors: colors.isEmpty ? nil : colors)
    }

    private func doing(_ m: Minion) -> String? {
        switch m.current?.kind {
        case .exercise: return "gym"
        case .bath(let kind, _, _): return kind == .shower ? "shower" : "bath"
        case .chore: return "roam"
        case .galley(let fare, _, _): return fare == .coffee ? "coffee" : "bite"
        default: return m.place == .lounge && m.activity != .sleeping ? "lounge" : nil
        }
    }

    func receivePeer(_ snap: PeerSnapshot) {
        world.peerName = peers.name
        timed("peer") { handle(world.applyPeer(snap, now: now)) }
        flushScene()
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
            let repo = snap.offices.first { $0.key == m.office }?.repo ?? station.rooms[m.office]?.repo ?? ""
            let home = Home(key: m.office, name: snap.name, repo: repo, issue: nil)
            let figure: Minion
            if let existing = minions[id] {
                figure = existing
                figure.home = home
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
            figure.sharedCallsign = m.callsign
            if !headless { figure.wearSuit(badge: NSColor(fleet.color(forRepo: repo))) }
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
        func go(_ want: Place) {
            if b.bathing || b.exercising || b.choring { simulation.finish(b, to: want); return }
            if b.place != want || b.path.isEmpty && b.state == .arriving { send(b, to: want) }
        }
        switch m.asleep ? nil : m.doing {
        case "gym":
            if !b.exercising {
                if b.bathing || b.choring { simulation.finish(b, to: .gym) }
                if !(station.rooms["kind:gym"].map { takeTurnInGym(b, station: station, gym: $0) } ?? false) { go(.lounge) }
            }
        case "bath", "shower":
            if !b.bathing {
                if b.exercising || b.choring { simulation.finish(b, to: .bath) }
                b.showering = m.doing == "shower"
                if !visitBath(b, station: station) { go(.lounge) }
            }
        case "roam":
            if !b.choring {
                if b.bathing || b.exercising { simulation.finish(b, to: .lounge) }
                if !startRoam(b, station: station) { go(.lounge) }
            }
        case "coffee", "bite":
            if b.fare == nil {
                if b.bathing || b.exercising || b.choring { simulation.finish(b, to: .lounge) }
                if !visitGalley(b, station: station, fare: m.doing == "coffee" ? .coffee : .bite) { go(.lounge) }
            }
        case "lounge":
            go(.lounge)
        default:
            go(m.asleep ? restPlace(b) : (station.rooms[m.office] != nil ? .room(m.office) : .lounge))
        }
        let cones = m.asleep ? 0 : (m.cones ?? 0)
        guard b.cones.count != cones else { return }
        clearPyramids(b)
        b.queued = []
        drawCones(b)
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

    var layoutDirty = false
    private var drawnUnchecked: [String: Bool] = [:]
    private var wasLooking = true
    var lastRebuildAt = CACurrentMediaTime()

    var settlesView = true
    var floorSettling: Bool { settlesView && (world.stillLooking || CACurrentMediaTime() - lastRebuildAt < 1.5) }

    static let unlitOffice = 0.75
    var settlingHalf: SIMD2<Double> { SIMD2(20, 20) }

    private func lightRooms() {
        for st in fleet.stations.values {
            for (k, o) in shownOffices(st) {
                let key = st.name + "|" + k
                let unchecked = o.look.unchecked
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

    func flushScene(firstRun: Bool = false) {
        timed("yards") { handle(world.reconcileYards()) }
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

    func handle(_ events: [WorldEvent]) { for e in events { handle(e) } }

    private func promptLanded(station: String, key: String, minionId: String, count: Int) {
        guard let m = minions[minionId], !m.isSubagent, count > 0 else { return }
        if !m.queued.isEmpty { m.queued.removeFirst() }
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
        case .office:
            break
        case .crewRoster(let members):
            setCrewRoster(members)
        case .crewActivity(let a):
            playCrew(a)
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
        case .pullRequestOpened(let repo, let number, let author):
            logEvent("\(world.crewName(author)) opened #\(number) \(repo)")
        case .issueStarted(let repo, let number, let author, _):
            logEvent("\(world.crewName(author)) started #\(number) \(repo)")
        case .deployStarted(let stationName, let repo, true, let expected, let release, let elapsed):
            beginMission(station: stationName, repo: repo, expected: expected, release: release, elapsed: elapsed)
        case .deployEnded(_, let repo, true, let outcome):
            endMission(repo: repo, outcome: outcome)
        case .deployStarted(_, _, false, _, _, _), .deployEnded(_, _, false, _):
            break
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

    func after(_ seconds: Double, _ run: @escaping () -> Void) { simulation.after(seconds, run) }

    func tick(now: TimeInterval) {
        let frame = max(0, now - lastTick)
        lastTick = now
        simulation.held = headless ? nil : hovered.flatMap { $0.hasPrefix("minion:") ? String($0.dropFirst(7)) : nil }
        if sim == nil {
            let wall = Date()
            let dt = max(0, wall.timeIntervalSince(lastWall ?? simulation.epoch)) * liveTimeScale
            simulation.step(dt: dt > Tempo.catchUp ? dt : min(dt, Tempo.frame))
            lastWall = wall
        } else {
            simulation.step(dt: frame)
        }
        if !headless { tickView(dt: min(0.1, frame)) }
        offerSnapshot(now: now)
    }

    private var lastOffer: TimeInterval = 0
    private var lastGitHubOffer: TimeInterval = -.infinity
    private func offerSnapshot(now: TimeInterval) {
        guard peers.isRunning, now - lastOffer >= 0.5 else { return }
        lastOffer = now
        let withGitHub = now - lastGitHubOffer >= 30
        if withGitHub { lastGitHubOffer = now }
        if let snap = makeSnapshot(withGitHub: withGitHub) { peers.offer(snap) }
    }

    func beat(contracted: Bool) {
        if contracted { layoutDirty = true }
        flushScene()
    }

    func drawStation(dt: Double) {
        if demo { tickDemo(dt: dt) }
        if Int(clock) != Int(clock - dt) { updatePower() }
        stepMission()
        if !headless {
            drawShuttles(dt: dt)
            tickHangars()
            tickUndocking()
            updateBerths()
            tickHullLamps()
            drawRockets()
            tickPadLifts()
            tickSparks(dt: dt)
            turnPlanets(dt: dt)
            drawDrones(dt: dt)
            tickPuffs(dt: dt)
            tickPadFields()
            drawVortices()
        }
        tickCrateMotions()
        tickOffices()
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
        for (key, label) in roomLabels {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let st = fleet.stations[parts[0]], parts[1].hasPrefix("kind:") || shownOffice(st, parts[1])?.phase == .built else { continue }
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
        var renamed = old.withoutAnswers
        renamed.shareName = new.shareName
        guard renamed != new.withoutAnswers else { return }
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
            out[info.repo] = RepoDetail(path: root, remote: github.nameWithOwner(repoRoot: root),
                                        detected: github.pipelineRead(repoRoot: root) ? github.detectedPipeline(repoRoot: root) : nil,
                                        workflow: world.workflow(repo: info.repo), branches: github.githubBranches(repoRoot: root))
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
                    if let b = room.branch, let r = room.repoRoot { github.pulls.refresh(branch: b, repoRoot: r) }
                    if let w = room.worktree { github.git.refreshCommits(worktree: w) }
                }
            }
            github.intervalMinutes = ConfigStore.shared.current.githubMinutes
        for (root, info) in world.repoRoots {
            github.releases.refresh(repoRoot: root)
            if info.station == "work" { github.pulls.refreshOpenPRs(repoRoot: root) }
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
