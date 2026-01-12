local ADDON_NAME, ns = ...

function ns.CreateRaidFrameOptions()
    if not ns.CreateCompactFrameOptions then
        error("Party frame options must be loaded before raid options.")
    end
    return ns.CreateCompactFrameOptions("raidFrames", "Raid Frames", 46, "raid")
end
