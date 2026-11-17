#!/usr/bin/env python3
# Copyright (C) 2026 Zudryx. Part of Rallyhorn, licensed under the GNU GPL v3 or later.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Print release notes from the "## Changes" list in Rallyhorn/README.md.

  changelog.py README.md --version 1.2.3
      just that version's entry (the GitHub release notes)
  changelog.py README.md --version 1.2.3 --since 1.2.0
      every entry newer than 1.2.0 up to 1.2.3, newest first, each under its
      own heading (the CurseForge changelog: CurseForge only gets some of the
      versions, so its notes cover everything since the last upload)

Entries look like "- **1.2.3:**" followed by lines indented by two spaces.
"""
import argparse
import re
import sys

ENTRY = re.compile(r"^- \*\*(\d+(?:\.\d+)*):\*\*\s*(.*)$")


def vkey(v):
    return tuple(int(x) for x in v.split("."))


def read_entries(path):
    entries, current, in_changes = [], None, False
    with open(path, encoding="utf-8") as f:
        for line in f.read().splitlines():
            if line.startswith("## "):
                in_changes = line.strip() == "## Changes"
                current = None
                continue
            if not in_changes:
                continue
            m = ENTRY.match(line)
            if m:
                current = (m.group(1), [m.group(2)] if m.group(2) else [])
                entries.append(current)
            elif line.startswith("- "):
                current = None   # some other top-level bullet
            elif current is not None:
                current[1].append(line[2:] if line.startswith("  ") else line)
    return [(v, "\n".join(lines).strip()) for v, lines in entries]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("readme")
    ap.add_argument("--version", required=True)
    ap.add_argument("--since", help="last version already released there (not included)")
    a = ap.parse_args()

    entries = read_entries(a.readme)
    if not a.since:
        print(next((text for v, text in entries if v == a.version), ""))
        return 0
    picked = [(v, text) for v, text in entries
              if vkey(a.since) < vkey(v) <= vkey(a.version)]
    print("\n\n".join("### Rallyhorn %s\n\n%s" % (v, text) for v, text in picked))
    return 0


if __name__ == "__main__":
    sys.exit(main())
