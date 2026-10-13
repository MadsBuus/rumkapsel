import Foundation

enum Theme: String, CaseIterable, Identifiable {
    case classic
    case kenney
    case kingdom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .kenney: return "Kenney Space Center"
        case .kingdom: return "Kenney Kingdom"
        }
    }

    var credit: String? {
        switch self {
        case .classic: return nil
        case .kenney: return "Kenney Space Center draws the station with the Space Kit, the Modular Space Kit and the Nature Kit by Kenney (kenney.nl, CC0)."
        case .kingdom: return "Kenney Kingdom draws the station as a walled castle on the sea, with the Castle, Fantasy Town, Nature, Pirate, Survival and Hexagon kits and Cube Pets by Kenney (kenney.nl, CC0)."
        }
    }

    var kickRises: Bool { self == .classic }

    var padGap: Int {
        switch self {
        case .classic, .kingdom: return 0
        case .kenney: return 5
        }
    }

    var repoColors: [RGB] {
        switch self {
        case .classic, .kenney: return Colors.classicRepos
        case .kingdom: return Colors.heraldry
        }
    }

    var vocabulary: Vocabulary {
        var v = Vocabulary()
        guard self == .kingdom else { return v }
        v.bay = "caravans"; v.pad = "harbour"; v.storage = "granary"; v.deck = "market"; v.decon = "customs"
        v.zoneWaiting = "stored"; v.zoneTesting = "tasting"; v.zoneCleared = "sealed"
        v.dorm = "inn"; v.lounge = "tavern"; v.bath = "bathhouse"; v.gym = "training yard"; v.monolith = "keep"
        v.theBay = "the caravan gate"; v.thePad = "the harbour"; v.theRocket = "the ship"
        v.inStorage = "the granary"; v.theDeck = "the market"; v.testedRow = "the sealed stores"; v.testDeck = "market"
        v.inDecon = "customs"; v.theMonolith = "the keep"; v.theDorm = "the inn"; v.theCouch = "the tavern bench"
        v.theBath = "the bathhouse"; v.theGym = "the training yard"
        v.lookRound = "taking a stroll through the castle"; v.leaving = "leaving the castle through the gate"
        v.inbound = "a caravan on the road with"; v.stow = "stacking a sheaf for the commit"; v.pack = "loading a crate for the pull request"
        v.asleep = "asleep at the inn";
        v.qaWalk = "inspecting the stalls at the market"
        v.crate = "barrel"; v.crates = "barrels"; v.loadInto = "aboard the ship"; v.standingBy = "moored at the quay"
        v.steaming = "loaded and made fast"; v.liftingOff = "casting off"; v.launchedTo = "sailed for"; v.onThePad = "at the harbour"
        v.holding = "untested, held at the quay"; v.cleared = "cleared to sail"
        v.liftedOff = "set sail"; v.aboard = "in the hold"; v.passedInspection = "were stamped at the market"
        v.office = "workshop"; v.offices = "workshops"; v.job = "order"; v.jobs = "orders"
        v.kicked = "sent"; v.kickedOff = "away from the castle"; v.unidentified = "unmarked goods"; v.ejected = "turned away at customs"
        v.clearedDecon = "cleared customs, into the granary"; v.toStorage = "goods to the granary"; v.toDeck = "off to market"
        v.atMonolith = "in the keep"; v.foldsAway = "its crate folds away on the quay"; v.shipLeaving = "the caravan to pull away"
        v.shipBeside = "a caravan drawing up beside"; v.shipComing = "its caravan"; v.lightsOn = "lanterns lit"
        v.monolithHover = "the keep: scholars and messengers"; v.bayHover = "caravan gate · new offices arrive here by road"
        v.padHover = "harbour · release pull requests wait here; merging sends the ship"
        v.deconHover = "customs · dependabot and friends wait here"
        return v
    }

    static var pinnedForPlan: Theme?
    static var forPlan: Theme { pinnedForPlan ?? ConfigStore.shared.current.theme }
}

struct Vocabulary {
    var bay = "bay", pad = "launch", storage = "storage", deck = "staging", decon = "decon"
    var zoneWaiting = "waiting", zoneTesting = "testing", zoneCleared = "cleared"
    var dorm = "dorm", lounge = "lounge", bath = "bath", gym = "gym", monolith = "monolith"
    var theBay = "the bay", thePad = "the pad", theRocket = "the rocket"
    var inStorage = "storage", theDeck = "the deck", testedRow = "the cleared rows", testDeck = "test deck", inDecon = "decon"
    var theMonolith = "the monolith", theDorm = "the dorm", theCouch = "the couch", theBath = "the bath", theGym = "the gym"
    var lookRound = "having a look round the station", leaving = "off the station on the next shuttle"
    var inbound = "shuttle inbound with", stow = "stowing a cube for the commit", pack = "packing a crate for the pull request"
    var asleep = "asleep in the dorm"
    var qaWalk = "walking the rows on the deck"
    var crate = "crate", crates = "crates", loadInto = "into the rocket", standingBy = "standing by on the pad"
    var steaming = "go for launch", liftingOff = "lifting off", launchedTo = "launched to", onThePad = "on the pad"
    var holding = "untested, holding on the pad", cleared = "cleared for launch"
    var liftedOff = "lifted off", aboard = "aboard", passedInspection = "passed inspection"
    var office = "office", offices = "offices", job = "job", jobs = "jobs"
    var kicked = "kicked", kickedOff = "off the station", unidentified = "unidentified object", ejected = "ejected from decon"
    var clearedDecon = "cleared decon, into storage", toStorage = "package to storage", toDeck = "moving to the test deck"
    var atMonolith = "at the monolith", foldsAway = "its crate folds away on the bay", shipLeaving = "the ship to lift off"
    var shipBeside = "a ship coming down beside", shipComing = "its ship", lightsOn = "lights on"
    var monolithHover = "the monolith: web research and subagents", bayHover = "hangar · new offices arrive here by ship"
    var padHover = "launch pad · release pull requests wait here; merging launches"
    var deconHover = "decon · dependabot and friends wait here"
}

enum Words {
    static var pinned: Vocabulary?
    static var current: Vocabulary { pinned ?? Theme.forPlan.vocabulary }
}
