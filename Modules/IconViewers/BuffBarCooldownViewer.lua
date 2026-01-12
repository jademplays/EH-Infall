local ADDON_NAME, ns = ...
local NephUI = ns.Addon

NephUI.IconViewers = NephUI.IconViewers or {}
local IconViewers = NephUI.IconViewers

IconViewers.BuffBarCooldownViewer = IconViewers.BuffBarCooldownViewer or {}
local BuffBar = IconViewers.BuffBarCooldownViewer

local C_Timer = _G.C_Timer
local UIParent = _G.UIParent
local WHITE8 = "Interface\\Buttons\\WHITE8X8"

local function PixelSnap(value)
    return math.max(0, math.floor((value or 0) + 0.5))
end

local function StripTextureMasks(texture)
    if not texture or not texture.GetMaskTexture then return end

    local i = 1
    local mask = texture:GetMaskTexture(i)
    while mask do
        texture:RemoveMaskTexture(mask)
        i = i + 1
        mask = texture:GetMaskTexture(i)
    end
end

local function StripBlizzardOverlay(icon)
    for _, region in ipairs({ icon:GetRegions() }) do
        if region:IsObjectType("Texture") and region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
            region:SetTexture("")
            region:Hide()
            region.Show = function() end
        end
    end
end

local function GetSettings()
    if not NephUI.db or not NephUI.db.profile then
        return nil
    end

    NephUI.db.profile.buffBarViewer = NephUI.db.profile.buffBarViewer or {}
    NephUI.db.profile.buffBarViewer.barColors = NephUI.db.profile.buffBarViewer.barColors or {}
    NephUI.db.profile.buffBarViewer.barColorsBySpec = NephUI.db.profile.buffBarViewer.barColorsBySpec or {}
    return NephUI.db.profile.buffBarViewer
end

local function GetCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local id = GetSpecializationInfo(specIndex)
        return id
    end
    return nil
end

local function GetBarColor(settings, barIndex)
    if not settings then return nil end
    local specID = GetCurrentSpecID()
    if specID and settings.barColorsBySpec and settings.barColorsBySpec[specID] then
        return settings.barColorsBySpec[specID][barIndex]
    end
    if settings.barColors then
        return settings.barColors[barIndex]
    end
    return nil
end

local function SetBarColor(settings, barIndex, color)
    if not settings then return end
    local specID = GetCurrentSpecID()
    settings.barColorsBySpec = settings.barColorsBySpec or {}
    if specID then
        settings.barColorsBySpec[specID] = settings.barColorsBySpec[specID] or {}
        settings.barColorsBySpec[specID][barIndex] = color
    else
        settings.barColors = settings.barColors or {}
        settings.barColors[barIndex] = color
    end
end

local function GetBarIndex(child)
    return child.layoutIndex or child.orderIndex or (child.GetID and child:GetID()) or 1
end

local function GetAnchorFrame(settings)
    local anchor = _G["EssentialCooldownViewer"]
    if anchor then
        return anchor
    end
    return nil
end

local function ComputeBarWidth(settings, viewer, iconTotal, spacing, barBorder)
    local width = settings.width or 0
    local anchor = GetAnchorFrame(settings) or viewer
    spacing = spacing or 0
    iconTotal = iconTotal or 0
    barBorder = barBorder or 0

    if width <= 0 then
        local anchorWidth
        if anchor and anchor.GetWidth then
            local ok, w = pcall(anchor.GetWidth, anchor)
            if ok then
                anchorWidth = anchor.__cdmIconWidth or w
            end
        end
        width = PixelSnap(anchorWidth or (viewer and viewer:GetWidth()) or 200)
        width = math.max(1, width - iconTotal - spacing)
    else
        width = PixelSnap(NephUI:Scale(width))
    end

    return width
end

local function ComputeBarHeight(settings, bar)
    local desired = settings.height or 16
    local scaled = NephUI:Scale(desired)
    if scaled <= 0 and bar and bar.GetHeight then
        local ok, h = pcall(bar.GetHeight, bar)
        if ok and h and h > 0 then
            return h
        end
    end
    return scaled
end

local function ApplyIconMaskSettings(iconFrame, settings)
    if not iconFrame or settings.hideIconMask == false then
        return
    end

    local iconTexture = iconFrame.icon or iconFrame.Icon or iconFrame.IconTexture
    if iconTexture then
        StripTextureMasks(iconTexture)
    end

    if iconFrame.GetRegions then
        for _, region in ipairs({ iconFrame:GetRegions() }) do
            if region and region:IsObjectType("Texture") then
                StripTextureMasks(region)
            end
        end
    end

    StripBlizzardOverlay(iconFrame)

    if iconFrame.DebuffBorder then
        if iconFrame.DebuffBorder.SetTexture then
            iconFrame.DebuffBorder:SetTexture(nil)
        end
        if iconFrame.DebuffBorder.Hide then
            iconFrame.DebuffBorder:Hide()
        end
    end
end

local function ApplyIconZoom(iconFrame, settings)
    if not iconFrame then return end
    local iconTexture = iconFrame.icon or iconFrame.Icon or iconFrame.IconTexture
    if not iconTexture then return end

    local zoom = settings.iconZoom or 0
    zoom = math.max(0, math.min(zoom, 0.45)) -- clamp for safety

    iconTexture:ClearAllPoints()
    iconTexture:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
    iconTexture:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)

    local left = zoom
    local right = 1 - zoom
    local top = zoom
    local bottom = 1 - zoom
    iconTexture:SetTexCoord(left, right, top, bottom)
end

local function ApplyIconBorder(iconFrame, settings)
    if not iconFrame then return end
    local size = settings.iconBorderSize or 0
    local borderSize = NephUI:ScaleBorder(size)

    if not iconFrame.__nuiIconBorder then
        local border = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
        iconFrame.__nuiIconBorder = border
    end

    local border = iconFrame.__nuiIconBorder
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", iconFrame, -borderSize, borderSize)
    border:SetPoint("BOTTOMRIGHT", iconFrame, borderSize, -borderSize)
    border:SetBackdrop({
        edgeFile = WHITE8,
        edgeSize = borderSize,
    })

    local c = settings.iconBorderColor or {0, 0, 0, 1}
    border:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    border:SetShown(borderSize > 0)
end

local function GetBarBackground(bar)
    if not bar then return nil end
    if bar.BarBG then
        return bar.BarBG
    end
    if bar.__nuiBarBG and bar.__nuiBarBG.GetObjectType and bar.__nuiBarBG:GetObjectType() == "Texture" then
        return bar.__nuiBarBG
    end

    for _, region in ipairs({ bar:GetRegions() }) do
        if region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas == "UI-HUD-CoolDownManager-Bar-BG" or atlas == "UI-HUD-CooldownManager-Bar-BG" then
                bar.__nuiBarBG = region
                return region
            end
        end
    end

    return nil
end

local function GetApplicationsFont(iconFrame)
    if not iconFrame then return nil end

    if iconFrame.Applications then
        if iconFrame.Applications.GetObjectType and iconFrame.Applications:GetObjectType() == "FontString" then
            return iconFrame.Applications
        elseif iconFrame.Applications.GetRegions then
            for _, region in ipairs({ iconFrame.Applications:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    return region
                end
            end
        end
    end

    for _, region in ipairs({ iconFrame:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            local name = region:GetName()
            if name and (name:find("Applications") or name:find("Stack")) then
                return region
            end
        end
    end

    return nil
end

local function RaiseTextLayer(fs, owner)
    -- No-op; frame level adjustments removed
end

local function StyleBarChild(child, settings, viewer)
    if not child or not child.Bar then return end

    local bar = child.Bar
    local iconFrame = child.Icon or child.IconFrame or child.IconButton
    local applicationsFS = GetApplicationsFont(iconFrame)
    local barHeight = PixelSnap(ComputeBarHeight(settings, bar))
    local iconSize = barHeight
    local font = (NephUI.GetGlobalFont and NephUI:GetGlobalFont()) or nil
    local iconBorderSize = settings.iconBorderSize or 0
    local iconBorderScaled = NephUI:ScaleBorder(iconBorderSize)
    local barIndex = GetBarIndex(child)

    if settings.hideIcon then
        iconSize = 0
        spacing = 0
        if iconFrame then
            iconFrame:Hide()
            iconFrame:SetAlpha(0)
            if iconFrame.SetSize then
                iconFrame:SetSize(0.001, 0.001)
            end
            if iconFrame.__nuiIconBorder then
                iconFrame.__nuiIconBorder:Hide()
            end
        end
    else
        if settings.hideIconMask ~= false then
            ApplyIconMaskSettings(iconFrame, settings)
        end
        ApplyIconZoom(iconFrame, settings)
        ApplyIconBorder(iconFrame, settings)

        if iconFrame then
            iconFrame:Show()
            iconFrame:SetAlpha(1)
            if iconFrame.SetSize then
                iconFrame:SetSize(iconSize, iconSize)
            end
        end
        if applicationsFS then
            applicationsFS:Show()
            if applicationsFS:GetParent() ~= iconFrame then
                applicationsFS:SetParent(iconFrame)
            end
        end
    end
    local iconTotalWidth = settings.hideIcon and 0 or PixelSnap(iconSize + (iconBorderScaled * 2))
    local iconTotalHeight = settings.hideIcon and 0 or PixelSnap(iconSize + (iconBorderScaled * 2))
    local barBorderSize = NephUI:ScaleBorder(settings.borderSize or 1)

    local barWidth = ComputeBarWidth(settings, viewer, iconTotalWidth, 0, 0)
    -- Bar visuals
    local tex = NephUI.GetTexture and NephUI:GetTexture(settings.texture) or WHITE8
    bar:SetStatusBarTexture(tex)
    local color = GetBarColor(settings, barIndex) or settings.barColor or { 0.9, 0.9, 0.9, 1 }
    bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    bar.__nuiBarIndex = barIndex
    local barBG = GetBarBackground(bar)
    if barBG then
        barBG:SetTexture(WHITE8)
        local bg = settings.bgColor or { 0.1, 0.1, 0.1, 0.7 }
        barBG:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
        barBG:ClearAllPoints()
        barBG:SetPoint("TOPLEFT", bar, "TOPLEFT")
        barBG:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
        barBG:SetDrawLayer("BACKGROUND", 0)
    end

    if bar.Pip then
        -- Hide Blizzard's end-cap "spark" so it doesn't overhang the bar
        bar.Pip:Hide()
        bar.Pip:SetTexture(nil)
    end

    local border = bar.Border or bar.__nuiBorder
    if not border then
        border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        bar.__nuiBorder = border
    end
    local borderSize = NephUI:ScaleBorder(settings.borderSize or 1)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", bar, -borderSize, borderSize)
    border:SetPoint("BOTTOMRIGHT", bar, borderSize, -borderSize)
    border:SetBackdrop({
        edgeFile = WHITE8,
        edgeSize = borderSize,
    })
    local bc = settings.borderColor or { 0, 0, 0, 1 }
    border:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
    border:SetFrameStrata("BACKGROUND")
    border:SetShown(borderSize > 0)

    bar:SetHeight(barHeight)
    local effectiveBarWidth = PixelSnap(math.max(1, barWidth or 1))
    bar:SetWidth(effectiveBarWidth)

    -- Resize containing button to fit icon + bar height (include borders)
    local iconSize = iconFrame and PixelSnap(iconFrame:GetHeight()) or barHeight
    local childHeight = PixelSnap(math.max(barHeight + barBorderSize * 2, iconTotalHeight, iconSize))
    child:SetHeight(childHeight)
    local childWidth = effectiveBarWidth + (settings.hideIcon and 0 or (iconSize or barHeight)) + (barBorderSize * 2)
    child:SetWidth(PixelSnap(childWidth))

    -- Text styling
    local nameFS = bar.Name
    if nameFS then
        if settings.showName == false then
            nameFS:Hide()
        else
            nameFS:Show()
            if font then
                nameFS:SetFont(font, settings.nameSize or 14, "OUTLINE")
            else
                nameFS:SetFont(nameFS:GetFont(), settings.nameSize or 14, "OUTLINE")
            end
            local nc = settings.nameColor or {1, 1, 1, 1}
            nameFS:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
            nameFS:ClearAllPoints()
            local anchor = settings.nameAnchor or "LEFT"
            if anchor == "MIDDLE" then anchor = "CENTER" end
            local ax = settings.nameOffsetX or 0
            local ay = settings.nameOffsetY or 0
            nameFS:SetPoint(anchor, bar, anchor, ax, ay)
        end
    end

    if applicationsFS and (iconFrame or bar) then
        if settings.showApplications == false then
            applicationsFS:Hide()
        else
            if settings.applicationsSize then
                if font then
                    applicationsFS:SetFont(font, settings.applicationsSize, "OUTLINE")
                else
                    applicationsFS:SetFont(applicationsFS:GetFont(), settings.applicationsSize, "OUTLINE")
                end
            end
            local ac = settings.applicationsColor or {1, 1, 1, 1}
            applicationsFS:SetTextColor(ac[1], ac[2], ac[3], ac[4] or 1)

            applicationsFS:ClearAllPoints()
            local anchor = settings.applicationsAnchor or "BOTTOMRIGHT"
            if anchor == "MIDDLE" then
                anchor = "CENTER"
            end
            local ax = settings.applicationsOffsetX or 0
            local ay = settings.applicationsOffsetY or 0
            local target = settings.hideIcon and bar or iconFrame
            if settings.hideIcon then
                if applicationsFS:GetParent() ~= bar then
                    applicationsFS:SetParent(bar)
                end
            else
                if applicationsFS:GetParent() ~= iconFrame then
                    applicationsFS:SetParent(iconFrame)
                end
            end
            applicationsFS:SetPoint(anchor, target, anchor, ax, ay)
            applicationsFS:Show()
        end
    end

    local durFS = bar.Duration
    if durFS then
        if settings.showDuration == false then
            durFS:Hide()
        else
            durFS:Show()
            if font then
                durFS:SetFont(font, settings.durationSize or 12, "OUTLINE")
            else
                durFS:SetFont(durFS:GetFont(), settings.durationSize or 12, "OUTLINE")
            end
            local dc = settings.durationColor or {1, 1, 1, 1}
            durFS:SetTextColor(dc[1], dc[2], dc[3], dc[4] or 1)
            durFS:ClearAllPoints()
            local anchor = settings.durationAnchor or "RIGHT"
            if anchor == "MIDDLE" then anchor = "CENTER" end
            local ax = settings.durationOffsetX or 0
            local ay = settings.durationOffsetY or 0
            durFS:SetPoint(anchor, bar, anchor, ax, ay)
        end
    end

    -- Hide Blizzard debuff border if present
    if child.DebuffBorder then
        child.DebuffBorder:Hide()
    end
end

function BuffBar:ApplyViewerStyle(viewer, settings)
    if not viewer or not settings then return end

    if viewer.GetChildren then
        local children = {}
        for _, child in ipairs({ viewer:GetChildren() }) do
            if child.Bar then
                table.insert(children, child)
            end
        end

        table.sort(children, function(a, b)
            local la = a.layoutIndex or a:GetID() or 0
            local lb = b.layoutIndex or b:GetID() or 0
            return la < lb
        end)

        for _, child in ipairs(children) do
            StyleBarChild(child, settings, viewer)
        end
    end
end

function BuffBar:Refresh()
    local settings = GetSettings()
    if not settings then return end

    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then return end

    if settings.enabled == false then
        viewer:Hide()
        return
    end

    viewer:Show()

    self:ApplyViewerStyle(viewer, settings)
end

local function TryHookViewer()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer or viewer.__nuiBuffBarHooked then
        return viewer ~= nil
    end

    viewer.__nuiBuffBarHooked = true

    viewer:HookScript("OnShow", function()
        BuffBar:Refresh()
    end)
    viewer:HookScript("OnSizeChanged", function()
        BuffBar:Refresh()
    end)

    if viewer.Bar and viewer.Bar.HookScript then
        viewer.Bar:HookScript("OnSizeChanged", function()
            BuffBar:Refresh()
        end)
    end

    BuffBar:Refresh()
    return true
end

function BuffBar:Initialize()
    if self.__initialized then return end
    self.__initialized = true

    local hooked = TryHookViewer()
    if not hooked then
        C_Timer.After(0.25, TryHookViewer)
        C_Timer.After(0.75, TryHookViewer)
        C_Timer.After(1.5, TryHookViewer)
    end

    -- Refresh layout when player auras change (bars can hide/show)
    if not self.__eventFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("UNIT_AURA")
        local throttle = 0
        f:SetScript("OnEvent", function(_, _, unit)
            if unit and unit ~= "player" then return end
            throttle = throttle + 1
            if throttle > 1 then
                return
            end
            C_Timer.After(0.1, function() -- Increased from 0.05 to 0.1 for better performance
                throttle = 0
                BuffBar:Refresh()
            end)
        end)
        self.__eventFrame = f
    end

    -- Hook Blizzard CooldownViewerSettings bar list to add per-bar color picker
    if not self.__settingsHooked then
        self.__settingsHooked = true
        local function ApplyBarColorsToItem(item, index)
            if not item or not item.Bar then return end

            local settings = GetSettings()
            if not settings then return end

            local savedColor = (settings.barColors and settings.barColors[index]) or settings.barColor or {1, 1, 1, 1}
            local fill = item.Bar.FillTexture or (item.Bar.GetStatusBarTexture and item.Bar:GetStatusBarTexture())
            if fill then
                fill:SetVertexColor(savedColor[1], savedColor[2], savedColor[3], savedColor[4] or 1)
            end

            if not item.__nuiColorSwatch then
                local swatch = CreateFrame("Button", nil, item, "ColorSwatchTemplate")
                swatch:SetPoint("LEFT", item, "RIGHT", 4, 0)
                swatch:SetSize(18, 18)
                swatch:Show()
                item.__nuiColorSwatch = swatch
            end

            local swatch = item.__nuiColorSwatch
            swatch:SetColorRGB(savedColor[1], savedColor[2], savedColor[3])
            swatch:Show()

            swatch:SetScript("OnClick", function()
                local info = {}
                info.r, info.g, info.b, info.opacity = savedColor[1], savedColor[2], savedColor[3], savedColor[4] or 1
                info.hasOpacity = true
                info.swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local a = ColorPickerFrame:GetColorAlpha()
                    SetBarColor(settings, index, { r, g, b, a })
                    if fill then
                        fill:SetVertexColor(r, g, b, a)
                    end
                    swatch:SetColorRGB(r, g, b)
                end
                info.cancelFunc = function()
                    local r, g, b, a = ColorPickerFrame:GetPreviousValues()
                    SetBarColor(settings, index, { r, g, b, a })
                    if fill then
                        fill:SetVertexColor(r, g, b, a)
                    end
                    swatch:SetColorRGB(r, g, b)
                end
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
        end

        local function HookSettingsBar(self)
            if not self or not self.itemPool then return end
            local activeItems = {}
            for item in self.itemPool:EnumerateActive() do
                table.insert(activeItems, item)
            end
            table.sort(activeItems, function(a, b)
                local aIdx = a.orderIndex or 0
                local bIdx = b.orderIndex or 0
                return aIdx < bIdx
            end)

            local visibleIndex = 0
            for _, item in ipairs(activeItems) do
                if item.Bar and item.Bar.Name and not item.Icon:IsDesaturated() then
                    visibleIndex = visibleIndex + 1
                    ApplyBarColorsToItem(item, visibleIndex)
                end
            end
        end

        if CooldownViewerSettingsBarCategoryMixin then
            hooksecurefunc(CooldownViewerSettingsBarCategoryMixin, "RefreshLayout", HookSettingsBar)
            -- Reapply colors on spec change
            local specFrame = CreateFrame("Frame")
            specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            specFrame:SetScript("OnEvent", function()
                if CooldownViewerSettingsBar and CooldownViewerSettingsBar.RefreshLayout then
                    CooldownViewerSettingsBar:RefreshLayout()
                end
            end)
        end
    end
end

-- Convenience export for external calls
NephUI.RefreshBuffBarCooldownViewer = function(self)
    return BuffBar:Refresh()
end
