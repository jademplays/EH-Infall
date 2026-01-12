local ADDON_NAME, ns = ...
local NephUI = ns.Addon

NephUI.AbsorbBars = NephUI.AbsorbBars or {}
local AbsorbBars = NephUI.AbsorbBars

local AbsorbBarUnitToFrame = {
    player = "NephUI_Player",
    target = "NephUI_Target",
    -- Boss frames will be handled dynamically
}

-- Generic function to create absorb bar for a unit
local function CreateAbsorbBarForUnit(unit)
    local frameName = AbsorbBarUnitToFrame[unit]

    -- Handle boss frames dynamically
    if not frameName and unit:match("^boss%d+$") then
        frameName = "NephUI_Boss" .. unit:match("^boss(%d+)$")
    end

    if not frameName then return end
    
    -- Wait for unit frame to exist
    local unitFrame = _G[frameName]
    if not unitFrame then
        C_Timer.After(0.5, function() CreateAbsorbBarForUnit(unit) end)
        return
    end
    
    if unitFrame.__nephuiAbsorbBar then
        return
    end
    
    local healthBar = unitFrame.healthBar
    if not healthBar then
        return
    end
    
    -- Create absorb bar frame as child of unitFrame (same parent as power bar)
    -- This ensures proper frame level ordering: Health (bottom), Absorb (middle), Power (top)
    local absorbBarName = frameName .. "_AbsorbBar"
    local absorbBar = CreateFrame("StatusBar", absorbBarName, unitFrame)
    absorbBar:SetFrameStrata("MEDIUM")
    -- Set frame level to be ABOVE the health bar but BELOW the power bar
    -- Health bar is at base level, absorb should be +1, power should be +2
    local function UpdateAbsorbBarFrameLevel()
        local healthLevel = (healthBar.GetFrameLevel and healthBar:GetFrameLevel()) or 0
        local powerBar = unitFrame.powerBar
        if powerBar and powerBar:IsShown() and powerBar.GetFrameLevel then
            -- Keep absorb below power, but never below the health bar texture.
            local powerLevel = powerBar:GetFrameLevel()
            absorbBar:SetFrameLevel(math.max(healthLevel + 1, powerLevel - 1))
        else
            -- Power bar doesn't exist or is hidden, set absorb to be above health.
            absorbBar:SetFrameLevel(healthLevel + 1)
        end
    end
    UpdateAbsorbBarFrameLevel()
    
    -- Anchor to health bar's status bar texture for precise alignment
    -- Initial positioning will be updated by UpdateAbsorbBarPosition
    local healthBarTexture = healthBar:GetStatusBarTexture()
    if not healthBarTexture then
        healthBarTexture = healthBar
    end
    absorbBar:SetPoint("TOPLEFT", healthBarTexture, "TOPLEFT", 0, 0)
    absorbBar:SetPoint("BOTTOMRIGHT", healthBarTexture, "BOTTOMRIGHT", 0, 0)
    
    -- Function to update texture from config
    local function UpdateAbsorbBarTexture()
        local db = NephUI.db.profile.unitFrames
        if not db or not db[unit] or not db[unit].AbsorbBar then
            local tex = NephUI:GetGlobalTexture()
            if tex then
                absorbBar:SetStatusBarTexture(tex)
            else
                absorbBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            end
            return
        end
        
        local textureName = db[unit].AbsorbBar.Texture or "Neph"
        local LSM = LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local texture = LSM:Fetch("statusbar", textureName)
            if texture then
                absorbBar:SetStatusBarTexture(texture)
            else
                local tex = NephUI:GetGlobalTexture()
                if tex then
                    absorbBar:SetStatusBarTexture(tex)
                else
                    absorbBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                end
            end
        else
            local tex = NephUI:GetGlobalTexture()
            if tex then
                absorbBar:SetStatusBarTexture(tex)
            else
                absorbBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            end
        end
    end
    
    -- Function to update color from config
    local function UpdateAbsorbBarColor()
        local db = NephUI.db.profile.unitFrames
        if not db or not db[unit] or not db[unit].AbsorbBar then
            -- Default: light blue/purple for absorbs
            absorbBar:SetStatusBarColor(0.3, 0.6, 1.0, 0.8)
            return
        end
        
        local color = db[unit].AbsorbBar.Color or {0.3, 0.6, 1.0, 0.8}
        local r, g, b, a = color[1], color[2], color[3], color[4] or 0.8
        absorbBar:SetStatusBarColor(r, g, b, a)
    end
    
    UpdateAbsorbBarTexture()
    UpdateAbsorbBarColor()
    
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    
    -- Set fill direction based on config (default to left)
    local function UpdateAbsorbBarFillDirection()
        local db = NephUI.db.profile.unitFrames
        if not db or not db[unit] or not db[unit].AbsorbBar then
            -- Default: left to right (anchored left, grows right)
            absorbBar:SetReverseFill(false)
            return
        end
        
        local fillDirection = db[unit].AbsorbBar.FillDirection or "left"
        if fillDirection == "right" then
            -- Right to left (anchored right, grows left)
            absorbBar:SetReverseFill(true)
        else
            -- Left to right (anchored left, grows right)
            absorbBar:SetReverseFill(false)
        end
    end
    
    -- Set initial fill direction
    UpdateAbsorbBarFillDirection()
    
    -- Ensure text tags render above the absorb bar by setting their frame levels higher
    -- The absorb bar is at healthBar:GetFrameLevel() - 1, so text tags need to be higher
    local function UpdateTextTagFrameLevels()
        -- Create a high-level parent frame for text tags if it doesn't exist
        -- Parent it to unitFrame (not healthBar) since text tags are anchored to unitFrame
        if not unitFrame.__textTagParent then
            local textTagParent = CreateFrame("Frame", nil, unitFrame)
            textTagParent:SetFrameStrata("MEDIUM")
            textTagParent:SetFrameLevel(healthBar:GetFrameLevel() + 20)
            textTagParent:SetAllPoints(unitFrame)
            textTagParent:SetAlpha(1) -- Fully visible to ensure children are visible
            textTagParent:EnableMouse(false)
            textTagParent:Show() -- Make sure it's shown
            unitFrame.__textTagParent = textTagParent
        end
        
        -- Reparent text tags to the high-level parent
        local textTagParent = unitFrame.__textTagParent
        if unitFrame.NameText then
            local wasShown = unitFrame.NameText:IsShown()
            unitFrame.NameText:SetParent(textTagParent)
            unitFrame.NameText:SetDrawLayer("OVERLAY")
            if wasShown then
                unitFrame.NameText:Show()
            end
        end
        if unitFrame.HealthText then
            local wasShown = unitFrame.HealthText:IsShown()
            unitFrame.HealthText:SetParent(textTagParent)
            unitFrame.HealthText:SetDrawLayer("OVERLAY")
            if wasShown then
                unitFrame.HealthText:Show()
            end
        end
        if unitFrame.PowerText then
            local wasShown = unitFrame.PowerText:IsShown()
            unitFrame.PowerText:SetParent(textTagParent)
            unitFrame.PowerText:SetDrawLayer("OVERLAY")
            if wasShown then
                unitFrame.PowerText:Show()
            end
        end
    end
    
    -- Update text tag frame levels after a short delay to ensure they're created
    C_Timer.After(0.1, UpdateTextTagFrameLevels)
    
    -- Also update text tag levels periodically to ensure they stay on top
    -- This handles cases where the unit frame might be recreated or updated
    local textTagUpdateTicker = C_Timer.NewTicker(1.0, function()
        if unitFrame and unitFrame.__nephuiAbsorbBar then
            UpdateTextTagFrameLevels()
        else
            -- Stop ticking if the frame is gone
            if textTagUpdateTicker then
                textTagUpdateTicker:Cancel()
            end
        end
    end)
    
    -- Function to update position and size (in case health bar moves or resizes)
    local function UpdateAbsorbBarPosition()
        if not absorbBar or not healthBar then return end
        
        local db = NephUI.db.profile.unitFrames
        local anchorMode = "health"
        if db and db[unit] and db[unit].AbsorbBar then
            anchorMode = db[unit].AbsorbBar.AnchorMode or "health"
        end
        
        -- Get health bar's status bar texture for precise anchoring
        local healthBarTexture = healthBar:GetStatusBarTexture()
        if not healthBarTexture then
            -- Fallback to health bar if texture doesn't exist
            healthBarTexture = healthBar
        end
        
        -- Check if power bar is enabled and shown, and get its height
        local powerBarEnabled = false
        local powerBarHeight = 0
        local powerBar = unitFrame.powerBar
        if powerBar and powerBar:IsShown() then
            -- Check database to see if power bar is enabled
            if db and db[unit] then
                local DB = db[unit]
                -- Handle both PowerBar and powerBar (case variations)
                local PowerBarDB = DB.PowerBar or DB.powerBar
                if PowerBarDB and PowerBarDB.Enabled ~= false then
                    -- Check if alternate power bar is shown (for player unit)
                    -- Alternate power bar takes precedence
                    local alternatePowerBarShown = false
                    if unit == "player" then
                        local altPowerBar = unitFrame.alternatePowerBar
                        if altPowerBar and altPowerBar:IsShown() and DB.AlternatePowerBar and DB.AlternatePowerBar.Enabled then
                            alternatePowerBarShown = true
                        end
                    end
                    if not alternatePowerBarShown then
                        powerBarEnabled = true
                        -- Get power bar height from database (default to 3 if not set)
                        local rawPowerBarHeight = PowerBarDB.Height or 3
                        -- The power bar border extends 1 pixel above the power bar
                        -- The health bar's bottom edge is at the power bar's top edge (0, 0 offset)
                        -- To align with the border's top edge (which is 1 pixel above power bar top),
                        -- we need to inset by: powerBarHeight + 1 pixel (for the border extension)
                        -- However, since the border extends 1 pixel up, we actually want to align
                        -- with the border's top edge, so we need powerBarHeight + 1
                        powerBarHeight = rawPowerBarHeight + 1
                    end
                end
            end
        end
        
        -- Calculate bottom inset: power bar height + 1 pixel spacing if enabled, 0 otherwise
        local bottomInset = powerBarHeight
        
        -- Re-anchor based on anchor mode
        absorbBar:ClearAllPoints()
        
        if anchorMode == "health" then
            -- Attach to health texture (covers entire health bar area - current behavior)
            absorbBar:SetPoint("TOPLEFT", healthBarTexture, "TOPLEFT", 0, 0)
            -- If power bar is enabled, anchor bottom edge to power bar border's top edge for precise alignment
            if powerBarEnabled and powerBar and powerBar.border then
                -- The power bar border extends 1 pixel outside the power bar on all sides
                -- The health bar is inset 1 pixel from the unit frame, same as the power bar
                -- So we need to account for the border's extension: anchor to border's top edge
                -- but adjust horizontally to align with health bar edges (border extends 1px left/right)
                absorbBar:SetPoint("BOTTOMLEFT", powerBar.border, "TOPLEFT", 1, 0)
                absorbBar:SetPoint("BOTTOMRIGHT", powerBar.border, "TOPRIGHT", -1, 0)
            else
                -- No power bar, use inset calculation
                absorbBar:SetPoint("BOTTOMRIGHT", healthBarTexture, "BOTTOMRIGHT", 0, bottomInset)
            end
        elseif anchorMode == "healthEnd" then
            -- Attach to end of health texture (starts where health ends)
            -- Get current health percentage to determine where health ends
            local currentHealth = UnitHealth(unit)
            local maxHealth = UnitHealthMax(unit)
            local healthPercent = (maxHealth > 0) and (currentHealth / maxHealth) or 0
            
            -- Get health bar width to calculate where health ends
            local healthBarWidth = healthBar:GetWidth()
            
            -- Calculate X offset where health ends (from left edge of health bar)
            local healthEndX = healthBarWidth * healthPercent
            
            -- Anchor absorb bar starting from where health ends
            -- TOPLEFT starts at health end position
            if powerBarEnabled and powerBar and powerBar.border then
                -- Anchor bottom edge to power bar border's top edge for precise alignment
                -- Account for border's 1 pixel extension on left/right sides
                absorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", healthEndX, 0)
                absorbBar:SetPoint("BOTTOMLEFT", powerBar.border, "TOPLEFT", 1, 0)
                absorbBar:SetPoint("BOTTOMRIGHT", powerBar.border, "TOPRIGHT", -1, 0)
            else
                -- No power bar, use inset calculation
                absorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", healthEndX, 0)
                absorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, bottomInset)
            end
        elseif anchorMode == "frame" then
            -- Attach to end of unit frame (anchored to frame itself, not health texture)
            absorbBar:SetPoint("TOPLEFT", unitFrame, "TOPLEFT", 1, -1)
            absorbBar:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", -1, 1 + bottomInset)
        end
        
        -- Also update frame level in case power bar changed
        UpdateAbsorbBarFrameLevel()
    end
    
    -- Store references and update functions
    unitFrame.__nephuiAbsorbBar = absorbBar
    absorbBar.healthBar = healthBar
    absorbBar.unitFrame = unitFrame
    absorbBar.unit = unit
    absorbBar.UpdateFillDirection = UpdateAbsorbBarFillDirection
    absorbBar.UpdateTexture = UpdateAbsorbBarTexture
    absorbBar.UpdateColor = UpdateAbsorbBarColor
    absorbBar.UpdateFrameLevel = UpdateAbsorbBarFrameLevel
    absorbBar.UpdatePosition = UpdateAbsorbBarPosition
    
    -- Hook power bar updates to adjust absorb bar frame level and position
    local function HookPowerBarUpdates()
        local powerBar = unitFrame.powerBar
        if powerBar then
            -- Update frame level and position when power bar is shown/hidden
            powerBar:HookScript("OnShow", function()
                UpdateAbsorbBarFrameLevel()
                UpdateAbsorbBarPosition()
            end)
            powerBar:HookScript("OnHide", function()
                UpdateAbsorbBarFrameLevel()
                UpdateAbsorbBarPosition()
            end)
        end
        
        -- Hook alternate power bar if it exists
        local alternatePowerBar = unitFrame.alternatePowerBar
        if alternatePowerBar then
            alternatePowerBar:HookScript("OnShow", function()
                UpdateAbsorbBarPosition()
            end)
            alternatePowerBar:HookScript("OnHide", function()
                UpdateAbsorbBarPosition()
            end)
        end
    end
    
    -- Try to hook power bar immediately, or wait if it doesn't exist yet
    if unitFrame.powerBar then
        HookPowerBarUpdates()
    else
        -- Wait a bit for power bar to be created
        C_Timer.After(0.1, HookPowerBarUpdates)
    end
    
    -- Hook unit frame's OnSizeChanged to update position
    unitFrame:HookScript("OnSizeChanged", UpdateAbsorbBarPosition)
    
    -- Initial position update
    UpdateAbsorbBarPosition()
    
    -- Update function - NO MATH, just display the raw value
    local function UpdateAbsorbBar()
        -- Get absorb amount directly - no math, no comparisons, just get the value
        local absorbAmount = UnitGetTotalAbsorbs(unit)
        
        -- Get max health for the bar range
        local maxHealth = UnitHealthMax(unit)
        
        -- Set bar range (using maxHealth directly, no math)
        absorbBar:SetMinMaxValues(0, maxHealth)
        
        -- Set the absorb value directly - no calculations, just display the raw value
        -- Use absorbAmount as-is, or 0 if nil (no comparison, just nil-coalescing)
        absorbBar:SetValue(absorbAmount or 0)
        
        -- Update fill direction, texture, and color in case they changed
        UpdateAbsorbBarFillDirection()
        UpdateAbsorbBarTexture()
        UpdateAbsorbBarColor()
        
        -- Update position in case power bars changed visibility
        UpdateAbsorbBarPosition()
        
        -- Show the bar (it will naturally show/hide based on value)
        absorbBar:Show()
    end
    
    -- Register events
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    -- Register target change event for target unit
    if unit == "target" then
        eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    end
    
    eventFrame:SetScript("OnEvent", function(self, event, eventUnit)
        if event == "PLAYER_TARGET_CHANGED" and unit == "target" then
            UpdateAbsorbBar()
        elseif (eventUnit == unit) or (not eventUnit and (event == "PLAYER_ENTERING_WORLD")) then
            UpdateAbsorbBar()
        end
    end)
    
    -- Initial update
    UpdateAbsorbBar()
end

function AbsorbBars:Initialize()
    C_Timer.After(0.5, function()
        CreateAbsorbBarForUnit("player")
        CreateAbsorbBarForUnit("target")
        -- Create absorb bars for boss frames
        for i = 1, 8 do
            CreateAbsorbBarForUnit("boss" .. i)
        end
    end)
    C_Timer.After(1.0, function()
        CreateAbsorbBarForUnit("player")
        CreateAbsorbBarForUnit("target")
        -- Create absorb bars for boss frames
        for i = 1, 8 do
            CreateAbsorbBarForUnit("boss" .. i)
        end
    end)
    C_Timer.After(2.0, function()
        CreateAbsorbBarForUnit("player")
        CreateAbsorbBarForUnit("target")
        -- Create absorb bars for boss frames
        for i = 1, 8 do
            CreateAbsorbBarForUnit("boss" .. i)
        end
    end)
end

