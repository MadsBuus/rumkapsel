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
    case galley(Command.Fare)

    static let bathBelow = 0.2, showerBelow = 0.08, roamBelow = 0.3, galleyBelow = 0.45

    static func after(_ rank: Rank?, roll: Double, night: Bool, bath: Bool, galley: Command.Fare? = nil) -> IdleAfter {
        if night { return .rest }
        switch rank {
        case .yard?, .release?:
            return bath && roll < bathBelow ? .bath(shower: roll < showerBelow) : .rest
        case .desk?, .message?, .qa?:
            if roll < roamBelow { return .roam }
            if let galley, roll < galleyBelow { return .galley(galley) }
            return .rest
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
    case galley(Command.Fare)
    case mission

    static let galleyFrom = 0.2, roamBelow = 0.33, gymBelow = 0.5, bathBelow = 0.58, missionBelow = 0.85

    static func pick(roll: Double, night: Bool, crew: Bool, gymFree: Bool, bath: Bool, shower: Bool, galley: Command.Fare? = nil, mission: Bool = false) -> IdlePick {
        if roll < roamBelow { return roll >= galleyFrom && !night ? galley.map { .galley($0) } ?? .roam : .roam }
        if roll < gymBelow { return !night && !crew && gymFree ? .gym : .roam }
        if roll < bathBelow { return bath ? .bath(shower: shower) : .roam }
        if roll < missionBelow { return !night && mission ? .mission : .read }
        return .read
    }
}

enum RoamSpots {
    static func choose(clear: [Cell], taken: [Cell], company: Bool, random: ([Cell]) -> Cell? = { $0.randomElement() }) -> Cell? {
        let apart = clear.filter { c in !taken.contains { abs($0.x - c.x) + abs($0.y - c.y) < 3 } }
        return random(company || apart.isEmpty ? clear : apart)
    }
}
