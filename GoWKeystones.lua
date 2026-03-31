local GOW = GuildsOfWow;

local Keystones = {};
GOW.Keystones = Keystones;

local openRaidLib = nil;
local libKeystone = nil;
local libKeystoneData = {};
local openRaidLibKeystoneData = nil;
local latestEntries = {};

local function RebuildLatestEntries()
	latestEntries = {};

	if (not GOW.Helper:IsKeystonesEnabled()) then
		return;
	end

	local numTotalMembers = GetNumGuildMembers() or 0;
	if (numTotalMembers <= 0 or not C_MythicPlus.IsMythicPlusActive()) then
		return;
	end

	local me = GOW.Helper:GetCurrentCharacterUniqueKey();

	for i = 1, numTotalMembers do
		local name, _, _, level = GetGuildRosterInfo(i);
		if (name) then
			local normalizedName = GOW.Helper:GetNormalizedCharacterName(name);
			local keystoneLevel, keystoneMapId = Keystones:GetGuildMemberKeystone(name, level, normalizedName == me);

			if (keystoneLevel and keystoneMapId) then
				local dungeonName = C_ChallengeMode.GetMapUIInfo(keystoneMapId);

				table.insert(latestEntries, {
					name = name,
					normalizedName = normalizedName,
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

	RebuildLatestEntries();
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

	if (openRaidLib and openRaidLibKeystoneData) then
		for unitName, keystoneInfo in pairs(openRaidLibKeystoneData) do
			if (keystoneInfo.level > 0 and GOW.Helper:GetNormalizedCharacterName(unitName) == normalizedName) then
				GOW.Logger:Debug("Keystone exported frome openRaidLib for " .. normalizedName .. ". Level: " .. keystoneInfo.level);
				return keystoneInfo.level, keystoneInfo.challengeMapID;
			end
		end
	end
end

function Keystones:GetLatestEntries()
	return latestEntries;
end
