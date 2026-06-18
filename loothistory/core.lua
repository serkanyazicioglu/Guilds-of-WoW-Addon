local GOW = GuildsOfWow;

local LootHistory = {};
GOW.LootHistory = LootHistory;

local function ExtractIconFilename(iconTexture)
    if not iconTexture then return "" end
    return string.match(iconTexture, "([^\\/]+)$") or "";
end

LootHistory.SOURCE_PERSONAL = "personal";
LootHistory.SOURCE_RCLC = "rclc";

LootHistory.state = {
    rclcPollTimer = nil,
    rclcSessionWasActive = false,
};

local RCLC_POLL_INTERVAL_SECONDS = 30;

function LootHistory:PopulateItemFromLink(entry, itemLink)
    if not itemLink then return end

    entry.item.link = itemLink;
    entry.item.itemID = tonumber(string.match(itemLink, "item:(%d+)"));
    entry.item.itemString = string.match(itemLink, "(item:[^|]+)") or "";

    -- Phase 1 — Fast path: GetItemInfoInstant is synchronous and never blocks.
    -- Populates subType, equipLoc, and icon (via GetItemIconByID).
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, _, itemSubType, _, itemEquipLoc = C_Item.GetItemInfoInstant(itemLink);
        entry.item.subType = itemSubType or "";
        entry.item.equipLoc = itemEquipLoc or "";
        if C_Item.GetItemIconByID and entry.item.itemID then
            local iconTexture = C_Item.GetItemIconByID(entry.item.itemID);
            entry.item.icon = ExtractIconFilename(iconTexture);
        end
    end

    -- Phase 2 — Best-effort enrichment: GetItemInfo may return cached name/ilvl.
    -- Icon fallback: GetItemInfo icon used only when Phase 1 left icon empty
    -- (e.g. GetItemIconByID was unavailable or returned nil).
    if C_Item and C_Item.GetItemInfo then
        local itemName, _, _, itemLevel, _, _, _, _, _, iconTexture = C_Item.GetItemInfo(itemLink);
        if itemName then entry.item.name = itemName; end
        if itemLevel then entry.item.ilvl = itemLevel; end
        if iconTexture and entry.item.icon == "" then
            entry.item.icon = ExtractIconFilename(iconTexture);
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
            votes = nil,  -- nil for personal entries; RCLC sets 0 or a count (see rclc.lua:MapToCanonical)
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
        -- entry.rclc is optional RCLC-only metadata (see rclc.lua:MapToCanonical)
        awardedAt = 0,
        season = nil,
    };
end

function LootHistory:PopulateSeason(entry, maxAgeSeconds)
    if not C_MythicPlus or not C_MythicPlus.GetCurrentSeason then return end
    if maxAgeSeconds then
        local age = GetServerTime() - (entry.awardedAt or 0);
        if age > maxAgeSeconds then return end
    end
    entry.season = C_MythicPlus.GetCurrentSeason();
end

function LootHistory:Init()
    if not GOW.Helper:IsWishlistsEnabled() then return end

    GOW.LootHistoryStore:EnsureStore();

    -- Start RCLC session poll timer (only while in a raid instance; paused during combat)
    if GOW.LootHistoryRCLC:IsRCLCAvailable() then
        self.state.rclcSessionWasActive = GOW.LootHistoryRCLC:IsSessionActive();

        -- Only start the timer if we're already in a raid; INSTANCE_CHANGED will
        -- handle transitions in and out.
        local _, instanceType = IsInInstance();
        if instanceType == "raid" then
            self:StartRCLCPollTimer();
        end

        -- This frame lives for the duration of the session (no explicit cleanup needed)
        local combatFrame = CreateFrame("Frame");
        combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED");
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
        combatFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
        combatFrame:RegisterEvent("INSTANCE_CHANGED");
        combatFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                LootHistory:StopRCLCPollTimer();
            elseif event == "PLAYER_REGEN_ENABLED" then
                -- Resume polling only if still in a raid instance
                local _, instType = IsInInstance();
                if instType == "raid" then
                    LootHistory:StartRCLCPollTimer();
                end
            elseif event == "PLAYER_ENTERING_WORLD" then
                -- Re-sync session state after loading screens
                LootHistory.state.rclcSessionWasActive = GOW.LootHistoryRCLC:IsSessionActive();
            elseif event == "INSTANCE_CHANGED" then
                -- Gate poll timer to raid instances only
                local _, instType = IsInInstance();
                if instType == "raid" then
                    LootHistory:StartRCLCPollTimer();
                else
                    LootHistory:StopRCLCPollTimer();
                end
            end
        end);
    end

    -- On startup, scan RCLC history if stale (or debug mode) and no active session
    if GOW.consts.ENABLE_DEBUGGING or GOW.LootHistoryStore:ShouldRefreshOnStartup(GetServerTime()) then
        if GOW.LootHistoryRCLC:IsRCLCAvailable() and not GOW.LootHistoryRCLC:IsSessionActive() then
            GOW.LootHistoryRCLC:ProcessRCLCLootHistory();
        end
    end

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


