import AppKit
import SceneKit

struct BerthLight: Equatable {
    let color: RGB
    let beat: Bool
}

extension StationController {
    func crateWords(repo: String?, number: Int?) -> (title: String?, who: String?) {
        guard let repo, let number, let work = github.work(repo: repo, number: number) else { return (nil, nil) }
        return (work.title.isEmpty ? nil : work.title, work.author.map(world.crewName))
    }

    func refreshObstacles() {
        var blocked: [String: Set<Cell>] = [:]
        func mark(_ station: String, _ node: SCNNode, offset: SIMD2<Double>, into: inout [String: Set<Cell>]) {
            let (lo, hi) = node.boundingBox
            let p = SIMD2(Double(node.position.x) - offset.x, Double(node.position.z) - offset.y)
            let r = Double(max(hi.x - lo.x, hi.z - lo.z)) / 2 * 0.8 * Double(node.scale.x)
            let f = Double(Station.fine)
            for sx in Int(((p.x - r) * f).rounded())...Int(((p.x + r) * f).rounded()) {
                for sy in Int(((p.y - r) * f).rounded())...Int(((p.y + r) * f).rounded()) { into[station, default: []].insert(Cell(x: sx, y: sy)) }
            }
        }
        func mark(_ station: String, _ node: SCNNode, offset: SIMD2<Double>) { mark(station, node, offset: offset, into: &blocked) }
        for n in markerRoot.childNodes {
            guard let name = n.name, let colon = name.firstIndex(of: ":"), let bar = name.firstIndex(of: "|"), colon < bar else { continue }
            let stationName = String(name[name.index(after: colon)..<bar])
            guard let st = fleet.stations[stationName] else { continue }
            mark(stationName, n, offset: st.offset)
        }
        for m in minions.values {
            for p in m.pyramids + m.queuedCones { mark(m.station, p, offset: .zero) }
        }
        for (key, r) in simulation.rockets {
            guard let st = fleet.stations[r.station] else { continue }
            let at = padPosition(station: st, slot: padSlot(station: st, key: key))
            let p = SIMD2(Double(at.x) - st.offset.x, Double(at.z) - st.offset.y)
            let hull = 0.3, f = Double(Station.fine)
            for sx in Int(((p.x - hull) * f).rounded())...Int(((p.x + hull) * f).rounded()) {
                for sy in Int(((p.y - hull) * f).rounded())...Int(((p.y + hull) * f).rounded()) { blocked[r.station, default: []].insert(Cell(x: sx, y: sy)) }
            }
        }
        if furnitureObstaclesAt != staticRoot.childNodes.count {
            furnitureObstaclesAt = staticRoot.childNodes.count
            var furniture: [String: Set<Cell>] = [:]
            for n in staticRoot.childNodes where n.geometry != nil && !(n.geometry is SCNPlane) && (n.name ?? "").hasPrefix("room:") {
                let (lo, hi) = n.boundingBox
                guard Double(hi.y - lo.y) * Double(n.scale.y) > 0.03 else { continue }
                let key = String(n.name!.dropFirst(5))
                guard let bar = key.firstIndex(of: "|"), let st = fleet.stations[String(key[..<bar])] else { continue }
                var spots: [String: Set<Cell>] = [:]
                mark(st.name, n, offset: st.offset, into: &spots)
                let floor = st.rooms[String(key[key.index(after: bar)...])].map { Set($0.cells) }
                let inside = (spots[st.name] ?? []).filter { floor?.contains(Station.cell(ofSub: $0)) ?? true }
                furniture[st.name, default: []].formUnion(inside)
            }
            furnitureObstacles = furniture
        }
        for (station, cells) in furnitureObstacles { blocked[station, default: []].formUnion(cells) }
        for door in staticRoot.childNodes where (door.name ?? "").hasPrefix("airlockdoor:") {
            let stationName = String(door.name!.dropFirst("airlockdoor:".count))
            guard let st = fleet.stations[stationName] else { continue }
            for post in door.childNodes where post.name == "post" {
                let f = Double(Station.fine)
                let p = SIMD2(Double(door.position.x + post.position.x) - st.offset.x, Double(door.position.z + post.position.z) - st.offset.y)
                blocked[stationName, default: []].insert(Cell(x: Int((p.x * f).rounded()), y: Int((p.y * f).rounded())))
            }
        }
        for st in fleet.stations.values { st.obstacles = blocked[st.name] ?? [] }
    }

    func packageCell(_ station: Station, _ room: Room) -> Cell {
        let key = roomKey(station, room)
        if let held = packageCells[key], room.cells.contains(held) { return held }
        let cells = farCells(station, room)
        var coned: Set<Cell> = []
        for m in minions.values where m.station == station.name {
            for n in m.pyramids + m.queuedCones {
                let x = Double(n.worldPosition.x) - station.offset.x
                let z = Double(n.worldPosition.z) - station.offset.y
                coned.insert(Cell(x: Int(x.rounded()), y: Int(z.rounded())))
            }
        }
        let cell = cells.first { !coned.contains($0) } ?? cells.first!
        packageCells[key] = cell
        return cell
    }

    private func relight(_ pkg: SCNNode, light: NSColor, blink: Bool, failing: Bool, size: Double) {
        if let plate = pkg.childNodes.first(where: { $0.geometry?.name == Props.plateName }) {
            plate.geometry?.firstMaterial = flat(light)
            let blinking = plate.action(forKey: "blink") != nil
            if blink && !blinking { plate.runAction(Props.blinking(), forKey: "blink") }
            if !blink && blinking { plate.removeAction(forKey: "blink"); plate.opacity = 1 }
        }
        let shell = pkg.childNodes.first { $0.geometry?.name == Props.shellName }
        if failing, shell == nil {
            let s = Props.failingShell(size: size)
            (s.geometry as? SCNBox).map { $0.width = size * 1.2; $0.length = size * 1.2 }
            s.geometry!.name = Props.shellName
            pkg.addChildNode(s)
        } else if !failing, let s = shell {
            s.removeFromParentNode()
        }
    }

    private func mine(_ slot: YardSlot) -> Bool { !slot.alien && world.isMine(repo: slot.repo, number: slot.number) }

    func reconcileYards() {
        for station in fleet.stations.values where station.hasPad {
            let before = (station.stored, station.staged)
            for (root, info) in world.repoRoots where info.station == station.name {
                if let c = github.cargo(repoRoot: root) { world.reconcile(station: station, repo: info.repo, root: root, cargo: c) }
            }
            if before.0 != station.stored || before.1 != station.staged { markersDirty = true }
        }
        for e in world.stationEvents() { handle(e) }
        for station in fleet.stations.values where station.hasPad {
            for (id, job) in cargo {
                guard case .carry(let crate, let from, _) = job.command.kind, crate.station == station.name,
                      let row = station.ledger[crate.repo, crate.number],
                      row.heading == .deck, row.placed == .storage, row.wanted == .storage, row.movedAt == nil else { continue }
                simulation.cancelCarry(id, backTo: from)
            }
        }
    }

    func rebuildMarkers() {
        var keep: Set<ObjectIdentifier> = []
        var signatures: [String: String] = [:]
        for station in fleet.stations.values {
            for room in station.rooms.values where room.branch != nil || world.crewBoxes[roomKey(station, room)] != nil || world.peerBoxes[roomKey(station, room)] != nil {
                let key = roomKey(station, room)
                var count: Int
                var ghosts = 0
                var pr: PullRequest?
                var packaged = false
                let boxOpacity = 1.0
                if room.branch == nil {
                    guard let cb = world.crewBoxes[key] ?? world.peerBoxes[key] else { continue }
                    if world.haulOrdered(office: key) { continue }
                    count = min(16, max(1, cb.count))
                    let peer = world.crewRoomInfo[key] == nil ? world.peerPull(key) : nil
                    let prNumber = world.crewPull(key) ?? peer?.pull
                    let state = world.isClosed(key) ? "CLOSED" : (peer?.pullState ?? (prNumber != nil ? "OPEN" : cb.state))
                    pr = PullRequest(number: prNumber ?? 0, title: "", state: state, reviewDecision: peer?.review ?? "", isDraft: false, url: "")
                    pr?.checks = peer?.checks ?? ""
                    packaged = prNumber != nil || world.isClosed(key)
                } else {
                    let local = world.localState(room)
                    let dirtyFiles = room.worktree.map { github.dirtyFiles(worktree: $0) } ?? 0
                    if (local.commits == 0 && dirtyFiles == 0) || world.haulOrdered(office: key) { continue }
                    pr = room.repoRoot.flatMap { github.pull(branch: room.branch!, repoRoot: $0) }
                    count = min(16, Int(pow(Double(local.commits), 0.7).rounded(.up)))
                    ghosts = min(8, Int(pow(Double(dirtyFiles), 0.6).rounded(.up)))
                    packaged = pr != nil
                }
                let base = NSColor(room.color).lighter(0.12)
                let status: NSColor?
                switch (pr?.state, pr?.reviewDecision, pr?.isDraft) {
                case (nil, _, _): status = nil
                case ("MERGED", _, _): status = NSColor(rgb: (0.6, 0.4, 0.9))
                case ("CLOSED", _, _): status = NSColor(rgb: (0.92, 0.22, 0.22))
                case (_, "APPROVED", _): status = NSColor(rgb: (0.45, 0.95, 0.5))
                case (_, "CHANGES_REQUESTED", _): status = NSColor(rgb: (0.95, 0.3, 0.3))
                case (_, _, true): status = NSColor(rgb: (0.6, 0.62, 0.68))
                default: status = NSColor(rgb: (0.4, 0.82, 0.45))
                }
                var color = status.map { $0.mixed(with: base, 0.15) } ?? base
                let failing = world.checksFailing(room)
                if world.isDusty(room) { color = color.mixed(with: NSColor(rgb: (0.55, 0.55, 0.6)), 0.55) }
                let floorShadow = NSColor(room.color).darker(0.16)
                let cells = farCells(station, room)
                let signature = (["\(station.offset.x),\(station.offset.y)"] + cells.map { "\($0.x),\($0.y)" } + [
                    "\(count)", "\(ghosts)", pr?.state ?? "", pr?.reviewDecision ?? "", "\(pr?.isDraft ?? false)", pr?.checks ?? "",
                    "\(failing)", "\(packaged)", "\(undelivered.contains(key))", "\(packing.contains(key))", "\(stowHeld.contains(key))", "\(world.isDusty(room))",
                ]).joined(separator: "|")
                let drawn = markerRoot.childNodes.filter { $0.name == "box:" + key }
                if packaged {
                    let cell = packageCell(station, room)
                    let size = 0.38
                    let closed = pr?.state == "CLOSED"
                    let checks = pr?.checks ?? ""
                    let light: NSColor = closed || failing || checks == "failure" ? NSColor(rgb: (0.95, 0.22, 0.22))
                        : checks == "pending" ? NSColor(rgb: (1.0, 0.72, 0.25)) : (status ?? NSColor(rgb: (0.4, 0.82, 0.45)))
                    let blink = checks == "pending" && !closed
                    let mine = world.isMine(office: key)
                    let task = world.taskNumber(room) ?? pr?.number
                    let words = crateWords(repo: room.repo, number: task)
                    let built = "\(closed)|\(mine)|\(room.color.r),\(room.color.g),\(room.color.b)|\(words.title ?? "")|\(words.who ?? "")"
                    signatures[key] = "package"
                    var pkg = packages[key]
                    if let p = pkg, p.parent == nil || packageBuilt[key] != built { p.removeFromParentNode(); packages[key] = nil; pkg = nil }
                    if pkg == nil {
                        let p = Props.package(color: closed ? NSColor(rgb: (0.75, 0.2, 0.2)) : NSColor(room.color), band: light, size: size, blink: blink, mine: mine,
                                              number: task, title: words.title, who: words.who)
                        p.name = "box:" + key
                        markerRoot.addChildNode(p)
                        packages[key] = p
                        packageBuilt[key] = built
                        pkg = p
                    }
                    guard let p = pkg else { continue }
                    drawn.filter { $0 !== p }.forEach { $0.removeFromParentNode() }
                    let at = v3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
                    if p.position.x != at.x || p.position.z != at.z { p.position = at }
                    relight(p, light: light, blink: blink, failing: failing, size: size)
                    p.opacity = undelivered.contains(key) || packing.contains(key) ? 0 : 1
                    keep.insert(ObjectIdentifier(p))
                    lastBoxCount[key] = 1
                    continue
                }
                signatures[key] = signature
                if markerSignatures[key] == signature, !drawn.isEmpty {
                    drawn.forEach { keep.insert(ObjectIdentifier($0)) }
                    continue
                }
                drawn.forEach { $0.removeFromParentNode() }
                var seed = stableHash(key) | 1
                func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
                var placedBoxes: [(pos: SIMD3<Double>, size: Double)] = []
                var newest: SCNNode?
                for i in 0..<(count + ghosts) {
                    let ghost = i >= count
                    let size = Props.cubeSizes[min(2, Int(rnd() * 3))]
                    let shade = CGFloat(rnd() * 0.1 - 0.04)
                    let n = Props.cube(color: color.lighter(shade), size: size, shadow: floorShadow)
                    n.childNodes.forEach { $0.name = "box:" + key }
                    let pos: SIMD3<Double>
                    if i >= 8, let base = placedBoxes[i - 8] as (pos: SIMD3<Double>, size: Double)? {
                        pos = SIMD3(base.pos.x + (rnd() - 0.5) * 0.06, base.pos.y + base.size / 2 + size / 2, base.pos.z + (rnd() - 0.5) * 0.06)
                    } else {
                        let cell = cells[(i / 3) % cells.count]
                        let room = max(0, 0.86 - size * 1.25)
                        pos = SIMD3(station.offset.x + Double(cell.x) + (rnd() - 0.5) * room, size / 2, station.offset.y + Double(cell.y) + (rnd() - 0.5) * room)
                    }
                    placedBoxes.append((pos, size))
                    n.position = v3(pos.x, pos.y, pos.z)
                    n.eulerAngles.y = rnd() * 0.9
                    n.name = "box:" + key
                    n.opacity = undelivered.contains(key) ? 0 : (ghost ? Props.ghostOpacity : boxOpacity)
                    if !ghost { newest = n }
                    if failing && !ghost {
                        let shell = Props.failingShell(size: size * 1.25)
                        shell.name = "box:" + key
                        n.addChildNode(shell)
                    }
                    markerRoot.addChildNode(n)
                    keep.insert(ObjectIdentifier(n))
                }
                newestCube[key] = newest
                if stowHeld.contains(key) { newest?.opacity = 0 }
                if let last = lastBoxCount[key], count > last, room.branch != nil, let box = newest,
                   let m = minions.values.first(where: { $0.station == station.name && $0.home.key == room.key && !$0.isPeer && !$0.isSubagent }) {
                    stowHeld.insert(key)
                    box.opacity = 0
                    let at = Cell(x: Int((Double(box.position.x) - station.offset.x).rounded()), y: Int((Double(box.position.z) - station.offset.y).rounded()))
                    simulation.post(.stow(office: room.key), for: m, rank: .yard, at: standCell(station, near: at), place: .room(room.key), announce: true)
                }
                lastBoxCount[key] = count + ghosts
            }
            for yard in [Yard.storage, .deck, .decon] where station.hasPad {
                let area = yard.rawValue
                let layout = station.layout(of: yard).filter { !$0.carried }
                let prefix = "\(area):\(station.name)|"
                var standing: [String: [SCNNode]] = [:]
                for n in markerRoot.childNodes where (n.name ?? "").hasPrefix(prefix) { standing[n.name!, default: []].append(n) }
                let wanted = Set(layout.map { prefix + "\($0.repo)|\($0.number)" })
                func vacated(_ from: SIMD3<Double>, _ to: SIMD3<Double>) -> Bool {
                    standing.allSatisfy { name, nodes in
                        !wanted.contains(name) || nodes.allSatisfy { n in
                            let p = n.position
                            return !(abs(Double(p.x) - to.x) < 0.001 && abs(Double(p.z) - to.z) < 0.001
                                     && Double(p.y) < from.y - 0.05 && Double(p.y) > to.y - 0.05)
                        }
                    }
                }
                for slot in layout {
                    let name = prefix + "\(slot.repo)|\(slot.number)"
                    let spec = (slot.cleared ? "tested" : "untested") + (slot.alien ? " alien" : "") + (mine(slot) ? " mine" : "")
                    if markerSignatures[name] == spec, let n = standing[name]?.first, !keep.contains(ObjectIdentifier(n)) {
                        keep.insert(ObjectIdentifier(n))
                        signatures[name] = spec
                        let at = SIMD3(Double(n.position.x), Double(n.position.y), Double(n.position.z))
                        let heading = crateMotions[ObjectIdentifier(n)]?.legs.last?.to ?? at
                        if abs(heading.x - slot.pos.x) > 0.001 || abs(heading.y - slot.pos.y) > 0.001 || abs(heading.z - slot.pos.z) > 0.001
                            || abs(Double(n.eulerAngles.y) - slot.yaw) > 0.001 {
                            stopCrate(n)
                            if abs(at.x - slot.pos.x) < 0.001, abs(at.z - slot.pos.z) < 0.001, at.y > slot.pos.y + 0.05, area == "decon" || vacated(at, slot.pos) {
                                moveCrate(n, legs: [MotionLeg(to: slot.pos, seconds: Hands.settleSeconds, ease: .easeIn)])
                            } else {
                                n.position = v3(slot.pos.x, slot.pos.y, slot.pos.z)
                                n.eulerAngles.y = slot.yaw
                            }
                        }
                        continue
                    }
                    let c = slot.alien ? Palette.alien.darker(0.3).mixed(with: NSColor(fleet.color(forRepo: slot.repo)).darker(0.3), 0.35) : NSColor(fleet.color(forRepo: slot.repo))
                    let band = area == "decon" ? Palette.alienLight.darker(0.3) : slot.cleared ? Props.passedLight
                        : area == "deck" ? Props.gateIdle : NSColor(rgb: (0.3, 0.32, 0.38))
                    let words = crateWords(repo: slot.repo, number: slot.number)
                    let pkg = Props.package(color: c, band: band, size: area == "decon" ? 0.3 : 0.38, mine: mine(slot), number: slot.number,
                                            title: words.title, who: words.who)
                    pkg.position = v3(slot.pos.x, slot.pos.y, slot.pos.z)
                    pkg.eulerAngles.y = slot.yaw
                    pkg.name = name
                    pkg.enumerateChildNodes { c, _ in c.name = pkg.name }
                    markerRoot.addChildNode(pkg)
                    if incoming.remove(name) != nil {
                        pkg.position.y = CGFloat(slot.pos.y + 1.2)
                        moveCrate(pkg, legs: [MotionLeg(to: slot.pos, seconds: Hands.settleSeconds * 1.5, ease: .easeIn)])
                    }
                    keep.insert(ObjectIdentifier(pkg))
                    signatures[name] = spec
                }
            }
        }
        for n in markerRoot.childNodes where !keep.contains(ObjectIdentifier(n)) && n.name != "haul" { n.removeFromParentNode() }
        packages = packages.filter { $0.value.parent != nil }
        packageBuilt = packageBuilt.filter { packages[$0.key] != nil }
        markerSignatures = signatures
        refreshObstacles()
    }

    func rebuildBerths() {
        if berthRoot.parent == nil { propRoot.addChildNode(berthRoot) }
        berthRoot.childNodes.forEach { $0.removeFromParentNode() }
        berthHexes = [:]
        guard Looks.current.drawsBerthHexes else { return }
        for station in fleet.stations.values where station.hasHangar {
            var hexes: [SCNNode] = []
            for at in station.hangarSlots {
                let berth = Props.berth()
                berth.node.position = v3(station.offset.x + at.x, 0, station.offset.y + at.y)
                berth.node.name = "bay:" + station.name
                berthRoot.addChildNode(berth.node)
                hexes.append(berth.rim)
            }
            berthHexes[station.name] = hexes
        }
        berthLit = [:]
    }

    func updateBerths() {
        var lit: [String: BerthLight] = [:]
        for f in simulation.flights {
            guard case .flight(_, _, let slot) = f.command.kind else { continue }
            let coming = f.phaseKind == .approach || f.phaseKind == .descend
            lit["\(f.station)|\(slot)"] = BerthLight(color: fleet.color(forRepo: f.repo), beat: coming)
        }
        for order in world.truth.deliveries.values {
            let key = "\(order.station)|\(order.slot)"
            guard lit[key] == nil, let station = fleet.stations[order.station], let room = station.rooms[order.roomKey] else { continue }
            lit[key] = BerthLight(color: room.color, beat: false)
        }
        guard lit != berthLit else { return }
        berthLit = lit
        for (name, hexes) in berthHexes {
            for (i, hex) in hexes.enumerated() {
                let light = lit["\(name)|\(i)"]
                hex.removeAllActions()
                hex.geometry?.firstMaterial?.diffuse.contents = light.map { NSColor($0.color) } ?? Props.berthIdle
                hex.opacity = light == nil ? 0.25 : 0.75
                if light?.beat == true {
                    hex.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.95, duration: 0.5), .fadeOpacity(to: 0.35, duration: 0.6)])))
                }
            }
        }
    }

    func rebuildPadHexes() {
        if padHexRoot.parent == nil { propRoot.addChildNode(padHexRoot) }
        padHexRoot.childNodes.forEach { $0.removeFromParentNode() }
        padRings = [:]
        for station in fleet.stations.values where station.hasPad {
            let held = Dictionary(uniqueKeysWithValues: world.padOrder(station: station).compactMap { key in
                world.padSlotOf[key].map { ($0, String(key.dropFirst(station.name.count + 1))) }
            })
            for (i, at) in world.padSlots(station: station).enumerated() {
                let pad = SCNNode(geometry: faceted(SCNTube(innerRadius: Hall.padRadius - 0.06, outerRadius: Hall.padRadius, height: 0.008)))
                pad.geometry!.firstMaterial = flat(held[i].map { NSColor(fleet.color(forRepo: $0)) } ?? Props.berthIdle)
                pad.opacity = held[i] == nil ? 0.25 : 0.7
                pad.position = v3(station.offset.x + at.x, 0.009, station.offset.y + at.y)
                pad.name = "pad:" + station.name
                padHexRoot.addChildNode(pad)
                if let repo = held[i] { padRings[station.name + "|" + repo] = pad }
            }
        }
    }

    func hatchBlink(station name: String) {
        guard let light = hatchLights[name] else { return }
        light.removeAllActions()
        let on = SCNAction.run { n in n.geometry?.firstMaterial?.diffuse.contents = Palette.alienLight.lighter(0.3) }
        let off = SCNAction.run { n in n.geometry?.firstMaterial?.diffuse.contents = Palette.alienLight.darker(0.35) }
        light.runAction(.sequence([on, .wait(duration: 0.3), off, .wait(duration: 0.3), on, .wait(duration: 0.3), off, .wait(duration: 0.3), on, .wait(duration: 0.6), off]))
    }

    func officeBase(_ station: Station, _ room: Room) -> NSColor {
        let full = world.isRemoteOnly(station, room) ? NSColor(room.color).dimmed(0.82) : NSColor(room.color)
        return room.key.hasPrefix("proj:") ? full.dimmed(0.86) : full
    }

    func officeLight(_ station: Station, _ room: Room) -> OfficeLight {
        if room.key.hasPrefix("kind:") { return .occupied }
        if minions.values.contains(where: { $0.station == station.name && $0.place == .room(room.key) && $0.state != .leaving }) { return .occupied }
        if world.peerDim(roomKey(station, room)) { return .dark }
        return now.timeIntervalSince(room.lastActive) < StationController.powerWindow ? .empty : .dark
    }

    func officeTone(_ base: NSColor, _ light: OfficeLight) -> NSColor {
        let floor = NSColor(rgb: (0.27, 0.28, 0.33))
        switch light {
        case .occupied: return base
        case .empty: return Looks.current.rimsOffices ? base : base.mixed(with: floor, 0.35).darker(0.1)
        case .dark: return base.mixed(with: floor, 0.6).darker(0.3)
        }
    }

    func updatePower() {
        for station in fleet.stations.values {
            for room in station.rooms.values where !room.key.hasPrefix("kind:") {
                let key = roomKey(station, room)
                let light = officeLight(station, room)
                guard let was = roomLight[key], was != light else { if roomLight[key] == nil { roomLight[key] = light }; continue }
                roomLight[key] = light
                roomPower[key] = light != .dark
                let base = officeBase(station, room)
                let from = officeTone(base, was), to = officeTone(base, light)
                for t in roomTiles[key] ?? [] {
                    t.removeAction(forKey: "light")
                    t.runAction(.customAction(duration: 0.6) { node, elapsed in
                        Looks.current.tint(tile: node, from.mixed(with: to, min(1, elapsed / 0.6)))
                    }, forKey: "light")
                    if was == .dark {
                        t.runAction(.sequence([.fadeOpacity(to: 0.35, duration: 0.05), .fadeOpacity(to: 1, duration: 0.08), .fadeOpacity(to: 0.5, duration: 0.05),
                                               .fadeOpacity(to: 1, duration: 0.12), .fadeOpacity(to: 0.7, duration: 0.05), .fadeOpacity(to: 1, duration: 0.1)]))
                    }
                }
                if was == .dark { logEvent("\(room.name): \(Words.current.lightsOn)") }
            }
        }
    }

    func updateBeams() {
        var live = Set<String>()
        for m in minions.values where m.place == .core && m.path.isEmpty && m.state == .settled && m.opacity > 0.5 && m.activity != .sleeping {
            guard let station = fleet.stations[m.station], station.cells(of: .core).contains(m.cell) else { continue }
            live.insert(m.id)
            let mp = station.monolithPosition
            let from = SIMD3(station.offset.x + mp.x, 1.9, station.offset.y + mp.y)
            let to = SIMD3(station.offset.x + m.pos.x, m.headHeight * 0.8, station.offset.y + m.pos.y)
            let cone = beams[m.id] ?? {
                let n = Props.beam()
                beamRoot.addChildNode(n)
                beams[m.id] = n
                return n
            }()
            Props.aim(cone, from: from, to: to, clock: clock, phase: m.bobPhase)
        }
        for (id, n) in beams where !live.contains(id) { n.removeFromParentNode(); beams[id] = nil }
    }
}

enum OfficeLight { case occupied, empty, dark }
