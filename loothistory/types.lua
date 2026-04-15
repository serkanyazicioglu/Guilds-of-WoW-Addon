local GOW = GuildsOfWow;

local LootHistoryTypes = {};
GOW.LootHistoryTypes = LootHistoryTypes;

-- Sources
LootHistoryTypes.SOURCE_PERSONAL = "personal";
LootHistoryTypes.SOURCE_RCLC = "rclc";

-- Store version
LootHistoryTypes.STORE_VERSION = "1.0.0";

-- Config
LootHistoryTypes.STARTUP_REFRESH_THRESHOLD_SECONDS = 3600;

-- Dedupe window for personal/RCLC overlap reconciliation (seconds)
LootHistoryTypes.RECONCILE_WINDOW_SECONDS = 300;

--- Populate entry.item fields from an item link using C_Item APIs.
--- @param entry table The canonical entry to populate
--- @param itemLink string The item link to parse
function LootHistoryTypes:PopulateItemFromLink(entry, itemLink)
    if not itemLink then return end

    entry.item.link = itemLink;
    entry.item.itemID = tonumber(itemLink:match("item:(%d+)"));
    entry.item.itemString = itemLink:match("(item:[^|]+)") or "";

    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, itemSubType, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink);
        entry.item.subType = itemSubType or "";
        entry.item.equipLoc = itemEquipLoc or "";
    end

    if C_Item and C_Item.GetItemInfo then
        local itemName, _, _, itemLevel = C_Item.GetItemInfo(itemLink);
        entry.item.name = itemName or "";
        entry.item.ilvl = itemLevel;
    elseif GetItemInfo then
        local itemName, _, _, itemLevel = GetItemInfo(itemLink);
        entry.item.name = itemName or "";
        entry.item.ilvl = itemLevel;
    end
end

--- Create a new canonical loot history entry with safe defaults.
--- @return table
function LootHistoryTypes:NewCanonicalEntry()
    return {
        canonicalId = "",

        -- source
        source = "",
        sourceEntryId = "",

        -- player
        winner = {
            name = "",
            realm = "",
            fullName = "",
            class = "",
            isSelf = false,
        },

        -- item
        item = {
            link = "",
            itemID = nil,
            itemString = "",
            name = "",
            ilvl = nil,
            equipLoc = "",
            subType = "",
        },

        -- award/response
        award = {
            response = "",
            responseID = nil,
            votes = nil,
            isAwardReason = false,
            note = "",
            owner = "",
            gear1 = "",
            gear2 = "",
        },

        -- encounter
        encounter = {
            instance = "",
            boss = "",
            difficultyID = nil,
            mapID = nil,
            groupSize = nil,
        },

        -- time
        awardedAt = 0,

        -- season (set at drop time for personal; nil for RCLC)
        season = nil,
    };
end

--- Create the default loot history store structure.
--- @return table
function LootHistoryTypes:NewStoreDefaults()
    return {
        version = LootHistoryTypes.STORE_VERSION,
        entries = {},

        ingestion = {
            rclc = {
                lastScannedAt = 0,
            },
        },
    };
end
