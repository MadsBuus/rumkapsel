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
                let k = String(key[key.index(after: bar)...])
                let floor = (st.rooms[k] ?? st.lingering[k]).map { Set($0.cells) }
                let inside = (spots[st.name] ?? []).filter { floor?.contains(Station.cell(ofSub: $0)) ?? true }
                furniture[st.name, default: []].formUnion(inside)
            }
            furnitureObstacles = furniture
        }
        for (station, cells) in furnitureObstacles { blocked[station, default: []].formUnion(cells) }
        for door in staticRoot.childNodes where (door.name ?? "").hasPrefix("glassdoor:") {
            let stationName = String(door.name!.dropFirst("glassdoor:".count))
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

    func rebuildMarkers() {
        var keep: Set<ObjectIdentifier> = []
        var signatures: [String: String] = [:]
        for station in fleet.stations.values {
            for (k, office) in shownOffices(station) {
                let room = office.room(k)
                let key = roomKey(station, room)
                if case .folding = office.phase {
                    for n in markerRoot.childNodes where n.name == "box:" + key { keep.insert(ObjectIdentifier(n)) }
                    signatures[key] = markerSignatures[key]
                    continue
                }
                guard room.branch != nil || world.crewBoxes[key] != nil || world.peerBoxes[key] != nil else { continue }
                var count: Int
                var ghosts = 0
                var pr: PullRequest?
                var packaged = false
                let boxOpacity = 1.0
                if room.branch == nil {
                    guard let cb = world.crewBoxes[key] ?? world.peerBoxes[key] else { continue }
                    if crateLeft(station, room) { continue }
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
                    if (local.commits == 0 && dirtyFiles == 0) || crateLeft(station, room) { continue }
                    pr = room.repoRoot.flatMap { github.pull(branch: room.branch!, repoRoot: $0) }
                    count = world.cubes(room) ?? 0
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
                let failing = office.look.failing
                if office.look.dusty { color = color.mixed(with: NSColor(rgb: (0.55, 0.55, 0.6)), 0.55) }
                let floorShadow = NSColor(room.color).darker(0.16)
                let cells = farCells(station, room)
                let up = officeUp(station, room.key)
                let packing = simulation.packing(station, room.key)
                let held = simulation.shown[station.name]?.cubes[room.key].map { $0 < count } ?? false
                let state: [String] = ["\(count)", "\(ghosts)", pr?.state ?? "", pr?.reviewDecision ?? "", "\(pr?.isDraft ?? false)", pr?.checks ?? "",
                                       "\(failing)", "\(packaged)", "\(up)", "\(packing)", "\(held)", "\(office.look.dusty)"]
                let signature = (["\(station.offset.x),\(station.offset.y)"] + cells.map { "\($0.x),\($0.y)" } + state).joined(separator: "|")
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
                    p.opacity = !up || packing ? 0 : 1
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
                    n.opacity = !up ? 0 : (ghost ? Props.ghostOpacity : boxOpacity)
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
                if held { newest?.opacity = 0 }
                lastBoxCount[key] = count + ghosts
            }
            if station.hasPad { drawCrates(station, keep: &keep) }
        }
        for n in markerRoot.childNodes where !keep.contains(ObjectIdentifier(n)) { n.removeFromParentNode() }
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
        for order in simulation.deliveries {
            let key = "\(order.station)|\(order.slot)"
            guard lit[key] == nil, let station = fleet.stations[order.station], let room = station.rooms[order.room] else { continue }
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
            let held = Dictionary(world.padOrder(station: station).compactMap { key in world.releases.padSlotOf[key].map { ($0, key) } },
                                  uniquingKeysWith: { a, _ in a })
            for (i, at) in world.padSlots(station: station).enumerated() {
                let pad = SCNNode(geometry: faceted(SCNTube(innerRadius: Hall.padRadius - 0.06, outerRadius: Hall.padRadius, height: 0.008)))
                pad.geometry!.firstMaterial = flat(held[i].map { NSColor(fleet.color(forRepo: RocketKey.parts($0).repo)) } ?? Props.berthIdle)
                pad.opacity = held[i] == nil ? 0.25 : 0.7
                pad.position = v3(station.offset.x + at.x, 0.009, station.offset.y + at.y)
                pad.name = "pad:" + station.name
                padHexRoot.addChildNode(pad)
                if let key = held[i] { padRings[key] = pad }
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

    func officeBase(_ room: Room, remote: Bool) -> NSColor {
        let full = remote ? NSColor(room.color).dimmed(0.82) : NSColor(room.color)
        return room.key.hasPrefix("proj:") ? full.dimmed(0.86) : full
    }

    func officeLight(_ station: Station, _ room: Room, dark: Bool) -> OfficeLight {
        if room.key.hasPrefix("kind:") { return .occupied }
        if minions.values.contains(where: { $0.station == station.name && $0.place == .room(room.key) && $0.state != .leaving }) { return .occupied }
        if dark { return .dark }
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
            for (k, office) in shownOffices(station) where office.phase == .built {
                let room = office.room(k)
                let key = roomKey(station, room)
                let light = officeLight(station, room, dark: office.look.dark)
                guard let was = roomLight[key], was != light else { if roomLight[key] == nil { roomLight[key] = light }; continue }
                roomLight[key] = light
                roomPower[key] = light != .dark
                let base = officeBase(room, remote: office.look.remote)
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

extension StationController {
    func restackYard() {
        world.learn(.restack)
        logEvent("the yard restacked")
    }

    func looseCrate(_ crate: CrateRef) -> SCNNode {
        let alien = fleet.stations[crate.station]?.facts.crates[CrateID(repo: crate.repo, number: crate.number)]?.alien == true
        let color = alien ? Palette.alien.darker(0.3) : NSColor(fleet.color(forRepo: crate.repo))
        let words = crateWords(repo: crate.repo, number: crate.number)
        return Props.package(color: color, band: NSColor(rgb: (0.3, 0.32, 0.38)), size: 0.38,
                             mine: !alien && world.isMine(repo: crate.repo, number: crate.number), number: crate.number,
                             title: words.title, who: words.who)
    }

    private func crateLeft(_ station: Station, _ room: Room) -> Bool {
        guard let repo = room.repo, let r = world.works.find(officeKey: room.key, repo: repo), let n = r.number else { return false }
        if r.stage.map({ $0 >= .stored }) == true { return true }
        guard let at = simulation.shown[station.name]?.crates[CrateID(repo: repo, number: n)] else { return false }
        return at != .office(room.key)
    }

    private func drawCrates(_ station: Station, keep: inout Set<ObjectIdentifier>) {
        let view = simulation.shown[station.name] ?? Shown()
        var live: Set<String> = []
        for (id, at) in view.crates.sorted(by: { $0.key < $1.key }) {
            let key = "\(station.name)|\(id.repo)|\(id.number)"
            if case .office = at {} else if let n = crateNodes[key], let office = packages.first(where: { $0.value === n })?.key {
                packages[office] = nil
                packageBuilt[office] = nil
            }
            let pos: SIMD3<Double>, yaw: Double, zone: Zone
            switch at {
            case .hands:
                live.insert(key)
                if let n = crateNodes[key] { dress(n, station, id, zone: heading(station, id)) }
                continue
            case .vortex:
                live.insert(key)
                continue
            case .aboard:
                continue
            case .office(let room):
                live.insert(key)
                let office = station.name + "|" + room
                if let pkg = packages[office] {
                    if let old = crateNodes[key], old !== pkg { stopCrate(old); old.removeFromParentNode() }
                    crateNodes[key] = pkg
                    crateLooks[key] = nil
                    keep.insert(ObjectIdentifier(pkg))
                } else if let n = crateNodes[key] ?? (station.facts.crates[id]?.place != .office(room) ? crateNode(station, id, zone: .waiting, at: officeAt(station, room), yaw: 0) : nil) {
                    rack(n)
                    let to = officeAt(station, room)
                    if !crateMoving(n), simd_distance(position(n), to) > 0.001 { n.position = v3(to.x, to.y, to.z) }
                    keep.insert(ObjectIdentifier(n))
                }
                continue
            case .row(let s): pos = s.pos; yaw = s.yaw; zone = s.zone
            case .parked(let p): pos = p.pos; yaw = p.yaw; zone = Zone(area: p.area) ?? .waiting
            case .falling(let to, let from, let since):
                live.insert(key)
                crateNodes[key].map(rack)
                let n = crateNode(station, id, zone: to.zone, at: from, yaw: to.yaw)
                if !crateMoving(n), simd_distance(position(n), to.pos) > 0.01 {
                    let left = since + Hands.settleSeconds - clock
                    if left > 0.05 { moveCrate(n, legs: [MotionLeg(to: to.pos, seconds: left, ease: .easeIn)]) } else { n.position = v3(to.pos.x, to.pos.y, to.pos.z) }
                }
                keep.insert(ObjectIdentifier(n))
                continue
            }
            live.insert(key)
            crateNodes[key].map(rack)
            let fresh = crateNodes[key] == nil
            let n = crateNode(station, id, zone: zone, at: pos, yaw: yaw)
            if fresh, appearing.remove(key) != nil {
                n.scale = SCNVector3(0.05, 0.05, 0.05)
                moveCrate(n, legs: [MotionLeg(to: pos, seconds: 0.4, ease: .easeOut, scale: 1)])
            }
            if let heading = crateMotions[ObjectIdentifier(n)]?.legs.last?.to, simd_distance(heading, pos) > 0.01 { stopCrate(n) }
            if !crateMoving(n), simd_distance(position(n), pos) > 0.001 || abs(Double(n.eulerAngles.y) - yaw) > 0.001 {
                n.position = v3(pos.x, pos.y, pos.z)
                n.eulerAngles.y = CGFloat(yaw)
            }
            keep.insert(ObjectIdentifier(n))
        }
        for (key, n) in crateNodes where key.hasPrefix(station.name + "|") && !live.contains(key) {
            crateNodes[key] = nil
            crateLooks[key] = nil
            stopCrate(n)
            guard n.parent === markerRoot else { n.removeFromParentNode(); continue }
            keep.insert(ObjectIdentifier(n))
            let fade = SCNAction.scale(to: 0.01, duration: 0.35); fade.timingMode = .easeIn
            n.runAction(.sequence([fade, .removeFromParentNode()]))
        }
    }

    private func heading(_ station: Station, _ id: CrateID) -> Zone {
        guard let job = simulation.cargo.values.first(where: { $0.crate == id && $0.command.crate?.station == station.name }) else { return .waiting }
        return job.spot?.zone ?? Zone(area: job.aim.area) ?? .waiting
    }

    func vanish(_ station: String, _ id: CrateID) {
        let key = "\(station)|\(id.repo)|\(id.number)"
        appearing.remove(key)
        crateLooks[key] = nil
        guard let n = crateNodes.removeValue(forKey: key) else { return }
        stopCrate(n)
        n.removeFromParentNode()
    }

    private func position(_ n: SCNNode) -> SIMD3<Double> { SIMD3(Double(n.position.x), Double(n.position.y), Double(n.position.z)) }

    private func officeAt(_ station: Station, _ room: String) -> SIMD3<Double> {
        let shown = simulation.shown[station.name]?.offices[room]
        let cell = (station.rooms[room] ?? station.lingering[room]).map { packageCell(station, $0) } ?? shown?.door ?? Cell(x: 0, y: 0)
        return SIMD3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
    }

    private func rack(_ n: SCNNode) {
        guard n.parent !== markerRoot else { return }
        let at = n.worldPosition
        stopCrate(n)
        n.removeFromParentNode()
        markerRoot.addChildNode(n)
        n.position = markerRoot.convertPosition(at, from: nil)
    }

    private func crateNode(_ station: Station, _ id: CrateID, zone: Zone, at pos: SIMD3<Double>, yaw: Double) -> SCNNode {
        let key = "\(station.name)|\(id.repo)|\(id.number)"
        if let n = crateNodes[key], crateMoving(n) || n.parent !== markerRoot && n.parent != nil { return n }
        let n = crateNodes[key] ?? {
            let made = SCNNode()
            made.position = v3(pos.x, pos.y, pos.z)
            made.eulerAngles.y = CGFloat(yaw)
            markerRoot.addChildNode(made)
            return made
        }()
        crateNodes[key] = n
        dress(n, station, id, zone: zone)
        return n
    }

    private func dress(_ n: SCNNode, _ station: Station, _ id: CrateID, zone: Zone) {
        let key = "\(station.name)|\(id.repo)|\(id.number)"
        let fact = station.facts.crates[id]
        let alien = fact?.alien ?? false
        let closed = fact?.closedAt != nil
        let mine = !alien && world.isMine(repo: id.repo, number: id.number)
        let look = "\(zone.rawValue)|\(alien)|\(mine)|\(closed)"
        guard crateLooks[key] != look else { return }
        let repo = NSColor(fleet.color(forRepo: id.repo))
        let color = closed ? NSColor(rgb: (0.75, 0.2, 0.2)) : alien ? Palette.alien.darker(0.3).mixed(with: repo.darker(0.3), 0.35) : repo
        let band = zone == .decon ? Palette.alienLight.darker(0.3) : zone == .cleared ? Props.passedGreen
            : zone == .testing ? Props.waitingAmber : NSColor(rgb: (0.3, 0.32, 0.38))
        let words = crateWords(repo: id.repo, number: id.number)
        let clothes = Props.package(color: color, band: band, size: zone == .decon ? 0.3 : 0.38, mine: mine, number: id.number,
                                    title: words.title, who: words.who)
        n.childNodes.forEach { $0.removeFromParentNode() }
        clothes.childNodes.forEach { n.addChildNode($0) }
        n.opacity = 1
        n.name = "\(zone.drawn):\(key)"
        n.enumerateChildNodes { c, _ in c.name = n.name }
        crateLooks[key] = look
    }
}

extension Zone {
    var drawn: String {
        switch self {
        case .waiting: return "storage"
        case .testing, .cleared: return "deck"
        case .decon: return "decon"
        }
    }
}
