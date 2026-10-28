import AppKit

extension StationController {
    func installPosterPanel() {
        let w = view.bounds.width
        let panel = PosterPanel(frame: NSRect(x: w - 472, y: 40, width: 460, height: max(200, view.bounds.height - 110)))
        panel.autoresizingMask = [.minXMargin, .height]
        panel.isHidden = true
        panel.onSetup = { [weak self] tab in
            guard let self else { return }
            if tab == 1, let repo = self.knownRepos.first { self.onChangeRepo?(repo) } else { self.onOpenSettings?(tab) }
        }
        view.addSubview(panel)
        posterPanel = panel
    }

    func openPoster(_ poster: Poster) {
        DispatchQueue.main.async { [self] in
            closeStory()
            if spaceLogPanel?.isHidden == false { toggleSpaceLog() }
            if neighboursPanel?.isHidden == false { toggleNeighbours() }
            posterPanel?.show(poster)
            posterPanel?.isHidden = false
        }
    }

    var postersHidden: Bool { postersOff && walker == nil }

    func togglePosters() {
        postersOff.toggle()
        enqueue { [self] in
            showPosters()
            if postersOff { closePoster() }
        }
    }

    func showPosters() {
        for n in statics.tagged("posters") { n.isHidden = postersHidden }
    }

    func closePoster() { DispatchQueue.main.async { [self] in posterPanel?.isHidden = true } }

    func posterTakes(point p: NSPoint) -> Bool {
        guard let panel = posterPanel, !panel.isHidden else { return false }
        return panel.frame.contains(p)
    }
}

final class PosterPanel: NSView {
    private let picture = NSImageView()
    private let words = NSTextField(wrappingLabelWithString: "")
    private let setup = NSButton(title: "", target: nil, action: nil)
    private var shown: Poster?
    var onSetup: ((Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.wantsLayer = true
        picture.layer?.cornerRadius = 10
        picture.layer?.masksToBounds = true
        words.textColor = Palette.text
        words.font = .systemFont(ofSize: 14)
        words.maximumNumberOfLines = 0
        setup.isBordered = false
        setup.target = self
        setup.action = #selector(goSetup)
        for v in [picture, words, setup] as [NSView] { addSubview(v) }
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

    override func layout() {
        super.layout()
        let inset: CGFloat = 26, width = bounds.width - inset * 2
        let setupHeight: CGFloat = setup.isHidden ? 0 : 40
        let textHeight = words.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
        let room = bounds.height - textHeight - setupHeight - 60
        let pictureHeight = max(120, min(room, width * 4 / 3))
        picture.frame = NSRect(x: inset + (width - pictureHeight * 3 / 4) / 2, y: bounds.height - 20 - pictureHeight, width: pictureHeight * 3 / 4, height: pictureHeight)
        words.frame = NSRect(x: inset, y: picture.frame.minY - 16 - textHeight, width: width, height: textHeight)
        setup.frame = NSRect(x: inset, y: words.frame.minY - 10 - setupHeight, width: width, height: setupHeight)
    }

    func show(_ poster: Poster) {
        shown = poster
        picture.image = poster.image
        let p = NSMutableParagraphStyle(); p.paragraphSpacing = 8; p.lineSpacing = 2
        words.attributedStringValue = NSAttributedString(string: poster.lines.joined(separator: "\n"),
                                                         attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: Palette.text, .paragraphStyle: p])
        if let s = poster.setup {
            setup.isHidden = false
            setup.attributedTitle = NSAttributedString(string: "⚙︎  " + s.words, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                                                              .foregroundColor: SpaceLogStyle.amber])
        } else {
            setup.isHidden = true
        }
        needsLayout = true
    }

    @objc private func goSetup() {
        guard let s = shown?.setup else { return }
        onSetup?(s.tab)
    }
}
