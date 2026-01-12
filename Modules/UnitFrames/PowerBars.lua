local ADDON_NAME, ns = ...
local NephUI = ns.Addon

-- Get UnitFrames module
local UF = NephUI.UnitFrames
if not UF then
    error("NephUI: UnitFrames module not initialized! Load UnitFrames.lua first.")
end

-- Get helper functions
local GetPowerBarDB = UF.GetPowerBarDB
local FetchPowerBarColor = UF.FetchPowerBarColor
local PowerBarColor = UF.PowerBarColor

local function GetUnitDB(unit)
    local db = NephUI.db and NephUI.db.profile and NephUI.db.profile.unitFrames
    if not db or not unit then return nil end
    local dbUnit = unit
    if unit:match("^boss(%d+)$") then dbUnit = "boss" end
    return db[dbUnit]
end

local function AlternatePowerBarShown(unitFrame, unit, DB)
    if unit ~= "player" then return false end
    if not unitFrame then return false end
    local altPowerBar = unitFrame.alternatePowerBar
    if not altPowerBar or not altPowerBar:IsShown() then return false end
    return DB and DB.AlternatePowerBar and DB.AlternatePowerBar.Enabled
end

local function UpdateHealthBarForPower(unitFrame, unit, DB)
    if not unitFrame or not unitFrame.healthBar then return end
    if AlternatePowerBarShown(unitFrame, unit, DB) then return end
    local powerBar = unitFrame.powerBar
    local hasPowerBar = powerBar and powerBar:IsShown()

    unitFrame.healthBar:ClearAllPoints()
    unitFrame.healthBar:SetPoint("TOPLEFT", unitFrame, "TOPLEFT", 1, -1)
    if hasPowerBar then
        unitFrame.healthBar:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT", 0, 0)
        unitFrame.healthBar:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT", 0, 0)
    else
        unitFrame.healthBar:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", -1, 1)
    end
end

UF.UpdateHealthBarForPower = UpdateHealthBarForPower

-- Update power bar event handler
local function UpdateUnitFramePowerBar(self, event, eventUnit, ...)
    local unit = self.unit
    if not unit then return end

    local DB = GetUnitDB(unit)
    local PowerBarDB = DB and GetPowerBarDB(DB)
    if not PowerBarDB or not PowerBarDB.Enabled then
        self:Hide()
        if self.border then
            self.border:Hide()
        end
        local unitFrame = self:GetParent()
        UpdateHealthBarForPower(unitFrame, unit, DB)
        return
    end
    
    -- Handle target change events - always update for these (unit might be new target)
    local isTargetChangeEvent = (event == "PLAYER_TARGET_CHANGED" and unit == "target") or 
                                (event == "PLAYER_FOCUS_CHANGED" and unit == "focus")
    
    -- For target change events, check if unit exists, but still try to update
    if not isTargetChangeEvent then
        if not UnitExists(unit) then return end
    else
        -- For target change, if unit doesn't exist, hide the bar
        if not UnitExists(unit) then
            self:Hide()
            return
        end
    end
    
    -- If event has a unit parameter, only update if it matches our unit
    -- (UNIT_POWER_UPDATE, UNIT_POWER_FREQUENT, UNIT_MAXPOWER, UNIT_DISPLAYPOWER all pass unit)
    if eventUnit and eventUnit ~= unit then return end
    
    -- For target and focus: if hooked, skip value updates (values come from Blizzard's bars)
    local isTargetOrFocus = (unit == "target" or unit == "focus")
    if isTargetOrFocus and self.__hookedToBlizzard then
        -- Power bar is hooked to Blizzard's bar, only update color if needed
        -- Try to get power type for color (this should be safe)
        local pType = UnitPowerType(unit)
        if pType then
            local col = PowerBarColor[pType] or { r = 0.8, g = 0.8, b = 0.8 }
            self:SetStatusBarColor(col.r, col.g, col.b)
        end
        return
    end
    
    -- Get power type and values (may return nil/secret values in combat)
    local pType = UnitPowerType(unit)
    local unitPower = UnitPower(unit, pType)
    local unitMaxPower = UnitPowerMax(unit, pType)
    
    -- Check if values are numbers before comparing (secret values aren't numbers)
    local powerIsValid = type(unitPower) == "number"
    local maxPowerIsValid = type(unitMaxPower) == "number"

    -- If we have secret values, use safe defaults and skip the update
    if not powerIsValid or not maxPowerIsValid then
        -- Can't safely update in combat with secret values, just show the bar with last known state
        self:Show()
        return
    end

    -- Handle case where maxPower is 0 (no power type or dead unit)
    -- Use pcall to safely check comparison since secret values pass type check but can't be compared
    local maxPowerIsZero = false
    if maxPowerIsValid then
        local success, result = pcall(function() return unitMaxPower <= 0 end)
        if success then
            maxPowerIsZero = result
        else
            -- If comparison fails (secret value), assume it's not zero to avoid errors
            maxPowerIsZero = false
        end
    end

    if maxPowerIsZero then
        -- No power type; hide the power bar and let health fill the space.
        self:Hide()
        if self.border then
            self.border:Hide()
        end
        local unitFrame = self:GetParent()
        local DB = GetUnitDB(unit)
        UpdateHealthBarForPower(unitFrame, unit, DB)
        return
    end
    
    self:Show()
    
    -- Use PowerBarColor for target and focus, otherwise use FetchPowerBarColor
    if isTargetOrFocus then
        local col = PowerBarColor[pType] or { r = 0.8, g = 0.8, b = 0.8 }
        self:SetStatusBarColor(col.r, col.g, col.b)
    else
        local r, g, b, a = FetchPowerBarColor(unit)
        self:SetStatusBarColor(r, g, b, a)
    end
    
    self:SetMinMaxValues(0, unitMaxPower)
    self:SetValue(unitPower)
    
    -- Ensure background color is always applied (important when power is 0)
    if self.bg then
        local db = NephUI.db.profile.unitFrames
        if db then
            local dbUnit = unit
            if unit:match("^boss(%d+)$") then dbUnit = "boss" end
            local DB = db[dbUnit]
            if DB then
                local PowerBarDB = GetPowerBarDB(DB)
                if PowerBarDB then
                    local bgColor = PowerBarDB.BGColor
                    if not bgColor or type(bgColor) ~= "table" or not bgColor[1] or not bgColor[2] or not bgColor[3] then
                        bgColor = {0.1, 0.1, 0.1, 0.7}
                    end
                    local bgR, bgG, bgB, bgA = unpack(bgColor)
                    if not bgA then bgA = bgColor[4] or 0.7 end
                    self.bg:SetVertexColor(bgR, bgG, bgB, bgA)
                end
            end
        end
    end
end

-- Export event handler
UF.UpdateUnitFramePowerBar = UpdateUnitFramePowerBar

-- Create power bar for a unit frame
function UF:CreatePowerBar(unitFrame, unit, DB, PowerBarDB)
    if not PowerBarDB then return end
    
    local unitFramePowerBar = CreateFrame("StatusBar", nil, unitFrame)
    unitFrame.powerBar = unitFramePowerBar

    if not unitFramePowerBar.__nephuiHealthAnchorHooks then
        unitFramePowerBar.__nephuiHealthAnchorHooks = true
        unitFramePowerBar:HookScript("OnShow", function(bar)
            local parentFrame = bar:GetParent()
            local barUnit = bar.unit or (parentFrame and parentFrame.unit)
            local barDB = GetUnitDB(barUnit)
            UpdateHealthBarForPower(parentFrame, barUnit, barDB)
        end)
        unitFramePowerBar:HookScript("OnHide", function(bar)
            local parentFrame = bar:GetParent()
            local barUnit = bar.unit or (parentFrame and parentFrame.unit)
            local barDB = GetUnitDB(barUnit)
            UpdateHealthBarForPower(parentFrame, barUnit, barDB)
        end)
    end
    
    if PowerBarDB.Enabled then
        local barHeight = PowerBarDB.Height
        
        unitFramePowerBar:SetStatusBarTexture(self.Media.ForegroundTexture)
        unitFramePowerBar:SetHeight(barHeight)
        unitFramePowerBar:SetPoint("BOTTOMLEFT", unitFrame, "BOTTOMLEFT", 1, 1)
        unitFramePowerBar:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", -1, 1)
        
        if not unitFramePowerBar.bg then
            unitFramePowerBar.bg = unitFramePowerBar:CreateTexture(nil, "BACKGROUND")
            unitFramePowerBar.bg:SetAllPoints()
        end
        
        -- Set texture first, then color - ensure color is applied
        unitFramePowerBar.bg:SetTexture(self.Media.BackgroundTexture)
        -- Get BGColor from database - ensure we have a valid color
        local bgColor = PowerBarDB.BGColor
        if not bgColor or type(bgColor) ~= "table" or not bgColor[1] or not bgColor[2] or not bgColor[3] then
            bgColor = {0.1, 0.1, 0.1, 0.7}
        end
        local r, g, b, a = unpack(bgColor)
        -- Ensure alpha is set (default to 0.7 if not provided)
        if not a then a = bgColor[4] or 0.7 end
        -- Apply vertex color - this tints the texture (WHITE8X8 will be tinted by this)
        unitFramePowerBar.bg:SetVertexColor(r, g, b, a)
        
        -- Create 1 pixel border for power bar
        if not unitFramePowerBar.border then
            local border = CreateFrame("Frame", nil, unitFramePowerBar, "BackdropTemplate")
            border:SetPoint("TOPLEFT", unitFramePowerBar, -1, 1)
            border:SetPoint("BOTTOMRIGHT", unitFramePowerBar, 1, -1)
            border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            border:SetBackdropBorderColor(0, 0, 0, 1)
            border:SetFrameLevel(unitFramePowerBar:GetFrameLevel() + 1)
            unitFramePowerBar.border = border
        end
        unitFramePowerBar.border:Show()
        
        unitFramePowerBar:Show()
        -- Ensure color is applied after showing (sometimes needed for initial load)
        unitFramePowerBar.bg:SetVertexColor(r, g, b, a)
        
        UpdateHealthBarForPower(unitFrame, unit, DB)
    else
        unitFramePowerBar:Hide()
        if unitFramePowerBar.border then
            unitFramePowerBar.border:Hide()
        end
        UpdateHealthBarForPower(unitFrame, unit, DB)
    end
    
    unitFramePowerBar.unit = unit
    unitFramePowerBar:RegisterEvent("UNIT_POWER_UPDATE")
    unitFramePowerBar:RegisterEvent("UNIT_POWER_FREQUENT") -- More frequent updates in combat
    unitFramePowerBar:RegisterEvent("UNIT_MAXPOWER")
    unitFramePowerBar:RegisterEvent("UNIT_DISPLAYPOWER") -- For power type changes
    -- Register target change event for target/focus frames
    if unit == "target" then
        unitFramePowerBar:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif unit == "focus" then
        unitFramePowerBar:RegisterEvent("PLAYER_FOCUS_CHANGED")
    end
    unitFramePowerBar:SetScript("OnEvent", UpdateUnitFramePowerBar)
    UpdateUnitFramePowerBar(unitFramePowerBar)
end

-- Update power bar (called from UpdateUnitFrame)
function UF:UpdatePowerBar(unitFrame, unit, DB, PowerBarDB)
    if not unitFrame or not PowerBarDB then return end
    
    local unitPowerBar = unitFrame.powerBar
    if not unitPowerBar then return end
    
    -- Check if alternate power bar is shown (for player unit)
    -- Alternate power bar takes precedence, so hide regular power bar if alternate is shown
    local alternatePowerBarShown = AlternatePowerBarShown(unitFrame, unit, DB)
    
    if PowerBarDB.Enabled and not alternatePowerBarShown then
        local unitPowerBarHeight = PowerBarDB.Height
        unitPowerBar:SetHeight(unitPowerBarHeight)
        unitPowerBar:SetStatusBarTexture(self.Media.ForegroundTexture)
        unitPowerBar:ClearAllPoints()
        unitPowerBar:SetPoint("BOTTOMLEFT", unitFrame, "BOTTOMLEFT", 1, 1)
        unitPowerBar:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", -1, 1)
        
        if not unitPowerBar.bg then
            unitPowerBar.bg = unitPowerBar:CreateTexture(nil, "BACKGROUND")
            unitPowerBar.bg:SetAllPoints()
        end
        -- Set texture first, then color - ensure color is applied
        unitPowerBar.bg:SetTexture(self.Media.BackgroundTexture)
        -- Get BGColor from database - ensure we have a valid color
        local bgColor = PowerBarDB.BGColor
        if not bgColor or type(bgColor) ~= "table" or not bgColor[1] or not bgColor[2] or not bgColor[3] then
            bgColor = {0.1, 0.1, 0.1, 0.7}
        end
        local r, g, b, a = unpack(bgColor)
        -- Ensure alpha is set (default to 0.7 if not provided)
        if not a then a = bgColor[4] or 0.7 end
        -- Apply vertex color - this tints the texture (WHITE8X8 will be tinted by this)
        unitPowerBar.bg:SetVertexColor(r, g, b, a)
        
        -- Create or update 1 pixel border for power bar
        if not unitPowerBar.border then
            local border = CreateFrame("Frame", nil, unitPowerBar, "BackdropTemplate")
            border:SetPoint("TOPLEFT", unitPowerBar, -1, 1)
            border:SetPoint("BOTTOMRIGHT", unitPowerBar, 1, -1)
            border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            border:SetBackdropBorderColor(0, 0, 0, 1)
            border:SetFrameLevel(unitPowerBar:GetFrameLevel() + 1)
            unitPowerBar.border = border
        end
        unitPowerBar.border:Show()
        
        unitPowerBar:Show()
        
        UpdateHealthBarForPower(unitFrame, unit, DB)
        
        -- Force update power bar values when unit frame updates (e.g., target change)
        UpdateUnitFramePowerBar(unitPowerBar)
    else
        unitPowerBar:Hide()
        if unitPowerBar.border then
            unitPowerBar.border:Hide()
        end
        UpdateHealthBarForPower(unitFrame, unit, DB)
    end
end

-- Hook into Blizzard's target and focus power bars to avoid secret value issues
function UF:HookTargetAndFocusPowerBars()
    -- Hook Target power bar
    local targetFrame = _G["TargetFrame"]
    local targetPowerBar = targetFrame and (targetFrame.manabar or targetFrame.powerBar)
    if targetPowerBar and not targetPowerBar.__nephuiHooked then
        targetPowerBar.__nephuiHooked = true
        
        -- Get our custom target power bar
        local targetUnitFrame = _G["NephUI_Target"]
        local customTargetPowerBar = targetUnitFrame and targetUnitFrame.powerBar
        
        if customTargetPowerBar then
            customTargetPowerBar.__hookedToBlizzard = true
            
            -- Function to sync values from Blizzard's bar to ours
            local function SyncTargetPowerBar()
                if not customTargetPowerBar then return end
                
                local value = targetPowerBar:GetValue()
                local min, max = targetPowerBar:GetMinMaxValues()
                if min and max then
                    customTargetPowerBar:SetMinMaxValues(min, max)
                    customTargetPowerBar:SetValue(value or 0)
                    
                    -- Update power text from Blizzard's bar values (check if enabled)
                    if targetUnitFrame and targetUnitFrame.PowerText then
                        local db = NephUI.db.profile.unitFrames
                        local PowerTextDB = db and db.target and db.target.Tags and db.target.Tags.Power
                        if PowerTextDB and PowerTextDB.Enabled ~= false then
                            local powerValue = value or 0
                            local maxValue = max
                            if type(powerValue) == "number" and type(maxValue) == "number" then
                                local displayStyle = PowerTextDB.DisplayStyle or "both"
                                if displayStyle == "current" then
                                    targetUnitFrame.PowerText:SetFormattedText("%d", powerValue)
                                else
                                    targetUnitFrame.PowerText:SetFormattedText("%d / %d", powerValue, maxValue)
                                end
                                targetUnitFrame.PowerText:Show()
                            end
                        else
                            targetUnitFrame.PowerText:Hide()
                        end
                    end
                end
            end
            
            -- Hook OnValueChanged to mirror values
            targetPowerBar:HookScript("OnValueChanged", function(self, value)
                if not customTargetPowerBar then return end
                SyncTargetPowerBar()
            end)

            -- Hook OnMinMaxChanged to sync when min/max values change
            if targetPowerBar:GetScript("OnMinMaxChanged") == nil then
                targetPowerBar:HookScript("OnMinMaxChanged", function(self)
                    if not customTargetPowerBar then return end
                    SyncTargetPowerBar()
                end)
            end
            
            -- Hook OnShow to sync when Blizzard's bar shows
            targetPowerBar:HookScript("OnShow", function(self)
                if not customTargetPowerBar then return end
                SyncTargetPowerBar()
                customTargetPowerBar:Show()
            end)
            
            -- Hook OnHide to hide our bar when Blizzard's hides
            targetPowerBar:HookScript("OnHide", function()
                if customTargetPowerBar then
                    customTargetPowerBar:Hide()
                end
            end)
            
            -- Removed OnUpdate hook - OnValueChanged should be sufficient for syncing
            
            -- Initial sync if Blizzard's bar is already shown
            if targetPowerBar:IsShown() then
                SyncTargetPowerBar()
                customTargetPowerBar:Show()
            end
        end
    end
    
    -- Hook Focus power bar
    local focusFrame = _G["FocusFrame"]
    local focusPowerBar = focusFrame and (focusFrame.manabar or focusFrame.powerBar)
    if focusPowerBar and not focusPowerBar.__nephuiHooked then
        focusPowerBar.__nephuiHooked = true
        
        -- Get our custom focus power bar
        local focusUnitFrame = _G["NephUI_Focus"]
        local customFocusPowerBar = focusUnitFrame and focusUnitFrame.powerBar
        
        if customFocusPowerBar then
            customFocusPowerBar.__hookedToBlizzard = true
            
            -- Function to sync values from Blizzard's bar to ours
            local function SyncFocusPowerBar()
                if not customFocusPowerBar then return end
                
                local value = focusPowerBar:GetValue()
                local min, max = focusPowerBar:GetMinMaxValues()
                if min and max then
                    customFocusPowerBar:SetMinMaxValues(min, max)
                    customFocusPowerBar:SetValue(value or 0)
                    
                    -- Update power text from Blizzard's bar values (check if enabled)
                    if focusUnitFrame and focusUnitFrame.PowerText then
                        local db = NephUI.db.profile.unitFrames
                        local PowerTextDB = db and db.focus and db.focus.Tags and db.focus.Tags.Power
                        if PowerTextDB and PowerTextDB.Enabled ~= false then
                            local powerValue = value or 0
                            local maxValue = max
                            if type(powerValue) == "number" and type(maxValue) == "number" then
                                local displayStyle = PowerTextDB.DisplayStyle or "both"
                                if displayStyle == "current" then
                                    focusUnitFrame.PowerText:SetFormattedText("%d", powerValue)
                                else
                                    focusUnitFrame.PowerText:SetFormattedText("%d / %d", powerValue, maxValue)
                                end
                                focusUnitFrame.PowerText:Show()
                            end
                        else
                            focusUnitFrame.PowerText:Hide()
                        end
                    end
                end
            end
            
            -- Hook OnValueChanged to mirror values
            focusPowerBar:HookScript("OnValueChanged", function(self, value)
                if not customFocusPowerBar then return end
                SyncFocusPowerBar()
            end)

            -- Hook OnMinMaxChanged to sync when min/max values change
            if focusPowerBar:GetScript("OnMinMaxChanged") == nil then
                focusPowerBar:HookScript("OnMinMaxChanged", function(self)
                    if not customFocusPowerBar then return end
                    SyncFocusPowerBar()
                end)
            end
            
            -- Hook OnShow to sync when Blizzard's bar shows
            focusPowerBar:HookScript("OnShow", function(self)
                if not customFocusPowerBar then return end
                SyncFocusPowerBar()
                customFocusPowerBar:Show()
            end)
            
            -- Hook OnHide to hide our bar when Blizzard's hides
            focusPowerBar:HookScript("OnHide", function()
                if customFocusPowerBar then
                    customFocusPowerBar:Hide()
                end
            end)
            
            -- Removed OnUpdate hook - OnValueChanged should be sufficient for syncing
            
            -- Initial sync if Blizzard's bar is already shown
            if focusPowerBar:IsShown() then
                SyncFocusPowerBar()
                customFocusPowerBar:Show()
            end
        end
    end
end
