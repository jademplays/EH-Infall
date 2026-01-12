local ADDON_NAME, ns = ...
local NephUI = ns.Addon

if not NephUI then
	error("NephUI not found! PixelPerfect.lua must load after Main.lua")
end

local min, max, floor, format = min, max, math.floor, string.format

local _G = _G
local GetPhysicalScreenSize = GetPhysicalScreenSize

function NephUI:RefreshGlobalFX()
	_G.GlobalFXDialogModelScene:Hide()
	_G.GlobalFXDialogModelScene:Show()

	_G.GlobalFXMediumModelScene:Hide()
	_G.GlobalFXMediumModelScene:Show()

	_G.GlobalFXBackgroundModelScene:Hide()
	_G.GlobalFXBackgroundModelScene:Show()
end

function NephUI:IsEyefinity(width, height)
	if NephUI.db.profile.general.eyefinity and width >= 3840 then
		if width >= 9840 then return 3280 end
		if width >= 7680 and width < 9840 then return 2560 end
		if width >= 5760 and width < 7680 then return 1920 end
		if width >= 5040 and width < 5760 then return 1680 end

		if width >= 4800 and width < 5760 and height == 900 then return 1600 end

		if width >= 4320 and width < 4800 then return 1440 end
		if width >= 4080 and width < 4320 then return 1360 end
		if width >= 3840 and width < 4080 then return 1224 end
	end
end

function NephUI:IsUltrawide(width, height)
	if NephUI.db.profile.general.ultrawide and width >= 2560 then
		if width >= 3440 and (height == 1440 or height == 1600) then return 2560 end

		if width >= 2560 and (height == 1080 or height == 1200) then return 1920 end
	end
end

function NephUI:UIMult()
	NephUI.mult = NephUI.perfect
end

function NephUI:PixelBestSize()
	return max(0.4, min(1.15, NephUI.perfect))
end

function NephUI:PixelScaleChanged(event)
	if event == 'UI_SCALE_CHANGED' then
		NephUI.physicalWidth, NephUI.physicalHeight = GetPhysicalScreenSize()
		NephUI.resolution = format('%dx%d', NephUI.physicalWidth, NephUI.physicalHeight)
		NephUI.perfect = 768 / NephUI.physicalHeight
	end

	NephUI:UIMult()
	
	if NephUI.ActionBars and NephUI.ActionBars.RefreshAll then
		NephUI.ActionBars:RefreshAll()
	end
end

function NephUI:Scale(x)
	local m = NephUI.mult
	if m == 1 or x == 0 then
		return x
	else
		local y = m > 1 and m or -m
		return x - x % (x < 0 and y or -y)
	end
end

-- Scale a border size and snap it to whole pixels (allows 0 to hide borders)
function NephUI:ScaleBorder(borderSize)
	local size = borderSize or 1
	size = floor(size + 0.5)
	if size < 0 then size = 0 end

	local scaled = self:Scale(size)
	scaled = floor(scaled + 0.5)
	if scaled < 0 then scaled = 0 end

	return scaled
end

