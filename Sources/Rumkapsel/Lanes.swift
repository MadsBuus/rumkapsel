// Doorways as one-lane sections, and who holds them: the rule apart from the picture.
//
// A room's doorway is its door tile, and the tile outside it for anyone going in or coming out;
// a yard doorway is its pair of tiles. A walker claims the lane before stepping into it, renews
// the claim while on it, and lets it go once off it; anyone else waits outside. A claim lapses a
// few station seconds after it was last renewed, so a stuck walker cannot lock a door. Tested by
// `--lane-tests` with a fake clock and made-up bodies; the scene only feeds it cells and time.

import Foundation

/// The lanes of one station: which cells belong to which lane, and which corridor tiles are a
/// door's approach.
struct DoorLanes {
    /// A room's door: its key, the door tile, and the corridor tile outside it.
    struct Door {
        var room: String
        var cell: Cell
        var outside: Cell?
    }

    /// Every lane cell by lane id.
    private(set) var lanes: [Cell: String] = [:]
    /// The tile outside each room's door, when it is not a lane cell itself: the lane and the room it leads to.
    private(set) var approaches: [Cell: (lane: String, room: String)] = [:]

    init() {}

    init(station: String, doors: [Door], yardDoorways: [(Cell, Cell)]) {
        var approaches: [Cell: (lane: String, room: String)] = [:]
        for d in doors {
            let id = lanes[d.cell] ?? "\(station)|door:\(d.room)"
            lanes[d.cell] = id
            if let out = d.outside, approaches[out] == nil { approaches[out] = (lane: id, room: d.room) }
        }
        for (a, b) in yardDoorways {
            let id = "\(station)|yard:\(a.x),\(a.y)-\(b.x),\(b.y)"
            lanes[a] = lanes[a] ?? id
            lanes[b] = lanes[b] ?? id
        }
        self.approaches = approaches.filter { lanes[$0.key] == nil }
    }

    /// The lane a cell is part of for one walker: a door or yard doorway tile always; the tile
    /// outside a room's door only for someone in that room or headed into it. Walking past along
    /// the corridor claims nothing.
    func lane(at cell: Cell, inRoom: String?, headedTo: String?) -> String? {
        if let id = lanes[cell] { return id }
        guard let a = approaches[cell] else { return nil }
        return inRoom == a.room || headedTo == a.room ? a.lane : nil
    }

    /// Whether a cell is any part of a lane, approach tiles included: nowhere to step aside to.
    func touches(_ cell: Cell) -> Bool { lanes[cell] != nil || approaches[cell] != nil }
}

/// Who holds which lane, and until when on the station clock.
struct LaneClaims {
    struct Claim {
        var holder: String
        var until: Double
    }
    /// How long a claim holds after it was last renewed, in station seconds.
    static let hold = 4.0

    private(set) var claims: [String: Claim] = [:]

    subscript(lane: String) -> Claim? { claims[lane] }

    /// Lapsed claims go.
    mutating func prune(at clock: Double) {
        claims = claims.filter { $0.value.until > clock }
    }

    /// One step of one walker, from the lane it stands on to the lane of its next tile, either or
    /// both nil. Returns true when the walker must wait outside: the next lane is held by someone
    /// else, alive and unlapsed. Otherwise the next lane is claimed, the lane stood on is renewed,
    /// and a lane the walker has left is released. `held` is the walker's own note of what it holds.
    mutating func step(walker: String, from here: String?, to next: String?, held: inout String?, at clock: Double,
                       alive: (String) -> Bool) -> Bool {
        var wait = false
        if let lane = next, lane != here {
            if let c = claims[lane], c.holder != walker, c.until > clock, alive(c.holder) {
                wait = true
            } else {
                claims[lane] = Claim(holder: walker, until: clock + LaneClaims.hold)
                held = lane
            }
        }
        if let lane = here, claims[lane]?.holder == walker { claims[lane] = Claim(holder: walker, until: clock + LaneClaims.hold) }
        if here == nil, next == nil, let h = held {
            if claims[h]?.holder == walker { claims[h] = nil }
            held = nil
        }
        return wait
    }
}
