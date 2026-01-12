local ADDON_NAME, ns = ...
local NephUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")

NephUI.CompactFrames = NephUI.CompactFrames or {}
local Engine = NephUI.CompactFrames

local PartyFrames = {}
NephUI.PartyFrames = PartyFrames

local pendingResizeFrames = {}
local ShouldHidePartyPlayerEntry

local ROLE_TEXTURES = {
    TANK = "Interface\\AddOns\\NephUI\\Media\\Tank.tga",
    HEALER = "Interface\\AddOns\\NephUI\\Media\\Healer.tga",
    DAMAGER = "Interface\\AddOns\\NephUI\\Media\\DPS.tga",
}

local HIGHLIGHT_REPLACEMENTS = {
    selection = "Interface\\AddOns\\NephUI\\Media\\uf_selected.tga",
    aggro = "Interface\\AddOns\\NephUI\\Media\\uf_aggro.tga",
    mouseover = "Interface\\AddOns\\NephUI\\Media\\uf_mouseover.tga",
}

-- Safely fetch health percent across API variants (12.0 curve vs legacy boolean)
local function SafeUnitHealthPercent(unit, includeAbsorbs, includePredicted)
    -- Prefer native helper to avoid secret-value comparison issues.
    if type(UnitHealthPercent) == "function" then
        local ok, pct

        -- Try modern signature with curve constants first
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitHealthPercent, unit, includePredicted, CurveConstants.ScaleTo100)
        else
            ok, pct = pcall(UnitHealthPercent, unit, includePredicted, true)
        end

        if (not ok or pct == nil) then
            ok, pct = pcall(UnitHealthPercent, unit, includePredicted)
        end

        if ok and pct ~= nil then
            return pct
        end
    end

    -- Fallback: calculate from missing health (handles absorbs on modern clients).
    if type(UnitHealthMissing) == "function" then
        local ok, pct = pcall(function()
            local missing = UnitHealthMissing(unit, includeAbsorbs)
            if type(missing) ~= "number" then
                return nil
            end
            local max = UnitHealthMax(unit)
            if not max or max <= 0 then
                return nil
            end
            local cur = max - missing
            local value = (cur / max) * 100
            return math.min(100, math.max(0, value))
        end)
        if ok and pct ~= nil then
            return pct
        end
    end

    -- Final fallback: compute from current/max.
    if UnitHealth and UnitHealthMax then
        local ok, pct = pcall(function()
            local cur = UnitHealth(unit)
            local max = UnitHealthMax(unit)
            if includeAbsorbs and UnitGetTotalAbsorbs then
                cur = (cur or 0) + (UnitGetTotalAbsorbs(unit) or 0)
            end
            if not cur or not max or max <= 0 then
                return nil
            end
            local value = (cur / max) * 100
            return math.min(100, math.max(0, value))
        end)
        if ok and pct ~= nil then
            return pct
        end
    end

    return nil
end

local function SafeGetName(frame)
    if not frame or not frame.GetName then return nil end
    local ok, name = pcall(frame.GetName, frame)
    if not ok then return nil end
    return name
end

local function SafeGetNumber(frame, method)
    if not frame or not method then return nil end
    local func = frame[method]
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, frame)
    if ok and type(value) == "number" then
        return value -- secret values are still valid numbers
    end
    return nil
end

local function EnsureBaseAnchor(frame)
    if not frame or frame.__nuiBaseAnchor then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    frame.__nuiBaseAnchor = {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x or 0,
        y = y or 0,
    }
end

function Engine:ApplyPendingResizes()
    if InCombatLockdown and InCombatLockdown() then return end
    for frame in pairs(pendingResizeFrames) do
        local pending = frame.__nuiPendingResize
        if pending and frame.SetSize and pending.width and pending.height then
            frame:SetSize(pending.width, pending.height)
        end
        frame.__nuiPendingResize = nil
        pendingResizeFrames[frame] = nil
    end
end

function Engine:EnsureResizeHandler()
    if self.resizeHandler then return end
    local handler = CreateFrame("Frame")
    handler:RegisterEvent("PLAYER_REGEN_ENABLED")
    handler:SetScript("OnEvent", function()
        Engine:ApplyPendingResizes()
    end)
    self.resizeHandler = handler
end

function Engine:QueuePendingResize(frame, width, height)
    if not frame or not width or not height then return end
    if width <= 0 or height <= 0 then return end
    frame.__nuiPendingResize = frame.__nuiPendingResize or {}
    frame.__nuiPendingResize.width = width
    frame.__nuiPendingResize.height = height
    pendingResizeFrames[frame] = true
    self:EnsureResizeHandler()
end

function Engine:UpdatePartySpacing(cfg)
    if not CompactPartyFrame then return end
    if UnitAffectingCombat("player") then return end
    local spacing = cfg and cfg.layout and cfg.layout.spacing and cfg.layout.spacing.vertical or 0
    local firstFrame = _G["CompactPartyFrameMember1"]
    if firstFrame then
        EnsureBaseAnchor(firstFrame)
    end
    local firstAnchor = firstFrame and firstFrame.__nuiBaseAnchor
    local prevVisible
    local visibleIndex = 0
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            EnsureBaseAnchor(frame)
            local base = frame.__nuiBaseAnchor
            if base then
                local hide = cfg and ShouldHidePartyPlayerEntry(frame, cfg, "party")
                local offsetY = base.y or 0
                frame:ClearAllPoints()
                if hide then
                    frame:SetPoint(base.point, base.relativeTo, base.relativePoint, base.x, base.y)
                else
                    visibleIndex = visibleIndex + 1
                    if spacing > 0 and visibleIndex > 1 then
                        offsetY = offsetY - spacing
                    end
                    if visibleIndex == 1 and firstAnchor then
                        frame:SetPoint(firstAnchor.point, firstAnchor.relativeTo, firstAnchor.relativePoint, firstAnchor.x, firstAnchor.y)
                    else
                        local relativeTo = prevVisible or base.relativeTo
                        if not relativeTo or relativeTo == frame then
                            relativeTo = (firstAnchor and firstAnchor.relativeTo) or frame:GetParent()
                        end
                        frame:SetPoint(base.point, relativeTo, base.relativePoint, base.x or 0, offsetY or 0)
                    end
                    prevVisible = frame
                end
            end
        end
    end
end

local function DetermineMode(frame)
    local name = SafeGetName(frame)
    if not name then return nil end
    if name:match("^CompactPartyFrame") or name:match("^CompactRaidFrame") then
        if frame:GetParent() == CompactPartyFrame or name:match("PartyFrameMember") then
            return "party"
        end
    end
    if name:match("^CompactRaidFrame") or name:match("^CompactRaidGroup") then
        return "raid"
    end
    return nil
end

local function GetPartyIndex(frame)
    local name = SafeGetName(frame)
    if not name then return nil end
    local idx = name:match("CompactPartyFrameMember(%d+)")
    if idx then
        return tonumber(idx)
    end
    return nil
end

local function GetUnitToken(frame)
    if not frame then return nil end
    if frame.unit then
        return frame.unit
    end
    if frame.displayedUnit then
        return frame.displayedUnit
    end
    if CompactUnitFrame_GetUnit then
        local ok, unit = pcall(CompactUnitFrame_GetUnit, frame)
        if ok and unit then
            return unit
        end
    end
    if frame.GetUnit then
        local ok, unit = pcall(frame.GetUnit, frame)
        if ok and unit then
            return unit
        end
    end
    if frame.GetAttribute then
        local ok, unit = pcall(frame.GetAttribute, frame, "unit")
        if ok and unit then
            return unit
        end
    end
    return nil
end

local ICON_ZOOM = 0.08
local CUSTOM_DEBUFF_BORDER = "Interface\\AddOns\\NephUI\\Media\\white_border.tga"

local function GetUnitClassColor(unit)
    if not unit then return nil end
    if unit == "pet" then
        local _, playerClass = UnitClass("player")
        if type(playerClass) == "string" then
            local playerColor = RAID_CLASS_COLORS[playerClass]
            if playerColor then
                return playerColor.r, playerColor.g, playerColor.b
            end
        end
    end
    local _, class = UnitClass(unit)
    if type(class) == "string" then
        local color = RAID_CLASS_COLORS[class]
        if color then
            return color.r, color.g, color.b
        end
    end
    return nil
end

ShouldHidePartyPlayerEntry = function(frame, cfg, mode)
    if mode ~= "party" then return false end
    local general = cfg and cfg.general
    if not (general and general.hidePlayerFrame) then
        return false
    end
    local unit = GetUnitToken(frame)
    if not unit then
        return false
    end
    local ok, isPlayer = pcall(UnitIsUnit, unit, "player")
    return ok and isPlayer == true
end

local function ApplyPartyPlayerHiddenState(frame, cfg, hide)
    if not frame then return end
    if not frame.__nuiPartyPlayerHideHooked then
        frame.__nuiPartyPlayerHideHooked = true
        frame:HookScript("OnShow", function(self)
            if self.__nuiPartyPlayerHidden then
                self:SetAlpha(0)
                if self.EnableMouse then
                    self:EnableMouse(false)
                end
                self:Hide()
            end
        end)
    end
    if hide then
        if not frame.__nuiPartyPlayerHidden then
            frame.__nuiPartyPlayerHidden = true
            if frame.IsMouseEnabled and frame:IsMouseEnabled() then
                frame.__nuiPartyPlayerMouseWasEnabled = true
                if frame.EnableMouse then
                    frame:EnableMouse(false)
                end
            end
            frame.__nuiPartyPlayerWasShown = frame:IsShown()
        end
        frame:SetAlpha(0)
        frame:Hide()
        return
    end
    if frame.__nuiPartyPlayerHidden then
        frame.__nuiPartyPlayerHidden = nil
        if frame.__nuiPartyPlayerMouseWasEnabled and frame.EnableMouse then
            frame:EnableMouse(true)
        end
        frame.__nuiPartyPlayerMouseWasEnabled = nil
        local opacity = cfg and cfg.layout and cfg.layout.opacity or 1
        frame:SetAlpha(opacity)
        if frame.__nuiPartyPlayerWasShown ~= false then
            frame:Show()
        end
        frame.__nuiPartyPlayerWasShown = nil
    end
end

local function AcquireHighlightTexture(frame, key, suffix)
    if not frame then return nil end
    if frame[key] then
        return frame[key]
    end
    local name = SafeGetName(frame)
    if name and suffix then
        return _G[name .. suffix]
    end
    return nil
end

local function AcquireDebuffHighlightTexture(frame)
    if not frame then return nil end
    if frame.__nuiDebuffHighlight then
        return frame.__nuiDebuffHighlight
    end
    local highlight = frame.debuffHighlight or frame.DebuffHighlight or frame.debuffHighlightTexture
    if not highlight then
        local name = SafeGetName(frame)
        if name then
            highlight = _G[name .. "DebuffHighlight"]
                or _G[name .. "DebuffHighlightTexture"]
                or _G[name .. "DispelHighlight"]
        end
    end
    if not highlight and frame.GetRegions then
        for i = 1, frame:GetNumRegions() do
            local region = select(i, frame:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                local regionName = region.GetName and region:GetName()
                if regionName and (regionName:find("DebuffHighlight") or regionName:find("DispelHighlight")) then
                    highlight = region
                    break
                end
            end
        end
    end
    frame.__nuiDebuffHighlight = highlight
    return highlight
end

local BACKGROUND_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local function AcquireBlizzardBackground(frame)
    if not frame then return nil end
    if frame.background then
        if frame.background.SetTexture then
            frame.background:SetTexture(BACKGROUND_TEXTURE)
        end
        return frame.background
    end
    if frame.Background then
        if frame.Background.SetTexture then
            frame.Background:SetTexture(BACKGROUND_TEXTURE)
        end
        return frame.Background
    end
    local name = SafeGetName(frame)
    if name then
        local bg = _G[name .. "Background"]
        if bg then
            if bg.SetTexture then
                bg:SetTexture(BACKGROUND_TEXTURE)
            end
            return bg
        end
    end
    local mode = DetermineMode(frame)
    if mode == "party" then
        local bg = _G["CompactPartyFrameMemberBackground"]
        if bg and bg.SetTexture then
            bg:SetTexture(BACKGROUND_TEXTURE)
        end
        return bg
    elseif mode == "raid" then
        local bg = _G["CompactRaidFrameBackground"]
        if bg and bg.SetTexture then
            bg:SetTexture(BACKGROUND_TEXTURE)
        end
        return bg
    end
    return nil
end

local function ApplyBackgroundColor(target, r, g, b, a)
    if not target or not r or not g or not b then return end
    local alpha = a or 1
    if target.SetVertexColor then
        target:SetVertexColor(r, g, b, alpha)
        if target.SetAlpha then
            target:SetAlpha(alpha)
        end
        return
    end
    if target.SetColorTexture then
        target:SetColorTexture(r, g, b, alpha)
        return
    end
    if target.SetBackdropColor then
        target:SetBackdropColor(r, g, b, alpha)
    end
end

local function UpdateMouseoverState(frame, entering)
    if not frame then return end
    frame.__nuiMouseoverActive = entering == true
    local mode = DetermineMode(frame)
    if not mode then return end
    local cfg = Engine:GetConfig(mode)
    Engine:ApplyMouseoverHighlight(frame, cfg)
end

function Engine:GetConfig(mode)
    if not NephUI.db or not NephUI.db.profile then return nil end
    if mode == "raid" then
        return NephUI.db.profile.raidFrames
    elseif mode == "party" then
        return NephUI.db.profile.partyFrames
    end
    return nil
end

local function UpdateResourceBarValues(bar)
    if not bar or not bar.__owner then return end
    local owner = bar.__owner
    local mode = DetermineMode(owner)
    local cfg = Engine:GetConfig(mode)
    local settings = cfg and cfg.resource
    if not settings or settings.enabled == false then
        bar:Hide()
        return
    end
    local unit = GetUnitToken(owner)
    if not unit then
        bar:Hide()
        return
    end
    local maxPower = UnitPowerMax(unit)
    -- Use pcall to safely check comparison since secret values pass type check but can't be compared
    local maxPowerIsZero = true
    if type(maxPower) == "number" then
        local success, result = pcall(function() return maxPower == 0 end)
        if success then
            maxPowerIsZero = result
        else
            -- If comparison fails (secret value), assume it's not zero
            maxPowerIsZero = false
        end
    end

    if not maxPower or maxPowerIsZero then
        bar:Hide()
        return
    end
    bar:SetMinMaxValues(0, maxPower)
    bar:SetValue(UnitPower(unit))
    bar:Show()
end

local function ResolveTexture(name)
    if not name or name == "" then
        return "Interface\\TargetingFrame\\UI-StatusBar"
    end
    if LSM then
        local resolved = LSM:Fetch("statusbar", name, true)
        if resolved then
            return resolved
        end
    end
    return name
end

local function ResolveFont(name)
    if not name or name == "" then
        return GameFontHighlight:GetFont()
    end
    if LSM then
        local resolved = LSM:Fetch("font", name, true)
        if resolved then
            return resolved
        end
    end
    return name
end

local function FormatNumber(value, abbreviate)
    if not value then
        return ""
    end
    if abbreviate and AbbreviateNumbers then
        local ok, formatted = pcall(AbbreviateNumbers, value)
        if ok and formatted then
            return formatted
        end
    end
    return tostring(value)
end

function Engine:EnsureOverlay(frame)
    if frame.NephUIOverlay then return frame.NephUIOverlay end
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 70)
    frame.NephUIOverlay = overlay
    return overlay
end

function Engine:EnsureBorder(frame)
    if frame.NephUIBorder then return frame.NephUIBorder end
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetFrameLevel(frame:GetFrameLevel() + 55)
    frame.NephUIBorder = border
    return border
end

local function EnsureAuraBorder(frame, size)
    if not frame then return nil end
    size = size or 1
    if size <= 0 then
        if frame.__nuiAuraBorder then
            frame.__nuiAuraBorder:Hide()
        end
        return nil
    end
    if not frame.CreateTexture then
        return nil
    end
    local border = frame.__nuiAuraBorder
    if not border then
        border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.__nuiAuraBorder = border
        local level = frame.GetFrameLevel and frame:GetFrameLevel() or 0
        border:SetFrameLevel(level + 2)
        border:SetBackdropBorderColor(0, 0, 0, 1)
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    end
    if not border.__nuiEdgeSize or border.__nuiEdgeSize ~= size then
        border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = size,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        border.__nuiEdgeSize = size
    end
    border:SetBackdropBorderColor(0, 0, 0, 1)
    border:Show()
    return border
end

local function ResolveAuraIcon(element)
    if not element then
        return nil
    end
    if element.icon then return element.icon end
    if element.Icon then return element.Icon end
    if element.iconTexture then return element.iconTexture end
    if element.IconTexture then return element.IconTexture end
    if element.texture then return element.texture end
    if element.GetObjectType and element:GetObjectType() == "Texture" then
        return element
    end
    return nil
end

local function ApplyDefaultDebuffBorder(owner)
    if not owner then return end
    local function SetTexture(tex)
        if tex and tex.SetTexture then
            tex:SetTexture(CUSTOM_DEBUFF_BORDER)
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetAlpha(1)
        end
    end
    SetTexture(owner.DebuffBorder or owner.border or owner.Border)
    local name = SafeGetName(owner)
    if name then
        SetTexture(_G[name .. "Border"])
        SetTexture(_G[name .. "DebuffBorder"])
    end
end

function Engine:StyleAuraIcon(element, borderSize)
    if not element then return end
    local icon = ResolveAuraIcon(element)
    local owner = element
    if owner.GetObjectType and owner:GetObjectType() == "Texture" then
        owner = owner:GetParent()
    end
    if icon and icon.SetTexCoord then
        icon:SetTexCoord(ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM)
    end
    if owner and owner.CreateTexture then
        local border = EnsureAuraBorder(owner, borderSize)
        if border then
            border:Show()
        end
        ApplyDefaultDebuffBorder(owner)
    elseif icon and icon.GetParent then
        local parent = icon:GetParent()
        if parent and parent.CreateTexture then
            local border = EnsureAuraBorder(parent, borderSize)
            if border then
                border:Show()
            end
            ApplyDefaultDebuffBorder(parent)
        end
    end
end

function Engine:ApplySpecialAuraLayout(element, settings, frame)
    if not element or not settings then return end
    if element.ClearAllPoints then
        local anchorPoint = settings.anchor or "CENTER"
        element:ClearAllPoints()
        element:SetPoint(anchorPoint, frame, anchorPoint, settings.offsetX or 0, settings.offsetY or 0)
    end
    local size = settings.size
    if size and size > 0 then
        if element.SetSize then
            element:SetSize(size, size)
        elseif element.SetScale and element.GetWidth then
            local width = element:GetWidth()
            if width and width > 0 then
                element:SetScale(size / width)
            end
        end
    end
end

function Engine:StyleSpecialAuraIcons(frame)
    if not frame then return end
    local mode = DetermineMode(frame)
    local modeCfg = Engine:GetConfig(mode)
    local specialSettings = modeCfg and modeCfg.auras and modeCfg.auras.centerDefensive or nil
    local specialBorder = specialSettings and specialSettings.borderSize
    if frame.centerStatusIcon then
        self:StyleAuraIcon(frame.centerStatusIcon, 0)
        if frame.centerStatusIcon.icon then
            self:StyleAuraIcon(frame.centerStatusIcon.icon, 0)
        end
    end
    local defensive = frame.CenterDefensiveBuff or frame.centerDefensiveBuff
    if defensive then
        self:StyleAuraIcon(defensive, specialBorder)
        if defensive.icon then
            self:StyleAuraIcon(defensive.icon, specialBorder)
        end
        if specialSettings then
            self:ApplySpecialAuraLayout(defensive, specialSettings, frame)
        end
    end
    local defensiveIcon = frame.CenterDefensiveBuffIcon or frame.centerDefensiveBuffIcon
    if defensiveIcon then
        self:StyleAuraIcon(defensiveIcon, specialBorder)
    end
end

local function LerpColor(a, b, t)
    return a[1] + (b[1] - a[1]) * t,
           a[2] + (b[2] - a[2]) * t,
           a[3] + (b[3] - a[3]) * t,
           a[4] + (b[4] - a[4]) * t
end

function Engine:ApplyBackground(frame, cfg)
    if not frame or not cfg then return end
    local healthCfg = cfg.health
    if not healthCfg then return end
    local bgCfg = healthCfg.background
    if not bgCfg then return end
    local background = AcquireBlizzardBackground(frame)
    if not background then return end

    local r, g, b, a
    if bgCfg.useClassColor then
        local unit = GetUnitToken(frame)
        if unit then
            local cr, cg, cb = GetUnitClassColor(unit)
            if cr then
                r, g, b = cr, cg, cb
                a = bgCfg.classColorAlpha or 1
            end
        end
    end
    if not r then
        local color = bgCfg.color or {0, 0, 0, 0.35}
        r, g, b = color[1] or 0, color[2] or 0, color[3] or 0
        a = color[4] or 1
    end

    -- If we have a background health bar (missing health visualization), apply color to it instead of Blizzard background
    if frame.healthBarBG then
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            frame.healthBarBG:SetStatusBarColor(r, g, b, a)
        end
        -- Make Blizzard background transparent
        ApplyBackgroundColor(background, 0, 0, 0, 0)
    else
        -- Normal behavior: apply to Blizzard background
        ApplyBackgroundColor(background, r, g, b, a)
    end
end

function Engine:ApplyLayout(frame, cfg)
    if not frame or not cfg or not cfg.layout then return end
    local layout = cfg.layout
    local currentWidth = SafeGetNumber(frame, "GetWidth") or 0
    local currentHeight = SafeGetNumber(frame, "GetHeight") or 0
    local locked = InCombatLockdown and InCombatLockdown()
    if not locked and next(pendingResizeFrames) then
        self:ApplyPendingResizes()
    end
    -- Temporarily disable size overrides for compact party/raid frames.
    --[[ 
    if layout.useCustomSize then
        if not frame.__nuiOriginal then
            frame.__nuiOriginal = {width = currentWidth, height = currentHeight}
        end
    end
    local targetWidth, targetHeight
    if layout.useCustomSize then
        targetWidth = layout.width or currentWidth
        targetHeight = layout.height or currentHeight
    elseif frame.__nuiOriginal then
        targetWidth = frame.__nuiOriginal.width or currentWidth
        targetHeight = frame.__nuiOriginal.height or currentHeight
    end
    if targetWidth and targetWidth > 0 and targetHeight and targetHeight > 0 then
        if locked then
            self:QueuePendingResize(frame, targetWidth, targetHeight)
        else
            if pendingResizeFrames[frame] then
                pendingResizeFrames[frame] = nil
                frame.__nuiPendingResize = nil
            end
            frame:SetSize(targetWidth, targetHeight)
        end
    end
    --]]
    frame:SetAlpha(cfg.layout.opacity or 1)

    if frame.healthBar then
        frame.healthBar:ClearAllPoints()
        frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    end

    local borderCfg = cfg.layout.border or {}
    local borderSize = borderCfg.size or 0
    if borderSize > 0 then
        local border = self:EnsureBorder(frame)
        local thickness = math.max(borderSize, 0.5)
        if border.SetBackdrop then
            border:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = thickness,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            local color = borderCfg.color or {0, 0, 0, 0.85}
            border:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
        end
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", frame, "TOPLEFT", -borderSize, borderSize)
        border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", borderSize, -borderSize)
        border:Show()
    elseif frame.NephUIBorder then
        frame.NephUIBorder:Hide()
    end
end

local ColorCurveCache = {}
local DEFAULT_GRADIENT_COLORS = {
    low = {1, 0.1, 0.1, 1},
    medium = {1, 0.9, 0, 1},
    high = {0.1, 0.95, 0.1, 1},
}

local function EncodeColor(color)
    if not color then
        return "1,0,0,1"
    end
    return string.format("%.3f,%.3f,%.3f,%.3f", color[1] or 1, color[2] or 0, color[3] or 0, color[4] or 1)
end

local function GetGradientCurve(cfg)
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not UnitHealthPercentColor then
        return nil
    end

    local gradientConfig = (cfg and cfg.health and cfg.health.gradient) or {}
    local gradient = {
        low = gradientConfig.low or DEFAULT_GRADIENT_COLORS.low,
        medium = gradientConfig.medium or DEFAULT_GRADIENT_COLORS.medium,
        high = gradientConfig.high or DEFAULT_GRADIENT_COLORS.high,
    }
    local key = table.concat({
        EncodeColor(gradient.low),
        EncodeColor(gradient.medium),
        EncodeColor(gradient.high),
    }, "|")

    if ColorCurveCache[key] then
        return ColorCurveCache[key]
    end

    local curve = C_CurveUtil.CreateColorCurve()
    if not curve then
        return nil
    end
    if Enum and Enum.LuaCurveType and curve.SetType then
        curve:SetType(Enum.LuaCurveType.Linear)
    end

    local function ToColor(list, fallback)
        local r = list and list[1] or fallback[1]
        local g = list and list[2] or fallback[2]
        local b = list and list[3] or fallback[3]
        local a = list and list[4] or fallback[4]
        return CreateColor(r, g, b, a)
    end

    local lowColor = ToColor(gradient.low, {1, 0, 0, 1})
    local midColor = ToColor(gradient.medium, {1, 1, 0, 1})
    local highColor = ToColor(gradient.high, {0, 1, 0, 1})

    curve:AddPoint(0, lowColor)
    curve:AddPoint(0.5, midColor)
    curve:AddPoint(1, highColor)

    ColorCurveCache[key] = curve
    return curve
end

function Engine:UpdateHealthBarBG(frame, unit)
    if not frame or not frame.healthBarBG or not unit then return end

    local maxHealth = UnitHealthMax(unit)
    if not maxHealth or maxHealth == 0 then return end

    -- Calculate missing health using UnitHealthMissing API if available
    local missingHealth = 0
    if type(UnitHealthMissing) == "function" then
        local ok, missing = pcall(UnitHealthMissing, unit, true) -- Include absorbs
        if ok and missing and type(missing) == "number" then
            missingHealth = missing
        end
    else
        -- Fallback: calculate manually
        local currentHealth = UnitHealth(unit) or 0
        local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
        missingHealth = maxHealth - currentHealth - absorbs
        missingHealth = math.max(0, missingHealth)
    end

    -- Update background bar (shows missing health)
    frame.healthBarBG:SetMinMaxValues(0, maxHealth)
    frame.healthBarBG:SetValue(missingHealth)
end

function Engine:ApplyHealth(frame, cfg)
    if not frame or not frame.healthBar or not cfg or cfg.enabled == false then return end
    local healthCfg = cfg.health
    if not healthCfg then return end

    -- Create background health bar for missing health visualization
    if not frame.healthBarBG then
        frame.healthBarBG = CreateFrame("StatusBar", nil, frame)
        frame.healthBarBG:SetAllPoints(frame.healthBar)
        frame.healthBarBG:SetReverseFill(true) -- Fill from right to left to show missing health

        -- Hook into health updates to keep background bar in sync
        frame:HookScript("OnEvent", function(self, event, ...)
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                local unit = GetUnitToken(self)
                if unit then
                    Engine:UpdateHealthBarBG(self, unit)
                end
            end
        end)
    end

    frame.healthBar:SetStatusBarTexture(ResolveTexture(healthCfg.texture))
    frame.healthBar:SetOrientation((healthCfg.orientation or "HORIZONTAL"):upper())

    -- Background bar uses global background texture for missing health visualization (consistent with unit frames)
    frame.healthBarBG:SetStatusBarTexture(NephUI:GetTexture() or "Interface\\TargetingFrame\\UI-StatusBar")
    frame.healthBarBG:SetOrientation((healthCfg.orientation or "HORIZONTAL"):upper())

    local unit = GetUnitToken(frame)
    local r, g, b, a = 0, 1, 0, 1
    if healthCfg.useClassColor and unit then
        local cr, cg, cb = GetUnitClassColor(unit)
        if cr then
            r, g, b = cr, cg, cb
        end
    elseif healthCfg.customColor then
        r, g, b, a = healthCfg.customColor[1], healthCfg.customColor[2], healthCfg.customColor[3], healthCfg.customColor[4] or 1
    end
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        frame.healthBar:SetStatusBarColor(r, g, b, a or 1)
    end

    -- Background bar color is now handled by ApplyBackground function

    -- Initial update of background bar
    if unit then
        Engine:UpdateHealthBarBG(frame, unit)
    end
end

function Engine:FormatHealth(frame, cfg)
    local unit = GetUnitToken(frame)
    if not unit then return "" end
    local textCfg = (cfg and cfg.text and cfg.text.health) or {}
    local fmt = textCfg.format or "PERCENT"
    local abbreviate = textCfg.abbreviate

    local ok, result = pcall(function()
        if fmt == "PERCENT" then
            local percent = SafeUnitHealthPercent(unit, false, true) or SafeUnitHealthPercent(unit, false, false)
            if percent then
                return string.format("%.0f%%", percent)
            end
            return ""
        elseif fmt == "DEFICIT" then
            local missing = UnitHealthMissing(unit, true) or UnitHealthMissing(unit)
            if not missing or missing <= 0 then
                return ""
            end
            return string.format("-%s", FormatNumber(missing, abbreviate))
        else
            local current = UnitHealth(unit, true) or UnitHealth(unit)
            local max = UnitHealthMax(unit, true) or UnitHealthMax(unit)
            if not current or not max or max == 0 then
                return ""
            end
            if fmt == "CURRENTMAX" then
                return string.format("%s / %s", FormatNumber(current, abbreviate), FormatNumber(max, abbreviate))
            end
            return FormatNumber(current, abbreviate)
        end
    end)

    if ok then
        return result
    end
    return ""
end

function Engine:FormatName(frame, cfg)
    local unit = GetUnitToken(frame)
    if not unit then return "" end
    local name, realm = UnitName(unit)
    if not name then return "" end
    local nameCfg = (cfg and cfg.text and cfg.text.name) or {}
    if realm and realm ~= "" and nameCfg.showRealm then
        name = name .. "-" .. realm
    end
    local limit = nameCfg.maxChars or 0
    if limit > 0 and #name > limit then
        name = name:sub(1, limit)
    end
    return name
end

function Engine:ApplyTexts(frame, cfg)
    if not frame or not cfg or not cfg.text then return end
    local overlay = self:EnsureOverlay(frame)
    local healthCfg = cfg.text.health
    if healthCfg and healthCfg.enabled then
        if not frame.NephUIHealthText then
            frame.NephUIHealthText = overlay:CreateFontString(nil, "OVERLAY")
            frame.NephUIHealthText:SetDrawLayer("OVERLAY", 3)
        end
        if frame.NephUIHealthText.SetDrawLayer then
            frame.NephUIHealthText:SetDrawLayer("OVERLAY", 3)
        end
        local font = ResolveFont(healthCfg.font)
        frame.NephUIHealthText:SetFont(font, healthCfg.size or 12, healthCfg.outline or "OUTLINE")
        frame.NephUIHealthText:ClearAllPoints()
        frame.NephUIHealthText:SetPoint(healthCfg.anchor or "CENTER", frame, healthCfg.anchor or "CENTER", healthCfg.offsetX or 0, healthCfg.offsetY or 0)
        frame.NephUIHealthText:SetText(self:FormatHealth(frame, cfg))
        frame.NephUIHealthText:SetShadowOffset(healthCfg.shadowOffsetX or 0, healthCfg.shadowOffsetY or 0)
        if not healthCfg.useClassColor then
            local color = healthCfg.color or {1, 1, 1, 1}
            frame.NephUIHealthText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        else
            local unit = GetUnitToken(frame)
            local cr, cg, cb = GetUnitClassColor(unit)
            if cr then
                frame.NephUIHealthText:SetTextColor(cr, cg, cb)
            end
        end
        frame.NephUIHealthText:Show()
    elseif frame.NephUIHealthText then
        frame.NephUIHealthText:Hide()
    end

    local nameCfg = cfg.text and cfg.text.name
    if nameCfg and nameCfg.enabled then
        if not frame.NephUINameText then
            frame.NephUINameText = overlay:CreateFontString(nil, "OVERLAY")
            frame.NephUINameText:SetDrawLayer("OVERLAY", 4)
        end
        if frame.NephUINameText.SetDrawLayer then
            frame.NephUINameText:SetDrawLayer("OVERLAY", 4)
        end
        local target = frame.NephUINameText
        target:SetFont(ResolveFont(nameCfg.font), nameCfg.size or 11, nameCfg.outline or "OUTLINE")
        target:ClearAllPoints()
        target:SetPoint(nameCfg.anchor or "TOP", frame, nameCfg.anchor or "TOP", nameCfg.offsetX or 0, nameCfg.offsetY or 0)
        target:SetShadowOffset(nameCfg.shadowOffsetX or 0, nameCfg.shadowOffsetY or 0)
        target:SetText(self:FormatName(frame, cfg))
        if nameCfg.useClassColor then
            local unit = GetUnitToken(frame)
            local cr, cg, cb = GetUnitClassColor(unit)
            if cr then
                target:SetTextColor(cr, cg, cb)
            end
        else
            local color = nameCfg.color or {1, 1, 1, 1}
            target:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        end
        target:Show()
        if frame.name then
            frame.name:Hide()
        end
    else
        if frame.NephUINameText then
            frame.NephUINameText:Hide()
        end
        if frame.name then
            frame.name:Show()
        end
    end
end

local function DisableIconMouse(icon)
    if not icon then return end
    if icon.EnableMouse then icon:EnableMouse(false) end
    if icon.EnableMouseWheel then icon:EnableMouseWheel(false) end
    if icon.SetMouseMotionEnabled then icon:SetMouseMotionEnabled(false) end
end

local function ApplyIconLayout(frame, icon, settings)
    if not icon or not settings then return end
    icon:ClearAllPoints()
    local anchor = settings.anchor or "CENTER"
    icon:SetPoint(anchor, frame, anchor, settings.offsetX or 0, settings.offsetY or 0)
    if icon.SetScale then
        icon:SetScale(settings.scale or 1)
    end
end

local function HandleStandardIcon(frame, iconKey, settings, refreshFunc)
    local icon = frame[iconKey]
    if not icon or not settings then return end
    DisableIconMouse(icon)
    if settings.enabled then
        icon.__nuiForcedHidden = true
        if icon.Hide then
            icon:Hide()
        end
        return
    end
    if icon.__nuiForcedHidden then
        icon.__nuiForcedHidden = nil
        if refreshFunc then
            refreshFunc(frame)
        end
    end
    ApplyIconLayout(frame, icon, settings)
end

local function ResolveDispelIcon(frame, index)
    if not frame then return nil end
    local suffixes = {
        "DispelDebuff" .. index,
        "dispelDebuff" .. index,
    }
    for _, suffix in ipairs(suffixes) do
        local icon = frame[suffix]
        if icon then
            return icon
        end
    end
    local name = SafeGetName(frame)
    if name then
        for _, suffix in ipairs(suffixes) do
            local global = _G[name .. suffix]
            if global then
                return global
            end
        end
    end
    return nil
end

local function EnsureDispelIconLayout(icon)
    if not icon or icon.__nuiDispelLayout then return end
    local point, relativeTo, relativePoint, offsetX, offsetY = icon:GetPoint(1)
    icon.__nuiDispelLayout = {
        point = point or "CENTER",
        relativePoint = relativePoint or point or "CENTER",
        relativeTo = relativeTo or icon:GetParent(),
        offsetX = offsetX or 0,
        offsetY = offsetY or 0,
        scale = (icon.GetScale and icon:GetScale()) or 1,
    }
end

local function ApplyDispelIconLayout(icon, settings, index)
    if not icon or not settings then return end
    EnsureDispelIconLayout(icon)
    local layout = icon.__nuiDispelLayout
    local anchor = settings.anchor or layout.point
    local relativePoint = anchor or layout.relativePoint
    local relativeTo = layout.relativeTo or icon:GetParent()
    local offsetX = (settings.offsetX ~= nil) and settings.offsetX or layout.offsetX
    local offsetY = (settings.offsetY ~= nil) and settings.offsetY or layout.offsetY
    local spacing = (settings.spacing ~= nil) and settings.spacing or 18
    if index and index > 1 then
        local growth = 0
        if anchor and anchor:find("RIGHT") then
            growth = -spacing
        elseif anchor and anchor:find("LEFT") then
            growth = spacing
        end
        offsetX = offsetX + growth * (index - 1)
    end
    icon:ClearAllPoints()
    icon:SetPoint(anchor, relativeTo, relativePoint, offsetX, offsetY)
    local scale = (settings.scale ~= nil) and settings.scale or layout.scale
    if icon.SetScale then
        icon:SetScale(scale)
    end
end

local function HandleDispelIcons(frame, cfg)
    if not frame or not cfg or not cfg.icons or not cfg.icons.dispel then return end
    local settings = cfg.icons.dispel
    for i = 1, 3 do
        local icon = ResolveDispelIcon(frame, i)
        if icon then
            if settings.hide then
                if not icon.__nuiDispelHidden then
                    icon.__nuiDispelHidden = true
                    if icon.Hide then
                        icon:Hide()
                    end
                end
            else
                if icon.__nuiDispelHidden then
                    icon.__nuiDispelHidden = nil
                    if icon.Show then
                        icon:Show()
                    end
                end
                ApplyDispelIconLayout(icon, settings, i)
            end
        end
    end
end

function Engine:ApplyIcons(frame, cfg)
    if not frame or not cfg or not cfg.icons then return end
    HandleStandardIcon(
        frame,
        "leaderIcon",
        cfg.icons.leader,
        function(f)
            if CompactUnitFrame_UpdateLeaderIndicator then
                CompactUnitFrame_UpdateLeaderIndicator(f)
            end
        end
    )
    HandleStandardIcon(
        frame,
        "roleIcon",
        cfg.icons.role,
        function(f)
            if CompactUnitFrame_UpdateRoleIcon then
                CompactUnitFrame_UpdateRoleIcon(f)
            end
        end
    )
    HandleStandardIcon(
        frame,
        "raidIcon",
        cfg.icons.raid,
        function(f)
            if CompactUnitFrame_UpdateRaidTargetIcon then
                CompactUnitFrame_UpdateRaidTargetIcon(f)
            end
        end
    )
    HandleStandardIcon(
        frame,
        "readyCheckIcon",
        cfg.icons.ready,
        function(f)
            if CompactUnitFrame_UpdateReadyCheck then
                CompactUnitFrame_UpdateReadyCheck(f)
            end
        end
    )
    local centerSettings = cfg.icons.centerStatus
    if frame.centerStatusIcon and centerSettings then
        DisableIconMouse(frame.centerStatusIcon)
        if centerSettings.enabled then
            frame.centerStatusIcon.__nuiForcedHidden = true
            if CompactUnitFrame_HideCenterStatusIcon then
                CompactUnitFrame_HideCenterStatusIcon(frame)
            elseif frame.centerStatusIcon.Hide then
                frame.centerStatusIcon:Hide()
            end
        else
            if frame.centerStatusIcon.__nuiForcedHidden then
                frame.centerStatusIcon.__nuiForcedHidden = nil
                if CompactUnitFrame_UpdateCenterStatusIcon then
                    CompactUnitFrame_UpdateCenterStatusIcon(frame)
                elseif frame.centerStatusIcon.Show then
                    frame.centerStatusIcon:Show()
                end
        end
        ApplyIconLayout(frame, frame.centerStatusIcon, centerSettings)
    end
    HandleDispelIcons(frame, cfg)
end
end

function Engine:ApplyRoleIconTexture(frame, cfg, mode)
    if not frame or not frame.roleIcon then return end
    mode = mode or DetermineMode(frame)
    if not mode then return end
    if cfg and cfg.enabled == false then return end
    local iconSettings = cfg and cfg.icons and cfg.icons.role
    if iconSettings and iconSettings.enabled then
        return
    end

    local icon = frame.roleIcon
    local unit = GetUnitToken(frame)
    if not unit then
        icon:Hide()
        return
    end

    local overlay = self:EnsureOverlay(frame)
    if overlay and icon.GetParent and icon:GetParent() ~= overlay then
        icon:SetParent(overlay)
    end
    if icon.SetDrawLayer then
        icon:SetDrawLayer("OVERLAY", 7)
    end

    local role = UnitGroupRolesAssigned(unit)
    if not role or role == "NONE" then
        icon:Hide()
        return
    end
    local texture = ROLE_TEXTURES[role]
    if not texture then
        icon:Hide()
        return
    end

    if icon.SetAtlas then
        icon:SetAtlas(nil)
    end
    icon:SetTexture(texture)
    icon:SetTexCoord(0, 1, 0, 1)
    icon:Show()
end

function Engine:StyleAuras(frame, cfg)
    if not frame or not cfg or not cfg.auras then return end
    local function ApplyCountdownText(aura, countdownSettings)
        if not aura or not aura.cooldown then return end
        local cooldown = aura.cooldown
        if cooldown.SetHideCountdownNumbers then
            cooldown:SetHideCountdownNumbers(countdownSettings and countdownSettings.enabled == false)
        end
        if not countdownSettings or countdownSettings.enabled == false then
            return
        end
        local function apply()
            if not aura.cooldown or (aura.cooldown.IsForbidden and aura.cooldown:IsForbidden()) then
                return
            end
            local fontString = aura.cooldown.Text or aura.cooldown.timerText
            if not fontString and aura.cooldown.GetRegions then
                for _, region in ipairs({aura.cooldown:GetRegions()}) do
                    if region.GetObjectType and region:GetObjectType() == "FontString" then
                        fontString = region
                        break
                    end
                end
            end
            if fontString and fontString.SetFont then
                local fontPath = ResolveFont(countdownSettings.font)
                local outline = countdownSettings.outline or "OUTLINE"
                local size = countdownSettings.size or 12
                fontString:SetFont(fontPath, size, outline)
                if fontString.ClearAllPoints and fontString.SetPoint then
                    fontString:ClearAllPoints()
                    fontString:SetPoint("CENTER", aura, "CENTER", countdownSettings.offsetX or 0, countdownSettings.offsetY or 0)
                end
            end
        end
        apply()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, apply)
        end
    end
    local function Layout(icons, settings)
        if not icons or not settings then return end
        if settings.enabled == false then
            for _, aura in ipairs(icons) do
                if aura then
                    aura:Hide()
                end
            end
            return
        end
        local perRow = settings.perRow or 0
        local useRows = perRow and perRow > 0
        local max = settings.max or #icons
        local anchor = settings.anchor or "TOPLEFT"
        local offsetX = settings.offsetX or 0
        local offsetY = settings.offsetY or 0
        local spacingX = settings.spacingX or 18
        local spacingY = settings.spacingY or 18
        local directionX = (anchor:find("RIGHT") and -1 or 1)
        local directionY = (anchor:find("BOTTOM") and 1 or -1)
        local horizontalGrowth = settings.horizontalGrowth and string.upper(settings.horizontalGrowth)
        local verticalGrowth = settings.verticalGrowth and string.upper(settings.verticalGrowth)
        if horizontalGrowth == "LEFT" then
            directionX = -1
        elseif horizontalGrowth == "RIGHT" then
            directionX = 1
        end
        if verticalGrowth == "UP" then
            directionY = 1
        elseif verticalGrowth == "DOWN" then
            directionY = -1
        end
        local active = 0
        local verticalPart = ""
        if anchor:find("TOP") then
            verticalPart = "TOP"
        elseif anchor:find("BOTTOM") then
            verticalPart = "BOTTOM"
        end
        local horizontalPart = ""
        if anchor:find("LEFT") then
            horizontalPart = "LEFT"
        elseif anchor:find("RIGHT") then
            horizontalPart = "RIGHT"
        end
        local function CombinePoint(v, h)
            local vert = v or ""
            local horiz = h or ""
            if vert ~= "" and horiz ~= "" then
                return vert .. horiz
            elseif vert ~= "" then
                return vert
            elseif horiz ~= "" then
                return horiz
            end
            return "CENTER"
        end
        local basePoint = CombinePoint(verticalPart, horizontalPart)
        local rowsFirst = {}
        local rowsLast = {}
        for i = 1, math.min(#icons, max) do
            local aura = icons[i]
            if aura then
                local auraSize = settings.size or 36
                if aura.SetSize then
                    aura:SetSize(auraSize, auraSize)
                end
                aura:ClearAllPoints()
                active = active + 1
                local row = 0
                local col = active - 1
                if useRows then
                    row = math.floor((active - 1) / perRow)
                    col = (active - 1) % perRow
                end
                if col == 0 then
                    if row == 0 then
                        aura:SetPoint(basePoint, frame, anchor, offsetX, offsetY)
                    elseif useRows then
                        local previousRowAnchor = rowsFirst[row - 1]
                        if previousRowAnchor then
                            local selfPoint = CombinePoint(directionY > 0 and "BOTTOM" or "TOP", horizontalPart)
                            local relativePoint = CombinePoint(directionY > 0 and "TOP" or "BOTTOM", horizontalPart)
                            local yDelta = (directionY > 0 and spacingY or -spacingY)
                            aura:SetPoint(selfPoint, previousRowAnchor, relativePoint, 0, yDelta)
                        else
                            aura:SetPoint(basePoint, frame, anchor, offsetX, offsetY + (row * spacingY * directionY))
                        end
                    else
                        aura:SetPoint(basePoint, frame, anchor, offsetX, offsetY + (row * spacingY * directionY))
                    end
                    rowsFirst[row] = aura
                    rowsLast[row] = aura
                else
                    local prevAura = rowsLast[row]
                    if prevAura then
                        local selfPoint = CombinePoint(verticalPart, directionX > 0 and "LEFT" or "RIGHT")
                        local relativePoint = CombinePoint(verticalPart, directionX > 0 and "RIGHT" or "LEFT")
                        aura:SetPoint(selfPoint, prevAura, relativePoint, directionX > 0 and spacingX or -spacingX, 0)
                    else
                        aura:SetPoint(basePoint, frame, anchor, offsetX + (col * spacingX * directionX), offsetY + (row * spacingY * directionY))
                    end
                    rowsLast[row] = aura
                end
                if aura.count then
                    aura.count:SetFont(ResolveFont(settings.stack and settings.stack.font), settings.stack and settings.stack.size or 12, "OUTLINE")
                end
                if aura.cooldown then
                    if aura.cooldown.SetDrawSwipe then
                        aura.cooldown:SetDrawSwipe(not settings.hideSwipe)
                    end
                    ApplyCountdownText(aura, settings.countdown)
                end
                self:StyleAuraIcon(aura, settings.borderSize)
            end
        end
    end

    -- Adjust aura positioning based on resource bar
    local function AdjustAuraSettingsForResourceBar(auraSettings)
        if not auraSettings or not cfg.resource or cfg.resource.enabled == false then
            return auraSettings
        end

        local adjusted = {}
        for k, v in pairs(auraSettings) do
            adjusted[k] = v
        end

        -- If auras are anchored to BOTTOM, move them up by resource bar height
        local anchor = adjusted.anchor or "TOPLEFT"
        if anchor:find("BOTTOM") then
            local resourceHeight = cfg.resource.height or 4
            local resourceOffsetY = cfg.resource.offsetY or 0
            -- Add spacing between resource bar and auras (2px spacing + 1px border)
            local spacing = 3
            adjusted.offsetY = (adjusted.offsetY or 0) + resourceHeight + resourceOffsetY + spacing
        end

        return adjusted
    end

    Layout(frame.buffFrames, AdjustAuraSettingsForResourceBar(cfg.auras.buffs))
    Layout(frame.debuffFrames, AdjustAuraSettingsForResourceBar(cfg.auras.debuffs))
end

function Engine:UpdateResource(frame, cfg)
    if not frame or not cfg or not cfg.resource then
        if frame and frame.NephUIResourceBar then
            frame.NephUIResourceBar:Hide()
        end
        return
    end
    local settings = cfg.resource
    if settings.enabled == false then
        if frame.NephUIResourceBar then
            frame.NephUIResourceBar:Hide()
        end
        return
    end
    if not frame.NephUIResourceBar then
        frame.NephUIResourceBar = CreateFrame("StatusBar", nil, frame)
        frame.NephUIResourceBar.bg = frame.NephUIResourceBar:CreateTexture(nil, "BACKGROUND")
        frame.NephUIResourceBar.bg:SetAllPoints()
        frame.NephUIResourceBar.border = CreateFrame("Frame", nil, frame.NephUIResourceBar, "BackdropTemplate")
        frame.NephUIResourceBar.border:SetFrameLevel(frame.NephUIResourceBar:GetFrameLevel() + 1)
        frame.NephUIResourceBar.border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        frame.NephUIResourceBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    end
    local bar = frame.NephUIResourceBar
    bar:SetStatusBarTexture(ResolveTexture(settings.texture))
    bar:SetOrientation((settings.orientation or "HORIZONTAL"):upper())
    local width = settings.width or SafeGetNumber(frame, "GetWidth")
    if settings.matchHealthWidth and frame.healthBar then
        local matchedWidth = SafeGetNumber(frame.healthBar, "GetWidth")
        if matchedWidth and matchedWidth > 0 then
            width = matchedWidth
        end
    end
    if not width or width <= 0 then
        width = settings.width or SafeGetNumber(frame, "GetWidth") or 50
    end
    local height = settings.height or 4
    if type(height) ~= "number" or height <= 0 then
        height = 4
    end
    bar:SetSize(width, height)
    bar:ClearAllPoints()
    bar:SetPoint(settings.anchor or "BOTTOM", frame, settings.anchor or "BOTTOM", settings.offsetX or 0, settings.offsetY or 0)
    if bar.border then
        bar.border:ClearAllPoints()
        bar.border:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
        bar.border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
    end
    local unit = GetUnitToken(frame)
    if settings.useClassColor and unit then
        local cr, cg, cb = GetUnitClassColor(unit)
        if cr then
            bar:SetStatusBarColor(cr, cg, cb)
        end
    elseif settings.usePowerColor and unit then
        local pType = UnitPowerType(unit)
        local powerColor = pType and PowerBarColor and PowerBarColor[pType]
        if powerColor then
            bar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        else
            local info = pType and GetPowerBarInfoByID and GetPowerBarInfoByID(pType)
            if info and info.r then
                bar:SetStatusBarColor(info.r, info.g, info.b)
            end
        end
    elseif settings.color then
        local color = settings.color
        bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    end
    local bgColor = settings.backgroundColor or {0, 0, 0, 0.5}
    bar.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.5)
    bar.__owner = frame
    bar:UnregisterAllEvents()
    if unit then
        bar:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
        bar:RegisterUnitEvent("UNIT_POWER_FREQUENT", unit)
        bar:RegisterUnitEvent("UNIT_MAXPOWER", unit)
        bar:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
    else
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    if not bar.__powerHandler then
        bar:SetScript("OnEvent", function(self, event, eventUnit)
            if eventUnit and self.__owner then
                local ownerUnit = GetUnitToken(self.__owner)
                if ownerUnit and eventUnit ~= ownerUnit then
                    return
                end
            end
            UpdateResourceBarValues(self)
        end)
        bar.__powerHandler = true
    end
    UpdateResourceBarValues(bar)
end

local function UpdateAbsorbLayer(frame, unit, cfgEntry, fieldKey, valueFunc, defaultColor)
    local bar = frame[fieldKey]
    if not cfgEntry or cfgEntry.enabled == false then
        if bar then
            bar:Hide()
        end
        return
    end
    if not unit or not frame.healthBar then
        if bar then
            bar:Hide()
        end
        return
    end
    local maxHealth = UnitHealthMax(unit)
    if not maxHealth or maxHealth <= 0 then
        if bar then
            bar:Hide()
        end
        return
    end
    if not bar then
        bar = CreateFrame("StatusBar", nil, frame.healthBar)
        frame[fieldKey] = bar
    end
    bar:SetAllPoints(frame.healthBar)
    bar:SetStatusBarTexture(ResolveTexture(cfgEntry.texture))
    bar:SetMinMaxValues(0, maxHealth)
    local value = valueFunc and valueFunc(unit) or 0
    bar:SetValue(value or 0)
    local orientation = (cfgEntry.orientation or "HORIZONTAL"):upper()
    if orientation ~= "VERTICAL" then
        orientation = "HORIZONTAL"
    end
    bar:SetOrientation(orientation)
    local anchorPoint = cfgEntry.anchorPoint or "RIGHT"
    local reverseFill = anchorPoint == "RIGHT"
    bar:SetReverseFill(reverseFill)
    local color = cfgEntry.color or defaultColor
    if color then
        bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    end
    bar:Show()
end

function Engine:UpdateAbsorbs(frame, cfg)
    if not frame or not frame.healthBar then return end
    local unit = GetUnitToken(frame)
    local healCfg = cfg and cfg.healAbsorbs
    local damageCfg = cfg and cfg.damageAbsorbs
    local healDefaultColor = {0.4, 0.1, 0.1, 0.7}
    local damageDefaultColor = {0.15, 0.35, 0.8, 0.7}
    UpdateAbsorbLayer(frame, unit, healCfg, "NephUIHealAbsorb", UnitGetTotalHealAbsorbs, healDefaultColor)
    UpdateAbsorbLayer(frame, unit, damageCfg, "NephUIDamageAbsorb", UnitGetTotalAbsorbs, damageDefaultColor)
end

function Engine:UpdateRange(frame, cfg)
    if not frame or not cfg or not cfg.general then return end
    if cfg.general.fadeOutOfRange and frame.inRange ~= nil and frame:GetAlpha() then
        frame:SetAlpha(frame.inRange and 1 or (cfg.general.outOfRangeAlpha or 0.55))
    end
    if cfg.general.hideRangeWidget then
        if frame.rangeIndicator then frame.rangeIndicator:Hide() end
        if frame.outOfRangeIndicator then frame.outOfRangeIndicator:Hide() end
    end
end

local function ApplyBlizzardHighlightTexture(texture, options, replacement)
    if not texture or not options then return end
    texture.__nuiHighlightOriginal = texture.__nuiHighlightOriginal or {
        texture = texture:GetTexture(),
        texCoord = {texture:GetTexCoord()},
    }

    if options.enabled == false then
        texture:SetTexture(nil)
        return
    end

    if replacement then
        texture:SetTexture(replacement)
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end

    local original = texture.__nuiHighlightOriginal
    if original.texture then
        texture:SetTexture(original.texture)
    end
    local coords = original.texCoord
    if coords and #coords >= 4 then
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
end

function Engine:ApplySelectionHighlightSkin(frame, cfg)
    if not frame or not cfg or not cfg.highlights then return end
    local settings = cfg.highlights.blizzardSelection
    if not settings then return end
    local highlight = AcquireHighlightTexture(frame, "selectionHighlight", "SelectionHighlight")
    if not highlight then return end
    ApplyBlizzardHighlightTexture(highlight, settings, HIGHLIGHT_REPLACEMENTS.selection)
    local selectionConfig = cfg.highlights.selection or {}
    local alpha = selectionConfig.alpha or 1
    highlight:SetAlpha(alpha)
end

function Engine:ApplyAggroHighlightSkin(frame, cfg)
    if not frame or not cfg or not cfg.highlights then return end
    local settings = cfg.highlights.blizzardAggro
    if not settings then return end
    local highlight = AcquireHighlightTexture(frame, "aggroHighlight", "AggroHighlight")
    if not highlight then return end
    ApplyBlizzardHighlightTexture(highlight, settings, HIGHLIGHT_REPLACEMENTS.aggro)
    local overlay = self:EnsureOverlay(frame)
    if highlight.SetParent and highlight:GetParent() ~= overlay then
        highlight:SetParent(overlay)
    end
    if highlight.SetDrawLayer then
        highlight:SetDrawLayer("OVERLAY", 7)
    end
end

function Engine:ApplyMouseoverHighlight(frame, cfg)
    if not frame or not cfg or not cfg.highlights then return end
    local settings = cfg.highlights.mouseover
    if not settings or settings.enabled == false then
        if frame.NephUIMouseoverHighlight then
            frame.NephUIMouseoverHighlight:Hide()
        end
        return
    end
    if not frame.NephUIMouseoverHighlight then
        frame.NephUIMouseoverHighlight = frame:CreateTexture(nil, "OVERLAY")
        frame.NephUIMouseoverHighlight:SetAllPoints(frame)
        frame.NephUIMouseoverHighlight:SetTexture(HIGHLIGHT_REPLACEMENTS.mouseover)
        frame.NephUIMouseoverHighlight:SetDrawLayer("OVERLAY", 2)
    end
    frame.NephUIMouseoverHighlight:SetAlpha(settings.alpha or 0.5)
    frame.NephUIMouseoverHighlight:SetShown(frame.__nuiMouseoverActive == true)
end

function Engine:UpdateHighlights(frame, cfg)
    if not frame or not cfg or not cfg.highlights then return end
    local selection = cfg.highlights.selection
    if selection and selection.mode ~= "BLIZZARD" then
        if not frame.NephUISelectionHighlight then
            frame.NephUISelectionHighlight = frame:CreateTexture(nil, "OVERLAY")
            frame.NephUISelectionHighlight:SetAllPoints(frame)
        end
        local color = selection.color or {1, 1, 1, 1}
        local selectionAlpha = selection.alpha
        frame.NephUISelectionHighlight:SetColorTexture(color[1], color[2], color[3], 1)
        frame.NephUISelectionHighlight:SetAlpha(selectionAlpha or color[4] or 0.35)
        local unit = GetUnitToken(frame)
        local showSelection = false
        if unit then
            local ok, result = pcall(UnitIsUnit, "target", unit)
            showSelection = ok and result == true
        end
        frame.NephUISelectionHighlight:SetShown(showSelection)
    elseif frame.NephUISelectionHighlight then
        frame.NephUISelectionHighlight:Hide()
    end

    local aggro = cfg.highlights.aggro
    if aggro and aggro.mode ~= "BLIZZARD" then
        if not frame.NephUIAggroHighlight then
            local overlay = self:EnsureOverlay(frame)
            frame.NephUIAggroHighlight = overlay:CreateTexture(nil, "OVERLAY")
            frame.NephUIAggroHighlight:SetAllPoints(frame)
        end
        if frame.NephUIAggroHighlight.SetDrawLayer then
            frame.NephUIAggroHighlight:SetDrawLayer("OVERLAY", 7)
        end
        local unit = GetUnitToken(frame)
        local status = unit and UnitThreatSituation("player", unit)
        if status and status > 0 then
            local r, g, b = GetThreatStatusColor(status)
            frame.NephUIAggroHighlight:SetColorTexture(r, g, b, 0.35)
            frame.NephUIAggroHighlight:Show()
        else
            frame.NephUIAggroHighlight:Hide()
        end
    elseif frame.NephUIAggroHighlight then
        frame.NephUIAggroHighlight:Hide()
    end

    self:ApplySelectionHighlightSkin(frame, cfg)
    self:ApplyAggroHighlightSkin(frame, cfg)
    self:ApplyMouseoverHighlight(frame, cfg)
end

function Engine:ApplyFrameSpacing(frame, cfg, mode)
    if mode ~= "party" then
        if not UnitAffectingCombat("player") then
            EnsureBaseAnchor(frame)
            if frame.__nuiBaseAnchor and frame.__nuiBaseAnchor.active then
                local base = frame.__nuiBaseAnchor
                frame:ClearAllPoints()
                frame:SetPoint(base.point, base.relativeTo, base.relativePoint, base.x, base.y)
                frame.__nuiBaseAnchor.active = false
            end
        end
        return
    end
    if not frame then return end
    EnsureBaseAnchor(frame)
    self:UpdatePartySpacing(cfg)
end

function Engine:EnsureMouseoverHandlers(frame)
    if not frame or frame.__nuiMouseoverHooked then return end
    frame.__nuiMouseoverHooked = true
    frame.__nuiMouseoverActive = frame:IsMouseOver() == true
    frame:HookScript("OnEnter", function(f) UpdateMouseoverState(f, true) end)
    frame:HookScript("OnLeave", function(f) UpdateMouseoverState(f, false) end)
end

function Engine:UpdateAbsorbGlow(frame, cfg)
    if not frame then return end
    local mode = DetermineMode(frame)
    if not mode then return end

    local hideGlow = cfg and cfg.damageAbsorbs and cfg.damageAbsorbs.hideBlizzardGlow

    -- Try multiple ways to find and control absorb glow frames
    local frameName = frame:GetName()
    local glowFrames = {}

    -- Method 1: Direct frame properties
    if frame.overAbsorbGlow then table.insert(glowFrames, frame.overAbsorbGlow) end
    if frame.OverAbsorbGlow then table.insert(glowFrames, frame.OverAbsorbGlow) end

    -- Method 2: Named frames based on frame name
    if frameName then
        local namedGlow = _G[frameName .. "OverAbsorbGlow"]
        if namedGlow then table.insert(glowFrames, namedGlow) end
        local namedGlow2 = _G[frameName .. "OverAbsorbGlow"]
        if namedGlow2 then table.insert(glowFrames, namedGlow2) end
    end

    -- Method 3: Global frames (as fallback)
    if mode == "party" then
        local globalGlow = _G["CompactPartyFrameMemberOverAbsorbGlow"]
        if globalGlow then table.insert(glowFrames, globalGlow) end
    elseif mode == "raid" then
        local globalGlow = _G["CompactRaidFrameOverAbsorbGlow"]
        if globalGlow then table.insert(glowFrames, globalGlow) end
    end

    -- Method 4: Search children recursively for absorb-related frames/textures
    local function SearchFrameForGlows(parentFrame)
        if not parentFrame or not parentFrame.GetNumChildren then return end
        for i = 1, parentFrame:GetNumChildren() do
            local child = select(i, parentFrame:GetChildren())
            if child then
                local childName
                if child.GetName then
                    local ok, result = pcall(child.GetName, child)
                    if ok then
                        childName = result
                    end
                end
                if childName and (childName:find("OverAbsorb") or childName:find("overabsorb") or childName:find("AbsorbGlow") or childName:find("absorbglow") or childName:find("Glow")) then
                    table.insert(glowFrames, child)
                elseif child.GetTexture then
                    local texture = child:GetTexture()
                    if texture and type(texture) == "string" and (texture:find("OverAbsorb") or texture:find("overabsorb") or texture:find("absorb") or texture:find("glow")) then
                        table.insert(glowFrames, child)
                    end
                end
                -- Search recursively
                SearchFrameForGlows(child)
            end
        end
    end
    SearchFrameForGlows(frame)

    -- Apply the setting to all found glow frames
    -- Only hide when toggle is enabled, let Blizzard handle showing naturally when disabled
    for _, glowFrame in ipairs(glowFrames) do
        if glowFrame and glowFrame.Hide and hideGlow then
            glowFrame:Hide()
        end
    end
end

function Engine:RefreshAbsorbGlows(mode)
    self:ForEach(mode, function(frame)
        local cfg = self:GetConfig(mode)
        self:UpdateAbsorbGlow(frame, cfg)
    end)
end

function Engine:StyleFrame(frame)
    local mode = DetermineMode(frame)
    if not mode then return end
    local cfg = self:GetConfig(mode)
    if not cfg or cfg.enabled == false then return end
    if ShouldHidePartyPlayerEntry(frame, cfg, mode) then
        ApplyPartyPlayerHiddenState(frame, cfg, true)
        return
    else
        ApplyPartyPlayerHiddenState(frame, cfg, false)
    end
    self:EnsureMouseoverHandlers(frame)
    self:ApplyLayout(frame, cfg)
    self:ApplyHealth(frame, cfg)  -- Must come before ApplyBackground for missing health BG check
    self:ApplyBackground(frame, cfg)
    self:ApplyTexts(frame, cfg)
    self:ApplyIcons(frame, cfg)
    self:StyleAuras(frame, cfg)
    self:StyleSpecialAuraIcons(frame)
    self:UpdateResource(frame, cfg)
    self:UpdateAbsorbs(frame, cfg)
    self:UpdateRange(frame, cfg)
    self:UpdateHighlights(frame, cfg)
    self:UpdateAbsorbGlow(frame, cfg)
    self:ApplyFrameSpacing(frame, cfg, mode)
end

function Engine:ForEach(mode, callback)
    if mode == "party" then
        if CompactPartyFrame then
            for i = 1, 5 do
                local frame = _G["CompactPartyFrameMember" .. i]
                if frame then callback(frame) end
            end
        end
    elseif mode == "raid" then
        if CompactRaidFrameContainer then
            local frames = CompactRaidFrameContainer.flowFrames
            if frames then
                for _, frame in pairs(frames) do
                    callback(frame)
                end
            end
        end
    else
        self:ForEach("party", callback)
        self:ForEach("raid", callback)
    end
end

function Engine:RefreshMode(mode)
    self:ForEach(mode, function(frame)
        self:StyleFrame(frame)
    end)
end

function Engine:Initialize()
    if self.initialized then return end
    self.initialized = true
    hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame) Engine:StyleFrame(frame) end)
    hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
        local mode = DetermineMode(frame)
        local cfg = Engine:GetConfig(mode)
        Engine:StyleAuras(frame, cfg)
        Engine:StyleSpecialAuraIcons(frame)
    end)
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame) Engine:ApplyTexts(frame, Engine:GetConfig(DetermineMode(frame))) end)
    hooksecurefunc("CompactUnitFrame_UpdateHealth", function(frame)
        Engine:ApplyHealth(frame, Engine:GetConfig(DetermineMode(frame)))
        Engine:ApplyTexts(frame, Engine:GetConfig(DetermineMode(frame)))  -- Update health text when health changes
    end)
    hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
        Engine:UpdateAbsorbs(frame, Engine:GetConfig(DetermineMode(frame)))
        Engine:UpdateAbsorbGlow(frame, Engine:GetConfig(DetermineMode(frame)))
    end)

    -- Also hook into other potential absorb glow update functions
    if CompactUnitFrame_UpdateOverAbsorbGlow then
        hooksecurefunc("CompactUnitFrame_UpdateOverAbsorbGlow", function(frame)
            Engine:UpdateAbsorbGlow(frame, Engine:GetConfig(DetermineMode(frame)))
        end)
    end
    hooksecurefunc("CompactUnitFrame_UpdateInRange", function(frame) Engine:UpdateRange(frame, Engine:GetConfig(DetermineMode(frame))) end)
    hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", function(frame)
        local mode = DetermineMode(frame)
        local cfg = Engine:GetConfig(mode)
        Engine:ApplyIcons(frame, cfg)
        Engine:ApplyRoleIconTexture(frame, cfg, mode)
    end)
    hooksecurefunc("CompactUnitFrame_UpdateSelectionHighlight", function(frame)
        local mode = DetermineMode(frame)
        if not mode then return end
        local cfg = Engine:GetConfig(mode)
        Engine:ApplySelectionHighlightSkin(frame, cfg)
    end)
    hooksecurefunc("CompactUnitFrame_UpdateAggroHighlight", function(frame)
        local mode = DetermineMode(frame)
        if not mode then return end
        local cfg = Engine:GetConfig(mode)
        Engine:ApplyAggroHighlightSkin(frame, cfg)
    end)
    if CompactUnitFrame_UpdateDebuffHighlight then
        hooksecurefunc("CompactUnitFrame_UpdateDebuffHighlight", function(frame)
            Engine:ApplyDebuffHighlightLayer(frame)
        end)
    end
    if CompactUnitFrame_UpdateDispelHighlight then
        hooksecurefunc("CompactUnitFrame_UpdateDispelHighlight", function(frame)
            Engine:ApplyDebuffHighlightLayer(frame)
        end)
    end
end

function PartyFrames:ApplySoloVisibility()
    local cfg = NephUI.db.profile.partyFrames
    if not cfg then return end
    if CompactPartyFrameTitle then
        CompactPartyFrameTitle:SetShown(not cfg.general.hideHeaderText)
    end
    if cfg.general.showWhenSolo and CompactPartyFrame and not IsInGroup() and not InCombatLockdown() then
        CompactPartyFrame:SetShown(true)
        if CompactPartyFrame.Layout then
            CompactPartyFrame:Layout()
        end
    end
end

function PartyFrames:ApplyContainerSettings()
    self:ApplySoloVisibility()
    Engine:RefreshMode("party")
end

function PartyFrames:Initialize()
    if self.initialized then return end
    self.initialized = true
    Engine:Initialize()
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:SetScript("OnEvent", function()
        PartyFrames:ApplyContainerSettings()
    end)
    if EditModeManagerFrame then
        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
            PartyFrames:ApplyContainerSettings()
        end)
        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            C_Timer.After(0.1, function()
                PartyFrames:ApplyContainerSettings()
            end)
        end)
    end
    if type(CompactPartyFrame_UpdateVisibility) == "function" then
        hooksecurefunc("CompactPartyFrame_UpdateVisibility", function()
            PartyFrames:ApplySoloVisibility()
        end)
    elseif CompactPartyFrame and type(CompactPartyFrame.UpdateVisibility) == "function" then
        hooksecurefunc(CompactPartyFrame, "UpdateVisibility", function()
            PartyFrames:ApplySoloVisibility()
        end)
    end
    self:ApplyContainerSettings()
end

function PartyFrames:Refresh()
    self:ApplyContainerSettings()
end
