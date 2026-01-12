local ADDON_NAME, ns = ...
local NephUI = ns.Addon

NephUI.ProcGlow = NephUI.ProcGlow or {}
local ProcGlow = NephUI.ProcGlow

-- Get LibCustomGlow for glow effects
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Track which icons currently have active glows
local activeGlowIcons = {}  -- [icon] = true

-- LibCustomGlow glow types
ProcGlow.LibCustomGlowTypes = {
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

-- Get settings for proc glow (viewers only)
local function GetProcGlowSettings()
    local settings = NephUI.db.profile.viewers.general.procGlow
    if not settings or not settings.enabled then return nil end
    return settings
end

-- Apply LibCustomGlow effects
local function ApplyLibCustomGlow(icon, settings)
    if not LCG then return false end
    if not icon then return false end
    
    local glowType = settings.glowType or "Pixel Glow"
    local color = settings.loopColor or {0.95, 0.95, 0.32, 1}
    -- Ensure color has alpha
    if not color[4] then
        color[4] = 1
    end
    local lines = settings.lcgLines or 14
    local frequency = settings.lcgFrequency or 0.25
    local thickness = settings.lcgThickness or 2

    -- Get the icon texture for anchoring (like ActionBarGlow does)
    local iconTexture = GetButtonIconTexture(icon)
    
    -- Use viewer glow key
    local glowKey = "_NephUICustomGlow"
    
    -- Stop any existing glow first
    ProcGlow:StopGlow(icon)
    
    -- Hide Blizzard's glow
    local region = icon.SpellActivationAlert
    if region then
        if region.ProcLoopFlipbook then
            region.ProcLoopFlipbook:Hide()
        end
        if region.ProcStartFlipbook then
            region.ProcStartFlipbook:Hide()
        end
    end
    
    if glowType == "Pixel Glow" then
        LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, glowKey)
        local glowFrame = icon["_PixelGlow" .. glowKey]
        if glowFrame then
            -- Anchor glow frame to icon texture like ActionBarGlow does
            local target = iconTexture or icon
            glowFrame:ClearAllPoints()
            glowFrame:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
            glowFrame:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        end
    elseif glowType == "Autocast Shine" then
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, 1, 0, 0, glowKey)
        local glowFrame = icon["_AutoCastGlow" .. glowKey]
        if glowFrame then
            -- Anchor glow frame to icon texture like ActionBarGlow does
            local target = iconTexture or icon
            glowFrame:ClearAllPoints()
            glowFrame:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
            glowFrame:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        end
    elseif glowType == "Action Button Glow" then
        LCG.ButtonGlow_Start(icon, color, frequency)
    elseif glowType == "Proc Glow" then
        LCG.ProcGlow_Start(icon, {
            color = color,
            startAnim = true,
            xOffset = 0,
            yOffset = 0,
            key = glowKey
        })
    end
    
    -- Flag that we have a custom glow active
    icon._NephUICustomGlowActive = true
    activeGlowIcons[icon] = true
    
    return true
end

-- Stop all glow effects on an icon
function ProcGlow:StopGlow(icon)
    if not icon then return end
    
    -- Stop LibCustomGlow effects (viewer key only)
    if LCG then
        pcall(LCG.PixelGlow_Stop, icon, "_NephUICustomGlow")
        pcall(LCG.AutoCastGlow_Stop, icon, "_NephUICustomGlow")
        pcall(LCG.ProcGlow_Stop, icon, "_NephUICustomGlow")
    end
    
    icon._NephUICustomGlowActive = nil
    activeGlowIcons[icon] = nil
end

-- Main function to start glow on a button (viewers only)
function ProcGlow:StartGlow(icon)
    if not icon then return end
    
    -- Skip action bar buttons - they're handled by ActionBarGlow
    local buttonName = icon:GetName() or ""
    if buttonName:match("ActionButton") or buttonName:match("MultiBar") or 
       buttonName:match("PetActionButton") or buttonName:match("StanceButton") then
        return
    end
    
    -- Already has our glow? Skip
    if icon._NephUICustomGlowActive then return end
    
    local settings = GetProcGlowSettings()
    if not settings then return end
    
    -- Always use LibCustomGlow
    if icon:IsShown() then
        ApplyLibCustomGlow(icon, settings)
    end
end

-- Hook function for ActionButtonSpellAlertManager:ShowAlert
local function Hook_ShowAlert(frame, button)
    local targetButton = button or frame
    if not targetButton then return end
    
    -- Skip action bar buttons - they're handled by ActionBarGlow
    local buttonName = targetButton:GetName() or ""
    if buttonName:match("ActionButton") or buttonName:match("MultiBar") or 
       buttonName:match("PetActionButton") or buttonName:match("StanceButton") then
        return
    end
    
    -- Handle different function signatures (viewers only)
    if ProcGlow.StartGlow then
        ProcGlow:StartGlow(targetButton)
    end
end

-- Hook into Blizzard's glow system
local function SetupGlowHooks()
    -- Hook ActionButton_ShowOverlayGlow - this is called when a proc happens
    if type(ActionButton_ShowOverlayGlow) == "function" then
        hooksecurefunc("ActionButton_ShowOverlayGlow", function(button)
            if not button then return end
            
            -- Skip action bar buttons - they're handled by ActionBarGlow
            local buttonName = button:GetName() or ""
            if buttonName:match("ActionButton") or buttonName:match("MultiBar") or 
               buttonName:match("PetActionButton") or buttonName:match("StanceButton") then
                return
            end
            
            -- Apply immediately (viewers only)
            if button:IsShown() then
                ProcGlow:StartGlow(button)
            end
        end)
    end
    
    -- Hook ActionButton_HideOverlayGlow - this is called when proc ends
    if type(ActionButton_HideOverlayGlow) == "function" then
        hooksecurefunc("ActionButton_HideOverlayGlow", function(button)
            if not button then return end
            
            -- Skip action bar buttons - they're handled by ActionBarGlow
            local buttonName = button:GetName() or ""
            if buttonName:match("ActionButton") or buttonName:match("MultiBar") or 
               buttonName:match("PetActionButton") or buttonName:match("StanceButton") then
                return
            end
            
            ProcGlow:StopGlow(button)
        end)
    end
    
    -- Also listen for spell activation events directly
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    eventFrame:SetScript("OnEvent", function(self, event, spellID)
        if not spellID then return end
        
        -- Find the icon with this spellID in our viewers
        local viewers = NephUI.viewers or {
            "EssentialCooldownViewer",
            "UtilityCooldownViewer",
            "BuffIconCooldownViewer",
        }
        
        for _, viewerName in ipairs(viewers) do
            local viewer = _G[viewerName]
            if viewer then
                local children = {viewer:GetChildren()}
                for _, child in ipairs(children) do
                    if child:IsShown() then
                        -- Wrap spell ID access and comparison in pcall to handle "secret" values
                        local matched = false
                        pcall(function()
                            local iconSpellID = child.spellID or child.SpellID or 
                                               (child.GetSpellID and child:GetSpellID())
                            if iconSpellID and iconSpellID == spellID then
                                matched = true
                            end
                        end)
                        
                        if matched then
                            if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                                -- Apply immediately
                                ProcGlow:StartGlow(child)
                            else
                                ProcGlow:StopGlow(child)
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- Initialize the module
function ProcGlow:Initialize()
    local settings = GetProcGlowSettings()
    if not settings or not settings.enabled then return end
    
    -- Set up hooks immediately
    SetupGlowHooks()
    
    -- Hook into the spell alert manager (wait for it to be available)
    C_Timer.After(0.5, function()
        if ActionButtonSpellAlertManager then
            hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", Hook_ShowAlert)
        end
    end)
end

-- Refresh all proc glows (viewers only)
function ProcGlow:RefreshAll()
    local settings = GetProcGlowSettings()
    if not settings or not settings.enabled then return end
    
    -- Store which icons had glows before refresh
    local iconsWithGlows = {}
    for icon, _ in pairs(activeGlowIcons) do
        if icon then
            -- Only track viewer icons
            local buttonName = icon:GetName() or ""
            if not (buttonName:match("ActionButton") or buttonName:match("MultiBar") or 
                    buttonName:match("PetActionButton") or buttonName:match("StanceButton")) then
                iconsWithGlows[icon] = true
            end
        end
    end
    
    -- Stop all existing custom glows
    for icon, _ in pairs(activeGlowIcons) do
        if icon then
            self:StopGlow(icon)
        end
    end
    wipe(activeGlowIcons)
    
    -- Re-apply glows to icons that had them before (if settings allow)
    for icon, _ in pairs(iconsWithGlows) do
        if icon and icon:IsShown() then
            self:StartGlow(icon)
        end
    end
end
