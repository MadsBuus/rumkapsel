import AppKit
import SceneKit
import SpriteKit

enum LoungeOrder: CaseIterable {
    case gym, bed, read, shower, toilet, coffee, bite

    var symbol: String {
        switch self {
        case .gym: return "dumbbell.fill"
        case .bed: return "bed.double.fill"
        case .read: return "book.fill"
        case .shower: return "shower.fill"
        case .toilet: return "toilet.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .bite: return "fork.knife"
        }
    }

    var words: String {
        switch self {
        case .gym: return "work out in the gym"
        case .bed: return "take a nap"
        case .read: return "read on the couch"
        case .shower: return "take a shower"
        case .toilet: return "go to the toilet"
        case .coffee: return "get a coffee"
        case .bite: return "have a bite"
        }
    }

    var color: NSColor {
        switch self {
        case .gym: return Palette.debris
        case .bed: return NSColor(Colors.quarters).lighter(0.35)
        case .read: return NSColor(rgb: (0.94, 0.65, 0.10))
        case .shower: return NSColor(rgb: (0.62, 0.82, 0.95))
        case .toilet: return NSColor(rgb: (0.92, 0.92, 0.9))
        case .coffee: return NSColor(rgb: (0.78, 0.55, 0.36))
        case .bite: return NSColor(rgb: (0.93, 0.6, 0.25))
        }
    }

    var texture: SKTexture {
        let side: CGFloat = 96
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.8, weight: .semibold)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: words)?.withSymbolConfiguration(config) else {
            return SKTexture()
        }
        let drawn = NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
            let s = image.size, k = min(r.width / s.width, r.height / s.height)
            let fit = NSRect(x: (r.width - s.width * k) / 2, y: (r.height - s.height * k) / 2, width: s.width * k, height: s.height * k)
            image.draw(in: fit)
            NSColor.white.set()
            fit.fill(using: .sourceAtop)
            return true
        }
        var rect = NSRect(x: 0, y: 0, width: side, height: side)
        guard let cg = drawn.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return SKTexture() }
        let t = SKTexture(cgImage: cg)
        t.filteringMode = .linear
        return t
    }
}

extension StationController {
    // MARK: hud

    var ink: (text: NSColor, dim: NSColor, onLight: Bool) {
        let bg = Looks.current.background.usingColorSpace(.deviceRGB) ?? Palette.void
        let light = bg.redComponent * 0.3 + bg.greenComponent * 0.59 + bg.blueComponent * 0.11 > 0.3
        return light ? (NSColor(rgb: (0.1, 0.12, 0.16)), NSColor(rgb: (0.2, 0.23, 0.28)), true) : (Palette.text, Palette.dim, false)
    }

    func buildHUD() {
        hud.scaleMode = .resizeFill
        hud.backgroundColor = .clear
        hud.isUserInteractionEnabled = false
        infoLabel.fontSize = 13
        infoLabel.fontColor = Palette.text
        infoLabel.horizontalAlignmentMode = .left
        infoLabel.verticalAlignmentMode = .bottom
        infoBackground.anchorPoint = CGPoint(x: 0, y: 0)
        hud.addChild(infoBackground)
        hud.addChild(infoLabel)
        followLabel.fontSize = 13
        followLabel.fontColor = Palette.text
        followLabel.horizontalAlignmentMode = .center
        followLabel.verticalAlignmentMode = .bottom
        hud.addChild(followLabel)
        fpsLabel.fontSize = 10
        fpsLabel.fontColor = Palette.dim
        fpsLabel.horizontalAlignmentMode = .left
        fpsLabel.verticalAlignmentMode = .top
        hud.addChild(fpsLabel)
        statusLabel.fontSize = 10
        statusLabel.fontColor = Palette.dim
        statusLabel.horizontalAlignmentMode = .right
        statusLabel.verticalAlignmentMode = .bottom
        hud.addChild(statusLabel)
        bubbleLabel.fontSize = 11
        bubbleLabel.fontColor = Palette.text
        bubbleLabel.horizontalAlignmentMode = .center
        bubbleLabel.verticalAlignmentMode = .bottom
        bubbleLabel.zPosition = 2
        bubblePlate.zPosition = 1
        bubbleLabel.isHidden = true
        bubblePlate.isHidden = true
        bubbleName.fontSize = 13
        bubbleName.fontColor = Palette.text
        bubbleName.horizontalAlignmentMode = .center
        bubbleName.verticalAlignmentMode = .bottom
        bubbleName.zPosition = 2
        bubbleName.isHidden = true
        hud.addChild(bubblePlate)
        hud.addChild(bubbleLabel)
        hud.addChild(bubbleName)
        for o in LoungeOrder.allCases {
            let icon = SKSpriteNode(texture: o.texture, size: Self.iconSize)
            icon.colorBlendFactor = 1
            icon.color = o.color
            icon.zPosition = 2
            icon.isHidden = true
            hud.addChild(icon)
            bubbleIcons.append(icon)
        }
    }

    static let iconSize = CGSize(width: 20, height: 20)
    static let iconGap: CGFloat = 8

    func canOrder(_ m: Minion) -> Bool { simulation.takesOrders(m) }

    func bubbleTakes(point p: NSPoint) -> Bool {
        bubbleLock.lock(); defer { bubbleLock.unlock() }
        bubbleCursor = p
        return bubbleHits?.hold.contains(p) ?? false
    }

    func bubbleClick(at p: NSPoint) -> Bool {
        bubbleLock.lock(); defer { bubbleLock.unlock() }
        guard let hits = bubbleHits, hits.plate.contains(p) else { return false }
        if let i = hits.icons.firstIndex(where: { $0.contains(p) }) {
            let order = LoungeOrder.allCases[i]
            bubbleHits = nil
            enqueue { [self] in self.order(minionId: hits.minion, order); self.hovered = nil }
        }
        return true
    }

    func order(minionId: String, _ o: LoungeOrder) {
        guard let m = minions[minionId], let station = fleet.stations[m.station], canOrder(m) else { return }
        simulation.dropIdleTurn(m)
        switch o {
        case .gym:
            guard station.rooms["kind:gym"] != nil else { logEvent("\(m.home.name): no gym here"); return }
            guard takeTurnInGym(m, station: station) else { logEvent("\(m.home.name): every piece of gear is taken"); return }
        case .shower, .toilet:
            m.showering = o == .shower
            guard station.rooms["kind:bath"] != nil else { logEvent("\(m.home.name): no bath here"); return }
            guard visitBath(m, station: station) else { logEvent("\(m.home.name): the bath is taken"); return }
        case .read:
            send(m, to: .lounge)
        case .bed:
            send(m, to: .quarters)
            m.napping = m.place == .quarters
        case .coffee, .bite:
            guard station.galley != nil else { logEvent("\(m.home.name): no galley here"); return }
            guard visitGalley(m, station: station, fare: o == .coffee ? .coffee : .bite) else { logEvent("\(m.home.name): someone is at the galley"); return }
        }
        m.idle = IdleClock()
    }

    func updateBubble() {
        func hide() {
            bubbleLabel.isHidden = true; bubblePlate.isHidden = true; bubbleName.isHidden = true
            bubbleIcons.forEach { $0.isHidden = true }
            bubbleLock.lock(); bubbleHits = nil; bubbleLock.unlock()
        }
        guard let h = hovered, h.hasPrefix("minion:"), let m = minions[String(h.dropFirst(7))], m.opacity > 0.2 else { hide(); return }
        let head = v3(Double(m.node.position.x), Double(m.node.position.y) + m.headHeight + 0.35, Double(m.node.position.z))
        let p = view.projectPoint(head)
        guard p.z > 0, p.z < 1 else { hide(); return }
        let iw = Self.iconSize.width, ih = Self.iconSize.height, gap = Self.iconGap
        let rowWidth = iw * CGFloat(bubbleIcons.count) + gap * CGFloat(bubbleIcons.count - 1)
        let allowed = canOrder(m)
        bubbleLabel.position = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y) + (allowed ? ih + 8 : 0))
        bubbleLabel.isHidden = false
        bubbleLock.lock(); let cursor = bubbleCursor; bubbleLock.unlock()
        var rects: [CGRect] = []
        var picking: LoungeOrder?
        for (i, icon) in bubbleIcons.enumerated() {
            let x = CGFloat(p.x) - rowWidth / 2 + iw / 2 + CGFloat(i) * (iw + gap)
            icon.position = CGPoint(x: x, y: CGFloat(p.y) + ih / 2)
            let r = CGRect(x: x - iw / 2 - gap / 2, y: CGFloat(p.y) - 3, width: iw + gap, height: ih + 6)
            rects.append(r)
            let under = allowed && cursor.map { r.contains($0) } == true
            icon.color = under ? LoungeOrder.allCases[i].color.lighter(0.35) : LoungeOrder.allCases[i].color
            icon.isHidden = !allowed
            if under { picking = LoungeOrder.allCases[i] }
        }
        let whose = m.isCrew ? m.title.map { $0 + " · " } ?? "" : ""
        bubbleLabel.text = picking?.words ?? whose + (!allowed && (m.busy || m.onJob || m.hasLoad) ? "busy · " : "") + m.words
        bubbleName.text = m.callsign
        bubbleName.position = CGPoint(x: CGFloat(p.x), y: bubbleLabel.frame.maxY + 3)
        bubbleName.isHidden = false
        let row = allowed ? CGRect(x: CGFloat(p.x) - rowWidth / 2, y: CGFloat(p.y), width: rowWidth, height: ih) : bubbleLabel.frame
        let f = bubbleLabel.frame.union(bubbleName.frame).union(row).insetBy(dx: -8, dy: -5)
        bubblePlate.position = CGPoint(x: f.midX, y: f.midY)
        bubblePlate.size = f.size
        bubblePlate.isHidden = false
        let feet = view.projectPoint(m.node.position)
        let column = CGRect(x: CGFloat(p.x) - 28, y: min(CGFloat(feet.y), f.minY) - 6, width: 56, height: max(0, f.minY - CGFloat(feet.y)) + 6)
        bubbleLock.lock(); bubbleHits = (m.id, f, f.union(column), allowed ? rects : []); bubbleLock.unlock()
    }

    private func layoutLegend(active: [Minion], busy: Int, waiting: Int, asleep: Int) {
        let ours = fleet.stations.values.flatMap { st in st.rooms.values.filter { world.isOurs(st, $0) } }
        let repos = Set(ours.compactMap(\.repo)).filter { !$0.isEmpty }
            .sorted { (fleet.repoColors[$0] ?? .max, $0) < (fleet.repoColors[$1] ?? .max, $1) }
        let showTitles = ConfigStore.shared.current.showTitles
        let others = minions.values.filter { $0.isCrew && $0.state != .leaving && fleet.stations[$0.station] != nil }
        let teammates = others.filter { !$0.isPeer }.map(\.busy).sorted { $0 && !$1 }
        let neighbours = others.filter(\.isPeer).map(\.busy).sorted { $0 && !$1 }
        var signature = "\(hud.size.width)|\(busy)|\(waiting)|\(asleep)|\(showTitles)|\(teammates)|\(neighbours)|"
        let rootOf = Dictionary(world.repoRoots.map { ($0.value.repo, $0.key) }, uniquingKeysWith: { a, _ in a })
        for repo in repos {
            let offices = ours.filter { $0.repo == repo }.count
            let workers = active.filter { $0.home.repo == repo && !$0.isSubagent }.count
            let loading = rootOf[repo].map { github.isBusy(repoRoot: $0) } ?? false
            signature += "\(repo):\(workers):\(offices):\(loading);"
        }
        let inked = signature + "|" + Looks.theme.rawValue
        guard inked != legendSignature else { return }
        legendSignature = inked
        statusLabel.fontColor = ink.dim; followLabel.fontColor = ink.text
        legendNodes.forEach { $0.removeFromParent() }; legendNodes = []
        jobNodes.forEach { $0.removeFromParent() }; jobNodes = []
        let slot = hud.size.width / CGFloat(max(1, repos.count))
        for (i, repo) in repos.enumerated() where showTitles {
            let x = slot * (CGFloat(i) + 0.5)
            let name = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
            name.fontSize = 14
            name.fontColor = ink.onLight ? NSColor(fleet.color(forRepo: repo)).darker(0.35) : NSColor(fleet.color(forRepo: repo)).lighter(0.15)
            name.text = repo
            name.horizontalAlignmentMode = .center
            name.verticalAlignmentMode = .top
            name.position = CGPoint(x: x, y: hud.size.height - 34)
            let offices = ours.filter { $0.repo == repo }.count
            let workers = active.filter { $0.home.repo == repo && !$0.isSubagent }.count
            let counts = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
            counts.fontSize = 10
            counts.fontColor = ink.dim
            counts.text = "\(workers) minions · \(offices) offices"
            counts.horizontalAlignmentMode = .center
            counts.verticalAlignmentMode = .top
            counts.position = CGPoint(x: x, y: hud.size.height - 52)
            hud.addChild(name); hud.addChild(counts)
            legendNodes.append(name); legendNodes.append(counts)
            if rootOf[repo].map({ github.isBusy(repoRoot: $0) }) == true {
                let spinner = SKSpriteNode(color: name.fontColor ?? Palette.dim, size: CGSize(width: 7, height: 7))
                spinner.position = CGPoint(x: x + name.frame.width / 2 + 12, y: hud.size.height - 41)
                spinner.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1.1)))
                spinner.alpha = 0.85
                hud.addChild(spinner); legendNodes.append(spinner)
            }
        }
        let white = ink.onLight ? ink.text : Palette.minion
        let groups: [(title: String, figures: [(color: NSColor, lit: Bool)], color: NSColor)] = [
            ("neighbours", neighbours.map { (Suit.base(.neighbour), $0) }, Suit.base(.neighbour).lighter(0.15)),
            ("teammates", teammates.map { (Suit.base(.crew), $0) }, Suit.base(.crew).lighter(0.15)),
            ("at work", Array(repeating: (white, true), count: busy), NSColor(rgb: (0.35, 0.78, 0.85))),
            ("waiting for you", Array(repeating: (white, true), count: waiting), Palette.pyramid),
            ("asleep", Array(repeating: (white, true), count: asleep), NSColor(Colors.quarters).lighter(0.25)),
        ]
        var x: CGFloat = hud.size.width - 16
        for (i, group) in groups.enumerated().reversed() where i >= 2 || !group.figures.isEmpty {
            let icons = min(group.figures.count, 8)
            let iconsWidth = CGFloat(icons) * 8
            for (k, f) in group.figures.prefix(icons).enumerated() {
                let r = SKSpriteNode(color: f.color, size: CGSize(width: 4, height: 9))
                r.alpha = f.lit ? 1 : 0.35
                r.position = CGPoint(x: x - iconsWidth + CGFloat(k) * 8 + 4, y: 14)
                hud.addChild(r); jobNodes.append(r)
            }
            x -= iconsWidth + 6
            let l = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
            l.fontSize = 12
            l.fontColor = ink.onLight ? group.color.darker(0.4) : group.color
            l.text = "\(group.title) \(group.figures.count)"
            l.horizontalAlignmentMode = .right
            l.verticalAlignmentMode = .bottom
            l.position = CGPoint(x: x, y: 9)
            hud.addChild(l); jobNodes.append(l)
            x -= l.frame.width + (i == 2 ? 40 : 22)
        }
    }

    func logEvent(_ text: String) {
        let l = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
        l.fontSize = 11
        l.fontColor = ink.text
        l.horizontalAlignmentMode = .left
        l.verticalAlignmentMode = .top
        l.text = text
        hud.addChild(l)
        eventLabels.insert((l, clock), at: 0)
        while eventLabels.count > 5 { eventLabels.removeLast().0.removeFromParent() }
    }

    static func span(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 48 * 3600 { return "\(Int(s / 3600))h" }
        if s < 21 * 24 * 3600 { return "\(Int(s / (24 * 3600)))d" }
        return "\(Int(s / (7 * 24 * 3600)))w"
    }

    private func roomAge(station: Station, room: Room) -> String? {
        guard !room.key.hasPrefix("kind:") else { return nil }
        var opened = room.openedAt
        if let repo = room.repo, let issue = world.taskNumber(room), let at = github.work(repo: repo, number: issue)?.at { opened = min(opened, at) }
        let now = Date()
        let quiet = now.timeIntervalSince(room.lastActive)
        let age = StationController.span(now.timeIntervalSince(opened)) + " old"
        return quiet < 15 * 60 ? age : age + " · quiet " + StationController.span(quiet)
    }

    private func roomInfo(station: Station, room: Room) -> String {
        var parts = [room.name]
        if let age = roomAge(station: station, room: room) { parts.append(age) }
        if room.key.hasPrefix("proj:") { parts.append("no branch yet · checking one out builds the office") }
        let local = world.localState(room)
        if local.local { parts.append(local.commits == 0 ? "local branch, nothing committed · a research session" : "local branch, \(local.commits) commits not pushed") }
        if let info = world.crewRoomInfo[roomKey(station, room)], let rec = world.record(office: roomKey(station, room)) {
            var line = "by \(world.crewName(rec.author ?? "?")) · ⎇ \(rec.work().branch ?? rec.branches.sorted().first ?? "?")"
            if let n = rec.pulls.keys.min() { line += " · PR #\(n) \(info.state.lowercased())" }
            if let t = rec.title { line += " · " + t }
            parts.append(line)
        }
        if let claims = world.peerOffices[roomKey(station, room)], !claims.isEmpty {
            let who = claims.keys.sorted().joined(separator: ", ")
            parts.append((room.repo.map { $0 + " · " } ?? "") + (world.pushedByPeer.contains(roomKey(station, room)) ? "checked out by " : "local branch on ") + who)
        } else if world.isProvisional(station, room) && room.worktree == nil {
            parts.append("held for a while · nobody is working here right now")
        }
        if room.key == "kind:lounge" { parts.append("waiting on you for a while · they chat here before bed") }
        if let branch = room.branch, let root = room.repoRoot {
            parts.append("⎇ " + branch)
            if let pr = github.pulls.pull(branch: branch, repoRoot: root) { parts.append(pr.summary); parts.append(pr.title) }
            if let w = room.worktree, let n = github.git.commitsAhead(worktree: w) { parts.append("\(n) commits") }
            if let w = room.worktree, github.git.dirtyFiles(worktree: w) > 0 { parts.append("\(github.git.dirtyFiles(worktree: w)) files uncommitted") }
        }
        let here = minions.values.filter { $0.station == station.name && $0.place == .room(room.key) && $0.state != .leaving }
        let workspaces = Set(here.map { URL(fileURLWithPath: $0.cwd).lastPathComponent }).sorted()
        if !workspaces.isEmpty { parts.append(workspaces.joined(separator: ", ")) }
        return parts.joined(separator: "   ")
    }

    func updateInfo() {
        let active = minions.values.filter { $0.state != .leaving && !$0.isCrew && !$0.isSubagent && $0.freeSince == 0 && fleet.stations[$0.station] != nil }
        let busy = active.filter(\.busy).count
        let waiting = active.filter { $0.activity == .waiting && !$0.busy }.count
        let asleep = active.filter { $0.activity == .sleeping }.count
        statusLabel.text = liveTimeScale > 1 ? "\(Int(liveTimeScale))× · holding space" : ""
        statusLabel.horizontalAlignmentMode = .center
        statusLabel.fontSize = 13
        statusLabel.fontColor = Palette.pyramid
        statusLabel.position = CGPoint(x: hud.size.width / 2, y: 12)
        infoLabel.position = CGPoint(x: 14, y: 12)
        if let hint = walkHint {
            followLabel.text = hint
            followLabel.position = CGPoint(x: hud.size.width / 2, y: liveTimeScale > 1 ? 54 : 36)
        } else if let id = following, let m = minions[id] {
            followLabel.text = "following \(m.callsign)\(m.isCrew ? m.title.map { " (\($0))" } ?? "" : "") · \(m.home.name) · \(m.words) · esc to let go"
            followLabel.position = CGPoint(x: hud.size.width / 2, y: liveTimeScale > 1 ? 54 : 36)
        } else { followLabel.text = "" }

        if clock - hudClock > 0.5 {
            hudClock = clock
            layoutLegend(active: active, busy: busy, waiting: waiting, asleep: asleep)
            if !headless { placePlanets() }
            if spaceLogButton != nil, clock - spaceLogClock > 10 { spaceLogClock = clock; countUnreadSpaceLog() }
            if storyOf != nil, clock - storyClock > 5 { drawStory() }
            drawCard()
            drawSetupCheck()
            updateNeighbours()
        }

        var y = hud.size.height - 70
        eventLabels.removeAll { l, t in
            let age = clock - t
            if age > 14 { l.removeFromParent(); return true }
            l.alpha = age < 11 ? 1 : (14 - age) / 3
            l.position = CGPoint(x: 12, y: y)
            y -= 15
            return false
        }

        defer {
            let hasText = !(infoLabel.text ?? "").isEmpty
            infoBackground.isHidden = !hasText
            if hasText {
                let f = infoLabel.frame.insetBy(dx: -8, dy: -5)
                infoBackground.position = f.origin
                infoBackground.size = f.size
            }
        }
        guard let hRaw = hovered else { infoLabel.text = ""; return }
        let h = hRaw.hasPrefix("box:") ? "room:" + hRaw.dropFirst(4) : hRaw
        if h.hasPrefix("room:") {
            let parts = h.dropFirst(5).split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2, let station = fleet.stations[parts[0]], let r = station.rooms[parts[1]] {
                infoLabel.text = roomInfo(station: station, room: r)
            }
        } else if h.hasPrefix("minion:peer:") {
            let who = h.dropFirst("minion:peer:".count).split(separator: "/").first.map(String.init) ?? ""
            let m = minions[String(h.dropFirst(7))]
            infoLabel.text = ["\(who)'s minion", m.map { $0.home.repo }, m?.activity.label, "working on their own machine · shared on the local network"]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "   ")
        } else if h.hasPrefix("minion:") {
            if let m = minions[String(h.dropFirst(7))] {
                var parts: [String] = []
                if let t = m.title { parts.append(t) }
                parts.append(m.activity.label)
                parts.append(m.home.name)
                if let b = m.branch { parts.append("⎇ " + b) }
                parts.append(URL(fileURLWithPath: m.cwd).lastPathComponent)
                parts.append("\(m.toolCount) tool calls")
                if m.isSubagent { parts.append("subagent") }
                infoLabel.text = parts.joined(separator: "   ")
            }
        } else if h.hasPrefix("link:") {
            infoLabel.text = String(h.split(separator: "|", maxSplits: 1).last ?? "")
        } else if h.hasPrefix("rocket:") {
            let label = String(h.dropFirst(7).split(separator: "|", maxSplits: 1).last ?? "")
            let repo = label.components(separatedBy: " · ").first ?? ""
            let left = fleet.stations.values.lazy.compactMap { $0.facts.staging[repo]?.timeLeft(at: self.now) }.first
            infoLabel.text = left.map { label + " · staging build " + $0 } ?? label
        } else if h.hasPrefix("decon:"), h.split(separator: "|").count == 3, let n = Int(h.split(separator: "|")[2]), n > 0 {
            let repo = String(h.split(separator: "|")[1])
            infoLabel.text = "\(repo) · \(Words.current.unidentified) · PR #\(n) · merge clears it into \(Words.current.inStorage), closing ejects it · click for its story"
        } else if h.hasPrefix("decon:") {
            let name = String(h.dropFirst(6))
            let waiting = fleet.stations[name]?.facts.count(.decon) ?? 0
            infoLabel.text = Words.current.deconHover + " · " + (waiting == 0 ? "nothing unscreened" : waiting == 1 ? "one object unscreened" : "\(waiting) objects unscreened")
        } else if (h.hasPrefix("storage:") || h.hasPrefix("deck:")), h.split(separator: "|").count == 3, let n = Int(h.split(separator: "|")[2]), n > 0 {
            let repo = String(h.split(separator: "|")[1])
            let prs = github.pulls(repo: repo, task: n)
            let what = prs.isEmpty ? "PR #\(n)" : "issue #\(n) · " + prs.map { "PR #\($0)" }.joined(separator: ", ")
            var parts = ["\(repo) · \(what)"]
            let work = github.work(repo: repo, number: n)
            if let title = work?.title, !title.isEmpty { parts.append(title) }
            if let author = work?.author { parts.append("by " + world.crewName(author) + (author == github.myLogin() ? " · yours" : "")) }
            parts.append(h.hasPrefix("deck:") ? "on staging, waiting for production" : "merged, waiting for staging")
            let station = String(h.split(separator: "|")[0].split(separator: ":", maxSplits: 1).last ?? "")
            if let story = StationController.crateStory(world.log.history(station, CrateID(repo: repo, number: n))) { parts.append(story) }
            parts.append("click for its story")
            infoLabel.text = parts.joined(separator: " · ")
        } else if h.hasPrefix("storage:") {
            let name = String(h.dropFirst(8).split(separator: "|").first ?? "")
            let parts = (fleet.stations[name]?.stored ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
            infoLabel.text = Words.current.storage + " · " + (parts.isEmpty ? "empty" : parts.joined(separator: " · ")) + " · waiting for a release"
        } else if h.hasPrefix("peer:") {
            infoLabel.text = "\(h.dropFirst(5))'s station · shared on the local network"
        } else if h.hasPrefix("deck:") {
            let qa = minions.values.filter { $0.activity == .qa && $0.state != .leaving }.map { $0.home.name }
            if !qa.isEmpty { infoLabel.text = Words.current.testDeck + " · QA in progress: " + qa.joined(separator: ", "); return }
            let name = String(h.dropFirst(5).split(separator: "|").first ?? "")
            let parts = (fleet.stations[name]?.staged ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
            infoLabel.text = Words.current.testDeck + " · " + (parts.isEmpty ? "nothing on staging" : parts.joined(separator: " · ") + " on staging, in QA")
        } else if h.hasPrefix("pad:") {
            let name = String(h.dropFirst(4))
            let due = fleet.stations[name].map { st in
                Set(st.stored.keys).union(st.staged.keys).compactMap { repo -> String? in
                    let n = (world.stagingIsDeck(station: name, repo: repo) ? st.staged : st.stored)[repo] ?? 0
                    return n > 0 ? "\(n) \(repo)" : nil
                }.sorted()
            } ?? []
            infoLabel.text = Words.current.padHover + (due.isEmpty ? "" : " · cargo waiting: " + due.joined(separator: ", "))
        } else if h.hasPrefix("hangar:") {
            infoLabel.text = Words.current.bayHover
        } else if h.hasPrefix("station:") {
            infoLabel.text = String(h.dropFirst(8)) + " · " + Words.current.monolithHover
        } else {
            infoLabel.text = ""
        }
    }

    static func crateStory(_ history: [EventLog.Step]) -> String? {
        let steps = history.filter(\.moved).suffix(3)
        guard !steps.isEmpty else { return nil }
        return steps.enumerated().map { i, s in
            "\(stepWords(s)) \(i == steps.count - 1 ? "since " : "")\(hoverClock.string(from: s.at))"
        }.joined(separator: " · ")
    }

    private static let hoverClock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    private static func stepWords(_ s: EventLog.Step) -> String {
        guard let to = s.to else { return "gone" }
        return s.from?.place == to.place ? CrateStory.what(s) : CrateStory.place(to)
    }

    func openCrate(_ id: CrateID) {
        let repo = id.repo, n = id.number
        if let item = github.board.items?.first(where: { $0.repo == repo && $0.number == n }), let url = URL(string: item.url) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            return
        }
        guard let root = world.repoRoots.first(where: { $0.value.repo == repo })?.key, let owner = github.nameWithOwner(repoRoot: root),
              let url = URL(string: "https://github.com/\(owner)/\(github.pulls(repo: repo, task: n).isEmpty ? "pull" : "issues")/\(n)") else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }

    func open(named raw: String?) {
        if let raw, raw.hasPrefix("rocket:") || raw.hasPrefix("link:") {
            let link = String(raw.drop { $0 != ":" }.dropFirst().split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            if let u = URL(string: link), u.scheme?.hasPrefix("http") == true { DispatchQueue.main.async { NSWorkspace.shared.open(u) } }
            return
        }
        guard let raw, raw.hasPrefix("room:") || raw.hasPrefix("box:") else { return }
        let name = raw.hasPrefix("box:") ? "room:" + raw.dropFirst(4) : raw
        let parts = name.dropFirst(5).split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]] else { return }
        if world.crewRoomInfo[roomKey(station, room)] != nil, let u = world.record(office: roomKey(station, room))?.url.flatMap(URL.init(string:)) {
            DispatchQueue.main.async { NSWorkspace.shared.open(u) }
            return
        }
        guard let branch = room.branch, let root = room.repoRoot else { return }
        if world.localState(room).local { logEvent("\(room.name): not on github yet"); return }
        var url: URL?
        if let pr = github.pulls.pull(branch: branch, repoRoot: root), let u = URL(string: pr.url) {
            url = u
        } else if let owner = github.nameWithOwner(repoRoot: root) {
            if let m = branch.firstMatch(of: #/^gh-(\d+)\//#) {
                url = URL(string: "https://github.com/\(owner)/issues/\(m.1)")
            } else {
                url = URL(string: "https://github.com/\(owner)/tree/\(branch)")
            }
        }
        if let url { DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
    }

    func announce(_ text: String) {
        enqueue { [self] in logEvent(text); ringBell(seed: text.hashValue) }
    }
}
