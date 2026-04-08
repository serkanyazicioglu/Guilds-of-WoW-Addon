local GOW = GuildsOfWow;

local Keystones = {};
GOW.Keystones = Keystones;

local openRaidLib = nil;
local libKeystone = nil;
local libKeystoneData = {};
local openRaidLibKeystoneData = nil;
local openRaidLibKeystoneMap = {};
local latestEntries = {};
local debugKeystoneMapIds = nil;
local rebuildPending = false;

local function GetDisplayRealmName(normalizedRealmName, guid)
	if (guid and GetPlayerInfoByGUID) then
		local _, _, _, _, _, characterName, realmName = GetPlayerInfoByGUID(guid);
		if (characterName and realmName and realmName ~= "") then
			return realmName;
		end
	end

	if (not normalizedRealmName or normalizedRealmName == "") then
		return GetRealmName();
	end

	return normalizedRealmName:gsub("(%l)(%u)", "%1 %2");
end

local function GetDisplayNameParts(fullName)
	local shortName, realm = strsplit("-", fullName or "");

	if (not shortName or shortName == "") then
		shortName = fullName or "";
	end

	if (not realm or realm == "") then
		realm = GetNormalizedRealmName();
	end

	return shortName, realm;
end

local function GetDebugKeystoneMapIds()
	if (debugKeystoneMapIds ~= nil) then
		return debugKeystoneMapIds;
	end

	debugKeystoneMapIds = {};

	if (C_ChallengeMode and C_ChallengeMode.GetMapTable) then
		for _, mapId in ipairs(C_ChallengeMode.GetMapTable() or {}) do
			local dungeonName = C_ChallengeMode.GetMapUIInfo(mapId);
			if (dungeonName and dungeonName ~= "") then
				table.insert(debugKeystoneMapIds, mapId);
			end
		end
	end

	return debugKeystoneMapIds;
end

local function GetRandomDebugKeystone()
	local mapIds = GetDebugKeystoneMapIds();
	if (#mapIds == 0) then
		return nil, nil;
	end

	return math.random(2, 15), mapIds[math.random(1, #mapIds)];
end

local function GetCurrentMaxPlayerLevel()
	if (GetMaxLevelForLatestExpansion) then
		return GetMaxLevelForLatestExpansion();
	end

	return MAX_PLAYER_LEVEL or 80;
end

local function RebuildOpenRaidLibKeystoneMap()
	openRaidLibKeystoneMap = {};

	if (not openRaidLibKeystoneData) then
		return;
	end

	for unitName, keystoneInfo in pairs(openRaidLibKeystoneData) do
		if (keystoneInfo.level and keystoneInfo.level > 0) then
			local normalizedName = GOW.Helper:GetNormalizedCharacterName(unitName);
			if (normalizedName) then
				openRaidLibKeystoneMap[normalizedName] = keystoneInfo;
			end
		end
	end
end

local function RebuildLatestEntries()
	latestEntries = {};

	if (not GOW.Helper:IsKeystonesEnabled()) then
		return;
	end

	RebuildOpenRaidLibKeystoneMap();

	local numTotalMembers = GetNumGuildMembers() or 0;
	if (numTotalMembers <= 0 or not C_MythicPlus.IsMythicPlusActive()) then
		return;
	end

	local me = GOW.Helper:GetCurrentCharacterUniqueKey();
	local playerFaction = UnitFactionGroup("player");
	local maxPlayerLevel = GetCurrentMaxPlayerLevel();

	for i = 1, numTotalMembers do
		local name, _, _, level, className, _, _, _, _, _, classFileName, _, _, _, _, _, guid = GetGuildRosterInfo(i);
		if (name) then
			local normalizedName = GOW.Helper:GetNormalizedCharacterName(name);
			local characterName, realmName = GetDisplayNameParts(name);
			local displayRealmName = GetDisplayRealmName(realmName, guid);
			local keystoneLevel, keystoneMapId = Keystones:GetGuildMemberKeystone(name, level, normalizedName == me);

			if ((not keystoneLevel or not keystoneMapId) and GOW.consts.ENABLE_DEBUGGING and (level or 0) >= maxPlayerLevel) then
				keystoneLevel, keystoneMapId = GetRandomDebugKeystone();
			end

			if (keystoneLevel and keystoneMapId) then
				local dungeonName = C_ChallengeMode.GetMapUIInfo(keystoneMapId);
				local classId = nil;
				if (classFileName and GetNumClasses and GetClassInfo) then
					for classIndex = 1, GetNumClasses() do
						local _, currentClassFileName, currentClassId = GetClassInfo(classIndex);
						if (currentClassFileName == classFileName) then
							classId = currentClassId or classIndex;
							break;
						end
					end
				end;

				table.insert(latestEntries, {
					name = characterName,
					realm = displayRealmName,
					fullName = name,
					normalizedName = normalizedName,
					className = className,
					classFileName = classFileName,
					classId = classId,
					faction = playerFaction,
					keystoneLevel = keystoneLevel,
					keystoneMapId = keystoneMapId,
					dungeonName = dungeonName or "Unknown",
					date = GetServerTime()
				});
			end
		end
	end

	table.sort(latestEntries, function(a, b)
		if ((a.keystoneLevel or 0) ~= (b.keystoneLevel or 0)) then
			return (a.keystoneLevel or 0) > (b.keystoneLevel or 0);
		end

		return string.lower(a.name or "") < string.lower(b.name or "");
	end);
end

local function ScheduleRebuild()
	if (rebuildPending) then return end

	rebuildPending = true;
	C_Timer.After(0.5, function()
		rebuildPending = false;
		RebuildLatestEntries();
	end);
end

local function UpdateLibKeystoneEntry(keyLevel, keyChallengeMapID, playerRating, playerName, channel)
	if (channel ~= "GUILD") then
		return;
	end

	if (not keyLevel or keyLevel == 0) then
		return;
	end

	local normalizedName = GOW.Helper:GetNormalizedCharacterName(playerName);
	if (not normalizedName) then
		return;
	end

	libKeystoneData[normalizedName] = {
		level = keyLevel,
		challengeMapID = keyChallengeMapID
	};

	ScheduleRebuild();
end

function Keystones:Initialize()
	if (not GOW.Helper:IsKeystonesEnabled()) then
		return;
	end

	openRaidLib = LibStub:GetLibrary("LibOpenRaid-1.0");
	libKeystone = LibStub:GetLibrary("LibKeystone", true);

	if (openRaidLib) then
		openRaidLib.RequestKeystoneDataFromGuild();
	end

	if (libKeystone) then
		libKeystone.Register(Keystones, UpdateLibKeystoneEntry);
		libKeystone.Request("GUILD");
	end
end

function Keystones:Refresh()
	if (openRaidLib) then
		openRaidLibKeystoneData = openRaidLib.GetAllKeystonesInfo();
		openRaidLib.RequestKeystoneDataFromGuild();
	end

	if (libKeystone) then
		libKeystone.Request("GUILD");
	end

	RebuildLatestEntries();
end

function Keystones:GetGuildMemberKeystone(name, level, isSelf)
	local normalizedName = GOW.Helper:GetNormalizedCharacterName(name);
	if (not normalizedName) then
		return nil;
	end

	if (isSelf) then
		return C_MythicPlus.GetOwnedKeystoneLevel(), C_MythicPlus.GetOwnedKeystoneChallengeMapID();
	end

	if (C_AddOns.IsAddOnLoaded("AstralKeys") and AstralKeys) then
		if (level >= _G["AstralEngine"].EXPANSION_LEVEL) then
			local keystoneLevel = _G["AstralEngine"].GetCharacterKeyLevel(name);
			local keystoneMapId = _G["AstralEngine"].GetCharacterMapID(name);

			if (keystoneLevel) then
				GOW.Logger:Debug("Keystone exported frome AstralKeys for " .. normalizedName .. ". Level: " .. keystoneLevel);
				return keystoneLevel, keystoneMapId;
			end
		end
	end

	if (libKeystone) then
		local keystoneInfo = libKeystoneData[normalizedName];
		if (keystoneInfo) then
			GOW.Logger:Debug("Keystone exported frome LibKeystone for " .. normalizedName .. ". Level: " .. keystoneInfo.level);
			return keystoneInfo.level, keystoneInfo.challengeMapID;
		end
	end

	if (openRaidLib and openRaidLibKeystoneMap) then
		local keystoneInfo = openRaidLibKeystoneMap[normalizedName];
		if (keystoneInfo and keystoneInfo.level and keystoneInfo.level > 0) then
			GOW.Logger:Debug("Keystone exported frome openRaidLib for " .. normalizedName .. ". Level: " .. keystoneInfo.level);
			return keystoneInfo.level, keystoneInfo.challengeMapID;
		end
	end
end

function Keystones:GetLatestEntries()
	return latestEntries;
end
