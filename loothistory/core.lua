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
        local itemName, _, _, itemLevel, _, _, itemSubType, _, itemEquipLoc, iconTexture = C_Item.GetItemInfo(itemLink);
        entry.item.name = itemName or "";
        entry.item.ilvl = itemLevel;
        entry.item.subType = itemSubType or "";
        entry.item.equipLoc = itemEquipLoc or "";
        if iconTexture then
            entry.item.icon = string.lower(string.match(tostring(iconTexture), "([^\\/]+)$") or "");
        end
    elseif C_Item and C_Item.GetItemInfoInstant then
        local _, _, itemSubType, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink);
        entry.item.subType = itemSubType or "";
        entry.item.equipLoc = itemEquipLoc or "";
        if C_Item.GetItemIconByID and entry.item.itemID then
            local iconTexture = C_Item.GetItemIconByID(entry.item.itemID);
            if iconTexture then
                entry.item.icon = string.lower(string.match(tostring(iconTexture), "([^\\/]+)$") or "");
            end
        end
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
            icon = "",
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
        GOW.Logger:Debug("LootHistory: RCLC session ended, processed history");
    end

    self.state.rclcSessionWasActive = isActive;
end


