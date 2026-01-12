local ADDON_NAME, ns = ...
local NephUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")

local AnchorPoints = {
    TOPLEFT = "Top Left",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}

local OrientationValues = {
    HORIZONTAL = "Horizontal",
    VERTICAL = "Vertical",
}

local HorizontalGrowthOptions = {
    LEFT = "Left",
    RIGHT = "Right",
}

local VerticalGrowthOptions = {
    UP = "Up",
    DOWN = "Down",
}

local OutlineOptions = {
    NONE = "None",
    OUTLINE = "Outline",
    THICKOUTLINE = "Thick Outline",
    MONOCHROME = "Monochrome",
}

local TextFormats = {
    PERCENT = "Percent",
    CURRENT = "Current",
    CURRENTMAX = "Current / Max",
    DEFICIT = "Missing",
}

local ColorModes = {
    CLASS = "Class Color",
    CUSTOM = "Static Color",
    GRADIENT = "Health Gradient",
}

local AbsorbAnchorOptions = {
    RIGHT = "Right",
    LEFT = "Left",
}

local DispelAnchorOptions = { DEFAULT = "Default" }
for key, value in pairs(AnchorPoints) do
    DispelAnchorOptions[key] = value
end

local function GetLSMValues(kind)
    if not LSM then return {} end
    local values = {}
    local hash = LSM:HashTable(kind)
    for name in pairs(hash) do
        values[name] = name
    end
    return values
end

local function Fetch(modeKey)
    local profile = NephUI.db and NephUI.db.profile
    if not profile then return nil end
    profile[modeKey] = profile[modeKey] or {}
    return profile[modeKey]
end

local function DeepValue(tbl, path)
    local node = tbl
    for key in string.gmatch(path, "[^%.]+") do
        if not node then return nil end
        node = node[key]
    end
    return node
end

local function DeepSet(tbl, path, value)
    local keys = {}
    for key in string.gmatch(path, "[^%.]+") do
        table.insert(keys, key)
    end
    local node = tbl
    for i = 1, #keys - 1 do
        local key = keys[i]
        node[key] = node[key] or {}
        node = node[key]
    end
    node[keys[#keys]] = value
end

local function SignalRefresh(modeKey)
    if not NephUI then return end
    if modeKey == "partyFrames" and NephUI.PartyFrames and NephUI.PartyFrames.Refresh then
        NephUI.PartyFrames:Refresh()
        return
    elseif modeKey == "raidFrames" and NephUI.RaidFrames and NephUI.RaidFrames.Refresh then
        NephUI.RaidFrames:Refresh()
        return
    end
    if NephUI.RefreshAll then
        NephUI:RefreshAll()
    end
end

local function GetRaidFramesClassColorCVar()
    local function FetchBool(getter, name)
        if not getter then return nil end
        local ok, value = pcall(getter, name)
        if ok then
            if type(value) == "boolean" then
                return value
            elseif type(value) == "string" then
                return value == "1"
            elseif type(value) == "number" then
                return value == 1
            end
        end
        return nil
    end
    if C_CVar and C_CVar.GetCVarBool then
        local v = FetchBool(C_CVar.GetCVarBool, "raidFramesDisplayClassColor")
        if v ~= nil then return v end
    end
    if C_CVar and C_CVar.GetCVar then
        local v = FetchBool(C_CVar.GetCVar, "raidFramesDisplayClassColor")
        if v ~= nil then return v end
    end
    local v = FetchBool(GetCVarBool, "raidFramesDisplayClassColor")
    if v ~= nil then return v end
    return FetchBool(GetCVar, "raidFramesDisplayClassColor")
end

local function SetRaidFramesClassColorCVar(enabled)
    local value = enabled and "1" or "0"
    local function Setter(func)
        if not func then return false end
        local ok = pcall(func, "raidFramesDisplayClassColor", value)
        return ok
    end
    if C_CVar and C_CVar.SetCVar then
        if Setter(C_CVar.SetCVar) then return end
    end
    Setter(SetCVar)
end

local function HexToRGBA(hex)
    if type(hex) ~= "string" then return nil end
    hex = hex:gsub("#", "")
    if #hex ~= 8 then return nil end
    local a = tonumber(hex:sub(1, 2), 16)
    local r = tonumber(hex:sub(3, 4), 16)
    local g = tonumber(hex:sub(5, 6), 16)
    local b = tonumber(hex:sub(7, 8), 16)
    if not (a and r and g and b) then return nil end
    return r / 255, g / 255, b / 255, a / 255
end

local function RGBAToHex(r, g, b, a)
    local function Clamp(x)
        return math.min(255, math.max(0, math.floor((x or 0) * 255 + 0.5)))
    end
    local alpha = Clamp(a or 1)
    local red = Clamp(r)
    local green = Clamp(g)
    local blue = Clamp(b)
    return string.format("%02X%02X%02X%02X", alpha, red, green, blue)
end

local function GetRaidFramesHealthColorCVar()
    local hexValue = nil
    local function FetchString(getter, name)
        if not getter then return nil end
        local ok, value = pcall(getter, name)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
        return nil
    end
    if C_CVar and C_CVar.GetCVar then
        hexValue = FetchString(C_CVar.GetCVar, "raidFramesHealthBarColor")
    end
    if not hexValue then
        hexValue = FetchString(GetCVar, "raidFramesHealthBarColor")
    end
    if not hexValue then return nil end
    return HexToRGBA(hexValue)
end

local function SetRaidFramesHealthColorCVar(r, g, b, a)
    local hex = RGBAToHex(r, g, b, a)
    local function Setter(func)
        if not func then return false end
        local ok = pcall(func, "raidFramesHealthBarColor", hex)
        return ok
    end
    if C_CVar and C_CVar.SetCVar then
        if Setter(C_CVar.SetCVar) then return end
    end
    Setter(SetCVar)
end

local function SimpleGetter(modeKey, path)
    return function()
        local tbl = Fetch(modeKey)
        return tbl and DeepValue(tbl, path)
    end
end

local function SimpleSetter(modeKey, path)
    return function(_, value)
        local tbl = Fetch(modeKey)
        if not tbl then return end
        DeepSet(tbl, path, value)
        SignalRefresh(modeKey)
    end
end

local function DisabledIfFalse(modeKey, path)
    return function()
        local tbl = Fetch(modeKey)
        local value = tbl and DeepValue(tbl, path)
        return value == false
    end
end

local function ColorGetter(modeKey, path)
    return function()
        local tbl = Fetch(modeKey)
        local value = tbl and DeepValue(tbl, path)
        if not value then
            return 1, 1, 1, 1
        end
        return value[1], value[2], value[3], value[4] or 1
    end
end

local function ColorSetter(modeKey, path)
    return function(_, r, g, b, a)
        local tbl = Fetch(modeKey)
        if not tbl then return end
        DeepSet(tbl, path, {r, g, b, a})
        SignalRefresh(modeKey)
    end
end

local function DispelAnchorGetter(modeKey, path)
    return function()
        local tbl = Fetch(modeKey)
        local value = tbl and DeepValue(tbl, path)
        if not value then
            return "DEFAULT"
        end
        return value
    end
end

local function DispelAnchorSetter(modeKey, path)
    return function(_, value)
        local tbl = Fetch(modeKey)
        if not tbl then return end
        local actual = value == "DEFAULT" and nil or value
        DeepSet(tbl, path, actual)
        SignalRefresh(modeKey)
    end
end

local function DispelNumberGetter(modeKey, path, fallback)
    fallback = fallback or 0
    return function()
        local tbl = Fetch(modeKey)
        local value = tbl and DeepValue(tbl, path)
        if value == nil then
            return fallback
        end
        return value
    end
end

local function BuildAuraOptions(modeKey, key, label, order, inline)
    local prefix = "auras." .. key
    local group = {
        type = "group",
        name = label,
        order = order,
        inline = inline == true,
        args = {
            enabled = {
                type = "toggle",
                name = "Show",
                order = 0,
                get = SimpleGetter(modeKey, prefix .. ".enabled"),
                set = SimpleSetter(modeKey, prefix .. ".enabled"),
            },
            size = {
                type = "range",
                name = "Size",
                min = 16,
                max = 64,
                step = 1,
                order = 1,
                get = SimpleGetter(modeKey, prefix .. ".size"),
                set = SimpleSetter(modeKey, prefix .. ".size"),
            },
            borderSize = {
                type = "range",
                name = "Border Thickness",
                min = 0,
                max = 4,
                step = 1,
                order = 2,
                get = SimpleGetter(modeKey, prefix .. ".borderSize"),
                set = SimpleSetter(modeKey, prefix .. ".borderSize"),
            },
            perRow = {
                type = "range",
                name = "Icons per Row",
                min = 0,
                max = 6,
                step = 1,
                order = 3,
                get = SimpleGetter(modeKey, prefix .. ".perRow"),
                set = SimpleSetter(modeKey, prefix .. ".perRow"),
            },
            spacingX = {
                type = "range",
                name = "Horizontal Spacing",
                min = 0,
                max = 40,
                step = 1,
                order = 4,
                get = SimpleGetter(modeKey, prefix .. ".spacingX"),
                set = SimpleSetter(modeKey, prefix .. ".spacingX"),
            },
            spacingY = {
                type = "range",
                name = "Vertical Spacing",
                min = 0,
                max = 40,
                step = 1,
                order = 5,
                get = SimpleGetter(modeKey, prefix .. ".spacingY"),
                set = SimpleSetter(modeKey, prefix .. ".spacingY"),
            },
            max = {
                type = "range",
                name = "Maximum Icons",
                min = 1,
                max = 12,
                step = 1,
                order = 6,
                get = SimpleGetter(modeKey, prefix .. ".max"),
                set = SimpleSetter(modeKey, prefix .. ".max"),
            },
            anchor = {
                type = "select",
                name = "Anchor",
                order = 7,
                values = AnchorPoints,
                get = SimpleGetter(modeKey, prefix .. ".anchor"),
                set = SimpleSetter(modeKey, prefix .. ".anchor"),
            },
            horizontalGrowth = {
                type = "select",
                name = "Horizontal Growth",
                order = 7.1,
                values = HorizontalGrowthOptions,
                get = SimpleGetter(modeKey, prefix .. ".horizontalGrowth"),
                set = SimpleSetter(modeKey, prefix .. ".horizontalGrowth"),
            },
            verticalGrowth = {
                type = "select",
                name = "Vertical Growth",
                order = 7.2,
                values = VerticalGrowthOptions,
                get = SimpleGetter(modeKey, prefix .. ".verticalGrowth"),
                set = SimpleSetter(modeKey, prefix .. ".verticalGrowth"),
            },
            offsetX = {
                type = "range",
                name = "Offset X",
                min = -40,
                max = 40,
                step = 1,
                order = 8,
                get = SimpleGetter(modeKey, prefix .. ".offsetX"),
                set = SimpleSetter(modeKey, prefix .. ".offsetX"),
            },
            offsetY = {
                type = "range",
                name = "Offset Y",
                min = -40,
                max = 40,
                step = 1,
                order = 9,
                get = SimpleGetter(modeKey, prefix .. ".offsetY"),
                set = SimpleSetter(modeKey, prefix .. ".offsetY"),
            },
            stackSize = {
                type = "range",
                name = "Stack Font Size",
                min = 8,
                max = 20,
                step = 1,
                order = 10,
                get = SimpleGetter(modeKey, prefix .. ".stack.size"),
                set = SimpleSetter(modeKey, prefix .. ".stack.size"),
            },
            countdown = {
                type = "toggle",
                name = "Show Countdown Text",
                order = 11,
                get = SimpleGetter(modeKey, prefix .. ".countdown.enabled"),
                set = SimpleSetter(modeKey, prefix .. ".countdown.enabled"),
            },
            countdownSize = {
                type = "range",
                name = "Duration Font Size",
                min = 8,
                max = 24,
                step = 1,
                order = 11.1,
                get = SimpleGetter(modeKey, prefix .. ".countdown.size"),
                set = SimpleSetter(modeKey, prefix .. ".countdown.size"),
            },
            hideSwipe = {
                type = "toggle",
                name = "Hide Swipe Animation",
                order = 12,
                get = SimpleGetter(modeKey, prefix .. ".hideSwipe"),
                set = SimpleSetter(modeKey, prefix .. ".hideSwipe"),
            },
        },
    }

    if key == "centerStatus" then
        local args = group.args
        if args.enabled then
            args.enabled.name = "Hide Center Status Icon"
            args.enabled.desc = "Checked = hide Blizzard's center status icon."
        end
        args.anchor = nil
        args.offsetX = nil
        args.offsetY = nil
        args.scale = nil
    end

    return group
end

local function BuildSpecialAuraOptions(modeKey, key, label, order)
    local prefix = "auras." .. key
    return {
        type = "group",
        name = label,
        order = order,
        args = {
            size = {
                type = "range",
                name = "Size",
                min = 8,
                max = 64,
                step = 1,
                order = 1,
                get = SimpleGetter(modeKey, prefix .. ".size"),
                set = SimpleSetter(modeKey, prefix .. ".size"),
            },
            borderSize = {
                type = "range",
                name = "Border Thickness",
                min = 0,
                max = 4,
                step = 1,
                order = 2,
                get = SimpleGetter(modeKey, prefix .. ".borderSize"),
                set = SimpleSetter(modeKey, prefix .. ".borderSize"),
            },
            anchor = {
                type = "select",
                name = "Anchor",
                order = 3,
                values = AnchorPoints,
                get = SimpleGetter(modeKey, prefix .. ".anchor"),
                set = SimpleSetter(modeKey, prefix .. ".anchor"),
            },
            offsetX = {
                type = "range",
                name = "Offset X",
                min = -60,
                max = 60,
                step = 1,
                order = 4,
                get = SimpleGetter(modeKey, prefix .. ".offsetX"),
                set = SimpleSetter(modeKey, prefix .. ".offsetX"),
            },
            offsetY = {
                type = "range",
                name = "Offset Y",
                min = -60,
                max = 60,
                step = 1,
                order = 5,
                get = SimpleGetter(modeKey, prefix .. ".offsetY"),
                set = SimpleSetter(modeKey, prefix .. ".offsetY"),
            },
        },
    }
end

local function BuildIconOptions(modeKey, key, label, order, inline)
    local prefix = "icons." .. key
    local group = {
        type = "group",
        name = label,
        order = order,
        inline = inline == true,
        args = {
            enabled = {
                type = "toggle",
                name = "Show",
                order = 1,
                get = SimpleGetter(modeKey, prefix .. ".enabled"),
                set = SimpleSetter(modeKey, prefix .. ".enabled"),
            },
            anchor = {
                type = "select",
                name = "Anchor",
                order = 2,
                values = AnchorPoints,
                get = SimpleGetter(modeKey, prefix .. ".anchor"),
                set = SimpleSetter(modeKey, prefix .. ".anchor"),
            },
            offsetX = {
                type = "range",
                name = "Offset X",
                min = -30,
                max = 30,
                step = 1,
                order = 3,
                get = SimpleGetter(modeKey, prefix .. ".offsetX"),
                set = SimpleSetter(modeKey, prefix .. ".offsetX"),
            },
            offsetY = {
                type = "range",
                name = "Offset Y",
                min = -30,
                max = 30,
                step = 1,
                order = 4,
                get = SimpleGetter(modeKey, prefix .. ".offsetY"),
                set = SimpleSetter(modeKey, prefix .. ".offsetY"),
            },
            scale = {
                type = "range",
                name = "Scale",
                min = 0.5,
                max = 2.0,
                step = 0.05,
                order = 5,
                get = SimpleGetter(modeKey, prefix .. ".scale"),
                set = SimpleSetter(modeKey, prefix .. ".scale"),
            },
        },
    }

    if group.args.enabled then
        local displayName = label or key
        group.args.enabled.name = "Hide " .. displayName
        group.args.enabled.desc = "Checked = hide Blizzard's " .. string.lower(displayName) .. "."
    end

    return group
end

local function BuildDispelIconOptions(modeKey, label, order)
    local prefix = "icons.dispel"
    return {
        type = "group",
        name = label,
        order = order,
        args = {
            hide = {
                type = "toggle",
                name = "Hide Icons",
                order = 1,
                get = SimpleGetter(modeKey, prefix .. ".hide"),
                set = SimpleSetter(modeKey, prefix .. ".hide"),
            },
            anchor = {
                type = "select",
                name = "Anchor",
                order = 2,
                values = DispelAnchorOptions,
                get = DispelAnchorGetter(modeKey, prefix .. ".anchor"),
                set = DispelAnchorSetter(modeKey, prefix .. ".anchor"),
            },
            offsetX = {
                type = "range",
                name = "Offset X",
                min = -60,
                max = 60,
                step = 1,
                order = 3,
                get = DispelNumberGetter(modeKey, prefix .. ".offsetX", 0),
                set = SimpleSetter(modeKey, prefix .. ".offsetX"),
            },
            offsetY = {
                type = "range",
                name = "Offset Y",
                min = -60,
                max = 60,
                step = 1,
                order = 4,
                get = DispelNumberGetter(modeKey, prefix .. ".offsetY", 0),
                set = SimpleSetter(modeKey, prefix .. ".offsetY"),
            },
            scale = {
                type = "range",
                name = "Scale",
                min = 0.5,
                max = 2,
                step = 0.05,
                order = 5,
                get = DispelNumberGetter(modeKey, prefix .. ".scale", 1),
                set = SimpleSetter(modeKey, prefix .. ".scale"),
            },
        },
    }
end

local function BuildTextOptions(modeKey, key, label, order, inline)
    local prefix = "text." .. key
    local args = {
        enabled = {
            type = "toggle",
            name = "Enable",
            order = 1,
            get = SimpleGetter(modeKey, prefix .. ".enabled"),
            set = SimpleSetter(modeKey, prefix .. ".enabled"),
        },
        font = {
            type = "select",
            name = "Font",
            dialogControl = "LSM30_Font",
            order = 2,
            values = GetLSMValues("font"),
            get = SimpleGetter(modeKey, prefix .. ".font"),
            set = SimpleSetter(modeKey, prefix .. ".font"),
        },
        size = {
            type = "range",
            name = "Font Size",
            order = 3,
            min = 8,
            max = 24,
            step = 1,
            get = SimpleGetter(modeKey, prefix .. ".size"),
            set = SimpleSetter(modeKey, prefix .. ".size"),
        },
        outline = {
            type = "select",
            name = "Outline",
            order = 4,
            values = OutlineOptions,
            get = SimpleGetter(modeKey, prefix .. ".outline"),
            set = SimpleSetter(modeKey, prefix .. ".outline"),
        },
        anchor = {
            type = "select",
            name = "Anchor",
            order = 5,
            values = AnchorPoints,
            get = SimpleGetter(modeKey, prefix .. ".anchor"),
            set = SimpleSetter(modeKey, prefix .. ".anchor"),
        },
        offsetX = {
            type = "range",
            name = "Offset X",
            order = 6,
            min = -40,
            max = 40,
            step = 0.5,
            get = SimpleGetter(modeKey, prefix .. ".offsetX"),
            set = SimpleSetter(modeKey, prefix .. ".offsetX"),
        },
        offsetY = {
            type = "range",
            name = "Offset Y",
            order = 7,
            min = -40,
            max = 40,
            step = 0.5,
            get = SimpleGetter(modeKey, prefix .. ".offsetY"),
            set = SimpleSetter(modeKey, prefix .. ".offsetY"),
        },
        shadowX = {
            type = "range",
            name = "Shadow Offset X",
            order = 8,
            min = -10,
            max = 10,
            step = 0.5,
            get = SimpleGetter(modeKey, prefix .. ".shadowOffsetX"),
            set = SimpleSetter(modeKey, prefix .. ".shadowOffsetX"),
        },
        shadowY = {
            type = "range",
            name = "Shadow Offset Y",
            order = 9,
            min = -10,
            max = 10,
            step = 0.5,
            get = SimpleGetter(modeKey, prefix .. ".shadowOffsetY"),
            set = SimpleSetter(modeKey, prefix .. ".shadowOffsetY"),
        },
        useClassColor = {
            type = "toggle",
            name = "Use Class Color",
            order = 10,
            get = SimpleGetter(modeKey, prefix .. ".useClassColor"),
            set = SimpleSetter(modeKey, prefix .. ".useClassColor"),
        },
        color = {
            type = "color",
            name = "Custom Color",
            hasAlpha = true,
            order = 11,
            get = ColorGetter(modeKey, prefix .. ".color"),
            set = ColorSetter(modeKey, prefix .. ".color"),
        },
    }

    if key == "health" then
        args.format = {
            type = "select",
            name = "Format",
            order = 10,
            values = TextFormats,
            get = SimpleGetter(modeKey, prefix .. ".format"),
            set = SimpleSetter(modeKey, prefix .. ".format"),
        }
        args.abbreviate = {
            type = "toggle",
            name = "Abbreviate Large Numbers",
            order = 11,
            get = SimpleGetter(modeKey, prefix .. ".abbreviate"),
            set = SimpleSetter(modeKey, prefix .. ".abbreviate"),
        }
    else
        args.showRealm = {
            type = "toggle",
            name = "Show Realm",
            order = 10,
            get = SimpleGetter(modeKey, prefix .. ".showRealm"),
            set = SimpleSetter(modeKey, prefix .. ".showRealm"),
        }
        args.maxChars = {
            type = "range",
            name = "Max Characters (0 = unlimited)",
            order = 11,
            min = 0,
            max = 20,
            step = 1,
            get = SimpleGetter(modeKey, prefix .. ".maxChars"),
            set = SimpleSetter(modeKey, prefix .. ".maxChars"),
        }
    end

    return {
        type = "group",
        name = label,
        order = order,
        inline = inline == true,
        args = args,
    }
end

local function BuildOptions(modeKey, label, order, variant)
    variant = variant or "party"
    local isRaid = variant == "raid"
    local group = {
        type = "group",
        name = label,
        order = order,
        childGroups = "tab",
        args = {
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable Styling",
                        order = 1,
                        get = function()
                            local tbl = Fetch(modeKey)
                            return tbl and tbl.enabled ~= false
                        end,
                    set = function(_, val)
                        local tbl = Fetch(modeKey)
                        if not tbl then return end
                        tbl.enabled = val
                        SignalRefresh(modeKey)
                    end,
                },
                    showWhenSolo = not isRaid and {
                        type = "toggle",
                        name = "Show When Solo",
                        order = 2,
                        get = SimpleGetter(modeKey, "general.showWhenSolo"),
                        set = SimpleSetter(modeKey, "general.showWhenSolo"),
                    } or nil,
                    hideHeader = not isRaid and {
                        type = "toggle",
                        name = "Hide Party Label",
                        order = 3,
                        get = SimpleGetter(modeKey, "general.hideHeaderText"),
                        set = SimpleSetter(modeKey, "general.hideHeaderText"),
                    } or nil,
                    hideGroupLabels = isRaid and {
                        type = "toggle",
                        name = "Hide Group Labels",
                        order = 3,
                        get = SimpleGetter(modeKey, "general.hideGroupLabels"),
                        set = SimpleSetter(modeKey, "general.hideGroupLabels"),
                    } or nil,
                    hidePlayerFrame = not isRaid and {
                        type = "toggle",
                        name = "Hide Player Frame",
                        desc = "Hides your own slot from the Blizzard party frame",
                        order = 4,
                        get = SimpleGetter(modeKey, "general.hidePlayerFrame"),
                        set = SimpleSetter(modeKey, "general.hidePlayerFrame"),
                    } or nil,
                    fadeRange = {
                        type = "toggle",
                        name = "Fade Out-Of-Range Units",
                        order = 5,
                        get = SimpleGetter(modeKey, "general.fadeOutOfRange"),
                        set = SimpleSetter(modeKey, "general.fadeOutOfRange"),
                    },
                    rangeAlpha = {
                        type = "range",
                        name = "Faded Alpha",
                        order = 6,
                        min = 0.1,
                        max = 1,
                        step = 0.05,
                        get = SimpleGetter(modeKey, "general.outOfRangeAlpha"),
                        set = SimpleSetter(modeKey, "general.outOfRangeAlpha"),
                    },
                    blizzardSelectionEnabled = {
                        type = "toggle",
                        name = "Show Blizzard Selection Highlight",
                        order = 7,
                        get = SimpleGetter(modeKey, "highlights.blizzardSelection.enabled"),
                        set = SimpleSetter(modeKey, "highlights.blizzardSelection.enabled"),
                    },
                    selectionColor = {
                        type = "color",
                        name = "Selection Color",
                        hasAlpha = true,
                        order = 8,
                        get = ColorGetter(modeKey, "highlights.selection.color"),
                        set = ColorSetter(modeKey, "highlights.selection.color"),
                    },
                    selectionAlpha = {
                        type = "range",
                        name = "Selection Alpha",
                        order = 9,
                        min = 0,
                        max = 1,
                        step = 0.05,
                        get = SimpleGetter(modeKey, "highlights.selection.alpha"),
                        set = SimpleSetter(modeKey, "highlights.selection.alpha"),
                    },
                    blizzardAggroEnabled = {
                        type = "toggle",
                        name = "Show Blizzard Aggro Highlight",
                        order = 10,
                        get = SimpleGetter(modeKey, "highlights.blizzardAggro.enabled"),
                        set = SimpleSetter(modeKey, "highlights.blizzardAggro.enabled"),
                    },
                    mouseoverHighlightEnabled = {
                        type = "toggle",
                        name = "Show Mouseover Highlight",
                        order = 11,
                        get = SimpleGetter(modeKey, "highlights.mouseover.enabled"),
                        set = SimpleSetter(modeKey, "highlights.mouseover.enabled"),
                    },
                    mouseoverHighlightAlpha = {
                        type = "range",
                        name = "Mouseover Highlight Alpha",
                        order = 12,
                        min = 0,
                        max = 1,
                        step = 0.05,
                        get = SimpleGetter(modeKey, "highlights.mouseover.alpha"),
                        set = SimpleSetter(modeKey, "highlights.mouseover.alpha"),
                        disabled = DisabledIfFalse(modeKey, "highlights.mouseover.enabled"),
                    },
                },
            },
            layout = {
                type = "group",
                name = "Layout",
                order = 5,
                args = {
                    -- Temporarily hide size override controls
                    --[[
                    useCustomSize = {
                        type = "toggle",
                        name = "Override Size",
                        order = 1,
                        get = SimpleGetter(modeKey, "layout.useCustomSize"),
                        set = SimpleSetter(modeKey, "layout.useCustomSize"),
                    },
                    width = {
                        type = "range",
                        name = "Width",
                        min = 20,
                        max = 500,
                        step = 1,
                        order = 2,
                        disabled = function()
                            local tbl = Fetch(modeKey)
                            return not (tbl and tbl.layout and tbl.layout.useCustomSize)
                        end,
                        get = SimpleGetter(modeKey, "layout.width"),
                        set = SimpleSetter(modeKey, "layout.width"),
                    },
                    height = {
                        type = "range",
                        name = "Height",
                        min = 20,
                        max = 100,
                        step = 1,
                        order = 3,
                        disabled = function()
                            local tbl = Fetch(modeKey)
                            return not (tbl and tbl.layout and tbl.layout.useCustomSize)
                        end,
                        get = SimpleGetter(modeKey, "layout.height"),
                        set = SimpleSetter(modeKey, "layout.height"),
                    },
                    --]]
                    opacity = {
                        type = "range",
                        name = "Opacity",
                        min = 0.2,
                        max = 1.0,
                        step = 0.05,
                        order = 4,
                        get = SimpleGetter(modeKey, "layout.opacity"),
                        set = SimpleSetter(modeKey, "layout.opacity"),
                    },
                    borderSize = {
                        type = "range",
                        name = "Border Thickness",
                        order = 7,
                        min = 0,
                        max = 6,
                        step = 1,
                        get = SimpleGetter(modeKey, "layout.border.size"),
                        set = SimpleSetter(modeKey, "layout.border.size"),
                    },
                    spacingY = {
                        type = "range",
                        name = isRaid and "Group Spacing" or "Frame Spacing",
                        order = 8,
                        min = 0,
                        max = isRaid and 20 or 40,
                        step = 0.5,
                        get = SimpleGetter(modeKey, "layout.spacing.vertical"),
                        set = SimpleSetter(modeKey, "layout.spacing.vertical"),
                    },
                },
            },
            health = {
                type = "group",
                name = "Health Bar",
                order = 10,
                args = {
                    texture = {
                        type = "select",
                        name = "Texture",
                        dialogControl = "LSM30_Statusbar",
                        order = 1,
                        values = GetLSMValues("statusbar"),
                        get = SimpleGetter(modeKey, "health.texture"),
                        set = SimpleSetter(modeKey, "health.texture"),
                    },
                    orientation = {
                        type = "select",
                        name = "Orientation",
                        order = 2,
                        values = OrientationValues,
                        get = SimpleGetter(modeKey, "health.orientation"),
                        set = SimpleSetter(modeKey, "health.orientation"),
                    },
                    classColor = {
                        type = "toggle",
                        name = "Use Class Color",
                        order = 3,
                        get = function()
                            local cvarValue = GetRaidFramesClassColorCVar()
                            if cvarValue ~= nil then
                                return cvarValue
                            end
                            local tbl = Fetch(modeKey)
                            if not tbl or not tbl.health then
                                return true
                            end
                            return tbl.health.useClassColor ~= false
                        end,
                        set = function(_, val)
                            SetRaidFramesClassColorCVar(val)
                            local tbl = Fetch(modeKey)
                            if not tbl then return end
                            DeepSet(tbl, "health.useClassColor", val)
                            SignalRefresh(modeKey)
                        end,
                    },
                    customColor = {
                        type = "color",
                        name = "Custom Color",
                        hasAlpha = true,
                        order = 4,
                        hidden = function()
                            local tbl = Fetch(modeKey)
                            return tbl and tbl.health and tbl.health.useClassColor ~= false
                        end,
                        get = function()
                            local r, g, b, a = GetRaidFramesHealthColorCVar()
                            if r then
                                return r, g, b, a or 1
                            end
                            local tbl = Fetch(modeKey)
                            local color = tbl and tbl.health and tbl.health.customColor or {0, 0.9, 0, 1}
                            return color[1], color[2], color[3], color[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            SetRaidFramesHealthColorCVar(r, g, b, a)
                            local tbl = Fetch(modeKey)
                            if not tbl then return end
                            DeepSet(tbl, "health.customColor", {r, g, b, a or 1})
                            SignalRefresh(modeKey)
                        end,
                    },
                    backgroundClassColor = {
                        type = "toggle",
                        name = "Use Class Color Background",
                        order = 5,
                        get = SimpleGetter(modeKey, "health.background.useClassColor"),
                        set = SimpleSetter(modeKey, "health.background.useClassColor"),
                    },
                    backgroundColor = {
                        type = "color",
                        name = "Background Color",
                        order = 6,
                        hasAlpha = true,
                        hidden = function()
                            local tbl = Fetch(modeKey)
                            return tbl and tbl.health and tbl.health.background and tbl.health.background.useClassColor
                        end,
                        get = ColorGetter(modeKey, "health.background.color"),
                        set = ColorSetter(modeKey, "health.background.color"),
                    },
                },
            },
            texts = {
                type = "group",
                name = "Text",
                order = 20,
                childGroups = "tab",
                args = {
                    healthText = BuildTextOptions(modeKey, "health", "Health Text", 1),
                    nameText = BuildTextOptions(modeKey, "name", "Name Text", 2),
                },
            },
            icons = {
                type = "group",
                name = "Status Icons",
                order = 30,
                childGroups = "tab",
                args = {
                    leader = BuildIconOptions(modeKey, "leader", "Leader Icon", 1),
                    role = BuildIconOptions(modeKey, "role", "Role Icon", 2),
                    raid = BuildIconOptions(modeKey, "raid", "Raid Marker", 3),
                    ready = BuildIconOptions(modeKey, "ready", "Ready Check", 4),
                    center = BuildIconOptions(modeKey, "centerStatus", "Center Status", 5),
                    dispel = BuildDispelIconOptions(modeKey, "Dispel Icons", 6),
                },
            },
            auras = {
                type = "group",
                name = "Auras",
                order = 40,
                childGroups = "tab",
                args = {
                    buffs = BuildAuraOptions(modeKey, "buffs", "Buffs", 1),
                    debuffs = BuildAuraOptions(modeKey, "debuffs", "Debuffs", 2),
                    centerDefensive = BuildSpecialAuraOptions(modeKey, "centerDefensive", "Center Defensive Buff", 3),
                },
            },
            resource = {
                type = "group",
                name = "Resource Bar",
                order = 50,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable",
                        order = 1,
                        get = SimpleGetter(modeKey, "resource.enabled"),
                        set = SimpleSetter(modeKey, "resource.enabled"),
                    },
                    matchWidth = {
                        type = "toggle",
                        name = "Match Health Width",
                        order = 2,
                        get = SimpleGetter(modeKey, "resource.matchHealthWidth"),
                        set = SimpleSetter(modeKey, "resource.matchHealthWidth"),
                    },
                    width = {
                        type = "range",
                        name = "Width",
                        order = 3,
                        min = 10,
                        max = 200,
                        step = 1,
                        disabled = function()
                            local tbl = Fetch(modeKey)
                            return tbl and tbl.resource and tbl.resource.matchHealthWidth
                        end,
                        get = SimpleGetter(modeKey, "resource.width"),
                        set = SimpleSetter(modeKey, "resource.width"),
                    },
                    height = {
                        type = "range",
                        name = "Height",
                        order = 4,
                        min = 1,
                        max = 20,
                        step = 1,
                        get = SimpleGetter(modeKey, "resource.height"),
                        set = SimpleSetter(modeKey, "resource.height"),
                    },
                    anchor = {
                        type = "select",
                        name = "Anchor",
                        order = 5,
                        values = AnchorPoints,
                        get = SimpleGetter(modeKey, "resource.anchor"),
                        set = SimpleSetter(modeKey, "resource.anchor"),
                    },
                    offsetX = {
                        type = "range",
                        name = "Offset X",
                        order = 6,
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SimpleGetter(modeKey, "resource.offsetX"),
                        set = SimpleSetter(modeKey, "resource.offsetX"),
                    },
                    offsetY = {
                        type = "range",
                        name = "Offset Y",
                        order = 7,
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SimpleGetter(modeKey, "resource.offsetY"),
                        set = SimpleSetter(modeKey, "resource.offsetY"),
                    },
                    orientation = {
                        type = "select",
                        name = "Orientation",
                        order = 8,
                        values = OrientationValues,
                        get = SimpleGetter(modeKey, "resource.orientation"),
                        set = SimpleSetter(modeKey, "resource.orientation"),
                    },
                    useClass = {
                        type = "toggle",
                        name = "Use Class Color",
                        order = 9,
                        get = SimpleGetter(modeKey, "resource.useClassColor"),
                        set = SimpleSetter(modeKey, "resource.useClassColor"),
                    },
                    usePowerColor = {
                        type = "toggle",
                        name = "Color by Power Type",
                        order = 10,
                        get = SimpleGetter(modeKey, "resource.usePowerColor"),
                        set = SimpleSetter(modeKey, "resource.usePowerColor"),
                    },
                    color = {
                        type = "color",
                        name = "Custom Color",
                        hasAlpha = true,
                        order = 11,
                        hidden = function()
                            local tbl = Fetch(modeKey)
                            return tbl and tbl.resource and (tbl.resource.useClassColor or tbl.resource.usePowerColor)
                        end,
                        get = ColorGetter(modeKey, "resource.color"),
                        set = ColorSetter(modeKey, "resource.color"),
                    },
                    backgroundColor = {
                        type = "color",
                        name = "Background Color",
                        hasAlpha = true,
                        order = 12,
                        get = ColorGetter(modeKey, "resource.backgroundColor"),
                        set = ColorSetter(modeKey, "resource.backgroundColor"),
                    },
                },
            },
            healAbsorbs = {
                type = "group",
                name = "Absorbs",
                order = 55,
                childGroups = "tab",
                args = {
                    heal = {
                        type = "group",
                        name = "Heal Absorb",
                        order = 1,
                        args = {
                            enabled = {
                                type = "toggle",
                                name = "Enable Heal Absorb Layer",
                                order = 1,
                                get = SimpleGetter(modeKey, "healAbsorbs.enabled"),
                                set = SimpleSetter(modeKey, "healAbsorbs.enabled"),
                            },
                            texture = {
                                type = "select",
                                name = "Texture",
                                dialogControl = "LSM30_Statusbar",
                                order = 2,
                                values = GetLSMValues("statusbar"),
                                get = SimpleGetter(modeKey, "healAbsorbs.texture"),
                                set = SimpleSetter(modeKey, "healAbsorbs.texture"),
                            },
                            color = {
                                type = "color",
                                name = "Heal Absorb Color",
                                hasAlpha = true,
                                order = 3,
                                get = ColorGetter(modeKey, "healAbsorbs.color"),
                                set = ColorSetter(modeKey, "healAbsorbs.color"),
                            },
                            anchorPoint = {
                                type = "select",
                                name = "Growth Anchor",
                                order = 4,
                                values = AbsorbAnchorOptions,
                                get = SimpleGetter(modeKey, "healAbsorbs.anchorPoint"),
                                set = SimpleSetter(modeKey, "healAbsorbs.anchorPoint"),
                            },
                        },
                    },
                    damage = {
                        type = "group",
                        name = "Damage Absorb",
                        order = 2,
                        args = {
                            enabled = {
                                type = "toggle",
                                name = "Enable Damage Absorb Layer",
                                order = 1,
                                get = SimpleGetter(modeKey, "damageAbsorbs.enabled"),
                                set = SimpleSetter(modeKey, "damageAbsorbs.enabled"),
                            },
                            texture = {
                                type = "select",
                                name = "Texture",
                                dialogControl = "LSM30_Statusbar",
                                order = 2,
                                values = GetLSMValues("statusbar"),
                                get = SimpleGetter(modeKey, "damageAbsorbs.texture"),
                                set = SimpleSetter(modeKey, "damageAbsorbs.texture"),
                            },
                            color = {
                                type = "color",
                                name = "Damage Absorb Color",
                                hasAlpha = true,
                                order = 3,
                                get = ColorGetter(modeKey, "damageAbsorbs.color"),
                                set = ColorSetter(modeKey, "damageAbsorbs.color"),
                            },
                            anchorPoint = {
                                type = "select",
                                name = "Growth Anchor",
                                order = 4,
                                values = AbsorbAnchorOptions,
                                get = SimpleGetter(modeKey, "damageAbsorbs.anchorPoint"),
                                set = SimpleSetter(modeKey, "damageAbsorbs.anchorPoint"),
                            },
                            hideBlizzardGlow = {
                                type = "toggle",
                                name = "Hide Blizzard Absorb Glow",
                                desc = "Hide Blizzard's absorb glow effects on party/raid frames",
                                order = 5,
                                get = SimpleGetter(modeKey, "damageAbsorbs.hideBlizzardGlow"),
                                set = SimpleSetter(modeKey, "damageAbsorbs.hideBlizzardGlow"),
                            },
                        },
                    },
                },
            },
        },
    }
    return group
end

ns.CreateCompactFrameOptions = BuildOptions

function ns.CreatePartyFrameOptions()
    return BuildOptions("partyFrames", "Party Frames", 45, "party")
end
