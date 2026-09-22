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
}

/// One thing the station can do: what floor it needs standing, what to press, where to look, and how
/// long before it starts over.
///
/// There is no speed on an entry. Speed belongs to a moment, not to a whole play — setup can run at
/// sixteen times and drop to one before the thing you came to watch — and since the moves are presses,
/// "16x" and "1x" are moves like any other. Put them in the list where they belong.
struct PlaybookEntry {
    let name: String
    /// Which shelf of the list it sits on.
    let group: String
    /// A press and the seconds to wait after it, on the station's clock.
    let moves: [(String, Double)]
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

    init(_ group: String, _ name: String, _ moves: [(String, Double)], camera: PlaybookCamera,
         tail: Double = 8, yard: Bool = false, bay: Bool = false,
         rooms: Set<String> = PlaybookEntry.idleRooms, crowd: Bool = true, settle: Double = 0) {
        self.group = group; self.name = name; self.moves = moves; self.camera = camera
        self.tail = tail; self.yard = yard; self.bay = bay
        self.rooms = rooms; self.crowd = crowd; self.settle = settle
    }
}

enum Playbook {
    /// The office every entry acts on, and the smallest floor that can show one body at a desk.
    private static let office = "task:web#455"
    /// The body every play is about, matched loosely on its office's name.
    private static let who = "booking"
    private static func at(_ moves: [(String, Double)]) -> [(String, Double)] { [("Target: web#455", 0.4)] + moves }

    static let entries: [PlaybookEntry] = [
        // What a session is doing, one to an entry: the knob says it, the body wears it, the routine plays.
        // One office, one body, no yard and none of the rooms it idles in — none of that is the subject.
        desk("coding", "coding"), desk("reading code", "reading code"), desk("testing", "testing"),
        desk("writing", "writing"), desk("thinking", "thinking"), desk("waiting for you", "waiting for you"),
        PlaybookEntry("work", "web research", at([("Set: session = web research", 1)]),
                      camera: .whole(2.6), tail: 16, rooms: [], crowd: false),
        PlaybookEntry("work", "QA testing", at([("Set: session = QA testing", 1)]),
                      camera: .follow(who, 4), tail: 22, yard: true, rooms: [], crowd: false, settle: 8),

        // A cone is a message being worked: a prompt lands and the body goes to it.
        PlaybookEntry("work", "a cone worked", at([("Set: session = coding", 1), ("Prompt", 1)]),
                      camera: .follow(who, 4), tail: 16, rooms: [], crowd: false),

        // The life of one piece of work, a press at a time. A merge sends the crate off to storage, so
        // that one alone needs the yard standing.
        PlaybookEntry("work", "a commit", at([("Set: session = coding", 1), ("Commit", 1)]),
                      camera: .follow(who, 4), tail: 12, rooms: [], crowd: false),
        PlaybookEntry("work", "a pull request opens", at([("Open PR", 2)]),
                      camera: .follow(who, 4), tail: 14, rooms: [], crowd: false),
        PlaybookEntry("work", "checks fail", at([("Open PR", 2), ("Checks failing", 2)]),
                      camera: .follow(who, 4), tail: 14, rooms: [], crowd: false),
        PlaybookEntry("work", "a pull request is approved", at([("Open PR", 2), ("Approve PR", 2)]),
                      camera: .follow(who, 4), tail: 14, rooms: [], crowd: false),
        PlaybookEntry("work", "a pull request merges", at([("Open PR", 2), ("Merge PR", 3)]),
                      camera: .whole(1.8), tail: 26, yard: true, rooms: [], crowd: false),
        PlaybookEntry("work", "a pull request closes unmerged", at([("Open PR", 2), ("Close PR", 2)]),
                      camera: .follow(who, 4), tail: 16, rooms: [], crowd: false),
        PlaybookEntry("work", "the session ends", at([("Set: session = coding", 1), ("Session ends", 2)]),
                      camera: .follow(who, 4), tail: 16, rooms: [], crowd: false),

        // Other people's work: a teammate's office, a bot's, a peer's. These are the crowd by definition.
        PlaybookEntry("other", "a teammate opens a pull request", [("Teammate: Open PR", 2)],
                      camera: .whole(2.0), tail: 18, rooms: []),
        PlaybookEntry("other", "a teammate merges", [("Teammate: Open PR", 2), ("Teammate: Merge PR", 3)],
                      camera: .whole(1.8), tail: 26, yard: true, rooms: []),
        PlaybookEntry("other", "a bot opens a pull request", [("Bot: Open PR", 2)],
                      camera: .whole(2.0), tail: 18, yard: true, rooms: []),
        PlaybookEntry("other", "a peer arrives", [("Peer: Leave", 2), ("Peer: Arrive", 2)],
                      camera: .whole(2.0), tail: 16, rooms: []),
        PlaybookEntry("other", "a peer leaves", [("Peer: Leave", 2)],
                      camera: .whole(2.0), tail: 16, rooms: []),

        // A body at work does not go to bed because it is dark, and that is right: only a session gone
        // quiet is asleep, and only an asleep body is sent to a bunk.
        PlaybookEntry("idle", "going to bed", at([("Set: session = sleeping", 1), ("Night", 3)]),
                      camera: .follow(who, 4), tail: 30, rooms: ["kind:quarters"], crowd: false, settle: 8),
        // The dorm under load: every session quiet at once, so the bunks are claimed together and the
        // walks to them cross. One body finds its bunk every time; the question this asks is how many of
        // five do.
        PlaybookEntry("idle", "everyone turns in", [("Everyone asleep", 3), ("Night", 3)],
                      camera: .follow(who, 3.2), tail: 34, rooms: ["kind:quarters"], settle: 12),
        // The floor moving under a sleeper. `bedCache` is dropped by any change to the plan, so the bunks
        // are worked out again — and a body already bedded down keeps saying so while the bunk it was
        // given may now be somewhere else.
        PlaybookEntry("idle", "a floor change while they sleep",
                      [("Everyone asleep", 3), ("Night", 8), ("New branch in repo", 4), ("New branch in repo", 4)],
                      camera: .follow(who, 3.2), tail: 30, rooms: ["kind:quarters"], settle: 14),
        PlaybookEntry("idle", "getting up", at([("Set: session = sleeping", 1), ("Night", 14),
                                        ("Day", 1), ("Set: session = coding", 2)]),
                      camera: .follow(who, 4), tail: 22, rooms: ["kind:quarters"], crowd: false),

        // What a body does when it is not working: each play keeps the one room it is about.
        PlaybookEntry("idle", "a bath", [("Bath", 2)], camera: .follow(who, 4), tail: 28,
                      rooms: ["kind:bath"], crowd: false, settle: 7),
        PlaybookEntry("idle", "a workout", [("Workout", 2)], camera: .follow(who, 4), tail: 28,
                      rooms: ["kind:gym"], crowd: false, settle: 7),
        PlaybookEntry("idle", "everyone to the lounge", [("Everyone to lounge", 2)],
                      camera: .follow(who, 4), tail: 20, rooms: ["kind:lounge"]),
        PlaybookEntry("idle", "a chore", [("Chore", 2)], camera: .whole(2.2), tail: 22,
                      rooms: ["kind:lounge"], crowd: false),
        PlaybookEntry("idle", "a meeting in the hall", [("Meet in the hall", 2)], camera: .whole(2.0), tail: 20, rooms: []),

        // The long errand: a crate crossing the whole station into a rocket. Setup runs fast, then it
        // drops to one so the loading and the launch are watched at the speed they happen.
        PlaybookEntry("release", "crate into rocket",
                      at([("16x", 0.5), ("Open PR", 2), ("Merge PR", 4), ("Stage: stored", 4),
                          ("1x", 0.5), ("Release: Production opens", 3),
                          ("Release: Mark tested", 3), ("Release: Production merges", 3)]),
                      camera: .whole(1.8), tail: 40, yard: true, rooms: [], crowd: false),
    ]

    /// A session at its desk: the smallest play there is, and the shape most of them take.
    private static func desk(_ name: String, _ session: String) -> PlaybookEntry {
        PlaybookEntry("work", name, at([("Set: session = \(session)", 1)]),
                      camera: .follow(who, 4), tail: 14, rooms: [], crowd: false)
    }

    static func find(_ words: String) -> Int? {
        let want = words.lowercased()
        return entries.firstIndex { $0.name.lowercased().contains(want) }
    }

    /// The shelves, in the order the list shows them: what a session does, what comes of it, what a body
    /// does when it is not working, and everyone else.
    static let groups = ["work", "release", "idle", "other"]
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
                        Text(group)
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
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
            Text(model.status).font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}

@MainActor
final class PlaybookModel: ObservableObject {
    @Published var playing = 0
    @Published var status = ""
    /// Rebuilds the station from nothing for the entry it is handed: the only reset that cannot leave
    /// anything of the last run behind.
    var restart: ((Int) -> Void)?

    func play(_ k: Int) { restart?(k) }
    func subtitle(_ e: PlaybookEntry) -> String {
        var parts = ["\(e.moves.count) presses"]
        if e.yard { parts.append("yard") }
        if e.bay { parts.append("bay") }
        return parts.joined(separator: " · ")
    }
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
        var at = 1.0
        for (name, after) in entry.moves {
            script.append(Timer.scheduledTimer(withTimeInterval: at, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.sim.press(name) }
            })
            at += after
        }
        // An office framed before it is opened is framed on nothing, and every press that changes the
        // floor puts the camera back where the station wants it. So the framing is not set once: it is
        // held, re-asked for every beat until the entry starts over.
        clock = 0
        camera = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.clock += 0.5; self?.hold(entry) }
        }

        loop = Timer.scheduledTimer(withTimeInterval: at + entry.tail, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.start(k) }
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
        }
    }

    func snapshot(to path: String) {
        let shot = station.view.snapshot()
        guard let tiff = shot.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
