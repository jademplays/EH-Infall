local ADDON_NAME, ns = ...
local NephUI = ns.Addon

-- Get UnitFrames module
local UF = NephUI.UnitFrames
if not UF then
    error("NephUI: UnitFrames module not initialized! Load UnitFrames.lua first.")
end

-- Get helper functions
local ResolveFrameName = UF.ResolveFrameName
local GetPowerBarDB = UF.GetPowerBarDB
local FetchNameTextColor = UF.FetchNameTextColor
local UpdateUnitAuras = UF.UpdateUnitAuras

-- Get UpdateUnitFrame event handler (from FrameUpdates.lua)
-- This will be set when FrameUpdates.lua loads
local UpdateUnitFrameEventHandler = nil

-- Get UpdateUnitFramePowerBar (from PowerBars.lua)
-- This will be set when PowerBars.lua loads
local UpdateUnitFramePowerBar = nil

-- Create unit frame
function UF:CreateUnitFrame(unit)
    local db = NephUI.db.profile.unitFrames
    if not db then return end
    
    local dbUnit = unit
    if unit:match("^boss(%d+)$") then dbUnit = "boss" end
    local DB = db[dbUnit]
    local GeneralDB = db.General
    if not DB or not DB.Enabled then return end
    
    local TagsDB = DB.Tags
    local NameDB = TagsDB and TagsDB.Name
    local HealthDB = TagsDB and TagsDB.Health
    local frameName = ResolveFrameName(unit)
    local unitFrame = CreateFrame("Button", frameName, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    
    unitFrame:SetSize(DB.Frame.Width, DB.Frame.Height)
    self:ApplyFrameLayer(unitFrame, GeneralDB)
    if self.ApplyFramePosition then
        self:ApplyFramePosition(unitFrame, unit, DB)
    end
    
    -- Create edit mode anchor if needed (will be shown/hidden based on Edit Mode state)
    if not unitFrame.editModeAnchor and self.CreateEditModeAnchor then
        self:CreateEditModeAnchor(unit)
    end
    
    unitFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    unitFrame:SetBackdropColor(0, 0, 0, 0) -- Transparent background
    unitFrame:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Create background health bar for missing health visualization
    unitFrame.healthBarBG = CreateFrame("StatusBar", nil, unitFrame)
    unitFrame.healthBarBG:SetStatusBarTexture(self.Media.BackgroundTexture)
    unitFrame.healthBarBG:SetReverseFill(true) -- Fill from right to left to show missing health

    -- Create foreground health bar for current health
    unitFrame.healthBar = CreateFrame("StatusBar", nil, unitFrame)
    unitFrame.healthBar:SetPoint("TOPLEFT", unitFrame, "TOPLEFT", 1, -1)
    unitFrame.healthBar:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", -1, 1)
    unitFrame.healthBar:SetStatusBarTexture(self.Media.ForegroundTexture)

    -- Keep missing-health bar aligned to the health bar so it never overlaps the power bar
    unitFrame.healthBarBG:ClearAllPoints()
    unitFrame.healthBarBG:SetAllPoints(unitFrame.healthBar)

    -- Set background health bar color (missing health)
    local bgR, bgG, bgB, bgA = unpack(DB.Frame.BGColor)
    unitFrame.healthBarBG:SetStatusBarColor(bgR, bgG, bgB, bgA)
    
    -- Ensure media is resolved (in case it wasn't called yet)
    if not self.Media or not self.Media.Font then
        self:ResolveMedia()
    end
    
    -- Name text
    unitFrame.NameText = unitFrame.healthBar:CreateFontString(nil, "OVERLAY")
    unitFrame.NameText:SetFont(self.Media.Font, DB.Tags.Name.FontSize, GeneralDB.FontFlag)
    unitFrame.NameText:SetPoint(DB.Tags.Name.AnchorFrom, unitFrame, DB.Tags.Name.AnchorTo, DB.Tags.Name.OffsetX, DB.Tags.Name.OffsetY)
    unitFrame.NameText:SetJustifyH(self:SetJustification(DB.Tags.Name.AnchorFrom))
    local statusColorR, statusColorG, statusColorB = FetchNameTextColor(unit, DB, GeneralDB)
    unitFrame.NameText:SetTextColor(statusColorR, statusColorG, statusColorB)
    unitFrame.NameText:SetShadowColor(unpack(GeneralDB.FontShadows.Color))
    unitFrame.NameText:SetShadowOffset(GeneralDB.FontShadows.OffsetX, GeneralDB.FontShadows.OffsetY)
    if NameDB.Enabled then
        unitFrame.NameText:Show()
    else
        unitFrame.NameText:Hide()
    end
    
    -- Health text
    unitFrame.HealthText = unitFrame.healthBar:CreateFontString(nil, "OVERLAY")
    unitFrame.HealthText:SetFont(self.Media.Font, DB.Tags.Health.FontSize, GeneralDB.FontFlag)
    unitFrame.HealthText:SetPoint(DB.Tags.Health.AnchorFrom, unitFrame, DB.Tags.Health.AnchorTo, DB.Tags.Health.OffsetX, DB.Tags.Health.OffsetY)
    unitFrame.HealthText:SetJustifyH(self:SetJustification(DB.Tags.Health.AnchorFrom))
    unitFrame.HealthText:SetTextColor(unpack(DB.Tags.Health.Color))
    unitFrame.HealthText:SetShadowColor(unpack(GeneralDB.FontShadows.Color))
    unitFrame.HealthText:SetShadowOffset(GeneralDB.FontShadows.OffsetX, GeneralDB.FontShadows.OffsetY)
    if HealthDB.Enabled then
        unitFrame.HealthText:Show()
    else
        unitFrame.HealthText:Hide()
    end
    
    -- Power text (for player, target, focus, boss)
    local PowerTextDB = DB.Tags and DB.Tags.Power
    if PowerTextDB and (unit == "player" or unit == "target" or unit == "focus" or unit:match("^boss%d+$")) then
        unitFrame.PowerText = unitFrame.healthBar:CreateFontString(nil, "OVERLAY")
        unitFrame.PowerText:SetFont(self.Media.Font, PowerTextDB.FontSize or DB.Tags.Health.FontSize, GeneralDB.FontFlag)
        unitFrame.PowerText:SetPoint(PowerTextDB.AnchorFrom or "BOTTOMRIGHT", unitFrame, PowerTextDB.AnchorTo or "BOTTOMRIGHT", PowerTextDB.OffsetX or -4, PowerTextDB.OffsetY or 4)
        unitFrame.PowerText:SetJustifyH(self:SetJustification(PowerTextDB.AnchorFrom or "BOTTOMRIGHT"))
        unitFrame.PowerText:SetTextColor(unpack(PowerTextDB.Color or DB.Tags.Health.Color))
        unitFrame.PowerText:SetShadowColor(unpack(GeneralDB.FontShadows.Color))
        unitFrame.PowerText:SetShadowOffset(GeneralDB.FontShadows.OffsetX, GeneralDB.FontShadows.OffsetY)
        if PowerTextDB.Enabled ~= false then
            unitFrame.PowerText:Show()
        else
            unitFrame.PowerText:Hide()
        end
    end
    
    -- Power bar (for player, target, focus) - handled by PowerBars.lua
    if unit ~= "targettarget" and unit ~= "pet" then
        local PowerBarDB = GetPowerBarDB(DB)
        if PowerBarDB and self.CreatePowerBar then
            self:CreatePowerBar(unitFrame, unit, DB, PowerBarDB)
        end
    end
    
    -- Leader/Assistant indicator (player frame only)
    if unit == "player" and DB.LeaderIndicator then
        local LeaderDB = DB.LeaderIndicator
        if not unitFrame.leaderIndicator then
            -- Create a frame to hold the texture for better layering control
            local leaderFrame = CreateFrame("Frame", nil, unitFrame)
            leaderFrame:SetSize(LeaderDB.Size or 15, LeaderDB.Size or 15)
            leaderFrame:SetPoint(LeaderDB.AnchorFrom or "RIGHT", unitFrame, LeaderDB.AnchorTo or "TOPRIGHT", LeaderDB.OffsetX or -3, LeaderDB.OffsetY or 0)
            leaderFrame:SetFrameLevel(unitFrame:GetFrameLevel() + 25)
            leaderFrame:SetFrameStrata("HIGH")
            
            -- Create texture on the frame using Blizzard's leader icon
            local leaderTexture = leaderFrame:CreateTexture(nil, "OVERLAY")
            leaderTexture:SetAllPoints()
            leaderTexture:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            
            unitFrame.leaderIndicator = leaderFrame
            unitFrame.leaderIndicator.texture = leaderTexture
            unitFrame.leaderIndicator:Hide()
        end
    end
    
    -- Status indicators (Combat & Resting) - player frame only
    if unit == "player" and DB.StatusIndicators then
        local StatusIndicatorsDB = DB.StatusIndicators
        
        -- Combat indicator
        if StatusIndicatorsDB.Combat then
            local CombatDB = StatusIndicatorsDB.Combat
            if not unitFrame.combatIndicator then
                -- Create a frame to hold the texture for better layering control
                local combatFrame = CreateFrame("Frame", nil, unitFrame)
                combatFrame:SetSize(CombatDB.Size or 24, CombatDB.Size or 24)
                combatFrame:SetPoint(CombatDB.AnchorFrom or "CENTER", unitFrame, CombatDB.AnchorTo or "TOPLEFT", CombatDB.OffsetX or 3, CombatDB.OffsetY or -3)
                combatFrame:SetFrameLevel(unitFrame:GetFrameLevel() + 5)
                combatFrame:SetFrameStrata("HIGH")
                
                -- Create texture on the frame
                local combatTexture = combatFrame:CreateTexture(nil, "OVERLAY")
                combatTexture:SetAllPoints()
                
                -- Set texture based on setting
                local textureType = CombatDB.Texture or "DEFAULT"
                if textureType == "DEFAULT" then
                    -- Use Blizzard's default combat icon
                    combatTexture:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
                    combatTexture:SetTexCoord(0.5, 1, 0, 0.49)
                else
                    -- Custom texture path (can be extended later for custom textures)
                    combatTexture:SetTexture(textureType)
                    combatTexture:SetTexCoord(0, 1, 0, 1)
                end
                
                unitFrame.combatIndicator = combatFrame
                unitFrame.combatIndicator.texture = combatTexture
                unitFrame.combatIndicator:Hide()
            end
        end
        
        -- Resting indicator
        if StatusIndicatorsDB.Resting then
            local RestingDB = StatusIndicatorsDB.Resting
            if not unitFrame.restingIndicator then
                -- Create a frame to hold the texture for better layering control
                local restingFrame = CreateFrame("Frame", nil, unitFrame)
                restingFrame:SetSize(RestingDB.Size or 24, RestingDB.Size or 24)
                restingFrame:SetPoint(RestingDB.AnchorFrom or "CENTER", unitFrame, RestingDB.AnchorTo or "TOPLEFT", RestingDB.OffsetX or 3, RestingDB.OffsetY or -3)
                restingFrame:SetFrameLevel(unitFrame:GetFrameLevel() + 5)
                restingFrame:SetFrameStrata("HIGH")
                
                -- Create texture on the frame
                local restingTexture = restingFrame:CreateTexture(nil, "OVERLAY")
                restingTexture:SetAllPoints()
                
                -- Set texture based on setting
                local textureType = RestingDB.Texture or "DEFAULT"
                if textureType == "DEFAULT" then
                    -- Use Blizzard's default resting icon
                    restingTexture:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
                    restingTexture:SetTexCoord(0, 0.5, 0, 0.421875)
                else
                    -- Custom texture path (can be extended later for custom textures)
                    restingTexture:SetTexture(textureType)
                    restingTexture:SetTexCoord(0, 1, 0, 1)
                end
                
                unitFrame.restingIndicator = restingFrame
                unitFrame.restingIndicator.texture = restingTexture
                unitFrame.restingIndicator:Hide()
            end
        end
    end
    
    -- Frame attributes
    unitFrame.unit = unit
    unitFrame:RegisterForClicks("AnyUp")
    unitFrame:SetAttribute("unit", unit)
    unitFrame:SetAttribute("*type1", "target")
    unitFrame:SetAttribute("*type2", "togglemenu")
    
    -- Events
    unitFrame:RegisterEvent("UNIT_HEALTH")
    unitFrame:RegisterEvent("UNIT_MAXHEALTH")
    unitFrame:RegisterEvent("UNIT_NAME_UPDATE")
    unitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    unitFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    -- Keep target name in sync with target-of-target inline display
    if unit == "target" then
        unitFrame:RegisterEvent("UNIT_TARGET")
    end
    
    -- Status indicator events (player frame only)
    if unit == "player" then
        unitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        unitFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        unitFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
    end
    
    -- Leader indicator events (player frame)
    if unit == "player" then
        unitFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        unitFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    end
    
    -- Register power events for power text updates
    if unit == "player" or unit == "target" or unit == "focus" or unit:match("^boss%d+$") then
        unitFrame:RegisterEvent("UNIT_POWER_UPDATE")
        unitFrame:RegisterEvent("UNIT_MAXPOWER")
    end
    
    -- Register UNIT_AURA for target and boss frames to update auras
    if unit == "target" or unit:match("^boss%d+$") then
        unitFrame:RegisterEvent("UNIT_AURA")
    end
    
    -- Special event for targettarget: listen to when target's target changes
    if unit == "targettarget" then
        unitFrame:RegisterEvent("UNIT_TARGET")
    end
    
    RegisterUnitWatch(unitFrame, false)
    unitFrame.__nephuiUnitWatchActive = true
    unitFrame.__nuiUFMouseoverActive = unitFrame:IsMouseOver() == true
    UF.UpdateMouseoverHighlight(unitFrame)
    
    --[[
    local function SetTooltipDefault(owner)
        -- Use Blizzard's default anchor, which respects user settings
        if GameTooltip_SetDefaultAnchor then
            GameTooltip_SetDefaultAnchor(GameTooltip, owner or UIParent)
        else
            -- Fallback: behave like a typical default bottom-right tooltip
            GameTooltip:SetOwner(owner or UIParent, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -13, 130)
        end
    end
    ]]
    
    unitFrame:SetScript("OnEnter", function(self)
        UF.SetMouseoverHighlightState(self, true)
        -- Tooltip intentionally disabled
        -- local unit = self.unit
        -- if unit and UnitExists(unit) then
        --     SetTooltipDefault(self)
        --     GameTooltip:SetUnit(unit)
        -- end
    end)
    unitFrame:SetScript("OnLeave", function(self)
        UF.SetMouseoverHighlightState(self, false)
        -- Tooltip intentionally disabled
        -- GameTooltip:Hide()
    end)

    -- Update frame when shown (important for boss frames)
    unitFrame:SetScript("OnShow", function(self)
        UF.UpdateUnitFrame(self.unit)
    end)

    unitFrame:SetScript("OnEvent", function(self, event, eventUnit)
        -- Only update for events that affect this unit
        if eventUnit and eventUnit ~= self.unit then return end
        -- For events without eventUnit (like PLAYER_TARGET_CHANGED), check if this frame needs updating
        if not eventUnit and event == "PLAYER_TARGET_CHANGED" and self.unit ~= "target" then return end
        if not eventUnit and event == "PLAYER_FOCUS_CHANGED" and self.unit ~= "focus" then return end
        if not eventUnit and event == "PLAYER_ENTERING_WORLD" then
            -- Always update on entering world
        elseif not eventUnit then
            return -- Ignore other events without eventUnit
        end

        UF.UpdateUnitFrame(self.unit)
    end)
    
    if unit == "pet" then unitFrame:RegisterEvent("UNIT_PET") end
    if unit == "focus" then unitFrame:RegisterEvent("PLAYER_FOCUS_CHANGED") end
    
    -- Set event handler (will be set by FrameUpdates.lua)
    if UF.UpdateUnitFrameEventHandler then
        unitFrame:SetScript("OnEvent", UF.UpdateUnitFrameEventHandler)
    end
    
    -- Initial update
    if UF.UpdateUnitFrameEventHandler then
        UF.UpdateUnitFrameEventHandler(unitFrame)
    end
    
    -- Update unit auras if this is a player, focus, target, or boss frame
    if (unit == "player" or unit == "focus" or unit == "target" or unit:match("^boss%d+$")) and UpdateUnitAuras then
        UpdateUnitAuras(unitFrame)
    end
end

