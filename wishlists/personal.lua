local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;

function GoWWishlists:PopulatePersonalWishlistView(frame)
    local panel3 = frame.wishlist3Panel;
    if not panel3 then return end

    local sourcePanel = panel3.sourcePanel;
    local lootPanel = panel3.lootPanel;
    local detailPanel = panel3.detailPanel;

    local charName = self.state.currentCharInfo and self.state.currentCharInfo.name or UnitName("player");
    local charRealm = self.state.currentCharInfo and self.state.currentCharInfo.realmNormalized or GetNormalizedRealmName();
    local filter = frame.personalDifficultyFilter or (GOW.DB and GOW.DB.profile and GOW.DB.profile.wishlistPersonalDifficulty) or "All";
    frame.personalDifficultyFilter = filter;

    sourcePanel.headerText:SetText("SOURCE");
    lootPanel.headerText:SetText("LOOT DROPS");
    detailPanel.headerText:SetText("WISHLIST");

    local currentBoss = nil; -- nil = All Bosses

    local bossGroups, bossOrder, unknownItems, bossToRaid, bossToJournalId; 
    local populateLootPanel;
    local populateDetailPanel;

    local function rebuildPersonalView()
        filter = frame.personalDifficultyFilter or "All";
        bossGroups, bossOrder, unknownItems, bossToRaid, bossToJournalId = self:CollectWishlistForCharacter(filter);

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

        self:PopulateSourcePanel(sourcePanel, bossOrder, bossCounts, function(selectedBoss)
            currentBoss = selectedBoss;
            if GOW.DB and GOW.DB.profile then GOW.DB.profile.wishlistSelectedBoss = selectedBoss end
            populateLootPanel(currentBoss);
        end, bossToRaid, bossToJournalId);

        local savedBoss = GOW.DB and GOW.DB.profile and GOW.DB.profile.wishlistSelectedBoss or nil;
        if savedBoss and bossGroups[savedBoss] then
            currentBoss = savedBoss;
            if sourcePanel.bossRows then
                for i, entry in ipairs(sourcePanel.bossRows) do
                    if entry.bossName == savedBoss then
                        sourcePanel.selectBoss(i);
                        break;
                    end
                end
            end
        else
            currentBoss = nil;
            populateLootPanel(nil);
        end
        populateDetailPanel();
    end

    populateLootPanel = function(selectedBoss)
        local scrollChild = lootPanel.scrollChild;
        self:ClearChildren(scrollChild);
        scrollChild:SetWidth(lootPanel.scrollFrame:GetWidth());

        local container = { sections = {}, scrollChild = scrollChild };

        if selectedBoss then
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
            self:BuildSections(container, scrollChild, bossGroups, bossOrder, unknownItems, bossToRaid, bossToJournalId);
        end

        self:RelayoutBrowserContent(container);

        if #container.sections == 0 then
            local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -40);
            emptyText:SetText("|cff888888No loot drops for this selection.|r");
            scrollChild:SetHeight(80);
        end
    end


    local detailSortMode = frame.detailSortMode or "upgrade";
    local detailSlotFilter = frame.detailSlotFilter or "All";
    local detailHideObtained = frame.detailHideObtained;
    if detailHideObtained == nil then detailHideObtained = true end

    populateDetailPanel = function()
        local scrollChild = detailPanel.scrollChild;
        self:ClearChildren(scrollChild);
        scrollChild:SetWidth(detailPanel.scrollFrame:GetWidth());

        local currentFilter = frame.personalDifficultyFilter or "All";
        local sortedItems = {};
        local obtainedItems = {};
        for _, entry in ipairs(self.state.allItems) do
            local passFilter = (currentFilter == "All") or (entry.difficulty == currentFilter);
            if passFilter and detailSlotFilter ~= "All" then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(entry.itemId);
                if equipLoc ~= detailSlotFilter then
                    passFilter = false;
                end
            end
            if passFilter then
                if entry.isObtained then
                    if not detailHideObtained then
                        table.insert(obtainedItems, entry);
                    end
                else
                    table.insert(sortedItems, entry);
                end
            end
        end

        local SLOT_LABELS = self.constants.SLOT_LABELS;
        if detailSortMode == "name" then
            table.sort(sortedItems, function(a, b)
                local aName = C_Item.GetItemInfo(a.itemId) or "";
                local bName = C_Item.GetItemInfo(b.itemId) or "";
                return aName < bName;
            end);
        elseif detailSortMode == "boss" then
            local bossIdx = {};
            for i, name in ipairs(bossOrder) do bossIdx[name] = i end
            table.sort(sortedItems, function(a, b)
                local ai = bossIdx[a.sourceBossName] or 999;
                local bi = bossIdx[b.sourceBossName] or 999;
                if ai ~= bi then return ai < bi end
                local aName = C_Item.GetItemInfo(a.itemId) or "";
                local bName = C_Item.GetItemInfo(b.itemId) or "";
                return aName < bName;
            end);
        elseif detailSortMode == "slot" then
            table.sort(sortedItems, function(a, b)
                local _, _, _, aLoc = C_Item.GetItemInfoInstant(a.itemId);
                local _, _, _, bLoc = C_Item.GetItemInfoInstant(b.itemId);
                local aSlot = SLOT_LABELS[aLoc] or "zzz";
                local bSlot = SLOT_LABELS[bLoc] or "zzz";
                if aSlot ~= bSlot then return aSlot < bSlot end
                local aName = C_Item.GetItemInfo(a.itemId) or "";
                local bName = C_Item.GetItemInfo(b.itemId) or "";
                return aName < bName;
            end);
        else -- "upgrade"
            table.sort(sortedItems, function(a, b)
                local aGain = (a.gain and a.gain.percent) or 0;
                local bGain = (b.gain and b.gain.percent) or 0;
                return aGain > bGain;
            end);
        end

        local yOffset = 0;

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

        if #sortedItems == 0 and #obtainedItems == 0 then
            local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -30);
            emptyText:SetText("|cff888888No items.|r");
            yOffset = 80;
        end

        if #obtainedItems > 0 then
            local sep = scrollChild:CreateTexture(nil, "ARTWORK");
            sep:SetTexture("Interface\\Buttons\\WHITE8x8");
            sep:SetVertexColor(0.25, 0.25, 0.3, 0.3);
            sep:SetHeight(1);
            sep:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
            sep:SetPoint("RIGHT", scrollChild, "RIGHT", -10, 0);
            yOffset = yOffset + 8;

            local obtHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
            obtHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -yOffset);
            obtHeader:SetText("|cff888888Obtained (" .. #obtainedItems .. ")|r");
            yOffset = yOffset + 16;

            for _, entry in ipairs(obtainedItems) do
                local row = self:CreateItemRow(scrollChild);
                row.showSource = true;
                self:PopulateItemRow(row, entry);

                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                row:SetAlpha(0.5);
                row:Show();
                yOffset = yOffset + self.constants.BROWSER_ITEM_HEIGHT;
            end
        end

        scrollChild:SetHeight(yOffset + 8);
    end

    if not detailPanel.sortBtn then
        local headerBar = detailPanel.headerBar;
        local popupMenu = self:GetOrCreatePopupMenu();
        local showPopup = popupMenu.showPopup;
        local SLOT_LABELS = self.constants.SLOT_LABELS;

        local SORT_LABELS = {
            upgrade = "Upgrade",
            name = "Name",
            boss = "Boss Order",
            slot = "Slot",
        };

        local sortBtn = self:CreateSubFilterBtn(detailPanel, "Sort: Upgrade", 90);
        sortBtn:SetHeight(14);
        sortBtn:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 4, -4);
        detailPanel.sortBtn = sortBtn;

        local slotBtn = self:CreateSubFilterBtn(detailPanel, "Slot: All", 80);
        slotBtn:SetHeight(14);
        slotBtn:SetPoint("LEFT", sortBtn, "RIGHT", 4, 0);
        detailPanel.slotBtn = slotBtn;

        local function updateSortLabel()
            sortBtn.btnText:SetText("Sort: " .. (SORT_LABELS[detailSortMode] or detailSortMode));
        end

        local function updateSlotLabel()
            slotBtn.btnText:SetText("Slot: " .. (SLOT_LABELS[detailSlotFilter] or detailSlotFilter));
        end

        sortBtn:SetScript("OnClick", function()
            if popupMenu.popup:IsShown() and popupMenu.popup.owner == "sort" then
                popupMenu.clearPopup();
                return;
            end
            local sortOptions = {
                { key = "upgrade", label = "Upgrade" },
                { key = "name",    label = "Name" },
                { key = "boss",    label = "Boss Order" },
                { key = "slot",    label = "Slot" },
            };
            popupMenu.popup.owner = "sort";
            showPopup(sortBtn, sortOptions, detailSortMode, function(key)
                detailSortMode = key;
                frame.detailSortMode = key;
                updateSortLabel();
                populateDetailPanel();
            end);
        end);

        slotBtn:SetScript("OnClick", function()
            if popupMenu.popup:IsShown() and popupMenu.popup.owner == "slot" then
                popupMenu.clearPopup();
                return;
            end
            local seenSlots = {};
            for _, entry in ipairs(self.state.allItems) do
                if not entry.isObtained then
                    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(entry.itemId);
                    if equipLoc and equipLoc ~= "" then
                        seenSlots[equipLoc] = true;
                    end
                end
            end
            local slotOptions = { { key = "All", label = "All Slots" } };
            for _, slotKey in ipairs(self.constants.SLOT_ORDER) do
                if seenSlots[slotKey] then
                    table.insert(slotOptions, { key = slotKey, label = SLOT_LABELS[slotKey] or slotKey });
                end
            end
            popupMenu.popup.owner = "slot";
            showPopup(slotBtn, slotOptions, detailSlotFilter, function(key)
                detailSlotFilter = key;
                frame.detailSlotFilter = key;
                updateSlotLabel();
                populateDetailPanel();
            end);
        end);

        detailPanel.updateSortLabel = updateSortLabel;
        detailPanel.updateSlotLabel = updateSlotLabel;

        local obtainedBtn = CreateFrame("Button", nil, detailPanel, "BackdropTemplate");
        obtainedBtn:SetSize(18, 14);
        obtainedBtn:SetPoint("LEFT", slotBtn, "RIGHT", 4, 0);
        self:ApplyBackdrop(obtainedBtn, self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a, 0.3, 0.3, 0.3, 0.4);
        local eyeTex = obtainedBtn:CreateTexture(nil, "ARTWORK");
        eyeTex:SetSize(12, 12);
        eyeTex:SetPoint("CENTER", obtainedBtn, "CENTER", 0, 0);
        eyeTex:SetTexture("Interface\\Minimap\\Tracking\\None");
        obtainedBtn.eyeTex = eyeTex;
        detailPanel.obtainedBtn = obtainedBtn;

        obtainedBtn:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP");
            if detailHideObtained then
                GameTooltip:AddLine("Show Obtained Items", 1, 1, 1);
            else
                GameTooltip:AddLine("Hide Obtained Items", 1, 1, 1);
            end
            GameTooltip:Show();
        end);
        obtainedBtn:SetScript("OnLeave", function() GameTooltip:Hide() end);

        local function updateObtainedBtn()
            self:SetButtonActiveWithIcon(obtainedBtn, eyeTex, not detailHideObtained);
        end

        obtainedBtn:SetScript("OnClick", function()
            detailHideObtained = not detailHideObtained;
            frame.detailHideObtained = detailHideObtained;
            updateObtainedBtn();
            populateDetailPanel();
        end);

        detailPanel.updateObtainedBtn = updateObtainedBtn;

        detailPanel.scrollFrame:SetPoint("TOPLEFT", sortBtn, "BOTTOMLEFT", -4, -4);
    end

    detailPanel.updateSortLabel();
    detailPanel.updateSlotLabel();
    detailPanel.updateObtainedBtn();

    self:SetupDifficultyDropdown(sourcePanel, function(diff)
        frame.personalDifficultyFilter = diff;
        if GOW.DB and GOW.DB.profile then GOW.DB.profile.wishlistPersonalDifficulty = diff end
        rebuildPersonalView();
    end);

    sourcePanel.updateDiffLabel(filter);

    rebuildPersonalView();
end
