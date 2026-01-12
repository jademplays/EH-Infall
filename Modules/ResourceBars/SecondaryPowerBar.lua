local ADDON_NAME, ns = ...
local NephUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")

-- Get ResourceBars module
local ResourceBars = NephUI.ResourceBars
if not ResourceBars then
    error("NephUI: ResourceBars module not initialized! Load ResourceDetection.lua first.")
end

-- Get functions from ResourceDetection
local GetSecondaryResource = ResourceBars.GetSecondaryResource
local GetResourceColor = ResourceBars.GetResourceColor
local GetSecondaryResourceValue = ResourceBars.GetSecondaryResourceValue
local GetChargedPowerPoints = ResourceBars.GetChargedPowerPoints
local tickedPowerTypes = ResourceBars.tickedPowerTypes
local fragmentedPowerTypes = ResourceBars.fragmentedPowerTypes

local function PixelSnap(value)
    return math.max(0, math.floor((value or 0) + 0.5))
end

-- SECONDARY POWER BAR

function ResourceBars:GetSecondaryPowerBar()
    if NephUI.secondaryPowerBar then return NephUI.secondaryPowerBar end

    local cfg = NephUI.db.profile.secondaryPowerBar
    local anchor = _G[cfg.attachTo] or UIParent
    local anchorPoint = cfg.anchorPoint or "CENTER"

    local bar = CreateFrame("Frame", ADDON_NAME .. "SecondaryPowerBar", anchor)
    bar:SetFrameStrata("MEDIUM")
    -- Keep the bar click-through so it never blocks PlayerFrame interactions
    bar:EnableMouse(false)
    bar:EnableMouseWheel(false)
    if bar.SetMouseMotionEnabled then
        bar:SetMouseMotionEnabled(false)
    end
    bar:SetHeight(NephUI:Scale(cfg.height or 4))
    bar:SetPoint("CENTER", anchor, anchorPoint, NephUI:Scale(cfg.offsetX or 0), NephUI:Scale(cfg.offsetY or 12))

    local width = cfg.width or 0
    if width <= 0 then
        width = PixelSnap(anchor.__cdmIconWidth or anchor:GetWidth())
        -- Width is already in pixels, no need to scale again
    else
        width = NephUI:Scale(width)
    end

    bar:SetWidth(width)

    -- BACKGROUND (lowest frame level)
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    -- STATUS BAR (for non-fragmented resources) - class/custom color fill
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    -- Use GetTexture helper: if cfg.texture is set, use it; otherwise use global texture
    local tex = NephUI:GetTexture(cfg.texture)
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel() + 1)

    -- BORDER - above ticks
    bar.Border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.Border:SetFrameLevel(bar:GetFrameLevel() + 4)
    local borderSize = NephUI:ScaleBorder(cfg.borderSize or 1)
    bar._scaledBorder = borderSize
    bar.Border:SetPoint("TOPLEFT", bar, -borderSize, borderSize)
    bar.Border:SetPoint("BOTTOMRIGHT", bar, borderSize, -borderSize)
    bar.Border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = borderSize,
    })
    local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
    bar.Border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

    -- TICKS FRAME - above charged overlay
    bar.TicksFrame = CreateFrame("Frame", nil, bar)
    bar.TicksFrame:SetAllPoints(bar)
    bar.TicksFrame:SetFrameLevel(bar:GetFrameLevel() + 3)

    -- CHARGED POWER OVERLAY FRAME - sits above the status bar, below ticks/border
    bar.ChargedFrame = CreateFrame("Frame", nil, bar)
    bar.ChargedFrame:SetAllPoints(bar)
    bar.ChargedFrame:SetFrameLevel(bar:GetFrameLevel() + 2)

    -- RUNE TIMER TEXT FRAME - above border
    bar.RuneTimerTextFrame = CreateFrame("Frame", nil, bar)
    bar.RuneTimerTextFrame:SetAllPoints(bar)
    bar.RuneTimerTextFrame:SetFrameLevel(bar:GetFrameLevel() + 5)

    -- TEXT FRAME - highest
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameLevel(bar:GetFrameLevel() + 6)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", NephUI:Scale(cfg.textX or 0), NephUI:Scale(cfg.textY or 0))
    bar.TextValue:SetJustifyH("CENTER")
    bar.TextValue:SetFont(NephUI:GetGlobalFont(), cfg.textSize or 12, "OUTLINE")
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")


    -- FRAGMENTED POWER BARS (for Runes)
    bar.FragmentedPowerBars = {}
    bar.FragmentedPowerBarTexts = {}

    -- TICKS
    bar.ticks = {}

    -- CHARGED POWER SEGMENTS
    bar.ChargedSegments = {}

    bar:Hide()

    NephUI.secondaryPowerBar = bar
    return bar
end

function ResourceBars:UpdateChargedPowerSegments(bar, resource, max)
    local cfg = NephUI.db.profile.secondaryPowerBar

    -- Hide all overlays first
    for _, segment in pairs(bar.ChargedSegments) do
        segment:Hide()
    end

    -- Bail out if the bar itself is hidden or not applicable
    if cfg.hideBarShowText or not resource or not max then
        return
    end

    if fragmentedPowerTypes[resource] or not tickedPowerTypes[resource] then
        return
    end

    local chargedPoints = GetChargedPowerPoints and GetChargedPowerPoints(resource)
    if not chargedPoints or #chargedPoints == 0 then
        return
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then
        return
    end

    if not max or max <= 0 then
        return
    end

    local segmentWidth = width / max
    local chargedColor = cfg.chargedColor or { 0.22, 0.62, 1.0, 0.8 }

    for _, index in ipairs(chargedPoints) do
        if index >= 1 and index <= max then
            local segment = bar.ChargedSegments[index]
            if not segment then
                segment = bar.ChargedFrame:CreateTexture(nil, "ARTWORK")
                bar.ChargedSegments[index] = segment
            end

            segment:ClearAllPoints()
            segment:SetPoint("LEFT", bar, "LEFT", (index - 1) * segmentWidth, 0)
            segment:SetSize(segmentWidth, height)
            -- Use charged color exclusively; avoid additive blend so class/custom bar colors do not tint these overlays.
            segment:SetColorTexture(chargedColor[1], chargedColor[2], chargedColor[3], chargedColor[4] or 0.8)
            segment:SetBlendMode("BLEND")
            segment:Show()
        end
    end
end

function ResourceBars:CreateFragmentedPowerBars(bar, resource)
    local cfg = NephUI.db.profile.secondaryPowerBar
    local maxPower = UnitPowerMax("player", resource)
    
    for i = 1, maxPower do
        if not bar.FragmentedPowerBars[i] then
            local fragmentBar = CreateFrame("StatusBar", nil, bar)
            -- Use GetTexture helper: if cfg.texture is set, use it; otherwise use global texture
            local tex = NephUI:GetTexture(cfg.texture)
            fragmentBar:SetStatusBarTexture(tex)
            fragmentBar:GetStatusBarTexture()
            fragmentBar:SetOrientation("HORIZONTAL")
            fragmentBar:SetFrameLevel(bar:GetFrameLevel() + 1)
            bar.FragmentedPowerBars[i] = fragmentBar
            
            -- Create text for reload time display (parented to RuneTimerTextFrame for higher frame level)
            local text = bar.RuneTimerTextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("TOP", fragmentBar, "TOP", NephUI:Scale(cfg.runeTimerTextX or 0), NephUI:Scale(cfg.runeTimerTextY or 0))
            text:SetJustifyH("CENTER")
            text:SetFont(NephUI:GetGlobalFont(), cfg.runeTimerTextSize or 10, "OUTLINE")
            text:SetShadowOffset(0, 0)
            text:SetText("")
            bar.FragmentedPowerBarTexts[i] = text
        end
    end
end

function ResourceBars:UpdateFragmentedPowerDisplay(bar, resource)
    local cfg = NephUI.db.profile.secondaryPowerBar
    local maxPower = UnitPowerMax("player", resource)
    if maxPower <= 0 then return end

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    -- Calculate base fragmented bar width - use floor to ensure pixel-perfect alignment
    -- This ensures each fragment is a whole pixel width, preventing sub-pixel rendering
    local baseFragmentedBarWidth = math.floor(barWidth / maxPower)
    -- Calculate the remaining width that needs to be distributed to the last rune
    local remainingWidth = barWidth - (baseFragmentedBarWidth * maxPower)
    
    -- Hide the main status bar fill (we display bars representing one (1) unit of resource each)
    bar.StatusBar:SetAlpha(0)

    -- Update texture for all fragmented bars (use per-bar texture if set, otherwise use global)
    local tex = NephUI:GetTexture(cfg.texture)
    for i = 1, maxPower do
        if bar.FragmentedPowerBars[i] then
            bar.FragmentedPowerBars[i]:SetStatusBarTexture(tex)
        end
    end

    local color
    local powerTypeColors = NephUI.db.profile.powerTypeColors
    if powerTypeColors.useClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            color = { r = classColor.r, g = classColor.g, b = classColor.b }
        else
            color = GetResourceColor(resource)
        end
    elseif powerTypeColors.colors[resource] then
        local r, g, b, a = powerTypeColors.colors[resource][1], powerTypeColors.colors[resource][2], powerTypeColors.colors[resource][3], powerTypeColors.colors[resource][4] or 1
        color = { r = r, g = g, b = b, a = a }
    else
        color = GetResourceColor(resource)
    end

    if resource == Enum.PowerType.Runes then
        -- Collect rune states: ready and recharging
        local readyList = {}
        local cdList = {}
        local now = GetTime()
        
        for i = 1, maxPower do
            local start, duration, runeReady = GetRuneCooldown(i)
            if runeReady then
                table.insert(readyList, { index = i })
            else
                if start and duration and duration > 0 then
                    local elapsed = now - start
                    local remaining = math.max(0, duration - elapsed)
                    local frac = math.max(0, math.min(1, elapsed / duration))
                    table.insert(cdList, { index = i, remaining = remaining, frac = frac })
                else
                    table.insert(cdList, { index = i, remaining = math.huge, frac = 0 })
                end
            end
        end

        -- Sort cdList by ascending remaining time
        table.sort(cdList, function(a, b)
            return a.remaining < b.remaining
        end)

        -- Build final display order: ready runes first, then CD runes sorted
        local displayOrder = {}
        local readyLookup = {}
        local cdLookup = {}
        
        for _, v in ipairs(readyList) do
            table.insert(displayOrder, v.index)
            readyLookup[v.index] = true
        end
        
        for _, v in ipairs(cdList) do
            table.insert(displayOrder, v.index)
            cdLookup[v.index] = v
        end

        for pos = 1, #displayOrder do
            local runeIndex = displayOrder[pos]
            local runeFrame = bar.FragmentedPowerBars[runeIndex]
            local runeText = bar.FragmentedPowerBarTexts[runeIndex]

            if runeFrame then
                runeFrame:ClearAllPoints()
                -- Calculate position using whole pixel widths for pixel-perfect alignment
                local runeX = (pos - 1) * baseFragmentedBarWidth
                -- Calculate width: last rune gets remaining width to fill the bar completely
                local runeWidth = (pos == #displayOrder) and (baseFragmentedBarWidth + remainingWidth) or baseFragmentedBarWidth
                -- barHeight is already in pixels (from bar:GetHeight()), no need to scale
                runeFrame:SetSize(runeWidth, barHeight)
                runeFrame:SetPoint("LEFT", bar, "LEFT", runeX, 0)

                -- Update rune timer text position and font size
                if runeText then
                    runeText:ClearAllPoints()
                    runeText:SetPoint("TOP", runeFrame, "TOP", NephUI:Scale(cfg.runeTimerTextX or 0), NephUI:Scale(cfg.runeTimerTextY or 0))
                    runeText:SetFont(NephUI:GetGlobalFont(), cfg.runeTimerTextSize or 10, "OUTLINE")
                    runeText:SetShadowOffset(0, 0)
                end

                local alpha = color.a or 1
                if readyLookup[runeIndex] then
                    -- Ready rune
                    runeFrame:SetMinMaxValues(0, 1)
                    runeFrame:SetValue(1)
                    runeText:SetText("")
                    runeFrame:SetStatusBarColor(color.r, color.g, color.b, alpha)
                else
                    -- Recharging rune
                    local cdInfo = cdLookup[runeIndex]
                    if cdInfo then
                        runeFrame:SetMinMaxValues(0, 1)
                        runeFrame:SetValue(cdInfo.frac)
                        
                        -- Only show timer text if enabled
                        if cfg.showFragmentedPowerBarText ~= false then
                            runeText:SetText(string.format("%.1f", math.max(0, cdInfo.remaining)))
                        else
                            runeText:SetText("")
                        end
                        
                        runeFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5, alpha)
                    else
                        runeFrame:SetMinMaxValues(0, 1)
                        runeFrame:SetValue(0)
                        runeText:SetText("")
                        runeFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5, alpha)
                    end
                end

                runeFrame:Show()
            end
        end

        -- Hide any extra rune frames beyond current maxPower
        for i = maxPower + 1, #bar.FragmentedPowerBars do
            if bar.FragmentedPowerBars[i] then
                bar.FragmentedPowerBars[i]:Hide()
                if bar.FragmentedPowerBarTexts[i] then
                    bar.FragmentedPowerBarTexts[i]:SetText("")
                end
            end
        end
        
        -- Add ticks between rune segments if enabled
        if cfg.showTicks then
            for i = 1, maxPower - 1 do
                local tick = bar.ticks[i]
                if not tick then
                    tick = bar.TicksFrame:CreateTexture(nil, "OVERLAY")
                    tick:SetColorTexture(0, 0, 0, 1)
                    bar.ticks[i] = tick
                end
                
                -- Calculate tick position using whole pixel widths for pixel-perfect alignment
                -- Position tick at the boundary between runes (i * baseFragmentedBarWidth)
                local tickX = i * baseFragmentedBarWidth
                tick:ClearAllPoints()
                tick:SetPoint("LEFT", bar, "LEFT", tickX, 0)
                -- Ensure tick width is at least 1 pixel to prevent disappearing
                local tickWidth = math.max(1, NephUI:Scale(1))
                -- barHeight is already in pixels (from bar:GetHeight()), no need to scale
                tick:SetSize(tickWidth, barHeight)
                tick:Show()
            end
            
            -- Hide extra ticks
            for i = maxPower, #bar.ticks do
                if bar.ticks[i] then
                    bar.ticks[i]:Hide()
                end
            end
        else
            -- Hide all ticks if disabled
            for _, tick in ipairs(bar.ticks) do
                tick:Hide()
            end
        end
    end
end

function ResourceBars:UpdateSecondaryPowerBarTicks(bar, resource, max)
    local cfg = NephUI.db.profile.secondaryPowerBar

    -- Hide all ticks first
    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    -- Don't show ticks if disabled, not a ticked power type, or if it's fragmented
    if not cfg.showTicks or not tickedPowerTypes[resource] or fragmentedPowerTypes[resource] then
        return
    end

    local width  = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    -- For Soul Shards, use the display max (not the internal fractional max)
    local displayMax = max
    if resource == Enum.PowerType.SoulShards then
        displayMax = UnitPowerMax("player", resource) -- non-fractional max (usually 5)
    end
    if not displayMax or displayMax <= 0 then
        return
    end

    local needed = displayMax - 1
    for i = 1, needed do
        local tick = bar.ticks[i]
        if not tick then
            tick = bar.TicksFrame:CreateTexture(nil, "OVERLAY")
            tick:SetColorTexture(0, 0, 0, 1)
            bar.ticks[i] = tick
        end

        local x = (i / displayMax) * width
        tick:ClearAllPoints()
        -- x is already in pixels (calculated from bar width), no need to scale
        tick:SetPoint("LEFT", bar.StatusBar, "LEFT", x, 0)
        -- Ensure tick width is at least 1 pixel to prevent disappearing
        local tickWidth = math.max(1, NephUI:Scale(1))
        -- height is already in pixels (from bar:GetHeight()), no need to scale
        tick:SetSize(tickWidth, height)
        tick:Show()
    end
end

function ResourceBars:UpdateSecondaryPowerBar()
    local cfg = NephUI.db.profile.secondaryPowerBar
    if not cfg.enabled then
        if NephUI.secondaryPowerBar then NephUI.secondaryPowerBar:Hide() end
        return
    end

    -- Track stagger percentage for dynamic color changes
    local bar = self:GetSecondaryPowerBar()
    local resource = GetSecondaryResource()
    if resource == "STAGGER" then
        local stagger = UnitStagger("player") or 0
        local maxHealth = UnitHealthMax("player") or 1
        local staggerPercent = (stagger / maxHealth) * 100

        -- Initialize tracking variable if it doesn't exist
        bar._lastStaggerPercent = bar._lastStaggerPercent or staggerPercent

        -- Check if we crossed a threshold and need to update colors
        if (staggerPercent >= 30 and bar._lastStaggerPercent < 30)
            or (staggerPercent < 30 and bar._lastStaggerPercent >= 30)
            or (staggerPercent >= 60 and bar._lastStaggerPercent < 60)
            or (staggerPercent < 60 and bar._lastStaggerPercent >= 60) then
            -- Force color update by clearing cached color
            bar._lastColorResource = nil
        end

        bar._lastStaggerPercent = staggerPercent
    end

    local anchor = _G[cfg.attachTo]
    if not anchor or not anchor:IsShown() then
        if NephUI.secondaryPowerBar then NephUI.secondaryPowerBar:Hide() end
        return
    end

    local bar = self:GetSecondaryPowerBar()
    local resource = GetSecondaryResource()
    
    if not resource then
        bar:Hide()
        return
    end

    -- Optionally hide when the secondary resource is mana (e.g., boomkin/ele)
    if cfg.hideWhenMana and resource == Enum.PowerType.Mana then
        if not InCombatLockdown() then
            bar:Hide()
        end
        return
    end

    -- Update layout
    local anchorPoint = cfg.anchorPoint or "CENTER"
    local desiredHeight = NephUI:Scale(cfg.height or 4)
    local desiredX = NephUI:Scale(cfg.offsetX or 0)
    local desiredY = NephUI:Scale(cfg.offsetY or 12)

    local width = cfg.width or 0
    if width <= 0 then
        width = PixelSnap(
            anchor.__cdmIconWidth
            or (NephUI.powerBar and NephUI.powerBar:IsShown() and NephUI.powerBar:GetWidth())
            or anchor:GetWidth()
        )
        -- Width is already in pixels, no need to scale again
    else
        width = NephUI:Scale(width)
    end

    -- Only reposition / resize when something actually changed to avoid texture flicker
    if bar._lastAnchor ~= anchor or bar._lastAnchorPoint ~= anchorPoint or bar._lastOffsetX ~= desiredX or bar._lastOffsetY ~= desiredY then
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", anchor, anchorPoint, desiredX, desiredY)
        bar._lastAnchor = anchor
        bar._lastAnchorPoint = anchorPoint
        bar._lastOffsetX = desiredX
        bar._lastOffsetY = desiredY
    end

    if bar._lastHeight ~= desiredHeight then
        bar:SetHeight(desiredHeight)
        bar._lastHeight = desiredHeight
    end

    if bar._lastWidth ~= width then
        bar:SetWidth(width)
        bar._lastWidth = width
    end

    -- Update background color
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    if bar.Background then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    -- Update texture (use per-bar texture if set, otherwise use global)
    local tex = NephUI:GetTexture(cfg.texture)
    if bar._lastTexture ~= tex then
        bar.StatusBar:SetStatusBarTexture(tex)
        bar._lastTexture = tex
    end

    -- Update border size and color
    local borderSize = cfg.borderSize or 1
    if bar.Border then
        local scaledBorder = NephUI:ScaleBorder(borderSize)
        bar._scaledBorder = scaledBorder
        bar.Border:ClearAllPoints()
        bar.Border:SetPoint("TOPLEFT", bar, -scaledBorder, scaledBorder)
        bar.Border:SetPoint("BOTTOMRIGHT", bar, scaledBorder, -scaledBorder)
        bar.Border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = scaledBorder,
        })
        -- Update border color
        local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
        bar.Border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        -- Show/hide border based on size
        if scaledBorder > 0 then
            bar.Border:Show()
        else
            bar.Border:Hide()
        end
    end

    -- Get resource values
    local max, maxDisplayValue, current, displayValue, valueType = GetSecondaryResourceValue(resource, cfg)
    if not max then
        bar:Hide()
        return
    end

    -- Handle fragmented power types (Runes)
    if fragmentedPowerTypes[resource] then
        self:CreateFragmentedPowerBars(bar, resource)
        self:UpdateFragmentedPowerDisplay(bar, resource)

        bar.StatusBar:SetMinMaxValues(0, max)
        bar.StatusBar:SetValue(current)

        local powerTypeColors = NephUI.db.profile.powerTypeColors
        if powerTypeColors.useClassColor then
            -- Class color for all resources
            local _, class = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                bar.StatusBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            else
                local color = GetResourceColor(resource)
                bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b)
            end
        elseif powerTypeColors.colors[resource] then
            -- Power type specific color
            local color = powerTypeColors.colors[resource]
            bar.StatusBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
        else
            -- Default resource color
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b)
        end

        bar.TextValue:SetText(tostring(current))
    else
        -- Normal bar display
        bar.StatusBar:SetAlpha(1)
        bar.StatusBar:SetMinMaxValues(0, max)
        bar.StatusBar:SetValue(current)

        -- Set bar color
        local powerTypeColors = NephUI.db.profile.powerTypeColors
        if powerTypeColors.useClassColor then
            -- Class color for all resources
            local _, class = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                bar.StatusBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            else
                local color = GetResourceColor(resource)
                bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b)
            end
        elseif powerTypeColors.colors[resource] and resource ~= "STAGGER" then
            -- Power type specific color (skip for stagger as it uses dynamic colors)
            local color = powerTypeColors.colors[resource]
            bar.StatusBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
        else
            -- Default resource color (includes dynamic stagger colors)
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b)
        end

        if cfg.textFormat == "Percent" or cfg.textFormat == "Percent%" then
            local precision = cfg.textPrecision and math.max(0, string.len(cfg.textPrecision) - 3) or 0
            if valueType == "custom" then
                bar.TextValue:SetText(displayValue)
            else
                bar.TextValue:SetText(string.format("%." .. (precision or 0) .. "f" .. (cfg.textFormat == "Percent%" and "%%" or ""), displayValue))
            end
        elseif cfg.textFormat == "Current / Maximum" then
            if valueType == "custom" then
                bar.TextValue:SetText(displayValue .. ' / ' .. (maxDisplayValue or max))
            else
                bar.TextValue:SetText(AbbreviateNumbers(displayValue) .. ' / ' .. AbbreviateNumbers(maxDisplayValue or max))
            end
        else -- Default "Current" format
            if valueType == "custom" then
                bar.TextValue:SetText(displayValue)
            else
                bar.TextValue:SetText(AbbreviateNumbers(displayValue))
            end
        end
        
        -- Hide fragmented bars
        for _, fragmentBar in ipairs(bar.FragmentedPowerBars) do
            fragmentBar:Hide()
        end
    end

    bar.TextValue:SetFont(NephUI:GetGlobalFont(), cfg.textSize or 12, "OUTLINE")
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:ClearAllPoints()
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", NephUI:Scale(cfg.textX or 0), NephUI:Scale(cfg.textY or 0))


    -- Show text
    bar.TextFrame:SetShown(cfg.showText ~= false)

    -- Handle hide bar but show text option
    if cfg.hideBarShowText then
        -- Hide the bar visuals but keep text visible
        if bar.StatusBar then
            bar.StatusBar:Hide()
        end
        if bar.Background then
            bar.Background:Hide()
        end
        -- Hide border when bar is hidden
        if bar.Border then
            bar.Border:Hide()
        end
        -- Hide ticks when bar is hidden
        for _, tick in ipairs(bar.ticks) do
            tick:Hide()
        end
        -- Hide fragmented power bars (runes) when bar is hidden
        for _, fragmentBar in ipairs(bar.FragmentedPowerBars) do
            fragmentBar:Hide()
        end
        -- Hide rune timer texts when bar is hidden
        for _, runeText in ipairs(bar.FragmentedPowerBarTexts) do
            if runeText then
                runeText:Hide()
            end
        end
    else
        -- Show the bar visuals
        if bar.StatusBar then
            bar.StatusBar:Show()
        end
        if bar.Background then
            bar.Background:Show()
        end
        -- Show border if size > 0
        if bar.Border and (bar._scaledBorder or NephUI:ScaleBorder(cfg.borderSize or 1)) > 0 then
            bar.Border:Show()
        end
        -- Update ticks if this is a ticked power type and not fragmented
        if not fragmentedPowerTypes[resource] then
            self:UpdateSecondaryPowerBarTicks(bar, resource, max)
        end
    end

    -- Update charged power overlays (e.g., Charged Combo Points)
    self:UpdateChargedPowerSegments(bar, resource, max)


    bar:Show()
end

-- Expose to main addon for backwards compatibility
NephUI.GetSecondaryPowerBar = function(self) return ResourceBars:GetSecondaryPowerBar() end
NephUI.UpdateSecondaryPowerBar = function(self) return ResourceBars:UpdateSecondaryPowerBar() end
NephUI.UpdateSecondaryPowerBarTicks = function(self, bar, resource, max) return ResourceBars:UpdateSecondaryPowerBarTicks(bar, resource, max) end
NephUI.CreateFragmentedPowerBars = function(self, bar, resource) return ResourceBars:CreateFragmentedPowerBars(bar, resource) end
NephUI.UpdateFragmentedPowerDisplay = function(self, bar, resource) return ResourceBars:UpdateFragmentedPowerDisplay(bar, resource) end
NephUI.UpdateChargedPowerSegments = function(self, bar, resource, max) return ResourceBars:UpdateChargedPowerSegments(bar, resource, max) end

