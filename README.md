# rumkapsel

A tiny macOS desk toy, a homage to [rymdkapsel](https://rymdkapsel.com) by Grapefrukt: your Claude Code sessions
are minions on a space station. Repos are colours, Conductor worktrees are offices, the monolith is where
web research and subagents happen, commits pile up as boxes, and pull requests colour them.


## Contributing

Pull requests welcome. Fork, branch, `./build.sh run` to try it, open a PR. Feature requests and bugs go in [issues](https://github.com/MadsBuus/rumkapsel/issues).

## Build

```bash
./build.sh run
```

Requires Xcode 26 / Swift 6.3 and the `gh` CLI for pull request lookups.

## Tests

```bash
swift build --build-system native && .build/debug/Rumkapsel --scenarios
```

runs the scripted scenarios headless in about twelve seconds; `--sim-tests`, `--idle-tests`, `--walk-tests`,
`--ledger-tests`, `--work-tests`, `--pipeline-tests` and `--layout-tests` run the model on its own, no window. TESTING.md has the whole gate
and where it is going.

## Release

`./release.sh 0.32` builds, signs, notarises and publishes a release with a Sparkle appcast. Notarisation
needs credentials stored once with `xcrun notarytool store-credentials rumkapsel`; without them the script
signs and publishes but says so, and the app is not notarised.

## Themes

Settings › General › Look picks how the station is drawn. **Classic** is the flat-shaded homage, adrift in
space. **Kenney Space Center** puts the same floor plan on the ground, laid out like the Cape: a lawn to every
side, the sea past the yard so the launch pad stands nearest the water, palms along the shore. It is built
from Kenney's [Space Kit](https://kenney.nl/assets/space-kit), [Modular Space Kit](https://kenney.nl/assets/modular-space-kit)
and [Nature Kit](https://kenney.nl/assets/nature-kit) (all CC0): astronauts for minions, kerbed platform
tiles for every floor, arches on the airlock and the decon hatch, a comms tower for the monolith, kit
rockets and speeders, a desk in every office, fuel by the pad and a rover in the bay. The view starts turned
about so the pad faces right. The models used live in `Resources/Kenney`.

THEMES.md is the guide to designing one: the layers of a place, designing for change, and how theme work is judged.

## Controls

| Key / gesture | Action |
|---|---|
| pinch | zoom, around the cursor |
| two-finger rotate | spin around the point under the cursor |
| two-finger slide | pan |
| one-finger drag up/down | tilt |
| W / A / S / D | pan |
| E / Q | zoom in / out |
| 1 / 2 / 3 / 4 | focus a station (work, then private) |
| 0 | focus the whole fleet |
| R | reset view |
| M | music (off by default) |
| F | float on top |
| click a minion | follow it: the camera goes with it, its order written along the bottom; Esc, a pan or a click on the floor lets go |
| double-click a minion | ask GitHub again about its repo |
| click a box | open the pull request or issue |
| right-click an office | kick it off the station (offices put there by peers or GitHub) |

## A minion's day

- **Working**: at its office, on the cone or with a tool. Every stretch of work is timed.
- **Just done** (under a minute): hops at the office, eager for your reply.
- **Waiting** (a minute to the quiet limit in Settings): paces its office.
- **Quiet**: by day it reads on a lounge couch; by night it sleeps in the dorm. Night is 22 to 07.
- **Bath**: a shower after twenty minutes or more of work, sometimes a pee after a shorter stretch, and loungers go every half hour or so. Never while busy, carrying, on an errand or in bed; if work calls mid-visit, it leaves at once.
- **Session over**: lounge by day, dorm by night. After twenty minutes the extras leave; two stay on standby.
- **QA**: while untested crates sit on the deck, one free worker walks the rows.

## Sharing on the local network

With sharing on, rumkapsels on the same network merge their work stations into one. An office is identified by its branch, so a colleague's checkout, your own worktree and the pull request on GitHub all light the same room. Each app only shares what it has checked out itself, in the repositories ticked under Repositories; what it learned from GitHub or from another peer never goes back out. A branch that exists only on someone's disk shows as an outlined room, and becomes a real one once it is pushed. Offices are held for a day after the last word from whoever had them, so people coming and going does not rearrange the station. Parsed GitHub answers ride along too, so one poll serves everyone in range.

## Flags

`--demo` runs with fake sessions. `--snapshot out.png --delay 6` renders a frame and exits.

`--gallery` opens the gallery: every routine a body plays and every piece the current theme draws,
one to a tile. The motion comes from the same table the station's tick reads and the pieces from the
current look, so a tile cannot show what the app does not. `--gallery --tiles` lists the sheet,
`--gallery --tile rockets --snapshot out.png` frames the tile whose name has those words for a
picture of one thing, and in the window `]` and `[` step between tiles with `0` for the whole sheet.

`--simulator` opens the simulator window on its own: a real station with the scanner, GitHub and the
network switched off, driven by a panel that writes made-up facts through the same entry points
production uses. The panel is a board and the moves on it. The board is the position — the session
in the target office, its commits, its pull request, its column, the repository's pipeline and
releases, the peer, the night — one knob each. The moves are what happens, one press each, and a
move whose ground is not laid lays it before it plays, so `Merge PR` on an office with no pull
request opens one first rather than greying out.

`--simulate "Target: web#455,Set: commits ahead = 8,Merge PR"` presses those in order, two seconds
apart: `Target:` picks the office, `Set: <knob> = <value>` turns a knob, and anything else is a move.
It pairs with `--snapshot` for a scripted check; the board's knobs and the whole event and command
log go to stderr when the snapshot is written. Every name is listed at the top of `Simulator.swift`.

## A homage

This exists because of [rymdkapsel](https://rymdkapsel.com), Martin Jonasson's (Grapefrukt) small, perfect space station game.
The tetromino rooms, the brown corridors, the tiny white minions, the monolith, the drone: all of that is his idea, and we borrowed the look
with love and no permission. If you have not played it, go play it. It is on every platform and it is a few dollars well spent.
Rumkapsel is a desk toy, not a game, and it is not affiliated with Grapefrukt in any way.
