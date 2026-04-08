local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local ns = select(2, ...);

function GoWWishlists:Initialize()
    if not ns.WISHLISTS then GOW.Logger:Debug("No wishlist data found. Skipping wishlist initialization.") return end

    self.state.compactMode = GOW.DB and GOW.DB.profile and GOW.DB.profile.wishlistCompactMode or false;
    self:BuildWishlistIndex();
    self:HandleLootDropEvents();
    -- self:HandleLootHistoryEvents();
    self:HandleLootInfoEvents();

    GOW.Logger:Debug("Wishlist module initialized.");
end

function GoWWishlists:HandleLootInfoEvents()
    local itemInfoFrame = CreateFrame("Frame");
    itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED");

    itemInfoFrame:SetScript("OnEvent", function(_, event, itemId, success)
        if event == "GET_ITEM_INFO_RECEIVED" and success then
            self:OnItemInfoReceived(itemId);
        end
    end);
end

function GoWWishlists:HandleLootDropEvents()
    local lootFrame = CreateFrame("Frame");
    lootFrame:RegisterEvent("START_LOOT_ROLL");

    lootFrame:SetScript("OnEvent", function(self, event, rollID)
        if event == "START_LOOT_ROLL" then
            GoWWishlists:OnStartLootRoll(rollID);
        end
    end);
end

function GoWWishlists:HandleLootHistoryEvents()
    local lootHistoryFrame = CreateFrame("Frame");
    lootHistoryFrame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP");
    lootHistoryFrame:RegisterEvent("LOOT_HISTORY_UPDATE_ENCOUNTER");

    lootHistoryFrame:SetScript("OnEvent", function(_, event, encounterID, lootListID)
        if event == "LOOT_HISTORY_UPDATE_DROP" and encounterID and lootListID then
            GoWWishlists:ProcessLootHistoryDrop(encounterID, lootListID);
        elseif event == "LOOT_HISTORY_UPDATE_ENCOUNTER" and encounterID then
            GoWWishlists:ProcessLootHistoryEncounter(encounterID);
        end
    end);
end

function GoWWishlists:RecordLootHistory(itemId, itemLink, encounterName, difficulty, timestamp)
    if not GOW.DB or not GOW.DB.profile then return end

    local history = GOW.DB.profile.lootHistory;
    if not history then
        GOW.DB.profile.lootHistory = {};
        history = GOW.DB.profile.lootHistory;
    end

    table.insert(history, {
        itemId = itemId,
        itemLink = itemLink,
        encounterName = encounterName,
        difficulty = difficulty,
        timestamp = timestamp or GetServerTime(),
    });

end

function GoWWishlists:RecordAllLootDrop(itemId, itemLink, encounterName, difficulty, winnerName, timestamp)
    if not GOW.DB or not GOW.DB.profile then return end

    local allHistory = GOW.DB.profile.allLootHistory;
    if not allHistory then
        GOW.DB.profile.allLootHistory = {};
        allHistory = GOW.DB.profile.allLootHistory;
    end

    table.insert(allHistory, {
        itemId = itemId,
        itemLink = itemLink,
        encounterName = encounterName,
        difficulty = difficulty,
        winner = winnerName or "Unknown",
        timestamp = timestamp or GetServerTime(),
    });

end

function GoWWishlists:IsLootRecorded(history, itemId, encounterName, matchKey, matchValue)
    for _, record in ipairs(history) do
        if record.itemId == itemId and record.encounterName == encounterName
            and (not matchKey or record[matchKey] == matchValue)
            and record.timestamp and (GetServerTime() - record.timestamp) < 300 then
            return true;
        end
    end
    return false;
end

function GoWWishlists:IsAllLootAlreadyRecorded(itemId, encounterName, winnerName)
    local allHistory = GOW.DB and GOW.DB.profile and GOW.DB.profile.allLootHistory or {};
    return self:IsLootRecorded(allHistory, itemId, encounterName, "winner", winnerName);
end

function GoWWishlists:MarkWishlistObtained(itemId, difficulty)
    for _, entry in ipairs(self.state.allItems) do
        if entry.itemId == itemId
            and (not difficulty or entry.difficulty == difficulty)
            and not entry.isObtained then
            entry.isObtained = true;
            GOW.Logger:Debug("Wishlist item marked obtained: " .. tostring(itemId) .. " (" .. tostring(entry.difficulty) .. ")");

            local indexed = self.state.wishlistIndex[itemId];
            if indexed then
                for i = #indexed, 1, -1 do
                    if indexed[i] == entry then
                        table.remove(indexed, i);
                        break;
                    end
                end
                if #indexed == 0 then
                    self.state.wishlistIndex[itemId] = nil;
                end
            end

            local crossKey = (entry.itemId == itemId) and entry.sourceItemId or entry.itemId;
            if crossKey then
                local crossList = self.state.wishlistIndex[crossKey];
                if crossList then
                    for j = #crossList, 1, -1 do
                        if crossList[j] == entry then
                            table.remove(crossList, j);
                            break;
                        end
                    end
                    if #crossList == 0 then
                        self.state.wishlistIndex[crossKey] = nil;
                    end
                end
            end

            return true;
        end
    end

    return false;
end

function GoWWishlists:ProcessDropInfo(dropInfo, encounterID, encounterName, difficulty)
    if not dropInfo then return end

    local itemLink = dropInfo.itemHyperlink;
    if not itemLink then return end

    local itemId = tonumber(itemLink:match("item:(%d+)"));
    if not itemId then return end

    if not encounterName then
        local encounterInfo = C_LootHistory.GetInfoForEncounter(encounterID);
        encounterName = encounterInfo and encounterInfo.encounterName or "Unknown";
    end
    if not difficulty then
        difficulty = self:GetCurrentDifficultyName();
    end

    local winner = dropInfo.winner;
    local winnerName = winner and (winner.name or winner.playerName) or nil;

    if winnerName and not self:IsAllLootAlreadyRecorded(itemId, encounterName, winnerName) then
        self:RecordAllLootDrop(itemId, itemLink, encounterName, difficulty, winnerName);
    end

    if winner and winner.isSelf then
        GOW.Logger:Debug(string.format("Player won item %s (%d) from %s", itemLink, itemId, encounterName));

        local history = GOW.DB and GOW.DB.profile and GOW.DB.profile.lootHistory or {};
        local alreadyRecorded = self:IsLootRecorded(history, itemId, encounterName);

        if not alreadyRecorded then
            self:RecordLootHistory(itemId, itemLink, encounterName, difficulty);
            local wasOnWishlist = self:MarkWishlistObtained(itemId, difficulty);
            if wasOnWishlist then
                GOW.Logger:PrintSuccessMessage(itemLink .. " obtained! Removed from your wishlist.");
            end
        end
    end

    return winnerName ~= nil; -- true if winner was resolved
end

function GoWWishlists:ProcessLootHistoryDrop(encounterID, lootListID)
    if not C_LootHistory or not C_LootHistory.GetSortedInfoForDrop then return end

    local dropInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID);
    local resolved = self:ProcessDropInfo(dropInfo, encounterID);

    -- If winner isn't known yet (rolls in progress), retry after rolls end (~30s)
    if not resolved and dropInfo and dropInfo.itemHyperlink then
        C_Timer.After(32, function()
            local retryInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID);
            self:ProcessDropInfo(retryInfo, encounterID);
        end);
    end
end

function GoWWishlists:ProcessLootHistoryEncounter(encounterID)
    if not C_LootHistory or not C_LootHistory.GetSortedDropsForEncounter then return end

    local drops = C_LootHistory.GetSortedDropsForEncounter(encounterID);
    if not drops then return end

    -- GetSortedDropsForEncounter returns {lootListID, itemHyperlink} per entry
    -- but does NOT include winner info. Use GetSortedInfoForDrop per drop for full details.
    local encounterInfo = C_LootHistory.GetInfoForEncounter(encounterID);
    local encounterName = encounterInfo and encounterInfo.encounterName or "Unknown";
    local difficulty = self:GetCurrentDifficultyName();

    for _, dropEntry in ipairs(drops) do
        if dropEntry.lootListID and C_LootHistory.GetSortedInfoForDrop then
            local dropInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, dropEntry.lootListID);
            self:ProcessDropInfo(dropInfo, encounterID, encounterName, difficulty);
        end
    end
end

function GoWWishlists:GetRaidNameForEncounter(journalEncounterId)
    if not journalEncounterId then return nil end
    local cached = self.state.raidNameCache[journalEncounterId];
    if cached ~= nil then
        return cached or nil;
    end

    if EJ_GetEncounterInfo then
        local _, _, _, _, _, journalInstanceID = EJ_GetEncounterInfo(journalEncounterId);
        if journalInstanceID and EJ_GetInstanceInfo then
            local instanceName = EJ_GetInstanceInfo(journalInstanceID);
            self.state.raidNameCache[journalEncounterId] = instanceName or false;
            return instanceName;
        end
    end

    self.state.raidNameCache[journalEncounterId] = false;
    return nil;
end

function GoWWishlists:CollectWishlistForCharacter(difficultyFilter)
    local bossGroups = {};
    local bossOrder = {};
    local unknownItems = {};
    local bossToRaid = {};
    local bossToJournalId = {};

    for _, entry in ipairs(self.state.allItems) do
        if not entry.isObtained then
            local passFilter = (not difficultyFilter or difficultyFilter == "All") or (entry.difficulty == difficultyFilter);
            if passFilter then
                local bossName = entry.sourceBossName;
                if bossName then
                    if not bossGroups[bossName] then
                        bossGroups[bossName] = {};
                        table.insert(bossOrder, bossName);
                        if entry.sourceJournalId then
                            bossToRaid[bossName] = self:GetRaidNameForEncounter(entry.sourceJournalId);
                            bossToJournalId[bossName] = entry.sourceJournalId;
                        end
                    end
                    table.insert(bossGroups[bossName], entry);
                else
                    table.insert(unknownItems, entry);
                end
            end
        end
    end

    return bossGroups, bossOrder, unknownItems, bossToRaid, bossToJournalId;
end

function GoWWishlists:SimulateLootDrops(count)
    if not ns.WISHLISTS then
        GOW.Logger:PrintErrorMessage("No wishlist data found.");
        return;
    end

    -- Pool only personal wishlist items
    local pool = {};
    local personalLists = ns.WISHLISTS.personalWishlists;
    if personalLists then
        for _, charEntry in ipairs(personalLists) do
            for _, item in ipairs(charEntry.wishlist) do
                if not item.isObtained then
                    table.insert(pool, item);
                end
            end
        end
    end

    if #pool == 0 then
        GOW.Logger:PrintMessage("No personal wishlist items available to simulate.");
        return;
    end

    -- Group items by itemId+difficulty
    local groups = {};
    local groupOrder = {};
    for _, item in ipairs(pool) do
        local key = item.itemId .. ":" .. (item.difficulty or "");
        if not groups[key] then
            groups[key] = {};
            table.insert(groupOrder, key);
        end
        table.insert(groups[key], item);
    end

    -- Sort: Mythic first, then groups with duplicates first
    table.sort(groupOrder, function(a, b)
        local aIsMythic = a:match(":Mythic$") and 1 or 0;
        local bIsMythic = b:match(":Mythic$") and 1 or 0;
        if aIsMythic ~= bIsMythic then return aIsMythic > bIsMythic end
        local aCount = #groups[a];
        local bCount = #groups[b];
        if aCount ~= bCount then return aCount > bCount end
        return false;
    end);

    count = math.min(count, #groupOrder);

    GOW.Logger:PrintMessage("Simulating " .. count .. " loot drop(s) from personal wishlist...");

    for i = 1, count do
        local key = groupOrder[i];
        local items = groups[key];
        local delay = (i - 1) * 0.3;
        C_Timer.After(delay, function()
            for _, item in ipairs(items) do
                self:ShowWishlistInfoFrame(item, nil);
            end
        end);
    end
end

function GoWWishlists:HandleSlashCommand()
    self:ShowWishlistBrowserFrame();
end
