// The per-frame worker loop, and the demo clock that feeds it.

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
            let s = SessionInfo(id: "demo-\(i)", cwd: a.1, repo: a.0, repoRoot: nil, owner: nil, lastModified: Date(), activity: a.2, area: nil,
                                title: nil, branch: a.3, toolCount: 0, isSubagent: i == 2, cwdExists: true, promptCount: 0, queuedCount: 0, eventMarkers: [:])
            let m = spawnMinion(s, station: stationName, home: h)
            m.busy = a.2 != .waiting && a.2 != .sleeping
            m.activity = a.2
            m.branch = a.3
            m.place = Place.forActivity(a.2, home: h.key, isSubagent: m.isSubagent)
        }
        // RK_DEMO_OFFICES adds that many more offices to the demo's work station, to see a theme under load.
        if let n = ProcessInfo.processInfo.environment["RK_DEMO_OFFICES"].flatMap(Int.init), n > 0 {
            let repos = ["api-node-nest", "tattoodo-web", "app-ios"]
            let work = fleet.station("work")
            for i in 0..<n {
                let repo = repos[i % repos.count]
                let h = Home.from(repo: repo, branch: "gh-\(900 + i)/demo-office-\(i)", cwd: "\(home)/conductor/workspaces/\(repo)/demo\(i)")
                work.ensureRoom(key: h.key, name: h.name, repo: h.repo, color: fleet.color(forRepo: h.repo), lastActive: Date())
            }
        }
        rebuildStatic()
        for m in minions.values { send(m, to: m.place) }
        logEvent("#450 opened a pull request")
        if let st = fleet.stations["work"] {
            for (i, repo) in ["api-node-nest", "tattoodo-web"].enumerated() {
                simulation.rocket(station: st.name, repo: repo, label: "rocket:https://github.com|demo release",
                                  untested: i == 1, tall: i == 1, cargo: 0,
                                  command: .rocket(.standBy, station: st.name, repo: repo))
            }
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
            // Demo: a merge sends #450's boxes to storage, then a release loads them into the rocket.
            if clock > 7, !demoMerged, let st = fleet.stations["work"], let room = st.rooms["task:tattoodo-web#450"] {
                demoMerged = true
                let key = roomKey(st, room)
                for (i, c) in room.cells.prefix(3).enumerated() {
                    let b = SCNNode(geometry: SCNBox(width: 0.26, height: 0.26, length: 0.26, chamferRadius: 0))
                    b.geometry!.firstMaterial = lit(NSColor(rgb: (0.6, 0.4, 0.9)))
                    b.position = v3(st.offset.x + Double(c.x) + Double(i) * 0.1 - 0.2, 0.13, st.offset.y + Double(c.y))
                    b.name = "box:" + key
                    markerRoot.addChildNode(b)
                }
                haulMergedBoxes(station: st, key: key, roomName: room.name, repo: room.repo ?? "work", number: 450)
            }
            if clock > 16, !demoStaged, let st = fleet.stations["work"], (st.stored["tattoodo-web"] ?? 0) > 0 { demoStaged = true; stageCargo(station: st, repo: "tattoodo-web") }
            if clock > 30, let r = simulation.rockets["work|tattoodo-web"], r.stage.rank == 0, let st = fleet.stations["work"] {
                simulation.rocket(station: st.name, repo: "tattoodo-web", label: r.label, untested: false, tall: true, cargo: 0,
                                  command: .rocket(.launch, station: st.name, repo: "tattoodo-web"))
                logEvent("tattoodo-web launched to production: release 2.14")
            }
            if clock > 6, !minions.keys.contains("demo-new") {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let cwd = "\(home)/conductor/workspaces/tattoodo-web/lagos"
                let station = fleet.station("work")
                let h = Home.from(repo: "tattoodo-web", branch: "gh-470/artist-search", cwd: cwd)
                station.ensureRoom(key: h.key, name: h.name, repo: h.repo, color: fleet.color(forRepo: h.repo), lastActive: Date())
                world.truth.officeOrdered("work|\(h.key)")
                rebuildStatic()
                for mm in minions.values where !mm.onJob { send(mm, to: mm.place) }
                let s = SessionInfo(id: "demo-new", cwd: cwd, repo: "tattoodo-web", repoRoot: nil, owner: nil, lastModified: Date(), activity: .coding("app"), area: nil,
                                    title: nil, branch: "gh-470/artist-search", toolCount: 0, isSubagent: false, cwdExists: true, promptCount: 0, queuedCount: 0, eventMarkers: [:])
                let m = spawnMinion(s, station: "work", home: h)
                m.busy = true; m.activity = .coding("app")
                simulation.startDelivery(m, roomKey: h.key)
            }
        }
    }

    /// The flush: a beat of water colour flickering in the bowl, then gone.
    func flush(at bowl: SIMD2<Double>, front: Double) {
        let water = SCNNode(geometry: SCNBox(width: 0.12, height: 0.012, length: 0.14, chamferRadius: 0))
        water.geometry!.firstMaterial = flat(NSColor(rgb: (0.62, 0.82, 0.95)))
        water.position = v3(bowl.x, Minion.seat + 0.006, bowl.y - 0.05 * front)
        water.opacity = 0
        propRoot.addChildNode(water)
        let blink = SCNAction.sequence([.fadeOpacity(to: 1, duration: 0.06), .fadeOpacity(to: 0.3, duration: 0.1)])
        water.runAction(.sequence([.repeat(blink, count: 5), .fadeOut(duration: 0.2), .removeFromParentNode()]))
    }

    /// The crate comes off its slot and onto the arms, and stays there until it is set down. Off the
    /// floor it comes up past the chest; off a stack it slides back at its own height first, then up:
    /// waist high from level one, above the head from higher up.
    func lift(_ m: Minion, _ node: SCNNode) {
        let at = node.worldPosition
        stopCrate(node)
        node.removeFromParentNode()
        m.node.addChildNode(node)
        node.position = m.node.convertPosition(at, from: nil)
        node.eulerAngles.y = CGFloat(Double(node.eulerAngles.y) - m.smoothFacing)   // keeps its own turn, now on the arms
        moveCrate(node, legs: Routines.liftLegs(from: Double(node.position.y), handsAt: m.handsAt, headHeight: m.headHeight))
        m.carried = node
    }

    /// The crate leaves the arms and goes down onto its slot. Level 0 is set down carefully in front;
    /// level 1 slides forward onto the top at waist height; level 2 goes over the head and slides in;
    /// higher, with a hop. It is turned on the way down the way the layout will draw it.
    func setDown(_ m: Minion, _ node: SCNNode, to pos: SIMD3<Double>, yaw: Double, level: Int) {
        let t = m.node.convertPosition(v3(pos.x, pos.y, pos.z), from: nil)
        let target = SIMD3(Double(t.x), Double(t.y), Double(t.z))
        moveCrate(node, legs: Routines.setDownLegs(to: target, level: level, headHeight: m.headHeight),
                  yawTo: yaw - m.smoothFacing)
    }

    /// Out of the hands: it stands exactly where the layout will draw it, and nothing moves it from here.
    func release(_ m: Minion, _ node: SCNNode, at pos: SIMD3<Double>, yaw: Double) {
        stopCrate(node)
        node.removeFromParentNode()
        node.position = v3(pos.x, pos.y, pos.z)
        node.eulerAngles = SCNVector3(0, yaw, 0)
        propRoot.addChildNode(node)
        drone.thud()
        m.carried = nil
    }

    /// The airlock doors: a pane drops into the floor for whoever is walking up to it, and stands
    /// again once they are through. Someone waiting inside for the cycle has both doors shut.
    func tickAirlockDoors(dt: Double) {
        for door in staticRoot.childNodes where (door.name ?? "").hasPrefix("airlockdoor:") {
            let stationName = String(door.name!.dropFirst("airlockdoor:".count))
            guard let st = fleet.stations[stationName], let pane = door.childNode(withName: "pane", recursively: false) else { continue }
            let half = Double(st.airlockCells.map(\.x).max()! - st.airlockCells.map(\.x).min()! + 1) / 2
            let dx = Double(door.position.x) - st.offset.x, dz = Double(door.position.z) - st.offset.y
            let walker = minions.values.contains { m in
                m.station == stationName && !m.path.isEmpty && clock >= m.wonderUntil
                    && abs(m.pos.x - dx) < half && abs(m.pos.y - dz) < 0.5
            }
            let want = walker ? 0.03 : 1.0
            let s = Double(pane.scale.y)
            pane.scale.y = CGFloat(s + (want - s) * min(1, dt * 8))
            pane.position.y = CGFloat(0.35 * Double(pane.scale.y))
        }
    }

    /// Every worker, once a frame. The simulation walks it and runs its commands; the scene runs the
    /// pallet errands, whose pallet is still a node, keeps the crate on the arms in step with the body's
    /// load, and draws the pose the body says it holds.
    /// What a body is wearing this frame. The pallet errand is the one prop the body cannot work
    /// out for itself, so it is handed in; everything else follows from the body.
    func kit(_ m: Minion) -> Routines.Outfit {
        let p = simulation.pallets[m.station]
        return Routines.outfit(m, at: clock, pallet: p.map { ($0.repo, $0.pushing) })
    }

    func tickMinions(dt: Double) {
        if !headless { tickAirlockDoors(dt: dt) }   // the panes only ever open for the eye
        for m in Array(minions.values) {
            guard let station = fleet.stations[m.station] else { despawn(m); continue }
            // Hovered: this one holds still while you read what it is up to. The rest carry on.
            if !headless, hovered == "minion:" + m.id { continue }   // a cursor left over a headless run's window freezes nobody
            var posed = true
            switch simulation.stepWalk(m, station: station, dt: dt) {
            case .waking:
                // Held still while it gets to its feet: nothing else runs, since the furniture must not
                // draw it anywhere while it rises. The mirror below still runs.
                m.mirror(station: station, clock: clock, dt: dt, outfit: kit(m))
                continue
            case .walking, .wondering: break
            case .there:
                switch simulation.stepThere(m, station: station, dt: dt) {
                case .gone: despawn(m); continue
                case .spent: posed = false
                case .posed: break
                }
            }
            mirrorLoad(m)
            if simulation.palletErrand(of: m) != nil, case .pushPallet = m.current?.kind, m.path.isEmpty {
                drawPusher(m, station: station)
            }
            if posed { simulation.stepRest(m, station: station, dt: dt) }
            m.mirror(station: station, clock: clock, dt: dt, outfit: kit(m))   // the picture catches up whatever else this frame skipped
            guard posed else { continue }
            pose(m, station: station, dt: dt)
        }
        for cue in simulation.drainCues() { play(cue) }
        // A carry that is over or off leaves no node behind: the rows draw what the ledger says.
        for (id, node) in cargoNodes where simulation.cargo[id] == nil && !crateMoving(node) {
            node.removeFromParentNode()
            cargoNodes[id] = nil
        }
        tagOnLift = tagOnLift.filter { simulation.cargo[$0] != nil }   // a carry called off owes no tag
    }

    /// The node on the arms follows the body's word: lifted when a load appears, sent down its arc when
    /// the set-down begins, and put where the landing says when the load leaves.
    func mirrorLoad(_ m: Minion) {
        if let load = m.load {
            if m.carried == nil, let node = nodeFor(load, m) {
                lift(m, node)
                m.arcStarted = false
                // The tested tag is slapped on as it comes off the row: that is the moment QA passed it.
                if let id = m.current?.id, tagOnLift.remove(id) != nil, node.childNode(withName: "tag", recursively: false) == nil {
                    let tag = Props.tag(size: 0.38)
                    tag.name = "tag"
                    tag.scale = SCNVector3(0.01, 1, 0.01)
                    tag.runAction(.scale(to: 1, duration: 0.25))
                    node.addChildNode(tag)
                }
            }
            if let node = m.carried, m.phaseKind == .setDown, m.phaseUntil > 0, !m.arcStarted, let on = m.settingDownOn {
                m.arcStarted = true
                setDown(m, node, to: on.pos, yaw: on.yaw, level: on.level)
            }
        } else if let node = m.carried {
            if let landing = m.landing, landing.dropped {
                // Set down behind, where the carrier came from: what cannot be carried on stays on the way it was, never in the way ahead.
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

    /// The node for what a body says it holds: the carry's crate, or a new office's crate by key.
    private func nodeFor(_ load: Body.Load, _ m: Minion) -> SCNNode? {
        switch load {
        case .crate: return m.current.flatMap { cargoNodes[$0.id] }
        case .office(let key): return boxes[key]
        }
    }

    /// What the simulation decided this frame that the scene shows once.
    private func play(_ cue: Cue) {
        switch cue {
        case .flush(_, let bowl, let front): flush(at: bowl, front: front)
        case .fidget(let id): minions[id]?.fidget()
        case .towel(_, let station, let taken):
            // Only the rail's own towel: the one on the shoulders is drawn from the body's drying.
            staticRoot.childNode(withName: "towel:" + station, recursively: true)?.isHidden = taken
        case .hop(let id):
            minions[id]?.node.runAction(.sequence([.moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08)]))
        case .clearCones(let id): if let m = minions[id] { clearPyramids(m) }
        case .landed(let job): job.onDone()
        case .reveal(let key): reveal(key)
        case .foldCrate(let key):
            if let crate = boxes.removeValue(forKey: key) {
                let fold = SCNAction.scale(to: 0.01, duration: 0.35); fold.timingMode = .easeIn
                crate.runAction(.sequence([fold, .removeFromParentNode()]))
            }
        case .stow(let id):
            // The cube comes off the head and goes down onto its place on the floor, and the box drawn
            // there takes over as it lands.
            guard let m = minions[id], let (cube, box) = m.stowing else { return }
            let world = cube.worldPosition
            stopCrate(cube)
            cube.removeFromParentNode()
            cube.position = world
            propRoot.addChildNode(cube)
            let at = SIMD3(Double(box.position.x), Double(box.position.y), Double(box.position.z))
            moveCrate(cube, legs: [MotionLeg(to: at, seconds: 0.6, ease: .easeIn)]) { [weak self, weak box, weak m] in
                self?.drone.thud()
                box?.opacity = 1
                cube.removeFromParentNode()
                m?.stowing = nil
            }
        case .packed(let key):
            // The crate is there, strapped, as the worker straightens up.
            packing.remove(key)
            if let pkg = markerRoot.childNodes.first(where: { $0.name == "box:" + key }) {
                pkg.opacity = 1
                let at = SIMD3(Double(pkg.position.x), Double(pkg.position.y), Double(pkg.position.z))
                pkg.scale = SCNVector3(0.05, 0.05, 0.05)
                moveCrate(pkg, legs: [MotionLeg(to: at, seconds: 0.35, ease: .easeOut, scale: 1)])
            } else { markersDirty = true }
        case .redraw: markersDirty = true
        case .palletLift(let station, let crate): palletLift(station: station, crate: crate)
        case .palletLanded(let station, let crate, let aboard): palletLanded(station: station, crate: crate, aboard: aboard)
        case .carryOrdered(let id, let crate): carryOrdered(id: id, crate: crate)
        case .sweep(let up): drone.sweep(up: up)
        case .crateOrdered(let key, let station, let slot, let repo): crateOrdered(key: key, station: station, slot: slot, repo: repo)
        case .crateDropped(let key, let station, let slot): crateDropped(key: key, station: station, slot: slot)
        case .rocketLoading, .liftOff, .steam, .rocketGone, .intoHold: play(rocket: cue)
        }
    }

    /// The flourishes on top of the mirror: the shower's drops, which way the figure turns, and the one
    /// little routine per activity. A frame may skip these — a dropped droplet is nothing.
    private func pose(_ m: Minion, station: Station, dt: Double) {
            let inBath = m.bathing && m.phaseKind == .act && m.path.isEmpty
            if inBath, m.showering, !m.drying, m.fetchSpot == nil, clock >= m.nextDropAt, let bath = station.rooms["kind:bath"] {
                // Pixel water from the nozzle, falling past the shoulders onto the drain.
                m.nextDropAt = clock + 0.05
                let nozzle = station.showerNozzle(bath: bath)
                let drop = SCNNode(geometry: SCNBox(width: 0.035, height: 0.06, length: 0.035, chamferRadius: 0))
                drop.geometry!.firstMaterial = flat(NSColor(rgb: (0.62, 0.82, 0.95)))
                drop.position = v3(nozzle.x + Double.random(in: -0.04...0.04), 0.66, nozzle.y + Double.random(in: -0.04...0.04))
                propRoot.addChildNode(drop)
                let fall = SCNAction.move(to: v3(drop.position.x, 0.02, drop.position.z), duration: 0.32); fall.timingMode = .easeIn
                drop.runAction(.sequence([fall, .fadeOut(duration: 0.08), .removeFromParentNode()]))
            }
            let resting = m.path.isEmpty && m.state == .settled
            // A visit outranks the day's work in the picture: someone on the treadmill is not also testing.
            let working = m.busy && resting && !m.isSubagent && m.activity != .waiting && !m.exercising && !m.bathing && !m.onJob
            let inBed = m.bed != nil && m.place == .quarters && m.path.isEmpty
            // A body on a seat keeps the way it was put down: a sitter is placed behind where its feet
            // are, along its own facing, so turning it to face the camera would swing it off the seat.
            let onFixture = (m.bathing || m.exercising || m.seated) && m.path.isEmpty && m.fetchSpot == nil
            let wantFacing = inBed ? 0 : (m.path.isEmpty && !onFixture ? Double(rig.eulerAngles.y) : m.facing)
            if !(working && !m.pyramids.isEmpty && m.nearCone) && !(m.place == .lounge && resting) && !(m.isQA && resting) {
                var delta = wantFacing - m.smoothFacing
                delta = atan2(sin(delta), cos(delta))
                m.smoothFacing += delta * min(1, dt * 12)
            }

            // One little routine per activity, so you can tell at a glance what a minion is up to.
            var tilt = 0.0, roll = 0.0, spin = 0.0, lean = 0.0
            let t = (clock + m.bobPhase) * m.tempo
            let atCone = working && !m.pyramids.isEmpty && m.nearCone
            if atCone, let cone = m.pyramids.last {
                // Stand a step back from the cone and face it.
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
            var lift: Double?   // the body up off the floor for a hop or a run, applied after the posture
            if m.place == .lounge, resting, let lounge = station.rooms["kind:lounge"] {
                let cx = Double(lounge.cells.map(\.x).reduce(0, +)) / Double(lounge.cells.count)
                let cy = Double(lounge.cells.map(\.y).reduce(0, +)) / Double(lounge.cells.count)
                let toTable = SIMD2(cx, cy) - m.pos
                m.smoothFacing = atan2(toTable.x, toTable.y)
                tilt = (m.couch != nil ? -0.22 : 0) + sin(t * 2.2) * 0.05   // sat back on a couch, or standing at the table
                roll = sin(t * 1.3) * 0.04
                if m.couch != nil { tilt = 0.12 + sin(t * 1.6) * 0.04 }   // reading on the couch
                // Two standing near each other talk: they turn to each other and nod in turn.
                let other = minions.values.first { $0.id != m.id && $0.station == m.station && $0.place == .lounge && $0.couch == nil && $0.isResting && !$0.busy && $0.path.isEmpty && length($0.pos - m.pos) < 1.4 }
                if m.couch == nil, let other {
                    let toThem = other.pos - m.pos
                    m.smoothFacing = atan2(toThem.x, toThem.y)
                    let myTurn = (Int(clock / 1.6) + (m.id < other.id ? 0 : 1)) % 2 == 0
                    tilt = myTurn ? 0.06 + max(0, sin(t * 4)) * 0.12 : -0.04   // the one talking nods; the other listens, head up
                    roll = myTurn ? 0 : sin(t * 0.9) * 0.05
                } else {
                    // Now and then a stretch, a look round, a shuffle or a yawn: a beat of it every nine seconds or so.
                    let cycle = clock / 9 + m.bobPhase
                    let within = (cycle - floor(cycle)) * 9
                    if within < 1.8 {
                        let f = sin(within / 1.8 * .pi)
                        switch Int(floor(cycle)) % 4 {
                        case 0: tilt = -0.32 * f; lift = 0.03 * f                 // a stretch: back, up on the toes
                        case 1: spin = 0.75 * sin(within / 1.8 * .pi * 2)           // a look round, one way then the other
                        case 2: roll = 0.12 * sin(within * 7)                      // a shuffle of the feet
                        default: tilt = -0.2 * f; roll = 0.06 * f                  // a yawn
                        }
                    }
                }
            }
            if m.exercising, m.phaseKind == .act, m.path.isEmpty, m.fetchSpot == nil, let kind = m.workout {
                let props = gymProps[station.name]
                switch kind {
                case .treadmill:   // running on the spot, leaning into the rail
                    tilt = 0.2; lift = abs(sin(t * 9)) * 0.05; roll = sin(t * 9) * 0.04
                case .bench:       // on the back along the bench, and the bar goes up and down over the chest
                    props?.bar.position.y = CGFloat(0.5 + max(0, sin(t * 2.4)) * 0.16)
                case .bag:         // jabs: a lean into each, and the bag swings off it
                    let jab = max(0, sin(t * 5.5))
                    lean = jab * 0.09; tilt = 0.1 + jab * 0.12; roll = sin(t * 5.5) * 0.05
                    let a = max(0, sin(t * 5.5 - 0.7)) * 0.28
                    props?.bag.eulerAngles = SCNVector3(-a * cos(m.smoothFacing + .pi), 0, a * sin(m.smoothFacing + .pi))
                case .mat:         // jumping jacks
                    lift = abs(sin(t * 6)) * 0.14; roll = sin(t * 6) * 0.14; tilt = -0.05
                }
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
            if clock < m.wonderUntil { tilt = -0.15; roll = 0; spin = 0 }   // a beat of wondering
            // A little hop to reach the top of a tall stack, on its way up and down through the phase.
            let hop = m.phaseUntil > 0 ? max(0, sin((m.phaseUntil - clock) / 1.1 * .pi)) : 0
            let held = Routines.hold(m.posture, tilt: tilt, roll: roll, hop: hop)
            tilt = held.tilt; roll = held.roll; m.tilt.position.y = CGFloat(held.rise)
            if let lift { m.tilt.position.y = lift }
            m.node.eulerAngles = SCNVector3(0, m.smoothFacing + spin, 0)
            m.tilt.eulerAngles = SCNVector3(tilt, 0, roll)
            if lean != 0 { m.node.position.x += CGFloat(sin(m.smoothFacing) * lean); m.node.position.z += CGFloat(cos(m.smoothFacing) * lean) }
    }
}
