import AppKit
import SceneKit

extension StationController {
    // MARK: demo

    func seedDemo() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let acts: [(String, String, Activity, String)] = [
            ("api-node-nest", "\(home)/conductor/workspaces/api-node-nest/bismarck", .coding("src"), "gh-5158/drop-the-services-pilot-gate-on-the-offerings-routes"),
            ("api-node-nest", "\(home)/conductor/workspaces/api-node-nest/regina", .testing, "gh-5140/settlement-redesign"),
            ("api-node-nest", "\(home)/conductor/workspaces/api-node-nest/bismarck", .researching, "gh-5158/drop-the-services-pilot-gate-on-the-offerings-routes"),
            ("tattoodo-web", "\(home)/conductor/workspaces/tattoodo-web/damascus", .coding("app"), "gh-455/booking-flow"),
            ("tattoodo-web", "\(home)/conductor/workspaces/tattoodo-web/oslo", .shipping, "gh-450/hero"),
            ("app-ios", "\(home)/conductor/workspaces/app-ios/lima", .waiting, "gh-298/onboarding"),
            ("app-ios", "\(home)/conductor/workspaces/app-ios/quito", .sleeping, "gh-290/crash-fix"),
            ("rumkapsel", "\(home)/dev/rumkapsel", .researching, "main"),
            ("madplan", "\(home)/dev/madplan", .thinking, "main"),
        ]
        for (i, a) in acts.enumerated() {
            let stationName = "work"
            let station = fleet.station(stationName)
            let h = Home.from(repo: a.0, branch: a.3, cwd: a.1)
            station.ensureRoom(key: h.key, name: h.name, repo: h.repo, color: fleet.color(forRepo: h.repo), lastActive: Date())
            world.learn(.opened(h.key, repo: h.repo, via: .appear), station: stationName)
            let s = SessionInfo(id: "demo-\(i)", cwd: a.1, repo: a.0, repoRoot: nil, owner: nil, lastModified: Date(), activity: a.2, area: nil,
                                title: nil, branch: a.3, toolCount: 0, isSubagent: i == 2, cwdExists: true, promptCount: 0, queuedCount: 0, eventMarkers: [:])
            let m = spawnMinion(s, station: stationName, home: h)
            m.busy = a.2 != .waiting && a.2 != .sleeping
            m.activity = a.2
            m.branch = a.3
            m.place = Place.forActivity(a.2, home: h.key, isSubagent: m.isSubagent)
        }
        if let n = ProcessInfo.processInfo.environment["RK_DEMO_OFFICES"].flatMap(Int.init), n > 0 {
            let repos = ["api-node-nest", "tattoodo-web", "app-ios"]
            let work = fleet.station("work")
            for i in 0..<n {
                let repo = repos[i % repos.count]
                let h = Home.from(repo: repo, branch: "gh-\(900 + i)/demo-office-\(i)", cwd: "\(home)/conductor/workspaces/\(repo)/demo\(i)")
                work.ensureRoom(key: h.key, name: h.name, repo: h.repo, color: fleet.color(forRepo: h.repo), lastActive: Date())
                world.learn(.opened(h.key, repo: h.repo, via: .appear), station: work.name)
            }
        }
        rebuildStatic()
        for m in minions.values { send(m, to: m.place) }
        logEvent("#450 opened a pull request")
        for (i, repo) in ["api-node-nest", "tattoodo-web"].enumerated() {
            world.learn(.release(repo: repo, production: i == 1, label: "rocket:https://github.com|demo release", quiet: true))
        }
    }

    func tickDemo(dt: Double) {
        demoClock += dt
        if demoClock > 3.0 {
            demoClock = 0
            if let m = minions.values.filter({ $0.busy && !$0.isSubagent && !$0.onJob }).randomElement() {
                m.toolCount += 1
                if m.toolCount % 2 == 0 { addPyramid(for: m) } else { clearPyramids(m) }
                ringBell(seed: m.id.hashValue)
            }
            if clock > 7, !demoMerged, let st = fleet.stations["work"], let room = st.rooms["task:tattoodo-web#450"] {
                demoMerged = true
                let crate = CrateID(repo: room.repo ?? "work", number: 450)
                world.learn(.policy(repo: crate.repo, RepoFacts(hasStaging: true, hasCleared: true)))
                world.learn(.work(WorkNews(crate: crate, office: room.key, stage: .ready)))
                world.learn(.work(WorkNews(crate: crate, office: room.key, stage: .stored)))
            }
            if clock > 16, !demoStaged, let st = fleet.stations["work"], (st.stored["tattoodo-web"] ?? 0) > 0 {
                demoStaged = true
                world.learn(.work(WorkNews(crate: CrateID(repo: "tattoodo-web", number: 450), stage: .qa)))
            }
            if clock > 30, !demoLaunched {
                demoLaunched = true
                world.learn(.launched(repo: "tattoodo-web"))
                logEvent("tattoodo-web launched to production: release 2.14")
            }
            if clock > 6, !minions.keys.contains("demo-new") {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let cwd = "\(home)/conductor/workspaces/tattoodo-web/lagos"
                let station = fleet.station("work")
                let h = Home.from(repo: "tattoodo-web", branch: "gh-470/artist-search", cwd: cwd)
                station.ensureRoom(key: h.key, name: h.name, repo: h.repo, color: fleet.color(forRepo: h.repo), lastActive: Date())
                world.learn(.opened(h.key, repo: h.repo, via: .shuttle(for: "demo-new")), station: "work")
                rebuildStatic()
                for mm in minions.values where !mm.onJob { send(mm, to: mm.place) }
                let s = SessionInfo(id: "demo-new", cwd: cwd, repo: "tattoodo-web", repoRoot: nil, owner: nil, lastModified: Date(), activity: .coding("app"), area: nil,
                                    title: nil, branch: "gh-470/artist-search", toolCount: 0, isSubagent: false, cwdExists: true, promptCount: 0, queuedCount: 0, eventMarkers: [:])
                let m = spawnMinion(s, station: "work", home: h)
                m.busy = true; m.activity = .coding("app")
            }
        }
    }

    func flush(_ bowl: PlacedFixture, in station: Station) {
        let water = SCNNode(geometry: SCNBox(width: 0.12, height: 0.012, length: 0.14, chamferRadius: 0))
        water.geometry!.firstMaterial = flat(NSColor(rgb: (0.62, 0.82, 0.95)))
        let at = station.offset + bowl.point(SIMD2(0, 0.05))
        water.position = v3(at.x, Seat.height + 0.006, at.y)
        water.eulerAngles.y = CGFloat(bowl.yaw)
        water.opacity = 0
        propRoot.addChildNode(water)
        let blink = SCNAction.sequence([.fadeOpacity(to: 1, duration: 0.06), .fadeOpacity(to: 0.3, duration: 0.1)])
        water.runAction(.sequence([.repeat(blink, count: 5), .fadeOut(duration: 0.2), .removeFromParentNode()]))
    }

    func lift(_ m: Minion, _ node: SCNNode) {
        let at = node.worldPosition
        stopCrate(node)
        node.removeFromParentNode()
        m.node.addChildNode(node)
        node.position = m.node.convertPosition(at, from: nil)
        node.eulerAngles.y = CGFloat(Double(node.eulerAngles.y) - m.smoothFacing)
        let from = SIMD3(Double(node.position.x), Double(node.position.y), Double(node.position.z))
        moveCrate(node, legs: m.floating ? Routines.floatLegs(from: from, to: .zero, headHeight: m.headHeight, toss: false)
                                         : Routines.liftLegs(from: from.y, handsAt: m.handsAt, headHeight: m.headHeight))
        m.carried = node
    }

    func setDown(_ m: Minion, _ node: SCNNode, to pos: SIMD3<Double>, yaw: Double, level: Int) {
        let t = m.node.convertPosition(v3(pos.x, pos.y, pos.z), from: nil)
        let target = SIMD3(Double(t.x), Double(t.y), Double(t.z))
        moveCrate(node, legs: m.floating ? Routines.floatLegs(from: .zero, to: target, headHeight: m.headHeight, toss: true)
                                         : Routines.setDownLegs(to: target, level: level, headHeight: m.headHeight),
                  yawTo: yaw - m.smoothFacing)
    }

    func release(_ m: Minion, _ node: SCNNode, at pos: SIMD3<Double>, yaw: Double) {
        stopCrate(node)
        node.removeFromParentNode()
        node.position = v3(pos.x, pos.y, pos.z)
        node.eulerAngles = SCNVector3(0, yaw, 0)
        propRoot.addChildNode(node)
        drone.thud()
        m.carried = nil
    }

    func tickGlassDoors(dt: Double) {
        let half = 0.5
        for door in statics.tagged("glassdoor") {
            let stationName = String(door.name!.dropFirst("glassdoor:".count))
            guard let st = fleet.stations[stationName], let pane = door.childNode(withName: "pane", recursively: false) else { continue }
            let dx = Double(door.position.x) - st.offset.x, dz = Double(door.position.z) - st.offset.y
            let walker = minions.values.contains { m in
                m.station == stationName && !m.path.isEmpty && clock >= m.wonderUntil
                    && abs(m.pos.x - dx) < half && abs(m.pos.y - dz) < 0.5
            } || walkerAt(door: door, in: st, half: half)
            let want = walker ? 0.03 : 1.0
            let s = Double(pane.scale.y)
            pane.scale.y = CGFloat(s + (want - s) * min(1, dt * 8))
            pane.position.y = CGFloat(0.35 * Double(pane.scale.y))
        }
    }

    func tickHullLamps() {
        let inbound = Set(simulation.flights.filter { $0.phaseKind == .approach || $0.phaseKind == .descend }.map(\.station))
        let on = clock.truncatingRemainder(dividingBy: 1.0) < 0.5
        for hull in statics.tagged("hull") {
            let lit = on && inbound.contains(String(hull.name!.dropFirst("hull:".count)))
            for lamp in hull.childNodes where lamp.name == "beacon" {
                lamp.geometry?.firstMaterial?.diffuse.contents = lit ? Props.hullLamp : Props.hullLampOff
                lamp.geometry?.firstMaterial?.emission.contents = lit ? Props.hullLamp : NSColor.black
            }
        }
    }

    func kit(_ m: Minion) -> Routines.Outfit { Routines.outfit(m, at: clock) }

    func tickMinions(dt: Double) {
        if !headless { tickGlassDoors(dt: dt) }
        for (m, how) in simulation.stepped {
            guard how != .gone, simulation.bodies[m.id] != nil, let station = fleet.stations[m.station] else { undraw(m); continue }
            if !headless { m.wearSuit(badge: NSColor(fleet.color(forRepo: m.home.repo))) }
            if how != .waking { mirrorLoad(m) }
            m.mirror(station: station, clock: clock, dt: dt, outfit: kit(m), hover: m.isSubagent ? Probe.hover(clock: clock, phase: m.bobPhase) : 0)
            if how == .posed { pose(m, station: station, dt: dt) }
        }
        for station in fleet.stations.values { tendKitchen(station); swivelChairs(station, dt: dt) }
        if !headless || walker != nil { prepareWalk() }
        blinkBoards()
        if clock - boardsCheckedAt >= 0.25 || clock < boardsCheckedAt {
            boardsCheckedAt = clock
            timed("boards") { for station in fleet.stations.values { tendMissionBoards(station) } }
        }
        if clock - feedsRolledAt >= 0.33 || clock < feedsRolledAt {
            feedsRolledAt = clock
            timed("feeds.pick") { rollFeeds() }
        }
        for cue in simulation.drainCues() { play(cue) }
        if layoutDirty { flushScene() }
    }

    func swivelChairs(_ station: Station, dt: Double) {
        for (ref, chair) in chairs[station.name] ?? [:] {
            guard let place = station.place(ref) else { continue }
            if let user = minions.values.first(where: { $0.station == station.name && $0.using == ref && $0.inPlace }) {
                chair.eulerAngles.y = CGFloat(place.sitting(clock - user.actStartedAt, of: user.actFor).chair)
            } else {
                let now = Double(chair.eulerAngles.y), rest = place.facing + .pi
                chair.eulerAngles.y = CGFloat(now + atan2(sin(rest - now), cos(rest - now)) * min(1, dt * 4))
            }
        }
    }

    func tendKitchen(_ station: Station) {
        guard let k = kitchens[station.name] else { return }
        let cook = minions.values.first { $0.station == station.name && $0.inPlace && $0.fare != nil }
        let p = cook.map { $0.actFor > 0 ? Timing.clamped((clock - $0.actStartedAt) / $0.actFor) : 0 } ?? 0
        let brewing = cook?.fare == .coffee, printing = cook?.fare == .bite
        let pouring = brewing && p > 0.12 && p < 0.78
        k.cup.isHidden = !brewing
        k.stream.isHidden = !pouring
        if pouring { k.stream.scale = SCNVector3(0.7 + 0.3 * sin(clock * 31), 1, 1) }
        k.head.position.x = CGFloat(pouring ? sin(clock * 53) * 0.002 : 0)
        k.lamp.geometry?.firstMaterial?.diffuse.contents = brewing
            ? (p < 0.12 ? Props.waitingAmber : Props.passedGreen) : NSColor(rgb: (0.3, 0.32, 0.36))
        if brewing { Kitchen.rise(k.steam, over: Kitchen.mugHeight / 2, at: clock) }
        let since = cook.map { clock - $0.actStartedAt } ?? 0
        let inside = printing && since < Galley.printSeconds
        k.window.geometry?.firstMaterial?.diffuse.contents = inside
            ? NSColor(rgb: (0.95, 0.55, 0.2)).blended(withFraction: 0.5 + 0.5 * sin(clock * 6), of: NSColor(rgb: (0.6, 0.25, 0.1)))!
            : NSColor(rgb: (0.16, 0.18, 0.22))
        k.meal.isHidden = !printing
        guard printing else { return }
        let out = CGFloat(Timing.easeInOut(Timing.clamped((since - Galley.printSeconds) / Galley.slideSeconds)))
        k.meal.position = SCNVector3(Kitchen.mealIn.x, Kitchen.mealIn.y + (Kitchen.mealOut.y - Kitchen.mealIn.y) * out,
                                     Kitchen.mealIn.z + (Kitchen.mealOut.z - Kitchen.mealIn.z) * out)
        let grown = CGFloat(max(0.05, Timing.clamped(since / Galley.printSeconds)))
        k.meal.scale = SCNVector3(1, grown, 1)
    }

    func mirrorLoad(_ m: Minion) {
        if let load = m.load {
            if m.carried == nil, let node = nodeFor(load, m) {
                lift(m, node)
                m.arcStarted = false
            }
            if let node = m.carried, m.phaseKind == .setDown, m.phaseUntil > 0, !m.arcStarted, let on = m.settingDownOn {
                m.arcStarted = true
                setDown(m, node, to: on.pos, yaw: on.yaw, level: on.level)
            }
        } else if let node = m.carried {
            if let landing = m.landing, landing.dropped {
                let at = node.worldPosition
                stopCrate(node)
                node.removeFromParentNode()
                node.position = at
                propRoot.addChildNode(node)
                moveCrate(node, legs: [MotionLeg(to: landing.pos, seconds: 0.35, ease: .easeIn)]) { [weak self] in self?.drone.thud() }
            } else if let landing = m.landing {
                release(m, node, at: landing.pos, yaw: landing.yaw ?? Double(node.eulerAngles.y))
            } else {
                stopCrate(node)
                node.removeFromParentNode()
            }
            m.carried = nil
            m.arcStarted = false
        }
        m.landing = nil
    }

    private func nodeFor(_ load: Body.Load, _ m: Minion) -> SCNNode? {
        switch load {
        case .crate(let c):
            if let n = crateNodes[c.key] { return n }
            let n = looseCrate(c)
            n.position = m.node.position
            markerRoot.addChildNode(n)
            crateNodes[c.key] = n
            return n
        case .office(let key): return boxes[key]
        }
    }

    func play(_ cue: Cue) {
        switch cue {
        case .flush(let station, let bowl): if let st = fleet.stations[station] { flush(bowl, in: st) }
        case .fidget(let id): minions[id]?.fidget()
        case .towel(_, let station, let taken):
            statics.node(named: "towel:" + station)?.isHidden = taken
        case .hop(let id):
            minions[id]?.node.runAction(.sequence([.moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08)]))
        case .clearCones(let id): if let m = minions[id] { clearPyramids(m) }
        case .floor: layoutDirty = true
        case .built(let key):
            for m in minions.values where m.station + "|" + m.home.key == key && m.owedCones > 0 {
                for _ in 0..<m.owedCones { addPyramid(for: m) }
                m.owedCones = 0
            }
        case .folds(let key):
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            for m in minions.values where m.station == parts[0] && m.home.key == parts[1] { clearPyramids(m) }
            stationAnchors[parts[0]]?.childNodes.filter { $0.name == "room:" + key }.forEach { $0.removeFromParentNode() }
        case .stow(let id):
            guard let m = minions[id], let (cube, box) = m.stowing else { return }
            let key: String? = { if case .stow(let office)? = m.current?.kind { return m.station + "|" + office }; return nil }()
            let world = cube.worldPosition
            stopCrate(cube)
            cube.removeFromParentNode()
            cube.position = world
            propRoot.addChildNode(cube)
            let at = SIMD3(Double(box.position.x), Double(box.position.y), Double(box.position.z))
            moveCrate(cube, legs: [MotionLeg(to: at, seconds: 0.6, ease: .easeIn)]) { [weak self, weak box, weak m] in
                self?.drone.thud()
                box?.opacity = 1
                if let self, let key { self.newestCube[key]?.opacity = 1 }
                cube.removeFromParentNode()
                m?.stowing = nil
            }
        case .ownTaken(let id, let c):
            guard let m = minions[id] else { return }
            switch c.kind {
            case .pack: clearPyramids(m)
            case .stow(let office):
                guard m.stowing == nil, let box = newestCube[m.station + "|" + office] else { return }
                let cube = SCNNode(geometry: box.geometry?.copy() as? SCNGeometry)
                cube.position = v3(0, m.headHeight + 0.14, 0)
                m.node.addChildNode(cube)
                m.stowing = (cube, box)
            default: break
            }
        case .ownDropped(let id, let c):
            switch c.kind {
            case .pack:
                markersDirty = true
            case .stow:
                guard let m = minions[id] else { return }
                markersDirty = true
                if let (cube, _) = m.stowing { cube.removeFromParentNode(); m.stowing = nil }
            default: break
            }
        case .packed(let key):
            if let pkg = markerRoot.childNodes.first(where: { $0.name == "box:" + key }) {
                pkg.opacity = 1
                let at = SIMD3(Double(pkg.position.x), Double(pkg.position.y), Double(pkg.position.z))
                pkg.scale = SCNVector3(0.05, 0.05, 0.05)
                moveCrate(pkg, legs: [MotionLeg(to: at, seconds: 0.35, ease: .easeOut, scale: 1)])
            } else { markersDirty = true }
        case .redraw: markersDirty = true
        case .hatch(let station): hatchBlink(station: station)
        case .appear(let station, let id): appearing.insert("\(station)|\(id.repo)|\(id.number)")
        case .vanish(let station, let id): vanish(station, id)
        case .sweep(let up): drone.sweep(up: up)
        case .crateOrdered(let order, let station, let slot, let room, let color): crateOrdered(order, station: station, slot: slot, room: room, color: color)
        case .crateDropped(let order, let station, let slot): crateDropped(order, station: station, slot: slot)
        }
    }

    private func pose(_ m: Minion, station: Station, dt: Double) {
            if case .use(let ref, .shower, _, _) = m.current?.kind, m.inPlace, !m.drying, clock < m.phaseUntil, clock >= m.nextDropAt, let head = station.place(ref) {
                m.nextDropAt = clock + 0.05
                let nozzle = station.offset + head.at + head.outward * Hands.arm
                let drop = SCNNode(geometry: SCNBox(width: 0.035, height: 0.06, length: 0.035, chamferRadius: 0))
                drop.geometry!.firstMaterial = flat(NSColor(rgb: (0.62, 0.82, 0.95)))
                drop.position = v3(nozzle.x + Double.random(in: -0.04...0.04), 0.66, nozzle.y + Double.random(in: -0.04...0.04))
                propRoot.addChildNode(drop)
                let fall = SCNAction.move(to: v3(drop.position.x, 0.02, drop.position.z), duration: 0.32); fall.timingMode = .easeIn
                drop.runAction(.sequence([fall, .fadeOut(duration: 0.08), .removeFromParentNode()]))
            }
            let resting = m.path.isEmpty && m.state == .settled
            let working = m.busy && resting && !m.isSubagent && m.activity != .waiting && !m.exercising && !m.bathing && !m.onJob
            var flatInBunk = false, onBunkEdge = false
            if m.bed != nil, m.place == .quarters {
                switch m.currentPose(at: clock) {
                case .flat: flatInBunk = true
                case .seated: onBunkEdge = m.beddingUntil > 0 || m.risingUntil > clock
                default: break
                }
            }
            let onFixture = (m.bathing || m.exercising || m.seated || m.inPlace) && m.path.isEmpty && m.fetchSpot == nil
            if m.sittingOn != nil, m.using != nil { m.smoothFacing = m.facing }
            let wantFacing = flatInBunk ? 0
                : onBunkEdge ? m.facing
                : (m.path.isEmpty && !onFixture && !m.onJob ? idleFacing(m) : m.facing)
            if !(working && !m.pyramids.isEmpty && m.nearCone) && !(m.place == .lounge && resting) && !(m.isQA && resting) {
                var delta = wantFacing - m.smoothFacing
                delta = atan2(sin(delta), cos(delta))
                m.smoothFacing += delta * min(1, dt * 12)
            }

            var tilt = 0.0, roll = 0.0, spin = 0.0, lean = 0.0
            let t = (clock + m.bobPhase) * m.tempo
            let atCone = working && !m.pyramids.isEmpty && m.nearCone
            if atCone, let cone = m.pyramids.last {
                let conePos = SIMD2(Double(cone.position.x), Double(cone.position.z))
                let mates = minions.values.filter { $0.station == m.station && $0.pyramidCell == m.pyramidCell && !$0.pyramids.isEmpty }.map(\.id).sorted()
                let slot = Double(mates.firstIndex(of: m.id) ?? 0)
                let angle = .pi + slot * 2 * .pi / 3
                let spot = conePos + SIMD2(cos(angle) * 0.4, sin(angle) * 0.4)
                let d = spot - m.pos
                if (d.x * d.x + d.y * d.y).squareRoot() > 0.02 { m.pos += d * min(1, dt * 4) }
                let toCone = conePos - m.pos
                m.smoothFacing = atan2(toCone.x, toCone.y)
            }
            if atCone {
                let slot = m.toolSlot(at: clock)
                let cone = m.pyramids.last
                let r = Routines.cone(slot: slot, t: t, struck: &m.hammerUp)
                tilt = r.tilt; roll = r.roll; spin = r.spin; lean = r.lean
                if let pitch = r.hammerPitch { m.hammerPivot?.eulerAngles.x = CGFloat(pitch) }
                if let aim = r.aim { m.lightPivot?.eulerAngles = aim }
                switch r.flash {
                case .weld(let on, let intensity):
                    if Looks.current.workSparks, m.weldLight == nil {
                        let l = Props.weldLamp()
                        propRoot.addChildNode(l)
                        m.weldLight = l
                    }
                    if let l = m.weldLight, let cone {
                        l.position = v3(cone.position.x + CGFloat(station.offset.x), 0.25, cone.position.z + CGFloat(station.offset.y))
                        l.light?.intensity = intensity
                        l.opacity = on ? 1 : 0
                    }
                case .strike:
                    drone.thud()
                    cone?.runAction(.sequence([.scale(to: 0.85, duration: 0.05), .scale(to: 1, duration: 0.25)]))
                default: break
                }
            }
            if !atCone || m.toolSlot(at: clock) != 0, let l = m.weldLight { l.removeFromParentNode(); m.weldLight = nil }
            var lift: Double?
            if m.place == .lounge, resting, let lounge = station.rooms["kind:lounge"] {
                let cx = Double(lounge.cells.map(\.x).reduce(0, +)) / Double(lounge.cells.count)
                let cy = Double(lounge.cells.map(\.y).reduce(0, +)) / Double(lounge.cells.count)
                let toTable = SIMD2(cx, cy) - m.pos
                m.smoothFacing = m.couch != nil ? m.facing : atan2(toTable.x, toTable.y)
                tilt = (m.couch != nil ? -0.22 : 0) + sin(t * 2.2) * 0.05
                roll = sin(t * 1.3) * 0.04
                if m.couch != nil { tilt = 0.12 + sin(t * 1.6) * 0.04 }
                let other = minions.values.first { $0.id != m.id && $0.station == m.station && $0.place == .lounge && $0.couch == nil && $0.isResting && !$0.busy && $0.path.isEmpty && length($0.pos - m.pos) < 1.4 }
                if m.couch == nil, let other {
                    let toThem = other.pos - m.pos
                    m.smoothFacing = atan2(toThem.x, toThem.y)
                    let myTurn = (Int(clock / 1.6) + (m.id < other.id ? 0 : 1)) % 2 == 0
                    tilt = myTurn ? 0.06 + max(0, sin(t * 4)) * 0.12 : -0.04
                    roll = myTurn ? 0 : sin(t * 0.9) * 0.05
                } else {
                    let cycle = clock / 9 + m.bobPhase
                    let within = (cycle - floor(cycle)) * 9
                    if within < 1.8 {
                        let f = sin(within / 1.8 * .pi)
                        switch Int(floor(cycle)) % 4 {
                        case 0: tilt = -0.32 * f; lift = 0.03 * f
                        case 1: spin = 0.75 * sin(within / 1.8 * .pi * 2)
                        case 2: roll = 0.12 * sin(within * 7)
                        default: tilt = -0.2 * f; roll = 0.06 * f
                        }
                    }
                }
            }
            if m.inPlace, let kind = m.workout {
                let props = gymProps[station.name]
                switch kind {
                case .treadmill:
                    tilt = 0.2; lift = abs(sin(t * 9)) * 0.05; roll = sin(t * 9) * 0.04
                case .bench:
                    if m.onBench { props?.bar.position.y = CGFloat(0.5 + max(0, sin(t * 2.4)) * 0.16) }
                case .bag:
                    let jab = max(0, sin(t * 5.5))
                    lean = jab * 0.09; tilt = 0.1 + jab * 0.12; roll = sin(t * 5.5) * 0.05
                    let a = max(0, sin(t * 5.5 - 0.7)) * 0.28
                    props?.bag.eulerAngles = SCNVector3(-a * cos(m.smoothFacing + .pi), 0, a * sin(m.smoothFacing + .pi))
                case .mat:
                    lift = abs(sin(t * 6)) * 0.14; roll = sin(t * 6) * 0.14; tilt = -0.05
                default: break
                }
            }
            if m.fare != nil, m.inPlace {
                tilt = 0.1 + sin(t * 1.1) * 0.02; roll = sin(t * 0.7) * 0.03
            }
            if working && !atCone {
                let r = Routines.working(m.activity, t: t, dt: dt, clock: clock)
                tilt = r.tilt; roll = r.roll; spin = r.spin; lean = r.lean
                if let lit = r.scanner { m.blinkScanner(lit) }
                if let aim = r.aim { m.lightPivot?.eulerAngles = aim }
                if case .tick = r.flash {
                    let tick = Props.qaTick()
                    tick.position = v3(m.node.position.x, m.headHeight + 0.2, m.node.position.z)
                    propRoot.addChildNode(tick)
                    drone.ping(seed: m.id.hashValue)
                }
            }
            if clock < m.wonderUntil { tilt = -0.15; roll = 0; spin = 0 }
            let hop = m.phaseUntil > 0 ? max(0, sin((m.phaseUntil - clock) / 1.1 * .pi)) : 0
            let held = Routines.hold(m.posture, tilt: tilt, roll: roll, hop: hop)
            tilt = held.tilt; roll = held.roll; m.tilt.position.y = CGFloat(held.rise)
            if let lift { m.tilt.position.y = lift }
            m.node.eulerAngles = SCNVector3(0, m.smoothFacing + spin, 0)
            m.tilt.eulerAngles = SCNVector3(tilt, 0, roll)
            if lean != 0 { m.node.position.x += CGFloat(sin(m.smoothFacing) * lean); m.node.position.z += CGFloat(cos(m.smoothFacing) * lean) }
    }
}
