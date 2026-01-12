local ADDON_NAME, ns = ...
local NephUI = ns.Addon

local importBuffer = ""

local function CreateProfileOptions()
    return {
        type = "group",
        name = "Import / Export",
        order = 99,
        args = {
            desc = {
                type  = "description",
                order = 1,
                name  = "Export your current profile as text to share, or paste a string to import.",
            },

            spacer1 = {
                type  = "description",
                order = 2,
                name  = "",
            },

            export = {
                type      = "input",
                name      = "Export Current Profile",
                order     = 10,
                width     = "full",
                multiline = true,
                get       = function()
                    return NephUI:ExportProfileToString()
                end,
                set       = function() end,
            },

            spacer2 = {
                type  = "description",
                order = 19,
                name  = " ",
            },

            import = {
                type      = "input",
                name      = "Import Profile String",
                order     = 20,
                width     = "full",
                multiline = true,
                get       = function()
                    return importBuffer
                end,
                set       = function(_, val)
                    importBuffer = val or ""
                end,
            },

            importButton = {
                type  = "execute",
                name  = "Import",
                order = 30,
                func  = function()
                    local importString = importBuffer
                    
                    -- If buffer is empty, try to get text from the custom GUI
                    if not importString or importString == "" then
                        local configFrame = _G["NephUI_ConfigFrame"]
                        if configFrame and configFrame:IsShown() then
                            -- Try to find the import edit box in the custom GUI
                            local function FindImportEditBox(parent, depth)
                                depth = depth or 0
                                if depth > 15 then return nil end
                                
                                -- Check if this is an EditBox with multiline
                                if type(parent) == "table" and parent.GetObjectType then
                                    local objType = parent:GetObjectType()
                                    if objType == "EditBox" then
                                        -- Check if it's the import box by looking at parent structure
                                        local parentFrame = parent:GetParent()
                                        if parentFrame then
                                            local label = parentFrame.label
                                            if label and label.GetText then
                                                local labelText = label:GetText() or ""
                                                if string.find(labelText:lower(), "import") then
                                                    return parent:GetText() or ""
                                                end
                                            end
                                        end
                                    end
                                end
                                
                                -- Check children
                                if type(parent) == "userdata" and parent.GetChildren then
                                    local children = {parent:GetChildren()}
                                    for _, child in ipairs(children) do
                                        local text = FindImportEditBox(child, depth + 1)
                                        if text then return text end
                                    end
                                end
                                
                                return nil
                            end
                            
                            importString = FindImportEditBox(configFrame, 0) or importBuffer
                        end
                    end
                    
                    -- Trim whitespace
                    if importString then
                        importString = importString:gsub("^%s+", ""):gsub("%s+$", "")
                    end
                    
                    if not importString or importString == "" then
                        print("|cffff0000NephUI: Import failed: No data found. Please paste your import string in the Import Profile String field.|r")
                        return
                    end
                    
                    local ok, err = NephUI:ImportProfileFromString(importString)
                    if ok then
                        print("|cff00ff00NephUI: Profile imported. Please reload your UI.|r")
                        -- Clear the import buffer after successful import
                        importBuffer = ""
                    else
                        print("|cffff0000NephUI: Import failed: " .. (err or "Unknown error") .. "|r")
                    end
                end,
            },
            spacer3 = {
                type  = "description",
                order = 31,
                name  = "|cff00ff00PRESSING THE IMPORT BUTTON WILL OVERWRITE YOUR CURRENT PROFILE|r",
            },
        },
    }
end

ns.CreateProfileOptions = CreateProfileOptions

