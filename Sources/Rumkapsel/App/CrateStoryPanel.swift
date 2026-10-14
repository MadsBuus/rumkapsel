import AppKit

struct CrateStoryFacts {
    let id: CrateID
    let title: String?
    let color: NSColor
    let told: CrateStory.Told
}

extension StationController {
    // MARK: crate story

    func installStory() {
        let w = view.bounds.width
        let panel = CrateStoryPanel(frame: NSRect(x: w - 472, y: 40, width: 460, height: max(200, view.bounds.height - 110)))
        panel.autoresizingMask = [.minXMargin, .height]
        panel.isHidden = true
        panel.onGo = { [weak self] id in self?.enqueue { self?.openCrate(id) } }
        view.addSubview(panel)
        storyPanel = panel
    }

    static func crate(named name: String) -> (station: String, id: CrateID)? {
        let parts = name.split(separator: "|").map(String.init)
        guard ["storage:", "deck:", "decon:"].contains(where: name.hasPrefix), parts.count == 3, let n = Int(parts[2]), n > 0 else { return nil }
        return (String(parts[0].split(separator: ":", maxSplits: 1).last ?? ""), CrateID(repo: parts[1], number: n))
    }

    func storyCrate(named name: String) -> (station: String, id: CrateID)? {
        if let found = StationController.crate(named: name) { return found }
        guard name.hasPrefix("box:") else { return nil }
        let key = name.dropFirst(4).split(separator: "|", maxSplits: 1).map(String.init)
        guard key.count == 2, let station = fleet.stations[key[0]] else { return nil }
        if let id = station.facts.offices[key[1]]?.crate { return (station.name, id) }
        guard let room = station.rooms[key[1]], let repo = room.repo, let n = world.taskNumber(room) else { return nil }
        return (station.name, CrateID(repo: repo, number: n))
    }

    func openStory(_ id: CrateID) {
        let station = fleet.stations.values.sorted { $0.name < $1.name }.first { $0.facts.crates[id] != nil }?.name ?? "work"
        openStory(station, id)
    }

    func openStory(_ station: String, _ id: CrateID) {
        storyOf = (station, id)
        drawStory(reveal: true)
        DispatchQueue.main.async { [self] in
            if spaceLogPanel?.isHidden == false { toggleSpaceLog() }
            if neighboursPanel?.isHidden == false { toggleNeighbours() }
        }
    }

    func closeStory() {
        storyPanel?.isHidden = true
        enqueue { [self] in storyOf = nil }
    }

    func drawStory(reveal: Bool = false) {
        guard let (station, id) = storyOf else { return }
        storyClock = clock
        let told = CrateStory.tell(world.log.history(station, id), now: world.now, current: fleet.stations[station]?.facts.crates[id])
        let facts = CrateStoryFacts(id: id, title: crateWords(repo: id.repo, number: id.number).title, color: NSColor(fleet.color(forRepo: id.repo)), told: told)
        DispatchQueue.main.async { [self] in
            guard let panel = storyPanel, reveal || !panel.isHidden else { return }
            panel.show(facts, fromEnd: reveal)
            panel.isHidden = false
        }
    }

    func storyTakes(point p: NSPoint) -> Bool {
        guard let panel = storyPanel, !panel.isHidden else { return false }
        return panel.frame.contains(p)
    }
}

final class CrateStoryPanel: NSView {
    private let text = LinkedText()
    private let scroll = NSScrollView()
    var onGo: ((CrateID) -> Void)? {
        didSet { text.onGo = { [weak self] t in if let id = t as? CrateID { self?.onGo?(id) } } }
    }

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
        scroll.documentView = text
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let deep = Palette.void
        NSGradient(colors: [deep.withAlphaComponent(0), deep.withAlphaComponent(0.7), deep.withAlphaComponent(0.88), deep.withAlphaComponent(0.92)],
                   atLocations: [0, 0.07, 0.2, 1], colorSpace: .deviceRGB)!.draw(in: bounds, angle: 0)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    private static func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    func show(_ f: CrateStoryFacts, fromEnd: Bool) {
        let scrolled = scroll.contentView.bounds.origin
        let out = NSMutableAttributedString()
        func add(_ s: String, _ attrs: [NSAttributedString.Key: Any]) { out.append(NSAttributedString(string: s, attributes: attrs)) }
        let indent: CGFloat = 30, column: CGFloat = 78

        let head = NSMutableParagraphStyle()
        head.headIndent = indent; head.tabStops = [NSTextTab(textAlignment: .left, location: indent)]; head.paragraphSpacing = 3
        let link: [NSAttributedString.Key: Any] = [LinkedText.target: f.id, .paragraphStyle: head]
        let mark = NSTextAttachment()
        let g = SpaceLogStyle.glyph(.crate, color: f.color, size: 18)
        mark.image = g
        mark.bounds = NSRect(x: 0, y: -2, width: g.size.width, height: g.size.height)
        out.append(NSAttributedString(attachment: mark))
        add("\t", link.merging([.font: NSFont.systemFont(ofSize: 18)]) { _, n in n })
        add("\(f.id.repo) #\(f.id.number)\n", link.merging([.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: Palette.text]) { _, n in n })
        let sub = NSMutableParagraphStyle()
        sub.firstLineHeadIndent = indent; sub.headIndent = indent; sub.paragraphSpacing = 20
        if let title = f.title {
            add(title + "\n", [LinkedText.target: f.id, .font: NSFont.systemFont(ofSize: 13), .foregroundColor: Palette.text.withAlphaComponent(0.8), .paragraphStyle: sub])
        } else {
            add("\n", [.font: NSFont.systemFont(ofSize: 6), .paragraphStyle: sub])
        }

        if f.told.lines.isEmpty {
            let p = NSMutableParagraphStyle(); p.firstLineHeadIndent = indent; p.headIndent = indent
            add("Nothing in the log for this \(Words.current.crate) yet.\n", [.font: SpaceLogStyle.italic(12), .foregroundColor: Palette.dim, .paragraphStyle: p])
        }
        for line in f.told.lines {
            switch line {
            case .step(let at, let what, let why):
                let p = NSMutableParagraphStyle()
                p.headIndent = column; p.tabStops = [NSTextTab(textAlignment: .left, location: column)]; p.paragraphSpacing = 1
                add(at, [.font: SpaceLogStyle.mono(10.5), .foregroundColor: Palette.dim.withAlphaComponent(0.85), .paragraphStyle: p])
                add("\t" + Self.sentence(what) + "\n", [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: Palette.text, .paragraphStyle: p])
                let small = NSMutableParagraphStyle()
                small.firstLineHeadIndent = column; small.headIndent = column; small.paragraphSpacing = 4
                add((why.isEmpty ? " " : why) + "\n", [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: Palette.dim, .paragraphStyle: small])
            case .wait(let words):
                let p = NSMutableParagraphStyle()
                p.firstLineHeadIndent = column + 14; p.headIndent = column + 14; p.paragraphSpacingBefore = 2; p.paragraphSpacing = 8
                add(words + "\n", [.font: SpaceLogStyle.italic(12), .foregroundColor: SpaceLogStyle.amber.withAlphaComponent(0.7), .paragraphStyle: p])
            }
        }
        if let footer = f.told.footer {
            let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = 16; p.firstLineHeadIndent = indent; p.headIndent = indent
            add(Self.sentence(footer) + "\n", [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: SpaceLogStyle.amber, .paragraphStyle: p])
        }
        text.textStorage?.setAttributedString(out)
        if fromEnd {
            text.layoutManager?.ensureLayout(for: text.textContainer!)
            text.sizeToFit()
            text.scrollToEndOfDocument(nil)
        } else {
            scroll.contentView.scroll(to: scrolled)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        needsDisplay = true
    }
}
