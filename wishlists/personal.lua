local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local L = GOW.Layout;

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
    local detailSourceFilter = frame.detailSourceFilter;
    if detailSourceFilter == nil then detailSourceFilter = (GOW.DB and GOW.DB.profile and GOW.DB.profile.wishlistPersonalSourceFilter) or false end
    frame.detailSourceFilter = detailSourceFilter;

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
            unknownItems = {};
        end

        local subtitleStr = charName .. "-" .. charRealm .. "  |  " .. totalCount .. " items remaining";
        frame.subtitleText:SetText(subtitleStr);
        frame.wishlistSubtitle = subtitleStr;

        self:PopulateSourcePanel(sourcePanel, bossOrder, bossCounts, function(selectedBoss)
            currentBoss = selectedBoss;
            if GOW.DB and GOW.DB.profile then GOW.DB.profile.wishlistSelectedBoss = selectedBoss end
            populateLootPanel(currentBoss);
            if detailSourceFilter then
                populateDetailPanel();
            end
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
        if not lootPanel.expandedBosses then lootPanel.expandedBosses = {} end

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
            self:BuildSections(container, scrollChild, bossGroups, bossOrder, unknownItems, bossToRaid, bossToJournalId, lootPanel.expandedBosses);
        end

        self:RelayoutBrowserContent(container);

        if #container.sections == 0 then
            local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            if not self:HasPersonalWishlistEntry() then
                emptyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -28);
                emptyText:SetPoint("RIGHT", scrollChild, "RIGHT", -10, 0);
                emptyText:SetJustifyH("CENTER");
                emptyText:SetWordWrap(true);
                emptyText:SetText("|cff888888No synced wishlist data found for this character.|r\n\n|cff666666" .. self:GetSyncAppInstallHint() .. "|r");
                scrollChild:SetHeight(110);
            else
                emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -40);
                emptyText:SetText("|cff888888No loot drops for this selection.|r");
                scrollChild:SetHeight(80);
            end
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
            if passFilter and detailSourceFilter and currentBoss then
                if entry.sourceBossName ~= currentBoss then
                    passFilter = false;
                end
            end
            if passFilter and detailSlotFilter ~= "All" then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(entry.itemId);
                if equipLoc == "INVTYPE_ROBE" then equipLoc = "INVTYPE_CHEST" end
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

        local nameCache = {};
        for _, item in ipairs(sortedItems) do
            if not nameCache[item.itemId] then
                nameCache[item.itemId] = C_Item.GetItemInfo(item.itemId) or "";
            end
        end

        if detailSortMode == "name" then
            table.sort(sortedItems, function(a, b)
                return nameCache[a.itemId] < nameCache[b.itemId];
            end);
        elseif detailSortMode == "boss" then
            local bossIdx = {};
            for i, name in ipairs(bossOrder) do bossIdx[name] = i end
            table.sort(sortedItems, function(a, b)
                local ai = bossIdx[a.sourceBossName] or 999;
                local bi = bossIdx[b.sourceBossName] or 999;
                if ai ~= bi then return ai < bi end
                return nameCache[a.itemId] < nameCache[b.itemId];
            end);
        elseif detailSortMode == "slot" then
            table.sort(sortedItems, function(a, b)
                local _, _, _, aLoc = C_Item.GetItemInfoInstant(a.itemId);
                local _, _, _, bLoc = C_Item.GetItemInfoInstant(b.itemId);
                local aSlot = SLOT_LABELS[aLoc] or "zzz";
                local bSlot = SLOT_LABELS[bLoc] or "zzz";
                if aSlot ~= bSlot then return aSlot < bSlot end
                return nameCache[a.itemId] < nameCache[b.itemId];
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
            yOffset = yOffset + self:GetItemRowHeight();
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
                yOffset = yOffset + self:GetItemRowHeight();
            end
        end

        scrollChild:SetHeight(yOffset + 8);
    end

    if not detailPanel.sortBtn then
        local headerBar = detailPanel.headerBar;
        local SLOT_LABELS = self.constants.SLOT_LABELS;
        local SORT_LABELS = self.constants.SORT_LABELS;
        local updateSortLabel, updateSlotLabel;

        local sortBtn = self:CreatePopupFilterBtn(detailPanel, "Sort: Upgrade", 90, "sort",
            self.constants.SORT_OPTIONS,
            function() return detailSortMode end,
            function(key)
                detailSortMode = key;
                frame.detailSortMode = key;
                updateSortLabel();
                populateDetailPanel();
            end);
        sortBtn:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 4, -4);
        detailPanel.sortBtn = sortBtn;

        local slotBtn = self:CreatePopupFilterBtn(detailPanel, "Slot: All", 80, "slot",
            function()
                local seenSlots = {};
                for _, entry in ipairs(self.state.allItems) do
                    if not entry.isObtained then
                        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(entry.itemId);
                        if equipLoc == "INVTYPE_ROBE" then equipLoc = "INVTYPE_CHEST" end
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
                return slotOptions;
            end,
            function() return detailSlotFilter end,
            function(key)
                detailSlotFilter = key;
                frame.detailSlotFilter = key;
                updateSlotLabel();
                populateDetailPanel();
            end);
        slotBtn:SetPoint("LEFT", sortBtn, "RIGHT", 4, 0);
        detailPanel.slotBtn = slotBtn;

        updateSortLabel = function()
            sortBtn.btnText:SetText("Sort: " .. (SORT_LABELS[detailSortMode] or detailSortMode));
        end

        updateSlotLabel = function()
            slotBtn.btnText:SetText("Slot: " .. (SLOT_LABELS[detailSlotFilter] or detailSlotFilter));
        end

        detailPanel.updateSortLabel = updateSortLabel;
        detailPanel.updateSlotLabel = updateSlotLabel;

        local obtainedBtn = L:CreateSubFilterBtn(detailPanel, "", 18);
        obtainedBtn:SetSize(18, 14);
        obtainedBtn:SetPoint("LEFT", slotBtn, "RIGHT", 4, 0);
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

        local sourceFilterBtn = L:CreateSubFilterBtn(detailPanel, "Source", 48);
        sourceFilterBtn:SetHeight(14);
        sourceFilterBtn:SetPoint("LEFT", obtainedBtn, "RIGHT", 4, 0);
        detailPanel.sourceFilterBtn = sourceFilterBtn;

        sourceFilterBtn:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP");
            if detailSourceFilter then
                GameTooltip:AddLine("Show All Sources", 1, 1, 1);
            else
                GameTooltip:AddLine("Show Current Source Only", 1, 1, 1);
            end
            GameTooltip:Show();
        end);
        sourceFilterBtn:SetScript("OnLeave", function() GameTooltip:Hide() end);

        local function updateSourceFilterBtn()
            L:SetButtonActive(sourceFilterBtn, detailSourceFilter);
        end

        sourceFilterBtn:SetScript("OnClick", function()
            detailSourceFilter = not detailSourceFilter;
            frame.detailSourceFilter = detailSourceFilter;
            if GOW.DB and GOW.DB.profile then GOW.DB.profile.wishlistPersonalSourceFilter = detailSourceFilter end
            updateSourceFilterBtn();
            populateDetailPanel();
        end);

        detailPanel.updateSourceFilterBtn = updateSourceFilterBtn;

        detailPanel.scrollFrame:SetPoint("TOPLEFT", sortBtn, "BOTTOMLEFT", -4, -4);
    end

    detailPanel.updateSortLabel();
    detailPanel.updateSlotLabel();
    detailPanel.updateObtainedBtn();
    detailPanel.updateSourceFilterBtn();

    self:SetupDifficultyDropdown(sourcePanel, function(diff)
        frame.personalDifficultyFilter = diff;
        if GOW.DB and GOW.DB.profile then GOW.DB.profile.wishlistPersonalDifficulty = diff end
        rebuildPersonalView();
    end);

    sourcePanel.updateDiffLabel(filter);

    rebuildPersonalView();
end
