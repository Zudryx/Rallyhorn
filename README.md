<p align="center"><img src="media/logo.png" width="128" alt="Rallyhorn logo"></p>

# Rallyhorn

World buff timer for **WoW Forever**. Rallyhorn tracks Rend, Onyxia and other
world buff drops for Horde and Alliance, warns you before they land, and
shares timers with your guild and group.

Rallyhorn only shows information. It never casts, targets, moves or clicks
anything for you.

## Download and install

1. Open the [Releases page](https://github.com/Zudryx/Rallyhorn/releases) and download `Rallyhorn-x.y.z.zip`
   from the newest release that isn't marked *Pre-release*.
2. Unzip it and copy the `Rallyhorn` folder into
   `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game completely, then check that Rallyhorn is ticked in the
   **AddOns** list on the character screen.

Type `/rhorn` in game to show or hide the window.

**Test builds.** Releases marked *Pre-release* (named "test 1", "test 2" and
so on) are new versions waiting to be tested. They can have bugs. They are
never sent to CurseForge.

## Full guide

Everything else is in [`Rallyhorn/README.md`](Rallyhorn/README.md), the same
guide that comes in the download: slash commands, how detection and sharing
work, capture mode, the in-game test checklist, known limits and the list of
changes.

## Found a problem?

Open an issue and include:

- what you saw and what you expected,
- the time it happened and where you were (city or zone),
- if you can, the capture log: turn on `/rhorn capture on`, wait for it to
  happen again, `/reload`, and copy the `capture` part of
  `WTF\Account\<your account>\SavedVariables\Rallyhorn.lua`. Remove other
  players' names before posting.

## License

Copyright (C) 2026 Zudryx. Rallyhorn is free software under the GNU General
Public License, version 3 or later (see [`LICENSE`](LICENSE)).

The Rallyhorn name and logo aren't covered by the GPL. Modified versions must
use a different name and logo (see [`NOTICE.md`](NOTICE.md)).

World of Warcraft and WoW Forever are trademarks of Blizzard Entertainment.
Rallyhorn is a fan-made addon, not affiliated with or endorsed by Blizzard.
