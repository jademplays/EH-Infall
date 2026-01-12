local ADDON_NAME, ns = ...
local NephUI = ns.Addon
local C_Timer = _G.C_Timer
local GetTime = _G.GetTime

-- Create namespace
NephUI.ResourceBars = NephUI.ResourceBars or {}
local ResourceBars = NephUI.ResourceBars

-- Update throttling to prevent flashing and improve performance
local lastPrimaryUpdate = 0
local lastSecondaryUpdate = 0
local UPDATE_THROTTLE = 0.066  -- 66ms minimum between updates (~15fps)

-- Get functions from sub-modules
local GetPrimaryResource = ResourceBars.GetPrimaryResource
local GetSecondaryResource = ResourceBars.GetSecondaryResource

local runeUpdateTicker = nil


local function StopRuneUpdateTicker()
    if runeUpdateTicker then
        runeUpdateTicker:Cancel()
        runeUpdateTicker = nil
    end
end

local function AreRunesRecharging()
    if type(GetRuneCooldown) ~= "function" then
        return false
    end

    local maxRunes = UnitPowerMax("player", Enum.PowerType.Runes) or 0
    if maxRunes <= 0 then
        maxRunes = 6
    end

    for i = 1, maxRunes do
        local start, duration, runeReady = GetRuneCooldown(i)
        if not runeReady and ((duration and duration > 0) or (start and start > 0)) then
            return true
        end
    end

    return false
end

local function StartRuneUpdateTicker()
    if runeUpdateTicker then return end

    runeUpdateTicker = C_Timer.NewTicker(0.1, function()
        local cfg = NephUI.db and NephUI.db.profile and NephUI.db.profile.secondaryPowerBar
        if cfg and cfg.enabled == false then
            StopRuneUpdateTicker()
            return
        end

        local resource = GetSecondaryResource()
        if resource == Enum.PowerType.Runes and AreRunesRecharging() then
            lastSecondaryUpdate = GetTime()
            ResourceBars:UpdateSecondaryPowerBar()
        else
            StopRuneUpdateTicker()
        end
    end)
end

-- EVENT HANDLER

function ResourceBars:OnUnitPower(_, unit)
    -- Be forgiving: if unit is nil or not "player", still update.
    -- It's cheap and avoids missing power updates.
    if unit and unit ~= "player" then
        return
    end

    local now = GetTime()
    if now - lastPrimaryUpdate >= UPDATE_THROTTLE then
        self:UpdatePowerBar()
        lastPrimaryUpdate = now
    end
    if now - lastSecondaryUpdate >= UPDATE_THROTTLE then
        self:UpdateSecondaryPowerBar()
        lastSecondaryUpdate = now
    end
end

function ResourceBars:OnRuneEvent()
    local cfg = NephUI.db and NephUI.db.profile and NephUI.db.profile.secondaryPowerBar
    if cfg and cfg.enabled == false then
        StopRuneUpdateTicker()
        return
    end

    local resource = GetSecondaryResource()
    if resource ~= Enum.PowerType.Runes then
        StopRuneUpdateTicker()
        return
    end

    local now = GetTime()
    if now - lastSecondaryUpdate >= UPDATE_THROTTLE then
        lastSecondaryUpdate = now
        self:UpdateSecondaryPowerBar()
    end

    if AreRunesRecharging() then
        StartRuneUpdateTicker()
    else
        StopRuneUpdateTicker()
    end
end

-- REFRESH

function ResourceBars:RefreshAll()
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
end

-- EVENT HANDLERS

function ResourceBars:OnSpecChanged()
    local now = GetTime()
    lastPrimaryUpdate = now
    lastSecondaryUpdate = now
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

    local resource = GetSecondaryResource()
    if resource == Enum.PowerType.Runes and AreRunesRecharging() then
        StartRuneUpdateTicker()
    else
        StopRuneUpdateTicker()
    end
end

function ResourceBars:OnShapeshiftChanged()
    -- Druid form changes affect primary/secondary resources
    local now = GetTime()
    lastPrimaryUpdate = now
    lastSecondaryUpdate = now
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
end

-- INITIALIZATION

function ResourceBars:Initialize()
    -- Register additional events
    NephUI:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function()
        ResourceBars:OnSpecChanged()
    end)
    NephUI:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function()
        ResourceBars:OnShapeshiftChanged()
    end)
    NephUI:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        ResourceBars:OnUnitPower()
    end)

    -- POWER UPDATES
    NephUI:RegisterEvent("UNIT_POWER_FREQUENT", function(_, unit)
        ResourceBars:OnUnitPower(_, unit)
    end)
    NephUI:RegisterEvent("UNIT_POWER_UPDATE", function(_, unit)
        ResourceBars:OnUnitPower(_, unit)
    end)
    NephUI:RegisterEvent("UNIT_MAXPOWER", function(_, unit)
        ResourceBars:OnUnitPower(_, unit)
    end)

    -- RUNES: rune cooldown progression does not reliably trigger UNIT_POWER_* updates,
    -- so we listen to rune-specific events and optionally poll while runes are recharging.
    NephUI:RegisterEvent("RUNE_POWER_UPDATE", function()
        ResourceBars:OnRuneEvent()
    end)
    NephUI:RegisterEvent("RUNE_TYPE_UPDATE", function()
        ResourceBars:OnRuneEvent()
    end)

    local resource = GetSecondaryResource()
    if resource == Enum.PowerType.Runes and AreRunesRecharging() then
        StartRuneUpdateTicker()
    else
        StopRuneUpdateTicker()
    end


    -- Initial update (delayed to ensure anchor frames are ready)
    C_Timer.After(0.1, function()
        ResourceBars:UpdatePowerBar()
        ResourceBars:UpdateSecondaryPowerBar()
    end)

    -- Also update after a short delay to catch any late-loading frames
    C_Timer.After(0.5, function()
        ResourceBars:UpdatePowerBar()
        ResourceBars:UpdateSecondaryPowerBar()
    end)
end

-- Expose event handlers to main addon for backwards compatibility
NephUI.OnUnitPower = function(self, _, unit) return ResourceBars:OnUnitPower(_, unit) end
NephUI.OnSpecChanged = function(self) return ResourceBars:OnSpecChanged() end
NephUI.OnShapeshiftChanged = function(self) return ResourceBars:OnShapeshiftChanged() end

