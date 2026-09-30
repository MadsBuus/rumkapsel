// A production deploy as a flight: the repository's planet on the horizon, a camera riding up from the
// pad to it, and the mission clock in a window in the corner, timed on how long its deploys usually take.

import AppKit
import SceneKit

enum DeployOutcome {
    case live, failed, cancelled
    /// A flight begun at the merge whose deploy never showed.
    case lost
    /// The signal is gone: the deploy failed, or none was ever seen.
    var signalLost: Bool { self == .failed || self == .lost }
}

/// A production deploy in flight, on the station's clock.
struct Mission {
    let repo: String
    let station: String
    var started: Double
    var expected: Double
    var release: String
    var ended: (outcome: DeployOutcome, at: Double, progress: Double)?
    /// How long the deploy took, from its start to its end.
    var took: Double?
    /// When its window opened: a flight joined late still gets its minute in full before it shrinks.
    var shownAt = 0.0
    var dustRaised = false
    /// The lifter has let go of the tip.
    var separated = false
    var legsOut = false
    var touchedDown = false

    /// How far along the flight is: most of the way by the usual length, creeping on past it, and after
    /// the end, docking, falling back to the pad, or stopped where the signal was lost.
    func progress(at clock: Double) -> Double {
        func ease(_ t: Double) -> Double { let k = max(0, min(1, t)); return k * k * (3 - 2 * k) }
        if let end = ended {
            switch end.outcome {
            case .live: return end.progress + (1 - end.progress) * ease((clock - end.at) / 4)
            case .cancelled: return end.progress * (1 - ease((clock - end.at) / 5))
            case .failed, .lost: return end.progress
            }
        }
        // Quick off the pad and up past the station in the first minute or so, then a long coast and approach
        // that still moves at a third of the pace at the end; past the usual length it creeps.
        let f = max(0, clock - started) / max(1, expected)
        return f < 1 ? 0.92 * (0.35 * f + 0.65 * (1 - pow(1 - f, 4))) : 0.92 + 0.05 * (1 - exp(-(f - 1) * 1.5))
    }

    /// The words under the clock.
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
        return p < 0.04 ? "Liftoff" : p < Mission.separation - 0.04 ? "Climbing" : p < Mission.correction.lowerBound ? "Stage separation"
            : Mission.correction.contains(p) ? "Course correction" : p < 0.8 ? "Coasting" : "Approaching \(repo)"
    }

    /// Where along the flight the lifter lets go, and the tip's short burn that sets it on course.
    static let separation = 0.5
    static let correction = 0.53..<0.62
    /// Out of the atmosphere: past here nothing shakes.
    static let space = 0.3

    static func duration(_ s: Double) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return m > 0 ? "\(m)m \(sec)s" : "\(sec)s"
    }
}

extension StationController {
    // MARK: missions

    /// One planet per repository that ships to production, far out past the station on the horizon.
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
            node.enumerateHierarchy { n, _ in n.categoryBitMask = Pick.planet }
            planetRoot.addChildNode(node)
            planets[repo] = node
        }
        // Their own sun, low and from the side.
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1100
        sun.light!.categoryBitMask = Pick.planet | Pick.colony
        sun.look(at: SCNVector3(forward.x * 0.5 + side.x * 1.4, -0.25, forward.y * 0.5 + side.y * 1.4))
        let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient; fill.light!.intensity = 45
        fill.light!.categoryBitMask = Pick.planet | Pick.colony
        planetRoot.addChildNode(sun); planetRoot.addChildNode(fill)
    }

    /// A production deploy starts. One flight is shown at a time: another repository's waits its turn and
    /// joins its own flight where it has got to, the clock having run for it all along.
    func beginMission(station: String, repo: String, expected: TimeInterval, release: String, elapsed: TimeInterval = 0) {
        let m = Mission(repo: repo, station: station, started: clock - elapsed, expected: expected, release: release)
        // Already flying since the merge: the run has turned up, and the clock is set to when it began.
        // The clock only moves earlier: a flight never sinks back toward the pad because its run began after the merge.
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
        if let current = mission {
            if current.repo != repo, !queuedMissions.contains(where: { $0.repo == repo }) { queuedMissions.append(m) }
            logEvent("\(repo): liftoff, deploying to production")
            return
        }
        launch(m)
        logEvent("\(repo): liftoff, deploying to production")
    }

    private func launch(_ m: Mission) {
        mission = m
        mission?.shownAt = clock
        let repo = m.repo, release = m.release
        missionShown = ""
        placePlanets()
        // The pad's own rocket is the one that flies: seen from the station it lifts off the pad and climbs
        // out of sight, and the pad stands empty while the flight is on. The camera riding it never sees it.
        rocketRoot.childNodes.filter { $0.name?.hasPrefix("rocket:") == true && $0.name?.contains("|\(repo) ") == true && !$0.isHidden }.forEach {
            let leaving = $0.clone()
            leaving.name = nil
            leaving.opacity = 1
            leaving.enumerateHierarchy { n, _ in n.categoryBitMask = Pick.launching }
            Props.shape(leaving, lifter: true, panels: RocketGeometry.panels)
            leaving.childNode(withName: "flame", recursively: false)?.opacity = 1
            rocketRoot.addChildNode(leaving)
            leaving.runAction(.sequence([Looks.current.launch(leaving), .removeFromParentNode()]))
            drone.sweep(up: true)
            $0.isHidden = true
            hiddenRockets.append($0)
        }
        settleColony(repo)
        Colonies.hoist(planets[repo]?.childNode(withName: "colony", recursively: false), repo: repo, release: release,
                       color: NSColor(fleet.color(forRepo: repo)))
        buildMissionCraft(repo: repo)
        if missionCamera.camera == nil {
            let cam = SCNCamera()
            cam.fieldOfView = 58
            cam.zNear = 0.05
            cam.zFar = 600
            cam.categoryBitMask = ~Pick.launching
            missionCamera.camera = cam
            scene.rootNode.addChildNode(missionCamera)
        }
        let pad = missionPad(mission!)
        puff(at: pad, up: SIMD3(0, 1, 0), color: NSColor(rgb: (0.78, 0.8, 0.84)), count: 900, spread: 88, speed: 0.9, life: 4.5, size: 0.22)
        stepMission()
        DispatchQueue.main.async { [self] in openMissionScreen() }
    }

    /// A 45-second pretend deploy of the first repository with a planet, ending the given way.
    func rehearseLaunch(_ outcome: DeployOutcome) {
        enqueue { [self] in
            guard mission == nil else { return }
            placePlanets()
            guard let repo = planets.keys.sorted().first ?? world.repoRoots.values.map(\.repo).sorted().first else { return }
            let station = world.repoRoots.values.first { $0.repo == repo }?.station ?? fleet.ordered.first?.name ?? "work"
            beginMission(station: station, repo: repo, expected: 45, release: latestRelease(repo) ?? "rehearsal")
            after(outcome == .live ? 45 : 25) { [weak self] in self?.endMission(repo: repo, outcome: outcome) }
        }
    }

    /// What a repository last shipped, as its flag says it: the tag, or the production release's number.
    func latestRelease(_ repo: String) -> String? {
        guard let root = world.repoRoots.first(where: { $0.value.repo == repo })?.key,
              let pr = github.releases(repoRoot: root)?.filter({ $0.isProduction && $0.state == "MERGED" }).max(by: { ($0.mergedAt ?? .distantPast) < ($1.mergedAt ?? .distantPast) })
        else { return nil }
        return pr.tag ? pr.title : "#\(pr.number)"
    }

    /// A planet's colony, built the first time a flight heads there, on the spot where flights come down.
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

    /// Where a flight comes down on a planet: high on the face turned to the station.
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

    /// The planets turn slowly, once in ten minutes; one holds still while its own flight comes down onto it.
    func turnPlanets(dt: Double) {
        let landing = mission.flatMap { $0.ended?.outcome == .live ? $0.repo : nil }
        for (repo, node) in planets where repo != landing {
            guard let globe = node.childNode(withName: "globe", recursively: false) else { continue }
            globe.eulerAngles.y += CGFloat(dt * 2 * .pi / 600)
        }
    }

    /// Where the camera is and what it looks at, every frame, from the flight's progress.
    func stepMission() {
        guard let m = mission else { return }
        if let end = m.ended, clock - end.at > (end.outcome.signalLost ? 5 : end.outcome == .live ? 24 : 8) {
            mission = nil
            hiddenRockets.forEach { $0.isHidden = false }
            hiddenRockets = []
            planets.values.forEach { $0.childNode(withName: "air", recursively: false)?.opacity = 1 }
            DispatchQueue.main.async { [self] in closeMissionScreen() }
            if !queuedMissions.isEmpty {
                var next = queuedMissions.removeFirst()
                // One that ended while it waited plays its ending now.
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
        // Straight up, faster and faster, then over and out along a curve to the planet.
        let top = pad + SIMD3(0, 48.9, 0), dock = planet + normal * r * 1.7
        func path(_ s: Double) -> SIMD3<Double> {
            if s <= 0.45 { return pad + SIMD3(0, 0.9 + 48 * pow(s / 0.45, 1.8), 0) }
            let t = min(1, (s - 0.45) / 0.55), u = 1 - t
            let c1 = top + SIMD3(0, 6, 0), c2 = dock + normal * r * 5
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
        let hover = planet + normal * (r + 0.45), ground = planet + normal * (r + 0.045)
        if let l = landing, l >= 4 {
            // Entry: down to a hover, turning engine-first on the way; then the burn down onto the ground.
            let e = ease((l - 4) / 3), d = 1 - pow(1 - max(0, min(1, (l - 7) / 3)), 2)
            scale = 1 - 0.78 * e
            craft = l < 7 ? dock + (hover - dock) * e : hover + (ground - hover) * d
            let turn = Double.pi * ease((l - 4.3) / 2)
            heading = l < 7 ? (-normal * cos(turn) + tangent * sin(turn)) : normal
            burning = l < 10
            // The atmosphere's shell fades as the craft comes down into it.
            planetNode?.childNode(withName: "air", recursively: false)?.opacity = CGFloat(1 - ease((l - 5) / 1.5))
            if l >= 7.4, !m.legsOut { mission?.legsOut = true; deployLegs() }
            if l >= 10, !m.touchedDown { mission?.touchedDown = true; settleLegs() }
            if l >= 8.4, !m.dustRaised { mission?.dustRaised = true; raiseDust(at: planet + normal * r, normal: normal, color: NSColor(fleet.color(forRepo: m.repo))) }
        }
        if s >= Mission.separation, !m.separated, m.ended?.outcome.signalLost != true {
            mission?.separated = true
            separateStage(heading: heading)
        }
        let separated = mission?.separated ?? false
        missionCraft.scale = SCNVector3(0.55 * scale, 0.55 * scale, 0.55 * scale)
        missionCraft.position = v3(craft.x, craft.y, craft.z)
        missionCraft.look(at: v3(craft.x + heading.x, craft.y + heading.y, craft.z + heading.z),
                          up: v3(tangent.x, tangent.y, tangent.z), localFront: SCNVector3(0, 1, 0))
        // The lifter burns from the pad to separation; the tip only for its course correction and its landing.
        let tipBurns = m.ended == nil ? Mission.correction.contains(s) : burning
        missionCraft.childNode(withName: "lifter plume", recursively: true)?.isHidden = !burning || separated
        missionCraft.childNode(withName: "tip plume", recursively: true)?.isHidden = !separated || !tipBurns

        // The camera: on the hull looking aft on the climb, behind the craft over the top, beside it coming down.
        var sideways = simd_cross(SIMD3(0.0, 1, 0), toStation)
        sideways /= max(0.001, simd_length(sideways))
        let aftAt = craft + sideways * 0.5 + SIMD3(0, 0.35, 0), aftLook = aftAt - SIMD3(0, 30, 0) + sideways * 7
        let chaseAt = craft - heading * 2.4 + SIMD3(0, 1.0, 0), chaseLook = craft + heading * 12 + SIMD3(0, 0.8, 0)
        let b = max(0, min(1, (s - 0.4) / 0.25)), blend = b * b * (3 - 2 * b)
        var at = aftAt + (chaseAt - aftAt) * blend
        var look = aftLook + (chaseLook - aftLook) * blend
        var up = toStation + (SIMD3(0, 1, 0) - toStation) * blend
        if let l = landing, l >= 4 {
            let k = ease((l - 4) / 1.5)
            let sideAt = craft + tangent * 0.5 + normal * 0.16, sideLook = craft + normal * 0.03
            at = at + (sideAt - at) * k
            look = look + (sideLook - look) * k
            up = up + (normal - up) * k
        }
        // Landed: a drone lifts off beside it and circles the tip slowly, low over the ground.
        if let l = landing, l >= 10.5 {
            let k = ease((l - 10.5) / 2)
            var around = simd_cross(normal, tangent)
            around /= max(0.001, simd_length(around))
            let a = (l - 10.5) * 0.32
            let droneAt = ground + normal * (0.1 + 0.07 * k) + (tangent * cos(a) + around * sin(a)) * (0.19 + 0.07 * k)
            let droneLook = ground + normal * 0.06
            at = at + (droneAt - at) * k
            look = look + (droneLook - look) * k
        }
        up /= max(0.001, simd_length(up))
        // Filling the station, the view can be turned a little about the craft, or the colony once it lands.
        if missionSize == 2, missionOrbit != .zero {
            let pivot = (landing ?? 0) >= 7 ? ground : craft
            var side = simd_cross(at - pivot, up)
            side /= max(0.001, simd_length(side))
            let turn = simd_quatd(angle: missionOrbit.x, axis: up) * simd_quatd(angle: missionOrbit.y, axis: side)
            at = pivot + turn.act(at - pivot)
            look = pivot + turn.act(look - pivot)
            up = turn.act(up)
        }
        let heat = landing.map { $0 >= 4 && $0 < 7.5 ? sin(.pi * ($0 - 4) / 3.5) : 0 } ?? 0
        // Shaking is the atmosphere's: on the climb out, easing off toward space, and again coming down.
        var shake = m.ended == nil && s < Mission.space ? (0.012 + 0.05 * (1 - min(1, s / 0.05))) * (1 - s / Mission.space) : 0
        if let l = landing { shake = l < 4 ? 0 : l < 7 ? 0.002 + 0.01 * heat : l < 10 ? 0.004 : 0 }
        // A rumble, not a twitch: a few slow sines out of step with each other, never a fresh jolt a frame.
        if shake > 0 {
            let t = clock, k = shake / 1.5
            let x: Double = sin(t * 23.1) + 0.5 * sin(t * 37.7)
            let y: Double = sin(t * 29.3 + 1.3) + 0.5 * sin(t * 41.9)
            let z: Double = sin(t * 19.7 + 2.1) + 0.5 * sin(t * 33.1)
            at += SIMD3(x, y, z) * k
        }
        missionCamera.position = v3(at.x, at.y, at.z)
        missionCamera.look(at: v3(look.x, look.y, look.z), up: v3(up.x, up.y, up.z), localFront: SCNVector3(0, 0, -1))
        if let end = m.ended, end.outcome.signalLost { missionCamera.eulerAngles.z += CGFloat((clock - end.at) * 2.4) }

        let clockText = "T+" + String(format: "%02d:%02d", Int(clock - m.started) / 60, Int(clock - m.started) % 60)
        let landed = (landing ?? 0) >= 10.5
        let auto = m.ended == nil && clock - m.shownAt > 60, ended = m.ended != nil
        let shown = clockText + "|" + m.phase(at: clock) + "|\(Int(heat * 12))|\(landed)|\(auto)|\(ended)"
        guard shown != missionShown else { return }
        missionShown = shown
        let phase = m.phase(at: clock), usual = "usually \(Int((m.expected / 60).rounded())) min", outcome = m.ended?.outcome
        let repo = m.repo, climbing = s < 0.3 && m.ended == nil
        DispatchQueue.main.async { [self] in
            missionScreen?.show(repo: repo, clock: clockText, phase: phase, usual: usual, outcome: outcome, climbing: climbing, heat: heat,
                                 success: landed ? (title: "\(repo) is live", detail: "Landed after \(Mission.duration(m.took ?? clock - m.started))") : nil)
            sizeMission(auto: auto, ended: ended, chip: "▲  \(repo)  ·  \(clockText)  ·  \(phase)")
        }
    }

    /// The ground kicked up under the landing burn, in the planet's colour, blowing out low and settling.
    private func raiseDust(at point: SIMD3<Double>, normal: SIMD3<Double>, color: NSColor) {
        let sand = color.mixed(with: NSColor(rgb: (0.82, 0.74, 0.6)), 0.45)
        puff(at: point, up: normal, color: sand, count: 1400, spread: 84, speed: 0.55, life: 3.2, size: 0.05)
    }

    /// A burst of soft particles from a point, going out around `up`, that then drift and fade.
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

    /// A soft round speck for smoke and dust.
    static let softDot: NSImage = {
        NSImage(size: NSSize(width: 32, height: 32), flipped: false) { r in
            NSGradient(colors: [NSColor.white, NSColor.white.withAlphaComponent(0)])!.draw(in: NSBezierPath(ovalIn: r), relativeCenterPosition: .zero)
            return true
        }
    }()

    /// The rocket the camera rides: the pad's own rocket in the repository's colour, split at its middle
    /// into the lifter and the tip that will land, each with a plume of its own. Seen only onboard.
    private func buildMissionCraft(repo: String) {
        missionCraft.childNodes.forEach { $0.removeFromParentNode() }
        missionCraft.removeAllActions()
        let rocket = Looks.current.rocket(color: NSColor(fleet.color(forRepo: repo)), tall: true, cargo: 6)
        // A rocket built as tip and lifter is taken apart into its pieces, the cradle left behind.
        Props.part(rocket, "cradle")?.removeFromParentNode()
        for name in ["tip", "lifter"] {
            guard let group = Props.part(rocket, name) else { continue }
            for c in group.childNodes { c.removeFromParentNode(); c.position.y += group.position.y; rocket.addChildNode(c) }
            group.removeFromParentNode()
        }
        let (lo, hi) = rocket.boundingBox
        let split = Double(lo.y) + Double(hi.y - lo.y) * 0.5
        let lifter = SCNNode(), tip = SCNNode()
        lifter.name = "lifter"; tip.name = "tip"
        for c in rocket.childNodes where c.name != "flame" {
            c.removeFromParentNode()
            (Double(c.position.y) < split ? lifter : tip).addChildNode(c)
        }
        let big = plume(scale: 1)
        big.name = "lifter plume"
        big.position = v3(0, Double(lo.y), 0)
        lifter.addChildNode(big)
        let small = plume(scale: 0.32, vacuum: true)
        small.name = "tip plume"
        small.position = v3(0, split, 0)
        small.isHidden = true
        tip.addChildNode(small)
        tip.setValue(split, forKey: "split")
        dressTip(tip, base: split, color: NSColor(fleet.color(forRepo: repo)))
        missionCraft.addChildNode(lifter)
        missionCraft.addChildNode(tip)
        missionCraft.enumerateHierarchy { n, _ in n.categoryBitMask = Pick.onboard }
        if missionCraft.parent == nil { scene.rootNode.addChildNode(missionCraft) }
    }

    /// Stage separation: a puff of gas, the lifter falls away tumbling behind, and the tip settles to the
    /// craft's foot to fly on alone.
    private func separateStage(heading: SIMD3<Double>) {
        guard let lifter = missionCraft.childNode(withName: "lifter", recursively: false),
              let tip = missionCraft.childNode(withName: "tip", recursively: false) else { return }
        let world = lifter.worldTransform
        lifter.removeFromParentNode()
        lifter.transform = world
        scene.rootNode.addChildNode(lifter)
        let at = lifter.worldPosition
        puff(at: SIMD3(Double(at.x), Double(at.y), Double(at.z)), up: -heading, color: NSColor(white: 0.95, alpha: 1),
             count: 260, spread: 70, speed: 0.5, life: 1.6, size: 0.06).enumerateHierarchy { n, _ in n.categoryBitMask = Pick.onboard }
        let away = SCNVector3(-heading.x * 4, -heading.y * 4 - 1.5, -heading.z * 4)
        lifter.childNode(withName: "lifter plume", recursively: true)?.runAction(.sequence([.wait(duration: 0.4), .hide()]))
        lifter.runAction(.sequence([
            .group([.moveBy(x: away.x, y: away.y, z: away.z, duration: 7),
                    .rotateBy(x: .pi * 1.3, y: .pi * 0.4, z: .pi * 0.8, duration: 7),
                    .sequence([.wait(duration: 4.5), .fadeOut(duration: 2.5)])]),
            .removeFromParentNode()]))
        let split = (tip.value(forKey: "split") as? Double) ?? 0
        tip.runAction(.move(to: v3(0, -split, 0), duration: 0.8))
    }

    /// What the tip carries to land: a dark heat-shield ring at its foot, four legs folded to the hull,
    /// thruster blocks at its shoulder, an antenna, and a beacon on the nose blinking in the repository's colour.
    private func dressTip(_ tip: SCNNode, base: Double, color: NSColor) {
        let (lo, hi) = tip.boundingBox
        let radius = max(0.05, Double(max(hi.x - lo.x, hi.z - lo.z)) / 2 * 0.8)
        let top = Double(hi.y)
        let dark = lit(NSColor(rgb: (0.18, 0.18, 0.21))), metal = lit(NSColor(rgb: (0.7, 0.72, 0.76)))
        let carbon = lit(NSColor(rgb: (0.11, 0.115, 0.13)))
        let shield = SCNNode(geometry: faceted(SCNCylinder(radius: radius * 1.08, height: 0.06)))
        shield.geometry!.firstMaterial = dark
        shield.position = v3(0, base + 0.03, 0)
        tip.addChildNode(shield)
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            // A leg hinged low on the hull, stowed flush along it: `facing` points it out, the fold swings it down.
            let facing = SCNNode()
            facing.position = v3(cos(a) * radius * 0.98, base + 0.1, sin(a) * radius * 0.98)
            facing.eulerAngles.y = CGFloat(-a)
            let fold = SCNNode()
            fold.name = "leg"
            fold.eulerAngles.z = CGFloat(Self.legStowed)
            let length = 0.5
            for side in [-1.0, 1.0] {
                let strut = SCNNode(geometry: SCNBox(width: 0.022, height: length, length: 0.018, chamferRadius: 0))
                strut.geometry!.firstMaterial = carbon
                strut.position = v3(0, -length / 2, side * 0.028)
                strut.eulerAngles.x = CGFloat(side * 0.055)
                fold.addChildNode(strut)
            }
            let brace = SCNNode(geometry: SCNBox(width: 0.012, height: 0.012, length: 0.06, chamferRadius: 0))
            brace.geometry!.firstMaterial = metal
            brace.position = v3(0, -length * 0.45, 0)
            fold.addChildNode(brace)
            let stripe = SCNNode(geometry: SCNBox(width: 0.026, height: 0.05, length: 0.03, chamferRadius: 0))
            stripe.geometry!.firstMaterial = lit(color)
            stripe.position = v3(0, -length * 0.86, 0)
            fold.addChildNode(stripe)
            let foot = SCNNode()
            foot.name = "foot"
            foot.position = v3(0, -length, 0)
            foot.eulerAngles.z = CGFloat(-Self.legStowed)
            let pad = SCNNode(geometry: faceted(SCNCylinder(radius: 0.05, height: 0.014), 6))
            pad.geometry!.firstMaterial = carbon
            let lamp = SCNNode(geometry: faceted(SCNCylinder(radius: 0.014, height: 0.016), 6))
            lamp.name = "lamp"
            lamp.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.37, 0.42)))
            lamp.position = v3(0, 0.004, 0)
            foot.addChildNode(pad); foot.addChildNode(lamp)
            fold.addChildNode(foot)
            facing.addChildNode(fold)
            tip.addChildNode(facing)
            // Thruster blocks round the shoulder.
            let rcs = SCNNode(geometry: SCNBox(width: 0.05, height: 0.07, length: 0.05, chamferRadius: 0))
            rcs.geometry!.firstMaterial = dark
            rcs.position = v3(cos(a + .pi / 4) * radius * 1.02, top - (top - base) * 0.42, sin(a + .pi / 4) * radius * 1.02)
            tip.addChildNode(rcs)
        }
        let antenna = SCNNode(geometry: faceted(SCNCylinder(radius: 0.008, height: 0.3), 4))
        antenna.geometry!.firstMaterial = metal
        antenna.position = v3(radius * 0.7, top - (top - base) * 0.3, 0)
        antenna.eulerAngles.z = -0.35
        tip.addChildNode(antenna)
        let beacon = SCNNode(geometry: SCNBox(width: 0.05, height: 0.05, length: 0.05, chamferRadius: 0))
        beacon.geometry!.firstMaterial = flat(color.lighter(0.5))
        beacon.position = v3(0, top + 0.02, 0)
        beacon.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.1), .wait(duration: 0.35),
                                                   .fadeOpacity(to: 0.15, duration: 0.25), .wait(duration: 0.5)])))
        tip.addChildNode(beacon)
    }

    /// Folded up flush along the hull, and swung down and out, as angles of a leg's fold.
    static let legStowed = Double.pi - 0.06, legDeployed = 0.62

    /// The legs swing down from the hull and lock, the feet level, their lights coming on.
    private func deployLegs() {
        let swing = SCNAction.customAction(duration: 1.3) { n, t in
            let k = Double(t) / 1.3, e = 1 - pow(1 - k, 3)
            let angle = Self.legStowed + (Self.legDeployed - Self.legStowed) * e
            if n.name == "leg" { n.eulerAngles.z = CGFloat(angle) }
            if n.name == "foot" { n.eulerAngles.z = CGFloat(-angle) }
        }
        missionCraft.enumerateHierarchy { n, _ in
            if n.name == "leg" || n.name == "foot" { n.runAction(swing) }
            if n.name == "lamp" {
                n.runAction(.sequence([.wait(duration: 1.3), .run { $0.geometry?.firstMaterial = flat(NSColor(rgb: (0.85, 0.95, 1))) }]))
            }
        }
    }

    /// Touchdown: the legs give a little under the weight and settle back.
    private func settleLegs() {
        let flex = SCNAction.customAction(duration: 0.7) { n, t in
            let k = Double(t) / 0.7, give = 0.09 * sin(.pi * k) * (1 - k * 0.5)
            if n.name == "leg" { n.eulerAngles.z = CGFloat(Self.legDeployed + give) }
            if n.name == "foot" { n.eulerAngles.z = CGFloat(-Self.legDeployed - give) }
        }
        missionCraft.enumerateHierarchy { n, _ in if n.name == "leg" || n.name == "foot" { n.runAction(flex) } }
    }

    /// An engine's plume: a hot core, a flame and a glow round it, flickering. Its top is at the node.
    /// An engine's flame: orange in the air off the pad, a short blue-white one in vacuum.
    private func plume(scale k: Double, vacuum: Bool = false) -> SCNNode {
        let flame = SCNNode()
        let layers = vacuum
            ? [(0.05, 0.7, NSColor(rgb: (0.95, 0.97, 1)), 1.0), (0.1, 1.3, NSColor(rgb: (0.5, 0.7, 1)), 0.6), (0.18, 1.9, NSColor(rgb: (0.65, 0.8, 1)), 0.2)]
            : [(0.05, 0.9, NSColor(rgb: (1, 0.95, 0.8)), 1.0), (0.11, 1.9, NSColor(rgb: (1, 0.55, 0.2)), 0.75), (0.26, 3.2, NSColor(rgb: (1, 0.75, 0.4)), 0.25)]
        for (radius, length, color, alpha) in layers {
            let cone = SCNNode(geometry: faceted(SCNCone(topRadius: radius * k, bottomRadius: 0, height: length * k), 8))
            let m = flat(color)
            m.blendMode = .add
            m.transparency = alpha
            m.writesToDepthBuffer = false
            cone.geometry!.firstMaterial = m
            cone.position = v3(0, -length * k / 2, 0)
            flame.addChildNode(cone)
        }
        flame.runAction(.repeatForever(.sequence((0..<6).map { _ in
            .scale(to: CGFloat.random(in: 0.82...1.18), duration: Double.random(in: 0.04...0.09))
        })))
        return flame
    }

    /// The foot of the flight: the repository's rocket where it stands, else the middle of its pad.
    private func missionPad(_ m: Mission) -> SIMD3<Double> {
        if let rocket = rocketRoot.childNodes.first(where: { $0.name?.hasPrefix("rocket:") == true && $0.name?.contains("|\(m.repo) ") == true }) {
            let p = rocket.worldPosition
            return SIMD3(Double(p.x), Double(p.y), Double(p.z))
        }
        let st = fleet.stations[m.station] ?? fleet.ordered.first
        guard let st else { return .zero }
        return SIMD3(st.padCenter.x + st.offset.x, 0, st.padCenter.y + st.offset.y)
    }

    /// The camera's window, bottom left, over the station. Main thread.
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
                if !openLandedFlag(near: p) { cycleMissionSize() }
            }
            screen.onOrbit = { [weak self] dx, dy in
                guard let self, missionSize == 2 else { return }
                missionOrbit = SIMD2(max(-0.9, min(0.9, missionOrbit.x - dx * 0.006)), max(-0.5, min(0.5, missionOrbit.y + dy * 0.006)))
            }
            // The ×: from medium or full back to the small picture; on the small picture, closed for this flight.
            screen.onClose = { [weak self] in
                guard let self else { return }
                if missionSize != 0 { missionSize = 2; cycleMissionSize() } else { missionUserSmall = true; sizeMission(auto: false, ended: false, chip: "") }
            }
            pip.autoresizingMask = [.minXMargin]
            screen.autoresizingMask = [.minXMargin]
            view.addSubview(pip)
            view.addSubview(screen)
            missionView = pip
            missionScreen = screen
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

    /// The window's place: the bottom right corner, over the log.
    var missionFrame: NSRect { NSRect(x: view.bounds.width - 12 - 384, y: 44, width: 384, height: 232) }

    /// The window shows unless it was closed with the ×. Main thread.
    func sizeMission(auto: Bool, ended: Bool, chip text: String) {
        guard let pip = missionView, let screen = missionScreen else { return }
        pip.isHidden = missionUserSmall; screen.isHidden = missionUserSmall
    }

    /// Landed, a click on the colony's flag opens the release it flies: the pull request, or the tag.
    /// True when the click was the flag's.
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

    /// The window a size up: from its corner to medium, to filling the station, and back to its corner.
    func cycleMissionSize() {
        guard let pip = missionView, let screen = missionScreen else { return }
        missionSize = (missionSize + 1) % 3
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

/// What lies over the camera's picture: the edge of a lens, faint scan lines, where the camera is, and
/// the mission clock. Static when the signal is lost.
final class MissionScreen: NSView {
    /// A click that is not the ×, where it landed in the window.
    var onClick: ((NSPoint) -> Void)?
    /// The × in the top right corner: the window shrinks to its chip.
    var onClose: (() -> Void)?
    /// A drag, a two-finger scroll or a twist over the window: how far, across and up.
    var onOrbit: ((Double, Double) -> Void)?
    private var dragged = false
    private var repo = "", clock = "", phase = "", usual = ""
    private var outcome: DeployOutcome?
    private var climbing = false
    private var heat = 0.0
    private var success: (title: String, detail: String)?
    private var successSince = Date()
    private var fade: Timer?
    private var noise: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(repo: String, clock: String, phase: String, usual: String, outcome: DeployOutcome?, climbing: Bool, heat: Double,
              success: (title: String, detail: String)? = nil) {
        self.repo = repo; self.clock = clock; self.phase = phase; self.usual = usual; self.outcome = outcome; self.climbing = climbing
        self.heat = heat
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
        // The lens: dark at the corners.
        NSGradient(colors: [NSColor.black.withAlphaComponent(0), NSColor.black.withAlphaComponent(0.55)])!
            .draw(in: NSBezierPath(rect: b), relativeCenterPosition: .zero)
        NSColor.black.withAlphaComponent(0.07).setFill()
        var y: CGFloat = 0
        while y < b.height { NSRect(x: 0, y: y, width: b.width, height: 1).fill(); y += 3 }
        // The engines' light at the foot of the frame while it climbs.
        if climbing {
            NSGradient(colors: [NSColor(rgb: (1, 0.6, 0.25)).withAlphaComponent(0.35), NSColor(rgb: (1, 0.6, 0.25)).withAlphaComponent(0)])!
                .draw(in: NSRect(x: 0, y: 0, width: b.width, height: b.height * 0.3), angle: 90)
        }
        // Re-entry: the air ahead of the craft glowing at the edges of the picture.
        if heat > 0.01 {
            let hot = NSColor(rgb: (1, 0.45, 0.2))
            let glow = NSGradient(colors: [hot.withAlphaComponent(0.6 * heat), hot.withAlphaComponent(0)])!
            let depth = min(b.width, b.height) * 0.35
            glow.draw(in: NSRect(x: 0, y: 0, width: b.width, height: depth), angle: 90)
            glow.draw(in: NSRect(x: 0, y: b.height - depth, width: b.width, height: depth), angle: -90)
            glow.draw(in: NSRect(x: 0, y: 0, width: depth, height: b.height), angle: 0)
            glow.draw(in: NSRect(x: b.width - depth, y: 0, width: depth, height: b.height), angle: 180)
        }
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
        NSAttributedString(string: "Onboard · \(repo)", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
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

        // The success card, fading up in the middle of the picture.
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

