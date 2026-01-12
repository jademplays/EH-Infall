local ADDON_NAME, ns = ...

local NephUI = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME,
    "AceConsole-3.0",
    "AceEvent-3.0"
)

ns.Addon = NephUI

local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub("LibDeflate", true)
local AceDBOptions = LibStub("AceDBOptions-3.0", true)
local LibDualSpec   = LibStub("LibDualSpec-1.0", true)

local WHITE8 = "Interface\\Buttons\\WHITE8X8"

local SELECTION_ALPHA = 0.5
local SelectionRegionKeys = {
    "Center",
    "MouseOverHighlight",
    "TopEdge",
    "BottomEdge",
    "LeftEdge",
    "RightEdge",
    "TopLeft",
    "TopRight",
    "BottomLeft",
    "BottomRight",
    "Left",
    "Right",
    "Top",
    "Bottom",
}

local function ApplyAlphaToRegion(region)
    if not region or not region.SetAlpha then
        return
    end

    region:SetAlpha(SELECTION_ALPHA)
    if region.HookScript and not region.__nephuiSelectionAlphaHooked then
        region.__nephuiSelectionAlphaHooked = true
        region:HookScript("OnShow", function(self)
            self:SetAlpha(SELECTION_ALPHA)
        end)
    end
end

local function ForceSelectionAlpha(selection)
    if not selection or not selection.SetAlpha then
        return
    end

    selection.__nephuiSelectionAlphaLock = true
    selection:SetAlpha(SELECTION_ALPHA)
    selection.__nephuiSelectionAlphaLock = nil
end

function NephUI:ApplySelectionAlpha(selection)
    if not selection then
        return
    end

    ForceSelectionAlpha(selection)

    if selection.HookScript and not selection.__nephuiSelectionOnShowHooked then
        selection.__nephuiSelectionOnShowHooked = true
        selection:HookScript("OnShow", function(self)
            NephUI:ApplySelectionAlpha(self)
        end)
    end

    if selection.SetAlpha and not selection.__nephuiSelectionAlphaHooked then
        selection.__nephuiSelectionAlphaHooked = true
        hooksecurefunc(selection, "SetAlpha", function(frame)
            if frame.__nephuiSelectionAlphaLock then
                return
            end
            ForceSelectionAlpha(frame)
        end)
    end

    for _, key in ipairs(SelectionRegionKeys) do
        ApplyAlphaToRegion(selection[key])
    end
end

function NephUI:ApplySelectionAlphaToFrame(frame)
    if not frame then
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end
    if frame.Selection then
        self:ApplySelectionAlpha(frame.Selection)
    end
end

function NephUI:ApplySelectionAlphaToAllFrames()
    local frame = EnumerateFrames()
    while frame do
        self:ApplySelectionAlphaToFrame(frame)
        frame = EnumerateFrames(frame)
    end
end

function NephUI:InitializeSelectionAlphaController()
    if self.__selectionAlphaInitialized then
        return
    end
    self.__selectionAlphaInitialized = true

    local function TryHookSelectionMixin()
        if self.__selectionMixinHooked then
            return true
        end
        if EditModeSelectionFrameBaseMixin then
            self.__selectionMixinHooked = true
            hooksecurefunc(EditModeSelectionFrameBaseMixin, "OnLoad", function(selectionFrame)
                NephUI:ApplySelectionAlpha(selectionFrame)
            end)
            hooksecurefunc(EditModeSelectionFrameBaseMixin, "OnShow", function(selectionFrame)
                NephUI:ApplySelectionAlpha(selectionFrame)
            end)
            return true
        end
        return false
    end

    if not TryHookSelectionMixin() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("ADDON_LOADED")
        waiter:SetScript("OnEvent", function(self, _, addonName)
            if addonName == "Blizzard_EditMode" or addonName == ADDON_NAME then
                if TryHookSelectionMixin() then
                    self:UnregisterEvent("ADDON_LOADED")
                    self:SetScript("OnEvent", nil)
                end
            end
        end)
    end

    self:ApplySelectionAlphaToAllFrames()
    C_Timer.After(0.5, function()
        NephUI:ApplySelectionAlphaToAllFrames()
    end)

    self.SelectionAlphaTicker = C_Timer.NewTicker(1.0, function()
        if EditModeManagerFrame and EditModeManagerFrame.editModeActive then
            NephUI:ApplySelectionAlphaToAllFrames()
        end
    end)
end

function NephUI:ExportProfileToString()
    if not self.db or not self.db.profile then
        return "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local serialized = AceSerializer:Serialize(self.db.profile)
    if not serialized or type(serialized) ~= "string" then
        return "Failed to serialize profile."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return "Failed to compress profile."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return "Failed to encode profile."
    end

    return "NUI1:" .. encoded
end

function NephUI:ImportProfileFromString(str)
    if not self.db or not self.db.profile then
        return false, "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, "No data provided."
    end

    str = str:gsub("%s+", "")
    str = str:gsub("^CDM1:", "")
    str = str:gsub("^NUI1:", "")

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, t = AceSerializer:Deserialize(serialized)
    if not ok or type(t) ~= "table" then
        return false, "Could not deserialize profile."
    end

    local profile = self.db.profile
    for k in pairs(profile) do
        profile[k] = nil
    end
    for k, v in pairs(t) do
        profile[k] = v
    end

    if self.RefreshAll then
        self:RefreshAll()
    end

    return true
end

function NephUI:OnInitialize()
    local defaults = NephUI.defaults
    if not defaults then
        error("NephUI: Defaults not loaded! Make sure Core/Defaults.lua is loaded before Core/Main.lua")
    end
    
    -- Use a unique database namespace to avoid conflicts with other addons
    -- The name must match the SavedVariables in NephUI.toc
    self.db = LibStub("AceDB-3.0"):New("NephUIDB", defaults, true)
    
    -- Verify the database was created with the correct namespace
    if not self.db or not self.db.sv then
        error("NephUI: Failed to initialize database! Check SavedVariables in NephUI.toc")
    end
    
    ns.db = self.db

    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied",  "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset",   "OnProfileChanged")
    
    -- Create ShadowUIParent for hiding UI elements
    self.ShadowUIParent = CreateFrame("Frame", nil, UIParent)
    self.ShadowUIParent:Hide()

    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(self.db, ADDON_NAME)
        -- Debug: verify LibDualSpec is working
        if self.db.IsDualSpecEnabled then
            -- LibDualSpec is properly initialized
        end
    else
        -- LibDualSpec not available (may be disabled in Classic Era for non-Season realms)
    end

    self:InitializePixelPerfect()

    self:SetupOptions()
    
    self:RegisterChatCommand("nephui", "OpenConfig")
    self:RegisterChatCommand("nui", "OpenConfig")
    self:RegisterChatCommand("nephuirefresh", "ForceRefreshBuffIcons")
    self:RegisterChatCommand("nephuicheckdualspec", "CheckDualSpec")
    
    self:CreateMinimapButton()
end

function NephUI:OnProfileChanged(event, db, profileKey)
    if self.RefreshAll then
        -- Defer RefreshAll if in combat to avoid taint/secret value errors
        if InCombatLockdown() then
            if not self.__pendingRefreshAll then
                self.__pendingRefreshAll = true
                local eventFrame = CreateFrame("Frame")
                eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                eventFrame:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    if NephUI.RefreshAll and not InCombatLockdown() then
                        NephUI:RefreshAll()
                    end
                    NephUI.__pendingRefreshAll = nil
                end)
            end
        else
            self:RefreshAll()
        end
    end
end

function NephUI:InitializePixelPerfect()
    self.physicalWidth, self.physicalHeight = GetPhysicalScreenSize()
    self.resolution = string.format('%dx%d', self.physicalWidth, self.physicalHeight)
    self.perfect = 768 / self.physicalHeight
    
    self:UIMult()
    
    self:RegisterEvent('UI_SCALE_CHANGED')
end

function NephUI:UI_SCALE_CHANGED()
    self:PixelScaleChanged('UI_SCALE_CHANGED')
end

local function StyleMicroButtonRegion(button, region)
    if not (button and region) then
        return
    end
    if region.__nephuiStyled then
        return
    end

    region.__nephuiStyled = true
    region:SetTexture(WHITE8)
    region:SetVertexColor(0, 0, 0, 1)
    region:SetAlpha(0.8)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", button, 2.5, -2.5)
    region:SetPoint("BOTTOMRIGHT", button, -2.5, 2.5)
end

local function StyleMicroButton(button)
    if not button then
        return
    end
    StyleMicroButtonRegion(button, button.Background)
    StyleMicroButtonRegion(button, button.PushedBackground)
end

function NephUI:StyleMicroButtons()
    if type(MICRO_BUTTONS) == "table" then
        for _, name in ipairs(MICRO_BUTTONS) do
            StyleMicroButton(_G[name])
        end
    end
    -- Fallback if MICRO_BUTTONS is missing
    StyleMicroButton(_G.CharacterMicroButton)
end

function NephUI:PLAYER_LOGIN()
    if self.ApplyGlobalFont then
        self:ApplyGlobalFont()
    end
    self:UnregisterEvent("PLAYER_LOGIN")
end

function NephUI:OnEnable()
    SetCVar("cooldownViewerEnabled", 1)
    
    if self.UIMult then
        self:UIMult()
    end
    
    if self.ApplyGlobalFont then
        C_Timer.After(0.5, function()
            self:ApplyGlobalFont()
        end)
    end
    
    self:RegisterEvent("PLAYER_LOGIN")
    
    C_Timer.After(0.1, function()
        NephUI:StyleMicroButtons()
    end)
    
    if self.IconViewers and self.IconViewers.HookViewers then
        self.IconViewers:HookViewers()
    end

    if self.IconViewers and self.IconViewers.BuffBarCooldownViewer and self.IconViewers.BuffBarCooldownViewer.Initialize then
        self.IconViewers.BuffBarCooldownViewer:Initialize()
    end

    if self.ProcGlow and self.ProcGlow.Initialize then
        C_Timer.After(1.0, function()
            self.ProcGlow:Initialize()
        end)
    end

    if self.CastBars and self.CastBars.Initialize then
        self.CastBars:Initialize()
    end
    
    if self.ResourceBars and self.ResourceBars.Initialize then
        self.ResourceBars:Initialize()
    end

    if self.PartyFrames and self.PartyFrames.Initialize then
        self.PartyFrames:Initialize()
    end

    if self.RaidFrames and self.RaidFrames.Initialize then
        self.RaidFrames:Initialize()
    end
    
    if self.AutoUIScale and self.AutoUIScale.Initialize then
        self.AutoUIScale:Initialize()
    end
    
    if self.Chat and self.Chat.Initialize then
        self.Chat:Initialize()
    end
    
    if self.Minimap and self.Minimap.Initialize then
        self.Minimap:Initialize()
    end
    
    if self.ActionBars and self.ActionBars.Initialize then
        self.ActionBars:Initialize()
    end
    
    if self.ActionBarGlow and self.ActionBarGlow.Initialize then
        C_Timer.After(1.0, function()
            self.ActionBarGlow:Initialize()
        end)
    end
    
    if self.BuffDebuffFrames and self.BuffDebuffFrames.Initialize then
        self.BuffDebuffFrames:Initialize()
    end
    
    if self.QOL and self.QOL.Initialize then
        self.QOL:Initialize()
    end

    if self.CharacterPanel and self.CharacterPanel.Initialize then
        self.CharacterPanel:Initialize()
    end
    
    C_Timer.After(0.1, function()
        if self.CastBars and self.CastBars.HookTargetAndFocusCastBars then
            self.CastBars:HookTargetAndFocusCastBars()
        end
        if self.CastBars and self.CastBars.HookFocusCastBar then
            self.CastBars:HookFocusCastBar()
        end
        if self.CastBars and self.CastBars.HookBossCastBars then
            self.CastBars:HookBossCastBars()
        end
    end)
    
    if self.UnitFrames and self.db.profile.unitFrames and self.db.profile.unitFrames.enabled then
        C_Timer.After(0.5, function()
            if self.UnitFrames.Initialize then
                self.UnitFrames:Initialize()
            end
            
            if self.AbsorbBars and self.AbsorbBars.Initialize then
                self.AbsorbBars:Initialize()
            end
            
            local UF = self.UnitFrames
            if UF and UF.RepositionAllUnitFrames then
                local originalReposition = UF.RepositionAllUnitFrames
                UF.RepositionAllUnitFrames = function(self, ...)
                    originalReposition(self, ...)
                    C_Timer.After(0.1, function()
                        if NephUI.CustomIcons and NephUI.CustomIcons.ApplyCustomIconsLayout then
                            NephUI.CustomIcons:ApplyCustomIconsLayout()
                        end
                        if NephUI.CustomIcons and NephUI.CustomIcons.ApplyTrinketsLayout then
                            NephUI.CustomIcons:ApplyTrinketsLayout()
                        end
                    end)
                end
            end
        end)
    end
    
    if self.IconViewers and self.IconViewers.AutoLoadBuffIcons then
        C_Timer.After(0.5, function()
            self.IconViewers:AutoLoadBuffIcons()
        end)
    end

    -- Ensure all viewers are skinned on load
    if self.IconViewers and self.IconViewers.RefreshAll then
        C_Timer.After(1.0, function()
            self.IconViewers:RefreshAll()
        end)
    end
    
    if self.CustomIcons then
        C_Timer.After(1.5, function()
            if self.CustomIcons.CreateCustomIconsTrackerFrame then
                self.CustomIcons:CreateCustomIconsTrackerFrame()
            end
            if self.CustomIcons.CreateTrinketsTrackerFrame then
                self.CustomIcons:CreateTrinketsTrackerFrame()
            end
            if self.CustomIcons.CreateDefensivesTrackerFrame then
                self.CustomIcons:CreateDefensivesTrackerFrame()
            end
        end)

        C_Timer.After(2.5, function()
            if self.CustomIcons.ApplyCustomIconsLayout then
                self.CustomIcons:ApplyCustomIconsLayout()
            end
            if self.CustomIcons.ApplyTrinketsLayout then
                self.CustomIcons:ApplyTrinketsLayout()
            end
            if self.CustomIcons.ApplyDefensivesLayout then
                self.CustomIcons:ApplyDefensivesLayout()
            end
        end)
    end

    self:InitializeSelectionAlphaController()
end

function NephUI:OpenConfig()
    if self.OpenConfigGUI then
        self:OpenConfigGUI()
    else
        print("|cffff0000[NephUI] Warning: Custom GUI not loaded, using AceConfigDialog|r")
        LibStub("AceConfigDialog-3.0"):Open(ADDON_NAME)
    end
end

function NephUI:CheckDualSpec()
    local LibDualSpec = LibStub("LibDualSpec-1.0", true)
    if not LibDualSpec then
        print("|cffff0000[NephUI] LibDualSpec-1.0 is NOT loaded.|r")
        print("|cffffff00This is normal on Classic Era realms (except Season of Discovery/Anniversary).|r")
        return
    end
    
    print("|cff00ff00[NephUI] LibDualSpec-1.0 is loaded.|r")
    
    if not self.db then
        print("|cffff0000[NephUI] Database not initialized yet.|r")
        return
    end
    
    if self.db.IsDualSpecEnabled then
        local isEnabled = self.db:IsDualSpecEnabled()
        print(string.format("|cff00ff00[NephUI] Dual Spec support: %s|r", isEnabled and "ENABLED" or "DISABLED"))
        
        if isEnabled then
            local currentSpec = GetSpecialization() or GetActiveTalentGroup() or 0
            print(string.format("|cff00ff00[NephUI] Current spec: %d|r", currentSpec))
            
            local currentProfile = self.db:GetCurrentProfile()
            print(string.format("|cff00ff00[NephUI] Current profile: %s|r", currentProfile))
            
            -- Check spec profiles
            for i = 1, 2 do
                local specProfile = self.db:GetDualSpecProfile(i)
                print(string.format("|cff00ff00[NephUI] Spec %d profile: %s|r", i, specProfile))
            end
        end
    else
        print("|cffff0000[NephUI] LibDualSpec methods not found on database (database not enhanced).|r")
    end
end

function NephUI:CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    
    if not LDB or not LibDBIcon then
        return
    end
    
    if not self.db.profile.minimap then
        self.db.profile.minimap = {
            hide = false,
        }
    end
    
    local dataObj = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        icon = "Interface\\AddOns\\NephUI\\Media\\nephui.tga",
        label = "NephUI",
        OnClick = function(clickedframe, button)
            if button == "LeftButton" then
                self:OpenConfig()
            elseif button == "RightButton" then
                self:OpenConfig()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:SetText("NephUI")
            tooltip:AddLine("Left-click to open configuration", 1, 1, 1)
            tooltip:AddLine("Right-click to open configuration", 1, 1, 1)
        end,
    })
    
    LibDBIcon:Register(ADDON_NAME, dataObj, self.db.profile.minimap)
end

function NephUI:RefreshViewers()
    if self.IconViewers and self.IconViewers.RefreshAll then
        self.IconViewers:RefreshAll()
    end

    if self.ProcGlow and self.ProcGlow.RefreshAll then
        self.ProcGlow:RefreshAll()
    end
end

function NephUI:RefreshCustomIcons()
    if not (self.CustomIcons and self.db and self.db.profile and self.db.profile.customIcons) then
        return
    end
    if self.db.profile.customIcons.enabled == false then
        return
    end

    local module = self.CustomIcons
    if module.CreateCustomIconsTrackerFrame then
        module:CreateCustomIconsTrackerFrame()
    end
end

function NephUI:RefreshAll()
    self:RefreshViewers()
    
    if self.ResourceBars and self.ResourceBars.RefreshAll then
        self.ResourceBars:RefreshAll()
    end
    
    if self.CastBars and self.CastBars.RefreshAll then
        self.CastBars:RefreshAll()
    end
    
    if self.Chat and self.Chat.RefreshAll then
        self.Chat:RefreshAll()
    end
    
    if self.ActionBars and self.ActionBars.RefreshAll then
        self.ActionBars:RefreshAll()
    end
    
    if self.BuffDebuffFrames and self.BuffDebuffFrames.RefreshAll then
        self.BuffDebuffFrames:RefreshAll()
    end

    if self.QOL and self.QOL.Refresh then
        self.QOL:Refresh()
    end

    if self.CharacterPanel and self.CharacterPanel.Refresh then
        self.CharacterPanel:Refresh()
    end
    
    if self.UnitFrames and self.UnitFrames.RefreshFrames then
        self.UnitFrames:RefreshFrames()
    end

    if self.PartyFrames and self.PartyFrames.Refresh then
        self.PartyFrames:Refresh()
    end

    if self.RaidFrames and self.RaidFrames.Refresh then
        self.RaidFrames:Refresh()
    end
    
    if self.Minimap and self.Minimap.Refresh then
        self.Minimap:Refresh()
    end
    
    if self.CustomIcons and self.db.profile.customIcons and self.db.profile.customIcons.enabled ~= false then
        self:RefreshCustomIcons()
    end
end
