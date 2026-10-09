// What a minion's box wears: a suit drawn on its faces, in the body's own white or the crew's grey. The faces are
// baked into Resources/Suits by `--bake-suits`; the repository's colour is a patch the minion wears over them.

import AppKit
import SceneKit

enum Suit {
    private static var made: [Bool: [SCNMaterial]] = [:]

    static func key(_ badge: NSColor, crew: Bool) -> String { WallPanel.key(badge) + (crew ? "|crew" : "") }
    /// A light grey, so the lights leave its sunlit faces white and its others shaded, not one flat white.
    private static func base(crew: Bool) -> NSColor { crew ? NSColor(rgb: (0.62, 0.64, 0.7)) : NSColor(rgb: (0.8, 0.8, 0.78)) }

    /// Where the repository's patch sits on the front face, as fractions across and down from the top of the head.
    static let patch = (x0: 0.64, y0: 0.36, x1: 0.8, y1: 0.4)

    /// The box's six faces, in SCNBox's order: front, right, back, left, top, bottom.
    static func materials(crew: Bool) -> [SCNMaterial] {
        if let m = made[crew] { return m }
        let base = base(crew: crew)
        func face(_ part: Part) -> SCNMaterial {
            let m = lit(base)
            m.diffuse.contents = load(part, crew: crew) ?? draw(base, width: part == .side ? 96 : 192, part: part)
            m.diffuse.mipFilter = .linear
            return m
        }
        let side = face(.side), top = lit(base)
        let out = [face(.front), side, face(.back), side, top, top]
        made[crew] = out
        return out
    }

    /// The repository's patch, toned into the suit.
    static func patchColor(_ badge: NSColor, crew: Bool) -> NSColor { base(crew: crew).blended(withFraction: 0.6, of: badge) ?? badge }

    /// Where the baked faces are: in the app's resources, or beside the sources when run from a build.
    static let root: URL? = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Suits"), FileManager.default.fileExists(atPath: r.path) { return r }
        return FileManager.default.fileExists(atPath: sourceRoot.path) ? sourceRoot : nil
    }()
    static let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Suits")
    private static func file(_ part: Part, crew: Bool) -> String { "suit-\(crew ? "crew" : "white")-\(part).png" }
    private static func load(_ part: Part, crew: Bool) -> NSImage? { root.flatMap { NSImage(contentsOf: $0.appendingPathComponent(file(part, crew: crew))) } }

    /// `rumkapsel --bake-suits`: draws every face and writes it beside the sources, to be committed. Run it again
    /// after changing how a suit is drawn.
    static func bake() -> Never {
        try? FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        for crew in [false, true] {
            for part in [Part.front, .back, .side] {
                let image = draw(base(crew: crew), width: part == .side ? 96 : 192, part: part)
                guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { continue }
                let url = sourceRoot.appendingPathComponent(file(part, crew: crew))
                try? png.write(to: url)
                print("wrote \(url.path)")
            }
        }
        exit(0)
    }

    /// Dark glass with a faint cold light low in it and a soft streak of reflection across.
    static let visor: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Textures.draw(64, 16) { ctx, w, h in
            ctx.setFillColor(NSColor(rgb: (0.09, 0.11, 0.15)).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(NSColor(rgb: (0.13, 0.19, 0.25)).cgColor)
            ctx.fill(CGRect(x: 0, y: h * 0.6, width: w, height: h * 0.4))
            ctx.setFillColor(NSColor(white: 1, alpha: 0.16).cgColor)
            ctx.move(to: CGPoint(x: w * 0.18, y: 0)); ctx.addLine(to: CGPoint(x: w * 0.26, y: 0))
            ctx.addLine(to: CGPoint(x: w * 0.16, y: h)); ctx.addLine(to: CGPoint(x: w * 0.08, y: h)); ctx.fillPath()
        }
        m.diffuse.mipFilter = .linear
        return m
    }()

    private enum Part { case front, back, side }

    /// One face, `width` pixels across and as tall as a standing body is to its width; heights below are
    /// fractions down from the top of the head. Every mark is a hairline seam, a shadow over a highlight,
    /// so the face's smaller mip levels come down to the body's own colour.
    private static func draw(_ base: NSColor, width: Int, part: Part) -> NSImage {
        Textures.draw(width, 432) { ctx, w, h in
            let b = base.usingColorSpace(.deviceRGB)!
            func shade(_ k: Double) -> CGColor {
                NSColor(calibratedRed: b.redComponent * k, green: b.greenComponent * k, blue: b.blueComponent * k, alpha: 1).cgColor
            }
            func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
                CGRect(x: x0 * w, y: y0 * h, width: (x1 - x0) * w, height: (y1 - y0) * h)
            }
            ctx.setFillColor(shade(1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            func seam(_ path: CGPath, _ alpha: Double) {
                ctx.setLineWidth(2)
                ctx.addPath(path)
                ctx.setStrokeColor(NSColor(rgb: (0.3, 0.32, 0.38), alpha: alpha).cgColor)
                ctx.strokePath()
                ctx.saveGState()
                ctx.translateBy(x: 1, y: 1.5)
                ctx.addPath(path)
                ctx.setStrokeColor(NSColor(white: 1, alpha: alpha * 0.7).cgColor)
                ctx.strokePath()
                ctx.restoreGState()
            }
            func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ alpha: Double = 0.16) {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x0 * w, y: y0 * h)); p.addLine(to: CGPoint(x: x1 * w, y: y1 * h))
                seam(p, alpha)
            }
            func panel(_ r: CGRect, _ alpha: Double) {
                seam(CGPath(roundedRect: r, cornerWidth: w * 0.05, cornerHeight: w * 0.05, transform: nil), alpha)
            }
            // The collar under the visor, the waistband, and the cuffs over the boots.
            line(0, 0.29, 1, 0.29, 0.2)
            ctx.setFillColor(shade(0.975))
            ctx.fill(rect(0, 0.6, 1, 0.645))
            line(0, 0.6, 1, 0.6); line(0, 0.645, 1, 0.645, 0.12)
            ctx.setFillColor(shade(0.965))
            ctx.fill(rect(0, 0.93, 1, 1))
            line(0, 0.93, 1, 0.93, 0.14)
            switch part {
            case .front:
                line(0.5, 0.3, 0.5, 0.6, 0.12)
                line(0.5, 0.645, 0.5, 0.93, 0.1)
                // The seam round the repository's patch, which the minion wears over it.
                panel(rect(patch.x0, patch.y0, patch.x1, patch.y1), 0.12)
            case .back:
                // The life-support pack: a panel with two vents.
                panel(rect(0.2, 0.33, 0.8, 0.56), 0.2)
                for y in [0.48, 0.51] { line(0.36, y, 0.64, y, 0.1) }
                line(0.5, 0.645, 0.5, 0.93, 0.1)
            case .side:
                line(0.5, 0.3, 0.5, 0.6, 0.1)
                line(0.5, 0.645, 0.5, 0.93, 0.08)
                panel(rect(0.22, 0.7, 0.78, 0.8), 0.1)
            }
        }
    }
}
