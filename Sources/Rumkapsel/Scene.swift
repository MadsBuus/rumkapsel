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
    /// Shading, in the one way that keeps a colour the colour it was. Adding or subtracting the same
    /// amount from red, green and blue does not: it flattens the ratios between them, which is what the
    /// eye reads as hue, so a darkened orange comes out red and a lightened one comes out cream. These
    /// move brightness and leave hue and saturation where they are — which is how the game shades, every
    /// face of a crate the same colour at a different value.
    func dimmed(_ f: CGFloat) -> NSColor { shaded(value: f) }
    func darker(_ f: CGFloat) -> NSColor { shaded(value: 1 - f) }
    func lighter(_ f: CGFloat) -> NSColor {
        let c = usingColorSpace(.deviceRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Brightness has a ceiling, so past it a colour lightens by losing saturation — as paint does.
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
    static let corridor = NSColor(rgb: (0.494, 0.400, 0.353))   // #7E665A, the game's hallway floor
    static let core = NSColor(rgb: (0.13, 0.14, 0.18))
    static let minion = NSColor(rgb: (0.96, 0.96, 0.94))
    static let pyramid = NSColor(rgb: (0.98, 0.85, 0.35))
    static let debris = NSColor(rgb: (0.55, 0.6, 0.7))
    /// An object of unknown origin: grey in decon, grey in storage, grey aboard.
    static let alien = NSColor(rgb: (0.58, 0.6, 0.66))
    /// The light on decon's hatch and on an unscreened object's plate.
    static let alienLight = NSColor(rgb: (0.5, 0.95, 0.55))
    /// Your own work: the straps on a crate whose pull request is yours. Near white, because the crate
    /// itself is already its repository's colour and a second colour there would read as another repo.
    static let mine = NSColor(rgb: (0.95, 0.96, 0.93))
    static let text = NSColor(rgb: (0.85, 0.87, 0.92))
    static let dim = NSColor(rgb: (0.5, 0.53, 0.6))
}

func v3(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 { SCNVector3(x, y, z) }

/// Nothing in the station is round: every turned shape is cut with a few flat sides.
/// Which nodes the pointer may find. A node carries `normal` unless it is scenery too big to click
/// through — the hull wall leaning over the airlock — which carries `scenery` and is passed over. The
/// camera reads the same mask, so scenery is a bit of its own rather than none at all.
enum Pick {
    static let normal = 1
    static let scenery = 2
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
        // Wall time rather than the renderer's: a frame asked for by hand carries no timestamp.
        let now = CACurrentMediaTime()
        guard Trace.frames else {
            if sim != nil { advanceSimulated(to: now) } else { tick(now: now) }
            return
        }
        // With RK_FRAMES set, a frame that took too long says so, and says what it spent the time on.
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

    /// What a frame spent its time on, while `RK_FRAMES` is set. Off, `timed` is the call it wraps.
    enum Trace {
        static let frames = ProcessInfo.processInfo.environment["RK_FRAMES"] != nil
        static let slowFrame = 0.05, slowWork = 0.02
    }
    private var phases: [(name: String, seconds: Double)] = []
    private var lastFrameAt = CACurrentMediaTime()
    /// Which frame this is, and which frame last built the floor: the floor is built once a frame at
    /// most. Everything that changes it asks for a redraw, and on a launch a dozen of those arrive
    /// together — each one rebuilding every tile of every station, on the thread that is drawing.
    private var frameNo = 0
    private var lastFloorFrame = -1
    private var lastGitHubFrame = -1
    /// Tiles built since the last frame was reported, for the trace.
    var tilesBuilt = 0
    /// Floor and border geometry shared between every tile that looks the same, and the look it was
    /// built for: a change of look empties it.
    var tileCache: [String: SCNGeometry] = [:]
    /// Whose floor each cell is, per station, for the length of one redraw.
    var owners: [String: [Cell: String]] = [:]
    var tileCacheLook: Theme = Looks.theme

    /// Runs `body`, noting how long it took when frames are being traced.
    @discardableResult func timed<T>(_ name: String, _ body: () -> T) -> T {
        guard Trace.frames else { return body() }
        let t0 = CACurrentMediaTime()
        defer { phases.append((name, CACurrentMediaTime() - t0)) }
        return body()
    }

    let view: StationView
    let scene = SCNScene()
    let hud: SKScene
    /// The station itself: its bodies, orders, walks and clock. The scene draws it and decides nothing.
    let simulation: Simulation<Minion>
    var world: World { simulation.world }
    let drone = Drone()
    private let scanner = TranscriptScanner()
    private let scanQueue = DispatchQueue(label: "rumkapsel.scan")
    /// The two handles the scene reaches for constantly; everything else it asks `world` for by name.
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
    /// Whatever the look lays under the fleet; rebuilt with the floor.
    let groundRoot = SCNNode()
    /// Where the view starts from before the user turns it: the look's.
    var viewYaw: Double { Looks.current.viewYaw }
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
    /// Offices whose pull request crate is being packed right now: drawn only once the worker is done.
    var packing: Set<String> = []
    var boxes: [String: SCNNode] = [:]
    var outlines: [String: SCNNode] = [:]
    let beamRoot = SCNNode()
    let rocketRoot = SCNNode()
    /// The rockets and the ships as drawn: a node per rocket by "station|repo", a node per flight.
    var rocketViews: [String: RocketView] = [:]
    var shuttleViews: [ObjectIdentifier: ShuttleView] = [:]
    /// The pallet each station has out, as drawn, keyed by station name; the errand is the simulation's.
    var palletViews: [String: PalletView] = [:]
    /// The panel on the wall by each storage doorway, so an order can make it blink.
    var consolePanels: [String: SCNNode] = [:]
    /// Props on their way out, fading on the station's clock rather than on an action.
    var fadingProps: [(node: SCNNode, at: Double)] = []
    var lastBoxCount: [String: Int] = [:]
    /// What each marker was last drawn as, by node name: an office's boxes by everything that shapes
    /// them, a yard crate by whether it wears the tested sticker. A redraw leaves alone whatever would
    /// come out the same, so drawing the floor twice costs nothing and moves nothing.
    var markerSignatures: [String: String] = [:]
    /// The one crate an office with a pull request has on its floor, by room key, with what it was built
    /// from: it stays where it stands for as long as the pull request does, and a redraw only re-lights it.
    var packages: [String: SCNNode] = [:]
    var packageBuilt: [String: String] = [:]
    /// The tile each office's crate was given, kept so nothing drawn later moves it.
    var packageCells: [String: Cell] = [:]
    /// Crates under way, by node: the one table that moves a crate's picture.
    var crateMotions: [ObjectIdentifier: CrateMotion] = [:]
    /// The cells the furniture covers, per station, and the static root's size when that was read.
    var furnitureObstacles: [String: Set<Cell>] = [:]
    var furnitureObstaclesAt = -1
    private var localSignature = ""
    private var pendingCrewDeliveries: [(login: String, key: String)] = []
    var hangarAnchors: [String: SCNNode] = [:]
    /// The gym's two things that move: the barbell over the bench and the bag on its arm, per station.
    var gymProps: [String: (bar: SCNNode, bag: SCNNode)] = [:]
    private var lastBusy: [String: Double] = [:]
    var stationAnchors: [String: SCNNode] = [:]     // props that must move with a station when it shifts
    var knownSpine: [String: Int] = [:]
    // Peers on the local network: their snapshots, the stations built from them, and their minions.
    let peers = PeerHub()
    var fadeIn: Set<String> = []
    private let peerRoot = SCNNode()
    private var peerMinions: [String: (minion: Minion, target: SIMD3<Double>)] = [:]
    /// How many of the peers' figures stand on the station, for the checks.
    var peerFigures: Int { peerMinions.count }
    private var peerColorBook: [String: RGB] = [:]
    var roomPower: [String: Bool] = [:]
    /// Crates under way are the simulation's (`Cargo`); the node each one is drawn as is kept here, by command id.
    var cargo: [Int: Cargo] {
        get { simulation.cargo }
        set { simulation.cargo = newValue }
    }
    var cargoNodes: [Int: SCNNode] = [:]
    /// Carries whose crate has passed QA: the tested tag goes on as the crate comes off the row, by the
    /// hands that carry it, not when it is set down again across the aisle.
    var tagOnLift: Set<Int> = []
    private var lastHaulSchedule = 0.0
    static let powerWindow: TimeInterval = 2 * 3600
    var beams: [String: SCNNode] = [:]
    let infoLabel = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
    let infoBackground = SKSpriteNode(color: Palette.void.withAlphaComponent(0.85), size: CGSize(width: 1, height: 1))
    let statusLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    /// Who the camera is with and what they are doing, bottom centre while following.
    let followLabel = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
    /// What a hovered minion is doing, on a dark plate above its head.
    let bubbleLabel = SKLabelNode(fontNamed: "HelveticaNeue")
    let bubblePlate = SKSpriteNode(color: Palette.void.withAlphaComponent(0.9), size: CGSize(width: 1, height: 1))
    /// The bubble's row of orders, one glyph each, in `LoungeOrder` order.
    var bubbleIcons: [SKSpriteNode] = []
    /// Decon's hatch light per station, for the blink and the puff when something comes through.
    var hatchLights: [String: SCNNode] = [:]
    /// When a manual GitHub refresh last went out. Focus, the menu item and `g` all land in the same place,
    /// and macOS will hand us two activations in a row; the second one would find every cache age just
    /// cleared by `invalidate()` and ask GitHub the whole round again, so a refresh close behind another is
    /// dropped. The poller's own intervals are untouched — this guards only the manual door.
    private var askedGitHubAt = Date.distantPast
    /// Objects just through decon's hatch, by marker name: drawn high and floated down onto their pile.
    var incoming: Set<String> = []
    /// Where the bubble and its icons are on screen, for the main thread's hover and click; nil while no bubble shows.
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
    var hovered: String?
    /// The minion the camera goes with, until a pan, Esc or a click on the floor.
    var following: String?
    private var lastTick = 0.0
    /// How fast station time runs in the live app: 1, or 4 while space is held.
    var liveTimeScale = 1.0
    /// Visits that ran their course in a simulated run, and station time: both the simulation's.
    var visitLog: [(kind: String, lasted: Double, planned: Double)] { simulation.visitLog }
    var clock: Double {
        get { simulation.clock }
        set { simulation.clock = newValue }
    }
    var targetHalf = SIMD2<Double>(6, 6)   // half-extent of the fleet as the default camera sees it
    var targetFocus = SIMD2<Double>(0, 0)
    var userZoom = 1.0
    var userZoomChanged = false
    var userDriving = 0.0          // seconds left of snappy camera response after a gesture
    /// A hand has been on the camera since launch: the one-time framing when the floor has finished arriving
    /// is for a view nobody has touched.
    var userTookView = false
    private var fpsFrames = 0, fpsMark = 0.0   // the frame counter behind RK_FPS
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
    var sim: SimHooks? {
        get { simulation.hooks }
        set { simulation.hooks = newValue }
    }
    /// A scripted run with no frame ever drawn: the view's own tick and its decorations are skipped, since
    /// nothing reads them. Everything on the station clock still runs, scene-side logic included.
    var headless = false
    /// Station time as a date: the wall clock for the app, the simulated clock for a simulator, which
    /// runs at its own pace and may stall. Everything on the station that judges freshness against
    /// "now" reads this, so a slow frame can never age a session or a landing.
    var now: Date { simulation.now }
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

    let padHexRoot = SCNNode()
    /// The hexagons on the bay's berths, by station, and which of them burn in whose colour.
    let berthRoot = SCNNode()
    var berthHexes: [String: [SCNNode]] = [:]
    var berthLit: [String: BerthLight] = [:]

    var viewPinned = false   // set from the command line: never overridden by the remembered view

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
        view.antialiasingMode = .multisampling2X   // flat shading and straight edges: 2X reads the same as 4X
        view.preferredFramesPerSecond = 30           // raised to 60 while a gesture is under way, lowered while unseen (tickView)
        view.isPlaying = true
        view.autoresizingMask = [.width, .height]
        view.allowsCameraControl = false
        view.overlaySKScene = hud
        view.onHover = { [weak self] node in let n = node?.name; self?.enqueue { self?.hovered = n } }
        view.hudTakesPoint = { [weak self] p in self?.bubbleTakes(point: p) ?? false }
        view.onHUDClick = { [weak self] p in self?.bubbleClick(at: p) ?? false }
        view.onDoubleClick = { [weak self] node in
            let n = node?.name
            self?.enqueue {
                if let n, n.hasPrefix("minion:") { self?.poke(minionId: String(n.dropFirst(7))) } else { self?.open(named: n) }
            }
        }
        view.onClick = { [weak self] node in
            // A click on a minion follows it; a click anywhere else lets go.
            let n = node?.name ?? ""
            if n.hasPrefix("minion:") { self?.enqueue { self?.follow(minionId: String(n.dropFirst(7))) }; return }
            self?.enqueue { self?.following = nil }
            guard !n.isEmpty else { return }
            if (n.hasPrefix("storage:") || n.hasPrefix("deck:") || n.hasPrefix("decon:")), n.split(separator: "|").count == 3 { self?.enqueue { self?.openCargo(named: n) } }
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
                self.userTookView = true
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
        view.onPan = { [weak self] dx, dy in self?.enqueue { self?.pan(byPixels: dx, dy) } }
        view.onMove = { [weak self] dir, zoom in self?.enqueue { self?.keyMove = dir; self?.keyZoom = zoom; if dir != .zero || zoom != 0 { self?.userTookView = true } } }
        github.onUpdate = { [weak self] in self?.enqueue { self?.onGitHubUpdate() } }
        view.onHold = { [weak self] held in self?.liveTimeScale = held ? 4 : 1 }
        view.onKey = { [weak self] key in
            guard let self else { return false }
            switch key {
            case "0": following = nil; focus(on: nil)
            case "1", "2", "3", "4": following = nil; focus(onIndex: Int(key)! - 1)
            case "r": following = nil; resetView()
            case "\u{1b}": following = nil
            case "g": refreshGitHub()
            default: return false
            }
            return true
        }
        view.delegate = self

        // What the model cannot see for itself: a crate already on someone's arms, or a rocket mid-load.
        world.hasPackage = { [weak self] key in self?.markerRoot.childNodes.contains { $0.name == "box:" + key } ?? false }
        // The scene's ears on the simulation.
        simulation.onEvent = { [weak self] event in self?.handle(event) }
        simulation.onLog = { [weak self] text in self?.logEvent(text) }
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
        Looks.use(ConfigStore.shared.current.theme)
        for n in [groundRoot, staticRoot, labelRoot, minionRoot, propRoot, markerRoot, debrisRoot, beamRoot, rocketRoot, peerRoot] { scene.rootNode.addChildNode(n) }

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 8
        camera.zNear = 0.1
        camera.zFar = 400
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
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 550
        scene.rootNode.addChildNode(ambient)
        buildBackdrop()
        rebuildStatic()
    }

    /// What lies past the fleet, from the look: the colour beyond everything and whatever drifts there.
    private func buildBackdrop() {
        debrisRoot.childNodes.forEach { $0.removeFromParentNode() }
        scene.background.contents = Looks.current.background
        debris = Looks.current.backdrop(into: debrisRoot)
    }

    func roomKey(_ station: Station, _ room: Room) -> String { "\(station.name)|\(room.key)" }

    /// Tiles depend on whether a branch is pushed, so relayout when that changes; otherwise just the props.
    func onGitHubUpdate() {
        // Every repository that answers says so, and on a launch they answer together: a dozen of these
        // arrive in one frame, each taking the world's whole diff against GitHub. Once a frame is enough,
        // since the one that runs sees everything that has landed by then.
        if !headless {
            guard lastGitHubFrame != frameNo else { return }
            lastGitHubFrame = frameNo
        }
        let sig = fleet.stations.values.flatMap { st in st.rooms.values.map { r in
            let l = world.localState(r)
            let checks = r.branch.flatMap { b in r.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0)?.checks } } ?? ""
            return "\(st.name)|\(r.key):\(l.local):\(l.commits > 0):\(checks)"
        } }.sorted().joined()
        // The world's diff first, then the redraw: a crate the board just cleared is handed to a carrier
        // while it still stands on the untested row, and the redraw then leaves it out as carried.
        timed("github") { handle(world.applyGitHub(now: now, timed: { n, b in self.timed(n, b) })) }
        // Offices left waiting for somewhere to stand come round on the next frame, since GitHub may
        // have nothing further to say and they would otherwise wait for something that never comes.
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
        // The model works out what the floor should look like; the scene then places the workers on it.
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
                    // A local signal never moves anything; it re-asks the authority now and for a while.
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
                    if let key = carriedRoom(of: m) { reveal(key); simulation.loseLoad(m) }
                } else if !m.onJob && !m.bathing && !m.isChore && m.place != restPlace && m.place != .bath && !(m.place == .lounge && restPlace == .quarters && m.bed == nil && night == false) {
                    m.activity = night ? .sleeping : .waiting
                    send(m, to: restPlace)
                }
            }
            assignTester(station: station, free: free)
        }
        // Offices that appeared without a shuttle ever ordered for them just show up. One with an order
        // out, in the air or on the floor, is the delivery queue's: it is walked in, never conjured.
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
        if cfg.shareOnLAN {
            peers.start(name: cfg.shareName.isEmpty ? NSUserName() : cfg.shareName)
        } else { peers.stop() }
    }

    /// Our own claim for the others: offices we have checked out ourselves in repositories ticked
    /// for sharing. Nothing learned from GitHub or from another peer goes back out.
    private func makeSnapshot(withGitHub: Bool) -> PeerSnapshot? {
        let cfg = ConfigStore.shared.current
        guard let station = fleet.stations["work"] else { return nil }
        var offices: [PeerSnapshot.Office] = []
        for r in station.rooms.values where r.worktree != nil && !r.key.hasPrefix("kind:") && (r.repo.map { cfg.shared(repo: $0) } ?? false)
            && now.timeIntervalSince(r.lastActive) < World.roomsWindow {   // only what was worked in lately: old checkouts stay home
            let key = roomKey(station, r)
            let pr = r.branch.flatMap { b in r.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }
            offices.append(PeerSnapshot.Office(key: r.key, name: r.name, repo: r.repo ?? "", branch: r.branch, color: r.color, cells: r.cells,
                                               pushed: r.branch != nil && !world.localState(r).local,
                                               startedAt: world.roomCreated[key] ?? .distantPast, lastActive: r.lastActive,
                                               boxes: lastBoxCount[key] ?? 0, dim: r.key.hasPrefix("proj:") || !(roomPower[key] ?? true),
                                               pull: pr?.number, pullState: pr?.state, review: pr?.reviewDecision, checks: pr?.checks))
        }
        let ms = minions.values.filter { $0.station == station.name && !$0.isCrew && $0.state != .leaving && cfg.shared(repo: $0.home.repo) && station.rooms[$0.home.key]?.worktree != nil }.map {
            PeerSnapshot.Minion(id: $0.id.hashValue.description, office: $0.home.key, asleep: $0.activity == .sleeping, busy: $0.busy,
                                activity: $0.activity.label, waiting: $0.activity == .waiting, cones: $0.pyramids.count + $0.queuedCones.count)
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
        world.peerName = peers.name
        timed("peer") { handle(world.applyPeer(snap, now: now)) }
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
            // A real minion in a teammate's grey, in the office they claim, posed the way their session is:
            // asleep in the dorm, at work with the tablet out, waiting with empty hands and its cones standing.
            let figure: Minion
            if let existing = peerMinions[id] {
                figure = existing.minion
            } else {
                figure = Minion(id: "peer:" + id, station: station.name, home: Home(key: m.office, name: snap.name, repo: "", issue: nil),
                                cwd: "", toolCount: 0, isSubagent: false, start: cell, crew: true)
                figure.node.position = v3(target.x, 0, target.z)
                figure.node.opacity = 1
                peerRoot.addChildNode(figure.node)
            }
            peerMinions[id] = (figure, target)
            figure.setPose(m.asleep ? .flat(height: 0) : .standing)
            figure.setTool(m.asleep || m.waiting == true || !m.busy ? nil : .tablet)
            let cones = m.asleep ? 0 : (m.cones ?? 0)
            if figure.pyramids.count + figure.queuedCones.count != cones {
                clearPyramids(figure)
                figure.queuedCones.forEach { $0.removeFromParentNode() }
                figure.queuedCones = []
                if cones > 0 {
                    addPyramid(for: figure)
                    for _ in 1..<max(1, cones) { addPyramid(for: figure, queued: true) }
                }
            }
        }
        let liveMinions = Set(snap.minions.map { "\(snap.name)/\($0.id)" })
        for id in peerMinions.keys where id.hasPrefix(snap.name + "/") && !liveMinions.contains(id) { removePeerFigure(id) }
    }

    /// A peer's figure leaves: its body and its cones.
    private func removePeerFigure(_ id: String) {
        guard let pm = peerMinions[id] else { return }
        clearPyramids(pm.minion)
        pm.minion.queuedCones.forEach { $0.removeFromParentNode() }
        pm.minion.node.removeFromParentNode()
        peerMinions[id] = nil
    }

    /// A peer has gone quiet: its figures leave, its offices stay held until their hold runs out.
    func dropPeer(_ name: String) {
        for id in peerMinions.keys where id.hasPrefix(name + "/") { removePeerFigure(id) }   // their figures leave with them
        handle(world.dropPeer(name))
        flushScene()
    }

    // MARK: events

    /// The floor plan or the props changed. The rebuild waits until the caller has finished its own
    /// work, so a scan can place its workers before the station is redrawn under them.
    private var layoutDirty = false
    /// Which offices were last drawn as not yet looked at, so the lights can be brought up on the ones
    /// that have been without rebuilding the floor under them.
    private var drawnUnchecked: [String: Bool] = [:]
    /// Whether the floor was still arriving last tick, so the one settling can be done when it stops.
    private var wasLooking = true
    /// When the floor was last rebuilt, on the wall clock.
    var lastRebuildAt = CACurrentMediaTime()

    /// The floor is still arriving, or has only just stopped. Answers from GitHub are not the end of it:
    /// offices land after them, and minions after those, each a rebuild of its own. Holding until the
    /// rebuilds go quiet is what "settled" has to mean, or the view is let go one step too early.
    var floorSettling: Bool { world.stillLooking || CACurrentMediaTime() - lastRebuildAt < 1.5 }

    /// How dim an office is while it waits to be looked at.
    static let unlitOffice = 0.75   // dim enough to read as unconfirmed, not so dim the colour goes
    /// How much floor the view takes in while a station is still arriving: one height, held still,
    /// since the frames of a launch are too uneven for the camera to move on.
    var settlingHalf: SIMD2<Double> { SIMD2(20, 20) }

    /// The lights, apart from the floor. An office confirmed today comes up to full where it stands: the
    /// tiles are already drawn, so this is a fade on what is there, never a reason to build them again.
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
    /// Offices ordered this scan, by session id: the worker fetches its own from the bay.
    private var newRooms: [String: String] = [:]
    /// Peer offices waiting for a carrier.
    private var peerDeliveries: [String] = []

    func flushScene(firstRun: Bool = false) {
        // The world's word first, then the picture: the reconciler may hand out carries or move a count,
        // and the redraw that follows draws what it decided. The drawing itself decides nothing.
        timed("yards") { reconcileYards() }
        timed("lights") { lightRooms() }
        // The floor has stopped arriving: frame it whole and settle everyone, once.
        if wasLooking, !floorSettling {
            wasLooking = false
            if !userTookView { focusNow(on: focused) }   // a view already being driven is not reframed under the hand
            timed("settle") { for st in fleet.stations.values { resettle(st) } }
        }
        if layoutDirty {
            // One floor a frame. The rest of what is asked for keeps its place in the queue and is drawn
            // on the next one, which is a frame late and not a second of the window frozen. A run with no
            // window has no frames to spread the work over, so it does the lot as it comes.
            if !headless {
                guard lastFloorFrame != frameNo else { return }
                lastFloorFrame = frameNo
            }
            layoutDirty = false; markersDirty = false
            timed("floor") { rebuildStatic() }
            if firstRun, !viewPinned { restoreView() }
            // Not while offices are still arriving: settling the bodies and reframing on a floor that
            // is about to grow again is the jitter.
            if !floorSettling { timed("settle") { for st in fleet.stations.values { resettle(st) } } }
            refreshRockets()   // the pad may have moved with the floor: rockets standing by and the due rings follow it
        } else if markersDirty {
            markersDirty = false
            timed("markers") { rebuildMarkers() }
        }
    }

    /// Offices ordered by a peer or by GitHub, once the floor they stand on has been drawn.
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

    /// A message reached the session: the one cone that stands for the message being worked. The
    /// queued cone at the head of the row, if any, is the one it came from.
    private func promptLanded(station: String, key: String, minionId: String, count: Int) {
        guard let m = minions[minionId], !m.isSubagent, count > 0 else { return }
        if let q = m.queuedCones.first { q.removeFromParentNode(); m.queuedCones.removeFirst() }
        addPyramid(for: m)
        arrangeQueuedCones(m)
    }

    /// The one place that turns an event into a cue. Diffs emit; this decides what the station does.
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
            if let m = minions[session], m.place == .room(from) { m.place = .room(to) }   // a delivery under way follows by its order
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
            // Just through the hatch: drawn at hatch height, they float down onto their pile.
            for n in numbers { incoming.insert("decon:\(stationName)|\(repo)|\(n)") }
        case .deconCleared(let stationName, let repo, let number):
            guard let station = fleet.stations[stationName] else { return }
            haulCleared(station: station, repo: repo, number: number)
        case .crewActivity(let a):
            playCrew(a)
        case .stagingOpened(let stationName, let repo, let number):
            guard let station = fleet.stations[stationName] else { return }
            simulation.orderPallet(station: station, repo: repo, number: number)
        case .stagingMerged(let stationName, let repo, let number):
            guard let station = fleet.stations[stationName] else { return }
            logEvent("\(repo): staging release #\(number) merged")
            simulation.palletMerged(station: station, repo: repo)
        case .stagingClosed(let stationName, let repo, let number):
            guard let station = fleet.stations[stationName] else { return }
            logEvent("\(repo): staging release #\(number) closed, not merged")
            simulation.palletClosed(station: station, repo: repo)
        case .releaseOpened, .releaseMerged(_, _, _, _, _, true):
            break    // the rocket command that comes with it is the cue; the log line came as a .log
        case .releaseMerged(let stationName, let repo, _, _, _, false):
            // A staging release without a board and without a pallet: nothing else would move the crates.
            if ConfigStore.shared.current.project == nil, let st = fleet.stations[stationName],
               world.truth.pallets[stationName]?.repo != repo { stageCargo(station: st, repo: repo) }
        case .rocketCommand(let stationName, let repo, let label, let untested, let tall, let cargo, let command):
            simulation.rocket(station: stationName, repo: repo, label: label, untested: untested, tall: tall, cargo: cargo, command: command)
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
                markersDirty = true
            case .cleared:
                logEvent("\(label): passed QA, ready to ship")   // the record's word carries it across the deck
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
            // My own office with a worker in it: the crate does not appear by itself. The worker
            // clears the cones and packs it at the office's package slot.
            if let m = minions.values.first(where: { !$0.isCrew && !$0.isSubagent && $0.home.key == roomKey && !$0.hasLoad && !$0.onJob }),
               let st = fleet.stations[m.station], let room = st.rooms[roomKey] {
                let cell = packageCell(st, room)
                let key = m.station + "|" + roomKey
                packing.insert(key)
                markerRoot.childNodes.filter { $0.name == "box:" + key }.forEach { $0.opacity = 0 }
                clearPyramids(m)
                start(m, .pack(office: roomKey), announce: true)
                walk(m, to: standCell(st, near: cell))
            }
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

    /// Things due later on the station clock, so they wait when the clock waits.
    private var timers: [(at: Double, run: () -> Void)] = []
    func after(_ seconds: Double, _ run: @escaping () -> Void) { timers.append((clock + seconds, run)) }

    func tick(now: TimeInterval) {
        let dt = min(0.1, max(0, now - lastTick))
        lastTick = now
        // Station time runs at real speed, or faster while space is held, in steps small enough that a
        // minion still walks rather than jumps. The camera, labels and HUD stay on real time.
        var budget = dt * (sim == nil ? liveTimeScale : 1)
        while budget > 1e-9 {   // a rounding sliver is not a step: it would run every decision twice in one frame
            let step = min(budget, 1.0 / 30.0)
            budget -= step
            stepStation(dt: step)
        }
        if !headless { tickView(dt: dt) }
    }

    /// Everything that happens on the station, by its clock.
    private func stepStation(dt: Double) {
        clock += dt
        if !timers.isEmpty {
            let due = timers.filter { $0.at <= clock }
            timers.removeAll { $0.at <= clock }
            due.forEach { $0.run() }
        }
        if demo { tickDemo(dt: dt) }
        if Int(clock) % 5 == 0 && Int(clock - dt) % 5 != 0 { updatePower() }
        if clock - lastHaulSchedule > 0.5 {
            lastHaulSchedule = clock
            simulation.scheduleCarries()
            simulation.stepRockets()
            simulation.servicePallets()
            simulation.reconcileBodies()
            flushScene()   // the reconciler's beat: the source against the floor, and a redraw only if that moved a count
            timed("obstacles") { refreshObstacles() }
            simulation.replanBlockedWalks()
        }
        simulation.stepShuttles()
        simulation.stepPallets(dt: dt)
        drawShuttles(dt: dt)
        updateBerths()
        tickHullLamps()
        drawRockets()
        drawPallets()
        tickCrateMotions()
        for (id, pm) in peerMinions {
            let p = SIMD3(Double(pm.minion.node.position.x), 0, Double(pm.minion.node.position.z))
            let d = pm.target - p
            let step = min(1, dt * 2)
            pm.minion.node.position.x += CGFloat(d.x * step); pm.minion.node.position.z += CGFloat(d.z * step)
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
        tickMinions(dt: dt)
    }

    /// The view: camera, labels and HUD, on real time whatever the station clock is doing.
    private func tickView(dt: Double) {
        if hud.size != viewSize { hud.size = viewSize }
        // A desk toy's frame rate: 60 while the camera is being driven, 30 whenever the window can be seen,
        // focused or not, since it sits beside the work; 8 only when it is covered or hidden.
        let seen = (view.window?.occlusionState.contains(.visible) ?? true) && !headless
        let want = !seen ? 8 : (userDriving > 0 || keyMove != .zero || keyZoom != 0 ? 60 : 30)
        if view.preferredFramesPerSecond != want { view.preferredFramesPerSecond = want }
        if ProcessInfo.processInfo.environment["RK_FPS"] != nil {
            fpsFrames += 1
            if clock - fpsMark >= 5 { FileHandle.standardError.write("fps \(Int(Double(fpsFrames) / max(0.1, clock - fpsMark))) want \(want) seen \(seen) active \(NSApp.isActive)\n".data(using: .utf8)!); fpsFrames = 0; fpsMark = clock }
        }
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

        if let id = following {
            // The camera keeps the followed minion in the middle; the zoom and the turn stay yours.
            if let m = minions[id], m.opacity > 0.05 {
                userPan = SIMD2(Double(m.node.position.x), Double(m.node.position.z)) - targetFocus
            } else { following = nil }
        }
        let k = 1 - exp(-dt * 2)
        let focus = targetFocus + userPan
        let kp = userDriving > 0 ? 1 - exp(-dt * 25) : k
        if userDriving > 0 { userDriving -= dt }
        if floorSettling {
            rig.position.x = focus.x; rig.position.z = focus.y   // pinned: nothing to ease toward
        } else {
            rig.position.x += (focus.x - Double(rig.position.x)) * kp
            rig.position.z += (focus.y - Double(rig.position.z)) * kp
        }
        let ky = 1 - exp(-dt * 10)
        rig.eulerAngles.y += (viewYaw + userYaw - Double(rig.eulerAngles.y)) * ky
        pitchNode.eulerAngles.x += (userPitch - Double(pitchNode.eulerAngles.x)) * ky
        // Nothing eases while the floor arrives: an eased camera closes a fraction of whatever gap is
        // left each frame, which is smooth only while the frames are even, and a launch is when they
        // are least even.
        if floorSettling {
            cameraNode.camera!.orthographicScale = fitScale(half: settlingHalf) / userZoom
        } else {
            let wantScale = fitScale(half: targetHalf) / userZoom
            let scaleK = abs(userZoom - 1) > 0.001 || userZoomChanged ? 1 - exp(-dt * 14) : k
            cameraNode.camera!.orthographicScale += (wantScale - cameraNode.camera!.orthographicScale) * scaleK
        }
        userZoomChanged = false

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
        updateBubble()
        if sim == nil, clock - lastSavedView > 2 { lastSavedView = clock; saveView() }
    }

    /// Settings changed: rebuild the fleet from scratch on the next scan.
    func applyConfigChange() {
        applySharing()
        enqueue { [self] in
            let cfg = ConfigStore.shared.current
            if Looks.theme != cfg.theme {
                // A new look: the backdrop, the ships and the rockets are drawn again; the floor is
                // rebuilt below and the minions come back with the rescan in their new figures.
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
    /// Each repository's checkout, remote and pipeline, for its page in the settings window.
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

    /// Re-asks GitHub about every office, branch and release right now.
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

    /// Renders the current frame to a PNG, used for self-checks.
    func snapshot(to path: String) {
        let image = view.snapshot()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
