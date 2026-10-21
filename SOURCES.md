# Sources: the target

Where intake is going. WIRING.md says how it is today; this file goes once the work is done.

## Why

`GitHubResolver` is one class of 1,600 lines that reads pull requests, releases, deploys, the feed, the
board, git counts and pipelines, each with its own cache, timer and saved copy. `World` reaches into it
from a dozen places and turns what it finds into stages and facts there and then. Adding a source
(Sentry, AWS, Jira) means another dozen places. The stale-news bug was one source's saved copy leaking
through one of them.

## The rule

A **source** (`Intake` in code: `Source` already names who said a stage) reads, caches, saves and says. It owns its reads, its cadence (the detectors), its saved
copy and whether it has answered live. It says what it knows as **reports**, and only once it has
answered live: until then the saved facts stand.

**World decides.** `World.hear(reports)` is the one door: it puts a stage on a piece of work in the
work book, hands a fact to the rules, or keeps what offices are made of. No other part of the station
reads a source.

## Reports

Two kinds, both plain values:

- **What is so now**, said again whenever asked, so a repeat changes nothing:
  - this piece of work, by any of its names, is at this stage;
  - this repository's yard holds these crates, by the board or by git;
  - these release pull requests are open;
  - these bots' pull requests are open.
- **What just happened**, said once:
  - a release merged;
  - a deploy started or ended;
  - a pull request changed state;
  - a card moved.

A name is whatever the source knows a piece of work by: a crate number, an office key, a pull request, a
branch, a folder. The work book joins names as it does today.

## The sources

| Source | Reads | Says |
|---|---|---|
| Transcripts | the session files | sessions: where, on which branch, doing what |
| Git | the checkouts, FSEvents, `git log` counts, tags | commits and pushes; what is on staging and production |
| Pull requests | the open list, single pulls, the feed | stages from pull requests; state changes; bots |
| Releases | release and hotfix pull requests, tags | open releases; releases merged |
| Deploys | Actions runs | deploys started and ended, and their usual length |
| Board | the project's items and moves | stages from columns; card moves; issue ↔ pull request links |
| Neighbours | the LAN snapshots | their offices and minions |

How a repository ships (the pipeline) stays one shared reading, made from Git's and Releases' answers.

They share the plumbing: the HTTP client with ETags, the rate gate, the detectors and the follow-ups.

## What stays in World

- Offices: workspaces, crew offices, neighbours' offices and their ends.
- Decon screening, and the work book.
- Turning stages into rules events.

## Stages

Each stage is a green PR with nothing different on screen.

1. **The plumbing and the first source.** `Watch` takes the scheduler out of `GitHubResolver` (the timer,
   the detectors, `ask`, heat). `Intake`, `Report` and `World.hear` come in, and Deploys moves out as
   `DeploySource`, saying its starts and ends through the door. Done.
2. **The resolver split**, one source per PR: Board, Pull requests, Releases and Git, all done. Each takes its reads,
   cache, saved copy and detector out of `GitHubResolver` and says its reports, and the deciding that
   World does on them stays in World.
3. **Events, not passes.** Today any answer that changes anything runs one pass over every source,
   repository and room, diffs it into events, and rebuilds the markers or the floor; sessions are read
   on a 5 s timer; neighbours send whole snapshots. The target is the way networked games and video
   streams work: small, fast **deltas** (the "what just happened" reports, each with an identity so a
   repeat or a late one does nothing) that every station plays, and now and then a **keyframe** (the
   "what is so now" reports) that corrects whatever drifted. In order:
   1. Measure: how often the pass and the session read run and how long they take (`timing` lines in
      `station.log`, once a minute).
   2. Sessions on file events: the transcript folders watched, each session reported as it changes.
   3. The busiest GitHub events handled where they land, each taken out of the pass: pull request
      changes, checks and reviews, board moves, yard counts, checkouts. The pass shrinks to the keyframe.
   4. Neighbours relay reports: a keyframe when they join, deltas after.
4. **A registry.** Which sources a repository uses is declared (for example board or git counts), and a
   new source is one file plus one registration. Each source says what it needs to connect and how to
   check it is connected.
5. **Setup and connecting** (below), after mission control's room. Mission control's monitors (Sentry
   first) are the proof that a new source is one file.

Done when the station reacts to reports as they land, the pass has shrunk to the occasional keyframe, and a
new source is one file plus one registration.

## Connecting

A new user should get from install to a working station without a terminal.

**A Sources tab in Settings**, one row per registered source: a light, who it is connected as, and a
Connect or Fix button.

| Source | Needs | Connect |
|---|---|---|
| Sessions | nothing: the app is not sandboxed and reads `~/.claude/projects` | found; more folders can be added |
| Git | git | found |
| GitHub | a token that reads repositories, the organisation and projects | see below |
| Board | GitHub, with project read | pick the project and its columns |
| Sentry | an auth token, an organisation and projects | paste the token, pick from lists |
| AWS | the user's own AWS login (`~/.aws` profiles or `aws sso login`) | pick a profile and alarms; the app never holds AWS keys |

**GitHub**, first that answers:

1. The GitHub CLI, if it is signed in: nothing to do, as today.
2. **Sign in with GitHub**: the device flow of an OAuth app registered on Mads' own account (not
   Tattoodo's). The app shows a code and opens github.com/login/device. Only the client ID ships in the
   app, and the token is kept in the Keychain.
3. A pasted token, for GitHub Enterprise or fine-grained tokens.

For 2 and 3 to work without the CLI, the reads that still run `gh` (the open lists, single pull
requests, the owner, the board) move onto the HTTP client as their sources do.

**First run** is a checklist on the setup card: sessions found, GitHub connected, these repositories and
how each ships, a board (optional), monitors (optional). Each step is a button, and the station builds as
they are ticked.
