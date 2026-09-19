# Wiring, as it is

How the code decided each stage before the record, and what changed. The tables below are the wiring as
it was at `7da3cfe`, kept as the map of where each source speaks; the last section says what decides
now. The target is [STAGES.md](STAGES.md). File references are under `Sources/Rumkapsel/`.

## Sources

| Source | Reads | Cadence | Code |
|---|---|---|---|
| Sessions | `~/.claude/projects` transcripts | on file change, and every 5 s | `Scanner.swift` |
| Conductor | `~/conductor/workspaces/<repo>` with a checkout at `~/dev/<repo>` | first scan only | `World.swift:420` |
| Git | commits ahead of trunk, dirty files, merge history, tags | 1 min (commits), with releases | `GitHub.swift:1209`, `:995` |
| GitHub pull requests | own branch's PR, team's open PRs, release PRs, activity feed | feed 1 min as a doorbell, PR asked at once when rung, all every 5 min | `GitHub.swift` |
| Deploy workflows | `.github/workflows` on the trunk, by keyword | with the pipeline, hourly | `GitHub.swift:699` |
| Board | one GitHub project, one single-select field | changes every 20 s, whole board every 5 min | `GitHub.swift:494`, `:552` |
| Neighbours | offices, pulls, boxes, board and GitHub knowledge | every 3 s | `Peers.swift`, `World.swift:887` |
| `.github/rumkapsel.json` | trunk, staging, production, release branches, board columns, ship | hourly, with the pipeline | `Pipelines.swift:12` |

## Stage by stage

### Inbound: an office appears

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Session in a checkout | not held while the station settles (10 scans) | `.officeOpened(.session)`, by shuttle or appearing | `World.swift:327`, `:337` |
| PR opens on the session's branch | | office re-keyed to `task:repo#PR` | `World.swift:473` |
| Teammate's open PR | not a bot, not a trunk branch, not kicked | `.officeOpened(.github)` | `World.swift:754` |
| Board issue in development | a sign of work: linked PR, `gh-N/` branch in the feed, a peer claim or a local worktree | `.officeOpened(.board)`, `.issueStarted` | `World.swift:671`, `:774` |
| Neighbour's office | adopted where the neighbour put it | shuttle if under 3 min old, else fades in | `World.swift:923` |

The office key is `task:repo#N` for a `gh-N/...` branch, `task:repo/branch` otherwise, and nothing for
`main`, `master`, `develop` or `HEAD` (`Station.swift:118`).

### Working: minions, cones, cubes

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| New prompt in a transcript | | `.prompt`, a cone | `World.swift:349`, `Scene.swift:1042` |
| Commits ahead of trunk | trunk is the first of `origin/<trunk>`, `develop`, `main`, `master` that exists | cubes; dirty files are ghost cubes | `GitHub.swift:1220` |
| Teammate pushes | feed | boxes = 1 + pushes | `World.swift:771` |
| Neighbour's boxes | | as the neighbour counts them | `World.swift:912` |

There is no Working state: it is an office with no pull request.

### Ready: a crate in the office

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Own branch's PR is OPEN | | `.pullRequestOpened`, the pack job | `World.swift:447`, `Scene.swift:1065` |
| Teammate's PR in the open list | | office drawn packaged | `SceneMarkers.swift:158` |
| Checks | the PR's check rollup | the plate light | `GitHub.swift:1273`, `SceneMarkers.swift:206` |
| Review | `reviewDecision`, draft | the crate's colour | `SceneMarkers.swift:176` |

Ready is not kept anywhere: it is worked out from the GitHub caches on every redraw.

### Stored: the crate goes to storage

Two paths, each moving crates on its own.

**The haul**, when an office's pull request is known to have merged:

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Own PR state MERGED | | `.officeMerged`, the haul to storage, the office folds | `World.swift:382`, `:1306` |
| Teammate PR leaves the open list | feed says merge or close, else the PR asked by number, else by branch; **with no checkout of the repository, assumed merged** | the haul, or the office drops if closed | `World.swift:721`, `:734` |
| Bot PR merges | feed, else the PR by number | `.deconCleared`, carried from decon | `World.swift:857` |

**The counts**, `Cargo` from the source, reconciled into the ledger (`World.swift:1087`):

| Source | Storage is | Code |
|---|---|---|
| Board | issues in the storage column | `GitHub.swift:302` |
| Git, staging and production exist | PR numbers in `staging..trunk` commit subjects | `GitHub.swift:1020` |
| Git, ships on tags | PR numbers in `<newest tag>..trunk` | `GitHub.swift:1033` |
| Git, no staging | PR numbers in `production..trunk` | `GitHub.swift:1043` |
| Git, none of those | merged PRs since the last release, the last 80 and 30 days at most | `GitHub.swift:1053` |

A crate the count has and the station does not is snapped into place, with no haul.

**Board or git**, per repository (`GitHub.swift:288`): the repository's own file decides if it says; else
the repository goes to the board the first time one of its issues is in the storage, QA or cleared
column, and **stays there for good**, saved in `board.json`. A repository has git counts at all only with
a release merged into staging or production, or when it ships on tags (`GitHub.swift:1002`).

### QA: on the staging area

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Count says deck (board QA column, or git `production..staging`) | repository has staging; no pallet out or queued | carry to the deck | `World.swift:1099`, `Jobs.swift:353` |
| Staging release PR opens | | a pallet is ordered | `World.swift:604`, `Pallet.swift:112` |
| Staging release PR merges | | the pallet goes; it unloads onto the deck | `Pallet.swift:166`, `:623` |
| Staging release PR closes | | the pallet unloads back to storage | `Pallet.swift` |
| Staging release merges | no board and no pallet | everything in storage carried to the deck | `Scene.swift:1036` |
| Board item moves to QA | | a log line only; the count moves it | `Scene.swift:1051` |

### Cleared: tested

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Board cleared column | | the crate's `cleared` flag | `GitHub.swift:304`, `Ledger.swift:191` |
| Board item moves to cleared | | carried to the tested row | `Scene.swift:1054`, `Jobs.swift:423` |
| Open production release has no `untested` label | no board | the whole release counts as tested: the rocket loads | `GitHub.swift:52`, `World.swift:594` |
| Bot crate | always | cleared from the start | `Ledger.swift:191` |

Without a board there is no Cleared per crate.

### Shipped: the rocket

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Open production release PR | or any open release with no staging | a rocket stands by; loads if not `untested` | `World.swift:533`, `:585` |
| Production release PR merges | | `.releaseMerged`, the launch | `GitHub.swift:1070`, `World.swift:565` |
| A new tag | ships on tags; not the first answer | the launch, with no rocket standing first | `GitHub.swift:1075` |
| A crate lands in storage | ships on merge (a deploy keyword in a workflow on push to trunk) | a launch per merge; these repositories skip the counts | `Ships.swift:311`, `World.swift:1091` |
| Board shipped column | | the item leaves the counts and is snapped away; a log line | `World.swift:1105`, `Scene.swift:1057` |

Shipped work is deleted from the ledger (`Ledger.swift:215`, `World.swift:520`). Offices fold at Stored,
never at Shipped.

### Outside work

A bot's pull request waits in decon (`World.swift:843`). Bots are recognised twice, differently: the open
list takes `is_bot`, `dependabot` or `[bot]` (`GitHub.swift:241`); the feed takes those and also `-bot`
and `webhook` (`GitHub.swift:809`). Nothing else counts as outside: a fork's pull request is anyone's.

## Baked-in settings

| Setting | Value | Code |
|---|---|---|
| Trunk names | `develop`, `main`, `master` | `Pipelines.swift:64`, `GitHub.swift:1220` |
| Long-lived branches | those plus `staging`, `production` | `Pipelines.swift:61`, `World.swift:26` |
| Branches that are not work | `main`, `master`, `develop`, `HEAD` | `Station.swift:123` |
| Release branch patterns | `release*`, `hotfix*` | `Pipelines.swift:51` |
| Issue branch pattern | `gh-<N>/...` | `Station.swift:119`, `World.swift:448`, `:682`, `:792` |
| Default branch names | `develop`, `staging`, `production` | `Config.swift:47` |
| Board field | `Status` | `Config.swift:61` |
| Board columns | In Development, Ready for staging, QA, Ready to ship, Shipped | `Config.swift:64` |
| Untested release | any label containing "untested" | `GitHub.swift:52` |
| Deploy words | deploy, serverless, flyctl, vercel, railway, heroku, kubectl, helm upgrade, docker push, gcloud, cdk deploy | `GitHub.swift:703` |
| Bot names | `dependabot`, `[bot]`, and in the feed `-bot`, `webhook` | `GitHub.swift:241`, `:809` |
| PR numbers in commits | `(#N)` at the end of a subject, `Merge pull request #N` | `GitHub.swift:1010`, `:1014` |
| Stale open PR | 14 days without an update | `GitHub.swift:236` |
| Git history floor | 30 days, 80 merged PRs, 5 release PRs per base | `GitHub.swift:1003`, `:1053`, `:973` |
| Teammate activity | feed events under 30 min | `World.swift:22` |
| Neighbour's offices held | 24 h | `World.swift:20` |
| Closed office window | 10 min | `World.swift:1323` |
| Conductor checkout | `~/dev/<repo>` | `World.swift:425` |

## Decided more than once, then

1. **Merged**: own office, teammate, bot, and a crate snapped in by the counts.
2. **To QA**: the count's carry, the pallet, a staging merge with no board, the git staging diff.
3. **Cleared**: the ledger flag, the board move, the release label, the QA minion's own count (`Jobs.swift:437`). Never checked against each other.
4. **Shipped**: the pad row deleted, `forgetShipped`, the board's snap, `clearPad`.
5. **Which number a crate has**: the issue or the pull request, depending on the path that made it.
6. **An office's key**: from the branch, re-keyed to the pull request, a teammate's, a board issue's.
7. **Bots**: two rules. **Trunk names**: four lists.

## Decided once, now

Every source above still reads what it read; what it does with it is report to the record
(`WorkBook.report`), and the station acts on the record's transitions, drained once per pass into
station events (`World.stationEvents`). The rules are in `Stage`/`Record.hear`, under the repository's
`Workflow`.

| Stage | Was decided by | Decided now by |
|---|---|---|
| Inbound, Working | the office going up, a prompt | the same, reported |
| Ready | two emissions of `.pullRequestOpened` | the record's transition, drained; the pack job follows |
| Stored | four places | the record: an office hauls when it says stored, whoever said it |
| QA | four places | the record's transition, drained into the carry to the deck; the pallet remains the hand carry for a staging release |
| Cleared | four places, unchecked | the record: the ledger's flag reads it, the carry across the deck follows its transition |
| Shipped | four places | the record: a rocket waits wherever work waits, loads when it is cleared, launches on the transition |

Names (5, 6) go through `Work` and the register `WorkBook`, one record per piece of work with every
alias. Folded in since: the ledger hears the record rather than the counts (its rows keep the station's
side, where a crate stands); GitHub's pull→issue table serves the hover only; the crew-room table is down
to an office's state; one bot rule; one trunk list; the workflow is a repository's, detected and
editable. Still inline: the merge blocks' state detection, which reports to the record but has not moved
into an integration of its own.
