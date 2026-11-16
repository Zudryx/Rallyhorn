# Rallyhorn

World buff drop timers for **WoW Forever**. Rallyhorn notices when a world buff
drops (for example an Onyxia or Rend head turn-in), shows how long the buff
lasts and when it can drop again, and shares those timers with your guild and
group.

Version 0.1.2 is a pre-release, built before Forever's raids open on
**December 9, 2026**. The timer engine, sharing, window and test tools work
now. The Horde Rend turn-in (Warchief's Blessing) was confirmed in game on
November 16, 2026. The Onyxia yell text and spell IDs can't be checked until
someone kills Onyxia, so they are still placeholders (see "Day-one checklist").

Rallyhorn only shows information. It never casts, targets, moves, or clicks
anything for you.

---

## Install

1. Download `Rallyhorn-x.y.z.zip` from the newest release on
   <https://github.com/Zudryx/Rallyhorn/releases> (skip the ones marked
   *Pre-release*: those are test builds). Unzip it. You get a folder called
   `Rallyhorn`.
2. Copy that folder into Forever's AddOns folder:
   `World of Warcraft\_forever_\Interface\AddOns\`
   (The beta used `_classic_beta_` instead of `_forever_`.) When you're done
   you should have `...\Interface\AddOns\Rallyhorn\Rallyhorn.toc`.
3. Restart the game completely. A new addon usually isn't picked up by `/reload`.
4. On the character screen, open **AddOns** and make sure Rallyhorn is ticked.

If the AddOns list says **out of date**, Blizzard has changed the interface
number. Tick "Load out of date AddOns", or change the first line of
`Rallyhorn.toc` to the new number.

### Why there's one plain TOC file

Rallyhorn ships a single `Rallyhorn.toc` containing `## Interface: 16001`.
Some Forever addons ship an extra `Rallyhorn_Camelot.toc`, but that isn't
needed here:

- The client looks for a game-specific file (`_Camelot`, or its newer alias
  `_Forever`) first, and falls back to the plain `.toc` when it can't find one.
  A plain TOC loads whatever the suffix ends up being called. "Camelot" was
  Forever's internal codename, and the suffix may still be renamed.
- Rallyhorn only targets Forever, so there are no other game versions to
  separate out.
- With one TOC there's only one file list to keep up to date.

If you later want one package for several game versions, add
`Rallyhorn_Camelot.toc` (Forever) next to the plain one.

---

## Using it

A small window lists each world buff for your faction. Each row shows:

- **Lands in 0:12**: the buff has been announced and is about to land.
- **Up · 1h 52m left**: the buff is active.
- **Ready in 3h 10m**: the buff is gone and can't drop again yet.
- **Can drop now**: the cooldown is over.
- **Gone · 2h ago**: the buff has ended and its cooldown is unknown.
- **No data**: no drop has been seen yet.

The small grey line under each row says when the buff dropped and where that
information came from: *heard* (you heard the yell), *your buff* (read from your
own buff), *heard + your buff* (both), *via Name Surname* (shared by another
player) or *test*. Hover over
a row for details. A grey `*` after a buff's name means its values are still
unverified.

To move the window, drag its title or any row. Lock it with `/rhorn lock`.
Settings are under **Esc → Options → AddOns → Rallyhorn**.

Rallyhorn has its own **minimap button** (the Rallyhorn horn logo on the edge
of the minimap). You don't need any other addon for it:

- Left-click shows or hides the window.
- Right-click opens the settings.
- Drag it to move it around the minimap.
- `/rhorn minimap off` hides it, and `/rhorn minimap reset` brings it back to
  its default spot.

If your game also shows its own addon list button by the minimap, Rallyhorn
appears in that list too, with the same clicks.

### Slash commands

`/rallyhorn` and `/rhorn` do the same thing.

| Command | What it does |
|---|---|
| `/rhorn` | Show or hide the window |
| `/rhorn show`, `hide`, `lock`, `unlock` | Window visibility and position lock |
| `/rhorn reset` | Put the window back in its default spot at normal size |
| `/rhorn minimap on` or `off` | Show or hide the minimap button |
| `/rhorn minimap reset` | Show the minimap button and put it back in its default spot |
| `/rhorn scale 0.8` | Set the window size (0.5 to 2) |
| `/rhorn status` | Print every timer to chat |
| `/rhorn list` | List buff keys, with their faction, type and whether they're verified |
| `/rhorn clear <key>` or `/rhorn clear all` | Forget timers |
| `/rhorn buff <key> show` or `hide` | Show or hide one buff's row |
| `/rhorn faction all` or `own` | Show both factions' buffs, or only yours |
| `/rhorn announce on` or `off` | Turn the chat message for new drops on or off |
| `/rhorn sound on` or `off` | Turn the raid-warning sound for new drops on or off |
| `/rhorn sync on` or `off` | Turn timer sharing on or off |
| `/rhorn sync guild on` or `off`, `/rhorn sync group on` or `off` | Turn sharing on or off for each channel |
| `/rhorn sync query` | Ask guild and group for their timers |
| `/rhorn sync status` | Show sharing state, message counts and why sending is blocked, if it is |
| `/rhorn test <key> [minutesAgo] [share]` | Make a fake drop (see the test checklist) |
| `/rhorn testyell <key>` | Send a fake NPC yell through the real yell detector |
| `/rhorn standin on` or `off` | Use Battle Shout as a stand-in world buff, for testing |
| `/rhorn capture on` or `off` | Turn capture mode (logging yells and auras) on or off |
| `/rhorn capture show [n]`, `stats`, `clear` | Look at or clear the capture log |
| `/rhorn options` | Open the settings page |
| `/rhorn debug on` or `off` | Turn extra diagnostic output on or off |
| `/rhorn version` | Show the addon, protocol and client versions |

The buff keys are `ony_horde`, `ony_alliance`, `rend`, `rend_alliance`,
`zandalar`, `resist_fire`, `songflower` and `dmf_fortune`. When the stand-in is on, `battleshout` is added.

---

## How it works

- **Data table** (`Data.lua`). Everything about a buff is in one table: name,
  faction, duration, cooldown, spell IDs, aura names, and the NPC lines that
  trigger it. NPC lines are matched by the NPC's name plus a few short keywords,
  not whole sentences, so if Blizzard rewords a yell you only edit the data.
  Anything not yet confirmed in Forever has `verified = false`.
- **Detection.**
  - The main method is NPC yells (`CHAT_MSG_MONSTER_YELL`, and `SAY` if a
    trigger asks for it).
  - The fallback is your own buffs. Rallyhorn only reads them out of combat,
    because Forever hides buff details from addons during combat.
  - A world buff on you that's more than two minutes old can only refine a drop
    Rallyhorn already knows about. It never starts a new timer, because Forever
    may pause or re-apply buffs.
  - A fresh buff whose length doesn't match the table is tracked for you only
    and never shared.
- **Timer engine** (`Engine.lua`). Every report, real or fake, goes through
  `Engine:RecordDrop(key, time, source)`.
  - Reports less than 90 seconds apart count as the same drop (30 seconds for
    Rend, because players can turn heads in only minutes apart). When two
    reports clash, the more trustworthy source wins: your own buff, then the
    yell, then a shared report, then a test.
  - Reports more than 5 minutes in the future or more than a day old are
    rejected.
- **Personal buffs** (Resist Fire, Songflower, Darkmoon fortune) come from your
  own buffs only and are never shared.

### Sharing timers

- **Where.** Rallyhorn sends addon messages over GUILD and PARTY/RAID, and only
  in the open world. Forever's engine blocks addon messages inside instances.
  Anything waiting to be sent is held until you're back outside.
- **What's in a message.** Only a buff key and a server timestamp. The format
  is versioned:
  - `1:D:<key>:<time>` reports one drop.
  - `1:Q:<version>:<nonce>` asks other players for their timers.
  - `1:S:<key>=<time>,...` answers a question.
  - Messages from newer versions, unknown buffs or bad input are ignored.
- **Keeping traffic down.**
  - When a whole city hears the same yell, each player waits a random 1 to 6
    seconds before sharing. Whoever shares first stops everyone else.
  - Answers to a question are delayed in the same way and only include what
    nobody else has already said.
  - Messages go out at most one every 1.5 seconds, well under Blizzard's limit.
    Anyone sending more than 15 messages a minute is ignored.
  - The automatic question sent at login, after a reload, on joining a group
    or on leaving an instance is limited to once every 5 minutes per channel,
    even across reloads.
- **Names.** Forever's two-part names ("First Last") are kept whole. A
  `-Realm` ending is only removed when it's your own realm.
- **Test drops** are never sent unless you ask, and then only to your party or
  raid, marked as a test. Rallyhorn refuses test-marked drops that arrive
  through guild chat.
- **Accounts that can't send.** Blizzard doesn't let trial and Veteran accounts
  send addon messages. They still receive shared timers.

### Capture mode

`/rhorn capture on` records two things:

- Every NPC yell or say: NPC, text, zone, subzone and time. It keeps 300 lines,
  and identical lines are counted instead of repeated.
- Every new helpful buff on you: spell ID, name, length and zone. It keeps 200.

Yells are also printed in chat as they happen. The log is saved to
`World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\Rallyhorn.lua`
when you log out or `/reload`, under `RallyhornDB.capture`. Lines from inside
instances may show as `<secret>`, which is expected.

---

## In-game test checklist (before Dec 9)

Run `/console scriptErrors 1` first so any Lua error shows up on screen.

**1. It loads**
- [ ] `/rhorn version` prints the addon version and client interface 16001.
- [ ] The window shows rows for your faction: Onyxia head, Rend head
  (Orgrimmar for Horde, Stormwind for Alliance), Resist Fire and Songflower.
- [ ] The settings page opens from Esc → Options → AddOns → Rallyhorn.
- [ ] The horn-logo button on the minimap's edge works: left-click toggles
  the window, right-click opens the settings, and you can drag it around the
  minimap. `/rhorn minimap off` hides it and `/rhorn minimap on` brings it
  back. After a `/reload` it's still where you left it.
- [ ] You can drag, `lock`, `unlock`, `scale 1.3` and `reset` the window.

**2. Fake timers**
- [ ] Run `/rhorn test ony_horde` (or `ony_alliance`). The row turns green:
  "Up · 2h 00m left", plus a chat message.
- [ ] Run `/rhorn clear all`, then `/rhorn test ony_horde 150`. The row shows
  "Ready in 3h 30m".
- [ ] Run `/rhorn clear all`, then `/rhorn testyell ony_horde`. A fake yell
  goes through the real yell detector and the row shows the drop as a test.
- [ ] Type `/reload`. The timers are still there.

**3. Battle Shout stand-in (tests the buff detector for real)**
- [ ] Run `/rhorn standin on`. A "Battle Shout (stand-in)" row appears.
- [ ] Cast Battle Shout out of combat. Within a second the row shows "Up" with
  the real length, and the grey line says *your buff*.
- [ ] Cast it during a fight. Nothing happens until combat ends, then the row
  updates. That's correct, because buff details are hidden in combat.
- [ ] If the row never updates, Forever uses a different spell ID. Turn on
  `/rhorn capture on`, cast Battle Shout again, and check the
  `[capture] new aura: Battle Shout (spell ID ...)` line. Rallyhorn also
  matches by name, so this should be rare.

**4. NPC yells reach the addon**
- [ ] Run `/rhorn capture on`.
- [ ] Leave capture on while you play. This doesn't have to happen in a city:
  any NPC or mob anywhere counts. Some mobs talk when they start a fight, and
  some quest and escort NPCs yell. Each yell prints
  `[capture] <NPC> yells: <text>` in chat.
- [ ] NPCs that only *say* something are logged quietly, without a chat line.
  `/rhorn capture show` lists both yells and says, with zone and time. Any line
  there proves NPC chat reaches the addon.
- [ ] Inside a dungeon, yells may show as `<secret>`. That's expected and
  doesn't matter for world buffs, which drop in cities.

**5. Sharing with a friend or a second account** (both need Rallyhorn installed)
- [ ] Get into the same party.
- [ ] On A, run `/rhorn clear all`, then `/rhorn test ony_horde share`. Within
  about 7 seconds B gets a chat message and a row saying *test via A's name*.
  Use `ony_alliance` if you're Alliance.
- [ ] Both run `/rhorn standin on`. When A casts Battle Shout, B's stand-in row
  updates (party only).
- [ ] Guild channel: log in one after the other, then `/rhorn sync status` on each shows
  "sent" at least 1 (the login question went out). It shows "received" above 0
  once the other player's messages arrive.
- [ ] Inside a dungeon, `/rhorn sync status` says "Can send now: no (instance)".
  After you leave, held messages go out.
- [ ] Afterwards, both run `/rhorn standin off` and `/rhorn clear all`.

**6. Capture file**
- [ ] With capture on, `/reload`, then open
  `WTF\Account\<ACCOUNT>\SavedVariables\Rallyhorn.lua` and find
  `RallyhornDB.capture.chat` and `.auras`.

---

## Day-one checklist (Dec 9, when Onyxia's Lair opens)

1. **Before the first kill:** you, and anyone in the guild willing to help, run
   `/rhorn capture on` and wait in Orgrimmar or Stormwind. One player from each
   faction is ideal.
2. **Capture the first turn-in.** When the head is turned in, note the time.
   Stay put until the buff lands, then `/reload`.
3. **Read the log.** In `SavedVariables\Rallyhorn.lua`, look under:
   - `RallyhornDB.capture.chat`: the NPC's name, the exact yell lines, and the
     seconds between the first yell and the buff landing.
   - `RallyhornDB.capture.auras`: the buff's spell ID, name and length.
4. **Update `Data.lua`** for `ony_horde` and `ony_alliance`:
   - `npc`: the yelling NPC's exact name.
   - `all`: one to three distinctive words from each yell. Use whole words
     only, any case. Capitalization and punctuation don't matter.
   - `delay` on the `stage = "announce"` trigger: the seconds from that yell
     until the buff lands.
   - `spellIds`, `duration`, and `cooldown` once known (the time before the
     head can be turned in again).
   - Set `verified = true` for each value you've confirmed.
5. **Check it.** `/rhorn testyell ony_horde` should match. If you have Lua
   installed, run the tests too (see Development).
6. **Ship a patch.**
   - Bump the version and push to the `testing` branch on GitHub. That makes
     a test build to try in game; merging into `main` releases it (see
     `MAINTAINING.md` in the repo).
   - Don't rename buff keys. Keys are what's shared between players, so
     keeping them lets old and new versions still share timers.
7. **Do the same for the Alliance Rend buff** (Might of Stormwind, key
   `rend_alliance`): an Alliance player with capture on in Stormwind records
   the yell, and it goes into `triggers`. Horde Rend is already confirmed.
   Do the same for any other world buff confirmed in Forever.

---

## Known limits

- Except Horde Rend, buff values are Classic Era placeholders until confirmed.
- Rend has no long cooldown in Forever (drops were seen minutes apart), so its
  row shows "Gone" rather than "Ready in" once the buff ends.
- Might of Stormwind (Alliance Rend) is picked up from your own buff only,
  until its yell is recorded.
- NPC names and keywords are English, so the addon only detects drops on
  English (enUS) clients for now.
- Forever reportedly applies world buffs in the open world only (not dungeons,
  raids or battlegrounds). Rallyhorn tracks the timers either way.
- Nothing is read or sent inside instances, because Forever blocks it.

## Renaming the addon

The name lives in one place: the folder and TOC name. To rename:

1. Rename the folder and `Rallyhorn.toc` to the new name.
2. In the TOC, update `## Title`, `## SavedVariables` (`<NewName>DB`), the
   three `AddonCompartmentFunc` lines (`<NewName>_OnAddonCompartment...`) and
   the folder name in `## IconTexture`. Make a new logo too: the Rallyhorn
   logo can't be used for a renamed copy (see `NOTICE.md`).
3. Optionally change the short slash command `/rhorn` in `Core.lua`.

Saved settings, the main slash command, the sync prefix and the window frame
all follow the folder name automatically. Changing the name also changes the
sync prefix, so renamed and old copies won't share timers.

## Development

- **Files.**
  - `Core.lua`: guards for secret values, events and saved variables.
  - `Matcher.lua`: matches NPC lines against the triggers.
  - `Data.lua`: the buff table.
  - `Engine.lua`: the timers.
  - `Sync.lua`: message format and sending.
  - `Capture.lua`: capture mode.
  - `Detect.lua`: yell and buff detection.
  - `UI.lua`: the window.
  - `Options.lua`: the settings page and the game's addon list entry.
  - `MinimapButton.lua`: Rallyhorn's own minimap button.
  - `Slash.lua`: slash commands.
- **Source and tests.** The code, tests and release process are on GitHub at
  <https://github.com/Zudryx/Rallyhorn>. The tests and their WoW API
  stand-ins live outside the addon folder, in `tests/`. From the top of the
  repo, run `lua5.3 tests/run_tests.lua`. `python3 tests/lint51.py Rallyhorn`
  flags code that WoW's Lua 5.1 would reject, and any unexpected globals.
  GitHub runs both on every push.

## Changes

- **0.1.2:**
  - Horde Rend (Warchief's Blessing) is confirmed in Forever: Thrall's two
    yells in Orgrimmar and the 1-hour buff. Its row no longer has the
    unverified `*`, and the tooltip says it has no long cooldown.
  - The buff cast by the Heralds of Thrall (the Crossroads and Razor Hill)
    now counts as Rend too.
  - Rend drops only a minute or two apart are now kept as separate drops.
  - New Alliance row: Rend head (Stormwind), for Might of Stormwind.
  - When Rallyhorn both heard the yell and saw your buff, the row now says
    *heard + your buff* instead of only *your buff*.
  - Rallyhorn has its own logo, now on the minimap button and in the game's
    addon list.
- **0.1.1:** Rallyhorn now has its own minimap button. It's draggable and can
  be hidden with `/rhorn minimap off`, and it needs no other addon.
- **0.1.0:** First test build.

## License

Copyright (C) 2026 Zudryx. Licensed under GPL-3.0-or-later (see `LICENSE`).

Additional term: the Rallyhorn name and logo aren't covered by the GPL.
Modified versions must use a different name and logo (see `NOTICE.md`).

World of Warcraft and WoW Forever are trademarks of Blizzard Entertainment.
This is a fan-made addon, not affiliated with Blizzard.
