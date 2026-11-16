-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- UI: a small movable, lockable window listing each tracked buff with its last
-- drop and when it can next drop, plus chat/sound alerts for new drops.
-- Plain (non-secure) frames only, so nothing here is affected by combat lockdown.

local ADDON_NAME, ns = ...

local UI = {}
ns.UI = UI

local WIDTH = 270
local ROW_HEIGHT = 30
local HEADER = 24
local PADDING = 8
local FRESH_ALERT = 120 -- only alert for drops that landed in the last 2 minutes (or are incoming)

local COLORS = {
    Horde = "|cffff6060",
    Alliance = "|cff6fa8ff",
    Both = "|cffffd100",
}

local SOURCE_TEXT = {
    yell = "heard",
    announce = "heard, est.",
    aura = "your buff",
    sync = "shared",
    test = "test",
    manual = "manual",
}

local function sourceLabel(record)
    local label = SOURCE_TEXT[record.source] or record.source or "?"
    if record.source == "aura" and record.heard then
        label = "heard + your buff"
    elseif record.source == "sync" and record.reporter then
        label = "via " .. record.reporter
    elseif record.source == "test" and record.reporter and not ns.IsSelf(record.reporter) then
        label = "test via " .. record.reporter
    end
    return label
end

function UI.StatusText(st)
    local fmt = ns.FormatDuration
    local buff = st.buff
    if st.state == "unknown" then
        return "|cff888888No data|r", ""
    end
    local record = st.record
    local verb = buff.kind == "personal" and "Gained " or "Dropped "
    local detail = verb .. ns.FormatClock(st.dropAt) .. " (" .. sourceLabel(record) .. ")"
    if st.state == "incoming" then
        return "|cffffd100Lands in " .. fmt(st.eta) .. "|r", detail
    elseif st.state == "active" then
        if st.readyAt then
            detail = detail .. " · ready " .. ns.FormatClock(st.readyAt)
        end
        return "|cff20ff20Up · " .. fmt(st.remaining) .. " left|r", detail
    elseif st.state == "cooldown" then
        return "|cffff9a2eReady in " .. fmt(st.readyIn) .. "|r", detail .. " · ready " .. ns.FormatClock(st.readyAt)
    elseif st.state == "ready" then
        return "|cff40c0ffCan drop now|r", detail
    end
    return "|cffaaaaaaGone · " .. fmt(st.since) .. " ago|r", detail
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function applyBackdrop(frame)
    if not frame.SetBackdrop then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.7)
        return
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.75)
    frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
end

function UI:Create()
    if self.frame then
        return self.frame
    end
    local template = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent, template)
    self.frame = f
    f:SetSize(WIDTH, HEADER + PADDING)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        UI:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        UI:StopMoving()
    end)
    applyBackdrop(f)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", PADDING, -7)
    f.title:SetText(ns.TITLE)

    f.lockText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.lockText:SetPoint("LEFT", f.title, "RIGHT", 6, 0)

    local ok, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
    if ok and close then
        close:SetSize(20, 20)
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function()
            ns.SetSetting("shown", false)
            ns.Print("window hidden. %s show brings it back.", ns.SLASH_COMMANDS[2])
        end)
        f.close = close
    end

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", PADDING, -HEADER - 2)
    f.empty:SetText("No buffs to show for your faction.")
    f.empty:Hide()

    f.rows = {}
    f.elapsed = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        f.elapsed = f.elapsed + elapsed
        if f.elapsed >= 1 then
            f.elapsed = 0
            UI:Refresh()
        end
    end)

    self:ApplySettings()
    self:Rebuild()
    return f
end

function UI:StartMoving()
    if self.frame and not ns.db.settings.locked then
        self.frame:StartMoving()
        self.moving = true
    end
end

function UI:StopMoving()
    if self.frame and self.moving then
        self.frame:StopMovingOrSizing()
        self.moving = false
        local point, _, relativePoint, x, y = self.frame:GetPoint(1)
        if point then
            ns.db.settings.point = { point, relativePoint, math.floor(x + 0.5), math.floor(y + 0.5) }
        end
    end
end

function UI:RestorePosition()
    local f = self.frame
    f:ClearAllPoints()
    local p = ns.db.settings.point
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -80, 120)
    end
end

function UI:ResetPosition()
    ns.db.settings.point = false
    if self.frame then
        self:RestorePosition()
    end
end

function UI:ApplySettings()
    local f = self.frame
    if not f then
        return
    end
    local s = ns.db.settings
    local scale = tonumber(s.scale) or 1
    if scale < 0.5 or scale > 2 then
        scale = 1
    end
    f:SetScale(scale)
    self:RestorePosition()
    f.lockText:SetText(s.locked and "(locked)" or "")
    if s.shown then
        f:Show()
    else
        f:Hide()
    end
end

function UI:GetRow(i)
    local f = self.frame
    local row = f.rows[i]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, f)
    row:SetSize(WIDTH - PADDING * 2, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, -HEADER - (i - 1) * ROW_HEIGHT)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", 0, -2)
    row.name:SetJustifyH("LEFT")
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("TOPRIGHT", 0, -2)
    row.status:SetJustifyH("RIGHT")
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", 0, -15)
    row.detail:SetPoint("TOPRIGHT", 0, -15)
    row.detail:SetJustifyH("LEFT")
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        UI:StartMoving()
    end)
    row:SetScript("OnDragStop", function()
        UI:StopMoving()
    end)
    row:SetScript("OnEnter", function(self)
        UI:ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    f.rows[i] = row
    return row
end

function UI:Rebuild()
    local f = self.frame
    if not f then
        return
    end
    local faction = ns.PlayerFaction()
    local visible = {}
    for _, buff in ipairs(ns.buffList) do
        if ns.IsBuffVisible(buff, faction) then
            visible[#visible + 1] = buff
        end
    end
    self.visible = visible
    for i, buff in ipairs(visible) do
        local row = self:GetRow(i)
        row.buff = buff
        local color = COLORS[buff.faction] or COLORS.Both
        row.name:SetText(color .. buff.label .. "|r" .. (buff.verified and "" or " |cff888888*|r"))
        row:Show()
    end
    for i = #visible + 1, #f.rows do
        f.rows[i]:Hide()
        f.rows[i].buff = nil
    end
    if #visible == 0 then
        f.empty:Show()
        f:SetHeight(HEADER + 20 + PADDING)
    else
        f.empty:Hide()
        f:SetHeight(HEADER + #visible * ROW_HEIGHT + PADDING)
    end
    self:Refresh()
end

function UI:Refresh()
    local f = self.frame
    if not f or not self.visible then
        return
    end
    local now = ns.Now()
    for i, buff in ipairs(self.visible) do
        local row = f.rows[i]
        local st = ns.Engine:GetStatus(buff.key, now)
        if row and st then
            local status, detail = UI.StatusText(st)
            row.status:SetText(status)
            row.detail:SetText(detail)
        end
    end
end

function UI:ShowTooltip(row)
    local buff = row.buff
    if not buff or not GameTooltip then
        return
    end
    pcall(function()
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        GameTooltip:AddLine(buff.name)
        GameTooltip:AddLine(buff.label .. " · " .. buff.faction .. " · " .. (buff.kind == "drop" and "world drop" or "personal"), 1, 1, 1)
        local cooldownText
        if buff.cooldown then
            cooldownText = "can drop every " .. ns.FormatDuration(buff.cooldown)
        else
            cooldownText = buff.cooldownText or "cooldown unknown"
        end
        GameTooltip:AddLine("Lasts " .. ns.FormatDuration(buff.duration) .. " · " .. cooldownText, 0.8, 0.8, 0.8, true)
        if not buff.verified then
            GameTooltip:AddLine("* Unverified: Classic Era values until confirmed in WoW Forever.", 1, 0.6, 0.2, true)
        end
        if buff.note then
            GameTooltip:AddLine(buff.note, 0.7, 0.7, 0.7, true)
        end
        local record = ns.Engine:GetRecord(buff.key)
        if record then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Last drop", ns.FormatClock(record.ts, true), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("Source", sourceLabel(record), 1, 0.82, 0, 1, 1, 1)
            if record.dur then
                GameTooltip:AddDoubleLine("Observed length", ns.FormatDuration(record.dur), 1, 0.82, 0, 1, 1, 1)
            end
            local history = ns.db.history[buff.key]
            if history and #history > 0 then
                GameTooltip:AddLine("Earlier: " .. ns.FormatClock(history[1].ts, true) ..
                    (#history > 1 and (" (+" .. (#history - 1) .. " more)") or ""), 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:Show()
    end)
end

function UI:Toggle()
    ns.SetSetting("shown", not ns.db.settings.shown)
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------

function UI:Alert(key, record, reason)
    if reason ~= "new" or not record then
        return
    end
    local buff = ns.GetBuff(key)
    if not buff or buff.kind ~= "drop" then
        return
    end
    local now = ns.Now()
    if record.ts < now - FRESH_ALERT then
        return -- learned about an old drop (e.g. on login): no fanfare
    end
    if not ns.IsBuffVisible(buff) and not buff.testOnly then
        return
    end
    if ns.db.settings.announce then
        local when
        if record.ts > now then
            when = "lands in " .. ns.FormatDuration(record.ts - now)
        else
            when = "dropped at " .. ns.FormatClock(record.ts)
        end
        ns.Print("%s%s|r %s (%s).", COLORS[buff.faction] or "", buff.label, when, sourceLabel(record))
    end
    if record.source ~= "aura" then
        ns.PlayAlert()
    end
end

ns.On("INIT", function()
    UI:Create()
end)

ns.On("LOGIN", function()
    UI:Rebuild() -- faction is known now
end)

ns.On("BUFFS_CHANGED", function()
    UI:Rebuild()
end)

ns.On("TIMER_CHANGED", function(key, record, reason)
    UI:Refresh()
    UI:Alert(key, record, reason)
end)

ns.On("SETTING_CHANGED", function(key)
    if key == "shown" or key == "locked" or key == "scale" then
        UI:ApplySettings()
    elseif key == "allFactions" or key == "visibility" then
        UI:Rebuild()
    end
end)
