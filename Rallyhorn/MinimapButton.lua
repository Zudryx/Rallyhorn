-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- MinimapButton: Rallyhorn's own button on the edge of the minimap. It needs
-- no other addon or library.
--   Left-click: show/hide the timer window. Right-click: settings.
--   Drag: move it around the minimap. Hide it with /rhorn minimap off.

local ADDON_NAME, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

MinimapButton.DEFAULT_ANGLE = 225 -- degrees, 0 = right of the minimap, counter-clockwise

-- Rallyhorn's own logo, in the addon folder (follows the folder name).
local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Icon"
local atan2 = math.atan2 or math.atan

local function offsetFor(angle)
    local radius = 80
    local ok, width = pcall(Minimap.GetWidth, Minimap)
    width = ok and ns.SafeNumber(width)
    if width and width > 0 then
        radius = width / 2 + 10
    end
    local rad = math.rad(angle)
    return math.cos(rad) * radius, math.sin(rad) * radius
end

function MinimapButton:UpdatePosition()
    local button = self.button
    if not button then
        return
    end
    local angle = tonumber(ns.db.settings.minimapAngle) or self.DEFAULT_ANGLE
    local x, y = offsetFor(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging: put the button where the cursor points, on the minimap's edge.
function MinimapButton:FollowCursor()
    local okCenter, mx, my = pcall(Minimap.GetCenter, Minimap)
    local okScale, scale = pcall(Minimap.GetEffectiveScale, Minimap)
    local okCursor, px, py = pcall(GetCursorPosition)
    if not (okCenter and okScale and okCursor) then
        return
    end
    mx, my, scale = ns.SafeNumber(mx), ns.SafeNumber(my), ns.SafeNumber(scale)
    px, py = ns.SafeNumber(px), ns.SafeNumber(py)
    if not (mx and my and scale and px and py) or scale <= 0 then
        return
    end
    px, py = px / scale, py / scale
    local angle = math.deg(atan2(py - my, px - mx)) % 360
    ns.db.settings.minimapAngle = math.floor(angle + 0.5) % 360
    self:UpdatePosition()
end

function MinimapButton:ShowTooltip(owner)
    if not GameTooltip then
        return
    end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.TITLE)
        GameTooltip:AddLine("Left-click: show or hide the timers", 1, 1, 1)
        GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
end

function MinimapButton:Create()
    if self.button then
        return self.button
    end
    if not _G.Minimap then
        return nil
    end
    local ok, button = pcall(CreateFrame, "Button", ADDON_NAME .. "MinimapButton", Minimap)
    if not ok or not button then
        ns.Debug("minimap button unavailable: %s", tostring(button))
        return nil
    end
    self.button = button
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0, 1, 0, 1)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.Options:Open()
        else
            ns.UI:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            MinimapButton:FollowCursor()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        MinimapButton:FollowCursor()
    end)
    button:SetScript("OnEnter", function(self)
        MinimapButton:ShowTooltip(self)
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    self:UpdatePosition()
    self:ApplySettings()
    return button
end

function MinimapButton:ApplySettings()
    if not self.button then
        return
    end
    if ns.db.settings.minimap then
        self.button:Show()
    else
        self.button:Hide()
    end
end

function MinimapButton:ResetPosition()
    ns.db.settings.minimapAngle = self.DEFAULT_ANGLE
    self:UpdatePosition()
end

ns.On("INIT", function()
    MinimapButton:Create()
end)

ns.On("SETTING_CHANGED", function(key)
    if key == "minimap" then
        MinimapButton:ApplySettings()
    end
end)
