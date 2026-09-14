## What's new in 0.27

- Nobody is left standing. A minion that stands still mid-task for ten seconds gives up, says so in the log, and the work goes back into the queue for the next free hands: a dropped carry is picked up from where the crate lies, an office crate on the bay floor is fetched by whoever is free, a visit simply ends. Waits on facts that never come are given up too.
- A new office's crate is always walked in, whatever the office is called by the time the shuttle lands. Renaming a branch mid-flight no longer strands a crate in the bay, and a second shuttle never lands on the first crate.
- A crate is a task. With a board, the crate is the issue a pull request closes, so the office's package and the board's item are one crate, not two. Hover a crate to see its issue and pull requests; click it to open the issue.
- Board moves arrive within a minute instead of five: the station asks every item that is not shipped by number, since a move on the board never touches the issue's own timestamp.
- A board move made while a crate is being carried is honoured after it lands, and a relaunch takes the board's word again for anything moved by hand before it.
- Traffic: right of way when two meet, a load before a job, a job before rest; whoever yields steps aside in a doorway. Someone on a couch or in bed is in nobody's way. Nothing sits in a doorway, no bed, fixture or chore.
- The rocket is loaded from the front, and nobody walks through it.
- The counters and titles count your own sessions only. Options to hide the private station and the repository titles. The GitHub interval is explained as the backstop it is.
- The station keeps a log: station.log in Application Support, every event, command, give-up and GitHub ask. Send the app SIGUSR1 to dump every body, order and crate into it.
