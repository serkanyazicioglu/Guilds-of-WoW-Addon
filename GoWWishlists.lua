local GOW = GuildsOfWow;
local GoWWishlists = {};
GOW.Wishlists = GoWWishlists;

local ns = select(2, ...);

local wishlistIndex = {};
local allItems = {};
local currentCharInfo = nil;
local guildWishlistData = nil;

local pendingItemRows = {};

local function registerPendingItem(itemId, callback)
    if not pendingItemRows[itemId] then
        pendingItemRows[itemId] = {};
    end
    table.insert(pendingItemRows[itemId], callback);
end

local function onItemInfoReceived(itemId)
    local callbacks = pendingItemRows[itemId];
    if not callbacks then return end
    pendingItemRows[itemId] = nil;
    for _, cb in ipairs(callbacks) do
        cb();
    end
end

local difficultyNames = {
    -- Retail raid difficulties
    [3]   = "Normal",       -- 10 Player
    [4]   = "Normal",       -- 25 Player
    [5]   = "Heroic",       -- 10 Player (Heroic)
    [6]   = "Heroic",       -- 25 Player (Heroic)
    [7]   = "LFR",          -- Legacy LFR (pre-SoO)
    [9]   = "Normal",       -- 40 Player
    [14]  = "Normal",       -- Normal (raids)
    [15]  = "Heroic",       -- Heroic (raids)
    [16]  = "Mythic",       -- Mythic (raids)
    [17]  = "LFR",          -- Looking For Raid
    [18]  = "Normal",       -- Event (raid)
    [33]  = "Timewalking",  -- Timewalking (raid)
    [151] = "LFR",          -- Looking For Raid (Timewalking)
    [220] = "Normal",       -- Story (solo raid)
    [241] = "Normal",       -- Lorewalking (raid)
    -- Classic raid difficulties
    [148] = "Normal",       -- 20 Player (ZG, AQ20)
    [175] = "Normal",       -- 10 Player (Classic)
    [176] = "Normal",       -- 25 Player (Classic)
    [193] = "Heroic",       -- 10 Player Heroic (Classic)
    [194] = "Heroic",       -- 25 Player Heroic (Classic)
};

local function getCurrentCharacterInfo()
    local name = UnitName("player");
    local realm = GetRealmName();
    local realmNormalized = GetNormalizedRealmName();
    local regionId = GetCurrentRegion();
    return {
        name = name,
        realm = realm,
        realmNormalized = realmNormalized,
        regionId = regionId,
        nameLower = name:lower(),
        realmLower = realmNormalized:lower(),
    };
end

function GoWWishlists:BuildWishlistIndex()
    wishlistIndex = {};
    allItems = {};
    guildWishlistData = nil;

    currentCharInfo = getCurrentCharacterInfo();
    local charInfo = currentCharInfo;

    if not ns.WISHLISTS then
        GOW.Logger:Debug("No wishlist data found, character info stored");
        return;
    end

    local isDebug = GOW.consts.ENABLE_DEBUGGING;

    -- Personal wishlists: find matching character (or first entry in debug mode)
    local personalLists = ns.WISHLISTS.personalWishlists;
    if personalLists then
        for _, charEntry in ipairs(personalLists) do
            local entryName = charEntry.name and charEntry.name:lower() or "";
            local entryRealm = charEntry.realmNameNormalized and charEntry.realmNameNormalized:lower() or "";

            if isDebug or (entryName == charInfo.nameLower and entryRealm == charInfo.realmLower) then
                for _, item in ipairs(charEntry.wishlist) do
                    item.characterName = entryName;
                    item.characterRealmNormalized = entryRealm;

                    table.insert(allItems, item);

                    if not item.isObtained then
                        local key = item.itemId;
                        wishlistIndex[key] = wishlistIndex[key] or {};
                        table.insert(wishlistIndex[key], item);
                    end
                end
                if not isDebug then break end
            end
        end
    end

    -- Guild wishlists: find matching guild for current character (or first entry in debug mode)
    local guildLists = ns.WISHLISTS.guildWishlists;
    if guildLists then
        if isDebug and #guildLists > 0 then
            guildWishlistData = guildLists[1];
        else
            local playerGuild = GetGuildInfo("player");
            if playerGuild then
                for _, guildEntry in ipairs(guildLists) do
                    local guildRealm = guildEntry.guildRealmNormalized and guildEntry.guildRealmNormalized:lower() or "";
                    if guildEntry.guild == playerGuild and guildRealm == charInfo.realmLower then
                        guildWishlistData = guildEntry;
                        break;
                    end
                end
            end
        end
    end

    for _, entry in ipairs(allItems) do
        C_Item.GetItemInfo(entry.itemId);
    end

    GOW.Logger:Debug("Wishlist index built: " .. #allItems .. " items indexed for " .. charInfo.nameLower .. "-" .. charInfo.realmLower);
end

local function getCurrentDifficultyName()
    local _, _, difficultyId = GetInstanceInfo();
    return difficultyNames[difficultyId];
end

function GoWWishlists:FindWishlistMatch(itemId)
    local entries = wishlistIndex[itemId];
    if not entries then
        return nil;
    end

    local difficulty = getCurrentDifficultyName();

    for _, entry in ipairs(entries) do
        if entry.difficulty == difficulty
            and not entry.isObtained then
            return entry;
        end
    end

    return nil;
end


-- Wishlist Loot Alert Container Frame
local wishlistAlertContainer = nil;
local ALERT_ITEM_ROW_HEIGHT = 66;
local ALERT_DISPLAY_TIME = 60;
local ALERT_FADE_TIME = 1.5;

local GOW_ACCENT_COLOR = { r = 0.1, g = 0.8, b = 0.3 }; 
local GOW_BG_COLOR = { r = 0.08, g = 0.08, b = 0.1 };  

local DIFF_COLORS = {
    ["Mythic"]      = { r = 0.616, g = 0, b = 1 },
    ["Heroic"]      = { r = 0, g = 0.439, b = 0.867 },
    ["Normal"]      = { r = 0.118, g = 1, b = 0 },
    ["LFR"]         = { r = 1, g = 0.820, b = 0 },
    ["Timewalking"] = { r = 0, g = 0.8, b = 1 },
};

local SUB_ACTIVE_COLOR = { r = GOW_ACCENT_COLOR.r, g = GOW_ACCENT_COLOR.g, b = GOW_ACCENT_COLOR.b, a = 0.3 };
local SUB_INACTIVE_COLOR = { r = 0.15, g = 0.15, b = 0.18, a = 0.8 };

local TAG_DISPLAY = {
    BIS      = { label = "BiS", color = "ff8000" },
    NEED     = { label = "N",   color = "ff0000" },
    GREED    = { label = "G",   color = "00ff00" },
    MINOR    = { label = "MU",  color = "ffff00" },
    TRANSMOG = { label = "T",   color = "ff69b4" },
    OFFSPEC  = { label = "OS",  color = "00ccff" },
};

local function formatTag(tag)
    if not tag or tag == "" then return nil end
    local info = TAG_DISPLAY[tag];
    if info then
        return string.format("|cff%s%s|r", info.color, info.label);
    end
    return tag;
end

local function formatDifficultyTag(difficulty)
    if not difficulty then return nil end
    local dc = DIFF_COLORS[difficulty];
    if dc then
        return string.format("|cff%02x%02x%02x%s|r", dc.r * 255, dc.g * 255, dc.b * 255, difficulty);
    end
    return difficulty;
end

local function clearChildren(parent, ...)
    local exclude = {};
    for _, frame in ipairs({ ... }) do
        exclude[frame] = true;
    end
    for _, child in ipairs({ parent:GetChildren() }) do
        if not exclude[child] then
            child:Hide();
            child:SetParent(nil);
        end
    end
end

local function createSubFilterBtn(btnParent, label, width)
    local btn = CreateFrame("Button", nil, btnParent, "BackdropTemplate");
    btn:SetHeight(18);
    btn:SetWidth(width);
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    });
    btn:SetBackdropColor(SUB_INACTIVE_COLOR.r, SUB_INACTIVE_COLOR.g, SUB_INACTIVE_COLOR.b, SUB_INACTIVE_COLOR.a);
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    btnText:SetPoint("CENTER", btn, "CENTER", 0, 0);
    btnText:SetText(label);
    btn.btnText = btnText;

    return btn;
end

local function setupLootFilterButtons(container, frame)
    local personalBtn = createSubFilterBtn(container, "|cffffffffPersonal|r", 70);
    personalBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -4);
    frame.personalBtn = personalBtn;

    local allDropsBtn = createSubFilterBtn(container, "|cffffffffAll Drops|r", 70);
    allDropsBtn:SetPoint("LEFT", personalBtn, "RIGHT", 4, 0);
    frame.allDropsBtn = allDropsBtn;

    local function setFilter(filter)
        frame.lootFilter = filter;
        if filter == "personal" then
            personalBtn:SetBackdropColor(SUB_ACTIVE_COLOR.r, SUB_ACTIVE_COLOR.g, SUB_ACTIVE_COLOR.b, SUB_ACTIVE_COLOR.a);
            personalBtn:SetBackdropBorderColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.5);
            allDropsBtn:SetBackdropColor(SUB_INACTIVE_COLOR.r, SUB_INACTIVE_COLOR.g, SUB_INACTIVE_COLOR.b, SUB_INACTIVE_COLOR.a);
            allDropsBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);
        else
            allDropsBtn:SetBackdropColor(SUB_ACTIVE_COLOR.r, SUB_ACTIVE_COLOR.g, SUB_ACTIVE_COLOR.b, SUB_ACTIVE_COLOR.a);
            allDropsBtn:SetBackdropBorderColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.5);
            personalBtn:SetBackdropColor(SUB_INACTIVE_COLOR.r, SUB_INACTIVE_COLOR.g, SUB_INACTIVE_COLOR.b, SUB_INACTIVE_COLOR.a);
            personalBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);
        end
        GoWWishlists:PopulateLootHistoryTab(frame);
    end

    personalBtn:SetScript("OnClick", function() setFilter("personal") end);
    allDropsBtn:SetScript("OnClick", function() setFilter("all") end);
    frame.SetLootFilter = setFilter;

    local lootEmptyText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    lootEmptyText:SetPoint("TOP", container, "TOP", 0, -56);
    lootEmptyText:Hide();
    frame.lootEmptyText = lootEmptyText;
end

local function saveFramePosition(frame, profileKey)
    if not GOW.DB or not GOW.DB.profile then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    GOW.DB.profile[profileKey] = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function restoreFramePosition(frame, profileKey, defaultPoint, defaultRelPoint, defaultX, defaultY)
    if GOW.DB and GOW.DB.profile and GOW.DB.profile[profileKey] then
        local pos = GOW.DB.profile[profileKey]
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        frame:SetPoint(defaultPoint, UIParent, defaultRelPoint, defaultX, defaultY)
    end
end

local function createAlertItemRow(parent, match, itemLink)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(ALERT_ITEM_ROW_HEIGHT);

    local sideBar = row:CreateTexture(nil, "ARTWORK", nil, 2);
    sideBar:SetTexture("Interface\\Buttons\\WHITE8x8");
    sideBar:SetVertexColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.8);
    sideBar:SetWidth(3);
    sideBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0);
    sideBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0);

    local icon = row:CreateTexture(nil, "ARTWORK");
    icon:SetSize(32, 32);
    icon:SetPoint("LEFT", row, "LEFT", 10, 0);
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    row.icon = icon;

    local iconBorder = row:CreateTexture(nil, "ARTWORK", nil, 0);
    iconBorder:SetTexture("Interface\\Buttons\\WHITE8x8");
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1);
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1);
    iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.8);
    row.iconBorder = iconBorder;

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1);
    nameText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    row.nameText = nameText;

    local tagText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    tagText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2);
    tagText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    tagText:SetJustifyH("LEFT");
    row.tagText = tagText;

    local statGainText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    statGainText:SetPoint("TOPLEFT", tagText, "BOTTOMLEFT", 0, -2);
    statGainText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    statGainText:SetJustifyH("LEFT");
    row.statGainText = statGainText;

    local sep = row:CreateTexture(nil, "ARTWORK");
    sep:SetTexture("Interface\\Buttons\\WHITE8x8");
    sep:SetVertexColor(0.3, 0.3, 0.3, 0.2);
    sep:SetHeight(1);
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 0);
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 0);

    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(match.itemId);
    row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark");

    if itemQuality then
        local r, g, b = C_Item.GetItemQualityColor(itemQuality);
        row.iconBorder:SetVertexColor(r, g, b, 0.9);
    end

    row.nameText:SetText(itemLink or itemName or ("Item:" .. tostring(match.itemId)));

    if not itemName then
        registerPendingItem(match.itemId, function()
            if row:GetParent() then
                local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(match.itemId);
                if name then
                    row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark");
                    if quality then
                        local r, g, b = C_Item.GetItemQualityColor(quality);
                        row.iconBorder:SetVertexColor(r, g, b, 0.9);
                    end
                    row.nameText:SetText(itemLink or name);
                end
            end
        end);
    end

    local tags = {};
    if match.difficulty then
        table.insert(tags, formatDifficultyTag(match.difficulty));
    end
    local tagLabel = formatTag(match.tag);
    if tagLabel then table.insert(tags, tagLabel) end
    if match.notes and match.notes ~= "" then
        table.insert(tags, "|cffaaaaaa\"" .. match.notes .. "\"|r");
    end
    row.tagText:SetText(table.concat(tags, "  "));

    local gain = match.gain;
    if gain and (gain.stat or gain.percent) then
        local statParts = {};
        if gain.stat and gain.stat > 0 then
            table.insert(statParts, "+" .. gain.stat);
        end
        if gain.percent and gain.percent > 0 then
            local metric = gain.metric or "";
            table.insert(statParts, string.format("(+%.1f%% %s)", gain.percent, metric));
        end
        if #statParts > 0 then
            row.statGainText:SetText("|cff00ff00" .. table.concat(statParts, " ") .. "|r");
        else
            row.statGainText:SetText("");
        end
    else
        row.statGainText:SetText("");
    end

    row:EnableMouse(true);
    row.itemId = match.itemId;
    row:SetScript("OnEnter", function(self)
        if self.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:SetItemByID(self.itemId);
            GameTooltip:Show();
        end
    end);
    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide();
    end);

    return row;
end

local function createWishlistAlertContainer()
    if wishlistAlertContainer then return wishlistAlertContainer end

    local frame = CreateFrame("Frame", "GoWWishlistAlertContainer", UIParent, "BackdropTemplate");
    frame:SetSize(360, 60);
    restoreFramePosition(frame, "wishlistInfoFramePos", "TOP", "TOP", 0, -120);
    frame:SetFrameStrata("DIALOG");
    frame:SetFrameLevel(200);
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", frame.StartMoving);
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing();
        saveFramePosition(self, "wishlistInfoFramePos");
    end);
    frame:SetClampedToScreen(true);

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    });
    frame:SetBackdropColor(GOW_BG_COLOR.r, GOW_BG_COLOR.g, GOW_BG_COLOR.b, 0.92);
    frame:SetBackdropBorderColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.7);

    local topStripe = frame:CreateTexture(nil, "ARTWORK");
    topStripe:SetTexture("Interface\\Buttons\\WHITE8x8");
    topStripe:SetVertexColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.9);
    topStripe:SetHeight(2);
    topStripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1);
    topStripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1);

    local glow = frame:CreateTexture(nil, "ARTWORK", nil, 1);
    glow:SetTexture("Interface\\Buttons\\WHITE8x8");
    glow:SetGradient("VERTICAL", CreateColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0), CreateColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.08));
    glow:SetHeight(30);
    glow:SetPoint("TOPLEFT", topStripe, "BOTTOMLEFT", 0, 0);
    glow:SetPoint("TOPRIGHT", topStripe, "BOTTOMRIGHT", 0, 0);

    local headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    headerText:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -8);
    headerText:SetText("|cff00ff00WISHLIST MATCHES|r");
    frame.headerText = headerText;

    local brandText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    brandText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 4);
    brandText:SetText("|cff00ff00Guilds of WoW|r");
    brandText:SetAlpha(0.5);

    local closeBtn = CreateFrame("Button", nil, frame);
    closeBtn:SetSize(16, 16);
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4);
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton");
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton");
    closeBtn:GetHighlightTexture():SetAlpha(0.3);
    closeBtn:SetScript("OnClick", function()
        frame:Hide();
        if frame.dismissTimer then frame.dismissTimer:Cancel(); frame.dismissTimer = nil end
    end);

    -- Fade-in animation
    local fadeInGroup = frame:CreateAnimationGroup();
    local fadeInAnim = fadeInGroup:CreateAnimation("Alpha");
    fadeInAnim:SetFromAlpha(0);
    fadeInAnim:SetToAlpha(1);
    fadeInAnim:SetDuration(0.5);
    fadeInAnim:SetSmoothing("OUT");
    fadeInGroup:SetScript("OnFinished", function()
        frame:SetAlpha(1);
    end);
    frame.fadeIn = fadeInGroup;

    -- Fade-out animation group
    local fadeOut = frame:CreateAnimationGroup();
    local fadeAnim = fadeOut:CreateAnimation("Alpha");
    fadeAnim:SetFromAlpha(1);
    fadeAnim:SetToAlpha(0);
    fadeAnim:SetDuration(ALERT_FADE_TIME);
    fadeAnim:SetSmoothing("IN");
    fadeOut:SetScript("OnFinished", function()
        frame:Hide();
        frame:SetAlpha(1);
        -- Clear item rows when fully dismissed
        for _, row in ipairs(frame.itemRows or {}) do
            row:Hide();
            row:SetParent(nil);
        end
        frame.itemRows = {};
    end);
    frame.fadeOut = fadeOut;

    -- Right-click to dismiss
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            self:Hide();
            if self.dismissTimer then self.dismissTimer:Cancel(); self.dismissTimer = nil end
            for _, row in ipairs(self.itemRows or {}) do
                row:Hide();
                row:SetParent(nil);
            end
            self.itemRows = {};
        end
    end);

    frame.itemRows = {};
    frame:Hide();
    wishlistAlertContainer = frame;
    return frame;
end

local function relayoutAlertContainer(frame)
    local HEADER_HEIGHT = 22;
    local FOOTER_HEIGHT = 18;
    local yOffset = HEADER_HEIGHT;

    for _, row in ipairs(frame.itemRows) do
        row:ClearAllPoints();
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -yOffset);
        row:SetPoint("RIGHT", frame, "RIGHT", -4, 0);
        row:Show();
        yOffset = yOffset + ALERT_ITEM_ROW_HEIGHT;
    end

    frame:SetHeight(yOffset + FOOTER_HEIGHT);
end

local function ShowWishlistInfoFrame(match, itemLink)
    local frame = createWishlistAlertContainer();

    if frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end
    if frame.dismissTimer then frame.dismissTimer:Cancel(); frame.dismissTimer = nil end
    frame:SetAlpha(1);

    local row = createAlertItemRow(frame, match, itemLink);
    table.insert(frame.itemRows, row);

    if #frame.itemRows == 1 then
        frame.headerText:SetText("|cff00ff00WISHLIST MATCH|r");
    else
        frame.headerText:SetText("|cff00ff00WISHLIST MATCHES|r  |cffaaaaaa(" .. #frame.itemRows .. ")|r");
    end

    relayoutAlertContainer(frame);

    if not frame:IsShown() then
        frame:SetAlpha(0);
        frame:Show();
        frame.fadeIn:Play();
    end

    frame.dismissTimer = C_Timer.NewTimer(ALERT_DISPLAY_TIME, function()
        if frame:IsShown() then
            frame.fadeOut:Play();
        end
    end);
end

local function onStartLootRoll(rollID)
    local inInstance, instanceType = IsInInstance();
    if not inInstance or instanceType ~= "raid" then
        return;
    end

    C_Timer.After(0.1, function()
        local itemLink, itemId

        if GetLootRollItemLink then
            itemLink = GetLootRollItemLink(rollID)
        end

        if not itemLink then return end

        itemId = tonumber(itemLink:match("item:(%d+)"));
        if not itemId then return end

        local match = GoWWishlists:FindWishlistMatch(itemId);
        if match then
            C_Timer.After(0.05, function()
                ShowWishlistInfoFrame(match, itemLink);
            end);
        end
    end)
end

function GoWWishlists:Initialize()
    if not ns.WISHLISTS then GOW.Logger:Debug("No wishlist data found. Skipping wishlist initialization.") return end

    self:BuildWishlistIndex();
    self:HandleLootDropEvents();
    self:HandleLootHistoryEvents();
    self:HandleLootInfoEvents();

    GOW.Logger:Debug("Wishlist module initialized.");
end

function GoWWishlists:HandleLootInfoEvents()
    local itemInfoFrame = CreateFrame("Frame");
    itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED");

    itemInfoFrame:SetScript("OnEvent", function(_, event, itemId, success)
        if event == "GET_ITEM_INFO_RECEIVED" and success then
            onItemInfoReceived(itemId);
        end
    end);
end

function GoWWishlists:HandleLootDropEvents()
    local lootFrame = CreateFrame("Frame");
    lootFrame:RegisterEvent("START_LOOT_ROLL");

    lootFrame:SetScript("OnEvent", function(self, event, rollID)
        if event == "START_LOOT_ROLL" then
            onStartLootRoll(rollID);
        end
    end);
end

function GoWWishlists:HandleLootHistoryEvents()
    local lootHistoryFrame = CreateFrame("Frame");
    lootHistoryFrame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP");
    lootHistoryFrame:RegisterEvent("LOOT_HISTORY_UPDATE_ENCOUNTER");

    lootHistoryFrame:SetScript("OnEvent", function(_, event, encounterID, lootListID)
        if event == "LOOT_HISTORY_UPDATE_DROP" and encounterID and lootListID then
            GoWWishlists:ProcessLootHistoryDrop(encounterID, lootListID);
        elseif event == "LOOT_HISTORY_UPDATE_ENCOUNTER" and encounterID then
            GoWWishlists:ProcessLootHistoryEncounter(encounterID);
        end
    end);
end

local function RecordLootHistory(itemId, itemLink, encounterName, difficulty, timestamp)
    if not GOW.DB or not GOW.DB.profile then return end

    local history = GOW.DB.profile.lootHistory;
    if not history then
        GOW.DB.profile.lootHistory = {};
        history = GOW.DB.profile.lootHistory;
    end

    table.insert(history, {
        itemId = itemId,
        itemLink = itemLink,
        encounterName = encounterName,
        difficulty = difficulty,
        timestamp = timestamp or GetServerTime(),
    });

end

local function RecordAllLootDrop(itemId, itemLink, encounterName, difficulty, winnerName, timestamp)
    if not GOW.DB or not GOW.DB.profile then return end

    local allHistory = GOW.DB.profile.allLootHistory;
    if not allHistory then
        GOW.DB.profile.allLootHistory = {};
        allHistory = GOW.DB.profile.allLootHistory;
    end

    table.insert(allHistory, {
        itemId = itemId,
        itemLink = itemLink,
        encounterName = encounterName,
        difficulty = difficulty,
        winner = winnerName or "Unknown",
        timestamp = timestamp or GetServerTime(),
    });

end

local function isLootRecorded(history, itemId, encounterName, matchKey, matchValue)
    for _, record in ipairs(history) do
        if record.itemId == itemId and record.encounterName == encounterName
            and (not matchKey or record[matchKey] == matchValue)
            and record.timestamp and (GetServerTime() - record.timestamp) < 300 then
            return true;
        end
    end
    return false;
end

local function isAllLootAlreadyRecorded(itemId, encounterName, winnerName)
    local allHistory = GOW.DB and GOW.DB.profile and GOW.DB.profile.allLootHistory or {};
    return isLootRecorded(allHistory, itemId, encounterName, "winner", winnerName);
end

local function MarkWishlistObtained(itemId, difficulty)
    for _, entry in ipairs(allItems) do
        if entry.itemId == itemId
            and (not difficulty or entry.difficulty == difficulty)
            and not entry.isObtained then
            entry.isObtained = true;
            GOW.Logger:Debug("Wishlist item marked obtained: " .. tostring(itemId) .. " (" .. tostring(entry.difficulty) .. ")");

            local indexed = wishlistIndex[itemId];
            if indexed then
                for i = #indexed, 1, -1 do
                    if indexed[i] == entry then
                        table.remove(indexed, i);
                        break;
                    end
                end
                if #indexed == 0 then
                    wishlistIndex[itemId] = nil;
                end
            end

            return true;
        end
    end

    return false;
end

local function processDropInfo(dropInfo, encounterID, encounterName, difficulty)
    if not dropInfo then return end

    local itemLink = dropInfo.itemHyperlink;
    if not itemLink then return end

    local itemId = tonumber(itemLink:match("item:(%d+)"));
    if not itemId then return end

    if not encounterName then
        local encounterInfo = C_LootHistory.GetInfoForEncounter(encounterID);
        encounterName = encounterInfo and encounterInfo.encounterName or "Unknown";
    end
    if not difficulty then
        difficulty = getCurrentDifficultyName();
    end

    local winner = dropInfo.winner;
    local winnerName = winner and (winner.name or winner.playerName) or nil;

    -- Record to all-loot history for any winner
    if winnerName and not isAllLootAlreadyRecorded(itemId, encounterName, winnerName) then
        RecordAllLootDrop(itemId, itemLink, encounterName, difficulty, winnerName);
    end

    -- Personal loot history + wishlist tracking only for self
    if winner and winner.isSelf then
        GOW.Logger:Debug(string.format("Player won item %s (%d) from %s", itemLink, itemId, encounterName));

        local history = GOW.DB and GOW.DB.profile and GOW.DB.profile.lootHistory or {};
        local alreadyRecorded = isLootRecorded(history, itemId, encounterName);

        if not alreadyRecorded then
            RecordLootHistory(itemId, itemLink, encounterName, difficulty);
            local wasOnWishlist = MarkWishlistObtained(itemId, difficulty);
            if wasOnWishlist then
                GOW.Logger:PrintSuccessMessage(itemLink .. " obtained! Removed from your wishlist.");
            end
        end
    end

    return winnerName ~= nil; -- true if winner was resolved
end

function GoWWishlists:ProcessLootHistoryDrop(encounterID, lootListID)
    if not C_LootHistory or not C_LootHistory.GetSortedInfoForDrop then return end

    local dropInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID);
    local resolved = processDropInfo(dropInfo, encounterID);

    -- If winner isn't known yet (rolls in progress), retry after rolls end (~30s)
    if not resolved and dropInfo and dropInfo.itemHyperlink then
        C_Timer.After(32, function()
            local retryInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID);
            processDropInfo(retryInfo, encounterID);
        end);
    end
end

function GoWWishlists:ProcessLootHistoryEncounter(encounterID)
    if not C_LootHistory or not C_LootHistory.GetSortedDropsForEncounter then return end

    local drops = C_LootHistory.GetSortedDropsForEncounter(encounterID);
    if not drops then return end

    -- GetSortedDropsForEncounter returns {lootListID, itemHyperlink} per entry
    -- but does NOT include winner info. Use GetSortedInfoForDrop per drop for full details.
    local encounterInfo = C_LootHistory.GetInfoForEncounter(encounterID);
    local encounterName = encounterInfo and encounterInfo.encounterName or "Unknown";
    local difficulty = getCurrentDifficultyName();

    for _, dropEntry in ipairs(drops) do
        if dropEntry.lootListID and C_LootHistory.GetSortedInfoForDrop then
            local dropInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, dropEntry.lootListID);
            processDropInfo(dropInfo, encounterID, encounterName, difficulty);
        end
    end
end

-- Wishlist Browser Frame
local wishlistBrowserFrame = nil;
local BROWSER_ITEM_HEIGHT = 28;
local BROWSER_BOSS_HEADER_HEIGHT = 24;

local function collectWishlistForCharacter()
    local bossGroups = {};
    local bossOrder = {};
    local unknownItems = {};

    for _, entry in ipairs(allItems) do
        if not entry.isObtained then
            local bossName = entry.sourceBossName;
            if bossName then
                if not bossGroups[bossName] then
                    bossGroups[bossName] = {};
                    table.insert(bossOrder, bossName);
                end
                table.insert(bossGroups[bossName], entry);
            else
                table.insert(unknownItems, entry);
            end
        end
    end

    return bossGroups, bossOrder, unknownItems;
end

local function createItemRow(parent)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(BROWSER_ITEM_HEIGHT);

    local iconBorder = row:CreateTexture(nil, "ARTWORK", nil, 0);
    iconBorder:SetTexture("Interface\\Buttons\\WHITE8x8");
    iconBorder:SetSize(24, 24);
    iconBorder:SetPoint("LEFT", row, "LEFT", 23, 0);
    iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.6);
    row.iconBorder = iconBorder;

    local icon = row:CreateTexture(nil, "ARTWORK", nil, 1);
    icon:SetSize(22, 22);
    icon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0);
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    row.icon = icon;

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    row.nameText = nameText;

    local tagText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    tagText:SetPoint("LEFT", nameText, "RIGHT", 8, 0);
    tagText:SetJustifyH("LEFT");
    row.tagText = tagText;

    local noteIcon = CreateFrame("Button", nil, row);
    noteIcon:SetSize(16, 16);
    noteIcon:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    local noteIconTex = noteIcon:CreateTexture(nil, "ARTWORK");
    noteIconTex:SetAllPoints();
    noteIconTex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up");

    local statGainText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    statGainText:SetPoint("RIGHT", noteIcon, "LEFT", -8, 0);
    statGainText:SetJustifyH("RIGHT");
    row.statGainText = statGainText;

    noteIcon:SetScript("OnEnter", function(self)
        row.highlight:Show();
        if self.noteText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Note", 0, 1, 0);
            GameTooltip:AddLine(self.noteText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    noteIcon:SetScript("OnLeave", function(self)
        row.highlight:Hide();
        GameTooltip:Hide();
    end);
    noteIcon:Hide();
    row.noteIcon = noteIcon;

    local highlight = row:CreateTexture(nil, "BACKGROUND");
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8");
    highlight:SetAllPoints();
    highlight:SetVertexColor(1, 1, 1, 0.04);
    highlight:Hide();
    row.highlight = highlight;

    row:EnableMouse(true);
    row:SetScript("OnEnter", function(self)
        self.highlight:Show();
        if self.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:SetItemByID(self.itemId);
            GameTooltip:Show();
        end
    end);
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide();
        GameTooltip:Hide();
    end);

    return row;
end

local function populateItemRow(row, entry)
    row.itemId = entry.itemId;

    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(entry.itemId);
    row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark");

    if itemQuality then
        local r, g, b, hex = C_Item.GetItemQualityColor(itemQuality);
        row.iconBorder:SetVertexColor(r, g, b, 0.7);
        row.nameText:SetText("|c" .. hex .. (itemName or ("Item " .. entry.itemId)) .. "|r");
    else
        row.iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.6);
        row.nameText:SetText(itemName or ("Item " .. entry.itemId));
    end

    if not itemName then
        registerPendingItem(entry.itemId, function()
            if row:GetParent() then
                populateItemRow(row, entry);
            end
        end);
    end

    -- Tags
    local tags = {};
    if entry.difficulty then
        table.insert(tags, formatDifficultyTag(entry.difficulty));
    end
    local tagLabel = formatTag(entry.tag);
    if tagLabel then table.insert(tags, tagLabel) end
    row.tagText:SetText(table.concat(tags, " "));

    local gain = entry.gain;
    if gain and (gain.stat or gain.percent) then
        local statParts = {};
        if gain.stat and gain.stat > 0 then
            table.insert(statParts, "+" .. gain.stat);
        end
        if gain.percent and gain.percent > 0 then
            local metric = gain.metric or "";
            table.insert(statParts, string.format("(+%.1f%% %s)", gain.percent, metric));
        end
        if #statParts > 0 then
            row.statGainText:SetText("|cff00ff00" .. table.concat(statParts, " ") .. "|r");
        else
            row.statGainText:SetText("");
        end
    else
        row.statGainText:SetText("");
    end

    -- Notes icon with tooltip
    if entry.notes and entry.notes ~= "" then
        row.noteIcon.noteText = entry.notes;
        row.noteIcon:Show();
    else
        row.noteIcon.noteText = nil;
        row.noteIcon:Hide();
    end
end

local function createBossHeader(parent, bossName, itemCount)
    local header = CreateFrame("Button", nil, parent);
    header:SetHeight(BROWSER_BOSS_HEADER_HEIGHT);
    header.isCollapsed = true;
    header.itemRows = {};

    -- Collapse/expand arrow
    local arrow = header:CreateTexture(nil, "OVERLAY");
    arrow:SetSize(12, 12);
    arrow:SetPoint("LEFT", header, "LEFT", 6, 0);
    arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-UP");
    header.arrow = arrow;

    -- Left accent bar
    local bar = header:CreateTexture(nil, "ARTWORK");
    bar:SetTexture("Interface\\Buttons\\WHITE8x8");
    bar:SetVertexColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.6);
    bar:SetSize(3, 16);
    bar:SetPoint("LEFT", arrow, "RIGHT", 4, 0);

    -- Boss name
    local nameText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("LEFT", bar, "RIGHT", 6, 0);
    nameText:SetText("|cffcc00cc" .. bossName .. "|r");

    -- Item count
    local countText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    countText:SetPoint("LEFT", nameText, "RIGHT", 8, 0);
    countText:SetText("|cff888888(" .. itemCount .. ")|r");

    -- Separator line
    local sep = header:CreateTexture(nil, "ARTWORK");
    sep:SetTexture("Interface\\Buttons\\WHITE8x8");
    sep:SetVertexColor(0.3, 0.3, 0.3, 0.3);
    sep:SetHeight(1);
    sep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 6, 0);
    sep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -6, 0);

    -- Hover highlight
    local highlight = header:CreateTexture(nil, "BACKGROUND");
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8");
    highlight:SetAllPoints();
    highlight:SetVertexColor(1, 1, 1, 0.04);
    highlight:Hide();
    header:SetScript("OnEnter", function(self) highlight:Show() end);
    header:SetScript("OnLeave", function(self) highlight:Hide() end);

    return header;
end

local function updateBossHeaderArrow(header)
    if header.isCollapsed then
        header.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-UP");
    else
        header.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-UP");
    end
end

function GoWWishlists:CreateWishlistBrowserFrame()
    if wishlistBrowserFrame then return wishlistBrowserFrame end

    local frame = CreateFrame("Frame", "GoWWishlistBrowserFrame", UIParent, "BackdropTemplate");
    frame:SetSize(520, 480);
    restoreFramePosition(frame, "wishlistBrowserFramePos", "CENTER", "CENTER", 0, 0);
    frame:SetFrameStrata("HIGH");
    frame:SetFrameLevel(100);
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", frame.StartMoving);
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing();
        saveFramePosition(self, "wishlistBrowserFramePos");
    end);
    frame:SetClampedToScreen(true);

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    });
    frame:SetBackdropColor(GOW_BG_COLOR.r, GOW_BG_COLOR.g, GOW_BG_COLOR.b, 0.95);
    frame:SetBackdropBorderColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.7);

    local topStripe = frame:CreateTexture(nil, "ARTWORK");
    topStripe:SetTexture("Interface\\Buttons\\WHITE8x8");
    topStripe:SetVertexColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.9);
    topStripe:SetHeight(2);
    topStripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1);
    topStripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1);

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12);
    titleText:SetText("|cff00ff00Wishlist|r");
    frame.titleText = titleText;

    local subtitleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    subtitleText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2);
    subtitleText:SetTextColor(0.6, 0.6, 0.6, 1);
    frame.subtitleText = subtitleText;

    local brandText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    brandText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 6);
    brandText:SetText("|cff00ff00Guilds of WoW|r");
    brandText:SetAlpha(0.5);

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    closeBtn:SetSize(24, 24);
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6);
    closeBtn:SetScript("OnClick", function() frame:Hide() end);

    -- ===== TAB SYSTEM =====
    local TAB_HEIGHT = 22;
    local TAB_ACTIVE_COLOR = { r = GOW_ACCENT_COLOR.r, g = GOW_ACCENT_COLOR.g, b = GOW_ACCENT_COLOR.b, a = 0.25 };
    local TAB_INACTIVE_COLOR = { r = 0.15, g = 0.15, b = 0.18, a = 0.9 };

    local function CreateTab(parent, label, tabIndex)
        local tab = CreateFrame("Button", nil, parent, "BackdropTemplate");
        tab:SetHeight(TAB_HEIGHT);
        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 0 },
        });

        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        tabText:SetPoint("CENTER", tab, "CENTER", 0, 1);
        tabText:SetText(label);
        tab.tabText = tabText;
        tab.tabIndex = tabIndex;

        tab:SetScript("OnEnter", function(self)
            if self.tabIndex ~= parent.activeTab then
                self:SetBackdropColor(0.2, 0.2, 0.25, 0.9);
            end
        end);
        tab:SetScript("OnLeave", function(self)
            if self.tabIndex ~= parent.activeTab then
                self:SetBackdropColor(TAB_INACTIVE_COLOR.r, TAB_INACTIVE_COLOR.g, TAB_INACTIVE_COLOR.b, TAB_INACTIVE_COLOR.a);
            end
        end);

        return tab;
    end

    local wishlistTab = CreateTab(frame, "|cff00ff00Wishlist|r", 1);
    wishlistTab:SetPoint("TOPLEFT", subtitleText, "BOTTOMLEFT", -4, -4);
    wishlistTab:SetWidth(90);
    frame.wishlistTab = wishlistTab;

    local lootHistoryTab = CreateTab(frame, "|cff00ff00Loot History|r", 2);
    lootHistoryTab:SetPoint("LEFT", wishlistTab, "RIGHT", 4, 0);
    lootHistoryTab:SetWidth(100);
    frame.lootHistoryTab = lootHistoryTab;

    -- Guild Wishlists tab (only shown when guild data exists)
    local guildWishlistTab = CreateTab(frame, "|cff00ff00Guild Loot|r", 3);
    guildWishlistTab:SetPoint("LEFT", lootHistoryTab, "RIGHT", 4, 0);
    guildWishlistTab:SetWidth(90);
    guildWishlistTab:Hide();
    frame.guildWishlistTab = guildWishlistTab;

    local tabIndicator = frame:CreateTexture(nil, "ARTWORK", nil, 2);
    tabIndicator:SetTexture("Interface\\Buttons\\WHITE8x8");
    tabIndicator:SetVertexColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.9);
    tabIndicator:SetHeight(2);
    frame.tabIndicator = tabIndicator;

    -- Content area starts below tabs
    -- ===== WISHLIST SCROLL FRAME =====
    local scrollFrame = CreateFrame("ScrollFrame", "GoWWishlistBrowserScrollFrame", frame, "UIPanelScrollFrameTemplate");
    scrollFrame:SetPoint("TOPLEFT", wishlistTab, "BOTTOMLEFT", -4, -8);
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 24);

    local scrollChild = CreateFrame("Frame", nil, scrollFrame);
    scrollChild:SetWidth(scrollFrame:GetWidth());
    scrollChild:SetHeight(1);
    scrollFrame:SetScrollChild(scrollChild);
    frame.scrollChild = scrollChild;
    frame.scrollFrame = scrollFrame;

    -- ===== LOOT HISTORY SCROLL FRAME =====
    local lootScrollFrame = CreateFrame("ScrollFrame", "GoWLootHistoryScrollFrame", frame, "UIPanelScrollFrameTemplate");
    lootScrollFrame:SetPoint("TOPLEFT", wishlistTab, "BOTTOMLEFT", -4, -8);
    lootScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 24);

    local lootScrollChild = CreateFrame("Frame", nil, lootScrollFrame);
    lootScrollChild:SetWidth(lootScrollFrame:GetWidth());
    lootScrollChild:SetHeight(1);
    lootScrollFrame:SetScrollChild(lootScrollChild);
    frame.lootScrollChild = lootScrollChild;
    frame.lootScrollFrame = lootScrollFrame;

    -- Loot history sub-filter: Personal / All Drops
    frame.lootFilter = "personal"; -- "personal" or "all"
    setupLootFilterButtons(lootScrollChild, frame);

    -- ===== GUILD WISHLISTS SCROLL FRAME =====
    local guildScrollFrame = CreateFrame("ScrollFrame", "GoWGuildWishlistScrollFrame", frame, "UIPanelScrollFrameTemplate");
    guildScrollFrame:SetPoint("TOPLEFT", wishlistTab, "BOTTOMLEFT", -4, -8);
    guildScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 24);

    local guildScrollChild = CreateFrame("Frame", nil, guildScrollFrame);
    guildScrollChild:SetWidth(guildScrollFrame:GetWidth());
    guildScrollChild:SetHeight(1);
    guildScrollFrame:SetScrollChild(guildScrollChild);
    frame.guildScrollChild = guildScrollChild;
    frame.guildScrollFrame = guildScrollFrame;
    frame.guildDifficultyFilter = "All";

    -- ===== TAB SWITCHING =====
    frame.activeTab = 1;

    local allTabs = { wishlistTab, lootHistoryTab, guildWishlistTab };
    local allScrollFrames = { scrollFrame, lootScrollFrame, guildScrollFrame };

    local function SetActiveTab(tabIndex)
        frame.activeTab = tabIndex;

        -- Hide all scroll frames, deactivate all tabs
        for _, sf in ipairs(allScrollFrames) do sf:Hide() end
        for _, tab in ipairs(allTabs) do
            if tab:IsShown() then
                tab:SetBackdropColor(TAB_INACTIVE_COLOR.r, TAB_INACTIVE_COLOR.g, TAB_INACTIVE_COLOR.b, TAB_INACTIVE_COLOR.a);
                tab:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5);
            end
        end

        -- Activate selected tab
        local activeTab = allTabs[tabIndex];
        local activeSF = allScrollFrames[tabIndex];
        activeSF:Show();
        activeTab:SetBackdropColor(TAB_ACTIVE_COLOR.r, TAB_ACTIVE_COLOR.g, TAB_ACTIVE_COLOR.b, TAB_ACTIVE_COLOR.a);
        activeTab:SetBackdropBorderColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.5);
        tabIndicator:ClearAllPoints();
        tabIndicator:SetPoint("BOTTOMLEFT", activeTab, "BOTTOMLEFT", 1, 0);
        tabIndicator:SetPoint("BOTTOMRIGHT", activeTab, "BOTTOMRIGHT", -1, 0);

        if tabIndex == 1 then
            frame.titleText:SetText("|cff00ff00Wishlist|r");
            if frame.wishlistSubtitle then
                frame.subtitleText:SetText(frame.wishlistSubtitle);
            end
        elseif tabIndex == 2 then
            frame.titleText:SetText("|cff00ff00Loot History|r");
            frame.SetLootFilter(frame.lootFilter or "personal");
        elseif tabIndex == 3 then
            frame.titleText:SetText("|cff00ff00Guild Loot|r");
            GoWWishlists:PopulateGuildWishlistTab(frame);
        end
    end

    wishlistTab:SetScript("OnClick", function() SetActiveTab(1) end);
    lootHistoryTab:SetScript("OnClick", function() SetActiveTab(2) end);
    guildWishlistTab:SetScript("OnClick", function() SetActiveTab(3) end);
    frame.SetActiveTab = SetActiveTab;

    -- ESC to close
    table.insert(UISpecialFrames, "GoWWishlistBrowserFrame");

    -- Start on wishlist tab
    SetActiveTab(1);

    frame:Hide();
    wishlistBrowserFrame = frame;
    return frame;
end

-- ===== LOOT HISTORY TAB =====
local LOOT_ROW_HEIGHT = 28;

local function createLootHistoryRow(parent, showWinner)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(LOOT_ROW_HEIGHT);

    -- Icon border
    local iconBorder = row:CreateTexture(nil, "ARTWORK", nil, 0);
    iconBorder:SetTexture("Interface\\Buttons\\WHITE8x8");
    iconBorder:SetSize(24, 24);
    iconBorder:SetPoint("LEFT", row, "LEFT", 8, 0);
    iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.6);
    row.iconBorder = iconBorder;

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK", nil, 1);
    icon:SetSize(22, 22);
    icon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0);
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    row.icon = icon;

    -- Item name/link
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    row.nameText = nameText;

    -- Winner name (only for All Drops view)
    if showWinner then
        local winnerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        winnerText:SetPoint("LEFT", nameText, "RIGHT", 6, 0);
        winnerText:SetJustifyH("LEFT");
        winnerText:SetTextColor(0.4, 0.8, 1, 1);
        row.winnerText = winnerText;
    end

    -- Boss name
    local bossText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    bossText:SetJustifyH("LEFT");
    bossText:SetTextColor(0.8, 0.5, 0.8, 1);
    if showWinner and row.winnerText then
        bossText:SetPoint("LEFT", row.winnerText, "RIGHT", 8, 0);
    else
        bossText:SetPoint("LEFT", nameText, "RIGHT", 8, 0);
    end
    row.bossText = bossText;

    -- Timestamp (right side)
    local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    timeText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    timeText:SetJustifyH("RIGHT");
    timeText:SetTextColor(0.5, 0.5, 0.5, 1);
    row.timeText = timeText;

    -- Hover highlight
    local highlight = row:CreateTexture(nil, "BACKGROUND");
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8");
    highlight:SetAllPoints();
    highlight:SetVertexColor(1, 1, 1, 0.04);
    highlight:Hide();
    row.highlight = highlight;

    row:EnableMouse(true);
    row:SetScript("OnEnter", function(self)
        self.highlight:Show();
        if self.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:SetItemByID(self.itemId);
            GameTooltip:Show();
        end
    end);
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide();
        GameTooltip:Hide();
    end);

    return row;
end

local function populateLootHistoryRow(row, record)
    row.itemId = record.itemId;

    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(record.itemId);
    row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark");

    if itemQuality then
        local r, g, b, hex = C_Item.GetItemQualityColor(itemQuality);
        row.iconBorder:SetVertexColor(r, g, b, 0.7);
        row.nameText:SetText(record.itemLink or ("|c" .. hex .. (itemName or ("Item " .. record.itemId)) .. "|r"));
    else
        row.iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.6);
        row.nameText:SetText(record.itemLink or itemName or ("Item " .. tostring(record.itemId)));
    end

    -- If item data wasn't cached yet, re-populate when it arrives
    if not itemName then
        registerPendingItem(record.itemId, function()
            if row:GetParent() then
                populateLootHistoryRow(row, record);
            end
        end);
    end

    -- Winner name (All Drops view)
    if row.winnerText and record.winner then
        row.winnerText:SetText("|cff66ccff" .. record.winner .. "|r");
    elseif row.winnerText then
        row.winnerText:SetText("");
    end

    -- Difficulty tag + boss name
    local bossLabel = "";
    if record.difficulty then
        local tag = formatDifficultyTag(record.difficulty);
        bossLabel = tag .. " ";
    end
    bossLabel = bossLabel .. (record.encounterName or "Unknown");
    row.bossText:SetText(bossLabel);

    -- Timestamp
    if record.timestamp then
        row.timeText:SetText(date("%m/%d %H:%M", record.timestamp));
    else
        row.timeText:SetText("?");
    end
end

function GoWWishlists:PopulateLootHistoryTab(frame)
    local lootScrollChild = frame.lootScrollChild;
    local filter = frame.lootFilter or "personal";
    local showWinner = (filter == "all");

    clearChildren(lootScrollChild, frame.personalBtn, frame.allDropsBtn);

    frame.personalBtn:Show();
    frame.allDropsBtn:Show();
    frame.lootEmptyText:Hide();

    local history;
    if filter == "all" then
        history = GOW.DB and GOW.DB.profile and GOW.DB.profile.allLootHistory;
    else
        history = GOW.DB and GOW.DB.profile and GOW.DB.profile.lootHistory;
    end

    -- Start content below the sub-filter buttons
    local SUB_FILTER_HEIGHT = 26;

    if not history or #history == 0 then
        if filter == "all" then
            frame.lootEmptyText:SetText("|cff888888No loot drops recorded yet.|r");
        else
            frame.lootEmptyText:SetText("|cff888888No personal loot history recorded yet.|r");
        end
        frame.lootEmptyText:Show();
        frame.subtitleText:SetText("0 items recorded");
        lootScrollChild:SetHeight(SUB_FILTER_HEIGHT + 100);
        return;
    end

    frame.subtitleText:SetText(#history .. " items recorded");

    local yOffset = SUB_FILTER_HEIGHT;
    -- Show newest first
    for i = #history, 1, -1 do
        local record = history[i];
        local row = createLootHistoryRow(lootScrollChild, showWinner);
        populateLootHistoryRow(row, record);
        row:SetPoint("TOPLEFT", lootScrollChild, "TOPLEFT", 0, -yOffset);
        row:SetPoint("RIGHT", lootScrollChild, "RIGHT", 0, 0);
        row:Show();
        yOffset = yOffset + LOOT_ROW_HEIGHT;
    end

    lootScrollChild:SetHeight(yOffset + 8);
end

local function relayoutBrowserContent(frame)
    local scrollChild = frame.scrollChild;
    local yOffset = 0;

    for _, section in ipairs(frame.sections) do
        local header = section.header;
        header:ClearAllPoints();
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        header:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        header:Show();
        yOffset = yOffset + BROWSER_BOSS_HEADER_HEIGHT;

        if not header.isCollapsed then
            for _, row in ipairs(header.itemRows) do
                row:ClearAllPoints();
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                row:Show();
                yOffset = yOffset + BROWSER_ITEM_HEIGHT;
            end
        else
            for _, row in ipairs(header.itemRows) do
                row:Hide();
            end
        end

        yOffset = yOffset + 4;
    end

    scrollChild:SetHeight(yOffset + 8);
end

local function buildSections(container, scrollChild, bossGroups, bossOrder, unknownItems)
    container.sections = {};

    local function addSection(bossName, items)
        local header = createBossHeader(scrollChild, bossName, #items);
        header.isCollapsed = true;
        updateBossHeaderArrow(header);

        header.itemRows = {};
        for _, entry in ipairs(items) do
            local row = createItemRow(scrollChild);
            populateItemRow(row, entry);
            table.insert(header.itemRows, row);
        end

        header:SetScript("OnClick", function(self)
            self.isCollapsed = not self.isCollapsed;
            updateBossHeaderArrow(self);
            relayoutBrowserContent(container);
        end);

        table.insert(container.sections, { header = header });
    end

    for _, bossName in ipairs(bossOrder) do
        addSection(bossName, bossGroups[bossName]);
    end
    if #unknownItems > 0 then
        addSection("Unknown Boss", unknownItems);
    end
end

function GoWWishlists:ShowWishlistBrowserFrame()
    local frame = self:CreateWishlistBrowserFrame();

    local charName = currentCharInfo and currentCharInfo.name or UnitName("player");
    local charRealm = currentCharInfo and currentCharInfo.realmNormalized or GetNormalizedRealmName();

    -- Clear previous content
    local scrollChild = frame.scrollChild;
    clearChildren(scrollChild);
    frame.sections = {};

    -- Update scroll child widths on show
    frame:SetScript("OnShow", function(self)
        scrollChild:SetWidth(self.scrollFrame:GetWidth());
        self.lootScrollChild:SetWidth(self.lootScrollFrame:GetWidth());
        self.guildScrollChild:SetWidth(self.guildScrollFrame:GetWidth());
    end);

    -- Show guild tab if guild data exists
    if guildWishlistData and guildWishlistData.wishlists and #guildWishlistData.wishlists > 0 then
        frame.guildWishlistTab:Show();
    else
        frame.guildWishlistTab:Hide();
    end

    local bossGroups, bossOrder, unknownItems = collectWishlistForCharacter();

    local totalCount = 0;
    for _, items in pairs(bossGroups) do totalCount = totalCount + #items end
    totalCount = totalCount + #unknownItems;

    if totalCount == 0 then
        frame.subtitleText:SetText(charName .. "-" .. charRealm .. "  |  0 items");
        frame.wishlistSubtitle = frame.subtitleText:GetText();
        if not frame.wishlistEmptyText then
            frame.wishlistEmptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            frame.wishlistEmptyText:SetPoint("TOP", scrollChild, "TOP", 0, -40);
            frame.wishlistEmptyText:SetWidth(scrollChild:GetWidth() - 40);
            frame.wishlistEmptyText:SetWordWrap(true);
            frame.wishlistEmptyText:SetJustifyH("CENTER");
        end
        local msg;
        if not ns.WISHLISTS then
            msg = "No wishlist data found. Make sure your wishlist is synced via the app.";
        else
            msg = "No wishlist items found for " .. charName .. "-" .. charRealm .. ".";
        end
        frame.wishlistEmptyText:SetText("|cff888888" .. msg .. "|r");
        frame.wishlistEmptyText:Show();
        scrollChild:SetHeight(100);
    else
        if frame.wishlistEmptyText then frame.wishlistEmptyText:Hide() end
        frame.subtitleText:SetText(charName .. "-" .. charRealm .. "  |  " .. totalCount .. " items remaining");
        frame.wishlistSubtitle = frame.subtitleText:GetText();
        buildSections(frame, scrollChild, bossGroups, bossOrder, unknownItems);
        relayoutBrowserContent(frame);
    end

    -- Always open on wishlist tab
    frame.SetActiveTab(1);
    frame:Show();
end

-- ===== CORE UI TAB INTEGRATION =====
local coreWishlistScrollFrame = nil;
local coreLootScrollFrame = nil;
local coreGuildWishlistScrollFrame = nil;

function GoWWishlists:CreateCoreWishlistFrame(parent)
    if coreWishlistScrollFrame then
        coreWishlistScrollFrame:SetParent(parent);
        coreWishlistScrollFrame:SetAllPoints(parent);
        return coreWishlistScrollFrame;
    end

    local sf = CreateFrame("ScrollFrame", "GoWCoreWishlistScroll", parent, "UIPanelScrollFrameTemplate");
    sf:SetAllPoints(parent);

    local child = CreateFrame("Frame", nil, sf);
    child:SetWidth(sf:GetWidth());
    child:SetHeight(1);
    sf:SetScrollChild(child);
    sf.scrollChild = child;
    sf.sections = {};

    sf:Hide();
    coreWishlistScrollFrame = sf;
    return sf;
end

function GoWWishlists:ShowCoreWishlistTab(parent, setStatusFn)
    local sf = self:CreateCoreWishlistFrame(parent);
    local scrollChild = sf.scrollChild;
    scrollChild:SetWidth(sf:GetWidth() - 20);

    clearChildren(scrollChild);
    sf.sections = {};

    if sf.emptyText then sf.emptyText:Hide() end

    local bossGroups, bossOrder, unknownItems = collectWishlistForCharacter();
    local charName, charRealm = currentCharInfo.name, currentCharInfo.realmNormalized;

    local totalCount = 0;
    for _, items in pairs(bossGroups) do totalCount = totalCount + #items end
    totalCount = totalCount + #unknownItems;

    if totalCount == 0 then
        if not sf.emptyText then
            sf.emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            sf.emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -40);
        end
        sf.emptyText:SetText("|cff888888No wishlist items found for " .. charName .. "-" .. charRealm .. ".|r");
        sf.emptyText:Show();
        scrollChild:SetHeight(100);
        if setStatusFn then setStatusFn(charName .. "-" .. charRealm .. "  |  0 items") end
        sf:Show();
        return;
    end

    if setStatusFn then
        setStatusFn(charName .. "-" .. charRealm .. "  |  " .. totalCount .. " items remaining");
    end

    buildSections(sf, scrollChild, bossGroups, bossOrder, unknownItems);

    relayoutBrowserContent(sf);
    sf:Show();
end

function GoWWishlists:CreateCoreLootFrame(parent)
    if coreLootScrollFrame then
        coreLootScrollFrame:SetParent(parent);
        coreLootScrollFrame:SetAllPoints(parent);
        return coreLootScrollFrame;
    end

    local sf = CreateFrame("ScrollFrame", "GoWCoreLootScroll", parent, "UIPanelScrollFrameTemplate");
    sf:SetAllPoints(parent);

    local child = CreateFrame("Frame", nil, sf);
    child:SetWidth(sf:GetWidth());
    child:SetHeight(1);
    sf:SetScrollChild(child);
    sf.lootScrollChild = child;
    sf.lootFilter = "personal";

    setupLootFilterButtons(child, sf);
    sf.subtitleText = { SetText = function() end };

    sf:Hide();
    coreLootScrollFrame = sf;
    return sf;
end

function GoWWishlists:ShowCoreLootHistoryTab(parent, setStatusFn)
    local sf = self:CreateCoreLootFrame(parent);
    sf.lootScrollChild:SetWidth(sf:GetWidth() - 20);

    if setStatusFn then
        sf.subtitleText = { SetText = function(_, text) setStatusFn(text) end };
    end

    sf.SetLootFilter(sf.lootFilter or "personal");
    sf:Show();
end

function GoWWishlists:HideCoreFrames()
    if coreWishlistScrollFrame then coreWishlistScrollFrame:Hide() end
    if coreLootScrollFrame then coreLootScrollFrame:Hide() end
    if coreGuildWishlistScrollFrame then coreGuildWishlistScrollFrame:Hide() end
end

-- ===== CORE UI: GUILD WISHLISTS TAB =====

local function setupGuildDifficultyFilter(container, frame)
    local difficulties = { "All", "Normal", "Heroic", "Mythic", "LFR" };
    local btns = {};

    for i, diff in ipairs(difficulties) do
        local btn = createSubFilterBtn(container, "|cffffffff" .. diff .. "|r", 60);
        if i == 1 then
            btn:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -4);
        else
            btn:SetPoint("LEFT", btns[i - 1], "RIGHT", 4, 0);
        end
        btns[i] = btn;
    end

    local function setDiffFilter(diff)
        frame.guildDifficultyFilter = diff;
        for i, btn in ipairs(btns) do
            if difficulties[i] == diff then
                btn:SetBackdropColor(SUB_ACTIVE_COLOR.r, SUB_ACTIVE_COLOR.g, SUB_ACTIVE_COLOR.b, SUB_ACTIVE_COLOR.a);
                btn:SetBackdropBorderColor(GOW_ACCENT_COLOR.r, GOW_ACCENT_COLOR.g, GOW_ACCENT_COLOR.b, 0.5);
            else
                btn:SetBackdropColor(SUB_INACTIVE_COLOR.r, SUB_INACTIVE_COLOR.g, SUB_INACTIVE_COLOR.b, SUB_INACTIVE_COLOR.a);
                btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);
            end
        end
        GoWWishlists:PopulateGuildWishlistTab(frame);
    end

    for i, btn in ipairs(btns) do
        btn:SetScript("OnClick", function() setDiffFilter(difficulties[i]) end);
    end

    frame.guildFilterBtns = btns;
    frame.SetGuildDiffFilter = setDiffFilter;
end

function GoWWishlists:CreateCoreGuildWishlistFrame(parent)
    if coreGuildWishlistScrollFrame then
        coreGuildWishlistScrollFrame:SetParent(parent);
        coreGuildWishlistScrollFrame:SetAllPoints(parent);
        return coreGuildWishlistScrollFrame;
    end

    local sf = CreateFrame("ScrollFrame", "GoWCoreGuildWishlistScroll", parent, "UIPanelScrollFrameTemplate");
    sf:SetAllPoints(parent);

    local child = CreateFrame("Frame", nil, sf);
    child:SetWidth(sf:GetWidth());
    child:SetHeight(1);
    sf:SetScrollChild(child);
    sf.guildScrollChild = child;
    sf.guildSections = {};
    sf.guildDifficultyFilter = "All";
    sf.subtitleText = { SetText = function() end };

    sf:Hide();
    coreGuildWishlistScrollFrame = sf;
    return sf;
end

function GoWWishlists:ShowCoreGuildWishlistTab(parent, setStatusFn)
    local sf = self:CreateCoreGuildWishlistFrame(parent);
    local scrollChild = sf.guildScrollChild;
    scrollChild:SetWidth(sf:GetWidth() - 20);

    if setStatusFn then
        sf.subtitleText = { SetText = function(_, text) setStatusFn(text) end };
    end

    -- Clear previous content (preserve filter buttons)
    local exclude = {};
    for _, btn in ipairs(sf.guildFilterBtns or {}) do
        exclude[btn] = true;
    end
    for _, child in ipairs({ scrollChild:GetChildren() }) do
        if not exclude[child] then
            child:Hide();
            child:SetParent(nil);
        end
    end
    sf.guildSections = {};

    if sf.guildEmptyText then sf.guildEmptyText:Hide() end

    local playerGuild = GetGuildInfo("player");

    if not guildWishlistData or not guildWishlistData.wishlists or #guildWishlistData.wishlists == 0 then
        if not sf.guildEmptyText then
            sf.guildEmptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            sf.guildEmptyText:SetPoint("TOP", scrollChild, "TOP", 0, -40);
            sf.guildEmptyText:SetWidth(scrollChild:GetWidth() - 40);
            sf.guildEmptyText:SetWordWrap(true);
            sf.guildEmptyText:SetJustifyH("CENTER");
        end
        local msg;
        if not playerGuild then
            msg = "You are not in a guild.";
        else
            msg = "No guild wishlist data found for " .. playerGuild .. ".";
        end
        sf.guildEmptyText:SetText("|cff888888" .. msg .. "|r");
        sf.guildEmptyText:Show();
        scrollChild:SetHeight(100);
        if setStatusFn then setStatusFn(playerGuild or "No Guild") end
        sf:Show();
        return;
    end

    -- Has data — setup filter and populate
    if not sf.guildFilterBtns then
        setupGuildDifficultyFilter(scrollChild, sf);
    end
    sf.SetGuildDiffFilter(sf.guildDifficultyFilter or "All");
    sf:Show();
end

-- ===== GUILD WISHLISTS TAB =====
local GUILD_ITEM_ROW_HEIGHT = 28;
local GUILD_MEMBER_ROW_HEIGHT = 22;
local GUILD_FILTER_HEIGHT = 26;

-- Collects guild wishlist data grouped by boss, then by item, then by member.
-- Returns: bossGroups = { bossName = { items = {key = itemData}, itemOrder = {keys} } }, bossOrder = {bossNames}
local function collectGuildWishlistByBoss(difficultyFilter)
    if not guildWishlistData or not guildWishlistData.wishlists then return {}, {} end

    local bossGroups = {};
    local bossOrder = {};

    for _, charEntry in ipairs(guildWishlistData.wishlists) do
        for _, item in ipairs(charEntry.wishlist) do
            if not item.isObtained then
                local passFilter = (difficultyFilter == "All") or (item.difficulty == difficultyFilter);
                if passFilter then
                    local bossName = item.sourceBossName or "Unknown Boss";
                    if not bossGroups[bossName] then
                        bossGroups[bossName] = { items = {}, itemOrder = {} };
                        table.insert(bossOrder, bossName);
                    end

                    local boss = bossGroups[bossName];
                    local itemKey = item.itemId .. "-" .. (item.difficulty or "");
                    if not boss.items[itemKey] then
                        boss.items[itemKey] = {
                            itemId = item.itemId,
                            difficulty = item.difficulty,
                            members = {},
                        };
                        table.insert(boss.itemOrder, itemKey);
                    end

                    table.insert(boss.items[itemKey].members, {
                        characterName = charEntry.name,
                        realmName = charEntry.realmName,
                        tag = item.tag,
                        notes = item.notes,
                        officerNotes = item.officerNotes,
                        gain = item.gain,
                    });
                end
            end
        end
    end

    return bossGroups, bossOrder;
end

-- ===== Guild Item Row (shows icon + item name + difficulty + member count) =====
local function createGuildItemRow(parent)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(GUILD_ITEM_ROW_HEIGHT);

    local iconBorder = row:CreateTexture(nil, "ARTWORK", nil, 0);
    iconBorder:SetTexture("Interface\\Buttons\\WHITE8x8");
    iconBorder:SetSize(22, 22);
    iconBorder:SetPoint("LEFT", row, "LEFT", 23, 0);
    iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.6);
    row.iconBorder = iconBorder;

    local icon = row:CreateTexture(nil, "ARTWORK", nil, 1);
    icon:SetSize(20, 20);
    icon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0);
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    row.icon = icon;

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    row.nameText = nameText;

    local infoText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    infoText:SetPoint("LEFT", nameText, "RIGHT", 8, 0);
    infoText:SetJustifyH("LEFT");
    row.infoText = infoText;

    local highlight = row:CreateTexture(nil, "BACKGROUND");
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8");
    highlight:SetAllPoints();
    highlight:SetVertexColor(1, 1, 1, 0.04);
    highlight:Hide();
    row.highlight = highlight;

    row:EnableMouse(true);
    row:SetScript("OnEnter", function(self)
        self.highlight:Show();
        if self.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:SetItemByID(self.itemId);
            GameTooltip:Show();
        end
    end);
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide();
        GameTooltip:Hide();
    end);

    return row;
end

local function populateGuildItemRow(row, itemData)
    row.itemId = itemData.itemId;

    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemData.itemId);
    row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark");

    if itemQuality then
        local r, g, b, hex = C_Item.GetItemQualityColor(itemQuality);
        row.iconBorder:SetVertexColor(r, g, b, 0.7);
        row.nameText:SetText("|c" .. hex .. (itemName or ("Item " .. itemData.itemId)) .. "|r");
    else
        row.iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.6);
        row.nameText:SetText(itemName or ("Item " .. itemData.itemId));
    end

    local parts = {};
    if itemData.difficulty then
        table.insert(parts, formatDifficultyTag(itemData.difficulty));
    end
    table.insert(parts, "|cff888888(" .. #itemData.members .. ")|r");
    row.infoText:SetText(table.concat(parts, "  "));

    if not itemName then
        registerPendingItem(itemData.itemId, function()
            if row:GetParent() then
                populateGuildItemRow(row, itemData);
            end
        end);
    end
end

-- ===== Guild Member Row (shows name + tag + gain + note icons) =====
local function createGuildMemberRow(parent)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(GUILD_MEMBER_ROW_HEIGHT);

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    nameText:SetPoint("LEFT", row, "LEFT", 52, 0);
    nameText:SetJustifyH("LEFT");
    row.nameText = nameText;

    local tagText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    tagText:SetPoint("LEFT", nameText, "RIGHT", 8, 0);
    tagText:SetJustifyH("LEFT");
    row.tagText = tagText;

    local gainText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    gainText:SetPoint("LEFT", tagText, "RIGHT", 8, 0);
    gainText:SetJustifyH("LEFT");
    row.gainText = gainText;

    -- Officer note icon (rightmost)
    local officerNoteIcon = CreateFrame("Button", nil, row);
    officerNoteIcon:SetSize(14, 14);
    officerNoteIcon:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    local officerNoteTex = officerNoteIcon:CreateTexture(nil, "ARTWORK");
    officerNoteTex:SetAllPoints();
    officerNoteTex:SetTexture("Interface\\Buttons\\UI-GuildButton-OfficerNote-Up");
    officerNoteIcon:SetScript("OnEnter", function(self)
        row.highlight:Show();
        if self.noteText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Officer Note", 1, 0.5, 0);
            GameTooltip:AddLine(self.noteText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    officerNoteIcon:SetScript("OnLeave", function(self)
        row.highlight:Hide();
        GameTooltip:Hide();
    end);
    officerNoteIcon:Hide();
    row.officerNoteIcon = officerNoteIcon;

    -- Player note icon (left of officer note)
    local noteIcon = CreateFrame("Button", nil, row);
    noteIcon:SetSize(14, 14);
    noteIcon:SetPoint("RIGHT", officerNoteIcon, "LEFT", -4, 0);
    local noteIconTex = noteIcon:CreateTexture(nil, "ARTWORK");
    noteIconTex:SetAllPoints();
    noteIconTex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up");
    noteIcon:SetScript("OnEnter", function(self)
        row.highlight:Show();
        if self.noteText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Note", 0, 1, 0);
            GameTooltip:AddLine(self.noteText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    noteIcon:SetScript("OnLeave", function(self)
        row.highlight:Hide();
        GameTooltip:Hide();
    end);
    noteIcon:Hide();
    row.noteIcon = noteIcon;

    local highlight = row:CreateTexture(nil, "BACKGROUND");
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8");
    highlight:SetAllPoints();
    highlight:SetVertexColor(1, 1, 1, 0.03);
    highlight:Hide();
    row.highlight = highlight;

    row:EnableMouse(true);
    row:SetScript("OnEnter", function(self) self.highlight:Show() end);
    row:SetScript("OnLeave", function(self) self.highlight:Hide() end);

    return row;
end

local function populateGuildMemberRow(row, member)
    row.nameText:SetText("|cff66ccff" .. member.characterName .. "|r");

    local tagLabel = formatTag(member.tag);
    row.tagText:SetText(tagLabel or "");

    local gain = member.gain;
    if gain and ((gain.stat and gain.stat > 0) or (gain.percent and gain.percent > 0)) then
        local parts = {};
        if gain.stat and gain.stat > 0 then
            table.insert(parts, "+" .. gain.stat);
        end
        if gain.percent and gain.percent > 0 then
            local metric = gain.metric or "";
            table.insert(parts, string.format("(+%.1f%% %s)", gain.percent, metric));
        end
        row.gainText:SetText("|cff00ff00" .. table.concat(parts, " ") .. "|r");
    else
        row.gainText:SetText("");
    end

    if member.notes and member.notes ~= "" then
        row.noteIcon.noteText = member.notes;
        row.noteIcon:Show();
    else
        row.noteIcon.noteText = nil;
        row.noteIcon:Hide();
    end

    if member.officerNotes and member.officerNotes ~= "" then
        row.officerNoteIcon.noteText = member.officerNotes;
        row.officerNoteIcon:Show();
    else
        row.officerNoteIcon.noteText = nil;
        row.officerNoteIcon:Hide();
    end
end

-- ===== Guild Layout =====
-- guildSections = { { header, items = { { row, memberRows = {} }, ... } }, ... }
local function relayoutGuildContent(frame)
    local scrollChild = frame.guildScrollChild;
    local yOffset = GUILD_FILTER_HEIGHT;

    for _, section in ipairs(frame.guildSections or {}) do
        local header = section.header;
        header:ClearAllPoints();
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        header:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        header:Show();
        yOffset = yOffset + BROWSER_BOSS_HEADER_HEIGHT;

        if not header.isCollapsed then
            for _, itemGroup in ipairs(section.items or {}) do
                local itemRow = itemGroup.row;
                itemRow:ClearAllPoints();
                itemRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                itemRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                itemRow:Show();
                yOffset = yOffset + GUILD_ITEM_ROW_HEIGHT;

                for _, memberRow in ipairs(itemGroup.memberRows or {}) do
                    memberRow:ClearAllPoints();
                    memberRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                    memberRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                    memberRow:Show();
                    yOffset = yOffset + GUILD_MEMBER_ROW_HEIGHT;
                end
            end
        else
            for _, itemGroup in ipairs(section.items or {}) do
                itemGroup.row:Hide();
                for _, memberRow in ipairs(itemGroup.memberRows or {}) do
                    memberRow:Hide();
                end
            end
        end

        yOffset = yOffset + 4;
    end

    scrollChild:SetHeight(yOffset + 8);
end

function GoWWishlists:PopulateGuildWishlistTab(frame)
    local guildScrollChild = frame.guildScrollChild;
    local filter = frame.guildDifficultyFilter or "All";

    -- Clear previous content (preserve filter buttons)
    local exclude = {};
    for _, btn in ipairs(frame.guildFilterBtns or {}) do
        exclude[btn] = true;
    end
    for _, child in ipairs({ guildScrollChild:GetChildren() }) do
        if not exclude[child] then
            child:Hide();
            child:SetParent(nil);
        end
    end

    -- Setup filter buttons on first call
    if not frame.guildFilterBtns then
        setupGuildDifficultyFilter(guildScrollChild, frame);
        frame.SetGuildDiffFilter(filter);
        return; -- SetGuildDiffFilter calls PopulateGuildWishlistTab again
    end

    local bossGroups, bossOrder = collectGuildWishlistByBoss(filter);

    -- Count unique members and total unique items
    local memberSet = {};
    local totalItems = 0;
    for _, bossName in ipairs(bossOrder) do
        local boss = bossGroups[bossName];
        for _, itemKey in ipairs(boss.itemOrder) do
            totalItems = totalItems + 1;
            for _, member in ipairs(boss.items[itemKey].members) do
                memberSet[member.characterName] = true;
            end
        end
    end
    local memberCount = 0;
    for _ in pairs(memberSet) do memberCount = memberCount + 1 end

    local guildName = guildWishlistData and guildWishlistData.guild or "Guild";
    frame.subtitleText:SetText(guildName .. "  |  " .. memberCount .. " members  |  " .. totalItems .. " items");

    if totalItems == 0 then
        if not frame.guildEmptyText then
            frame.guildEmptyText = guildScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            frame.guildEmptyText:SetPoint("TOP", guildScrollChild, "TOP", 0, -56);
            frame.guildEmptyText:SetWidth(guildScrollChild:GetWidth() - 40);
            frame.guildEmptyText:SetWordWrap(true);
            frame.guildEmptyText:SetJustifyH("CENTER");
        end
        local msg;
        if not ns.WISHLISTS then
            msg = "No wishlist data found. Make sure your wishlist is synced via the app.";
        elseif not guildWishlistData then
            msg = "No guild wishlist data found. You may not be in a guild, or your guild has no wishlists synced.";
        else
            msg = "No guild wishlist items" .. (filter ~= "All" and (" for " .. filter) or "") .. ".";
        end
        frame.guildEmptyText:SetText("|cff888888" .. msg .. "|r");
        frame.guildEmptyText:Show();
        guildScrollChild:SetHeight(GUILD_FILTER_HEIGHT + 100);
        frame.guildSections = {};
        return;
    end

    if frame.guildEmptyText then frame.guildEmptyText:Hide() end

    -- Build sections: Boss → Items → Members
    frame.guildSections = {};
    for _, bossName in ipairs(bossOrder) do
        local boss = bossGroups[bossName];
        local header = createBossHeader(guildScrollChild, bossName, #boss.itemOrder);
        header.isCollapsed = true;
        updateBossHeaderArrow(header);

        local items = {};
        for _, itemKey in ipairs(boss.itemOrder) do
            local itemData = boss.items[itemKey];

            local itemRow = createGuildItemRow(guildScrollChild);
            populateGuildItemRow(itemRow, itemData);

            local memberRows = {};
            for _, member in ipairs(itemData.members) do
                local memberRow = createGuildMemberRow(guildScrollChild);
                populateGuildMemberRow(memberRow, member);
                table.insert(memberRows, memberRow);
            end

            table.insert(items, { row = itemRow, memberRows = memberRows });
        end

        header:SetScript("OnClick", function(self)
            self.isCollapsed = not self.isCollapsed;
            updateBossHeaderArrow(self);
            relayoutGuildContent(frame);
        end);

        table.insert(frame.guildSections, { header = header, items = items });
    end

    relayoutGuildContent(frame);
end

function GoWWishlists:HandleGuildSlashCommand()
    local frame = self:CreateWishlistBrowserFrame();

    -- Show guild tab and switch to it
    frame.guildWishlistTab:Show();

    -- Set subtitle context
    local charName = currentCharInfo and currentCharInfo.name or UnitName("player");
    local charRealm = currentCharInfo and currentCharInfo.realmNormalized or GetNormalizedRealmName();
    frame.wishlistSubtitle = charName .. "-" .. charRealm;

    -- Ensure scroll child widths are set
    frame.scrollChild:SetWidth(frame.scrollFrame:GetWidth());
    frame.lootScrollChild:SetWidth(frame.lootScrollFrame:GetWidth());
    frame.guildScrollChild:SetWidth(frame.guildScrollFrame:GetWidth());

    frame.SetActiveTab(3);
    frame:Show();
end

function GoWWishlists:SimulateLootDrops(count)
    if not ns.WISHLISTS then
        GOW.Logger:PrintErrorMessage("No wishlist data found.");
        return;
    end

    -- Collect all non-obtained items from every wishlist source
    local pool = {};
    local personalLists = ns.WISHLISTS.personalWishlists;
    if personalLists then
        for _, charEntry in ipairs(personalLists) do
            for _, item in ipairs(charEntry.wishlist) do
                if not item.isObtained then
                    table.insert(pool, item);
                end
            end
        end
    end
    local guildLists = ns.WISHLISTS.guildWishlists;
    if guildLists then
        for _, guildEntry in ipairs(guildLists) do
            for _, charEntry in ipairs(guildEntry.wishlists) do
                for _, item in ipairs(charEntry.wishlist) do
                    if not item.isObtained then
                        table.insert(pool, item);
                    end
                end
            end
        end
    end

    if #pool == 0 then
        GOW.Logger:PrintMessage("No wishlist items available to simulate.");
        return;
    end

    count = math.min(count, #pool);

    -- Shuffle and pick `count` unique items
    for i = #pool, 2, -1 do
        local j = math.random(1, i);
        pool[i], pool[j] = pool[j], pool[i];
    end

    GOW.Logger:PrintMessage("Simulating " .. count .. " loot drop(s)...");

    for i = 1, count do
        local item = pool[i];
        local delay = (i - 1) * 0.3;
        C_Timer.After(delay, function()
            ShowWishlistInfoFrame(item, nil);
        end);
    end
end

function GoWWishlists:HandleSlashCommand()
    self:ShowWishlistBrowserFrame();
end