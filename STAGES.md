# Stages

What a piece of work goes through, what the station does at each step, and what may tell it so. The
station reacts to stages only; where a stage comes from is the business of the integrations below and
of nothing else. Changing what triggers what is a change to a table here, not to the scene.

## Things

These are the words, in code, docs, settings and the log. A theme may draw them differently and call
them what it likes on screen (`Vocabulary`), but underneath they are these.

| Thing | What it is |
|---|---|
| **minion** | a session at work |
| **office** | a branch: one room per piece of work |
| **shuttle** | brings a new office to the bay |
| **bay** | where shuttles land |
| **cone** | the message a minion is working on |
| **cube** | a commit; a ghost cube is uncommitted work |
| **crate** | a pull request |
| **storage** | where merged crates wait for a release |
| **pallet** | carries crates from storage to the staging area |
| **staging area** | where crates are tested (was "the deck") |
| **launchpad** | where the rocket waits |
| **rocket** | a release to production |
| **decon** | where pull requests from outside wait to be screened |

## Stages

In order. Work only moves forward, except where a stage says how it goes back.

| Stage | On the station | Optional |
|---|---|---|
| **Inbound** | a shuttle brings the office | |
| **Working** | a minion hammering, cones, cubes piling up | |
| **Ready** | a crate packed in the office; its light shows checks, its straps the review | |
| **Stored** | the crate carried to storage | |
| **QA** | the pallet takes it to the staging area, where it is tested | yes: no staging, no QA |
| **Cleared** | a green sticker: tested, ready to ship | yes: nothing to clear it, no Cleared |
| **Shipped** | loaded onto the rocket and launched; the office is archived | |

A repository without QA goes from Stored to Shipped. One without Cleared never waits for it: the
rocket does not hold for a sticker nobody can give.

**The rocket follows the stages.** Anything Stored or Cleared and not yet Shipped means a rocket stands
on the launchpad for that repository, loading what is ready. Shipped launches it. This holds however
the repository ships, by a release pull request, a tag or a deploy.

**Outside work** is a pull request not from the team: a bot, a fork, a first-time contributor. It skips
Inbound, Working and Ready and waits in decon; merged, it joins storage as Stored and goes on like
anything else, counted as Cleared from the start.

## Integrations

Each integration reports signals, "this work in this repository reached this stage, at this time", and
nothing else. None of them knows about the station. Only the first three are needed; a project that
has pull requests and nothing else gets a whole station.

| Integration | What it gives the station | Stages | How fast |
|---|---|---|---|
| **Local sessions** (Claude Code, Conductor; other agents later) | minions and cones; an office for every checkout; whose office is whose | Inbound, Working | at once: the transcripts are watched, and read every 5 s besides |
| **Git** (the checkout: branches, history, tags) | cubes and ghost cubes; unpushed work; what is merged and not yet released; the trunk, staging and production branches; a tag as a release | Working, Stored, QA, Shipped | a minute or so; local, but tied to the release read |
| **GitHub pull requests** (essential) | the crate, its light and straps; teammates' offices; the merge that sends a crate to storage; release pull requests as the pallet and the rocket; outside work | Inbound, Ready, Stored, QA, Shipped, outside | the activity feed once a minute as a doorbell, a pull request asked at once when rung, everything again every 5 min |
| **GitHub issues** (optional) | one identity for a branch, its pull request and its issue: `gh-N/…` names the office after the issue, `closes #N` ties the crate to it; assignees as teammates | identity; Inbound | with the pull request |
| **GitHub Projects** (optional) | Cleared per crate, the one signal nothing else gives; a doorbell that rings within seconds; a source for Stored and QA where a team moves cards faster than it merges | Cleared; doorbell; Stored, QA by choice | what moved, every 20 s; the whole board every 5 min |
| **Neighbours** | everything, second hand, from a sister station on the network | all | every 3 s, as fast as the neighbour heard it |

**A project with no issues** is the common case: work is the branch, then the pull request. The office
is named after the branch, the crate carries the pull request's number, the board has nothing to say.
Issues add names and a second number, not a stage.

**Later, not now:** GitHub Actions and deployments (QA when a staging deploy lands, Cleared when
production is approved, Shipped when the production deploy succeeds); Sentry and the like (incoming
bugs: something new arriving at the station, not a stage); AWS and the like (the state of the
infrastructure); ticket systems (Jira, Linear, in the board's place).

Speed is not a rule of its own, it is why the rules below are the way they are. Most integrations are
a combination: something cheap and quick that only says *something moved* (a transcript changing, a
feed event, a board item's time), and something slow and thorough that says *what*. The quick one is a
**doorbell**: when it rings, the thorough one is asked about that work straight away instead of at its
next turn, and the full read every few minutes is only the backstop for a missed ring. A signal is
worth what it says, not how soon: a doorbell alone never moves work.

## Priorities

Several signals can say the same thing: merged work is a column on the board, a merged pull request and
a commit on the trunk. They are heard together, by two rules:

- **Forward: the furthest wins.** Any signal that is set up may move work on. Whichever says it first
  moves it; the others catch up and change nothing. A board that is quick, or git that is slow, or a card
  nobody remembered to move, never holds work back.
- **Back: only the first in line.** Work goes back a stage only when the highest signal for that stage
  *changes* to an earlier one: a card moved from QA back to development, a pull request closed unmerged.
  A signal that simply has not caught up is not saying anything, and a lower signal can never pull work
  back at all.

So the order matters for one thing: whose word takes work back, and whose word the hover quotes.
Defaults, first in line first:

| Stage | Signals |
|---|---|
| Inbound | local session · pushed branch · board: in development · neighbour |
| Working | local session · neighbour |
| Ready | pull request open |
| Stored | board column · pull request merged · merge in git history |
| QA | board column · deployment to staging · release into the staging branch |
| Cleared | board column · environment approval · pull request label |
| Shipped | board column · deployment to production · release into the production branch · tag · merge, where every merge deploys |

A repository can reorder a stage, or switch a signal off, in Settings; this table is only where it
starts.

## Worked example: our own setup

Develop → staging → production, a board with In Development / Ready for staging / QA / Ready to ship /
Shipped. What decides each stage today, and what the board is actually for:

| Stage | Decides it today | Without the board | The board adds |
|---|---|---|---|
| Inbound | session; teammate's pull request; a board issue with a branch or pull request in sight | the same, minus the board | an office for an issue that has a branch but no pull request yet |
| Working | session, commits | same | nothing |
| Ready | pull request open | same | nothing |
| Stored | the merge for the haul; the board's column for the counts | git `staging..trunk` for the counts, the same set | seconds instead of minutes; the crate numbered by issue instead of pull request |
| QA | the staging release for the pallet; the board's column for the counts | git `production..staging` for the counts | speed only |
| Cleared | the Ready to ship column, per crate | the `untested` label on the release, for the whole release | **the only per-crate Cleared** |
| Shipped | the production release merging | same | leftover crates tidied away |
| Outside | bots, from pull requests and the feed | same | nothing |

So the board's real jobs are Cleared and the doorbell; the rest it does again, faster, and the two
sources agreeing about it has been where the bugs were. Under the rules above, driving Stored and QA
from the board becomes a choice per repository, off by default, and whichever source says it first
simply wins.
