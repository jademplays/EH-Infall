local ADDON_NAME, ns = ...
local NephUI = ns.Addon

local RaidFrames = {}
NephUI.RaidFrames = RaidFrames

local Engine = NephUI.CompactFrames

local function ForEachGroup(callback)
    for i = 1, 8 do
        local group = _G["CompactRaidGroup" .. i]
        if group then
            callback(group, i)
        end
    end
end

function RaidFrames:ApplyGroupLabels()
    local cfg = NephUI.db.profile.raidFrames
    if not cfg or not cfg.general then return end
    ForEachGroup(function(group)
        if group.title then
            group.title:SetShown(not cfg.general.hideGroupLabels)
        end
        if group.borderFrame and group.borderFrame.title then
            group.borderFrame.title:SetShown(not cfg.general.hideGroupLabels)
        end
    end)
end

function RaidFrames:ApplyContainerSettings()
    self:ApplyGroupLabels()
    if Engine and Engine.RefreshMode then
        Engine:RefreshMode("raid")
    end
end

function RaidFrames:Initialize()
    if self.initialized then return end
    self.initialized = true
    if Engine and Engine.Initialize then
        Engine:Initialize()
    end
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self.eventFrame:SetScript("OnEvent", function()
        RaidFrames:ApplyContainerSettings()
    end)
    if EditModeManagerFrame then
        local function RefreshRaidFrames()
            RaidFrames:ApplyContainerSettings()
        end
        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", RefreshRaidFrames)
        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            C_Timer.After(0.1, function()
                RefreshRaidFrames()
            end)
        end)
    end
    self:ApplyContainerSettings()
end

function RaidFrames:Refresh()
    self:ApplyContainerSettings()
end
