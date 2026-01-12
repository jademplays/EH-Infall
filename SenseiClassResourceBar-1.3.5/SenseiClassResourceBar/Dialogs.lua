local _, addonTable = ...

StaticPopupDialogs["SCRB_EXPORT_SETTINGS"] = StaticPopupDialogs["SCRB_EXPORT_SETTINGS"]
    or {
        text = "Export",
        button1 = CLOSE,
        hasEditBox = true,
        editBoxWidth = 320,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

StaticPopupDialogs["SCRB_IMPORT_SETTINGS"] = StaticPopupDialogs["SCRB_IMPORT_SETTINGS"]
    or {
        text = "Import",
        button1 = OKAY,
        button2 = CANCEL,
        hasEditBox = true,
        editBoxWidth = 320,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
StaticPopupDialogs["SCRB_IMPORT_SETTINGS"].OnShow = function(self)
    self:SetFrameStrata("TOOLTIP")
    local editBox = self.editBox or self:GetEditBox()
    editBox:SetText("")
    editBox:SetFocus()
end
StaticPopupDialogs["SCRB_IMPORT_SETTINGS"].EditBoxOnEnterPressed = function(editBox)
    local parent = editBox:GetParent()
    if parent and parent.button1 then parent.button1:Click() end
end