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

## Controls

| Key / gesture | Action |
|---|---|
| pinch | zoom, around the cursor |
| two-finger rotate | spin around the point under the cursor |
| two-finger slide | pan |
| one-finger drag up/down | tilt |
| W / A / S / D | pan |
| E / Q | zoom in / out |
| 1 / 2 / 3 / 4 | focus a station (work, crew, private, then peers) |
| 0 | focus the whole fleet |
| R | reset view |
| M | music (off by default) |
| F | float on top |
| click a box | open the pull request or issue |

## Flags

`--demo` runs with fake sessions. `--snapshot out.png --delay 6` renders a frame and exits.

## A homage

This exists because of [rymdkapsel](https://rymdkapsel.com), Martin Jonasson's (Grapefrukt) small, perfect space station game.
The tetromino rooms, the brown corridors, the tiny white minions, the monolith, the drone: all of that is his idea, and we borrowed the look
with love and no permission. If you have not played it, go play it. It is on every platform and it is a few dollars well spent.
Rumkapsel is a desk toy, not a game, and it is not affiliated with Grapefrukt in any way.
