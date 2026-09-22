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
    case whole(Double)
    case area(String, Double)
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

    init(_ name: String, _ moves: [(String, Double)], camera: PlaybookCamera,
         tail: Double = 8, yard: Bool = false, bay: Bool = false) {
        self.name = name; self.moves = moves; self.camera = camera
        self.tail = tail; self.yard = yard; self.bay = bay
    }
}

enum Playbook {
    /// The office every entry acts on, and the smallest floor that can show one body at a desk.
    private static let office = "task:web#455"
    private static func at(_ moves: [(String, Double)]) -> [(String, Double)] { [("Target: web#455", 0.4)] + moves }

    static let entries: [PlaybookEntry] = [
        // What a session is doing, one to an entry: the knob says it, the body wears it, the routine plays.
        PlaybookEntry("coding", at([("Set: session = coding", 1)]), camera: .area(office, 5), tail: 14),
        PlaybookEntry("reading code", at([("Set: session = reading code", 1)]), camera: .area(office, 5), tail: 14),
        PlaybookEntry("testing", at([("Set: session = testing", 1)]), camera: .area(office, 5), tail: 14),
        PlaybookEntry("writing", at([("Set: session = writing", 1)]), camera: .area(office, 5), tail: 14),
        PlaybookEntry("thinking", at([("Set: session = thinking", 1)]), camera: .area(office, 5), tail: 14),
        PlaybookEntry("waiting for you", at([("Set: session = waiting for you", 1)]), camera: .area(office, 5), tail: 14),
        PlaybookEntry("web research", at([("Set: session = web research", 1)]), camera: .whole(2.2), tail: 16),
        PlaybookEntry("QA testing", at([("Set: session = QA testing", 1)]), camera: .area("deck", 3), tail: 18, yard: true),

        // A cone is a message being worked: a prompt lands and the body goes to it.
        PlaybookEntry("a cone worked", at([("Set: session = coding", 1), ("Prompt", 1)]), camera: .area(office, 5), tail: 16),

        // The life of one piece of work, a press at a time.
        PlaybookEntry("a commit", at([("Set: session = coding", 1), ("Commit", 1)]), camera: .area(office, 5), tail: 12),
        PlaybookEntry("a pull request opens", at([("Open PR", 2)]), camera: .area(office, 4), tail: 14),
        PlaybookEntry("checks fail", at([("Open PR", 2), ("Checks failing", 2)]), camera: .area(office, 4), tail: 14),
        PlaybookEntry("a pull request is approved", at([("Open PR", 2), ("Approve PR", 2)]), camera: .area(office, 4), tail: 14),
        PlaybookEntry("a pull request merges", at([("Open PR", 2), ("Merge PR", 3)]), camera: .whole(1.6), tail: 24, yard: true),
        PlaybookEntry("a pull request closes unmerged", at([("Open PR", 2), ("Close PR", 2)]), camera: .area(office, 4), tail: 16),
        PlaybookEntry("the session ends", at([("Set: session = coding", 1), ("Session ends", 2)]), camera: .area(office, 4), tail: 16),

        // Other people's work: a teammate's office, a bot's, a peer's.
        PlaybookEntry("a teammate opens a pull request", [("Teammate: Open PR", 2)], camera: .whole(1.8), tail: 18),
        PlaybookEntry("a teammate merges", [("Teammate: Open PR", 2), ("Teammate: Merge PR", 3)], camera: .whole(1.6), tail: 24, yard: true),
        PlaybookEntry("a bot opens a pull request", [("Bot: Open PR", 2)], camera: .area("decon", 3), tail: 18, yard: true),
        PlaybookEntry("a peer arrives", [("Peer: Leave", 2), ("Peer: Arrive", 2)], camera: .whole(1.8), tail: 16),
        PlaybookEntry("a peer leaves", [("Peer: Leave", 2)], camera: .whole(1.8), tail: 16),

        // The day, and what everyone does when nobody is working.
        // A body at work does not go to bed because it is dark, and that is right: only a session that
        // has gone quiet is asleep, and only an asleep body is sent to a bunk.
        PlaybookEntry("going to bed", at([("Set: session = sleeping", 1), ("Night", 3)]),
                      camera: .area("kind:quarters", 4), tail: 26),
        PlaybookEntry("getting up", at([("Set: session = sleeping", 1), ("Night", 14),
                                        ("Day", 1), ("Set: session = coding", 2)]),
                      camera: .area("kind:quarters", 4), tail: 22),
        PlaybookEntry("everyone to the lounge", [("Everyone to lounge", 2)], camera: .area("kind:lounge", 4), tail: 18),
        PlaybookEntry("a bath", [("Bath", 2)], camera: .area("kind:bath", 5), tail: 22),
        PlaybookEntry("a workout", [("Workout", 2)], camera: .area("kind:gym", 4), tail: 22),
        PlaybookEntry("a chore", [("Chore", 2)], camera: .whole(1.8), tail: 20),
        PlaybookEntry("a meeting in the hall", [("Meet in the hall", 2)], camera: .whole(1.8), tail: 20),

        // The long errand: a crate crossing the whole station into a rocket. Setup runs fast, then it
        // drops to one so the loading and the launch are watched at the speed they happen.
        PlaybookEntry("crate into rocket",
                      at([("16x", 0.5), ("Open PR", 2), ("Merge PR", 4), ("Stage: stored", 4),
                          ("1x", 0.5), ("Release: Production opens", 3),
                          ("Release: Mark tested", 3), ("Release: Production merges", 3)]),
                      camera: .area("pad", 2.2), tail: 40, yard: true),
    ]

    static func find(_ words: String) -> Int? {
        let want = words.lowercased()
        return entries.firstIndex { $0.name.lowercased().contains(want) }
    }
}

/// The list beside the station. Selecting an entry starts it from the top.
struct PlaybookPanel: View {
    @ObservedObject var model: PlaybookModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("what the station does")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
            List(Array(Playbook.entries.enumerated()), id: \.offset, selection: Binding(
                get: { model.playing }, set: { if let k = $0 { model.play(k) } })) { k, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.system(size: 12))
                        Text(model.subtitle(entry)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .tag(k)
                }
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
        start(0)
    }

    private func mount(_ rect: NSRect) {
        station.view.frame = rect
        station.view.autoresizingMask = [.width, .height]
        station.viewSize = rect.size
        station.drone.isEnabled = false
        view.addSubview(station.view)
    }

    /// From nothing, every time: the old station is thrown away rather than tidied, so no crate, cone or
    /// body of the last run can be mistaken for this one's.
    func start(_ k: Int) {
        guard k >= 0, k < Playbook.entries.count else { return }
        let entry = Playbook.entries[k]
        script.forEach { $0.invalidate() }; script = []
        camera?.invalidate(); camera = nil
        loop?.invalidate(); loop = nil
        station.view.removeFromSuperview()
        let stationRect = NSRect(x: listWidth, y: 0, width: frame.width - listWidth, height: frame.height)
        station = StationController(frame: stationRect, demo: false, simulated: true)
        sim = SimulatorModel(station: station)
        mount(stationRect)
        model.playing = k
        model.status = entry.name
        sim.seed()
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
        camera = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hold(entry) }
        }
        loop = Timer.scheduledTimer(withTimeInterval: at + entry.tail, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.start(k) }
        }
    }

    /// Held every beat rather than set once. Seeding is enqueued onto the station's own queue, so the
    /// floor does not exist when an entry starts and there is no delay worth guessing; and every press
    /// that changes the floor puts the camera back where the station wants it.
    private func hold(_ entry: PlaybookEntry) {
        if let work = station.fleet.stations["work"], work.hasPad != entry.yard || work.hasHangar != entry.bay {
            work.hasPad = entry.yard
            work.hasHangar = entry.bay
            station.rebuildStatic()
            // What floor the entry actually got, since "the smallest station that shows it" is the point.
            FileHandle.standardError.write("playbook \(entry.name): yard \(entry.yard) (\(work.padCells.count + work.deckCells.count + work.storageCells.count) cells), bay \(entry.bay) (\(work.hangarCells.count) cells)\n".data(using: .utf8)!)
        }
        aim(entry.camera)
    }

    private func aim(_ camera: PlaybookCamera) {
        switch camera {
        case .whole(let zoom): station.setView(yawDegrees: 0, pitchDegrees: -30, zoom: zoom)
        case .area(let name, let zoom): station.look(at: name, in: "work", zoom: zoom)
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
