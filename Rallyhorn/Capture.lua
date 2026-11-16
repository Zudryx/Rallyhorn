-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- Capture mode: records every NPC yell/say (NPC, text, zone, time) and every
-- newly seen helpful aura on the player into the saved variables, so the real
-- Forever yell lines and spell IDs can be collected and pasted into Data.lua.
--
-- The log is in WTF\Account\<ACCOUNT>\SavedVariables\Rallyhorn.lua (written
-- on logout or /reload) under RallyhornDB.capture.

local ADDON_NAME, ns = ...

local Capture = {}
ns.Capture = Capture

Capture.MAX_CHAT = 300
Capture.MAX_AURAS = 200
Capture.MAX_TEXT = 300
Capture.DEDUPE_SCAN = 50   -- how far back to look for an identical line

function Capture:Enabled()
    return ns.db ~= nil and ns.db.capture.enabled == true
end

local function describe(value)
    if ns.IsSecret(value) then
        return "<secret>", true
    end
    if type(value) == "string" then
        return value, false
    end
    if value == nil then
        return "?", false
    end
    return tostring(value), false
end

function Capture:LogChat(chat, npc, text, zone, matches)
    if not self:Enabled() then
        return
    end
    local log = ns.db.capture.chat
    local npcText, npcSecret = describe(npc)
    local lineText, textSecret = describe(text)
    if #lineText > self.MAX_TEXT then
        lineText = string.sub(lineText, 1, self.MAX_TEXT)
    end
    local now = ns.Now()

    for i = #log, math.max(1, #log - self.DEDUPE_SCAN), -1 do
        local e = log[i]
        if e.event == chat and e.npc == npcText and e.text == lineText then
            e.count = (e.count or 1) + 1
            e.lastSeen = ns.FormatClock(now, true)
            return e
        end
    end

    local matched
    if matches and #matches > 0 then
        local keys = {}
        for _, m in ipairs(matches) do
            keys[#keys + 1] = m.buff.key
        end
        matched = table.concat(keys, ",")
    end

    local entry = {
        when = ns.FormatClock(now, true),
        time = now,
        event = chat,
        npc = npcText,
        text = lineText,
        zone = zone or "?",
        subzone = ns.SubZoneText(),
        secret = (npcSecret or textSecret) or nil,
        matched = matched,
        count = 1,
    }
    log[#log + 1] = entry
    while #log > self.MAX_CHAT do
        table.remove(log, 1)
    end

    if chat == "YELL" then
        ns.Print("|cff66ccff[capture]|r %s yells: %s%s", npcText, lineText,
            matched and ("  |cff20ff20-> " .. matched .. "|r") or "")
    end
    return entry
end

-- Called for every helpful aura seen on the player while capture is on.
function Capture:LogAura(spellId, name, duration)
    if not self:Enabled() then
        return
    end
    local id = spellId or (name and ("name:" .. name))
    if not id then
        return
    end
    local c = ns.db.capture
    local now = ns.Now()
    local existing = c.auras[id]
    if existing then
        existing.lastSeen = ns.FormatClock(now, true)
        return existing
    end
    if (c.auraCount or 0) >= self.MAX_AURAS then
        return
    end
    local entry = {
        spellId = spellId,
        name = name or "?",
        duration = duration,
        zone = ns.ZoneText() or "?",
        firstSeen = ns.FormatClock(now, true),
        time = now,
    }
    c.auras[id] = entry
    c.auraCount = (c.auraCount or 0) + 1
    ns.Print("|cff66ccff[capture]|r new aura: %s (spell ID %s, %s)", entry.name, tostring(spellId or "?"),
        duration and duration > 0 and ns.FormatDuration(duration) or "no duration")
    return entry
end

function Capture:Clear()
    local c = ns.db.capture
    c.chat = {}
    c.auras = {}
    c.auraCount = 0
end

function Capture:Show(n)
    local log = ns.db.capture.chat
    n = math.max(1, math.min(tonumber(n) or 10, 50))
    if #log == 0 then
        ns.Print("capture log is empty.")
    end
    for i = math.max(1, #log - n + 1), #log do
        local e = log[i]
        ns.Print("%s %s [%s] %s: %s%s%s", e.when or "?", e.event or "?", e.zone or "?", e.npc or "?", e.text or "?",
            (e.count or 1) > 1 and (" (x" .. e.count .. ")") or "",
            e.matched and ("  -> " .. e.matched) or "")
    end
    ns.Print("%d chat lines and %d auras captured. Full log: SavedVariables\\%s.lua", #log,
        ns.db.capture.auraCount or 0, ADDON_NAME)
end

function Capture:Stats()
    local c = ns.db.capture
    ns.Print("capture is %s: %d/%d chat lines, %d/%d auras.", c.enabled and "|cff20ff20on|r" or "off",
        #c.chat, self.MAX_CHAT, c.auraCount or 0, self.MAX_AURAS)
end

ns.On("LOGIN", function()
    if Capture:Enabled() then
        ns.Print("capture mode is |cff20ff20on|r (%s capture off to stop).", ns.SLASH_COMMANDS[2])
    end
end)

ns.On("SETTING_CHANGED", function(key, value)
    if key == "capture" and value then
        -- log the auras we already have, so the list starts complete
        if ns.Detect then
            ns.Detect:RequestScan()
        end
    end
end)
