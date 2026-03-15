local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;

function GoWWishlists:CreateAlertItemRow(parent, match, itemLink)
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(self.constants.ALERT_ITEM_ROW_HEIGHT);

    -- Green accent sidebar
    local sideBar = row:CreateTexture(nil, "ARTWORK", nil, 2);
    sideBar:SetTexture("Interface\\Buttons\\WHITE8x8");
    sideBar:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.8);
    sideBar:SetWidth(3);
    sideBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0);
    sideBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0);

    -- Inner frame for vertical centering
    local inner = CreateFrame("Frame", nil, row);
    inner:SetPoint("LEFT", row, "LEFT", 0, 0);
    inner:SetPoint("RIGHT", row, "RIGHT", 0, 0);
    inner:SetHeight(46);
    inner:SetPoint("TOP", row, "TOP", 0, -math.floor((self.constants.ALERT_ITEM_ROW_HEIGHT - 46) / 2));

    local iconBorder, icon = self:CreateRowIcon(inner, 24, 10);
    row.iconBorder = iconBorder;
    row.icon = icon;

    -- Line 1: item name
    local nameText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 6, 2);
    nameText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
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

    -- Hover zone for info line tooltip (difficulty)
    row.infoHover = self:CreateTextHoverTooltip(inner, infoText, row);

    -- Line 3: tag + gain + notes
    local detailText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    detailText:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -2);
    detailText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    detailText:SetJustifyH("LEFT");
    detailText:SetWordWrap(false);
    row.detailText = detailText;

    -- Hover zone for detail line tooltip (tag)
    row.detailHover = self:CreateTextHoverTooltip(inner, detailText, row, "Priority", 0, 1, 0);

    local gainBadge = self:CreateGainBadge(inner);
    gainBadge:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -8, 0);
    row.gainBadge = gainBadge;

    -- Bottom separator
    self:CreateRowSeparator(row);

    -- Note icon: top-right
    local noteIcon = CreateFrame("Button", nil, row);
    noteIcon:SetSize(14, 14);
    noteIcon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6);
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

    -- Populate: icon + name (Line 1)
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
    row.detailText:SetText(self:BuildDetailLine(match));

    -- Set tooltip text for info line (source + difficulty)
    local infoParts = {};
    if match.sourceBossName then table.insert(infoParts, "Source: " .. match.sourceBossName) end
    if match.difficulty then table.insert(infoParts, "Difficulty: " .. match.difficulty) end
    if #infoParts > 0 then row.infoHover.tipText = table.concat(infoParts, "\n") end

    -- Set tooltip text for detail line (tag/priority)
    if match.tag then
        local tagInfo = self.constants.TAG_DISPLAY[match.tag];
        if tagInfo then
            row.detailHover.tipText = tagInfo.tip;
        end
    end

    self:ApplyNoteIcon(row, match.notes);
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
