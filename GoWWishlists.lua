local GOW = GuildsOfWow;
local GoWWishlists = {};
GOW.Wishlists = GoWWishlists;

local ns = select(2, ...);

GoWWishlists.state = {
    wishlistIndex = {},
    allItems = {},
    currentCharInfo = nil,
    guildWishlistData = nil,
    pendingItemRows = {},
};

GoWWishlists.frames = {};
GoWWishlists.constants = {};

function GoWWishlists:RegisterPendingItem(itemId, callback)
    if not self.state.pendingItemRows[itemId] then
        self.state.pendingItemRows[itemId] = {};
    end
    table.insert(self.state.pendingItemRows[itemId], callback);
end

function GoWWishlists:OnItemInfoReceived(itemId)
    local callbacks = self.state.pendingItemRows[itemId];
    if not callbacks then return end
    self.state.pendingItemRows[itemId] = nil;
    for _, cb in ipairs(callbacks) do
        cb();
    end
end

GoWWishlists.constants.DIFFICULTY_NAMES = {
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

function GoWWishlists:GetCurrentCharacterInfo()
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
    self.state.wishlistIndex = {};
    self.state.allItems = {};
    self.state.guildWishlistData = nil;

    self.state.currentCharInfo = self:GetCurrentCharacterInfo();
    local charInfo = self.state.currentCharInfo;

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

                    table.insert(self.state.allItems, item);

                    if not item.isObtained then
                        local key = item.itemId;
                        self.state.wishlistIndex[key] = self.state.wishlistIndex[key] or {};
                        table.insert(self.state.wishlistIndex[key], item);
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
            self.state.guildWishlistData = guildLists[1];
        else
            local playerGuild = GetGuildInfo("player");
            if playerGuild then
                for _, guildEntry in ipairs(guildLists) do
                    local guildRealm = guildEntry.guildRealmNormalized and guildEntry.guildRealmNormalized:lower() or "";
                    if guildEntry.guild == playerGuild and guildRealm == charInfo.realmLower then
                        self.state.guildWishlistData = guildEntry;
                        break;
                    end
                end
            end
        end
    end

    for _, entry in ipairs(self.state.allItems) do
        C_Item.GetItemInfo(entry.itemId);
    end

    GOW.Logger:Debug("Wishlist index built: " .. #self.state.allItems .. " items indexed for " .. charInfo.nameLower .. "-" .. charInfo.realmLower);
end

function GoWWishlists:GetCurrentDifficultyName()
    local _, _, difficultyId = GetInstanceInfo();
    return self.constants.DIFFICULTY_NAMES[difficultyId];
end

function GoWWishlists:FindWishlistMatch(itemId)
    local entries = self.state.wishlistIndex[itemId];
    if not entries then
        return nil;
    end

    local difficulty = self:GetCurrentDifficultyName();

    for _, entry in ipairs(entries) do
        if entry.difficulty == difficulty
            and not entry.isObtained then
            return entry;
        end
    end

    return nil;
end


-- Wishlist Loot Alert Container Frame
GoWWishlists.constants.ALERT_ITEM_ROW_HEIGHT = 66;
GoWWishlists.constants.ALERT_DISPLAY_TIME = 60;
GoWWishlists.constants.ALERT_FADE_TIME = 1.5;

GoWWishlists.constants.GOW_ACCENT_COLOR = { r = 0.1, g = 0.8, b = 0.3 };
GoWWishlists.constants.GOW_BG_COLOR = { r = 0.08, g = 0.08, b = 0.1 };

GoWWishlists.constants.DIFF_COLORS = {
    ["Mythic"]      = { r = 0.616, g = 0, b = 1 },
    ["Heroic"]      = { r = 0, g = 0.439, b = 0.867 },
    ["Normal"]      = { r = 0.118, g = 1, b = 0 },
    ["LFR"]         = { r = 1, g = 0.820, b = 0 },
    ["Timewalking"] = { r = 0, g = 0.8, b = 1 },
};

GoWWishlists.constants.DIFF_ABBREV = {
    ["Mythic"]      = "M",
    ["Heroic"]      = "H",
    ["Normal"]      = "N",
    ["LFR"]         = "LFR",
    ["Timewalking"] = "TW",
};

GoWWishlists.constants.SUB_ACTIVE_COLOR = { r = GoWWishlists.constants.GOW_ACCENT_COLOR.r, g = GoWWishlists.constants.GOW_ACCENT_COLOR.g, b = GoWWishlists.constants.GOW_ACCENT_COLOR.b, a = 0.3 };
GoWWishlists.constants.SUB_INACTIVE_COLOR = { r = 0.15, g = 0.15, b = 0.18, a = 0.8 };

GoWWishlists.constants.TAG_DISPLAY = {
    BIS      = { label = "BiS", color = "ff8000" },
    NEED     = { label = "N",   color = "ff0000" },
    GREED    = { label = "G",   color = "00ff00" },
    MINOR    = { label = "MU",  color = "ffff00" },
    TRANSMOG = { label = "T",   color = "ff69b4" },
    OFFSPEC  = { label = "OS",  color = "00ccff" },
};

function GoWWishlists:FormatTag(tag)
    if not tag or tag == "" then return nil end
    local info = self.constants.TAG_DISPLAY[tag];
    if info then
        return string.format("|cff%s%s|r", info.color, info.label);
    end
    return tag;
end

-- Class color lookup
function GoWWishlists:GetClassColor(classId)
    if not classId then return nil end
    local _, classFile = GetClassInfo(classId);
    if classFile then
        local GetClassColorFunc = GetClassColorObj or C_ClassColor.GetClassColor;
        local color = GetClassColorFunc(classFile);
        if color then return color end
    end
    return nil;
end

function GoWWishlists:ClassColorToHex(color)
    if not color then return "ffffff" end
    return string.format("%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255);
end

function GoWWishlists:FormatDifficultyTag(difficulty)
    if not difficulty then return nil end
    local dc = self.constants.DIFF_COLORS[difficulty];
    local abbrev = self.constants.DIFF_ABBREV[difficulty] or difficulty;
    if dc then
        return string.format("|cff%02x%02x%02x%s|r", dc.r * 255, dc.g * 255, dc.b * 255, abbrev);
    end
    return abbrev;
end

function GoWWishlists:ClearChildren(parent, ...)
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
    -- Also hide regions (FontStrings, Textures) that aren't child frames
    for _, region in ipairs({ parent:GetRegions() }) do
        region:Hide();
        region:SetParent(nil);
    end
end

function GoWWishlists:CreateSubFilterBtn(btnParent, label, width)
    local btn = CreateFrame("Button", nil, btnParent, "BackdropTemplate");
    btn:SetHeight(18);
    btn:SetWidth(width);
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    });
    btn:SetBackdropColor(self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a);
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    btnText:SetPoint("CENTER", btn, "CENTER", 0, 0);
    btnText:SetText(label);
    btn.btnText = btnText;

    return btn;
end

function GoWWishlists:SetupLootFilterButtons(container, frame)
    local personalBtn = self:CreateSubFilterBtn(container, "|cffffffffPersonal|r", 70);
    personalBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -4);
    frame.personalBtn = personalBtn;

    local allDropsBtn = self:CreateSubFilterBtn(container, "|cffffffffAll Drops|r", 70);
    allDropsBtn:SetPoint("LEFT", personalBtn, "RIGHT", 4, 0);
    frame.allDropsBtn = allDropsBtn;

    local function setFilter(filter)
        frame.lootFilter = filter;
        if filter == "personal" then
            personalBtn:SetBackdropColor(self.constants.SUB_ACTIVE_COLOR.r, self.constants.SUB_ACTIVE_COLOR.g, self.constants.SUB_ACTIVE_COLOR.b, self.constants.SUB_ACTIVE_COLOR.a);
            personalBtn:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
            allDropsBtn:SetBackdropColor(self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a);
            allDropsBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);
        else
            allDropsBtn:SetBackdropColor(self.constants.SUB_ACTIVE_COLOR.r, self.constants.SUB_ACTIVE_COLOR.g, self.constants.SUB_ACTIVE_COLOR.b, self.constants.SUB_ACTIVE_COLOR.a);
            allDropsBtn:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
            personalBtn:SetBackdropColor(self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a);
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

function GoWWishlists:SaveFramePosition(frame, profileKey)
    if not GOW.DB or not GOW.DB.profile then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    GOW.DB.profile[profileKey] = { point = point, relativePoint = relativePoint, x = x, y = y }
end

function GoWWishlists:RestoreFramePosition(frame, profileKey, defaultPoint, defaultRelPoint, defaultX, defaultY)
    if GOW.DB and GOW.DB.profile and GOW.DB.profile[profileKey] then
        local pos = GOW.DB.profile[profileKey]
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        frame:SetPoint(defaultPoint, UIParent, defaultRelPoint, defaultX, defaultY)
    end
end

function GoWWishlists:CreateAlertItemRow(parent, match, itemLink)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(self.constants.ALERT_ITEM_ROW_HEIGHT);

    local sideBar = row:CreateTexture(nil, "ARTWORK", nil, 2);
    sideBar:SetTexture("Interface\\Buttons\\WHITE8x8");
    sideBar:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.8);
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
        self:RegisterPendingItem(match.itemId, function()
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
        table.insert(tags, self:FormatDifficultyTag(match.difficulty));
    end
    local tagLabel = self:FormatTag(match.tag);
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

function GoWWishlists:CreateWishlistAlertContainer()
    if self.frames.alertContainer then return self.frames.alertContainer end

    local frame = CreateFrame("Frame", "GoWWishlistAlertContainer", UIParent, "BackdropTemplate");
    frame:SetSize(360, 60);
    self:RestoreFramePosition(frame, "wishlistInfoFramePos", "TOP", "TOP", 0, -120);
    frame:SetFrameStrata("DIALOG");
    frame:SetFrameLevel(200);
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", frame.StartMoving);
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing();
        GoWWishlists:SaveFramePosition(self, "wishlistInfoFramePos");
    end);
    frame:SetClampedToScreen(true);

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    });
    frame:SetBackdropColor(self.constants.GOW_BG_COLOR.r, self.constants.GOW_BG_COLOR.g, self.constants.GOW_BG_COLOR.b, 0.92);
    frame:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.7);

    local topStripe = frame:CreateTexture(nil, "ARTWORK");
    topStripe:SetTexture("Interface\\Buttons\\WHITE8x8");
    topStripe:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.9);
    topStripe:SetHeight(2);
    topStripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1);
    topStripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1);

    local glow = frame:CreateTexture(nil, "ARTWORK", nil, 1);
    glow:SetTexture("Interface\\Buttons\\WHITE8x8");
    glow:SetGradient("VERTICAL", CreateColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0), CreateColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.08));
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
    fadeAnim:SetDuration(self.constants.ALERT_FADE_TIME);
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
    self.frames.alertContainer = frame;
    return frame;
end

function GoWWishlists:RelayoutAlertContainer(frame)
    local HEADER_HEIGHT = 22;
    local FOOTER_HEIGHT = 18;
    local yOffset = HEADER_HEIGHT;

    for _, row in ipairs(frame.itemRows) do
        row:ClearAllPoints();
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -yOffset);
        row:SetPoint("RIGHT", frame, "RIGHT", -4, 0);
        row:Show();
        yOffset = yOffset + self.constants.ALERT_ITEM_ROW_HEIGHT;
    end

    frame:SetHeight(yOffset + FOOTER_HEIGHT);
end

function GoWWishlists:ShowWishlistInfoFrame(match, itemLink)
    local frame = self:CreateWishlistAlertContainer();

    if frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end
    if frame.dismissTimer then frame.dismissTimer:Cancel(); frame.dismissTimer = nil end
    frame:SetAlpha(1);

    local row = self:CreateAlertItemRow(frame, match, itemLink);
    table.insert(frame.itemRows, row);

    if #frame.itemRows == 1 then
        frame.headerText:SetText("|cff00ff00WISHLIST MATCH|r");
    else
        frame.headerText:SetText("|cff00ff00WISHLIST MATCHES|r  |cffaaaaaa(" .. #frame.itemRows .. ")|r");
    end

    self:RelayoutAlertContainer(frame);

    if not frame:IsShown() then
        frame:SetAlpha(0);
        frame:Show();
        frame.fadeIn:Play();
    end

    frame.dismissTimer = C_Timer.NewTimer(self.constants.ALERT_DISPLAY_TIME, function()
        if frame:IsShown() then
            frame.fadeOut:Play();
        end
    end);
end

function GoWWishlists:OnStartLootRoll(rollID)
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
                self:ShowWishlistInfoFrame(match, itemLink);
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
            self:OnItemInfoReceived(itemId);
        end
    end);
end

function GoWWishlists:HandleLootDropEvents()
    local lootFrame = CreateFrame("Frame");
    lootFrame:RegisterEvent("START_LOOT_ROLL");

    lootFrame:SetScript("OnEvent", function(self, event, rollID)
        if event == "START_LOOT_ROLL" then
            GoWWishlists:OnStartLootRoll(rollID);
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

function GoWWishlists:RecordLootHistory(itemId, itemLink, encounterName, difficulty, timestamp)
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

function GoWWishlists:RecordAllLootDrop(itemId, itemLink, encounterName, difficulty, winnerName, timestamp)
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

function GoWWishlists:IsLootRecorded(history, itemId, encounterName, matchKey, matchValue)
    for _, record in ipairs(history) do
        if record.itemId == itemId and record.encounterName == encounterName
            and (not matchKey or record[matchKey] == matchValue)
            and record.timestamp and (GetServerTime() - record.timestamp) < 300 then
            return true;
        end
    end
    return false;
end

function GoWWishlists:IsAllLootAlreadyRecorded(itemId, encounterName, winnerName)
    local allHistory = GOW.DB and GOW.DB.profile and GOW.DB.profile.allLootHistory or {};
    return self:IsLootRecorded(allHistory, itemId, encounterName, "winner", winnerName);
end

function GoWWishlists:MarkWishlistObtained(itemId, difficulty)
    for _, entry in ipairs(self.state.allItems) do
        if entry.itemId == itemId
            and (not difficulty or entry.difficulty == difficulty)
            and not entry.isObtained then
            entry.isObtained = true;
            GOW.Logger:Debug("Wishlist item marked obtained: " .. tostring(itemId) .. " (" .. tostring(entry.difficulty) .. ")");

            local indexed = self.state.wishlistIndex[itemId];
            if indexed then
                for i = #indexed, 1, -1 do
                    if indexed[i] == entry then
                        table.remove(indexed, i);
                        break;
                    end
                end
                if #indexed == 0 then
                    self.state.wishlistIndex[itemId] = nil;
                end
            end

            return true;
        end
    end

    return false;
end

function GoWWishlists:ProcessDropInfo(dropInfo, encounterID, encounterName, difficulty)
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
        difficulty = self:GetCurrentDifficultyName();
    end

    local winner = dropInfo.winner;
    local winnerName = winner and (winner.name or winner.playerName) or nil;

    -- Record to all-loot history for any winner
    if winnerName and not self:IsAllLootAlreadyRecorded(itemId, encounterName, winnerName) then
        self:RecordAllLootDrop(itemId, itemLink, encounterName, difficulty, winnerName);
    end

    -- Personal loot history + wishlist tracking only for self
    if winner and winner.isSelf then
        GOW.Logger:Debug(string.format("Player won item %s (%d) from %s", itemLink, itemId, encounterName));

        local history = GOW.DB and GOW.DB.profile and GOW.DB.profile.lootHistory or {};
        local alreadyRecorded = self:IsLootRecorded(history, itemId, encounterName);

        if not alreadyRecorded then
            self:RecordLootHistory(itemId, itemLink, encounterName, difficulty);
            local wasOnWishlist = self:MarkWishlistObtained(itemId, difficulty);
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
    local resolved = self:ProcessDropInfo(dropInfo, encounterID);

    -- If winner isn't known yet (rolls in progress), retry after rolls end (~30s)
    if not resolved and dropInfo and dropInfo.itemHyperlink then
        C_Timer.After(32, function()
            local retryInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID);
            self:ProcessDropInfo(retryInfo, encounterID);
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
    local difficulty = self:GetCurrentDifficultyName();

    for _, dropEntry in ipairs(drops) do
        if dropEntry.lootListID and C_LootHistory.GetSortedInfoForDrop then
            local dropInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, dropEntry.lootListID);
            self:ProcessDropInfo(dropInfo, encounterID, encounterName, difficulty);
        end
    end
end

-- Wishlist Browser Frame
GoWWishlists.constants.BROWSER_ITEM_HEIGHT = 58;
GoWWishlists.constants.BROWSER_BOSS_HEADER_HEIGHT = 24;

function GoWWishlists:CollectWishlistForCharacter()
    local bossGroups = {};
    local bossOrder = {};
    local unknownItems = {};

    for _, entry in ipairs(self.state.allItems) do
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

function GoWWishlists:CreateItemRow(parent)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(self.constants.BROWSER_ITEM_HEIGHT);

    -- Inner anchor for vertical centering: icon + text block
    local inner = CreateFrame("Frame", nil, row);
    inner:SetPoint("LEFT", row, "LEFT", 0, 0);
    inner:SetPoint("RIGHT", row, "RIGHT", 0, 0);
    inner:SetHeight(46); -- ~3 lines of text height + spacing
    inner:SetPoint("TOP", row, "TOP", 0, -math.floor((self.constants.BROWSER_ITEM_HEIGHT - 46) / 2));

    local iconBorder = inner:CreateTexture(nil, "ARTWORK", nil, 0);
    iconBorder:SetTexture("Interface\\Buttons\\WHITE8x8");
    iconBorder:SetSize(24, 24);
    iconBorder:SetPoint("LEFT", inner, "LEFT", 8, 0);
    iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.6);
    row.iconBorder = iconBorder;

    local icon = inner:CreateTexture(nil, "ARTWORK", nil, 1);
    icon:SetSize(22, 22);
    icon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0);
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    row.icon = icon;

    -- Note icon: top-right
    local noteIcon = CreateFrame("Button", nil, row);
    noteIcon:SetSize(14, 14);
    noteIcon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6);
    local noteIconTex = noteIcon:CreateTexture(nil, "ARTWORK");
    noteIconTex:SetAllPoints();
    noteIconTex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up");
    noteIcon:Hide();
    row.noteIcon = noteIcon;

    -- Line 1: item name
    local nameText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 6, 2);
    nameText:SetPoint("RIGHT", row, "RIGHT", -26, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    row.nameText = nameText;

    -- Line 2: source + difficulty
    local infoText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3);
    infoText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    infoText:SetJustifyH("LEFT");
    infoText:SetWordWrap(false);
    row.infoText = infoText;

    -- Line 3: tag + gain + notes
    local detailText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    detailText:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -2);
    detailText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    detailText:SetJustifyH("LEFT");
    detailText:SetWordWrap(false);
    row.detailText = detailText;

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

    -- Bottom separator
    local sep = row:CreateTexture(nil, "ARTWORK");
    sep:SetTexture("Interface\\Buttons\\WHITE8x8");
    sep:SetVertexColor(0.25, 0.25, 0.3, 0.15);
    sep:SetHeight(1);
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0);
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0);

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

function GoWWishlists:PopulateItemRow(row, entry)
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
        self:RegisterPendingItem(entry.itemId, function()
            if row:GetParent() then
                self:PopulateItemRow(row, entry);
            end
        end);
    end

    -- Line 2: source + difficulty
    local infoParts = {};
    if row.showSource and entry.sourceBossName then
        table.insert(infoParts, "|cff888888" .. entry.sourceBossName .. "|r");
    end
    if entry.difficulty then
        table.insert(infoParts, self:FormatDifficultyTag(entry.difficulty));
    end
    row.infoText:SetText(table.concat(infoParts, "  "));

    -- Line 3: tag + gain + notes
    local detailParts = {};
    local tagLabel = self:FormatTag(entry.tag);
    if tagLabel then table.insert(detailParts, tagLabel) end

    local gain = entry.gain;
    if gain and gain.percent and gain.percent > 0 then
        local metric = (gain.metric and gain.metric ~= "") and gain.metric or "DPS";
        table.insert(detailParts, "|cff00ff00+" .. string.format("%.1f", gain.percent) .. "% " .. metric .. "|r");
    elseif gain and gain.stat and gain.stat > 0 then
        table.insert(detailParts, "|cff00ff00+" .. gain.stat .. "|r");
    end
    if entry.notes and entry.notes ~= "" then
        table.insert(detailParts, "|cffaaaaaa\"" .. entry.notes .. "\"|r");
    end
    row.detailText:SetText(table.concat(detailParts, "  |cff555555·|r  "));

    -- Notes icon with tooltip
    if entry.notes and entry.notes ~= "" then
        row.noteIcon.noteText = entry.notes;
        row.noteIcon:Show();
    else
        row.noteIcon.noteText = nil;
        row.noteIcon:Hide();
    end
end

function GoWWishlists:CreateBossHeader(parent, bossName, itemCount)
    local header = CreateFrame("Button", nil, parent);
    header:SetHeight(self.constants.BROWSER_BOSS_HEADER_HEIGHT);
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
    bar:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.6);
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

function GoWWishlists:UpdateBossHeaderArrow(header)
    if header.isCollapsed then
        header.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-UP");
    else
        header.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-UP");
    end
end

-- ===== 3-PANEL LAYOUT SYSTEM =====
GoWWishlists.constants.SOURCE_PANEL_WIDTH = 200;
GoWWishlists.constants.DETAIL_PANEL_WIDTH = 280;
GoWWishlists.constants.PANEL_HEADER_HEIGHT = 28;
GoWWishlists.constants.BOSS_ROW_HEIGHT = 24;
GoWWishlists.constants.SOURCE_FILTER_HEIGHT = 26;

function GoWWishlists:StyleScrollBar(scrollFrame)
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"];
    if not scrollBar then return end

    -- Hide default up/down buttons
    local upBtn = scrollBar.ScrollUpButton or _G[scrollBar:GetName() .. "ScrollUpButton"];
    local downBtn = scrollBar.ScrollDownButton or _G[scrollBar:GetName() .. "ScrollDownButton"];
    if upBtn then upBtn:SetAlpha(0); upBtn:SetSize(1, 1) end
    if downBtn then downBtn:SetAlpha(0); downBtn:SetSize(1, 1) end

    -- Narrow the scrollbar track
    scrollBar:SetWidth(6);

    -- Style the thumb (draggable part)
    local thumb = scrollBar.ThumbTexture or scrollBar:GetThumbTexture();
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8x8");
        thumb:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
        thumb:SetSize(6, 40);
    end

    -- Add a dark track background
    local track = scrollBar:CreateTexture(nil, "BACKGROUND");
    track:SetTexture("Interface\\Buttons\\WHITE8x8");
    track:SetVertexColor(0.05, 0.05, 0.08, 0.6);
    track:SetAllPoints(scrollBar);

    -- Auto-hide scrollbar when content fits
    local function updateScrollBarVisibility()
        local child = scrollFrame:GetScrollChild();
        if not child then return end
        local contentH = child:GetHeight();
        local frameH = scrollFrame:GetHeight();
        if contentH > frameH + 1 then
            scrollBar:Show();
        else
            scrollBar:Hide();
        end
    end
    scrollFrame:HookScript("OnScrollRangeChanged", updateScrollBarVisibility);
    scrollFrame:HookScript("OnShow", updateScrollBarVisibility);
end

function GoWWishlists:CreatePanelFrame(parent, name)
    local panel = CreateFrame("Frame", name, parent, "BackdropTemplate");
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    });
    panel:SetBackdropColor(0.06, 0.06, 0.08, 0.95);
    panel:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6);

    -- Panel header bar
    local headerBar = CreateFrame("Frame", nil, panel);
    headerBar:SetHeight(self.constants.PANEL_HEADER_HEIGHT);
    headerBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1);
    headerBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1);

    local headerBg = headerBar:CreateTexture(nil, "BACKGROUND");
    headerBg:SetTexture("Interface\\Buttons\\WHITE8x8");
    headerBg:SetAllPoints();
    headerBg:SetVertexColor(0.1, 0.1, 0.13, 0.9);

    local headerText = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    headerText:SetPoint("LEFT", headerBar, "LEFT", 10, 0);
    headerText:SetTextColor(0.7, 0.7, 0.7, 1);
    panel.headerText = headerText;
    panel.headerBar = headerBar;

    -- Scroll frame for panel content
    local sf = CreateFrame("ScrollFrame", name and (name .. "Scroll") or nil, panel, "UIPanelScrollFrameTemplate");
    sf:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -2);
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 2);

    local child = CreateFrame("Frame", nil, sf);
    child:SetHeight(1);
    sf:SetScrollChild(child);
    panel.scrollFrame = sf;
    panel.scrollChild = child;

    -- Style scrollbar to match theme
    self:StyleScrollBar(sf);

    -- Set scroll child width once layout completes (GetWidth() is 0 at creation time)
    sf:HookScript("OnShow", function(self)
        local w = self:GetWidth();
        if w > 0 then child:SetWidth(w) end
    end);

    return panel;
end

function GoWWishlists:Create3PanelLayout(parent)
    local container = CreateFrame("Frame", nil, parent);
    container:SetAllPoints(parent);

    local SOURCE_W = self.constants.SOURCE_PANEL_WIDTH;
    local DETAIL_W = self.constants.DETAIL_PANEL_WIDTH;

    -- Left panel: Source/boss selection
    local sourcePanel = self:CreatePanelFrame(container, "GoWSourcePanel");
    sourcePanel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0);
    sourcePanel:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0);
    sourcePanel:SetWidth(SOURCE_W);
    sourcePanel.headerText:SetText("SOURCE");
    container.sourcePanel = sourcePanel;

    -- Right panel: Wishlist / Player detail
    local detailPanel = self:CreatePanelFrame(container, "GoWDetailPanel");
    detailPanel:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0);
    detailPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0);
    detailPanel:SetWidth(DETAIL_W);
    detailPanel.headerText:SetText("WISHLIST");
    container.detailPanel = detailPanel;

    -- Center panel: Loot drops / items
    local lootPanel = self:CreatePanelFrame(container, "GoWLootPanel");
    lootPanel:SetPoint("TOPLEFT", sourcePanel, "TOPRIGHT", 2, 0);
    lootPanel:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMLEFT", -2, 0);
    lootPanel.headerText:SetText("LOOT DROPS");
    container.lootPanel = lootPanel;

    container.panels = { sourcePanel, lootPanel, detailPanel };

    return container;
end

-- ===== SOURCE PANEL CONTENT =====
function GoWWishlists:CreateBossRow(parent, bossName, itemCount, isAllBosses)
    local row = CreateFrame("Button", nil, parent);
    row:SetHeight(self.constants.BOSS_ROW_HEIGHT);

    local highlight = row:CreateTexture(nil, "BACKGROUND");
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8");
    highlight:SetAllPoints();
    highlight:SetVertexColor(1, 1, 1, 0.04);
    highlight:Hide();
    row.highlight = highlight;

    local activeBar = row:CreateTexture(nil, "ARTWORK", nil, 2);
    activeBar:SetTexture("Interface\\Buttons\\WHITE8x8");
    activeBar:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.8);
    activeBar:SetWidth(3);
    activeBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0);
    activeBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0);
    activeBar:Hide();
    row.activeBar = activeBar;

    local activeBg = row:CreateTexture(nil, "BACKGROUND", nil, 1);
    activeBg:SetTexture("Interface\\Buttons\\WHITE8x8");
    activeBg:SetAllPoints();
    activeBg:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.08);
    activeBg:Hide();
    row.activeBg = activeBg;

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    nameText:SetPoint("LEFT", row, "LEFT", 10, 0);
    nameText:SetPoint("RIGHT", row, "RIGHT", -36, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    if isAllBosses then
        nameText:SetText("|cffffffff" .. bossName .. "|r");
    else
        nameText:SetText("|cffcc99ff" .. bossName .. "|r");
    end
    row.nameText = nameText;

    local countBadge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    countBadge:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    countBadge:SetJustifyH("RIGHT");
    countBadge:SetText("|cff888888" .. itemCount .. "|r");
    row.countBadge = countBadge;

    row:SetScript("OnEnter", function(self)
        if not self.isActive then self.highlight:Show() end
    end);
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide();
    end);

    row.isActive = false;
    return row;
end

function GoWWishlists:SetBossRowActive(row, active)
    row.isActive = active;
    if active then
        row.activeBar:Show();
        row.activeBg:Show();
    else
        row.activeBar:Hide();
        row.activeBg:Hide();
    end
end

function GoWWishlists:PopulateSourcePanel(panel, bossOrder, bossCounts, onBossSelected)
    local scrollChild = panel.scrollChild;
    self:ClearChildren(scrollChild);
    scrollChild:SetWidth(panel.scrollFrame:GetWidth());

    local totalCount = 0;
    for _, name in ipairs(bossOrder) do
        totalCount = totalCount + (bossCounts[name] or 0);
    end

    local yOffset = 0;
    local bossRows = {};

    -- "All Bosses" row
    local allRow = self:CreateBossRow(scrollChild, "All Bosses", totalCount, true);
    allRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
    allRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
    allRow:Show();
    self:SetBossRowActive(allRow, true);
    table.insert(bossRows, { row = allRow, bossName = nil });
    yOffset = yOffset + self.constants.BOSS_ROW_HEIGHT;

    -- Separator after All Bosses
    local sep = scrollChild:CreateTexture(nil, "ARTWORK");
    sep:SetTexture("Interface\\Buttons\\WHITE8x8");
    sep:SetVertexColor(0.25, 0.25, 0.3, 0.4);
    sep:SetHeight(1);
    sep:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, -yOffset);
    sep:SetPoint("RIGHT", scrollChild, "RIGHT", -6, 0);
    yOffset = yOffset + 4;

    -- Individual boss rows
    for _, bossName in ipairs(bossOrder) do
        local count = bossCounts[bossName] or 0;
        local bossRow = self:CreateBossRow(scrollChild, bossName, count, false);
        bossRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        bossRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        bossRow:Show();
        table.insert(bossRows, { row = bossRow, bossName = bossName });
        yOffset = yOffset + self.constants.BOSS_ROW_HEIGHT;
    end

    scrollChild:SetHeight(yOffset + 4);

    -- Click handling
    local function selectBoss(selectedIdx)
        for i, entry in ipairs(bossRows) do
            GoWWishlists:SetBossRowActive(entry.row, i == selectedIdx);
        end
        local selectedBoss = bossRows[selectedIdx] and bossRows[selectedIdx].bossName or nil;
        onBossSelected(selectedBoss);
    end

    for i, entry in ipairs(bossRows) do
        entry.row:SetScript("OnClick", function() selectBoss(i) end);
    end

    panel.bossRows = bossRows;
    panel.selectBoss = selectBoss;
end

function GoWWishlists:CreateSearchBox(parent)
    local search = CreateFrame("EditBox", nil, parent, "BackdropTemplate");
    search:SetHeight(20);
    search:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    });
    search:SetBackdropColor(0.05, 0.05, 0.07, 0.9);
    search:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.5);
    search:SetFontObject("GameFontNormalSmall");
    search:SetTextInsets(20, 6, 0, 0);
    search:SetAutoFocus(false);
    search:SetMaxLetters(30);

    local searchIcon = search:CreateTexture(nil, "OVERLAY");
    searchIcon:SetSize(12, 12);
    searchIcon:SetPoint("LEFT", search, "LEFT", 5, 0);
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon");
    searchIcon:SetVertexColor(0.5, 0.5, 0.5, 0.7);

    -- Placeholder text
    local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    placeholder:SetPoint("LEFT", search, "LEFT", 20, 0);
    placeholder:SetText("|cff555555Search items...|r");
    search.placeholder = placeholder;

    search:SetScript("OnEditFocusGained", function(self)
        self.placeholder:Hide();
    end);
    search:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self.placeholder:Show() end
    end);
    search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus();
    end);

    return search;
end

function GoWWishlists:CreateWishlistBrowserFrame()
    if self.frames.browserFrame then return self.frames.browserFrame end

    local frame = CreateFrame("Frame", "GoWWishlistBrowserFrame", UIParent, "BackdropTemplate");
    frame:SetSize(900, 540);
    self:RestoreFramePosition(frame, "wishlistBrowserFramePos", "CENTER", "CENTER", 0, 0);
    frame:SetFrameStrata("HIGH");
    frame:SetFrameLevel(100);
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", frame.StartMoving);
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing();
        GoWWishlists:SaveFramePosition(self, "wishlistBrowserFramePos");
    end);
    frame:SetClampedToScreen(true);

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    });
    frame:SetBackdropColor(self.constants.GOW_BG_COLOR.r, self.constants.GOW_BG_COLOR.g, self.constants.GOW_BG_COLOR.b, 0.95);
    frame:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.7);

    local topStripe = frame:CreateTexture(nil, "ARTWORK");
    topStripe:SetTexture("Interface\\Buttons\\WHITE8x8");
    topStripe:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.9);
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
    local TAB_ACTIVE_COLOR = { r = self.constants.GOW_ACCENT_COLOR.r, g = self.constants.GOW_ACCENT_COLOR.g, b = self.constants.GOW_ACCENT_COLOR.b, a = 0.25 };
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
    tabIndicator:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.9);
    tabIndicator:SetHeight(2);
    frame.tabIndicator = tabIndicator;

    -- Content area starts below tabs
    local contentTop = wishlistTab; -- tabs are the top anchor

    -- ===== PERSONAL WISHLIST: 3-PANEL CONTAINER =====
    local wishlistContainer = CreateFrame("Frame", "GoWWishlistContainer", frame);
    wishlistContainer:SetPoint("TOPLEFT", contentTop, "BOTTOMLEFT", -4, -8);
    wishlistContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 20);
    frame.wishlistContainer = wishlistContainer;

    local wishlist3Panel = self:Create3PanelLayout(wishlistContainer);
    frame.wishlist3Panel = wishlist3Panel;
    -- Alias for backward compat with relayout methods
    frame.scrollChild = wishlist3Panel.lootPanel.scrollChild;
    frame.scrollFrame = wishlist3Panel.lootPanel.scrollFrame;

    -- ===== LOOT HISTORY: single-column scroll (unchanged) =====
    local lootScrollFrame = CreateFrame("ScrollFrame", "GoWLootHistoryScrollFrame", frame, "UIPanelScrollFrameTemplate");
    lootScrollFrame:SetPoint("TOPLEFT", contentTop, "BOTTOMLEFT", -4, -8);
    lootScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 20);

    local lootScrollChild = CreateFrame("Frame", nil, lootScrollFrame);
    lootScrollChild:SetWidth(lootScrollFrame:GetWidth());
    lootScrollChild:SetHeight(1);
    lootScrollFrame:SetScrollChild(lootScrollChild);
    frame.lootScrollChild = lootScrollChild;
    frame.lootScrollFrame = lootScrollFrame;

    -- Style loot history scrollbar
    self:StyleScrollBar(lootScrollFrame);

    -- Loot history sub-filter: Personal / All Drops
    frame.lootFilter = "personal"; -- "personal" or "all"
    self:SetupLootFilterButtons(lootScrollChild, frame);

    -- ===== GUILD WISHLISTS: 3-PANEL CONTAINER =====
    local guildContainer = CreateFrame("Frame", "GoWGuildContainer", frame);
    guildContainer:SetPoint("TOPLEFT", contentTop, "BOTTOMLEFT", -4, -8);
    guildContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 20);
    frame.guildContainer = guildContainer;

    local guild3Panel = self:Create3PanelLayout(guildContainer);
    frame.guild3Panel = guild3Panel;
    -- Aliases for backward compat
    frame.guildScrollChild = guild3Panel.lootPanel.scrollChild;
    frame.guildScrollFrame = guild3Panel.lootPanel.scrollFrame;
    frame.guildDifficultyFilter = "All";

    -- ===== TAB SWITCHING =====
    frame.activeTab = 1;

    local allTabs = { wishlistTab, lootHistoryTab, guildWishlistTab };
    local allContentFrames = { wishlistContainer, lootScrollFrame, guildContainer };

    local function SetActiveTab(tabIndex)
        frame.activeTab = tabIndex;

        -- Hide all content frames, deactivate all tabs
        for _, cf in ipairs(allContentFrames) do cf:Hide() end
        for _, tab in ipairs(allTabs) do
            if tab:IsShown() then
                tab:SetBackdropColor(TAB_INACTIVE_COLOR.r, TAB_INACTIVE_COLOR.g, TAB_INACTIVE_COLOR.b, TAB_INACTIVE_COLOR.a);
                tab:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5);
            end
        end

        -- Activate selected tab
        local activeTab = allTabs[tabIndex];
        local activeContent = allContentFrames[tabIndex];
        activeContent:Show();
        activeTab:SetBackdropColor(TAB_ACTIVE_COLOR.r, TAB_ACTIVE_COLOR.g, TAB_ACTIVE_COLOR.b, TAB_ACTIVE_COLOR.a);
        activeTab:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
        tabIndicator:ClearAllPoints();
        tabIndicator:SetPoint("BOTTOMLEFT", activeTab, "BOTTOMLEFT", 1, 0);
        tabIndicator:SetPoint("BOTTOMRIGHT", activeTab, "BOTTOMRIGHT", -1, 0);

        if tabIndex == 1 then
            frame.titleText:SetText("|cff00ff00Wishlist|r");
            if frame.wishlistSubtitle then
                frame.subtitleText:SetText(frame.wishlistSubtitle);
            end
            GoWWishlists:PopulatePersonalWishlistView(frame);
        elseif tabIndex == 2 then
            frame.titleText:SetText("|cff00ff00Loot History|r");
            frame.SetLootFilter(frame.lootFilter or "personal");
        elseif tabIndex == 3 then
            frame.titleText:SetText("|cff00ff00Guild Loot|r");
            GoWWishlists:PopulateGuildWishlistView(frame);
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
    self.frames.browserFrame = frame;
    return frame;
end

-- ===== LOOT HISTORY TAB =====
GoWWishlists.constants.LOOT_ROW_HEIGHT = 28;

function GoWWishlists:CreateLootHistoryRow(parent, showWinner)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(self.constants.LOOT_ROW_HEIGHT);

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

function GoWWishlists:PopulateLootHistoryRow(row, record)
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
        self:RegisterPendingItem(record.itemId, function()
            if row:GetParent() then
                self:PopulateLootHistoryRow(row, record);
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
        local tag = self:FormatDifficultyTag(record.difficulty);
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

    self:ClearChildren(lootScrollChild, frame.personalBtn, frame.allDropsBtn);

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
        local row = self:CreateLootHistoryRow(lootScrollChild, showWinner);
        self:PopulateLootHistoryRow(row, record);
        row:SetPoint("TOPLEFT", lootScrollChild, "TOPLEFT", 0, -yOffset);
        row:SetPoint("RIGHT", lootScrollChild, "RIGHT", 0, 0);
        row:Show();
        yOffset = yOffset + self.constants.LOOT_ROW_HEIGHT;
    end

    lootScrollChild:SetHeight(yOffset + 8);
end

function GoWWishlists:RelayoutBrowserContent(frame)
    local scrollChild = frame.scrollChild;
    local yOffset = 0;

    for _, section in ipairs(frame.sections) do
        local header = section.header;
        header:ClearAllPoints();
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        header:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        header:Show();
        yOffset = yOffset + self.constants.BROWSER_BOSS_HEADER_HEIGHT;

        if not header.isCollapsed then
            for _, row in ipairs(header.itemRows) do
                row:ClearAllPoints();
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                row:Show();
                yOffset = yOffset + self.constants.BROWSER_ITEM_HEIGHT;
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

function GoWWishlists:BuildSections(container, scrollChild, bossGroups, bossOrder, unknownItems)
    container.sections = {};

    local function addSection(bossName, items)
        local header = self:CreateBossHeader(scrollChild, bossName, #items);
        header.isCollapsed = true;
        self:UpdateBossHeaderArrow(header);

        header.itemRows = {};
        for _, entry in ipairs(items) do
            local row = self:CreateItemRow(scrollChild);
            self:PopulateItemRow(row, entry);
            table.insert(header.itemRows, row);
        end

        header:SetScript("OnClick", function(self)
            self.isCollapsed = not self.isCollapsed;
            GoWWishlists:UpdateBossHeaderArrow(self);
            GoWWishlists:RelayoutBrowserContent(container);
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

    -- Show guild tab if guild data exists
    if self.state.guildWishlistData and self.state.guildWishlistData.wishlists and #self.state.guildWishlistData.wishlists > 0 then
        frame.guildWishlistTab:Show();
    else
        frame.guildWishlistTab:Hide();
    end

    -- Always open on wishlist tab
    frame.SetActiveTab(1);
    frame:Show();
end

-- ===== PERSONAL WISHLIST: 3-PANEL VIEW =====
function GoWWishlists:PopulatePersonalWishlistView(frame)
    local panel3 = frame.wishlist3Panel;
    if not panel3 then return end

    local sourcePanel = panel3.sourcePanel;
    local lootPanel = panel3.lootPanel;
    local detailPanel = panel3.detailPanel;

    local charName = self.state.currentCharInfo and self.state.currentCharInfo.name or UnitName("player");
    local charRealm = self.state.currentCharInfo and self.state.currentCharInfo.realmNormalized or GetNormalizedRealmName();

    local bossGroups, bossOrder, unknownItems = self:CollectWishlistForCharacter();

    local totalCount = 0;
    local bossCounts = {};
    for _, bossName in ipairs(bossOrder) do
        local count = #bossGroups[bossName];
        bossCounts[bossName] = count;
        totalCount = totalCount + count;
    end
    if #unknownItems > 0 then
        table.insert(bossOrder, "Unknown Boss");
        bossGroups["Unknown Boss"] = unknownItems;
        bossCounts["Unknown Boss"] = #unknownItems;
        totalCount = totalCount + #unknownItems;
    end

    local subtitleStr = charName .. "-" .. charRealm .. "  |  " .. totalCount .. " items remaining";
    frame.subtitleText:SetText(subtitleStr);
    frame.wishlistSubtitle = subtitleStr;

    -- Source panel header
    sourcePanel.headerText:SetText("SOURCE");

    -- Loot panel header
    lootPanel.headerText:SetText("LOOT DROPS");

    -- Detail panel header
    detailPanel.headerText:SetText("WISHLIST");

    -- Current filter state
    local currentBoss = nil; -- nil = All Bosses

    -- Populate loot (center) panel for selected boss
    local function populateLootPanel(selectedBoss)
        local scrollChild = lootPanel.scrollChild;
        self:ClearChildren(scrollChild);
        scrollChild:SetWidth(lootPanel.scrollFrame:GetWidth());

        local container = { sections = {}, scrollChild = scrollChild };

        if selectedBoss then
            -- Show only the selected boss's items (expanded)
            local items = bossGroups[selectedBoss];
            if items and #items > 0 then
                local header = self:CreateBossHeader(scrollChild, selectedBoss, #items);
                header.isCollapsed = false;
                self:UpdateBossHeaderArrow(header);

                header.itemRows = {};
                for _, entry in ipairs(items) do
                    local row = self:CreateItemRow(scrollChild);
                    self:PopulateItemRow(row, entry);
                    table.insert(header.itemRows, row);
                end

                header:SetScript("OnClick", function(h)
                    h.isCollapsed = not h.isCollapsed;
                    GoWWishlists:UpdateBossHeaderArrow(h);
                    GoWWishlists:RelayoutBrowserContent(container);
                end);

                table.insert(container.sections, { header = header });
            end
        else
            -- Show all bosses (collapsed by default)
            self:BuildSections(container, scrollChild, bossGroups, bossOrder, unknownItems);
        end

        self:RelayoutBrowserContent(container);
    end

    -- Populate detail (right) panel — personal wishlist sorted by gain desc
    local function populateDetailPanel()
        local scrollChild = detailPanel.scrollChild;
        self:ClearChildren(scrollChild);
        scrollChild:SetWidth(detailPanel.scrollFrame:GetWidth());

        -- Collect all non-obtained items and sort by gain% descending
        local sortedItems = {};
        for _, entry in ipairs(self.state.allItems) do
            if not entry.isObtained then
                table.insert(sortedItems, entry);
            end
        end
        table.sort(sortedItems, function(a, b)
            local aGain = (a.gain and a.gain.percent) or 0;
            local bGain = (b.gain and b.gain.percent) or 0;
            return aGain > bGain;
        end);

        local yOffset = 0;

        -- Item count header
        local countText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        countText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -yOffset);
        countText:SetText("|cff888888" .. #sortedItems .. " items|r");
        yOffset = yOffset + 16;

        for _, entry in ipairs(sortedItems) do
            local row = self:CreateItemRow(scrollChild);
            row.showSource = true;
            self:PopulateItemRow(row, entry);

            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
            row:Show();
            yOffset = yOffset + self.constants.BROWSER_ITEM_HEIGHT;
        end

        if #sortedItems == 0 then
            local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -30);
            emptyText:SetText("|cff888888No items remaining.|r");
            yOffset = 80;
        end

        scrollChild:SetHeight(yOffset + 8);
    end

    -- Populate source panel
    self:PopulateSourcePanel(sourcePanel, bossOrder, bossCounts, function(selectedBoss)
        currentBoss = selectedBoss;
        populateLootPanel(currentBoss);
    end);

    -- Initial populate
    populateLootPanel(nil); -- All Bosses
    populateDetailPanel();
end

-- ===== CORE UI TAB INTEGRATION =====

function GoWWishlists:CreateCoreWishlistFrame(parent)
    if self.frames.coreWishlistScroll then
        self.frames.coreWishlistScroll:SetParent(parent);
        self.frames.coreWishlistScroll:SetAllPoints(parent);
        return self.frames.coreWishlistScroll;
    end

    local container = CreateFrame("Frame", "GoWCoreWishlistContainer", parent);
    container:SetAllPoints(parent);

    local panel3 = self:Create3PanelLayout(container);
    container.wishlist3Panel = panel3;
    -- Aliases for populate methods
    container.scrollChild = panel3.lootPanel.scrollChild;
    container.scrollFrame = panel3.lootPanel.scrollFrame;

    container:Hide();
    self.frames.coreWishlistScroll = container;
    return container;
end

function GoWWishlists:ShowCoreWishlistTab(parent, setStatusFn)
    local container = self:CreateCoreWishlistFrame(parent);

    -- Build a frame-like object that PopulatePersonalWishlistView expects
    local frame = {
        wishlist3Panel = container.wishlist3Panel,
        subtitleText = { SetText = function(_, text) if setStatusFn then setStatusFn(text) end end },
        wishlistSubtitle = nil,
    };

    self:PopulatePersonalWishlistView(frame);
    container:Show();
end

function GoWWishlists:CreateCoreLootFrame(parent)
    if self.frames.coreLootScroll then
        self.frames.coreLootScroll:SetParent(parent);
        self.frames.coreLootScroll:SetAllPoints(parent);
        return self.frames.coreLootScroll;
    end

    local sf = CreateFrame("ScrollFrame", "GoWCoreLootScroll", parent, "UIPanelScrollFrameTemplate");
    sf:SetAllPoints(parent);
    self:StyleScrollBar(sf);

    local child = CreateFrame("Frame", nil, sf);
    child:SetWidth(sf:GetWidth());
    child:SetHeight(1);
    sf:SetScrollChild(child);
    sf.lootScrollChild = child;
    sf.lootFilter = "personal";

    self:SetupLootFilterButtons(child, sf);
    sf.subtitleText = { SetText = function() end };

    sf:Hide();
    self.frames.coreLootScroll = sf;
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
    if self.frames.coreWishlistScroll then self.frames.coreWishlistScroll:Hide() end
    if self.frames.coreLootScroll then self.frames.coreLootScroll:Hide() end
    if self.frames.coreGuildWishlistScroll then self.frames.coreGuildWishlistScroll:Hide() end
end

-- ===== CORE UI: GUILD WISHLISTS TAB =====

function GoWWishlists:CreateCoreGuildWishlistFrame(parent)
    if self.frames.coreGuildWishlistScroll then
        self.frames.coreGuildWishlistScroll:SetParent(parent);
        self.frames.coreGuildWishlistScroll:SetAllPoints(parent);
        return self.frames.coreGuildWishlistScroll;
    end

    local container = CreateFrame("Frame", "GoWCoreGuildWishlistContainer", parent);
    container:SetAllPoints(parent);

    local panel3 = self:Create3PanelLayout(container);
    container.guild3Panel = panel3;
    container.guildScrollChild = panel3.lootPanel.scrollChild;
    container.guildScrollFrame = panel3.lootPanel.scrollFrame;
    container.guildDifficultyFilter = "All";

    container:Hide();
    self.frames.coreGuildWishlistScroll = container;
    return container;
end

function GoWWishlists:ShowCoreGuildWishlistTab(parent, setStatusFn)
    local container = self:CreateCoreGuildWishlistFrame(parent);

    local frame = {
        guild3Panel = container.guild3Panel,
        guildDifficultyFilter = container.guildDifficultyFilter or "All",
        subtitleText = { SetText = function(_, text) if setStatusFn then setStatusFn(text) end end },
    };

    self:PopulateGuildWishlistView(frame);
    container:Show();
end

-- ===== GUILD WISHLISTS TAB =====
GoWWishlists.constants.GUILD_ITEM_ROW_HEIGHT = 28;
GoWWishlists.constants.GUILD_MEMBER_ROW_HEIGHT = 22;
GoWWishlists.constants.GUILD_FILTER_HEIGHT = 26;

-- Collects guild wishlist data grouped by boss, then by item, then by member.
-- Returns: bossGroups = { bossName = { items = {key = itemData}, itemOrder = {keys} } }, bossOrder = {bossNames}
function GoWWishlists:CollectGuildWishlistByBoss(difficultyFilter)
    if not self.state.guildWishlistData or not self.state.guildWishlistData.wishlists then return {}, {} end

    local bossGroups = {};
    local bossOrder = {};

    for _, charEntry in ipairs(self.state.guildWishlistData.wishlists) do
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
                        classId = charEntry.classId,
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
function GoWWishlists:CreateGuildItemRow(parent)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(self.constants.GUILD_ITEM_ROW_HEIGHT);

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

function GoWWishlists:PopulateGuildItemRow(row, itemData)
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
        table.insert(parts, self:FormatDifficultyTag(itemData.difficulty));
    end
    local memberCount = #itemData.members;
    table.insert(parts, "|cff888888" .. memberCount .. (memberCount == 1 and " wants" or " want") .. "|r");

    -- Avg gain badge
    local totalPercent, gainCount, avgMetric = 0, 0, nil;
    for _, m in ipairs(itemData.members) do
        if m.gain and m.gain.percent and m.gain.percent > 0 then
            totalPercent = totalPercent + m.gain.percent;
            gainCount = gainCount + 1;
            if not avgMetric and m.gain.metric and m.gain.metric ~= "" then
                avgMetric = m.gain.metric;
            end
        end
    end
    if gainCount > 0 then
        local avgPercent = totalPercent / gainCount;
        avgMetric = avgMetric or "DPS";
        table.insert(parts, "|cff00ff00avg +" .. string.format("%.1f", avgPercent) .. "% " .. avgMetric .. "|r");
    end

    row.infoText:SetText(table.concat(parts, "  "));

    if not itemName then
        self:RegisterPendingItem(itemData.itemId, function()
            if row:GetParent() then
                self:PopulateGuildItemRow(row, itemData);
            end
        end);
    end
end

-- ===== Guild Member Row (shows name + tag + gain + note icons) =====
function GoWWishlists:CreateGuildMemberRow(parent)
    local row = CreateFrame("Button", nil, parent);
    row:SetHeight(self.constants.GUILD_MEMBER_ROW_HEIGHT);

    -- Class color accent bar
    local classBar = row:CreateTexture(nil, "ARTWORK");
    classBar:SetTexture("Interface\\Buttons\\WHITE8x8");
    classBar:SetSize(2, 14);
    classBar:SetPoint("LEFT", row, "LEFT", 42, 0);
    classBar:SetVertexColor(0.5, 0.5, 0.5, 0.3);
    row.classBar = classBar;

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    nameText:SetPoint("LEFT", classBar, "RIGHT", 6, 0);
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

function GoWWishlists:PopulateGuildMemberRow(row, member, guildRealm)
    -- Class-colored name, with realm suffix if cross-realm
    local classColor = self:GetClassColor(member.classId);
    local colorHex = self:ClassColorToHex(classColor);
    local displayName = member.characterName;
    if guildRealm and member.realmName and member.realmName ~= guildRealm then
        displayName = displayName .. "-" .. member.realmName;
    end
    row.nameText:SetText("|cff" .. colorHex .. displayName .. "|r");

    -- Class color accent bar
    if classColor then
        row.classBar:SetVertexColor(classColor.r, classColor.g, classColor.b, 0.8);
    else
        row.classBar:SetVertexColor(0.5, 0.5, 0.5, 0.3);
    end

    local tagLabel = self:FormatTag(member.tag);
    row.tagText:SetText(tagLabel or "");

    -- Clean gain format: +X.X% DPS/HPS
    local gain = member.gain;
    if gain and gain.percent and gain.percent > 0 then
        local metric = (gain.metric and gain.metric ~= "") and gain.metric or "DPS";
        row.gainText:SetText("|cff00ff00+" .. string.format("%.1f", gain.percent) .. "% " .. metric .. "|r");
    elseif gain and gain.stat and gain.stat > 0 then
        row.gainText:SetText("|cff00ff00+" .. gain.stat .. "|r");
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
function GoWWishlists:RelayoutGuildContent(frame)
    local scrollChild = frame.guildScrollChild;
    local yOffset = self.constants.GUILD_FILTER_HEIGHT;

    for _, section in ipairs(frame.guildSections or {}) do
        local header = section.header;
        header:ClearAllPoints();
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        header:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        header:Show();
        yOffset = yOffset + self.constants.BROWSER_BOSS_HEADER_HEIGHT;

        if not header.isCollapsed then
            for _, itemGroup in ipairs(section.items or {}) do
                local itemRow = itemGroup.row;
                itemRow:ClearAllPoints();
                itemRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                itemRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                itemRow:Show();
                yOffset = yOffset + self.constants.GUILD_ITEM_ROW_HEIGHT;

                for _, memberRow in ipairs(itemGroup.memberRows or {}) do
                    memberRow:ClearAllPoints();
                    memberRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                    memberRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                    memberRow:Show();
                    yOffset = yOffset + self.constants.GUILD_MEMBER_ROW_HEIGHT;
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

-- ===== GUILD WISHLISTS: 3-PANEL VIEW =====
function GoWWishlists:PopulateGuildWishlistView(frame)
    local panel3 = frame.guild3Panel;
    if not panel3 then return end

    local sourcePanel = panel3.sourcePanel;
    local lootPanel = panel3.lootPanel;
    local detailPanel = panel3.detailPanel;

    if not self.state.guildWishlistData or not self.state.guildWishlistData.wishlists or #self.state.guildWishlistData.wishlists == 0 then
        local playerGuild = GetGuildInfo("player");
        local msg;
        if not playerGuild then
            msg = "You are not in a guild.";
        else
            msg = "No guild wishlist data found for " .. playerGuild .. ".";
        end
        -- Show empty in loot panel
        local sc = lootPanel.scrollChild;
        self:ClearChildren(sc);
        local emptyText = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        emptyText:SetPoint("TOP", sc, "TOP", 0, -30);
        emptyText:SetText("|cff888888" .. msg .. "|r");
        sc:SetHeight(80);
        frame.subtitleText:SetText(playerGuild or "No Guild");
        return;
    end

    local guildName = self.state.guildWishlistData.guild or "Guild";
    local guildRealm = self.state.guildWishlistData.guildRealm;
    local filter = frame.guildDifficultyFilter or "All";

    -- Source panel header
    sourcePanel.headerText:SetText("SOURCE");

    -- Loot panel header
    lootPanel.headerText:SetText("LOOT");

    -- Detail panel header
    detailPanel.headerText:SetText("WISHLIST");

    -- Setup difficulty filter in source panel (above boss list)
    local function rebuildGuildView()
        filter = frame.guildDifficultyFilter or "All";
        local bossGroups, bossOrder = self:CollectGuildWishlistByBoss(filter);

        -- Compute boss counts and totals
        local bossCounts = {};
        local totalItems = 0;
        local memberSet = {};
        for _, bossName in ipairs(bossOrder) do
            local boss = bossGroups[bossName];
            local count = #boss.itemOrder;
            bossCounts[bossName] = count;
            totalItems = totalItems + count;
            for _, itemKey in ipairs(boss.itemOrder) do
                for _, member in ipairs(boss.items[itemKey].members) do
                    memberSet[member.characterName] = true;
                end
            end
        end
        local memberCount = 0;
        for _ in pairs(memberSet) do memberCount = memberCount + 1 end
        frame.subtitleText:SetText(guildName .. "  |  " .. memberCount .. " members  |  " .. totalItems .. " items");

        -- Populate source panel boss list
        self:PopulateSourcePanel(sourcePanel, bossOrder, bossCounts, function(selectedBoss)
            self:PopulateGuildLootPanel(lootPanel, bossGroups, bossOrder, selectedBoss, guildRealm, detailPanel);
        end);

        -- Populate loot panel (all bosses)
        self:PopulateGuildLootPanel(lootPanel, bossGroups, bossOrder, nil, guildRealm, detailPanel);

        -- Reset detail panel
        self:PopulateGuildDetailDefault(detailPanel, guildName, memberCount, totalItems);
    end

    -- Setup difficulty filter buttons in the source panel header area
    if not sourcePanel.diffFilterBtns then
        local difficulties = { "All", "Normal", "Heroic", "Mythic", "LFR" };
        local btns = {};
        local headerBar = sourcePanel.headerBar;

        for i, diff in ipairs(difficulties) do
            local btn = self:CreateSubFilterBtn(sourcePanel, diff, 36);
            btn:SetHeight(14);
            if i == 1 then
                btn:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 4, -4);
            else
                btn:SetPoint("LEFT", btns[i - 1], "RIGHT", 2, 0);
            end
            btns[i] = btn;
        end

        local function setDiffFilter(diff)
            frame.guildDifficultyFilter = diff;
            for i, btn in ipairs(btns) do
                if difficulties[i] == diff then
                    btn:SetBackdropColor(self.constants.SUB_ACTIVE_COLOR.r, self.constants.SUB_ACTIVE_COLOR.g, self.constants.SUB_ACTIVE_COLOR.b, self.constants.SUB_ACTIVE_COLOR.a);
                    btn:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
                else
                    btn:SetBackdropColor(self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a);
                    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);
                end
            end
            rebuildGuildView();
        end

        for i, btn in ipairs(btns) do
            btn:SetScript("OnClick", function() setDiffFilter(difficulties[i]) end);
        end

        sourcePanel.diffFilterBtns = btns;
        sourcePanel.scrollFrame:SetPoint("TOPLEFT", btns[1], "BOTTOMLEFT", -4, -4);
    end

    -- Set initial difficulty active
    if sourcePanel.diffFilterBtns then
        local difficulties = { "All", "Normal", "Heroic", "Mythic", "LFR" };
        for i, btn in ipairs(sourcePanel.diffFilterBtns) do
            if difficulties[i] == filter then
                btn:SetBackdropColor(self.constants.SUB_ACTIVE_COLOR.r, self.constants.SUB_ACTIVE_COLOR.g, self.constants.SUB_ACTIVE_COLOR.b, self.constants.SUB_ACTIVE_COLOR.a);
                btn:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
            else
                btn:SetBackdropColor(self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a);
                btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);
            end
        end
    end

    rebuildGuildView();
end

function GoWWishlists:PopulateGuildLootPanel(lootPanel, bossGroups, bossOrder, selectedBoss, guildRealm, detailPanel)
    local scrollChild = lootPanel.scrollChild;
    self:ClearChildren(scrollChild);
    scrollChild:SetWidth(lootPanel.scrollFrame:GetWidth());

    local container = { guildSections = {}, guildScrollChild = scrollChild };

    local function buildBossSection(bossName)
        local boss = bossGroups[bossName];
        if not boss then return end

        local header = self:CreateBossHeader(scrollChild, bossName, #boss.itemOrder);
        header.isCollapsed = (selectedBoss == nil); -- expanded when specific boss, collapsed for all
        self:UpdateBossHeaderArrow(header);

        local items = {};
        for _, itemKey in ipairs(boss.itemOrder) do
            local itemData = boss.items[itemKey];

            -- Sort members by gain descending
            table.sort(itemData.members, function(a, b)
                local aGain = (a.gain and a.gain.percent) or 0;
                local bGain = (b.gain and b.gain.percent) or 0;
                return aGain > bGain;
            end);

            local itemRow = self:CreateGuildItemRow(scrollChild);
            self:PopulateGuildItemRow(itemRow, itemData);

            local memberRows = {};
            for _, member in ipairs(itemData.members) do
                local memberRow = self:CreateGuildMemberRow(scrollChild);
                self:PopulateGuildMemberRow(memberRow, member, guildRealm);

                -- Click member → show detail
                memberRow:SetScript("OnClick", function()
                    GoWWishlists:PopulateGuildPlayerDetail(detailPanel, member, guildRealm);
                end);
                memberRow:EnableMouse(true);

                table.insert(memberRows, memberRow);
            end

            table.insert(items, { row = itemRow, memberRows = memberRows });
        end

        header:SetScript("OnClick", function(h)
            h.isCollapsed = not h.isCollapsed;
            GoWWishlists:UpdateBossHeaderArrow(h);
            GoWWishlists:RelayoutGuildContent(container);
        end);

        table.insert(container.guildSections, { header = header, items = items });
    end

    if selectedBoss then
        buildBossSection(selectedBoss);
    else
        for _, bossName in ipairs(bossOrder) do
            buildBossSection(bossName);
        end
    end

    self:RelayoutGuildContent(container);
end

function GoWWishlists:CollectGuildObtainedItems()
    local results = {};
    local data = self.state.guildWishlistData;
    if not data or not data.wishlists then return results end

    for _, charEntry in ipairs(data.wishlists) do
        for _, item in ipairs(charEntry.wishlist) do
            if item.isObtained then
                table.insert(results, {
                    itemId = item.itemId,
                    difficulty = item.difficulty,
                    encounterName = item.sourceBossName or "Unknown",
                    winner = charEntry.name,
                    timestamp = item.obtainedOn and math.floor(item.obtainedOn / 1000) or nil,
                });
            end
        end
    end

    table.sort(results, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0);
    end);

    return results;
end

function GoWWishlists:CollectMemberObtainedItems(characterName, realmName)
    local results = {};
    local data = self.state.guildWishlistData;
    if not data or not data.wishlists then return results end

    for _, charEntry in ipairs(data.wishlists) do
        if charEntry.name == characterName and charEntry.realmName == realmName then
            for _, item in ipairs(charEntry.wishlist) do
                if item.isObtained then
                    table.insert(results, {
                        itemId = item.itemId,
                        difficulty = item.difficulty,
                        encounterName = item.sourceBossName or "Unknown",
                        winner = charEntry.name,
                        timestamp = item.obtainedOn and math.floor(item.obtainedOn / 1000) or nil,
                    });
                end
            end
            break;
        end
    end

    table.sort(results, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0);
    end);

    return results;
end

function GoWWishlists:PopulateGuildDetailDefault(detailPanel, guildName, memberCount, totalItems)
    local scrollChild = detailPanel.scrollChild;
    self:ClearChildren(scrollChild);
    scrollChild:SetWidth(detailPanel.scrollFrame:GetWidth());

    detailPanel.headerText:SetText("LOOT HISTORY");

    local yOffset = 8;

    local guildText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    guildText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
    guildText:SetText("|cff00ff00" .. guildName .. "|r");
    yOffset = yOffset + 22;

    local statsText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    statsText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
    statsText:SetText("|cff888888" .. memberCount .. " members  ·  " .. totalItems .. " items|r");
    yOffset = yOffset + 16;

    -- Guild obtained items from wishlists
    local obtainedItems = self:CollectGuildObtainedItems();
    if #obtainedItems == 0 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        emptyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
        emptyText:SetPoint("RIGHT", scrollChild, "RIGHT", -10, 0);
        emptyText:SetWordWrap(true);
        emptyText:SetText("|cff666666No obtained items yet.\nItems will appear here as guild members obtain their wishlist drops.|r");
        yOffset = yOffset + 40;
        scrollChild:SetHeight(yOffset);
        return;
    end

    -- Section header
    local sectionHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    sectionHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
    sectionHeader:SetText("|cff888888Obtained Items (" .. #obtainedItems .. ")|r");
    yOffset = yOffset + 16;

    -- Already sorted most-recent-first, cap at 50
    local maxRows = 50;
    for i, record in ipairs(obtainedItems) do
        if i > maxRows then break end

        local row = self:CreateLootHistoryRow(scrollChild, true);
        self:PopulateLootHistoryRow(row, record);

        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        row:Show();
        yOffset = yOffset + self.constants.LOOT_ROW_HEIGHT;
    end

    scrollChild:SetHeight(yOffset + 8);
end

function GoWWishlists:PopulateGuildPlayerDetail(detailPanel, member, guildRealm)
    local scrollChild = detailPanel.scrollChild;
    self:ClearChildren(scrollChild);
    scrollChild:SetWidth(detailPanel.scrollFrame:GetWidth());

    local classColor = self:GetClassColor(member.classId);
    local colorHex = self:ClassColorToHex(classColor);

    local displayName = member.characterName;
    if guildRealm and member.realmName and member.realmName ~= guildRealm then
        displayName = displayName .. "-" .. member.realmName;
    end

    detailPanel.headerText:SetText("|cff" .. colorHex .. displayName .. "|r");

    local yOffset = 4;

    -- Back button
    local backBtn = CreateFrame("Button", nil, scrollChild, "BackdropTemplate");
    backBtn:SetSize(16, 16);
    backBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, -yOffset);
    local backText = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    backText:SetAllPoints();
    backText:SetText("|cff888888< Back|r");
    backBtn:SetWidth(40);
    backBtn:SetScript("OnClick", function()
        -- Find guild stats and reset to default
        local guildName = GoWWishlists.state.guildWishlistData and GoWWishlists.state.guildWishlistData.guild or "Guild";
        GoWWishlists:PopulateGuildDetailDefault(detailPanel, guildName, 0, 0);
    end);
    backBtn:SetScript("OnEnter", function(self)
        backText:SetText("|cffffff00< Back|r");
    end);
    backBtn:SetScript("OnLeave", function(self)
        backText:SetText("|cff888888< Back|r");
    end);
    yOffset = yOffset + 22;

    -- Find this member's full wishlist from guild data
    local memberItems = {};
    if self.state.guildWishlistData and self.state.guildWishlistData.wishlists then
        for _, charEntry in ipairs(self.state.guildWishlistData.wishlists) do
            if charEntry.name == member.characterName and charEntry.realmName == member.realmName then
                for _, item in ipairs(charEntry.wishlist) do
                    if not item.isObtained then
                        table.insert(memberItems, item);
                    end
                end
                break;
            end
        end
    end

    -- Sort by gain% descending
    table.sort(memberItems, function(a, b)
        local aGain = (a.gain and a.gain.percent) or 0;
        local bGain = (b.gain and b.gain.percent) or 0;
        return aGain > bGain;
    end);

    -- Item count
    local countText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    countText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
    countText:SetText("|cff888888" .. #memberItems .. " wishlist items|r");
    yOffset = yOffset + 16;

    -- Wishlist items
    for _, entry in ipairs(memberItems) do
        local row = self:CreateItemRow(scrollChild);
        row.showSource = true;
        self:PopulateItemRow(row, entry);

        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        row:Show();
        yOffset = yOffset + self.constants.BROWSER_ITEM_HEIGHT;
    end

    if #memberItems == 0 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -(yOffset + 20));
        emptyText:SetText("|cff888888No wishlist items.|r");
        yOffset = yOffset + 60;
    end

    -- Obtained items for this member
    local memberObtained = self:CollectMemberObtainedItems(member.characterName, member.realmName);
    if #memberObtained > 0 then
        -- Section separator
        local sep = scrollChild:CreateTexture(nil, "ARTWORK");
        sep:SetTexture("Interface\\Buttons\\WHITE8x8");
        sep:SetVertexColor(0.25, 0.25, 0.3, 0.3);
        sep:SetHeight(1);
        sep:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
        sep:SetPoint("RIGHT", scrollChild, "RIGHT", -10, 0);
        yOffset = yOffset + 8;

        local lootHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        lootHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
        lootHeader:SetText("|cff888888Obtained Items (" .. #memberObtained .. ")|r");
        yOffset = yOffset + 16;

        -- Already sorted most-recent-first, cap at 20
        for i, record in ipairs(memberObtained) do
            if i > 20 then break end

            local row = self:CreateLootHistoryRow(scrollChild, false);
            self:PopulateLootHistoryRow(row, record);

            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
            row:Show();
            yOffset = yOffset + self.constants.LOOT_ROW_HEIGHT;
        end
    end

    scrollChild:SetHeight(yOffset + 8);
end

function GoWWishlists:HandleGuildSlashCommand()
    local frame = self:CreateWishlistBrowserFrame();

    -- Show guild tab and switch to it
    frame.guildWishlistTab:Show();

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
            self:ShowWishlistInfoFrame(item, nil);
        end);
    end
end

function GoWWishlists:HandleSlashCommand()
    self:ShowWishlistBrowserFrame();
end