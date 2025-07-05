local GOW = GuildsOfWow;
local Logger = {};
GOW.Logger = Logger;

function Logger:Debug(msg)
    if (GOW.consts.ENABLE_DEBUGGING) then
        Logger:PrintMessage(" [DEBUG] " .. msg);
    end
end

function Logger:PrintMessage(msg, isSummary)
    if GOW.DB and GOW.DB.profile and GOW.DB.profile.onlyShowSummary and not isSummary then
        return
    end
    print(Logger:GetColoredStringWithBranding("ffcc00", msg))
end

function Logger:PrintSuccessMessage(msg)
    print(Logger:GetColoredStringWithBranding("00ff00", msg));
end

function Logger:PrintErrorMessage(msg)
    print(Logger:GetColoredStringWithBranding("ff0000", msg));
end

function Logger:GetColoredStringWithBranding(color, msg)
    return Logger:GetColoredString("00ff00", "Guilds of WoW: ") .. Logger:GetColoredString(color, msg);
end

function Logger:GetColoredString(color, msg)
    local colorString = "|cff";
    return colorString .. color .. msg .. "|r";
end

function Logger:PrintTable(t)
    for key, value in pairs(t) do
        print(key, value);
    end
end
