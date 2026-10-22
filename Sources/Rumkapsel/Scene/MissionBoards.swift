import AppKit
import SceneKit

struct MissionBoards: Equatable {
    enum Lamp: Equatable { case dark, green, amber, red }
    struct Row: Equatable { let repo: String; let color: RGB; let lamps: [Lamp] }

    static let lamps = ["Deploy", "Checks", "Waiting", "Release", "Errors", "Alarm"]
    static let rows = 8

    var rows: [Row] = []
    var clock = ""
}

struct MissionScreens {
    struct Feed { let name: String; let camera: SCNNode; let material: SCNMaterial }
    let annunciator: SCNMaterial
    let clock: SCNMaterial
    var feeds: [Feed]
    let wall: SIMD3<Double>
    var shown: MissionBoards?
}

extension StationController {
    func missionBoards(_ station: Station) -> MissionBoards {
        var b = MissionBoards()
        let repos = Set(world.repoRoots.values.filter { $0.station == station.name }.map(\.repo))
            .sorted { (fleet.repoColors[$0] ?? .max, $0) < (fleet.repoColors[$1] ?? .max, $1) }
        b.rows = repos.prefix(MissionBoards.rows).map { repo in
            let deploy = deployLamp(station, repo)
            let offices = station.rooms.values.filter { $0.repo == repo && !$0.key.hasPrefix("kind:") }
            let checks: MissionBoards.Lamp = offices.contains(where: world.checksFailing) ? .red : offices.isEmpty ? .dark : .green
            let rows = station.facts.crates.values.filter { $0.id.repo == repo && ($0.zone == .testing || $0.zone == .cleared) }
            let waiting: MissionBoards.Lamp = rows.isEmpty ? .dark : rows.contains { $0.zone == .testing } ? .amber : .green
            let rocket = station.facts.rockets.values.first { $0.repo == repo && !$0.launched && $0.kind != .merge }
            let release: MissionBoards.Lamp = rocket.map { $0.go ? .green : .amber } ?? .dark
            let alarm: MissionBoards.Lamp = [deploy, checks].contains(.red) ? .red : .dark
            return MissionBoards.Row(repo: repo, color: fleet.color(forRepo: repo), lamps: [deploy, checks, waiting, release, .dark, alarm])
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        b.clock = f.string(from: now)
        return b
    }

    private func deployLamp(_ station: Station, _ repo: String) -> MissionBoards.Lamp {
        let flight = flights.last { $0.mission.repo == repo && $0.mission.station == station.name }?.mission
        if flight?.ended?.outcome.signalLost == true { return .red }
        if loadingFlights.contains(where: { $0.repo == repo && $0.ended == nil }) || (flight != nil && flight?.ended == nil) { return .amber }
        switch station.facts.staging[repo]?.deploy {
        case .failed?: return .red
        case .running?: return .amber
        case .live?: return .green
        default: return flight?.ended != nil ? .green : .dark
        }
    }

    func tendMissionBoards(_ station: Station) {
        guard var screens = missionScreens[station.name] else { return }
        let now = missionBoards(station)
        guard now != screens.shown else { return }
        if screens.shown?.rows != now.rows { show(Screens.annunciator(now.rows), on: screens.annunciator) }
        if screens.shown?.clock != now.clock { show(Screens.nixieClock(now.clock), on: screens.clock) }
        screens.shown = now
        missionScreens[station.name] = screens
    }

    func feedCameras(_ station: Station) -> [(name: String, camera: SCNNode)] {
        let o = station.offset
        func camera(_ from: SIMD3<Double>, looking at: SIMD3<Double>) -> SCNNode {
            let n = SCNNode()
            n.camera = SCNCamera()
            n.camera!.fieldOfView = 50
            n.camera!.zNear = 0.1
            n.position = v3(from.x + o.x, from.y, from.z + o.y)
            n.look(at: v3(at.x + o.x, at.y, at.z + o.y))
            return n
        }
        var out: [(String, SCNNode)] = []
        if station.hasPad {
            let c = station.hall.padCenter
            out.append(("The pad", camera(SIMD3(c.x + 2.6, 2.4, c.y + 3.2), looking: SIMD3(c.x, 0.7, c.y))))
        }
        if station.hasHangar {
            let c = station.hangarCenter
            out.append(("The bay", camera(SIMD3(c.x - 2.4, 1.25, c.y - 2.9), looking: SIMD3(c.x + 0.4, 0.25, c.y + 0.6))))
        }
        return out
    }

    func rollFeeds() {
        let lit = missionScreens.values.filter { s in
            let p = view.projectPoint(v3(s.wall.x, s.wall.y, s.wall.z))
            return p.z > 0 && p.z < 1 && p.x >= 0 && p.y >= 0 && Double(p.x) <= viewSize.width && Double(p.y) <= viewSize.height
        }.flatMap(\.feeds)
        guard !lit.isEmpty else { return }
        let at = clock
        DispatchQueue.main.async { [self] in
            let r = feedRenderer
            for feed in lit {
                r.pointOfView = feed.camera
                let frame = r.snapshot(atTime: at, with: CGSize(width: 320, height: 200), antialiasingMode: .none)
                show(Screens.crt(frame, caption: feed.name), on: feed.material)
            }
        }
    }

    private func show(_ image: NSImage, on m: SCNMaterial) {
        m.diffuse.contents = image
        m.emission.contents = image
    }
}
