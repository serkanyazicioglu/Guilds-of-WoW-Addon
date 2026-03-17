local GOW = GuildsOfWow;
local GoWWishlists = {};
GOW.Wishlists = GoWWishlists;

local ns = select(2, ...);

GoWWishlists.state = {
    wishlistIndex = {},
    allItems = {},
    hasPersonalWishlistEntry = false,
    currentCharInfo = nil,
    guildWishlistData = nil,
    pendingItemRows = {},
    raidNameCache = {},
    compactMode = false,
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
    self.state.hasPersonalWishlistEntry = false;
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
                self.state.hasPersonalWishlistEntry = true;
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


GoWWishlists.constants.ALERT_DISPLAY_TIME = 60;
GoWWishlists.constants.ALERT_FADE_TIME = 1.5;

GoWWishlists.constants.GOW_ACCENT_COLOR = { r = 0.1, g = 0.8, b = 0.3 };
GoWWishlists.constants.GOW_BG_COLOR = { r = 0.08, g = 0.08, b = 0.1 };

GoWWishlists.constants.DIFF_COLORS = {
    ["Mythic"]      = { r = 0.616, g = 0, b = 1 },
    ["Heroic"]      = { r = 0, g = 0.439, b = 0.867 },
    ["Normal"]      = { r = 0.118, g = 1, b = 0 },
    ["LFR"]         = { r = 1, g = 0.820, b = 0 },
};

GoWWishlists.constants.DIFF_ABBREV = {
    ["Mythic"]      = "M",
    ["Heroic"]      = "H",
    ["Normal"]      = "N",
    ["LFR"]         = "LFR",
};

GoWWishlists.constants.SUB_ACTIVE_COLOR = { r = GoWWishlists.constants.GOW_ACCENT_COLOR.r, g = GoWWishlists.constants.GOW_ACCENT_COLOR.g, b = GoWWishlists.constants.GOW_ACCENT_COLOR.b, a = 0.3 };
GoWWishlists.constants.SUB_INACTIVE_COLOR = { r = 0.15, g = 0.15, b = 0.18, a = 0.8 };

GoWWishlists.constants.TAB_HEIGHT = 22;
GoWWishlists.constants.TAB_ACTIVE_COLOR = { r = GoWWishlists.constants.GOW_ACCENT_COLOR.r, g = GoWWishlists.constants.GOW_ACCENT_COLOR.g, b = GoWWishlists.constants.GOW_ACCENT_COLOR.b, a = 0.25 };
GoWWishlists.constants.TAB_INACTIVE_COLOR = { r = 0.15, g = 0.15, b = 0.18, a = 0.9 };

GoWWishlists.constants.COLOR_ACCENT = "|cff00ff00";
GoWWishlists.constants.COLOR_SECONDARY = "|cff888888";
GoWWishlists.constants.COLOR_DIM = "|cff666666";
GoWWishlists.constants.COLOR_TIMESTAMP = "|cff555555";
GoWWishlists.constants.COLOR_CLOSE = "|r";

GoWWishlists.constants.TAG_DISPLAY = {
    BIS      = { label = "BiS", color = "25f478", tip = "Best in Slot" },
    NEED     = { label = "N",   color = "ff8000", tip = "Need" },
    GREED    = { label = "G",   color = "ffd700", tip = "Greed" },
    MINOR    = { label = "M",   color = "6495ed", tip = "Minor Upgrade" },
    TRANSMOG = { label = "T",   color = "ff69b4", tip = "Transmog" },
    OFFSPEC  = { label = "OS",  color = "a9a9a9", tip = "Off-Spec" },
};

GoWWishlists.constants.DIFFICULTIES = { "All", "Normal", "Heroic", "Mythic", "LFR" };

GoWWishlists.constants.STANDARD_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
};

GoWWishlists.constants.SLOT_LABELS = {
    ["All"] = "All",
    ["INVTYPE_HEAD"] = "Head",
    ["INVTYPE_NECK"] = "Neck",
    ["INVTYPE_SHOULDER"] = "Shoulder",
    ["INVTYPE_CHEST"] = "Chest",
    ["INVTYPE_ROBE"] = "Chest",
    ["INVTYPE_WAIST"] = "Waist",
    ["INVTYPE_LEGS"] = "Legs",
    ["INVTYPE_FEET"] = "Feet",
    ["INVTYPE_WRIST"] = "Wrist",
    ["INVTYPE_HAND"] = "Hands",
    ["INVTYPE_FINGER"] = "Ring",
    ["INVTYPE_TRINKET"] = "Trinket",
    ["INVTYPE_CLOAK"] = "Back",
    ["INVTYPE_WEAPONMAINHAND"] = "Main Hand",
    ["INVTYPE_WEAPONOFFHAND"] = "Off-Hand",
    ["INVTYPE_HOLDABLE"] = "Off-Hand",
    ["INVTYPE_RANGED"] = "Ranged",
    ["INVTYPE_2HWEAPON"] = "Two-Hand",
    ["INVTYPE_WEAPON"] = "One-Hand",
};

GoWWishlists.constants.SLOT_ORDER = {
    "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER",
    "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WAIST",
    "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST",
    "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_TRINKET",
    "INVTYPE_CLOAK", "INVTYPE_WEAPONMAINHAND",
    "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE",
    "INVTYPE_RANGED", "INVTYPE_2HWEAPON", "INVTYPE_WEAPON",
};

GoWWishlists.constants.BROWSER_ITEM_HEIGHT_CARD = 68;
GoWWishlists.constants.BROWSER_ITEM_HEIGHT_COMPACT = 44;
GoWWishlists.constants.GUILD_ITEM_ROW_HEIGHT_CARD = 36;
GoWWishlists.constants.GUILD_ITEM_ROW_HEIGHT_COMPACT = 28;
GoWWishlists.constants.ALERT_ITEM_ROW_HEIGHT_CARD = 68;
GoWWishlists.constants.ALERT_ITEM_ROW_HEIGHT_COMPACT = 58;

GoWWishlists.constants.BADGE_COLUMN_WIDTH = 40;

function GoWWishlists:GetItemRowHeight()
    return self.state.compactMode and self.constants.BROWSER_ITEM_HEIGHT_COMPACT or self.constants.BROWSER_ITEM_HEIGHT_CARD;
end

function GoWWishlists:GetGuildItemRowHeight()
    return self.state.compactMode and self.constants.GUILD_ITEM_ROW_HEIGHT_COMPACT or self.constants.GUILD_ITEM_ROW_HEIGHT_CARD;
end

function GoWWishlists:GetAlertItemRowHeight()
    return self.state.compactMode and self.constants.ALERT_ITEM_ROW_HEIGHT_COMPACT or self.constants.ALERT_ITEM_ROW_HEIGHT_CARD;
end

function GoWWishlists:CreateBadgeColumn(parent, options)
    local opts = type(options) == "table" and options or {};
    local col = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    local width = opts.width or self.constants.BADGE_COLUMN_WIDTH;
    col:SetWidth(width);

    if opts.attachAfter then
        col:SetPoint("TOPLEFT", opts.attachAfter, "TOPRIGHT", 0, 0);
        col:SetPoint("BOTTOMLEFT", opts.attachAfter, "BOTTOMRIGHT", 0, 0);
    else
        col:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0);
        col:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0);
    end

    col:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" });
    col:SetBackdropColor(0.08, 0.08, 0.1, 0.5);
    col.isDifficultyOnly = opts.difficultyOnly == true;

    if col.isDifficultyOnly then
        local diffText = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        diffText:SetPoint("LEFT", col, "LEFT", 2, 0);
        diffText:SetPoint("RIGHT", col, "RIGHT", -2, 0);
        diffText:SetJustifyH("CENTER");
        col.diffText = diffText;
    else
        local content = CreateFrame("Frame", nil, col);
        content:SetWidth(width - 4);
        content:SetHeight(opts.contentHeight or 28);
        content:SetPoint("CENTER", col, "CENTER", 0, 0);

        local diffText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        diffText:SetPoint("TOP", content, "TOP", 0, 0);
        diffText:SetWidth(width - 4);
        diffText:SetJustifyH("CENTER");
        col.diffText = diffText;

        local sep = content:CreateTexture(nil, "ARTWORK");
        sep:SetTexture("Interface\\Buttons\\WHITE8x8");
        sep:SetVertexColor(0.3, 0.3, 0.35, 0.3);
        sep:SetSize(24, 1);
        sep:SetPoint("TOP", diffText, "BOTTOM", 0, -3);
        col.sep = sep;

        local tagText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        tagText:SetPoint("TOP", sep, "BOTTOM", 0, -3);
        tagText:SetWidth(width - 4);
        tagText:SetJustifyH("CENTER");
        col.tagText = tagText;
    end

    col:EnableMouse(true);
    col:SetScript("OnEnter", function(self)
        if self.tipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine(self.tipText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    col:SetScript("OnLeave", function() GameTooltip:Hide() end);

    local border = col:CreateTexture(nil, "ARTWORK", nil, 2);
    border:SetTexture("Interface\\Buttons\\WHITE8x8");
    border:SetVertexColor(0.25, 0.25, 0.3, 0.3);
    border:SetWidth(1);
    border:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, 0);
    border:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, 0);

    return col;
end

function GoWWishlists:ApplyBadgeColumnState(badgeCol, difficulty, tag)
    if not badgeCol or not badgeCol.diffText then
        return;
    end

    local diffAbbrev = difficulty and self.constants.DIFF_ABBREV[difficulty] or "";
    local dc = difficulty and self.constants.DIFF_COLORS[difficulty];
    if dc then
        badgeCol.diffText:SetText(string.format("|cff%02x%02x%02x%s|r", dc.r * 255, dc.g * 255, dc.b * 255, diffAbbrev));
    else
        badgeCol.diffText:SetText(diffAbbrev);
    end

    local tipParts = {};
    if difficulty then
        table.insert(tipParts, difficulty);
    end

    if badgeCol.tagText then
        local tagLabel = self:FormatTag(tag);
        badgeCol.tagText:SetText(tagLabel or "");
        if badgeCol.sep then
            badgeCol.sep:SetShown(diffAbbrev ~= "" and tagLabel ~= nil);
        end

        local tagInfo = tag and self.constants.TAG_DISPLAY[tag];
        if tagInfo then
            table.insert(tipParts, tagInfo.tip);
        end
    elseif badgeCol.sep then
        badgeCol.sep:Hide();
    end

    badgeCol.tipText = #tipParts > 0 and table.concat(tipParts, "\n") or nil;
end

function GoWWishlists:FormatSlotBadge(itemId)
    if not itemId then return nil end
    local _, _, _, equipLoc, _, classId, subclassId = C_Item.GetItemInfoInstant(itemId);
    if not equipLoc or equipLoc == "" then return nil end

    local slotLabel = self.constants.SLOT_LABELS[equipLoc];
    if not slotLabel then return nil end

    local subclassName;
    if classId and subclassId then
        subclassName = C_Item.GetItemSubClassInfo(classId, subclassId);
        -- Skip generic subclasses
        if subclassName == "Miscellaneous" or subclassName == "Junk" then
            subclassName = nil;
        end
    end

    if subclassName then
        return slotLabel .. " / " .. subclassName;
    end
    return slotLabel;
end

function GoWWishlists:ApplyBackdrop(frame, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    frame:SetBackdrop(self.constants.STANDARD_BACKDROP);
    frame:SetBackdropColor(bgR, bgG, bgB, bgA or 1);
    frame:SetBackdropBorderColor(borderR, borderG, borderB, borderA or 1);
end

function GoWWishlists:RefreshWishlistViews()
    local browserFrame = self.frames.browserFrame;
    if browserFrame and browserFrame.compactBtn and browserFrame.compactBtn.UpdateState then
        browserFrame.compactBtn:UpdateState();
    end
    if browserFrame and browserFrame:IsShown() and browserFrame.SetActiveTab then
        browserFrame.SetActiveTab(browserFrame.activeTab or 1);
    end

    local coreWishlists = self.frames.coreWishlists;
    if coreWishlists and coreWishlists.compactBtn and coreWishlists.compactBtn.UpdateState then
        coreWishlists.compactBtn:UpdateState();
    end
    if coreWishlists and coreWishlists:IsShown() then
        if coreWishlists.RefreshContent then
            coreWishlists:RefreshContent();
        end
        if coreWishlists.SetActiveTab then
            coreWishlists.SetActiveTab(coreWishlists.activeTab or 1);
        end
    end

    local alertContainer = self.frames.alertContainer;
    if alertContainer and alertContainer:IsShown() and alertContainer.itemRows and #alertContainer.itemRows > 0 then
        local activeAlerts = {};
        for _, row in ipairs(alertContainer.itemRows) do
            table.insert(activeAlerts, {
                entry = row.entry,
                itemLink = row.itemLink,
            });
            row:Hide();
            row:SetParent(nil);
        end

        alertContainer.itemRows = {};
        for _, alert in ipairs(activeAlerts) do
            if alert.entry then
                table.insert(alertContainer.itemRows, self:CreateAlertItemRow(alertContainer, alert.entry, alert.itemLink));
            end
        end

        if self.RelayoutAlertContainer then
            self:RelayoutAlertContainer(alertContainer);
        end
    end
end

function GoWWishlists:ToggleCompactMode()
    self.state.compactMode = not self.state.compactMode;
    if GOW.DB and GOW.DB.profile then
        GOW.DB.profile.wishlistCompactMode = self.state.compactMode;
    end
    self:RefreshWishlistViews();
end

function GoWWishlists:GroupAndSortBosses(bossOrder, bossToRaid, bossToJournalId)
    local jid = bossToJournalId or {};
    local raidOrder = {};
    local raidBosses = {};
    local ungrouped = {};

    for _, bossName in ipairs(bossOrder) do
        local raidName = bossToRaid[bossName];
        if raidName then
            if not raidBosses[raidName] then
                raidBosses[raidName] = {};
                table.insert(raidOrder, raidName);
            end
            table.insert(raidBosses[raidName], bossName);
        else
            table.insert(ungrouped, bossName);
        end
    end

    table.sort(raidOrder, function(a, b)
        local function getInstanceId(raid, bossList)
            for _, bName in ipairs(bossList) do
                local encId = jid[bName];
                if encId and EJ_GetEncounterInfo then
                    local _, _, _, _, _, instId = EJ_GetEncounterInfo(encId);
                    if instId then return instId end
                end
            end
            return 0;
        end
        return getInstanceId(a, raidBosses[a]) < getInstanceId(b, raidBosses[b]);
    end);

    for _, raidName in ipairs(raidOrder) do
        table.sort(raidBosses[raidName], function(a, b)
            return (jid[a] or 0) < (jid[b] or 0);
        end);
    end

    return raidOrder, raidBosses, ungrouped;
end

function GoWWishlists:SetupDifficultyDropdown(sourcePanel, onChangeCallback)
    if sourcePanel.diffDropdownBtn then return end
    local headerBar = sourcePanel.headerBar;
    local popupMenu = self:GetOrCreatePopupMenu();
    local showPopup = popupMenu.showPopup;

    local activeDiff = "All";

    local btn = self:CreateSubFilterBtn(sourcePanel, "Diff: All", 80);
    btn:SetHeight(14);
    btn:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 4, -4);

    local function updateDiffLabel(diff)
        activeDiff = diff;
        btn.btnText:SetText("Diff: " .. diff);
        local textWidth = btn.btnText:GetStringWidth();
        btn:SetWidth(math.max(textWidth + 16, 60));
        self:SetButtonActive(btn, diff ~= "All");
    end

    btn:SetScript("OnClick", function()
        if popupMenu.popup:IsShown() and popupMenu.popup.owner == "difficulty" then
            popupMenu.clearPopup();
            return;
        end
        local options = {};
        for _, diff in ipairs(self.constants.DIFFICULTIES) do
            table.insert(options, { key = diff, label = diff });
        end
        popupMenu.popup.owner = "difficulty";
        showPopup(btn, options, activeDiff, function(key)
            updateDiffLabel(key);
            onChangeCallback(key);
        end);
    end);

    sourcePanel.diffDropdownBtn = btn;
    sourcePanel.updateDiffLabel = updateDiffLabel;
    sourcePanel.scrollFrame:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", -4, -4);
end

function GoWWishlists:SetItemIconAndName(row, itemId, itemLink)
    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemId);
    row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark");

    if itemQuality then
        local r, g, b, hex = C_Item.GetItemQualityColor(itemQuality);
        row.iconBorder:SetVertexColor(r, g, b, 0.7);
        row.nameText:SetText(itemLink or ("|c" .. hex .. (itemName or ("Item " .. itemId)) .. "|r"));
    else
        row.iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.6);
        row.nameText:SetText(itemLink or itemName or ("Item " .. itemId));
    end

    return itemName;
end

function GoWWishlists:BuildInfoLine(entry, showSource)
    local parts = {};
    if showSource ~= false and entry.sourceBossName then
        table.insert(parts, "|cff888888" .. entry.sourceBossName .. "|r");
    end
    return table.concat(parts, "  ");
end

function GoWWishlists:CreateNoteIconButton(parent, row, texturePath, header, headerR, headerG, headerB)
    local button = CreateFrame("Button", nil, parent);
    button:SetSize(14, 14);

    local texture = button:CreateTexture(nil, "ARTWORK");
    texture:SetAllPoints();
    texture:SetTexture(texturePath);

    button:SetScript("OnEnter", function(self)
        row.highlight:Show();
        if self.noteText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine(header, headerR or 1, headerG or 1, headerB or 1);
            GameTooltip:AddLine(self.noteText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    button:SetScript("OnLeave", function()
        row.highlight:Hide();
        GameTooltip:Hide();
    end);
    button:Hide();

    return button;
end

function GoWWishlists:ApplyNoteLabels(row, notes)
    if row.noteIcon then
        row.noteIcon.noteText = nil;
        row.noteIcon:Hide();
    end

    if notes and notes ~= "" and row.noteIcon then
        row.noteIcon.noteText = notes;
        row.noteIcon:Show();
    end
end

function GoWWishlists:CreateGainBadge(parent)
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    badge:SetHeight(16);
    badge:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    });
    badge:SetBackdropColor(0.05, 0.15, 0.05, 0.85);
    badge:SetBackdropBorderColor(0.1, 0.8, 0.3, 0.6);

    local text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    text:SetPoint("CENTER", badge, "CENTER", 0, 0);
    text:SetJustifyH("CENTER");
    badge.text = text;

    badge:EnableMouse(true);
    badge:SetScript("OnEnter", function(self)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Upgrade", 0, 1, 0);
            GameTooltip:AddLine(self.tooltipText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end);

    badge:Hide();
    return badge;
end

function GoWWishlists:ApplyGainBadge(badge, gain, prefix)
    if not badge then return end
    prefix = prefix or "";

    local hasGain = false;
    if gain and gain.percent and gain.percent > 0 then
        local metric = (gain.metric and gain.metric ~= "") and gain.metric or "DPS";
        badge.text:SetText("|cff00ff00" .. prefix .. string.format("%.1f", gain.percent) .. "%|r");

        local tipParts = {};
        table.insert(tipParts, string.format("%.1f%% %s", gain.percent, metric));
        if gain.stat and gain.stat > 0 then
            table.insert(tipParts, "+" .. string.format("%.0f", gain.stat) .. " " .. metric);
        end
        badge.tooltipText = table.concat(tipParts, "\n");
        hasGain = true;
    elseif gain and gain.stat and gain.stat > 0 then
        badge.text:SetText("|cff00ff00" .. prefix .. string.format("%.0f", gain.stat) .. "|r");
        badge.tooltipText = "+" .. string.format("%.0f", gain.stat);
        hasGain = true;
    end

    if hasGain then
        badge:SetWidth(badge.text:GetStringWidth() + 12);
        badge:Show();
    else
        badge.tooltipText = nil;
        badge:Hide();
    end
end

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

function GoWWishlists:HasGuildWishlistData()
    return self.state.guildWishlistData and self.state.guildWishlistData.wishlists and #self.state.guildWishlistData.wishlists > 0;
end

function GoWWishlists:HasPersonalWishlistEntry()
    return self.state.hasPersonalWishlistEntry == true;
end

function GoWWishlists:GetSyncAppInstallHint()
    return "Download and install the GoW Sync App to populate your wishlist data for this feature.";
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

function GoWWishlists:CreateTextHoverTooltip(parent, anchor, row, header, headerR, headerG, headerB)
    local hover = CreateFrame("Frame", nil, parent);
    hover:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 2);
    hover:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, -2);
    hover:EnableMouse(true);
    hover:SetScript("OnEnter", function(self)
        row.highlight:Show();
        if self.tipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            if header then
                GameTooltip:AddLine(header, headerR or 1, headerG or 1, headerB or 1);
            end
            GameTooltip:AddLine(self.tipText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    hover:SetScript("OnLeave", function()
        row.highlight:Hide();
        GameTooltip:Hide();
    end);
    return hover;
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
    self:ApplyBackdrop(btn, self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a, 0.3, 0.3, 0.3, 0.4);

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    btnText:SetPoint("CENTER", btn, "CENTER", 0, 0);
    btnText:SetText(label);
    btn.btnText = btnText;

    return btn;
end

function GoWWishlists:SetButtonActive(btn, isActive)
    if isActive then
        btn:SetBackdropColor(self.constants.SUB_ACTIVE_COLOR.r, self.constants.SUB_ACTIVE_COLOR.g, self.constants.SUB_ACTIVE_COLOR.b, self.constants.SUB_ACTIVE_COLOR.a);
        btn:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
    else
        btn:SetBackdropColor(self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a);
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);
    end
end

function GoWWishlists:SetButtonActiveWithIcon(btn, iconTex, isActive)
    self:SetButtonActive(btn, isActive);
    if iconTex then
        if isActive then
            iconTex:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 1);
        else
            iconTex:SetVertexColor(0.5, 0.5, 0.5, 0.6);
        end
    end
end

function GoWWishlists:CreateRowHighlight(frame, alpha)
    local highlight = frame:CreateTexture(nil, "BACKGROUND");
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8");
    highlight:SetAllPoints();
    highlight:SetVertexColor(1, 1, 1, alpha or 0.04);
    highlight:Hide();
    return highlight;
end

function GoWWishlists:CreateRowIcon(parent, borderSize, leftOffset)
    local iconBorder = parent:CreateTexture(nil, "ARTWORK", nil, 0);
    iconBorder:SetTexture("Interface\\Buttons\\WHITE8x8");
    iconBorder:SetSize(borderSize, borderSize);
    iconBorder:SetPoint("LEFT", parent, "LEFT", leftOffset, 0);
    iconBorder:SetVertexColor(0.4, 0.4, 0.4, 0.6);

    local icon = parent:CreateTexture(nil, "ARTWORK", nil, 1);
    icon:SetSize(borderSize - 2, borderSize - 2);
    icon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0);
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);

    return iconBorder, icon;
end

function GoWWishlists:CreateRowSeparator(parent)
    local sep = parent:CreateTexture(nil, "ARTWORK");
    sep:SetTexture("Interface\\Buttons\\WHITE8x8");
    sep:SetVertexColor(0.25, 0.25, 0.3, 0.15);
    sep:SetHeight(1);
    sep:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 6, 0);
    sep:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 0);
    return sep;
end

function GoWWishlists:CreateItemTooltipZone(row, iconBorder)
    local iconHover = CreateFrame("Frame", nil, row);
    iconHover:SetAllPoints(iconBorder);
    iconHover:EnableMouse(true);
    iconHover:SetScript("OnEnter", function()
        row.highlight:Show();
        if row.itemId then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT");
            GameTooltip:SetItemByID(row.itemId);
            GameTooltip:Show();
        end
    end);
    iconHover:SetScript("OnLeave", function()
        row.highlight:Hide();
        GameTooltip:Hide();
    end);

    row:EnableMouse(true);
    row:SetScript("OnEnter", function(self) self.highlight:Show() end);
    row:SetScript("OnLeave", function(self) self.highlight:Hide() end);

    return iconHover;
end

function GoWWishlists:CreateTabButton(parentFrame, label, tabIndex)
    local c = self.constants;
    local tab = CreateFrame("Button", nil, parentFrame, "BackdropTemplate");
    tab:SetHeight(c.TAB_HEIGHT);
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
        if self.tabIndex ~= parentFrame.activeTab then
            self:SetBackdropColor(0.2, 0.2, 0.25, 0.9);
        end
    end);
    tab:SetScript("OnLeave", function(self)
        if self.tabIndex ~= parentFrame.activeTab then
            self:SetBackdropColor(c.TAB_INACTIVE_COLOR.r, c.TAB_INACTIVE_COLOR.g, c.TAB_INACTIVE_COLOR.b, c.TAB_INACTIVE_COLOR.a);
        end
    end);

    return tab;
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

function GoWWishlists:GetOrCreatePopupMenu()
    if self.frames.sharedPopup then
        return self.frames.sharedPopup;
    end

    local popup = CreateFrame("Frame", "GoWDetailPopup", UIParent, "BackdropTemplate");
    popup:SetFrameStrata("TOOLTIP");
    self:ApplyBackdrop(popup, 0.1, 0.1, 0.13, 0.96, 0.3, 0.3, 0.35, 0.8);
    popup:Hide();
    popup:SetClampedToScreen(true);
    popup.items = {};

    local function clearPopup()
        for _, item in ipairs(popup.items) do
            item:Hide();
            item:SetParent(nil);
        end
        popup.items = {};
        popup:Hide();
    end

    local accentHex = string.format("%02x%02x%02x", self.constants.GOW_ACCENT_COLOR.r * 255, self.constants.GOW_ACCENT_COLOR.g * 255, self.constants.GOW_ACCENT_COLOR.b * 255);

    local function showPopup(anchor, options, currentValue, onSelect)
        clearPopup();
        local ITEM_HEIGHT = 18;
        local MIN_POPUP_WIDTH = 110;
        local yOff = 4;
        local maxTextWidth = 0;

        for _, opt in ipairs(options) do
            local item = CreateFrame("Button", nil, popup);
            item:SetHeight(ITEM_HEIGHT);
            item:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -yOff);
            item:SetPoint("RIGHT", popup, "RIGHT", -4, 0);

            local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
            text:SetPoint("LEFT", item, "LEFT", 6, 0);
            text:SetJustifyH("LEFT");

            local isActive = (opt.key == currentValue);
            if isActive then
                text:SetText("|cff" .. accentHex .. opt.label .. "|r");
            else
                text:SetText("|cffcccccc" .. opt.label .. "|r");
            end

            local tw = text:GetStringWidth();
            if tw > maxTextWidth then maxTextWidth = tw end

            local hl = item:CreateTexture(nil, "BACKGROUND");
            hl:SetTexture("Interface\\Buttons\\WHITE8x8");
            hl:SetAllPoints();
            hl:SetVertexColor(1, 1, 1, 0.06);
            hl:Hide();

            item:SetScript("OnEnter", function() hl:Show() end);
            item:SetScript("OnLeave", function() hl:Hide() end);
            item:SetScript("OnClick", function()
                clearPopup();
                onSelect(opt.key, opt.label);
            end);

            table.insert(popup.items, item);
            yOff = yOff + ITEM_HEIGHT;
        end

        local popupWidth = math.max(MIN_POPUP_WIDTH, maxTextWidth + 24);
        popup:SetSize(popupWidth, yOff + 4);
        popup:ClearAllPoints();
        popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2);
        popup:Show();
    end

    popup:SetScript("OnShow", function()
        popup:SetPropagateKeyboardInput(false);
    end);
    popup:SetScript("OnHide", function()
        popup:SetPropagateKeyboardInput(true);
    end);

    local clickAway = CreateFrame("Button", nil, UIParent);
    clickAway:SetAllPoints(UIParent);
    clickAway:SetFrameStrata("TOOLTIP");
    clickAway:SetFrameLevel(popup:GetFrameLevel() - 1);
    clickAway:RegisterForClicks("AnyUp");
    clickAway:SetScript("OnClick", function() clearPopup(); clickAway:Hide() end);
    clickAway:Hide();

    popup:HookScript("OnShow", function() clickAway:Show() end);
    popup:HookScript("OnHide", function() clickAway:Hide() end);

    self.frames.sharedPopup = { popup = popup, showPopup = showPopup, clearPopup = clearPopup };
    return self.frames.sharedPopup;
end
