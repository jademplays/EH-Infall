local ADDON_NAME, ns = ...
local NephUI = ns.Addon

-- Get CastBars module
local CastBars = NephUI.CastBars
if not CastBars then
    error("NephUI: CastBars module not initialized! Load CastBars.lua first.")
end

-- EMPOWERED CAST FUNCTIONS

function CastBars:InitializeEmpoweredStages(bar)
    if not bar or not bar.isEmpowered or not bar.numStages or bar.numStages <= 0 then
        return
    end

    -- Clean up existing stages
    if bar.empoweredStages then
        for _, stage in ipairs(bar.empoweredStages) do
            if stage then
                stage:Hide()
            end
        end
    else
        bar.empoweredStages = {}
    end

    -- Create stage markers
    local status = bar.status
    if not status then return end

    -- Wait a frame for the bar to be properly sized
    C_Timer.After(0, function()
        -- Check if frame is ready by checking visibility instead of comparing width
        -- This avoids taint issues with GetWidth() comparisons
        if not status:IsVisible() then
            C_Timer.After(0.05, function()
                CastBars:InitializeEmpoweredStages(bar)
            end)
            return
        end
        
        -- Calculate width from bar dimensions to avoid taint from GetWidth()
        -- Status bar width = bar width - icon width
        local cfg = NephUI.db.profile.castBar
        local barHeight = (cfg and cfg.height) or 24
        local iconWidth = NephUI:Scale(barHeight)  -- Icon width equals bar height
        
        -- Get bar width safely - bar width is set by our code so should be less tainted
        local barOk, barW = pcall(function() return bar:GetWidth() end)
        if not barOk then
            C_Timer.After(0.05, function()
                CastBars:InitializeEmpoweredStages(bar)
            end)
            return
        end
        
        -- Calculate status bar width: bar width - icon width
        local barWidth = (tonumber(barW) or 200) - iconWidth
        if barWidth < 0 then barWidth = 100 end  -- Safety fallback

        -- Calculate tick positions based on number of stages
        -- For now, always show 4 ticks regardless of detected stages
        local tickPositions = {}
        -- Always use 4 stages: 21%, 42%, 63%, 84%
        tickPositions = {0.18, 0.42, 0.63, 0.84}
        
        -- Keep 3-stage code for later use:
        -- if bar.numStages == 4 then
        --     -- 4 stages: 21%, 42%, 63%, 84%
        --     tickPositions = {0.21, 0.42, 0.63, 0.84}
        -- else
        --     -- Default for 3 stages: 20%, 38%, 63%
        --     tickPositions = {0.20, 0.38, 0.63}
        -- end
        
        for i = 1, #tickPositions do
            local stage = bar.empoweredStages[i]
            if not stage then
                stage = status:CreateTexture(nil, "OVERLAY")
                stage:SetColorTexture(1, 1, 1, 0.8)
                stage:SetWidth(2)
                bar.empoweredStages[i] = stage
            end

            -- Get height from config to avoid taint issues with GetHeight()
            -- Use config value instead of reading from frame
            local cfg = NephUI.db.profile.castBar
            local stageHeight = (cfg and cfg.height) or 24  -- Default to 24 if config not available
            stage:SetHeight(stageHeight)

            -- Position stage marker at 20%, 38%, or 63% of bar width
            local position = tickPositions[i] * barWidth
            stage:ClearAllPoints()
            stage:SetPoint("LEFT", status, "LEFT", position - 1, 0)
            stage:SetPoint("TOP", status, "TOP", 0, 0)
            stage:SetPoint("BOTTOM", status, "BOTTOM", 0, 0)
            stage:Show()
        end
    end)
end

function CastBars:OnPlayerSpellcastEmpowerStart(unit, castGUID, spellID)
    local cfg = NephUI.db.profile.castBar
    if not cfg or not cfg.enabled then
        return
    end

    local bar = self:GetCastBar()
    self:UpdateCastBarLayout()


    local name, _, texture, startTimeMS, endTimeMS, _, _, _, _, numStages = UnitCastingInfo("player")
    
    -- Debug: Check what UnitCastingInfo returned (uncomment to debug)
    -- print("UnitCastingInfo numStages:", numStages)
    
    -- Get empowered stage info from C_Spell API if spellID is available
    -- This is more reliable than UnitCastingInfo for numStages
    if spellID and C_Spell and C_Spell.GetSpellEmpowerInfo then
        local empowerInfo = C_Spell.GetSpellEmpowerInfo(spellID)
        if empowerInfo then
            -- Debug: Check what C_Spell.GetSpellEmpowerInfo returned (uncomment to debug)
            -- print("C_Spell.GetSpellEmpowerInfo numStages:", empowerInfo.numStages)
            if empowerInfo.numStages and empowerInfo.numStages > 0 then
                numStages = empowerInfo.numStages
            end
        end
    end
    
    -- Debug: Final numStages value (uncomment to debug)
    -- print("Final numStages:", numStages)
    
    -- If UnitCastingInfo doesn't have the data, try to get spell info from spellID
    if not name or not startTimeMS or not endTimeMS then
        -- Try C_Spell API if spellID is available
        if spellID and C_Spell and C_Spell.GetSpellInfo then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo then
                if not name then
                    name = spellInfo.name
                end
                if not texture then
                    texture = spellInfo.iconID or 136243
                end
            end
        end
        
        -- If we still don't have essential data, use defaults
        if not name then
            name = "Empowered Cast"
        end
        if not texture then
            texture = 136243
        end
        if not startTimeMS or not endTimeMS then
            local now = GetTime()
            startTimeMS = now * 1000
            -- Default to 3 second empower duration
            endTimeMS = (now + 3) * 1000
        end
    end

    bar.isEmpowered = true
    bar.numStages = numStages or 3  -- Default to 3 stages if not detected
    bar.castGUID = castGUID
    bar.isChannel = false

    bar.icon:SetTexture(texture)
    bar.spellName:SetText(name)

    local font = NephUI:GetGlobalFont()
    bar.spellName:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.spellName:SetShadowOffset(0, 0)

    bar.timeText:SetFont(font, cfg.textSize or 10, "OUTLINE")
    bar.timeText:SetShadowOffset(0, 0)

    local now = GetTime()
    bar.startTime = startTimeMS / 1000
    bar.endTime = endTimeMS / 1000

    -- Safety: if start time is very old, clamp to now
    if bar.startTime < now - 5 then
        local dur = (endTimeMS - startTimeMS) / 1000
        bar.startTime = now
        bar.endTime = now + dur
    end

    -- Initialize empowered stages
    if bar.numStages and bar.numStages > 0 then
        -- Delay slightly to ensure bar is sized
        C_Timer.After(0.01, function()
            if bar.isEmpowered and bar.numStages > 0 then
                self:InitializeEmpoweredStages(bar)
            end
        end)
    end

    bar:SetScript("OnUpdate", CastBars.CastBar_OnUpdate)
    bar:Show()
end

function CastBars:OnPlayerSpellcastEmpowerUpdate(unit, castGUID, spellID)
    if not NephUI.castBar then return end
    if NephUI.castBar.castGUID and castGUID and castGUID ~= NephUI.castBar.castGUID then
        return
    end

    local bar = NephUI.castBar
    
    -- Update empowered cast info
    local name, _, texture, startTimeMS, endTimeMS, _, _, _, _, numStages = UnitCastingInfo("player")
    
    -- Get empowered stage info from C_Spell API if spellID is available
    -- This is more reliable than UnitCastingInfo for numStages
    if spellID and C_Spell and C_Spell.GetSpellEmpowerInfo then
        local empowerInfo = C_Spell.GetSpellEmpowerInfo(spellID)
        if empowerInfo then
            if empowerInfo.numStages and empowerInfo.numStages > 0 then
                numStages = empowerInfo.numStages
            end
        end
    end
    
    if startTimeMS and endTimeMS then
        bar.startTime = startTimeMS / 1000
        bar.endTime = endTimeMS / 1000
    end

    -- Update stages if number changed
    if numStages and numStages ~= bar.numStages then
        bar.numStages = numStages
        self:InitializeEmpoweredStages(bar)
    end
end

function CastBars:OnPlayerSpellcastEmpowerStop(unit, castGUID, spellID)
    if not NephUI.castBar then return end

    if castGUID and NephUI.castBar.castGUID and castGUID ~= NephUI.castBar.castGUID then
        return
    end

    -- Check if still casting (empowered cast may transition to regular cast)
    local name, _, texture, startTimeMS, endTimeMS = UnitCastingInfo("player")
    if name and startTimeMS and endTimeMS then
        -- Still casting, update the bar
        NephUI.castBar.icon:SetTexture(texture)
        NephUI.castBar.spellName:SetText(name)
        NephUI.castBar.startTime = startTimeMS / 1000
        NephUI.castBar.endTime = endTimeMS / 1000
        NephUI.castBar.isEmpowered = false
        NephUI.castBar.numStages = 0
        if NephUI.castBar.empoweredStages then
            for _, stage in ipairs(NephUI.castBar.empoweredStages) do
                stage:Hide()
            end
        end
        return
    end

    -- Cast finished, hide the bar
    NephUI.castBar.castGUID = nil
    NephUI.castBar.isChannel = nil
    NephUI.castBar.isEmpowered = nil
    NephUI.castBar.numStages = nil
    if NephUI.castBar.empoweredStages then
        for _, stage in ipairs(NephUI.castBar.empoweredStages) do
            stage:Hide()
        end
    end
    NephUI.castBar:Hide()
    NephUI.castBar:SetScript("OnUpdate", nil)
end

-- Expose to main addon for backwards compatibility
NephUI.InitializeEmpoweredStages = function(self, bar) return CastBars:InitializeEmpoweredStages(bar) end
NephUI.OnPlayerSpellcastEmpowerStart = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastEmpowerStart(unit, castGUID, spellID) end
NephUI.OnPlayerSpellcastEmpowerUpdate = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastEmpowerUpdate(unit, castGUID, spellID) end
NephUI.OnPlayerSpellcastEmpowerStop = function(self, unit, castGUID, spellID) return CastBars:OnPlayerSpellcastEmpowerStop(unit, castGUID, spellID) end

