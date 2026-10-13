import AppKit

struct NeighbourFacts {
    struct Office { let key: String; let name: String; let color: NSColor; let atWork: Int; let pull: Int?; let pullState: String? }
    struct Neighbour {
        let name: String
        let reaching: Bool, reachedBy: Bool
        let arrival: PeerHub.Arrival?
        let offices: [Office]
    }
    enum Light { case linked, waiting, off }

    var name = ""
    var problem: (String, String)?
    var offered: [Office] = []
    var neighbours: [Neighbour] = []
    var near: [String] = []
    var comings: [(at: Date, words: String)] = []
    var light = Light.off
}

extension StationController {
    // MARK: neighbours

    func installNeighbours() {
        let button = NeighboursButton(frame: NSRect(x: 0, y: view.bounds.height - 28, width: 90, height: 20))
        button.autoresizingMask = [.minXMargin, .minYMargin]
        button.onClick = { [weak self] in self?.toggleNeighbours() }
        button.onResize = { [weak self, weak button] in
            guard let self, let button, let host = button.superview else { return }
            button.setFrameOrigin(NSPoint(x: host.bounds.width - 12 - self.spaceLogCorner - 8 - button.frame.width, y: button.frame.minY))
        }
        button.isHidden = true
        let w = view.bounds.width
        let panel = NeighboursPanel(frame: NSRect(x: w - 472, y: 40, width: 460, height: max(200, view.bounds.height - 110)))
        panel.autoresizingMask = [.minXMargin, .height]
        panel.isHidden = true
        panel.onGo = { [weak self] key in self?.lookAtNeighbourOffice(key) }
        view.addSubview(panel)
        view.addSubview(button)
        neighboursButton = button
        neighboursPanel = panel
        button.onResize?()
    }

    func toggleNeighbours() {
        guard let panel = neighboursPanel else { return }
        if panel.isHidden {
            if spaceLogPanel?.isHidden == false { toggleSpaceLog() }
            panel.isHidden = false
        } else {
            panel.isHidden = true
        }
        neighboursButton?.open = !panel.isHidden
        let open = !panel.isHidden
        enqueue { [self] in
            neighboursOpen = open
            if open { updateNeighbours() }
        }
    }

    func updateNeighbours() {
        let sharing = peers.isRunning
        guard sharing else {
            DispatchQueue.main.async { [self] in
                neighboursButton?.isHidden = true
                if neighboursPanel?.isHidden == false { toggleNeighbours() }
            }
            return
        }
        let open = neighboursOpen
        let facts = open ? neighbourFacts() : nil
        let count = world.peerSnapshots.count
        let light: NeighbourFacts.Light = !peers.networkUp || peers.blocked ? .off : count > 0 ? .linked : .waiting
        DispatchQueue.main.async { [self] in
            neighboursButton?.isHidden = false
            neighboursButton?.show(count: count, light: light)
            if let facts { neighboursPanel?.show(facts) }
        }
    }

    private func neighbourFacts() -> NeighbourFacts {
        var f = NeighbourFacts()
        f.name = peers.name
        let status = peers.status
        let station = fleet.station("work")
        func color(_ repo: String) -> NSColor { NSColor(fleet.color(forRepo: repo)) }
        if let mine = makeSnapshot(withGitHub: false) {
            f.offered = mine.offices.sorted { $0.name < $1.name }.map { o in
                NeighbourFacts.Office(key: o.key, name: o.name, color: color(o.repo), atWork: mine.minions.filter { $0.office == o.key && !$0.asleep }.count,
                                      pull: o.pull, pullState: o.pullState)
            }
        }
        let names = Set(world.peerSnapshots.keys).union(status.reaching).union(status.reachedBy)
        f.neighbours = names.sorted().map { name in
            let snap = world.peerSnapshots[name]?.snap
            let offices = (snap?.offices ?? []).sorted { $0.name < $1.name }.map { o in
                NeighbourFacts.Office(key: o.key, name: station.rooms[o.key]?.name ?? o.name, color: color(o.repo),
                                      atWork: snap?.minions.filter { $0.office == o.key && !$0.asleep }.count ?? 0, pull: o.pull, pullState: o.pullState)
            }
            return NeighbourFacts.Neighbour(name: name, reaching: status.reaching.contains(name), reachedBy: status.reachedBy.contains(name),
                                            arrival: snap == nil ? nil : status.arrivals[name], offices: offices)
        }
        f.near = peers.nearby.filter { !names.contains($0) }
        f.comings = status.comings
        if !peers.networkUp {
            f.problem = ("No network", "Neighbours come back when this Mac is on a network again.")
        } else if peers.blocked {
            f.problem = ("Not allowed on the local network", "System Settings › Privacy & Security › Local Network lets rumkapsel in.")
        }
        f.light = f.problem != nil ? .off : world.peerSnapshots.isEmpty ? .waiting : .linked
        return f
    }

    private func lookAtNeighbourOffice(_ key: String) {
        enqueue { [self] in
            guard let station = fleet.stations["work"], station.rooms[key] != nil else { return }
            following = nil
            userTookView = true
            look(at: key, in: station.name, zoom: max(userZoom, 3))
            hovered = "room:\(station.name)|\(key)"
        }
    }
}

final class NeighboursButton: NSView {
    var onClick: (() -> Void)?
    var onResize: (() -> Void)?
    var open = false { didSet { if open != oldValue { needsDisplay = true } } }
    private var count = 0
    private var light = NeighbourFacts.Light.off
    private let lamp = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        lamp.frame = CGRect(x: 8, y: 7, width: 6, height: 6)
        lamp.cornerRadius = 3
        layer?.addSublayer(lamp)
        toolTip = "Neighbours · N"
        show(count: 0, light: .off)
    }
    required init?(coder: NSCoder) { fatalError() }

    static let green = NSColor(rgb: (0.35, 0.85, 0.5))
    static func tint(_ light: NeighbourFacts.Light) -> NSColor {
        switch light {
        case .linked: return green
        case .waiting: return SpaceLogStyle.amber
        case .off: return NSColor(rgb: (0.45, 0.46, 0.5))
        }
    }

    private var title: NSAttributedString {
        let s = NSMutableAttributedString(string: "Neighbours", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: Palette.text])
        if count > 0 { s.append(NSAttributedString(string: "  \(count)", attributes: [.font: SpaceLogStyle.mono(10), .foregroundColor: Palette.text])) }
        return s
    }

    func show(count: Int, light: NeighbourFacts.Light) {
        guard count != self.count || light != self.light || frame.width == 90 else { return }
        self.count = count
        self.light = light
        lamp.backgroundColor = Self.tint(light).cgColor
        lamp.removeAllAnimations()
        if light == .linked {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.45; a.duration = 1.6
            a.autoreverses = true; a.repeatCount = .infinity
            lamp.add(a, forKey: "breathe")
        }
        setFrameSize(NSSize(width: 30 + title.size().width, height: 20))
        onResize?()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let edge = Self.tint(light)
        (open ? Palette.void.mixed(with: edge, 0.22) : SpaceLogStyle.plate).setFill()
        bounds.fill()
        edge.withAlphaComponent(open ? 0.9 : 0.45).setStroke()
        let frame = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); frame.lineWidth = 1; frame.stroke()
        let t = title
        t.draw(at: NSPoint(x: 20, y: (bounds.height - t.size().height) / 2))
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NeighboursPanel: NSView {
    private let text = LinkedText()
    private let scroll = NSScrollView()
    var onGo: ((String) -> Void)? {
        didSet { text.onGo = { [weak self] t in if let key = t as? String { self?.onGo?(key) } } }
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

    static func seconds(_ s: TimeInterval) -> String {
        s < 0.1 ? "under 0.1 s" : s < 10 ? String(format: "%.1f s", s) : s < 120 ? "\(Int(s)) s" : "\(Int(s / 60)) min"
    }

    func show(_ f: NeighbourFacts) {
        let scrolled = scroll.contentView.bounds.origin
        let now = Date()
        let out = NSMutableAttributedString()
        func add(_ s: String, _ attrs: [NSAttributedString.Key: Any]) { out.append(NSAttributedString(string: s, attributes: attrs)) }
        let indent: CGFloat = 30

        func heading(_ s: String, first: Bool = false) {
            let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = first ? 0 : 22; p.paragraphSpacing = 10
            add(s + "\n", [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: SpaceLogStyle.amber, .paragraphStyle: p])
        }
        func quiet(_ s: String) {
            let p = NSMutableParagraphStyle(); p.paragraphSpacing = 12; p.firstLineHeadIndent = indent; p.headIndent = indent
            add(s + "\n", [.font: SpaceLogStyle.italic(12), .foregroundColor: Palette.dim, .paragraphStyle: p])
        }
        func line(_ shape: SpaceLog.Entry.Shape, _ color: NSColor, _ big: String, _ rest: String = "", link: String? = nil, size: CGFloat = 16) {
            let p = NSMutableParagraphStyle()
            p.headIndent = indent; p.tabStops = [NSTextTab(textAlignment: .left, location: indent)]; p.paragraphSpacing = 2
            var attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: p]
            if let link { attrs[LinkedText.target] = link }
            let mark = NSTextAttachment()
            let g = SpaceLogStyle.glyph(shape, color: color, size: 14)
            mark.image = g
            mark.bounds = NSRect(x: 0, y: -1, width: g.size.width, height: g.size.height)
            out.append(NSAttributedString(attachment: mark))
            add("\t", attrs.merging([.font: NSFont.systemFont(ofSize: size)]) { _, n in n })
            add(big, attrs.merging([.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: Palette.text]) { _, n in n })
            add(rest + "\n", attrs.merging([.font: NSFont.systemFont(ofSize: size), .foregroundColor: Palette.text.withAlphaComponent(0.88)]) { _, n in n })
        }
        func small(_ s: String, gap: CGFloat = 1) {
            let p = NSMutableParagraphStyle()
            p.firstLineHeadIndent = indent; p.headIndent = indent; p.paragraphSpacing = gap
            add(s + "\n", [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: Palette.dim, .paragraphStyle: p])
        }
        func office(_ o: NeighbourFacts.Office, link: Bool) {
            var bits: [String] = []
            if o.atWork > 0 { bits.append("\(o.atWork) at work") }
            if let n = o.pull { bits.append("#\(n)" + (o.pullState == "OPEN" || o.pullState == nil ? "" : " " + o.pullState!.lowercased())) }
            line(.office, o.color, o.name, bits.isEmpty ? "" : "   " + bits.joined(separator: " · "), link: link ? o.key : nil, size: 13.5)
        }

        heading("You", first: true)
        if let (big, why) = f.problem {
            line(.office, NeighboursButton.tint(.off), big)
            small(why, gap: 8)
        } else {
            line(.office, NeighboursButton.tint(f.light), "You share as \(f.name)")
            small(f.offered.isEmpty ? "No office goes out: no repository is shared." : "\(f.offered.count) office\(f.offered.count == 1 ? " goes" : "s go") out", gap: 6)
        }
        for o in f.offered { office(o, link: true) }

        heading("Neighbours")
        if f.neighbours.isEmpty && f.near.isEmpty { quiet("Nobody in range. A station shows up here when it runs on the same network with sharing on.") }
        for n in f.neighbours {
            let heard = n.arrival.map { now.timeIntervalSince($0.at) }
            let fresh = heard.map { $0 < PeerHub.heartbeat * 2 } ?? false
            line(.office, NeighboursButton.tint(fresh ? .linked : .waiting), n.name,
                 heard.map { " · heard \(Self.seconds($0)) ago" } ?? " · not heard yet")
            var how: [String] = []
            if let gap = n.arrival?.gap { how.append("every \(Self.seconds(gap))") }
            if let lag = n.arrival?.lag { how.append(lag < -1 || lag > 60 ? "clocks disagree" : "\(Self.seconds(lag)) on the way") }
            how.append(n.reaching && n.reachedBy ? "linked both ways" : n.reaching ? "you reach them, they have not reached you"
                       : n.reachedBy ? "they reach you, you cannot reach them" : "no link")
            small(how.joined(separator: " · "), gap: 6)
            if n.offices.isEmpty { small("Shares no office", gap: 8) }
            for o in n.offices { office(o, link: true) }
            add("\n", [.font: NSFont.systemFont(ofSize: 8)])
        }
        for name in f.near { quiet("\(name) is near but not answering") }

        if !f.comings.isEmpty {
            heading("Links")
            let hms = DateFormatter(); hms.dateFormat = "HH:mm:ss"
            for c in f.comings.suffix(12).reversed() {
                let p = NSMutableParagraphStyle(); p.paragraphSpacing = 2; p.firstLineHeadIndent = indent; p.headIndent = indent + 64
                add(hms.string(from: c.at) + "   ", [.font: SpaceLogStyle.mono(10.5), .foregroundColor: Palette.dim.withAlphaComponent(0.8), .paragraphStyle: p])
                add(c.words.prefix(1).uppercased() + c.words.dropFirst() + "\n", [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.text.withAlphaComponent(0.8), .paragraphStyle: p])
            }
        }
        text.textStorage?.setAttributedString(out)
        scroll.contentView.scroll(to: scrolled)
        scroll.reflectScrolledClipView(scroll.contentView)
        needsDisplay = true
    }
}
