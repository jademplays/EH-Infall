local ADDON_NAME, ns = ...
local NephUI = ns.Addon

if not NephUI then
	error("NephUI not found! Toolkit.lua must load after Main.lua")
end

local _G = _G
local type = type
local getmetatable = getmetatable
local hooksecurefunc = hooksecurefunc
local tonumber = tonumber

local EnumerateFrames = EnumerateFrames
local CreateFrame = CreateFrame

local issecurevalue = issecurevalue

local function CanAccessFrame(frame)
	if not frame then
		return false
	end

	if issecurevalue and issecurevalue(frame) then
		return false
	end

	if frame.IsForbidden then
		local ok, forbidden = pcall(frame.IsForbidden, frame)
		if not ok or forbidden then
			return false
		end
	end

	return true
end

local function WatchPixelSnap(frame, snap)
	if not CanAccessFrame(frame) then
		return
	end

	if frame.PixelSnapDisabled and snap then
		frame.PixelSnapDisabled = nil
	end
end

local function DisablePixelSnap(frame)
	if not CanAccessFrame(frame) then
		return
	end

	if not frame.PixelSnapDisabled then
		if frame.SetSnapToPixelGrid then
			frame:SetSnapToPixelGrid(false)
			frame:SetTexelSnappingBias(0)
		elseif frame.GetStatusBarTexture then
			local texture = frame:GetStatusBarTexture()
			if type(texture) == 'table' and texture.SetSnapToPixelGrid then
				texture:SetSnapToPixelGrid(false)
				texture:SetTexelSnappingBias(0)
			end
		end

		frame.PixelSnapDisabled = true
	end
end

local function Size(frame, width, height, ...)
	local w = NephUI:Scale(width)
	frame:SetSize(w, (height and NephUI:Scale(height)) or w, ...)
end

local function Width(frame, width, ...)
	frame:SetWidth(NephUI:Scale(width), ...)
end

local function Height(frame, height, ...)
	frame:SetHeight(NephUI:Scale(height), ...)
end

local function Point(obj, arg1, arg2, arg3, arg4, arg5, ...)
	if not arg2 then arg2 = obj:GetParent() end

	if type(arg2)=='number' then arg2 = NephUI:Scale(arg2) end
	if type(arg3)=='number' then arg3 = NephUI:Scale(arg3) end
	if type(arg4)=='number' then arg4 = NephUI:Scale(arg4) end
	if type(arg5)=='number' then arg5 = NephUI:Scale(arg5) end

	obj:SetPoint(arg1, arg2, arg3, arg4, arg5, ...)
end

local function GrabPoint(obj, pointValue)
	if type(pointValue) == 'string' then
		local pointIndex = tonumber(pointValue)
		if not pointIndex then
			for i = 1, obj:GetNumPoints() do
				local point, relativeTo, relativePoint, xOfs, yOfs = obj:GetPoint(i)
				if not point then
					break
				elseif point == pointValue then
					return point, relativeTo, relativePoint, xOfs, yOfs
				end
			end
		end

		pointValue = pointIndex
	end

	return obj:GetPoint(pointValue)
end

local function SetPointsRestricted(frame)
	if frame and not pcall(frame.GetPoint, frame) then
		return true
	end
end

local function NudgePoint(obj, xAxis, yAxis, noScale, pointValue, clearPoints)
	if not xAxis then xAxis = 0 end
	if not yAxis then yAxis = 0 end

	local x = (noScale and xAxis) or NephUI:Scale(xAxis)
	local y = (noScale and yAxis) or NephUI:Scale(yAxis)

	local point, relativeTo, relativePoint, xOfs, yOfs = GrabPoint(obj, pointValue)

	if clearPoints or SetPointsRestricted(obj) then
		obj:ClearAllPoints()
	end

	obj:SetPoint(point, relativeTo, relativePoint, xOfs + x, yOfs + y)
end

local function PointXY(obj, xOffset, yOffset, noScale, pointValue, clearPoints)
	local x = xOffset and ((noScale and xOffset) or NephUI:Scale(xOffset))
	local y = yOffset and ((noScale and yOffset) or NephUI:Scale(yOffset))

	local point, relativeTo, relativePoint, xOfs, yOfs = GrabPoint(obj, pointValue)

	if clearPoints or SetPointsRestricted(obj) then
		obj:ClearAllPoints()
	end

	obj:SetPoint(point, relativeTo, relativePoint, x or xOfs, y or yOfs)
end

local function SetOutside(obj, anchor, xOffset, yOffset, anchor2, noScale)
	if not anchor then anchor = obj:GetParent() end

	if not xOffset then xOffset = 1 end
	if not yOffset then yOffset = 1 end
	local x = (noScale and xOffset) or NephUI:Scale(xOffset)
	local y = (noScale and yOffset) or NephUI:Scale(yOffset)

	if SetPointsRestricted(obj) or obj:GetPoint() then
		obj:ClearAllPoints()
	end

	DisablePixelSnap(obj)
	obj:SetPoint('TOPLEFT', anchor, 'TOPLEFT', -x, y)
	obj:SetPoint('BOTTOMRIGHT', anchor2 or anchor, 'BOTTOMRIGHT', x, -y)
end

local function SetInside(obj, anchor, xOffset, yOffset, anchor2, noScale)
	if not anchor then anchor = obj:GetParent() end

	if not xOffset then xOffset = 1 end
	if not yOffset then yOffset = 1 end
	local x = (noScale and xOffset) or NephUI:Scale(xOffset)
	local y = (noScale and yOffset) or NephUI:Scale(yOffset)

	if SetPointsRestricted(obj) or obj:GetPoint() then
		obj:ClearAllPoints()
	end

	DisablePixelSnap(obj)
	obj:SetPoint('TOPLEFT', anchor, 'TOPLEFT', x, -y)
	obj:SetPoint('BOTTOMRIGHT', anchor2 or anchor, 'BOTTOMRIGHT', -x, y)
end

local API = {
	Size = Size,
	Point = Point,
	Width = Width,
	Height = Height,
	PointXY = PointXY,
	GrabPoint = GrabPoint,
	NudgePoint = NudgePoint,
	SetOutside = SetOutside,
	SetInside = SetInside,
}

local function AddAPI(object)
	local mk = getmetatable(object).__index
	for method, func in next, API do
		if not object[method] then
			mk[method] = func
		end
	end

	if not object.DisabledPixelSnap and (mk.SetSnapToPixelGrid or mk.SetStatusBarTexture or mk.SetColorTexture or mk.SetVertexColor or mk.CreateTexture or mk.SetTexCoord or mk.SetTexture) then
		if mk.SetSnapToPixelGrid then hooksecurefunc(mk, 'SetSnapToPixelGrid', WatchPixelSnap) end
		if mk.SetStatusBarTexture then hooksecurefunc(mk, 'SetStatusBarTexture', DisablePixelSnap) end
		if mk.SetColorTexture then hooksecurefunc(mk, 'SetColorTexture', DisablePixelSnap) end
		if mk.SetVertexColor then hooksecurefunc(mk, 'SetVertexColor', DisablePixelSnap) end
		if mk.CreateTexture then hooksecurefunc(mk, 'CreateTexture', DisablePixelSnap) end
		if mk.SetTexCoord then hooksecurefunc(mk, 'SetTexCoord', DisablePixelSnap) end
		if mk.SetTexture then hooksecurefunc(mk, 'SetTexture', DisablePixelSnap) end

		mk.DisabledPixelSnap = true
	end
end

local handled = { Frame = true }
local object = CreateFrame('Frame')
AddAPI(object)
AddAPI(object:CreateTexture())
AddAPI(object:CreateFontString())
if object.CreateMaskTexture then
	AddAPI(object:CreateMaskTexture())
end

object = EnumerateFrames()
while object do
	local objType = object:GetObjectType()
	if not object:IsForbidden() and not handled[objType] then
		AddAPI(object)
		handled[objType] = true
	end

	object = EnumerateFrames(object)
end

AddAPI(_G.GameFontNormal)
AddAPI(CreateFrame('ScrollFrame'))

