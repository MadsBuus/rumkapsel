## What's new in 0.28

- Hold space to run the station four times faster. The camera keeps its pace, and the station says so while space is held.
- Every repository has its own way to production. A repository without a staging branch skips the deck: merged work waits in storage and its rocket loads from there. Releases into master or main count as production, including releases cut on a release or hotfix branch, as android does.
- A repository on the board that goes straight from development to shipped gets its yard from git, so its merged work still shows in storage.
- Sharing on the local network shows more and clutters less. Only offices worked in during the last twelve hours are shared. A shared office carries its pull request and checks, and its people as real minions, working, waiting with their messages, or asleep.
- A teammate's office that is not on GitHub yet is drawn solid while someone works in it, with its outline kept as a mark, and dimmed when they say it is idle.
- Works with teammates still on 0.27: they simply see less until they update.
