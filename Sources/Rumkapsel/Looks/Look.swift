// How the station is drawn. The scene owns where everything stands, what it is named, what the walks
// go round and how things move; a look only says what a thing is drawn as. Every piece comes back as a
// node with its origin where the scene expects it, and the scene places it, names it and fades it.
// A new theme is a new `Look` and a case in `Theme`; nothing in the scene branches on which one is on.

import AppKit
import SceneKit

protocol Look {
    /// The colour past the edge of everything.
    var background: NSColor { get }
    /// The view's turn about the vertical before the user turns it.
    var viewYaw: Double { get }
    /// How far the floor's top stands over a tile's plane: flat marks on the floor go above it.
    var floorTop: Double { get }
    /// Whether the hallway gets its small dark dots.
    var dotsHallway: Bool { get }

    /// What lies beyond the fleet, into `root`; returns what drifts, each with its velocity.
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)]
    /// The ground under the fleet, into `root`; rebuilt with the floor, since the fleet's extent moves.
    func ground(under stations: [Station], into root: SCNNode)

    /// Hung under a floor tile's plane, in the plane's frame; `open` holds the edges with no floor beyond,
    /// numbered round the tile z-, x-, z+, x+.
    func tileDetail(open: Set<Int>, color: NSColor) -> SCNNode?
    /// Recolour a floor tile and whatever the look hung on it.
    func tint(tile: SCNNode, _ color: NSColor)

    /// The frame over the airlock's doorway, `width` across, with a tile under each of `spans` (x from its
    /// middle). The posts are the scene's, since the walks go between them; `showsPosts` says if they are drawn.
    func airlockFrame(width: Double, spans: [Double], tint: NSColor) -> (node: SCNNode, showsPosts: Bool)
    /// The decon hatch's frame for a hatch facing along `facing`, and the height its light hangs at.
    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double)
    /// The monolith, standing on the origin.
    func monolith() -> SCNNode

    /// A figure to stand in a minion's box, or nil to draw the box.
    func figure(crew: Bool, height: Double) -> SCNNode?
    /// Pose that figure `torso` tall, hung from the middle of a box `height` tall: the full height standing.
    func pose(figure: SCNNode, height: Double, torso: Double)
    /// A shuttle, nose along +x, its hull's middle at the origin.
    func shuttle(color: NSColor) -> SCNNode
    /// A rocket standing on the origin, with children named "hatch" and "flame" the scene reaches for.
    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode

    /// Props for a station, in the station's own cells, in spots nobody stands on.
    func dress(station: Station) -> [SCNNode]
    /// A prop for an office, in the station's own cells.
    func dress(office room: Room, in station: Station) -> SCNNode?
}

/// The look the scene draws with, swapped when the theme changes.
enum Looks {
    private(set) static var theme: Theme = .classic
    private(set) static var current: Look = ClassicLook()

    static func use(_ theme: Theme) {
        self.theme = theme
        switch theme {
        case .classic: current = ClassicLook()
        case .kenney: current = KenneyLook()
        }
    }
}
