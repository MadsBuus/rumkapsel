import Foundation

enum Callsign {
    static let ranks = [
        "Ensign", "Lieutenant", "Commander", "Chief Engineer", "Science Officer", "Yeoman", "Cadet", "Redshirt", "Helmsman",
        "Navigator", "Quartermaster", "Away Team", "Space Cadet", "Overseer", "Vault Dweller", "Wastelander", "Ghoul", "Scribe",
        "Paladin", "Courier", "Raider", "Padawan", "Scavenger", "Moisture Farmer", "Bounty Hunter", "Smuggler", "Droid Wrangler",
        "Junk Dealer", "Mechanic", "Pit Crew", "Tractor Beam Tech", "Airlock Warden", "Hyperdrive Tuner", "Rad Sponge",
    ]

    static let names = [
        "Bixby", "Quarkle", "Zimmo", "Tarka", "Vorn", "Plink", "Grubbs", "Nebbish", "Rollo", "Dweeble", "Sprocket", "Glorp",
        "Tibbs", "Brack", "Mobo", "Zuzu", "Rook", "Fennick", "Pellow", "Kiko", "Snoot", "Bolo", "Rivet", "Fizzwick", "Pockle",
        "Grommet", "Tupper", "Mungo", "Biscuit", "Noodle", "Pip", "Waffles", "Crumb", "Zorp", "Blip", "Nubbin", "Vex", "Tamsin",
        "Quill", "Ozzo", "Dorrick", "Lumo", "Pasko", "Haddle", "Ruckus", "Tinker", "Mops", "Jinx", "Bobbin", "Fuse", "Wobble",
        "Dingus", "Pickles", "Scoot", "Gubbins", "Tork", "Yarrow", "Brisket", "Moxie", "Pinto", "Dabble", "Squib", "Thimble",
    ]

    static func of(_ id: String) -> String {
        let h = stableHash(id)
        return ranks[Int(h % UInt64(ranks.count))] + " " + names[Int((h / UInt64(ranks.count)) % UInt64(names.count))]
    }
}
