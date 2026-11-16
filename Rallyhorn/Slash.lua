-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- Slash commands: /rallyhorn or /rhorn. Type /rhorn help in game.

local ADDON_NAME, ns = ...

local Slash = {}
ns.Slash = Slash

local function onOff(value)
    return value and "|cff20ff20on|r" or "|cffff4040off|r"
end

-- "on"/"off"/"" -> true/false/nil
local function parseToggle(word)
    word = word and string.lower(word) or ""
    if word == "on" or word == "1" or word == "true" or word == "yes" then
        return true
    elseif word == "off" or word == "0" or word == "false" or word == "no" then
        return false
    end
    return nil
end

local function splitWords(text)
    local words = {}
    for w in string.gmatch(text or "", "%S+") do
        words[#words + 1] = w
    end
    return words
end

local function toggleSetting(key, word, label)
    local value = parseToggle(word)
    if value == nil and word and word ~= "" then
        ns.Print("%s is %s; use on or off.", label, onOff(ns.GetSetting(key)))
        return
    end
    if value == nil then
        value = not ns.GetSetting(key)
    end
    ns.SetSetting(key, value)
    ns.Print("%s %s.", label, onOff(value))
end

local function buffKeys()
    local keys = {}
    for _, b in ipairs(ns.buffList) do
        keys[#keys + 1] = b.key
    end
    return table.concat(keys, ", ")
end

local function requireBuff(key)
    local buff = ns.GetBuff(key and string.lower(key))
    if not buff then
        ns.Print("unknown buff '%s'. Known: %s", tostring(key), buffKeys())
    end
    return buff
end

local HELP = {
    "|cffffd100Window|r  (no args) toggle · show · hide · lock · unlock · reset · scale <0.5-2>",
    "|cffffd100Minimap|r  minimap on/off · minimap reset",
    "|cffffd100Timers|r  status · list · clear <key/all> · buff <key> show/hide · faction own/all",
    "|cffffd100Alerts|r  announce on/off · sound on/off",
    "|cffffd100Sharing|r  sync on/off · sync guild on/off · sync group on/off · sync query · sync status",
    "|cffffd100Testing|r  test <key> [minutesAgo] [share] · testyell <key> · standin on/off",
    "|cffffd100Capture|r  capture on/off · capture show [n] · capture stats · capture clear",
    "|cffffd100Other|r  options · debug on/off · version",
}

Slash.commands = {}
local C = Slash.commands

function C.help()
    ns.Print("v%s commands (%s or %s):", ns.VERSION, ns.SLASH_COMMANDS[1], ns.SLASH_COMMANDS[2])
    for _, line in ipairs(HELP) do
        ns.Print(line)
    end
end

function C.toggle()
    ns.UI:Toggle()
end

function C.show()
    ns.SetSetting("shown", true)
end

function C.hide()
    ns.SetSetting("shown", false)
end

function C.lock()
    ns.SetSetting("locked", true)
    ns.Print("window locked.")
end

function C.unlock()
    ns.SetSetting("locked", false)
    ns.Print("window unlocked; drag it by the title or any row.")
end

function C.reset()
    ns.UI:ResetPosition()
    ns.SetSetting("scale", 1)
    ns.SetSetting("shown", true)
    ns.Print("window position and scale reset.")
end

function C.scale(args)
    local value = tonumber(args[1])
    if not value or value < 0.5 or value > 2 then
        ns.Print("usage: scale <0.5-2>")
        return
    end
    ns.SetSetting("scale", value)
end

function C.minimap(args)
    local word = args[1] and string.lower(args[1]) or ""
    if word == "reset" then
        ns.SetSetting("minimap", true)
        ns.MinimapButton:ResetPosition()
        ns.Print("minimap button moved back to its default spot.")
        return
    end
    toggleSetting("minimap", word, "minimap button")
end

function C.status()
    local now = ns.Now()
    local any = false
    for _, buff in ipairs(ns.buffList) do
        if ns.IsBuffVisible(buff) then
            any = true
            local st = ns.Engine:GetStatus(buff.key, now)
            local status, detail = ns.UI.StatusText(st)
            ns.Print("%s: %s %s", buff.label, status, detail ~= "" and ("|cff888888" .. detail .. "|r") or "")
        end
    end
    if not any then
        ns.Print("no buffs visible (try %s faction all).", ns.SLASH_COMMANDS[2])
    end
end

function C.list()
    for _, buff in ipairs(ns.buffList) do
        ns.Print("%s |cff888888(%s, %s, %s%s%s)|r", buff.key, buff.label, buff.faction, buff.kind,
            buff.verified and "" or ", unverified", ns.IsBuffVisible(buff) and "" or ", hidden")
    end
end

function C.clear(args)
    local key = args[1] and string.lower(args[1])
    if key == "all" then
        ns.Engine:ClearAll()
        ns.Print("all timers cleared.")
        return
    end
    if not requireBuff(key) then
        return
    end
    if ns.Engine:Clear(key) then
        ns.Print("%s cleared.", key)
    else
        ns.Print("%s had no timer.", key)
    end
end

function C.buff(args)
    local buff = requireBuff(args[1])
    if not buff then
        return
    end
    local value = parseToggle(args[2] == "show" and "on" or args[2] == "hide" and "off" or args[2])
    if value == nil then
        ns.Print("usage: buff <key> show/hide")
        return
    end
    ns.db.settings.visibility[buff.key] = value
    ns.SetSetting("visibility", ns.db.settings.visibility)
    ns.Print("%s %s.", buff.key, value and "shown" or "hidden")
end

function C.faction(args)
    local word = args[1] and string.lower(args[1])
    if word ~= "own" and word ~= "all" then
        ns.Print("usage: faction own/all (now: %s)", ns.db.settings.allFactions and "all" or "own")
        return
    end
    ns.SetSetting("allFactions", word == "all")
    ns.Print("showing %s buffs.", word == "all" and "both factions'" or "your faction's")
end

function C.announce(args)
    toggleSetting("announce", args[1], "chat announcements")
end

function C.sound(args)
    toggleSetting("sound", args[1], "drop sound")
end

function C.sync(args)
    local sub = args[1] and string.lower(args[1]) or ""
    local s = ns.db.settings
    if sub == "guild" then
        toggleSetting("syncGuild", args[2], "guild sharing")
    elseif sub == "group" then
        toggleSetting("syncGroup", args[2], "party/raid sharing")
    elseif sub == "query" then
        local n = ns.Sync:Query(nil, true)
        ns.Print(n > 0 and "asked %d channel(s) for timers." or "nothing to ask (sharing off, no guild/group, or asked under a minute ago).", n)
    elseif sub == "status" then
        local canSend, why = ns.Sync:CanSend()
        local st = ns.Sync.stats
        ns.Print("sharing %s (guild %s, group %s). Can send now: %s%s.", onOff(s.sync), onOff(s.syncGuild),
            onOff(s.syncGroup), canSend and "yes" or "no", why and (" (" .. why .. ")") or "")
        ns.Print("sent %d, received %d, rejected %d, drops accepted %d, queued %d. Prefix: %s",
            st.sent, st.received, st.rejected, st.dropsAccepted, #ns.Sync.queue, ns.Sync.prefix or ns.SYNC_PREFIX)
    else
        toggleSetting("sync", sub, "timer sharing")
    end
end

-- /rhorn test <key> [minutesAgo] [share]
function C.test(args)
    local buff = requireBuff(args[1])
    if not buff then
        return
    end
    local minutes, share = 0, false
    for i = 2, #args do
        local word = string.lower(args[i])
        if word == "share" then
            share = true
        elseif tonumber(word) then
            minutes = tonumber(word)
        end
    end
    local ts = ns.Now() - math.floor(minutes * 60 + 0.5)
    local ok, reason = ns.Engine:RecordDrop(buff.key, ts, "test", ns.PlayerName(), { share = share })
    if ok then
        ns.Print("test drop for %s at %s%s.", buff.key, ns.FormatClock(ts),
            share and (buff.kind == "drop" and " (sharing with your party/raid)" or " (personal buffs are never shared)") or "")
    else
        ns.Print("test drop for %s not recorded: %s%s", buff.key, reason,
            reason == "duplicate" and (" (a timer within " .. ns.Engine:Window(buff) .. "s exists; " .. ns.SLASH_COMMANDS[2] .. " clear " .. buff.key .. " first)") or "")
    end
end

-- /rhorn testyell <key>: feeds a fake NPC yell through the real yell path.
function C.testyell(args)
    local buff = requireBuff(args[1])
    if not buff then
        return
    end
    local trigger
    for _, t in ipairs(buff.triggers or {}) do
        trigger = t
        if t.stage ~= "announce" then
            break
        end
    end
    if not trigger then
        ns.Print("%s has no yell triggers (it is detected from your auras).", buff.key)
        return
    end
    local text, npc = ns.Matcher.SampleLine(trigger)
    local event = trigger._chat == "SAY" and "CHAT_MSG_MONSTER_SAY" or "CHAT_MSG_MONSTER_YELL"
    local matches = ns.Detect:OnMonsterChat(event, text, npc, true)
    ns.Print("fake yell from %s: \"%s\" matched %d buff(s).", npc or "?", text, #matches)
end

function C.standin(args)
    toggleSetting("standin", args[1], "Battle Shout stand-in")
    if ns.db.settings.standin then
        ns.Print("cast Battle Shout out of combat; a 'battleshout' row appears in the window.")
    end
end

function C.capture(args)
    local sub = args[1] and string.lower(args[1]) or ""
    if sub == "show" then
        ns.Capture:Show(args[2])
    elseif sub == "stats" then
        ns.Capture:Stats()
    elseif sub == "clear" then
        ns.Capture:Clear()
        ns.Print("capture log cleared.")
    else
        toggleSetting("capture", sub, "capture mode")
        if ns.db.capture.enabled then
            ns.Print("logging NPC yells/says and new auras. The log is saved on logout or /reload.")
        end
    end
end

function C.options()
    ns.Options:Open()
end
C.config = C.options
C.settings = C.options

function C.debug(args)
    toggleSetting("debug", args[1], "debug output")
end

function C.version()
    local ok, _, _, _, interface = pcall(_G.GetBuildInfo)
    ns.Print("version %s, sync protocol %d, client interface %s.", ns.VERSION, ns.Sync.PROTOCOL,
        tostring(ok and ns.SafeNumber(interface) or "?"))
end

function Slash.Run(input)
    if not ns.db then
        ns.Print("still loading.")
        return
    end
    local words = splitWords(input)
    local command = words[1] and string.lower(words[1]) or "toggle"
    table.remove(words, 1)
    local handler = C[command]
    if not handler then
        ns.Print("unknown command '%s'.", command)
        C.help()
        return
    end
    handler(words)
end

for i, command in ipairs(ns.SLASH_COMMANDS) do
    _G["SLASH_" .. ns.SLASH_ID .. i] = command
end
SlashCmdList[ns.SLASH_ID] = function(input)
    ns.SafeRun(Slash.Run, input)
end
