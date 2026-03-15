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

    local wishlistTab = self:CreateTabButton(frame, "|cff00ff00PERSONAL|r", 1);
    wishlistTab:SetPoint("TOPLEFT", subtitleText, "BOTTOMLEFT", -4, -4);
    wishlistTab:SetWidth(90);
    frame.wishlistTab = wishlistTab;

    local guildWishlistTab = self:CreateTabButton(frame, "|cff00ff00ROSTER|r", 2);
    guildWishlistTab:SetPoint("LEFT", wishlistTab, "RIGHT", 4, 0);
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

    local allTabs = { wishlistTab, guildWishlistTab };
    local allContentFrames = { wishlistContainer, guildContainer };

    local function SetActiveTab(tabIndex)
        frame.activeTab = tabIndex;

        -- Hide all content frames, deactivate all tabs
        for _, cf in ipairs(allContentFrames) do cf:Hide() end
        for _, tab in ipairs(allTabs) do
            if tab:IsShown() then
                tab:SetBackdropColor(self.constants.TAB_INACTIVE_COLOR.r, self.constants.TAB_INACTIVE_COLOR.g, self.constants.TAB_INACTIVE_COLOR.b, self.constants.TAB_INACTIVE_COLOR.a);
                tab:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5);
            end
        end

        -- Activate selected tab
        local activeTab = allTabs[tabIndex];
        local activeContent = allContentFrames[tabIndex];
        activeContent:Show();
        activeTab:SetBackdropColor(self.constants.TAB_ACTIVE_COLOR.r, self.constants.TAB_ACTIVE_COLOR.g, self.constants.TAB_ACTIVE_COLOR.b, self.constants.TAB_ACTIVE_COLOR.a);
        activeTab:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
        tabIndicator:ClearAllPoints();
        tabIndicator:SetPoint("BOTTOMLEFT", activeTab, "BOTTOMLEFT", 1, 0);
        tabIndicator:SetPoint("BOTTOMRIGHT", activeTab, "BOTTOMRIGHT", -1, 0);

        if tabIndex == 1 then
            frame.titleText:SetText("|cff00ff00PERSONAL|r");
            if frame.wishlistSubtitle then
                frame.subtitleText:SetText(frame.wishlistSubtitle);
            end
            GoWWishlists:PopulatePersonalWishlistView(frame);
        elseif tabIndex == 2 then
            frame.titleText:SetText("|cff00ff00ROSTER|r");
            GoWWishlists:PopulateGuildWishlistView(frame);
        end
    end

    wishlistTab:SetScript("OnClick", function() SetActiveTab(1) end);
    guildWishlistTab:SetScript("OnClick", function() SetActiveTab(2) end);
    frame.SetActiveTab = SetActiveTab;

    -- ESC to close
    table.insert(UISpecialFrames, "GoWWishlistBrowserFrame");

    -- Start on wishlist tab
    SetActiveTab(1);

    frame:Hide();
    self.frames.browserFrame = frame;
    return frame;
end

function GoWWishlists:ShowWishlistBrowserFrame()
    local frame = self:CreateWishlistBrowserFrame();

    -- Show roster tab if guild data exists
    if self:HasGuildWishlistData() then
        frame.guildWishlistTab:Show();
    else
        frame.guildWishlistTab:Hide();
    end

    -- Always open on personal tab
    frame.SetActiveTab(1);
    frame:Show();
end

-- Single core "Wishlists" tab with embedded PERSONAL / ROSTER sub-tabs
function GoWWishlists:CreateCoreWishlistsFrame(parent)
    if self.frames.coreWishlists then
        self.frames.coreWishlists:SetParent(parent);
        self.frames.coreWishlists:SetAllPoints(parent);
        return self.frames.coreWishlists;
    end

    local container = CreateFrame("Frame", "GoWCoreWishlistsContainer", parent);
    container:SetAllPoints(parent);

    local personalTab = self:CreateTabButton(container, "|cff00ff00PERSONAL|r", 1);
    personalTab:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -4);
    personalTab:SetWidth(90);

    local rosterTab = self:CreateTabButton(container, "|cff00ff00ROSTER|r", 2);
    rosterTab:SetPoint("LEFT", personalTab, "RIGHT", 4, 0);
    rosterTab:SetWidth(90);
    rosterTab:Hide();

    local tabIndicator = container:CreateTexture(nil, "ARTWORK", nil, 2);
    tabIndicator:SetTexture("Interface\\Buttons\\WHITE8x8");
    tabIndicator:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.9);
    tabIndicator:SetHeight(2);

    -- Personal content
    local personalContainer = CreateFrame("Frame", nil, container);
    personalContainer:SetPoint("TOPLEFT", personalTab, "BOTTOMLEFT", -4, -6);
    personalContainer:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0);

    local personalPanel = self:Create3PanelLayout(personalContainer);
    container.wishlist3Panel = personalPanel;
    container.scrollChild = personalPanel.lootPanel.scrollChild;
    container.scrollFrame = personalPanel.lootPanel.scrollFrame;

    -- Guild content
    local guildContent = CreateFrame("Frame", nil, container);
    guildContent:SetPoint("TOPLEFT", personalTab, "BOTTOMLEFT", -4, -6);
    guildContent:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0);

    local guildPanel = self:Create3PanelLayout(guildContent);
    container.guild3Panel = guildPanel;
    container.guildScrollChild = guildPanel.lootPanel.scrollChild;
    container.guildScrollFrame = guildPanel.lootPanel.scrollFrame;
    container.guildDifficultyFilter = "All";

    container.activeTab = 1;
    local allTabs = { personalTab, rosterTab };
    local allContentFrames = { personalContainer, guildContent };

    container.rosterTab = rosterTab;

    local function SetActiveTab(tabIndex)
        container.activeTab = tabIndex;
        for _, cf in ipairs(allContentFrames) do cf:Hide() end
        for _, tab in ipairs(allTabs) do
            if tab:IsShown() then
                tab:SetBackdropColor(self.constants.TAB_INACTIVE_COLOR.r, self.constants.TAB_INACTIVE_COLOR.g, self.constants.TAB_INACTIVE_COLOR.b, self.constants.TAB_INACTIVE_COLOR.a);
                tab:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5);
            end
        end
        local activeTab = allTabs[tabIndex];
        local activeContent = allContentFrames[tabIndex];
        activeContent:Show();
        activeTab:SetBackdropColor(self.constants.TAB_ACTIVE_COLOR.r, self.constants.TAB_ACTIVE_COLOR.g, self.constants.TAB_ACTIVE_COLOR.b, self.constants.TAB_ACTIVE_COLOR.a);
        activeTab:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
        tabIndicator:ClearAllPoints();
        tabIndicator:SetPoint("BOTTOMLEFT", activeTab, "BOTTOMLEFT", 1, 0);
        tabIndicator:SetPoint("BOTTOMRIGHT", activeTab, "BOTTOMRIGHT", -1, 0);
    end

    container.SetActiveTab = SetActiveTab;
    personalTab:SetScript("OnClick", function() SetActiveTab(1) end);
    rosterTab:SetScript("OnClick", function() SetActiveTab(2) end);

    SetActiveTab(1);
    container:Hide();
    self.frames.coreWishlists = container;
    return container;
end

function GoWWishlists:ShowCoreWishlistsTab(parent, setStatusFn)
    local container = self:CreateCoreWishlistsFrame(parent);

    local subtitleProxy = { SetText = function(_, text) if setStatusFn then setStatusFn(text) end end };

    -- Show roster tab if guild data exists
    if self:HasGuildWishlistData() then
        container.rosterTab:Show();
    else
        container.rosterTab:Hide();
    end

    -- Populate personal view
    local personalFrame = {
        wishlist3Panel = container.wishlist3Panel,
        subtitleText = subtitleProxy,
        wishlistSubtitle = nil,
    };
    self:PopulatePersonalWishlistView(personalFrame);

    -- Populate guild view if data exists
    if self:HasGuildWishlistData() then
        local guildFrame = {
            guild3Panel = container.guild3Panel,
            guildDifficultyFilter = container.guildDifficultyFilter or "All",
            subtitleText = subtitleProxy,
        };
        self:PopulateGuildWishlistView(guildFrame);
    end

    container.SetActiveTab(container.activeTab or 1);
    container:Show();
end

function GoWWishlists:HideCoreFrames()
    if self.frames.coreWishlists then self.frames.coreWishlists:Hide() end
end
