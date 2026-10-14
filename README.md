# rumkapsel

A tiny macOS desk toy, a homage to [rymdkapsel](https://rymdkapsel.com) by Grapefrukt: your Claude Code
sessions are minions on a space station. Every piece of work gets an office, commits pile up as cubes, a
pull request is a crate that is carried through the yard as it merges, is tested and ships, and a
release goes up in a rocket. Repositories are colours, teammates' work shows up from GitHub, and
stations on the same network share a floor.

## Build and run

```bash
./build.sh run        # the release build, then launch it
./build.sh fast run   # a debug build for this machine only, in seconds
./test.sh             # the gate, before every commit
```

Requires macOS 14 and Xcode 26 / Swift 6.3 to build.

## Setting up

What the station needs:

- **git**, and **Claude Code sessions**: every folder a session runs in that is a git checkout becomes a
  repository on the station, wherever it lives. Worktrees join their repository. Settings › Repositories ›
  Watch a repository… adds one by hand.
- **GitHub pull requests**, read through the [GitHub CLI](https://cli.github.com) (`brew install gh`, then
  `gh auth login`). Without a GitHub remote a repository is local work only: offices and cubes, no crates.

That is enough for the whole station: offices, crates in storage when they merge, and a rocket when the work
ships. What is optional:

- **A testing phase**: a `staging` branch releases go through.
- **How it ships**: a production branch (release pull requests), release tags (`v1.2`), or a workflow that
  deploys on every push. None of them: it doesn't ship, and merged crates wait in storage.
- **A GitHub project board** and issues (Settings › GitHub), to lay the yard out from its columns.
- **Neighbours**: sharing on the local network, per repository (Settings › General and Repositories).

Each new repository is set up from what it has: the trunk is GitHub's default branch, the testing phase is on
when a `staging` branch exists, and how it ships is read from its branches, tags and workflows. It is shown on
the station and not shared. A quiet card in the top corner says what was found; "Looks right" keeps it,
"Change…" opens its page in Settings, and ignoring it keeps it too. When the yard is empty the station says
why, and Settings › General has the same setup check.

`./release.sh <version>` builds, signs, notarises and publishes a release with a Sparkle appcast; its header
says the one-time setup.

## Controls

| Key or gesture | Does |
|---|---|
| pinch, or ⌥-scroll | zoom, around the cursor |
| two-finger rotate | spin round the point under the cursor |
| two-finger slide | pan |
| drag up or down | tilt |
| W A S D | pan |
| E / Q | zoom in / out |
| hold space | play the picture four times as fast |
| R | reset the view |
| 0, 1–4 | the whole fleet; focus a station |
| L | the Station Log |
| N | the Neighbours panel |
| G | ask GitHub again |
| F | walk the station, down in the hallway at a minion's eye height; F or Esc goes back up |
| Esc | let go of a minion, step out of the walk, close the panels |
| hover a minion | it stops and its bubble says what it is doing; a lounger's bubble lets you pick its next thing |
| click a minion | follow it, its order written along the bottom; Esc, a pan or a click elsewhere lets go |
| F while following | ride along behind it |
| click a crate or a rocket | open its pull request, issue or release |
| double-click a minion | ask GitHub again about its repository |
| double-click an office, crate or rocket | open it |
| double-click the floor | walk the station from there |
| right-click an office | kick it off the station (not your own checkout) |
| ⌘M | music, off by default |
| ⌘F | float on top |

Walking: W A S D to move, drag to look, Q / E to turn, shift to run, space for the jetpack. Click a
minion to ride along behind it; W A S D steps off, Esc goes back up.

The menus repeat these and add Settings (⌘,), Refresh GitHub (⌘⇧R), Reset Colours, Reset Office Layout,
and a Develop menu: the Graphics Gallery (⌘⇧G), the Playbook (⌘⇧P), the body and facts reports (⌘⇧B, ⌘⇧L),
Restack the Yard, Skip to the Facts, and Rehearse Launch.

## Themes

Settings › General › Look picks how the station is drawn.

- **Classic**: the flat-shaded homage, adrift in space.
- **Kenney Space Center**: the same station on the ground, laid out like the Cape, its pad out on a
  causeway, built from Kenney's [Space Kit](https://kenney.nl/assets/space-kit),
  [Modular Space Kit](https://kenney.nl/assets/modular-space-kit) and
  [Nature Kit](https://kenney.nl/assets/nature-kit) (CC0).
- **Kenney Kingdom**: a walled castle on the sea, with Kenney's Castle, Fantasy Town, Nature, Pirate,
  Survival and Hexagon kits and Cube Pets (CC0). Its words change with it: caravans, a granary, a
  market, a harbour.

The models used live in `Resources/Kenney`.

A production deploy flies: an onboard camera rides the repository's rocket from the pad to its planet and
lands it at the repository's colony, timed on how long its deploys usually take. The planet surfaces are
[Solar System Scope](https://www.solarsystemscope.com/textures/)'s textures (CC BY 4.0), tinted in each
repository's colour, in `Resources/Planets`.

## The rest

- [STATION.md](STATION.md): what everything on the station is and may do.
- [WIRING.md](WIRING.md): where the facts come from, how often, and the stage rules.
- [ARCHITECTURE.md](ARCHITECTURE.md): how the code is cut.
- [TESTING.md](TESTING.md): the gate, the suites, and the tools for looking and debugging.
- [THEMES.md](THEMES.md): how to design a theme and judge it.
- [ROADMAP.md](ROADMAP.md): what is still open.
- [floor/README.md](floor/README.md): how the floor plans are drawn and baked.

Pull requests welcome: fork, branch, `./build.sh fast run` to try it, `./test.sh`, open a PR. Feature
requests and bugs go in [issues](https://github.com/MadsBuus/rumkapsel/issues).

## A homage

This exists because of [rymdkapsel](https://rymdkapsel.com), Martin Jonasson's (Grapefrukt) small,
perfect space station game. The tetromino rooms, the brown corridors, the tiny white minions, the
monolith, the drone: all of that is his idea, and we borrowed the look with love and no permission. If you
have not played it, go play it. Rumkapsel is a desk toy, not a game, and it is not affiliated with
Grapefrukt in any way.
