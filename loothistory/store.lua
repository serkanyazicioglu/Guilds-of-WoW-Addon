local GOW = GuildsOfWow;
local Types = GOW.LootHistoryTypes;

local LootHistoryStore = {};
GOW.LootHistoryStore = LootHistoryStore;

--- Get or lazily initialize the loot history store from SavedVariables.
--- Stored under GOW.DB.profile.guilds[guildKey].lootHistory.
--- @return table|nil The loot history store, or nil if no guild key available
function LootHistoryStore:GetStore()
    if not GOW.DB then return nil end

    local guildKey = GOW.Core:GetGuildKey();
    if not guildKey then return nil end

    local guildData = GOW.DB.profile.guilds[guildKey];
    if not guildData.lootHistory then
        guildData.lootHistory = Types:NewStoreDefaults();
    end

    local store = guildData.lootHistory;

    -- Ensure sub-tables exist (defensive against partial saves)
    if not store.entries then store.entries = {} end
    if not store.ingestion then store.ingestion = {} end
    if not store.ingestion.rclc then
        store.ingestion.rclc = {
            lastScanAt = 0,
            lastImportedEntryId = "",
            lastSessionSeen = "",
            sessionActive = false,
            sessionEndedAt = 0,
        };
    end
    if not store.sync then
        store.sync = {
            uploadState = Types.UPLOAD_IDLE,
            safeToUpload = false,
            lastProcessedAt = 0,
            lastUploadTriggerAt = 0,
            triggerReason = "",
            revision = 0,
            uploaderHasGuildData = false,
        };
    end

    return store;
end

--- Get a single entry by canonical ID.
--- @param canonicalId string
--- @return table|nil
function LootHistoryStore:GetEntry(canonicalId)
    local store = self:GetStore();
    if not store then return nil end
    return store.entries[canonicalId];
end

--- Get all entries (the entries table keyed by canonicalId).
--- @return table
function LootHistoryStore:GetAllEntries()
    local store = self:GetStore();
    if not store then return {} end
    return store.entries;
end

--- Check whether an entry from a given source already exists.
--- @param source string "personal" or "rclc"
--- @param sourceEntryId string
--- @return boolean
function LootHistoryStore:HasEntryBySource(source, sourceEntryId)
    if not source or not sourceEntryId or sourceEntryId == "" then return false end
    local store = self:GetStore();
    if not store then return false end

    for _, entry in pairs(store.entries) do
        if entry.source == source and entry.sourceEntryId == sourceEntryId then
            return true;
        end
    end
    return false;
end

--- Generate a deterministic canonical ID from source + sourceEntryId.
--- @param entry table A canonical entry (must have source and sourceEntryId)
--- @return string
function LootHistoryStore:MakeCanonicalId(entry)
    if not entry then return "" end
    local source = entry.source or "";
    local sourceEntryId = entry.sourceEntryId or "";
    if sourceEntryId ~= "" then
        return source .. "-" .. sourceEntryId;
    end
    -- Fallback to hash if no sourceEntryId
    return source .. "-" .. self:MakeFallbackHash(entry);
end

--- Generate a deterministic fallback hash from stable loot fields.
--- Used when sourceEntryId is unavailable.
--- @param entry table A canonical entry
--- @return string
function LootHistoryStore:MakeFallbackHash(entry)
    if not entry then return "0" end
    local parts = {
        entry.winner and entry.winner.fullName or "",
        entry.item and tostring(entry.item.itemID or "") or "",
        entry.awardedAt and entry.awardedAt.date or "",
        entry.awardedAt and entry.awardedAt.time or "",
        entry.encounter and entry.encounter.boss or "",
        entry.encounter and entry.encounter.instance or "",
    };
    -- Simple string hash: concatenate and compute a numeric hash
    local str = table.concat(parts, "|");
    local hash = 0;
    for i = 1, #str do
        hash = (hash * 31 + string.byte(str, i)) % 2147483647;
    end
    return tostring(hash);
end

--- Check if an entry is a duplicate (by source+sourceEntryId, then fallback hash).
--- @param entry table A canonical entry
--- @return boolean
function LootHistoryStore:IsDuplicate(entry)
    if not entry then return true end

    -- Primary: check source + sourceEntryId
    if entry.source and entry.sourceEntryId and entry.sourceEntryId ~= "" then
        if self:HasEntryBySource(entry.source, entry.sourceEntryId) then
            return true;
        end
    end

    -- Fallback: check canonical ID (which uses fallback hash if no sourceEntryId)
    local canonicalId = self:MakeCanonicalId(entry);
    if canonicalId ~= "" and self:GetEntry(canonicalId) then
        return true;
    end

    return false;
end

--- Persist a canonical entry into the store. Returns true if entry was added, false if duplicate.
--- @param entry table A canonical entry
--- @return boolean
function LootHistoryStore:PersistEntry(entry)
    if not entry then return false end
    local store = self:GetStore();
    if not store then return false end

    if self:IsDuplicate(entry) then
        return false;
    end

    local canonicalId = self:MakeCanonicalId(entry);
    entry.canonicalId = canonicalId;
    entry.lastChangedAt = GetServerTime();

    store.entries[canonicalId] = entry;
    store.updatedAt = GetServerTime();

    GOW.Logger:Debug("LootHistoryStore: Persisted entry " .. canonicalId);
    return true;
end

--- Remove an entry by canonical ID.
--- @param canonicalId string
--- @return boolean true if removed
function LootHistoryStore:RemoveEntry(canonicalId)
    local store = self:GetStore();
    if not store then return false end
    if not store.entries[canonicalId] then return false end

    store.entries[canonicalId] = nil;
    store.updatedAt = GetServerTime();

    GOW.Logger:Debug("LootHistoryStore: Removed entry " .. canonicalId);
    return true;
end

-- ============================================================
-- Sync state management
-- ============================================================

--- Mark the upload state as pending (data changed, not yet ready).
function LootHistoryStore:MarkUploadPending()
    local store = self:GetStore();
    if not store then return end

    store.sync.uploadState = Types.UPLOAD_PENDING;
    store.sync.safeToUpload = false;
end

--- Mark the store as ready for upload.
--- @param reason string One of Types.TRIGGER_* constants
function LootHistoryStore:MarkReadyForUpload(reason)
    local store = self:GetStore();
    if not store then return end

    local now = GetServerTime();
    store.sync.uploadState = Types.UPLOAD_READY;
    store.sync.safeToUpload = true;
    store.sync.lastProcessedAt = now;
    store.sync.lastUploadTriggerAt = now;
    store.sync.triggerReason = reason or "";
    store.sync.revision = (store.sync.revision or 0) + 1;
    store.sync.uploaderHasGuildData = GOW.Wishlists and GOW.Wishlists:HasGuildWishlistData() or false;

    GOW.Logger:Debug("LootHistoryStore: Marked ready for upload (reason=" .. tostring(reason) .. ", rev=" .. tostring(store.sync.revision) .. ")");
end

--- Finalize the store for upload, unless an RCLC session is active.
--- @param reason string One of Types.TRIGGER_* constants
function LootHistoryStore:FinalizeForUpload(reason)
    -- Check RCLC session state — do not finalize during active session
    if GOW.LootHistoryRCLC and GOW.LootHistoryRCLC:IsSessionActive() then
        GOW.Logger:Debug("LootHistoryStore: Skipping finalization, RCLC session is active.");
        return;
    end

    self:MarkReadyForUpload(reason);
end

--- Check whether the store should be re-finalized on startup.
--- @param now number Current server time
--- @return boolean
function LootHistoryStore:ShouldRefreshOnStartup(now)
    local store = self:GetStore();
    if not store then return false end

    local lastProcessed = store.sync.lastProcessedAt or 0;
    if lastProcessed == 0 then return true end
    return (now - lastProcessed) >= Types.STARTUP_REFRESH_THRESHOLD_SECONDS;
end

--- Run store migrations if the schema version has changed.
function LootHistoryStore:MigrateIfNeeded()
    local store = self:GetStore();
    if not store then return end

    -- Currently at version 1 — no migrations needed yet.
    -- Future migrations go here:
    -- if store.version < 2 then ... store.version = 2 end
end
