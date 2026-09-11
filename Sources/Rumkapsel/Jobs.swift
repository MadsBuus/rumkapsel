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
        if m.current?.crate != nil { dropWhereStanding(m) }
        for (id, c) in cargo where c.carrier == m.id { cargo[id]?.carrier = nil }
        world.truth.dropped(by: m.id)
        world.truth.jobs[m.id] = nil
        m.carried?.removeFromParentNode()
        m.pyramids.forEach { $0.removeFromParentNode() }
        m.queuedCones.forEach { $0.removeFromParentNode() }
        m.weldLight?.removeFromParentNode()
        m.node.removeFromParentNode()
        minions[m.id] = nil
    }

    func carriedRoom(of m: Minion) -> String? {
        if case .deliverOffice(let key) = m.current?.kind { return "\(m.station)|\(key)" }
        return nil
    }

    // MARK: commands

    /// Hands a command to an actor. It replaces the one in hand at the next interruptible phase;
    /// mid-lift or setting down it waits its turn, and only one waits at a time.
    private func assign(_ m: Minion, _ c: Command, announce: Bool = false) { start(m, c, announce: announce) }

    /// A command that has run its course hands over to its successor: the pallet's push to its unload.
    /// Not a new order cutting in, so the interruptible rule does not apply.
    func handOver(_ m: Minion, _ c: Command, announce: Bool = false) {
        m.current = nil
        begin(m, c, announce: announce)
    }

    /// The one way to give a minion an order. It takes over at the next interruptible phase; mid-lift or
    /// setting down it waits its turn, and only one waits at a time.
    func start(_ m: Minion, _ c: Command, announce: Bool = false) {
        guard m.current == nil || canInterrupt(m, with: c) else { m.pending = c; return }
        begin(m, c, announce: announce)
    }

    /// Walking and standing about can be cut into; a crouch cannot, and a carry only to send the
    /// crate on the arms somewhere else.
    private func canInterrupt(_ m: Minion, with c: Command) -> Bool {
        guard m.wakeUntil == 0 else { return false }   // still stepping out of the shuttle
        let phase = m.phaseKind
        if phase.takesNewDestination {
            guard let held = m.current?.crate, let want = c.crate else { return false }
            return held == want
        }
        return phase.interruptible
    }

    /// Every command issued, whoever runs it, goes past the taps: the log line and the panel.
    func issue(_ c: Command, by who: String, announce: Bool = false) {
        sim?.onCommand?(c, who)
        if announce { logEvent(c.words) }
    }

    private func begin(_ m: Minion, _ c: Command, announce: Bool = false) {
        issue(c, by: m.home.name)
        // Redirected mid-carry: keep the crate and walk on to the new spot.
        let redirected = m.carried != nil && m.current?.crate != nil && m.current?.crate == c.crate
        // A change of orders is visible: a beat standing, head up, then off. A message from you is urgent.
        if let old = m.current, !redirected, old.kindName != c.kindName, m.state == .settled {
            if case .work = c.kind { m.wonderUntil = clock + 0.15 } else { m.wonderUntil = clock + 0.5 }
        }
        m.current = c
        m.phase = redirected ? (c.phases.firstIndex(of: .haul) ?? 0) : 0
        m.phaseUntil = 0
        m.pending = nil
        world.truth.jobs[m.id] = (c, m.phase)
        if announce { logEvent(c.words) }
        if redirected, case .carry(_, _, let to) = c.kind { walk(m, to: to.cell) }
    }

    /// On to the next phase of the command in hand.
    func advance(_ m: Minion) {
        guard let c = m.current else { return }
        m.phaseUntil = 0
        if m.phase + 1 < c.phases.count { m.phase += 1 }
        world.truth.jobs[m.id] = (c, m.phase)
    }

    /// Done, or given up: whatever was queued starts now, else the minion goes back to resting.
    func finish(_ m: Minion) {
        world.truth.jobs[m.id] = nil
        m.current = nil
        m.phase = 0
        m.phaseUntil = 0
        m.fetchSpot = nil
        if let next = m.pending { m.pending = nil; begin(m, next, announce: next.isJob) }
        else { send(m, to: restPlace(m)) }
    }

    /// A command whose target went away: put down what is on the arms, where the minion stands.
    func dropWhereStanding(_ m: Minion) {
        guard let held = m.carried else { return }
        let at = held.worldPosition
        stopCrate(held)
        held.removeFromParentNode()
        held.position = at
        propRoot.addChildNode(held)
        moveCrate(held, legs: [MotionLeg(to: SIMD3(Double(at.x), 0.12, Double(at.z)), seconds: 0.35, ease: .easeIn)]) { [weak self] in self?.drone.thud() }
        m.carried = nil
        world.truth.dropped(by: m.id)
    }

    /// Off the station: through the airlock when there is one, and gone once inside.
    func dismiss(_ m: Minion) {
        m.state = .leaving
        start(m, .leave)
        m.couch = nil; m.bed = nil
        guard let station = fleet.stations[m.station], let hatch = station.airlockHatches.randomElement(),
              let inner = station.airlockInner.first(where: { $0.x == hatch.inside.x }) else { return }
        m.place = .airlock
        m.path = route(m, to: inner)
        // Then, after the cycle, out through the hatch onto the bay: where the shuttle would pick them up.
        let wait = SIMD2(Double(inner.x), Double(inner.y))
        m.path += [wait] + station.path(from: wait, to: hatch.bay)
    }

    /// Night on a station is the clock's business alone: a quiet afternoon is a lounge afternoon, not bedtime.
    func isNight(_ station: Station) -> Bool {
        if let forced = sim?.night { return forced }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 22 || hour < 7
    }

    /// Where a minion belongs given what it is doing and the hour.
    func restPlace(_ m: Minion) -> Place {
        Place.forActivity(m.activity, home: m.home.key, isSubagent: m.isSubagent, night: fleet.stations[m.station].map(isNight) ?? true)
    }

    /// After the floor changes, everyone carries on: settled somewhere still valid, stay; walking to a
    /// spot that still exists, keep it and re-plan from here; only if the target is gone, go somewhere new.
    func resettle(_ station: Station) {
        for m in minions.values where m.station == station.name && !m.onJob && m.state != .leaving {
            let cells = station.cells(of: m.place)
            if m.path.isEmpty {
                if m.place == .core || cells.contains(m.cell) { continue }
            } else if let last = m.path.last {
                let dest = Cell(x: Int(last.x.rounded()), y: Int(last.y.rounded()))
                if cells.contains(dest) {
                    m.path = route(m, to: dest)
                    if !m.path.isEmpty || m.cell == dest { continue }
                }
            }
            send(m, to: m.place)
        }
    }

    func send(_ m: Minion, to place: Place) {
        guard let station = fleet.stations[m.station] else { return }
        if place != .quarters { m.bed = nil }
        var place = place
        if place == .quarters, m.bed == nil {
            let used = Set(minions.values.filter { $0.station == m.station && $0.id != m.id }.compactMap(\.bed))
            m.bed = station.beds.indices.first { !used.contains($0) }
            if m.bed == nil { place = .lounge }   // every bed taken: the lounge
        }
        if place != .lounge { m.couch = nil }
        if place == .lounge, m.couch == nil {
            let used = Set(minions.values.filter { $0.station == m.station && $0.id != m.id }.compactMap(\.couch))
            m.couch = station.couches.indices.first { !used.contains($0) }
        }
        // One to a couch: if someone already holds this seat, give it up and stand at the table.
        if place == .lounge, let c = m.couch, minions.values.contains(where: { $0.id != m.id && $0.station == m.station && $0.couch == c }) {
            m.couch = nil
        }
        let cells = station.cells(of: place)
        let target: Cell
        if let b = m.bed, b < station.beds.count { target = station.beds[b].cell }
        else if place == .lounge, let c = m.couch, c < station.couches.count, let lounge = station.rooms["kind:lounge"] {
            let spot = station.couches[c]
            target = lounge.cells.min { a, b in hypot(Double(a.x) - spot.x, Double(a.y) - spot.y) < hypot(Double(b.x) - spot.x, Double(b.y) - spot.y) } ?? lounge.cells[0]
        }
        else if let t = cells.randomElement() { target = t }
        else { return }
        m.place = place
        // A bath or a chore in hand survives a re-plan to where it already is; anything else rests.
        let keep = (m.bathing && place == .bath) || (m.isChore && place == m.place)
        if !keep { start(m, .rest(place: place, home: m.home.key, name: m.home.name, asleep: m.activity == .sleeping)) }
        m.path = route(m, to: target)
        // No way found and far off: walk straight rather than stand still or slide.
        if m.path.isEmpty, abs(m.pos.x - Double(target.x)) + abs(m.pos.y - Double(target.y)) > 1 { m.path = [SIMD2(Double(target.x), Double(target.y))] }
        m.nextWanderAt = clock + Double.random(in: 1...3)
    }

    func walk(_ m: Minion, to cell: Cell) {
        guard let station = fleet.stations[m.station] else { return }
        m.path = route(m, to: cell)
    }

    /// Spots taken by the other minions on a station, as the pathfinder sees them: solid, like props.
    func crowd(around m: Minion) -> Set<Cell> {
        var out: Set<Cell> = []
        for o in minions.values where o.id != m.id && o.station == m.station && o.state != .leaving && o.opacity > 0.5 {
            let s = Station.sub(o.pos)
            for dx in -1...1 { for dy in -1...1 { out.insert(Cell(x: s.x + dx, y: s.y + dy)) } }
        }
        return out
    }

    /// A walk for a minion: round the props and round everyone else.
    func route(_ m: Minion, to cell: Cell) -> [SIMD2<Double>] {
        guard let station = fleet.stations[m.station] else { return [] }
        return station.path(from: m.pos, to: cell, avoiding: crowd(around: m))
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
        let slotIndex = shipsInFlight(m.station) % station.hangarSlots.count
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
        let command = Command.flight(.dropCrate(roomKey: roomKey), station: m.station, slot: slotIndex,
                                     what: "the office for \(room.name)")
        launch(Shuttle(node: ship, station: m.station, command: command, high: high, down: down, exit: exit,
                       restYaw: Double.random(in: 0..<(2 * .pi)), drift: Double.random(in: -0.6...0.6),
                       unloadAt: 0.8, unloadFor: 1.2) { [weak self] in
            box.opacity = 1
            box.position = v3(slot.x, 0.42, slot.z)
            self?.moveCrate(box, legs: [MotionLeg(to: SIMD3(slot.x, 0.09, slot.z), seconds: 0.5, ease: .easeIn)])
            self?.world.truth.crateInBay(key)   // the crate is on the floor now: a carrier may fetch it
        })
        drone.sweep(up: false)
        assign(m, .deliverOffice(key: roomKey, name: room.name), announce: false)
        m.place = .hangar
        m.fetchSpot = station.hangarSlots[slotIndex]
        walk(m, to: station.hangarCells[min(station.hangarCells.count - 1, slotIndex * 2)])
    }

    /// Archiving: boxes shrink away, whoever is inside steps out into the hallway, and the room
    /// detaches, sinks and fades. The model drops the room at once; only the visuals linger.
    func archive(station: String, key: String, roomKey: String, name: String, hall: Cell?, announce: Bool, reason: String) {
        cancelCarries(roomKey: key)
        for m in minions.values where m.station == station && m.home.key == roomKey { clearPyramids(m) }
        stationAnchors[station]?.childNodes.filter { $0.name == "room:" + key }.forEach { $0.removeFromParentNode() }
        world.truth.forgetOffice(key)
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

    /// Takes a carry command and the crate it moves. The crate is spoken for from here on, so nothing
    /// else is told to move it and the yard layout leaves its spot alone.
    func carry(_ command: Command, node: SCNNode, roomKey: String = "", onDone: @escaping () -> Void) {
        guard let crate = command.crate else { return }
        world.truth.claimed(crate)
        node.name = "haul"
        cargo[command.id] = Cargo(command: command, node: node, onDone: onDone, carrier: nil, roomKey: roomKey, issuedAt: clock)
    }

    /// Drops every carry tied to a room, freeing whoever was carrying.
    /// Only carries into the office are dropped with it. A haul out of it, to storage, goes on: the
    /// crate belongs in storage whatever becomes of the office.
    private func cancelCarries(roomKey: String) {
        for (id, c) in cargo where c.roomKey == roomKey {
            if case .carry(_, _, let to) = c.command.kind, to.area == .storage { continue }
            c.node.removeFromParentNode()
            if let crate = c.command.crate { world.truth.forget(crate) }
            cargo[id] = nil
            if let who = c.carrier, let m = minions[who] { m.carried = nil; world.truth.dropped(by: m.id); finish(m) }
        }
    }

    /// The node a crate stands on, by the name the yard gave it. Unnumbered crates of a repository
    /// share a name, so a carry takes the one standing on the slot it names.
    func crateNode(_ area: String, _ crate: CrateRef, at spot: Spot? = nil) -> SCNNode? {
        let name = "\(area):\(crate.station)|\(crate.repo)|\(crate.number)"
        let all = markerRoot.childNodes.filter { $0.name == name }
        guard let spot else { return all.first }
        return all.min { a, b in
            func d(_ n: SCNNode) -> Double {
                let p = n.worldPosition
                return pow(Double(p.x) - spot.pos.x, 2) + pow(Double(p.y) - spot.pos.y, 2) + pow(Double(p.z) - spot.pos.z, 2)
            }
            return d(a) < d(b)
        }
    }

    /// Merged: the office's package is carried to the storage bay in one trip. The model has already
    /// noted that the office is free to clear; this only moves what is on the floor.
    func haulMergedBoxes(station: Station, key: String, roomName: String, repo: String, number: Int) {
        guard let pkg = markerRoot.childNodes.first(where: { $0.name == "box:" + key }),
              let room = station.rooms[key.split(separator: "|", maxSplits: 1).map(String.init).last ?? ""] else { return }
        logEvent("\(roomName): merged, package to storage")
        let command = world.carryToStorage(station: station, room: room, repo: repo, number: number)
        carry(command, node: pkg, roomKey: key) { [weak self] in
            guard let self else { return }
            world.landedInStorage(station: station, repo: repo, number: number)
            pkg.removeFromParentNode()
            rebuildMarkers()
            refreshRockets()
        }
    }

    /// A staging release merged: the repo's storage crates are carried to the test deck.
    func stageCargo(station: Station, repo: String, commands: [Command]? = nil) {
        let list = commands ?? world.carryToDeck(station: station, repo: repo, count: station.stored[repo] ?? 0)
        var started = 0
        for command in list {
            guard let crate = command.crate, case .carry(_, let from, _) = command.kind,
                  let node = crateNode("storage", crate, at: from) else { continue }
            started += 1
            carry(command, node: node) { [weak self] in
                guard let self else { return }
                station.stored[repo] = max(0, (station.stored[repo] ?? 1) - 1)
                station.staged[repo, default: 0] += 1
                node.removeFromParentNode()
                rebuildMarkers()
                refreshRockets()
                fleet.save()
            }
        }
        guard started > 0 else { return }
        logEvent("\(repo): deployed to staging, moving to the test deck")
    }

    /// Gives waiting carries to free minions on the same station. A carry nobody picked up by its
    /// deadline lands where it stands, rather than holding the world back.
    func scheduleCarries() {
        for (id, job) in cargo where job.carrier == nil {
            guard case .carry(let crate, let from, _) = job.command.kind, let station = fleet.stations[crate.station] else { continue }
            // Crates stacked above this one are still on their way: wait, deadline and all.
            guard job.command.after.allSatisfy({ cargo[$0] == nil }) else { continue }
            let free = minions.values.filter { $0.station == crate.station && !$0.onJob && $0.carried == nil && !$0.isSubagent && $0.state != .leaving && $0.wakeUntil == 0 }
            guard let m = free.min(by: { abs($0.cell.x - from.cell.x) + abs($0.cell.y - from.cell.y) < abs($1.cell.x - from.cell.x) + abs($1.cell.y - from.cell.y) }) else {
                if let patience = job.command.patience, clock - job.issuedAt > patience {
                    cargo[id] = nil
                    job.node.removeFromParentNode()
                    world.truth.forget(crate)
                    job.onDone()
                }
                continue
            }
            assign(m, job.command, announce: true)
            guard m.current?.id == job.command.id else { continue }
            cargo[id]?.carrier = m.id
            m.bed = nil
            m.couch = nil   // off the couch: the seat is free for someone else
            m.path = route(m, to: standCell(station, near: from.cell))
        }
        tickRockets()
        servicePallets()
    }

    // MARK: crew

    /// A teammate's reaction has run its course: back to the quarters, or the bots' room.
    func crewRested(_ m: Minion) {
        m.busy = false
        m.activity = .sleeping
        clearPyramids(m)
        send(m, to: m.id == "crew:bots" ? .room("kind:bots") : .quarters)
    }

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

    /// Hands a teammate a reaction: where to be, what to do there, and until when.
    func react(_ m: Minion, _ activity: Activity, place: Place, minutes: Double, words: String) {
        m.activity = activity
        m.busy = true
        if m.place != place || m.path.isEmpty { send(m, to: place) }
        start(m, .react(activity, place: place, for: minutes * 60, words: words))
    }

    /// A tested crate crosses the aisle to the tested row on someone's arms. Anything stacked on top of
    /// it is moved aside first, one carry each, and those go first.
    func carryAcrossDeck(station: Station, repo: String, number: Int) {
        for command in world.carryToTested(station: station, repo: repo, number: number) {
            guard let crate = command.crate, case .carry(_, let from, _) = command.kind,
                  let node = crateNode("deck", crate, at: from) else { continue }
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
