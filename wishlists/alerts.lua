local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;

function GoWWishlists:CreateAlertItemRow(parent, match, itemLink)
    local rowHeight = self:GetAlertItemRowHeight();
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(rowHeight);

    local sideBar = row:CreateTexture(nil, "ARTWORK", nil, 2);
    sideBar:SetTexture("Interface\\Buttons\\WHITE8x8");
    sideBar:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.8);
    sideBar:SetWidth(3);
    sideBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0);
    sideBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0);

    -- Badge column
    local badgeCol = CreateFrame("Frame", nil, row, "BackdropTemplate");
    badgeCol:SetWidth(self.constants.BADGE_COLUMN_WIDTH);
    badgeCol:SetPoint("TOPLEFT", sideBar, "TOPRIGHT", 0, 0);
    badgeCol:SetPoint("BOTTOMLEFT", sideBar, "BOTTOMRIGHT", 0, 0);
    badgeCol:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" });
    badgeCol:SetBackdropColor(0.08, 0.08, 0.1, 0.5);

    local content = CreateFrame("Frame", nil, badgeCol);
    content:SetWidth(self.constants.BADGE_COLUMN_WIDTH - 4);
    content:SetHeight(28);
    content:SetPoint("CENTER", badgeCol, "CENTER", 0, 0);

    local diffText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    diffText:SetPoint("TOP", content, "TOP", 0, 0);
    diffText:SetWidth(self.constants.BADGE_COLUMN_WIDTH - 4);
    diffText:SetJustifyH("CENTER");
    badgeCol.diffText = diffText;

    local badgeSep = content:CreateTexture(nil, "ARTWORK");
    badgeSep:SetTexture("Interface\\Buttons\\WHITE8x8");
    badgeSep:SetVertexColor(0.3, 0.3, 0.35, 0.3);
    badgeSep:SetSize(24, 1);
    badgeSep:SetPoint("TOP", diffText, "BOTTOM", 0, -3);
    badgeCol.sep = badgeSep;

    local tagText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    tagText:SetPoint("TOP", badgeSep, "BOTTOM", 0, -3);
    tagText:SetWidth(self.constants.BADGE_COLUMN_WIDTH - 4);
    tagText:SetJustifyH("CENTER");
    badgeCol.tagText = tagText;

    badgeCol:EnableMouse(true);
    badgeCol:SetScript("OnEnter", function(self)
        if self.tipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine(self.tipText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    badgeCol:SetScript("OnLeave", function() GameTooltip:Hide() end);

    local colBorder = badgeCol:CreateTexture(nil, "ARTWORK", nil, 2);
    colBorder:SetTexture("Interface\\Buttons\\WHITE8x8");
    colBorder:SetVertexColor(0.25, 0.25, 0.3, 0.3);
    colBorder:SetWidth(1);
    colBorder:SetPoint("TOPRIGHT", badgeCol, "TOPRIGHT", 0, 0);
    colBorder:SetPoint("BOTTOMRIGHT", badgeCol, "BOTTOMRIGHT", 0, 0);

    row.badgeCol = badgeCol;

    local BADGE_W = self.constants.BADGE_COLUMN_WIDTH;
    local iconSize = self.state.compactMode and 24 or 32;

    local inner = CreateFrame("Frame", nil, row);
    inner:SetPoint("LEFT", badgeCol, "RIGHT", 4, 0);
    inner:SetPoint("RIGHT", row, "RIGHT", 0, 0);
    local innerHeight = self.state.compactMode and 38 or 50;
    inner:SetHeight(innerHeight);
    inner:SetPoint("TOP", row, "TOP", 0, -math.floor((rowHeight - innerHeight) / 2));

    local iconBorder, icon = self:CreateRowIcon(inner, iconSize, 4);
    row.iconBorder = iconBorder;
    row.icon = icon;

    local nameText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 6, 2);
    nameText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    row.nameText = nameText;

    local infoText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2);
    infoText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    infoText:SetJustifyH("LEFT");
    infoText:SetWordWrap(false);
    row.infoText = infoText;

    row.infoHover = self:CreateTextHoverTooltip(inner, infoText, row);

    -- Slot badge (card mode only)
    local slotText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    slotText:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -1);
    slotText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    slotText:SetJustifyH("LEFT");
    slotText:SetWordWrap(false);
    row.slotText = slotText;

    local gainBadge = self:CreateGainBadge(inner);
    gainBadge:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    gainBadge:SetPoint("TOP", nameText, "TOP", 0, 0);
    row.gainBadge = gainBadge;

    -- Note text labels (inline for wide alert rows)
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

    self:CreateRowSeparator(row);

    local noteIcon = CreateFrame("Button", nil, row);
    noteIcon:SetSize(14, 14);
    noteIcon:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -4, 0);
    local noteIconTex = noteIcon:CreateTexture(nil, "ARTWORK");
    noteIconTex:SetAllPoints();
    noteIconTex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up");
    noteIcon:Hide();
    row.noteIcon = noteIcon;

    row.highlight = self:CreateRowHighlight(row);
    row.iconHover = self:CreateItemTooltipZone(row, iconBorder);

    noteIcon:SetScript("OnEnter", function(self)
        row.highlight:Show();
        if self.noteText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Note", 0, 1, 0);
            GameTooltip:AddLine(self.noteText, 1, 1, 1, true);
            GameTooltip:Show();
        end
    end);
    noteIcon:SetScript("OnLeave", function()
        row.highlight:Hide();
        GameTooltip:Hide();
    end);

    row.itemId = match.itemId;
    local itemName = self:SetItemIconAndName(row, match.itemId, itemLink);

    if not itemName then
        self:RegisterPendingItem(match.itemId, function()
            if row:GetParent() then
                self:SetItemIconAndName(row, match.itemId, itemLink);
            end
        end);
    end

    row.infoText:SetText(self:BuildInfoLine(match));

    -- Badge column populate
    local diffAbbrev = match.difficulty and self.constants.DIFF_ABBREV[match.difficulty] or "";
    local dc = match.difficulty and self.constants.DIFF_COLORS[match.difficulty];
    if dc then
        badgeCol.diffText:SetText(string.format("|cff%02x%02x%02x%s|r", dc.r * 255, dc.g * 255, dc.b * 255, diffAbbrev));
    else
        badgeCol.diffText:SetText(diffAbbrev);
    end
    local tagLabel = self:FormatTag(match.tag);
    badgeCol.tagText:SetText(tagLabel or "");
    badgeCol.sep:SetShown(diffAbbrev ~= "" and tagLabel ~= nil);

    local tipParts = {};
    if match.difficulty then table.insert(tipParts, match.difficulty) end
    local tagInfo = match.tag and self.constants.TAG_DISPLAY[match.tag];
    if tagInfo then table.insert(tipParts, tagInfo.tip) end
    badgeCol.tipText = #tipParts > 0 and table.concat(tipParts, "\n") or nil;

    -- Slot badge
    local slotBadge = self:FormatSlotBadge(match.itemId);
    if slotBadge then
        row.slotText:SetText("|cff888888" .. slotBadge .. "|r");
    else
        row.slotText:SetText("");
    end

    local infoParts = {};
    if match.sourceBossName then table.insert(infoParts, "Source: " .. match.sourceBossName) end
    if match.difficulty then table.insert(infoParts, "Difficulty: " .. match.difficulty) end
    if #infoParts > 0 then row.infoHover.tipText = table.concat(infoParts, "\n") end

    self:ApplyNoteLabels(row, match.notes, match.officerNotes);
    self:ApplyGainBadge(row.gainBadge, match.gain);

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

    self:ApplyBackdrop(frame, self.constants.GOW_BG_COLOR.r, self.constants.GOW_BG_COLOR.g, self.constants.GOW_BG_COLOR.b, 0.92, self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.7);

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
        for _, row in ipairs(frame.itemRows or {}) do
            row:Hide();
            row:SetParent(nil);
        end
        frame.itemRows = {};
    end);

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

    local fadeOut = frame:CreateAnimationGroup();
    local fadeAnim = fadeOut:CreateAnimation("Alpha");
    fadeAnim:SetFromAlpha(1);
    fadeAnim:SetToAlpha(0);
    fadeAnim:SetDuration(self.constants.ALERT_FADE_TIME);
    fadeAnim:SetSmoothing("IN");
    fadeOut:SetScript("OnFinished", function()
        frame:Hide();
        frame:SetAlpha(1);
        for _, row in ipairs(frame.itemRows or {}) do
            row:Hide();
            row:SetParent(nil);
        end
        frame.itemRows = {};
    end);
    frame.fadeOut = fadeOut;

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
    if GOW.DB and GOW.DB.profile and not GOW.DB.profile.showLootAlerts then
        return;
    end

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
