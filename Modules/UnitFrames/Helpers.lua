local ADDON_NAME, ns = ...
local NephUI = ns.Addon

-- Get UnitFrames module
local UF = NephUI.UnitFrames
if not UF then
    error("NephUI: UnitFrames module not initialized! Load UnitFrames.lua first.")
end

-- Helper to get PowerBar DB (handles both PowerBar and powerBar)
local function GetPowerBarDB(DB)
    return DB.PowerBar or DB.powerBar
end

-- Fetch unit color based on settings
local function FetchUnitColor(unit, DB, GeneralDB)
    if not DB or not DB.Frame then return 0.1, 0.1, 0.1, 1 end
    
    if DB.Frame.ClassColor then
        if unit == "pet" then
            local _, playerClass = UnitClass("player")
            if type(playerClass) == "string" then
                local playerClassColor = RAID_CLASS_COLORS[playerClass]
                if playerClassColor then
                    return playerClassColor.r, playerClassColor.g, playerClassColor.b
                end
            end
        end
    
        -- Safely check if unit is player (may return secret value in combat)
        local isPlayer = UnitIsPlayer(unit)
        if type(isPlayer) == "boolean" and isPlayer then
            local _, class = UnitClass(unit)
            if type(class) == "string" then
                local unitClassColor = RAID_CLASS_COLORS[class]
                if unitClassColor then
                    return unitClassColor.r, unitClassColor.g, unitClassColor.b
                end
            end
        end
    end
    
    if DB.Frame.ReactionColor then
        local reaction = UnitReaction(unit, "player")
        if type(reaction) == "number" then
            local reactionColors = GeneralDB and GeneralDB.CustomColors and GeneralDB.CustomColors.Reaction
            local reactionColor = reactionColors and reactionColors[reaction]
            if reactionColor then
                return reactionColor[1], reactionColor[2], reactionColor[3]
            end
        end
    end
    
    local fgColor = DB.Frame.FGColor or {0.1, 0.1, 0.1, 1}
    return fgColor[1], fgColor[2], fgColor[3], fgColor[4] or 1
end

-- Fetch name text color
local function FetchNameTextColor(unit, DB, GeneralDB)
    if not DB or not DB.Tags or not DB.Tags.Name then return 1, 1, 1 end
    
    if DB.Tags.Name.ColorByStatus then
        if unit == "pet" then
            local _, playerClass = UnitClass("player")
            if type(playerClass) == "string" then
                local playerClassColor = RAID_CLASS_COLORS[playerClass]
                if playerClassColor then
                    return playerClassColor.r, playerClassColor.g, playerClassColor.b
                end
            end
        end
    
        -- Safely check if unit is player (may return secret value in combat)
        local isPlayer = UnitIsPlayer(unit)
        if type(isPlayer) == "boolean" and isPlayer then
            local _, class = UnitClass(unit)
            if type(class) == "string" then
                local classColor = RAID_CLASS_COLORS[class]
                if classColor then
                    return classColor.r, classColor.g, classColor.b
                end
            end
        end
        
        local reaction = UnitReaction(unit, "player")
        if type(reaction) == "number" then
            local reactionColors = GeneralDB and GeneralDB.CustomColors and GeneralDB.CustomColors.Reaction
            local reactionColor = reactionColors and reactionColors[reaction]
            if reactionColor then
                return reactionColor[1], reactionColor[2], reactionColor[3]
            end
        end
    end
    
    local unitTextColor = DB.Tags.Name.Color or {1, 1, 1, 1}
    return unitTextColor[1], unitTextColor[2], unitTextColor[3]
end

-- Fetch power bar color
local function FetchPowerBarColor(unit)
    local db = NephUI.db.profile.unitFrames
    if not db then return 1, 1, 1, 1 end
    
    local dbUnit = unit
    if unit:match("^boss(%d+)$") then dbUnit = "boss" end
    local DB = db[dbUnit]
    local GeneralDB = db.General
    local PowerBarDB = DB and GetPowerBarDB(DB)
    if not DB or not PowerBarDB then return 1, 1, 1, 1 end
    
    if PowerBarDB.ColorByType then
        local powerToken = UnitPowerType(unit)
        if powerToken then
            local color = GeneralDB and GeneralDB.CustomColors and GeneralDB.CustomColors.Power and GeneralDB.CustomColors.Power[powerToken]
            if color then
                return color[1], color[2], color[3], color[4] or 1
            end
        end
    end
    
    local powerBarFG = PowerBarDB.FGColor or {0.5, 0.5, 0.5, 1}
    return powerBarFG[1], powerBarFG[2], powerBarFG[3], powerBarFG[4] or 1
end

-- Get anchor frame by name
local function GetAnchorFrame(anchorName)
    if not anchorName or anchorName == "" then
        return UIParent
    end
    
    local frame = _G[anchorName]
    if frame then
        return frame
    end
    
    -- Fallback to UIParent if frame not found
    return UIParent
end

-- Shared event frame for deferred mouse disabling (protected in combat)
local mouseDisableEventFrame = nil
local pendingMouseDisableFrames = {}

local function ProcessPendingMouseDisables()
    if InCombatLockdown() then return end
    
    for frame, _ in pairs(pendingMouseDisableFrames) do
        if frame and not InCombatLockdown() then
            if frame.EnableMouse then
                frame:EnableMouse(false)
            end
            if frame.EnableMouseWheel then
                frame:EnableMouseWheel(false)
            end
        end
    end
    
    pendingMouseDisableFrames = {}
end

local function SafeDisableMouse(frame)
    if not frame then return end
    
    if InCombatLockdown() then
        pendingMouseDisableFrames[frame] = true
        
        if not mouseDisableEventFrame then
            mouseDisableEventFrame = CreateFrame("Frame")
            mouseDisableEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            mouseDisableEventFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                ProcessPendingMouseDisables()
            end)
        end
        
        mouseDisableEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        if frame.EnableMouse then
            frame:EnableMouse(false)
        end
        if frame.EnableMouseWheel then
            frame:EnableMouseWheel(false)
        end
    end
end

-- Mask frame (hide default unit frames)
local function MaskFrame(unitFrame)
    if not unitFrame or unitFrame.__cdmMasked then return end
    
    unitFrame.__cdmMasked = true
    unitFrame:SetAlpha(0)
    SafeDisableMouse(unitFrame)
    
    -- Hook OnShow to keep it hidden
    unitFrame:HookScript("OnShow", function(self)
        self:SetAlpha(0)
        SafeDisableMouse(self)
    end)
end

-- Make PlayerFrame clickthrough when unit frame customization is enabled
local function MakePlayerFrameClickthrough()
    if not PlayerFrame then return end
    
    local db = NephUI.db.profile.unitFrames
    if not db or not db.enabled then return end
    
    -- Make PlayerFrame clickthrough and invisible
    PlayerFrame:SetAlpha(0)
    SafeDisableMouse(PlayerFrame)
    
    -- Hook OnShow to keep it clickthrough and invisible
    if not PlayerFrame.__nephuiClickthroughHooked then
        PlayerFrame.__nephuiClickthroughHooked = true
        PlayerFrame:HookScript("OnShow", function(self)
            local db = NephUI.db.profile.unitFrames
            if db and db.enabled then
                self:SetAlpha(0)
                SafeDisableMouse(self)
            end
        end)
    end

    local runeFrame = _G["RuneFrame"]
    if runeFrame then
        SafeDisableMouse(runeFrame)
        if not runeFrame.__nephuiClickthroughHooked then
            runeFrame.__nephuiClickthroughHooked = true
            runeFrame:HookScript("OnShow", function(self)
                local db = NephUI.db.profile.unitFrames
                if db and db.enabled then
                    SafeDisableMouse(self)
                end
            end)
        end
    end
end

local MOUSEOVER_HIGHLIGHT_TEXTURE = "Interface\\AddOns\\NephUI\\Media\\uf_mouseover.tga"

local function GetMouseoverHighlightSettings()
    local profile = NephUI.db and NephUI.db.profile and NephUI.db.profile.unitFrames
    if not profile or profile.enabled == false then
        return nil
    end
    local general = profile.General
    local globalSettings = general and general.MouseoverHighlight
    if not globalSettings or globalSettings.Enabled == false then
        return nil
    end

    local alpha = globalSettings.Alpha or 0.5
    if type(alpha) ~= "number" then
        alpha = 0.5
    end
    alpha = math.min(1, math.max(0, alpha))

    return {
        alpha = alpha,
    }
end

local function EnsureMouseoverHighlightTexture(frame)
    if not frame then return nil end
    -- Parent to the health bar so the glow stays above the fill but within the border
    local parent = frame.healthBar or frame
    local highlight = frame.mouseoverHighlight
    if not highlight then
        highlight = parent:CreateTexture(nil, "OVERLAY")
        frame.mouseoverHighlight = highlight
    elseif highlight:GetParent() ~= parent then
        highlight:SetParent(parent)
    end

    highlight:ClearAllPoints()
    highlight:SetAllPoints(parent)
    highlight:SetTexture(MOUSEOVER_HIGHLIGHT_TEXTURE)
    highlight:SetDrawLayer("OVERLAY", 1)
    return highlight
end

local function UpdateMouseoverHighlight(frame)
    if not frame then return end
    local settings = GetMouseoverHighlightSettings()
    if not settings then
        if frame.mouseoverHighlight then
            frame.mouseoverHighlight:Hide()
        end
        frame.__nuiUFMouseoverEnabled = false
        frame.__nuiUFMouseoverActive = false
        return
    end

    local highlight = EnsureMouseoverHighlightTexture(frame)
    if not highlight then return end
    highlight:SetAlpha(settings.alpha or 0.5)
    frame.__nuiUFMouseoverEnabled = true
    highlight:SetShown(frame.__nuiUFMouseoverActive == true)
end

local function SetMouseoverHighlightState(frame, entering)
    if not frame then return end
    frame.__nuiUFMouseoverActive = entering == true
    UpdateMouseoverHighlight(frame)
end

-- Power bar color table (for target/focus)
local PowerBarColor = {
    [Enum.PowerType.Mana] = { r = 0.0, g = 0.5, b = 1.0 },
    [Enum.PowerType.Rage] = { r = 1.0, g = 0.0, b = 0.0 },
    [Enum.PowerType.Focus] = { r = 1.0, g = 0.5, b = 0.25 },
    [Enum.PowerType.Energy] = { r = 1.0, g = 1.0, b = 0.0 },
    [Enum.PowerType.ComboPoints] = { r = 1.0, g = 0.96, b = 0.41 },
    [Enum.PowerType.Runes] = { r = 0.77, g = 0.12, b = 0.23 },
    [Enum.PowerType.RunicPower] = { r = 0.0, g = 0.82, b = 1.0 },
    [Enum.PowerType.SoulShards] = { r = 0.58, g = 0.51, b = 0.79 },
    [Enum.PowerType.LunarPower] = { r = 0.3, g = 0.52, b = 0.9 },
    [Enum.PowerType.HolyPower] = { r = 0.0, g = 0.5, b = 1.0 },
    [Enum.PowerType.Maelstrom] = { r = 0.0, g = 0.5, b = 1.0 },
    [Enum.PowerType.Chi] = { r = 0.0, g = 1.0, b = 0.59 },
    [Enum.PowerType.Insanity] = { r = 0.4, g = 0.0, b = 0.8 },
    [Enum.PowerType.ArcaneCharges] = { r = 0.0, g = 0.5, b = 1.0 },
    [Enum.PowerType.Fury] = { r = 0.79, g = 0.26, b = 0.99 },
    [Enum.PowerType.Pain] = { r = 1.0, g = 0.61, b = 0.0 },
    [Enum.PowerType.Essence] = { r = 0.2, g = 0.58, b = 0.5 },
}

-- Export functions
UF.GetPowerBarDB = GetPowerBarDB
UF.FetchUnitColor = FetchUnitColor
UF.FetchNameTextColor = FetchNameTextColor
UF.FetchPowerBarColor = FetchPowerBarColor
UF.GetAnchorFrame = GetAnchorFrame
UF.MaskFrame = MaskFrame
UF.SafeDisableMouse = SafeDisableMouse
UF.PowerBarColor = PowerBarColor
UF.MakePlayerFrameClickthrough = MakePlayerFrameClickthrough
UF.UpdateMouseoverHighlight = UpdateMouseoverHighlight
UF.SetMouseoverHighlightState = SetMouseoverHighlightState
