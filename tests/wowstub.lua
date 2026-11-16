-- Minimal stand-ins for the WoW API, enough to load and drive the addon
-- outside the game. Runs under Lua 5.3 (texlua); WoW itself uses Lua 5.1.

unpack = unpack or table.unpack
date = os.date
time = os.time

FAKE = {}
SENT = {}
PRINTS = {}
ERRORS = {}
SOUNDS = {}
TIMERS = {}
FRAMES = {}
OPENED_SETTINGS = {}

function resetFake()
    FAKE = {
        server = 1800000000,      -- server epoch seconds
        game = 5000,              -- GetTime()
        name = "Aldric Stone",    -- Forever two-part name
        realm = "Forever",
        faction = "Horde",
        zone = "Orgrimmar",
        subzone = "",
        inInstance = false,
        instanceType = "none",
        combat = false,
        guild = true,
        group = false,
        raid = false,
        auras = {},
        sendResult = 0,
    }
    SENT, PRINTS, ERRORS, SOUNDS, TIMERS, FRAMES, OPENED_SETTINGS = {}, {}, {}, {}, {}, {}, {}
end
resetFake()

-- secret values: tables with a marker; touching them like a string throws
SECRET_MT = {
    __index = function() error("touched a secret value (index)") end,
    __concat = function() error("touched a secret value (concat)") end,
    __lt = function() error("touched a secret value (compare)") end,
    __le = function() error("touched a secret value (compare)") end,
    __len = function() error("touched a secret value (len)") end,
}
function makeSecret()
    return setmetatable({ __secret = true }, SECRET_MT)
end
function issecretvalue(v)
    return type(v) == "table" and rawget(v, "__secret") == true
end

---------------------------------------------------------------------------
-- timers & clock
---------------------------------------------------------------------------

C_Timer = {
    After = function(delay, fn)
        TIMERS[#TIMERS + 1] = { due = FAKE.game + delay, fn = fn }
    end,
}

function runTimers()
    local guard = 0
    while true do
        guard = guard + 1
        assert(guard < 10000, "timer loop")
        local idx, best
        for i, t in ipairs(TIMERS) do
            if t.due <= FAKE.game and (not best or t.due < best.due) then
                idx, best = i, t
            end
        end
        if not idx then
            return
        end
        table.remove(TIMERS, idx)
        best.fn()
    end
end

-- advance both clocks, running timers in between (1 s steps)
function advance(seconds)
    local steps = math.ceil(seconds)
    for _ = 1, steps do
        local step = math.min(1, seconds)
        seconds = seconds - step
        FAKE.game = FAKE.game + step
        FAKE.server = FAKE.server + step
        runTimers()
    end
end

function GetServerTime() return FAKE.server end
function GetTime() return FAKE.game end

---------------------------------------------------------------------------
-- frames
---------------------------------------------------------------------------

local Methods = {}
local FrameMT = { __index = Methods }

function Methods:RegisterEvent(event) self.events[event] = true end
function Methods:RegisterUnitEvent(event, unit) self.events[event] = unit or true end
function Methods:UnregisterEvent(event) self.events[event] = nil end
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:GetScript(name) return self.scripts[name] end
function Methods:HookScript(name, fn) self.scripts[name] = fn end
function Methods:SetSize(w, h) self.width, self.height = w, h end
function Methods:SetWidth(w) self.width = w end
function Methods:SetHeight(h) self.height = h end
function Methods:GetHeight() return self.height end
function Methods:SetFrameStrata() end
function Methods:SetClampedToScreen() end
function Methods:SetMovable() end
function Methods:EnableMouse() end
function Methods:RegisterForDrag() end
function Methods:SetBackdrop() end
function Methods:SetBackdropColor() end
function Methods:SetBackdropBorderColor() end
function Methods:SetPoint(...) self.point = { ... } end
function Methods:ClearAllPoints() self.point = nil end
function Methods:GetPoint()
    if not self.point then return nil end
    local p = self.point
    -- SetPoint(point, relativeTo, relativePoint, x, y) or SetPoint(point, x, y)
    if type(p[2]) == "number" then
        return p[1], UIParent, p[1], p[2], p[3]
    end
    return p[1], p[2], p[3], p[4] or 0, p[5] or 0
end
function Methods:SetText(t) self.text = t end
function Methods:GetText() return self.text end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:IsShown() return self.shown end
function Methods:SetShown(v) self.shown = v and true or false end
function Methods:StartMoving() self.movingNow = true end
function Methods:StopMovingOrSizing() self.movingNow = false end
function Methods:SetScale(s) self.scale = s end
function Methods:SetJustifyH() end
function Methods:SetAllPoints() end
function Methods:SetColorTexture() end
function Methods:SetChecked(v) self.checked = v end
function Methods:GetChecked() return self.checked end
function Methods:CreateFontString() return newRegion() end
function Methods:SetFrameLevel() end
function Methods:RegisterForClicks() end
function Methods:SetHighlightTexture() end
function Methods:SetTexture(t) self.texture = t end
function Methods:SetTexCoord() end
function Methods:GetWidth() return self.width end
function Methods:GetCenter() return self.centerX, self.centerY end
function Methods:GetEffectiveScale() return self.effectiveScale or 1 end
function Methods:CreateTexture() return newRegion() end

function newRegion()
    return setmetatable({ events = {}, scripts = {}, shown = true }, FrameMT)
end

function CreateFrame(kind, name, parent, template)
    local f = newRegion()
    f.kind, f.name, f.parent, f.template = kind, name, parent, template
    if template == "UICheckButtonTemplate" then
        f.Text = newRegion()
    end
    FRAMES[#FRAMES + 1] = f
    if name then
        _G[name] = f
    end
    return f
end

UIParent = newRegion()
Minimap = newRegion()
Minimap.width, Minimap.centerX, Minimap.centerY, Minimap.effectiveScale = 140, 500, 400, 1
function GetCursorPosition() return FAKE.cursorX or 0, FAKE.cursorY or 0 end
BackdropTemplateMixin = {}

-- deliver an event to every frame registered for it
function fireEvent(event, ...)
    for _, f in ipairs(FRAMES) do
        if f.events[event] and f.scripts.OnEvent then
            f.scripts.OnEvent(f, event, ...)
        end
    end
end

DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, text) PRINTS[#PRINTS + 1] = text end,
}

GameTooltip = newRegion()
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:AddLine(t) self.lines = self.lines or {}; self.lines[#self.lines + 1] = t end
function GameTooltip:AddDoubleLine(a, b) self.lines = self.lines or {}; self.lines[#self.lines + 1] = a .. ": " .. b end

---------------------------------------------------------------------------
-- game API
---------------------------------------------------------------------------

C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "0.1.1" end end }
function GetBuildInfo() return "1.60.1", "70338", "Nov 1 2026", 16001 end
function GetNormalizedRealmName() return FAKE.realm end
function UnitName(unit) if unit == "player" then return FAKE.name, nil end end
function UnitFullName(unit) if unit == "player" then return FAKE.name, FAKE.realm end end
function GetUnitName(unit) if unit == "player" then return FAKE.name end end
function UnitFactionGroup() return FAKE.faction, FAKE.faction end
function IsInInstance() return FAKE.inInstance, FAKE.instanceType end
function InCombatLockdown() return FAKE.combat end
function UnitAffectingCombat() return FAKE.combat end
function GetRealZoneText() return FAKE.zone end
function GetZoneText() return FAKE.zone end
function GetSubZoneText() return FAKE.subzone end
function IsInGuild() return FAKE.guild end
function IsInGroup() return FAKE.group or FAKE.raid end
function IsInRaid() return FAKE.raid end
LE_PARTY_CATEGORY_HOME = 1

SOUNDKIT = { RAID_WARNING = 8959 }
function PlaySound(kit) SOUNDS[#SOUNDS + 1] = kit end

function geterrorhandler()
    return function(err)
        ERRORS[#ERRORS + 1] = tostring(err)
        io.stderr:write("ADDON ERROR: " .. tostring(err) .. "\n")
    end
end

Enum = {
    SendAddonMessageResult = {
        Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
        InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7,
        ChannelThrottle = 8, GeneralError = 9, NotInGuild = 10, AddOnMessageLockdown = 11,
        TargetOffline = 12,
    },
}

C_ChatInfo = {
    prefixes = {},
    RegisterAddonMessagePrefix = function(prefix)
        assert(#prefix <= 16, "prefix too long")
        C_ChatInfo.prefixes[prefix] = true
        return true
    end,
    SendAddonMessage = function(prefix, text, channel)
        assert(C_ChatInfo.prefixes[prefix], "prefix not registered")
        assert(#text <= 255, "message too long: " .. #text)
        if FAKE.sendResult == 0 then
            SENT[#SENT + 1] = { prefix = prefix, text = text, channel = channel, at = FAKE.game }
        end
        return FAKE.sendResult
    end,
}

C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        if unit ~= "player" or filter ~= "HELPFUL" then return nil end
        return FAKE.auras[index]
    end,
}

Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        return { ID = 42, name = name, GetID = function() return 42 end }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) OPENED_SETTINGS[#OPENED_SETTINGS + 1] = id end,
}

SlashCmdList = {}

---------------------------------------------------------------------------
-- addon loader
---------------------------------------------------------------------------

ADDON_DIR = ADDON_DIR or "Rallyhorn"

function tocFiles()
    local files = {}
    for line in io.lines(ADDON_DIR .. "/Rallyhorn.toc") do
        if line:match("%.lua%s*$") and not line:match("^#") then
            files[#files + 1] = line:match("^%s*(.-)%s*$")
        end
    end
    return files
end

-- Fresh game session: new namespace, optional saved variables.
function boot(opts)
    opts = opts or {}
    resetFake()
    for k, v in pairs(opts.fake or {}) do
        FAKE[k] = v
    end
    C_ChatInfo.prefixes = {}
    RallyhornDB = opts.db
    Rallyhorn = nil
    local ns = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(ADDON_DIR .. "/" .. file))
        chunk("Rallyhorn", ns)
    end
    fireEvent("ADDON_LOADED", "Rallyhorn")
    fireEvent("PLAYER_LOGIN")
    fireEvent("PLAYER_ENTERING_WORLD", true, false)
    if not opts.keepTimers then
        advance(20) -- let the login query go out and the first aura scan run
        SENT = {}
        PRINTS = {}
    end
    return ns
end

function slash(text)
    SlashCmdList["RALLYHORN"](text)
end

function printed(pattern)
    for _, line in ipairs(PRINTS) do
        if line:find(pattern) then
            return line
        end
    end
    return nil
end
