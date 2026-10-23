import AppKit
import SceneKit

enum RepoStatus: Int, CaseIterable, Comparable {
    case calm, flying, ready, testing, holding, failing
    static func < (a: RepoStatus, b: RepoStatus) -> Bool { a.rawValue < b.rawValue }

    var words: String {
        switch self {
        case .calm: return "calm"
        case .flying: return "flying"
        case .ready: return "ready"
        case .testing: return "testing"
        case .holding: return "holding"
        case .failing: return "failing"
        }
    }

    var color: NSColor {
        switch self {
        case .calm: return NSColor(rgb: (0.45, 0.75, 0.55))
        case .flying: return NSColor(rgb: (0.4, 0.85, 1.0))
        case .ready: return NSColor(rgb: (0.85, 0.9, 0.4))
        case .testing: return NSColor(rgb: (1.0, 0.82, 0.3))
        case .holding: return NSColor(rgb: (1.0, 0.62, 0.2))
        case .failing: return NSColor(rgb: (1.0, 0.28, 0.24))
        }
    }

    static let sweep = 1.65
    var angle: Double { -RepoStatus.sweep + Double(rawValue) / Double(RepoStatus.allCases.count - 1) * RepoStatus.sweep * 2 }

    static func of(deploy: MissionBoards.Lamp, checks: MissionBoards.Lamp, waiting: MissionBoards.Lamp, release: MissionBoards.Lamp, errors: MissionBoards.Lamp) -> RepoStatus {
        if [deploy, checks, errors].contains(.red) { return .failing }
        if release == .amber { return .holding }
        if waiting == .amber { return .testing }
        if waiting == .green || release == .green { return .ready }
        if deploy == .amber { return .flying }
        return .calm
    }
}

struct MissionBoards: Equatable {
    enum Lamp: Equatable { case dark, green, amber, red }
    struct Row: Equatable { let repo: String; let color: RGB; let status: RepoStatus; var quiver = false }

    static let rows = 8

    struct ErrorRow: Equatable { let repo: String; let color: RGB; let hourly: [Int]; let level: Sentry.Level; let lastHour: Int }

    var rows: [Row] = []
    var clock = ""
    var errors: [ErrorRow]?
    var errorsLink: (url: String, words: String)?
    static func == (a: MissionBoards, b: MissionBoards) -> Bool {
        a.rows == b.rows && a.clock == b.clock && a.errors == b.errors && a.errorsLink?.url == b.errorsLink?.url
    }
}

struct MissionScreens {
    struct Feed { let name: String; let camera: SCNNode; let material: SCNMaterial; var caption: String; let home: SCNMatrix4 }
    final class Needle { let node: SCNNode; var angle: Double; var target: Double; var quiver = false; init(_ n: SCNNode, at a: Double) { node = n; angle = a; target = a } }
    let annunciator: SCNMaterial
    let board: SCNNode
    var needles: [String: Needle] = [:]
    let clock: SCNMaterial
    let errors: SCNMaterial
    let errorsNode: SCNNode
    var feeds: [Feed]
    let wall: SIMD3<Double>
    var shown: MissionBoards?
    static let near = 0.4, nearEvery = 0.33, farEvery = 10.0
    static let queue = DispatchQueue(label: "rumkapsel.feeds", qos: .utility)
}

extension StationController {
    func missionBoards(_ station: Station) -> MissionBoards {
        var b = MissionBoards()
        let repos = Set(world.repoRoots.values.filter { $0.station == station.name }.map(\.repo))
            .sorted { (fleet.repoColors[$0] ?? .max, $0) < (fleet.repoColors[$1] ?? .max, $1) }
        b.rows = repos.prefix(MissionBoards.rows).map { repo in
            var deploy = deployLamp(station, repo), deployBlink = 0.0
            if let p = station.facts.staging[repo]?.progress(at: now), deploy == .amber { deployBlink = p > StagingFact.late ? 3 : 1 }
            if let beat = stagingBeat(station: station.name, repo: repo), beat.live, clock - beat.at < 3 { deploy = .green; deployBlink = 3 }
            let offices = station.rooms.values.filter { $0.repo == repo && !$0.key.hasPrefix("kind:") }
            let checks: MissionBoards.Lamp = offices.contains(where: world.checksFailing) ? .red : offices.isEmpty ? .dark : .green
            let rows = station.facts.crates.values.filter { $0.id.repo == repo && ($0.zone == .testing || $0.zone == .cleared) }
            let waiting: MissionBoards.Lamp = rows.isEmpty ? .dark : rows.contains { $0.zone == .testing } ? .amber : .green
            let rocket = station.facts.rockets.values.first { $0.repo == repo && !$0.launched && $0.kind != .merge }
            let release: MissionBoards.Lamp = rocket.map { $0.go ? .green : .amber } ?? .dark
            let errors: MissionBoards.Lamp
            switch world.errors(repo: repo).map({ Sentry.trend($0, at: now).level }) {
            case nil: errors = .dark
            case .calm?: errors = .green
            case .rising?: errors = .amber
            case .spiking?: errors = .red
            }
            return MissionBoards.Row(repo: repo, color: fleet.color(forRepo: repo),
                                     status: RepoStatus.of(deploy: deploy, checks: checks, waiting: waiting, release: release, errors: errors),
                                     quiver: deployBlink > 0)
        }
        if ConfigStore.shared.current.sentryOrg != nil || !world.errorsByProject.isEmpty {
            let followed = Set(world.errorsByProject.values.map(\.repo))
                .sorted { (fleet.repoColors[$0] ?? .max, $0) < (fleet.repoColors[$1] ?? .max, $1) }
            let trends = followed.compactMap { repo in world.errors(repo: repo).map { (repo, Sentry.trend($0, at: now)) } }
            b.errors = trends.prefix(4).map { repo, t in
                MissionBoards.ErrorRow(repo: repo, color: fleet.color(forRepo: repo), hourly: t.hourly, level: t.level, lastHour: t.lastHour)
            }
            if let (repo, t) = trends.filter({ $0.1.level > .calm }).max(by: { ($0.1.level, $0.1.lastHour) < ($1.1.level, $1.1.lastHour) }),
               let link = t.worst?.link {
                b.errorsLink = (link, "\(repo)'s errors are \(t.level.words) · click to open the worst in Sentry")
            } else if let org = ConfigStore.shared.current.sentryOrg {
                b.errorsLink = (Sentry.issuesPage(org: org), "Errors and alarms · click to open Sentry")
            }
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
        if screens.shown?.rows != now.rows {
            show(Screens.dials(now.rows), on: screens.annunciator)
            if screens.shown?.rows.map(\.repo) != now.rows.map(\.repo) {
                screens.needles.values.forEach { $0.node.removeFromParentNode() }
                screens.needles = [:]
                for (i, row) in now.rows.enumerated() {
                    let n = MissionRoom.needle(Screens.dial(i, of: now.rows.count).radius)
                    n.position = Screens.dial(i, of: now.rows.count).hub
                    screens.board.addChildNode(n)
                    screens.needles[row.repo] = .init(n, at: RepoStatus.calm.angle)
                }
            }
            for row in now.rows { screens.needles[row.repo]?.target = row.status.angle; screens.needles[row.repo]?.quiver = row.quiver }
        }
        if screens.shown?.clock != now.clock { show(Screens.nixieClock(now.clock), on: screens.clock) }
        if screens.shown == nil || screens.shown?.errors != now.errors {
            show(now.errors.map(Screens.errors) ?? Screens.noSignal("Errors and alarms"), on: screens.errors)
        }
        screens.errorsNode.name = now.errorsLink.map { "link:\($0.url)|\($0.words)" } ?? screens.errorsNode.name
        screens.shown = now
        missionScreens[station.name] = screens
    }

    func swingNeedles(dt: Double) {
        for s in missionScreens.values {
            for n in s.needles.values where abs(n.target - n.angle) > 0.0005 || n.quiver {
                n.angle += (n.target - n.angle) * min(1, dt * 2.5)
                let shake = n.quiver ? sin(clock * 31) * 0.035 + sin(clock * 17) * 0.02 : 0
                n.node.eulerAngles.z = CGFloat(-(n.angle + shake))
            }
        }
    }

    func feedCameras(_ station: Station) -> [(name: String, camera: SCNNode)] {
        let o = station.offset
        func camera(_ from: SIMD3<Double>, looking at: SIMD3<Double>) -> SCNNode {
            let n = SCNNode()
            n.camera = SCNCamera()
            n.camera!.fieldOfView = 50
            n.camera!.zNear = 0.1
            n.camera!.zFar = 9
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
        if let w = walker, w.phase < 1 { return }
        var near = false
        let seen = missionScreens.filter { _, s in
            let p = view.projectPoint(v3(s.wall.x, s.wall.y, s.wall.z))
            guard p.z > 0, p.z < 1, p.x >= 0, p.y >= 0, Double(p.x) <= viewSize.width, Double(p.y) <= viewSize.height else { return false }
            let l = view.projectPoint(v3(s.wall.x - 2.4, s.wall.y, s.wall.z)), r = view.projectPoint(v3(s.wall.x + 2.4, s.wall.y, s.wall.z))
            if walker != nil || abs(Double(r.x - l.x)) > MissionScreens.near * viewSize.width { near = true }
            return true
        }
        let every = near ? MissionScreens.nearEvery : MissionScreens.farEvery
        guard !seen.isEmpty, !feedsBusy, clock - feedsFarAt >= every || clock < feedsFarAt else { return }
        feedsFarAt = clock
        feedsBusy = true
        let lit = seen.flatMap { name, s in s.feeds.map { f -> MissionScreens.Feed in
            var f = f
            if f.name == "The pad", let up = flights.last(where: { $0.mission.station == name && $0.mission.ended.map { self.clock - $0.at < 20 } ?? true }) {
                let t = max(0, Int(clock - up.mission.tZero))
                return MissionScreens.Feed(name: f.name, camera: up.camera, material: f.material,
                                           caption: "\(up.mission.repo) · T+" + String(format: "%02d:%02d", t / 60, t % 60) + " · " + up.mission.phase(at: clock),
                                           home: f.home)
            }
            if f.name == "The pad", let hold = feedHolds[name], clock < hold.until {
                f.camera.position = v3(hold.at.x + 1.3, hold.at.y + 1.1, hold.at.z + 1.6)
                f.camera.look(at: v3(hold.at.x, hold.at.y + 0.7, hold.at.z))
            } else {
                f.camera.transform = f.home
            }
            if f.name == "The pad", let st = fleet.stations[name],
               let (repo, left) = st.facts.staging.lazy.compactMap({ k, v in v.timeLeft(at: self.now).map { (k, $0) } }).first {
                f.caption = "Staging \(repo) · \(left)"
            }
            return f
        } }
        let (pw, ph) = Screens.pixels(Screens.feedWide)
        let at = clock, size = near ? CGSize(width: pw, height: ph) : CGSize(width: pw / 2, height: ph / 2)
        let r = feedRenderer
        MissionScreens.queue.async { [self] in
            let t0 = CACurrentMediaTime()
            let frames = lit.map { feed -> NSImage in
                r.pointOfView = feed.camera
                return r.snapshot(atTime: at, with: size, antialiasingMode: near ? .multisampling2X : .none)
            }
            let spent = CACurrentMediaTime() - t0
            enqueue { [weak self] in
                guard let self else { return }
                for (feed, frame) in zip(lit, frames) { show(Screens.crt(frame, caption: feed.caption), on: feed.material) }
                tallied(near ? "feeds.near" : "feeds.far", spent)
                feedsBusy = false
            }
        }
    }

    private func show(_ image: NSImage, on m: SCNMaterial) {
        m.diffuse.contents = image
        m.emission.contents = image
    }
}
