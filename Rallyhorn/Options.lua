-- Rallyhorn - Copyright (C) 2026 Zudryx - GPL-3.0-or-later (see LICENSE, NOTICE.md)
--
-- Options: a page in the game's Settings > AddOns panel (when the Settings API
-- is available) and the addon compartment entry next to the minimap.
-- Everything here is also reachable with slash commands.

local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

Options.ITEMS = {
    { key = "shown", label = "Show the timer window" },
    { key = "locked", label = "Lock the window in place" },
    { key = "minimap", label = "Show the minimap button" },
    { key = "allFactions", label = "Show the other faction's buffs too" },
    { key = "announce", label = "Announce new drops in chat" },
    { key = "sound", label = "Play a sound when a buff drops" },
    { key = "sync", label = "Share timers with other players (open world only)" },
    { key = "syncGuild", label = "    ...with my guild" },
    { key = "syncGroup", label = "    ...with my party or raid" },
    { key = "capture", label = "Capture mode: log NPC yells and new auras" },
    { key = "standin", label = "Battle Shout stand-in (testing)" },
}

function Options:Build()
    if self.panel then
        return true
    end
    if not (_G.Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return false
    end
    local ok, err = pcall(function()
        local panel = CreateFrame("Frame")
        panel.name = ns.TITLE

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText(ns.TITLE .. " " .. ns.VERSION)

        local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        sub:SetText("World buff drop timers. Type " .. ns.SLASH_COMMANDS[2] .. " help for all commands.")

        local y = -70
        for _, item in ipairs(self.ITEMS) do
            local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", 16, y)
            local label = cb.Text or cb.text
            if not label then
                label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            end
            label:SetText(item.label)
            cb:SetScript("OnClick", function(button)
                ns.SetSetting(item.key, button:GetChecked() and true or false)
            end)
            item.check = cb
            y = y - 30
        end

        panel:SetScript("OnShow", function()
            Options:Refresh()
        end)

        local category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
        Settings.RegisterAddOnCategory(category)
        self.category = category
        self.panel = panel
    end)
    if not ok then
        ns.Debug("settings panel unavailable: %s", tostring(err))
        return false
    end
    return true
end

function Options:Refresh()
    for _, item in ipairs(self.ITEMS) do
        if item.check then
            item.check:SetChecked(ns.GetSetting(item.key) and true or false)
        end
    end
end

function Options:Open()
    if self.category and _G.Settings and Settings.OpenToCategory then
        local id = self.category.GetID and self.category:GetID() or self.category.ID
        if pcall(Settings.OpenToCategory, id) then
            return true
        end
    end
    ns.Print("the settings page is not available on this client; use %s help.", ns.SLASH_COMMANDS[2])
    return false
end

ns.On("INIT", function()
    Options:Build()
end)

ns.On("SETTING_CHANGED", function()
    if Options.panel and Options.panel.IsShown and Options.panel:IsShown() then
        Options:Refresh()
    end
end)

---------------------------------------------------------------------------
-- Addon compartment (the puzzle-piece button by the minimap). The TOC names
-- these globals; they are built from the addon name so a rename stays simple.
---------------------------------------------------------------------------

_G[ADDON_NAME .. "_OnAddonCompartmentClick"] = function(_, mouseButton)
    if not ns.db then
        return
    end
    if type(mouseButton) == "table" then
        mouseButton = mouseButton.buttonName -- 11.0+ passes MenuInputData
    end
    if mouseButton == "RightButton" then
        Options:Open()
    else
        ns.UI:Toggle()
    end
end

_G[ADDON_NAME .. "_OnAddonCompartmentEnter"] = function(_, menuButton)
    if not GameTooltip then
        return
    end
    pcall(function()
        GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.TITLE)
        GameTooltip:AddLine("Left-click: show or hide the timers", 1, 1, 1)
        GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
        GameTooltip:Show()
    end)
end

_G[ADDON_NAME .. "_OnAddonCompartmentLeave"] = function()
    if GameTooltip then
        GameTooltip:Hide()
    end
end
