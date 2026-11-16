-- Rallyhorn: world buff drop timers for WoW Forever.
-- Copyright (C) 2026 Zudryx
-- This program is free software: you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the Free Software
-- Foundation, either version 3 of the License, or (at your option) any later
-- version. See LICENSE and NOTICE.md (the Rallyhorn name and logo are excluded).
--
-- Core: namespace, safe wrappers around game APIs, events, saved variables.

local ADDON_NAME, ns = ...

-- The addon name lives in exactly one place: the folder/TOC name. Everything
-- else (saved variables, slash command, sync prefix, globals) derives from it.
ns.NAME = ADDON_NAME
ns.TITLE = ADDON_NAME
ns.DB_NAME = ADDON_NAME .. "DB"               -- must match ## SavedVariables in the TOC
ns.SLASH_ID = string.upper(ADDON_NAME)
ns.SLASH_COMMANDS = { "/" .. string.lower(ADDON_NAME), "/rhorn" }
ns.SYNC_PREFIX = string.sub(ADDON_NAME, 1, 16)  -- addon message prefixes max out at 16 chars
_G[ADDON_NAME] = ns                            -- one global, for debugging (/dump Rallyhorn)

local function readMetadata(field)
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if getter then
        local ok, value = pcall(getter, ADDON_NAME, field)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
    return nil
end

ns.VERSION = readMetadata("Version") or "0.1.1"

---------------------------------------------------------------------------
-- Secret-value guards
-- WoW Forever runs on the Midnight engine. Some values handed to addons are
-- "secret": type() works on them, but comparing, concatenating or doing math
-- with them throws. Everything read from the game goes through these.
---------------------------------------------------------------------------

function ns.IsSecret(value)
    local check = _G.issecretvalue
    if not check then
        return false
    end
    local ok, result = pcall(check, value)
    if not ok then
        return true -- if we cannot tell, assume the worst
    end
    return result == true
end

function ns.SafeString(value)
    if ns.IsSecret(value) or type(value) ~= "string" then
        return nil
    end
    return value
end

function ns.SafeNumber(value)
    if ns.IsSecret(value) or type(value) ~= "number" then
        return nil
    end
    if value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

-- Returns true, false, or nil when the value is secret/unknown.
function ns.SafeBool(value)
    if ns.IsSecret(value) then
        return nil
    end
    if value then
        return true
    end
    return false
end

-- Calls a game function and returns its first result only if it is readable.
local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    return pcall(fn, ...)
end
ns.SafeCall = safeCall

---------------------------------------------------------------------------
-- Time
---------------------------------------------------------------------------

-- Server epoch seconds. Everyone in a region shares the server clock, so sync
-- timestamps line up even if a player's PC clock is wrong.
function ns.Now()
    local ok, t = safeCall(_G.GetServerTime)
    t = ok and ns.SafeNumber(t)
    if t then
        return math.floor(t)
    end
    return math.floor(time())
end

-- Seconds since the client started (fractional). Used for throttles and aura math.
function ns.GameTime()
    local ok, t = safeCall(_G.GetTime)
    t = ok and ns.SafeNumber(t)
    return t or 0
end

function ns.After(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, function()
            ns.SafeRun(fn)
        end)
        return true
    end
    return false
end

function ns.FormatDuration(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    if seconds < 0 then
        seconds = 0
    end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%dh %02dm", h, m)
    elseif m > 0 then
        return string.format("%dm %02ds", m, s)
    end
    return string.format("%ds", s)
end

function ns.FormatClock(ts, withDate)
    if type(ts) ~= "number" then
        return "?"
    end
    local ok, text = pcall(date, withDate and "%Y-%m-%d %H:%M:%S" or "%H:%M", math.floor(ts))
    if ok and type(text) == "string" then
        return text
    end
    return tostring(math.floor(ts))
end

---------------------------------------------------------------------------
-- Names
-- Forever characters have two-part names ("First Last"), unique per region.
-- Keep the space, never split on it, and only strip a "-Realm" suffix when it
-- is our own realm (in case the client still appends one).
---------------------------------------------------------------------------

local function trim(s)
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end
ns.Trim = trim

function ns.MyRealm()
    local ok, realm = safeCall(_G.GetNormalizedRealmName)
    realm = ok and ns.SafeString(realm)
    if realm and realm ~= "" then
        return realm
    end
    return nil
end

function ns.NormalizeName(name)
    name = ns.SafeString(name)
    if not name then
        return nil
    end
    name = trim(name)
    if name == "" then
        return nil
    end
    local realm = ns.MyRealm()
    if realm then
        local suffix = "-" .. realm
        if #name > #suffix and string.lower(string.sub(name, -#suffix)) == string.lower(suffix) then
            name = string.sub(name, 1, #name - #suffix)
        end
    end
    return name
end

local selfNames
function ns.ResetSelfNames()
    selfNames = nil
end

local function collectSelfNames()
    local set = {}
    local function add(n)
        n = ns.NormalizeName(n)
        if n then
            set[string.lower(n)] = true
        end
    end
    local ok, name, realm = safeCall(_G.UnitName, "player")
    if ok then
        add(name)
        if ns.SafeString(name) and ns.SafeString(realm) and realm ~= "" then
            add(name .. "-" .. realm)
        end
    end
    ok, name, realm = safeCall(_G.UnitFullName, "player")
    if ok and ns.SafeString(name) then
        add(name)
        if ns.SafeString(realm) and realm ~= "" then
            add(name .. "-" .. realm)
        end
    end
    ok, name = safeCall(_G.GetUnitName, "player", true)
    if ok then
        add(name)
    end
    return set
end

function ns.IsSelf(name)
    name = ns.NormalizeName(name)
    if not name then
        return false
    end
    if not selfNames or not next(selfNames) then
        selfNames = collectSelfNames()
    end
    return selfNames[string.lower(name)] == true
end

function ns.PlayerName()
    local ok, name = safeCall(_G.UnitName, "player")
    return (ok and ns.SafeString(name)) or "player"
end

---------------------------------------------------------------------------
-- World state
---------------------------------------------------------------------------

function ns.InOpenWorld()
    if not _G.IsInInstance then
        return true
    end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok or ns.IsSecret(inInstance) or ns.IsSecret(instanceType) then
        return false
    end
    if inInstance then
        return false
    end
    if type(instanceType) == "string" and instanceType ~= "none" then
        return false
    end
    return true
end

function ns.InCombat()
    local ok, value = safeCall(_G.InCombatLockdown)
    if ok then
        local b = ns.SafeBool(value)
        if b == nil or b then
            return true
        end
    end
    ok, value = safeCall(_G.UnitAffectingCombat, "player")
    if ok then
        local b = ns.SafeBool(value)
        if b == nil or b then
            return true
        end
    end
    return false
end

function ns.ZoneText()
    local ok, zone = safeCall(_G.GetRealZoneText)
    zone = ok and ns.SafeString(zone)
    if not zone or zone == "" then
        ok, zone = safeCall(_G.GetZoneText)
        zone = ok and ns.SafeString(zone)
    end
    return zone or nil
end

function ns.SubZoneText()
    local ok, sub = safeCall(_G.GetSubZoneText)
    sub = ok and ns.SafeString(sub)
    if sub == "" then
        return nil
    end
    return sub or nil
end

function ns.PlayerFaction()
    local ok, faction = safeCall(_G.UnitFactionGroup, "player")
    return (ok and ns.SafeString(faction)) or nil
end

function ns.IsInGuild()
    local ok, value = safeCall(_G.IsInGuild)
    return ok and ns.SafeBool(value) == true
end

function ns.IsInGroup()
    local ok, value = safeCall(_G.IsInGroup, _G.LE_PARTY_CATEGORY_HOME)
    return ok and ns.SafeBool(value) == true
end

function ns.IsInRaid()
    local ok, value = safeCall(_G.IsInRaid, _G.LE_PARTY_CATEGORY_HOME)
    return ok and ns.SafeBool(value) == true
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

local CHAT_PREFIX = "|cffff9a2e" .. ADDON_NAME .. "|r: "

local function format(fmt, ...)
    if select("#", ...) > 0 then
        local ok, text = pcall(string.format, fmt, ...)
        if ok then
            return text
        end
    end
    return tostring(fmt)
end

function ns.Print(fmt, ...)
    local text = CHAT_PREFIX .. format(fmt, ...)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(text)
    else
        print(text)
    end
end

function ns.Debug(fmt, ...)
    if ns.db and ns.db.settings and ns.db.settings.debug then
        ns.Print("|cff888888[debug]|r " .. format(fmt, ...))
    end
end

function ns.PlayAlert()
    if not (ns.db and ns.db.settings.sound) then
        return
    end
    local kit = _G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING
    if kit and _G.PlaySound then
        pcall(PlaySound, kit, "Master")
    end
end

---------------------------------------------------------------------------
-- Error-safe runner and internal callbacks
---------------------------------------------------------------------------

function ns.SafeRun(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local handler = _G.geterrorhandler and geterrorhandler()
        if handler then
            handler(err)
        else
            print(err)
        end
    end
    return ok
end

local callbacks = {}

function ns.On(name, fn)
    local list = callbacks[name]
    if not list then
        list = {}
        callbacks[name] = list
    end
    list[#list + 1] = fn
end

function ns.Fire(name, ...)
    local list = callbacks[name]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeRun(list[i], ...)
    end
end

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}
ns.eventFrame = eventFrame

local function addHandler(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = fn
    return #list == 1
end

function ns.RegisterEvent(event, fn)
    if addHandler(event, fn) then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            ns.Debug("event %s is not available on this client", event)
        end
    end
end

function ns.RegisterUnitEvent(event, unit, fn)
    if addHandler(event, fn) then
        local ok = false
        if eventFrame.RegisterUnitEvent then
            ok = pcall(eventFrame.RegisterUnitEvent, eventFrame, event, unit)
        end
        if not ok then
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeRun(list[i], event, ...)
    end
end)

---------------------------------------------------------------------------
-- Saved variables (account-wide)
---------------------------------------------------------------------------

ns.DEFAULTS = {
    schema = 1,
    settings = {
        shown = true,
        locked = false,
        scale = 1,
        point = false,          -- { point, relativePoint, x, y } once moved
        minimap = true,         -- show the minimap button
        minimapAngle = 225,     -- its position around the minimap, in degrees
        sync = true,
        syncGuild = true,
        syncGroup = true,
        allFactions = false,
        announce = true,
        sound = true,
        standin = false,
        visibility = {},        -- [buffKey] = true/false overrides the buff's default
        debug = false,
    },
    timers = {},                -- [buffKey] = { ts, source, reporter, seen, dur }
    history = {},               -- [buffKey] = { { ts, source, reporter }, ... } newest first
    syncState = {
        lastQuery = {},         -- [channel] = server time of our last automatic query
    },
    capture = {
        enabled = false,
        chat = {},
        auras = {},
        auraCount = 0,
    },
}

local function mergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            mergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end
ns.MergeDefaults = mergeDefaults

function ns.InitDB()
    local db = _G[ns.DB_NAME]
    if type(db) ~= "table" then
        db = {}
        _G[ns.DB_NAME] = db
    end
    mergeDefaults(db, ns.DEFAULTS)
    ns.db = db
    return db
end

-- Central setter so the slash commands and the Settings panel behave the same.
function ns.SetSetting(key, value)
    if not ns.db then
        return
    end
    if key == "capture" then
        ns.db.capture.enabled = value and true or false
    else
        ns.db.settings[key] = value
    end
    ns.Fire("SETTING_CHANGED", key, value)
end

function ns.GetSetting(key)
    if not ns.db then
        return nil
    end
    if key == "capture" then
        return ns.db.capture.enabled
    end
    return ns.db.settings[key]
end

ns.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then
        return
    end
    ns.InitDB()
    ns.Fire("INIT")
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    ns.ResetSelfNames()
    ns.Fire("LOGIN")
end)
