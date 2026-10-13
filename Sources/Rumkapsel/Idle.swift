import Foundation

struct IdleClock {
    private(set) var dueAt = 0.0
    static let span = 120.0...300.0

    var armed: Bool { dueAt > 0 }

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

enum IdleAfter: Equatable {
    case rest
    case bath(shower: Bool)
    case roam

    static let bathBelow = 0.35, showerBelow = 0.12, roamBelow = 0.3

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

enum IdlePick: Equatable {
    case roam
    case gym
    case bath(shower: Bool)
    case read

    static let roamBelow = 0.40, gymBelow = 0.65, bathBelow = 0.85

    static func pick(roll: Double, night: Bool, crew: Bool, gymFree: Bool, bath: Bool, shower: Bool) -> IdlePick {
        if roll < roamBelow { return .roam }
        if roll < gymBelow { return !night && !crew && gymFree ? .gym : .roam }
        if roll < bathBelow { return bath ? .bath(shower: shower) : .roam }
        return .read
    }
}

enum RoamSpots {
    static func choose(clear: [Cell], taken: [Cell], company: Bool, random: ([Cell]) -> Cell? = { $0.randomElement() }) -> Cell? {
        let apart = clear.filter { c in !taken.contains { abs($0.x - c.x) + abs($0.y - c.y) < 3 } }
        return random(company || apart.isEmpty ? clear : apart)
    }
}
