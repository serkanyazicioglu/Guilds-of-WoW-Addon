local GOW = GuildsOfWow;
local LootHistory = GOW.LootHistory;
local Store = GOW.LootHistoryStore;
local GoWWishlists = GOW.Wishlists;

local LootHistoryPersonal = {};
GOW.LootHistoryPersonal = LootHistoryPersonal;

local personalEntryCounter = 0;

function LootHistoryPersonal:IsRelevantForHistory(itemId)
    if not GoWWishlists or not GoWWishlists.FindWishlistMatch then return nil end
    return GoWWishlists:FindWishlistMatch(itemId);
end

function LootHistoryPersonal:GenerateSourceEntryId(itemId, timestamp)
    personalEntryCounter = personalEntryCounter + 1;
    return tostring(itemId or 0) .. "-" .. tostring(timestamp or 0) .. "-" .. tostring(personalEntryCounter);
end

function LootHistoryPersonal:MapToCanonical(itemId, itemLink, encounterName, difficulty, difficultyID)
    if not itemId or not itemLink then return nil end

    local entry = LootHistory:NewCanonicalEntry();
    local now = GetServerTime();

    entry.source = LootHistory.SOURCE_PERSONAL;
    entry.sourceEntryId = self:GenerateSourceEntryId(itemId, now);

    local charInfo = GoWWishlists.state and GoWWishlists.state.currentCharInfo;
    if charInfo then
        entry.winner.name = charInfo.name or "";
        entry.winner.realm = charInfo.realmNormalized or "";
        entry.winner.fullName = (charInfo.name or "") .. "-" .. (charInfo.realmNormalized or "");
    end
    entry.winner.isSelf = true;

    local _, classToken = UnitClass("player");
    entry.winner.class = classToken or "";

    LootHistory:PopulateItemFromLink(entry, itemLink);
    entry.item.itemID = itemId;

    entry.encounter.boss = encounterName or "";
    entry.encounter.difficulty = difficulty or "";
    entry.encounter.difficultyID = difficultyID;

    local instanceName, _, _, _, _, _, _, instanceID, instanceGroupSize = GetInstanceInfo();
    entry.encounter.instance = instanceName or "";
    entry.encounter.mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil;
    entry.encounter.groupSize = instanceGroupSize;

    entry.awardedAt = now;

    if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
        entry.season = C_MythicPlus.GetCurrentSeason();
    end

    entry.canonicalId = Store:MakeCanonicalId(entry);

    return entry;
end
