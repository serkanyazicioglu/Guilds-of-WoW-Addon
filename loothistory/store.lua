local GOW = GuildsOfWow;

local LootHistoryStore = {};
GOW.LootHistoryStore = LootHistoryStore;

local STORE_VERSION = "1.0.0";
local STARTUP_REFRESH_THRESHOLD_SECONDS = 3600;

function LootHistoryStore:GetStore()
    if not GOW.DB then return nil end

    local guildKey = GOW.Core:GetGuildKey();
    if not guildKey then return nil end

    local guildData = GOW.DB.profile.guilds[guildKey];
    if not guildData.lootHistory then
        guildData.lootHistory = LootHistoryStore:NewStoreDefaults();
    end

    local store = guildData.lootHistory;

    if not store.entries then store.entries = {} end
    if not store.ingestion then store.ingestion = {} end
    if not store.ingestion.rclc then store.ingestion.rclc = { lastScannedAt = 0 } end

    return store;
end

function LootHistoryStore:GetEntry(canonicalId)
    local store = self:GetStore();
    if not store then return nil end
    return store.entries[canonicalId];
end

function LootHistoryStore:GetAllEntries()
    local store = self:GetStore();
    if not store then return {} end
    return store.entries;
end

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

function LootHistoryStore:MakeCanonicalId(entry)
    if not entry then return "" end
    local source = entry.source or "";
    local sourceEntryId = entry.sourceEntryId or "";
    if sourceEntryId ~= "" then
        return source .. "-" .. sourceEntryId;
    end

    return source .. "-" .. self:MakeFallbackHash(entry);
end

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

function LootHistoryStore:SaveDropEntry(entry)
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

function LootHistoryStore:RemoveDropEntry(canonicalId)
    local store = self:GetStore();
    if not store then return false end
    if not store.entries[canonicalId] then return false end

    store.entries[canonicalId] = nil;

    GOW.Logger:Debug("LootHistoryStore: Removed entry " .. canonicalId);
    return true;
end

function LootHistoryStore:ShouldRefreshOnStartup(now)
    local store = self:GetStore();
    if not store then return false end

    local lastScanned = store.ingestion.rclc.lastScannedAt or 0;
    if lastScanned == 0 then return true end
    return (now - lastScanned) >= STARTUP_REFRESH_THRESHOLD_SECONDS;
end

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

