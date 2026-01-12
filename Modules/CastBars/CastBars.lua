local ADDON_NAME, ns = ...
local NephUI = ns.Addon

-- Create namespace
NephUI.CastBars = NephUI.CastBars or {}
local CastBars = NephUI.CastBars

-- Build helpers so we can branch between Midnight (>=120000) and retail (TWW)
local BUILD_NUMBER = tonumber((select(4, GetBuildInfo()))) or 0
local IS_MIDNIGHT_OR_LATER = BUILD_NUMBER >= 120000

-- Utility functions (from Main.lua)
local function GetClassColor()
    local classColor = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
    if not classColor then
        return 1, 1, 1
    end
    return classColor.r, classColor.g, classColor.b
end

local function CreateBorder(frame)
    if frame.border then return frame.border end

    local bord = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	local borderSize = (NephUI.ScaleBorder and NephUI:ScaleBorder(1)) or math.floor((NephUI:Scale(1) or 1) + 0.5)
	local borderOffset = borderSize
	bord:SetPoint("TOPLEFT", frame, -borderOffset, borderOffset)
	bord:SetPoint("BOTTOMRIGHT", frame, borderOffset, -borderOffset)
    bord:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = borderSize,
    })
    bord:SetBackdropBorderColor(0, 0, 0, 1)
    bord:SetFrameLevel(frame:GetFrameLevel() + 1)

    frame.border = bord
    return bord
end

-- Export utilities
CastBars.GetClassColor = GetClassColor
CastBars.CreateBorder = CreateBorder
CastBars.BUILD_NUMBER = BUILD_NUMBER
CastBars.IS_MIDNIGHT_OR_LATER = IS_MIDNIGHT_OR_LATER

-- Resolve a cast icon texture across client variants
local function ResolveCastIconTexture(spellbar, unit, spellID)
    -- Midnight+ uses the new spell texture pipeline
    if IS_MIDNIGHT_OR_LATER then
        if spellID and C_Spell and C_Spell.GetSpellTexture then
            local tex = C_Spell.GetSpellTexture(spellID)
            if tex then
                return tex
            end
        end
        return 136243 -- fallback book icon
    end

    -- Retail (TWW) fallback path
    local texture

    -- First try the Blizzard spellbar's existing icon texture
    if spellbar then
        local icon = spellbar.Icon or spellbar.icon
        if icon and icon.GetTexture then
            texture = icon:GetTexture()
        end
    end

    -- Then try spell-based lookups
    if not texture and spellID then
        if GetSpellTexture then
            texture = GetSpellTexture(spellID)
        end
        if not texture and C_Spell and C_Spell.GetSpellTexture then
            texture = C_Spell.GetSpellTexture(spellID)
        end
    end

    -- Finally ask the unit APIs
    if not texture and unit then
        if UnitCastingInfo then
            local _, _, tex = UnitCastingInfo(unit)
            texture = texture or tex
        end
        if not texture and UnitChannelInfo then
            local _, _, tex = UnitChannelInfo(unit)
            texture = texture or tex
        end
    end

    return texture or 136243
end

CastBars.ResolveCastIconTexture = ResolveCastIconTexture

-- CastBar OnUpdate function
local function CastBar_OnUpdate(frame, elapsed)
    if not frame.startTime or not frame.endTime then return end

    local now = GetTime()
    if now >= frame.endTime then
        frame.castGUID  = nil
        frame.isChannel = nil
        frame.isEmpowered = nil
        frame.numStages = nil
        if frame.empoweredStages then
            for _, stage in ipairs(frame.empoweredStages) do
                stage:Hide()
            end
        end
        frame:Hide()
        frame:SetScript("OnUpdate", nil)
        return
    end

    local status = frame.status
    if not status then return end

    local duration  = frame.endTime - frame.startTime
    if duration <= 0 then duration = 0.001 end

    local remaining = frame.endTime - now
    local progress

    if frame.isChannel then
        progress = remaining
    else
        progress = now - frame.startTime
    end

    status:SetMinMaxValues(0, duration)
    status:SetValue(progress)

    if frame.timeText then
        -- Get the config for this cast bar
        local cfg
        if frame == NephUI.castBar then
            cfg = NephUI.db.profile.castBar
        elseif frame == NephUI.targetCastBar then
            cfg = NephUI.db.profile.targetCastBar
        elseif frame == NephUI.focusCastBar then
            cfg = NephUI.db.profile.focusCastBar
        elseif NephUI.bossCastBars then
            -- Check if this is a boss cast bar
            for _, bossBar in pairs(NephUI.bossCastBars) do
                if frame == bossBar then
                    cfg = NephUI.db.profile.bossCastBar
                    break
                end
            end
        end
        
        -- Show/hide time text based on setting
        if cfg and cfg.showTimeText ~= false then
            frame.timeText:Show()
            -- Boss cast bars show current/max format, others show remaining time
            if cfg == NephUI.db.profile.bossCastBar then
                frame.timeText:SetFormattedText("%.1f/%.1f", progress, duration)
            else
                frame.timeText:SetFormattedText("%.1f", remaining)
            end
        else
            frame.timeText:Hide()
        end
    end
end

-- Export CastBar_OnUpdate
CastBars.CastBar_OnUpdate = CastBar_OnUpdate

-- Initialize function
function CastBars:Initialize()
    -- Register player cast bar events
    NephUI:RegisterEvent("UNIT_SPELLCAST_START", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastStart then
            self:OnPlayerSpellcastStart(unit, castGUID, spellID)
        end
    end)
    
    NephUI:RegisterEvent("UNIT_SPELLCAST_STOP", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastStop then
            self:OnPlayerSpellcastStop(unit, castGUID, spellID)
        end
    end)
    
    NephUI:RegisterEvent("UNIT_SPELLCAST_FAILED", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastStop then
            self:OnPlayerSpellcastStop(unit, castGUID, spellID)
        end
    end)
    
    NephUI:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastStop then
            self:OnPlayerSpellcastStop(unit, castGUID, spellID)
        end
    end)
    
    NephUI:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastChannelStart then
            self:OnPlayerSpellcastChannelStart(unit, castGUID, spellID)
        end
    end)
    
    NephUI:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastStop then
            self:OnPlayerSpellcastStop(unit, castGUID, spellID)
        end
    end)
    
    NephUI:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastChannelUpdate then
            self:OnPlayerSpellcastChannelUpdate(unit, castGUID, spellID)
        end
    end)
    
    -- Register empowered cast events
    NephUI:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastEmpowerStart then
            self:OnPlayerSpellcastEmpowerStart(unit, castGUID, spellID)
        end
    end)
    
    NephUI:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastEmpowerUpdate then
            self:OnPlayerSpellcastEmpowerUpdate(unit, castGUID, spellID)
        end
    end)
    
    NephUI:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP", function(_, unit, castGUID, spellID)
        if unit == "player" and self.OnPlayerSpellcastEmpowerStop then
            self:OnPlayerSpellcastEmpowerStop(unit, castGUID, spellID)
        end
    end)
    
    -- Hook target and focus cast bars (will be called from OnEnable with delay)
    if self.HookTargetAndFocusCastBars then
        self:HookTargetAndFocusCastBars()
    end
    if self.HookFocusCastBar then
        self:HookFocusCastBar()
    end
end

-- Refresh function
function CastBars:RefreshAll()
    if self.UpdateCastBarLayout then
        self:UpdateCastBarLayout()
    end
    if self.UpdateTargetCastBarLayout then
        self:UpdateTargetCastBarLayout()
    end
    if self.UpdateFocusCastBarLayout then
        self:UpdateFocusCastBarLayout()
    end
end

-- Test functions for showing fake casts
function CastBars:ShowTestCastBar()
    if not self.GetCastBar then return end
    
    local bar = self:GetCastBar()
    if not bar then return end
    
    if self.UpdateCastBarLayout then
        self:UpdateCastBarLayout()
    end
    
    local now = GetTime()
    bar.startTime = now
    bar.endTime = now + 15
    bar.isChannel = false
    bar.castGUID = "test_" .. now
    bar.isEmpowered = false
    bar.numStages = nil
    
    bar.icon:SetTexture(136243)  -- Default spell icon
    bar.spellName:SetText("Test Cast")
    
    local cfg = NephUI.db.profile.castBar
    local font = NephUI:GetGlobalFont()
    bar.spellName:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.spellName:SetShadowOffset(0, 0)
    
    if bar.timeText then
        bar.timeText:SetFont(font, cfg.textSize or 10, "OUTLINE")
        bar.timeText:SetShadowOffset(0, 0)
    end
    
    bar:SetScript("OnUpdate", CastBar_OnUpdate)
    bar:Show()
end

function CastBars:ShowTestTargetCastBar()
    if not self.GetTargetCastBar then return end
    
    local bar = self:GetTargetCastBar()
    if not bar then return end
    
    if self.UpdateTargetCastBarLayout then
        self:UpdateTargetCastBarLayout()
    end
    
    local now = GetTime()
    bar.startTime = now
    bar.endTime = now + 15
    bar.isChannel = false
    bar.castGUID = "test_target_" .. now
    bar.isEmpowered = false
    bar.numStages = nil
    
    bar.icon:SetTexture(136243)  -- Default spell icon
    bar.spellName:SetText("Test Target Cast")
    
    local cfg = NephUI.db.profile.targetCastBar
    local font = NephUI:GetGlobalFont()
    bar.spellName:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.spellName:SetShadowOffset(0, 0)
    
    if bar.timeText then
        bar.timeText:SetFont(font, cfg.textSize or 10, "OUTLINE")
        bar.timeText:SetShadowOffset(0, 0)
    end
    
    bar:SetScript("OnUpdate", CastBar_OnUpdate)
    bar:Show()
end

function CastBars:ShowTestFocusCastBar()
    if not self.GetFocusCastBar then return end
    
    local bar = self:GetFocusCastBar()
    if not bar then return end
    
    if self.UpdateFocusCastBarLayout then
        self:UpdateFocusCastBarLayout()
    end
    
    local now = GetTime()
    bar.startTime = now
    bar.endTime = now + 15
    bar.isChannel = false
    bar.castGUID = "test_focus_" .. now
    bar.isEmpowered = false
    bar.numStages = nil
    
    bar.icon:SetTexture(136243)  -- Default spell icon
    bar.spellName:SetText("Test Focus Cast")
    
    local cfg = NephUI.db.profile.focusCastBar
    local font = NephUI:GetGlobalFont()
    bar.spellName:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.spellName:SetShadowOffset(0, 0)
    
    if bar.timeText then
        bar.timeText:SetFont(font, cfg.textSize or 10, "OUTLINE")
        bar.timeText:SetShadowOffset(0, 0)
    end
    
    bar:SetScript("OnUpdate", CastBar_OnUpdate)
    bar:Show()
end

-- Expose test functions to main addon
NephUI.ShowTestCastBar = function(self) return CastBars:ShowTestCastBar() end
NephUI.ShowTestTargetCastBar = function(self) return CastBars:ShowTestTargetCastBar() end
NephUI.ShowTestFocusCastBar = function(self) return CastBars:ShowTestFocusCastBar() end

