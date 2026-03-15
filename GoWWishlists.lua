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
    raidNameCache = {},
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
GoWWishlists.constants.ALERT_ITEM_ROW_HEIGHT = 58;
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

GoWWishlists.constants.COLOR_ACCENT = "|cff00ff00";
GoWWishlists.constants.COLOR_SECONDARY = "|cff888888";
GoWWishlists.constants.COLOR_DIM = "|cff666666";
GoWWishlists.constants.COLOR_TIMESTAMP = "|cff555555";
GoWWishlists.constants.COLOR_CLOSE = "|r";

GoWWishlists.constants.TAG_DISPLAY = {
    BIS      = { label = "BiS",     color = "ff8000", tip = "Best in Slot" },
    NEED     = { label = "Need",    color = "ff0000", tip = "Need" },
    GREED    = { label = "Greed",   color = "00ff00", tip = "Greed" },
    MINOR    = { label = "Minor",   color = "ffff00", tip = "Minor Upgrade" },
    TRANSMOG = { label = "Tmog",    color = "ff69b4", tip = "Transmog" },
    OFFSPEC  = { label = "Offspec", color = "00ccff", tip = "Off-Spec" },
};

GoWWishlists.constants.DIFFICULTIES = { "All", "Normal", "Heroic", "Mythic", "LFR" };
GoWWishlists.constants.DIFFICULTY_LABELS = { "All", "N", "H", "M", "LFR" };

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

function GoWWishlists:ApplyBackdrop(frame, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    frame:SetBackdrop(self.constants.STANDARD_BACKDROP);
    frame:SetBackdropColor(bgR, bgG, bgB, bgA or 1);
    frame:SetBackdropBorderColor(borderR, borderG, borderB, borderA or 1);
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

function GoWWishlists:HighlightDifficultyBtn(btns, activeDiff)
    local difficulties = self.constants.DIFFICULTIES;
    for i, btn in ipairs(btns) do
        self:SetButtonActive(btn, difficulties[i] == activeDiff);
    end
end

function GoWWishlists:SetupDifficultyFilterButtons(sourcePanel, onChangeCallback)
    if sourcePanel.diffFilterBtns then return end
    local difficulties = self.constants.DIFFICULTIES;
    local diffLabels = self.constants.DIFFICULTY_LABELS;
    local btns = {};
    local headerBar = sourcePanel.headerBar;

    for i, diff in ipairs(difficulties) do
        local btn = self:CreateSubFilterBtn(sourcePanel, diffLabels[i], 36);
        btn:SetHeight(14);
        if i == 1 then
            btn:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 4, -4);
        else
            btn:SetPoint("LEFT", btns[i - 1], "RIGHT", 2, 0);
        end
        btns[i] = btn;
    end

    for i, btn in ipairs(btns) do
        btn:SetScript("OnClick", function() onChangeCallback(difficulties[i]) end);
    end

    sourcePanel.diffFilterBtns = btns;
    sourcePanel.scrollFrame:SetPoint("TOPLEFT", btns[1], "BOTTOMLEFT", -4, -4);
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
    if entry.difficulty then
        table.insert(parts, self:FormatDifficultyTag(entry.difficulty));
    end
    return table.concat(parts, "  ");
end

function GoWWishlists:BuildDetailLine(entry)
    local tagLabel = self:FormatTag(entry.tag);
    return tagLabel or "";
end

function GoWWishlists:ApplyNoteIcon(row, notes)
    if notes and notes ~= "" then
        row.noteIcon.noteText = notes;
        row.noteIcon:Show();
    else
        row.noteIcon.noteText = nil;
        row.noteIcon:Hide();
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
