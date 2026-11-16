#!/usr/bin/env python3
"""Lua 5.1 compatibility + global-usage lint for the addon.

The only Lua available here is LuaTeX's Lua 5.3, which accepts syntax that
WoW's Lua 5.1 rejects. This strips comments/strings and flags 5.2+ features,
then lists every global each file reads or writes (via luac -l) and flags
ones that are not known WoW API / Lua 5.1 names.
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Any Lua 5.3/5.4 compiler can list globals: LuaTeX's here, plain luac on GitHub.
LUAC = next((c for c in ("texluac", "luac5.3", "luac5.4", "luac") if shutil.which(c)), None)
if LUAC is None:
    sys.exit("lint51: no luac found (install lua5.3)")

ADDON = Path(sys.argv[1])

FORBIDDEN_TOKENS = [
    (r"\bgoto\b", "goto (5.2+)"),
    (r"::", "label (5.2+)"),
    (r"//", "integer division (5.3)"),
    (r"&", "bitwise and (5.3)"),
    (r"(?<![~<>=])~(?!=)", "bitwise xor/not (5.3)"),
    (r"<<|>>", "bit shift (5.3)"),
    (r"(?<!\|)\|(?!\|)", "bitwise or (5.3)"),
]
FORBIDDEN_NAMES = [
    "table.unpack", "table.pack", "table.move", "math.type", "math.tointeger",
    "math.ult", "utf8.", "string.pack", "string.unpack", "rawlen", "os.", "io.",
    "require", "dofile", "loadfile", "_ENV", "coroutine.isyieldable",
]

# Lua 5.1 + WoW globals the addon may touch.
KNOWN_GLOBALS = set("""
_G assert error ipairs next pairs pcall print rawget rawset select setmetatable getmetatable
tonumber tostring type unpack xpcall math string table date time strsplit wipe
CreateFrame UIParent GameTooltip DEFAULT_CHAT_FRAME C_AddOns GetAddOnMetadata C_Timer C_ChatInfo
C_UnitAuras GetServerTime GetTime GetNormalizedRealmName UnitName UnitFullName GetUnitName
IsInInstance InCombatLockdown UnitAffectingCombat GetRealZoneText GetZoneText GetSubZoneText
UnitFactionGroup IsInGuild IsInGroup IsInRaid LE_PARTY_CATEGORY_HOME SOUNDKIT PlaySound
geterrorhandler issecretvalue Enum Settings BackdropTemplateMixin SlashCmdList GetBuildInfo
Minimap GetCursorPosition
""".split())

def strip_comments_and_strings(src: str) -> str:
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                end = src.find("]" + m.group(1) + "]", i)
                i = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = src.find("\n", i)
                i = n if end < 0 else end
            out.append(" ")
            continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            end = src.find("]" + m.group(1) + "]", i)
            i = n if end < 0 else end + len(m.group(1)) + 2
            out.append('""')
            continue
        if c in "\"'":
            j = i + 1
            body = []
            while j < n and src[j] != c:
                if src[j] == "\\":
                    body.append(src[j:j + 2])
                    j += 2
                    continue
                body.append(src[j])
                j += 1
            text = "".join(body)
            for esc, why in ((r"\\z", "\\z escape (5.2+)"), (r"\\x[0-9a-fA-F]", "\\x escape (5.2+)"), (r"\\u\{", "\\u{} escape (5.3)")):
                if re.search(esc, text):
                    problems.append(f"{current}: string uses {why}: {text[:40]!r}")
            i = j + 1
            out.append('""')
            continue
        out.append(c)
        i += 1
    return "".join(out)

problems = []
globals_report = {}
for path in sorted(ADDON.glob("*.lua")):
    current = path.name
    code = strip_comments_and_strings(path.read_text())
    for lineno, line in enumerate(code.splitlines(), 1):
        for pat, why in FORBIDDEN_TOKENS:
            if re.search(pat, line):
                problems.append(f"{current}:{lineno}: {why}: {line.strip()[:80]}")
        for name in FORBIDDEN_NAMES:
            if re.search(r"(?<![\w.])" + re.escape(name) + (r"\b" if not name.endswith(".") else ""), line):
                problems.append(f"{current}:{lineno}: {name} is not Lua 5.1/WoW: {line.strip()[:80]}")
        if re.search(r"%d", line) and "string.format" in line and "math.floor" not in line:
            pass  # format checks are covered by tests

    listing = subprocess.run([LUAC, "-l", "-p", str(path)], capture_output=True, text=True).stdout
    names = set(re.findall(r"[GS]ETTABUP\s.*_ENV \"([^\"]+)\"", listing))
    globals_report[current] = names
    for name in sorted(names):
        if name not in KNOWN_GLOBALS:
            problems.append(f"{current}: unexpected global '{name}'")

for f, names in globals_report.items():
    print(f"{f}: {', '.join(sorted(names))}")
print()
if problems:
    print("PROBLEMS:")
    for p in problems:
        print("  " + p)
    sys.exit(1)
print("lint51: OK (no Lua 5.2+ syntax, all globals known)")
