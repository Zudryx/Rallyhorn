-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- Data: the one table of world buffs. Patching detection for a new game build
-- should only ever mean editing this file.
--
-- Fields
--   key          unique id, letters/digits/underscore only (used in sync messages)
--   name         the buff's in-game name (also used to match auras by name, enUS)
--   label        short text for the timer window
--   faction      "Horde", "Alliance" or "Both"
--   kind         "drop"     = a world event (head turn-in etc.): timers are tracked and shared
--                "personal" = a buff you pick up yourself: tracked from your own auras, never shared
--   duration     buff length in seconds (an observed aura duration overrides it per drop)
--   cooldown     minimum seconds between two drops, or nil if unknown
--   cooldownText optional: what the tooltip says instead of "cooldown unknown"
--   dedupeWindow optional: reports this many seconds apart count as one drop (default 90)
--   spellIds     aura spell IDs that mean "this buff"
--   auraNames    aura names that mean "this buff" (fallback when spell IDs change)
--   triggers     NPC chat lines that announce or apply the buff:
--                  npc    list of NPC names (exact, case-insensitive)
--                  all    every fragment must appear (whole words, case/punctuation-insensitive)
--                  any    optional: at least one of these must appear
--                  chat   "YELL" (default), "SAY" or "ANY"
--                  zones  optional list of zone names the line must come from
--                  delay  seconds from this line until the buff lands (0 = lands now)
--                  stage  "announce" for the heads-up line, nil for the line that applies the buff
--   verified     false until the values are confirmed in WoW Forever
--   defaultHidden  true to keep the row out of the window unless the player turns it on
--   note         shown in the tooltip
--
-- Every value marked verified = false comes from Classic Era and is a placeholder.
-- Forever's raids open on Dec 9, 2026; use capture mode to collect the real values.
-- verified = true means the NPC, the yell lines and the buff length were seen in
-- WoW Forever; the note says what is still an estimate.

local ADDON_NAME, ns = ...

ns.BUFFS = {
    {
        key = "ony_horde",
        name = "Rallying Cry of the Dragonslayer",
        label = "Onyxia head (Orgrimmar)",
        faction = "Horde",
        kind = "drop",
        duration = 7200,
        cooldown = 21600,
        spellIds = { 22888 },
        auraNames = { "Rallying Cry of the Dragonslayer" },
        triggers = {
            { npc = { "Overlord Runthak" }, all = { "onyxia" }, delay = 14, stage = "announce" },
            { npc = { "Overlord Runthak" }, all = { "rallying cry" }, delay = 0 },
        },
        verified = false,
        note = "Onyxia's Lair opens Dec 9, 2026. NPC, yell keywords, delay, cooldown and spell ID are Classic Era placeholders.",
    },
    {
        key = "ony_alliance",
        name = "Rallying Cry of the Dragonslayer",
        label = "Onyxia head (Stormwind)",
        faction = "Alliance",
        kind = "drop",
        duration = 7200,
        cooldown = 21600,
        spellIds = { 22888 },
        auraNames = { "Rallying Cry of the Dragonslayer" },
        triggers = {
            { npc = { "Major Mattingly" }, all = { "onyxia" }, delay = 14, stage = "announce" },
            { npc = { "Major Mattingly" }, all = { "rallying cry" }, delay = 0 },
        },
        verified = false,
        note = "Onyxia's Lair opens Dec 9, 2026. NPC, yell keywords, delay, cooldown and spell ID are Classic Era placeholders.",
    },
    {
        key = "rend",
        name = "Warchief's Blessing",
        label = "Rend head (Orgrimmar)",
        faction = "Horde",
        kind = "drop",
        duration = 3600,
        cooldown = nil,
        cooldownText = "no long cooldown (drops seen 1 to 16 minutes apart)",
        -- Heads can be turned in minutes apart (83 seconds was the shortest
        -- gap seen on Nov 17, 2026), so keep separate drops apart.
        dedupeWindow = 30,
        -- 16609: confirmed in Forever, in Orgrimmar and in the Barrens.
        -- 355366: listed by a guide for the Heralds of Thrall; not seen in
        -- game yet (the heralds' buff also showed up as 16609).
        spellIds = { 16609, 355366 },
        auraNames = { "Warchief's Blessing" },
        triggers = {
            -- Thrall in Orgrimmar. Captured Nov 16-17, 2026: the second yell
            -- (when the buff lands) came 5 and 6 seconds after the first.
            -- "...The false Warchief, Rend Blackhand, has fallen!"
            { npc = { "Thrall" }, all = { "rend blackhand" }, delay = 6, stage = "announce" },
            -- "Be bathed in my power! Drink in my might! ..."
            { npc = { "Thrall" }, all = { "my might" }, delay = 0 },
            -- The Herald of Thrall (heard in the Barrens). Same first line;
            -- second line 3 to 4 seconds later.
            { npc = { "Herald of Thrall" }, all = { "rend blackhand" }, delay = 4, stage = "announce" },
            -- "Be bathed in the power of the Warchief! Drink in his might! ..."
            { npc = { "Herald of Thrall" }, all = { "his might" }, delay = 0 },
        },
        verified = true,
        note = "Confirmed in WoW Forever: Thrall's two yells in Orgrimmar, the Herald of Thrall's two yells in the Barrens, spell ID 16609 and the 1-hour buff. The buff lands with the second yell, 3 to 6 seconds after the first.",
    },
    {
        key = "rend_alliance",
        name = "Might of Stormwind",
        label = "Rend head (Stormwind)",
        faction = "Alliance",
        kind = "drop",
        duration = 3600,
        cooldown = nil,
        dedupeWindow = 30,
        -- Reported for Forever: 1304678 and 460940.
        spellIds = { 1304678, 460940 },
        auraNames = { "Might of Stormwind" },
        -- The Stormwind yell has not been recorded yet, so this one is picked
        -- up from your own buff only. Capture mode logs the yell for a patch.
        triggers = {},
        verified = false,
        note = "Forever's Alliance twin of Warchief's Blessing: Rend's head goes to Master Mathias Shaw in Stormwind (End of the Dark Horde). The buff reaches Stormwind, Goldshire, Lakeshire and Sentinel Hill. Picked up from your own buff until the yell is recorded.",
    },
    {
        key = "zandalar",
        name = "Spirit of Zandalar",
        label = "Spirit of Zandalar",
        faction = "Both",
        kind = "drop",
        duration = 7200,
        cooldown = nil,
        spellIds = { 24425 },
        auraNames = { "Spirit of Zandalar" },
        triggers = {
            { npc = { "Molthor" }, all = { "hakkar" }, delay = 0 },
        },
        verified = false,
        defaultHidden = true,
        note = "Not confirmed in Forever. Hidden by default; turn on with /rhorn buff zandalar show.",
    },
    {
        key = "resist_fire",
        name = "Resist Fire",
        label = "Resist Fire (LBRS)",
        faction = "Both",
        kind = "personal",
        duration = 3600,
        spellIds = { 15123 },
        auraNames = { "Resist Fire" },
        triggers = {},
        verified = false,
        note = "Reported in Forever: +83 fire resistance for 60 min from a Scarshield Spellbinder in Lower Blackrock Spire. The spell ID is the Classic one.",
    },
    {
        key = "songflower",
        name = "Songflower Serenade",
        label = "Songflower (Felwood)",
        faction = "Both",
        kind = "personal",
        duration = 3600,
        spellIds = { 15366 },
        auraNames = { "Songflower Serenade" },
        triggers = {},
        verified = false,
        note = "Not confirmed in Forever. Classic Era values.",
    },
    {
        key = "dmf_fortune",
        name = "Sayge's Dark Fortune",
        label = "Darkmoon fortune",
        faction = "Both",
        kind = "personal",
        duration = 7200,
        spellIds = { 23735, 23736, 23737, 23738, 23766, 23767, 23768, 23769 },
        auraNames = {},
        triggers = {},
        verified = false,
        defaultHidden = true,
        note = "Not confirmed in Forever. Hidden by default.",
    },
}

-- Test stand-in: a buff a Warrior can produce at will, so the aura-detection
-- and sync paths can be exercised for real before any world buff exists.
-- Turned on with /rhorn standin on. Shared over party/raid only, flagged as a test.
ns.STANDIN = {
    key = "battleshout",
    name = "Battle Shout",
    label = "Battle Shout (stand-in)",
    faction = "Both",
    kind = "drop",
    testOnly = true,
    duration = 120,
    cooldown = nil,
    dedupeWindow = 20,
    spellIds = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 },
    auraNames = { "Battle Shout" },
    triggers = {},
    verified = false,
    note = "Test stand-in. Cast Battle Shout to fire the aura detector; the real duration is read from the aura.",
}

---------------------------------------------------------------------------
-- Index
---------------------------------------------------------------------------

ns.buffList = {}
ns.buffByKey = {}
ns.buffBySpell = {}
ns.buffByName = {}

local function lowerTrim(s)
    return ns.Trim(string.lower(s))
end

-- Returns a list of problems with a buff definition (empty when fine).
function ns.ValidateBuff(b)
    local problems = {}
    if type(b.key) ~= "string" or not string.match(b.key, "^[%w_]+$") or #b.key > 32 then
        problems[#problems + 1] = "bad key"
    end
    if type(b.name) ~= "string" then
        problems[#problems + 1] = "missing name"
    end
    if b.kind ~= "drop" and b.kind ~= "personal" then
        problems[#problems + 1] = "kind must be drop or personal"
    end
    if type(b.duration) ~= "number" or b.duration <= 0 then
        problems[#problems + 1] = "bad duration"
    end
    if b.cooldown ~= nil and (type(b.cooldown) ~= "number" or b.cooldown < 0) then
        problems[#problems + 1] = "bad cooldown"
    end
    if b.faction ~= "Horde" and b.faction ~= "Alliance" and b.faction ~= "Both" then
        problems[#problems + 1] = "faction must be Horde, Alliance or Both"
    end
    for _, t in ipairs(b.triggers or {}) do
        if type(t.npc) ~= "table" or #t.npc == 0 then
            problems[#problems + 1] = "trigger without npc"
        end
        if type(t.all) ~= "table" or #t.all == 0 then
            problems[#problems + 1] = "trigger without fragments"
        end
        if t.delay ~= nil and (type(t.delay) ~= "number" or t.delay < 0 or t.delay > 120) then
            problems[#problems + 1] = "trigger delay must be 0-120"
        end
    end
    return problems
end

local function addBuff(b, index)
    local problems = ns.ValidateBuff(b)
    if #problems > 0 then
        ns.Print("ignoring buff '%s': %s", tostring(b.key), table.concat(problems, ", "))
        return
    end
    if index.byKey[b.key] then
        ns.Print("ignoring duplicate buff key '%s'", b.key)
        return
    end
    index.list[#index.list + 1] = b
    index.byKey[b.key] = b
    for _, id in ipairs(b.spellIds or {}) do
        -- first definition wins for shared IDs (both Onyxia entries use 22888);
        -- the faction filter below resolves which one the player meant
        local existing = index.bySpell[id]
        if not existing then
            index.bySpell[id] = { b }
        else
            existing[#existing + 1] = b
        end
    end
    for _, n in ipairs(b.auraNames or {}) do
        local k = lowerTrim(n)
        local existing = index.byName[k]
        if not existing then
            index.byName[k] = { b }
        else
            existing[#existing + 1] = b
        end
    end
    -- precompute normalized trigger data for the matcher
    for _, t in ipairs(b.triggers or {}) do
        t._npc = {}
        for _, n in ipairs(t.npc or {}) do
            t._npc[#t._npc + 1] = lowerTrim(n)
        end
        t._all = {}
        for _, frag in ipairs(t.all or {}) do
            t._all[#t._all + 1] = ns.Matcher.Normalize(frag)
        end
        t._any = nil
        if t.any and #t.any > 0 then
            t._any = {}
            for _, frag in ipairs(t.any) do
                t._any[#t._any + 1] = ns.Matcher.Normalize(frag)
            end
        end
        t._zones = nil
        if t.zones and #t.zones > 0 then
            t._zones = {}
            for _, z in ipairs(t.zones) do
                t._zones[lowerTrim(z)] = true
            end
        end
        t._chat = string.upper(t.chat or "YELL")
    end
end

function ns.BuildBuffIndex()
    local index = { list = {}, byKey = {}, bySpell = {}, byName = {} }
    for _, b in ipairs(ns.BUFFS) do
        addBuff(b, index)
    end
    if ns.db and ns.db.settings.standin then
        addBuff(ns.STANDIN, index)
    end
    ns.buffList = index.list
    ns.buffByKey = index.byKey
    ns.buffBySpell = index.bySpell
    ns.buffByName = index.byName
    ns.Fire("BUFFS_CHANGED")
end

function ns.GetBuff(key)
    if type(key) ~= "string" then
        return nil
    end
    return ns.buffByKey[key]
end

-- Picks the best buff for an aura when several share an ID/name: prefer the
-- player's own faction, then "Both", then whatever is left.
function ns.ResolveAuraBuff(candidates)
    if not candidates or #candidates == 0 then
        return nil
    end
    if #candidates == 1 then
        return candidates[1]
    end
    local faction = ns.PlayerFaction()
    for _, b in ipairs(candidates) do
        if b.faction == faction then
            return b
        end
    end
    for _, b in ipairs(candidates) do
        if b.faction == "Both" then
            return b
        end
    end
    return candidates[1]
end

function ns.IsBuffVisible(b, faction)
    local override = ns.db and ns.db.settings.visibility[b.key]
    if override == false then
        return false
    end
    if override ~= true and b.defaultHidden then
        return false
    end
    if ns.db and ns.db.settings.allFactions then
        return true
    end
    faction = faction or ns.PlayerFaction()
    if b.faction ~= "Both" and faction and b.faction ~= faction then
        return false
    end
    return true
end

ns.On("INIT", function()
    ns.BuildBuffIndex()
end)

ns.On("SETTING_CHANGED", function(key)
    if key == "standin" then
        ns.BuildBuffIndex()
    end
end)
