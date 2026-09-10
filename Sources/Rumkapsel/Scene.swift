// The scene's spine: shared helpers, every stored property, the build, the scan glue and the tick.

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

/// Nothing in the station is round: every turned shape is cut with a few flat sides.
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
        // Wall time rather than the renderer's: a frame asked for by hand carries no timestamp.
        let now = CACurrentMediaTime()
        if sim != nil { advanceSimulated(to: now) } else { tick(now: now) }
    }

    let view: StationView
    let scene = SCNScene()
    let hud: SKScene
    let world: World
    let drone = Drone()
    private let scanner = TranscriptScanner()
    private let scanQueue = DispatchQueue(label: "rumkapsel.scan")
    /// The two handles the scene reaches for constantly; everything else it asks `world` for by name.
    var fleet: Fleet { world.fleet }
    var github: GitHubResolver { world.github }

    var minions: [String: Minion] = [:]
    let staticRoot = SCNNode()
    let labelRoot = SCNNode()
    let minionRoot = SCNNode()
    let propRoot = SCNNode()
    let markerRoot = SCNNode()
    private let debrisRoot = SCNNode()
    let rig = SCNNode()
    let pitchNode = SCNNode()
    let cameraNode = SCNNode()
    var roomTiles: [String: [SCNNode]] = [:]
    /// Doorways: pairs of cells whose shared edge has no dark border, keyed "x,y|x,y" in both orders.
    var openEdges: Set<String> = []
    var roomLabels: [String: SCNNode] = [:]
    var floorLabels: [(node: SCNNode, baseYaw: Double)] = []
    /// Rooms whose office has not been delivered yet, keyed by "station|room". Station truth keeps the
    /// list; the model has already put the room on the floor, this only holds its tiles back until a
    /// carrier walks it in.
    var undelivered: Set<String> { world.truth.pendingOffices }
    var boxes: [String: SCNNode] = [:]
    var outlines: [String: SCNNode] = [:]
    let beamRoot = SCNNode()
    let rocketRoot = SCNNode()
    /// One rocket actor per repository with a release on the pad, keyed "station|repo".
    var rocketActors: [String: Rocket] = [:]
    /// Every shuttle in the air right now, each running its flight command.
    var shuttles: [Shuttle] = []
    /// The one hover pallet a station may have out, keyed by station name.
    var pallets: [String: Pallet] = [:]
    /// The panel on the wall by each storage doorway, so an order can make it blink.
    var consolePanels: [String: SCNNode] = [:]
    /// Props on their way out, fading on the station's clock rather than on an action.
    var fadingProps: [(node: SCNNode, at: Double)] = []
    /// A staging release that ended before its pallet was out, by "station|repo": true pushes the
    /// pallet to the deck once it is loaded, false empties it back into storage.
    var palletWishes: [String: Bool] = [:]
    var lastBoxCount: [String: Int] = [:]
    private var localSignature = ""
    private var pendingCrewDeliveries: [(login: String, key: String)] = []
    var hangarAnchors: [String: SCNNode] = [:]
    private var lastBusy: [String: Double] = [:]
    var stationAnchors: [String: SCNNode] = [:]     // props that must move with a station when it shifts
    var knownSpine: [String: Int] = [:]
    // Peers on the local network: their snapshots, the stations built from them, and their minions.
    let peers = PeerHub()
    var fadeIn: Set<String> = []
    private let peerRoot = SCNNode()
    private var peerMinions: [String: (node: SCNNode, target: SIMD3<Double>)] = [:]
    private var peerColorBook: [String: RGB] = [:]
    var roomPower: [String: Bool] = [:]
    var haulingRooms: Set<String> = []
    /// A crate in motion: the command that moves it, the node on the floor, and what to do when it lands.
    struct Cargo { let command: Command; let node: SCNNode; let onDone: () -> Void; var carrier: String?; var roomKey: String = "" }
    var cargo: [Int: Cargo] = [:]
    private var lastHaulSchedule = 0.0
    static let powerWindow: TimeInterval = 2 * 3600
    var beams: [String: SCNNode] = [:]
    let infoLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    let infoBackground = SKSpriteNode(color: Palette.void.withAlphaComponent(0.85), size: CGSize(width: 1, height: 1))
    let statusLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    /// What a hovered minion is doing, on a dark plate above its head.
    let bubbleLabel = SKLabelNode(fontNamed: "HelveticaNeue")
    let bubblePlate = SKSpriteNode(color: Palette.void.withAlphaComponent(0.9), size: CGSize(width: 1, height: 1))
    let shareDot = SKSpriteNode(color: NSColor(rgb: (0.35, 0.85, 0.5)), size: CGSize(width: 7, height: 7))
    let shareLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    var legendNodes: [SKNode] = []
    var jobNodes: [SKNode] = []
    var hudClock = 0.0
    var legendSignature = ""
    var eventLabels: [(SKLabelNode, Double)] = []
    var hovered: String?
    private var lastTick = 0.0
    var clock = 0.0
    var targetHalf = SIMD2<Double>(6, 6)   // half-extent of the fleet as the default camera sees it
    var targetFocus = SIMD2<Double>(0, 0)
    var userZoom = 1.0
    var userZoomChanged = false
    var userDriving = 0.0          // seconds left of snappy camera response after a gesture
    private var keyMove = SIMD2<Double>(0, 0)   // WASD held: screen-relative direction, x right and y up
    private var keyZoom = 0.0                    // E/Q held: +1 zooms in, -1 out
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
    /// Set only in a simulator window: the event and command taps, and the clock the panel drives.
    var sim: SimHooks?
    var demoClock = 0.0
    var demoMerged = false
    var demoStaged = false

    static let activeWindow: TimeInterval = 60 * 60     // a worker stays with a session for an hour of quiet
    static let busyWindow: TimeInterval = 90
    static let replyWindow: TimeInterval = 20
    static let sleepWindow: TimeInterval = 5 * 60
    static let subagentWindow: TimeInterval = 3 * 60
    static let scanWindow: TimeInterval = 14 * 24 * 3600   // how far back transcripts are read

    /// Dark ink for anything written on a tile, whatever the tile's colour.
    static let inkOnTile = NSColor(rgb: (0.03, 0.03, 0.05))
    /// Floor cells under a room's writing, so boxes and cones keep off the words.
    var labelCells: [String: Set<Cell>] = [:]

    let ringRoot = SCNNode()

    var viewPinned = false   // set from the command line: never overridden by the remembered view

    init(frame: NSRect, demo: Bool, simulated: Bool = false) {
        self.demo = demo
        if simulated { sim = SimHooks() }
        world = World(demo: demo || simulated)
        world.simulated = simulated
        world.fleet.persists = !simulated
        world.github.frozen = simulated
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

        // What the model cannot see for itself: a crate already on someone's arms, or a rocket mid-load.
        world.haulInFlight = { [weak self] key in self?.cargo.values.contains { $0.roomKey == key } ?? false }
        world.haulingRoom = { [weak self] key in self?.haulingRooms.contains(key) ?? false }
        world.hasPackage = { [weak self] key in self?.markerRoot.childNodes.contains { $0.name == "box:" + key } ?? false }
        world.rocketBusy = { [weak self] key in self?.rocketActors[key]?.isBusy ?? false }
        peers.snapshotProvider = { [weak self] g in self?.makeSnapshot(withGitHub: g) }
        peers.onSnapshot = { [weak self] snap in self?.enqueue { self?.receivePeer(snap) } }
        if !simulated { applySharing() }
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

    func roomKey(_ station: Station, _ room: Room) -> String { "\(station.name)|\(room.key)" }

    /// Tiles depend on whether a branch is pushed, so relayout when that changes; otherwise just the props.
    func onGitHubUpdate() {
        let sig = fleet.stations.values.flatMap { st in st.rooms.values.map { r in
            let l = world.localState(r)
            let checks = r.branch.flatMap { b in r.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0)?.checks } } ?? ""
            return "\(st.name)|\(r.key):\(l.local):\(l.commits > 0):\(checks)"
        } }.sorted().joined()
        if sig != localSignature { localSignature = sig; rebuildStatic() } else { rebuildMarkers() }
        handle(world.applyGitHub(now: Date()))
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
        let now = Date()
        // The model works out what the floor should look like; the scene then places the workers on it.
        var homes: [String: World.MinionHome] = [:]
        for m in minions.values { homes[m.id] = World.MinionHome(station: m.station, key: m.home.key, idle: !m.onJob) }
        newRooms = [:]
        let events = world.applyScan(result, now: now, minionHomes: homes)
        let firstRun = events.contains { if case .worldLoaded = $0 { return true }; return false }
        handle(events)
        let cfg = ConfigStore.shared.current
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
            let home = world.homeFor(s, station: stationName)
            var isNew = minions[s.id] == nil
            var reused = false
            if isNew && !s.isSubagent {
                // A free worker on this station takes the new session before the shuttle brings another.
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
                    case .prompt: break   // the model says so, as a .prompt event: the cones went up already
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

            if let key = newRooms[s.id], !m.onJob, !m.isSubagent, fleet.stations[stationName]?.hasHangar == true {
                startDelivery(m, roomKey: key)
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
            if minions.values.contains(where: { $0.station == station.name && $0.busy && !$0.isCrew }) { lastBusy[station.name] = clock }
            let night = isNight(station)
            let free = minions.values.filter { $0.station == station.name && $0.freeSince > 0 && $0.state != .leaving && !$0.isSubagent }
                .sorted { $0.freeSince < $1.freeSince }
            for (i, m) in free.enumerated() where !m.isQA {
                let longIdle = clock - m.freeSince > 20 * 60 && i >= 2          // keep a couple on standby, let the rest go
                let restPlace: Place = night ? .quarters : .lounge
                if longIdle || (i >= station.beds.count + station.couches.count) {
                    dismiss(m)
                    if let key = carriedRoom(of: m) { reveal(key); m.carried?.removeFromParentNode(); m.carried = nil }
                } else if !m.onJob && !m.bathing && !m.isChore && m.place != restPlace && m.place != .bath && !(m.place == .lounge && restPlace == .quarters && m.bed == nil && night == false) {
                    m.activity = night ? .sleeping : .waiting
                    send(m, to: restPlace)
                }
            }
            assignTester(station: station, free: free)
        }
        // Offices that appeared without a minion to deliver them just show up.
        let pending = Set(minions.values.compactMap { m in carriedRoom(of: m) ?? newRooms[m.id].map { "\(m.station)|\($0)" } })
        for key in undelivered where !pending.contains(key) {
            layoutDirty = true
            world.truth.officeDelivered(key)
            outlines.removeValue(forKey: key)?.removeFromParentNode()
            boxes.removeValue(forKey: key)?.removeFromParentNode()
        }
        if layoutDirty {
            flushScene(firstRun: firstRun)
            for m in minions.values {
                guard case .deliverOffice(let r) = m.current?.kind, let station = fleet.stations[m.station] else { continue }
                if m.carried == nil, let c = station.hangarCells.randomElement() { walk(m, to: c) }
                else if let door = station.doorCell(of: r) { walk(m, to: door) }
            }
        } else {
            flushScene()
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
                                               pushed: r.branch != nil && !world.localState(r).local,
                                               startedAt: world.roomCreated[key] ?? .distantPast, lastActive: r.lastActive,
                                               boxes: lastBoxCount[key] ?? 0, dim: r.key.hasPrefix("proj:") || !(roomPower[key] ?? true)))
        }
        let ms = minions.values.filter { $0.station == station.name && !$0.isCrew && $0.state != .leaving && cfg.shared(repo: $0.home.repo) && station.rooms[$0.home.key]?.worktree != nil }.map {
            PeerSnapshot.Minion(id: $0.id.hashValue.description, office: $0.home.key, asleep: $0.activity == .sleeping, busy: $0.busy)
        }
        var knowledge: [GitHubResolver.Knowledge]?
        var board: GitHubResolver.ProjectKnowledge?
        if withGitHub {
            knowledge = world.repoRoots.filter { $0.value.station == "work" && cfg.shared(repo: $0.value.repo) }.compactMap { github.knowledge(repoRoot: $0.key, repo: $0.value.repo) }
            if let p = cfg.project { board = github.projectKnowledge(owner: p.owner, number: p.number) }
        }
        return PeerSnapshot(version: PeerSnapshot.current, name: peers.name, since: peers.since, offices: offices, minions: ms, github: knowledge, project: board)
    }

    /// A peer's claim lands on our work station. The model merges it; the scene shows the result and
    /// stands their figures in whichever offices we happened to give them.
    func receivePeer(_ snap: PeerSnapshot) {
        handle(world.applyPeer(snap, now: Date()))
        flushScene()
        flushDeliveries()
        placePeerMinions(snap)
    }

    /// Their minions stand in the office they claim here, wherever we happened to put it.
    private func placePeerMinions(_ snap: PeerSnapshot) {
        let station = fleet.station("work")
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
        let liveMinions = Set(snap.minions.map { "\(snap.name)/\($0.id)" })
        for (id, pm) in peerMinions where id.hasPrefix(snap.name + "/") && !liveMinions.contains(id) { pm.node.removeFromParentNode(); peerMinions[id] = nil }
    }

    /// A peer has gone quiet: its figures leave, its offices stay held until their hold runs out.
    func dropPeer(_ name: String) {
        handle(world.dropPeer(name))
        flushScene()
    }

    // MARK: events

    /// The floor plan or the props changed. The rebuild waits until the caller has finished its own
    /// work, so a scan can place its workers before the station is redrawn under them.
    private var layoutDirty = false
    private var markersDirty = false
    /// Offices ordered this scan, by session id: the worker fetches its own from the bay.
    private var newRooms: [String: String] = [:]
    /// Peer offices waiting for a carrier.
    private var peerDeliveries: [String] = []

    func flushScene(firstRun: Bool = false) {
        if layoutDirty {
            layoutDirty = false; markersDirty = false
            rebuildStatic()
            if firstRun, !viewPinned { restoreView() }
            for st in fleet.stations.values { resettle(st) }
        } else if markersDirty {
            markersDirty = false
            rebuildMarkers()
        }
    }

    /// Offices ordered by a peer or by GitHub, once the floor they stand on has been drawn.
    private func flushDeliveries() {
        let station = fleet.station("work")
        for roomKey in peerDeliveries {
            let free = minions.values.filter { $0.station == station.name && !$0.isCrew && !$0.isSubagent && !$0.onJob && $0.carried == nil && !$0.busy }
                .min(by: { $0.freeSince > $1.freeSince })
            if let m = free { startDelivery(m, roomKey: roomKey) } else { reveal(station.name + "|" + roomKey) }
        }
        peerDeliveries = []
        for d in pendingCrewDeliveries {
            if let m = minions["crew:" + d.login], !m.onJob { startDelivery(m, roomKey: d.key) } else { reveal(station.name + "|" + d.key) }
        }
        pendingCrewDeliveries = []
    }

    func handle(_ events: [WorldEvent]) { for e in events { handle(e) } }

    /// A message landed in an office: one cone per message that arrived since last time, and its
    /// worker walks over to work them. A queued cone lights up when it is picked up.
    private func promptLanded(station: String, key: String, minionId: String, count: Int) {
        guard let m = minions[minionId], !m.isSubagent else { return }
        for _ in 0..<min(count, 5) {
            if let q = m.queuedCones.first { q.removeFromParentNode(); m.queuedCones.removeFirst() }
            addPyramid(for: m)
        }
    }

    /// The one place that turns an event into a cue. Diffs emit; this decides what the station does.
    func handle(_ event: WorldEvent) {
        sim?.onEvent?(event)
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
            if let m = minions[session] {
                // The office kept its floor under a new name: the delivery follows it.
                if case .deliverOffice = m.current?.kind, let old = m.current {
                    m.current = Command(kind: .deliverOffice(key: to), words: old.words)
                    world.truth.jobs[m.id] = (m.current!, m.phase)
                }
                if m.place == .room(from) { m.place = .room(to) }
            }
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
        case .crewRoster(let members, let bots):
            setCrewRoster(members, bots: bots)
        case .crewActivity(let a):
            playCrew(a)
        case .stagingOpened(let stationName, let repo, let number):
            guard let station = fleet.stations[stationName] else { return }
            orderPallet(station: station, repo: repo, number: number)
        case .stagingMerged(let stationName, let repo, let number):
            guard let station = fleet.stations[stationName] else { return }
            logEvent("\(repo): staging release #\(number) merged")
            palletMerged(station: station, repo: repo)
        case .stagingClosed(let stationName, let repo, let number):
            guard let station = fleet.stations[stationName] else { return }
            logEvent("\(repo): staging release #\(number) closed, not merged")
            palletClosed(station: station, repo: repo)
        case .releaseOpened, .releaseMerged(_, _, _, _, _, true):
            break    // the rocket command that comes with it is the cue; the log line came as a .log
        case .releaseMerged(let stationName, let repo, _, _, _, false):
            // A staging release without a board and without a pallet: nothing else would move the crates.
            if ConfigStore.shared.current.project == nil, let st = fleet.stations[stationName],
               world.truth.pallets[stationName]?.repo != repo { stageCargo(station: st, repo: repo) }
        case .rocketCommand(let stationName, let repo, let label, let untested, let tall, let cargo, let command):
            handle(rocket: stationName, repo: repo, label: label, untested: untested, tall: tall, cargo: cargo, command: command)
        case .prompt(let stationName, let key, let minionId, let count):
            promptLanded(station: stationName, key: key, minionId: minionId, count: count)
        case .crewHidden:
            for m in minions.values where m.isCrew { despawn(m) }
        case .boardMoved(let item, let from, let to):
            guard let info = world.repoRoots.values.first(where: { $0.repo == item.repo }), let station = fleet.stations[info.station] else { return }
            let st = ConfigStore.shared.current.statuses
            let label = "#\(item.number) \(item.title.prefix(36))"
            switch to {
            case .deck where from == st.storage:
                logEvent("\(label): on staging, to the deck")   // the yard reconciliation carries it across
                rebuildMarkers()
            case .cleared:
                logEvent("\(label): passed QA, ready to ship")
                handle(.crateCleared(station: station.name, repo: item.repo, number: item.number))
            case .shipped where from != nil:
                logEvent("\(label): shipped")
            case .storage where from == st.development:
                logEvent("\(label): merged, ready for staging")
            case .development where from != nil && from != st.development:
                logEvent("\(label): in development")
            default: break
            }
        case .pullRequestOpened(let repo, let number, let author, _):
            logEvent("\(world.crewName(author)) opened #\(number) \(repo)")
        case .issueStarted(let repo, let number, let author, _):
            logEvent("\(world.crewName(author)) started #\(number) \(repo)")
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

    func tick(now: TimeInterval) {
        let dt = min(0.1, max(0, now - lastTick))
        lastTick = now
        clock += dt
        if demo { tickDemo(dt: dt) }
        if Int(clock) % 5 == 0 && Int(clock - dt) % 5 != 0 { updatePower() }
        if clock - lastHaulSchedule > 0.5 { lastHaulSchedule = clock; scheduleCarries(); refreshObstacles() }
        tickShuttles()
        tickPallets()
        for (id, pm) in peerMinions {
            let p = SIMD3(Double(pm.node.position.x), 0, Double(pm.node.position.z))
            let d = pm.target - p
            let step = min(1, dt * 2)
            pm.node.position.x += CGFloat(d.x * step); pm.node.position.z += CGFloat(d.z * step)
            _ = id
        }
        if Int(clock) % 5 == 0 && Int(clock - dt) % 5 != 0 {
            for name in world.stalePeers(olderThan: 20) { dropPeer(name) }
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

        tickMinions(dt: dt)

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
        updateBubble()
        if sim == nil, clock - lastSavedView > 2 { lastSavedView = clock; saveView() }
    }

    /// Settings changed: rebuild the fleet from scratch on the next scan.
    func applyConfigChange() {
        applySharing()
        enqueue { [self] in
            for m in Array(minions.values) { despawn(m) }
            world.reset()
            rebuildStatic()
            rescan()
        }
    }

    var knownRepos: [String] { world.knownRepos }
    var seenLogins: Set<String> { world.seenLogins }

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
        for (root, info) in world.repoRoots {
            github.refreshReleases(repoRoot: root)
            if info.station == "work" { github.refreshFeed(repoRoot: root); github.refreshOpenPRs(repoRoot: root) }
        }
            logEvent("asking github…")
        }
    }

    /// Renders the current frame to a PNG, used for self-checks.
    func snapshot(to path: String) {
        let image = view.snapshot()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
