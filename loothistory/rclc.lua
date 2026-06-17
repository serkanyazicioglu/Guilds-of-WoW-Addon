local GOW = GuildsOfWow;
local LootHistory = GOW.LootHistory;
local Store = GOW.LootHistoryStore;
local GoWWishlists = GOW.Wishlists;

local LootHistoryRCLC = {};
GOW.LootHistoryRCLC = LootHistoryRCLC;

local RECONCILE_WINDOW_SECONDS = 300;
local SEASON_LOOKBACK_SECONDS = 43200; -- 12 hrs

function LootHistoryRCLC:GetRCLCGlobal()
    return _G["RCLootCouncil"] or _G["RCLootCouncil_Classic"];
end

function LootHistoryRCLC:IsRCLCAvailable()
    return self:GetRCLCGlobal() ~= nil;
end

function LootHistoryRCLC:IsSessionActive()
    local RCLC = self:GetRCLCGlobal();
    if not RCLC then return false end
    return RCLC.handleLoot == true;
end

function LootHistoryRCLC:GetRCLCLootDB()
    local RCLC = self:GetRCLCGlobal();
    if not RCLC then return nil end

    -- Preferred: public API
    if RCLC.GetHistoryDB then
        local ok, db = pcall(RCLC.GetHistoryDB, RCLC);
        if ok and db then return db end
    end

    -- Fallback: navigate module structure
    if RCLC.GetModule then
        local ok, histModule = pcall(RCLC.GetModule, RCLC, "RCLootHistory", true);
        if ok and histModule and histModule.db and histModule.db.factionrealm then
            return histModule.db.factionrealm;
        end
        if ok and not histModule then
            GOW.Logger:Debug("LootHistoryRCLC: RCLC.GetModule('RCLootHistory') returned nil. RCLC import unavailable.");
        end
    end

    return nil;
end

function LootHistoryRCLC:MapToCanonical(playerKey, rclcEntry)
    if not rclcEntry then return nil end

    local entry = LootHistory:NewCanonicalEntry();

    entry.source = LootHistory.SOURCE_RCLC;
    entry.sourceEntryId = rclcEntry.id or "";

    entry.winner.fullName = playerKey or "";
    if playerKey then
        local name, realm = playerKey:match("^(.-)%-(.+)$");
        entry.winner.name = name or playerKey;
        entry.winner.realm = realm or "";
    end
    entry.winner.class = rclcEntry.class or "";

    -- Determine isSelf
    local charInfo = GoWWishlists.state and GoWWishlists.state.currentCharInfo;
    if charInfo then
        local selfKey = (charInfo.name or "") .. "-" .. (charInfo.realmNormalized or "");
        entry.winner.isSelf = (playerKey == selfKey);
    else
        entry.winner.isSelf = false;
    end

    local itemLink = rclcEntry.lootWon;
    if not itemLink or itemLink == "" then return nil end

    LootHistory:PopulateItemFromLink(entry, itemLink);

    entry.award.response = rclcEntry.response or "";
    entry.award.responseID = rclcEntry.responseID;
    entry.award.votes = rclcEntry.votes or 0;
    entry.award.isAwardReason = rclcEntry.isAwardReason or false;
    entry.award.note = rclcEntry.note or "";
    entry.award.owner = rclcEntry.owner or "";
    entry.award.itemReplaced1 = rclcEntry.itemReplaced1 or "";
    entry.award.itemReplaced2 = rclcEntry.itemReplaced2 or "";

    entry.encounter.boss = rclcEntry.boss or "";
    entry.encounter.instance = rclcEntry.instance or "";
    entry.encounter.difficultyID = rclcEntry.difficultyID;
    if rclcEntry.difficultyID and GetDifficultyInfo then
        entry.encounter.difficulty = GetDifficultyInfo(rclcEntry.difficultyID) or "";
    end
    entry.encounter.mapID = rclcEntry.mapID;
    entry.encounter.groupSize = rclcEntry.groupSize;

    entry.rclc = {
        color = rclcEntry.color,
        tierToken = rclcEntry.tierToken or false,
        iClass = rclcEntry.iClass,
        iSubClass = rclcEntry.iSubClass,
    };

    -- RCLC entry IDs are formatted as "{unixTimestamp}-{sessionId}-{entryIndex}"
    -- e.g. "1703001234-1-5". Extract the leading timestamp for awardedAt.
    if rclcEntry.id then
        entry.awardedAt = tonumber((rclcEntry.id):match("^(%d+)")) or 0;
    end

    if entry.awardedAt > 0 and C_MythicPlus and C_MythicPlus.GetCurrentSeason then
        local age = GetServerTime() - entry.awardedAt;
        if age <= SEASON_LOOKBACK_SECONDS then
            entry.season = C_MythicPlus.GetCurrentSeason();
        end
    end

    -- If RCLC entry has no id, sourceEntryId remains ""; SaveDropEntry will reject it.
    entry.canonicalId = Store:MakeCanonicalId(entry);

    return entry;
end

function LootHistoryRCLC:ProcessRCLCLootHistory()
    if self:IsSessionActive() then return end

    local lootDB = self:GetRCLCLootDB();
    if not lootDB then return end

    local store = Store:EnsureStore();
    if not store then return end

    local importCount = 0;

    for playerKey, entries in pairs(lootDB) do
        if type(entries) == "table" then
            for _, rclcEntry in ipairs(entries) do
                local entryId = rclcEntry.id or "";
                if entryId ~= "" and Store:GetEntry(LootHistory.SOURCE_RCLC .. "-" .. entryId) then
                    -- Already imported, skip
                else
                    local canonical = self:MapToCanonical(playerKey, rclcEntry);
                    if canonical then
                        local persisted = Store:SaveDropEntry(canonical);
                        if persisted then
                            importCount = importCount + 1;
                            -- Reconcile: if self loot, remove any personal duplicate
                            if canonical.winner.isSelf then
                                self:ReconcilePersonalOverlaps(canonical);
                            end
                        end
                    end
                end
            end
        end
    end

    -- Update ingestion metadata
    store.ingestion.rclc.lastScannedAt = GetServerTime();

    if importCount > 0 then
        GOW.Logger:Debug("LootHistoryRCLC: Imported " .. importCount .. " new entries from RCLC");
    end
end

function LootHistoryRCLC:ReconcilePersonalOverlaps(rclcEntry)
    if not rclcEntry.winner.isSelf then return end

    local itemID = rclcEntry.item.itemID;
    if not itemID then return end

    local allEntries = Store:GetAllEntries();
    local reconcileWindow = RECONCILE_WINDOW_SECONDS;

    for canonicalId, existingEntry in pairs(allEntries) do
        if existingEntry.source == LootHistory.SOURCE_PERSONAL
            and existingEntry.item.itemID == itemID
            and existingEntry.awardedAt and rclcEntry.awardedAt
            and math.abs(existingEntry.awardedAt - rclcEntry.awardedAt) <= reconcileWindow then
            Store:RemoveDropEntry(canonicalId);
            GOW.Logger:Debug("LootHistoryRCLC: Reconciled personal entry " .. canonicalId .. " with RCLC entry");
            return  -- at most one personal entry will match per RCLC entry
        end
    end
end
