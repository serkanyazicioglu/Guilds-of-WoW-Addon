local GOW = GuildsOfWow;
local L = GOW.Layout;
local Store = GOW.LootHistoryStore;
local LootHistory = GOW.LootHistory;
local RCLC = GOW.LootHistoryRCLC;
local Duration = GOW.Duration;

local LootHistoryUI = {};
GOW.LootHistoryUI = LootHistoryUI;

local ROW_HEIGHT = 28;
local HEADER_HEIGHT = 32;
local ICON_SIZE = 22;

local sortedCache = nil;
local sortedGeneration = nil;

function LootHistoryUI:GetSortedEntries()
    local store = Store:EnsureStore();
    local gen = store and store.generation or nil;
    if sortedCache and gen and gen == sortedGeneration then
        return sortedCache;
    end

    local entries = Store:GetAllEntries();
    local sorted = {};
    for _, entry in pairs(entries) do
        table.insert(sorted, entry);
    end
    table.sort(sorted, function(a, b)
        return (a.awardedAt or 0) > (b.awardedAt or 0);
    end);

    sortedCache = sorted;
    sortedGeneration = gen;
    return sorted;
end

function LootHistoryUI:CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(ROW_HEIGHT);

    local icon = row:CreateTexture(nil, "ARTWORK");
    icon:SetSize(ICON_SIZE, ICON_SIZE);
    icon:SetPoint("LEFT", row, "LEFT", 6, 0);
    row.icon = icon;

    local winnerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    winnerText:SetWidth(120);
    winnerText:SetJustifyH("LEFT");
    winnerText:SetWordWrap(false);
    row.winnerText = winnerText;

    local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    itemText:SetPoint("LEFT", icon, "RIGHT", 6, 0);
    itemText:SetPoint("RIGHT", winnerText, "LEFT", -8, 0);
    itemText:SetJustifyH("LEFT");
    itemText:SetWordWrap(false);
    row.itemText = itemText;

    winnerText:SetPoint("LEFT", itemText, "RIGHT", 8, 0);

    local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    sourceText:SetPoint("LEFT", winnerText, "RIGHT", 8, 0);
    sourceText:SetWidth(80);
    sourceText:SetJustifyH("LEFT");
    sourceText:SetWordWrap(false);
    row.sourceText = sourceText;

    local difficultyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    difficultyText:SetPoint("LEFT", sourceText, "RIGHT", 8, 0);
    difficultyText:SetWidth(60);
    difficultyText:SetJustifyH("LEFT");
    difficultyText:SetWordWrap(false);
    row.difficultyText = difficultyText;

    local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    timeText:SetPoint("LEFT", difficultyText, "RIGHT", 8, 0);
    timeText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    timeText:SetJustifyH("RIGHT");
    timeText:SetWordWrap(false);
    row.timeText = timeText;

    local itemHitZone = CreateFrame("Frame", nil, row);
    itemHitZone:SetPoint("LEFT", icon, "LEFT", 0, 0);
    itemHitZone:SetPoint("RIGHT", itemText, "RIGHT", 0, 0);
    itemHitZone:SetPoint("TOP", row, "TOP", 0, 0);
    itemHitZone:SetPoint("BOTTOM", row, "BOTTOM", 0, 0);
    itemHitZone:EnableMouse(true);
    itemHitZone:SetScript("OnEnter", function(self)
        if row.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:SetHyperlink(row.itemLink);
            GameTooltip:Show();
        end
    end);
    itemHitZone:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    row.itemHitZone = itemHitZone;

    return row;
end

function LootHistoryUI:PopulateRow(row, entry)
    row.itemLink = entry.item.link;

    local iconTexture = entry.item.icon;
    if not iconTexture and entry.item.itemID then
        iconTexture = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.item.itemID);
    end

    row.icon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark");

    local displayName = entry.item.link or entry.item.name or ("Item " .. (entry.item.itemID or "?"));
    row.itemText:SetText(displayName);

    local winnerDisplay = entry.winner.name or entry.winner.fullName or "";
    local classColor = entry.winner.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.winner.class];
    if classColor then
        row.winnerText:SetText(classColor:WrapTextInColorCode(winnerDisplay));
    else
        row.winnerText:SetText(winnerDisplay);
    end

    local sourceLabel = entry.source == LootHistory.SOURCE_RCLC and "|cffff8000RCLC|r" or "|cff888888Personal|r";
    row.sourceText:SetText(sourceLabel);

    row.difficultyText:SetText(entry.encounter.difficulty or "");

    row.timeText:SetText(Duration:Format(entry.awardedAt));
end

function LootHistoryUI:ShowEmptyState(container)
    local scrollChild = container.lhScrollChild;
    if not container.emptyStateText then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -40);
        emptyText:SetPoint("LEFT", scrollChild, "LEFT", 16, 0);
        emptyText:SetPoint("RIGHT", scrollChild, "RIGHT", -16, 0);
        emptyText:SetJustifyH("CENTER");
        emptyText:SetTextColor(0.55, 0.55, 0.55, 1);
        container.emptyStateText = emptyText;
    end
    local rclcAvailable = RCLC:IsRCLCAvailable();
    local rclcStatus = rclcAvailable and "|cff00ff00Yes|r" or "|cffff0000No|r";
    local rclcInstructions = rclcAvailable
        and "Use \"Scan RCLC\" to import previous sessions,\nor type /reload if you just installed the addon."
        or "Install RCLootCouncil to import loot history from\nprevious RCLC sessions, or type /reload if you just installed the addon.";
    container.emptyStateText:SetText(
        "No loot history found.\n\n" ..
        "Loot history is recorded automatically after raids\n" ..
        "or when an RCLC loot session ends.\n\n" ..
        "RCLootCouncil detected: " .. rclcStatus .. "\n\n" ..
        rclcInstructions
    );
    container.emptyStateText:Show();
end

function LootHistoryUI:HideEmptyState(container)
    if container.emptyStateText then
        container.emptyStateText:Hide();
    end
end

function LootHistoryUI:ApplyRowBackground(row, index)
    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND");
        row.bg:SetAllPoints(row);
        row.bg:SetTexture("Interface\\Buttons\\WHITE8x8");
    end
    if index % 2 == 0 then
        row.bg:SetVertexColor(1, 1, 1, 0.03);
    else
        row.bg:SetVertexColor(0, 0, 0, 0.1);
    end
end

function LootHistoryUI:PopulateLootHistoryView(container)
    if container.lootHistoryRows then
        for _, row in ipairs(container.lootHistoryRows) do
            row:Hide();
        end
    end
    container.lootHistoryRows = container.lootHistoryRows or {};

    if not container.headerBar then
        local headerBar = CreateFrame("Frame", nil, container);
        headerBar:SetHeight(HEADER_HEIGHT);
        headerBar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0);
        headerBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0);

        local scanBtn = L:CreateActionButton(headerBar, {
            text = "Scan RCLC",
            width = 90,
            tooltip = "Re-scan RCLC Loot History",
            tooltipSubtext = "Import any new entries from RCLootCouncil",
            onClick = function()
                if RCLC:IsRCLCAvailable() then
                    if RCLC:IsSessionActive() then
                        GOW.Logger:PrintErrorMessage("Cannot scan while an RCLC loot session is active.");
                        return;
                    end
                    RCLC:ProcessRCLCLootHistory();
                    LootHistoryUI:PopulateLootHistoryView(container);
                    GOW.Logger:PrintSuccessMessage("RCLC loot history scan complete.");
                else
                    GOW.Logger:PrintErrorMessage("RCLootCouncil is not loaded.");
                end
            end,
        });
        scanBtn:SetPoint("TOPLEFT", headerBar, "TOPLEFT", 6, -4);

        local countText = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        countText:SetPoint("LEFT", scanBtn, "RIGHT", 12, 0);
        countText:SetTextColor(0.6, 0.6, 0.6, 1);
        headerBar.countText = countText;

        container.headerBar = headerBar;
    end

    if not container.lhScrollFrame then
        local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate");
        scrollFrame:SetPoint("TOPLEFT", container.headerBar, "BOTTOMLEFT", 0, -4);
        scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -22, 4);

        local scrollChild = CreateFrame("Frame", nil, scrollFrame);
        scrollChild:SetWidth(scrollFrame:GetWidth() or 600);
        scrollFrame:SetScrollChild(scrollChild);
        scrollFrame:SetScript("OnSizeChanged", function(self)
            scrollChild:SetWidth(self:GetWidth());
        end);

        container.lhScrollFrame = scrollFrame;
        container.lhScrollChild = scrollChild;
    end

    local scrollChild = container.lhScrollChild;
    local entries = self:GetSortedEntries();

    container.headerBar.countText:SetText(#entries .. " entries");

    if #entries == 0 then
        self:ShowEmptyState(container);
    else
        self:HideEmptyState(container);
    end

    local yOffset = 0;
    for i, entry in ipairs(entries) do
        local row = container.lootHistoryRows[i];
        if not row then
            row = self:CreateRow(scrollChild);
            container.lootHistoryRows[i] = row;
        end

        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        self:PopulateRow(row, entry);
        row:Show();
        self:ApplyRowBackground(row, i);

        yOffset = yOffset + ROW_HEIGHT;
    end

    for i = #entries + 1, #container.lootHistoryRows do
        container.lootHistoryRows[i]:Hide();
    end

    scrollChild:SetHeight(math.max(yOffset, 1));
end
