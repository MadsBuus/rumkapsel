# Wiring, as it is

Where each source speaks, and what the station does with what it says, stage by stage. The last section
says who decides. The target is [STAGES.md](STAGES.md). File references are under `Sources/Rumkapsel/`.

## Sources

| Source | Reads | Cadence | Code |
|---|---|---|---|
| Sessions | `~/.claude/projects` transcripts | on file change, and every 5 s | `Scanner.swift` |
| Conductor | `~/conductor/workspaces/<repo>` with a checkout at `~/dev/<repo>` | first scan only | `World.swift` |
| Git | commits ahead of trunk, dirty files, merge history, tags | 1 min (commits), with releases | `GitHub.swift` |
| GitHub pull requests | own branch's PR, team's open PRs, release PRs, activity feed | feed 1 min as a doorbell, PR asked at once when rung, all every 5 min | `GitHub.swift`, `Integrations/PullRequests.swift` |
| Deploy workflows | `.github/workflows` on the branch a deploy runs from, by keyword | hourly | `GitHub.swift`, `Integrations/Deployments.swift` |
| Board | one GitHub project, one single-select field | changes every 20 s, whole board every 5 min | `GitHub.swift` |
| Neighbours | offices, pulls, boxes, board and GitHub knowledge | as soon as something changes (looked at twice a second), at least every 3 s; GitHub knowledge every 30 s | `Peers.swift`, `World.swift`, `NeighboursPanel.swift` |
| `.github/rumkapsel.json` | trunk, staging, production, release branches, board columns, ship | hourly, with the pipeline | `Pipelines.swift`, `GitHub.swift` |

## Stage by stage

### Inbound: an office appears

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Session in a checkout | not held while the station settles (10 scans) | `.officeOpened(.session)`, by shuttle or appearing | `World.swift` |
| PR opens on the session's branch | | office re-keyed to `task:repo#PR` | `World.swift` |
| Teammate's open PR | not a bot, not a trunk branch, not kicked | `.officeOpened(.github)` | `World.swift` |
| Board issue in development | a sign of work: linked PR, `gh-N/` branch in the feed, a peer claim or a local worktree | `.officeOpened(.board)`, `.issueStarted` | `World.swift` |
| Neighbour's office | adopted where the neighbour put it | shuttle if under 3 min old, else fades in | `World.swift` |

The office key is `task:repo#N` for a `gh-N/...` branch, `task:repo#PR` once the branch has a pull request
(the open one, else the newest, so a merge does not rename the office), `task:repo/branch` otherwise, and
nothing for `main`, `master`, `develop` or `HEAD` (`Work.swift`). One checkout has one office: a merged office
left behind in a checkout whose session now lives in another office folds once its crate is hauled (`World.swift`).

### Working: minions, cones, cubes

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| New prompt in a transcript | | `.prompt`, a cone | `World.swift`, `Scene.swift` |
| Commits ahead of trunk | trunk is the first of `origin/<trunk>`, `develop`, `main`, `master` that exists | cubes; dirty files are ghost cubes | `GitHub.swift` |
| Teammate pushes | feed | boxes = 1 + pushes | `World.swift` |
| Neighbour's boxes | | as the neighbour counts them | `World.swift` |

There is no Working state: it is an office with no pull request.

### Ready: a crate in the office

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Own branch's PR is OPEN | | `.pullRequestOpened`, the pack job | `World.swift`, `Scene.swift` |
| Teammate's PR in the open list | | office drawn packaged | `SceneMarkers.swift` |
| Checks | the PR's check rollup | the plate light | `GitHub.swift`, `SceneMarkers.swift` |
| Review | `reviewDecision`, draft | the crate's colour | `SceneMarkers.swift` |

Ready is not kept anywhere: it is worked out from the GitHub caches on every redraw.

### Stored: the crate goes to storage

Two paths.

**The haul**, when an office's pull request is known to have merged:

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Own PR state MERGED | | `.officeMerged`, the haul to storage, the office folds | `World.swift`, `Jobs.swift` |
| Teammate PR leaves the open list | feed says merge or close, else the PR asked by number, else by branch; **with no checkout of the repository, assumed merged** | the haul, or the office drops if closed | `Integrations/PullRequests.swift`, `World.swift` |
| Bot PR merges | feed, else the PR by number | `.deconCleared`, carried from decon | `World.swift`, `Jobs.swift` |

**The counts**, `Cargo` from the source, reported to the record and reconciled into the ledger
(`Releases.swift`):

| Source | Storage is | Code |
|---|---|---|
| Board | issues in the storage column | `GitHub.swift` |
| Git, staging and production exist | PR numbers in `staging..trunk` commit subjects | `GitHub.swift` |
| Git, ships on tags | PR numbers in `<newest tag>..trunk` | `GitHub.swift` |
| Git, no staging | PR numbers in `production..trunk` | `GitHub.swift` |
| Git, none of those | merged PRs since the last release, the last 80 and 30 days at most | `GitHub.swift` |

A crate the count has and the station does not is placed where the count says, with no haul.

**Board or git**, per repository (`GitHub.swift`): the repository's own file decides if it says; else
the repository goes to the board the first time one of its issues is in the storage, QA or cleared
column, and **stays there for good**, saved in `board.json`. A repository has git counts at all only with
a release merged into staging or production, or when it ships on tags.

### QA: on the staging area

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Work reaches QA (board QA column, or git `production..staging`) | repository has staging; the crate stands in storage | one carry per crate to the staged rows | `World.swift`, `Yard.swift`, `Jobs.swift` |
| Staging release PR opens | | a staging batch is noted; a log line | `Releases.swift`, `Staging.swift` |
| Staging release PR merges | board or no board | every crate in storage carried to the staged rows | `Scene.swift`, `Jobs.swift` |
| Staging release PR closes | | the batch is forgotten; nothing moves | `Staging.swift` |
| Staging deploy runs | the batch merged | the rocket's tip is welded while it runs | `Staging.swift`, `Rockets.swift` |
| Board item moves to QA | | a log line | `Scene.swift` |

### Cleared: tested

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Work reaches Cleared (board cleared column) | | the crate's `cleared` flag | `Releases.swift`, `Ledger.swift` |
| Work reaches Cleared | | carried to the cleared rows; the releases are read again at once, so the rocket loads on the last card | `World.swift`, `Jobs.swift`, `Yard.swift` |
| Open production release has no `untested` label | no board, or no QA | the whole release counts as cleared: the rocket loads | `GitHub.swift`, `Releases.swift` |
| Open production release has no `untested` label | a board testing on the deck | work with no card counts as cleared; carded work waits for its card | `Releases.swift` |
| Bot crate | always | cleared from the start | `Ledger.swift` |

Without a board there is no Cleared per crate.

### Shipped: the rocket

| Trigger | Condition | Effect | Code |
|---|---|---|---|
| Open production release PR | or any open release with no staging | a rocket stands by and docks on its lift (9 s, Classic); loads once docked, if cleared | `Releases.swift` |
| Work waiting, no release open | the repository ships, and not at once | a rocket stands by; loads if cleared | `Releases.swift` |
| The rocket stands by | not cleared to load | whatever it took aboard goes back to its rows | `Releases.swift`, `Ledger.swift` |
| Production release PR merges | | `.releaseMerged`, the launch: the vortex pulls the crates aboard, the rocket climbs | `GitHub.swift`, `Releases.swift`, `Vortex.swift`, `Rockets.swift` |
| A new tag | ships on tags; not the first answer | the launch | `GitHub.swift` |
| A crate lands in storage | ships on merge (a deploy keyword in a workflow on push to trunk) | a launch per merge; these repositories skip the counts | `Rockets.swift`, `Releases.swift` |
| Board shipped column | | shipped on the record: the rocket launches; a log line | `Releases.swift`, `World.swift`, `Scene.swift` |
| Hotfix PR opens | a PR into production from anything but the trunk, staging or a release branch | an express rocket with a red tip stands on a pad slot of its own | `GitHub.swift`, `Releases.swift` |
| Hotfix PR merges | | its crate is hauled to storage, the vortex pulls it into the express rocket and that goes up; the release rocket keeps its cargo, and the hotfix's work ships as it climbs | `Releases.swift`, `Rockets.swift`, `Vortex.swift` |
| Production deploy starts | | the flight flies the rocket going up, waiting while a hotfix rocket still loads | `Mission.swift` |

Shipped work is deleted from the ledger (`Ledger.swift`, `Releases.swift`). Offices fold at Stored,
never at Shipped.

### Outside work

A bot's pull request waits in decon (`World.swift`). One rule recognises bots (`GitHub.swift`): the open
list's `is_bot`, or a login with `dependabot`, `[bot]`, a `-bot` ending or `webhook`. Nothing else counts as
outside: a fork's pull request is anyone's.

## Baked-in settings

| Setting | Value | Code |
|---|---|---|
| Trunk names | `develop`, `main`, `master` | `Pipelines.swift`, `GitHub.swift` |
| Long-lived branches | those plus `staging`, `production` | `Pipelines.swift` |
| Branches that are not work | `main`, `master`, `develop`, `HEAD` | `Work.swift` |
| Release branch patterns | `release*`, `hotfix*` | `Pipelines.swift` |
| Issue branch pattern | `gh-<N>/...` | `Work.swift` |
| Default branch names | `develop`, `staging`, `production` | `Config.swift` |
| Board field | `Status` | `Config.swift` |
| Board columns | In Development, Ready for staging, QA, Ready to ship, Shipped | `Config.swift` |
| Untested release | any label containing "untested" | `GitHub.swift` |
| Deploy words | environment:, serverless deploy, sls deploy, flyctl, vercel, railway, heroku, kubectl, helm upgrade, docker push, gcloud, cdk deploy, netlify deploy, wrangler deploy, firebase deploy, fly deploy | `Integrations/Deployments.swift` |
| Bot names | `dependabot`, `[bot]`, `-bot`, `webhook` | `GitHub.swift` |
| PR numbers in commits | `(#N)` at the end of a subject, `Merge pull request #N` | `GitHub.swift` |
| Stale open PR | 14 days without an update | `GitHub.swift` |
| Git history floor | 30 days, 80 merged PRs, 5 release PRs per base | `GitHub.swift` |
| Teammate activity | feed events under 30 min | `World.swift` |
| Neighbour's offices held | 24 h | `World.swift` |
| Closed office window | 10 min | `World.swift` |
| Conductor checkout | `~/dev/<repo>` | `World.swift` |

## Who decides

Every source above reads what it reads; what it does with it is report to the record
(`WorkBook.report`), and the station acts on the record's transitions, drained once per pass into
station events (`World.stationEvents`). The rules are in `Stage`/`Record.hear`, under the repository's
`Workflow`.

| Stage | Decided by |
|---|---|
| Inbound, Working | the office going up, a prompt, reported |
| Ready | the record's transition, drained; the pack job follows |
| Stored | the record: an office hauls when it says stored, whoever said it |
| QA | the record's transition, drained into one carry per crate to the staged rows; a staging release merging carries the whole of storage |
| Cleared | the record: the ledger's flag reads it, the carry across the staging area follows its transition |
| Shipped | the record: a rocket waits wherever work waits, loads when it is cleared, launches on the transition |

Names go through `Work` and the register `WorkBook`, one record per piece of work with every alias.
The ledger hears the record rather than the counts (its rows keep the station's side, where a crate
stands); GitHub's pull→issue table serves the hover only; the crew-room table is down to an office's
state; one bot rule; the workflow is a repository's, detected and editable; and the
reading of a pull request's state, your own office's by branch, a teammate's from the feed, then by
number, then by branch, is `PullRequests` (`Integrations/`), which reads and reports and decides nothing.
A piece of work whose first word is already stored, a merged office found at launch, is placed and not
carried: history, not news.
