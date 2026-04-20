local GOW = GuildsOfWow;

local LootHistory = {};
GOW.LootHistory = LootHistory;

LootHistory.SOURCE_PERSONAL = "personal";
LootHistory.SOURCE_RCLC = "rclc";

LootHistory.state = {
    rclcPollTimer = nil,
    rclcSessionWasActive = false,
    isInitialized = false,
};

local RCLC_POLL_INTERVAL_SECONDS = 30;

function LootHistory:PopulateItemFromLink(entry, itemLink)
    if not itemLink then return end

    entry.item.link = itemLink;
    entry.item.itemID = tonumber(string.match(itemLink, "item:(%d+)"));
    entry.item.itemString = string.match(itemLink, "(item:[^|]+)") or "";

    if C_Item and C_Item.GetItemInfo then
        local itemName, _, _, itemLevel, _, _, itemSubType, _, itemEquipLoc = C_Item.GetItemInfo(itemLink);
        entry.item.name = itemName or "";
        entry.item.ilvl = itemLevel;
        entry.item.subType = itemSubType or "";
        entry.item.equipLoc = itemEquipLoc or "";
    elseif C_Item and C_Item.GetItemInfoInstant then
        local _, _, itemSubType, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink);
        entry.item.subType = itemSubType or "";
        entry.item.equipLoc = itemEquipLoc or "";
    end
end

function LootHistory:NewCanonicalEntry()
    return {
        canonicalId = "",
        source = "",
        sourceEntryId = "",
        winner = {
            name = "",
            realm = "",
            fullName = "",
            class = "",
            isSelf = false,
        },
        item = {
            link = "",
            itemID = nil,
            itemString = "",
            name = "",
            ilvl = nil,
            equipLoc = "",
            subType = "",
        },
        award = {
            response = "",
            responseID = nil,
            votes = nil,
            isAwardReason = false,
            note = "",
            owner = "",
            itemReplaced1 = "",
            itemReplaced2 = "",
        },
        encounter = {
            instance = "",
            boss = "",
            difficulty = "",
            difficultyID = nil,
            mapID = nil,
            groupSize = nil,
        },
        awardedAt = 0,
        season = nil,
    };
end

function LootHistory:Init()
    if not GOW.Helper:IsWishlistsEnabled() then return end

    local Store = GOW.LootHistoryStore;
    local RCLC = GOW.LootHistoryRCLC;

    Store:GetStore();

    -- Start RCLC session poll timer (paused during combat)
    if RCLC:IsRCLCAvailable() then
        self.state.rclcSessionWasActive = RCLC:IsSessionActive();
        self:StartRCLCPollTimer();

        local combatFrame = CreateFrame("Frame");
        combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED");
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
        combatFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                LootHistory:StopRCLCPollTimer();
            elseif event == "PLAYER_REGEN_ENABLED" then
                LootHistory:StartRCLCPollTimer();
                LootHistory:PollRCLCSession();
            end
        end);
    end

    -- On startup, scan RCLC history if stale (or debug mode) and no active session
    if GOW.consts.ENABLE_DEBUGGING or Store:ShouldRefreshOnStartup(GetServerTime()) then
        if RCLC:IsRCLCAvailable() and not RCLC:IsSessionActive() then
            RCLC:ProcessRCLCLootHistory();
        end
    end

    self.state.isInitialized = true;
    GOW.Logger:Debug("LootHistory: Initialized");
end

function LootHistory:StartRCLCPollTimer()
    if self.state.rclcPollTimer then return end
    self.state.rclcPollTimer = GOW.timers:ScheduleRepeatingTimer(function()
        LootHistory:PollRCLCSession();
    end, RCLC_POLL_INTERVAL_SECONDS);
end

function LootHistory:StopRCLCPollTimer()
    if not self.state.rclcPollTimer then return end
    GOW.timers:CancelTimer(self.state.rclcPollTimer);
    self.state.rclcPollTimer = nil;
end

--- Poll RCLC session state to detect session end transitions.
function LootHistory:PollRCLCSession()
    local RCLC = GOW.LootHistoryRCLC;
    local isActive = RCLC:IsSessionActive();
    local wasActive = self.state.rclcSessionWasActive;

    if wasActive and not isActive then
        -- Session just ended, process RCLC history
        RCLC:ProcessRCLCLootHistory();
        GOW.Logger:Debug("LootHistory: RCLC session ended — processed history");
    end

    self.state.rclcSessionWasActive = isActive;
end

function LootHistory:ProcessRCLCLootHistory()
    local RCLC = GOW.LootHistoryRCLC;
    if RCLC:IsRCLCAvailable() and not RCLC:IsSessionActive() then
        RCLC:ProcessRCLCLootHistory();
    end
end

function LootHistory:DebugStatus()
    local Store = GOW.LootHistoryStore;
    local RCLC = GOW.LootHistoryRCLC;
    local store = Store:GetStore();
    if not store then
        GOW.Logger:PrintErrorMessage("LootHistory store not initialized.");
        return;
    end

    local entryCount = 0;
    local personalCount = 0;
    local rclcCount = 0;
    for _, entry in pairs(store.entries) do
        entryCount = entryCount + 1;
        if entry.source == LootHistory.SOURCE_PERSONAL then
            personalCount = personalCount + 1;
        elseif entry.source == LootHistory.SOURCE_RCLC then
            rclcCount = rclcCount + 1;
        end
    end

    GOW.Logger:PrintMessage("--- Loot History Status ---");
    GOW.Logger:PrintMessage("Entries: " .. entryCount .. " (personal=" .. personalCount .. ", rclc=" .. rclcCount .. ")");
    GOW.Logger:PrintMessage("RCLC: available=" .. tostring(RCLC:IsRCLCAvailable()) .. ", session=" .. tostring(RCLC:IsSessionActive()));
    GOW.Logger:PrintMessage("Last scanned: " .. tostring(store.ingestion.rclc.lastScannedAt));
end

--- Simulate a personal loot drop using a random item from the active wishlist.
function LootHistory:DebugTestDrop()
    local GoWWishlists = GOW.Wishlists;
    if not GoWWishlists or not GoWWishlists.state or not GoWWishlists.state.allItems then
        GOW.Logger:PrintErrorMessage("Wishlist data not loaded.");
        return;
    end

    -- Find a non-obtained wishlist item
    local pool = {};
    for _, item in ipairs(GoWWishlists.state.allItems) do
        if not item.isObtained and item.itemId then
            table.insert(pool, item);
        end
    end

    if #pool == 0 then
        GOW.Logger:PrintErrorMessage("No wishlist items available to simulate.");
        return;
    end

    local pick = pool[math.random(#pool)];
    local itemId = pick.itemId;
    local difficulty = pick.difficulty or "Heroic";

    -- Build a fake item link (for testing — may not resolve full item info)
    local itemLink = "|cff0070dd|Hitem:" .. itemId .. "::::::::70:::::|h[Test Item " .. itemId .. "]|h|r";

    -- Try to get a real link if the item is cached
    if C_Item and C_Item.GetItemInfo then
        local name, link = C_Item.GetItemInfo(itemId);
        if link then itemLink = link end
    end

    local Personal = GOW.LootHistoryPersonal;

    local entry = Personal:MapToCanonical(itemId, itemLink, "Debug Boss", difficulty, 16);
    if not entry then
        GOW.Logger:PrintErrorMessage("Failed to map test entry.");
        return;
    end

    local persisted = GOW.LootHistoryStore:SaveDropEntry(entry);

    if persisted then
        GOW.Logger:PrintSuccessMessage("Test drop recorded: " .. itemLink .. " (id=" .. entry.canonicalId .. ")");
    else
        GOW.Logger:PrintErrorMessage("Test drop was a duplicate, not recorded.");
    end
end

--- Seed the loot history store with realistic test entries for both personal and RCLC sources.
--- Produces a representative SavedVariables structure.
function LootHistory:DebugSeed()
    local Store = GOW.LootHistoryStore;
    local store = Store:GetStore();
    if not store then
        GOW.Logger:PrintErrorMessage("LootHistory store not initialized.");
        return;
    end

    local now = GetServerTime();
    local HOUR = 3600;
    local DAY = 86400;

    -- Player info
    local charInfo = GOW.Wishlists and GOW.Wishlists.state and GOW.Wishlists.state.currentCharInfo;
    local selfName = charInfo and charInfo.name or "TestPlayer";
    local selfRealm = charInfo and charInfo.realmNormalized or "TestRealm";
    local selfFull = selfName .. "-" .. selfRealm;
    local _, selfClass = UnitClass("player");
    selfClass = selfClass or "WARRIOR";

    -- Seed data: {itemId, itemName, ilvl, boss, instance, difficulty, difficultyID, equipLoc, subType}
    local PERSONAL_SEEDS = {
        { 212438, "Signet of the Priory",    639, "Stormwall Blockade",  "Liberation of Undermine", "Heroic",  16, "INVTYPE_FINGER", "Miscellaneous" },
        { 212442, "Seal of the Poisoned Pact", 626, "Mug'Zee",           "Liberation of Undermine", "Normal",  14, "INVTYPE_FINGER", "Miscellaneous" },
        { 212396, "Everforged Greathelm",    639, "Vexie and the Geargrinders", "Liberation of Undermine", "Heroic",  16, "INVTYPE_HEAD",   "Plate" },
    };

    local RCLC_SEEDS = {
        { 212407, "Demolition Breastplate",   639, "Cauldron of Carnage", "Liberation of Undermine", "Heroic",  16, "INVTYPE_CHEST",  "Plate",   selfFull,   selfClass, true,  "Mainspec", 1, 3,  false, "BIS item" },
        { 212416, "Band of the Molten Forge",  639, "Stormwall Blockade", "Liberation of Undermine", "Heroic",  16, "INVTYPE_FINGER", "Miscellaneous", selfFull, selfClass, true, "Need",     2, 1,  false, "" },
        { 212454, "Gallagio Commendation",     639, "Gallywix",           "Liberation of Undermine", "Heroic",  16, "INVTYPE_TRINKET","Miscellaneous", "Tankbot-" .. selfRealm, "PALADIN",  false, "Mainspec", 1, 5,  false, "upgrade" },
        { 212399, "Riveted Waistguard",        626, "The One-Armed Bandit", "Liberation of Undermine", "Normal", 14, "INVTYPE_WAIST", "Plate",  "Healguy-" .. selfRealm, "PRIEST", false, "Offspec", 3, 0,  true,  "Disenchant" },
        { 212446, "Tempered Plating",          639, "Mug'Zee",            "Liberation of Undermine", "Heroic",  16, "INVTYPE_TRINKET","Miscellaneous", "Dpslord-" .. selfRealm, "MAGE", false, "Greed", 4, 2,  false, "" },
    };

    local importCount = 0;

    -- Personal entries
    for i, seed in ipairs(PERSONAL_SEEDS) do
        local itemId, itemName, ilvl, boss, instance, diff, diffID, equipLoc, subType = unpack(seed);
        local entry = LootHistory:NewCanonicalEntry();
        local entryTime = now - (DAY * (4 - i)) - (HOUR * 2);

        entry.source = LootHistory.SOURCE_PERSONAL;
        entry.sourceEntryId = itemId .. "-" .. entryTime .. "-" .. i;

        entry.winner.name = selfName;
        entry.winner.realm = selfRealm;
        entry.winner.fullName = selfFull;
        entry.winner.class = selfClass;
        entry.winner.isSelf = true;

        entry.item.link = "|cff0070dd|Hitem:" .. itemId .. "::::::::80:::::|h[" .. itemName .. "]|h|r";
        entry.item.itemID = itemId;
        entry.item.itemString = "item:" .. itemId .. "::::::::80:::::";
        entry.item.name = itemName;
        entry.item.ilvl = ilvl;
        entry.item.equipLoc = equipLoc;
        entry.item.subType = subType;

        entry.encounter.boss = boss;
        entry.encounter.instance = instance;
        entry.encounter.difficulty = diff;
        entry.encounter.difficultyID = diffID;
        entry.encounter.mapID = 2296;
        entry.encounter.groupSize = 20;

        entry.awardedAt = entryTime;

        if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
            entry.season = C_MythicPlus.GetCurrentSeason();
        end

        entry.canonicalId = Store:MakeCanonicalId(entry);

        if Store:SaveDropEntry(entry) then
            importCount = importCount + 1;
        end
    end

    -- RCLC entries
    for i, seed in ipairs(RCLC_SEEDS) do
        local itemId, itemName, ilvl, boss, instance, diff, diffID, equipLoc, subType,
              winnerFull, winnerClass, isSelf, response, responseID, votes, isAwardReason, note = unpack(seed);

        local entry = LootHistory:NewCanonicalEntry();
        local entryTime = now - (DAY * (6 - i)) - (HOUR * 3);
        local rclcId = tostring(entryTime) .. "-" .. i;

        entry.source = LootHistory.SOURCE_RCLC;
        entry.sourceEntryId = rclcId;

        local name, realm = string.match(winnerFull, "^(.-)%-(.+)$");
        entry.winner.name = name or winnerFull;
        entry.winner.realm = realm or selfRealm;
        entry.winner.fullName = winnerFull;
        entry.winner.class = winnerClass;
        entry.winner.isSelf = isSelf;

        entry.item.link = "|cff0070dd|Hitem:" .. itemId .. "::::::::80:::::|h[" .. itemName .. "]|h|r";
        entry.item.itemID = itemId;
        entry.item.itemString = "item:" .. itemId .. "::::::::80:::::";
        entry.item.name = itemName;
        entry.item.ilvl = ilvl;
        entry.item.equipLoc = equipLoc;
        entry.item.subType = subType;

        entry.award.response = response;
        entry.award.responseID = responseID;
        entry.award.votes = votes;
        entry.award.isAwardReason = isAwardReason;
        entry.award.note = note;
        entry.award.owner = "";
        entry.award.itemReplaced1 = "|cff0070dd|Hitem:190503::::::::80:::::|h[Old Ring]|h|r";
        entry.award.itemReplaced2 = (i <= 2) and "|cff0070dd|Hitem:190504::::::::80:::::|h[Other Ring]|h|r" or "";

        entry.encounter.boss = boss;
        entry.encounter.instance = instance;
        entry.encounter.difficulty = diff;
        entry.encounter.difficultyID = diffID;
        entry.encounter.mapID = 2296;
        entry.encounter.groupSize = 20;

        entry.awardedAt = entryTime;

        if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
            entry.season = C_MythicPlus.GetCurrentSeason();
        end

        entry.canonicalId = Store:MakeCanonicalId(entry);

        if Store:SaveDropEntry(entry) then
            importCount = importCount + 1;
        end
    end

    GOW.Logger:PrintSuccessMessage("Seeded " .. importCount .. " loot history entries (" .. #PERSONAL_SEEDS .. " personal, " .. #RCLC_SEEDS .. " RCLC).");
    self:DebugStatus();
end

--- Dump a single entry's full structure to chat for debugging.
--- @param canonicalId string|nil If nil, dumps the first entry found.
function LootHistory:DebugDump(canonicalId)
    local store = GOW.LootHistoryStore:GetStore();
    if not store then
        GOW.Logger:PrintErrorMessage("LootHistory store not initialized.");
        return;
    end

    local entry;
    if canonicalId and canonicalId ~= "" then
        entry = store.entries[canonicalId];
        if not entry then
            GOW.Logger:PrintErrorMessage("Entry not found: " .. canonicalId);
            return;
        end
    else
        for id, e in pairs(store.entries) do
            entry = e;
            canonicalId = id;
            break;
        end
    end

    if not entry then
        GOW.Logger:PrintErrorMessage("No entries in store.");
        return;
    end

    GOW.Logger:PrintMessage("--- Entry: " .. canonicalId .. " ---");
    GOW.Logger:PrintMessage("source=" .. tostring(entry.source) .. "  sourceEntryId=" .. tostring(entry.sourceEntryId));
    GOW.Logger:PrintMessage("winner: " .. tostring(entry.winner.fullName) .. " (" .. tostring(entry.winner.class) .. ") isSelf=" .. tostring(entry.winner.isSelf));
    GOW.Logger:PrintMessage("item: " .. tostring(entry.item.name) .. " id=" .. tostring(entry.item.itemID) .. " ilvl=" .. tostring(entry.item.ilvl) .. " slot=" .. tostring(entry.item.equipLoc));
    GOW.Logger:PrintMessage("encounter: " .. tostring(entry.encounter.boss) .. " @ " .. tostring(entry.encounter.instance) .. " diffID=" .. tostring(entry.encounter.difficultyID));
    GOW.Logger:PrintMessage("time: " .. tostring(entry.awardedAt) .. " (unix)");
    GOW.Logger:PrintMessage("award: resp=" .. tostring(entry.award.response) .. " votes=" .. tostring(entry.award.votes) .. " note=" .. tostring(entry.award.note));
end

--- Clear all entries from the loot history store.
function LootHistory:DebugClear()
    local store = GOW.LootHistoryStore:GetStore();
    if not store then return end

    local count = 0;
    for id in pairs(store.entries) do
        count = count + 1;
    end

    store.entries = {};
    store.ingestion.rclc.lastScannedAt = 0;

    GOW.Logger:PrintSuccessMessage("Cleared " .. count .. " loot history entries.");
end

function LootHistory:HandleSlashCommand(subcommand)
    if not GOW.consts.ENABLE_DEBUGGING then
        GOW.Logger:PrintErrorMessage("Debug mode is not enabled.");
        return;
    end

    if not self.state.isInitialized then
        GOW.Logger:PrintErrorMessage("LootHistory not initialized.");
        return;
    end

    if subcommand == "status" then
        self:DebugStatus();
    elseif subcommand == "test" then
        self:DebugTestDrop();
    elseif subcommand == "rclc" then
        GOW.Logger:PrintMessage("Scanning RCLC history...");
        self:ProcessRCLCLootHistory();
        self:DebugStatus();
    elseif subcommand == "seed" then
        self:DebugSeed();
    elseif subcommand == "dump" then
        self:DebugDump();
    elseif subcommand == "clear" then
        self:DebugClear();
    else
        GOW.Logger:PrintMessage("Usage: /gow lh <status|test|rclc|seed|dump|clear>");
    end
end
