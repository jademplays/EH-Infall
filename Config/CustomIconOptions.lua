local ADDON_NAME, ns = ...
local NephUI = ns.Addon

local function CreateCustomIconOptions()
    return {
        type = "group",
        name = "Dynamic Icons",
        order = 6,
        args = {
            header = {
                type = "header",
                name = "Dynamic Icons",
                order = 1,
            },
            description = {
                type = "description",
                name = "Build custom spell, item, and equipment-slot trackers. Use the UI below to add icons, configure visuals, and organize groups.",
                order = 2,
            },
            dynamicUI = {
                type = "dynamicIcons",
                name = "Dynamic Icons",
                order = 3,
            },
        },
    }
end

ns.CreateCustomIconOptions = CreateCustomIconOptions

