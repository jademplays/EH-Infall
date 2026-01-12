local ADDON_NAME, ns = ...
local NephUI = ns.Addon

-- Get UnitFrames module
local UF = NephUI.UnitFrames
if not UF then
    error("NephUI: UnitFrames module not initialized! Load UnitFrames.lua first.")
end

-- Get helper functions
local ResolveFrameName = UF.ResolveFrameName
local GetAnchorFrame = UF.GetAnchorFrame
local UnitToFrameName = UF.UnitToFrameName

-- Helper function to get friendly display name for units
local function GetUnitDisplayName(unit)
    if unit:match("^boss(%d+)$") then
        local bossNum = unit:match("^boss(%d+)$")
        return "Boss " .. bossNum
    end
    local displayNames = {
        player = "Player",
        target = "Target",
        targettarget = "Target Target",
        pet = "Pet",
        focus = "Focus",
    }
    return displayNames[unit] or unit
end

-- Create draggable anchor frame for a unit frame
function UF:CreateEditModeAnchor(unit)
    local frameName = ResolveFrameName(unit)
    local unitFrame = frameName and _G[frameName]
    if not unitFrame then return end
    
    -- Check if anchor already exists
    if unitFrame.editModeAnchor then
        return unitFrame.editModeAnchor
    end
    
    local anchor = CreateFrame("Frame", frameName .. "_EditModeAnchor", UIParent)
    anchor.unit = unit
    anchor.unitFrame = unitFrame
    
    -- Set strata to TOOLTIP so frame name appears above other UI elements
    anchor:SetFrameStrata("TOOLTIP")
    
    -- No backdrop - only show the frame name text
    -- Set anchor to be 8 pixels larger than unit frame (for clickable area)
    local frameWidth = unitFrame:GetWidth() or 200
    local frameHeight = unitFrame:GetHeight() or 40
    anchor:SetSize(math.max(1, frameWidth + 8), math.max(1, frameHeight + 8))
    
    -- Create text label for frame name
    local label = anchor:CreateFontString(nil, "OVERLAY")
    local fontPath = NephUI:GetGlobalFont()
    if fontPath then
        label:SetFont(fontPath, 12, "OUTLINE")
    else
        label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    end
    label:SetTextColor(0.2, 0.5, 1, 1) -- Blue color matching border
    label:SetText(GetUnitDisplayName(unit))
    label:SetPoint("TOP", anchor, "TOP", 0, -2)
    label:SetJustifyH("CENTER")
    anchor.label = label
    
    -- Make it draggable
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetClampedToScreen(true)
    
    -- Position it over the unit frame
    anchor:SetPoint("CENTER", unitFrame, "CENTER", 0, 0)
    
    -- Function to update unit frame position based on anchor position
    local function UpdateUnitFrameFromAnchor(anchor)
        if InCombatLockdown() then return end
        
        local db = NephUI.db.profile.unitFrames
        if not db then return end
        
        local dbUnit = anchor.unit
        if anchor.unit:match("^boss(%d+)$") then dbUnit = "boss" end
        
        local DB = db[dbUnit]
        if not DB or not DB.Frame then return end
        
        local unit = anchor.unit
        local anchorX, anchorY, offsetX, offsetY
        
        -- Check if using ECV anchor system
        local ecv = _G["EssentialCooldownViewer"]
        if DB.Frame.AnchorToCooldown and ecv and ecv:IsVisible() then
            -- Special calculation for ECV anchor system
            if unit == "player" then
                -- Player: RIGHT edge to ECV LEFT edge with -20 + offsetX
                -- To calculate offsetX: frame.RIGHT = ecv.LEFT - 20 + offsetX
                -- So: offsetX = frame.RIGHT - ecv.LEFT + 20
                local ecvLeft = ecv:GetLeft()
                local anchorRight = anchor:GetRight()
                if ecvLeft and anchorRight then
                    offsetX = anchorRight - ecvLeft + 20
                    offsetX = math.floor(offsetX + 0.5) -- Round for pixel-perfect alignment
                end
                
                -- Y offset is relative to ECV center
                local ecvX, ecvY = ecv:GetCenter()
                local anchorX_center, anchorY_center = anchor:GetCenter()
                if ecvY and anchorY_center then
                    offsetY = anchorY_center - ecvY
                    offsetY = math.floor(offsetY + 0.5) -- Round for pixel-perfect alignment
                end
            elseif unit == "target" then
                -- Target: LEFT edge to ECV RIGHT edge with 20 + offsetX
                -- To calculate offsetX: frame.LEFT = ecv.RIGHT + 20 + offsetX
                -- So: offsetX = frame.LEFT - ecv.RIGHT - 20
                local ecvRight = ecv:GetRight()
                local anchorLeft = anchor:GetLeft()
                if ecvRight and anchorLeft then
                    offsetX = anchorLeft - ecvRight - 20
                    offsetX = math.floor(offsetX + 0.5) -- Round for pixel-perfect alignment
                end
                
                -- Y offset is relative to ECV center
                local ecvX, ecvY = ecv:GetCenter()
                local anchorX_center, anchorY_center = anchor:GetCenter()
                if ecvY and anchorY_center then
                    offsetY = anchorY_center - ecvY
                    offsetY = math.floor(offsetY + 0.5) -- Round for pixel-perfect alignment
                end
            end
        else
            -- Standard anchor calculation with pixel-perfect alignment
            local anchorFrameName = DB.Frame.AnchorFrame or "UIParent"
            local anchorFrame = GetAnchorFrame(anchorFrameName)
            
            if anchorFrame then
                anchorX, anchorY = anchorFrame:GetCenter()
                local selfX, selfY = anchor:GetCenter()
                
                if anchorX and anchorY and selfX and selfY then
                    -- Account for scale differences between anchor and anchorFrame
                    local anchorScale = anchor:GetEffectiveScale()
                    local frameScale = anchorFrame:GetEffectiveScale()
                    
                    -- Convert to same coordinate space if scales differ
                    if anchorScale ~= frameScale then
                        selfX = (selfX * anchorScale) / frameScale
                        selfY = (selfY * anchorScale) / frameScale
                    end
                    
                    -- Calculate offset and round for pixel-perfect alignment
                    offsetX = selfX - anchorX
                    offsetY = selfY - anchorY
                    offsetX = math.floor(offsetX + 0.5)
                    offsetY = math.floor(offsetY + 0.5)
                end
            end
        end
        
        -- Update database if we calculated offsets
        if offsetX and offsetY then
            DB.Frame.OffsetX = offsetX
            DB.Frame.OffsetY = offsetY
            
            -- Reposition unit frame using ApplyFramePosition (which handles ECV correctly)
            if unitFrame and UF.ApplyFramePosition then
                UF:ApplyFramePosition(unitFrame, unit, DB)
            end
        end
    end
    
    -- Drag handlers
    anchor:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:StartMoving()
        self.isMoving = true
        
        -- Set up OnUpdate to move unit frame in real-time while dragging
        self:SetScript("OnUpdate", function(self, elapsed)
            if not self.isMoving then
                self:SetScript("OnUpdate", nil)
                return
            end
            UpdateUnitFrameFromAnchor(self)
        end)
    end)
    
    anchor:SetScript("OnDragStop", function(self)
        if InCombatLockdown() then return end
        self:StopMovingOrSizing()
        self.isMoving = false
        
        -- Remove OnUpdate script
        self:SetScript("OnUpdate", nil)
        
        -- Final update to ensure database is saved
        UpdateUnitFrameFromAnchor(self)
    end)
    
    -- Hide by default
    anchor:Hide()
    
    unitFrame.editModeAnchor = anchor
    return anchor
end

-- Set center alpha for viewer Selection frames
local function SetViewerSelectionCenterAlpha()
    local viewerNames = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
    }
    
    for _, viewerName in ipairs(viewerNames) do
        local viewer = _G[viewerName]
        if viewer and viewer.Selection and viewer.Selection.Center then
            local center = viewer.Selection.Center
            if center.SetAlpha then
                center:SetAlpha(0.3)
                -- Hook OnShow to maintain alpha when frame is shown
                if not center.__nephuiAlphaSet then
                    center.__nephuiAlphaSet = true
                    center:HookScript("OnShow", function(self)
                        self:SetAlpha(0.3)
                    end)
                end
            end
        end
    end
end

-- Hide default Blizzard edit mode Selection frames
local function HideBlizzardSelectionFrames()
    local db = NephUI.db.profile.unitFrames
    if not db or not db.enabled then return end
    
    -- Hide Selection frames if they exist and set up hooks
    local function HideSelectionFrame(frame, selectionFrame)
        if frame and selectionFrame then
            if not selectionFrame.__nephuiSelectionHidden then
                selectionFrame.__nephuiSelectionHidden = true
                -- Hook OnShow to keep it hidden
                selectionFrame:HookScript("OnShow", function(self)
                    local db = NephUI.db.profile.unitFrames
                    if db and db.enabled then
                        self:Hide()
                    end
                end)
            end
            selectionFrame:Hide()
        end
    end
    
    HideSelectionFrame(PlayerFrame, PlayerFrame and PlayerFrame.Selection)
    HideSelectionFrame(TargetFrame, TargetFrame and TargetFrame.Selection)
    HideSelectionFrame(FocusFrame, FocusFrame and FocusFrame.Selection)
    HideSelectionFrame(PetFrame, PetFrame and PetFrame.Selection)
end

-- Force unit frames to stay visible while anchors are shown
local function EnsureAnchorModeUnitVisibility(unitFrame, shouldForceShow)
    if not unitFrame then return end

    if shouldForceShow then
        if unitFrame.__nephuiUnitWatchActive then
            UnregisterUnitWatch(unitFrame)
            unitFrame.__nephuiUnitWatchActive = nil
            unitFrame.__nephuiUnitWatchNeedsRestore = true
        end
        unitFrame.__nephuiEditModeForced = true
        unitFrame:Show()

        if unitFrame.unit and not UnitExists(unitFrame.unit) then
            local db = NephUI.db and NephUI.db.profile and NephUI.db.profile.unitFrames
            local dbUnit = unitFrame.unit
            if dbUnit and dbUnit:match("^boss(%d+)$") then dbUnit = "boss" end
            local DB = db and db[dbUnit]

            if DB and unitFrame.healthBar then
                local maxHealth = 100
                local healthValue = 100
                local fg = DB.Frame and DB.Frame.FGColor or { 0.5, 0.5, 0.5, 1 }
                unitFrame.healthBar:SetMinMaxValues(0, maxHealth)
                unitFrame.healthBar:SetValue(healthValue)
                unitFrame.healthBar:SetStatusBarColor(fg[1] or 0.5, fg[2] or 0.5, fg[3] or 0.5, fg[4] or 1)
                unitFrame.healthBar:Show()
            end

            if DB and unitFrame.healthBarBG then
                local maxHealth = 100
                local missing = 0
                local bg = DB.Frame and DB.Frame.BGColor or { 0.1, 0.1, 0.1, 0.7 }
                unitFrame.healthBarBG:SetMinMaxValues(0, maxHealth)
                unitFrame.healthBarBG:SetValue(missing)
                unitFrame.healthBarBG:SetStatusBarColor(bg[1] or 0.1, bg[2] or 0.1, bg[3] or 0.1, bg[4] or 0.7)
                unitFrame.healthBarBG:Show()
            end
        end
    elseif unitFrame.__nephuiEditModeForced then
        unitFrame.__nephuiEditModeForced = nil

        if unitFrame.__nephuiUnitWatchNeedsRestore then
            RegisterUnitWatch(unitFrame, false)
            unitFrame.__nephuiUnitWatchActive = true
            unitFrame.__nephuiUnitWatchNeedsRestore = nil
        end

        if unitFrame.unit and not UnitExists(unitFrame.unit) then
            unitFrame:Hide()
        end
    end
end

-- Update edit mode anchors visibility and position
function UF:UpdateEditModeAnchors()
    local db = NephUI.db.profile.unitFrames
    if not db or not db.General then return end
    
    -- Set viewer selection center alpha
    SetViewerSelectionCenterAlpha()
    
    -- Hide default Blizzard Selection frames when custom frames are enabled
    if db.enabled then
        HideBlizzardSelectionFrames()
    end
    
    local toggleEnabled = db.General.ShowEditModeAnchors ~= false
    local inEditMode = EditModeManagerFrame and EditModeManagerFrame.editModeActive
    
    -- Show anchors if Edit Mode is active OR if the toggle is enabled
    local showAnchors = inEditMode or toggleEnabled
    
    for unit in pairs(UnitToFrameName) do
        local frameName = ResolveFrameName(unit)
        local unitFrame = frameName and _G[frameName]
        if unitFrame then
            local dbUnit = unit
            if unit:match("^boss(%d+)$") then
                dbUnit = "boss"
            end
            local unitDB = db[dbUnit]
            local enabled = unitDB and unitDB.Enabled ~= false
            if enabled then
                EnsureAnchorModeUnitVisibility(unitFrame, showAnchors)

                if not unitFrame.editModeAnchor then
                    self:CreateEditModeAnchor(unit)
                end
                
                local anchor = unitFrame.editModeAnchor
                if anchor then
                    if showAnchors then
                        -- Update anchor size to be 8 pixels larger than unit frame
                        local frameWidth = unitFrame:GetWidth() or 200
                        local frameHeight = unitFrame:GetHeight() or 40
                        anchor:SetSize(math.max(1, frameWidth + 8), math.max(1, frameHeight + 8))
                        -- Only update position if not currently being dragged
                        if not anchor.isMoving then
                            anchor:ClearAllPoints()
                            anchor:SetPoint("CENTER", unitFrame, "CENTER", 0, 0)
                        end
                        anchor:Show()
                        -- Show label
                        if anchor.label then
                            anchor.label:Show()
                        end
                    else
                        anchor:Hide()
                        -- Hide label
                        if anchor.label then
                            anchor.label:Hide()
                        end
                    end
                end
            end
        end
    end
    
    -- Update boss anchor
    self:UpdateBossAnchor()

    -- Update center line visibility
    if NephUI and NephUI.UpdateCenterLine then
        NephUI.UpdateCenterLine()
    end
end

-- Hook Edit Mode
function UF:HookEditMode()
    if self.EditModeHooked then return end
    self.EditModeHooked = true
    
    -- Wait for EditModeManagerFrame to exist
    local function TryHook()
        if not EditModeManagerFrame then
            return false
        end
        
        -- Hook EnterEditMode
        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
            HideBlizzardSelectionFrames()
            SetViewerSelectionCenterAlpha()
            self:UpdateEditModeAnchors()
        end)
        
        -- Hook ExitEditMode
        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            HideBlizzardSelectionFrames()
            SetViewerSelectionCenterAlpha()
            self:UpdateEditModeAnchors()
            
            -- Reposition all frames after edit mode exits to ensure correct alignment
            -- This is important when cooldown viewers or other anchor frames were moved
            if self.RepositionAllUnitFrames then
                C_Timer.After(0.1, function()
                    if not InCombatLockdown() then
                        self:RepositionAllUnitFrames()
                    end
                end)
            end
        end)
        
        
        -- Initial call to set viewer selection center alpha
        SetViewerSelectionCenterAlpha()
        
        -- Also set up a delayed call to catch frames that might be created later
        C_Timer.After(1.0, function()
            SetViewerSelectionCenterAlpha()
        end)
        
        return true
    end
    
    if not TryHook() then
        -- Wait for EditModeManagerFrame to load
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("ADDON_LOADED")
        waiter:SetScript("OnEvent", function(self, event, addonName)
            if TryHook() then
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
            end
        end)
    end
end

