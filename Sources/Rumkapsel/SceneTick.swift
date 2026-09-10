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
            ("rymdkapsel", "\(home)/dev/rymdkapsel", .researching, "main"),
            ("madplan", "\(home)/dev/madplan", .thinking, "main"),
        ]
        for (i, a) in acts.enumerated() {
            let stationName = a.1.contains("/conductor/") ? "work" : "private"
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
        rebuildStatic()
        for m in minions.values { send(m, to: m.place) }
        logEvent("#450 opened a pull request")
        if let st = fleet.stations["work"] {
            for (i, repo) in ["api-node-nest", "tattoodo-web"].enumerated() {
                handle(rocket: st.name, repo: repo, label: "rocket:https://github.com|demo release",
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
                haulMergedBoxes(station: st, key: key, roomName: room.name, repo: room.repo ?? "work", number: 0)
            }
            if clock > 16, !demoStaged, let st = fleet.stations["work"], (st.stored["tattoodo-web"] ?? 0) > 0 { demoStaged = true; stageCargo(station: st, repo: "tattoodo-web") }
            if clock > 30, let r = rocketActors["work|tattoodo-web"], r.stage.rank == 0, let st = fleet.stations["work"] {
                handle(rocket: st.name, repo: "tattoodo-web", label: r.label, untested: false, tall: true, cargo: 0,
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
                startDelivery(m, roomKey: h.key)
            }
        }
    }

    /// Every worker, once a frame: its walk, its pose, its props.
    /// A shuttle that dropped this office's crate and has not risen from the slot yet.
    func shipStillOver(roomKey: String, station: String) -> Bool {
        shuttles.contains { s in
            guard s.station == station, case .flight(let kind, _, _) = s.command.kind, case .dropCrate(let key) = kind, key == roomKey else { return false }
            return s.phase < 3   // approach, descend, unload
        }
    }

    /// Where the shower's water comes from, in world x/z: the nozzle over the corner across from the bowl.
    func showerNozzle(station: Station, bath: Room) -> SIMD2<Double> {
        let cells = bath.cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let sc2 = cells.count > 1 ? cells[1] : cells.last!
        return SIMD2(station.offset.x + Double(sc2.x) + 0.3, station.offset.y + Double(sc2.y) - 0.18)
    }

    // MARK: hands

    /// Everything a crate does between two slots, in one place. Every crate that moves by hand — a
    /// carry, an office delivery, anything later — goes through `startLift`/`lift` and
    /// `startSetDown`/`setDown`/`release`, so there is one lift on the station and one set-down.
    ///
    /// The arcs are crate motions on the station clock (`CrateMotion`), and so are the phases. Both
    /// are derived from the numbers below and nowhere else, so the two cannot drift: a phase is exactly
    /// its arc plus the beat around it, whatever those durations are changed to.
    enum Hands {
        /// The crate's two legs off its slot: back at its own height, then up onto the arms.
        static let liftFirst = 0.3, liftSecond = 0.35
        /// Crouched over it before the hands take hold.
        static let liftCrouch = 0.45
        /// Out of the arms, over the slot, and squarely down onto it.
        static let setDownFirst = 0.35, setDownSecond = 0.45
        /// A beat standing over it before straightening up.
        static let setDownSettle = 0.3
        static var liftArc: Double { liftFirst + liftSecond }
        static var liftSeconds: Double { liftCrouch + liftArc }
        static var setDownArc: Double { setDownFirst + setDownSecond }
        static var setDownSeconds: Double { setDownArc + setDownSettle }
        /// How high one crate stands on the next.
        static let level = 0.34
        /// An arm's length, and the slack either side of it.
        static let arm = 0.34, near = 0.28, far = 0.42
        /// How long a crate takes to settle down a level when the one under it is taken away.
        static let settleSeconds = 0.6
    }

    /// Stands an arm's length from what it is about to work on, facing it. True once it stands right.
    func atArmsLength(_ m: Minion, of spot: SIMD2<Double>, dt: Double) -> Bool {
        let to = spot - m.pos
        let dist = (to.x * to.x + to.y * to.y).squareRoot()
        if dist > 0.05 { m.facing = atan2(to.x, to.y) }
        guard dist < Hands.near || dist > Hands.far, dist > 0.001 else { return true }
        let want = spot - to / dist * Hands.arm
        m.pos += (want - m.pos) * min(1, dt * 6)
        return (want - m.pos).x.magnitude + (want - m.pos).y.magnitude <= 0.02
    }

    /// Crouching to a crate: how high it stands decides the posture, and the lift decides the clock.
    func startLift(_ m: Minion, height: Double) {
        m.handsAt = max(0, Int((height / Hands.level).rounded()))
        m.phaseUntil = clock + Hands.liftSeconds
    }

    /// True once the crouch is over and the hands should be on the crate.
    func liftDue(_ m: Minion) -> Bool { clock >= m.phaseUntil - Hands.liftArc }

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
        let y = Double(node.position.y)
        let via: SIMD3<Double>
        switch m.handsAt {
        case 0: via = SIMD3(0, m.headHeight * 0.45, 0.3)
        case 1: via = SIMD3(0, y, 0.2)
        default: via = SIMD3(0, max(m.headHeight + 0.2, y), 0.15)
        }
        moveCrate(node, legs: [MotionLeg(to: via, seconds: Hands.liftFirst, ease: .easeOut),
                               MotionLeg(to: SIMD3(0, m.headHeight + 0.14, 0), seconds: Hands.liftSecond)])
        m.carried = node
    }

    /// Standing over the slot: the level it goes onto decides the posture, the set-down the clock.
    func startSetDown(_ m: Minion, level: Int) {
        m.handsAt = level
        m.phaseUntil = clock + Hands.setDownSeconds
    }

    /// The crate leaves the arms and goes down onto its slot. Level 0 is set down carefully in front;
    /// level 1 slides forward onto the top at waist height; level 2 goes over the head and slides in;
    /// higher, with a hop. It is turned on the way down the way the layout will draw it.
    func setDown(_ m: Minion, _ node: SCNNode, to pos: SIMD3<Double>, yaw: Double, level: Int) {
        let t = m.node.convertPosition(v3(pos.x, pos.y, pos.z), from: nil)
        let target = SIMD3(Double(t.x), Double(t.y), Double(t.z))
        let via: SIMD3<Double>
        switch level {
        case 0: via = SIMD3(0, m.headHeight * 0.45, 0.3)
        case 1: via = SIMD3(0, target.y, 0.2)
        default: via = SIMD3(0, max(m.headHeight + 0.2, target.y), 0.15)
        }
        moveCrate(node, legs: [MotionLeg(to: via, seconds: Hands.setDownFirst),
                               MotionLeg(to: target, seconds: Hands.setDownSecond, ease: level == 0 ? .easeIn : .easeOut)],
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

    /// Where an office's crate is set down: the far cell its own package will be drawn on, on the floor.
    func officeCrateSlot(station: Station, roomKey: String) -> Spot? {
        guard let room = station.rooms[roomKey], let cell = farCells(station, room).first else { return nil }
        return Spot(area: .office, station: station.name, owner: roomKey, label: room.name, cell: cell,
                    pos: SIMD3(station.offset.x + Double(cell.x), 0.09, station.offset.y + Double(cell.y)))
    }

    func tickMinions(dt: Double) {
        for m in Array(minions.values) {
            guard let station = fleet.stations[m.station] else { despawn(m); continue }
            // Hovered: this one holds still while you read what it is up to. The rest carry on.
            if hovered == "minion:" + m.id { continue }
            let waitingAge = m.activity == .waiting ? clock - m.waitingSince : 0
            let jumping = m.activity == .waiting && waitingAge < 60 && !m.onJob
            let pacing = m.activity == .waiting && waitingAge >= 60 && !m.onJob
            // Pace by the task, not by who: a loaded minion is the slowest thing on the station, below
            // a stroll; hurrying to work is the fastest; pacing while waiting is slower still.
            let speed = m.isHauling ? 1.1 : (m.busy ? 2.4 : (pacing ? 0.8 : 1.4))
            if m.lying, !m.path.isEmpty {
                if m.wakeUntil == 0 { m.wakeUntil = clock + 1.1; m.setSleeping(false); m.bed = nil }
            }
            if m.wakeUntil > 0 {
                if clock < m.wakeUntil { m.node.opacity = m.opacity; continue } else { m.wakeUntil = 0 }
            }
            if let target = m.path.first, clock >= m.wonderUntil {
                let d = target - m.pos
                let dist = (d.x * d.x + d.y * d.y).squareRoot()
                let step = speed * dt
                if dist <= step { m.pos = target; m.path.removeFirst() } else { m.pos += d / dist * step }
                m.facing = atan2(d.x, d.y)
            } else {
                if m.commitDrop, let c = m.carried {
                    m.commitDrop = false
                    m.carried = nil
                    let world = c.worldPosition
                    stopCrate(c)
                    c.removeFromParentNode()
                    c.position = world
                    propRoot.addChildNode(c)
                    moveCrate(c, legs: [MotionLeg(to: SIMD3(Double(world.x), 0.12, Double(world.z)), seconds: 0.35, ease: .easeIn)]) { [weak self] in
                        self?.drone.thud()
                        c.runAction(.sequence([.wait(duration: 0.4), .fadeOut(duration: 0.3), .removeFromParentNode()]))   // a fade, not a move
                    }
                }
                switch m.current?.kind {
                case .deliverOffice(let r):
                    // Off the shuttle and into the office: the crate is fetched from the bay, lifted the
                    // way any crate is lifted, and set down on the office's own slot before the reveal.
                    let key = "\(m.station)|\(r)"
                    let slot = officeCrateSlot(station: station, roomKey: r)
                    switch m.phaseKind {
                    case .walk:
                        advance(m); continue
                    case .approach:
                        if boxes[key] != nil, !world.truth.isInBay(key) { continue }   // the shuttle has not set it down yet
                        if shipStillOver(roomKey: r, station: m.station) { continue }  // and it has not lifted off the slot yet
                        if let spot = m.fetchSpot {
                            let d = spot - m.pos
                            if (d.x * d.x + d.y * d.y).squareRoot() > 0.04 { m.pos += d * min(1, dt * 5); m.facing = atan2(d.x, d.y); continue }
                            m.fetchSpot = nil
                        }
                        // An arm's length from the crate, facing it, then the crouch: the same as any carry.
                        if let box = boxes[key] {
                            let at = SIMD2(Double(box.worldPosition.x) - station.offset.x, Double(box.worldPosition.z) - station.offset.y)
                            guard atArmsLength(m, of: at, dt: dt) else { continue }
                            startLift(m, height: Double(box.worldPosition.y))
                        } else {
                            startLift(m, height: 0)
                        }
                        advance(m); continue
                    case .lift:
                        guard liftDue(m) else { continue }
                        if m.carried == nil, let box = boxes[key] {
                            world.truth.tookFromBay(key)
                            lift(m, box)
                        }
                        if clock < m.phaseUntil { continue }
                        advance(m)
                        // The office went away while the crate was in the air: nothing to walk it into.
                        if let slot { walk(m, to: slot.cell) } else { reveal(key); finish(m) }
                        continue
                    case .haul:
                        advance(m); continue
                    default:
                        guard let slot, let box = m.carried else {
                            m.carried?.removeFromParentNode()
                            m.carried = nil
                            reveal(key)
                            finish(m)
                            continue
                        }
                        let spot = SIMD2(slot.pos.x - station.offset.x, slot.pos.z - station.offset.y)
                        if m.phaseUntil == 0 {
                            guard atArmsLength(m, of: spot, dt: dt) else { continue }
                            startSetDown(m, level: slot.level)
                            setDown(m, box, to: slot.pos, yaw: slot.yaw, level: slot.level)
                            continue
                        }
                        let toSpot = spot - m.pos
                        if (toSpot.x * toSpot.x + toSpot.y * toSpot.y).squareRoot() > 0.05 { m.facing = atan2(toSpot.x, toSpot.y) }
                        if clock < m.phaseUntil { continue }
                        release(m, box, at: slot.pos, yaw: slot.yaw)
                        reveal(key)   // set down on its slot: the office fades in round it as the crate fades out
                        finish(m)
                        continue
                    }
                case .dispatch, .loadPallet, .waitPallet, .pushPallet, .unloadPallet:
                    palletStep(m, station: station)
                    continue
                case .react(_, _, let seconds):
                    // There: work at it for its span of station time, then back to the quarters.
                    if m.phaseKind == .walk { advance(m); m.phaseUntil = clock + seconds; continue }
                    if clock >= m.phaseUntil { crewRested(m) }
                case .carry(let crate, _, let to):
                    guard let id = m.current?.id, let job = cargo[id] else {
                        // The crate went away: put down whatever is on the arms, where it stands.
                        dropWhereStanding(m)
                        finish(m); continue
                    }
                    switch m.phaseKind {
                    case .walk:
                        advance(m); continue
                    case .approach:
                        // Stand an arm's length from the crate, facing it, before taking hold.
                        let boxAt = SIMD2(Double(job.node.worldPosition.x) - station.offset.x, Double(job.node.worldPosition.z) - station.offset.y)
                        guard atArmsLength(m, of: boxAt, dt: dt) else { continue }
                        advance(m)
                        startLift(m, height: Double(job.node.worldPosition.y))
                        continue
                    case .lift:
                        // Take hold at the crate's own height, bring it up and over the head.
                        let boxAt = SIMD2(Double(job.node.worldPosition.x) - station.offset.x, Double(job.node.worldPosition.z) - station.offset.y)
                        let toBox = boxAt - m.pos
                        if (toBox.x * toBox.x + toBox.y * toBox.y).squareRoot() > 0.05 { m.facing = atan2(toBox.x, toBox.y) }
                        guard liftDue(m) else { continue }
                        if m.carried == nil {
                            lift(m, job.node)
                            self.world.truth.pickedUp(crate, by: m.id)   // truth from the pickup: nobody else may move it
                        }
                        if clock < m.phaseUntil { continue }
                        advance(m)
                        walk(m, to: to.cell)
                        continue
                    case .haul:
                        advance(m); continue
                    default:
                        // Set the crate down squarely on its slot, then a beat before straightening up.
                        // A crate is heavy: it stays on the arms all the way there and the hands do the lowering.
                        let spot = SIMD2(to.pos.x - station.offset.x, to.pos.z - station.offset.y)
                        if m.phaseUntil == 0 {
                            // A step back from the spot so the crate goes down in front, not underfoot.
                            guard atArmsLength(m, of: spot, dt: dt) else { continue }
                            startSetDown(m, level: to.level)
                            setDown(m, job.node, to: to.pos, yaw: to.yaw, level: to.level)
                            continue
                        }
                        let toSpot = spot - m.pos
                        if (toSpot.x * toSpot.x + toSpot.y * toSpot.y).squareRoot() > 0.05 { m.facing = atan2(toSpot.x, toSpot.y) }
                        if clock < m.phaseUntil { continue }
                        release(m, job.node, at: to.pos, yaw: to.yaw)
                        cargo[id] = nil
                        self.world.truth.setDown(crate, at: to)
                        job.onDone()
                        finish(m)
                        continue
                    }
                default:
                    break
                }
                // There: the quiet commands move on from walking to being there, so truth says so too.
                if m.path.isEmpty, m.phaseKind == .walk, let c = m.current {
                    switch c.kind {
                    case .goTo, .bath, .chore, .qa, .sleep, .work, .react, .leave: advance(m)
                    default: break
                    }
                }
                switch m.state {
                case .arriving:
                    m.state = .settled
                case .settled:
                    if m.isQA, clock >= m.nextWanderAt {
                        // Stack by stack along the untested row: stand in the aisle beside it, face it, sweep it.
                        let stacks = Dictionary(grouping: world.yardLayout(station: station, area: "deck").filter { !$0.cleared }, by: \.column)
                            .values.compactMap { $0.first }.sorted { $0.column < $1.column }
                        if !stacks.isEmpty {
                            let stack = stacks[m.qaStop % stacks.count]
                            m.qaStop += 1
                            let aisle = [Cell(x: stack.cell.x, y: stack.cell.y - 1), Cell(x: stack.cell.x, y: stack.cell.y + 1)]
                                .first { station.deckCells.contains($0) } ?? stack.cell
                            m.path = station.path(from: m.pos, to: aisle)
                            m.facing = atan2(stack.pos.x - station.offset.x - Double(aisle.x), stack.pos.z - station.offset.y - Double(aisle.y))
                        }
                        m.nextWanderAt = clock + Double.random(in: 4...7)
                        m.setTool(.scanner)
                        if clock >= m.nextImpatience {
                            m.nextImpatience = clock + Double.random(in: 5...9)
                            m.node.runAction(.sequence([.moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08)]))
                        }
                    }
                    // Bath rules: a shower after a long stretch of work, maybe a pee after a short one,
                    // and loungers go now and then. Never while busy, carrying, on a job or in bed.
                    if m.busy && !m.wasBusy { m.busySince = clock; m.bathDue = 0 }
                    if !m.busy && m.wasBusy && !m.isSubagent {
                        let stretch = clock - m.busySince
                        if stretch > 20 * 60 { m.bathDue = clock + Double.random(in: 3...20); m.showering = true }
                        else if stretch > 3 * 60 { m.shortStretches += 1; if m.shortStretches % 2 == 0 { m.bathDue = clock + Double.random(in: 3...20); m.showering = false } }
                    }
                    m.wasBusy = m.busy
                    if m.bathDue == 0, m.place == .lounge, !m.isSubagent {
                        if m.nextBathAt == 0 { m.nextBathAt = clock + Double.random(in: 420...900) }
                        if clock >= m.nextBathAt { m.bathDue = clock; m.showering = false; m.nextBathAt = 0 }
                    } else if m.place != .lounge { m.nextBathAt = 0 }
                    let settled = m.path.isEmpty
                    // Chores: a lounger with nothing to do wanders off to check on the yard, the bay or the
                    // hallway, lingers a while, and comes back to the couch.
                    if m.isChore {
                        if settled, clock >= m.phaseUntil { m.nextChoreAt = clock + Double.random(in: 180...480); send(m, to: .lounge) }
                    } else if m.place == .lounge, !m.busy, m.isResting, settled, !m.isSubagent, m.bathDue == 0 {
                        if m.nextChoreAt == 0 { m.nextChoreAt = clock + Double.random(in: 60...240) }
                        if clock >= m.nextChoreAt {
                            // A loaded rocket on the pad draws a crowd: the idle drift to the deck's aisle beside it.
                            let rocketReady = rocketActors.values.contains { $0.station == station.name && ($0.isSteaming || $0.isLaunching) }
                            let padSide = station.deckCells.filter { $0.y == (station.deckCells.map(\.y).min() ?? 0) + 1 }
                            // Somewhere to stand: a cell whose centre is clear, never one buried under crates.
                            let spots = (rocketReady && !padSide.isEmpty ? padSide : station.corridorCells + station.storageCells + station.deckCells + station.hangarCells)
                                .filter { c in (-1...1).allSatisfy { dx in (-1...1).allSatisfy { dy in !station.obstacles.contains(Cell(x: c.x * Station.fine + dx, y: c.y * Station.fine + dy)) } } }   // the whole cell clear
                            if let spot = spots.randomElement() {
                                start(m, .chore(spot: spot))
                                m.couch = nil
                                m.place = .core
                                m.path = station.path(from: m.pos, to: spot)
                                m.phaseUntil = clock + Double.random(in: 10...25)
                                m.nextWanderAt = m.phaseUntil
                            }
                        }
                    }
                    if m.place == .bath {
                        // Once in the cell, shuffle to the fixture itself: under the nozzle, or in front of the bowl.
                        if settled, let spot = m.fetchSpot {
                            let d = spot - m.pos
                            if (d.x * d.x + d.y * d.y).squareRoot() > 0.03 { m.pos += d * min(1, dt * 5); continue }
                            m.fetchSpot = nil
                        }
                        if settled {
                            m.setStatic(true, frame: Int(clock * 12))
                            if m.showering, clock >= m.nextDropAt, let bath = station.rooms["kind:bath"] {
                                // Pixel water from the nozzle, falling past the shoulders onto the drain.
                                m.nextDropAt = clock + 0.05
                                let nozzle = showerNozzle(station: station, bath: bath)
                                let drop = SCNNode(geometry: SCNBox(width: 0.035, height: 0.06, length: 0.035, chamferRadius: 0))
                                drop.geometry!.firstMaterial = flat(NSColor(rgb: (0.62, 0.82, 0.95)))
                                drop.position = v3(nozzle.x + Double.random(in: -0.05...0.05), 0.56, nozzle.y + Double.random(in: -0.05...0.05))
                                propRoot.addChildNode(drop)
                                let fall = SCNAction.move(to: v3(drop.position.x, 0.02, drop.position.z), duration: 0.32); fall.timingMode = .easeIn
                                drop.runAction(.sequence([fall, .fadeOut(duration: 0.08), .removeFromParentNode()]))
                            }
                        }
                        if clock >= m.phaseUntil && settled {   // done; work waits its turn
                            m.setStatic(false, frame: 0)
                            m.fixture = nil
                            var back = restPlace(m)
                            if !m.busy, case .bath(_, let where_) = m.current?.kind { back = where_ }
                            send(m, to: back)
                        }
                    } else if m.bathDue > 0, clock >= m.bathDue, !m.busy, !m.onJob, m.carried == nil, !m.isSubagent, m.place != .quarters, settled, station.rooms["kind:bath"] != nil {
                        // One to a fixture: the shower or the bowl, whichever is free; both taken, wait.
                        let taken = Set(minions.values.filter { $0.id != m.id && $0.station == m.station && $0.bathing }.compactMap(\.fixture))
                        let want = m.showering ? 1 : 0
                        guard let fixture = [want, 1 - want].first(where: { !taken.contains($0) }) else { continue }
                        m.showering = fixture == 1
                        m.fixture = fixture
                        // Off to the bath for a moment, then back to wherever it was.
                        m.bathDue = 0
                        let back = m.place
                        send(m, to: .bath)
                        start(m, .bath(m.showering ? .shower : .quick, back: back))
                        m.phaseUntil = clock + (m.showering ? 10 : 6)
                        // Toilet in the near corner, shower in the far one: pick one and walk to it, facing the fixture.
                        if let bath = station.rooms["kind:bath"] {
                            let cells = bath.cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                            let cell = m.showering ? (cells.count > 1 ? cells[1] : cells.last!) : cells.first!
                            m.path = station.path(from: m.pos, to: cell)
                            // Then the exact spot: under the nozzle, or a step in front of the bowl, facing it.
                            let nozzle = showerNozzle(station: station, bath: bath)
                            m.fetchSpot = m.showering ? SIMD2(nozzle.x - station.offset.x, nozzle.y - station.offset.y)
                                                      : SIMD2(Double(cell.x) - 0.02, Double(cell.y) + 0.1)
                            m.facing = m.showering ? .pi / 4 : -.pi * 3 / 4
                        }
                    }
                    if let pc = m.pyramidCell, !m.onJob, m.place == .room(m.home.key) {
                        if abs(m.cell.x - pc.x) + abs(m.cell.y - pc.y) > 1 { walk(m, to: pc) }
                    } else if clock >= m.nextWanderAt, m.activity != .sleeping, !m.bathing, m.place != .quarters, !(m.place == .lounge && m.couch != nil), !jumping {
                        let choices = station.cells(of: m.place).filter { $0 != m.cell }
                        if let dest = choices.randomElement() { m.path = station.path(from: m.pos, to: dest) }
                        m.nextWanderAt = clock + (pacing ? Double.random(in: 2.5...6) : m.busy ? Double.random(in: 2...5) : Double.random(in: 8...20))
                    }
                case .leaving:
                    m.opacity -= dt * 1.5
                    if m.opacity <= 0 { despawn(m); continue }
                }
            }
            if m.state != .leaving { m.opacity = min(1, m.opacity + dt * 2) }
            var bunkLift = 0.0
            // Seats and beds draw a minion in only while it has nothing else to do.
            if m.path.isEmpty, m.isResting, m.place == .lounge, let c = m.couch, c < station.couches.count {
                m.pos += (station.couches[c] - m.pos) * min(1, dt * 4)
            }
            if m.path.isEmpty, m.isResting, m.place == .quarters {
                if let b = m.bed, b < station.beds.count {
                    m.pos += (station.beds[b].pos - m.pos) * min(1, dt * 4)
                    bunkLift = station.beds[b].level == 1 ? 0.36 : 0
                }
            }
            let resting = m.path.isEmpty && m.state == .settled
            if resting && m.activity == .sleeping && m.place == .quarters { m.setSleeping(true) }
            let jump = jumping && resting && m.place != .lounge ? abs(sin(clock * 7 + m.bobPhase)) * 0.14 : 0
            m.node.position = v3(station.offset.x + m.pos.x, jump + bunkLift, station.offset.y + m.pos.y)
            m.shadow.position.y = CGFloat(0.003 - jump)   // the shadow stays on the floor while the body hops
            m.node.opacity = m.opacity
            let working = m.busy && resting && !m.isSubagent && m.activity != .waiting
            let inBed = m.bed != nil && m.place == .quarters && m.path.isEmpty
            let wantFacing = inBed ? 0 : (m.path.isEmpty ? Double(rig.eulerAngles.y) : m.facing)
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
                // Working the cone: welding, hammering, pushing and pulling, or bent over it.
                let tool = m.toolSlot(at: clock)
                let cone = m.pyramids.last
                m.setTool([Minion.Tool.goggles, .hammer, .scanner, .flashlight][tool])
                switch tool {
                case 0:
                    tilt = 0.32
                    if m.weldLight == nil {
                        let l = SCNNode()
                        l.light = SCNLight(); l.light!.type = .omni; l.light!.color = NSColor(rgb: (1.0, 0.85, 0.55)); l.light!.attenuationEndDistance = 2.5
                        let spark = SCNNode(geometry: SCNPlane(width: 0.08, height: 0.08))
                        spark.geometry!.firstMaterial = flat(NSColor(rgb: (1.0, 0.95, 0.8)))
                        spark.constraints = [SCNBillboardConstraint()]
                        l.addChildNode(spark)
                        propRoot.addChildNode(l)
                        m.weldLight = l
                    }
                    if let l = m.weldLight, let cone {
                        l.position = v3(cone.position.x + CGFloat(station.offset.x), 0.25, cone.position.z + CGFloat(station.offset.y))
                        let on = Double.random(in: 0...1) < 0.55
                        l.light?.intensity = on ? Double.random(in: 300...1200) : 0
                        l.opacity = on ? 1 : 0
                    }
                case 1:
                    // Quick drop onto the peak, slower lift back: the grip pitches, the body only leans a little.
                    let phase = (t * 1.1).truncatingRemainder(dividingBy: 1)
                    let swing = phase < 0.25 ? pow(phase / 0.25, 2) : 1 - pow((phase - 0.25) / 0.75, 1.5)
                    m.hammerPivot?.eulerAngles.x = Minion.hammerRest + (Minion.hammerStrike - Minion.hammerRest) * swing
                    tilt = swing * 0.14
                    if swing > 0.97 && !m.hammerUp { m.hammerUp = true; drone.thud(); cone?.runAction(.sequence([.scale(to: 0.85, duration: 0.05), .scale(to: 1, duration: 0.25)])) }
                    if swing < 0.2 { m.hammerUp = false }
                case 2:
                    lean = sin(t * 2.5) * 0.05
                    tilt = 0.12 + sin(t * 2.5) * 0.08
                default:
                    // Inspecting the cone by torchlight: the beam wanders over it.
                    tilt = 0.18 + sin(t * 1.5) * 0.04
                    m.lightPivot?.eulerAngles = SCNVector3(0.35 + sin(t * 1.3) * 0.25, sin(t * 0.9) * 0.45, 0)
                }
            }
            if !atCone || m.toolSlot(at: clock) != 0, let l = m.weldLight { l.removeFromParentNode(); m.weldLight = nil }
            if !working && !(m.place == .lounge && resting && m.couch != nil) && palletErrand(of: m) == nil { m.setTool(nil) }
            if m.place == .lounge, resting, let lounge = station.rooms["kind:lounge"] {
                let cx = Double(lounge.cells.map(\.x).reduce(0, +)) / Double(lounge.cells.count)
                let cy = Double(lounge.cells.map(\.y).reduce(0, +)) / Double(lounge.cells.count)
                let toTable = SIMD2(cx, cy) - m.pos
                m.smoothFacing = atan2(toTable.x, toTable.y)
                tilt = (m.couch != nil ? -0.22 : 0) + sin(t * 2.2) * 0.05   // sat back on a couch, or standing at the table
                roll = sin(t * 1.3) * 0.04
                if m.couch != nil { m.setTool(.tablet); tilt = 0.12 + sin(t * 1.6) * 0.04 }   // reading on the couch
            }
            if working && !atCone {
                switch m.activity {
                case .testing, .running: m.setTool(.scanner); m.blinkScanner(Int(clock * 6) % 2 == 0)
                case .exploring: m.setTool(.flashlight)
                case .coding, .reading, .writing, .qa, .planning, .skill: m.setTool(.tablet)
                default: m.setTool(nil)
                }
                switch m.activity {
                case .coding: tilt = sin(t * 14) * 0.06                       // typing: quick nods
                case .exploring:                                              // reading code: the torch plays over the boxes
                    tilt = 0.12; spin = sin(t * 1.2) * 0.7
                    m.lightPivot?.eulerAngles = SCNVector3(0.3 + sin(t * 1.7) * 0.2, sin(t * 0.8) * 0.3, 0)
                case .writing: tilt = 0.2 + sin(t * 3) * 0.06                 // writing: head down over the clipboard, small nods
                case .thinking: tilt = -0.18; roll = sin(t * 1.4) * 0.14      // thinking: head back, slow sway
                case .planning: tilt = -0.12 + sin(t * 2) * 0.05              // planning: looking up
                case .reading: tilt = -0.18                                   // reading your message: head back
                case .testing: spin = sin(t * 1.6) * 0.6; tilt = 0.1         // testing: sweeping the scanner across
                case .running: tilt = sin(t * 22) * 0.04; roll = cos(t * 19) * 0.04   // running things: jittery
                case .shipping: roll = sin(t * 9) * 0.16                      // shipping: excited wiggle
                case .skill: tilt = 0.15; roll = sin(t * 3) * 0.05           // using a skill: heads-down on the tablet
                case .delegating: spin = sin(t * 4) * 0.3                     // delegating: glancing about
                case .qa:
                    // QA on the test deck: facing a stack, the scanner sweeping it from the floor to the top, a tick now and then.
                    tilt = 0.08 + sin(t * 1.4) * 0.22; spin = 0
                    if Int(t * 2) % 9 == 0 && Int((t - dt) * 2) % 9 != 0 {
                        let tick = SCNNode(geometry: SCNBox(width: 0.16, height: 0.02, length: 0.16, chamferRadius: 0))
                        tick.eulerAngles = SCNVector3(Double.pi / 2, 0, Double.pi / 4)
                        tick.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.9, 0.45)))
                        tick.position = v3(m.node.position.x, m.headHeight + 0.2, m.node.position.z)
                        propRoot.addChildNode(tick)
                        tick.runAction(.sequence([.group([.moveBy(x: 0, y: 0.5, z: 0, duration: 0.9), .sequence([.wait(duration: 0.5), .fadeOut(duration: 0.4)])]), .removeFromParentNode()]))
                        drone.ping(seed: m.id.hashValue)
                    }
                default: roll = sin(t * 5) * 0.07
                }
            }
            if clock < m.wonderUntil { tilt = -0.15; roll = 0; spin = 0 }   // a beat of wondering
            switch m.posture {
            case .none: m.tilt.position.y = 0
            case .crouch: tilt = max(tilt, 0.28); roll = 0; m.tilt.position.y = -0.12   // knees bent, not a bow
            case .waist: tilt = max(tilt, 0.14); roll = 0; m.tilt.position.y = 0       // waist height: a lean, no crouch
            case .reach: tilt = min(tilt, -0.18); roll = 0; m.tilt.position.y = 0.05   // up on the toes, head back
            case .jump:                                                               // a little hop to reach the top of a tall stack
                let hop = m.phaseUntil > 0 ? max(0, sin((m.phaseUntil - clock) / 1.1 * .pi)) * 0.28 : 0
                tilt = min(tilt, -0.12); roll = 0; m.tilt.position.y = hop
            }
            m.node.eulerAngles = SCNVector3(0, m.smoothFacing + spin, 0)
            m.tilt.eulerAngles = SCNVector3(tilt, 0, roll)
            if lean != 0 { m.node.position.x += CGFloat(sin(m.smoothFacing) * lean); m.node.position.z += CGFloat(cos(m.smoothFacing) * lean) }
        }
    }
}
