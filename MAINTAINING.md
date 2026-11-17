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

## How changes reach players

1. **Every finished change is released on GitHub.** Make a new version (see
   below) and push it to **`main`**. That publishes GitHub release `vX.Y.Z`
   with the addon zip and `RallyhornUpdater.zip`, and the owner updates with
   "Update Rallyhorn.bat" to test it in game. A push that doesn't change the
   version (for example a docs-only change) releases nothing.
2. **CurseForge waits for the owner.** Nothing is sent there automatically.
   Only when the owner says the changes are complete, run Actions > Release >
   Run workflow on `main` with **CurseForge: upload** (or
   `gh workflow run release.yml --ref main -f curseforge=upload`). It sends
   the current release's zip, with a changelog covering every version since
   the last upload. The `curseforge` tag marks what was sent last; the
   workflow moves it, so don't move or delete it by hand.
3. **Test builds are optional**, for trying something risky before it's a
   release. Pushing to **`testing`** publishes a GitHub **pre-release**
   (`vX.Y.Z-test.N`), installed by "Update Rallyhorn (testing).bat". It needs
   a version that isn't released yet, only the newest test build is kept, and
   test builds never go to CurseForge. Once that version is released on
   `main`, its test builds are removed. Fast-forward `testing` to `main` after
   each release so it never falls behind.

## The updater

`updater/` holds the Windows updater: `Update-Rallyhorn.ps1` and the two
`.bat` files that run it. Every release (test builds too) carries it as
`RallyhornUpdater.zip`. It finds the `_forever_\Interface\AddOns` folder,
installs the newest release if it's newer than the installed `## Version:`,
keeps the old copy in a `backup` folder next to itself and prints the release
notes. It picks the addon zip by the name `Rallyhorn-*.zip`, so keep that
name. Keep the `.ps1` plain ASCII: Windows PowerShell 5.1 misreads other
characters in a file without a byte order mark.

## Making a new version

- Bump the version in **both** `Rallyhorn/Rallyhorn.toc` (`## Version:`) and
  the fallback in `Rallyhorn/Core.lua` (`readMetadata("Version") or "x.y.z"`).
  The release workflow stops if they don't match.
- Add a `- **x.y.z:**` entry at the top of `## Changes` in
  `Rallyhorn/README.md`, written for players. That entry becomes the release
  notes (`.github/scripts/changelog.py` reads it).
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

## Logo

`media/logo.svg` is the original. Made from it:

- `media/logo.png` (512 px) and `media/logo-400.png` (400 px, for CurseForge).
- `media/social-preview.png` (1280×640): GitHub's link preview. GitHub has no
  API for it, so upload it by hand under Settings > General > Social preview.
- `Rallyhorn/Media/Icon.tga`: the in-game icon (minimap button and the game's
  addon list). 64×64, uncompressed 32-bit with alpha, rows stored bottom-up
  (the usual TGA layout). Check it in game after remaking it: a TGA written
  with the wrong row order shows up upside down.

## When WoW Forever patches

If the game's interface number changes, update `## Interface:` in
`Rallyhorn/Rallyhorn.toc` (in game: `/dump select(4, GetBuildInfo())`), then
make a new version as above.

## CurseForge

Not set up yet. Once the CurseForge project exists:

1. Add `## X-Curse-Project-ID: <project id>` to `Rallyhorn/Rallyhorn.toc`
   and release that as a new version.
2. Add a CurseForge API token as the repository secret `CF_API_KEY`
   (Settings > Secrets and variables > Actions).
3. Check it without uploading: Actions > Release > Run workflow, branch
   `main`, **CurseForge: check**. It also shows the changelog it would send.

Uploads only happen when the owner asks (see "How changes reach players").
`.github/scripts/curseforge_upload.py` tags them with the WoW Forever game
version that matches `## Interface` (16001 = 1.60.1). If an upload fails, fix
the cause and run **upload** again; the `curseforge` tag only moves after a
successful upload.
