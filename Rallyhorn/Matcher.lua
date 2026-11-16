-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- Matcher: decides whether an NPC chat line is one of the buff triggers in
-- Data.lua. Matching is by NPC name plus short whole-word fragments, so a
-- reworded yell only needs a data edit, never a code change.

local ADDON_NAME, ns = ...

local Matcher = {}
ns.Matcher = Matcher

-- Lowercase, strip UI escape codes, turn every run of non-letters/digits into
-- one space, and pad with spaces so " fragment " finds whole words only.
-- Bytes 128-255 count as letters so accented names survive.
function Matcher.Normalize(text)
    if type(text) ~= "string" then
        return " "
    end
    local s = string.lower(text)
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "|t.-|t", " ")
    s = string.gsub(s, "|h", " ")
    s = string.gsub(s, "[^%w\128-\255]+", " ")
    s = ns.Trim(s)
    return " " .. s .. " "
end

local function containsAll(haystack, fragments)
    for i = 1, #fragments do
        if not string.find(haystack, fragments[i], 1, true) then
            return false
        end
    end
    return true
end

local function containsAny(haystack, fragments)
    for i = 1, #fragments do
        if string.find(haystack, fragments[i], 1, true) then
            return true
        end
    end
    return false
end

local function npcMatches(trigger, npcLower)
    for i = 1, #trigger._npc do
        if trigger._npc[i] == npcLower then
            return true
        end
    end
    return false
end

-- chat: "YELL" or "SAY". zone may be nil (unknown zones never block a match).
-- Returns a list of { buff = <buff>, trigger = <trigger> }, at most one per buff.
function Matcher.Match(npc, text, zone, chat, buffList)
    local results = {}
    npc = ns.SafeString(npc)
    text = ns.SafeString(text)
    if not npc or not text then
        return results
    end
    chat = chat or "YELL"
    local npcLower = ns.Trim(string.lower(npc))
    local normalized = Matcher.Normalize(text)
    local zoneLower = ns.SafeString(zone) and ns.Trim(string.lower(zone)) or nil

    for _, buff in ipairs(buffList or ns.buffList) do
        local best
        for _, trigger in ipairs(buff.triggers or {}) do
            if trigger._npc
                and (trigger._chat == "ANY" or trigger._chat == chat)
                and npcMatches(trigger, npcLower)
                and (not trigger._zones or not zoneLower or trigger._zones[zoneLower])
                and containsAll(normalized, trigger._all)
                and (not trigger._any or containsAny(normalized, trigger._any)) then
                -- a line that applies the buff beats a heads-up line
                if not best or (best.stage == "announce" and trigger.stage ~= "announce") then
                    best = trigger
                end
                if trigger.stage ~= "announce" then
                    break
                end
            end
        end
        if best then
            results[#results + 1] = { buff = buff, trigger = best }
        end
    end
    return results
end

-- Builds a chat line that satisfies a trigger; used by /rhorn testyell.
function Matcher.SampleLine(trigger)
    local words = {}
    for _, frag in ipairs(trigger.all or {}) do
        words[#words + 1] = frag
    end
    if trigger.any and trigger.any[1] then
        words[#words + 1] = trigger.any[1]
    end
    return "(test) " .. table.concat(words, " ... ") .. "!", trigger.npc and trigger.npc[1]
end
