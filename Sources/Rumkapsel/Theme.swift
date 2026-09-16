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

    /// Whether each station is a world of its own, shown one at a time, rather than the fleet laid out together.
    var separateWorlds: Bool { false }

    /// The words the station's parts and doings are called by in this theme.
    var vocabulary: Vocabulary { Vocabulary() }

    /// The theme the plan is laid out for: the config's, unless a test pins one.
    static var pinnedForPlan: Theme?
    static var forPlan: Theme { pinnedForPlan ?? ConfigStore.shared.current.theme }
}

/// The words a theme calls the station's parts and doings by: floor signs, hover text, orders and the log.
/// These are Classic's; a theme changes only the ones it draws as something else.
struct Vocabulary {
    // Floor signs.
    var bay = "bay", airlock = "airlock", pad = "launch", storage = "storage", deck = "staging", decon = "decon"
    var dorm = "dorm", lounge = "lounge", bath = "bath"
    // Places, as said in a sentence.
    var theBay = "the bay", theAirlock = "the airlock", thePad = "the pad", theRocket = "the rocket"
    var inStorage = "storage", theDeck = "the deck", testedRow = "the deck, tested row", testDeck = "test deck", inDecon = "decon"
    var theMonolith = "the monolith", theDorm = "the dorm", theCouch = "the couch", theBath = "the bath", theGym = "the gym"
    // What minions are doing.
    var lookRound = "having a look round the station", leaving = "off the station through the airlock"
    var inbound = "shuttle inbound with", stow = "stowing a cube for the commit", pack = "packing a crate for the pull request"
    var asleep = "asleep in the dorm", console = "off to the storage console with the tablet", pallet = "the pallet"
    var qaWalk = "walking the rows on the deck"
    // Releases.
    var crate = "crate", crates = "crates", loadInto = "into the rocket", standingBy = "standing by on the pad"
    var steaming = "loaded and steaming", liftingOff = "lifting off", launchedTo = "launched to", onThePad = "on the pad"
    var holding = "untested, holding on the pad", cleared = "cleared for launch"
    // The log.
    var kicked = "kicked", kickedOff = "off the station", unidentified = "unidentified object", ejected = "ejected from decon"
    var clearedDecon = "cleared decon, into storage", toStorage = "package to storage", toDeck = "moving to the test deck"
    var atMonolith = "at the monolith", foldsAway = "its crate folds away on the bay", shipLeaving = "the ship to lift off"
    var shipBeside = "a ship coming down beside", lightsOn = "lights on"
    // Hover text.
    var monolithHover = "the monolith: web research and subagents", bayHover = "hangar · new offices arrive here by ship"
    var padHover = "launch pad · release pull requests wait here; merging launches"
    var deconHover = "decon · dependabot and friends wait here"
}

enum Words {
    /// Pinned by the test runs, so the log lines a scenario expects read the same whatever theme is picked.
    static var pinned: Vocabulary?
    static var current: Vocabulary { pinned ?? Theme.forPlan.vocabulary }
}
