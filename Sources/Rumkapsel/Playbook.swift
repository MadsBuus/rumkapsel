import AppKit
import SwiftUI

enum PlaybookCamera {
    case whole(Double)
    case follow(String, Double)
    case area(String, Double)
}

enum PlaybookWait: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    case beat(Double)
    case until(String, (StationController) -> Bool)

    init(floatLiteral value: Double) { self = .beat(value) }
    init(integerLiteral value: Int) { self = .beat(Double(value)) }

    static func crate(_ n: Int, _ words: String, _ holds: @escaping (Ledger.Crate) -> Bool) -> PlaybookWait {
        .until("#\(n) \(words)") { c in c.fleet.stations.values.contains { $0.ledger["web", n].map(holds) ?? false } }
    }
    static func inStorage(_ n: Int) -> PlaybookWait { crate(n, "in storage") { $0.stands(in: .storage) } }
    static func onDeck(_ n: Int) -> PlaybookWait { crate(n, "back on the deck") { $0.area == .deck && !$0.inTransit } }
    static func onStack(_ n: Int) -> PlaybookWait { crate(n, "on the cleared rows") { $0.area == .tested && !$0.inTransit } }
    static func pickedUp(_ n: Int) -> PlaybookWait {
        .until("#\(n) picked up") { c in c.minions.values.contains { m in
            if m.carried != nil, case .crate(let crate)? = m.load { return crate.number == n }
            return false
        } }
    }
    static func loaded(_ n: Int) -> PlaybookWait { crate(n, "in the rocket") { $0.area == .pad } }
    static let bodiesUp = PlaybookWait.until("bodies spawned") { c in !c.minions.isEmpty }
    static let rocketOnPad = PlaybookWait.until("web's rocket on the pad") { c in c.world.padKeys().contains { $0.hasSuffix("|web") } }
    static let bodyOnDeck = PlaybookWait.until("somebody in the hall") { c in
        c.minions.values.contains { m in c.fleet.stations[m.station]?.hall.cells.contains(m.cell) ?? false }
    }
    static let toStaged = PlaybookWait.until("web's crates going to the staged rows") { c in
        c.fleet.stations.values.contains { $0.ledger.crates(of: "web").contains { $0.heading == .deck } }
    }
    static let stagedDown = PlaybookWait.until("web's crates down on the staged rows") { c in
        c.fleet.stations.values.contains { st in
            let web = st.ledger.crates(of: "web")
            return web.contains { $0.placed == .deck && !$0.cleared } && !web.contains { $0.heading == .deck || $0.placed == .storage }
        }
    }
    static func welderUp(_ repo: String) -> PlaybookWait {
        .until("\(repo)'s tip under the torch") { c in c.simulation.drones.values.joined().contains { d in
            if case .weld(let key) = d.task { return d.torch && key.hasSuffix("|" + repo) }
            return false
        } }
    }
    static func weldAlmost(_ repo: String) -> PlaybookWait {
        .until("\(repo)'s weld nearly done") { c in c.simulation.rockets.values.contains {
            $0.repo == repo && $0.welding && $0.welded >= Double(RocketGeometry.panels - 1) } }
    }
    static let flightFarOut = PlaybookWait.until("the flight far out") { c in c.mission.map { $0.progress(at: c.clock) > 0.8 } ?? false }
}

struct PlaybookEntry {
    let name: String
    let seeing: String
    let group: String
    let moves: [(String, PlaybookWait)]
    let camera: PlaybookCamera
    let tail: Double
    let yard: Bool
    let bay: Bool
    let rooms: Set<String>
    let crowd: Bool
    let settle: Double

    static let idleRooms: Set<String> = ["kind:quarters", "kind:lounge", "kind:bath", "kind:gym"]

    init(_ group: String, _ name: String, _ seeing: String, _ moves: [(String, PlaybookWait)], camera: PlaybookCamera,
         tail: Double = 8, yard: Bool = false, bay: Bool = false,
         rooms: Set<String> = PlaybookEntry.idleRooms, crowd: Bool = true, settle: Double = 0) {
        self.group = group; self.name = name; self.seeing = seeing; self.moves = moves; self.camera = camera
        self.tail = tail; self.yard = yard; self.bay = bay
        self.rooms = rooms; self.crowd = crowd; self.settle = settle
    }
}

enum Playbook {
    private static let office = "task:web#455"
    private static let who = "booking"
    private static func at(_ moves: [(String, PlaybookWait)]) -> [(String, PlaybookWait)] { [("Target: web#455", 0.4)] + moves }

    private static let tested = 430
    private static var passQA: String { "Board: Move web#\(tested) to \(ConfigStore.shared.current.statuses.cleared)" }
    private static let approved = 431

    static let entries: [PlaybookEntry] = [
        desk("Session: coding", "minion hammers at the desk", "coding"),
        desk("Session: reading code", "minion reads at the desk", "reading code"),
        desk("Session: running tests", "minion runs tests at the desk", "testing"),
        desk("Session: writing", "minion writes at the desk", "writing"),
        desk("Session: thinking", "minion thinks at the desk", "thinking"),
        desk("Session: waiting for you", "minion stops and waits, no cone", "waiting for you"),
        PlaybookEntry("office", "Session: web research", "subagent walks to the monolith", at([("Set: session = web research", 1)]),
                      camera: .whole(2.6), tail: 16, rooms: [], crowd: false),
        PlaybookEntry("office", "Session: QA testing", "minion walks the deck rows", at([("Set: session = QA testing", 1)]),
                      camera: .follow(who, 4), tail: 22, yard: true, rooms: [], crowd: false, settle: 8),
        PlaybookEntry("office", "Message sent", "new cone appears, minion works it", at([("Set: session = coding", 1), ("Prompt", 1)]),
                      camera: .follow(who, 4), tail: 16, rooms: [], crowd: false),
        PlaybookEntry("office", "Commit", "cube stowed on the office floor", at([("Set: session = coding", 1), ("Commit", 1)]),
                      camera: .follow(who, 4), tail: 12, rooms: [], crowd: false),
        PlaybookEntry("office", "Session ends", "minion leaves, office stays", at([("Set: session = coding", 1), ("Session ends", 2)]),
                      camera: .follow(who, 4), tail: 16, rooms: [], crowd: false),

        PlaybookEntry("pull request", "PR opened", "crate packed in the office", at([("Open PR", 2)]),
                      camera: .follow(who, 4), tail: 14, rooms: [], crowd: false),
        PlaybookEntry("pull request", "PR checks fail", "crate light turns red", at([("Open PR", 2), ("Checks failing", 2)]),
                      camera: .follow(who, 4), tail: 14, rooms: [], crowd: false),
        PlaybookEntry("pull request", "PR approved", "crate light turns green", at([("Open PR", 2), ("Approve PR", 2)]),
                      camera: .follow(who, 4), tail: 14, rooms: [], crowd: false),
        PlaybookEntry("pull request", "PR merged", "crate carried to storage", at([("Open PR", 2), ("Merge PR", .inStorage(455))]),
                      camera: .whole(1.8), tail: 8, yard: true, rooms: [], crowd: false),
        PlaybookEntry("pull request", "PR closed unmerged", "crate turns red", at([("Open PR", 2), ("Close PR", 2)]),
                      camera: .follow(who, 4), tail: 16, rooms: [], crowd: false),

        PlaybookEntry("release", "Staging PR merged", "web's crates are carried from storage to the staged rows, the back row by a toss",
                      [("16x", 0.5), ("Release: Staging opens", 0.25), ("1x", 0.25), ("Release: Staging merges", .toStaged), ("1x", .stagedDown)],
                      camera: .area("hall", 2.4), tail: 6, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Staging deploy running", "web's tip is welded over ring by ring by a drone circling the hull",
                      [("16x", 0.5), ("Release: Staging opens", 0.25), ("Release: Staging merges", 0.25),
                       ("Deploy: Staging starts", .welderUp("web")), ("1x", .weldAlmost("web")), ("Deploy: Staging goes live", 4)],
                      camera: .area("pad", 3), tail: 6, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Staging deploy running, new rocket", "the tip is welded together panel by panel by a drone circling the hull (api's first release)",
                      [("Target: api#5158", 0.4), ("16x", 0.5), ("Release: Staging opens", 0.25), ("Release: Staging merges", 0.25),
                       ("Deploy: Staging starts", 0.5), ("GitHub: Poll", .welderUp("api")), ("1x", .weldAlmost("api")), ("Deploy: Staging goes live", 4)],
                      camera: .area("pad", 3), tail: 6, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Staging deploy live", "the staged crates' lights turn from blue to amber: ready for a tester",
                      [("16x", 0.5), ("Release: Staging opens", 0.25), ("Release: Staging merges", 0.25), ("Deploy: Staging starts", .stagedDown),
                       ("1x", 1), ("Deploy: Staging goes live", 4)],
                      camera: .area("deck", 2.6), tail: 6, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "QA approves a crate", "carried from the staged rows across the aisle to the cleared rows",
                      [("4x", 0.5), (passQA, .pickedUp(tested)), ("1x", .onStack(tested))],
                      camera: .area("yard", 2.7), tail: 6, yard: true, rooms: [], crowd: false),
        PlaybookEntry("release", "Production PR opened", "two drones fly the kick stage in under the tip as the cradle raises it",
                      [("1x", 0.5), ("Release: Production opens", 12)],
                      camera: .area("pad", 3), tail: 4, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Production PR merged", "the drones form a ring at the field and the vortex pulls web's cleared crates through it, spiralling them into the rocket",
                      [("16x", 0.5), ("Release: Production opens", 2), ("1x", 0.5), ("Release: Production merges", .loaded(approved))],
                      camera: .area("yard", 2.6), tail: 4, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Production deploy succeeds", "the rocket flies to its colony and lands", [("16x", 0.5), ("Release: Production opens", 2), ("Release: Production merges", 2),
                                                                           ("1x", 0.5), ("Deploy: Production starts", .flightFarOut), ("Deploy: Goes live", 30)],
                      camera: .area("pad", 2.4), tail: 4, yard: true, rooms: [], crowd: true),

        PlaybookEntry("detours", "Staging deploy fails", "the staged crates' lights turn red",
                      [("16x", 0.5), ("Release: Staging opens", 0.25), ("Release: Staging merges", 0.25), ("Deploy: Staging starts", .stagedDown),
                       ("1x", 1), ("Deploy: Staging fails", 6)],
                      camera: .area("deck", 2.6), tail: 4, yard: true, rooms: [], crowd: true),
        PlaybookEntry("detours", "Production deploy fails", "the flight loses signal", [("16x", 0.5), ("Release: Production opens", 2), ("Release: Production merges", 2),
                                                                         ("1x", 0.5), ("Deploy: Production starts", .flightFarOut), ("Deploy: Fails", 10)],
                      camera: .area("pad", 2.4), tail: 4, yard: true, rooms: [], crowd: true),

        PlaybookEntry("others", "Teammate PR opened", "crate packed in the teammate's office", [("Teammate: Open PR", 2)],
                      camera: .whole(2.0), tail: 18, rooms: []),
        PlaybookEntry("others", "Teammate PR merged", "teammate's crate carried to storage", [("Teammate: Open PR", 2), ("Teammate: Merge PR", 3)],
                      camera: .whole(1.8), tail: 26, yard: true, rooms: []),
        PlaybookEntry("others", "Bot PR opened", "object arrives in decon", [("Bot: Open PR", 2)],
                      camera: .whole(2.0), tail: 18, yard: true, rooms: []),
        PlaybookEntry("others", "Peer station connects", "peer's offices fade in", [("Peer: Leave", 2), ("Peer: Arrive", 2)],
                      camera: .whole(2.0), tail: 16, rooms: []),
        PlaybookEntry("others", "Peer station disconnects", "peer's offices fade out", [("Peer: Leave", 2)],
                      camera: .whole(2.0), tail: 16, rooms: []),

        PlaybookEntry("life", "Session asleep", "minion goes to its bunk", at([("Set: session = sleeping", 1), ("Night", 3)]),
                      camera: .follow(who, 4), tail: 30, rooms: ["kind:quarters"], crowd: false, settle: 8),
        PlaybookEntry("life", "All sessions asleep", "all minions go to their bunks", [("Everyone asleep", 3), ("Night", 3)],
                      camera: .follow(who, 3.2), tail: 34, rooms: ["kind:quarters"], settle: 12),
        PlaybookEntry("life", "Session wakes", "minion gets up, back to the desk", at([("Set: session = sleeping", 1), ("Night", 14),
                                        ("Day", 1), ("Set: session = coding", 2)]),
                      camera: .follow(who, 4), tail: 22, rooms: ["kind:quarters"], crowd: false),
        PlaybookEntry("life", "Bath", "minion showers and dries off", [("Bath", 2)], camera: .follow(who, 4), tail: 28,
                      rooms: ["kind:bath"], crowd: false, settle: 7),
        PlaybookEntry("life", "Workout", "minion uses the gym", [("Workout", 2)], camera: .follow(who, 4), tail: 28,
                      rooms: ["kind:gym"], crowd: false, settle: 7),
        PlaybookEntry("life", "Everyone to the lounge", "minions sit on the couches", [("Everyone to lounge", 2)],
                      camera: .follow(who, 4), tail: 20, rooms: ["kind:lounge"]),
        PlaybookEntry("life", "Chore", "minion does a chore", [("Chore", 2)], camera: .whole(2.2), tail: 22,
                      rooms: ["kind:lounge"], crowd: false),
        PlaybookEntry("life", "Meeting in the hall", "two minions meet in the hallway", [("Meet in the hall", 2)], camera: .whole(2.0), tail: 20, rooms: []),
    ]

    private static func desk(_ name: String, _ seeing: String, _ session: String) -> PlaybookEntry {
        PlaybookEntry("office", name, seeing, at([("Set: session = \(session)", 1)]),
                      camera: .follow(who, 4), tail: 14, rooms: [], crowd: false)
    }

    static func find(_ words: String) -> Int? {
        let want = words.lowercased()
        return entries.firstIndex { $0.name.lowercased().contains(want) }
    }

    static let groups = ["office", "pull request", "release", "detours", "others", "life"]
    static func shelfTitle(_ group: String) -> String {
        ["office": "Session", "pull request": "Pull request", "release": "Release", "detours": "When a release goes another way",
         "others": "Other people", "life": "Idle"][group] ?? group
    }
    static func onShelf(_ group: String) -> [(offset: Int, entry: PlaybookEntry)] {
        entries.enumerated().filter { $0.element.group == group }.map { ($0.offset, $0.element) }
    }
}

struct PlaybookPanel: View {
    @ObservedObject var model: PlaybookModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Playbook.groups, id: \.self) { group in
                        Text(Playbook.shelfTitle(group))
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 6)
                        ForEach(Playbook.onShelf(group), id: \.offset) { row in
                            Button { model.play(row.offset) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.entry.name).font(.system(size: 12))
                                    Text(model.subtitle(row.entry)).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(model.playing == row.offset ? Color.accentColor.opacity(0.25) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 6)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            Divider()
            HStack(spacing: 6) {
                Button("Replay") { model.play(model.playing) }
                Button(model.paused ? "Resume" : "Pause") { model.togglePause() }
                Picker("", selection: $model.speed) {
                    Text("¼×").tag("¼x"); Text("½×").tag("½x"); Text("1×").tag("1x")
                }
                .pickerStyle(.segmented).frame(width: 120)
            }
            .controlSize(.small).padding(.horizontal, 10).padding(.top, 8)
            Text(model.status).font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}

@MainActor
final class PlaybookModel: ObservableObject {
    @Published var playing = 0
    @Published var status = ""
    @Published var speed = "1x" { didSet { onSpeed?(speed) } }
    @Published var paused = false
    var onSpeed: ((String) -> Void)?
    var onPause: ((Bool) -> Void)?
    func togglePause() { paused.toggle(); onPause?(paused) }
    var restart: ((Int) -> Void)?

    func play(_ k: Int) { restart?(k) }
    func subtitle(_ e: PlaybookEntry) -> String { e.seeing }
}

@MainActor
final class PlaybookController {
    let view = NSView()
    let model = PlaybookModel()
    private(set) var station: StationController
    private var sim: SimulatorModel
    private var panel: NSHostingView<PlaybookPanel>
    private var script: [Timer] = []
    private var camera: Timer?
    private var aimed = false
    private var clock = 0.0
    private var loop: Timer?
    private let listWidth = 240.0
    private var stationRect: NSRect { NSRect(x: listWidth, y: 0, width: max(1, view.bounds.width - listWidth), height: view.bounds.height) }

    init(frame: NSRect) {
        let stationRect = NSRect(x: listWidth, y: 0, width: frame.width - listWidth, height: frame.height)
        station = StationController(frame: stationRect, demo: false, simulated: true)
        sim = SimulatorModel(station: station)
        panel = NSHostingView(rootView: PlaybookPanel(model: model))
        view.frame = frame
        view.autoresizingMask = [.width, .height]
        panel.frame = NSRect(x: 0, y: 0, width: listWidth, height: frame.height)
        panel.autoresizingMask = [.height, .maxXMargin]
        view.addSubview(panel)
        mount(stationRect)
        model.restart = { [weak self] k in self?.start(k) }
        model.onSpeed = { [weak self] speed in self?.sim.press(speed) }
        model.onPause = { [weak self] paused in self?.sim.press(paused ? "Pause" : "Resume") }
    }

    private func mount(_ rect: NSRect) {
        station.view.frame = rect
        station.view.autoresizingMask = [.width, .height]
        station.viewSize = rect.size
        station.view.postsFrameChangedNotifications = true
        let shown = station.view, told = station
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: shown, queue: .main) { [weak told, weak shown] _ in
            MainActor.assumeIsolated { if let shown { told?.viewSize = shown.bounds.size } }
        }
        station.drone.isEnabled = false
        station.settlesView = false
        view.addSubview(station.view)
    }

    func start(_ k: Int) {
        guard k >= 0, k < Playbook.entries.count else { return }
        let entry = Playbook.entries[k]
        script.forEach { $0.invalidate() }; script = []
        camera?.invalidate(); camera = nil
        aimed = false
        clock = 0
        loop?.invalidate(); loop = nil
        sim.quiesce()
        station.quiesce()
        station.view.removeFromSuperview()
        let stationRect = self.stationRect
        station = StationController(frame: stationRect, demo: false, simulated: true)
        sim = SimulatorModel(station: station)
        mount(stationRect)
        model.playing = k
        model.status = entry.name
        let work = station.fleet.station("work", fixed: entry.rooms.sorted().map { Place.room($0) })
        work.hasPad = entry.yard
        work.hasHangar = entry.bay
        FileHandle.standardError.write("playbook \(entry.name): rooms \(work.rooms.keys.sorted().joined(separator: " ")), yard \(entry.yard), bay \(entry.bay), crowd \(entry.crowd)\n".data(using: .utf8)!)
        sim.seed(crowd: entry.crowd)
        let hands: [(String, PlaybookWait)] = [("", .bodiesUp), ("GitHub: Poll", .rocketOnPad), ("Hands: one free on the deck", .bodyOnDeck)]
        let moves = (entry.yard ? hands : []) + entry.moves
        var next = 0, pressedAt = 0.0, waited = 0.0
        script.append(Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                waited += 0.25
                if next > 0 {
                    switch moves[next - 1].1 {
                    case .beat(let s): if waited - pressedAt < s { return }
                    case .until(let words, let holds):
                        if !holds(self.station) {
                            guard waited - pressedAt > 120 else { return }
                            FileHandle.standardError.write("playbook \(entry.name): waited two minutes for \(words), it never came\n".data(using: .utf8)!)
                        }
                    }
                }
                guard next < moves.count else {
                    t.invalidate()
                    self.loop = Timer.scheduledTimer(withTimeInterval: entry.tail, repeats: false) { [weak self] _ in
                        MainActor.assumeIsolated { self?.start(k) }
                    }
                    return
                }
                let name = moves[next].0
                if !name.isEmpty {
                    FileHandle.standardError.write("playbook \(entry.name): \(String(format: "%.2f", waited))s press \(name)\n".data(using: .utf8)!)
                    self.sim.press(name == "1x" ? self.model.speed : name)
                }
                next += 1; pressedAt = waited
            }
        })
        clock = 0
        camera = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.clock += 0.5; self?.hold(entry) }
        }
    }

    private func hold(_ entry: PlaybookEntry) {
        guard !aimed else { return }
        guard clock >= entry.settle else { return }
        if case .follow = entry.camera, station.minions.isEmpty { return }
        aimed = true
        aim(entry.camera)
    }

    private func aim(_ camera: PlaybookCamera) {
        switch camera {
        case .whole(let zoom): station.setView(yawDegrees: 0, pitchDegrees: -30, zoom: zoom)
        case .follow(let who, let zoom): station.follow(named: who, zoom: zoom)
        case .area(let name, let zoom): station.look(at: name, in: station.fleet.ordered.first?.name ?? "work", zoom: zoom)
        }
    }

    func snapshot(to path: String) {
        let shot = station.composedSnapshot()
        guard let tiff = shot.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
