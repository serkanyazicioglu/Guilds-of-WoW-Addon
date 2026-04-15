local GOW = GuildsOfWow;
local Types = GOW.LootHistoryTypes;
local Store = GOW.LootHistoryStore;
local GoWWishlists = GOW.Wishlists;

local LootHistoryPersonal = {};
GOW.LootHistoryPersonal = LootHistoryPersonal;

local personalEntryCounter = 0;

--- Check whether an item is relevant for personal loot history.
--- Returns the wishlist match entry if relevant, nil otherwise.
--- Uses existing wishlist index: itemId + sourceItemId (tokens) + catalystItemId.
--- @param itemId number
--- @return table|nil wishlistMatch
function LootHistoryPersonal:IsRelevantForHistory(itemId)
    if not GoWWishlists or not GoWWishlists.FindWishlistMatch then return nil end
    return GoWWishlists:FindWishlistMatch(itemId);
end

--- Generate a unique source entry ID for a personal loot record.
--- @param itemId number
--- @param timestamp number
--- @return string
function LootHistoryPersonal:GenerateSourceEntryId(itemId, timestamp)
    personalEntryCounter = personalEntryCounter + 1;
    return "personal-" .. tostring(itemId or 0) .. "-" .. tostring(timestamp or 0) .. "-" .. tostring(personalEntryCounter);
end

--- Map a personal loot event into the canonical entry shape.
--- @param itemId number
--- @param itemLink string
--- @param encounterName string
--- @param difficulty string Difficulty name (e.g. "Heroic")
--- @param difficultyID number
--- @return table|nil canonicalEntry
function LootHistoryPersonal:MapToCanonical(itemId, itemLink, encounterName, difficulty, difficultyID)
    if not itemId or not itemLink then return nil end

    local entry = Types:NewCanonicalEntry();
    local now = GetServerTime();

    -- Source
    entry.source = Types.SOURCE_PERSONAL;
    entry.sourceEntryId = self:GenerateSourceEntryId(itemId, now);
    entry.observedAt = now;

    -- Winner (always self for personal tracking)
    local charInfo = GoWWishlists.state and GoWWishlists.state.currentCharInfo;
    if charInfo then
        entry.winner.name = charInfo.name or "";
        entry.winner.realm = charInfo.realmNormalized or "";
        entry.winner.fullName = (charInfo.name or "") .. "-" .. (charInfo.realmNormalized or "");
    end
    entry.winner.isSelf = true;

    -- Try to get class from player unit
    local _, classToken = UnitClass("player");
    entry.winner.class = classToken or "";

    -- Item
    Types:PopulateItemFromLink(entry, itemLink);
    entry.item.itemID = itemId;

    -- Encounter
    entry.encounter.boss = encounterName or "";
    entry.encounter.difficultyID = difficultyID;

    local instanceName, _, _, _, _, _, _, instanceID, instanceGroupSize = GetInstanceInfo();
    entry.encounter.instance = instanceName or "";
    entry.encounter.mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil;
    entry.encounter.groupSize = instanceGroupSize;

    -- Time
    entry.awardedAt = now;

    -- Season
    if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
        entry.season = C_MythicPlus.GetCurrentSeason();
    end

    -- Lifecycle
    entry.status = "confirmed";
    entry.lastChangedAt = now;

    -- Generate and assign canonical ID
    entry.canonicalId = Store:MakeCanonicalId(entry);

    return entry;
end
