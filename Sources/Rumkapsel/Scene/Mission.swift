import AppKit
import SceneKit

enum DeployOutcome {
    case live, failed, cancelled
    case lost
    var signalLost: Bool { self == .failed || self == .lost }
}

struct Mission {
    let repo: String
    let station: String
    var rocket = ""
    var started: Double
    var climbed: Double?
    var pad: SIMD3<Double>?
    var expected: Double
    var release: String
    var ended: (outcome: DeployOutcome, at: Double, progress: Double)?
    var took: Double?
    var shownAt = 0.0
    var dustRaised = false
    var separated = false
    var separatedAt = 0.0
    var cameraSide: SIMD3<Double>?
    var trackAim: SIMD3<Double>?
    var trackVelocity = SIMD3<Double>(0, 0, 0)
    var trackFov = 30.0
    var colonyLook: SIMD3<Double>?
    var lastStep = 0.0
    var lastThrust = 0.0
    var rehearsal: Int?

    func progress(at clock: Double) -> Double {
        func ease(_ t: Double) -> Double { let k = max(0, min(1, t)); return k * k * (3 - 2 * k) }
        if let end = ended {
            switch end.outcome {
            case .live: return end.progress + (1 - end.progress) * ease((clock - end.at) / 4)
            case .cancelled: return end.progress * (1 - ease((clock - end.at) / 5))
            case .failed, .lost: return end.progress
            }
        }
        let e = max(0, clock - tZero), launch = launchSeconds, share = Mission.separationShare
        let f = e < launch ? share * e / launch : share + (1 - share) * (e - launch) / max(1, flight - launch)
        return f < 1 ? Mission.curve(f) : 0.92 + 0.05 * (1 - exp(-(f - 1) * 1.5))
    }

    var tZero: Double { climbed ?? started }
    var flight: Double { climbed.map { max(2 * Mission.liftoff, expected - ($0 - started)) } ?? expected }
    var launchSeconds: Double { min(Mission.liftoff, max(1, flight) * Mission.separationShare) }

    static func curve(_ f: Double) -> Double { 0.92 * (0.35 * f + 0.65 * (1 - pow(1 - f, 4))) }
    static let separationShare: Double = {
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 { let mid = (lo + hi) / 2; if curve(mid) < separation { lo = mid } else { hi = mid } }
        return lo
    }()

    func phase(at clock: Double) -> String {
        if let end = ended {
            switch end.outcome {
            case .live:
                let l = clock - end.at
                return l < 4 ? "Final approach" : l < 7 ? "Entering the atmosphere" : l < 10 ? "Landing burn"
                    : "Landed · live in \(Mission.duration(took ?? end.at - started))"
            case .failed: return "Signal lost · the deploy failed"
            case .lost: return "Signal lost · no deploy seen"
            case .cancelled: return "Scrubbed · back to the pad"
            }
        }
        let p = progress(at: clock)
        if clock - started > expected { return "Holding short · longer than usual" }
        if separated {
            let since = clock - separatedAt
            if since < Mission.correction.lowerBound { return "Stage separation" }
            if Mission.correction.contains(since) { return "Course correction" }
        }
        return p < 0.04 ? "Liftoff" : p < Mission.separation - 0.04 ? "Climbing" : p < Mission.separation ? "Stage separation"
            : p < 0.8 ? "Cruising" : "Approaching \(repo)"
    }

    static let separation = 0.5
    static let correction = 1.2..<2.7
    static let liftoff = 12.0
    static let undock = 3.5
    static let toTheMast = 0.38
    static let colonyCut = 4.5
    static let space = 0.3

    static func duration(_ s: Double) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return m > 0 ? "\(m)m \(sec)s" : "\(sec)s"
    }
}

extension StationController {
    // MARK: missions

    func placePlanets() {
        var repos = Set(world.repoRoots.filter { !github.pipeline(repoRoot: $0.key).production.isEmpty }.map(\.value.repo))
        if let m = mission { repos.insert(m.repo) }
        let names = repos.sorted()
        guard names != planets.keys.sorted() || planetRoot.parent == nil else { return }
        if planetRoot.parent == nil { scene.rootNode.addChildNode(planetRoot) }
        planetRoot.childNodes.forEach { $0.removeFromParentNode() }
        planets = [:]
        let centre = frame(for: fleet.ordered).focus
        let yaw = viewYaw
        let forward = SIMD2(-sin(yaw), -cos(yaw)), side = SIMD2(cos(yaw), -sin(yaw))
        for (i, repo) in names.enumerated() {
            let lateral = (Double(i) - Double(names.count - 1) / 2) * 14
            let at = centre + forward * (40 + Double(i % 2) * 12) + side * lateral
            let radius = 2.6 + Double(Planets.seed(repo) % 3) * 0.6
            let node = Looks.current.planet(name: repo, color: NSColor(fleet.color(forRepo: repo)), radius: radius)
            node.position = v3(at.x, 9 + Double((i * 7) % 3) * 4, at.y)
            node.enumerateHierarchy { n, _ in n.categoryBitMask = n.name == "air" ? Pick.air : Pick.planet }
            planetRoot.addChildNode(node)
            planets[repo] = node
        }
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1100
        sun.light!.categoryBitMask = Pick.planet | Pick.colony | Pick.onboard
        sun.look(at: SCNVector3(forward.x * 0.5 + side.x * 1.4, -0.25, forward.y * 0.5 + side.y * 1.4))
        let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient; fill.light!.intensity = 45
        fill.light!.categoryBitMask = Pick.planet | Pick.colony
        let bounce = SCNNode(); bounce.light = SCNLight(); bounce.light!.type = .ambient; bounce.light!.intensity = 420
        bounce.light!.categoryBitMask = Pick.onboard
        planetRoot.addChildNode(sun); planetRoot.addChildNode(fill); planetRoot.addChildNode(bounce)
    }

    func beginMission(station: String, repo: String, expected: TimeInterval, release: String, elapsed: TimeInterval = 0) {
        var m = Mission(repo: repo, station: station, started: clock - elapsed, expected: expected, release: release)
        m.rocket = world.rocketKey(station: station, repo: repo, release: release)
        if var current = mission, current.repo == repo, current.ended == nil {
            current.started = min(current.started, m.started); current.expected = expected
            if !release.isEmpty { current.release = release }
            mission = current
            return
        }
        if let i = queuedMissions.firstIndex(where: { $0.repo == repo && $0.ended == nil }) {
            queuedMissions[i].started = min(queuedMissions[i].started, m.started); queuedMissions[i].expected = expected
            return
        }
        if mission != nil || rocketLoading(m) {
            if !queuedMissions.contains(where: { $0.repo == repo }) { queuedMissions.append(m) }
            return
        }
        launch(m)
    }

    private func launch(_ m: Mission) {
        mission = m
        mission?.shownAt = clock
        let repo = m.repo, release = m.release
        missionShown = ""
        placePlanets()
        logEvent("\(repo): liftoff, deploying to production")
        if let (key, r, _) = padRocket(m, climbing: true), let at = r.climbing, let v = rocketViews[key], !v.node.isHidden,
           let st = fleet.stations[RocketKey.parts(key).station] {
            v.node.childNode(withName: "hold", recursively: false)?.removeFromParentNode()
            let leaving = v.node.clone()
            leaving.name = nil
            leaving.enumerateHierarchy { n, _ in n.categoryBitMask = Pick.launching }
            Props.shape(leaving, lifter: true, panels: RocketGeometry.panels)
            rocketRoot.addChildNode(leaving)
            undocking.append((leaving, at, padPosition(station: st, slot: r.slot)))
            pose(leaving, at: padPosition(station: st, slot: r.slot), t: clock - at)
            drone.sweep(up: true)
            v.node.isHidden = true
            hiddenRockets.append(v.node)
            mission?.climbed = at
        }
        settleColony(repo)
        Colonies.hoist(planets[repo]?.childNode(withName: "colony", recursively: false), repo: repo, release: release,
                       color: NSColor(fleet.color(forRepo: repo)))
        buildMissionCraft(repo: repo, release: release, hotfix: RocketKey.parts(m.rocket).hotfix != nil)
        scene.lightingEnvironment.contents = FlightCraft.environment
        if missionCamera.camera == nil {
            let cam = SCNCamera()
            cam.fieldOfView = 58
            cam.zNear = 0.01
            cam.zFar = 600
            cam.categoryBitMask = ~(Pick.launching | Pick.air)
            FlightCraft.film(cam)
            missionCamera.camera = cam
            scene.rootNode.addChildNode(missionCamera)
        }
        let pad = missionPad(mission!)
        mission?.pad = pad
        puff(at: pad + SIMD3(0, 0.3, 0), up: SIMD3(0, 1, 0), color: NSColor(white: 0.95, alpha: 1), count: 80, spread: 80, speed: 0.4, life: 1.2, size: 0.03)
        stepMission()
        DispatchQueue.main.async { [self] in openMissionScreen() }
    }

    private func clearMission() {
        mission = nil
        hiddenRockets.forEach { $0.isHidden = false }
        hiddenRockets = []
        planets.values.forEach { $0.childNode(withName: "air", recursively: false)?.opacity = 1 }
        DispatchQueue.main.async { [self] in closeMissionScreen() }
    }

    func rehearseLaunch(_ outcome: DeployOutcome) {
        enqueue { [self] in
            if let m = mission {
                guard m.rehearsal != nil else { return }
                clearMission()
            }
            placePlanets()
            guard let repo = planets.keys.sorted().first ?? world.repoRoots.values.map(\.repo).sorted().first else { return }
            let station = world.repoRoots.values.first { $0.repo == repo }?.station ?? fleet.ordered.first?.name ?? "work"
            rehearsals += 1
            let id = rehearsals
            beginMission(station: station, repo: repo, expected: 45, release: latestRelease(repo) ?? "rehearsal")
            mission?.rehearsal = id
            after(outcome == .live ? 45 : 25) { [weak self] in
                guard let self, self.mission?.rehearsal == id else { return }
                self.endMission(repo: repo, outcome: outcome)
            }
        }
    }

    func latestRelease(_ repo: String) -> String? {
        guard let root = world.repoRoots.first(where: { $0.value.repo == repo })?.key,
              let pr = github.releases(repoRoot: root)?.filter({ $0.isProduction && $0.state == "MERGED" }).max(by: { ($0.mergedAt ?? .distantPast) < ($1.mergedAt ?? .distantPast) })
        else { return nil }
        return pr.tag ? pr.title : "#\(pr.number)"
    }

    private func settleColony(_ repo: String) {
        guard let node = planets[repo], node.childNode(withName: "colony", recursively: false) == nil,
              let globe = node.childNode(withName: "globe", recursively: false)?.geometry as? SCNSphere else { return }
        let radius = Double(globe.radius)
        let n = landingNormal(planet: SIMD3(Double(node.position.x), Double(node.position.y), Double(node.position.z)))
        let colony = Colonies.build(repo: repo, color: NSColor(fleet.color(forRepo: repo)), release: latestRelease(repo) ?? "", ground: radius)
        colony.position = v3(n.x * radius, n.y * radius, n.z * radius)
        var side = simd_cross(n, SIMD3(0, 1, 0)); side /= max(0.001, simd_length(side))
        colony.look(at: v3(n.x * radius * 2, n.y * radius * 2, n.z * radius * 2), up: v3(side.x, side.y, side.z), localFront: SCNVector3(0, 1, 0))
        node.addChildNode(colony)
    }

    func landingNormal(planet: SIMD3<Double>) -> SIMD3<Double> {
        let centre = frame(for: fleet.ordered).focus
        var toStation = SIMD3(centre.x - planet.x, 0, centre.y - planet.z)
        toStation /= max(0.001, simd_length(toStation))
        let n = toStation + SIMD3(0, 0.55, 0)
        return n / simd_length(n)
    }

    func endMission(repo: String, outcome: DeployOutcome) {
        if let i = queuedMissions.firstIndex(where: { $0.repo == repo && $0.ended == nil }) {
            queuedMissions[i].ended = (outcome, clock, queuedMissions[i].progress(at: clock))
            queuedMissions[i].took = clock - queuedMissions[i].started
        }
        if var m = mission, m.repo == repo, m.ended == nil {
            m.ended = (outcome, clock, m.progress(at: clock))
            m.took = clock - m.started
            mission = m
        }
        switch outcome {
        case .live:
            let took = mission.flatMap { $0.repo == repo ? $0.took : nil } ?? queuedMissions.first { $0.repo == repo }?.took ?? 0
            logEvent("\(repo): landed, live in \(Mission.duration(took))")
        case .failed: logEvent("\(repo): the deploy failed")
        case .lost: logEvent("\(repo): no deploy seen")
        case .cancelled: logEvent("\(repo): deploy cancelled")
        }
    }

    func turnPlanets(dt: Double) {
        let landing = mission.flatMap { $0.ended?.outcome == .live ? $0.repo : nil }
        for (repo, node) in planets where repo != landing {
            guard let globe = node.childNode(withName: "globe", recursively: false) else { continue }
            globe.eulerAngles.y += CGFloat(dt * 2 * .pi / 600)
        }
    }

    func missionFlies(_ m: Mission, _ key: String) -> Bool {
        let a = RocketKey.parts(m.rocket), b = RocketKey.parts(key)
        return a.station == b.station && a.repo == b.repo && a.hotfix == b.hotfix
    }

    func padRocket(_ m: Mission, climbing: Bool = false) -> (key: String, rocket: ShownRocket, launched: Bool)? {
        guard let st = fleet.stations[RocketKey.parts(m.rocket).station] else { return nil }
        let all = simulation.shownRockets(st).filter { missionFlies(m, $0.key) }
            .map { ($0.key, $0.rocket, st.facts.rockets[String($0.key.dropFirst(st.name.count + 1))]?.launched == true) }
        if climbing { return all.filter { $0.1.climbing != nil }.max { $0.1.climbing! < $1.1.climbing! } }
        return all.first { $0.2 && $0.1.climbing == nil } ?? all.first { $0.1.climbing == nil } ?? all.first
    }

    func rocketLoading(_ m: Mission) -> Bool {
        padRocket(m).map { $0.launched && $0.rocket.climbing == nil } ?? false
    }

    func stepMission() {
        if mission == nil, let i = queuedMissions.firstIndex(where: { !rocketLoading($0) }) {
            launch(queuedMissions.remove(at: i))
            return
        }
        guard let m = mission else { return }
        if let end = m.ended, clock - end.at > (end.outcome.signalLost ? 5 : end.outcome == .live ? 24 : 8) {
            clearMission()
            if !queuedMissions.isEmpty {
                var next = queuedMissions.removeFirst()
                if let end = next.ended { next.ended = (end.outcome, clock, next.progress(at: end.at)) }
                launch(next)
            }
            return
        }
        let s = m.progress(at: clock)
        let pad = missionPad(m)
        let centreXZ = frame(for: fleet.ordered).focus
        let centre = SIMD3(centreXZ.x, 0.0, centreXZ.y)
        let planetNode = planets[m.repo]
        let planet = planetNode.map { SIMD3(Double($0.position.x), Double($0.position.y), Double($0.position.z)) } ?? pad + SIMD3(0, 40, -40)
        let r = (planetNode?.childNode(withName: "globe", recursively: false)?.geometry as? SCNSphere).map { Double($0.radius) } ?? 3
        var toStation = SIMD3(centre.x - planet.x, 0, centre.z - planet.z)
        toStation /= max(0.001, simd_length(toStation))
        let normal = landingNormal(planet: planet)
        let dock = planet + normal * r * 1.7
        let climb = max(6, (dock.y - pad.y - 0.9) / (1 + 1.8 / 0.45 * 0.55 / 3))
        let top = pad + SIMD3(0, climb + 0.9, 0)
        func path(_ s: Double) -> SIMD3<Double> {
            if s <= 0.45 { return pad + SIMD3(0, 0.9 + climb * pow(s / 0.45, 1.8), 0) }
            let t = min(1, (s - 0.45) / 0.55), u = 1 - t
            var c2 = dock + normal * r * 5
            c2.y = min(c2.y, dock.y)
            let c1 = top + SIMD3(0, climb * 1.8 / 0.45 * 0.55 / 3, 0)
            return top * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + dock * (t * t * t)
        }
        func ease(_ t: Double) -> Double { let k = max(0, min(1, t)); return k * k * (3 - 2 * k) }
        let landing = m.ended.flatMap { $0.outcome == .live ? clock - $0.at : nil }
        var craft = path(s)
        var heading = path(min(1, s + 0.01)) - path(max(0, s - 0.01))
        heading = simd_length(heading) < 1e-6 ? SIMD3(0, 1, 0) : heading / simd_length(heading)
        var tangent = simd_cross(normal, SIMD3(0, 1, 0))
        tangent /= max(0.001, simd_length(tangent))
        var scale = 1.0
        var burning = m.ended.map { $0.outcome == .cancelled || ($0.outcome == .live && clock - $0.at < 10) } ?? true
        let hover = planet + normal * (r + 0.45), ground = planet + normal * (r + 0.007)
        var flipping = false
        if let l = landing {
            if l < 4 {
                let turn = ease((l - 1.5) / 2.5)
                flipping = l >= 1.5 && l < 4
                if turn > 0 {
                    var axis = simd_cross(heading, normal)
                    if simd_length(axis) < 1e-4 { axis = tangent }
                    axis /= simd_length(axis)
                    let angle = acos(max(-1, min(1, simd_dot(heading, normal)))) * turn
                    heading = simd_quatd(angle: angle, axis: axis).act(heading)
                }
            } else {
                let e = ease((l - 4) / 3), d = 1 - pow(1 - max(0, min(1, (l - 7) / 3)), 2)
                scale = 1 - 0.78 * e
                craft = l < 7 ? dock + (hover - dock) * e : hover + (ground - hover) * d
                heading = normal
                craft -= heading * (FlightCraft.tipBase - FlightCraft.standDepth) * 0.55 * scale * e
            }
            burning = l < 1 || (l >= 4 && l < 10)
            if let tip = missionCraft.childNode(withName: "tip", recursively: false) {
                FlightCraft.feet(tip, out: ease((l - 8) / 1.2))
                FlightCraft.strain(tip, heat: l >= 4 && l < 7.5 ? sin(.pi * (l - 4) / 3.5) : 0)
            }
            if l >= 8.4, !m.dustRaised { mission?.dustRaised = true; raiseDust(at: planet + normal * r, normal: normal, color: NSColor(fleet.color(forRepo: m.repo))) }
        }
        if s >= Mission.separation, !m.separated, m.ended?.outcome.signalLost != true {
            mission?.separated = true
            mission?.separatedAt = clock
            separateStage(heading: heading)
        }
        let separated = mission?.separated ?? false
        missionCraft.scale = SCNVector3(0.55 * scale, 0.55 * scale, 0.55 * scale)
        missionCraft.position = v3(craft.x, craft.y, craft.z)
        var side = m.cameraSide ?? SIMD3(centre.x - pad.x, 0, centre.z - pad.z)
        side -= heading * simd_dot(side, heading)
        if simd_length(side) < 1e-4 { side = tangent - heading * simd_dot(tangent, heading) }
        side /= max(1e-6, simd_length(side))
        mission?.cameraSide = side
        let bearing = FlightCraft.cameraBearing, square = simd_cross(side, heading)
        let x = side * cos(bearing) - square * sin(bearing), z = side * sin(bearing) + square * cos(bearing)
        func f(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }
        missionCraft.simdOrientation = simd_quatf(simd_float3x3(columns: (f(x), f(heading), f(z))))
        let since = separated ? clock - (mission?.separatedAt ?? clock) : -1
        let tipBurns = m.ended == nil ? since >= Mission.correction.lowerBound : burning
        let coasting = m.ended == nil && clock - m.tZero < Mission.undock
        if coasting { fireThrusters(often: true) }
        if let air = missionCraft.childNode(withName: "lifter plume", recursively: true) {
            air.isHidden = !burning || separated || coasting
            FlightCraft.air(air, thin: s / Mission.space)
        }
        missionCraft.childNode(withName: "tip plume", recursively: true)?.isHidden = !separated || !tipBurns

        let dt = max(0, min(0.1, clock - m.lastStep))
        mission?.lastStep = clock
        let centreOfCraft = craft + heading * 0.6 * 0.55 * scale
        let onboard = landing == nil && clock - m.tZero < m.launchSeconds * Mission.toTheMast && m.ended?.outcome.signalLost != true
        let atColony = (landing ?? 0) >= Mission.colonyCut
        var at: SIMD3<Double>, look: SIMD3<Double>, up: SIMD3<Double>, fov: Double
        if onboard, let mount = (missionCraft.value(forKey: "lifter") as? SCNNode)?.childNode(withName: "down cam", recursively: false)?.simdWorldTransform {
            func column(_ c: SIMD4<Float>) -> SIMD3<Double> { SIMD3(Double(c.x), Double(c.y), Double(c.z)) }
            at = column(mount.columns.3)
            let forward = -column(mount.columns.2)
            look = at + forward / max(0.001, simd_length(forward)) * 10
            up = column(mount.columns.1)
            fov = 58
        } else if atColony {
            var around = simd_cross(normal, tangent)
            around /= max(0.001, simd_length(around))
            at = ground + normal * 0.09 + tangent * 0.62 + around * 0.32
            let pad = ground + normal * 0.12
            let want = pad + (centreOfCraft - pad) * 0.6
            let was = m.colonyLook ?? want
            look = was + (want - was) * (1 - exp(-dt * 2.5))
            mission?.colonyLook = look
            up = normal
            fov = 40
        } else {
            var away = SIMD3(planet.x - pad.x, 0, planet.z - pad.z)
            away /= max(0.001, simd_length(away))
            var across = simd_cross(SIMD3(0, 1, 0), away)
            if simd_dot(across, SIMD3(centre.x - pad.x, 0, centre.z - pad.z)) < 0 { across = -across }
            at = pad + across * 8 - away * 2 + SIMD3(0, max(1, (dock.y - pad.y) * 0.7), 0)
            let distance0 = max(0.5, simd_length(centreOfCraft - at))
            let frame0 = distance0 * tan(m.trackFov * .pi / 360)
            let nudge = SIMD3(sin(floor(clock / 2.6) * 12.9898), 0.6 * sin(floor(clock / 2.6) * 78.233), cos(floor(clock / 2.6) * 37.719)) * frame0 * 0.25
            let target = centreOfCraft + heading * 0.4 * 0.55 * scale + nudge
            let was = m.trackAim ?? target
            var velocity = m.trackVelocity + ((target - was) * 18 - m.trackVelocity * 5.5) * dt
            if m.trackAim == nil { velocity = .zero }
            var aim = was + velocity * dt
            mission?.trackAim = aim
            mission?.trackVelocity = velocity
            let distance = max(0.5, simd_length(aim - at))
            let size = 1.4 * 0.55 * scale
            let want = min(35, max(0.6, 2 * atan(size * 1.2 / distance) * 180 / .pi)) * (1 + 0.07 * sin(clock * 0.45) + 0.04 * sin(clock * 1.7))
            let zoom = m.trackFov + (want - m.trackFov) * (1 - exp(-dt * 0.9))
            mission?.trackFov = zoom
            let frame = distance * tan(zoom * .pi / 360)
            let sx: Double = sin(clock * 13.1) + 0.6 * sin(clock * 29.7)
            let sy: Double = sin(clock * 17.3 + 2) + 0.5 * sin(clock * 31.1)
            let sz: Double = cos(clock * 11.9) + 0.4 * sin(clock * 23.3)
            let hx: Double = sin(clock * 0.9) + 0.4 * sin(clock * 2.3)
            let hy: Double = 0.6 * sin(clock * 1.3 + 1)
            let hz: Double = cos(clock * 0.7) + 0.3 * sin(clock * 3.1)
            let hand = SIMD3(hx, hy, hz) * (frame * 0.05)
            let shiver = SIMD3(sx, sy, sz) * (frame * 0.008 * min(1, distance / 15))
            aim += hand + shiver
            look = aim
            up = SIMD3(0, 1, 0)
            fov = zoom
        }
        missionCamera.camera?.fieldOfView = CGFloat(fov)
        let sky = scene.rootNode.childNode(withName: "flight stars", recursively: false) ?? {
            let n = FlightCraft.stars()
            scene.rootNode.addChildNode(n)
            return n
        }()
        sky.simdPosition = SIMD3(Float(at.x), Float(at.y), Float(at.z))
        if separated {
            if flipping { fireThrusters(often: true) } else if m.ended == nil { fireThrusters(often: Mission.correction.contains(since)) }
        }
        up /= max(0.001, simd_length(up))
        if missionSize == 2, missionOrbit != .zero {
            let pivot = at
            var side = simd_cross(at - pivot, up)
            side /= max(0.001, simd_length(side))
            let turn = simd_quatd(angle: missionOrbit.x, axis: up) * simd_quatd(angle: missionOrbit.y, axis: side)
            at = pivot + turn.act(at - pivot)
            look = pivot + turn.act(look - pivot)
            up = turn.act(up)
        }
        let shake = onboard && m.ended == nil && s < Mission.space ? (0.012 + 0.05 * (1 - min(1, s / 0.05))) * (1 - s / Mission.space) : 0
        if shake > 0 {
            let t = clock, k = shake / 1.5 * 0.35 * simd_length(look - at)
            let x: Double = sin(t * 23.1) + 0.5 * sin(t * 37.7)
            let y: Double = sin(t * 29.3 + 1.3) + 0.5 * sin(t * 41.9)
            let z: Double = sin(t * 19.7 + 2.1) + 0.5 * sin(t * 33.1)
            look += SIMD3(x, y, z) * k
        }
        missionCamera.position = v3(at.x, at.y, at.z)
        missionCamera.look(at: v3(look.x, look.y, look.z), up: v3(up.x, up.y, up.z), localFront: SCNVector3(0, 0, -1))
        if let end = m.ended, end.outcome.signalLost { missionCamera.eulerAngles.z += CGFloat((clock - end.at) * 2.4) }

        let clockText = "T+" + String(format: "%02d:%02d", Int(clock - m.tZero) / 60, Int(clock - m.tZero) % 60)
        let landed = (landing ?? 0) >= 10.5
        let auto = m.ended == nil && clock - m.shownAt > 60, ended = m.ended != nil
        let camera = onboard ? "Onboard" : atColony ? "At the colony" : "From the station"
        let shown = clockText + "|" + m.phase(at: clock) + "|" + camera + "|\(landed)|\(auto)|\(ended)"
        guard shown != missionShown else { return }
        missionShown = shown
        let phase = m.phase(at: clock), usual = "usually \(Int((m.expected / 60).rounded())) min", outcome = m.ended?.outcome
        let repo = m.repo
        DispatchQueue.main.async { [self] in
            missionScreen?.show(repo: repo, camera: camera, clock: clockText, phase: phase, usual: usual, outcome: outcome,
                                 success: landed ? (title: "\(repo) is live", detail: "Landed after \(Mission.duration(m.took ?? clock - m.started))") : nil)
            sizeMission(auto: auto, ended: ended, chip: "▲  \(repo)  ·  \(clockText)  ·  \(phase)")
        }
    }

    private func raiseDust(at point: SIMD3<Double>, normal: SIMD3<Double>, color: NSColor) {
        let sand = color.mixed(with: NSColor(rgb: (0.82, 0.74, 0.6)), 0.45)
        puff(at: point, up: normal, color: sand.withAlphaComponent(0.35), count: 220, spread: 88, speed: 0.3, life: 2.4, size: 0.008)
    }

    @discardableResult
    private func puff(at point: SIMD3<Double>, up: SIMD3<Double>, color: NSColor, count: Int, spread: CGFloat,
                      speed: CGFloat, life: CGFloat, size: CGFloat) -> SCNNode {
        let ps = SCNParticleSystem()
        ps.particleImage = Self.softDot
        ps.birthRate = CGFloat(count) / 2.2
        ps.emissionDuration = 2.2
        ps.loops = false
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = spread
        ps.particleVelocity = speed
        ps.particleVelocityVariation = speed * 0.7
        ps.particleLifeSpan = life
        ps.particleLifeSpanVariation = life * 0.4
        ps.particleSize = size
        ps.particleSizeVariation = size * 0.6
        ps.dampingFactor = 1.6
        ps.particleColor = color.withAlphaComponent(0.8)
        ps.particleColorVariation = SCNVector4(0, 0.05, 0.1, 0.2)
        ps.blendMode = .alpha
        ps.isAffectedByGravity = false
        let fade = CAKeyframeAnimation(); fade.values = [0.85, 0.6, 0]; fade.keyTimes = [0, 0.5, 1]
        ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        let grow = CAKeyframeAnimation(); grow.values = [0.5, 1.4, 2.2]; grow.keyTimes = [0, 0.4, 1]
        ps.propertyControllers?[.size] = SCNParticlePropertyController(animation: grow)
        let node = SCNNode()
        node.position = v3(point.x, point.y, point.z)
        node.look(at: v3(point.x + up.x, point.y + up.y, point.z + up.z), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 1, 0))
        node.addParticleSystem(ps)
        scene.rootNode.addChildNode(node)
        node.runAction(.sequence([.wait(duration: Double(2.2 + life * 1.5)), .removeFromParentNode()]))
        return node
    }

    static let softDot: NSImage = {
        NSImage(size: NSSize(width: 32, height: 32), flipped: false) { r in
            NSGradient(colors: [NSColor.white, NSColor.white.withAlphaComponent(0)])!.draw(in: NSBezierPath(ovalIn: r), relativeCenterPosition: .zero)
            return true
        }
    }()

    private func buildMissionCraft(repo: String, release: String, hotfix: Bool) {
        missionCraft.childNodes.forEach { $0.removeFromParentNode() }
        missionCraft.removeAllActions()
        let (lifter, tip) = FlightCraft.build(color: NSColor(fleet.color(forRepo: repo)), repo: repo, release: release, hotfix: hotfix)
        FlightCraft.mountCameras(lifter: lifter, tip: tip)
        missionCraft.addChildNode(lifter)
        missionCraft.addChildNode(tip)
        missionCraft.setValue(lifter, forKey: "lifter")
        missionCraft.enumerateHierarchy { n, _ in n.categoryBitMask = Pick.onboard }
        if missionCraft.parent == nil { scene.rootNode.addChildNode(missionCraft) }
    }

    func prepareFlight() {
        let (lifter, tip) = FlightCraft.build(color: NSColor(white: 0.6, alpha: 1), repo: "", release: "")
        view.prepare([lifter, tip]) { _ in }
    }

    private func fireThrusters(often settling: Bool) {
        guard let m = mission else { return }
        let every = settling ? 0.22 : 4.5
        guard clock - m.lastThrust >= every else { return }
        mission?.lastThrust = clock
        var pods: [SCNNode] = []
        missionCraft.enumerateHierarchy { n, _ in if n.name == "rcs", (n.value(forKey: "facesCamera") as? Bool) != true { pods.append(n) } }
        guard !pods.isEmpty, let local = pods[Int(clock * 7) % pods.count].value(forKey: "nozzle") as? SIMD3<Double> else { return }
        let pod = pods[Int(clock * 7) % pods.count]
        let at = pod.simdConvertPosition(SIMD3(Float(local.x), Float(local.y), Float(local.z)), to: nil)
        let out = pod.simdConvertVector(SIMD3<Float>(1, 0, 0), to: nil)
        puff(at: SIMD3(Double(at.x), Double(at.y), Double(at.z)), up: SIMD3(Double(out.x), Double(out.y), Double(out.z)),
             color: NSColor(white: 0.97, alpha: 1), count: settling ? 40 : 25, spread: 12, speed: 0.7, life: 0.4, size: 0.008)
            .enumerateHierarchy { n, _ in n.categoryBitMask = Pick.onboard }
    }

    private func separateStage(heading: SIMD3<Double>) {
        guard let lifter = missionCraft.childNode(withName: "lifter", recursively: false) else { return }
        let at = SIMD3(Double(lifter.worldPosition.x), Double(lifter.worldPosition.y), Double(lifter.worldPosition.z))
            + heading * FlightCraft.lifterTop * 0.55
        puff(at: at, up: -heading, color: NSColor(white: 0.95, alpha: 1),
             count: 120, spread: 70, speed: 0.35, life: 1.2, size: 0.03).enumerateHierarchy { n, _ in n.categoryBitMask = Pick.onboard }
        lifter.childNode(withName: "lifter plume", recursively: true)?.isHidden = true
        let drop = SCNAction.moveBy(x: 0.25, y: -5, z: 0.15, duration: 7)
        drop.timingMode = .easeIn
        let tumble = SCNAction.rotateBy(x: 1.9, y: 1.1, z: 1.4, duration: 7)
        tumble.timingMode = .easeIn
        lifter.runAction(.sequence([.group([drop, tumble, .sequence([.wait(duration: 5), .fadeOut(duration: 2)])]), .removeFromParentNode()]))
    }

    private func missionPad(_ m: Mission) -> SIMD3<Double> {
        if let pad = m.pad { return pad }
        if let (key, r, _) = padRocket(m), let st = fleet.stations[RocketKey.parts(key).station] {
            let p = padPosition(station: st, slot: r.slot)
            return SIMD3(Double(p.x), Double(p.y), Double(p.z))
        }
        let st = fleet.stations[m.station] ?? fleet.ordered.first
        guard let st else { return .zero }
        let taken = Set(st.facts.rockets.values.compactMap(\.slot))
        let slots = world.padSlots(station: st)
        let free = (0..<slots.count).first { !taken.contains($0) } ?? 0
        let p = padPosition(station: st, slot: free)
        return SIMD3(Double(p.x), Double(p.y), Double(p.z))
    }

    func openMissionScreen() {
        if missionView == nil {
            let frame = missionFrame
            let pip = SCNView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
            pip.scene = scene
            pip.pointOfView = missionCamera
            pip.backgroundColor = Looks.current.background
            pip.preferredFramesPerSecond = 24
            pip.antialiasingMode = .none
            pip.isPlaying = true
            pip.rendersContinuously = true
            let screen = MissionScreen(frame: frame)
            screen.onClick = { [weak self] p in
                guard let self else { return }
                if !openLandedFlag(near: p) { setMissionSize(min(2, missionSize + 1)) }
            }
            screen.onOrbit = { [weak self] dx, dy in
                guard let self, missionSize == 2 else { return }
                missionOrbit = SIMD2(max(-0.9, min(0.9, missionOrbit.x - dx * 0.006)), max(-0.5, min(0.5, missionOrbit.y + dy * 0.006)))
            }
            screen.onClose = { [weak self] in
                guard let self else { return }
                if missionSize != 0 { setMissionSize(missionSize - 1) } else { missionUserSmall = true; sizeMission(auto: false, ended: false, chip: "") }
            }
            pip.autoresizingMask = [.minXMargin]
            screen.autoresizingMask = [.minXMargin]
            view.addSubview(pip)
            view.addSubview(screen)
            missionView = pip
            missionScreen = screen
            setMissionSize(1)
        }
        missionView?.isHidden = false
        missionScreen?.isHidden = false
    }

    func closeMissionScreen() {
        missionView?.removeFromSuperview(); missionView = nil
        missionScreen?.removeFromSuperview(); missionScreen = nil
        missionUserSmall = false; missionUserOpened = false
        missionSize = 0; missionOrbit = .zero
    }

    var missionFrame: NSRect { NSRect(x: view.bounds.width - 12 - 384, y: 44, width: 384, height: 232) }

    func sizeMission(auto: Bool, ended: Bool, chip text: String) {
        guard let pip = missionView, let screen = missionScreen else { return }
        pip.isHidden = missionUserSmall; screen.isHidden = missionUserSmall
    }

    private func openLandedFlag(near p: NSPoint) -> Bool {
        guard let m = mission, m.ended?.outcome == .live, let pip = missionView,
              let flag = planets[m.repo]?.childNode(withName: "colony", recursively: false)?.childNode(withName: "cloth", recursively: true) else { return false }
        let at = pip.projectPoint(flag.presentation.worldPosition)
        guard at.z < 1, hypot(Double(at.x - p.x), Double(at.y - p.y)) < 40,
              let root = world.repoRoots.first(where: { $0.value.repo == m.repo })?.key, let owner = github.nameWithOwner(repoRoot: root) else { return false }
        let path = m.release.hasPrefix("#") ? "pull/\(m.release.dropFirst())" : "releases/tag/\(m.release)"
        guard !m.release.isEmpty, let url = URL(string: "https://github.com/\(owner)/\(path)") else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    func setMissionSize(_ size: Int) {
        guard let pip = missionView, let screen = missionScreen else { return }
        missionSize = max(0, min(2, size))
        if missionSize != 2 { missionOrbit = .zero }
        let full = missionSize == 2
        let w = min(view.bounds.width * 0.55, 820), medium = NSRect(x: view.bounds.width - 12 - w, y: 44, width: w, height: w * 232 / 384)
        let frame = full ? view.bounds : missionSize == 1 ? medium : missionFrame
        pip.frame = frame; screen.frame = frame
        pip.autoresizingMask = full ? [.width, .height] : [.minXMargin]
        screen.autoresizingMask = full ? [.width, .height] : [.minXMargin]
        screen.needsDisplay = true
    }

    func missionTakes(point p: NSPoint) -> Bool {
        missionScreen.map { !$0.isHidden && $0.frame.contains(p) } ?? false
    }
}

final class MissionScreen: NSView {
    var onClick: ((NSPoint) -> Void)?
    var onClose: (() -> Void)?
    var onOrbit: ((Double, Double) -> Void)?
    private var dragged = false
    private var repo = "", clock = "", phase = "", usual = ""
    private var camera = "Onboard"
    private var outcome: DeployOutcome?
    private var success: (title: String, detail: String)?
    private var successSince = Date()
    private var fade: Timer?
    private var noise: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(repo: String, camera: String, clock: String, phase: String, usual: String, outcome: DeployOutcome?,
              success: (title: String, detail: String)? = nil) {
        self.repo = repo; self.camera = camera; self.clock = clock; self.phase = phase; self.usual = usual; self.outcome = outcome
        if success != nil, self.success == nil { successSince = Date() }
        self.success = success
        if success != nil, fade == nil {
            fade = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] t in
                guard let self else { return t.invalidate() }
                self.needsDisplay = true
                if Date().timeIntervalSince(self.successSince) > 1.2 { t.invalidate() }
            }
        }
        if outcome?.signalLost == true, noise == nil {
            noise = Timer.scheduledTimer(withTimeInterval: 1 / 15, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        }
        needsDisplay = true
    }

    override func removeFromSuperview() { noise?.invalidate(); noise = nil; fade?.invalidate(); fade = nil; super.removeFromSuperview() }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        NSGradient(colors: [NSColor.black.withAlphaComponent(0), NSColor.black.withAlphaComponent(0.55)])!
            .draw(in: NSBezierPath(rect: b), relativeCenterPosition: .zero)
        NSColor.black.withAlphaComponent(0.07).setFill()
        var y: CGFloat = 0
        while y < b.height { NSRect(x: 0, y: y, width: b.width, height: 1).fill(); y += 3 }
        if outcome?.signalLost == true {
            for _ in 0..<Int(b.width * b.height / 40) {
                NSColor(white: CGFloat.random(in: 0.2...0.9), alpha: 0.5).setFill()
                NSRect(x: .random(in: 0..<b.width), y: .random(in: 0..<b.height), width: 2, height: 2).fill()
            }
        }
        NSColor(rgb: (0.98, 0.72, 0.3)).withAlphaComponent(0.6).setStroke()
        let edge = NSBezierPath(rect: b.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()

        let pad: CGFloat = 12
        let live = NSColor(rgb: (1, 0.35, 0.3))
        live.withAlphaComponent(Int(Date().timeIntervalSince1970 * 2) % 2 == 0 ? 0.95 : 0.4).setFill()
        NSBezierPath(ovalIn: NSRect(x: pad, y: b.height - pad - 9, width: 8, height: 8)).fill()
        NSAttributedString(string: "\(camera) · \(repo)", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                                  .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
            .draw(at: NSPoint(x: pad + 14, y: b.height - pad - 12))
        let x = NSAttributedString(string: "×", attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium),
                                                             .foregroundColor: NSColor.white.withAlphaComponent(0.7)])
        x.draw(at: NSPoint(x: closeRect.midX - x.size().width / 2, y: closeRect.midY - x.size().height / 2))

        NSGradient(colors: [NSColor.black.withAlphaComponent(0.65), NSColor.black.withAlphaComponent(0)])!
            .draw(in: NSRect(x: 0, y: 0, width: b.width, height: 64), angle: 90)
        let big = NSAttributedString(string: clock, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
                                                                  .foregroundColor: NSColor.white])
        big.draw(at: NSPoint(x: pad, y: pad + 14))
        let tint = outcome?.signalLost == true ? live : outcome == .live ? NSColor(rgb: (0.45, 0.95, 0.55)) : NSColor(rgb: (0.98, 0.72, 0.3))
        NSAttributedString(string: phase, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: tint])
            .draw(at: NSPoint(x: pad + big.size().width + 12, y: pad + 20))
        NSAttributedString(string: usual, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.55)])
            .draw(at: NSPoint(x: pad, y: pad))

        if let success {
            let a = CGFloat(min(1, Date().timeIntervalSince(successSince) / 1.2))
            let big = max(18, b.height * 0.1)
            let title = NSAttributedString(string: success.title, attributes: [.font: NSFont.systemFont(ofSize: big, weight: .bold),
                                                                              .foregroundColor: NSColor.white.withAlphaComponent(a)])
            let detail = NSAttributedString(string: success.detail, attributes: [.font: NSFont.systemFont(ofSize: big * 0.5, weight: .medium),
                                                                                .foregroundColor: NSColor(rgb: (0.45, 0.95, 0.55)).withAlphaComponent(a)])
            let h = title.size().height + detail.size().height + 6
            let band = NSRect(x: 0, y: b.height * 0.8 - h / 2 - 14, width: b.width, height: h + 28)
            NSGradient(colors: [NSColor.black.withAlphaComponent(0), NSColor.black.withAlphaComponent(0.45 * a), NSColor.black.withAlphaComponent(0)])!
                .draw(in: band, angle: 90)
            title.draw(at: NSPoint(x: b.midX - title.size().width / 2, y: band.minY + 14 + detail.size().height + 6))
            detail.draw(at: NSPoint(x: b.midX - detail.size().width / 2, y: band.minY + 14))
        }
    }

    override func mouseDown(with event: NSEvent) { dragged = false }
    override func mouseDragged(with event: NSEvent) { dragged = true; onOrbit?(Double(event.deltaX), Double(event.deltaY)) }
    override func scrollWheel(with event: NSEvent) { onOrbit?(Double(event.scrollingDeltaX), Double(event.scrollingDeltaY)) }
    override func rotate(with event: NSEvent) { onOrbit?(Double(event.rotation) * 4, 0) }
    override func magnify(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if dragged { dragged = false; return }
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.contains(p) { onClose?() } else { onClick?(p) }
    }
    private var closeRect: NSRect { NSRect(x: bounds.width - 30, y: bounds.height - 30, width: 26, height: 26) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
