## What's new in 0.29

- Each repository's way to production is read from what it actually does: where most work merges, where releases end, and what is released through staging. Nobody has to set it up, and the Releases tab in Settings shows what was found for each repository and why.
- A repository can state its release setup exactly, for everyone, with a small .github/rumkapsel.json file on its default branch.
- Repositories that deploy on every merge now ship on merge: the merged crate goes straight up in a small rocket of its own.
