import AppKit
import SceneKit

struct MissionBoards: Equatable {
    enum Lamp: Equatable { case dark, green, amber, red }
    struct Row: Equatable { let repo: String; let color: RGB; let lamps: [Lamp]; var blink: [Double] = [] }

    static let lamps = ["Deploy", "Checks", "Waiting", "Release", "Errors", "Alarm"]
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
    let annunciator: SCNMaterial
    let blink: SCNNode
    let clock: SCNMaterial
    let errors: SCNMaterial
    let errorsNode: SCNNode
    var feeds: [Feed]
    let wall: SIMD3<Double>
    var shown: MissionBoards?
    static let near = 0.4, nearEvery = 0.5, farEvery = 30.0
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
            let alarm: MissionBoards.Lamp = [deploy, checks, errors].contains(.red) ? .red : .dark
            return MissionBoards.Row(repo: repo, color: fleet.color(forRepo: repo), lamps: [deploy, checks, waiting, release, errors, alarm],
                                     blink: [deployBlink, 0, 0, 0, 0, 0])
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
            show(Screens.annunciator(now.rows), on: screens.annunciator)
            if let m = screens.blink.geometry?.firstMaterial { show(Screens.annunciator(now.rows, blinking: true), on: m) }
        }
        if screens.shown?.clock != now.clock { show(Screens.nixieClock(now.clock), on: screens.clock) }
        if screens.shown == nil || screens.shown?.errors != now.errors {
            show(now.errors.map(Screens.errors) ?? Screens.noSignal("Errors and alarms"), on: screens.errors)
        }
        screens.errorsNode.name = now.errorsLink.map { "link:\($0.url)|\($0.words)" } ?? screens.errorsNode.name
        screens.shown = now
        missionScreens[station.name] = screens
    }

    func blinkBoards() {
        for s in missionScreens.values {
            let rate = s.shown?.rows.flatMap(\.blink).max() ?? 0
            s.blink.isHidden = rate <= 0 || (clock * rate).truncatingRemainder(dividingBy: 1) >= 0.5
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
        let at = clock, size = near ? CGSize(width: 320, height: 200) : CGSize(width: 160, height: 100)
        let r = feedRenderer
        MissionScreens.queue.async { [self] in
            let t0 = CACurrentMediaTime()
            let frames = lit.map { feed -> NSImage in
                r.pointOfView = feed.camera
                return r.snapshot(atTime: at, with: size, antialiasingMode: .none)
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
