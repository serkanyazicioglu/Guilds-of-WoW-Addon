local GOW = GuildsOfWow;
local Types = GOW.LootHistoryTypes;
local Store = GOW.LootHistoryStore;
local RCLC = GOW.LootHistoryRCLC;

local LootHistory = {};
GOW.LootHistory = LootHistory;

LootHistory.state = {
    rclcPollTimer = nil,
    rclcSessionWasActive = false,
    isInitialized = false,
};

local RCLC_POLL_INTERVAL_SECONDS = 30;

--- Initialize the loot history module.
--- Gated behind retail-only wishlists feature flag.
function LootHistory:Init()
    if not GOW.Helper:IsWishlistsEnabled() then return end

    -- Initialize store and run migrations
    Store:GetStore();
    Store:MigrateIfNeeded();

    -- Register PLAYER_LOGOUT for upload finalization
    -- (C_LootHistory events are handled by wishlists/events.lua)
    local eventFrame = CreateFrame("Frame");
    eventFrame:RegisterEvent("PLAYER_LOGOUT");
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGOUT" then
            LootHistory:OnLogout();
        end
    end);

    -- Start RCLC session poll timer
    if RCLC:IsRCLCAvailable() then
        self.state.rclcSessionWasActive = RCLC:IsSessionActive();
        self.state.rclcPollTimer = GOW.timers:ScheduleRepeatingTimer(function()
            LootHistory:PollRCLCSession();
        end, RCLC_POLL_INTERVAL_SECONDS);
    end

    -- Check if we should refresh on startup
    if Store:ShouldRefreshOnStartup(GetServerTime()) then
        -- On startup, scan RCLC history if available and no active session
        if RCLC:IsRCLCAvailable() and not RCLC:IsSessionActive() then
            RCLC:ProcessRCLCLootHistory();
        end
        Store:FinalizeForUpload(Types.TRIGGER_STARTUP);
    end

    self.state.isInitialized = true;
    GOW.Logger:Debug("LootHistory: Initialized");
end

--- Handle PLAYER_LOGOUT — finalize upload state.
function LootHistory:OnLogout()
    Store:FinalizeForUpload(Types.TRIGGER_LOGOUT);
end

--- Poll RCLC session state to detect session end transitions.
function LootHistory:PollRCLCSession()
    local isActive = RCLC:IsSessionActive();
    local wasActive = self.state.rclcSessionWasActive;

    if wasActive and not isActive then
        -- Session just ended, process RCLC history
        RCLC:ProcessRCLCLootHistory();
        Store:FinalizeForUpload(Types.TRIGGER_RCLC_SESSION_END);
        GOW.Logger:Debug("LootHistory: RCLC session ended — processed history");
    end

    self.state.rclcSessionWasActive = isActive;
end

--- Public API: Get a single entry by canonical ID.
--- @param canonicalId string
--- @return table|nil
function LootHistory:GetEntry(canonicalId)
    return Store:GetEntry(canonicalId);
end

--- Public API: Get all entries.
--- @return table
function LootHistory:GetAllEntries()
    return Store:GetAllEntries();
end

--- Public API: Check if entry exists by source and source entry ID.
--- @param source string
--- @param sourceEntryId string
--- @return boolean
function LootHistory:HasEntryBySource(source, sourceEntryId)
    return Store:HasEntryBySource(source, sourceEntryId);
end

--- Public API: Finalize store for desktop upload.
--- @param reason string One of Types.TRIGGER_* constants
function LootHistory:FinalizeForUpload(reason)
    Store:FinalizeForUpload(reason);
end

--- Public API: Trigger RCLC history processing manually.
function LootHistory:ProcessRCLCLootHistory()
    if RCLC:IsRCLCAvailable() and not RCLC:IsSessionActive() then
        RCLC:ProcessRCLCLootHistory();
    end
end

-- ============================================================
-- Debug helpers (gated behind GOW.consts.ENABLE_DEBUGGING)
-- ============================================================

--- Print a summary of the current loot history store state.
function LootHistory:DebugStatus()
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
        if entry.source == Types.SOURCE_PERSONAL then
            personalCount = personalCount + 1;
        elseif entry.source == Types.SOURCE_RCLC then
            rclcCount = rclcCount + 1;
        end
    end

    GOW.Logger:PrintMessage("--- Loot History Status ---");
    GOW.Logger:PrintMessage("Entries: " .. entryCount .. " (personal=" .. personalCount .. ", rclc=" .. rclcCount .. ")");
    GOW.Logger:PrintMessage("Upload: state=" .. tostring(store.sync.uploadState) .. ", safe=" .. tostring(store.sync.safeToUpload) .. ", rev=" .. tostring(store.sync.revision));
    GOW.Logger:PrintMessage("RCLC: available=" .. tostring(RCLC:IsRCLCAvailable()) .. ", session=" .. tostring(RCLC:IsSessionActive()));
    GOW.Logger:PrintMessage("Last processed: " .. tostring(store.sync.lastProcessedAt) .. ", reason=" .. tostring(store.sync.triggerReason));
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
    local now = GetServerTime();

    -- Build a fake item link (for testing — may not resolve full item info)
    local itemLink = "|cff0070dd|Hitem:" .. itemId .. "::::::::70:::::|h[Test Item " .. itemId .. "]|h|r";

    -- Try to get a real link if the item is cached
    if C_Item and C_Item.GetItemInfo then
        local name, link = C_Item.GetItemInfo(itemId);
        if link then itemLink = link end
    elseif GetItemInfo then
        local name, link = GetItemInfo(itemId);
        if link then itemLink = link end
    end

    local Personal = GOW.LootHistoryPersonal;
    local wishlistMatch = Personal:IsRelevantForHistory(itemId);

    local entry = Personal:MapToCanonical(itemId, itemLink, "Debug Boss", difficulty, 16, wishlistMatch);
    if not entry then
        GOW.Logger:PrintErrorMessage("Failed to map test entry.");
        return;
    end

    Store:MarkUploadPending();
    local persisted = Store:PersistEntry(entry);

    if persisted then
        GOW.Logger:PrintSuccessMessage("Test drop recorded: " .. itemLink .. " (id=" .. entry.canonicalId .. ")");
    else
        GOW.Logger:PrintErrorMessage("Test drop was a duplicate, not recorded.");
    end
end

--- Clear all entries from the loot history store.
function LootHistory:DebugClear()
    local store = Store:GetStore();
    if not store then return end

    local count = 0;
    for id in pairs(store.entries) do
        count = count + 1;
    end

    store.entries = {};
    store.updatedAt = GetServerTime();
    store.sync.uploadState = Types.UPLOAD_IDLE;
    store.sync.safeToUpload = false;

    GOW.Logger:PrintSuccessMessage("Cleared " .. count .. " loot history entries.");
end

--- Handle /gow lh subcommands.
--- @param subcommand string The subcommand after "lh"
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
    elseif subcommand == "sync" then
        self:FinalizeForUpload(Types.TRIGGER_MANUAL);
        GOW.Logger:PrintSuccessMessage("Upload finalized (manual).");
    elseif subcommand == "clear" then
        self:DebugClear();
    else
        GOW.Logger:PrintMessage("Usage: /gow lh <status|test|rclc|sync|clear>");
    end
end
