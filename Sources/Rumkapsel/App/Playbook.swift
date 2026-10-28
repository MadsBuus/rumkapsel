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

    static func crate(_ n: Int, _ words: String, _ holds: @escaping (Shown.At) -> Bool) -> PlaybookWait {
        .until("#\(n) \(words)") { c in c.simulation.shown.values.contains { $0.crates[CrateID(repo: "web", number: n)].map(holds) ?? false } }
    }
    static func inStorage(_ n: Int) -> PlaybookWait { crate(n, "in storage") { if case .row(let s) = $0 { return s.zone == .waiting }; return false } }
    static func onStack(_ n: Int) -> PlaybookWait { crate(n, "on the cleared rows") { if case .row(let s) = $0 { return s.zone == .cleared }; return false } }
    static func pickedUp(_ n: Int) -> PlaybookWait {
        .until("#\(n) picked up") { c in c.minions.values.contains { m in
            if m.carried != nil, case .crate(let crate)? = m.load { return crate.number == n }
            return false
        } }
    }
    static func loaded(_ n: Int) -> PlaybookWait { crate(n, "in the rocket") { if case .aboard = $0 { return true }; return false } }
    static let sliceOut = PlaybookWait.until("#455's slice out on the rows") { c in
        let slices = c.world.works.slices(repo: "web", of: 455).compactMap(\.number)
        return c.simulation.shown.values.contains { v in slices.contains { n in if case .row? = v.crates[CrateID(repo: "web", number: n)] { return true }; return false } }
    }
    static let bodiesUp = PlaybookWait.until("bodies spawned") { c in !c.minions.isEmpty }
    static let rocketOnPad = PlaybookWait.until("web's rocket on the pad") { c in c.simulation.shown.values.contains { $0.rockets.values.contains { $0.repo == "web" } } }
    static let bodyOnDeck = PlaybookWait.until("somebody in the hall") { c in
        c.minions.values.contains { m in c.fleet.stations[m.station]?.hall.cells.contains(m.cell) ?? false }
    }
    static let toStaged = PlaybookWait.until("web's crates going to the staged rows") { c in
        c.simulation.cargo.values.contains { $0.crate.repo == "web" && $0.spot?.zone == .testing }
    }
    static let stagedDown = PlaybookWait.until("web's crates down on the staged rows") { c in
        c.fleet.stations.values.contains { st in
            let web = st.facts.crates.values.filter { $0.id.repo == "web" }
            let view = c.simulation.shown[st.name] ?? Shown()
            return web.contains { $0.zone == .testing } && !web.contains { $0.zone == .waiting }
                && web.allSatisfy { f in if case .row(let s)? = view.crates[f.id] { return s.zone == f.zone }; return f.zone == nil }
        }
    }
    static func welderUp(_ repo: String) -> PlaybookWait {
        .until("\(repo)'s tip under the torch") { c in c.simulation.drones.values.joined().contains { d in
            if case .weld(let key) = d.task { return d.torch && key.hasSuffix("|" + repo) }
            return false
        } }
    }
    static func weldAlmost(_ repo: String) -> PlaybookWait {
        .until("\(repo)'s weld nearly done") { c in c.simulation.shown.values.contains { $0.rockets.values.contains {
            $0.repo == repo && $0.welding && $0.welded >= Double(RocketGeometry.panels - 1) } } }
    }
    static let flightFarOut = PlaybookWait.until("the flight far out") { c in c.missions.last.map { $0.progress(at: c.clock) > 0.8 } ?? false }
    static let flightsFarOut = PlaybookWait.until("both flights far out") { c in c.missions.count >= 2 && c.missions.allSatisfy { $0.progress(at: c.clock) > 0.8 } }
    static let hotfixGone = PlaybookWait.until("the hotfix rocket climbed") { c in
        !c.simulation.shown.values.contains { $0.rockets.values.contains { if case .hotfix = $0.kind { return true }; return false } }
    }
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

    static let idleRooms: Set<String> = ["kind:quarters", "kind:lounge", "kind:bath", "kind:gym", "kind:galley"]

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
        PlaybookEntry("office", "Probes reading code", "two probes lift off the minion and scan its office, then one flies back and docks",
                      at([("Probe: Read code", 2), ("Probe: Read code", 14), ("Probe: Done", 10)]), camera: .follow(who, 12), tail: 8, rooms: [], crowd: false),
        PlaybookEntry("office", "Probe researching", "a probe shuttles between the monolith and its minion, carrying the answer home, then docks",
                      at([("Probe: Research", 40), ("Probe: Done", 10)]), camera: .whole(2.2), tail: 8, rooms: [], crowd: false),
        PlaybookEntry("office", "Session: web research", "the session's minion walks to the monolith", at([("Set: session = web research", 1)]),
                      camera: .whole(2.6), tail: 16, rooms: [], crowd: false),
        PlaybookEntry("office", "Session: QA testing", "minion walks the deck rows", at([("Set: session = QA testing", 1)]),
                      camera: .follow(who, 4), tail: 22, yard: true, rooms: [], crowd: false, settle: 8),
        PlaybookEntry("office", "Message sent", "new cone appears, minion works it", at([("Set: session = coding", 1), ("Prompt", 1)]),
                      camera: .follow(who, 4), tail: 16, rooms: [], crowd: false),
        PlaybookEntry("office", "Commit", "cube stowed on the office floor", at([("Set: session = coding", 1), ("Commit", 1)]),
                      camera: .follow(who, 4), tail: 12, rooms: [], crowd: false),
        PlaybookEntry("office", "New office by shuttle", "a shuttle sets leo's new office down in the bay as a crate, he carries it to the door and the office unfolds from there",
                      [("Target: api#5158", 6), ("Teammate: New branch", 4), ("Teammate: Open PR", 30)], camera: .whole(2.0), tail: 6, bay: true, rooms: []),
        PlaybookEntry("office", "Office folds", "kim's office is kicked off: the floor rolls up toward the door into a crate that sinks away",
                      [("Target: web#460", 6), ("Peer: Kick office", 8)], camera: .whole(2.0), tail: 6, rooms: []),
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
        PlaybookEntry("pull request", "Epic: part of the issue merged", "a pull request that doesn't close its issue: its crate is carried to storage and the office stays, with a planning console, a pennant and a tally",
                      at([("Set: session = coding", 1), ("Open PR, part of the issue", 2), ("Merge PR", .sliceOut)]),
                      camera: .follow(who, 3), tail: 16, yard: true, rooms: [], crowd: false),
        PlaybookEntry("pull request", "Epic: resident at the console", "the epic's minion codes upright at the console while its session works, and leans back there when it goes quiet",
                      at([("Set: session = coding", 1), ("Open PR, part of the issue", 2), ("Merge PR", .sliceOut),
                          ("Prompt", 12), ("Set: session = sleeping", 14)]),
                      camera: .follow(who, 3), tail: 30, yard: true),
        PlaybookEntry("pull request", "Epic: issue closed", "the epic's issue closes: the office packs up and leaves like any finished office",
                      at([("Open PR, part of the issue", 2), ("Merge PR", .sliceOut), ("Issue closes", 4)]),
                      camera: .whole(1.8), tail: 14, yard: true, rooms: [], crowd: false),

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
        PlaybookEntry("release", "Production PR opened", "the iris opens, the tip goes down the shaft onto its kick stage and the deck raises the stack flush with the pad",
                      [("1x", 0.5), ("Release: Production opens", 12)],
                      camera: .area("pad", 3), tail: 4, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Rocket waits on testing", "arrows in the repository's colour run across the aisle from its untested crates to the cleared rows",
                      [("1x", 0.5), ("Release: Production opens", 12)],
                      camera: .area("deck", 2.6), tail: 10, yard: true, rooms: [], crowd: false),
        PlaybookEntry("release", "Production PR merged", "the drones form a ring at the field and the vortex pulls web's cleared crates through it, spiralling them into the rocket",
                      [("16x", 0.5), ("Release: Production opens", 2), ("1x", 0.5), ("Release: Production merges", .loaded(approved))],
                      camera: .area("yard", 2.6), tail: 4, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Production deploy succeeds", "the rocket flies to its colony and lands", [("16x", 0.5), ("Release: Production opens", 2), ("Release: Production merges", 2),
                                                                           ("1x", 0.5), ("Deploy: Production starts", .flightFarOut), ("Deploy: Goes live", 30)],
                      camera: .area("pad", 2.4), tail: 4, yard: true, rooms: [], crowd: true),

        PlaybookEntry("release", "Production deploy from the pad", "the deploy starts at the merge: the vortex loads the rocket, it climbs off its pad and the flight takes it from there while the deck sinks",
                      [("16x", 0.5), ("Release: Production opens", 2), ("1x", 0.5), ("Release: Production merges", 1), ("Deploy: Production starts", .flightFarOut),
                       ("Deploy: Goes live", 30)],
                      camera: .area("pad", 2.4), tail: 4, yard: true, rooms: [], crowd: true),

        PlaybookEntry("release", "Two production deploys at once", "web lifts off, then api a few seconds later: each has its own flight and screen, stacked, and each lands on its own",
                      [("16x", 0.5), ("Target: web#455", 0.4), ("Release: Production opens", 2), ("Release: Production merges", 2),
                       ("Target: api#5158", 0.4), ("Release: Production opens", 2), ("Release: Production merges", 2), ("1x", 0.5),
                       ("Target: web#455", 0.4), ("Deploy: Production starts", 6), ("Target: api#5158", 0.4), ("Deploy: Production starts", .flightsFarOut),
                       ("Deploy: Goes live", 8), ("Target: web#455", 0.4), ("Deploy: Goes live", 30)],
                      camera: .area("pad", 2.4), tail: 4, yard: true, rooms: [], crowd: true),

        PlaybookEntry("release", "Hotfix PR opened", "an express rocket with a red tip stands beside web's release rocket",
                      at([("1x", 0.5), ("Release: Production opens", 2), ("Release: Hotfix opens", 12)]),
                      camera: .area("pad", 3), tail: 4, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Hotfix PR merged", "#455's crate is carried to storage, the vortex pulls it into the express rocket and it goes up; the release rocket stays",
                      at([("1x", 0.5), ("Release: Production opens", 2), ("Release: Hotfix opens", 6), ("Release: Hotfix merges", .hotfixGone)]),
                      camera: .area("yard", 2.6), tail: 10, yard: true, rooms: [], crowd: true),

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
        PlaybookEntry("others", "A neighbour's minion takes a break", "kim's minion, in its orange suit, takes a turn in the gym, sits on the couch, then goes back to work",
                      [("Peer: Arrive", 2), ("Peer: To the gym", 24), ("Peer: To the lounge", 16), ("Peer: Back to work", 12)],
                      camera: .follow("kim", 3), tail: 4),

        PlaybookEntry("life", "Session asleep", "minion goes to its bunk", at([("Set: session = sleeping", 1), ("Night", 3)]),
                      camera: .follow(who, 4), tail: 30, rooms: ["kind:quarters"], crowd: false, settle: 8),
        PlaybookEntry("life", "All sessions asleep", "all minions go to their bunks", [("Everyone asleep", 3), ("Night", 3)],
                      camera: .follow(who, 3.2), tail: 34, rooms: ["kind:quarters"], settle: 12),
        PlaybookEntry("life", "Session wakes", "minion gets up, back to the desk", at([("Set: session = sleeping", 1), ("Night", 14),
                                        ("Day", 1), ("Set: session = coding", 2)]),
                      camera: .follow(who, 4), tail: 22, rooms: ["kind:quarters"], crowd: false),
        PlaybookEntry("life", "Bath", "minion showers and dries off", [("Bath", 2)], camera: .follow(who, 4), tail: 28,
                      rooms: ["kind:bath"], crowd: false, settle: 7),
        PlaybookEntry("life", "Bath: the bowl", "minion turns round, sits on the bowl, gets up and it flushes", [("Bath: the bowl", 2)], camera: .follow(who, 4), tail: 28,
                      rooms: ["kind:bath"], crowd: false, settle: 7),
        PlaybookEntry("life", "Workout", "minion uses the gym", [("Workout", 2)], camera: .follow(who, 4), tail: 28,
                      rooms: ["kind:gym"], crowd: false, settle: 7),
        PlaybookEntry("life", "Coffee", "minion makes a coffee in the galley and takes it back to the couch", [("Coffee", 2)],
                      camera: .area("galley", 7), tail: 40, rooms: ["kind:lounge", "kind:galley"], crowd: false, settle: 7),
        PlaybookEntry("life", "A bite", "the galley prints a bowl of noodles; minion eats it on the couch, bowl and all", [("A bite", 2)],
                      camera: .area("galley", 5), tail: 130, rooms: ["kind:lounge", "kind:galley"], crowd: false, settle: 7),
        PlaybookEntry("life", "Mission control", "two minions take a turn in mission control: one at a console, one at the holo table",
                      [("Mission control: a console", 2), ("Mission control: the holo table", 3)], camera: .area("mission", 5), tail: 60,
                      yard: true, rooms: ["kind:lounge", "kind:mission"], crowd: false, settle: 7),
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
        let tempo: Set<String> = ["1x", "4x", "16x", "Pause", "Resume", ""]
        let subject = moves.lastIndex { !tempo.contains($0.0) } ?? moves.count
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
                if next == subject { self.station.simulation.skip() }
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
