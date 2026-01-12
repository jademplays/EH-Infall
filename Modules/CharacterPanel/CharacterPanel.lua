local ADDON_NAME, ns = ...
local NephUI = ns.Addon

NephUI.CharacterPanel = NephUI.CharacterPanel or {}
local CharacterPanel = NephUI.CharacterPanel

local isMop = select(4, GetBuildInfo()) >= 50000 and select(4, GetBuildInfo()) < 60000

local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
local GetItemQualityColor = (C_Item and C_Item.GetItemQualityColor) and C_Item.GetItemQualityColor or GetItemQualityColor
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) and C_Item.GetItemInfoInstant or GetItemInfo
local GetInventoryItemDurability = (C_Item and C_Item.GetInventoryItemDurability) and C_Item.GetInventoryItemDurability or GetInventoryItemDurability
local GetInventoryItemQuality = (C_Item and C_Item.GetInventoryItemQuality) and C_Item.GetInventoryItemQuality or GetInventoryItemQuality

local NUM_SOCKET_TEXTURES = 4

local expansionRequiredSockets = {
    [10] = {
        [INVSLOT_NECK] = 2,
        [INVSLOT_FINGER1] = 2,
        [INVSLOT_FINGER2] = 2,
    },
    [9] = {
        [INVSLOT_NECK] = 3,
    },
}

local expansionEnchantableSlots = {
    [10] = {
        [INVSLOT_HEAD] = true,
        [INVSLOT_BACK] = true,
        [INVSLOT_CHEST] = true,
        [INVSLOT_WRIST] = true,
        [INVSLOT_WRIST] = true,
        [INVSLOT_LEGS] = true,
        [INVSLOT_FEET] = true,
        [INVSLOT_MAINHAND] = true,
        [INVSLOT_FINGER1] = true,
        [INVSLOT_FINGER2] = true,
        [INVSLOT_SHOULDER] = true,
    },
    [9] = {
        [INVSLOT_HEAD] = true,
        [INVSLOT_BACK] = true,
        [INVSLOT_CHEST] = true,
        [INVSLOT_WRIST] = true,
        [INVSLOT_WAIST] = true,
        [INVSLOT_LEGS] = true,
        [INVSLOT_FEET] = true,
        [INVSLOT_MAINHAND] = true,
        [INVSLOT_FINGER1] = true,
        [INVSLOT_FINGER2] = true,
        [INVSLOT_SHOULDER] = true,
    },
}

-- Fallback for newer expansions or when GetExpansionForLevel returns an unknown value.
local defaultEnchantableSlots = {
    [INVSLOT_HEAD] = true,
    [INVSLOT_BACK] = true,
    [INVSLOT_CHEST] = true,
    [INVSLOT_WRIST] = true,
    [INVSLOT_WAIST] = true,
    [INVSLOT_LEGS] = true,
    [INVSLOT_FEET] = true,
    [INVSLOT_MAINHAND] = true,
    [INVSLOT_OFFHAND] = true,
    [INVSLOT_FINGER1] = true,
    [INVSLOT_FINGER2] = true,
    [INVSLOT_SHOULDER] = true,
}

local buttonLayout = {
    [INVSLOT_HEAD] = "left",
    [INVSLOT_NECK] = "left",
    [INVSLOT_SHOULDER] = "left",
    [INVSLOT_BACK] = "left",
    [INVSLOT_CHEST] = "left",
    [INVSLOT_WRIST] = "left",

    [INVSLOT_HAND] = "right",
    [INVSLOT_WAIST] = "right",
    [INVSLOT_LEGS] = "right",
    [INVSLOT_FEET] = "right",
    [INVSLOT_FINGER1] = "right",
    [INVSLOT_FINGER2] = "right",
    [INVSLOT_TRINKET1] = "right",
    [INVSLOT_TRINKET2] = "right",

    [INVSLOT_MAINHAND] = "center",
    [INVSLOT_OFFHAND] = "center",
}

local scanningTooltip
local enchantReplacementTable
local GetItemEnchantAsText, GetSocketTextures, ProcessEnchantText, CanEnchantSlot

if isMop then
    buttonLayout[INVSLOT_RANGED] = "center"

    scanningTooltip = CreateFrame("GameTooltip", "NephUIBCPScanningTooltip", nil, "GameTooltipTemplate")
    scanningTooltip:SetOwner(UIParent, "ANCHOR_NONE")

    enchantReplacementTable = {
        ["Stamina"] = "Stam",
        ["Intellect"] = "Int",
        ["Agility"] = "Agi",
        ["Strength"] = "Str",

        ["Mastery"] = "Mast",
        ["Versatility"] = "Vers",
        ["Critical Strike"] = "Crit",
        ["Haste"] = "Haste",
        ["Avoidance"] = "Avoid",

        ["Rating"] = "",
        ["rating"] = "",

        ["Minor"] = "Min",
        ["Movement"] = "Move",

        [" and "] = " ",
    }

    local function hasEnchant(itemLink)
        if not itemLink then
            return false
        end

        local itemString = itemLink:match("item[%-?%d:]+")
        if not itemString then
            return false
        end

        local _, _, enchantId = strsplit(":", itemString)
        return enchantId and enchantId ~= ""
    end

    function GetItemEnchantAsText(unit, slot)
        scanningTooltip:ClearLines()
        scanningTooltip:SetInventoryItem(unit, slot)
        local itemLink = GetInventoryItemLink(unit, slot)

        if not hasEnchant(itemLink) then
            return nil, nil
        end

        -- Original enchant name extraction
        for i = scanningTooltip:NumLines(), 3, -1 do
            local fontString = _G["NephUIBCPScanningTooltipTextLeft" .. i]
            if fontString and fontString:GetObjectType() == "FontString" then
                local text = fontString:GetText()
                if text then
                    local startsWithPlus = string.find(text, "^%+")
                    local r, g, b, a = fontString:GetTextColor()
                    if r == 1 and (string.format("%.3f", g) == "0.125" and string.format("%.3f", b) == "0.125" and a == 1) then
                        if startsWithPlus then
                            return nil, ProcessEnchantText(text)
                        end
                    elseif r == 0 and g == 1 and b == 0 and a == 1 then
                        if not string.find(text, "<") and not string.find(text, "Equip: ") and not string.find(text, "Socket Bonus:") and not string.find(text, "Use: ") then
                            if startsWithPlus then
                                return nil, ProcessEnchantText(text)
                            elseif (slot == INVSLOT_MAINHAND or slot == INVSLOT_OFFHAND or slot == INVSLOT_BACK) then
                                return nil, ProcessEnchantText(text)
                            end
                        end
                    end
                end
            end
        end
    end

    function GetSocketTextures(unit, slot)
        scanningTooltip:ClearLines()
        scanningTooltip:SetInventoryItem(unit, slot)

        local textures = {}

        for i = 1, 10 do
            local texture = _G["NephUIBCPScanningTooltipTexture" .. i]
            if texture and texture:IsShown() then
                table.insert(textures, texture:GetTexture())
            end
        end

        return textures
    end

    local slotsThatHaveEnchants = {
        [INVSLOT_SHOULDER] = true,
        [INVSLOT_BACK] = true,
        [INVSLOT_CHEST] = true,
        [INVSLOT_WRIST] = true,
        [INVSLOT_LEGS] = true,
        [INVSLOT_HAND] = true,
        [INVSLOT_FEET] = true,
        [INVSLOT_MAINHAND] = true,
        [INVSLOT_OFFHAND] = true,
    }

    function CanEnchantSlot(unit, slot)
        local class = select(2, UnitClass(unit))
        if class == "HUNTER" and slot == INVSLOT_RANGED then
            return true
        end

        return slotsThatHaveEnchants[slot]
    end
else
    enchantReplacementTable = {
        ["Stamina"] = "Stam",
        ["Intellect"] = "Int",
        ["Agility"] = "Agi",
        ["Strength"] = "Str",

        ["Mastery"] = "Mast",
        ["Versatility"] = "Vers",
        ["Critical Strike"] = "Crit",
        ["Haste"] = "Haste",
        ["Avoidance"] = "Avoid",

        -- Chest
        ["Mark of Nalorakk"] = "Str+Stam",
        ["Mark of the Rootwarden"] = "Agi+Speed",
        ["Mark of the Worldsoul"] = "Primary",

        -- Boots
        ["Mark of the Magister"] = "Int+Mana",
        ["Lynx's Dexterity"] = "Avoid+Stam",
        ["Shaladrassil's Roots"] = "Leech+Stam",
        ["Farstrider's Hunt"] = "Speed+Stam",

        -- Helm
        ["Hex of Leeching"] = "Leech",
        ["Empowered Hex of Leeching"] = "Leech",
        ["Blessing of Speed"] = "Speed",
        ["Empowered Blessing of Speed"] = "Speed",
        ["Rune of Avoidance"] = "Avoid",
        ["Empowered Rune of Avoidance"] = "Avoid",

        -- Ring
        ["Amani Mastery"] = "Mastery",
        ["Eyes of the Eagle"] = "Crit Effect",
        ["Zul'jin's Mastery"] = "Mastery",
        ["Nature's Wrath"] = "Crit",
        ["Nature's Fury"] = "Crit",
        ["Thalassian Haste"] = "Haste",
        ["Thalassian Versatility"] = "Vers",
        ["Thallassian Verysatility"] = "Vers", -- Handle potential typo
        ["Silvermoon's Alacrity"] = "Haste",
        ["Silvermoon's Tenacity"] = "Vers",

        -- Legs
        ["Forest Hunter's Armor Kit"] = "Pri+Stam",
        ["Thalassian Scout Armor Kit"] = "Primary",
        ["Blood Knight's Armor Kit"] = "Pri+Armor",
        ["Arcanoweave Spellthread"] = "Int+Mana",
        ["Bright Linene Spellthread"] = "Int",
        ["Sunfire Silk Spellthread"] = "Int+Stam",

        -- Shoulders
        ["Flight of the Eagle"] = "Speed",
        ["Akil'zon's Celerity"] = "Speed",
        ["Nature's Grace"] = "Avoidance",
        ["Amirdrassil's Grace"] = "Avoidance",
        ["Thalassian Recovery"] = "Leech",
        ["Silvermoon's Mending"] = "Leech",

        -- Weapon
        ["Strength of Halazzi"] = "Halazzi",
        ["Jan'alai's Precision"] = "Precision",
        ["Berseker's Rage"] = "Rage",
        ["Worldsoul Cradle"] = "Cradle",
        ["Worldsoul Aegis"] = "Aegis",
        ["Worldsoul Tenacity"] = "Tenacity",
        ["Flames of the Sin'dorei"] = "Sin'dorei",
        ["Acuity of the Ren'dorei"] = "Ren'dorei",
        ["Arcane Mastery"] = "Arcane",

        ["Minor Speed Increase"] = "Speed",
        ["Homebound Speed"] = "Speed & HS Red.",
        ["Plainsrunner's Breeze"] = "Speed",
        ["Graceful Avoid"] = "Avoid",
        ["Regenerative Leech"] = "Leech",
        ["Watcher's Loam"] = "Stam",
        ["Rider's Reassurance"] = "Mount Speed",
        ["Accelerated Agility"] = "Speed & Agi",
        ["Reserve of Int"] = "Mana & Int",
        ["Sustained Str"] = "Stam & Str",
        ["Waking Stats"] = "Primary Stat",

        ["Cavalry's March"] = "Mount Speed",
        ["Scout's March"] = "Speed",

        ["Defender's March"] = "Stam",
        ["Stormrider's Agi"] = "Agi & Speed",
        ["Council's Intellect"] = "Int & Mana",
        ["Crystalline Radiance"] = "Primary Stat",
        ["Oathsworn's Strength"] = "Str & Stam",

        ["Chant of Armored Avoid"] = "Avoid",
        ["Chant of Armored Leech"] = "Leech",
        ["Chant of Armored Speed"] = "Speed",
        ["Chant of Winged Grace"] = "Avoid & FallDmg",
        ["Chant of Leeching Fangs"] = "Leech & Recup",
        ["Chant of Burrowing Rapidity"] = "Speed & HScd",

        ["Cursed Haste"] = "Haste & |cffcc0000-Vers|r",
        ["Cursed Crit"] = "Crit & |cffcc0000-Haste|r",
        ["Cursed Mastery"] = "Mast & |cffcc0000-Crit|r",
        ["Cursed Versatility"] = "Vers & |cffcc0000-Mast|r",

        ["Shadowed Belt Clasp"] = "Stamina",

        ["Incandescent Essence"] = "Essence",
        ["+"] = "",
    }

    local enchantPattern = ENCHANTED_TOOLTIP_LINE:gsub("%%s", "(.*)")
    local enchantAtlasPattern = "(.*)%s*|A:(.*):20:20|a"
    local enchatColoredPatten = "|cn(.*):(.*)|r"

    function GetItemEnchantAsText(unit, slot)
        local data = C_TooltipInfo.GetInventoryItem(unit, slot)
        if not data or not data.lines then
            return nil, nil
        end

        -- Original enchant name extraction
        for _, line in ipairs(data.lines) do
            local text = line.leftText
            local enchantText = text and string.match(text, enchantPattern)
            if enchantText then
                local maybeEnchantText, atlas
                local maybeEnchantColor, maybeEnchantTextColored = enchantText:match(enchatColoredPatten)
                if maybeEnchantColor then
                    enchantText = maybeEnchantTextColored
                else
                    maybeEnchantText, atlas = enchantText:match(enchantAtlasPattern)
                    enchantText = maybeEnchantText or enchantText
                end

                return atlas, ProcessEnchantText(enchantText)
            end
        end

        return nil, nil
    end

    function GetSocketTextures(unit, slot)
        local data = C_TooltipInfo.GetInventoryItem(unit, slot)
        if not data or not data.lines then
            return {}
        end

        local textures = {}
        for _, line in ipairs(data.lines) do
            if line.type == 3 then
                if line.gemIcon then
                    table.insert(textures, line.gemIcon)
                else
                    table.insert(textures, string.format("Interface\\ItemSocketingFrame\\UI-EmptySocket-%s", line.socketType))
                end
            end
        end

        return textures
    end

    function CanEnchantSlot(unit, slot)
        local expansion = GetExpansionForLevel(UnitLevel(unit))
        local slotsThatHaveEnchants = expansion and expansionEnchantableSlots[expansion] or defaultEnchantableSlots

        if slotsThatHaveEnchants[slot] then
            return true
        end

        if slot == INVSLOT_OFFHAND then
            local offHandItemLink = GetInventoryItemLink(unit, slot)
            if offHandItemLink then
                local itemEquipLoc = select(4, GetItemInfoInstant(offHandItemLink))
                return itemEquipLoc ~= "INVTYPE_HOLDABLE" and itemEquipLoc ~= "INVTYPE_SHIELD"
            end
            return false
        end

        return false
    end
end

local function GetDB()
    if not (NephUI.db and NephUI.db.profile) then
        return nil
    end
    if not NephUI.db.profile.qol then
        NephUI.db.profile.qol = {}
    end
    return NephUI.db.profile.qol
end

local function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do
        table.insert(a, n)
    end
    table.sort(a, f)
    local i = 0
    local iter = function()
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end
    return iter
end

function ProcessEnchantText(enchantText)
    -- First, check for full enchant name replacements (contains matching)
    for seek, replacement in pairsByKeys(enchantReplacementTable) do
        if enchantText:find(seek, 1, true) then
            -- If the enchant text contains the key phrase, replace the entire text
            return replacement
        end
    end

    -- If no full replacement found, apply partial replacements
    for seek, replacement in pairsByKeys(enchantReplacementTable) do
        enchantText = enchantText:gsub(seek, replacement)
    end
    return enchantText
end

local function ColorGradient(perc, ...)
    if perc >= 1 then
        local r, g, b = select(select("#", ...) - 2, ...)
        return r, g, b
    elseif perc <= 0 then
        local r, g, b = ...
        return r, g, b
    end

    local num = select("#", ...) / 3

    local segment, relperc = math.modf(perc * (num - 1))
    local r1, g1, b1, r2, g2, b2 = select((segment * 3) + 1, ...)

    return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
end

local function ColorGradientHP(perc)
    return ColorGradient(perc, 1, 0, 0, 1, 1, 0, 0, 1, 0)
end

local function AnchorTextureLeftOfParent(parent, textures)
    textures[1]:SetPoint("RIGHT", parent, "LEFT", -3, 1)
    for i = 2, NUM_SOCKET_TEXTURES do
        textures[i]:SetPoint("RIGHT", textures[i - 1], "LEFT", -2, 0)
    end
end

local function AnchorTextureRightOfParent(parent, textures)
    textures[1]:SetPoint("LEFT", parent, "RIGHT", 3, 1)
    for i = 2, NUM_SOCKET_TEXTURES do
        textures[i]:SetPoint("LEFT", textures[i - 1], "RIGHT", 2, 0)
    end
end

local function CreateAdditionalDisplayForButton(button)
    local parent = button:GetParent()
    local additionalFrame = CreateFrame("frame", nil, parent)
    additionalFrame:SetWidth(100)

    additionalFrame.ilvlDisplay = additionalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")

    additionalFrame.enchantDisplay = additionalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    additionalFrame.enchantDisplay:SetTextColor(0, 1, 0, 1)

    additionalFrame.durabilityDisplay = CreateFrame("StatusBar", nil, additionalFrame)
    additionalFrame.durabilityDisplay:SetMinMaxValues(0, 1)
    additionalFrame.durabilityDisplay:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    additionalFrame.durabilityDisplay:GetStatusBarTexture():SetHorizTile(false)
    additionalFrame.durabilityDisplay:GetStatusBarTexture():SetVertTile(false)
    additionalFrame.durabilityDisplay:SetHeight(40)
    additionalFrame.durabilityDisplay:SetWidth(2.3)
    additionalFrame.durabilityDisplay:SetOrientation("VERTICAL")

    additionalFrame.socketDisplay = {}

    for i = 1, NUM_SOCKET_TEXTURES do
        additionalFrame.socketDisplay[i] = additionalFrame:CreateTexture()
        additionalFrame.socketDisplay[i]:SetWidth(14)
        additionalFrame.socketDisplay[i]:SetHeight(14)
    end

    return additionalFrame
end

local function positonLeft(button)
    local additionalFrame = button.BCPDisplay

    additionalFrame:SetPoint("TOPLEFT", button, "TOPRIGHT")
    additionalFrame:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT")

    additionalFrame.ilvlDisplay:SetPoint("BOTTOMLEFT", additionalFrame, "BOTTOMLEFT", 10, 2)
    additionalFrame.enchantDisplay:SetPoint("TOPLEFT", additionalFrame, "TOPLEFT", 10, -7)

    additionalFrame.durabilityDisplay:SetPoint("TOPLEFT", button, "TOPLEFT", -6, 0)
    additionalFrame.durabilityDisplay:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -6, 0)

    AnchorTextureRightOfParent(additionalFrame.ilvlDisplay, additionalFrame.socketDisplay)
end

local function positonRight(button)
    local additionalFrame = button.BCPDisplay

    additionalFrame:SetPoint("TOPRIGHT", button, "TOPLEFT")
    additionalFrame:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT")

    additionalFrame.ilvlDisplay:SetPoint("BOTTOMRIGHT", additionalFrame, "BOTTOMRIGHT", -10, 2)
    additionalFrame.enchantDisplay:SetPoint("TOPRIGHT", additionalFrame, "TOPRIGHT", -10, -7)

    additionalFrame.durabilityDisplay:SetWidth(1.2)
    additionalFrame.durabilityDisplay:SetPoint("TOPRIGHT", button, "TOPRIGHT", 4, 0)
    additionalFrame.durabilityDisplay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, 0)

    AnchorTextureLeftOfParent(additionalFrame.ilvlDisplay, additionalFrame.socketDisplay)
end

local function positonCenter(button)
    local additionalFrame = button.BCPDisplay

    additionalFrame:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -100, 0)
    additionalFrame:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, -100)

    additionalFrame.durabilityDisplay:SetHeight(2)
    additionalFrame.durabilityDisplay:SetWidth(40)
    additionalFrame.durabilityDisplay:SetOrientation("HORIZONTAL")
    additionalFrame.durabilityDisplay:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, -2)
    additionalFrame.durabilityDisplay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, -2)

    additionalFrame.ilvlDisplay:SetPoint("BOTTOM", button, "TOP", 0, 7)

    local buttonId = button:GetID()
    if isMop then
        if buttonId == INVSLOT_MAINHAND then
            additionalFrame.enchantDisplay:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", -5, 0)

            additionalFrame.socketDisplay[1]:SetPoint("RIGHT", button, "LEFT", -5, 0)
            for i = 2, NUM_SOCKET_TEXTURES do
                additionalFrame.socketDisplay[i]:SetPoint("RIGHT", additionalFrame.socketDisplay[i - 1], "LEFT", -2, 0)
            end
        elseif buttonId == INVSLOT_RANGED then
            additionalFrame.enchantDisplay:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 5, 0)

            additionalFrame.socketDisplay[1]:SetPoint("LEFT", button, "RIGHT", 5, 0)
            for i = 2, NUM_SOCKET_TEXTURES do
                additionalFrame.socketDisplay[i]:SetPoint("LEFT", additionalFrame.socketDisplay[i - 1], "RIGHT", 2, 0)
            end
        else
            additionalFrame.enchantDisplay:SetPoint("BOTTOM", button, "TOP", 0, 20)
            AnchorTextureLeftOfParent(additionalFrame.ilvlDisplay, additionalFrame.socketDisplay)
        end
    else
        if button:GetID() == INVSLOT_MAINHAND then
            additionalFrame.enchantDisplay:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", -5, 0)
            AnchorTextureLeftOfParent(additionalFrame.ilvlDisplay, additionalFrame.socketDisplay)
        else
            additionalFrame.enchantDisplay:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 5, 0)
            AnchorTextureRightOfParent(additionalFrame.ilvlDisplay, additionalFrame.socketDisplay)
        end
    end
end

local function AnchorAdditionalDisplay(button)
    local layout = buttonLayout[button:GetID()]
    if layout == "left" then
        positonLeft(button)
    elseif layout == "right" then
        positonRight(button)
    elseif layout == "center" then
        positonCenter(button)
    end
end

local function UpdateAdditionalDisplay(button, unit)
    local additionalFrame = button.BCPDisplay
    if not additionalFrame then
        return
    end

    local slot = button:GetID()
    local itemLink = GetInventoryItemLink(unit, slot)

    if not additionalFrame.prevItemLink or itemLink ~= additionalFrame.prevItemLink then
        local itemiLvlText = ""
        if itemLink then
            local ilvl = GetDetailedItemLevelInfo(itemLink)
            local quality = GetInventoryItemQuality(unit, slot)
            if quality then
                local hex = select(4, GetItemQualityColor(quality))
                itemiLvlText = "|c" .. hex .. ilvl .. "|r"
            else
                itemiLvlText = ilvl
            end
        end
        additionalFrame.ilvlDisplay:SetText(itemiLvlText or "")

        local atlas, enchantText
        if itemLink then
            atlas, enchantText = GetItemEnchantAsText(unit, slot)
        end

        local canEnchant = CanEnchantSlot(unit, slot)

        if not enchantText then
            local shouldDisplayEchantMissingText = canEnchant and itemLink and IsLevelAtEffectiveMaxLevel(UnitLevel(unit))
            additionalFrame.enchantDisplay:SetText(shouldDisplayEchantMissingText and "|cffff0000Missing|r" or "")
        else
            local maxSize = 18
            local containsColor = string.find(enchantText, "|c")
            if containsColor then
                maxSize = maxSize + strlen("|cffffffff|r")
            end
            enchantText = string.sub(enchantText, 1, maxSize)

            local enchantQuality = ""
            if atlas then
                enchantQuality = "|A:" .. atlas .. ":12:12|a"
            end

            if slot == INVSLOT_OFFHAND then
                additionalFrame.enchantDisplay:SetText(enchantQuality .. enchantText)
            else
                additionalFrame.enchantDisplay:SetText(enchantText .. enchantQuality)
            end
        end

        local textures = itemLink and GetSocketTextures(unit, slot) or {}
        for i = 1, NUM_SOCKET_TEXTURES do
            local socketTexture = additionalFrame.socketDisplay[i]
            if #textures >= i then
                socketTexture:SetTexture(textures[i])
                socketTexture:SetVertexColor(1, 1, 1)
                socketTexture:Show()
            else
                local expansion = GetExpansionForLevel(UnitLevel(unit))
                local expansionSocketRequirement = expansion and expansionRequiredSockets[expansion]
                if expansionSocketRequirement and expansionSocketRequirement[slot] and i <= expansionSocketRequirement[slot] then
                    socketTexture:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Red")
                    socketTexture:SetVertexColor(1, 0, 0)
                    socketTexture:Show()
                else
                    socketTexture:Hide()
                end
            end
        end

        additionalFrame.prevItemLink = itemLink
    end

    local currentDurability, maxDurability = GetInventoryItemDurability(slot)
    local percDurability = currentDurability and maxDurability and currentDurability / maxDurability

    if not additionalFrame.prevDurability or additionalFrame.prevDurability ~= percDurability then
        if UnitIsUnit("player", unit) and percDurability and percDurability < 1 then
            additionalFrame.durabilityDisplay:Show()
            additionalFrame.durabilityDisplay:SetValue(percDurability)
            additionalFrame.durabilityDisplay:SetStatusBarColor(ColorGradientHP(percDurability))
        else
            additionalFrame.durabilityDisplay:Hide()
        end
        additionalFrame.prevDurability = percDurability
    end

    additionalFrame:Show()
end

local function CreateInspectIlvlDisplay()
    local parent = InspectPaperDollItemsFrame
    if not parent then
        return
    end

    if not parent.ilvlDisplay then
        parent.ilvlDisplay = parent:CreateFontString(nil, "OVERLAY", isMop and "GameFontHighlightOutline" or "GameFontHighlightOutline22")
        parent.ilvlDisplay:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -20)
        parent.ilvlDisplay:SetPoint("BOTTOMLEFT", parent, "TOPRIGHT", -80, -67)
    end

    parent.ilvlDisplay:Show()
end

local LEGENDARY_ITEM_LEVEL = 483
local STEP_ITEM_LEVEL = 17

local levelThresholds = {}
for i = 4, 1, -1 do
    levelThresholds[i] = LEGENDARY_ITEM_LEVEL - (STEP_ITEM_LEVEL * (i - 1))
end

local function UpdateInspectIlvlDisplay(unit)
    if isMop then
        return
    end

    if not unit or not InspectPaperDollItemsFrame or not InspectPaperDollItemsFrame.ilvlDisplay then
        return
    end

    local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
    local color
    if ilvl < levelThresholds[4] then
        color = "fafafa"
    elseif ilvl < levelThresholds[3] then
        color = "1eff00"
    elseif ilvl < levelThresholds[2] then
        color = "0070dd"
    elseif ilvl < levelThresholds[1] then
        color = "a335ee"
    else
        color = "ff8000"
    end

    InspectPaperDollItemsFrame.ilvlDisplay:SetText(string.format("|cff%s%d|r", color, ilvl))
end

local function updateButton(button, unit)
    if not buttonLayout[button:GetID()] then
        return
    end

    if not CharacterPanel:IsActive() then
        if button.BCPDisplay then
            button.BCPDisplay:Hide()
        end
        return
    end

    if not button.BCPDisplay then
        button.BCPDisplay = CreateAdditionalDisplayForButton(button)
        AnchorAdditionalDisplay(button)
    end

    button.BCPDisplay:Show()

    if isMop then
        C_Timer.After(0, function()
            if CharacterPanel:IsActive() then
                UpdateAdditionalDisplay(button, unit)
            end
        end)
    else
        UpdateAdditionalDisplay(button, unit)
    end
end

local characterSlots = {
    "CharacterHeadSlot",
    "CharacterNeckSlot",
    "CharacterShoulderSlot",
    "CharacterChestSlot",
    "CharacterWaistSlot",
    "CharacterLegsSlot",
    "CharacterFeetSlot",
    "CharacterWristSlot",
    "CharacterHandsSlot",
    "CharacterFinger0Slot",
    "CharacterFinger1Slot",
    "CharacterTrinket0Slot",
    "CharacterTrinket1Slot",
    "CharacterBackSlot",
    "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
}

local function UpdateInspectButtons()
    if not InspectPaperDollItemsFrame then
        return
    end

    for i = 1, InspectPaperDollItemsFrame:GetNumChildren() do
        local child = select(i, InspectPaperDollItemsFrame:GetChildren())
        if child and child.GetID then
            updateButton(child, InspectFrame and InspectFrame.unit or "target")
        end
    end
end

function CharacterPanel:IsEnabledInDB()
    local db = GetDB()
    if not db then
        return false
    end
    return db.characterPanel ~= false
end

function CharacterPanel:IsActive()
    return self.active
end

function CharacterPanel:HideAllDisplays()
    for _, slot in ipairs(characterSlots) do
        local button = _G[slot]
        if button and button.BCPDisplay then
            button.BCPDisplay:Hide()
        end
    end

    if InspectPaperDollItemsFrame and InspectPaperDollItemsFrame.ilvlDisplay then
        InspectPaperDollItemsFrame.ilvlDisplay:SetText("")
        InspectPaperDollItemsFrame.ilvlDisplay:Hide()
    end
end

function CharacterPanel:UpdateAllCharacterSlots()
    if not self:IsActive() then
        self:HideAllDisplays()
        return
    end

    for _, slot in ipairs(characterSlots) do
        local button = _G[slot]
        if button then
            updateButton(button, "player")
        end
    end
end

function CharacterPanel:SOCKET_INFO_UPDATE()
    if not self:IsActive() then
        return
    end
    if CharacterFrame and CharacterFrame:IsShown() then
        self:UpdateAllCharacterSlots()
    end
end

function CharacterPanel:UNIT_INVENTORY_CHANGED(unit)
    if unit == "player" then
        self:SOCKET_INFO_UPDATE()
    end
end

local gemsWeCareAbout = {
    192991,
    192985,
    192982,
    192988,

    192945,
    192948,
    192952,
    192955,

    192961,
    192958,
    192964,
    192967,

    192919,
    192925,
    192922,
    192928,

    192935,
    192932,
    192938,
    192942,

    192973,
    192970,
    192979,
    192976,
}

function CharacterPanel:PLAYER_ENTERING_WORLD()
    if not self:IsActive() then
        return
    end

    for _, gemID in ipairs(gemsWeCareAbout) do
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(gemID)
        end
    end
end

function CharacterPanel:ADDON_LOADED(addonName)
    if addonName == "Blizzard_InspectUI" then
        local talentButton = InspectPaperDollItemsFrame and InspectPaperDollItemsFrame.InspectTalents
        if talentButton and talentButton.SetSize then
            talentButton:SetSize(72, 32)
        end

        if not self.inspectHooksSet then
            self.inspectHooksSet = true

            hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
                updateButton(button, InspectFrame and InspectFrame.unit or "target")
            end)

            hooksecurefunc("InspectPaperDollFrame_SetLevel", function()
                if not InspectFrame or not InspectFrame.unit then
                    return
                end
                CreateInspectIlvlDisplay()
                UpdateInspectIlvlDisplay(InspectFrame.unit)
            end)
        end

        if InspectFrame and InspectFrame.unit then
            CreateInspectIlvlDisplay()
            UpdateInspectIlvlDisplay(InspectFrame.unit)
            UpdateInspectButtons()
        end
    end
end

function CharacterPanel:SetupHooks()
    if self.hooksSet then
        return
    end
    self.hooksSet = true

    hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
        updateButton(button, "player")
    end)
end

function CharacterPanel:CreateEventFrame()
    if self.eventFrame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        if CharacterPanel[event] then
            CharacterPanel[event](CharacterPanel, ...)
        end
    end)

    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("SOCKET_INFO_UPDATE")
    frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    self.eventFrame = frame
end

function CharacterPanel:Initialize()
    if self.initialized then
        self.active = self:IsEnabledInDB()
        return
    end

    self.initialized = true
    self.active = self:IsEnabledInDB()

    self:SetupHooks()
    self:CreateEventFrame()

    if self:IsActive() then
        self:UpdateAllCharacterSlots()
    else
        self:HideAllDisplays()
    end
end

function CharacterPanel:Refresh()
    if not self.initialized then
        self:Initialize()
    end

    self.active = self:IsEnabledInDB()

    if not self:IsActive() then
        self:HideAllDisplays()
        return
    end

    self:UpdateAllCharacterSlots()

    if InspectFrame and InspectFrame:IsShown() then
        CreateInspectIlvlDisplay()
        UpdateInspectIlvlDisplay(InspectFrame.unit)
        UpdateInspectButtons()
    end
end


