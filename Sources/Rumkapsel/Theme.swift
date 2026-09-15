// Which look the station is drawn in, as the model knows it: a name for the config, a title and a
// credit for the picker, and the one knob a theme may turn on the floor plan. Nothing here draws;
// how a theme draws lives in Looks/, behind `Look`, and the scene is the only thing that asks.

import Foundation

enum Theme: String, CaseIterable, Identifiable {
    case classic
    case kenney

    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .kenney: return "Kenney Space Center"
        }
    }

    /// Whose work the look is built from, for the settings page.
    var credit: String? {
        switch self {
        case .classic: return nil
        case .kenney: return "Kenney Space Center draws the station with the Space Kit, the Modular Space Kit and the Nature Kit by Kenney (kenney.nl, CC0)."
        }
    }

    /// Tiles between the test deck and the launch pad: hard by it in Classic, a causeway's length out on
    /// the ground. The only way a theme reaches the floor plan.
    var padGap: Int {
        switch self {
        case .classic: return 0
        case .kenney: return 5
        }
    }

    /// The theme the plan is laid out for: the config's, unless a test pins one.
    static var pinnedForPlan: Theme?
    static var forPlan: Theme { pinnedForPlan ?? ConfigStore.shared.current.theme }
}
