local GOW = GuildsOfWow;

local Keystones = {};
GOW.Keystones = Keystones;

local openRaidLib = nil;
local libKeystone = nil;
local libKeystoneData = {};
local openRaidLibKeystoneData = nil;

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
	end

	if (libKeystone) then
		libKeystone.Request("GUILD");
	end
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
