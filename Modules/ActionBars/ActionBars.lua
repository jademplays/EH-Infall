local ADDON_NAME, ns = ...
local NephUI = ns.Addon

NephUI.ActionBars = NephUI.ActionBars or {}
local ActionBars = NephUI.ActionBars

local LSM = LibStub("LibSharedMedia-3.0")

-- Texture paths
local BACKDROP_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local HIGHLIGHT_TEXTURE = [[Interface\AddOns\NephUI\Media\white_border.tga]]

-- Track processed buttons to avoid double-processing
local processedButtons = {}

-- Cache Blizzard's range indicator placeholder (shown when no keybind exists)
local RANGE_INDICATOR_TEXT = tostring(rawget(_G, "RANGE_INDICATOR") or "")

-- Strip WoW color codes from text to make comparisons reliable
local function StripColorCodes(text)
    if not text or text == "" then
        return text
    end
    
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

-- Icon zoom settings (crop edges for cleaner look)
local ICON_ZOOM = { 0.08, 0.92, 0.08, 0.92 }

-- Collect micro menu buttons using Blizzard's MICRO_BUTTONS list
local function CollectMicroButtons()
    local collected = {}
    if type(MICRO_BUTTONS) == "table" then
        for _, name in ipairs(MICRO_BUTTONS) do
            local button = _G[name]
            if button then
                table.insert(collected, button)
            end
        end
    end
    return collected
end

-- Mapping of bar config names to actual bar frame names and prefixes
local BAR_FRAME_MAP = {
    bar1 = { frame = "MainActionBar", prefix = "Action" },
    bar2 = { frame = "MultiBarBottomLeft", prefix = "MultiBarBottomLeft" },
    bar3 = { frame = "MultiBarBottomRight", prefix = "MultiBarBottomRight" },
    bar4 = { frame = "MultiBarRight", prefix = "MultiBarRight" },
    bar5 = { frame = "MultiBarLeft", prefix = "MultiBarLeft" },
    bar6 = { frame = "MultiBar5", prefix = "MultiBar5" },
    bar7 = { frame = "MultiBar6", prefix = "MultiBar6" },
    bar8 = { frame = "MultiBar7", prefix = "MultiBar7" },
    petBar = { frame = "PetActionBar", prefix = "PetAction" },
    stanceBar = { frame = "StanceBar", prefix = "Stance" },
    microMenu = { frame = "MicroMenu", fallbackFrame = "MicroButtonAndBagsBar", buttonProvider = CollectMicroButtons },
}

-- Action bar prefixes to iterate through
local BAR_PREFIXES = {
    "Action",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "PetAction",
    "Stance"
}

-- Function to get a button by prefix and index
local function GetActionButton(prefix, index)
    return _G[prefix .. "Button" .. index]
end

-- Function to get font path (action bar specific or global)
local function GetActionBarFont(cfg)
    if cfg and cfg.font and cfg.font ~= "" then
        local fontPath = LSM:Fetch("font", cfg.font)
        if fontPath then
            return fontPath
        end
    end
    -- Fallback to global font
    return NephUI:GetGlobalFont()
end

-- Scale helper that respects NephUI's pixel perfect multiplier
local function ScaleOffset(value)
    if not value or value == 0 then
        return 0
    end
    return NephUI:Scale(value)
end

-- Function to validate if keybind text contains meaningful content
local function IsValidKeybindText(text)
    text = StripColorCodes(text)
    
    if not text or text == "" then
        return false
    end
    
    -- Hide Blizzard's range indicator placeholder and similar fallbacks
    if RANGE_INDICATOR_TEXT ~= "" and text == RANGE_INDICATOR_TEXT then
        return false
    end
    
    -- Remove all whitespace for checking
    local cleaned = text:gsub("%s+", "")
    
    -- Only hide blank text and empty brackets - allow all other keybinds to show
    if cleaned == "" or cleaned == "[]" then
        return false
    end
    
    if RANGE_INDICATOR_TEXT ~= "" and cleaned == RANGE_INDICATOR_TEXT then
        return false
    end
    
    return true
end

-- Function to style a text element
local function StyleTextElement(element, textCfg, defaultFont)
    if not element or element:IsForbidden() then
        return
    end
    
    if not textCfg then
        return
    end
    
    -- Hide/show based on config
    if textCfg.hide then
        element:Hide()
        return
    else
        element:Show()
    end
    
    -- Set font (don't read from Blizzard to avoid taint)
    local fontPath = defaultFont
    if fontPath then
        local fontSize = textCfg.fontSize or 12
        local flags = "OUTLINE"
        element:SetFont(fontPath, fontSize, flags)
    end
    
    -- Set color
    if textCfg.fontColor then
        element:SetVertexColor(unpack(textCfg.fontColor))
    end
    
    -- Set position (don't read from Blizzard to avoid taint)
    local elementName = element:GetName() or ""
    local anchorPoint, relativePoint
    local offsetX, offsetY
    
    if elementName:find("HotKey") then
        anchorPoint, relativePoint = "TOPRIGHT", "TOPRIGHT"
        offsetX = textCfg.offsetX or -2
        offsetY = textCfg.offsetY or -4
    elseif elementName:find("Count") then
        anchorPoint, relativePoint = "BOTTOMRIGHT", "BOTTOMRIGHT"
        offsetX = textCfg.offsetX or -2
        offsetY = textCfg.offsetY or 4
    elseif elementName:find("Name") then
        anchorPoint, relativePoint = "BOTTOM", "BOTTOM"
        offsetX = textCfg.offsetX or 0
        offsetY = textCfg.offsetY or 2
    else
        -- Default anchor
        anchorPoint, relativePoint = "CENTER", "CENTER"
        offsetX = textCfg.offsetX or 0
        offsetY = textCfg.offsetY or 0
    end
    
    -- Apply position
    element:ClearAllPoints()
    local scaledOffsetX = ScaleOffset(offsetX)
    local scaledOffsetY = ScaleOffset(offsetY)
    element:SetPoint(anchorPoint, element:GetParent(), relativePoint, scaledOffsetX, scaledOffsetY)
end

-- Function to style a single action button
local function StyleActionButton(button)
    if not button or button:IsForbidden() or processedButtons[button] then
        return
    end
    
    local cfg = NephUI.db.profile.actionBars
    if not cfg or not cfg.enabled then
        return
    end
    
    -- Mark as processed
    processedButtons[button] = true
    
    -- Get the icon texture
    local icon = button.icon
    if not icon then
        return
    end
    
    -- Hide default Blizzard textures
    if button.NormalTexture then
        button.NormalTexture:SetAlpha(0)
    end
    
    if button.IconMask then
        button.IconMask:Hide()
    end
    
    if button.InterruptDisplay then
        button.InterruptDisplay:SetAlpha(0)
    end
    
    if button.SpellCastAnimFrame then
        button.SpellCastAnimFrame:SetAlpha(0)
    end
    
    if button.SlotBackground then
        button.SlotBackground:Hide()
    end
    
    if button.SlotArt then
        button.SlotArt:Hide()
    end
    
    -- Create or update backdrop texture
    if not button.__nephuiBackdrop then
        button.__nephuiBackdrop = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    end
    
    local backdrop = button.__nephuiBackdrop
    local backdropColor = cfg.backdropColor or {0.1, 0.1, 0.1, 1}
    backdrop:SetTexture(BACKDROP_TEXTURE)
    -- Round to nearest integer for pixel perfect rendering
    local backdropOffset = (NephUI.ScaleBorder and NephUI:ScaleBorder(1)) or math.floor(NephUI:Scale(1) + 0.5)
    backdrop:SetPoint("TOPLEFT", button, "TOPLEFT", -backdropOffset, backdropOffset)
    backdrop:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", backdropOffset, -backdropOffset)
    backdrop:SetVertexColor(unpack(backdropColor))
    backdrop:Show()
    
    -- Optional border that grows outward from the backdrop using Blizzard's WHITE8x8 texture
    local configuredBorderSize = math.max(0, cfg.borderSize or 0)
    local scaledBorderSize = (NephUI.ScaleBorder and NephUI:ScaleBorder(configuredBorderSize)) or math.floor(NephUI:Scale(configuredBorderSize) + 0.5)
    if scaledBorderSize > 0 then
        if not button.__nephuiBorder then
            button.__nephuiBorder = button:CreateTexture(nil, "BACKGROUND", nil, -2)
        end
        local border = button.__nephuiBorder
        border:SetTexture(BACKDROP_TEXTURE)
        local totalOffset = backdropOffset + scaledBorderSize
        border:SetPoint("TOPLEFT", button, "TOPLEFT", -totalOffset, totalOffset)
        border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", totalOffset, -totalOffset)
        local borderColor = cfg.borderColor or {0, 0, 0, 1}
        border:SetVertexColor(unpack(borderColor))
        border:Show()
    elseif button.__nephuiBorder then
        button.__nephuiBorder:Hide()
    end
    
    -- Style the icon
    icon:SetTexCoord(unpack(ICON_ZOOM))
    icon:SetDrawLayer("BACKGROUND", 0)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

    -- Update highlight texture to NephUI custom border
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetTexture(HIGHLIGHT_TEXTURE)
        highlight:SetTexCoord(0, 1, 0, 1)
        highlight:ClearAllPoints()
        highlight:SetPoint("TOPLEFT", button, "TOPLEFT", -backdropOffset, backdropOffset)
        highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", backdropOffset, -backdropOffset)
        highlight:SetBlendMode("ADD")
    end

    -- Use Blizzard's default textures (no replacement needed)
    
    -- Style cooldown frame
    if button.cooldown then
        button.cooldown:ClearAllPoints()
        button.cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        button.cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    end
    
    -- Hide profession quality overlay
    if button.ProfessionQualityOverlayFrame then
        C_Timer.After(0.5, function()
            if button and button.ProfessionQualityOverlayFrame then
                button.ProfessionQualityOverlayFrame:SetAlpha(0)
            end
        end)
    end
    
    -- Style text elements
    local fontPath = GetActionBarFont(cfg)
    
    -- Style keybind text (HotKey) - use defaults if config doesn't exist
    if button.HotKey then
        local keybindCfg = cfg.keybindText or {}
        StyleTextElement(button.HotKey, keybindCfg, fontPath)
        
        -- Validate and hide empty keybinds
        local function UpdateKeybindVisibility()
            if not button.HotKey or button.HotKey:IsForbidden() then
                return
            end
            
            -- Respect config hide setting
            if keybindCfg.hide then
                button.HotKey:Hide()
                return
            end
            
            -- Check if the current text is valid
            local currentText = button.HotKey:GetText() or ""
            if IsValidKeybindText(currentText) then
                button.HotKey:Show()
            else
                button.HotKey:Hide()
            end
        end
        
        -- Check immediately after a short delay to allow Blizzard to set initial text
        C_Timer.After(0.1, UpdateKeybindVisibility)
        
        -- Hook SetText to validate whenever keybind text is updated
        if not button.HotKey.__nephuiKeybindValidator then
            hooksecurefunc(button.HotKey, "SetText", function()
                C_Timer.After(0.05, UpdateKeybindVisibility)
            end)
            button.HotKey.__nephuiKeybindValidator = true
        end
    end
    
    -- Style macro text (Name) - use defaults if config doesn't exist
    if button.Name then
        local macroCfg = cfg.macroText or {}
        StyleTextElement(button.Name, macroCfg, fontPath)
    end
    
    -- Style count text (Count) - use defaults if config doesn't exist
    if button.Count then
        local countCfg = cfg.countText or {}
        StyleTextElement(button.Count, countCfg, fontPath)
    end
end

-- Track bars with active mouseover effects
local activeMouseoverBars = {}

-- Track pending fade timers to cancel them
local pendingFadeTimers = {} -- [barFrame] = timer

-- Track current fade state to prevent duplicate calls
local barFadeState = {} -- [barFrame] = { isShowing = bool }

-- Safely toggle mouse interaction on frames
local function ToggleMouseInteraction(frame, enable)
    if not frame or InCombatLockdown() then return end
    if enable then
        frame:EnableMouse(true)
    else
        frame:EnableMouse(false)
    end
end

-- Collect all buttons for a given action bar prefix
local function CollectBarButtons(prefix)
    if not prefix then
        return {}
    end

    local collected = {}
    for slot = 1, 12 do
        local actionButton = GetActionButton(prefix, slot)
        if actionButton then
            table.insert(collected, actionButton)
        end
    end
    return collected
end

-- Apply alpha transition to action bar frames
local function ApplyBarAlphaTransition(barFrame, shouldShow)
    if not barFrame then return end
    
    -- Don't change alpha while in edit mode - keep it at 1.0
    if EditModeManagerFrame and EditModeManagerFrame.editModeActive then
        return
    end
    
    local actionBarConfig = NephUI.db.profile.actionBars
    local mouseoverSettings = actionBarConfig and actionBarConfig.mouseover
    
    -- If mouseover is disabled, ensure full visibility
    if not mouseoverSettings or not mouseoverSettings.enabled then
        barFrame:SetAlpha(1.0)
        -- Always keep mouse enabled for keybinding to work
        ToggleMouseInteraction(barFrame, true)
        barFadeState[barFrame] = nil
        return
    end
    
    -- Get or create fade state
    local fadeState = barFadeState[barFrame]
    if not fadeState then
        fadeState = { isShowing = false }
        barFadeState[barFrame] = fadeState
    end
    
    -- If already in the desired state, don't restart the fade
    if fadeState.isShowing == shouldShow then
        return
    end
    
    -- Update state
    fadeState.isShowing = shouldShow
    
    local fadeInTime = 0.3
    local fadeOutTime = 0.3
    local inactiveAlpha = mouseoverSettings.alpha or 0.5
    local targetAlpha = shouldShow and 1.0 or inactiveAlpha
    
    -- Instant change during combat
    if InCombatLockdown() then
        barFrame:SetAlpha(targetAlpha)
        return
    end
    
    -- Apply smooth fade transition (use fixed start alpha to avoid reading)
    if shouldShow then
        local fadeInfo = {
            mode = "IN",
            timeToFade = fadeInTime,
            startAlpha = inactiveAlpha,
            endAlpha = 1.0,
        }
        UIFrameFade(barFrame, fadeInfo)
        -- Always keep mouse enabled for keybinding to work
        ToggleMouseInteraction(barFrame, true)
    else
        local fadeInfo = {
            mode = "OUT",
            timeToFade = fadeOutTime,
            startAlpha = 1.0,
            endAlpha = inactiveAlpha,
        }
        UIFrameFade(barFrame, fadeInfo)
        -- Keep mouse enabled even when faded - this allows Blizzard's quick keybind to work
        -- The alpha fade provides the visual feedback without blocking mouse events
        ToggleMouseInteraction(barFrame, true)
    end
end

-- Remove all mouseover event handlers from a bar
local function ClearBarMouseoverHandlers(barFrame, buttonPrefix)
    if not barFrame then return end
    
    -- Clear frame handlers (only on the bar frame, not buttons)
    -- We don't clear button handlers because HookScript preserves original handlers
    -- and we want to keep Blizzard's handlers for keybinding to work
    barFrame:SetScript("OnEnter", nil)
    barFrame:SetScript("OnLeave", nil)
    
    -- Cancel any pending fade timer
    if pendingFadeTimers[barFrame] then
        pendingFadeTimers[barFrame] = nil
    end
    
    -- Note: We don't clear button scripts because:
    -- 1. HookScript preserves original handlers
    -- 2. Clearing them would break Blizzard's keybinding system
    -- 3. Multiple HookScript calls are safe (they stack)
    
    activeMouseoverBars[barFrame] = nil
end

-- Check if mouse is over bar frame or any of its buttons
local function IsMouseOverBarOrButtons(barFrame, barButtons)
    if barFrame:IsMouseOver() then
        return true
    end
    
    for _, actionButton in ipairs(barButtons) do
        if actionButton and actionButton:IsMouseOver() then
            return true
        end
    end
    
    return false
end

-- Attach mouseover behavior to an action bar
local function AttachMouseoverToBar(barFrame, buttonPrefix, buttonProvider)
    if not barFrame then return end
    
    -- Clean up any existing handlers first
    ClearBarMouseoverHandlers(barFrame, buttonPrefix)
    
    -- Cancel any pending fade timer
    if pendingFadeTimers[barFrame] then
        pendingFadeTimers[barFrame] = nil
    end
    
    local fadeDelay = 0.2
    local barButtons = {}
    if type(buttonProvider) == "function" then
        barButtons = buttonProvider() or {}
    else
        barButtons = CollectBarButtons(buttonPrefix)
    end
    
    -- Store barButtons on the frame for later access
    barFrame.__nephuiBarButtons = barButtons
    
    -- Configure frame for mouse interaction
    barFrame:EnableMouse(true)
    barFrame:SetMouseMotionEnabled(true)
    barFrame:SetMouseClickEnabled(true)
    
    -- Ensure buttons have mouse enabled for keybinding (but don't attach handlers to them)
    for _, actionButton in ipairs(barButtons) do
        actionButton:EnableMouse(true)
        actionButton:SetMouseMotionEnabled(true)
    end
    
    -- Only attach handlers to the bar frame itself
    -- When mouse enters bar frame, fade in immediately
    barFrame:HookScript("OnEnter", function()
        -- Cancel any pending fade out
        if pendingFadeTimers[barFrame] then
            pendingFadeTimers[barFrame] = nil
        end
        -- Fade in to full alpha
        ApplyBarAlphaTransition(barFrame, true)
    end)
    
    -- When mouse leaves bar frame, check if it's over any button before fading
    barFrame:HookScript("OnLeave", function()
        -- Cancel any existing pending timer
        if pendingFadeTimers[barFrame] then
            pendingFadeTimers[barFrame] = nil
        end
        
        -- Set a timer to check if we should fade out
        pendingFadeTimers[barFrame] = C_Timer.After(fadeDelay, function()
            pendingFadeTimers[barFrame] = nil
            -- Check if mouse is still over bar or any button
            if not IsMouseOverBarOrButtons(barFrame, barButtons) then
                -- Fade out to configured alpha
                ApplyBarAlphaTransition(barFrame, false)
            end
        end)
    end)
    
    -- Also hook buttons' OnEnter to fade in when hovering buttons directly
    -- This handles the case where mouse goes directly to a button without touching the bar frame
    for _, actionButton in ipairs(barButtons) do
        actionButton:HookScript("OnEnter", function()
            -- Cancel any pending fade out
            if pendingFadeTimers[barFrame] then
                pendingFadeTimers[barFrame] = nil
            end
            -- Fade in to full alpha
            ApplyBarAlphaTransition(barFrame, true)
        end)
        
        actionButton:HookScript("OnLeave", function()
            -- Cancel any existing pending timer
            if pendingFadeTimers[barFrame] then
                pendingFadeTimers[barFrame] = nil
            end
            
            -- Set a timer to check if we should fade out
            pendingFadeTimers[barFrame] = C_Timer.After(fadeDelay, function()
                pendingFadeTimers[barFrame] = nil
                -- Check if mouse is still over bar or any button
                if not IsMouseOverBarOrButtons(barFrame, barButtons) then
                    -- Fade out to configured alpha
                    ApplyBarAlphaTransition(barFrame, false)
                end
            end)
        end)
    end
    
    -- Initialize as faded - set alpha directly without fade on initial load
    -- But if in edit mode, keep at 1.0
    local actionBarConfig = NephUI.db.profile.actionBars
    local mouseoverSettings = actionBarConfig and actionBarConfig.mouseover
    local inEditMode = EditModeManagerFrame and EditModeManagerFrame.editModeActive
    
    if mouseoverSettings and mouseoverSettings.enabled and not inEditMode then
        local inactiveAlpha = mouseoverSettings.alpha or 0.3
        barFrame:SetAlpha(inactiveAlpha)
        -- Initialize state as not showing
        local fadeState = barFadeState[barFrame]
        if not fadeState then
            fadeState = { isShowing = false }
            barFadeState[barFrame] = fadeState
        else
            fadeState.isShowing = false
        end
    else
        barFrame:SetAlpha(1.0)
        -- If in edit mode, mark as showing
        if inEditMode then
            local fadeState = barFadeState[barFrame]
            if not fadeState then
                fadeState = { isShowing = true }
                barFadeState[barFrame] = fadeState
            else
                fadeState.isShowing = true
            end
        end
    end
    
    -- Always keep mouse enabled for keybinding to work, even when faded
    ToggleMouseInteraction(barFrame, true)
    activeMouseoverBars[barFrame] = true
end

-- Configure mouseover behavior for all action bars
local function ConfigureMouseoverBars()
    local actionBarConfig = NephUI.db.profile.actionBars
    if not actionBarConfig or not actionBarConfig.enabled then
        return
    end
    
    local mouseoverSettings = actionBarConfig.mouseover
    
    -- If mouseover is globally disabled, restore all bars to full visibility
    if not mouseoverSettings or not mouseoverSettings.enabled then
        for configKey, barData in pairs(BAR_FRAME_MAP) do
        local frameName = barData.frame
        local buttonPrefix = barData.prefix
        local fallbackFrame = barData.fallbackFrame
        -- Handle MainActionBar/MainMenuBar compatibility and custom fallbacks
        local barFrame = _G[frameName]
            or (fallbackFrame and _G[fallbackFrame])
            or (frameName == "MainActionBar" and _G["MainMenuBar"])
            
            if barFrame then
                ClearBarMouseoverHandlers(barFrame, buttonPrefix)
                barFrame:SetAlpha(1.0)
                ToggleMouseInteraction(barFrame, true)
            end
        end
        return
    end
    
    local perBarSettings = mouseoverSettings.bars or {}
    
    -- Process each configured action bar
    for configKey, barData in pairs(BAR_FRAME_MAP) do
        local frameName = barData.frame
        local buttonPrefix = barData.prefix
        local fallbackFrame = barData.fallbackFrame
        local buttonProvider = barData.buttonProvider
        -- Handle MainActionBar/MainMenuBar compatibility and custom fallbacks
        local barFrame = _G[frameName]
            or (fallbackFrame and _G[fallbackFrame])
            or (frameName == "MainActionBar" and _G["MainMenuBar"])
        
        if barFrame and (buttonPrefix or buttonProvider) then
            if perBarSettings[configKey] then
                -- Enable mouseover for this specific bar
                AttachMouseoverToBar(barFrame, buttonPrefix, buttonProvider)
            else
                -- Disable mouseover and restore visibility
                ClearBarMouseoverHandlers(barFrame, buttonPrefix)
                barFrame:SetAlpha(1.0)
                ToggleMouseInteraction(barFrame, true)
            end
        end
    end
    
    -- Initialize all active mouseover bars as faded (set alpha directly without fade)
    -- But only if not in edit mode - in edit mode, keep them at 1.0
    if not (EditModeManagerFrame and EditModeManagerFrame.editModeActive) then
        local actionBarConfig = NephUI.db.profile.actionBars
        local mouseoverSettings = actionBarConfig and actionBarConfig.mouseover
        if mouseoverSettings and mouseoverSettings.enabled then
            local inactiveAlpha = mouseoverSettings.alpha or 0.3
            for trackedFrame in pairs(activeMouseoverBars) do
                trackedFrame:SetAlpha(inactiveAlpha)
                -- Initialize state as not showing
                local fadeState = barFadeState[trackedFrame]
                if not fadeState then
                    fadeState = { isShowing = false }
                    barFadeState[trackedFrame] = fadeState
                else
                    fadeState.isShowing = false
                end
            end
        end
    end
end

-- Function to style all action bars
function ActionBars:StyleAllBars()
    local cfg = NephUI.db.profile.actionBars
    if not cfg or not cfg.enabled then
        return
    end
    
    -- Hide Blizzard main bar art if present
    if MainActionBar and MainActionBar.BorderArt then
        MainActionBar.BorderArt:Hide()
    end
    
    -- Clear processed buttons cache
    processedButtons = {}
    
    -- Iterate through all bar prefixes
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local button = GetActionButton(prefix, i)
            if button then
                StyleActionButton(button)
            end
        end
    end
    
    -- Configure mouseover behavior
    ConfigureMouseoverBars()
end

-- Hook to catch new buttons being created (only on initial setup, not on updates)
function ActionBars:HookButtonCreation()
    -- Don't hook ActionButton_Update functions as they can cause taint issues
    -- Only style buttons on initial load and edit mode changes
end

-- Set all active mouseover bars to full alpha (for edit mode)
local function SetAllMouseoverBarsToFullAlpha()
    for trackedFrame in pairs(activeMouseoverBars) do
        if trackedFrame then
            trackedFrame:SetAlpha(1.0)
            -- Update state to reflect that it's showing
            local fadeState = barFadeState[trackedFrame]
            if not fadeState then
                fadeState = { isShowing = true }
                barFadeState[trackedFrame] = fadeState
            else
                fadeState.isShowing = true
            end
        end
    end
end

-- Restore all active mouseover bars to configured alpha (for exiting edit mode)
local function RestoreMouseoverBarsAlpha()
    local actionBarConfig = NephUI.db.profile.actionBars
    local mouseoverSettings = actionBarConfig and actionBarConfig.mouseover
    if mouseoverSettings and mouseoverSettings.enabled then
        local inactiveAlpha = mouseoverSettings.alpha or 0.3
        for trackedFrame in pairs(activeMouseoverBars) do
            if trackedFrame then
                trackedFrame:SetAlpha(inactiveAlpha)
                -- Update state to reflect that it's not showing
                local fadeState = barFadeState[trackedFrame]
                if fadeState then
                    fadeState.isShowing = false
                end
            end
        end
    end
end

-- Hook Edit Mode to reapply styling
function ActionBars:HookEditMode()
    if EditModeManagerFrame then
        -- Hook EnterEditMode
        if EditModeManagerFrame.EnterEditMode then
            hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
                -- Set all mouseover bars to full alpha in edit mode
                SetAllMouseoverBarsToFullAlpha()
                C_Timer.After(0.2, function()
                    ActionBars:StyleAllBars()
                    -- Set alpha again after StyleAllBars to ensure it stays at 1.0
                    SetAllMouseoverBarsToFullAlpha()
                end)
            end)
        end
        
        -- Hook ExitEditMode
        if EditModeManagerFrame.ExitEditMode then
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
                C_Timer.After(0.2, function()
                    ActionBars:StyleAllBars()
                    -- Restore mouseover bars to configured alpha after exiting edit mode
                    RestoreMouseoverBarsAlpha()
                end)
            end)
        end
        
        -- Register callback if available
        if EditModeManagerFrame.RegisterCallback then
            EditModeManagerFrame:RegisterCallback("EditModeEnter", function()
                -- Set all mouseover bars to full alpha in edit mode
                SetAllMouseoverBarsToFullAlpha()
                C_Timer.After(0.2, function()
                    ActionBars:StyleAllBars()
                    -- Set alpha again after StyleAllBars to ensure it stays at 1.0
                    SetAllMouseoverBarsToFullAlpha()
                end)
            end)
            
            EditModeManagerFrame:RegisterCallback("EditModeExit", function()
                C_Timer.After(0.2, function()
                    ActionBars:StyleAllBars()
                    -- Restore mouseover bars to configured alpha after exiting edit mode
                    RestoreMouseoverBarsAlpha()
                end)
            end)
        end
    end
end

-- Initialize function
function ActionBars:Initialize()
    local cfg = NephUI.db.profile.actionBars
    if not cfg or not cfg.enabled then
        return
    end
    
    -- Wait for action bars to be fully loaded
    C_Timer.After(0.5, function()
        self:StyleAllBars()
        self:HookButtonCreation()
        self:HookEditMode()
    end)
    
    -- Also style after PLAYER_LOGIN
    NephUI:RegisterEvent("PLAYER_LOGIN", function()
        C_Timer.After(0.5, function()
            self:StyleAllBars()
        end)
    end)
    
    -- Periodic check to catch any buttons we might have missed (only once after a delay)
    C_Timer.After(2.0, function()
        self:StyleAllBars()
    end)
end

-- Refresh function
function ActionBars:RefreshAll()
    -- Clear processed buttons cache
    processedButtons = {}
    
    -- Re-style all bars
    self:StyleAllBars()
    
    -- Reconfigure mouseover behavior
    ConfigureMouseoverBars()
end

