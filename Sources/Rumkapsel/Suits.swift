// What a minion's box wears: a suit drawn on its faces, in the body's own white or the crew's grey.

import AppKit
import SceneKit

enum Suit {
    private static var made: [String: [SCNMaterial]] = [:]

    static func key(_ badge: NSColor, crew: Bool) -> String { WallPanel.key(badge) + (crew ? "|crew" : "") }

    /// The box's six faces, in SCNBox's order: front, right, back, left, top, bottom.
    static func materials(badge: NSColor, crew: Bool, subagent: Bool) -> [SCNMaterial] {
        let k = key(badge, crew: crew) + (subagent ? "|sub" : "")
        if let m = made[k] { return m }
        let base = crew ? NSColor(rgb: (0.62, 0.64, 0.7)) : Palette.minion
        func face(_ image: NSImage) -> SCNMaterial {
            let m = lit(base)
            m.diffuse.contents = image
            m.diffuse.mipFilter = .linear
            return m
        }
        let side = face(draw(base, badge: badge, width: 48, part: .side))
        let plain = lit(base)
        let out = [face(draw(base, badge: badge, width: 96, part: .front)), side,
                   face(draw(base, badge: badge, width: 96, part: .back)), side, plain, plain]
        made[k] = out
        return out
    }

    /// Dark glass with a cold light behind it and a streak of reflection across.
    static let visor: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Textures.draw(64, 16) { ctx, w, h in
            ctx.setFillColor(NSColor(rgb: (0.07, 0.11, 0.17)).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(NSColor(rgb: (0.16, 0.36, 0.46)).cgColor)
            ctx.fill(CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.45))
            ctx.setFillColor(NSColor(white: 1, alpha: 0.45).cgColor)
            ctx.move(to: CGPoint(x: w * 0.18, y: 0)); ctx.addLine(to: CGPoint(x: w * 0.3, y: 0))
            ctx.addLine(to: CGPoint(x: w * 0.2, y: h)); ctx.addLine(to: CGPoint(x: w * 0.08, y: h)); ctx.fillPath()
        }
        return m
    }()

    private enum Part { case front, back, side }

    /// One face, `width` pixels across and as tall as a standing body is to its width; heights below are
    /// fractions down from the top of the head.
    private static func draw(_ base: NSColor, badge: NSColor, width: Int, part: Part) -> NSImage {
        let h = 216
        return Textures.draw(width, h) { ctx, w, h in
            let b = base.usingColorSpace(.deviceRGB)!
            func shade(_ k: Double) -> CGColor {
                NSColor(calibratedRed: b.redComponent * k, green: b.greenComponent * k, blue: b.blueComponent * k, alpha: 1).cgColor
            }
            func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
                CGRect(x: x0 * w, y: y0 * h, width: (x1 - x0) * w, height: (y1 - y0) * h)
            }
            func ink(_ alpha: Double) -> CGColor { NSColor(rgb: (0.1, 0.11, 0.16), alpha: alpha).cgColor }
            // Lit from above: a shade lighter at the shoulders, a shade darker at the shins.
            for i in 0..<12 {
                let t = Double(i) / 11
                ctx.setFillColor(shade(1.02 - 0.08 * t))
                ctx.fill(rect(0, Double(i) / 12, 1, Double(i + 1) / 12 + 0.002))
            }
            func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, alpha: Double, width lw: CGFloat = 1.5) {
                ctx.setStrokeColor(ink(alpha)); ctx.setLineWidth(lw)
                ctx.move(to: CGPoint(x: x0 * w, y: y0 * h)); ctx.addLine(to: CGPoint(x: x1 * w, y: y1 * h)); ctx.strokePath()
            }
            line(0, 0.29, 1, 0.29, alpha: 0.18)
            switch part {
            case .front:
                line(0.5, 0.3, 0.5, 0.6, alpha: 0.22)
                line(0.13, 0.3, 0.13, 0.6, alpha: 0.1); line(0.87, 0.3, 0.87, 0.6, alpha: 0.1)
                ctx.setFillColor(badge.cgColor)
                ctx.fill(rect(0.6, 0.34, 0.85, 0.43))
                ctx.setStrokeColor(ink(0.35)); ctx.setLineWidth(1)
                ctx.stroke(rect(0.6, 0.34, 0.85, 0.43))
                ctx.setFillColor(NSColor(white: 1, alpha: 0.5).cgColor)
                ctx.fill(rect(0.63, 0.36, 0.7, 0.38))
            case .back:
                ctx.setFillColor(shade(0.86))
                ctx.fill(rect(0.15, 0.18, 0.85, 0.56))
                ctx.setStrokeColor(ink(0.3)); ctx.setLineWidth(1.5)
                ctx.stroke(rect(0.15, 0.18, 0.85, 0.56))
                for y in [0.42, 0.46, 0.5] { line(0.25, y, 0.75, y, alpha: 0.35) }
                ctx.setFillColor(badge.cgColor)
                ctx.fill(rect(0.68, 0.22, 0.78, 0.26))
            case .side:
                line(0.5, 0.3, 0.5, 0.6, alpha: 0.12)
                ctx.setStrokeColor(ink(0.18)); ctx.setLineWidth(1)
                ctx.stroke(rect(0.2, 0.7, 0.8, 0.79))
            }
            // The belt, its buckle in front, and the legs below it.
            ctx.setFillColor(NSColor(rgb: (0.27, 0.28, 0.33)).cgColor)
            ctx.fill(rect(0, 0.6, 1, 0.67))
            if part == .front {
                ctx.setFillColor(NSColor(rgb: (0.78, 0.8, 0.84)).cgColor)
                ctx.fill(rect(0.43, 0.605, 0.57, 0.665))
            }
            if part != .side {
                line(0.5, 0.69, 0.5, 1, alpha: 0.25)
                ctx.setFillColor(ink(0.08))
                ctx.fill(rect(0.12, 0.79, 0.4, 0.85)); ctx.fill(rect(0.6, 0.79, 0.88, 0.85))
            }
            ctx.setFillColor(NSColor(rgb: (0.3, 0.31, 0.36)).cgColor)
            ctx.fill(rect(0, 0.94, 1, 1))
            // A little wear, the same scuffs on every suit.
            var r = Textures.Seeded(s: part == .front ? 7 : part == .back ? 11 : 13)
            for _ in 0..<4 {
                let x = r.next() * 0.8, y = 0.45 + r.next() * 0.45, s = 0.04 + r.next() * 0.08
                ctx.setFillColor(ink(0.05 + r.next() * 0.04))
                ctx.fillEllipse(in: rect(x, y, x + s, y + s * 0.5))
            }
        }
    }
}
