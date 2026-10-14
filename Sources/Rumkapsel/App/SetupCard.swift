import AppKit
import SceneKit
import SpriteKit

struct SetupCardFacts: Equatable {
    enum Kind: Equatable { case new, mismatch }
    var kind = Kind.new
    let repos: [String]
    let lines: [String]
    let colors: [String: RGB]
    let room: CGSize
}

extension StationController {
    // MARK: the new-repository card

    func installCard() {
        let card = SetupCard(frame: NSRect(x: view.bounds.width - SetupCard.width - 16, y: view.bounds.height - 200, width: SetupCard.width, height: 120))
        card.autoresizingMask = [.minXMargin, .minYMargin]
        card.isHidden = true
        card.onAnswer = { [weak self] facts, second in self?.enqueue { self?.answerCard(facts, second: second) } }
        view.addSubview(card)
        setupCard = card
    }

    func cardRepos() -> [String] {
        let cfg = ConfigStore.shared.current
        return world.newRepos.filter { cfg.repos[$0] == nil && !answeredCards.contains($0) && cfg.shown(repo: $0) && world.setup(repo: $0).pipeline != nil }
    }

    func drawCard() {
        var repos = cardRepos()
        var facts = SetupCardFacts(repos: repos, lines: Setup.card(repos.map(world.setup(repo:))),
                                   colors: Dictionary(uniqueKeysWithValues: repos.map { ($0, fleet.color(forRepo: $0)) }), room: viewSize)
        if repos.isEmpty, !demo {
            let found = world.mismatches.filter { !answeredCards.contains("mismatch:" + $0.repo) }
            repos = found.map(\.repo)
            facts = SetupCardFacts(kind: .mismatch, repos: repos, lines: Setup.mismatchCard(found.flatMap(\.lines)),
                                   colors: Dictionary(uniqueKeysWithValues: repos.map { ($0, fleet.color(forRepo: $0)) }), room: viewSize)
        }
        guard facts != cardFacts else { return }
        cardFacts = facts
        DispatchQueue.main.async { [self] in
            guard let card = setupCard else { return }
            card.isHidden = facts.repos.isEmpty
            if !facts.repos.isEmpty { card.show(facts, top: view.bounds.height - 74, right: view.bounds.width - 16) }
        }
    }

    func answerCard(_ facts: SetupCardFacts, second: Bool) {
        let repos = facts.repos
        switch facts.kind {
        case .new:
            answeredCards.formUnion(repos)
            if !demo, !world.simulated { ConfigStore.shared.update(byUser: true) { c in for r in repos { c.repos[r, default: .init()].answered = true } } }
            if second, let first = repos.first { DispatchQueue.main.async { [self] in onChangeRepo?(first) } }
        case .mismatch:
            let lines = Dictionary(uniqueKeysWithValues: world.mismatches.map { ($0.repo, $0.lines) })
            answeredCards.formUnion(repos.map { "mismatch:" + $0 })
            if !demo, !world.simulated {
                ConfigStore.shared.update(byUser: true) { c in
                    for r in repos {
                        guard let o = c.repos[r] else { continue }
                        c.repos[r] = second ? { var k = o; k.kept = (o.kept ?? []) + (lines[r] ?? []); return k }() : o.usingRepository
                    }
                }
            }
        }
        drawCard()
    }

    func cardTakes(point p: NSPoint) -> Bool {
        guard let card = setupCard, !card.isHidden else { return false }
        return card.frame.contains(p)
    }

    // MARK: the empty yard's setup check

    func drawSetupCheck() {
        if setupLabel.parent == nil {
            setupLabel.fontName = "HelveticaNeue-Italic"
            setupLabel.fontSize = 14
            setupLabel.numberOfLines = 0
            setupLabel.preferredMaxLayoutWidth = 300
            setupLabel.horizontalAlignmentMode = .center
            setupLabel.verticalAlignmentMode = .center
            setupLabel.zPosition = 1
            setupPlate.zPosition = 0.5
            hud.addChild(setupPlate)
            hud.addChild(setupLabel)
        }
        let station = fleet.stations.values.filter(\.hasPad).min { $0.name < $1.name }
        let problems = demo ? [] : Setup.problems(world.setupCheck)
        setupProblems = problems.map(\.settings)
        func hide() { setupLabel.isHidden = true; setupPlate.isHidden = true }
        guard walker == nil, let first = problems.first else { return hide() }
        var at = CGPoint(x: hud.size.width / 2, y: hud.size.height / 2)
        if let station, !station.hall.cells.isEmpty {
            guard !station.facts.crates.values.contains(where: { $0.zone != nil }) else { return hide() }
            let cells = station.hall.cells
            let x = Double(cells.map(\.x).min()! + cells.map(\.x).max()!) / 2, y = Double(cells.map(\.y).min()! + cells.map(\.y).max()!) / 2
            let p = view.projectPoint(SCNVector3(station.offset.x + x, 0.05, station.offset.y + y))
            at = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
            guard p.z > 0, p.z < 1, view.bounds.insetBy(dx: 40, dy: 40).contains(at) else { return hide() }
        }
        setupLabel.text = first.station
        setupLabel.fontColor = ink.text
        setupLabel.position = at
        let f = setupLabel.frame.insetBy(dx: -12, dy: -8)
        setupPlate.color = (ink.onLight ? NSColor.white : Palette.void).withAlphaComponent(0.78)
        setupPlate.size = f.size
        setupPlate.position = CGPoint(x: f.midX, y: f.midY)
        setupLabel.isHidden = false; setupPlate.isHidden = false
    }
}

final class SetupCard: NSView {
    static let width: CGFloat = 430
    private let text = NSTextField(wrappingLabelWithString: "")
    private let yes = NSButton(title: "Looks right", target: nil, action: nil)
    private let change = NSButton(title: "Change…", target: nil, action: nil)
    private var facts: SetupCardFacts?
    var onAnswer: ((SetupCardFacts, Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        layer?.cornerRadius = 8
        layer?.backgroundColor = Palette.void.withAlphaComponent(0.88).cgColor
        layer?.borderColor = Palette.dim.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1
        text.isSelectable = false
        text.drawsBackground = false
        text.isBordered = false
        addSubview(text)
        for (b, action) in [(yes, #selector(looksRight)), (change, #selector(changeIt))] {
            b.target = self
            b.action = action
            b.bezelStyle = .rounded
            b.controlSize = .regular
            b.refusesFirstResponder = true
            addSubview(b)
        }
        yes.keyEquivalent = ""
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    @objc private func looksRight() { if let facts { onAnswer?(facts, false) } }
    @objc private func changeIt() { if let facts { onAnswer?(facts, true) } }

    func show(_ f: SetupCardFacts, top: CGFloat, right: CGFloat) {
        facts = f
        yes.title = f.kind == .new ? "Looks right" : "Use the repository's"
        change.title = f.kind == .new ? "Change…" : "Keep mine"
        let out = NSMutableAttributedString()
        let lead = NSMutableParagraphStyle(); lead.paragraphSpacing = 6
        let row = NSMutableParagraphStyle(); row.paragraphSpacing = 3
        func color(_ repo: String) -> NSColor { (f.colors[repo].map { NSColor($0) } ?? Palette.text).lighter(0.15) }
        for (i, line) in f.lines.enumerated() {
            let head = i == 0
            let attrs: [NSAttributedString.Key: Any] = head
                ? [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: Palette.text, .paragraphStyle: lead]
                : [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: Palette.text.withAlphaComponent(0.82), .paragraphStyle: row]
            let s = NSMutableAttributedString(string: line + (i == f.lines.count - 1 ? "" : "\n"), attributes: attrs)
            for repo in f.repos {
                let r = (line as NSString).range(of: repo)
                if r.location != NSNotFound, head ? f.kind == .new && f.repos.count == 1 : r.location == 0 { s.addAttribute(.foregroundColor, value: color(repo), range: r) }
            }
            out.append(s)
        }
        text.attributedStringValue = out
        let width = max(220, min(SetupCard.width, f.room.width - 32))
        let inner = width - 32
        let height = ceil(text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: 1000)).height ?? 40)
        let total = 14 + height + 12 + 24 + 12
        frame = NSRect(x: right - width, y: max(8, top - total), width: width, height: total)
        text.frame = NSRect(x: 16, y: total - 16 - height, width: inner, height: height)
        change.sizeToFit(); yes.sizeToFit()
        change.frame.origin = NSPoint(x: width - 16 - change.frame.width, y: 12)
        yes.frame.origin = NSPoint(x: change.frame.minX - 8 - yes.frame.width, y: 12)
    }
}
