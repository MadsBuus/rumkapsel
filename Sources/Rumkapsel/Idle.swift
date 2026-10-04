// A lounger's idle life: the rule apart from the picture.
//
// One idle clock per lounger, two to five minutes. When it runs out one thing is picked by weight:
// a look round the station most often, a turn in the gym by day, the bath, or staying on the couch
// with a book. Leaving the lounge does not reset the clock; becoming busy does; it starts again
// only once the lounger is back on the couch with nothing to do. Tested by `--idle-tests`.

import Foundation

/// The clock: armed when a lounger settles with nothing to do, kept while away, dropped by work.
struct IdleClock {
    /// When the clock runs out on the station clock; 0 while unarmed.
    private(set) var dueAt = 0.0
    static let span = 120.0...300.0

    var armed: Bool { dueAt > 0 }

    /// One tick. `lounging` is settled on the couch with nothing to do; `busy` is real work. Returns
    /// true the tick the clock runs out, once, and disarms so the next arming waits for a return.
    mutating func tick(at clock: Double, lounging: Bool, busy: Bool, span: () -> Double = { Double.random(in: IdleClock.span) }) -> Bool {
        var due = false
        if lounging {
            if dueAt == 0 { dueAt = clock + span() }
            if clock >= dueAt { dueAt = 0; due = true }
        }
        if busy { dueAt = 0 }
        return due
    }
}

/// What a body does the moment an order ends and the board has nothing for it: by night, rest; after
/// hard work, now and then the bath first; after work at a desk, a message or QA, now and then a look
/// round the station; otherwise rest, where the idle clock takes over.
enum IdleAfter: Equatable {
    case rest
    case bath(shower: Bool)
    case roam

    /// A breather in the bath after hard work this often, a shower the hardest; a look round after quiet
    /// work this often.
    static let bathBelow = 0.35, showerBelow = 0.12, roamBelow = 0.3

    /// The choice for one roll in 0..<1, after an order of `rank` (nil when none was in hand).
    static func after(_ rank: Rank?, roll: Double, night: Bool, bath: Bool) -> IdleAfter {
        if night { return .rest }
        switch rank {
        case .yard?, .release?:
            return bath && roll < bathBelow ? .bath(shower: roll < showerBelow) : .rest
        case .desk?, .message?, .qa?:
            return roll < roamBelow ? .roam : .rest
        default:
            return .rest
        }
    }
}

/// What a lounger does when the clock runs out.
enum IdlePick: Equatable {
    case roam
    case gym
    case bath(shower: Bool)
    case read

    /// The weights: a look round most often, then the gym, then the bath, and now and then a book.
    static let roamBelow = 0.40, gymBelow = 0.65, bathBelow = 0.85

    /// The pick for one roll in 0..<1. The gym only by day and never for the crew, the bath only where
    /// there is one; a pick with nowhere to go becomes a look round the station instead. `gymFree`
    /// says a fixture is free; `shower` decides between a shower and the toilet.
    static func pick(roll: Double, night: Bool, crew: Bool, gymFree: Bool, bath: Bool, shower: Bool) -> IdlePick {
        if roll < roamBelow { return .roam }
        if roll < gymBelow { return !night && !crew && gymFree ? .gym : .roam }
        if roll < bathBelow { return bath ? .bath(shower: shower) : .roam }
        return .read
    }
}

/// Where a look round the station may stand: a clear tile out of every doorway, apart from where
/// others stand and where other roamers are headed; beside the pad when a loaded rocket steams,
/// where company is fine.
enum RoamSpots {
    static func choose(clear: [Cell], taken: [Cell], company: Bool, random: ([Cell]) -> Cell? = { $0.randomElement() }) -> Cell? {
        let apart = clear.filter { c in !taken.contains { abs($0.x - c.x) + abs($0.y - c.y) < 3 } }
        return random(company || apart.isEmpty ? clear : apart)
    }
}
