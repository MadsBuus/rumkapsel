# rymdkapsel

A tiny macOS desk toy in the spirit of [rymdkapsel](https://rymdkapsel.com): your Claude Code sessions
are minions on a space station. Repos are colours, Conductor worktrees are offices, the monolith is where
web research and subagents happen, commits pile up as boxes, and pull requests colour them.

Not affiliated with Grapefrukt. Just a love letter.

## Build

```bash
./build.sh run
```

Requires Xcode 26 / Swift 6.3 and the `gh` CLI for pull request lookups.

## Controls

| Key / gesture | Action |
|---|---|
| pinch | zoom |
| two-finger rotate | spin around the vertical axis |
| two-finger up/down | tilt |
| one-finger drag | pan |
| 1 / 2 / 3 | focus work / private / both |
| R | reset view |
| M | music (off by default) |
| F | float on top |
| click a box | open the pull request or issue |

## Flags

`--demo` runs with fake sessions. `--snapshot out.png --delay 6` renders a frame and exits.
