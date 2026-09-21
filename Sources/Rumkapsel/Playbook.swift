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

/// One thing the station can do: what it needs standing, what to press, where to look, how fast, and how
/// long before it starts over.
struct PlaybookEntry {
    let name: String
    /// A press and the seconds to wait after it, on the station's clock.
    let moves: [(String, Double)]
    let camera: PlaybookCamera
    /// A time press: nil leaves it at whatever the station runs at, "4x" watches a long errand in a
    /// quarter of the time it takes.
    let speed: String?
    /// Seconds after the last press before the station is torn down and the entry plays again.
    let tail: Double
    /// The floor this entry needs. The plaza and its two arms are the plan's own and always stand; the
    /// yard and the bay are the station's to drop when an entry has no use for them.
    let pad: Bool
    let hangar: Bool

    init(_ name: String, _ moves: [(String, Double)], camera: PlaybookCamera, speed: String? = nil,
         tail: Double = 6, pad: Bool = true, hangar: Bool = true) {
        self.name = name; self.moves = moves; self.camera = camera
        self.speed = speed; self.tail = tail; self.pad = pad; self.hangar = hangar
    }
}

enum Playbook {
    /// Two ends of the scale to begin with: one body at one cone, and a crate crossing the whole station
    /// into a rocket. Both are presses on a real station; neither knows what it looks like.
    static let entries: [PlaybookEntry] = [
        PlaybookEntry("a cone worked", [("Target: web#455", 0.5), ("Set: session = coding", 1), ("Prompt", 1)],
                   camera: .area("task:web#455", 5), tail: 12, pad: false, hangar: false),
        PlaybookEntry("crate into rocket",
                   [("Target: web#455", 0.5), ("Open PR", 2), ("Merge PR", 6),
                    ("Stage: stored", 6), ("Release: Production opens", 4),
                    ("Release: Mark tested", 3), ("Release: Production merges", 4)],
                   camera: .area("pad", 2.2), speed: "4x", tail: 40),
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
        if let s = e.speed { parts.append(s) }
        if !e.pad { parts.append("no yard") }
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
        if let s = entry.speed { sim.press(s) }
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
        if let work = station.fleet.stations["work"], work.hasPad != entry.pad || work.hasHangar != entry.hangar {
            work.hasPad = entry.pad
            work.hasHangar = entry.hangar
            station.rebuildStatic()
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
