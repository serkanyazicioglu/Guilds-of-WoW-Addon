local GOW = GuildsOfWow;

local LootHistoryStore = {};
GOW.LootHistoryStore = LootHistoryStore;

local STORE_VERSION = "1.0.0";
local STARTUP_REFRESH_THRESHOLD_SECONDS = 3600;

function LootHistoryStore:EnsureStore()
    if not GOW.DB then
        GOW.Logger:Debug("LootHistoryStore: EnsureStore failed: no GOW.DB");
        return nil;
    end

    local guildKey = GOW.Core:GetGuildKey();
    if not guildKey then
        GOW.Logger:Debug("LootHistoryStore: EnsureStore failed: no guild key (player not in a guild)");
        return nil;
    end

    local guildData = GOW.DB.profile.guilds[guildKey];
    if not guildData.lootHistory then
        guildData.lootHistory = LootHistoryStore:NewStoreDefaults();
    end

    return guildData.lootHistory;
end

function LootHistoryStore:GetEntry(canonicalId)
    local store = self:EnsureStore();
    if not store then return nil end
    return store.entries[canonicalId];
end

function LootHistoryStore:GetAllEntries()
    local store = self:EnsureStore();
    if not store then return {} end
    return store.entries;
end

function LootHistoryStore:MakeCanonicalId(entry)
    if not entry then return "" end
    local source = entry.source or "";
    local sourceEntryId = entry.sourceEntryId or "";
    if sourceEntryId == "" then return "" end
    return source .. "-" .. sourceEntryId;
end

function LootHistoryStore:IsDuplicate(entry)
    if not entry then return true end
    if not entry.canonicalId or entry.canonicalId == "" then return false end
    return self:GetEntry(entry.canonicalId) ~= nil;
end

function LootHistoryStore:SaveDropEntry(entry)
    if not entry then return false end
    local store = self:EnsureStore();
    if not store then
        GOW.Logger:Debug("LootHistoryStore: SaveDropEntry failed: no store (player not in a guild?)");
        return false;
    end

    if not entry.canonicalId or entry.canonicalId == "" then
        entry.canonicalId = self:MakeCanonicalId(entry);
    end

    if entry.canonicalId == "" then
        GOW.Logger:Debug("LootHistoryStore: SaveDropEntry failed: no canonicalId could be generated");
        return false;
    end

    if self:IsDuplicate(entry) then
        return false;
    end

    store.entries[entry.canonicalId] = entry;

    GOW.Logger:Debug("LootHistoryStore: Persisted entry " .. entry.canonicalId);
    return true;
end

function LootHistoryStore:RemoveDropEntry(canonicalId)
    local store = self:EnsureStore();
    if not store then return false end
    if not store.entries[canonicalId] then return false end

    store.entries[canonicalId] = nil;

    GOW.Logger:Debug("LootHistoryStore: Removed entry " .. canonicalId);
    return true;
end

function LootHistoryStore:ShouldRefreshOnStartup(now)
    local store = self:EnsureStore();
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

