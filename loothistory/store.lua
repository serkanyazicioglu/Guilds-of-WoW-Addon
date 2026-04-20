local GOW = GuildsOfWow;

local LootHistoryStore = {};
GOW.LootHistoryStore = LootHistoryStore;

local STORE_VERSION = "1.0.0";
local STARTUP_REFRESH_THRESHOLD_SECONDS = 3600;

--- Get or lazily initialize the loot history store from SavedVariables.
--- Stored under GOW.DB.profile.guilds[guildKey].lootHistory.
--- @return table|nil The loot history store, or nil if no guild key available
function LootHistoryStore:GetStore()
    if not GOW.DB then return nil end

    local guildKey = GOW.Core:GetGuildKey();
    if not guildKey then return nil end

    local guildData = GOW.DB.profile.guilds[guildKey];
    if not guildData.lootHistory then
        guildData.lootHistory = LootHistoryStore:NewStoreDefaults();
    end

    local store = guildData.lootHistory;

    -- Ensure sub-tables exist (defensive against partial saves)
    if not store.entries then store.entries = {} end
    if not store.ingestion then store.ingestion = {} end
    if not store.ingestion.rclc then
        store.ingestion.rclc = { lastScannedAt = 0 };
    else
        -- Normalize to expected shape, stripping stale keys
        store.ingestion.rclc = {
            lastScannedAt = store.ingestion.rclc.lastScannedAt or store.ingestion.rclc.lastScanAt or 0,
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
        entry.awardedAt or 0,
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

    store.entries[canonicalId] = entry;

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

    GOW.Logger:Debug("LootHistoryStore: Removed entry " .. canonicalId);
    return true;
end

-- ============================================================
-- Startup check
-- ============================================================

--- Check whether the store should re-scan RCLC on startup.
--- @param now number Current server time
--- @return boolean
function LootHistoryStore:ShouldRefreshOnStartup(now)
    local store = self:GetStore();
    if not store then return false end

    local lastScanned = store.ingestion.rclc.lastScannedAt or 0;
    if lastScanned == 0 then return true end
    return (now - lastScanned) >= STARTUP_REFRESH_THRESHOLD_SECONDS;
end

--- Create the default loot history store structure.
--- @return table
function LootHistoryStore:NewStoreDefaults()
    return {
        version = STORE_VERSION,
        entries = {},

        ingestion = {
            rclc = {
                lastScannedAt = 0,
            },
        },
    };
end

