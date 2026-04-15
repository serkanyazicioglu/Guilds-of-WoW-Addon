local GOW = GuildsOfWow;
local Types = GOW.LootHistoryTypes;
local Store = GOW.LootHistoryStore;
local GoWWishlists = GOW.Wishlists;

local LootHistoryRCLC = {};
GOW.LootHistoryRCLC = LootHistoryRCLC;

--- Check whether RCLC addon is loaded.
--- @return boolean
function LootHistoryRCLC:IsRCLCAvailable()
    return _G["RCLootCouncil"] ~= nil;
end

--- Check whether an RCLC loot session is currently active.
--- @return boolean
function LootHistoryRCLC:IsSessionActive()
    if not self:IsRCLCAvailable() then return false end
    return _G["RCLootCouncil"].handleLoot == true;
end

--- Get the RCLC loot history database.
--- Returns table keyed by "Name-Realm" → array of entries, or nil.
--- @return table|nil
function LootHistoryRCLC:GetRCLCLootDB()
    if not self:IsRCLCAvailable() then return nil end

    local RCLC = _G["RCLootCouncil"];

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
    end

    return nil;
end

--- Map a single RCLC lootDB entry into the canonical shape.
--- @param playerKey string "Name-Realm" key from the lootDB
--- @param rclcEntry table A single RCLC history entry
--- @return table|nil canonicalEntry
function LootHistoryRCLC:MapToCanonical(playerKey, rclcEntry)
    if not rclcEntry then return nil end

    local entry = Types:NewCanonicalEntry();
    local now = GetServerTime();

    -- Source
    entry.source = Types.SOURCE_RCLC;
    entry.sourceEntryId = rclcEntry.id or "";
    entry.observedAt = now;

    -- Winner — parse "Name-Realm" key
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

    -- Item — parse from lootWon link
    local itemLink = rclcEntry.lootWon;
    if not itemLink or itemLink == "" then return nil end

    Types:PopulateItemFromLink(entry, itemLink);

    -- Award (RCLC-specific rich data)
    entry.award.response = rclcEntry.response or "";
    entry.award.responseID = rclcEntry.responseID;
    entry.award.votes = rclcEntry.votes or 0;
    entry.award.isAwardReason = rclcEntry.isAwardReason or false;
    entry.award.note = rclcEntry.note or "";
    entry.award.owner = rclcEntry.owner or "";
    entry.award.gear1 = rclcEntry.itemReplaced1 or "";
    entry.award.gear2 = rclcEntry.itemReplaced2 or "";

    -- Encounter
    entry.encounter.boss = rclcEntry.boss or "";
    entry.encounter.instance = rclcEntry.instance or "";
    entry.encounter.difficultyID = rclcEntry.difficultyID;
    entry.encounter.mapID = rclcEntry.mapID;
    entry.encounter.groupSize = rclcEntry.groupSize;

    -- Time
    entry.awardedAt.date = rclcEntry.date or "";
    entry.awardedAt.time = rclcEntry.time or "";
    -- Parse unix timestamp from RCLC id format "unix_timestamp-counter"
    if rclcEntry.id then
        entry.awardedAt.unix = tonumber((rclcEntry.id):match("^(%d+)"));
    end

    -- Wishlist matching (only for self)
    if entry.winner.isSelf and entry.item.itemID then
        local wishlistMatch = GoWWishlists.FindWishlistMatch and GoWWishlists:FindWishlistMatch(entry.item.itemID);
        Types:PopulateWishlistMatch(entry, wishlistMatch);
    end

    -- Lifecycle
    entry.status = "confirmed";
    entry.lastChangedAt = now;

    -- Generate canonical ID
    if entry.sourceEntryId == "" then
        entry.sourceEntryId = tostring(Store:MakeFallbackHash(entry));
    end
    entry.canonicalId = Store:MakeCanonicalId(entry);

    return entry;
end

--- Process the full RCLC loot history database.
--- Should only be called when no RCLC session is active.
function LootHistoryRCLC:ProcessRCLCLootHistory()
    if self:IsSessionActive() then return end

    local lootDB = self:GetRCLCLootDB();
    if not lootDB then return end

    local store = Store:GetStore();
    local importCount = 0;

    for playerKey, entries in pairs(lootDB) do
        if type(entries) == "table" then
            for _, rclcEntry in ipairs(entries) do
                -- Skip already-imported entries
                local entryId = rclcEntry.id or "";
                if entryId ~= "" and Store:HasEntryBySource(Types.SOURCE_RCLC, entryId) then
                    -- Already imported, skip
                else
                    local canonical = self:MapToCanonical(playerKey, rclcEntry);
                    if canonical then
                        local persisted = Store:PersistEntry(canonical);
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
    local now = GetServerTime();
    store.ingestion.rclc.lastScanAt = now;
    store.ingestion.rclc.sessionEndedAt = now;
    store.updatedAt = now;

    if importCount > 0 then
        Store:MarkUploadPending();
        GOW.Logger:Debug("LootHistoryRCLC: Imported " .. importCount .. " new entries from RCLC");
    end
end

--- Reconcile personal loot entries that overlap with an RCLC entry.
--- RCLC entries take precedence; matching personal entries are removed.
--- @param rclcEntry table The RCLC canonical entry
function LootHistoryRCLC:ReconcilePersonalOverlaps(rclcEntry)
    if not rclcEntry.winner.isSelf then return end

    local allEntries = Store:GetAllEntries();
    local reconcileWindow = Types.RECONCILE_WINDOW_SECONDS;

    -- Collect IDs first to avoid mutating table during iteration
    local toRemove = {};
    for canonicalId, existingEntry in pairs(allEntries) do
        if existingEntry.source == Types.SOURCE_PERSONAL
            and existingEntry.item.itemID == rclcEntry.item.itemID
            and existingEntry.awardedAt.unix and rclcEntry.awardedAt.unix
            and math.abs(existingEntry.awardedAt.unix - rclcEntry.awardedAt.unix) <= reconcileWindow then
            table.insert(toRemove, canonicalId);
        end
    end

    for _, canonicalId in ipairs(toRemove) do
        Store:RemoveEntry(canonicalId);
        GOW.Logger:Debug("LootHistoryRCLC: Reconciled personal entry " .. canonicalId .. " with RCLC entry");
    end
end
