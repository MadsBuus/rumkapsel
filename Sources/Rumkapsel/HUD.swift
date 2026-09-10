// The overlay: the legend, the log, the info panel and the hover bubble.

import AppKit
import SceneKit
import SpriteKit

extension StationController {
    // MARK: hud

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
        shareLabel.fontSize = 10
        shareLabel.fontColor = Palette.dim
        shareLabel.horizontalAlignmentMode = .right
        shareLabel.verticalAlignmentMode = .top
        hud.addChild(shareDot)
        hud.addChild(shareLabel)
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
        hud.addChild(bubblePlate)
        hud.addChild(bubbleLabel)
    }

    /// Hovering a minion holds it still and says what it is doing, above its head.
    func updateBubble() {
        guard let h = hovered, h.hasPrefix("minion:"), let m = minions[String(h.dropFirst(7))], m.opacity > 0.2 else {
            bubbleLabel.isHidden = true; bubblePlate.isHidden = true
            return
        }
        let head = v3(Double(m.node.position.x), Double(m.node.position.y) + m.headHeight + 0.35, Double(m.node.position.z))
        let p = view.projectPoint(head)
        guard p.z > 0, p.z < 1 else { bubbleLabel.isHidden = true; bubblePlate.isHidden = true; return }
        bubbleLabel.text = m.words
        bubbleLabel.position = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        bubbleLabel.isHidden = false
        let f = bubbleLabel.frame.insetBy(dx: -7, dy: -4)
        bubblePlate.position = CGPoint(x: f.midX, y: f.midY)
        bubblePlate.size = f.size
        bubblePlate.isHidden = false
    }

    /// Top: repos in their colours with counts. Bottom: jobs with one tiny minion per worker, like the game.
    private func layoutLegend(active: [Minion], busy: Int, waiting: Int, asleep: Int) {
        let withOffices = Set(fleet.stations.values.flatMap { $0.rooms.values.compactMap(\.repo) })
        let withRockets = Set(world.repoRoots.filter { github.openReleases(repoRoot: $0.key)?.isEmpty == false }.map(\.value.repo))
        let repos = fleet.repoColors.keys.filter { withOffices.contains($0) || withRockets.contains($0) }
            .sorted { fleet.repoColors[$0]! < fleet.repoColors[$1]! }
        guard !repos.isEmpty else { return }
        var signature = "\(hud.size.width)|\(busy)|\(waiting)|\(asleep)|"
        let rootOf = Dictionary(world.repoRoots.map { ($0.value.repo, $0.key) }, uniquingKeysWith: { a, _ in a })
        for repo in repos {
            let offices = fleet.stations.values.flatMap { $0.rooms.values }.filter { $0.repo == repo }.count
            let workers = active.filter { $0.home.repo == repo && !$0.isSubagent }.count
            let loading = rootOf[repo].map { github.isBusy(repoRoot: $0) } ?? false
            signature += "\(repo):\(workers):\(offices):\(loading);"
        }
        guard signature != legendSignature else { return }
        legendSignature = signature
        legendNodes.forEach { $0.removeFromParent() }; legendNodes = []
        jobNodes.forEach { $0.removeFromParent() }; jobNodes = []
        let slot = hud.size.width / CGFloat(repos.count)
        for (i, repo) in repos.enumerated() {
            let x = slot * (CGFloat(i) + 0.5)
            let name = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
            name.fontSize = 14
            name.fontColor = NSColor(fleet.color(forRepo: repo)).lighter(0.15)
            name.text = repo
            name.horizontalAlignmentMode = .center
            name.verticalAlignmentMode = .top
            name.position = CGPoint(x: x, y: hud.size.height - 34)
            let offices = fleet.stations.values.flatMap { $0.rooms.values }.filter { $0.repo == repo }.count
            let workers = active.filter { $0.home.repo == repo && !$0.isSubagent }.count
            let counts = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")
            counts.fontSize = 10
            counts.fontColor = Palette.dim
            counts.text = "\(workers) minions · \(offices) offices"
            counts.horizontalAlignmentMode = .center
            counts.verticalAlignmentMode = .top
            counts.position = CGPoint(x: x, y: hud.size.height - 52)
            hud.addChild(name); hud.addChild(counts)
            legendNodes.append(name); legendNodes.append(counts)
            // A small spinner beside the title while this repository is being refreshed from GitHub.
            if rootOf[repo].map({ github.isBusy(repoRoot: $0) }) == true {
                let spinner = SKSpriteNode(color: name.fontColor ?? Palette.dim, size: CGSize(width: 7, height: 7))
                spinner.position = CGPoint(x: x + name.frame.width / 2 + 12, y: hud.size.height - 41)
                spinner.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1.1)))
                spinner.alpha = 0.85
                hud.addChild(spinner); legendNodes.append(spinner)
            }
        }
        let jobs: [(String, Int, NSColor)] = [
            ("working", busy, NSColor(rgb: (0.35, 0.78, 0.85))),
            ("waiting", waiting, Palette.pyramid),
            ("sleeping", asleep, NSColor(Colors.quarters).lighter(0.25)),
        ]
        var x: CGFloat = hud.size.width - 16
        for (title, count, color) in jobs.reversed() {
            let icons = min(count, 8)
            let iconsWidth = CGFloat(icons) * 8
            for k in 0..<icons {
                let r = SKSpriteNode(color: Palette.minion, size: CGSize(width: 4, height: 9))
                r.position = CGPoint(x: x - iconsWidth + CGFloat(k) * 8 + 4, y: 14)
                hud.addChild(r); jobNodes.append(r)
            }
            x -= iconsWidth + 6
            let l = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
            l.fontSize = 12
            l.fontColor = color
            l.text = "\(title) \(count)"
            l.horizontalAlignmentMode = .right
            l.verticalAlignmentMode = .bottom
            l.position = CGPoint(x: x, y: 9)
            hud.addChild(l); jobNodes.append(l)
            x -= l.frame.width + 22
        }
    }

    func logEvent(_ text: String) {
        let l = SKLabelNode(fontNamed: "HelveticaNeue-Italic")
        l.fontSize = 11
        l.fontColor = Palette.text
        l.horizontalAlignmentMode = .left
        l.verticalAlignmentMode = .top
        l.text = text
        hud.addChild(l)
        eventLabels.insert((l, clock), at: 0)
        while eventLabels.count > 5 { eventLabels.removeLast().0.removeFromParent() }
    }

    private func roomInfo(station: Station, room: Room) -> String {
        var parts = [room.name]
        if room.key.hasPrefix("proj:") { parts.append("no branch yet · /start-issue or /grab-issue builds the office") }
        let local = world.localState(room)
        if local.local { parts.append(local.commits == 0 ? "local branch, nothing committed · a research session" : "local branch, \(local.commits) commits not pushed") }
        if let info = world.crewRoomInfo[roomKey(station, room)] {
            var line = "by \(world.crewName(info.author)) · ⎇ \(info.branch)"
            if let n = info.prNumber { line += " · PR #\(n) \(info.state.lowercased())" }
            if let t = info.title { line += " · " + t }
            parts.append(line)
        }
        if let claims = world.peerOffices[roomKey(station, room)], !claims.isEmpty {
            let who = claims.keys.sorted().joined(separator: ", ")
            parts.append((world.pushedByPeer.contains(roomKey(station, room)) ? "checked out by " : "local branch on ") + who)
        } else if world.isProvisional(station, room) && room.worktree == nil {
            parts.append("held for a while · nobody is working here right now")
        }
        if room.key == "kind:bots" { parts.append("dependabot and friends") }
        if room.key == "kind:lounge" { parts.append("waiting on you for a while · they chat here before bed") }
        if let branch = room.branch, let root = room.repoRoot {
            parts.append("⎇ " + branch)
            if let pr = github.pull(branch: branch, repoRoot: root) { parts.append(pr.summary); parts.append(pr.title) }
            if let w = room.worktree, let n = github.commitsAhead(worktree: w) { parts.append("\(n) commits") }
            if let w = room.worktree, github.dirtyFiles(worktree: w) > 0 { parts.append("\(github.dirtyFiles(worktree: w)) files uncommitted") }
        }
        let here = minions.values.filter { $0.station == station.name && $0.place == .room(room.key) && $0.state != .leaving }
        let workspaces = Set(here.map { URL(fileURLWithPath: $0.cwd).lastPathComponent }).sorted()
        if !workspaces.isEmpty { parts.append(workspaces.joined(separator: ", ")) }
        return parts.joined(separator: "   ")
    }

    func updateInfo() {
        let active = minions.values.filter { $0.state != .leaving }
        let busy = active.filter(\.busy).count
        let waiting = active.filter { $0.activity == .waiting }.count
        let asleep = active.filter { $0.activity == .sleeping }.count
        statusLabel.text = ""
        infoLabel.position = CGPoint(x: 14, y: 12)

        if clock - hudClock > 0.5 {
            hudClock = clock
            layoutLegend(active: active, busy: busy, waiting: waiting, asleep: asleep)
            // Sharing indicator: green dot when broadcasting, with how many stations are in range.
            let sharing = peers.isRunning
            shareDot.isHidden = !sharing
            shareLabel.isHidden = !sharing
            if sharing {
                // Grey without a network, amber while looking, green once someone answers.
                let n = world.peerSnapshots.count
                let up = peers.networkUp
                let status = !up ? "no network" : n > 0 ? "\(n) peer\(n == 1 ? "" : "s") in range" : "nobody in range"
                shareLabel.text = "sharing as \(peers.name) · " + status
                shareDot.color = !up ? NSColor(rgb: (0.45, 0.46, 0.5)) : n > 0 ? NSColor(rgb: (0.35, 0.85, 0.5)) : NSColor(rgb: (0.9, 0.7, 0.3))
                shareLabel.position = CGPoint(x: hud.size.width - 14, y: hud.size.height - 14)
                shareDot.position = CGPoint(x: hud.size.width - 14 - shareLabel.frame.width - 10, y: hud.size.height - 19)
                shareDot.alpha = n > 0 && up ? 0.7 + 0.3 * sin(clock * 2) : 0.8
            }
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
        } else if h.hasPrefix("rocket:") {
            infoLabel.text = String(h.dropFirst(7).split(separator: "|", maxSplits: 1).last ?? "")
        } else if (h.hasPrefix("storage:") || h.hasPrefix("deck:")), h.split(separator: "|").count == 3, let n = Int(h.split(separator: "|")[2]), n > 0 {
            let parts = h.split(separator: "|")
            infoLabel.text = "\(parts[1]) · PR #\(n) · \(h.hasPrefix("deck:") ? "on staging, waiting for production" : "merged, waiting for staging") · click to open"
        } else if h.hasPrefix("storage:") {
            let name = String(h.dropFirst(8).split(separator: "|").first ?? "")
            let parts = (fleet.stations[name]?.stored ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
            infoLabel.text = "storage · " + (parts.isEmpty ? "empty" : parts.joined(separator: " · ")) + " · waiting for a release"
        } else if h.hasPrefix("peer:") {
            infoLabel.text = "\(h.dropFirst(5))'s station · shared on the local network"
        } else if h.hasPrefix("deck:") {
            let qa = minions.values.filter { $0.activity == .qa && $0.state != .leaving }.map { $0.home.name }
            if !qa.isEmpty { infoLabel.text = "test deck · QA in progress: " + qa.joined(separator: ", "); return }
            let name = String(h.dropFirst(5).split(separator: "|").first ?? "")
            let parts = (fleet.stations[name]?.staged ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
            infoLabel.text = "test deck · " + (parts.isEmpty ? "nothing on staging" : parts.joined(separator: " · ") + " on staging, in QA")
        } else if h.hasPrefix("pad:") {
            let name = String(h.dropFirst(4))
            let due = (ConfigStore.shared.current.stagingBranch.isEmpty ? fleet.stations[name]?.stored : fleet.stations[name]?.staged)?.filter { $0.value > 0 }.map { "\($0.value) \($0.key)" }.sorted() ?? []
            infoLabel.text = "launch pad · release pull requests wait here; merging launches" + (due.isEmpty ? "" : " · cargo waiting: " + due.joined(separator: ", "))
        } else if h.hasPrefix("hangar:") {
            infoLabel.text = "hangar · new offices arrive here by ship"
        } else if h.hasPrefix("station:") {
            infoLabel.text = String(h.dropFirst(8)) + " · the monolith: web research and subagents"
        } else {
            infoLabel.text = ""
        }
    }

    /// A crate in storage or on the deck opens its pull request.
    func openCargo(named name: String) {
        let parts = name.split(separator: "|").map(String.init)
        guard parts.count == 3, let n = Int(parts[2]), n > 0 else { return }
        let repo = parts[1]
        if let item = github.projectItems()?.first(where: { $0.repo == repo && $0.number == n }), let url = URL(string: item.url) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            return
        }
        guard let root = world.repoRoots.first(where: { $0.value.repo == repo })?.key, let owner = github.nameWithOwner(repoRoot: root),
              let url = URL(string: "https://github.com/\(owner)/pull/\(n)") else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }

    func open(named raw: String?) {
        if let raw, raw.hasPrefix("rocket:"), let u = URL(string: String(raw.dropFirst(7).split(separator: "|", maxSplits: 1).first ?? "")) {
            DispatchQueue.main.async { NSWorkspace.shared.open(u) }
            return
        }
        guard let raw, raw.hasPrefix("room:") || raw.hasPrefix("box:") else { return }
        let name = raw.hasPrefix("box:") ? "room:" + raw.dropFirst(4) : raw
        let parts = name.dropFirst(5).split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]] else { return }
        if let info = world.crewRoomInfo[roomKey(station, room)], let u = info.url.flatMap(URL.init(string:)) {
            DispatchQueue.main.async { NSWorkspace.shared.open(u) }
            return
        }
        guard let branch = room.branch, let root = room.repoRoot else { return }
        if world.localState(room).local { logEvent("\(room.name): not on github yet"); return }
        var url: URL?
        if let pr = github.pull(branch: branch, repoRoot: root), let u = URL(string: pr.url) {
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

    /// A line in the station log from outside the scene, such as an update notice.
    func announce(_ text: String) {
        enqueue { [self] in logEvent(text); ringBell(seed: text.hashValue) }
    }
}
