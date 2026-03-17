local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;

GoWWishlists.constants.BROWSER_ITEM_HEIGHT = 68;
GoWWishlists.constants.BROWSER_BOSS_HEADER_HEIGHT = 24;
GoWWishlists.constants.RAID_HEADER_HEIGHT = 18;

function GoWWishlists:CreateBadgeColumn(parent, rowHeight)
    local col = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    col:SetWidth(self.constants.BADGE_COLUMN_WIDTH);
    col:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0);
    col:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0);
    col:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    });
    col:SetBackdropColor(0.08, 0.08, 0.1, 0.5);

    local content = CreateFrame("Frame", nil, col);
    content:SetWidth(self.constants.BADGE_COLUMN_WIDTH - 4);
    content:SetHeight(28);
    content:SetPoint("CENTER", col, "CENTER", 0, 0);

    local diffText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    diffText:SetPoint("TOP", content, "TOP", 0, 0);
    diffText:SetWidth(self.constants.BADGE_COLUMN_WIDTH - 4);
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
    tagText:SetWidth(self.constants.BADGE_COLUMN_WIDTH - 4);
    tagText:SetJustifyH("CENTER");
    col.tagText = tagText;

    col:EnableMouse(true);
    col:SetScript("OnEnter", function(self)
        if self.tipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine(self.tipText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    col:SetScript("OnLeave", function() GameTooltip:Hide() end);

    -- Right-side border
    local border = col:CreateTexture(nil, "ARTWORK", nil, 2);
    border:SetTexture("Interface\\Buttons\\WHITE8x8");
    border:SetVertexColor(0.25, 0.25, 0.3, 0.3);
    border:SetWidth(1);
    border:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, 0);
    border:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, 0);

    return col;
end

function GoWWishlists:CreateItemRow(parent)
    local isCompact = self.state.compactMode;
    local rowHeight = self:GetItemRowHeight();
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(rowHeight);

    -- Badge column (left side)
    local badgeCol = self:CreateBadgeColumn(row, rowHeight);
    row.badgeCol = badgeCol;

    local BADGE_W = self.constants.BADGE_COLUMN_WIDTH;
    local iconSize = isCompact and 22 or 32;

    -- Inner content area (right of badge column)
    local inner = CreateFrame("Frame", nil, row);
    inner:SetPoint("LEFT", badgeCol, "RIGHT", 4, 0);
    inner:SetPoint("RIGHT", row, "RIGHT", 0, 0);
    local innerHeight = isCompact and 34 or 50;
    inner:SetHeight(innerHeight);
    inner:SetPoint("TOP", row, "TOP", 0, -math.floor((rowHeight - innerHeight) / 2));

    local iconBorder, icon = self:CreateRowIcon(inner, iconSize, 4);
    row.iconBorder = iconBorder;
    row.icon = icon;

    -- Note icons (top-right)
    local officerNoteIcon = CreateFrame("Button", nil, row);
    officerNoteIcon:SetSize(14, 14);
    officerNoteIcon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6);
    local officerNoteTex = officerNoteIcon:CreateTexture(nil, "ARTWORK");
    officerNoteTex:SetAllPoints();
    officerNoteTex:SetTexture("Interface\\Buttons\\UI-GuildButton-OfficerNote-Up");
    officerNoteIcon:Hide();
    row.officerNoteIcon = officerNoteIcon;

    local noteIcon = CreateFrame("Button", nil, row);
    noteIcon:SetSize(14, 14);
    noteIcon:SetPoint("RIGHT", officerNoteIcon, "LEFT", -2, 0);
    local noteIconTex = noteIcon:CreateTexture(nil, "ARTWORK");
    noteIconTex:SetAllPoints();
    noteIconTex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up");
    noteIcon:Hide();
    row.noteIcon = noteIcon;

    -- Name text (top line)
    local nameText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 6, 2);
    nameText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    row.nameText = nameText;

    -- Info text (second line: boss · difficulty)
    local infoText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2);
    infoText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    infoText:SetJustifyH("LEFT");
    infoText:SetWordWrap(false);
    row.infoText = infoText;

    row.infoHover = self:CreateTextHoverTooltip(inner, infoText, row);

    -- Slot badge text (third line, card mode only)
    local slotText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    slotText:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -1);
    slotText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    slotText:SetJustifyH("LEFT");
    slotText:SetWordWrap(false);
    row.slotText = slotText;
    if isCompact then slotText:Hide() end

    -- Gain badge (right of name line)
    local gainBadge = self:CreateGainBadge(inner);
    gainBadge:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    gainBadge:SetPoint("TOP", nameText, "TOP", 0, 0);
    row.gainBadge = gainBadge;

    -- Note text labels (inline text for wide rows, fall back to icons for narrow)
    local noteLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    noteLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    noteLabel:SetPoint("TOP", infoText, "TOP", 0, 0);
    noteLabel:SetJustifyH("RIGHT");
    noteLabel:SetWordWrap(false);
    noteLabel:Hide();
    row.noteLabel = noteLabel;

    local noteHover = CreateFrame("Frame", nil, row);
    noteHover:SetPoint("TOPLEFT", noteLabel, "TOPLEFT", 0, 2);
    noteHover:SetPoint("BOTTOMRIGHT", noteLabel, "BOTTOMRIGHT", 0, -2);
    noteHover:EnableMouse(true);
    noteHover:SetScript("OnEnter", function(self)
        row.highlight:Show();
        if self.tipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Note", 0, 1, 0);
            GameTooltip:AddLine(self.tipText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    noteHover:SetScript("OnLeave", function()
        row.highlight:Hide();
        GameTooltip:Hide();
    end);
    noteHover:Hide();
    row.noteHover = noteHover;

    local officerNoteLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    officerNoteLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    officerNoteLabel:SetPoint("TOP", slotText, "TOP", 0, 0);
    officerNoteLabel:SetJustifyH("RIGHT");
    officerNoteLabel:SetWordWrap(false);
    officerNoteLabel:Hide();
    row.officerNoteLabel = officerNoteLabel;

    local officerNoteHover = CreateFrame("Frame", nil, row);
    officerNoteHover:SetPoint("TOPLEFT", officerNoteLabel, "TOPLEFT", 0, 2);
    officerNoteHover:SetPoint("BOTTOMRIGHT", officerNoteLabel, "BOTTOMRIGHT", 0, -2);
    officerNoteHover:EnableMouse(true);
    officerNoteHover:SetScript("OnEnter", function(self)
        row.highlight:Show();
        if self.tipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Officer Note", 1, 0.5, 0);
            GameTooltip:AddLine(self.tipText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    officerNoteHover:SetScript("OnLeave", function()
        row.highlight:Hide();
        GameTooltip:Hide();
    end);
    officerNoteHover:Hide();
    row.officerNoteHover = officerNoteHover;

    -- Tooltip scripts for note icons
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

    -- Bottom separator
    self:CreateRowSeparator(row);

    row.highlight = self:CreateRowHighlight(row);
    self:CreateItemTooltipZone(row, iconBorder);

    return row;
end

function GoWWishlists:PopulateItemRow(row, entry)
    row.itemId = entry.itemId;

    local itemName = self:SetItemIconAndName(row, entry.itemId);

    if not itemName then
        self:RegisterPendingItem(entry.itemId, function()
            if row:GetParent() then
                self:PopulateItemRow(row, entry);
            end
        end);
    end

    row.infoText:SetText(self:BuildInfoLine(entry, row.showSource));

    -- Badge column: difficulty + tag
    if row.badgeCol then
        local diffAbbrev = entry.difficulty and self.constants.DIFF_ABBREV[entry.difficulty] or "";
        local dc = entry.difficulty and self.constants.DIFF_COLORS[entry.difficulty];
        if dc then
            row.badgeCol.diffText:SetText(string.format("|cff%02x%02x%02x%s|r", dc.r * 255, dc.g * 255, dc.b * 255, diffAbbrev));
        else
            row.badgeCol.diffText:SetText(diffAbbrev);
        end

        local tagLabel = self:FormatTag(entry.tag);
        row.badgeCol.tagText:SetText(tagLabel or "");
        row.badgeCol.sep:SetShown(diffAbbrev ~= "" and tagLabel ~= nil);

        local tipParts = {};
        if entry.difficulty then table.insert(tipParts, entry.difficulty) end
        local tagInfo = entry.tag and self.constants.TAG_DISPLAY[entry.tag];
        if tagInfo then table.insert(tipParts, tagInfo.tip) end
        row.badgeCol.tipText = #tipParts > 0 and table.concat(tipParts, "\n") or nil;
    end

    -- Slot badge (card mode only)
    if row.slotText then
        local slotBadge = self:FormatSlotBadge(entry.itemId);
        if slotBadge and not self.state.compactMode then
            row.slotText:SetText("|cff888888" .. slotBadge .. "|r");
            row.slotText:Show();
        else
            row.slotText:SetText("");
            row.slotText:Hide();
        end
    end

    local infoParts = {};
    if entry.sourceBossName then table.insert(infoParts, "Source: " .. entry.sourceBossName) end
    if entry.difficulty then table.insert(infoParts, "Difficulty: " .. entry.difficulty) end
    row.infoHover.tipText = #infoParts > 0 and table.concat(infoParts, "\n") or nil;

    self:ApplyNoteLabels(row, entry.notes, entry.officerNotes);
    self:ApplyGainBadge(row.gainBadge, entry.gain);
end

function GoWWishlists:CreateBossHeader(parent, bossName, itemCount)
    local header = CreateFrame("Button", nil, parent);
    header:SetHeight(self.constants.BROWSER_BOSS_HEADER_HEIGHT);
    header.isCollapsed = true;
    header.itemRows = {};

    local arrow = header:CreateTexture(nil, "OVERLAY");
    arrow:SetSize(12, 12);
    arrow:SetPoint("LEFT", header, "LEFT", 6, 0);
    arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-UP");
    header.arrow = arrow;

    local bar = header:CreateTexture(nil, "ARTWORK");
    bar:SetTexture("Interface\\Buttons\\WHITE8x8");
    bar:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.6);
    bar:SetSize(3, 16);
    bar:SetPoint("LEFT", arrow, "RIGHT", 4, 0);

    local nameText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("LEFT", bar, "RIGHT", 6, 0);
    nameText:SetText("|cffcc00cc" .. bossName .. "|r");

    local countText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    countText:SetPoint("LEFT", nameText, "RIGHT", 8, 0);
    countText:SetText("|cff888888(" .. itemCount .. ")|r");

    local sep = header:CreateTexture(nil, "ARTWORK");
    sep:SetTexture("Interface\\Buttons\\WHITE8x8");
    sep:SetVertexColor(0.3, 0.3, 0.3, 0.3);
    sep:SetHeight(1);
    sep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 6, 0);
    sep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -6, 0);

    local highlight = self:CreateRowHighlight(header);
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

GoWWishlists.constants.SOURCE_PANEL_WIDTH = 180;
GoWWishlists.constants.DETAIL_PANEL_WIDTH = 260;
GoWWishlists.constants.PANEL_HEADER_HEIGHT = 28;
GoWWishlists.constants.BOSS_ROW_HEIGHT = 24;
GoWWishlists.constants.SOURCE_FILTER_HEIGHT = 26;

function GoWWishlists:StyleScrollBar(scrollFrame)
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"];
    if not scrollBar then return end

    local upBtn = scrollBar.ScrollUpButton or _G[scrollBar:GetName() .. "ScrollUpButton"];
    local downBtn = scrollBar.ScrollDownButton or _G[scrollBar:GetName() .. "ScrollDownButton"];
    if upBtn then upBtn:SetAlpha(0); upBtn:SetSize(1, 1) end
    if downBtn then downBtn:SetAlpha(0); downBtn:SetSize(1, 1) end

    scrollBar:SetWidth(6);

    local thumb = scrollBar.ThumbTexture or scrollBar:GetThumbTexture();
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8x8");
        thumb:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
        thumb:SetSize(6, 40);
    end

    local track = scrollBar:CreateTexture(nil, "BACKGROUND");
    track:SetTexture("Interface\\Buttons\\WHITE8x8");
    track:SetVertexColor(0.05, 0.05, 0.08, 0.6);
    track:SetAllPoints(scrollBar);

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
    self:ApplyBackdrop(panel, 0.06, 0.06, 0.08, 0.95, 0.2, 0.2, 0.25, 0.6);

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

    local sf = CreateFrame("ScrollFrame", name and (name .. "Scroll") or nil, panel, "UIPanelScrollFrameTemplate");
    sf:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -2);
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 2);

    local child = CreateFrame("Frame", nil, sf);
    child:SetHeight(1);
    sf:SetScrollChild(child);
    panel.scrollFrame = sf;
    panel.scrollChild = child;

    self:StyleScrollBar(sf);

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

    local sourcePanel = self:CreatePanelFrame(container, "GoWSourcePanel");
    sourcePanel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0);
    sourcePanel:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0);
    sourcePanel:SetWidth(SOURCE_W);
    sourcePanel.headerText:SetText("SOURCE");
    container.sourcePanel = sourcePanel;

    local detailPanel = self:CreatePanelFrame(container, "GoWDetailPanel");
    detailPanel:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0);
    detailPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0);
    detailPanel:SetWidth(DETAIL_W);
    detailPanel.headerText:SetText("WISHLIST");
    container.detailPanel = detailPanel;

    local lootPanel = self:CreatePanelFrame(container, "GoWLootPanel");
    lootPanel:SetPoint("TOPLEFT", sourcePanel, "TOPRIGHT", 2, 0);
    lootPanel:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMLEFT", -2, 0);
    lootPanel.headerText:SetText("LOOT DROPS");
    container.lootPanel = lootPanel;

    container.panels = { sourcePanel, lootPanel, detailPanel };

    return container;
end

function GoWWishlists:CreateBossRow(parent, bossName, itemCount, isAllBosses)
    local row = CreateFrame("Button", nil, parent);
    row:SetHeight(self.constants.BOSS_ROW_HEIGHT);

    row.highlight = self:CreateRowHighlight(row);

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

function GoWWishlists:PopulateSourcePanel(panel, bossOrder, bossCounts, onBossSelected, bossToRaid, bossToJournalId)
    local scrollChild = panel.scrollChild;
    self:ClearChildren(scrollChild);
    scrollChild:SetWidth(panel.scrollFrame:GetWidth());

    local totalCount = 0;
    for _, name in ipairs(bossOrder) do
        totalCount = totalCount + (bossCounts[name] or 0);
    end

    local yOffset = 0;
    local bossRows = {};

    local allRow = self:CreateBossRow(scrollChild, "All Bosses", totalCount, true);
    allRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
    allRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
    allRow:Show();
    self:SetBossRowActive(allRow, true);
    table.insert(bossRows, { row = allRow, bossName = nil });
    yOffset = yOffset + self.constants.BOSS_ROW_HEIGHT;

    local sep = scrollChild:CreateTexture(nil, "ARTWORK");
    sep:SetTexture("Interface\\Buttons\\WHITE8x8");
    sep:SetVertexColor(0.25, 0.25, 0.3, 0.4);
    sep:SetHeight(1);
    sep:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, -yOffset);
    sep:SetPoint("RIGHT", scrollChild, "RIGHT", -6, 0);
    yOffset = yOffset + 4;

    local function addBossRow(bossName)
        local count = bossCounts[bossName] or 0;
        local bossRow = self:CreateBossRow(scrollChild, bossName, count, false);
        bossRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        bossRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        bossRow:Show();
        table.insert(bossRows, { row = bossRow, bossName = bossName });
        yOffset = yOffset + self.constants.BOSS_ROW_HEIGHT;
    end

    local hasRaidGroups = bossToRaid and next(bossToRaid);
    if hasRaidGroups then
        local raidOrder, raidBosses, ungrouped = self:GroupAndSortBosses(bossOrder, bossToRaid, bossToJournalId);

        for _, raidName in ipairs(raidOrder) do
            local raidHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
            raidHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -(yOffset + 2));
            raidHeader:SetPoint("RIGHT", scrollChild, "RIGHT", -8, 0);
            raidHeader:SetJustifyH("LEFT");
            raidHeader:SetWordWrap(false);
            raidHeader:SetText("|cff666666" .. raidName .. "|r");
            yOffset = yOffset + self.constants.RAID_HEADER_HEIGHT;

            for _, bossName in ipairs(raidBosses[raidName]) do
                addBossRow(bossName);
            end
        end

        if #ungrouped > 0 then
            local otherHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
            otherHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -(yOffset + 2));
            otherHeader:SetPoint("RIGHT", scrollChild, "RIGHT", -8, 0);
            otherHeader:SetJustifyH("LEFT");
            otherHeader:SetWordWrap(false);
            otherHeader:SetText("|cff666666Other|r");
            yOffset = yOffset + self.constants.RAID_HEADER_HEIGHT;

            for _, bossName in ipairs(ungrouped) do
                addBossRow(bossName);
            end
        end
    else
        for _, bossName in ipairs(bossOrder) do
            addBossRow(bossName);
        end
    end

    scrollChild:SetHeight(yOffset + 4);

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
    self:ApplyBackdrop(search, 0.05, 0.05, 0.07, 0.9, 0.25, 0.25, 0.3, 0.5);
    search:SetFontObject("GameFontNormalSmall");
    search:SetTextInsets(20, 6, 0, 0);
    search:SetAutoFocus(false);
    search:SetMaxLetters(30);

    local searchIcon = search:CreateTexture(nil, "OVERLAY");
    searchIcon:SetSize(12, 12);
    searchIcon:SetPoint("LEFT", search, "LEFT", 5, 0);
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon");
    searchIcon:SetVertexColor(0.5, 0.5, 0.5, 0.7);

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
GoWWishlists.constants.LOOT_ROW_HEIGHT = 44;

function GoWWishlists:CreateLootHistoryRow(parent, showWinner)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(self.constants.LOOT_ROW_HEIGHT);

    local inner = CreateFrame("Frame", nil, row);
    inner:SetPoint("LEFT", row, "LEFT", 0, 0);
    inner:SetPoint("RIGHT", row, "RIGHT", 0, 0);
    inner:SetHeight(34);
    inner:SetPoint("TOP", row, "TOP", 0, -math.floor((self.constants.LOOT_ROW_HEIGHT - 34) / 2));

    local iconBorder, icon = self:CreateRowIcon(inner, 24, 8);
    row.iconBorder = iconBorder;
    row.icon = icon;

    local nameText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 6, 2);
    nameText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    row.nameText = nameText;

    local infoText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3);
    infoText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    infoText:SetJustifyH("LEFT");
    infoText:SetWordWrap(false);
    row.infoText = infoText;

    row.showWinner = showWinner;

    self:CreateRowSeparator(row);

    row.highlight = self:CreateRowHighlight(row);
    self:CreateItemTooltipZone(row, iconBorder);

    return row;
end

function GoWWishlists:PopulateLootHistoryRow(row, record)
    row.itemId = record.itemId;

    local itemName = self:SetItemIconAndName(row, record.itemId, record.itemLink);

    if not itemName then
        self:RegisterPendingItem(record.itemId, function()
            if row:GetParent() then
                self:PopulateLootHistoryRow(row, record);
            end
        end);
    end

    local infoParts = {};
    if record.difficulty then
        table.insert(infoParts, self:FormatDifficultyTag(record.difficulty));
    end
    if record.encounterName then
        table.insert(infoParts, "|cff888888" .. record.encounterName .. "|r");
    end
    if row.showWinner and record.winner then
        local winnerHex = "66ccff";
        if record.winnerClass then
            local classColor = self:GetClassColor(record.winnerClass);
            if classColor then
                winnerHex = self:ClassColorToHex(classColor);
            end
        end
        table.insert(infoParts, "|cff" .. winnerHex .. record.winner .. "|r");
    end
    if record.timestamp then
        table.insert(infoParts, "|cff555555" .. date("%m/%d %H:%M", record.timestamp) .. "|r");
    end
    row.infoText:SetText(table.concat(infoParts, "  "));
end
function GoWWishlists:RelayoutBrowserContent(frame)
    local scrollChild = frame.scrollChild;
    local yOffset = 0;

    for _, section in ipairs(frame.sections) do
        if section.raidLabel then
            section.raidLabel:ClearAllPoints();
            section.raidLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -(yOffset + 2));
            section.raidLabel:SetPoint("RIGHT", scrollChild, "RIGHT", -8, 0);
            section.raidLabel:Show();
            yOffset = yOffset + self.constants.RAID_HEADER_HEIGHT;
        else
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
    end

    scrollChild:SetHeight(yOffset + 8);
end

function GoWWishlists:BuildSections(container, scrollChild, bossGroups, bossOrder, unknownItems, bossToRaid, bossToJournalId)
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

    local function addRaidLabel(raidName)
        local label = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        label:SetJustifyH("LEFT");
        label:SetWordWrap(false);
        label:SetText("|cff666666" .. raidName .. "|r");
        table.insert(container.sections, { raidLabel = label });
    end

    local hasRaidGroups = bossToRaid and next(bossToRaid);
    if hasRaidGroups then
        local raidOrder, raidBosses, ungrouped = self:GroupAndSortBosses(bossOrder, bossToRaid, bossToJournalId);

        for _, raidName in ipairs(raidOrder) do
            addRaidLabel(raidName);
            for _, bossName in ipairs(raidBosses[raidName]) do
                addSection(bossName, bossGroups[bossName]);
            end
        end

        if #ungrouped > 0 then
            addRaidLabel("Other");
            for _, bossName in ipairs(ungrouped) do
                addSection(bossName, bossGroups[bossName]);
            end
        end
    else
        for _, bossName in ipairs(bossOrder) do
            addSection(bossName, bossGroups[bossName]);
        end
    end

    if unknownItems and #unknownItems > 0 then
        addSection("Unknown Boss", unknownItems);
    end
end
