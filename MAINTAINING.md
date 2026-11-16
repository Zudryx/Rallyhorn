# Maintaining Rallyhorn

## Ground rules

- **Information only.** Rallyhorn shows timers and messages. Never add
  anything that casts, targets, moves, clicks or plays for the player.
- **Don't name other addons** in the addon, its guide, the release notes or
  pull requests, and never suggest Rallyhorn is one of them or works with them.
- **Original work.** Don't copy code or data from other addons. Buff data
  comes from what players record in game (capture mode) and from public
  WoW Forever guides, rewritten in our own words.
- **License headers.** New Lua files start with the same license header as the
  others (Copyright (C) 2026 Zudryx, GPL-3.0-or-later). Don't change `LICENSE`.
  The name and logo terms are in `NOTICE.md`. The addon folder carries its own
  copies of both, so keep them identical to the ones at the top of the repo.
- **Don't rename buff keys** (`ony_horde`, `rend`, ...). The keys are what's
  shared between players, so renaming one breaks sharing with older versions.
- **Never commit saved data** from the game (`WTF`, `SavedVariables`). It can
  hold other players' names.

## The owner tests before anything reaches players

1. Work goes on the **`testing`** branch. Each push there runs the tests and
   publishes a GitHub **pre-release** test build (`vX.Y.Z-test.N`). Test
   builds are never sent to CurseForge, and only the newest one is kept.
2. A test build needs a version that isn't released yet, so bump the version
   first (see below). A push for a version that's already released (for
   example a docs-only change) makes no test build.
3. When the owner has tried the test build in game and approves, merge
   `testing` into **`main`**. That publishes the normal GitHub release
   `vX.Y.Z` (and uploads it to CurseForge once that's set up).

## Making a new version

- Bump the version in **both** `Rallyhorn/Rallyhorn.toc` (`## Version:`) and
  the fallback in `Rallyhorn/Core.lua` (`readMetadata("Version") or "x.y.z"`).
  The release workflow stops if they don't match.
- Add a `- **x.y.z:**` entry at the top of `## Changes` in
  `Rallyhorn/README.md`, written for players. That entry becomes the release
  notes.
- Run the tests (they must all pass):

  ```
  lua5.3 tests/run_tests.lua
  python3 tests/lint51.py Rallyhorn
  ```

  `lint51.py` flags code that WoW's Lua 5.1 would reject and any unexpected
  global names.

## Updating buff data

Buff data lives in `Rallyhorn/Data.lua`. The "Day-one checklist" in
`Rallyhorn/README.md` explains how to read a capture log and which fields to
fill in. Set `verified = true` only for a buff whose NPC, yell lines and buff
length were seen in WoW Forever, and say in its `note` what is still an
estimate. Add a test with the real yell lines, like the Rend ones in
`tests/run_tests.lua`.

## When WoW Forever patches

If the game's interface number changes, update `## Interface:` in
`Rallyhorn/Rallyhorn.toc` (in game: `/dump select(4, GetBuildInfo())`), then
make a new version as above.

## CurseForge

Not set up yet. Once the CurseForge project exists:

1. Add `## X-Curse-Project-ID: <project id>` to `Rallyhorn/Rallyhorn.toc`.
2. Add a CurseForge API token as the repository secret `CF_API_KEY`
   (Settings > Secrets and variables > Actions).
3. Check it without uploading: Actions > Release > Run workflow, branch
   `main`, **CurseForge: check**.

From then on, every new release on `main` is also uploaded to CurseForge by
`.github/scripts/curseforge_upload.py`, tagged with the WoW Forever game
version that matches `## Interface` (16001 = 1.60.1). If an upload fails, fix
the cause and run the workflow by hand with **upload**.
