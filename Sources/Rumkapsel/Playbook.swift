// The playbook: a list of things the station can do, and the station doing the one you picked.
//
// A stage entry owns no geometry and no motion. It is a station, a handful of presses, a camera and a
// clock — the presses are the simulator's own, which write through the entry points production uses, so
// what you watch is the station working, not a picture of it working. Nothing here can show something
// the station cannot do, because nothing here draws.
//
//     --playbook                 the window: the list on the left, the station on the right
//     --playbook --entries       every entry's name, one per line
//     --playbook --entry <words> plays the first entry whose name has those words
//
// An entry ends, the station is torn down and seeded again, and it plays from the top.

import AppKit
import SwiftUI

/// Where the camera sits for an entry: on one area of the floor, on one body, or back far enough for all
/// of it. `zoom` is the station's own, so these are the same framings `--focus` and `--follow` give.
enum PlaybookCamera {
    /// Back far enough for the whole floor.
    case whole(Double)
    /// With one body, named loosely: its id, or any part of its office's name. The camera keeps up with
    /// it and lets go the moment you pan, which is the point — the play aims once and the view is yours.
    case follow(String, Double)
    /// On one area of the floor: "pad", "deck", "storage", "bay", or a room's name, as `--look` takes them.
    case area(String, Double)
}

/// What a move waits for before the next is pressed: a short beat, or a fact about the station coming
/// true. A carry takes as long as it takes, so anything that waits for one waits for its fact, never a
/// guess at its length.
enum PlaybookWait: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    /// Seconds, for a beat between presses that need nothing to have happened.
    case beat(Double)
    /// Until the fact holds, named for the log.
    case until(String, (StationController) -> Bool)

    init(floatLiteral value: Double) { self = .beat(value) }
    init(integerLiteral value: Int) { self = .beat(Double(value)) }

    /// A crate of web's, by number, in a place.
    static func crate(_ n: Int, _ words: String, _ holds: @escaping (Ledger.Crate) -> Bool) -> PlaybookWait {
        .until("#\(n) \(words)") { c in c.fleet.stations.values.contains { $0.ledger["web", n].map(holds) ?? false } }
    }
    static func inStorage(_ n: Int) -> PlaybookWait { crate(n, "in storage") { $0.stands(in: .storage) } }
    /// Set down on the deck's untested row, or on its stack by the rocket, by where it was put down last.
    static func onDeck(_ n: Int) -> PlaybookWait { crate(n, "back on the deck") { $0.area == .deck && !$0.inTransit } }
    static func onStack(_ n: Int) -> PlaybookWait { crate(n, "on its stack by the rocket") { $0.area == .tested && !$0.inTransit } }
    /// Picked up: on somebody's arms.
    static func pickedUp(_ n: Int) -> PlaybookWait {
        .until("#\(n) picked up") { c in c.minions.values.contains { m in
            if m.carried != nil, case .crate(let crate)? = m.load { return crate.number == n }
            return false
        } }
    }
    static func loaded(_ n: Int) -> PlaybookWait { crate(n, "in the rocket") { $0.area == .pad } }
    /// Bodies spawned: the seed's scan has come back.
    static let bodiesUp = PlaybookWait.until("bodies spawned") { c in !c.minions.isEmpty }
    /// Web's rocket has its place on the pad, so web's tested crates stand on their stack beside it.
    static let rocketOnPad = PlaybookWait.until("web's rocket on the pad") { c in
        c.fleet.stations.values.contains { c.world.testedStack(station: $0, repo: "web") != nil }
    }
    /// Somebody standing on the deck.
    static let bodyOnDeck = PlaybookWait.until("somebody on the deck") { c in
        c.minions.values.contains { m in c.fleet.stations[m.station]?.deckCells.contains(m.cell) ?? false }
    }
    /// The pallet out and loaded, and gone again once emptied.
    static let palletLoaded = PlaybookWait.until("the pallet loaded") { c in c.world.truth.pallets.values.contains { $0.state == .loaded } }
    static let palletGone = PlaybookWait.until("the pallet emptied") { c in c.world.truth.pallets.isEmpty }
    /// A repository's tip all but built: every panel on but the last, which waits for staging to be live.
    static func tipAlmost(_ repo: String) -> PlaybookWait {
        .until("\(repo)'s tip nearly built") { c in c.simulation.rockets.values.contains { $0.repo == repo && $0.panels >= RocketGeometry.panels - 1 } }
    }
    /// Across on the deck, still loaded, waiting for staging.
    static let palletStaged = PlaybookWait.until("the pallet on the deck") { c in c.world.truth.pallets.values.contains { $0.state == .staged } }
    /// The flight most of the way to its planet.
    static let flightFarOut = PlaybookWait.until("the flight far out") { c in c.mission.map { $0.progress(at: c.clock) > 0.8 } ?? false }
}

/// One thing the station can do: what floor it needs standing, what to press, where to look, and how
/// long before it starts over.
///
/// There is no speed on an entry. Speed belongs to a moment, not to a whole play — setup can run at
/// sixteen times and drop to one before the thing you came to watch — and since the moves are presses,
/// "16x" and "1x" are moves like any other. Put them in the list where they belong.
struct PlaybookEntry {
    let name: String
    /// What you will see, under the name.
    let seeing: String
    /// Which shelf of the list it sits on.
    let group: String
    /// A press and what to wait for after it.
    let moves: [(String, PlaybookWait)]
    let camera: PlaybookCamera
    /// Seconds after the last press before the station is torn down and the entry plays again.
    let tail: Double
    /// Whether this entry needs the yard: the pad, the test deck, storage and decon are one block, and
    /// `hasPad` is the gate on all four. An entry about one office in a hallway wants none of it.
    let yard: Bool
    /// Whether it needs the bay hanging outside the airlock.
    let bay: Bool
    /// The rooms the crew idle in that this entry needs standing. A play about a bunk wants the dorm and
    /// the hallway it stands on, and nothing else: the lounge, the bath and the gym are three more rooms
    /// to read past.
    let rooms: Set<String>
    /// The rest of the desk — two more offices of mine, the teammate, the peer. Off leaves one office and
    /// one body, which is all most plays are about.
    let crowd: Bool
    /// How long to let the station settle before the camera looks. A body works where the work is, not
    /// where it lives — QA happens on the test deck, a wash in the bath — so a play that aims the moment
    /// it starts spends its first seconds watching a walk. Aim once the body is where the play is about.
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
    /// The office every entry acts on, and the smallest floor that can show one body at a desk.
    private static let office = "task:web#455"
    /// The body every play is about, matched loosely on its office's name.
    private static let who = "booking"
    private static func at(_ moves: [(String, PlaybookWait)]) -> [(String, PlaybookWait)] { [("Target: web#455", 0.4)] + moves }

    /// The crate on the deck in every seeded station, and the columns QA moves it between.
    private static let tested = 430
    private static var passQA: String { "Board: Move web#\(tested) to \(ConfigStore.shared.current.statuses.cleared)" }
    /// The crate the seed has already approved, standing on its stack by the rocket, and QA sending it back.
    private static let approved = 431
    private static var rejectQA: String { "Board: Move web#\(approved) to \(ConfigStore.shared.current.statuses.deck)" }

    static let entries: [PlaybookEntry] = [
        // In an office: one session, one body, no yard.
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

        // A pull request, from packed to merged or closed.
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

        // The release, through the yard: web's crates already stand in storage and on the deck.
        PlaybookEntry("release", "Staging PR opened", "pallet loads crates from storage", [("1x", 0.5), ("Release: Staging opens", .palletLoaded)],
                      camera: .area("storage", 3), tail: 6, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Staging PR merged", "pallet pushed to the deck, waits there loaded while staging deploys",
                      [("16x", 0.5), ("Release: Staging opens", .palletLoaded), ("1x", 0.5), ("Release: Staging merges", 0.25), ("Deploy: Staging starts", .palletStaged)],
                      camera: .area("deck", 2.6), tail: 10, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Staging deploy goes live", "the waiting pallet is unloaded onto the deck",
                      [("16x", 0.5), ("Release: Staging opens", .palletLoaded), ("Release: Staging merges", 0.25), ("Deploy: Staging starts", .palletStaged),
                       ("1x", 1), ("Deploy: Staging goes live", .palletGone)],
                      camera: .area("deck", 2.6), tail: 6, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Staging deploy fails", "the waiting pallet's light turns red; it stays loaded",
                      [("16x", 0.5), ("Release: Staging opens", .palletLoaded), ("Release: Staging merges", 0.25), ("Deploy: Staging starts", .palletStaged),
                       ("1x", 1), ("Deploy: Staging fails", 6)],
                      camera: .area("deck", 2.6), tail: 4, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Staging PR closed unmerged", "pallet unloads back into storage", [("16x", 0.5), ("Release: Staging opens", .palletLoaded), ("1x", 0.5), ("Release: Staging closes", .palletGone)],
                      camera: .area("storage", 3), tail: 6, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "QA approves a crate", "crate set on the X-ray belt, scanned green, out small on the pad, carried to the rocket", [("4x", 0.5), (passQA, .pickedUp(tested)), ("1x", .onStack(tested))],
                      camera: .area("yard", 2.7), tail: 6, yard: true, rooms: [], crowd: false),
        PlaybookEntry("release", "QA rejects a crate", "crate carried back through the arch, scanned red, set in the untested row", [("4x", 0.5), (rejectQA, .pickedUp(approved)), ("1x", .onDeck(approved))],
                      camera: .area("yard", 2.7), tail: 6, yard: true, rooms: [], crowd: false),
        PlaybookEntry("release", "Staging deploy builds a new tip", "api's first release to staging: the pusher welds the tip together panel by panel on its cradle",
                      [("Target: api#5158", 0.4), ("16x", 0.5), ("Release: Staging opens", .palletLoaded), ("Release: Staging merges", 0.25),
                       ("Deploy: Staging starts", .palletStaged), ("GitHub: Poll", 0.25), ("1x", .tipAlmost("api")), ("Deploy: Staging goes live", .palletGone)],
                      camera: .area("pad", 3), tail: 6, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Staging deploy re-welds the tip", "web's tip is already built: the pusher goes over its seams while staging deploys",
                      [("16x", 0.5), ("Release: Staging opens", .palletLoaded), ("Release: Staging merges", 0.25),
                       ("Deploy: Staging starts", .palletStaged), ("1x", 10), ("Deploy: Staging goes live", .palletGone)],
                      camera: .area("pad", 3), tail: 6, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Production PR opened", "the lifter rises out of the pad under the tip; the approved crate is loaded",
                      [("1x", 0.5), ("Release: Production opens", .loaded(approved))],
                      camera: .area("pad", 3), tail: 10, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Production deploy succeeds", "rocket flies to the colony and lands", [("16x", 0.5), ("Release: Production opens", 2), ("Release: Production merges", 2),
                                                                           ("1x", 0.5), ("Deploy: Production starts", .flightFarOut), ("Deploy: Goes live", 30)],
                      camera: .area("pad", 2.4), tail: 4, yard: true, rooms: [], crowd: true),
        PlaybookEntry("release", "Production deploy fails", "flight loses signal", [("16x", 0.5), ("Release: Production opens", 2), ("Release: Production merges", 2),
                                                                         ("1x", 0.5), ("Deploy: Production starts", .flightFarOut), ("Deploy: Fails", 10)],
                      camera: .area("pad", 2.4), tail: 4, yard: true, rooms: [], crowd: true),

        // Other people's work: a teammate's office, a bot's, a neighbour station's.
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

        // Life on the station, each in the one room it is about.
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

    /// A session at its desk: the smallest play there is, and the shape most of them take.
    private static func desk(_ name: String, _ seeing: String, _ session: String) -> PlaybookEntry {
        PlaybookEntry("office", name, seeing, at([("Set: session = \(session)", 1)]),
                      camera: .follow(who, 4), tail: 14, rooms: [], crowd: false)
    }

    static func find(_ words: String) -> Int? {
        let want = words.lowercased()
        return entries.firstIndex { $0.name.lowercased().contains(want) }
    }

    /// The shelves, in the order the list shows them: what a session does, what comes of it, what a body
    /// does when it is not working, and everyone else.
    static let groups = ["office", "pull request", "release", "others", "life"]
    /// What a shelf is called in the list.
    static func shelfTitle(_ group: String) -> String {
        ["office": "Session", "pull request": "Pull request", "release": "Release",
         "others": "Other people", "life": "Idle"][group] ?? group
    }
    static func onShelf(_ group: String) -> [(offset: Int, entry: PlaybookEntry)] {
        entries.enumerated().filter { $0.element.group == group }.map { ($0.offset, $0.element) }
    }
}

/// The list beside the station. Selecting an entry starts it from the top.
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
                            // A button rather than a row of a selected list: a list hands its selection
                            // back, and a play that restarts to the same entry leaves the selection where
                            // it was, so the next click is no change at all and nothing happens.
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
            // Tuning: the part being watched plays at the speed picked here; replay starts it over.
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
    /// The speed the watched part plays at, as the station's own speed press names it.
    @Published var speed = "1x" { didSet { onSpeed?(speed) } }
    @Published var paused = false
    var onSpeed: ((String) -> Void)?
    var onPause: ((Bool) -> Void)?
    func togglePause() { paused.toggle(); onPause?(paused) }
    /// Rebuilds the station from nothing for the entry it is handed: the only reset that cannot leave
    /// anything of the last run behind.
    var restart: ((Int) -> Void)?

    func play(_ k: Int) { restart?(k) }
    func subtitle(_ e: PlaybookEntry) -> String { e.seeing }
}

/// The window: a live station on the right, the list on the left. The station is a real one with the
/// scanner, GitHub and the network switched off — the simulator's station, without the board.
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
    /// Seconds since this play started, for the settle.
    private var clock = 0.0
    private var loop: Timer?
    private let listWidth = 240.0
    private var frame: NSRect

    init(frame: NSRect) {
        self.frame = frame
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
        station.drone.isEnabled = false
        station.settlesView = false
        view.addSubview(station.view)
    }

    /// From nothing, every time: the old station is thrown away rather than tidied, so no crate, cone or
    /// body of the last run can be mistaken for this one's.
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
        let stationRect = NSRect(x: listWidth, y: 0, width: frame.width - listWidth, height: frame.height)
        station = StationController(frame: stationRect, demo: false, simulated: true)
        sim = SimulatorModel(station: station)
        mount(stationRect)
        model.playing = k
        model.status = entry.name
        // The floor is settled before anything is seeded onto it: a room taken away later leaves whoever
        // was sent to it sitting in mid-air, and a rebuild mid-play throws the camera out to a
        // forty-tile fit. Built once, right, and never rebuilt.
        let work = station.fleet.station("work", fixed: entry.rooms.sorted().map { Place.room($0) })
        work.hasPad = entry.yard
        work.hasHangar = entry.bay
        // What floor the play actually got, since the smallest station that shows a thing is the point.
        FileHandle.standardError.write("playbook \(entry.name): rooms \(work.rooms.keys.sorted().joined(separator: " ")), yard \(entry.yard), bay \(entry.bay), crowd \(entry.crowd)\n".data(using: .utf8)!)
        sim.seed(crowd: entry.crowd)
        // One move at a time: pressed, then its wait, looked at every quarter second. A fact that never
        // comes is said in the log after two minutes and the play goes on, so a broken entry shows itself.
        // Anything in the yard needs someone free to carry: laid with the floor, before the first move.
        // An empty name presses nothing and only waits.
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
        // An office framed before it is opened is framed on nothing, and every press that changes the
        // floor puts the camera back where the station wants it. So the framing is not set once: it is
        // held, re-asked for every beat until the entry starts over.
        clock = 0
        camera = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.clock += 0.5; self?.hold(entry) }
        }

    }

    /// The floor is checked every beat, because seeding is enqueued onto the station's own queue and there
    /// is no delay worth guessing. The camera is not: `look` sets `userZoomChanged`, which is the camera's
    /// own word for "snap there", so asking for it every beat snaps the view over and over and reads as
    /// zooming at random. It is aimed when the floor changes under it and at the two moments the entry
    /// knows about, and otherwise left alone.
    private func hold(_ entry: PlaybookEntry) {
        // Once, as soon as there is something to look at, and never again: the view is yours after that.
        // A play that keeps asking for its framing takes the camera back out of your hands mid-gesture.
        // Bodies are spawned by the scan the seed pushes, so a play that follows one has to wait for it;
        // aiming at an empty station leaves the camera wherever it happened to be.
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
        let shot = station.view.snapshot()
        guard let tiff = shot.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
