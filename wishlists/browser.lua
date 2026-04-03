local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local L = GOW.Layout;

function GoWWishlists:CreateCompactToggleButton(parent)
    local compactBtn = L:CreateActionButton(parent, {
        text = "Compact",
        width = 60,
        tooltip = "Toggle compact mode",
        tooltipSubtext = "Reduces row height and hides slot and subclass badges",
        onClick = function() self:ToggleCompactMode() end,
    });

    local function updateCompactBtn()
        L:SetButtonActive(compactBtn, self.state.compactMode);
        compactBtn.btnText:SetText(self.state.compactMode and "|cff00ff00Compact|r" or "Compact");
    end

    compactBtn.UpdateState = updateCompactBtn;
    updateCompactBtn();
    return compactBtn;
end

local function UpdateRosterTabVisibility(self, host)
    local rosterTab = host.rosterTab or host.guildWishlistTab;
    if not rosterTab then return end

    if self:HasGuildWishlistData() then
        rosterTab:Show();
    else
        rosterTab:Hide();
    end
end

local function GetSavedTabIndex(host)
    local savedTab = GOW.DB and GOW.DB.profile and GOW.DB.profile.wishlistActiveTab or 1;
    local rosterTab = host.rosterTab or host.guildWishlistTab;
    if savedTab == 2 and rosterTab and not rosterTab:IsShown() then
        savedTab = 1;
    end
    return savedTab;
end

local function InitializeWishlistTabHost(self, host, options)
    local personalTab = self:CreateTabButton(host, "|cff00ff00PERSONAL|r", 1);
    personalTab:SetPoint(
        options.personalTabPoint or "TOPLEFT",
        options.personalTabRelativeTo or host,
        options.personalTabRelativePoint or "TOPLEFT",
        options.personalTabOffsetX or 0,
        options.personalTabOffsetY or 0
    );
    personalTab:SetWidth(options.personalTabWidth or 90);

    local compactBtn = self:CreateCompactToggleButton(host);
    compactBtn:SetPoint(
        options.compactAnchorPoint or "TOP",
        personalTab,
        options.compactAnchorRelativePoint or "TOP",
        options.compactAnchorOffsetX or 0,
        options.compactAnchorOffsetY or 0
    );
    compactBtn:SetPoint(
        options.compactRightPoint or "RIGHT",
        options.compactRightRelativeTo or host,
        options.compactRightRelativePoint or "RIGHT",
        options.compactRightOffsetX or 0,
        options.compactRightOffsetY or 0
    );

    local rosterTab = self:CreateTabButton(host, "|cff00ff00ROSTER|r", 2);
    rosterTab:SetPoint("LEFT", personalTab, "RIGHT", 4, 0);
    rosterTab:SetWidth(options.rosterTabWidth or 90);
    rosterTab:Hide();

    local tabIndicator = host:CreateTexture(nil, "ARTWORK", nil, 2);
    tabIndicator:SetTexture("Interface\\Buttons\\WHITE8x8");
    tabIndicator:SetVertexColor(L.constants.GOW_ACCENT_COLOR.r, L.constants.GOW_ACCENT_COLOR.g, L.constants.GOW_ACCENT_COLOR.b, 0.9);
    tabIndicator:SetHeight(2);

    local personalContainer = CreateFrame("Frame", options.personalContainerName, host);
    personalContainer:SetPoint("TOPLEFT", personalTab, "BOTTOMLEFT", options.contentOffsetX or -4, options.contentOffsetY or -8);
    personalContainer:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", options.contentRight or 0, options.contentBottom or 0);

    local personalPanel = self:Create3PanelLayout(personalContainer);

    local guildContainer = CreateFrame("Frame", options.guildContainerName, host);
    guildContainer:SetPoint("TOPLEFT", personalTab, "BOTTOMLEFT", options.contentOffsetX or -4, options.contentOffsetY or -8);
    guildContainer:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", options.contentRight or 0, options.contentBottom or 0);

    local guildPanel = self:Create3PanelLayout(guildContainer);

    host.compactBtn = compactBtn;
    host.wishlistTab = personalTab;
    host.rosterTab = rosterTab;
    host.guildWishlistTab = rosterTab;
    host.tabIndicator = tabIndicator;
    host.wishlistContainer = personalContainer;
    host.guildContainer = guildContainer;
    host.wishlist3Panel = personalPanel;
    host.scrollChild = personalPanel.lootPanel.scrollChild;
    host.scrollFrame = personalPanel.lootPanel.scrollFrame;
    host.guild3Panel = guildPanel;
    host.guildScrollChild = guildPanel.lootPanel.scrollChild;
    host.guildScrollFrame = guildPanel.lootPanel.scrollFrame;
    host.guildDifficultyFilter = host.guildDifficultyFilter or "All";
    host.activeTab = 1;

    local allTabs = { personalTab, rosterTab };
    local allContentFrames = { personalContainer, guildContainer };

    local function SetActiveTab(tabIndex)
        if tabIndex == 2 and not rosterTab:IsShown() then
            tabIndex = 1;
        end
        if tabIndex ~= 1 and tabIndex ~= 2 then
            tabIndex = 1;
        end

        host.activeTab = tabIndex;
        if GOW.DB and GOW.DB.profile then
            GOW.DB.profile.wishlistActiveTab = tabIndex;
        end

        for _, contentFrame in ipairs(allContentFrames) do
            contentFrame:Hide();
        end

        for _, tab in ipairs(allTabs) do
            if tab:IsShown() then
                self:SetTabActive(tab, false);
            end
        end

        local activeTab = allTabs[tabIndex];
        local activeContent = allContentFrames[tabIndex];
        if not activeTab or not activeContent then
            return;
        end
        activeContent:Show();
        self:SetTabActive(activeTab, true);
        tabIndicator:ClearAllPoints();
        tabIndicator:SetPoint("BOTTOMLEFT", activeTab, "BOTTOMLEFT", 1, 0);
        tabIndicator:SetPoint("BOTTOMRIGHT", activeTab, "BOTTOMRIGHT", -1, 0);

        if options.onTabChanged then
            options.onTabChanged(host, tabIndex);
        end
    end

    host.SetActiveTab = SetActiveTab;
    personalTab:SetScript("OnClick", function() SetActiveTab(1) end);
    rosterTab:SetScript("OnClick", function() SetActiveTab(2) end);
    SetActiveTab(1);
end

local function RefreshStandaloneTab(frame, tabIndex)
    if tabIndex == 1 then
        frame.titleText:SetText("|cff00ff00PERSONAL|r");
        if frame.wishlistSubtitle then
            frame.subtitleText:SetText(frame.wishlistSubtitle);
        end
        GoWWishlists:PopulatePersonalWishlistView(frame);
    else
        frame.titleText:SetText("|cff00ff00ROSTER|r");
        GoWWishlists:PopulateGuildWishlistView(frame);
    end
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

    L:ApplyBackdrop(frame, L.constants.GOW_BG_COLOR.r, L.constants.GOW_BG_COLOR.g, L.constants.GOW_BG_COLOR.b, 0.95, L.constants.GOW_ACCENT_COLOR.r, L.constants.GOW_ACCENT_COLOR.g, L.constants.GOW_ACCENT_COLOR.b, 0.7);

    local topStripe = frame:CreateTexture(nil, "ARTWORK");
    topStripe:SetTexture("Interface\\Buttons\\WHITE8x8");
    topStripe:SetVertexColor(L.constants.GOW_ACCENT_COLOR.r, L.constants.GOW_ACCENT_COLOR.g, L.constants.GOW_ACCENT_COLOR.b, 0.9);
    topStripe:SetHeight(2);
    topStripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1);
    topStripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1);

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12);
    titleText:SetText("|cff00ff00PERSONAL|r");
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

    InitializeWishlistTabHost(self, frame, {
        personalTabRelativeTo = subtitleText,
        personalTabRelativePoint = "BOTTOMLEFT",
        personalTabOffsetX = -4,
        personalTabOffsetY = -4,
        compactRightRelativeTo = frame,
        compactRightOffsetX = -8,
        contentOffsetX = -4,
        contentOffsetY = -8,
        contentRight = -4,
        contentBottom = 20,
        personalContainerName = "GoWWishlistContainer",
        guildContainerName = "GoWGuildContainer",
        onTabChanged = RefreshStandaloneTab,
    });

    local reloadBtn = L:CreateActionButton(frame, {
        text = "Reload UI",
        width = 80,
        tooltip = "Reload the UI",
        tooltipSubtext = "Wishlist data is more than 20 minutes old",
        onClick = function() ReloadUI() end,
    });
    reloadBtn:SetPoint("RIGHT", frame.compactBtn, "LEFT", -4, 0);
    reloadBtn:SetPoint("TOP", frame.compactBtn, "TOP", 0, 0);
    reloadBtn:Hide();
    frame.reloadBtn = reloadBtn;

    table.insert(UISpecialFrames, "GoWWishlistBrowserFrame");

    frame:Hide();
    self.frames.browserFrame = frame;
    return frame;
end

function GoWWishlists:ShowWishlistBrowserFrame()
    local frame = self:CreateWishlistBrowserFrame();

    if frame.reloadBtn then
        if self:IsWishlistDataStale() then frame.reloadBtn:Show() else frame.reloadBtn:Hide() end
    end

    UpdateRosterTabVisibility(self, frame);
    frame.SetActiveTab(GetSavedTabIndex(frame));
    frame:Show();
end

function GoWWishlists:CreateCoreWishlistsFrame(parent)
    if self.frames.coreWishlists then
        self.frames.coreWishlists:SetParent(parent);
        self.frames.coreWishlists:SetAllPoints(parent);
        return self.frames.coreWishlists;
    end

    local container = CreateFrame("Frame", "GoWCoreWishlistsContainer", parent);
    container:SetAllPoints(parent);

    InitializeWishlistTabHost(self, container, {
        personalTabRelativeTo = container,
        personalTabRelativePoint = "TOPLEFT",
        personalTabOffsetX = 4,
        personalTabOffsetY = -4,
        compactRightRelativeTo = container,
        compactRightRelativePoint = "TOPRIGHT",
        compactRightOffsetX = -4,
        contentOffsetX = -4,
        contentOffsetY = -6,
        contentRight = 0,
        contentBottom = 0,
    });

    local reloadBtn = L:CreateActionButton(container, {
        text = "Reload UI",
        width = 80,
        tooltip = "Reload the UI",
        tooltipSubtext = "Wishlist data is more than 20 minutes old",
        onClick = function() ReloadUI() end,
    });
    reloadBtn:SetPoint("RIGHT", container.compactBtn, "LEFT", -4, 0);
    reloadBtn:SetPoint("TOP", container.compactBtn, "TOP", 0, 0);
    reloadBtn:Hide();
    container.reloadBtn = reloadBtn;

    container:Hide();
    self.frames.coreWishlists = container;
    return container;
end

function GoWWishlists:ShowCoreWishlistsTab(parent, setStatusFn)
    local container = self:CreateCoreWishlistsFrame(parent);

    if container.reloadBtn then
        if self:IsWishlistDataStale() then container.reloadBtn:Show() else container.reloadBtn:Hide() end
    end

    local subtitleProxy = { SetText = function(_, text) if setStatusFn then setStatusFn(text) end end };
    container.setStatusFn = setStatusFn;

    UpdateRosterTabVisibility(self, container);

    local personalFrame = {
        wishlist3Panel = container.wishlist3Panel,
        subtitleText = subtitleProxy,
        wishlistSubtitle = nil,
    };
    local guildFrame = {
        guild3Panel = container.guild3Panel,
        guildDifficultyFilter = container.guildDifficultyFilter or "All",
        subtitleText = subtitleProxy,
    };
    container.personalFrame = personalFrame;
    container.guildFrame = guildFrame;

    function container:RefreshContent()
        GoWWishlists:PopulatePersonalWishlistView(self.personalFrame);
        if GoWWishlists:HasGuildWishlistData() then
            self.guildFrame.guildDifficultyFilter = self.guildDifficultyFilter or "All";
            GoWWishlists:PopulateGuildWishlistView(self.guildFrame);
        end
    end

    container:RefreshContent();
    container.SetActiveTab(GetSavedTabIndex(container));
    container:Show();
end

function GoWWishlists:HideCoreFrames()
    if self.frames.coreWishlists then self.frames.coreWishlists:Hide() end
end
