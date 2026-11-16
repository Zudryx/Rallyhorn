-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- Detect: turns game events into Engine:RecordDrop() calls.
--   1. NPC yells/says matched against the triggers in Data.lua.
--   2. Fallback: the player's own helpful auras, scanned only out of combat
--      (aura contents are hidden in combat on the Midnight engine).

local ADDON_NAME, ns = ...

local Detect = {}
ns.Detect = Detect

Detect.SCAN_DELAY = 0.3
Detect.MAX_AURAS = 255     -- the modern engine has no 40-buff cap; stop at the first empty slot
Detect.FRESH_WINDOW = 120  -- a world buff applied this recently counts as a drop we saw
Detect.DURATION_TOLERANCE = 0.05

-- event: CHAT_MSG_MONSTER_YELL or CHAT_MSG_MONSTER_SAY. Returns the matches.
-- isTest: set by /rhorn testyell so the fake drop is recorded (and never shared) as a test.
function Detect:OnMonsterChat(event, text, npc, isTest)
    local chat = (event == "CHAT_MSG_MONSTER_SAY") and "SAY" or "YELL"
    local zone = ns.ZoneText()
    local matches = {}
    local safeText, safeNpc = ns.SafeString(text), ns.SafeString(npc)
    if safeText and safeNpc then
        matches = ns.Matcher.Match(safeNpc, safeText, zone, chat, ns.buffList)
    end
    if not isTest then
        ns.Capture:LogChat(chat, npc, text, zone, matches)
    end
    local now = ns.Now()
    for _, m in ipairs(matches) do
        local source = (m.trigger.stage == "announce") and "announce" or "yell"
        if isTest then
            source = "test"
        end
        local ok, reason = ns.Engine:RecordDrop(m.buff.key, now + (m.trigger.delay or 0), source, safeNpc)
        ns.Debug("%s matched %s (%s): %s", safeNpc, m.buff.key, source, tostring(reason))
    end
    return matches
end

---------------------------------------------------------------------------
-- Aura fallback
---------------------------------------------------------------------------

function Detect:FindBuffForAura(spellId, name)
    local candidates = spellId and ns.buffBySpell[spellId]
    if not candidates and name then
        candidates = ns.buffByName[ns.Trim(string.lower(name))]
    end
    return ns.ResolveAuraBuff(candidates)
end

-- aura: an AuraData table. now: server epoch; gameNow: GetTime().
function Detect:ProcessAura(aura, now, gameNow)
    local spellId = ns.SafeNumber(aura.spellId)
    local name = ns.SafeString(aura.name)
    local duration = ns.SafeNumber(aura.duration)
    local expires = ns.SafeNumber(aura.expirationTime)
    ns.Capture:LogAura(spellId, name, duration)

    local buff = self:FindBuffForAura(spellId, name)
    if not buff then
        return nil
    end
    if not duration or not expires or duration <= 0 or expires <= 0 then
        return nil -- no timing information: cannot tell when it landed
    end
    local appliedAgo = gameNow - (expires - duration)
    if appliedAgo < -5 then
        return nil
    end
    local ts = now - appliedAgo
    if buff.kind == "drop" and appliedAgo > self.FRESH_WINDOW then
        -- An old world buff (e.g. after logging in) only refines a drop we
        -- already know about. If Forever pauses world buffs inside instances,
        -- expiration minus duration is no longer the drop time, so it must
        -- never start a new, shared timer.
        local current = ns.Engine:GetRecord(buff.key)
        if not current or math.abs(current.ts - ts) > ns.Engine:Window(buff) then
            return buff, false, "stale-aura"
        end
    end
    -- A world buff whose length does not match the table may be a restored or
    -- re-applied buff rather than a fresh drop: track it locally, never share it.
    local noShare = buff.kind == "drop" and not buff.testOnly
        and math.abs(duration - buff.duration) > buff.duration * self.DURATION_TOLERANCE
    local ok, reason = ns.Engine:RecordDrop(buff.key, ts, "aura", ns.PlayerName(),
        { duration = duration, noShare = noShare })
    return buff, ok, reason
end

function Detect:ScanAuras()
    if ns.InCombat() then
        self.pendingScan = true
        return false
    end
    self.pendingScan = false
    local getter = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getter then
        return false
    end
    local now, gameNow = ns.Now(), ns.GameTime()
    for i = 1, self.MAX_AURAS do
        local ok, aura = pcall(getter, "player", i, "HELPFUL")
        if not ok or ns.IsSecret(aura) or type(aura) ~= "table" then
            break
        end
        local processed, err = pcall(self.ProcessAura, self, aura, now, gameNow)
        if not processed then
            ns.Debug("aura %d skipped: %s", i, tostring(err))
        end
    end
    return true
end

function Detect:RequestScan()
    if self.scanQueued then
        return
    end
    self.scanQueued = true
    if not ns.After(self.SCAN_DELAY, function()
        Detect.scanQueued = false
        Detect:ScanAuras()
    end) then
        self.scanQueued = false
        self:ScanAuras()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function onMonsterChat(event, text, npc)
    Detect:OnMonsterChat(event, text, npc)
end

ns.RegisterEvent("CHAT_MSG_MONSTER_YELL", onMonsterChat)
ns.RegisterEvent("CHAT_MSG_MONSTER_SAY", onMonsterChat)

ns.RegisterUnitEvent("UNIT_AURA", "player", function(_, unit)
    if ns.SafeString(unit) == "player" then
        Detect:RequestScan()
    end
end)

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if Detect.pendingScan then
        Detect:RequestScan()
    end
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ns.After(3, function()
        Detect:RequestScan()
    end)
end)
