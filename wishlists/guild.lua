local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local ns = select(2, ...);

GoWWishlists.constants.GUILD_MEMBER_ROW_HEIGHT = 22;
GoWWishlists.constants.GUILD_FILTER_HEIGHT = 26;

local function GetAverageGainFromMembers(members)
    local sum, count = 0, 0;
    for _, member in ipairs(members or {}) do
        local gain = member.gain and member.gain.percent;
        if gain and gain > 0 then
            sum = sum + gain;
            count = count + 1;
        end
    end
    return count > 0 and (sum / count) or 0;
end

local function BuildBossOrderIndex(self, bossNames, bossToRaid, bossToJournalId)
    local orderedBosses = {};
    local hasRaidGroups = bossToRaid and next(bossToRaid);

    if hasRaidGroups then
        local raidOrder, raidBosses, ungrouped = self:GroupAndSortBosses(bossNames, bossToRaid, bossToJournalId);
        for _, raidName in ipairs(raidOrder) do
            for _, bossName in ipairs(raidBosses[raidName]) do
                table.insert(orderedBosses, bossName);
            end
        end
        for _, bossName in ipairs(ungrouped) do
            table.insert(orderedBosses, bossName);
        end
    else
        for _, bossName in ipairs(bossNames) do
            table.insert(orderedBosses, bossName);
        end
    end

    local bossIndex = {};
    for index, bossName in ipairs(orderedBosses) do
        bossIndex[bossName] = index;
    end
    return bossIndex;
end

local function NormalizeGuildLootSort(sortMode)
    if not sortMode or sortMode == "" or sortMode == "boss" then
        return "mostwanted";
    end
    return sortMode;
end

-- Returns an array of {id, name} for teams matching the current guild.
function GoWWishlists:GetGuildTeams()
    local teams = {};
    if not ns.TEAMS or not ns.TEAMS.teams then return teams end
    local guildData = self.state.guildWishlistData;
    if not guildData then return teams end

    local guildName = guildData.guild;
    local guildRealm = guildData.guildRealmNormalized and guildData.guildRealmNormalized:lower() or "";

    for _, team in ipairs(ns.TEAMS.teams) do
        local teamRealm = team.guildRealmNormalized and team.guildRealmNormalized:lower() or "";
        if team.guild == guildName and teamRealm == guildRealm then
            table.insert(teams, { id = team.id, name = team.name or team.title });
        end
    end
    return teams;
end

-- Builds a name-realmNormalized lookup set for a given team id.
function GoWWishlists:BuildRosterMemberSet(teamId)
    if not ns.TEAMS or not ns.TEAMS.teams then return nil end
    for _, team in ipairs(ns.TEAMS.teams) do
        if team.id == teamId then
            local memberSet = {};
            for _, member in ipairs(team.members or {}) do
                local key = member.name .. "-" .. (member.realmNormalized or "");
                memberSet[key] = true;
            end
            return memberSet;
        end
    end
    return nil;
end

-- Collects guild wishlist data grouped by boss, then by item, then by member.
-- Returns: bossGroups = { bossName = { items = {key = itemData}, itemOrder = {keys} } }, bossOrder = {bossNames}
function GoWWishlists:CollectGuildWishlistByBoss(difficultyFilter, rosterMemberSet)
    if not self.state.guildWishlistData or not self.state.guildWishlistData.wishlists then return {}, {}, {}, {} end

    local bossGroups = {};
    local bossOrder = {};
    local bossToRaid = {};
    local bossToJournalId = {};

    for _, charEntry in ipairs(self.state.guildWishlistData.wishlists) do
        local passRoster = true;
        if rosterMemberSet then
            local charKey = charEntry.name .. "-" .. (charEntry.realmNameNormalized or "");
            passRoster = rosterMemberSet[charKey] == true;
        end

        if passRoster then
            for _, item in ipairs(charEntry.wishlist) do
                if not item.isObtained then
                    local passFilter = (difficultyFilter == "All") or (item.difficulty == difficultyFilter);
                    if passFilter then
                        local bossName = item.sourceBossName or "Unknown Boss";
                        if not bossGroups[bossName] then
                            bossGroups[bossName] = { items = {}, itemOrder = {} };
                            table.insert(bossOrder, bossName);
                            if item.sourceJournalId then
                                bossToRaid[bossName] = self:GetRaidNameForEncounter(item.sourceJournalId);
                                bossToJournalId[bossName] = item.sourceJournalId;
                            end
                        end

                        local boss = bossGroups[bossName];
                        local itemKey = item.itemId .. "-" .. (item.difficulty or "");
                        if not boss.items[itemKey] then
                            boss.items[itemKey] = {
                                itemId = item.itemId,
                                difficulty = item.difficulty,
                                isTierSetPiece = item.isTierSetPiece,
                                isCatalystItem = item.isCatalystItem,
                                catalystItemId = item.catalystItemId,
                                members = {},
                            };
                            table.insert(boss.itemOrder, itemKey);
                        else
                            if item.isCatalystItem then
                                boss.items[itemKey].isCatalystItem = true;
                                boss.items[itemKey].catalystItemId = boss.items[itemKey].catalystItemId or item.catalystItemId;
                            end
                        end

                        table.insert(boss.items[itemKey].members, {
                            characterName = charEntry.name,
                            realmName = charEntry.realmName,
                            classId = charEntry.classId,
                            tag = item.tag,
                            notes = item.notes,
                            officerNotes = item.officerNotes,
                            gain = item.gain,
                            report = item.report,
                            isCatalystItem = item.isCatalystItem,
                        });
                    end
                end
            end
        end
    end

    return bossGroups, bossOrder, bossToRaid, bossToJournalId;
end

function GoWWishlists:CreateGuildItemRow(parent)
    local isCompact = self.state.compactMode;
    local rowHeight = self:GetGuildItemRowHeight();
    local row = CreateFrame("Frame", nil, parent);
    row:SetHeight(rowHeight);

    row.badgeCol = self:CreateBadgeColumn(row, {
        width = 30,
        difficultyOnly = true,
    });

    local iconSize = isCompact and 20 or 24;
    local iconBorder, icon = self:CreateRowIcon(row, iconSize, 34);
    row.iconBorder = iconBorder;
    row.icon = icon;

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("LEFT", iconBorder, "RIGHT", 6, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    row.nameText = nameText;

    local infoText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    infoText:SetPoint("LEFT", nameText, "RIGHT", 8, 0);
    infoText:SetJustifyH("LEFT");
    row.infoText = infoText;

    row.infoHover = self:CreateTextHoverTooltip(row, infoText, row);

    row.tierBadge = self:CreateTierBadge(row);
    row.tierBadge:SetPoint("RIGHT", row, "RIGHT", -6, 0);

    local gainBadge = self:CreateGainBadge(row);
    gainBadge:SetPoint("RIGHT", row, "RIGHT", -6, 0);
    row.gainBadge = gainBadge;

    row.highlight = self:CreateRowHighlight(row);
    self:CreateItemTooltipZone(row, iconBorder);

    return row;
end

function GoWWishlists:PopulateGuildItemRow(row, itemData)
    row.itemId = itemData.itemId;

    local displayId = itemData.itemId;
    local itemName = self:SetItemIconAndName(row, itemData.itemId, nil, nil);

    if row.badgeCol then
        self:ApplyBadgeColumnState(row.badgeCol, itemData.difficulty, nil);
    end

    local parts = {};
    local memberCount = #itemData.members;
    table.insert(parts, "|cff888888" .. memberCount .. (memberCount == 1 and " wants" or " want") .. "|r");
    row.infoText:SetText(table.concat(parts, "  "));

    row.infoHover.tipText = itemData.difficulty and ("Difficulty: " .. itemData.difficulty) or nil;

    local totalPercent, gainCount, avgMetric = 0, 0, nil;
    for _, m in ipairs(itemData.members) do
        if m.gain and m.gain.percent and m.gain.percent > 0 then
            totalPercent = totalPercent + m.gain.percent;
            gainCount = gainCount + 1;
            if not avgMetric and m.gain.metric and m.gain.metric ~= "" then
                avgMetric = m.gain.metric;
            end
        end
    end
    if gainCount > 0 then
        self:UpdateGainBadge(row.gainBadge, { percent = totalPercent / gainCount, metric = avgMetric or "DPS" }, "avg ");
    else
        row.gainBadge:Hide();
    end

    self:UpdateTierBadge(row.tierBadge, itemData.isTierSetPiece);

    row.gainBadge:ClearAllPoints();
    local rightAnchor = row;
    local rightOffset = -6;
    local anchorPoint = "RIGHT";
    if row.tierBadge:IsShown() then
        row.tierBadge:ClearAllPoints();
        row.tierBadge:SetPoint("RIGHT", rightAnchor, "RIGHT", rightOffset, 0);
        rightAnchor = row.tierBadge;
        anchorPoint = "LEFT";
        rightOffset = -4;
    end
    row.gainBadge:SetPoint("RIGHT", rightAnchor, anchorPoint, rightOffset, 0);

    if not itemName then
        self:RegisterPendingItem(displayId, function()
            if row:GetParent() then
                self:PopulateGuildItemRow(row, itemData);
            end
        end);
    end
end

function GoWWishlists:CreateGuildMemberRow(parent)
    local row = CreateFrame("Button", nil, parent);
    row:SetHeight(self.constants.GUILD_MEMBER_ROW_HEIGHT);

    local classBar = row:CreateTexture(nil, "ARTWORK");
    classBar:SetTexture("Interface\\Buttons\\WHITE8x8");
    classBar:SetSize(2, 14);
    classBar:SetPoint("LEFT", row, "LEFT", 42, 0);
    classBar:SetVertexColor(0.5, 0.5, 0.5, 0.3);
    row.classBar = classBar;

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    nameText:SetPoint("LEFT", classBar, "RIGHT", 6, 0);
    nameText:SetJustifyH("LEFT");
    row.nameText = nameText;

    local tagText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    tagText:SetPoint("LEFT", nameText, "RIGHT", 8, 0);
    tagText:SetJustifyH("LEFT");
    row.tagText = tagText;

    row.tagHover = self:CreateTextHoverTooltip(row, tagText, row, "Priority", 0, 1, 0);

    local gainBadge = self:CreateGainBadge(row);
    gainBadge:SetPoint("LEFT", tagText, "RIGHT", 8, 0);
    row.gainBadge = gainBadge;

    row.officerNoteIcon = self:CreateNoteIconButton(row, row, "Interface\\Buttons\\UI-GuildButton-OfficerNote-Up", "Officer Note", 1, 0.5, 0);
    row.officerNoteIcon:SetPoint("RIGHT", row, "RIGHT", -8, 0);

    row.noteIcon = self:CreateNoteIconButton(row, row, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "Note", 0, 1, 0);
    row.noteIcon:SetPoint("RIGHT", row.officerNoteIcon, "LEFT", -4, 0);

    row.catalystBadge = self:CreateCatalystBadge(row);
    row.catalystBadge:SetPoint("RIGHT", row.noteIcon, "LEFT", -4, 0);

    row.highlight = self:CreateRowHighlight(row, 0.03);

    row:EnableMouse(true);
    row:SetScript("OnEnter", function(self) self.highlight:Show() end);
    row:SetScript("OnLeave", function(self) self.highlight:Hide() end);

    return row;
end

function GoWWishlists:PopulateGuildMemberRow(row, member, guildRealm)
    local classColor = self:GetClassColor(member.classId);
    local colorHex = self:ClassColorToHex(classColor);
    local displayName = member.characterName;
    if guildRealm and member.realmName and member.realmName ~= guildRealm then
        displayName = displayName .. "-" .. member.realmName;
    end
    row.nameText:SetText("|cff" .. colorHex .. displayName .. "|r");

    if classColor then
        row.classBar:SetVertexColor(classColor.r, classColor.g, classColor.b, 0.8);
    else
        row.classBar:SetVertexColor(0.5, 0.5, 0.5, 0.3);
    end

    local tagLabel = self:FormatTag(member.tag);
    row.tagText:SetText(tagLabel or "");

    row.tagHover.tipText = nil;
    if member.tag then
        local tagInfo = self.constants.TAG_DISPLAY[member.tag];
        if tagInfo then
            row.tagHover.tipText = tagInfo.tip;
        end
    end

    self:UpdateGainBadge(row.gainBadge, member.gain, nil, member.report, member.isCatalystItem);
    self:UpdateCatalystBadge(row.catalystBadge, member.isCatalystItem);

    self:UpdateNoteIcon(row.noteIcon, member.notes);
    self:UpdateNoteIcon(row.officerNoteIcon, self:HasGuildWishlistData() and member.officerNotes or nil);
end

function GoWWishlists:RelayoutGuildContent(frame)
    local scrollChild = frame.guildScrollChild;
    local yOffset = 0;

    for _, section in ipairs(frame.guildSections or {}) do
        if section.raidLabel then
            section.raidLabel:ClearAllPoints();
            section.raidLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -(yOffset + 2));
            section.raidLabel:SetPoint("RIGHT", scrollChild, "RIGHT", -8, 0);
            section.raidLabel:Show();
            yOffset = yOffset + self.constants.RAID_HEADER_HEIGHT;
        elseif section.obtainedSeparator then
            section.obtainedSeparator:ClearAllPoints();
            section.obtainedSeparator:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
            section.obtainedSeparator:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
            section.obtainedSeparator:Show();
            yOffset = yOffset + 24;
        elseif section.obtainedRows then
            for _, row in ipairs(section.obtainedRows) do
                row:ClearAllPoints();
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                row:Show();
                yOffset = yOffset + self.constants.LOOT_ROW_HEIGHT;
            end
        elseif section.header then
            local header = section.header;
            header:ClearAllPoints();
            header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
            header:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
            header:Show();
            yOffset = yOffset + self.constants.BROWSER_BOSS_HEADER_HEIGHT;

            if not header.isCollapsed then
                for _, itemGroup in ipairs(section.items or {}) do
                    local itemRow = itemGroup.row;
                    itemRow:ClearAllPoints();
                    itemRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                    itemRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                    itemRow:Show();
                    yOffset = yOffset + self:GetGuildItemRowHeight();

                    for _, memberRow in ipairs(itemGroup.memberRows or {}) do
                        memberRow:ClearAllPoints();
                        memberRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                        memberRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                        memberRow:Show();
                        yOffset = yOffset + self.constants.GUILD_MEMBER_ROW_HEIGHT;
                    end
                end
            else
                for _, itemGroup in ipairs(section.items or {}) do
                    itemGroup.row:Hide();
                    for _, memberRow in ipairs(itemGroup.memberRows or {}) do
                        memberRow:Hide();
                    end
                end
            end

            yOffset = yOffset + 4;
        elseif section.items then
            for _, itemGroup in ipairs(section.items) do
                local itemRow = itemGroup.row;
                itemRow:ClearAllPoints();
                itemRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                itemRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                itemRow:Show();
                yOffset = yOffset + self:GetGuildItemRowHeight();

                for _, memberRow in ipairs(itemGroup.memberRows or {}) do
                    memberRow:ClearAllPoints();
                    memberRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
                    memberRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
                    memberRow:Show();
                    yOffset = yOffset + self.constants.GUILD_MEMBER_ROW_HEIGHT;
                end
            end
        end
    end

    scrollChild:SetHeight(yOffset + 8);
end

function GoWWishlists:PopulateGuildWishlistView(frame)
    local panel3 = frame.guild3Panel;
    if not panel3 then return end

    local sourcePanel = panel3.sourcePanel;
    local lootPanel = panel3.lootPanel;
    local detailPanel = panel3.detailPanel;

    if not self.state.guildWishlistData or not self.state.guildWishlistData.wishlists or #self.state.guildWishlistData.wishlists == 0 then
        local playerGuild = GetGuildInfo("player");
        local msg;
        if not playerGuild then
            msg = "You are not in a guild.";
        else
            msg = "No guild wishlist data found for " .. playerGuild .. ".";
        end
        local sc = lootPanel.scrollChild;
        self:ClearChildren(sc);
        local emptyText = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        emptyText:SetPoint("TOPLEFT", sc, "TOPLEFT", 10, -28);
        emptyText:SetPoint("RIGHT", sc, "RIGHT", -10, 0);
        emptyText:SetJustifyH("CENTER");
        emptyText:SetWordWrap(true);
        if playerGuild then
            emptyText:SetText("|cff888888" .. msg .. "|r\n\n|cff666666" .. self:GetSyncAppInstallHint() .. "|r");
            sc:SetHeight(110);
        else
            emptyText:SetText("|cff888888" .. msg .. "|r");
            sc:SetHeight(80);
        end
        frame.subtitleText:SetText(playerGuild or "No Guild");
        return;
    end

    local rebuildGuildView;

    local guildName = self.state.guildWishlistData.guild or "Guild";
    local guildRealm = self.state.guildWishlistData.guildRealm;
    local filter = frame.guildDifficultyFilter or (GOW.DB and GOW.DB.profile and GOW.DB.profile.wishlistGuildDifficulty) or "All";
    frame.guildDifficultyFilter = filter;

    local guildRosterFilter = frame.guildRosterFilter or (GOW.DB and GOW.DB.profile and GOW.DB.profile.guildRosterFilter) or "all";
    frame.guildRosterFilter = guildRosterFilter;

    if not panel3.guildRosterBar then
        local rosterParent = panel3:GetParent();
        local rosterBar = CreateFrame("Frame", nil, rosterParent, "BackdropTemplate");
        rosterBar:SetHeight(22);
        rosterBar:SetPoint("TOPLEFT", rosterParent, "TOPLEFT", 0, 0);
        rosterBar:SetPoint("TOPRIGHT", rosterParent, "TOPRIGHT", 0, 0);
        self:ApplyBackdrop(rosterBar, 0.06, 0.06, 0.08, 0.9, 0.2, 0.2, 0.2, 0.4);
        panel3.guildRosterBar = rosterBar;

        local rosterLabel = rosterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        rosterLabel:SetPoint("LEFT", rosterBar, "LEFT", 6, 0);
        rosterLabel:SetText("|cff888888Roster:|r");
        rosterBar.rosterLabel = rosterLabel;

        local rosterBtn = self:CreateSubFilterBtn(rosterBar, "All Members", 120);
        rosterBtn:SetHeight(14);
        rosterBtn:SetPoint("LEFT", rosterLabel, "RIGHT", 4, 0);
        rosterBar.rosterBtn = rosterBtn;

        local popupMenu = self:GetOrCreatePopupMenu();
        local showPopup = popupMenu.showPopup;

        local function updateRosterLabel()
            local label = "All Members";
            if guildRosterFilter ~= "all" then
                local teams = self:GetGuildTeams();
                for _, t in ipairs(teams) do
                    if t.id == guildRosterFilter then
                        label = t.name;
                        break;
                    end
                end
            end
            rosterBtn.btnText:SetText(label);
            local textWidth = rosterBtn.btnText:GetStringWidth();
            rosterBtn:SetWidth(math.max(textWidth + 16, 80));
            self:SetButtonActive(rosterBtn, guildRosterFilter ~= "all");
        end

        rosterBtn:SetScript("OnClick", function()
            if popupMenu.popup:IsShown() and popupMenu.popup.owner == "guildroster" then
                popupMenu.clearPopup();
                return;
            end
            local options = { { key = "all", label = "All Members" } };
            local teams = self:GetGuildTeams();
            for _, t in ipairs(teams) do
                table.insert(options, { key = t.id, label = t.name });
            end
            popupMenu.popup.owner = "guildroster";
            showPopup(rosterBtn, options, guildRosterFilter, function(key)
                guildRosterFilter = key;
                frame.guildRosterFilter = key;
                if GOW.DB and GOW.DB.profile then
                    GOW.DB.profile.guildRosterFilter = key;
                end
                updateRosterLabel();
                rebuildGuildView();
            end);
        end);

        rosterBar.updateRosterLabel = updateRosterLabel;

        panel3:ClearAllPoints();
        panel3:SetPoint("TOPLEFT", rosterBar, "BOTTOMLEFT", 0, -2);
        panel3:SetPoint("BOTTOMRIGHT", rosterParent, "BOTTOMRIGHT", 0, 0);
    end

    -- Validate saved roster filter (team may no longer exist)
    if guildRosterFilter ~= "all" then
        local validTeam = false;
        local teams = self:GetGuildTeams();
        for _, t in ipairs(teams) do
            if t.id == guildRosterFilter then
                validTeam = true;
                break;
            end
        end
        if not validTeam then
            guildRosterFilter = "all";
            frame.guildRosterFilter = "all";
            if GOW.DB and GOW.DB.profile then
                GOW.DB.profile.guildRosterFilter = "all";
            end
        end
    end

    panel3.guildRosterBar.updateRosterLabel();

    sourcePanel.headerText:SetText("SOURCE");
    lootPanel.headerText:SetText("LOOT");
    detailPanel.headerText:SetText("WISHLIST");
    lootPanel.ownerFrame = frame;

    local guildLootSortMode = NormalizeGuildLootSort(frame.guildLootSortMode);
    frame.guildLootSortMode = guildLootSortMode;
    local guildHideObtained = frame.guildHideObtained;
    if guildHideObtained == nil then guildHideObtained = true end

    if not lootPanel.guildSortBtn then
        local headerBar = lootPanel.headerBar;
        local updateGuildSortLabel;

        local GUILD_SORT_LABELS = {
            bosspriority = "Boss Priority",
            mostwanted = "Most Wanted",
            avggain = "Upgrade",
            name = "Name",
            slot = "Slot Name",
        };

        local sortBtn = self:CreatePopupFilterBtn(lootPanel, "Sort: Most Wanted", 130, "guildsort",
            function()
                local sortOptions = {
                    { key = "mostwanted", label = "Most Wanted" },
                    { key = "avggain",    label = "Upgrade" },
                    { key = "name",       label = "Name" },
                    { key = "slot",       label = "Slot Name" },
                };
                if lootPanel.allowBossPrioritySort then
                    table.insert(sortOptions, { key = "bosspriority", label = "Boss Priority" });
                end
                return sortOptions;
            end,
            function() return NormalizeGuildLootSort(frame.guildLootSortMode or guildLootSortMode) end,
            function(key)
                guildLootSortMode = key;
                frame.guildLootSortMode = key;
                updateGuildSortLabel();
                rebuildGuildView();
            end);
        sortBtn:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 4, -4);
        lootPanel.guildSortBtn = sortBtn;

        local obtainedBtn = CreateFrame("Button", nil, lootPanel, "BackdropTemplate");
        obtainedBtn:SetSize(18, 14);
        obtainedBtn:SetPoint("LEFT", sortBtn, "RIGHT", 4, 0);
        self:ApplyBackdrop(obtainedBtn, self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a, 0.3, 0.3, 0.3, 0.4);
        local eyeTex = obtainedBtn:CreateTexture(nil, "ARTWORK");
        eyeTex:SetSize(12, 12);
        eyeTex:SetPoint("CENTER", obtainedBtn, "CENTER", 0, 0);
        eyeTex:SetTexture("Interface\\Minimap\\Tracking\\None");
        obtainedBtn.eyeTex = eyeTex;
        lootPanel.guildObtainedBtn = obtainedBtn;

        obtainedBtn:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP");
            local hideObtained = frame.guildHideObtained;
            if hideObtained == nil then hideObtained = guildHideObtained end
            if hideObtained then
                GameTooltip:AddLine("Show Obtained Items", 1, 1, 1);
            else
                GameTooltip:AddLine("Hide Obtained Items", 1, 1, 1);
            end
            GameTooltip:Show();
        end);
        obtainedBtn:SetScript("OnLeave", function() GameTooltip:Hide() end);

        updateGuildSortLabel = function()
            local activeSort = NormalizeGuildLootSort(frame.guildLootSortMode or guildLootSortMode);
            sortBtn.btnText:SetText("Sort: " .. (GUILD_SORT_LABELS[activeSort] or activeSort));
        end

        local function updateGuildObtainedBtn()
            local hideObtained = frame.guildHideObtained;
            if hideObtained == nil then hideObtained = guildHideObtained end
            self:SetButtonActiveWithIcon(obtainedBtn, eyeTex, not hideObtained);
        end

        obtainedBtn:SetScript("OnClick", function()
            guildHideObtained = not guildHideObtained;
            frame.guildHideObtained = guildHideObtained;
            updateGuildObtainedBtn();
            rebuildGuildView();
        end);

        lootPanel.updateGuildSortLabel = updateGuildSortLabel;
        lootPanel.updateGuildObtainedBtn = updateGuildObtainedBtn;

        lootPanel.scrollFrame:SetPoint("TOPLEFT", sortBtn, "BOTTOMLEFT", -4, -4);
    end

    lootPanel.updateGuildSortLabel();
    lootPanel.updateGuildObtainedBtn();

    rebuildGuildView = function()
        filter = frame.guildDifficultyFilter or "All";
        guildLootSortMode = NormalizeGuildLootSort(frame.guildLootSortMode);
        frame.guildLootSortMode = guildLootSortMode;
        guildHideObtained = frame.guildHideObtained;
        if guildHideObtained == nil then guildHideObtained = true end
        guildRosterFilter = frame.guildRosterFilter or "all";

        local rosterMemberSet = nil;
        if guildRosterFilter ~= "all" then
            rosterMemberSet = self:BuildRosterMemberSet(guildRosterFilter);
        end

        local bossGroups, bossOrder, bossToRaid, bossToJournalId = self:CollectGuildWishlistByBoss(filter, rosterMemberSet);

        local bossCounts = {};
        local totalItems = 0;
        local memberSet = {};
        for _, bossName in ipairs(bossOrder) do
            local boss = bossGroups[bossName];
            local count = #boss.itemOrder;
            bossCounts[bossName] = count;
            totalItems = totalItems + count;
            for _, itemKey in ipairs(boss.itemOrder) do
                for _, member in ipairs(boss.items[itemKey].members) do
                    memberSet[member.characterName] = true;
                end
            end
        end
        local memberCount = 0;
        for _ in pairs(memberSet) do memberCount = memberCount + 1 end
        local displayName = guildName;
        if guildRosterFilter ~= "all" then
            local teams = self:GetGuildTeams();
            for _, t in ipairs(teams) do
                if t.id == guildRosterFilter then
                    displayName = t.name;
                    break;
                end
            end
        end
        frame.subtitleText:SetText(displayName .. "  |  " .. memberCount .. " members  |  " .. totalItems .. " items");

        self:PopulateSourcePanel(sourcePanel, bossOrder, bossCounts, function(selectedBoss)
            self:PopulateGuildLootPanel(lootPanel, bossGroups, bossOrder, selectedBoss, guildRealm, detailPanel, bossToRaid, bossToJournalId, guildLootSortMode, guildHideObtained, rosterMemberSet);
        end, bossToRaid, bossToJournalId);

        self:PopulateGuildLootPanel(lootPanel, bossGroups, bossOrder, nil, guildRealm, detailPanel, bossToRaid, bossToJournalId, guildLootSortMode, guildHideObtained, rosterMemberSet);

        if detailPanel._activeMember then
            self:PopulateGuildPlayerDetail(detailPanel, detailPanel._activeMember, detailPanel._activeGuildRealm);
        else
            self:PopulateGuildDetailDefault(detailPanel, displayName, memberCount, totalItems, rosterMemberSet);
        end
    end

    self:SetupDifficultyDropdown(sourcePanel, function(diff)
        frame.guildDifficultyFilter = diff;
        if GOW.DB and GOW.DB.profile then GOW.DB.profile.wishlistGuildDifficulty = diff end
        rebuildGuildView();
    end);

    sourcePanel.updateDiffLabel(filter);

    rebuildGuildView();
end

function GoWWishlists:PopulateGuildLootPanel(lootPanel, bossGroups, bossOrder, selectedBoss, guildRealm, detailPanel, bossToRaid, bossToJournalId, sortMode, hideObtained, rosterMemberSet)
    local scrollChild = lootPanel.scrollChild;
    self:ClearChildren(scrollChild);
    scrollChild:SetWidth(lootPanel.scrollFrame:GetWidth());
    if not lootPanel.expandedBosses then lootPanel.expandedBosses = {} end

    sortMode = NormalizeGuildLootSort(sortMode);
    if hideObtained == nil then hideObtained = true end
    lootPanel.allowBossPrioritySort = selectedBoss == nil;

    if selectedBoss and sortMode == "bosspriority" then
        sortMode = "mostwanted";
        if lootPanel.ownerFrame then
            lootPanel.ownerFrame.guildLootSortMode = sortMode;
        end
    end
    if lootPanel.updateGuildSortLabel then
        lootPanel.updateGuildSortLabel();
    end

    local container = { guildSections = {}, guildScrollChild = scrollChild };
    local SLOT_LABELS = self.constants.SLOT_LABELS;

    local function sortItemDataList(itemList, sortKey)
        if sortKey == "mostwanted" then
            table.sort(itemList, function(a, b)
                local aCount = #a.members;
                local bCount = #b.members;
                if aCount ~= bCount then return aCount > bCount end
                local aName = C_Item.GetItemInfo(a.itemId) or "";
                local bName = C_Item.GetItemInfo(b.itemId) or "";
                return aName < bName;
            end);
        elseif sortKey == "avggain" then
            table.sort(itemList, function(a, b)
                local aAvg = GetAverageGainFromMembers(a.members);
                local bAvg = GetAverageGainFromMembers(b.members);
                if aAvg ~= bAvg then return aAvg > bAvg end
                local aName = C_Item.GetItemInfo(a.itemId) or "";
                local bName = C_Item.GetItemInfo(b.itemId) or "";
                return aName < bName;
            end);
        elseif sortKey == "name" then
            table.sort(itemList, function(a, b)
                local aName = C_Item.GetItemInfo(a.itemId) or "";
                local bName = C_Item.GetItemInfo(b.itemId) or "";
                return aName < bName;
            end);
        elseif sortKey == "slot" then
            table.sort(itemList, function(a, b)
                local _, _, _, aLoc = C_Item.GetItemInfoInstant(a.itemId);
                local _, _, _, bLoc = C_Item.GetItemInfoInstant(b.itemId);
                local aSlot = SLOT_LABELS[aLoc] or "zzz";
                local bSlot = SLOT_LABELS[bLoc] or "zzz";
                if aSlot ~= bSlot then return aSlot < bSlot end
                local aName = C_Item.GetItemInfo(a.itemId) or "";
                local bName = C_Item.GetItemInfo(b.itemId) or "";
                return aName < bName;
            end);
        end
        return itemList;
    end

    local function buildItemWithMembers(itemData)
        table.sort(itemData.members, function(a, b)
            local aGain = (a.gain and a.gain.percent) or 0;
            local bGain = (b.gain and b.gain.percent) or 0;
            return aGain > bGain;
        end);

        local itemRow = self:CreateGuildItemRow(scrollChild);
        self:PopulateGuildItemRow(itemRow, itemData);

        local memberRows = {};
        for _, member in ipairs(itemData.members) do
            local memberRow = self:CreateGuildMemberRow(scrollChild);
            self:PopulateGuildMemberRow(memberRow, member, guildRealm);
            memberRow:SetScript("OnClick", function()
                GoWWishlists:PopulateGuildPlayerDetail(detailPanel, member, guildRealm);
            end);
            memberRow:EnableMouse(true);
            table.insert(memberRows, memberRow);
        end

        return { row = itemRow, memberRows = memberRows };
    end

    local function buildBossSection(bossName, itemSortKey)
        local boss = bossGroups[bossName];
        if not boss then return end

        local header = self:CreateBossHeader(scrollChild, bossName, #boss.itemOrder);
        local expandedBosses = lootPanel.expandedBosses or {};
        header.isCollapsed = not expandedBosses[bossName];
        self:UpdateBossHeaderArrow(header);

        local bossItems = {};
        for _, itemKey in ipairs(boss.itemOrder) do
            table.insert(bossItems, boss.items[itemKey]);
        end
        if itemSortKey then
            sortItemDataList(bossItems, itemSortKey);
        end

        local items = {};
        for _, itemData in ipairs(bossItems) do
            table.insert(items, buildItemWithMembers(itemData));
        end

        header:SetScript("OnClick", function(h)
            h.isCollapsed = not h.isCollapsed;
            if not lootPanel.expandedBosses then lootPanel.expandedBosses = {} end
            lootPanel.expandedBosses[bossName] = not h.isCollapsed or nil;
            GoWWishlists:UpdateBossHeaderArrow(h);
            GoWWishlists:RelayoutGuildContent(container);
        end);

        table.insert(container.guildSections, { header = header, items = items });
    end

    local function addRaidLabel(raidName)
        local label = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        label:SetJustifyH("LEFT");
        label:SetWordWrap(false);
        label:SetText("|cff666666" .. raidName .. "|r");
        table.insert(container.guildSections, { raidLabel = label });
    end

    local bossOrderIndex = BuildBossOrderIndex(self, bossOrder, bossToRaid, bossToJournalId);

    local function buildFlatList(sortKey, onlyBossName)
        local flatItems = {};
        if onlyBossName then
            local boss = bossGroups[onlyBossName];
            if boss then
                for _, itemKey in ipairs(boss.itemOrder) do
                    table.insert(flatItems, boss.items[itemKey]);
                end
            end
        else
            for _, bossName in ipairs(bossOrder) do
                local boss = bossGroups[bossName];
                if boss then
                    for _, itemKey in ipairs(boss.itemOrder) do
                        table.insert(flatItems, boss.items[itemKey]);
                    end
                end
            end
        end

        sortItemDataList(flatItems, sortKey);

        local items = {};
        for _, itemData in ipairs(flatItems) do
            table.insert(items, buildItemWithMembers(itemData));
        end
        table.insert(container.guildSections, { items = items });
    end

    local function buildBossPrioritySections()
        local prioritizedBosses = {};
        for _, bossName in ipairs(bossOrder) do
            local boss = bossGroups[bossName];
            if boss then
                local bossGainSum, bossGainCount = 0, 0;
                for _, itemKey in ipairs(boss.itemOrder) do
                    for _, member in ipairs(boss.items[itemKey].members) do
                        local gain = member.gain and member.gain.percent;
                        if gain and gain > 0 then
                            bossGainSum = bossGainSum + gain;
                            bossGainCount = bossGainCount + 1;
                        end
                    end
                end

                table.insert(prioritizedBosses, {
                    name = bossName,
                    avgGain = bossGainCount > 0 and (bossGainSum / bossGainCount) or 0,
                    order = bossOrderIndex[bossName] or math.huge,
                });
            end
        end

        table.sort(prioritizedBosses, function(a, b)
            if a.avgGain ~= b.avgGain then
                return a.avgGain > b.avgGain;
            end
            return a.order < b.order;
        end);

        for _, bossInfo in ipairs(prioritizedBosses) do
            buildBossSection(bossInfo.name);
        end
    end

    local function buildGroupedSections(itemSortKey)
        local hasRaidGroups = bossToRaid and next(bossToRaid);
        if hasRaidGroups then
            local raidOrder, raidBosses, ungrouped = self:GroupAndSortBosses(bossOrder, bossToRaid, bossToJournalId);

            for _, raidName in ipairs(raidOrder) do
                addRaidLabel(raidName);
                for _, bossName in ipairs(raidBosses[raidName]) do
                    buildBossSection(bossName, itemSortKey);
                end
            end

            if #ungrouped > 0 then
                addRaidLabel("Other");
                for _, bossName in ipairs(ungrouped) do
                    buildBossSection(bossName, itemSortKey);
                end
            end
        else
            for _, bossName in ipairs(bossOrder) do
                buildBossSection(bossName, itemSortKey);
            end
        end
    end

    if selectedBoss then
        buildFlatList(sortMode, selectedBoss);
    elseif sortMode == "bosspriority" then
        buildBossPrioritySections();
    else
        buildGroupedSections(sortMode);
    end

    if not hideObtained then
        local obtainedItems = self:CollectObtainedItems(nil, nil, rosterMemberSet);
        if #obtainedItems > 0 then
            local sepFrame = CreateFrame("Frame", nil, scrollChild);
            sepFrame:SetHeight(24);
            local sepLine = sepFrame:CreateTexture(nil, "ARTWORK");
            sepLine:SetTexture("Interface\\Buttons\\WHITE8x8");
            sepLine:SetVertexColor(0.25, 0.25, 0.3, 0.3);
            sepLine:SetHeight(1);
            sepLine:SetPoint("TOPLEFT", sepFrame, "TOPLEFT", 10, -4);
            sepLine:SetPoint("RIGHT", sepFrame, "RIGHT", -10, 0);
            local sepText = sepFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
            sepText:SetPoint("TOPLEFT", sepFrame, "TOPLEFT", 10, -10);
            sepText:SetText("|cff888888Obtained (" .. #obtainedItems .. ")|r");
            table.insert(container.guildSections, { obtainedSeparator = sepFrame });

            local obtRows = {};
            local maxRows = 50;
            for i, record in ipairs(obtainedItems) do
                if i > maxRows then break end
                local row = self:CreateLootHistoryRow(scrollChild, true);
                self:PopulateLootHistoryRow(row, record);
                row:SetAlpha(0.5);
                table.insert(obtRows, row);
            end
            table.insert(container.guildSections, { obtainedRows = obtRows });
        end
    end

    if #container.guildSections == 0 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -40);
        emptyText:SetText("|cff888888No items match the current filters.|r");
        scrollChild:SetHeight(80);
        return;
    end

    self:RelayoutGuildContent(container);
end

function GoWWishlists:CollectObtainedItems(characterName, realmName, rosterMemberSet)
    local results = {};
    local data = self.state.guildWishlistData;
    if not data or not data.wishlists then return results end

    for _, charEntry in ipairs(data.wishlists) do
        local passRoster = true;
        if rosterMemberSet then
            local charKey = charEntry.name .. "-" .. (charEntry.realmNameNormalized or "");
            passRoster = rosterMemberSet[charKey] == true;
        end

        if passRoster then
            local match = not characterName or (GOW.Helper:StripDiacritics(charEntry.name) == GOW.Helper:StripDiacritics(characterName) and charEntry.realmName == realmName);
            if match then
                for _, item in ipairs(charEntry.wishlist) do
                    if item.isObtained then
                        table.insert(results, {
                            itemId = item.itemId,
                            difficulty = item.difficulty,
                            encounterName = item.sourceBossName or "Unknown",
                            winner = charEntry.name,
                            winnerClass = charEntry.classId,
                            timestamp = item.obtainedOn and math.floor(item.obtainedOn / 1000) or nil,
                        });
                    end
                end
                if characterName then break end
            end
        end
    end

    table.sort(results, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0);
    end);

    return results;
end

function GoWWishlists:PopulateGuildDetailDefault(detailPanel, guildName, memberCount, totalItems, rosterMemberSet)
    local scrollChild = detailPanel.scrollChild;
    self:ClearChildren(scrollChild);
    scrollChild:SetWidth(detailPanel.scrollFrame:GetWidth());

    detailPanel.headerText:SetText("LOOT HISTORY");

    detailPanel._activeMember = nil;
    detailPanel._activeGuildRealm = nil;
    detailPanel._lastGuildName = guildName;
    detailPanel._lastMemberCount = memberCount;
    detailPanel._lastTotalItems = totalItems;
    detailPanel._lastRosterMemberSet = rosterMemberSet;

    local guildHistoryView = detailPanel.guildHistoryView or "date";

    local yOffset = 8;

    local guildText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    guildText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
    guildText:SetText("|cff00ff00" .. guildName .. "|r");
    yOffset = yOffset + 22;

    local statsText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    statsText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
    statsText:SetText("|cff888888" .. memberCount .. " members  |cff666666|||r  |cff888888" .. totalItems .. " items|r");
    yOffset = yOffset + 20;

    local dateBtn = self:CreateSubFilterBtn(scrollChild, "Date", 50);
    dateBtn:SetHeight(14);
    dateBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);

    local charBtn = self:CreateSubFilterBtn(scrollChild, "Character", 70);
    charBtn:SetHeight(14);
    charBtn:SetPoint("LEFT", dateBtn, "RIGHT", 4, 0);

    local function updateViewToggle()
        if guildHistoryView == "date" then
            self:SetButtonActive(dateBtn, true);
            self:SetButtonActive(charBtn, false);
        else
            self:SetButtonActive(charBtn, true);
            self:SetButtonActive(dateBtn, false);
        end
    end

    local function setView(view)
        guildHistoryView = view;
        detailPanel.guildHistoryView = view;
        self:PopulateGuildDetailDefault(detailPanel, guildName, memberCount, totalItems, rosterMemberSet);
    end

    dateBtn:SetScript("OnClick", function() setView("date") end);
    charBtn:SetScript("OnClick", function() setView("character") end);
    updateViewToggle();
    yOffset = yOffset + 20;

    local obtainedItems = self:CollectObtainedItems(nil, nil, rosterMemberSet);
    if #obtainedItems == 0 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        emptyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
        emptyText:SetPoint("RIGHT", scrollChild, "RIGHT", -10, 0);
        emptyText:SetWordWrap(true);
        emptyText:SetText("|cff666666\nItems will appear here as guild members obtain their wishlist drops.|r");
        yOffset = yOffset + 40;
        scrollChild:SetHeight(yOffset);
        return;
    end

    if guildHistoryView == "character" then
        local charMap = {};
        local charOrder = {};
        for _, record in ipairs(obtainedItems) do
            local name = record.winner;
            if not charMap[name] then
                charMap[name] = { count = 0, classId = nil, realmName = nil };
                table.insert(charOrder, name);
            end
            charMap[name].count = charMap[name].count + 1;
        end

        local guildData = self.state.guildWishlistData;
        if guildData and guildData.wishlists then
            for _, charEntry in ipairs(guildData.wishlists) do
                if charMap[charEntry.name] then
                    charMap[charEntry.name].classId = charEntry.classId;
                    charMap[charEntry.name].realmName = charEntry.realmName;
                end
            end
        end

        table.sort(charOrder, function(a, b) return charMap[a].count > charMap[b].count end);

        local sectionHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        sectionHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
        sectionHeader:SetText("|cff888888Characters (" .. #charOrder .. ")|r");
        yOffset = yOffset + 16;

        local guildRealm = guildData and guildData.guildRealm;

        for _, charName in ipairs(charOrder) do
            local info = charMap[charName];
            local classColor = self:GetClassColor(info.classId);
            local colorHex = self:ClassColorToHex(classColor);

            local charRow = CreateFrame("Button", nil, scrollChild, "BackdropTemplate");
            charRow:SetHeight(22);
            charRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
            charRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
            self:ApplyBackdrop(charRow, 0.1, 0.1, 0.13, 0.5, 0, 0, 0, 0);

            local nameText = charRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
            nameText:SetPoint("LEFT", charRow, "LEFT", 12, 0);
            nameText:SetText("|cff" .. colorHex .. charName .. "|r");

            local countText = charRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
            countText:SetPoint("RIGHT", charRow, "RIGHT", -12, 0);
            countText:SetText("|cff888888" .. info.count .. " items|r");

            local hl = self:CreateRowHighlight(charRow);
            charRow:SetScript("OnEnter", function() hl:Show() end);
            charRow:SetScript("OnLeave", function() hl:Hide() end);

            charRow:SetScript("OnClick", function()
                GoWWishlists:PopulateGuildPlayerDetail(detailPanel, {
                    characterName = charName,
                    realmName = info.realmName,
                    classId = info.classId,
                }, guildRealm);
            end);

            charRow:Show();
            yOffset = yOffset + 22;
        end
    else
        local sectionHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        sectionHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
        sectionHeader:SetText("|cff888888Obtained Items (" .. #obtainedItems .. ")|r");
        yOffset = yOffset + 16;

        local maxRows = 50;
        for i, record in ipairs(obtainedItems) do
            if i > maxRows then break end

            local row = self:CreateLootHistoryRow(scrollChild, true);
            self:PopulateLootHistoryRow(row, record);

            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
            row:Show();
            yOffset = yOffset + self.constants.LOOT_ROW_HEIGHT;
        end
    end

    scrollChild:SetHeight(yOffset + 8);
end

function GoWWishlists:PopulateGuildPlayerDetail(detailPanel, member, guildRealm)
    local scrollChild = detailPanel.scrollChild;
    self:ClearChildren(scrollChild);
    scrollChild:SetWidth(detailPanel.scrollFrame:GetWidth());

    local classColor = self:GetClassColor(member.classId);
    local colorHex = self:ClassColorToHex(classColor);

    local displayName = member.characterName;
    if guildRealm and member.realmName and member.realmName ~= guildRealm then
        displayName = displayName .. "-" .. member.realmName;
    end

    detailPanel.headerText:SetText("|cff" .. colorHex .. displayName .. "|r");

    detailPanel._activeMember = member;
    detailPanel._activeGuildRealm = guildRealm;

    local guildPlayerSortMode = detailPanel.guildPlayerSortMode or "upgrade";
    local guildPlayerSlotFilter = detailPanel.guildPlayerSlotFilter or "All";
    local SLOT_LABELS = self.constants.SLOT_LABELS;
    local SLOT_ORDER = self.constants.SLOT_ORDER;

    local yOffset = 4;

    local backBtn = CreateFrame("Button", nil, scrollChild, "BackdropTemplate");
    backBtn:SetSize(16, 16);
    backBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, -yOffset);
    local backText = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    backText:SetAllPoints();
    backText:SetText("|cff888888< Back|r");
    backBtn:SetWidth(40);
    backBtn:SetScript("OnClick", function()
        local name = detailPanel._lastGuildName or (GoWWishlists.state.guildWishlistData and GoWWishlists.state.guildWishlistData.guild or "Guild");
        local mc = detailPanel._lastMemberCount or 0;
        local ti = detailPanel._lastTotalItems or 0;
        local rms = detailPanel._lastRosterMemberSet;
        GoWWishlists:PopulateGuildDetailDefault(detailPanel, name, mc, ti, rms);
    end);
    backBtn:SetScript("OnEnter", function(self)
        backText:SetText("|cffffff00< Back|r");
    end);
    backBtn:SetScript("OnLeave", function(self)
        backText:SetText("|cff888888< Back|r");
    end);
    yOffset = yOffset + 22;

    local allMemberItems = {};
    local memberBossNames = {};
    local memberBossToRaid = {};
    local memberBossToJournalId = {};
    local seenBosses = {};
    if self.state.guildWishlistData and self.state.guildWishlistData.wishlists then
        for _, charEntry in ipairs(self.state.guildWishlistData.wishlists) do
            if GOW.Helper:StripDiacritics(charEntry.name) == GOW.Helper:StripDiacritics(member.characterName) and charEntry.realmName == member.realmName then
                for _, item in ipairs(charEntry.wishlist) do
                    if not item.isObtained then
                        table.insert(allMemberItems, item);

                        local bossName = item.sourceBossName or "Unknown Boss";
                        if not seenBosses[bossName] then
                            seenBosses[bossName] = true;
                            table.insert(memberBossNames, bossName);
                        end
                        if item.sourceJournalId then
                            memberBossToRaid[bossName] = self:GetRaidNameForEncounter(item.sourceJournalId);
                            memberBossToJournalId[bossName] = item.sourceJournalId;
                        end
                    end
                end
                break;
            end
        end
    end

    local memberBossOrderIndex = BuildBossOrderIndex(self, memberBossNames, memberBossToRaid, memberBossToJournalId);

    local memberItems = {};
    local seenSlots = {};
    for _, entry in ipairs(allMemberItems) do
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(entry.itemId);
        if equipLoc and equipLoc ~= "" then
            seenSlots[equipLoc] = true;
        end
        if guildPlayerSlotFilter == "All" or equipLoc == guildPlayerSlotFilter then
            table.insert(memberItems, entry);
        end
    end

    local SORT_LABELS = self.constants.SORT_LABELS;
    if guildPlayerSortMode == "name" then
        table.sort(memberItems, function(a, b)
            local aName = C_Item.GetItemInfo(a.itemId) or "";
            local bName = C_Item.GetItemInfo(b.itemId) or "";
            return aName < bName;
        end);
    elseif guildPlayerSortMode == "boss" then
        table.sort(memberItems, function(a, b)
            local aIndex = memberBossOrderIndex[a.sourceBossName or "Unknown Boss"] or math.huge;
            local bIndex = memberBossOrderIndex[b.sourceBossName or "Unknown Boss"] or math.huge;
            if aIndex ~= bIndex then return aIndex < bIndex end
            local aName = C_Item.GetItemInfo(a.itemId) or "";
            local bName = C_Item.GetItemInfo(b.itemId) or "";
            return aName < bName;
        end);
    elseif guildPlayerSortMode == "slot" then
        table.sort(memberItems, function(a, b)
            local _, _, _, aLoc = C_Item.GetItemInfoInstant(a.itemId);
            local _, _, _, bLoc = C_Item.GetItemInfoInstant(b.itemId);
            local aSlot = SLOT_LABELS[aLoc] or "zzz";
            local bSlot = SLOT_LABELS[bLoc] or "zzz";
            if aSlot ~= bSlot then return aSlot < bSlot end
            local aName = C_Item.GetItemInfo(a.itemId) or "";
            local bName = C_Item.GetItemInfo(b.itemId) or "";
            return aName < bName;
        end);
    else
        table.sort(memberItems, function(a, b)
            local aGain = (a.gain and a.gain.percent) or 0;
            local bGain = (b.gain and b.gain.percent) or 0;
            return aGain > bGain;
        end);
    end

    local function rebuild()
        self:PopulateGuildPlayerDetail(detailPanel, member, guildRealm);
    end

    local sortBtn = self:CreatePopupFilterBtn(scrollChild, "Sort: " .. (SORT_LABELS[guildPlayerSortMode] or guildPlayerSortMode), 110, "playerSort",
        self.constants.SORT_OPTIONS,
        function() return guildPlayerSortMode end,
        function(key)
            detailPanel.guildPlayerSortMode = key;
            rebuild();
        end);
    sortBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);

    local slotBtn = self:CreatePopupFilterBtn(scrollChild, "Slot: " .. (SLOT_LABELS[guildPlayerSlotFilter] or guildPlayerSlotFilter), 80, "playerSlot",
        function()
            local slotOptions = { { key = "All", label = "All Slots" } };
            for _, slotKey in ipairs(SLOT_ORDER) do
                if seenSlots[slotKey] then
                    table.insert(slotOptions, { key = slotKey, label = SLOT_LABELS[slotKey] or slotKey });
                end
            end
            return slotOptions;
        end,
        function() return guildPlayerSlotFilter end,
        function(key)
            detailPanel.guildPlayerSlotFilter = key;
            rebuild();
        end);
    slotBtn:SetPoint("LEFT", sortBtn, "RIGHT", 4, 0);

    yOffset = yOffset + 20;

    local countText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    countText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
    countText:SetText("|cff888888" .. #memberItems .. " wishlist items|r");
    yOffset = yOffset + 16;

    for _, entry in ipairs(memberItems) do
        local row = self:CreateItemRow(scrollChild);
        row.showSource = true;
        self:PopulateItemRow(row, entry);

        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
        row:Show();
        yOffset = yOffset + self:GetItemRowHeight();
    end

    if #memberItems == 0 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -(yOffset + 20));
        emptyText:SetText("|cff888888No wishlist items.|r");
        yOffset = yOffset + 60;
    end

    local memberObtained = self:CollectObtainedItems(member.characterName, member.realmName);
    if #memberObtained > 0 then
        local sep = scrollChild:CreateTexture(nil, "ARTWORK");
        sep:SetTexture("Interface\\Buttons\\WHITE8x8");
        sep:SetVertexColor(0.25, 0.25, 0.3, 0.3);
        sep:SetHeight(1);
        sep:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
        sep:SetPoint("RIGHT", scrollChild, "RIGHT", -10, 0);
        yOffset = yOffset + 8;

        local lootHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        lootHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset);
        lootHeader:SetText("|cff888888Obtained Items (" .. #memberObtained .. ")|r");
        yOffset = yOffset + 16;

        for i, record in ipairs(memberObtained) do
            if i > 20 then break end

            local row = self:CreateLootHistoryRow(scrollChild, false);
            self:PopulateLootHistoryRow(row, record);

            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset);
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0);
            row:Show();
            yOffset = yOffset + self.constants.LOOT_ROW_HEIGHT;
        end
    end

    scrollChild:SetHeight(yOffset + 8);
end
