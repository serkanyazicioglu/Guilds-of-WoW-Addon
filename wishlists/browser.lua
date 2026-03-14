local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;

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

    self:ApplyBackdrop(frame, self.constants.GOW_BG_COLOR.r, self.constants.GOW_BG_COLOR.g, self.constants.GOW_BG_COLOR.b, 0.95, self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.7);

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

    local wishlistContainer = CreateFrame("Frame", "GoWWishlistContainer", frame);
    wishlistContainer:SetPoint("TOPLEFT", contentTop, "BOTTOMLEFT", -4, -8);
    wishlistContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 20);
    frame.wishlistContainer = wishlistContainer;

    local wishlist3Panel = self:Create3PanelLayout(wishlistContainer);
    frame.wishlist3Panel = wishlist3Panel;
    -- Alias for backward compat with relayout methods
    frame.scrollChild = wishlist3Panel.lootPanel.scrollChild;
    frame.scrollFrame = wishlist3Panel.lootPanel.scrollFrame;

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
