local ADDON_NAME, ns = ...
local NephUI = ns.Addon

-- Create namespace
NephUI.AutoUIScale = NephUI.AutoUIScale or {}
local AutoUIScale = NephUI.AutoUIScale

function AutoUIScale:SetUIScale(scale)
    if scale and type(scale) == "number" and UIParent then
        -- Only set UIParent scale, don't touch the CVar to avoid conflicts with edit mode
        -- The CVar is managed by WoW's built-in UI scale system, we just override the visual scale
        UIParent:SetScale(scale)
    end
end

function AutoUIScale:ApplySavedScale()
    -- Check if we have a saved UI scale value
    -- If the user has previously set a UI scale (via confirm button or preset buttons), apply it
    -- If no saved value exists (first load), do nothing - preserve their current UI scale
    if NephUI and NephUI.db and NephUI.db.profile and NephUI.db.profile.general then
        local savedScale = NephUI.db.profile.general.uiScale
        if savedScale and type(savedScale) == "number" then
            -- Apply immediately without delay to avoid breaking edit mode anchors
            -- Edit mode reads anchor positions early, so we need the scale set before that
            AutoUIScale:SetUIScale(savedScale)
        end
        -- If savedScale is nil, do nothing - this is the first load, preserve their current scale
    end
end

function AutoUIScale:Initialize()
    -- Apply saved scale immediately
    self:ApplySavedScale()
    
    -- Also register for PLAYER_LOGIN to apply it as early as possible
    -- This ensures the scale is set before edit mode initializes
    if not self.loginHandlerRegistered then
        self.loginHandlerRegistered = true
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_LOGIN")
        frame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_LOGIN" then
                AutoUIScale:ApplySavedScale()
                self:UnregisterEvent("PLAYER_LOGIN")
            end
        end)
    end
end

