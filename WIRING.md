# Wiring

Where each source speaks, what it says, and what the station does with it: sources → events → rules →
playback. This file owns the sources, their cadences and the stage rules. What things are and may do is
[STATION.md](STATION.md); the code seams are [ARCHITECTURE.md](ARCHITECTURE.md). File references are
under `Sources/Rumkapsel/`.

## The flow

1. **Sources** read and cache. None of them knows about the picture (`Integrations/`).
2. **Reports.** A source says "this work reached this stage, by me, at this time" to the work's record
   (`WorkBook.report`), or tells `World` something that is not a stage (an office opened, a release
   open, a bot's pull request). A record turns what it hears into a transition by the rules under
   **Priorities**.
3. **Events.** Transitions become `.work` events; the rest become `.office`, `.release`, `.hotfixes`,
   `.launched`, `.staging`, `.decon`, `.sweep` and `.policy` events (`Rules/Rules.swift`).
4. **Rules.** `World.learn` hands each event to `Rules.apply` at once: new facts and effects (a log line,
   "this is history", a rename, the decon hatch). The facts are what the HUD, the hover and the log read.
5. **Playback** compares what is shown with the facts and plays the difference (`Playback/`).

A source's first answer is quiet: whatever it holds already existed, so it is placed without a word and
shown at once. Only changes after it are news.

## Sources and cadences

| Source | Reads | Cadence | Code |
|---|---|---|---|
| Sessions | `~/.claude/projects` transcripts | FSEvents on that folder, and every 5 s | `Integrations/Scanner.swift`, `Integrations/Watcher.swift` |
| Discovery | Conductor's workspaces (`~/conductor/workspaces/<repo>/*`, each joined to its repository, else `~/dev/<repo>`), and repositories watched in Settings | first scan | `Integrations/Discovery.swift`, `Integrations/World.swift` |
| Git, per checkout | commits ahead of the trunk, dirty files, the branch checked out | at once on a change in the repository's `.git` (FSEvents on its refs, `HEAD` and worktrees; objects excluded), else 60 s | `GitSource` (`Integrations/Git.swift`), `Integrations/GitWatch.swift` |
| Git, per repository | merges and tags for the counts; the pipeline; deploy workflows | with the releases; pipeline and workflows re-read hourly | `Integrations/GitHub.swift`, `Integrations/Pipelines.swift` |
| Pull requests | your branch's pull request, by branch or number; the team's open list; release and hotfix pull requests | the base interval (Settings › GitHub, 5 min by default) | `PullSource` (`Integrations/PullRequests.swift`); releases: `ReleaseSource` (`Integrations/Releases.swift`), the way to production in `GitHubResolver.readPipeline`, the git counts in `GitSource.count` |
| Pull request detector | the 20 most recently updated pull requests, conditional (ETag) | 5 s focused, 10 s active, 60 s idle | `PullSource.detectPulls` |
| Activity feed | each repository's events, conditional (ETag), team repositories only | 60 s (GitHub's `X-Poll-Interval`), 3 min idle | `PullSource.detectFeed` |
| Deploys | Actions runs on push to the staging and production branches, conditional (ETag) | 30 s focused, 1 min active, 2 min idle; 5 s while hot | `DeploySource`, `Integrations/Deployments.swift` |
| Board | one GitHub project, one single-select field | the items updated since yesterday, conditional (REST, ETag): 10 s focused, 20 s active, 60 s idle, 5 s while hot; the whole board at the base interval whatever the deltas, a fresher item kept | `BoardSource` (`Integrations/ProjectBoard.swift`) |
| Neighbours | offices, minions, colours, GitHub knowledge | looked at twice a second and sent on a change, at least every 3 s; GitHub knowledge every 30 s | `Integrations/Peers.swift`, `Scene/Scene.swift` (`makeSnapshot`) |

Every scan asks the base-interval sources; each answers from its cache until its interval is up. A failed
call keeps the previous answer.

What was saved on disk last time (`board.json`, the open pull requests and the feed in
`rumkapsel.github.json`) is history: until its source has answered live, or a neighbour has, it moves no
stage, opens no office and counts no crate. The saved facts stand until then, and the board is asked for
at once on start.

**Detectors.** Cheap conditional reads (`Integrations/Detectors.swift`) that say *something moved*; the
one scheduler ticks them every second (`Watch`), each first ask jittered. A 304 costs
nothing against the rate limit and is not parsed. Requests go out one at a time. The pace is the app's:
**focused** when it is in front, **active** while a session worked in the last 10 minutes, else **idle**.
A detector never polls faster than GitHub's `X-Poll-Interval`; one that gets no answer (403, 404, the
network) backs off from 10 s, doubling to 5 min, and starts over on the next answer. A repository's owner
is asked once before its detectors start. A detector never moves work by itself: what it hears makes the
thorough read happen at once, and once more 15 s later (one follow-up per repository, carrying every
change since). The open list and the releases are read at most every 15 s per repository; the rest waits
for the follow-up.

**The rate gate** (`RateGate`): out of budget (`remaining` 0) or `Retry-After`, everything waits until
GitHub says, plus a few seconds' jitter; a secondary limit (429, or 403 "rate limit") waits a minute,
doubling while it repeats; under 200 left, the detectors run four times slower, under 50 eight times.
GraphQL's budget is read every 5 min from `rate_limit`; under 200, the `gh` reads wait for its reset.

| Hears | Reads at once |
|---|---|
| a pull request's `updated_at` moves (pushed, reviewed, labelled, commented) | that pull request by number and by branch, where the station follows it; a followed branch's checks every 30 s for 3 min |
| … opened, closed or reopened | the open list too |
| … merged, or a pull request into staging or production | the releases and the counts; the deploys hot for 5 min, the board hot for 2 min |
| a full page of pull requests all new since the last look | the open list, the releases and every pull request the station follows |
| a release, or a push to staging or production, in the feed (new by event id) | the releases; the deploys hot for 5 min |
| a deploy runs | the deploys hot while it runs |
| a board answer with a full page (100 items since yesterday) | the whole board |
| the remote refs in a `.git` move (a push, a fetch) | that repository's detectors, rung, pulls and deploys hot for 30 s; the checkouts' commits; their branches' checks every 30 s for 3 min |
| a commit in a `.git` | that repository's checkouts' commits and branch |
| a checkout in one worktree | that worktree's commits and branch |
| a tag in a `.git`, for a repository that ships on tags | the releases |
| our own `git fetch` (its echo within 2 s) | nothing |
| `gh pr create`, `gh pr merge` or `git push` in a transcript, Refresh GitHub, a poke | the detectors, rung, pulls and deploys hot for 30 s; the board hot for 2 min |
| your pull request has checks pending or an approval | that pull request, every 30 s for 3 min |

The deploys of a repository off the team (no feed) are asked at their own pace; a teammate's direct push
to its staging or production is seen within that, a merge at once through the pull requests. Without a
token, or before the owner is known, the deploys are read with `gh run list` at the base interval.

## Stages

What a piece of work goes through. The station reacts to stages; where a stage comes from is the
business of the sources and nothing else. Work moves forward, and back only as **Priorities** says.

| Stage | On the station | Optional |
|---|---|---|
| **Inbound** | a shuttle brings the office | |
| **Working** | a minion at work, cones, cubes piling up | |
| **Ready** | a crate packed in the office | |
| **Stored** | the crate in storage | |
| **QA** | the crate on the testing rows | yes: no staging, no QA |
| **Cleared** | the crate on the cleared rows, a sticker on its lid | yes: nothing to clear it, no Cleared |
| **Shipped** | the crate aboard a rocket that has launched; gone | |

A repository without QA goes from Stored to Shipped. One without Cleared never waits for it: the rocket
does not hold for a sticker nobody can give. Where a crate stands is `Rules.place(stage, …)`.

## Priorities

Several sources can say the same thing. `Record.hear` (`State/Stages.swift`) takes them by two rules:

- **Forward: the furthest wins.** Any source the repository's workflow lists may move work on. Whichever
  says it first moves it; the others catch up and change nothing.
- **Back: only the first in line.** Work goes back a stage only when the first source in line for its
  current stage, having said that stage, now says an earlier one: a card moved from QA back to
  development. A source that simply has not caught up says nothing.

First in line (`Workflow.inLine`): for Inbound a session, then pull requests, the board, a neighbour;
for Working a session, then a neighbour; for Ready pull requests. From Stored on, the repository's
workflow says.

## The workflow is the repository's

Each repository answers one question per stage (`State/Workflow.swift`). The answers are detected from
its pipeline and whether a board is followed (`Workflow.detected`), shown and editable per repository in
Settings › Repositories:

| Question | Answer: sources, first in line first | Off |
|---|---|---|
| When is work **stored**? | board · pull requests · git | |
| Does it go through **QA**? | board · deployments · pull requests | **no**: stored goes straight to the rocket |
| When is it **cleared**? | board · deployments · pull requests | **always**: the rocket never waits |
| When has it **shipped**? | board · deployments · pull requests · git | |

"Pull requests" covers releases: a staging release, a production release without the `untested` label,
a merge. Deployments are listed but report nothing ([ROADMAP.md](ROADMAP.md)). Outside work is a bot's
pull request, always (see **Outside work**).

Detected: no staging means no QA; a repository that ships on merge or on tags has no Cleared; without a
board, the board is left out of every answer.

## Repositories: where they come from

One repository per git repository, named after its main checkout's folder; a worktree joins its
repository (its `.git` file points into the main checkout's `.git/worktrees/`), never a new one.

- **Sessions**: any folder a Claude session runs in, wherever it is, that is inside a git checkout
  (`Integrations/Scanner.swift`).
- **Conductor**: each repository with workspaces under `~/conductor/workspaces/<repo>/`, joined to the
  repository its workspaces belong to, else `~/dev/<repo>` (`Discovery.conductor`).
- **Watched**: a folder picked in Settings › Repositories › Watch a repository…, any folder inside a
  checkout, saved as the repository's `path` (`Discovery.root(of:)`).
- **Worktrees**: `git worktree list` says how many more checkouts a repository has (Settings).

A repository is **new** when it is not in `seen-repos.json` in the support folder and its config has no
entry. The first launch of a build that has the file fills it with every repository there is, so an
upgrade shows nothing; every repository registered after that goes in at once, so one removed and found
again is not new. A new one gets the detected answers at once and a card on the station saying them
(`App/SetupCard.swift`, words in `Integrations/Setup.swift`): "New repository: web", "Ships from production
through staging · not shared". Several at once share one card, four lines and then "and N more". "Looks
right" and "Change…" (which opens its page in Settings) write `answered` into its config entry; a card left
alone stays until answered and does not come back after a restart. Answering never resets the station.

**Settings and the repository disagree**: once a repository's way to production has been read
successfully, every answer set by hand (trunk, how it ships, the release branch, the testing phase) that
differs from what was read, or names a branch GitHub does not have, is a line on the same card
(`Setup.disagreements`): "tattoodo-web: your settings say it merges into develop, but the repository
merges into main." "Use the repository's" clears the answers set by hand; "Keep mine" saves those lines
as `kept` in the repository's entry, and the same disagreement is never asked again. A failed read never
asks. New repositories go first.

**The setup check** (`Setup.problems`), after the first scan: on the empty yard (the middle of the window
when there is no station yet) in station words, and in Settings › General with the command to run. No
repositories yet; every repository hidden; the GitHub CLI not on the `PATH` the app uses, or not signed in
("The station can't reach GitHub yet: see Settings"); no repository on GitHub ("notes isn't on GitHub, so it
never ships"); a branch set by hand that GitHub does not have (`git ls-remote`, read with the way to
production).

## The way to production

Read from what the repository has (`Integrations/Pipelines.swift`, `PipelineDetection.detect`), per
repository, and hourly again:

- **Trunk**: GitHub's default branch (`repos/{owner}/{repo}`, conditional), else `origin/HEAD`, unless it
  is `staging` or `production`; where most pull requests merge wins over both. While the history is
  unread, `develop`, `main` or `master` go before the default branch.
- **Testing phase**: on when a `staging` branch exists; with release history, the branch released onward
  into production.
- **How it ships**, the first that holds: a **production** branch (`production`, else `master` or `main`
  when not the trunk, or the branch releases end in) ships by release pull requests; a workflow that
  deploys on every push to the trunk **ships on merge**; a version tag (`v1.2`, `1.2.3`) from the last
  year **ships on tags**, pushed tags alone, no GitHub Release needed; else it **doesn't ship**: merged
  crates wait in storage and no rocket stands by. A `master` or `main` guessed as production by its name
  alone, with no release into it, gives way to a deploy on push or to tags.
- **A read that fails** (the merged pull requests, or `.github/rumkapsel.json` other than a 404) keeps
  the way already known; with none known, nothing is stored and the next scan asks again. A way known
  from before the repository gained or lost its GitHub remote is not kept.
- **No GitHub remote**: local work only, nothing asked of GitHub.

A `.github/rumkapsel.json` on the default branch says it for everyone and wins. Settings › Repositories
answers each question by hand (trunk, how it ships and its release branch, the testing phase and its
branch); an answer left alone stays detected. Until a repository's way is read, its facts keep what they
had (`.policy` waits). Releases come from the trunk, from staging, or from a release or hotfix branch.

- **Ships on merge**: each merged crate goes straight up in a rocket of its own.
- **Ships on tags**: what the trunk has that the newest tag (by date, and a version) has not waits in
  storage; no rocket stands by, and a new tag launches one.

## Triggers, stage by stage

### Inbound: an office

| Trigger | Condition | Event | Code |
|---|---|---|---|
| A session in a checkout | held while the station settles at start, up to 10 scans | `.office(.opened)`: simply there in the first scans, else by shuttle; Inbound by session | `World.applyScan` |
| A pull request opens on the session's branch | | `.office(.renamed)` to `task:repo#PR` | `World.applyScan` |
| A teammate's open pull request | not a bot, not a long-lived branch, not kicked; one new office per pass | `.office(.opened)` by shuttle once the repository has answered; Ready by pull requests | `World.swift` |
| A board issue in development | assigned to a teammate, open, with a sign of work: a linked pull request, a `gh-N/` branch in the feed, a neighbour's office, a local worktree | `.office(.opened)`; Inbound by board | `World.swift` |
| A neighbour's office | adopted where the neighbour put it | `.office(.opened)`: by shuttle if under 3 min old, else fades in; Inbound by neighbour | `World.applyPeer` |

The office key is `task:repo#N` for a `gh-N/...` branch, `task:repo#PR` once the branch has a pull
request (the open one, else the newest, so a merge does not rename it), `task:repo/branch` otherwise, and
nothing for `main`, `master`, `develop` or `HEAD` (`State/Work.swift`). One checkout has one office.

An office ends (`.office(.gone)`) when its checkout is gone or on another branch, when nobody claims it
for a day, when it is kicked, or by `Rules.officeEnds`: not yours and not a neighbour's, and merged, or
closed unmerged ten minutes ago.

### Working

| Trigger | Effect | Code |
|---|---|---|
| A new prompt in a transcript | a cone; Working by session | `World.applyScan` |
| Commits ahead of the trunk | cubes, at most 16; dirty files are ghost cubes | `World.cubes` |
| A teammate pushes | boxes: one plus the pushes | `World.swift` |
| A neighbour's boxes | as the neighbour counts them | `World.applyPeer` |

### An issue and its pull requests

A pull request **closes** an issue when GitHub links it (`closingIssuesReferences`) or its description says
so in GitHub's closing words (close, fix, resolve and their forms, then `#N`), which covers pull requests
into a branch other than the default, where GitHub links nothing. One that is linked to an issue by its
branch and does not close it is a **slice** (`WorkBook.note(closes:)`, `Record.epic`): a record and a crate
of its own, working in the issue's office. A record kept from before that still holds a slice is split
once its pull request has been read (`World.checkSlices`); a shipped one, holding a pull request not read
yet, once its issue is read open, its slices then born shipped; a closed answer is not asked again that
run. The issue then goes back to what its other sources say, with no crate while it holds no pull request
of its own (`WorkBook.crateless`, used by `FactFeed.learn` and `World.status`). An issue is an epic while it
is open, read from its board item (live, else the saved board), else `gh issue view` at the base interval
(`World.issueOpen`), and one of its slices has merged (`WorkBook.hasMergedSlice`); the office's fact
carries it (`OfficeFact.epic`) and `Rules.officeEnds` ends it when the issue closes. Your own epic in
development on the board is a board office with no crew member when no workspace holds it; a workspace
that goes hands it over instead of dropping it (`World.ownEpicOnBoard`).

### Ready

| Trigger | Event | Code |
|---|---|---|
| Your branch's pull request is open | Ready by pull requests → the crate in its office | `World.applyScan` |
| A teammate's pull request is in the open list | the same | `World.swift` |
| Checks | the plate light, read when drawn | `Scene/SceneMarkers.swift` |

### Stored

| Trigger | Event | Code |
|---|---|---|
| Your pull request merged | Stored by pull requests → the crate in storage | `World.applyScan` |
| A teammate's pull request leaves the open list | Stored or closed: the feed says, else the pull request asked by number, else by branch; with no checkout of the repository it is taken as merged | `Integrations/PullRequests.swift` |
| A pull request closed unmerged | the work keeps its stage, closed → red, gone after 10 min | `World.learnClosed` |
| The counts | per repository, `Cargo`: Stored, QA and Cleared by board or git, see below | `World.reconcile` |

The counts, by source:

| Source | Storage is | QA is |
|---|---|---|
| Board | issues in the storage column | the QA column; the cleared column is Cleared |
| Git, staging and production exist | pull request numbers in `staging..trunk` commit subjects | `production..staging` |
| Git, ships on tags | `<newest tag>..trunk` | |
| Git, no staging | `production..trunk` | |
| Git, none of those | pull requests merged into the trunk since the last release, the last 80 and 30 days at most | merged before the last staging release |

Board or git, per repository: the repository's file decides if it says; else a repository goes to the
board the first time one of its issues stands in the storage, QA or cleared column, and stays there,
saved in `board.json`. A crate the counts have that the station has not is placed where the counts say.
The first exact count after launch takes away row crates it does not list (`.sweep`), quietly.

### QA

| Trigger | Event | Code |
|---|---|---|
| The board's QA column, or git `production..staging` | QA → the crate to the testing rows | `World.reconcile` |
| With the board, a stored crate's pull request in git `production..staging` | QA by git, forward only: a card the board left behind still goes across, and the board saying storage again does not bring it back | `World.reconcile` |
| A staging release pull request opens, merges or closes | `.staging(.opened/.merged/.closed)`; after a merge the git counts find its crates in `production..staging` | `World.applyStaging` |
| A staging deploy starts or ends | `.staging(.deploy)`: the tip is welded while it runs | `World.swift` |

### Cleared

| Trigger | Condition | Event | Code |
|---|---|---|---|
| The board's cleared column | | Cleared by board | `World.reconcile` |
| An open production release without an `untested` label | pull requests can clear; with a board testing on the deck, only work with no card | Cleared by pull requests | `World.applyReleases` |
| A bot's crate | always | cleared from the start | `Rules` (`.decon`) |

### Shipped: the rocket

| Trigger | Condition | Event | Code |
|---|---|---|---|
| An open production release (or any open release, with no staging) | | `.release(production:)`: a rocket docked, go once its cargo is cleared | `World.applyReleases`, `Rules/RocketRules.swift` |
| Work waiting, no release open | the repository ships, and not on merge or tags | `.release(production: nil)`: a rocket standing by | the same |
| A production release merges | | `.launched`: the cargo aboard; Shipped for what waited | the same |
| A new tag | ships on tags; not the first answer | `.launched` | `GitHub.swift`, `World.applyReleases` |
| A crate lands in storage | ships on merge | a rocket of its own with the crate aboard | `Rules.mergeRocket` |
| Work shipped by another source | the board's shipped column, git not listing it | `.launched` with those crates | `World.launchShipped` |
| A hotfix pull request is open | into production from anything but the trunk, staging or a release branch | `.hotfixes`: an express rocket on its own slot | `World.applyHotfixes` |
| A hotfix merges | | `.launched(hotfix:)` with its crate; the release rocket keeps its cargo | the same |
| A production deploy starts | | the flight | `Scene/Mission.swift` |

Offices fold at Stored, never at Shipped.

### Outside work

A bot's pull request waits in decon (`World.screen`): `.decon` with the bots' open numbers. Merged, it is
Stored by pull requests and carried out; closed, `.deconClosed` ejects it. One rule recognises bots
(`GitHubResolver.isBot`): the open list's `is_bot`, or a login with `dependabot`, `[bot]`, a `-bot` ending
or `webhook`.

## Baked-in settings

| Setting | Value | Code |
|---|---|---|
| Trunk names | `develop`, `main`, `master` | `Integrations/Pipelines.swift` |
| Long-lived branches | those plus `staging`, `production` | `State/Work.swift`, `Integrations/Pipelines.swift` |
| Branches that are not work | `main`, `master`, `develop`, `HEAD` | `State/Work.swift` |
| Release branch patterns | `release*`, `hotfix*` | `Integrations/Pipelines.swift` |
| Issue branch pattern | `gh-<N>/...` | `State/Work.swift` |
| Closing words | `close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`, `resolved`, then `#N` | `Integrations/PullRequests.swift` |
| Default branch names | `develop`, `main`, `master`; `staging`; `production` | `Integrations/Pipelines.swift` |
| Ships on tags | a version tag from the last 365 days | `Integrations/Pipelines.swift` |
| Board field | `Status` | `Integrations/Config.swift` |
| Board columns | In Development, Ready for staging, QA, Ready to ship, Shipped | `Integrations/Config.swift` |
| Untested release | any label containing "untested" | `Integrations/GitHub.swift` |
| Deploy words | environment:, serverless deploy, sls deploy, flyctl, vercel, railway, heroku, kubectl, helm upgrade, docker push, gcloud, cdk deploy, netlify deploy, wrangler deploy, firebase deploy, fly deploy | `Integrations/Deployments.swift` |
| Bot names | `dependabot`, `[bot]`, `-bot`, `webhook` | `Integrations/GitHub.swift` |
| Pull request numbers in commits | `(#N)` at the end of a subject, `Merge pull request #N` | `Integrations/GitHub.swift` |
| Stale open pull request | 14 days without an update | `Integrations/GitHub.swift` |
| Git history floor | 30 days, 80 merged pull requests, 5 release pull requests per base | `Integrations/GitHub.swift` |
| Teammate activity | feed events under 30 min | `Integrations/World.swift` |
| Neighbour's offices held | 24 h | `Integrations/World.swift` |
| Offices shared | worked in within 12 h | `Scene/Scene.swift` |
| Closed crate kept | 10 min | `Rules/Rules.swift` |
| Stored crate kept, repository that doesn't ship | 24 h | `Rules/Rules.swift` |
