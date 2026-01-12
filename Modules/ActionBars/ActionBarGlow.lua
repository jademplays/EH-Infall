local ADDON_NAME, ns = ...
local NephUI = ns.Addon

NephUI.ActionBarGlow = NephUI.ActionBarGlow or {}
local ActionBarGlow = NephUI.ActionBarGlow

-- Get LibCustomGlow for glow effects
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Track which buttons have active glows: [button] = spellID
local activeGlowIcons = {}
-- Reverse lookup: spellID -> { [button] = true }
local spellGlowMap = {}

-- LibCustomGlow glow types
ActionBarGlow.LibCustomGlowTypes = {
    "Pixel Glow",
    "Autocast Shine",
    "Action Button Glow",
    "Proc Glow",
}

-- Try to find the icon texture attached to the button
local function GetButtonIconTexture(button)
    if not button then return nil end

    local icon = button.icon or button.Icon or button.IconTexture
    if icon and icon.GetObjectType and icon:GetObjectType() == "Texture" then
        return icon
    end

    local buttonName = button.GetName and button:GetName()
    if buttonName then
        local namedIcon = _G[buttonName .. "Icon"] or _G[buttonName .. "IconTexture"]
        if namedIcon then
            return namedIcon
        end
    end

    if button.GetRegions then
        for _, region in ipairs({button:GetRegions()}) do
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                local regionName = region:GetName()
                if not regionName or regionName:find("Icon") then
                    return region
                end
            end
        end
    end

    return nil
end

local function AnchorGlowFrameToIcon(button, glowFrame, xOffset, yOffset)
    if not glowFrame then return end
    local icon = GetButtonIconTexture(button)
    local target = icon or button
    xOffset = xOffset or 0
    yOffset = yOffset or 0

    glowFrame:ClearAllPoints()
    glowFrame:SetPoint("TOPLEFT", target, "TOPLEFT", -xOffset, yOffset)
    glowFrame:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", xOffset, -yOffset)
end

local function AnchorOverlayGlowToIcon(button, xOffset, yOffset)
    if not button then return end
    local overlay = button.__LBGoverlay
    if not overlay then return end

    local icon = GetButtonIconTexture(button)
    local target = icon or button
    local targetWidth = (target and target.GetWidth and target:GetWidth()) or (button.GetWidth and button:GetWidth()) or 0
    local targetHeight = (target and target.GetHeight and target:GetHeight()) or (button.GetHeight and button:GetHeight()) or 0

    xOffset = xOffset or 0
    yOffset = yOffset or 0

    overlay:ClearAllPoints()
    overlay:SetSize(targetWidth * 1.4, targetHeight * 1.4)
    overlay:SetPoint("TOPLEFT", target, "TOPLEFT", -(targetWidth * 0.2 + xOffset), targetHeight * 0.2 + yOffset)
    overlay:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", targetWidth * 0.2 + xOffset, -(targetHeight * 0.2 + yOffset))
end

-- Check if button is an action bar button
local function IsActionBarButton(button)
    if not button then return false end
    local buttonName = button:GetName()
    if not buttonName or type(buttonName) ~= "string" then return false end
    return buttonName:match("ActionButton") or buttonName:match("MultiBar") or 
           buttonName:match("PetActionButton") or buttonName:match("StanceButton")
end

-- Get settings for action bar proc glow
local function GetActionBarGlowSettings()
    local settings = NephUI.db.profile.actionBars.procGlow
    if not settings or not settings.enabled then return nil end
    return settings
end

-- Hide Blizzard's SpellActivationAlert (just hide it, don't interfere with events)
local function HideBlizzardGlow(button)
    if not button then return end
    local alert = button.SpellActivationAlert
    if alert then
        alert:Hide()
    end
end

-- Get spellID from a button
local function GetButtonSpellID(button)
    if not button then return nil end
    local spellID = nil
    pcall(function()
        if button.GetSpellId then
            spellID = button:GetSpellId()
        end
        if not spellID then
            spellID = button.spellID or button.SpellID
        end
        if not spellID and button.GetSpellID then
            spellID = button:GetSpellID()
        end
        if not spellID then
            local actionID = button.action
            if not actionID and button.GetAction then
                actionID = button:GetAction()
            end
            if actionID then
                local actionType, id, subType = GetActionInfo(actionID)
                if actionType == "spell" then
                    spellID = id
                elseif actionType == "macro" and id then
                    local macroSpellID = GetMacroSpell(id)
                    if macroSpellID then
                        spellID = macroSpellID
                    end
                elseif actionType == "flyout" and id and FlyoutHasSpell then
                    -- Try to find the first spell in the flyout that matches current button
                    local _, _, numSlots = GetFlyoutInfo(id)
                    for slot = 1, numSlots or 0 do
                        local flyoutSpellID = GetFlyoutSlotInfo(id, slot)
                        if flyoutSpellID then
                            spellID = flyoutSpellID
                            break
                        end
                    end
                end
            end
        end
    end)
    return spellID
end

-- Apply LibCustomGlow effects (replaces Blizzard's glow)
local function ApplyLibCustomGlow(button, settings, spellID)
    if not LCG or not button then return false end
    
    if not spellID then
        spellID = GetButtonSpellID(button)
    end
    
    local glowType = settings.glowType or "Pixel Glow"
    local color = settings.loopColor or {0.95, 0.95, 0.32, 1}
    if not color[4] then color[4] = 1 end
    
    local lines = settings.lcgLines or 14
    local frequency = settings.lcgFrequency or 0.25
    local thickness = settings.lcgThickness or 2
    local glowKey = "_NephUIActionBarGlow"
    
    -- Stop any existing glow first
    ActionBarGlow:StopGlow(button)
    
    -- Hide Blizzard's glow
    HideBlizzardGlow(button)
    
    if glowType == "Pixel Glow" then
        LCG.PixelGlow_Start(button, color, lines, frequency, nil, thickness, 0, 0, true, glowKey)
        local glowFrame = button["_PixelGlow" .. glowKey]
        AnchorGlowFrameToIcon(button, glowFrame, 0, 0)
    elseif glowType == "Autocast Shine" then
        LCG.AutoCastGlow_Start(button, color, lines, frequency, 1, 0, 0, glowKey)
        local glowFrame = button["_AutoCastGlow" .. glowKey]
        AnchorGlowFrameToIcon(button, glowFrame, 0, 0)
    elseif glowType == "Action Button Glow" then
        LCG.ButtonGlow_Start(button, color, frequency)
        AnchorOverlayGlowToIcon(button, 0, 0)
        if button.__LBGoverlay == nil then
            C_Timer.After(0, function()
                AnchorOverlayGlowToIcon(button, 0, 0)
            end)
        end
    elseif glowType == "Proc Glow" then
        LCG.ProcGlow_Start(button, {
            color = color,
            startAnim = true,
            xOffset = 0,
            yOffset = 0,
            key = glowKey
        })
        local glowFrame = button["_ProcGlow" .. glowKey]
        AnchorGlowFrameToIcon(button, glowFrame, 0, 0)
    end
    
    activeGlowIcons[button] = spellID
    if spellID then
        spellGlowMap[spellID] = spellGlowMap[spellID] or {}
        spellGlowMap[spellID][button] = true
    end
    return true
end

-- Stop all glow effects on a button
function ActionBarGlow:StopGlow(button)
    if not button then return end
    
    local trackedSpellID = activeGlowIcons[button]
    if trackedSpellID then
        local map = spellGlowMap[trackedSpellID]
        if map then
            map[button] = nil
            if not next(map) then
                spellGlowMap[trackedSpellID] = nil
            end
        end
    end
    
    -- Stop LibCustomGlow effects
    if LCG then
        pcall(LCG.PixelGlow_Stop, button, "_NephUIActionBarGlow")
        pcall(LCG.AutoCastGlow_Stop, button, "_NephUIActionBarGlow")
        pcall(LCG.ProcGlow_Stop, button, "_NephUIActionBarGlow")
        pcall(LCG.ButtonGlow_Stop, button)
    end
    
    activeGlowIcons[button] = nil
end

-- Initialize the module
function ActionBarGlow:Initialize()
    local settings = GetActionBarGlowSettings()
    if not settings or not settings.enabled then return end
    
    -- Hook ActionButton_ShowOverlayGlow - replace Blizzard's glow with ours
    if type(ActionButton_ShowOverlayGlow) == "function" then
        hooksecurefunc("ActionButton_ShowOverlayGlow", function(button)
            if not button or not IsActionBarButton(button) then return end
            
            local settings = GetActionBarGlowSettings()
            if not settings then return end
            
            -- Hide Blizzard's glow and show our custom glow
            HideBlizzardGlow(button)
            if button:IsShown() then
                local spellID = GetButtonSpellID(button)
                ApplyLibCustomGlow(button, settings, spellID)
            end
        end)
    end
    
    -- Hook ActionButton_HideOverlayGlow - hide our glow when Blizzard hides theirs
    if type(ActionButton_HideOverlayGlow) == "function" then
        hooksecurefunc("ActionButton_HideOverlayGlow", function(button)
            if not button or not IsActionBarButton(button) then return end
            
            -- Hide our custom glow
            ActionBarGlow:StopGlow(button)
        end)
    end
    
    -- Hook ActionButtonSpellAlertManager:ShowAlert
    C_Timer.After(0.5, function()
        if ActionButtonSpellAlertManager then
            hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(frame, button)
                local targetButton = button or frame
                if not targetButton or not IsActionBarButton(targetButton) then return end
                
                local settings = GetActionBarGlowSettings()
                if not settings then return end
                
                HideBlizzardGlow(targetButton)
                if targetButton:IsShown() then
                    local spellID = GetButtonSpellID(targetButton)
                    ApplyLibCustomGlow(targetButton, settings, spellID)
                end
            end)
        end
    end)
    
    -- Hook SpellActivationAlert Show and Hide methods directly on all buttons
    C_Timer.After(1, function()
        local function HookButtonAlert(button)
            if not button or not IsActionBarButton(button) then return end
            local alert = button.SpellActivationAlert
            if alert then
                -- Hook Show method
                if not alert._NephUIShowHooked then
                    local originalShow = alert.Show
                    alert.Show = function(self, ...)
                        if originalShow then
                            originalShow(self, ...)
                        end
                        -- Replace with our glow
                        local btn = self:GetParent()
                        if btn and IsActionBarButton(btn) then
                            local settings = GetActionBarGlowSettings()
                            if settings then
                                HideBlizzardGlow(btn)
                                if btn:IsShown() then
                                    local spellID = GetButtonSpellID(btn)
                                    ApplyLibCustomGlow(btn, settings, spellID)
                                end
                            end
                        end
                    end
                    alert._NephUIShowHooked = true
                end
                
                -- Hook Hide method
                if not alert._NephUIHideHooked then
                    local originalHide = alert.Hide
                    alert.Hide = function(self, ...)
                        if originalHide then
                            originalHide(self, ...)
                        end
                        -- Hide our glow when Blizzard hides theirs
                        local btn = self:GetParent()
                        if btn and IsActionBarButton(btn) then
                            ActionBarGlow:StopGlow(btn)
                        end
                    end
                    alert._NephUIHideHooked = true
                end
            end
        end
        
        for i = 1, 120 do
            HookButtonAlert(_G["ActionButton" .. i])
        end
        for i = 1, 10 do
            HookButtonAlert(_G["PetActionButton" .. i])
            HookButtonAlert(_G["StanceButton" .. i])
        end
        for i = 1, 12 do
            for j = 1, 12 do
                HookButtonAlert(_G["MultiBar" .. i .. "Button" .. j])
            end
        end
    end)
    
    -- Also listen for spell activation events as backup
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    eventFrame:SetScript("OnEvent", function(self, event, spellID)
        if not spellID then return end
        
        local settings = GetActionBarGlowSettings()
        if not settings then return end
        
        -- Helper to find buttons with matching spellID
        local function FindButtonsWithSpellID(checkSpellID)
            local buttons = {}
            for i = 1, 120 do
                local button = _G["ActionButton" .. i]
                if button and IsActionBarButton(button) then
                    local buttonSpellID = GetButtonSpellID(button)
                    if buttonSpellID == checkSpellID then
                        table.insert(buttons, button)
                    end
                end
            end
            for i = 1, 10 do
                local petButton = _G["PetActionButton" .. i]
                if petButton then
                    local buttonSpellID = GetButtonSpellID(petButton)
                    if buttonSpellID == checkSpellID then
                        table.insert(buttons, petButton)
                    end
                end
                local stanceButton = _G["StanceButton" .. i]
                if stanceButton then
                    local buttonSpellID = GetButtonSpellID(stanceButton)
                    if buttonSpellID == checkSpellID then
                        table.insert(buttons, stanceButton)
                    end
                end
            end
            for i = 1, 12 do
                for j = 1, 12 do
                    local button = _G["MultiBar" .. i .. "Button" .. j]
                    if button then
                        local buttonSpellID = GetButtonSpellID(button)
                        if buttonSpellID == checkSpellID then
                            table.insert(buttons, button)
                        end
                    end
                end
            end
            return buttons
        end
        
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
            local buttons = FindButtonsWithSpellID(spellID)
            for _, button in ipairs(buttons) do
                if button:IsShown() then
                    HideBlizzardGlow(button)
                    ApplyLibCustomGlow(button, settings, spellID)
                end
            end
        elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            -- Stop glows on buttons registered for this spell
            local buttonsForSpell = spellGlowMap[spellID]
            if buttonsForSpell then
                for button in pairs(buttonsForSpell) do
                    ActionBarGlow:StopGlow(button)
                end
            end
        end
    end)
end

-- Refresh all action bar glows
function ActionBarGlow:RefreshAll()
    local settings = GetActionBarGlowSettings()
    if not settings or not settings.enabled then return end
    
    -- Stop all glows
    for button, _ in pairs(activeGlowIcons) do
        if button then
            self:StopGlow(button)
        end
    end
    wipe(activeGlowIcons)
end
