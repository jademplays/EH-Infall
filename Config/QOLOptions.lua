local ADDON_NAME, ns = ...
local NephUI = ns.Addon

local function CreateQOLOptions()
    return {
        type = "group",
        name = "QoL",
        order = 2.7,
        args = {
            header = {
                type = "header",
                name = "Quality of Life",
                order = 1,
            },
            characterPanel = {
                type = "toggle",
                name = "Character Panel Enhancements",
                desc = "Show item level, enchants, missing enchants, sockets, and durability on character and inspect frames.",
                width = "full",
                order = 1.5,
                get = function()
                    local db = NephUI.db and NephUI.db.profile and NephUI.db.profile.qol
                    if not db then
                        return true
                    end
                    if db.characterPanel == nil then
                        return true
                    end
                    return db.characterPanel
                end,
                set = function(_, val)
                    if not NephUI.db or not NephUI.db.profile then
                        return
                    end
                    NephUI.db.profile.qol = NephUI.db.profile.qol or {}
                    NephUI.db.profile.qol.characterPanel = val
                    if NephUI.CharacterPanel and NephUI.CharacterPanel.Refresh then
                        NephUI.CharacterPanel:Refresh()
                    end
                end,
            },
            hideBagsBar = {
                type = "toggle",
                name = "Hide Bags Bar",
                desc = "Hide the default Bags Bar frame.",
                width = "full",
                order = 2,
                get = function()
                    local db = NephUI.db and NephUI.db.profile and NephUI.db.profile.qol
                    return db and db.hideBagsBar or false
                end,
                set = function(_, val)
                    if not NephUI.db or not NephUI.db.profile then
                        return
                    end
                    NephUI.db.profile.qol = NephUI.db.profile.qol or {}
                    NephUI.db.profile.qol.hideBagsBar = val
                    if NephUI.QOL and NephUI.QOL.Refresh then
                        NephUI.QOL:Refresh()
                    end
                end,
            },
            tooltipIDs = {
                type = "toggle",
                name = "Show Tooltip IDs",
                desc = "Show spell, item, unit, quest, and other IDs in tooltips.",
                width = "full",
                order = 3,
                get = function()
                    local db = NephUI.db and NephUI.db.profile and NephUI.db.profile.qol
                    return db and db.tooltipIDs or false
                end,
                set = function(_, val)
                    if not NephUI.db or not NephUI.db.profile then
                        return
                    end
                    NephUI.db.profile.qol = NephUI.db.profile.qol or {}
                    NephUI.db.profile.qol.tooltipIDs = val
                    if NephUI.QOL and NephUI.QOL.Refresh then
                        NephUI.QOL:Refresh()
                    end
                end,
            },
        },
    }
end

ns.CreateQOLOptions = CreateQOLOptions


