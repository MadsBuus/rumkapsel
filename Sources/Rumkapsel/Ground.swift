// The ground under the station in the Kenney theme, laid out as the Cape is: a lawn to every side,
// the sea past the yard so the pad stands nearest the water, palms along the shore and scrub on the
// grass. Rebuilt with the floor, since the fleet's extent moves; nothing here is walked on or hit.

import AppKit
import SceneKit

/// A small generator of its own, so the scrub stands where it stood on the last rebuild.
struct Scatter {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func between(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    mutating func pick<T>(_ items: [T]) -> T { items[min(items.count - 1, Int(next() * Double(items.count)))] }
}

extension StationController {
    func rebuildGround() {
        groundRoot.childNodes.forEach { $0.removeFromParentNode() }
        guard Theme.isKenney else { return }
        // The fleet's footprint in world units: each station's bounds, with its offset, and the whole.
        var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
        var footprints: [(lo: SIMD2<Double>, hi: SIMD2<Double>)] = []
        for st in fleet.stations.values {
            let b = st.bounds
            let a = SIMD2(Double(b.min.x) + st.offset.x - 0.5, Double(b.min.y) + st.offset.y - 0.5)
            let z = SIMD2(Double(b.max.x) + st.offset.x + 0.5, Double(b.max.y) + st.offset.y + 0.5)
            footprints.append((a, z))
            lo = pointwiseMin(lo, a); hi = pointwiseMax(hi, z)
        }
        guard lo.x.isFinite else { return }
        let onStation = { (p: SIMD2<Double>, margin: Double) -> Bool in
            footprints.contains { p.x > $0.lo.x - margin && p.x < $0.hi.x + margin && p.y > $0.lo.y - margin && p.y < $0.hi.y + margin }
        }
        // The pad stands at the fleet's west end on its causeway, so the sea begins a few tiles past it.
        let shore = (lo.x - 4).rounded()
        let mid = (lo + hi) / 2
        let reach = 140.0
        let lawn = SCNNode(geometry: SCNPlane(width: reach, height: reach * 2))
        lawn.geometry!.firstMaterial = lit(Kit.grass)
        lawn.eulerAngles.x = -.pi / 2
        lawn.position = v3(shore + reach / 2, -0.03, mid.y)
        groundRoot.addChildNode(lawn)
        let sea = SCNNode(geometry: SCNPlane(width: reach, height: reach * 2))
        sea.geometry!.firstMaterial = lit(Kit.water)
        sea.eulerAngles.x = -.pi / 2
        sea.position = v3(shore - reach / 2, -0.08, mid.y)
        groundRoot.addChildNode(sea)
        // The shore: the kit's bank tiles in a row, their grass side turned toward the station.
        let span = Int(reach / 2)
        let midZ = mid.y.rounded()
        for k in -span...span {
            guard let bank = Kit.node("ground_riverSide", from: .nature, tint: Kit.shoreTint) else { break }
            bank.eulerAngles.y = .pi / 2
            bank.position = v3(shore + 0.5, -0.03, midZ + Double(k))
            groundRoot.addChildNode(bank)
        }
        var rng = Scatter(seed: 7)
        func plant(_ name: String, at p: SIMD2<Double>, scale: Double) {
            guard let n = Kit.node(name, from: .nature, tint: Kit.scrubTint) else { return }
            n.scale = SCNVector3(scale, scale, scale)
            n.eulerAngles.y = rng.between(0, 2 * .pi)
            n.position = v3(p.x, -0.03, p.y)
            groundRoot.addChildNode(n)
        }
        // Palms along the shore, a few steps up the bank, and never on the station.
        let palms = ["tree_palm", "tree_palmTall", "tree_palmBend", "tree_palmDetailedShort"]
        for _ in 0..<26 {
            let p = SIMD2(shore + rng.between(1.2, 4.5), midZ + rng.between(-Double(span) + 2, Double(span) - 2))
            guard !onStation(p, 1.5) else { continue }
            plant(rng.pick(palms), at: p, scale: rng.between(0.75, 1.1))
        }
        // Scrub on the lawn round the fleet: tufts of grass most of all, then bushes, rocks and flowers.
        let scrub = ["grass", "grass", "grass_large", "grass_large", "plant_bush", "plant_bushLarge", "rock_smallA", "rock_smallB", "flower_yellowA", "flower_redA"]
        for _ in 0..<140 {
            let p = SIMD2(rng.between(max(shore + 1.5, lo.x - 22), hi.x + 22), rng.between(lo.y - 22, hi.y + 22))
            guard !onStation(p, 1.2) else { continue }
            plant(rng.pick(scrub), at: p, scale: rng.between(0.7, 1.1))
        }
        for _ in 0..<6 {
            let p = SIMD2(rng.between(max(shore + 3, lo.x - 22), hi.x + 22), rng.between(lo.y - 22, hi.y + 22))
            guard !onStation(p, 2) else { continue }
            plant("rock_largeA", at: p, scale: rng.between(0.8, 1.2))
        }
    }
}
