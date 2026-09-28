// The station log on screen: its button, the log, and where a line leads on the floor.

import AppKit
import SceneKit

extension StationController {
    // MARK: station log

    /// What GitHub has told the station, for the log. On the scene's thread.
    func spaceLogFacts() -> SpaceLog.Facts {
        let repos = world.repoRoots.sorted { $0.value.repo < $1.value.repo }.map { root, info in
            SpaceLog.Repo(name: info.repo, feed: github.feed(repoRoot: root) ?? [], releases: github.releases(repoRoot: root) ?? [])
        }
        let config = ConfigStore.shared.current
        var titles: [String: [Int: String]] = [:]
        for (root, info) in world.repoRoots { for pr in github.teamOpenPRs(repoRoot: root) ?? [] { titles[info.repo, default: [:]][pr.number] = pr.title } }
        return SpaceLog.Facts(repos: repos, board: config.project == nil ? [] : github.projectItems() ?? [], statuses: config.statuses,
                              me: github.myLogin(), name: { [world] in world.crewName($0) },
                              title: { [github] repo, n in
            if let t = github.work(repo: repo, number: n)?.title, !t.isEmpty { return t }
            if let issue = github.task(repo: repo, pull: n), let t = github.work(repo: repo, number: issue)?.title, !t.isEmpty { return t }
            return titles[repo]?[n]
        }, isReleaseBranch: { [world, github] repo, branch in
            guard let root = world.repoRoots.first(where: { $0.value.repo == repo })?.key else { return false }
            return github.pipeline(repoRoot: root).isReleaseHead(branch)
        })
    }

    /// Reads GitHub's facts into the story. On the scene's thread.
    @discardableResult
    func advanceSpaceLog() -> (story: SpaceLog.Story, changed: Bool) {
        let facts = spaceLogFacts()
        let now = Date()
        let fresh = SpaceLog.read(facts, since: now.addingTimeInterval(-SpaceLog.reach))
        let releases = SpaceLog.releaseNumbers(facts)
        let changed = StoryBook.shared.update { $0.add(fresh, feeds: facts.repos, now: now, releases: releases) }
        return (StoryBook.shared.current, changed)
    }

    /// Draws the panel on the main thread. Called from the scene's thread.
    private func drawSpaceLog(_ story: SpaceLog.Story, fresh: Bool) {
        var colors: [String: NSColor] = [:]
        for e in story.entries { if let r = e.repo, colors[r] == nil { colors[r] = NSColor(fleet.color(forRepo: r)) } }
        DispatchQueue.main.async { [self] in spaceLogPanel?.show(story: story, colors: colors, fromTop: fresh) }
    }

    /// Fills the panel as it opens.
    func refreshSpaceLog() {
        enqueue { [self] in
            spaceLogDrawnAt = clock
            drawSpaceLog(advanceSpaceLog().story, fresh: true)
        }
    }

    /// Takes in what is new: counts it for the button, or redraws an open log. On the scene's thread.
    func countUnreadSpaceLog() {
        let (story, changed) = advanceSpaceLog()
        let since = max(story.readAt ?? .distantPast, Date().addingTimeInterval(-SpaceLog.reach))
        let n = SpaceLog.fold(story.entries.filter { $0.at > since }).count
        if spaceLogOpen, changed || clock - spaceLogDrawnAt > 60 {
            spaceLogDrawnAt = clock
            drawSpaceLog(story, fresh: false)
        }
        DispatchQueue.main.async { [self] in if spaceLogPanel?.isHidden != false { spaceLogButton?.unread = n } }
    }

    /// The button and the panel, over the station view.
    func installSpaceLog() {
        let w = view.bounds.width
        let button = SpaceLogButton(frame: NSRect(x: w - 72, y: view.bounds.height - 28, width: 60, height: 20))
        button.autoresizingMask = [.minXMargin, .minYMargin]
        button.onClick = { [weak self] in self?.toggleSpaceLog() }
        button.onResize = { [weak self, weak button] in
            guard let self, let button, let host = button.superview else { return }
            button.setFrameOrigin(NSPoint(x: host.bounds.width - 12 - button.frame.width, y: button.frame.minY))
            self.spaceLogCorner = button.frame.width + 12
        }
        let panel = SpaceLogPanel(frame: NSRect(x: w - 472, y: 40, width: 460, height: max(200, view.bounds.height - 110)))
        panel.autoresizingMask = [.minXMargin, .height]
        panel.isHidden = true
        panel.onGo = { [weak self] t in self?.goTo(t) }
        view.addSubview(panel)
        view.addSubview(button)
        spaceLogButton = button
        spaceLogPanel = panel
        button.onResize?()
    }

    /// Opens or closes the log.
    func toggleSpaceLog() {
        guard let panel = spaceLogPanel else { return }
        if panel.isHidden {
            panel.isHidden = false
            spaceLogButton?.unread = 0
            refreshSpaceLog()
        } else {
            panel.isHidden = true
            StoryBook.shared.update { $0.readAt = Date(); return true }
        }
        spaceLogButton?.open = !panel.isHidden
        let open = !panel.isHidden
        enqueue { [self] in spaceLogOpen = open }
    }

    /// Takes the camera to what a line names, or opens it on GitHub when it is no longer on the floor.
    func goTo(_ t: SpaceLog.Target) {
        enqueue { [self] in
            let numbers = Set([t.number, t.number.flatMap { github.task(repo: t.repo, pull: $0) }].compactMap { $0 })
            func named(_ match: (String) -> Bool) -> SCNNode? {
                for root in [markerRoot, rocketRoot] {
                    if let n = root.childNodes(passingTest: { n, _ in n.name.map(match) == true && n.parent?.name != n.name }).first { return n }
                }
                return nil
            }
            func crate() -> SCNNode? {
                named { name in
                    guard ["storage:", "deck:", "decon:"].contains(where: name.hasPrefix) else { return false }
                    let p = name.split(separator: "|")
                    return p.count == 3 && p[1] == t.repo && Int(p[2]).map(numbers.contains) == true
                }
            }
            func rocket() -> SCNNode? { named { $0.hasPrefix("rocket:") && $0.contains("|\(t.repo) ") } }
            func office() -> (Station, Room)? {
                for st in fleet.stations.values {
                    for room in st.rooms.values where room.repo == t.repo {
                        if let k = world.taskNumber(room), numbers.contains(k) { return (st, room) }
                        if let rec = world.record(office: roomKey(st, room)), !numbers.isDisjoint(with: rec.pulls.keys) { return (st, room) }
                    }
                }
                return nil
            }
            func lookAt(_ node: SCNNode) {
                let p = node.worldPosition
                following = nil
                focused = nil
                userPan = SIMD2(Double(p.x), Double(p.z)) - targetFocus
                if userZoom < 3 { userZoom = 3; userZoomChanged = true }
                userTookView = true
                hovered = node.name
            }
            func toCrate() -> Bool { guard let n = crate() else { return false }; lookAt(n); return true }
            func toRocket() -> Bool {
                guard t.number == nil || t.kind == .launch, let n = rocket() else { return false }
                lookAt(n); return true
            }
            func toOffice() -> Bool {
                guard let (st, room) = office() else { return false }
                following = nil
                userTookView = true
                look(at: room.key, in: st.name, zoom: max(userZoom, 3))
                hovered = "room:\(st.name)|\(room.key)"
                return true
            }
            let went: Bool
            switch t.kind {
            case .deck, .cleared, .merged: went = toCrate() || toOffice() || toRocket()
            case .opened, .started: went = toOffice() || toCrate() || toRocket()
            case .launch, .staging: went = toRocket() || toCrate() || toOffice()
            }
            if went { return }
            guard let root = world.repoRoots.first(where: { $0.value.repo == t.repo })?.key, let owner = github.nameWithOwner(repoRoot: root) else { return }
            // GitHub redirects /issues/N to the pull request when N is one.
            let url = URL(string: "https://github.com/\(owner)" + (t.number.map { "/issues/\($0)" } ?? "/pulls"))
            if let url { DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
        }
    }

    /// Whether the log takes the pointer here.
    func spaceLogTakes(point p: NSPoint) -> Bool {
        if let b = spaceLogButton, b.frame.contains(p) { return true }
        if let panel = spaceLogPanel, !panel.isHidden, panel.frame.contains(p) { return true }
        return false
    }
}

enum SpaceLogStyle {
    static let amber = NSColor(rgb: (0.98, 0.72, 0.3))
    static let plate = Palette.void.withAlphaComponent(0.94)

    /// A launch's line.
    static let launch = NSColor(rgb: (1.0, 0.62, 0.3))

    static func mono(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
    static func italic(_ size: CGFloat) -> NSFont {
        NSFont(name: "HelveticaNeue-Italic", size: size) ?? .systemFont(ofSize: size)
    }

    /// A line's mark: its shape, flat, in the repository's colour.
    static func glyph(_ shape: SpaceLog.Entry.Shape, color: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let w = r.width, h = r.height
            let dark = color.darker(0.45)
            switch shape {
            case .rocket:
                let body = NSBezierPath()
                body.move(to: NSPoint(x: w * 0.5, y: h))
                body.line(to: NSPoint(x: w * 0.72, y: h * 0.62)); body.line(to: NSPoint(x: w * 0.72, y: h * 0.18))
                body.line(to: NSPoint(x: w * 0.28, y: h * 0.18)); body.line(to: NSPoint(x: w * 0.28, y: h * 0.62)); body.close()
                color.setFill(); body.fill()
                let fins = NSBezierPath()
                fins.move(to: NSPoint(x: w * 0.28, y: h * 0.42)); fins.line(to: NSPoint(x: w * 0.1, y: 0)); fins.line(to: NSPoint(x: w * 0.28, y: h * 0.18)); fins.close()
                fins.move(to: NSPoint(x: w * 0.72, y: h * 0.42)); fins.line(to: NSPoint(x: w * 0.9, y: 0)); fins.line(to: NSPoint(x: w * 0.72, y: h * 0.18)); fins.close()
                dark.setFill(); fins.fill()
            case .crate, .checked:
                let box = NSRect(x: w * 0.1, y: h * 0.12, width: w * 0.8, height: h * 0.76)
                color.setFill(); box.fill()
                (shape == .checked ? NSColor(rgb: (0.45, 0.95, 0.5)) : dark).setFill()
                NSRect(x: box.minX, y: box.midY - h * 0.08, width: box.width, height: h * 0.16).fill()
            case .office:
                let hex = NSBezierPath()
                for i in 0..<6 {
                    let a = CGFloat(i) * .pi / 3
                    let p = NSPoint(x: w * 0.5 + cos(a) * w * 0.45, y: h * 0.5 + sin(a) * h * 0.45)
                    i == 0 ? hex.move(to: p) : hex.line(to: p)
                }
                hex.close(); color.setFill(); hex.fill()
            case .order:
                let cone = NSBezierPath()
                cone.move(to: NSPoint(x: w * 0.5, y: h * 0.92)); cone.line(to: NSPoint(x: w * 0.88, y: h * 0.12)); cone.line(to: NSPoint(x: w * 0.12, y: h * 0.12)); cone.close()
                color.setFill(); cone.fill()
            }
            return true
        }
    }
}

/// "Log" on a small plate, with the unread count and a light that breathes while there is any.
final class SpaceLogButton: NSView {
    var onClick: (() -> Void)?
    /// Told when the width changes.
    var onResize: (() -> Void)?
    var unread = 0 { didSet { if unread != oldValue { resize(); needsDisplay = true; breathe() } } }
    var open = false { didSet { needsDisplay = true } }
    private let light = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        light.frame = CGRect(x: 8, y: 7, width: 6, height: 6)
        light.backgroundColor = SpaceLogStyle.amber.cgColor
        layer?.addSublayer(light)
        toolTip = "Station log · L"
        resize()
    }
    required init?(coder: NSCoder) { fatalError() }

    private var title: NSAttributedString {
        let s = NSMutableAttributedString(string: "Log", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: SpaceLogStyle.amber])
        if unread > 0 { s.append(NSAttributedString(string: "  \(unread)", attributes: [.font: SpaceLogStyle.mono(10), .foregroundColor: Palette.text])) }
        return s
    }

    private func resize() { setFrameSize(NSSize(width: 30 + title.size().width, height: 20)); onResize?() }

    private func breathe() {
        light.removeAllAnimations()
        light.opacity = unread > 0 ? 1 : 0.35
        guard unread > 0 else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1; a.toValue = 0.25; a.duration = 1.1
        a.autoreverses = true; a.repeatCount = .infinity
        light.add(a, forKey: "breathe")
    }

    override func draw(_ dirtyRect: NSRect) {
        (open ? Palette.void.mixed(with: SpaceLogStyle.amber, 0.22) : SpaceLogStyle.plate).setFill()
        bounds.fill()
        SpaceLogStyle.amber.withAlphaComponent(open ? 0.9 : 0.45).setStroke()
        let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
        let t = title
        t.draw(at: NSPoint(x: 20, y: (bounds.height - t.size().height) / 2))
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The log: one line per event with small print under it, over space darkening towards the edge.
final class SpaceLogPanel: NSView {
    private let text = LinkedText()
    private let scroll = NSScrollView()
    var onGo: ((SpaceLog.Target) -> Void)? { get { text.onGo } set { text.onGo = newValue } }

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

    /// `fromTop` for a panel just opened; otherwise the scroll position is kept.
    func show(story: SpaceLog.Story, colors: [String: NSColor], fromTop: Bool = true) {
        let scrolled = scroll.contentView.bounds.origin
        let now = Date()
        let cal = Calendar.current
        let hhmm = DateFormatter(); hhmm.dateFormat = "HH:mm"
        let readAt = story.readAt
        let entries = story.entries.filter { $0.at > now.addingTimeInterval(-SpaceLog.reach) }
        // With no last look, the last twelve hours count as new.
        let since = max(readAt ?? now.addingTimeInterval(-12 * 3600), now.addingTimeInterval(-SpaceLog.reach))

        let out = NSMutableAttributedString()
        func add(_ s: String, _ attrs: [NSAttributedString.Key: Any]) { out.append(NSAttributedString(string: s, attributes: attrs)) }
        let indent: CGFloat = 30

        func quiet(_ line: String, _ color: NSColor) {
            let p = NSMutableParagraphStyle(); p.alignment = .center; p.paragraphSpacingBefore = 4; p.paragraphSpacing = 18
            add(line + "\n", [.font: SpaceLogStyle.italic(12), .foregroundColor: color, .paragraphStyle: p])
        }
        func day(_ d: Date, first: Bool) {
            let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = first ? 0 : 22; p.paragraphSpacing = 14
            let sol = cal.ordinality(of: .day, in: .year, for: d) ?? 0
            let name = cal.isDateInToday(d) ? "today" : cal.isDateInYesterday(d) ? "yesterday" : { let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: d).lowercased() }()
            add("Sol \(sol)", [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: SpaceLogStyle.amber, .paragraphStyle: p])
            add("   \(name)\n", [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: SpaceLogStyle.amber.withAlphaComponent(0.6), .paragraphStyle: p])
        }

        let lines = SpaceLog.gather(SpaceLog.fold(SpaceLog.rollUp(entries))).sorted { $0.at > $1.at }
        if lines.isEmpty {
            day(now, first: true)
            quiet("Nothing yet. Launches, deliveries and inspections land here.", Palette.dim)
        }
        var gaps = story.gaps.filter { $0.to > now.addingTimeInterval(-SpaceLog.reach) }.sorted { $0.to > $1.to }
        var marked = readAt == nil
        var lastDay: Date?
        if let newest = lines.first, !cal.isDateInToday(newest.at) {
            day(now, first: true)
            quiet("Quiet so far today.", Palette.dim)
            lastDay = cal.startOfDay(for: now)
        }
        for e in lines {
            let d = cal.startOfDay(for: e.at)
            if d != lastDay { day(d, first: lastDay == nil); lastDay = d }
            if !marked, e.at <= since {
                marked = true
                if e.key != lines.first?.key { quiet("· you were here, \(StationController.span(now.timeIntervalSince(since))) ago ·", SpaceLogStyle.amber.withAlphaComponent(0.75)) }
            }
            while let g = gaps.first, g.to >= e.at {
                gaps.removeFirst()
                let stamp = DateFormatter(); stamp.dateFormat = "EEE HH:mm"
                quiet("no word from \(g.repo) between \(stamp.string(from: g.from)) and \(stamp.string(from: g.to))", Palette.dim)
            }

            let alpha: CGFloat = e.at > since ? 1 : 0.5
            let launch = e.shape == .rocket
            let size: CGFloat = launch ? 19 : 16
            let repoColor = e.repo.flatMap { colors[$0] } ?? Palette.dim
            let head = NSMutableParagraphStyle()
            head.headIndent = indent
            head.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            head.paragraphSpacingBefore = launch ? 6 : 0
            head.paragraphSpacing = 2
            head.lineBreakMode = .byWordWrapping
            var link: [NSAttributedString.Key: Any] = [:]
            if let repo = e.repo, let item = e.note ?? e.items.first { link[LinkedText.target] = SpaceLog.Target(kind: e.kind, repo: repo, item: item) }
            func put(_ s: String, _ attrs: [NSAttributedString.Key: Any]) { add(s, link.merging(attrs) { _, new in new }.merging([.paragraphStyle: head]) { _, new in new }) }

            let mark = NSTextAttachment()
            let g = SpaceLogStyle.glyph(e.shape, color: repoColor.withAlphaComponent(alpha), size: launch ? 18 : 14)
            mark.image = g
            mark.bounds = NSRect(x: 0, y: launch ? -2 : -1, width: g.size.width, height: g.size.height)
            out.append(NSAttributedString(attachment: mark))
            put("\t", [.font: NSFont.systemFont(ofSize: size)])
            let (who, rest) = e.sentence
            let ink = (launch ? SpaceLogStyle.launch : Palette.text).withAlphaComponent(alpha)
            if let who { put(who.prefix(1).uppercased() + who.dropFirst() + " ", [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: ink]) }
            put(rest + "\n", [.font: NSFont.systemFont(ofSize: size, weight: launch ? .semibold : .regular), .foregroundColor: ink.withAlphaComponent(alpha * (launch ? 1 : 0.88))])

            let small = NSMutableParagraphStyle()
            small.firstLineHeadIndent = indent; small.headIndent = indent; small.paragraphSpacing = 1
            small.lineBreakMode = .byTruncatingTail
            let more = (small.mutableCopy() as! NSMutableParagraphStyle)
            more.firstLineHeadIndent = indent + 44; more.headIndent = indent + 44
            let detail = e.items.filter { $0 != e.note && $0.hasPrefix("#") }
            let shown = detail.prefix(detail.count > 3 ? 2 : 3)
            add(hhmm.string(from: e.at) + (shown.isEmpty ? "\n" : "  "), [.font: SpaceLogStyle.mono(10.5), .foregroundColor: Palette.dim.withAlphaComponent(alpha * 0.8), .paragraphStyle: small])
            for (i, item) in shown.enumerated() {
                var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: Palette.dim.withAlphaComponent(alpha * 0.95), .paragraphStyle: i == 0 ? small : more]
                if let repo = e.repo { attrs[LinkedText.target] = SpaceLog.Target(kind: e.kind, repo: repo, item: item) }
                add(item + "\n", attrs)
            }
            if detail.count > shown.count {
                add("and \(detail.count - shown.count) more\n", [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: Palette.dim.withAlphaComponent(alpha * 0.6), .paragraphStyle: more])
            }
            add("\n", [.font: NSFont.systemFont(ofSize: launch ? 12 : 9)])
        }
        text.textStorage?.setAttributedString(out)
        if fromTop { text.scroll(.zero) } else { scroll.contentView.scroll(to: scrolled); scroll.reflectScrolledClipView(scroll.contentView) }
        needsDisplay = true
    }
}

/// The log's text, where a line can be clicked. Not selectable, so it never takes the keyboard.
final class LinkedText: NSTextView {
    static let target = NSAttributedString.Key("rumkapsel.spacelog.target")
    var onGo: ((SpaceLog.Target) -> Void)?

    private func target(at event: NSEvent) -> SpaceLog.Target? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        var p = convert(event.locationInWindow, from: nil)
        p.x -= textContainerOrigin.x; p.y -= textContainerOrigin.y
        var fraction: CGFloat = 0
        let glyph = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &fraction)
        guard lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc).insetBy(dx: -4, dy: -2).contains(p) else { return nil }
        let i = lm.characterIndexForGlyph(at: glyph)
        guard i < storage.length else { return nil }
        return storage.attribute(Self.target, at: i, effectiveRange: nil) as? SpaceLog.Target
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { (target(at: event) == nil ? NSCursor.arrow : NSCursor.pointingHand).set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { if let t = target(at: event) { onGo?(t) } }
}
