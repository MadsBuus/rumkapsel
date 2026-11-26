import AppKit

enum RepoAct { case folder, terminal, github, hide, trash }
struct RepoPick { let repo: String }

extension StationController {
    // MARK: repo details

    func installRepoPanel() {
        let w = view.bounds.width
        let panel = RepoPanel(frame: NSRect(x: w - 472, y: 40, width: 460, height: max(200, view.bounds.height - 110)))
        panel.autoresizingMask = [.minXMargin, .height]
        panel.isHidden = true
        panel.onAct = { [weak self] act in self?.enqueue { self?.repoAct(act) } }
        panel.onPick = { [weak self] repo in self?.enqueue { self?.openRepo(repo) } }
        view.addSubview(panel)
        repoPanel = panel
    }

    func titleClick(at p: NSPoint) -> Bool {
        bubbleLock.lock(); let repo = titleHits.first { $0.rect.contains(p) }?.repo; let more = moreTitlesHit?.contains(p) == true; bubbleLock.unlock()
        if more { enqueue { [self] in openRepoList() }; return true }
        guard let repo else { return false }
        enqueue { [self] in openRepo(repo) }
        return true
    }

    func openRepoList() {
        let ours = fleet.stations.values.flatMap { st in st.rooms.values.filter { world.isOurs(st, $0) } }
        let rows = stationRepos().map { r in
            RepoPanel.Row(repo: r.repo, color: NSColor(fleet.color(forRepo: r.repo)), lastActive: r.lastActive, offices: ours.filter { $0.repo == r.repo }.count)
        }
        repoOf = nil
        let now = world.now
        DispatchQueue.main.async { [self] in
            closeStory()
            closePoster()
            if spaceLogPanel?.isHidden == false { toggleSpaceLog() }
            if neighboursPanel?.isHidden == false { toggleNeighbours() }
            repoPanel?.showList(rows, now: now)
            repoPanel?.isHidden = false
        }
    }

    func openRepo(_ repo: String) {
        guard let facts = repoFacts(repo) else { return }
        repoOf = repo
        let color = NSColor(fleet.color(forRepo: repo))
        DispatchQueue.main.async { [self] in
            closeStory()
            closePoster()
            if spaceLogPanel?.isHidden == false { toggleSpaceLog() }
            if neighboursPanel?.isHidden == false { toggleNeighbours() }
            repoPanel?.show(facts, color: color, now: world.now)
            repoPanel?.isHidden = false
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let git = RepoFolder.readGit(root: facts.root) { github.run($0, cwd: $1) }
            enqueue { [self] in
                guard repoOf == repo, var now = repoFacts(repo) else { return }
                now.git = git
                DispatchQueue.main.async { [self] in
                    guard repoPanel?.isHidden == false else { return }
                    repoPanel?.show(now, color: color, now: world.now)
                }
            }
        }
    }

    private func repoFacts(_ repo: String) -> RepoFolder? {
        guard let root = world.root(ofRepo: repo) else { return nil }
        let rooms = fleet.stations.values.flatMap { st in st.rooms.values.filter { $0.repo == repo && world.isOurs(st, $0) } }
        let crates = fleet.stations.values.reduce(0) { n, st in n + st.facts.crates.keys.filter { $0.repo == repo }.count }
        let p = github.pipelineRead(repoRoot: root) ? github.pipeline(repoRoot: root) : nil
        return RepoFolder(repo: repo, root: root, via: world.repoVia[repo], lastSession: world.repoLastSession[repo], lastActive: world.lastActive(repo: repo),
                         offices: rooms.count, crates: crates, github: github.nameWithOwner(repoRoot: root),
                         way: p.map { Setup.way($0) + ($0.why.isEmpty ? "" : ": \($0.why)") })
    }

    func closeRepoPanel() {
        repoPanel?.isHidden = true
        enqueue { [self] in repoOf = nil }
    }

    func repoPanelTakes(point p: NSPoint) -> Bool {
        guard let panel = repoPanel, !panel.isHidden else { return false }
        return panel.frame.contains(p)
    }

    private func repoAct(_ act: RepoAct) {
        guard let repo = repoOf, let facts = repoFacts(repo) else { return }
        let url = URL(fileURLWithPath: facts.root, isDirectory: true)
        switch act {
        case .folder: DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        case .terminal:
            DispatchQueue.main.async {
                guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
                NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
            }
        case .github:
            guard let owner = facts.github, let u = URL(string: "https://github.com/\(owner)") else { return }
            DispatchQueue.main.async { NSWorkspace.shared.open(u) }
        case .hide:
            DispatchQueue.main.async { [self] in
                closeRepoPanel()
                ConfigStore.shared.update(byUser: true) { c in
                    var o = c.repos[repo] ?? AppConfig.RepoOverride()
                    o.shown = false; o.answered = true
                    c.repos[repo] = o
                }
            }
        case .trash:
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let unsaved = RepoFolder(repo: repo, root: facts.root, lastActive: facts.lastActive,
                                        git: RepoFolder.readGit(root: facts.root) { github.run($0, cwd: $1) }).unsaved()
                DispatchQueue.main.async { [self] in confirmTrash(repo: repo, url: url, unsaved: unsaved) }
            }
        }
    }

    private func confirmTrash(repo: String, url: URL, unsaved: [String]) {
        let alert = NSAlert()
        alert.messageText = "Move \(repo) to the Trash?"
        alert.informativeText = (url.path as NSString).abbreviatingWithTildeInPath + ", with every worktree inside it, goes to the Trash."
            + (unsaved.isEmpty ? " Everything in it is committed and pushed." : "\n\nIt still holds work found nowhere else:\n• " + unsaved.joined(separator: "\n• "))
        alert.alertStyle = unsaved.isEmpty ? .informational : .critical
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            let failed = NSAlert()
            failed.messageText = "\(repo) stays where it is"
            failed.informativeText = error.localizedDescription
            failed.runModal()
            return
        }
        StationLog.write("event", "repo \(repo) moved to the Trash from \(url.path)")
        closeRepoPanel()
        enqueue { [self] in
            world.forget(repo: repo)
            legendSignature = ""
            handle([.layoutChanged])
        }
    }
}

final class RepoPanel: NSView {
    private let text = LinkedText()
    private let scroll = NSScrollView()
    var onAct: ((RepoAct) -> Void)?
    var onPick: ((String) -> Void)?

    struct Row { let repo: String; let color: NSColor; let lastActive: Date; let offices: Int }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        scroll.frame = bounds.insetBy(dx: 10, dy: 6)
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .light
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 14, height: 12)
        text.autoresizingMask = [.width]
        text.frame = NSRect(origin: .zero, size: scroll.contentSize)
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.onGo = { [weak self] t in if let pick = t as? RepoPick { self?.onPick?(pick.repo) } }
        scroll.documentView = text
        addSubview(scroll)
        actions.frame = NSRect(x: bounds.width - 150, y: bounds.height - 46, width: 120, height: 26)
        actions.autoresizingMask = [.minXMargin, .minYMargin]
        actions.appearance = NSAppearance(named: .darkAqua)
        actions.bezelStyle = .recessed
        actions.isHidden = true
        addSubview(actions)
    }
    required init?(coder: NSCoder) { fatalError() }

    private let actions = NSPopUpButton(frame: .zero, pullsDown: true)

    private func fillActions(github: Bool) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Actions", action: nil, keyEquivalent: "")
        var groups: [[(String, RepoAct)]] = [[("Open the Folder", .folder), ("Open in Terminal", .terminal)] + (github ? [("Open on GitHub", .github)] : []),
                                             [("Hide from the Station", .hide)], [("Move to Trash…", .trash)]]
        groups = groups.filter { !$0.isEmpty }
        for (i, group) in groups.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            for (title, act) in group {
                let item = NSMenuItem(title: title, action: #selector(picked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = act
                menu.addItem(item)
            }
        }
        actions.menu = menu
    }

    @objc private func picked(_ item: NSMenuItem) {
        if let act = item.representedObject as? RepoAct { onAct?(act) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let deep = Palette.void
        NSGradient(colors: [deep.withAlphaComponent(0), deep.withAlphaComponent(0.7), deep.withAlphaComponent(0.88), deep.withAlphaComponent(0.92)],
                   atLocations: [0, 0.07, 0.2, 1], colorSpace: .deviceRGB)!.draw(in: bounds, angle: 0)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    func show(_ f: RepoFolder, color: NSColor, now: Date) {
        let out = NSMutableAttributedString()
        func add(_ s: String, _ attrs: [NSAttributedString.Key: Any]) { out.append(NSAttributedString(string: s, attributes: attrs)) }
        let indent: CGFloat = 30
        func para(spacing: CGFloat = 3, before: CGFloat = 0) -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle(); p.firstLineHeadIndent = indent; p.headIndent = indent; p.paragraphSpacing = spacing; p.paragraphSpacingBefore = before
            return p
        }

        let head = NSMutableParagraphStyle()
        head.headIndent = indent; head.tabStops = [NSTextTab(textAlignment: .left, location: indent)]; head.paragraphSpacing = 3
        let mark = NSTextAttachment()
        let g = SpaceLogStyle.glyph(.office, color: color, size: 18)
        mark.image = g
        mark.bounds = NSRect(x: 0, y: -2, width: g.size.width, height: g.size.height)
        out.append(NSAttributedString(attachment: mark))
        add("\t", [.font: NSFont.systemFont(ofSize: 18), .paragraphStyle: head])
        add(f.repo + "\n", [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: Palette.text, .paragraphStyle: head])
        add((f.root as NSString).abbreviatingWithTildeInPath + "\n", [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.dim, .paragraphStyle: para(spacing: 18)])
        fillActions(github: f.github != nil)
        actions.isHidden = false

        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: Palette.text, .paragraphStyle: para(spacing: 10)]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.dim, .paragraphStyle: para()]
        add(f.whyHere(window: StationController.scanWindow, now: now) + "\n", big)

        var when: [String] = []
        if let s = f.lastSession { when.append("Last Claude session \(RepoFolder.words(now.timeIntervalSince(s))) ago") }
        if let g = f.git {
            if let c = g.lastCommit { when.append("last commit \(RepoFolder.words(now.timeIntervalSince(c))) ago") }
            if let own = g.lastOwnCommit { when.append("yours \(RepoFolder.words(now.timeIntervalSince(own))) ago") }
            else if g.remote != nil { when.append("you never committed here") }
        }
        if !when.isEmpty { add(Self.sentence(when.joined(separator: ", ")) + ".\n", big) }

        if f.git == nil {
            add("Looking through the folder…\n", [.font: SpaceLogStyle.italic(12), .foregroundColor: Palette.dim, .paragraphStyle: para(spacing: 10)])
        } else {
            if let advice = f.advice(now: now) {
                add(advice + "\n", [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: SpaceLogStyle.amber, .paragraphStyle: para(spacing: 10)])
            }
            let unsaved = f.unsaved()
            if unsaved.isEmpty {
                add("Everything here is committed and pushed.\n", [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: RepoStatus.calm.color, .paragraphStyle: para(spacing: 10)])
            } else {
                for u in unsaved { add("• " + Self.sentence(u) + "\n", [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: SpaceLogStyle.amber, .paragraphStyle: para()]) }
                add("\n", [.font: NSFont.systemFont(ofSize: 6), .paragraphStyle: para()])
            }
        }

        var station = ["\(f.offices) office\(f.offices == 1 ? "" : "s")", "\(f.crates) \(f.crates == 1 ? Words.current.crate : Words.current.crates)"]
        if let g = f.git { station.append("\(g.branches) branch\(g.branches == 1 ? "" : "es")"); if g.worktrees > 0 { station.append("\(g.worktrees) worktree\(g.worktrees == 1 ? "" : "s")") } }
        add(Self.sentence(station.joined(separator: " · ")) + "\n", small)
        if let way = f.way { add(Self.sentence(way) + "\n", small) }
        if let gh = f.github { add("On GitHub as \(gh)\n", small) } else if let remote = f.git?.remote { add("Remote \(remote)\n", small) } else if f.git != nil { add("No remote: this folder is the only copy\n", small) }

        text.textStorage?.setAttributedString(out)
        needsDisplay = true
    }

    func showList(_ rows: [Row], now: Date) {
        actions.isHidden = true
        let out = NSMutableAttributedString()
        func add(_ s: String, _ attrs: [NSAttributedString.Key: Any]) { out.append(NSAttributedString(string: s, attributes: attrs)) }
        let indent: CGFloat = 30
        let title = NSMutableParagraphStyle(); title.firstLineHeadIndent = indent; title.headIndent = indent; title.paragraphSpacing = 16
        add("Repositories on the station\n", [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: Palette.text, .paragraphStyle: title])
        for r in rows {
            let head = NSMutableParagraphStyle()
            head.headIndent = indent; head.tabStops = [NSTextTab(textAlignment: .left, location: indent)]; head.paragraphSpacing = 1
            let mark = NSTextAttachment()
            let g = SpaceLogStyle.glyph(.office, color: r.color, size: 15)
            mark.image = g
            mark.bounds = NSRect(x: 0, y: -2, width: g.size.width, height: g.size.height)
            let pick: [NSAttributedString.Key: Any] = [LinkedText.target: RepoPick(repo: r.repo), .paragraphStyle: head]
            out.append(NSAttributedString(attachment: mark))
            add("\t", pick.merging([.font: NSFont.systemFont(ofSize: 15)]) { _, n in n })
            add(r.repo + "\n", pick.merging([.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: Palette.text]) { _, n in n })
            let small = NSMutableParagraphStyle(); small.firstLineHeadIndent = indent; small.headIndent = indent; small.paragraphSpacing = 10
            let when = r.lastActive == .distantPast ? "no Claude session yet" : "last here \(RepoFolder.words(now.timeIntervalSince(r.lastActive))) ago"
            add("\(Self.sentence(when)) · \(r.offices) office\(r.offices == 1 ? "" : "s")\n",
                [LinkedText.target: RepoPick(repo: r.repo), .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.dim, .paragraphStyle: small])
        }
        text.textStorage?.setAttributedString(out)
        needsDisplay = true
    }

    private static func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}
