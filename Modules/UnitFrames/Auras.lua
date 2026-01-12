local ADDON_NAME, ns = ...
local NephUI = ns.Addon

-- Get UnitFrames module
local UF = NephUI.UnitFrames
if not UF then
    error("NephUI: UnitFrames module not initialized! Load UnitFrames.lua first.")
end

local TruncateWhenZero = C_StringUtil and C_StringUtil.TruncateWhenZero

-- Update unit auras (buffs/debuffs)
local function UpdateUnitAuras(frame)
    if not frame or not frame.unit then return end

    local unit = frame.unit
    local isBossPreview = UF.BossPreviewMode and unit:match("^boss%d+$")
    if not UnitExists(unit) and not isBossPreview then
        if frame.buffIcons then
            for _, iconFrame in ipairs(frame.buffIcons) do
                iconFrame:Hide()
            end
        end
        if frame.debuffIcons then
            for _, iconFrame in ipairs(frame.debuffIcons) do
                iconFrame:Hide()
            end
        end
        return
    end

    local hasAuraAPI = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex

    local db = NephUI.db.profile.unitFrames
    if not db then return end
    local dbUnit = unit
    if unit:match("^boss%d+$") then
        dbUnit = "boss"
    end
    local DB = db[dbUnit]
    local GeneralDB = db.General
    if not DB then return end

    -- Get aura settings (with defaults)
    local auraSettings = DB.Auras or {}
    local frameWidth = frame:GetWidth() or 200

    -- Separate settings for debuffs and buffs
    local debuffSettings = auraSettings.Debuffs or {}
    local buffSettings = auraSettings.Buffs or {}

    -- Global/shared settings (fallbacks)
    local globalWidth = (auraSettings.Width and auraSettings.Width > 0) and auraSettings.Width or (frameWidth + 2)
    local globalHeight = (auraSettings.Height and auraSettings.Height > 0) and auraSettings.Height or 18
    local globalAlpha = auraSettings.Alpha or 1
    local globalOffsetX = auraSettings.OffsetX or 0
    local globalOffsetY = auraSettings.OffsetY or 2
    local globalSpacing = auraSettings.Spacing or 2
    local globalIconsPerRow = auraSettings.IconsPerRow or 6 -- Default to 6 icons per row
    local globalRowLimit = auraSettings.RowLimit or 0 -- 0 = unlimited

    -- Debuff-specific settings (with global fallbacks)
    local debuffWidth = (debuffSettings.Width and debuffSettings.Width > 0) and debuffSettings.Width or globalWidth
    local debuffHeight = (debuffSettings.Height and debuffSettings.Height > 0) and debuffSettings.Height or globalHeight
    local debuffAlpha = debuffSettings.Alpha or globalAlpha
    local debuffOffsetX = debuffSettings.OffsetX or globalOffsetX
    local debuffOffsetY = debuffSettings.OffsetY or globalOffsetY
    local debuffSpacing = debuffSettings.Spacing or globalSpacing
    local debuffIconsPerRow = debuffSettings.IconsPerRow or globalIconsPerRow
    local debuffIconSize = debuffSettings.IconSize or math.max(14, math.floor(debuffHeight * 0.7 + 0.5))
    local debuffAnchorPoint = debuffSettings.AnchorPoint or "TOPLEFT"
    local debuffGrowthDirection = debuffSettings.GrowthDirection or "RIGHT"
    local debuffRowGrowthDirection = debuffSettings.RowGrowthDirection or "DOWN"
    local showDebuffs = debuffSettings.Enabled ~= false

    -- Buff-specific settings (with global fallbacks)
    local buffWidth = (buffSettings.Width and buffSettings.Width > 0) and buffSettings.Width or globalWidth
    local buffHeight = (buffSettings.Height and buffSettings.Height > 0) and buffSettings.Height or globalHeight
    local buffAlpha = buffSettings.Alpha or globalAlpha
    local buffOffsetX = buffSettings.OffsetX or globalOffsetX
    local buffOffsetY = buffSettings.OffsetY or globalOffsetY
    local buffSpacing = buffSettings.Spacing or globalSpacing
    local buffIconsPerRow = buffSettings.IconsPerRow or globalIconsPerRow
    local buffIconSize = buffSettings.IconSize or math.max(14, math.floor(buffHeight * 0.7 + 0.5))
    local buffAnchorPoint = buffSettings.AnchorPoint or "TOPLEFT"
    local buffGrowthDirection = buffSettings.GrowthDirection or "RIGHT"
    local buffRowGrowthDirection = buffSettings.RowGrowthDirection or "DOWN"
    local showBuffs = buffSettings.Enabled ~= false
    -- Use specified icons per row instead of calculating from width
    local debuffMaxPerRow = math.max(1, math.min(20, debuffIconsPerRow))
    local buffMaxPerRow = math.max(1, math.min(20, buffIconsPerRow))
    local totalRowLimit = globalRowLimit -- 0 = unlimited

    frame.buffIcons = frame.buffIcons or {}
    frame.debuffIcons = frame.debuffIcons or {}
    frame.previewBuffIcons = frame.previewBuffIcons or {}
    frame.previewDebuffIcons = frame.previewDebuffIcons or {}

    local function GetIcon(t, index, parent, iconSize, auraAlpha)
        local iconFrame = t[index]
        if not iconFrame then
            iconFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            t[index] = iconFrame
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:SetAlpha(auraAlpha)
            iconFrame:EnableMouse(true)

            -- Create icon texture first
            local tex = iconFrame:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            iconFrame.icon = tex

            -- Stack/count text
            local countOverlay = CreateFrame("Frame", nil, iconFrame)
            countOverlay:SetAllPoints(iconFrame)
            countOverlay:SetFrameLevel(iconFrame:GetFrameLevel() + 11)
            iconFrame.countOverlay = countOverlay

            local countText = countOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            countText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
            countText:SetJustifyH("RIGHT")
            countText:SetJustifyV("BOTTOM")
            iconFrame.countText = countText

            -- Cooldown swipe overlay
            local cd = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
            cd:SetAllPoints(iconFrame)
            cd:SetDrawEdge(false)
            cd:SetReverse(true)            -- user preference: reverse swipe
            cd.noOCC = true                -- allow external cooldown text mods
            cd.noCooldownCount = false      -- allow Blizzard/OmniCC countdown text
            iconFrame.cooldown = cd

            -- Create separate border frame (like SkinIcon does)
            -- Must be created after texture and cooldown
            local border = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
            -- Set explicit size - anchor to iconFrame (not texture) to avoid "secret value" errors
            -- Since texture uses SetAllPoints on iconFrame, this matches texture bounds
            border:SetAllPoints(iconFrame)
            -- Set frame level high enough to be above everything
            border:SetFrameLevel(iconFrame:GetFrameLevel() + 10)
            iconFrame.border = border

            -- Add black border (exactly like SkinIcon does, using lowercase x)
            -- Set backdrop after frame has explicit dimensions from SetAllPoints
            border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            border:SetBackdropBorderColor(0, 0, 0, 1)
            border:Show()

            -- Tooltip support using Blizzard's default anchor
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

            iconFrame:SetScript("OnEnter", function(self)
                if not self.unit or not self.auraIndex or not self.auraFilter then
                    return
                end
                if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
                    return
                end

                local auraData = C_UnitAuras.GetAuraDataByIndex(self.unit, self.auraIndex, self.auraFilter)
                if not auraData then
                    return
                end

                SetTooltipDefault(self)
                GameTooltip:SetUnitAura(self.unit, self.auraIndex, self.auraFilter)
            end)
            iconFrame:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        else
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:SetAlpha(auraAlpha)
            if iconFrame.countOverlay then
                iconFrame.countOverlay:SetAllPoints(iconFrame)
                iconFrame.countOverlay:SetFrameLevel(iconFrame:GetFrameLevel() + 11)
            end
            -- Ensure border is still properly anchored and shown if it exists
            if iconFrame.border then
                -- Anchor to iconFrame (not texture) to avoid "secret value" errors
                -- Since texture uses SetAllPoints on iconFrame, this matches texture bounds
                iconFrame.border:SetAllPoints(iconFrame)
                iconFrame.border:Show()
            end
        end
        return iconFrame
    end

    -- Hide old icons
    for _, fIcon in ipairs(frame.buffIcons) do
        fIcon:Hide()
    end
    for _, fIcon in ipairs(frame.debuffIcons) do
        fIcon:Hide()
    end

    -- Hide preview icons
    for _, icon in ipairs(frame.previewBuffIcons or {}) do
        icon:Hide()
    end
    for _, icon in ipairs(frame.previewDebuffIcons or {}) do
        icon:Hide()
    end

    local function Populate(containerTable, filter, isBuff, rowOffset, maxRows, iconSize, auraOffsetX, auraOffsetY, auraSpacing, auraAlpha, maxPerRow, anchorPoint, growthDirection, rowGrowthDirection)
        local shown = 0
        rowOffset = rowOffset or 0
        maxRows = maxRows or 999
        local auraList = nil
        local totalAuras = nil

        -- Use new GetUnitAuras API (supports sortRule/sortDirection)
        if C_UnitAuras and C_UnitAuras.GetUnitAuras then
            -- Use default sorting (nil args) unless configured otherwise
            local ok, result = pcall(C_UnitAuras.GetUnitAuras, unit, filter, nil, nil)
            if ok and type(result) == "table" then
                auraList = result
                totalAuras = #result
            end
        end

        if not auraList or not totalAuras or totalAuras == 0 then
            return
        end

        for index = 1, totalAuras do
            local auraData = auraList[index]
            if not auraData then
                break
            end

            shown = shown + 1
            local col = (shown - 1) % maxPerRow
            local row = math.floor((shown - 1) / maxPerRow) + rowOffset

            -- Check if we've exceeded the row limit
            if row >= maxRows then
                break
            end

            local iconFrame = GetIcon(containerTable, shown, frame, iconSize, auraAlpha)
            iconFrame.icon:SetTexture(auraData.icon)
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:SetAlpha(auraAlpha)
            iconFrame.unit = unit
            -- Preserve index for tooltip; fall back to loop index
            local auraIndex = index
            if type(auraData) == "table" then
                if auraData.auraIndex and type(auraData.auraIndex) == "number" then
                    auraIndex = auraData.auraIndex
                elseif auraData.index and type(auraData.index) == "number" then
                    auraIndex = auraData.index
                end
            end
            iconFrame.auraIndex = auraIndex
            iconFrame.auraFilter = filter
            iconFrame.isBuff = isBuff and true or false
            iconFrame.auraInstanceID = auraData.auraInstanceID

            -- Update stack/count text
            if iconFrame.countText then
                local count = auraData.applications
                if TruncateWhenZero then
                    iconFrame.countText:SetText(TruncateWhenZero(count))
                else
                    iconFrame.countText:SetText(count and tostring(count) or "")
                end
            end

            -- Cooldown swipe (prefer duration objects to stay secure in combat)
            if iconFrame.cooldown then
                iconFrame.cooldown:Hide()

                local applied = false
                local cooldown = iconFrame.cooldown

                -- use duration objects when available
                if cooldown.SetCooldownFromDurationObject and auraData.auraInstanceID then
                    -- Prefer new duration API (works in combat); fall back for older clients
                    local durationObj
                    if C_UnitAuras.GetAuraDuration then
                        local ok, obj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
                        if ok then
                            durationObj = obj
                        end
                    end
                    if not durationObj and C_UnitAuras.GetUnitAuraDuration then
                        local ok, obj = pcall(C_UnitAuras.GetUnitAuraDuration, unit, auraData.auraInstanceID)
                        if ok then
                            durationObj = obj
                        end
                    end

                    if durationObj then
                        local setOk = pcall(cooldown.SetCooldownFromDurationObject, cooldown, durationObj, true) -- clearIfZero
                        if setOk then
                            applied = true
                        else
                            -- If SetCooldownFromDurationObject fails, try deriving numbers from the duration object
                            local eOK, elapsed = pcall(durationObj.GetElapsedDuration, durationObj)
                            local rOK, remaining = pcall(durationObj.GetRemainingDuration, durationObj)
                            if eOK and rOK and elapsed and remaining then
                                local startTime = GetTime() - elapsed
                                local total = elapsed + remaining
                                local numOk = pcall(cooldown.SetCooldown, cooldown, startTime, total)
                                if numOk then
                                    applied = true
                                end
                            end
                        end
                    end
                end

                -- Fallback: numeric start/duration (avoid comparisons; allow secret-safe arithmetic)
                if not applied then
                    local duration = auraData.duration
                    local expirationTime = auraData.expirationTime
                    if duration and expirationTime then
                        local ok = pcall(function()
                            local startTime = expirationTime - duration
                            cooldown:SetCooldown(startTime, duration)
                        end)
                        if ok then
                            applied = true
                        end
                    end
                end

                if applied then
                    cooldown:Show()
                end
            end

            -- Calculate position based on anchor point and growth directions
            local xOffset, yOffset = auraOffsetX, auraOffsetY

            -- Apply column offset based on growth direction
            if growthDirection == "RIGHT" then
                xOffset = xOffset + col * (iconSize + auraSpacing)
            elseif growthDirection == "LEFT" then
                xOffset = xOffset - col * (iconSize + auraSpacing)
            elseif growthDirection == "DOWN" then
                yOffset = yOffset - col * (iconSize + auraSpacing)
            elseif growthDirection == "UP" then
                yOffset = yOffset + col * (iconSize + auraSpacing)
            end

            -- Apply row offset based on row growth direction
            if rowGrowthDirection == "DOWN" then
                yOffset = yOffset - row * (iconSize + auraSpacing)
            elseif rowGrowthDirection == "UP" then
                yOffset = yOffset + row * (iconSize + auraSpacing)
            elseif rowGrowthDirection == "RIGHT" then
                xOffset = xOffset + row * (iconSize + auraSpacing)
            elseif rowGrowthDirection == "LEFT" then
                xOffset = xOffset - row * (iconSize + auraSpacing)
            end

            -- Determine the correct anchor points for positioning icons outside the frame
            -- The icons should touch the outside edge of the frame at the chosen anchor point
            local iconAnchorPoint, frameAnchorPoint
            if anchorPoint == "TOPLEFT" then
                -- Icon's bottom-left touches frame's top-left (icons above frame)
                iconAnchorPoint, frameAnchorPoint = "BOTTOMLEFT", "TOPLEFT"
            elseif anchorPoint == "TOPRIGHT" then
                -- Icon's bottom-right touches frame's top-right (icons above frame)
                iconAnchorPoint, frameAnchorPoint = "BOTTOMRIGHT", "TOPRIGHT"
            elseif anchorPoint == "BOTTOMLEFT" then
                -- Icon's top-left touches frame's bottom-left (icons below frame)
                iconAnchorPoint, frameAnchorPoint = "TOPLEFT", "BOTTOMLEFT"
            elseif anchorPoint == "BOTTOMRIGHT" then
                -- Icon's top-right touches frame's bottom-right (icons below frame)
                iconAnchorPoint, frameAnchorPoint = "TOPRIGHT", "BOTTOMRIGHT"
            elseif anchorPoint == "TOP" then
                -- Icon's bottom touches frame's top (icons above frame)
                iconAnchorPoint, frameAnchorPoint = "BOTTOM", "TOP"
            elseif anchorPoint == "BOTTOM" then
                -- Icon's top touches frame's bottom (icons below frame)
                iconAnchorPoint, frameAnchorPoint = "TOP", "BOTTOM"
            elseif anchorPoint == "LEFT" then
                -- Icon's right touches frame's left (icons to the left of frame)
                iconAnchorPoint, frameAnchorPoint = "RIGHT", "LEFT"
            elseif anchorPoint == "RIGHT" then
                -- Icon's left touches frame's right (icons to the right of frame)
                iconAnchorPoint, frameAnchorPoint = "LEFT", "RIGHT"
            elseif anchorPoint == "CENTER" then
                -- Icons centered (this might not make much sense, but fallback to original behavior)
                iconAnchorPoint, frameAnchorPoint = "CENTER", "CENTER"
            else
                -- Fallback to original behavior for any unexpected values
                iconAnchorPoint, frameAnchorPoint = "TOPLEFT", anchorPoint
            end

            iconFrame:ClearAllPoints()
            iconFrame:SetPoint(iconAnchorPoint, frame, frameAnchorPoint, xOffset, yOffset)

            iconFrame:Show()

            index = index + 1
        end

        return shown
    end

    -- Debuffs and buffs are positioned independently so one list never shifts the other
    local maxDebuffRows = totalRowLimit > 0 and totalRowLimit or 999

    -- Show real debuffs unless preview is enabled
    if showDebuffs and not debuffSettings.Preview and hasAuraAPI then
        -- Use different debuff filters based on unit type
        local debuffFilter = (unit == "player") and "HARMFUL" or "HARMFUL|PLAYER"
        Populate(frame.debuffIcons, debuffFilter, false, 0, maxDebuffRows, debuffIconSize, debuffOffsetX, debuffOffsetY, debuffSpacing, debuffAlpha, debuffMaxPerRow, debuffAnchorPoint, debuffGrowthDirection, debuffRowGrowthDirection)
    end

    -- Buff rows do not inherit debuff rows; they use their own anchor/offset
    local buffRowOffset = 0
    local maxBuffRows = totalRowLimit > 0 and totalRowLimit or 999

    -- Show real buffs unless preview is enabled
    if showBuffs and maxBuffRows > 0 and not buffSettings.Preview and hasAuraAPI then
        Populate(frame.buffIcons, "HELPFUL", true, buffRowOffset, maxBuffRows, buffIconSize, buffOffsetX, buffOffsetY, buffSpacing, buffAlpha, buffMaxPerRow, buffAnchorPoint, buffGrowthDirection, buffRowGrowthDirection)
    end

    -- Preview mode: Show fake icons for configuration preview
    local function CreateFakeAura(containerTable, index, isBuff, iconSize, auraOffsetX, auraOffsetY, auraSpacing, auraAlpha, maxPerRow, anchorPoint, growthDirection, rowGrowthDirection)
        local iconFrame = GetIcon(containerTable, index, frame, iconSize, auraAlpha)
        -- Use different icons for buff and debuff previews
        if isBuff then
            iconFrame.icon:SetTexture(135932) -- Buff preview icon
        else
            iconFrame.icon:SetTexture(136207) -- Debuff preview icon
        end
        iconFrame:SetSize(iconSize, iconSize)
        iconFrame:SetAlpha(auraAlpha)
        iconFrame.unit = unit
        iconFrame.auraIndex = index
        iconFrame.auraFilter = isBuff and "HELPFUL" or "HARMFUL"
        iconFrame.isBuff = isBuff and true or false
        iconFrame.auraInstanceID = -index -- Use negative IDs for fake auras

        -- Hide cooldown for preview
        if iconFrame.cooldown then
            iconFrame.cooldown:Hide()
        end

        -- Calculate position
        local col = (index - 1) % maxPerRow
        local row = math.floor((index - 1) / maxPerRow)

        local xOffset, yOffset = auraOffsetX, auraOffsetY

        -- Apply column offset based on growth direction
        if growthDirection == "RIGHT" then
            xOffset = xOffset + col * (iconSize + auraSpacing)
        elseif growthDirection == "LEFT" then
            xOffset = xOffset - col * (iconSize + auraSpacing)
        elseif growthDirection == "DOWN" then
            yOffset = yOffset - col * (iconSize + auraSpacing)
        elseif growthDirection == "UP" then
            yOffset = yOffset + col * (iconSize + auraSpacing)
        end

        -- Apply row offset based on row growth direction
        if rowGrowthDirection == "DOWN" then
            yOffset = yOffset - row * (iconSize + auraSpacing)
        elseif rowGrowthDirection == "UP" then
            yOffset = yOffset + row * (iconSize + auraSpacing)
        elseif rowGrowthDirection == "RIGHT" then
            xOffset = xOffset + row * (iconSize + auraSpacing)
        elseif rowGrowthDirection == "LEFT" then
            xOffset = xOffset - row * (iconSize + auraSpacing)
        end

        -- Determine the correct anchor points for positioning icons outside the frame
        -- The icons should touch the outside edge of the frame at the chosen anchor point
        local iconAnchorPoint, frameAnchorPoint
        if anchorPoint == "TOPLEFT" then
            -- Icon's bottom-left touches frame's top-left (icons above frame)
            iconAnchorPoint, frameAnchorPoint = "BOTTOMLEFT", "TOPLEFT"
        elseif anchorPoint == "TOPRIGHT" then
            -- Icon's bottom-right touches frame's top-right (icons above frame)
            iconAnchorPoint, frameAnchorPoint = "BOTTOMRIGHT", "TOPRIGHT"
        elseif anchorPoint == "BOTTOMLEFT" then
            -- Icon's top-left touches frame's bottom-left (icons below frame)
            iconAnchorPoint, frameAnchorPoint = "TOPLEFT", "BOTTOMLEFT"
        elseif anchorPoint == "BOTTOMRIGHT" then
            -- Icon's top-right touches frame's bottom-right (icons below frame)
            iconAnchorPoint, frameAnchorPoint = "TOPRIGHT", "BOTTOMRIGHT"
        elseif anchorPoint == "TOP" then
            -- Icon's bottom touches frame's top (icons above frame)
            iconAnchorPoint, frameAnchorPoint = "BOTTOM", "TOP"
        elseif anchorPoint == "BOTTOM" then
            -- Icon's top touches frame's bottom (icons below frame)
            iconAnchorPoint, frameAnchorPoint = "TOP", "BOTTOM"
        elseif anchorPoint == "LEFT" then
            -- Icon's right touches frame's left (icons to the left of frame)
            iconAnchorPoint, frameAnchorPoint = "RIGHT", "LEFT"
        elseif anchorPoint == "RIGHT" then
            -- Icon's left touches frame's right (icons to the right of frame)
            iconAnchorPoint, frameAnchorPoint = "LEFT", "RIGHT"
        elseif anchorPoint == "CENTER" then
            -- Icons centered (this might not make much sense, but fallback to original behavior)
            iconAnchorPoint, frameAnchorPoint = "CENTER", "CENTER"
        else
            -- Fallback to original behavior for any unexpected values
            iconAnchorPoint, frameAnchorPoint = "TOPLEFT", anchorPoint
        end

        iconFrame:ClearAllPoints()
        iconFrame:SetPoint(iconAnchorPoint, frame, frameAnchorPoint, xOffset, yOffset)
        iconFrame:Show()

        return iconFrame
    end

    -- Preview debuffs (12 fake icons)
    if debuffSettings.Preview then
        for i = 1, 12 do
            CreateFakeAura(frame.previewDebuffIcons, i, false, debuffIconSize, debuffOffsetX, debuffOffsetY, debuffSpacing, debuffAlpha, debuffMaxPerRow, debuffAnchorPoint, debuffGrowthDirection, debuffRowGrowthDirection)
        end
    end

    -- Preview buffs (12 fake icons)
    if buffSettings.Preview then
        for i = 1, 12 do
            CreateFakeAura(frame.previewBuffIcons, i, true, buffIconSize, buffOffsetX, buffOffsetY, buffSpacing, buffAlpha, buffMaxPerRow, buffAnchorPoint, buffGrowthDirection, buffRowGrowthDirection)
        end
    end
end

-- Export function
UF.UpdateUnitAuras = UpdateUnitAuras

