// What a worker is told to do: the command phases, walking, hauling, deliveries and the crew.

import AppKit
import SceneKit

extension StationController {
    // MARK: minions and props

    func spawnMinion(_ s: SessionInfo, station: String, home: Home) -> Minion {
        let st = fleet.stations[station]
        // Straight into its own office when there is one, each on a cell of its own; subagents at the monolith.
        let start: Cell
        if s.isSubagent { start = st?.coreCenter ?? Cell(x: 0, y: 0) }
        else if let cells = st?.rooms[home.key]?.cells, !cells.isEmpty { start = cells[minions.count % cells.count] }
        else { start = st?.hangarCells.first ?? st?.cells(of: .quarters).randomElement() ?? Cell(x: 0, y: 0) }
        let m = Minion(id: s.id, station: station, home: home, cwd: s.cwd, toolCount: s.toolCount, isSubagent: s.isSubagent, start: start)
        m.markers = s.eventMarkers
        m.promptCount = s.promptCount
        minionRoot.addChildNode(m.node)
        minions[s.id] = m
        return m
    }

    func despawn(_ m: Minion) {
        if let key = carriedRoom(of: m) { reveal(key) }
        // A crate on its arms goes down where it stands, and the carry waits for someone else.
        simulation.forget(m)
        mirrorLoad(m)
        m.carried?.removeFromParentNode()
        m.pyramids.forEach { $0.removeFromParentNode() }
        m.queuedCones.forEach { $0.removeFromParentNode() }
        m.weldLight?.removeFromParentNode()
        m.node.removeFromParentNode()
    }

    func carriedRoom(of m: Minion) -> String? {
        if case .deliverOffice(let id) = m.current?.kind { return world.truth.deliveries[id]?.key }
        return nil
    }

    // MARK: the simulation's side of a body

    /// The orders, the rest and the walks are the simulation's (`Simulation.swift`); the scene asks
    /// for them here by the names it always used.
    func start(_ m: Minion, _ c: Command, announce: Bool = false) { simulation.start(m, c, announce: announce) }
    private func assign(_ m: Minion, _ c: Command, announce: Bool = false) { simulation.start(m, c, announce: announce) }
    func handOver(_ m: Minion, _ c: Command, announce: Bool = false) { simulation.handOver(m, c, announce: announce) }
    func issue(_ c: Command, by who: String, announce: Bool = false) { simulation.issue(c, by: who, announce: announce) }
    func advance(_ m: Minion) { simulation.advance(m) }
    func finish(_ m: Minion, to place: Place? = nil) { simulation.finish(m, to: place) }
    func dismiss(_ m: Minion) { simulation.dismiss(m) }
    func isNight(_ station: Station) -> Bool { simulation.isNight(station) }
    func restPlace(_ m: Minion) -> Place { simulation.restPlace(m) }
    func resettle(_ station: Station) { simulation.resettle(station) }
    func send(_ m: Minion, to place: Place) { simulation.send(m, to: place) }
    func walk(_ m: Minion, to cell: Cell) { simulation.walk(m, to: cell) }
    func route(_ m: Minion, to cell: Cell, round blocker: String? = nil) -> [SIMD2<Double>] { simulation.route(m, to: cell, round: blocker) }
    func standCell(_ st: Station, near cell: Cell) -> Cell { simulation.standCell(st, near: cell) }
    @discardableResult func visitBath(_ m: Minion, station: Station) -> Bool { simulation.visitBath(m, station: station) }
    @discardableResult func takeTurnInGym(_ m: Minion, station: Station, gym: Room) -> Bool { simulation.takeTurnInGym(m, station: station, gym: gym) }
    @discardableResult func startRoam(_ m: Minion, station: Station) -> Bool { simulation.startRoam(m, station: station) }
    func react(_ m: Minion, _ activity: Activity, place: Place, minutes: Double, words: String) { simulation.react(m, activity, place: place, minutes: minutes, words: words) }
    func crewRested(_ m: Minion) { simulation.crewRested(m) }

    /// Everything a body is doing, to the log, on request (`kill -USR1`): the way to see the station
    /// from outside when a picture looks wrong.
    func dumpState() {
        StationLog.write("dump", "--- state at station clock \(Int(clock)) ---")
        for m in minions.values.sorted(by: { $0.home.name < $1.home.name }) {
            let job = m.current.map { "\($0.words) · \(m.phaseKind)" } ?? "nothing"
            let spot = m.fetchSpot.map { " fetchSpot \(Int($0.x.rounded())),\(Int($0.y.rounded()))" } ?? ""
            let more = [m.carried != nil ? "carrying" : nil, m.waitingOn.map { "waiting on \($0)" }, m.pending.map { "pending: \($0.words)" },
                        m.wakeUntil > 0 ? "waking" : nil, m.busy ? "busy" : nil, m.isCrew ? "crew" : nil, m.wedged ? "wedged" : nil].compactMap { $0 }
            StationLog.write("dump", "\(m.home.name) [\(m.station)]: \(job) at \(m.cell.x),\(m.cell.y) path \(m.path.count)\(spot) \(more.joined(separator: ", "))")
        }
        StationLog.write("dump", "boxes on the floor: \(boxes.keys.sorted().joined(separator: ", "))")
        StationLog.write("dump", "pending offices: \(world.truth.pendingOffices.sorted().joined(separator: ", "))")
        for d in world.truth.deliveries.values.sorted(by: { $0.id < $1.id }) {
            StationLog.write("dump", "delivery \(d.id): \(d.key) slot \(d.slot) \(d.landed ? "on the floor" : "in the air") for \(d.session ?? "-")")
        }
        for s in shuttles { StationLog.write("dump", "shuttle: \(s.command.words) phase \(s.phaseKind)") }
        for st in fleet.stations.values {
            for c in st.ledger.allCrates.sorted(by: { ($0.repo, $0.number) < ($1.repo, $1.number) }) {
                StationLog.write("dump", "crate \(c.repo)#\(c.number): wanted \(c.wanted.map(\.words) ?? "nowhere") placed \(c.placed.map(\.words) ?? "nowhere")\(c.heading.map { " heading \($0.words)" } ?? "")\(c.movedAt != nil ? " moved by hand" : "")")
            }
        }
        for (id, job) in cargo { StationLog.write("dump", "cargo \(id): \(job.command.words) carrier \(job.carrier ?? "none") aim \(job.aim.cell.x),\(job.aim.cell.y) at \(String(format: "%.2f,%.2f", job.aim.pos.x, job.aim.pos.z))") }
    }

    /// How many shuttles are over a station's bay right now: the flights in the air, nothing else.
    func shipsInFlight(_ station: String) -> Int { shuttles.filter { $0.station == station }.count }

    /// A new worker arrives by shuttle: it stays invisible until the ship has set down, then steps out.
    func arriveByShuttle(_ m: Minion) {
        guard let station = fleet.stations[m.station], station.hasHangar, let anchor = hangarAnchors[m.station] else { return }
        let slotIndex = shipsInFlight(m.station) % station.hangarSlots.count
        let slot = station.hangarSlots[slotIndex]
        m.pos = slot
        m.opacity = 0
        m.node.opacity = 0
        m.wakeUntil = clock + 8.1   // held until the ship lands
        let ship = shuttle(color: NSColor(fleet.color(forRepo: m.home.repo)))
        let local = SIMD3(slot.x - station.hangarCenter.x, 0, slot.y - station.hangarCenter.y)
        let corners: [SIMD3<Double>] = [SIMD3(12, 9, 12), SIMD3(-12, 9, 12), SIMD3(12, 9, -12), SIMD3(-12, 9, -12)]
        let start = local + corners.randomElement()!, high = local + SIMD3(0, 5, 0), down = local + SIMD3(0, 0.55, 0), exit = local + corners.randomElement()!
        ship.position = v3(start.x, start.y, start.z)
        anchor.addChildNode(ship)
        let command = Command.flight(.bringWorker(m.id), station: m.station, slot: slotIndex,
                                     what: "a new worker for \(m.home.name)")
        launch(Shuttle(node: ship, station: m.station, command: command, high: high, down: down, exit: exit,
                       restYaw: nil, drift: 0, unloadAt: 0.6, unloadFor: 1.0) { [weak m] in
            m?.opacity = 1
            m?.wakeUntil = 0
        })
        drone.sweep(up: false)
    }

    /// The shuttle body, wings in a repo colour.
    private func shuttle(color: NSColor) -> SCNNode {
        let ship = SCNNode()
        let hull = SCNNode(geometry: SCNBox(width: 0.7, height: 0.14, length: 0.4, chamferRadius: 0.03))
        hull.geometry!.firstMaterial = lit(NSColor(rgb: (0.85, 0.86, 0.9)))
        ship.addChildNode(hull)
        let cockpit = SCNNode(geometry: SCNBox(width: 0.2, height: 0.1, length: 0.2, chamferRadius: 0.02))
        cockpit.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.75, 1.0)))
        cockpit.position = v3(0.16, 0.11, 0)
        ship.addChildNode(cockpit)
        for side in [-1.0, 1.0] {
            let wing = SCNNode(geometry: SCNBox(width: 0.28, height: 0.05, length: 0.34, chamferRadius: 0))
            wing.geometry!.firstMaterial = lit(color)
            wing.position = v3(-0.14, 0, side * 0.34)
            ship.addChildNode(wing)
        }
        for side in [-1.0, 1.0] {
            let skid = SCNNode(geometry: SCNBox(width: 0.5, height: 0.03, length: 0.03, chamferRadius: 0))
            skid.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.3, 0.35)))
            skid.position = v3(0, -0.14, side * 0.16)
            ship.addChildNode(skid)
        }
        return ship
    }

    /// Hands a flight to a new shuttle: the log and the panel see the command, the tick flies it.
    private func launch(_ ship: Shuttle) {
        issue(ship.command, by: "shuttle", announce: true)
        ship.begin(at: clock)
        shuttles.append(ship)
    }

    /// One frame of every flight in the air.
    func tickShuttles() {
        shuttles.removeAll { !$0.advance(at: clock) }
    }

    /// A shuttle descends slowly onto a free hangar slot, sets down a crate, and lifts away.
    /// Everything is parented to the hangar anchor, so a station shifting underneath does not misalign it.
    func startDelivery(_ m: Minion, roomKey: String) {
        guard let station = fleet.stations[m.station], station.hasHangar, let room = station.rooms[roomKey],
              let anchor = hangarAnchors[m.station] else { return }
        let key = "\(station.name)|\(roomKey)"
        // A slot with nothing on it and no ship bound for it; every slot taken, the least recently ordered.
        let slotIndex = world.truth.freeSlots(station: station.name, of: station.hangarSlots.count).first
            ?? shipsInFlight(m.station) % station.hangarSlots.count
        let order = world.truth.orderDelivery(station: station.name, roomKey: roomKey, slot: slotIndex, session: m.id)
        let slotLocal = station.hangarSlots[slotIndex] - station.hangarCenter
        let slot = SIMD3(slotLocal.x, 0, slotLocal.y)

        let box = Props.crate(color: NSColor(room.color))
        box.position = v3(slot.x, 0.09, slot.z)
        box.opacity = 0
        box.name = "room:" + key
        anchor.addChildNode(box)
        boxes[key] = box

        let ship = shuttle(color: NSColor(room.color))
        let corners: [SIMD3<Double>] = [SIMD3(12, 9, 12), SIMD3(-12, 9, 12), SIMD3(12, 9, -12), SIMD3(-12, 9, -12)]
        let start = slot + corners.randomElement()!
        let high = slot + SIMD3(0, 5.0, 0)
        let down = slot + SIMD3(0, 0.55, 0)
        let exit = slot + corners.randomElement()! * SIMD3(1, 0.9, 1)
        ship.position = v3(start.x, start.y, start.z)
        ship.look(at: v3(high.x, high.y, high.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(1, 0, 0))
        anchor.addChildNode(ship)
        let command = Command.flight(.dropCrate(order: order), station: m.station, slot: slotIndex,
                                     what: "the office for \(room.name)")
        let flight = Shuttle(node: ship, station: m.station, command: command, high: high, down: down, exit: exit,
                             restYaw: Double.random(in: 0..<(2 * .pi)), drift: Double.random(in: -0.6...0.6),
                             unloadAt: 0.8, unloadFor: 1.2) { [weak self] in
            box.opacity = 1
            box.position = v3(slot.x, 0.42, slot.z)
            self?.moveCrate(box, legs: [MotionLeg(to: SIMD3(slot.x, 0.09, slot.z), seconds: 0.5, ease: .easeIn)])
            self?.world.truth.crateLanded(order: order)   // on the floor now: it will be fetched, by whoever is free
        }
        // A hard sequence: the crate comes out only once its carrier stands at the slot. With no carrier
        // left for it, the ship unloads anyway and the crate waits on the floor.
        let spot = station.hangarSlots[slotIndex], stationName = m.station
        flight.ready = { [weak self] in
            guard let self, let carrier = self.minions.values.first(where: { o in
                guard o.station == stationName, case .deliverOffice(let k) = o.current?.kind else { return false }
                return k == order
            }) else { return true }
            return carrier.path.isEmpty && hypot(carrier.pos.x - spot.x, carrier.pos.y - spot.y) < 1.3
        }
        launch(flight)
        drone.sweep(up: false)
        assign(m, .deliverOffice(order: order, name: room.name), announce: false)
        m.place = .hangar
        m.fetchSpot = station.hangarSlots[slotIndex]
        walk(m, to: station.hangarCells[min(station.hangarCells.count - 1, slotIndex * 2)])
    }

    /// Archiving: boxes shrink away, whoever is inside steps out into the hallway, and the room
    /// detaches, sinks and fades. The model drops the room at once; only the visuals linger.
    func archive(station: String, key: String, roomKey: String, name: String, hall: Cell?, announce: Bool, reason: String) {
        simulation.cancelCarries(roomKey: key)
        for m in minions.values where m.station == station && m.home.key == roomKey { clearPyramids(m) }
        stationAnchors[station]?.childNodes.filter { $0.name == "room:" + key }.forEach { $0.removeFromParentNode() }
        world.forgetOffice(key)
        world.truth.officeDelivered(key)
        outlines.removeValue(forKey: key)?.removeFromParentNode()
        boxes.removeValue(forKey: key)?.removeFromParentNode()
        if announce {
            // The reverse of the unfold: the name goes first, then the floor rolls up toward the
            // doorway tile by tile, into a hex that drops through the floor where the crate once stood.
            // The room is already off the floor plan: the doorway is the tile beside the corridor
            // (the one outside is `hall`), and the colour is the tiles' own.
            let st = fleet.stations[station]
            let tiles = roomTiles[key] ?? []
            let ox = st?.offset.x ?? 0, oz = st?.offset.y ?? 0
            func cellOf(_ t: SCNNode) -> Cell { Cell(x: Int((Double(t.position.x) - ox).rounded()), y: Int((Double(t.position.z) - oz).rounded())) }
            let tileCells = tiles.map(cellOf)
            var door: Cell? = tileCells.first
            if let h = hall, let d = tileCells.first(where: { abs($0.x - h.x) + abs($0.y - h.y) == 1 }) { door = d }
            let color = tiles.first?.geometry?.firstMaterial?.diffuse.contents as? NSColor
            let ghost = SCNNode()
            for t in tiles { t.removeFromParentNode(); ghost.addChildNode(t) }
            if let l = roomLabels[key] { l.removeFromParentNode(); ghost.addChildNode(l); roomLabels[key] = nil; l.runAction(.fadeOut(duration: 0.4)) }
            for b in markerRoot.childNodes where b.name == "box:" + key {
                b.runAction(.sequence([.scale(to: 0.01, duration: 0.5), .removeFromParentNode()]))
            }
            propRoot.addChildNode(ghost)
            func dist(_ t: SCNNode) -> Double {
                guard let door else { return 0 }
                let c = cellOf(t)
                return Double(abs(c.x - door.x) + abs(c.y - door.y))
            }
            let furthest = tiles.map(dist).max() ?? 0
            var last = 0.0
            for t in tiles {
                let at = 0.5 + (furthest - dist(t)) * 0.1
                last = max(last, at + 0.5)
                t.runAction(.sequence([.wait(duration: at), .fadeOut(duration: 0.6)]))
            }
            if let st, let color, let door {
                let hex = Props.crate(color: color)
                hex.position = v3(st.offset.x + Double(door.x), 0.09, st.offset.y + Double(door.y))
                hex.scale = SCNVector3(0.01, 0.01, 0.01)
                ghost.addChildNode(hex)
                let grow = SCNAction.scale(to: 1, duration: 0.35); grow.timingMode = .easeOut
                let sink = SCNAction.moveBy(x: 0, y: -3, z: 0, duration: 1.6); sink.timingMode = .easeIn
                hex.runAction(.sequence([.wait(duration: last - 0.2), grow, .wait(duration: 0.4), sink]))
                last += 0.35 + 0.4 + 1.6
            }
            ghost.runAction(.sequence([.wait(duration: last), .removeFromParentNode()]))
            if let hall, let st {
                for m in minions.values where m.station == station && m.place == .room(roomKey) {
                    m.path = st.path(from: m.pos, to: hall)
                    m.place = .core   // parked in the hallway until the next scan sends it on
                    m.nextWanderAt = clock + 4
                    m.strollUntil = clock + 8   // out at a walk, not a run
                }
            }
            logEvent("archived: \(name)" + (reason.isEmpty ? "" : " · \(reason)"))
        }
        roomTiles[key] = nil
    }

    func reveal(_ key: String) {
        // The crate that was set down hands over to the office's own package: it fades out on its slot
        // over the same beat the office fades in, rather than blinking away.
        // The crate folds open where it stands, and the office unfolds out of it: tile by tile away
        // from the doorway until the plot is filled, then the name fades in.
        let parts0 = key.split(separator: "|", maxSplits: 1).map(String.init)
        let station0 = parts0.count == 2 ? fleet.stations[parts0[0]] : nil
        let door = station0?.doorCell(of: parts0[1])
        if let crate = boxes.removeValue(forKey: key) {
            let fold = SCNAction.scale(to: 0.01, duration: 0.35); fold.timingMode = .easeIn
            crate.runAction(.sequence([fold, .removeFromParentNode()]))
        }
        if let o = outlines.removeValue(forKey: key) { o.runAction(.sequence([.fadeOut(duration: 0.4), .removeFromParentNode()])) }
        guard world.truth.officeDelivered(key) else { return }
        var furthest = 0.0
        for t in roomTiles[key] ?? [] {
            let cx = Double(t.position.x) - (station0?.offset.x ?? 0), cz = Double(t.position.z) - (station0?.offset.y ?? 0)
            let d = door.map { abs(cx - Double($0.x)) + abs(cz - Double($0.y)) } ?? 0
            furthest = max(furthest, d)
            t.opacity = 0
            t.runAction(.sequence([.wait(duration: 0.3 + d * 0.1), .fadeIn(duration: 0.6)]))
        }
        let after = 0.3 + furthest * 0.1 + 0.5
        roomLabels[key]?.runAction(.sequence([.wait(duration: after), .fadeIn(duration: 0.5)]))
        // Cones that arrived while the plot was still empty land once the floor is there.
        self.after(after) { [weak self] in
            guard let self else { return }
            for m in self.minions.values where m.station + "|" + m.home.key == key && m.owedCones > 0 {
                for _ in 0..<m.owedCones { self.addPyramid(for: m) }
                m.owedCones = 0
            }
        }
        markerRoot.childNodes.filter { $0.name == "box:" + key }.forEach { $0.runAction(.sequence([.wait(duration: after), .fadeIn(duration: 0.4)])) }
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]] {
            logEvent("new office: \(room.name)")
        }
    }

    /// Where a session's cones stand: its office's clear cells, nearest the door first. The crates hold
    /// the far corners and the writing is left alone.
    func coneCells(for m: Minion) -> (station: Station, key: String, cells: [Cell])? {
        guard let station = fleet.stations[m.station], case .room(let key) = Place.forActivity(.reading, home: m.home.key, isSubagent: false),
              !key.hasPrefix("kind:") else { return nil }   // prompts only land in an office
        let cells = station.cells(of: .room(key))
        guard let firstCell = cells.first else { return nil }   // the office is gone
        // Clear of crates and writing. Cones are not in the way of cones: the row is the same whatever
        // stands in it, or it would shuffle every time it was looked at.
        let written = labelCells["\(m.station)|\(key)"] ?? []
        let full = "\(m.station)|\(key)"
        let crated = Set(markerRoot.childNodes.filter { $0.name == "box:" + full }.map {
            Cell(x: Int((Double($0.position.x) - station.offset.x).rounded()), y: Int((Double($0.position.z) - station.offset.y).rounded()))
        })
        let clear = cells.filter { c in !crated.contains(c) && !written.contains(c) }
        let door = station.doorCell(of: key) ?? firstCell
        let nearDoor = (clear.isEmpty ? cells : clear).sorted { (abs($0.x - door.x) + abs($0.y - door.y)) < (abs($1.x - door.x) + abs($1.y - door.y)) }
        return (station, key, nearDoor)
    }

    /// The queue moved up: each queued cone slides to its place in the row.
    func arrangeQueuedCones(_ m: Minion) {
        guard let (_, _, cells) = coneCells(for: m), !cells.isEmpty else { return }
        for (i, q) in m.queuedCones.enumerated() {
            let cell = cells[min(cells.count - 1, 1 + i)]
            let to = v3(Double(cell.x), 0, Double(cell.y))
            guard abs(q.position.x - to.x) > 0.01 || abs(q.position.z - to.z) > 0.01, !q.hasActions else { continue }
            let slide = SCNAction.move(to: to, duration: 0.4); slide.timingMode = .easeInEaseOut
            q.runAction(slide)
        }
    }

    func addPyramid(for m: Minion, queued: Bool = false) {
        guard let (station, key, nearDoor) = coneCells(for: m) else { return }
        // Nothing on the plot before the office has unfolded: the cone is owed, and lands with the reveal.
        if undelivered.contains(m.station + "|" + key) { m.owedCones += 1; return }
        guard !nearDoor.isEmpty else { return }
        // One cone is the message being worked, on the cell nearest the door. Queued messages stand
        // in a row behind it, in the order they will be taken. A new message shrinks the old one away.
        if !queued { clearPyramids(m) }
        let cell = nearDoor[min(nearDoor.count - 1, queued ? 1 + m.queuedCones.count : 0)]
        let tint = station.rooms[key].map { NSColor($0.color).lighter(0.22) } ?? Palette.pyramid
        let floorColor = station.rooms[key].map { NSColor($0.color) } ?? Palette.corridor
        let n = Props.pyramid(color: tint, size: 0.32, floor: floorColor)
        let ox = 0.0, oz = 0.0
        n.position = v3(Double(cell.x) + ox, -0.35, Double(cell.y) + oz)
        let rise = SCNAction.move(to: v3(Double(cell.x) + ox, 0, Double(cell.y) + oz), duration: 0.5)
        rise.timingMode = .easeOut
        n.runAction(rise)
        n.name = "room:\(station.name)|\(key)"
        let anchor = stationAnchors[station.name] ?? { let a = SCNNode(); a.position = v3(station.offset.x, 0, station.offset.y); propRoot.addChildNode(a); stationAnchors[station.name] = a; return a }()
        anchor.addChildNode(n)
        if queued {
            n.opacity = 0.35
            m.queuedCones.append(n)
            return
        }
        m.pyramids.append(n)
        m.pyramidCell = cell
        refreshObstacles()
        guard !m.onJob else { return }
        m.place = .room(key)
        // Working the message is a job like any other: it shows in the log and on hover.
        if m.isResting { start(m, Command(kind: .work(office: key), words: "working your message in \(m.home.name)")) }
        walk(m, to: cell)
    }

    /// Worked: the cone shrinks away where it stands.
    func clearPyramids(_ m: Minion) {
        for p in m.pyramids {
            let shrink = SCNAction.scale(to: 0.01, duration: 0.35); shrink.timingMode = .easeIn
            p.runAction(.sequence([shrink, .removeFromParentNode()]))
        }
        m.pyramids = []
        m.pyramidCell = nil
        refreshObstacles()
    }

    func ringBell(seed: Int) {
        guard clock - lastPing > 0.25 else { return }
        lastPing = clock
        drone.ping(seed: seed)
    }

    // MARK: hauling

    /// Takes a carry command and the crate it moves. The simulation speaks for the crate from here on;
    /// the node is what the scene lifts when the carrier's body says the crate is on its arms.
    func carry(_ command: Command, node: SCNNode, roomKey: String = "", onDone: @escaping () -> Void) {
        guard simulation.carry(command, roomKey: roomKey, onDone: onDone) else { return }
        node.name = "haul"
        cargoNodes[command.id] = node
    }

    /// The node a crate stands on in the rows, by the name the yard gave it.
    func crateNode(_ crate: CrateRef) -> SCNNode? {
        let tail = ":\(crate.station)|\(crate.repo)|\(crate.number)"
        return markerRoot.childNodes.first { ($0.name ?? "") == "storage" + tail || ($0.name ?? "") == "deck" + tail }
    }

    /// Merged: the office's package is carried to the storage bay in one trip. The model has already
    /// noted that the office is free to clear; this only moves what is on the floor.
    func haulMergedBoxes(station: Station, key: String, roomName: String, repo: String, number: Int) {
        guard let pkg = markerRoot.childNodes.first(where: { $0.name == "box:" + key }),
              let room = station.rooms[key.split(separator: "|", maxSplits: 1).map(String.init).last ?? ""] else { return }
        logEvent("\(roomName): merged, package to storage")
        // The order names the office; the carry starts from where the package actually stands.
        let at = pkg.position
        let exact = Spot(area: .office, station: station.name, owner: room.key, label: room.name,
                         cell: Cell(x: Int((Double(at.x) - station.offset.x).rounded()), y: Int((Double(at.z) - station.offset.y).rounded())),
                         pos: SIMD3(Double(at.x), Double(at.y), Double(at.z)))
        let command = world.carryToStorage(station: station, room: room, repo: repo, number: number).from(exact)
        carry(command, node: pkg, roomKey: key) { [weak self] in
            guard let self else { return }
            world.landed(station: station, repo: repo, number: number, in: .storage, at: now)
            pkg.removeFromParentNode()
            rebuildMarkers()
            refreshRockets()
            // Every merge ships: the crate goes up at once, in a rocket of its own.
            if world.shipsOnMerge(station: station.name, repo: repo) { launchOnMerge(station: station, repo: repo) }
        }
    }

    /// A staging release merged: the repo's storage crates are carried to the test deck. Without
    /// commands from the reconciler, every crate of the repository belonging to storage goes.
    func stageCargo(station: Station, repo: String, commands: [Command]? = nil) {
        let list = commands ?? world.carryToDeck(station: station, repo: repo, numbers: station.ledger.crates(of: repo).filter { $0.placed == .storage }.map(\.number))
        var started = 0
        for command in list {
            guard let crate = command.crate, case .carry(_, _, let to) = command.kind, let node = crateNode(crate) else {
                if let crate = command.crate { world.unorder(crate) }   // nothing on the floor to carry: the order is off
                continue
            }
            started += 1
            carry(command, node: node) { [weak self] in
                guard let self else { return }
                // Where it actually went down: the order may have been sent back on the way.
                let landedIn = world.area(of: crate).flatMap(Yard.init(area:)) ?? to
                world.landed(station: station, repo: repo, number: crate.number, in: landedIn, at: now)
                node.removeFromParentNode()
                rebuildMarkers()
                refreshRockets()
            }
        }
        guard started > 0 else { return }
        logEvent("\(repo): deployed to staging, moving to the test deck")
    }

    // MARK: crew

    /// The crew's minions, brought in line with who the model says is around.
    func setCrewRoster(_ members: [String: CrewMember], bots: Int) {
        let station = fleet.station("work")
        for (login, member) in members where minions["crew:" + login] == nil {
            let home = Home(key: member.homeKey, name: login, repo: member.repo, issue: nil)
            let start = station.cells(of: .quarters).randomElement() ?? station.coreCenter
            let m = Minion(id: "crew:" + login, station: station.name, home: home, cwd: "", toolCount: 0, isSubagent: false, start: start, crew: true)
            m.title = world.crewName(login)
            m.activity = .sleeping
            minionRoot.addChildNode(m.node)
            minions[m.id] = m
            send(m, to: .quarters)
        }
        for m in minions.values where m.isCrew && m.id != "crew:bots" && members[String(m.id.dropFirst(5))] == nil { despawn(m) }
        if bots > 0, minions["crew:bots"] == nil {
            let m = Minion(id: "crew:bots", station: station.name, home: Home(key: "kind:bots", name: "bots", repo: "crew", issue: nil), cwd: "", toolCount: 0, isSubagent: true, start: station.coreCenter, crew: true)
            m.title = "dependabot"; m.activity = .sleeping
            minionRoot.addChildNode(m.node); minions[m.id] = m
            send(m, to: .room("kind:bots"))
        }
    }

    /// What a teammate just did, played out on the floor as a command of its own: they walk there,
    /// work at it until the time is up, and then go back to the quarters.
    func playCrew(_ a: CrewActivity) {
        guard let m = minions["crew:" + a.login], !m.onJob else { return }
        let who = world.crewName(a.login)
        switch a.kind {
        case "push" where a.hasRoom:
            react(m, .coding("x"), place: .room(a.roomKey), minutes: 20, words: "\(who) pushing to \(a.label)")
            if a.ready { logEvent("\(who) pushed to \(a.label)") }
        case "review" where a.hasRoom:
            let verb = a.detail == "approved" ? "approved" : a.detail == "changes_requested" ? "requested changes on" : "reviewed"
            react(m, .exploring, place: .room(a.roomKey), minutes: 10, words: "\(who) reading \(a.label) over")
            logEvent("\(who) \(verb) \(a.label)")
        case "comment" where a.hasRoom:
            react(m, .writing, place: .room(a.roomKey), minutes: 8, words: "\(who) writing on \(a.label)")
        case "branch_create":
            react(m, .planning, place: .core, minutes: 10, words: "\(who) planning \(a.branch ?? "a branch") at the monolith")
            logEvent("\(who) started \(a.branch ?? "a branch")")
        case "issue_open":
            logEvent("\(who) filed \(a.label) \(a.title?.prefix(40) ?? "")")
            react(m, .writing, place: .room(m.home.key), minutes: 8, words: "\(who) filing \(a.label)")
            addPyramid(for: m)
        default: break
        }
    }

    /// A tested crate crosses the aisle to the tested row on someone's arms. Anything stacked on top of
    /// it is moved aside first, one carry each, and those go first.
    func carryAcrossDeck(station: Station, repo: String, number: Int) {
        for command in world.carryToTested(station: station, repo: repo, number: number) {
            guard let crate = command.crate, let node = crateNode(crate) else { world.unorder(command.crate!); continue }
            carry(command, node: node) { [weak self] in
                guard let self else { return }
                node.removeFromParentNode()
                if crate.number == number { drone.ping(seed: number) }
                rebuildMarkers()
            }
        }
    }

    /// When the deck holds cargo and nothing is cleared to launch, one free worker walks the rows, impatient.
    func assignTester(station: Station, free: [Minion]) {
        var cargoOnDeck = station.staged.values.reduce(0, +) > 0
        if ConfigStore.shared.current.project != nil {
            // With a board, QA is done once every crate on the deck is marked ready to ship.
            cargoOnDeck = world.repoRoots.contains { root, info in
                info.station == station.name && (github.cargo(repoRoot: root).map { $0.deckNumbers.count > $0.clearedNumbers.count } ?? false)
            }
        }
        let cleared = rocketActors.values.contains { $0.station == station.name && $0.isSteaming }
        let wanted = cargoOnDeck && !cleared && !station.deckCells.isEmpty
        let current = minions.values.first { $0.station == station.name && $0.isQA }
        if wanted, current == nil, let m = free.first(where: { !$0.onJob }) {
            m.activity = .qa
            m.busy = true
            send(m, to: .room("kind:deck"))
            start(m, .qa(deck: station.name))
            logEvent("staging ready for QA · \(m.home.name) walks the rows")
        } else if !wanted, let m = current {
            m.busy = false
            m.activity = .waiting
            m.setTool(nil)
            send(m, to: .lounge)
        }
    }
}
