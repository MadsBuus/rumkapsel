// What a minion's box wears: a suit drawn on its faces, in the body's own white or the crew's grey.

import AppKit
import SceneKit

enum Suit {
    private static var made: [String: [SCNMaterial]] = [:]
    /// The back and side faces, which carry no badge: one pair per base colour.
    private static var plain: [Bool: (back: SCNMaterial, side: SCNMaterial)] = [:]

    static func key(_ badge: NSColor, crew: Bool) -> String { WallPanel.key(badge) + (crew ? "|crew" : "") }

    /// The box's six faces, in SCNBox's order: front, right, back, left, top, bottom.
    static func materials(badge: NSColor, crew: Bool) -> [SCNMaterial] {
        let k = key(badge, crew: crew)
        if let m = made[k] { return m }
        let base = crew ? NSColor(rgb: (0.62, 0.64, 0.7)) : Palette.minion
        func face(_ image: NSImage) -> SCNMaterial {
            let m = lit(base)
            m.diffuse.contents = image
            m.diffuse.mipFilter = .linear
            return m
        }
        let pair = plain[crew] ?? {
            let p = (back: face(draw(base, badge: badge, width: 192, part: .back)), side: face(draw(base, badge: badge, width: 96, part: .side)))
            plain[crew] = p
            return p
        }()
        let top = lit(base)
        let out = [face(draw(base, badge: badge, width: 192, part: .front)), pair.side, pair.back, pair.side, top, top]
        made[k] = out
        return out
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
    private static func draw(_ base: NSColor, badge: NSColor, width: Int, part: Part) -> NSImage {
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
                // The repository's colour: a small patch on the chest, toned into the suit.
                let patch = rect(0.64, 0.36, 0.8, 0.4)
                ctx.setFillColor(base.blended(withFraction: 0.6, of: badge)!.cgColor)
                ctx.fill(patch)
                panel(patch, 0.12)
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
