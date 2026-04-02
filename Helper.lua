local Helper = {}
Helper.__index = Helper

local GOW = GuildsOfWow or {};

local roles = {
    [1] = { name = "Tank", iconTexCoords = { 0, 0.296875, 0.296875, 0.61 } },
    [2] = { name = "Healer", iconTexCoords = { 0.296875, 0.59375, 0, 0.296875 } },
    [3] = { name = "DPS", iconTexCoords = { 0.296875, 0.59375, 0.296875, 0.63 } }
};
local factionIcons = {
    Alliance = "Interface\\Icons\\INV_BannerPVP_02",
    Horde = "Interface\\Icons\\INV_BannerPVP_01",
    Neutral = "Interface\\Icons\\Achievement_character_pandaren_female"
};

function Helper:GetRoles()
    return roles;
end

function Helper:GetRole(roleId)
    if (roleId <= 0) then
        return nil;
    end

    return roles[tonumber(roleId or 0)];
end

function Helper:GetFactionIcon(faction)
    if (faction == 1 or faction == "Alliance") then
        return factionIcons.Alliance;
    elseif (faction == 0 or faction == "Horde") then
        return factionIcons.Horde;
    end

    return factionIcons.Neutral;
end

function Helper:GetClassColor(classFileName)
    local classColorSource = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS;
    return classColorSource and classColorSource[classFileName] or nil;
end

function Helper:GetGowGameVersionId()
    if (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) then
        return 1;
    elseif (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) then
        return 2;
    elseif (WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC) then
        return 4;
    else
        return 3;
    end
end

function Helper:GetCurrentRegionByGameVersion()
    local regionId = GetCurrentRegion();

    if (self:GetGowGameVersionId() == 3) then
        return tonumber("4" .. tostring(regionId));
    elseif (self:GetGowGameVersionId() == 2) then
        return tonumber("8" .. tostring(regionId));
    elseif (self:GetGowGameVersionId() == 4) then
        return tonumber("19" .. tostring(regionId));
    end

    return regionId;
end

function Helper:IsInGameCalendarAccessible()
    return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE or WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC;
end

function Helper:IsWishlistsEnabled()
    return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE;
end

function Helper:IsKeystonesEnabled()
    return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE;
end

function Helper:GetCurrentCharacterUniqueKey()
    local name, characterRealm = UnitName("player");
    if (characterRealm == nil) then
        characterRealm = GetNormalizedRealmName();
    end
    return name .. "-" .. characterRealm;
end

function Helper:GetNormalizedCharacterName(name)
    if (not name or name == "") then
        return nil;
    end

    if (string.find(name, "-", 1, true)) then
        return name;
    end

    return name .. "-" .. GetNormalizedRealmName();
end

function Helper:IsInCombat()
    return InCombatLockdown() or UnitAffectingCombat("player");
end

function Helper:IsPlayerCreatedInGameEvent(eventInfo)
    return eventInfo.calendarType == "GUILD_EVENT" or eventInfo.calendarType == "PLAYER";
end

function Helper:IsInGameEventAdmin(eventInfo)
    return eventInfo.modStatus == "CREATOR" or eventInfo.modStatus == "MODERATOR";
end

function Helper:InviteToParty(inviteName)
    if (not IsInRaid() and GetNumGroupMembers() == 5 and C_PartyInfo.AllowedToDoPartyConversion(true)) then
        C_PartyInfo.ConvertToRaid();
    end

    C_PartyInfo.InviteUnit(inviteName);
end

GOW.Helper = Helper;
