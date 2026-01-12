-- MTT.lua - Midnight Trinket Tracker - On-Use Trinkets Only
-- Automatically detects and tracks on-use trinkets

local ADDON_NAME = "MTT"
local MTT = CreateFrame("Frame", "MidnightTrinketTracker")

-----------------------------------------------------------
-- Saved Variables
-----------------------------------------------------------
MTTDB = MTTDB or {
    trinketData = {}, -- [itemID] = {buffSpellId, useSpellId, icon, duration}
    spellData = {}, -- [spellID] = {buffSpellId, icon, duration} - for potions, racials, etc
    position = { point = "CENTER", x = 0, y = -200 },
    debugMode = false,
    config = {
        iconSize = 60,
        spacing = 1,
        growthDirection = "HORIZONTAL", -- HORIZONTAL or VERTICAL
    },
}

-----------------------------------------------------------
-- Constants
-----------------------------------------------------------
local MAX_ICONS = 4
local SHOW_COOLDOWN_TEXT = true

-----------------------------------------------------------
-- State Management
-----------------------------------------------------------
local State = {
    equippedTrinkets = {}, -- [slotID] = itemID
    activeBuffs = {}, -- [itemID or spellID] = {icon, duration, expirationTime, applications, source}
    inCombat = false,
    pendingLearning = {}, -- [itemID] = {useSpellId, timestamp}
    cleanupTicker = nil,
    learningMode = false, -- Manual learning mode toggle
}

-----------------------------------------------------------
-- Icon Pool
-----------------------------------------------------------
local iconPool = {}

local function CreateTrinketIcon(index)
    local frame = CreateFrame("Frame", ADDON_NAME.."Icon"..index, UIParent)
    frame:SetSize(MTTDB.config.iconSize, MTTDB.config.iconSize)
    frame:Hide()
    
    -- Outer border (black)
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetAllPoints()
    frame.border:SetColorTexture(0, 0, 0, 1)
    
    -- Inner border (gray highlight)
    frame.innerBorder = frame:CreateTexture(nil, "BACKGROUND")
    frame.innerBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.innerBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.innerBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
    
    -- Background (inside borders)
    frame.bg = frame:CreateTexture(nil, "BORDER")
    frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    frame.bg:SetColorTexture(0, 0, 0, 0.8)
    
    -- Icon texture (on top of background)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    
    -- Cooldown spiral (on top of icon)
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.cooldown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetDrawSwipe(true)
    frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    frame.cooldown:SetHideCountdownNumbers(not SHOW_COOLDOWN_TEXT)
    
    -- Stack count (overlay)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    frame.count:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    frame.count:SetTextColor(1, 1, 1, 1)
    
    -- Make first icon movable
    if index == 1 then
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetClampedToScreen(true)
        
        frame:SetScript("OnDragStart", function(self)
            if IsShiftKeyDown() then
                self:StartMoving()
            end
        end)
        
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            
            -- Always save as CENTER position for consistency
            local _, _, _, x, y = self:GetPoint()
            MTTDB.position = { point = "CENTER", x = x, y = y }
            
            if MTTDB.debugMode then
                print("|cff00ff00MTT:|r Position saved: CENTER", x, y)
            end
            
            -- Reposition all icons immediately
            PositionIcons()
        end)
    end
    
    frame.buffSource = nil
    frame.buffSourceId = nil
    return frame
end

local function InitializeIconPool()
    for i = 1, MAX_ICONS do
        iconPool[i] = CreateTrinketIcon(i)
    end
end

local function PositionIcons()
    -- Count visible icons
    local visibleIcons = {}
    for _, icon in ipairs(iconPool) do
        if icon:IsShown() then
            table.insert(visibleIcons, icon)
        end
    end
    
    local visibleCount = #visibleIcons
    if visibleCount == 0 then return end
    
    local iconSize = MTTDB.config.iconSize
    local spacing = MTTDB.config.spacing
    
    if MTTDB.config.growthDirection == "HORIZONTAL" then
        -- Horizontal growth from center
        local totalWidth = (visibleCount * iconSize) + ((visibleCount - 1) * spacing)
        local centerOffset = -totalWidth / 2 + iconSize / 2
        
        -- Position first icon at center point
        local firstIcon = visibleIcons[1]
        firstIcon:ClearAllPoints()
        firstIcon:SetPoint("CENTER", UIParent, "CENTER", 
                           MTTDB.position.x + centerOffset, 
                           MTTDB.position.y)
        
        -- Position remaining icons to the right
        for i = 2, visibleCount do
            local icon = visibleIcons[i]
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", visibleIcons[i-1], "RIGHT", spacing, 0)
        end
    else
        -- Vertical growth from bottom (first icon at bottom, grows upward)
        -- Position first icon at the saved position (bottom)
        local firstIcon = visibleIcons[1]
        firstIcon:ClearAllPoints()
        firstIcon:SetPoint("CENTER", UIParent, "CENTER", 
                           MTTDB.position.x, 
                           MTTDB.position.y)
        
        -- Position remaining icons upward from the first
        for i = 2, visibleCount do
            local icon = visibleIcons[i]
            icon:ClearAllPoints()
            icon:SetPoint("BOTTOM", visibleIcons[i-1], "TOP", 0, spacing)
        end
    end
end

-----------------------------------------------------------
-- Equipment Scanning
-----------------------------------------------------------

local function ScanEquippedTrinkets()
    wipe(State.equippedTrinkets)
    
    for slot = 13, 14 do
        local itemId = GetInventoryItemID("player", slot)
        if itemId then
            State.equippedTrinkets[slot] = itemId
            
            if MTTDB.debugMode then
                local itemName = C_Item.GetItemNameByID(itemId)
                local data = MTTDB.trinketData[itemId]
                local status = data and "|cff00ff00(learned)|r" or "|cffff8800(not learned)|r"
                print("|cff888888MTT:|r Slot", slot, "-", itemName or "Item "..itemId, status)
            end
        end
    end
end

-----------------------------------------------------------
-- Display Functions
-----------------------------------------------------------

local function UpdateDisplay()
    for _, icon in ipairs(iconPool) do
        icon:Hide()
    end
    
    local sortedBuffs = {}
    for key, buffData in pairs(State.activeBuffs) do
        -- For items, only show if equipped
        if buffData.source == "item" then
            if State.equippedTrinkets[13] == buffData.sourceId or State.equippedTrinkets[14] == buffData.sourceId then
                table.insert(sortedBuffs, buffData)
            end
        else
            -- For spells, always show
            table.insert(sortedBuffs, buffData)
        end
    end
    
    table.sort(sortedBuffs, function(a, b)
        return a.expirationTime < b.expirationTime
    end)
    
    for i = 1, math.min(#sortedBuffs, MAX_ICONS) do
        local buffData = sortedBuffs[i]
        local icon = iconPool[i]
        
        icon.icon:SetTexture(buffData.icon)
        
        -- Store source info for tooltip
        icon.buffSource = buffData.source
        icon.buffSourceId = buffData.sourceId
        
        if buffData.duration > 0 then
            icon.cooldown:SetCooldown(buffData.expirationTime - buffData.duration, buffData.duration)
        else
            icon.cooldown:Clear()
        end
        
        if buffData.applications and buffData.applications > 1 then
            icon.count:SetText(buffData.applications)
        else
            icon.count:SetText("")
        end
        
        icon:Show()
    end
    
    -- Reposition icons with grow-from-center after showing/hiding
    PositionIcons()
end

local function CleanupExpiredBuffs()
    local now = GetTime()
    local removed = false
    
    for itemId, buffData in pairs(State.activeBuffs) do
        if buffData.expirationTime > 0 and buffData.expirationTime < now then
            State.activeBuffs[itemId] = nil
            removed = true
            
            if MTTDB.debugMode then
                print("|cff888888MTT:|r Removed expired buff for item", itemId)
            end
        end
    end
    
    if removed then
        UpdateDisplay()
    end
end

-----------------------------------------------------------
-- Auto-Learning (Trinkets and Spells)
-----------------------------------------------------------

local function AttemptAutoLearnSpell(spellId)
    if InCombatLockdown() then
        if MTTDB.debugMode then
            print("|cffff8800MTT:|r Spell", spellId, "used in combat - cannot learn (scan buffs after combat)")
        end
        return
    end
    
    if MTTDB.debugMode then
        print("|cff00ff00MTT:|r Auto-learning spell", spellId)
    end
    
    C_Timer.After(0.3, function()
        if InCombatLockdown() then return end
        
        local bestMatch = nil
        local now = GetTime()
        
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end
            
            local buffAge = auraData.expirationTime and (auraData.duration - (auraData.expirationTime - now)) or 999
            
            if auraData.duration and auraData.duration >= 3 and buffAge < 2 then
                if not bestMatch or buffAge < bestMatch.age then
                    local icon = C_Spell.GetSpellTexture(auraData.spellId)
                    if icon then
                        bestMatch = {
                            spellId = auraData.spellId,
                            icon = icon,
                            duration = auraData.duration,
                            age = buffAge,
                            expirationTime = auraData.expirationTime,
                        }
                    end
                end
            end
        end
        
        if bestMatch then
            MTTDB.spellData[spellId] = {
                buffSpellId = bestMatch.spellId,
                icon = bestMatch.icon,
                duration = bestMatch.duration,
            }
            
            State.activeBuffs["spell_"..spellId] = {
                icon = bestMatch.icon,
                duration = bestMatch.duration,
                expirationTime = bestMatch.expirationTime,
                applications = 1,
                source = "spell",
                sourceId = spellId,
            }
            
            local spellInfo = C_Spell.GetSpellInfo(spellId)
            local spellName = spellInfo and spellInfo.name or "Spell "..spellId
            print("|cff00ff00MTT:|r ✓ Auto-learned", spellName)
            print("|cff888888MTT:|r Buff:", bestMatch.spellId, "Duration:", bestMatch.duration)
            
            UpdateDisplay()
        else
            print("|cffff0000MTT:|r Could not auto-learn spell", spellId)
        end
    end)
end

local function AttemptAutoLearn(itemId, useSpellId)
    if InCombatLockdown() then
        State.pendingLearning[itemId] = {
            useSpellId = useSpellId,
            timestamp = GetTime(),
        }
        
        if MTTDB.debugMode then
            print("|cffff8800MTT:|r Trinket", itemId, "used in combat - will learn after combat")
        end
        return
    end
    
    if MTTDB.debugMode then
        print("|cff00ff00MTT:|r Auto-learning trinket", itemId, "with use spell", useSpellId)
    end
    
    C_Timer.After(0.3, function()
        if InCombatLockdown() then
            State.pendingLearning[itemId] = {
                useSpellId = useSpellId,
                timestamp = GetTime(),
            }
            return
        end
        
        local bestMatch = nil
        local now = GetTime()
        
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end
            
            local buffAge = auraData.expirationTime and (auraData.duration - (auraData.expirationTime - now)) or 999
            
            if auraData.duration and auraData.duration >= 3 and buffAge < 2 then
                if not bestMatch or buffAge < bestMatch.age then
                    local icon = C_Spell.GetSpellTexture(auraData.spellId)
                    if icon then
                        bestMatch = {
                            spellId = auraData.spellId,
                            icon = icon,
                            duration = auraData.duration,
                            age = buffAge,
                            expirationTime = auraData.expirationTime,
                        }
                    end
                end
            end
        end
        
        if bestMatch then
            MTTDB.trinketData[itemId] = {
                buffSpellId = bestMatch.spellId,
                useSpellId = useSpellId,
                icon = bestMatch.icon,
                duration = bestMatch.duration,
            }
            
            State.activeBuffs[itemId] = {
                icon = bestMatch.icon,
                duration = bestMatch.duration,
                expirationTime = bestMatch.expirationTime,
                applications = 1,
                itemId = itemId,
            }
            
            local itemName = C_Item.GetItemNameByID(itemId)
            print("|cff00ff00MTT:|r ✓ Auto-learned", itemName or "Item "..itemId)
            print("|cff888888MTT:|r Buff:", bestMatch.spellId, "Use:", useSpellId, "Duration:", bestMatch.duration)
            
            if bestMatch.spellId ~= useSpellId then
                print("|cff888888MTT:|r (Use spell differs from buff spell)")
            end
            
            UpdateDisplay()
        else
            State.activeBuffs[itemId] = nil
            UpdateDisplay()
            print("|cffff0000MTT:|r Could not auto-learn trinket", itemId)
        end
    end)
end

local function ProcessPendingLearning()
    if InCombatLockdown() or not next(State.pendingLearning) then return end
    
    for itemId, data in pairs(State.pendingLearning) do
        AttemptAutoLearn(itemId, data.useSpellId)
    end
    
    wipe(State.pendingLearning)
end

-----------------------------------------------------------
-- Buff Tracking
-----------------------------------------------------------

local function ScanBuffsOutOfCombat()
    if InCombatLockdown() then return end
    
    -- Build lookup for trinkets
    local buffToItem = {}
    for itemId, data in pairs(MTTDB.trinketData) do
        if data.buffSpellId and (State.equippedTrinkets[13] == itemId or State.equippedTrinkets[14] == itemId) then
            buffToItem[data.buffSpellId] = {type = "item", id = itemId}
        end
    end
    
    -- Build lookup for spells (potions, racials, etc)
    for spellId, data in pairs(MTTDB.spellData) do
        if data.buffSpellId then
            buffToItem[data.buffSpellId] = {type = "spell", id = spellId}
        end
    end
    
    for i = 1, 40 do
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not auraData then break end
        
        local source = buffToItem[auraData.spellId]
        
        if source then
            local key = source.type == "item" and source.id or ("spell_"..source.id)
            local cached = source.type == "item" and MTTDB.trinketData[source.id] or MTTDB.spellData[source.id]
            
            State.activeBuffs[key] = {
                icon = cached.icon,
                duration = auraData.duration or cached.duration,
                expirationTime = auraData.expirationTime or 0,
                applications = auraData.applications or 1,
                source = source.type,
                sourceId = source.id,
            }
        end
    end
end

local function OnSpellCastSucceeded(unit, castGUID, spellId)
    if unit ~= "player" then return end
    
    -- First, check if this is already learned (trinket or spell)
    local spellData = MTTDB.spellData[spellId]
    if spellData then
        State.activeBuffs["spell_"..spellId] = {
            icon = spellData.icon,
            duration = spellData.duration,
            expirationTime = GetTime() + spellData.duration,
            applications = 1,
            source = "spell",
            sourceId = spellId,
        }
        UpdateDisplay()
        return
    end
    
    -- Check if any cached trinket matches
    for slot = 13, 14 do
        local itemId = State.equippedTrinkets[slot]
        if itemId then
            local cached = MTTDB.trinketData[itemId]
            
            if cached and (cached.useSpellId == spellId or cached.buffSpellId == spellId) then
                State.activeBuffs[itemId] = {
                    icon = cached.icon,
                    duration = cached.duration,
                    expirationTime = GetTime() + cached.duration,
                    applications = 1,
                    source = "item",
                    sourceId = itemId,
                }
                UpdateDisplay()
                return
            end
        end
    end
    
    -- LEARNING MODE: Only learn when explicitly enabled
    if not State.learningMode then
        return
    end
    
    -- Try to learn trinkets first
    C_Timer.After(0.1, function()
        -- Check BOTH slots and find which one has the cooldown
        local slot13Item = State.equippedTrinkets[13]
        local slot14Item = State.equippedTrinkets[14]
        
        local start13, duration13 = 0, 0
        local start14, duration14 = 0, 0
        
        if slot13Item then
            start13, duration13 = GetInventoryItemCooldown("player", 13)
        end
        if slot14Item then
            start14, duration14 = GetInventoryItemCooldown("player", 14)
        end
        
        -- Count how many slots have cooldowns
        local cooldownSlots = {}
        if start13 > 0 and duration13 > 1.5 and slot13Item and not MTTDB.trinketData[slot13Item] then
            table.insert(cooldownSlots, {slot = 13, itemId = slot13Item})
        end
        if start14 > 0 and duration14 > 1.5 and slot14Item and not MTTDB.trinketData[slot14Item] then
            table.insert(cooldownSlots, {slot = 14, itemId = slot14Item})
        end
        
        -- Only learn if exactly ONE slot has a cooldown (unambiguous)
        if #cooldownSlots == 1 then
            local slotData = cooldownSlots[1]
            local itemName = C_Item.GetItemNameByID(slotData.itemId)
            
            AttemptAutoLearn(slotData.itemId, spellId)
            print("|cff00ff00MTT:|r Learned trinket:", itemName or "Item "..slotData.itemId)
            
            local icon = C_Spell.GetSpellTexture(spellId) or select(5, C_Item.GetItemInfoInstant(slotData.itemId))
            State.activeBuffs[slotData.itemId] = {
                icon = icon,
                duration = 20,
                expirationTime = GetTime() + 20,
                applications = 1,
                source = "item",
                sourceId = slotData.itemId,
            }
            
            UpdateDisplay()
            return
        elseif #cooldownSlots > 1 then
            print("|cffff8800MTT:|r Both trinkets on cooldown - use them separately to learn!")
            return
        end
        
        -- Try to learn as a spell (potion, racial, etc)
        AttemptAutoLearnSpell(spellId)
    end)
end

-----------------------------------------------------------
-- Events
-----------------------------------------------------------

MTT:RegisterEvent("ADDON_LOADED")
MTT:RegisterEvent("PLAYER_LOGIN")
MTT:RegisterEvent("PLAYER_ENTERING_WORLD")
MTT:RegisterEvent("UNIT_AURA")
MTT:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
MTT:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
MTT:RegisterEvent("PLAYER_REGEN_DISABLED")
MTT:RegisterEvent("PLAYER_REGEN_ENABLED")

MTT:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        MTTDB.trinketData = MTTDB.trinketData or {}
        MTTDB.spellData = MTTDB.spellData or {}
        MTTDB.position = MTTDB.position or { point = "CENTER", x = 0, y = -200 }
        MTTDB.debugMode = MTTDB.debugMode or false
        MTTDB.config = MTTDB.config or {
            iconSize = 60,
            spacing = 1,
            growthDirection = "HORIZONTAL",
        }
        
        InitializeIconPool()
        -- Don't call PositionIcons here - UpdateDisplay will handle it
        
        -- Start cleanup ticker
        if State.cleanupTicker then
            State.cleanupTicker:Cancel()
        end
        State.cleanupTicker = C_Timer.NewTicker(0.5, CleanupExpiredBuffs)
        
        print("|cff00ff00MTT|r Midnight Trinket Tracker loaded!")
        print("  Use |cffff8800/mtt learn|r to track abilities")
        print("  Use |cffff8800/mtt config|r to customize")
        
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        ScanEquippedTrinkets()
        ScanBuffsOutOfCombat()
        UpdateDisplay()
        
    elseif event == "PLAYER_REGEN_DISABLED" then
        State.inCombat = true
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        State.inCombat = false
        ProcessPendingLearning()
        ScanBuffsOutOfCombat()
        UpdateDisplay()
        
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellCastSucceeded(arg1, arg2, arg3)
        
    elseif event == "UNIT_AURA" and arg1 == "player" then
        if not InCombatLockdown() then
            ScanBuffsOutOfCombat()
        end
        UpdateDisplay()
        
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ScanEquippedTrinkets()
        if not InCombatLockdown() then
            ScanBuffsOutOfCombat()
        end
        UpdateDisplay()
    end
end)

-----------------------------------------------------------
-- Config UI
-----------------------------------------------------------

local configFrame

local function CreateConfigUI()
    if configFrame then
        configFrame:Show()
        return
    end
    
    -- Main frame using Blizzard style
    configFrame = CreateFrame("Frame", "MTTConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    configFrame:SetSize(320, 380)
    configFrame:SetPoint("CENTER")
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", configFrame.StartMoving)
    configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
    configFrame:SetClampedToScreen(true)
    configFrame:Hide()
    
    -- Title
    configFrame.title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    configFrame.title:SetPoint("LEFT", configFrame.TitleBg, "LEFT", 5, 0)
    configFrame.title:SetText("MTT Config")
    
    local yOffset = -35
    
    -- Icon Size
    local sizeLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, yOffset)
    sizeLabel:SetText("Icon Size")
    
    local sizeSlider = CreateFrame("Slider", "MTTConfigSizeSlider", configFrame, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 5, -10)
    sizeSlider:SetWidth(210)
    sizeSlider:SetMinMaxValues(30, 100)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetValue(MTTDB.config.iconSize)
    sizeSlider.Low:SetText("30")
    sizeSlider.High:SetText("100")
    sizeSlider.Text:SetText("")
    
    -- Value box below slider (like X/Y position)
    local sizeValue = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
    sizeValue:SetSize(60, 25)
    sizeValue:SetPoint("TOP", sizeSlider, "BOTTOM", 0, -5)
    sizeValue:SetAutoFocus(false)
    sizeValue:SetText(tostring(MTTDB.config.iconSize))
    sizeValue:SetMaxLetters(3)
    sizeValue:SetNumeric(true)
    sizeValue:SetJustifyH("CENTER")
    sizeValue:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or 60
        value = math.max(30, math.min(100, value))
        MTTDB.config.iconSize = value
        sizeSlider:SetValue(value)
        self:SetText(value)
        self:ClearFocus()
        
        for _, icon in ipairs(iconPool) do
            icon:SetSize(value, value)
        end
        PositionIcons()
    end)
    sizeValue:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(MTTDB.config.iconSize))
        self:ClearFocus()
    end)
    sizeValue:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    
    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        sizeValue:SetText(value)
        MTTDB.config.iconSize = value
        
        for _, icon in ipairs(iconPool) do
            icon:SetSize(value, value)
        end
        PositionIcons()
    end)
    
    yOffset = yOffset - 90
    
    -- Spacing
    local spacingLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spacingLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, yOffset)
    spacingLabel:SetText("Spacing")
    
    local spacingSlider = CreateFrame("Slider", "MTTConfigSpacingSlider", configFrame, "OptionsSliderTemplate")
    spacingSlider:SetPoint("TOPLEFT", spacingLabel, "BOTTOMLEFT", 5, -10)
    spacingSlider:SetWidth(210)
    spacingSlider:SetMinMaxValues(0, 20)
    spacingSlider:SetValueStep(1)
    spacingSlider:SetObeyStepOnDrag(true)
    spacingSlider:SetValue(MTTDB.config.spacing)
    spacingSlider.Low:SetText("0")
    spacingSlider.High:SetText("20")
    spacingSlider.Text:SetText("")
    
    -- Value box below slider (like X/Y position)
    local spacingValue = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
    spacingValue:SetSize(60, 25)
    spacingValue:SetPoint("TOP", spacingSlider, "BOTTOM", 0, -5)
    spacingValue:SetAutoFocus(false)
    spacingValue:SetText(tostring(MTTDB.config.spacing))
    spacingValue:SetMaxLetters(2)
    spacingValue:SetNumeric(true)
    spacingValue:SetJustifyH("CENTER")
    spacingValue:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or 1
        value = math.max(0, math.min(20, value))
        MTTDB.config.spacing = value
        spacingSlider:SetValue(value)
        self:SetText(value)
        self:ClearFocus()
        PositionIcons()
    end)
    spacingValue:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(MTTDB.config.spacing))
        self:ClearFocus()
    end)
    spacingValue:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    
    spacingSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        spacingValue:SetText(value)
        MTTDB.config.spacing = value
        PositionIcons()
    end)
    
    yOffset = yOffset - 90
    
    -- Growth Direction
    local directionLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    directionLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, yOffset)
    directionLabel:SetText("Growth Direction")
    
    local horizontalBtn = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    horizontalBtn:SetSize(130, 25)
    horizontalBtn:SetPoint("TOPLEFT", directionLabel, "BOTTOMLEFT", 0, -10)
    horizontalBtn:SetText("Horizontal")
    
    local verticalBtn = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    verticalBtn:SetSize(130, 25)
    verticalBtn:SetPoint("LEFT", horizontalBtn, "RIGHT", 10, 0)
    verticalBtn:SetText("Vertical")
    
    local function UpdateDirectionButtons()
        if MTTDB.config.growthDirection == "HORIZONTAL" then
            horizontalBtn:Disable()
            horizontalBtn:SetAlpha(0.5)
            verticalBtn:Enable()
            verticalBtn:SetAlpha(1)
        else
            horizontalBtn:Enable()
            horizontalBtn:SetAlpha(1)
            verticalBtn:Disable()
            verticalBtn:SetAlpha(0.5)
        end
    end
    
    horizontalBtn:SetScript("OnClick", function()
        MTTDB.config.growthDirection = "HORIZONTAL"
        UpdateDirectionButtons()
        PositionIcons()
    end)
    
    verticalBtn:SetScript("OnClick", function()
        MTTDB.config.growthDirection = "VERTICAL"
        UpdateDirectionButtons()
        PositionIcons()
    end)
    
    UpdateDirectionButtons()
    
    yOffset = yOffset - 70
    
    -- Position (X, Y)
    local positionLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    positionLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, yOffset)
    positionLabel:SetText("Position (X, Y)")
    
    -- X coordinate
    local xLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xLabel:SetPoint("TOPLEFT", positionLabel, "BOTTOMLEFT", 0, -10)
    xLabel:SetText("X:")
    
    local xBox = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
    xBox:SetSize(80, 25)
    xBox:SetPoint("LEFT", xLabel, "RIGHT", 5, 0)
    xBox:SetAutoFocus(false)
    xBox:SetText(tostring(math.floor(MTTDB.position.x)))
    xBox:SetMaxLetters(6)
    xBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or 0
        MTTDB.position.x = value
        self:ClearFocus()
        PositionIcons()
    end)
    xBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(math.floor(MTTDB.position.x)))
        self:ClearFocus()
    end)
    
    -- Y coordinate
    local yLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    yLabel:SetPoint("LEFT", xBox, "RIGHT", 15, 0)
    yLabel:SetText("Y:")
    
    local yBox = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
    yBox:SetSize(80, 25)
    yBox:SetPoint("LEFT", yLabel, "RIGHT", 5, 0)
    yBox:SetAutoFocus(false)
    yBox:SetText(tostring(math.floor(MTTDB.position.y)))
    yBox:SetMaxLetters(6)
    yBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or 0
        MTTDB.position.y = value
        self:ClearFocus()
        PositionIcons()
    end)
    yBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(math.floor(MTTDB.position.y)))
        self:ClearFocus()
    end)
    
    configFrame:Show()
end

-----------------------------------------------------------
-- Slash Commands
-----------------------------------------------------------

SLASH_MTT1 = "/mtt"
SlashCmdList["MTT"] = function(msg)
    msg = msg:lower():trim()
    
    if msg == "config" or msg == "c" then
        CreateConfigUI()
        
    elseif msg == "debug" or msg == "d" then
        MTTDB.debugMode = not MTTDB.debugMode
        print("|cff00ff00MTT:|r Debug mode", MTTDB.debugMode and "ENABLED" or "DISABLED")
        
        if MTTDB.debugMode then
            ScanEquippedTrinkets()
        end
        
    elseif msg == "learn" then
        State.learningMode = not State.learningMode
        
        if State.learningMode then
            print("|cff00ff00MTT:|r Learning mode |cff00ff00ENABLED|r")
            print("|cffff8800→|r Use any ability to learn it")
            print("|cffff8800→|r Type /mtt learn again to stop")
        else
            print("|cff00ff00MTT:|r Learning mode |cffff0000DISABLED|r")
        end
        
    elseif msg == "list" or msg == "l" then
        print("|cff00ff00MTT - Learned Abilities:|r")
        
        local trinketCount = 0
        print("  |cffff8800Trinkets:|r")
        for itemId, data in pairs(MTTDB.trinketData) do
            local itemName = C_Item.GetItemNameByID(itemId)
            local spellInfo = C_Spell.GetSpellInfo(data.buffSpellId)
            local spellName = spellInfo and spellInfo.name or "?"
            
            print(string.format("    %s", itemName or "Item "..itemId))
            print(string.format("      → %s (%d)", spellName, data.buffSpellId))
            trinketCount = trinketCount + 1
        end
        if trinketCount == 0 then
            print("    |cff888888None yet|r")
        end
        
        local spellCount = 0
        print("  |cffff8800Spells (Potions/Racials/etc):|r")
        for spellId, data in pairs(MTTDB.spellData) do
            local spellInfo = C_Spell.GetSpellInfo(spellId)
            local spellName = spellInfo and spellInfo.name or "Spell "..spellId
            local buffInfo = C_Spell.GetSpellInfo(data.buffSpellId)
            local buffName = buffInfo and buffInfo.name or "?"
            
            print(string.format("    %s (%d)", spellName, spellId))
            print(string.format("      → %s (%d)", buffName, data.buffSpellId))
            spellCount = spellCount + 1
        end
        if spellCount == 0 then
            print("    |cff888888None yet|r")
        end
        
    elseif msg == "move" then
        print("|cff00ff00MTT:|r Hold SHIFT and drag any icon to move")
        
        local hasVisible = false
        for _, icon in ipairs(iconPool) do
            if icon:IsShown() then
                hasVisible = true
                break
            end
        end
        
        if not hasVisible then
            for i = 1, 2 do
                local icon = iconPool[i]
                icon.icon:SetTexture(136235)
                icon.cooldown:Clear()
                icon.count:SetText("")
                icon:Show()
            end
            print("|cff888888MTT:|r Showing test icons (disappear when you use a trinket)")
        end
        
    elseif msg == "clear" then
        -- Show confirmation dialog
        StaticPopupDialogs["MTT_CLEAR_CONFIRM"] = {
            text = "Remove all learned trinkets, racials, and potions?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                wipe(MTTDB.trinketData)
                wipe(MTTDB.spellData)
                print("|cff00ff00MTT:|r Cleared all learned trinkets, racials, and potions")
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("MTT_CLEAR_CONFIRM")
        
    elseif msg == "reset" then
        MTTDB = {
            trinketData = {},
            position = { point = "CENTER", x = 0, y = -200 },
            debugMode = false,
        }
        ReloadUI()
        
    else
        print("|cff00ff00MTT - Midnight Trinket Tracker|r")
        print("")
        print("  |cffff8800/mtt learn|r - Toggle learning mode")
        print("    Use ANY ability (trinkets, potions, racials) while enabled")
        print("    Toggle off when done learning")
        print("")
        print("  |cffff8800/mtt config|r - Open config menu")
        print("  |cffff8800/mtt move|r - Move the icons (SHIFT + drag)")
        print("  |cffff8800/mtt list|r - Show all learned abilities")
        print("  |cffff8800/mtt debug|r - Toggle debug mode")
        print("  |cffff8800/mtt clear|r - Clear all learned data")
    end
end