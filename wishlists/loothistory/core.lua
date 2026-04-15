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
