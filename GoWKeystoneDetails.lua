GoWKeystoneDetails = {}
GoWKeystoneDetails.__index = GoWKeystoneDetails

local GOW = GuildsOfWow or {};

local PANEL_HEIGHT = 430;
local LEFT_PANEL_WIDTH = 210;
local HEADER_HEIGHT = 24;
local FILTER_BUTTON_HEIGHT = 14;
local LEFT_ROW_HEIGHT = 28;
local RIGHT_ROW_HEIGHT = 28;
local RIGHT_ROW_SPACING = 0;
local RIGHT_PANEL_WIDTH = 730;

local function GetClassColor(classFileName)
    local classColorSource = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS;
    return classColorSource and classColorSource[classFileName] or nil;
end

function GoWKeystoneDetails:new(core, ui, gui)
    local self = setmetatable({}, GoWKeystoneDetails);
    self.CORE = core;
    self.UI = ui;
    self.GUI = gui;
    self.pendingMembers = {};
    self.selectedDungeon = "All Dungeons";
    self.rootHost = nil;
    self.nativeRoot = nil;
    return self;
end

function GoWKeystoneDetails:Hide()
    if (self.nativeRoot) then
        self.nativeRoot:Hide();
        self.nativeRoot:SetParent(nil);
        self.nativeRoot = nil;
    end
end

function GoWKeystoneDetails:NormalizeCharacterKey(characterName)
    if (characterName == nil) then
        return "";
    end

    return string.lower(string.gsub(characterName, "[^%w]", ""));
end

function GoWKeystoneDetails:GetCharacterKeyFromUnit(unit)
    local name, realm = UnitFullName(unit);
    if (not name) then
        return nil;
    end

    if (realm == nil or realm == "") then
        realm = GetNormalizedRealmName();
    end

    return name .. "-" .. realm;
end

function GoWKeystoneDetails:IsMemberInCurrentGroup(memberKey)
    if (not IsInGroup()) then
        return false;
    end

    local normalizedMemberKey = self:NormalizeCharacterKey(memberKey);
    local playerKey = self:GetCharacterKeyFromUnit("player");

    if (playerKey and self:NormalizeCharacterKey(playerKey) == normalizedMemberKey) then
        return true;
    end

    if (IsInRaid()) then
        for i = 1, GetNumGroupMembers() do
            local unitKey = self:GetCharacterKeyFromUnit("raid" .. i);
            if (unitKey and self:NormalizeCharacterKey(unitKey) == normalizedMemberKey) then
                return true;
            end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local unitKey = self:GetCharacterKeyFromUnit("party" .. i);
            if (unitKey and self:NormalizeCharacterKey(unitKey) == normalizedMemberKey) then
                return true;
            end
        end
    end

    return false;
end

function GoWKeystoneDetails:GetGuildOnlineMemberMap()
    if (C_GuildInfo and C_GuildInfo.GuildRoster) then
        C_GuildInfo.GuildRoster();
    end

    local onlineMap = {};
    local numTotalMembers = GetNumGuildMembers() or 0;

    for i = 1, numTotalMembers do
        local memberName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i);
        if (memberName) then
            onlineMap[self:NormalizeCharacterKey(memberName)] = online;
            onlineMap[self:NormalizeCharacterKey(Ambiguate(memberName, "short"))] = online;
        end
    end

    return onlineMap;
end

function GoWKeystoneDetails:BuildRows()
    local onlineMap = self:GetGuildOnlineMemberMap();
    local me = GOW.Helper:GetCurrentCharacterUniqueKey();
    local sourceRows = GOW.Keystones:GetLatestEntries();
    local rows = {};

    for _, entry in ipairs(sourceRows) do
        local inviteName = entry.normalizedName or GOW.Helper:GetNormalizedCharacterName(entry.name);
        local isSelf = (inviteName == me);
        local isOnline = onlineMap[self:NormalizeCharacterKey(inviteName)] or onlineMap[self:NormalizeCharacterKey(entry.name)] or false;
        local isInGroup = self:IsMemberInCurrentGroup(inviteName);
        local isInvitePending = self.pendingMembers[inviteName] == true;
        local buttonText = "Invite";

        if (isSelf) then
            buttonText = "You";
        elseif (isInGroup) then
            buttonText = "Joined";
        elseif (isInvitePending) then
            buttonText = "Invite Pending";
        elseif (not isOnline) then
            buttonText = "Offline";
        end

        table.insert(rows, {
            inviteName = inviteName,
            name = entry.name,
            realm = entry.realm,
            classFileName = entry.classFileName,
            faction = entry.faction,
            keystoneLevel = entry.keystoneLevel,
            keystoneMapId = entry.keystoneMapId,
            dungeonName = entry.dungeonName,
            canInvite = (not isSelf and isOnline and not isInGroup and not isInvitePending),
            buttonText = buttonText
        });
    end

    table.sort(rows, function(a, b)
        if ((a.keystoneLevel or 0) ~= (b.keystoneLevel or 0)) then
            return (a.keystoneLevel or 0) > (b.keystoneLevel or 0);
        end

        return string.lower(a.name or "") < string.lower(b.name or "");
    end);

    return rows;
end

function GoWKeystoneDetails:GetSeasonDungeonFilters(rows)
    local filters = {};
    local countsByDungeon = {};
    local seenDungeons = {};

    for _, row in ipairs(rows) do
        local dungeonName = row.dungeonName or "Unknown";
        countsByDungeon[dungeonName] = (countsByDungeon[dungeonName] or 0) + 1;
    end

    table.insert(filters, {
        name = "All Dungeons",
        count = #rows,
        enabled = (#rows > 0)
    });

    if (C_ChallengeMode and C_ChallengeMode.GetMapTable) then
        for _, mapId in ipairs(C_ChallengeMode.GetMapTable() or {}) do
            local dungeonName = C_ChallengeMode.GetMapUIInfo(mapId);
            if (dungeonName and dungeonName ~= "" and not seenDungeons[dungeonName]) then
                seenDungeons[dungeonName] = true;
                table.insert(filters, {
                    name = dungeonName,
                    count = countsByDungeon[dungeonName] or 0,
                    enabled = (countsByDungeon[dungeonName] or 0) > 0
                });
            end
        end
    end

    for dungeonName, count in pairs(countsByDungeon) do
        if (not seenDungeons[dungeonName]) then
            table.insert(filters, {
                name = dungeonName,
                count = count,
                enabled = count > 0
            });
        end
    end

    return filters;
end

function GoWKeystoneDetails:NormalizeSelectedDungeon(filters)
    for _, filter in ipairs(filters) do
        if (filter.name == self.selectedDungeon and filter.enabled) then
            return;
        end
    end

    self.selectedDungeon = "All Dungeons";
end

function GoWKeystoneDetails:FilterRows(rows)
    if (self.selectedDungeon == nil or self.selectedDungeon == "All Dungeons") then
        return rows;
    end

    local filteredRows = {};
    for _, row in ipairs(rows) do
        if (row.dungeonName == self.selectedDungeon) then
            table.insert(filteredRows, row);
        end
    end

    return filteredRows;
end

function GoWKeystoneDetails:GetInvitableNames(rows)
    local inviteNames = {};

    for _, row in ipairs(rows) do
        if (row.canInvite) then
            table.insert(inviteNames, row.inviteName);
        end
    end

    return inviteNames;
end

function GoWKeystoneDetails:InviteName(inviteName)
    GOW.Helper:InviteToParty(inviteName);
    self.pendingMembers[inviteName] = true;

    C_Timer.After(60, function()
        self.pendingMembers[inviteName] = nil;
        if (self.UI and self.UI.containerFrame and self.UI.containerFrame:IsShown() and self.CORE and self.CORE.RefreshApplication) then
            self.CORE:RefreshApplication();
        end
    end);
end

function GoWKeystoneDetails:UpdatePanelScroll(panel, contentHeight)
    if (not panel or not panel.scrollFrame) then
        return;
    end

    panel.scrollFrame.contentHeight = contentHeight or 0;
    panel.scrollFrame:SetVerticalScroll(0);
end

function GoWKeystoneDetails:CreateLeftFilterRow(parent, filter, index, total)
    local L = GOW.Layout;
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate");
    row:SetHeight(LEFT_ROW_HEIGHT);
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * LEFT_ROW_HEIGHT));
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * LEFT_ROW_HEIGHT));

    row.highlight = L:CreateRowHighlight(row, 0.06);
    row.separator = L:CreateRowSeparator(row);

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    row.nameText:SetPoint("LEFT", row, "LEFT", 10, 0);
    row.nameText:SetPoint("RIGHT", row, "RIGHT", -42, 0);
    row.nameText:SetJustifyH("LEFT");

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    row.countText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    row.countText:SetJustifyH("RIGHT");

    local isSelected = (filter.name == self.selectedDungeon);
    local isEnabled = filter.enabled == true;

    if (isSelected) then
        L:ApplyBackdrop(row, L.constants.SUB_ACTIVE_COLOR.r, L.constants.SUB_ACTIVE_COLOR.g, L.constants.SUB_ACTIVE_COLOR.b, 0.22, L.constants.GOW_ACCENT_COLOR.r, L.constants.GOW_ACCENT_COLOR.g, L.constants.GOW_ACCENT_COLOR.b, 0.45);
    else
        L:ApplyBackdrop(row, 0, 0, 0, 0, 0, 0, 0, 0);
    end

    if (not isEnabled) then
        row.nameText:SetText("|cff666666" .. filter.name .. "|r");
        row.countText:SetText("|cff666666" .. tostring(filter.count or 0) .. "|r");
    elseif (isSelected) then
        row.nameText:SetText("|cffb9f3c8" .. filter.name .. "|r");
        row.countText:SetText("|cffb9f3c8" .. tostring(filter.count or 0) .. "|r");
    else
        row.nameText:SetText("|cffdddddd" .. filter.name .. "|r");
        row.countText:SetText("|cff9a9a9a" .. tostring(filter.count or 0) .. "|r");
    end

    row:SetScript("OnEnter", function(self)
        if (not isSelected and isEnabled) then
            self.highlight:Show();
        end
    end);
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide();
    end);
    row:SetScript("OnClick", function()
        if (not isEnabled) then
            return;
        end

        self.selectedDungeon = filter.name;
        self:Render();
    end);

    if (index == total) then
        row.separator:Hide();
    end

    return row;
end

function GoWKeystoneDetails:CreateLevelBadge(parent, text)
    local L = GOW.Layout;
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    badge:SetHeight(16);
    badge:SetBackdrop(L.constants.STANDARD_BACKDROP);
    badge:SetBackdropColor(0.05, 0.15, 0.05, 0.85);
    badge:SetBackdropBorderColor(0.1, 0.8, 0.3, 0.6);

    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0);
    badge.text:SetText("|cff00ff00" .. text .. "|r");
    badge:SetWidth(badge.text:GetStringWidth() + 12);

    return badge;
end

function GoWKeystoneDetails:CreateInviteButton(parent, row)
    local L = GOW.Layout;
    local btn = L:CreateSubFilterBtn(parent, row.canInvite and "Invite" or row.buttonText, 70);
    btn:SetHeight(FILTER_BUTTON_HEIGHT);
    btn:SetWidth(62);
    L:SetButtonActive(btn, row.canInvite);
    if (not row.canInvite) then
        btn.btnText:SetText("|cff888888" .. row.buttonText .. "|r");
    end

    btn:SetScript("OnClick", function()
        if (not row.canInvite) then
            return;
        end

        self:InviteName(row.inviteName);
        self:Render();
    end);

    return btn;
end

function GoWKeystoneDetails:CreateRightRow(parent, row, index)
    local L = GOW.Layout;
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    frame:SetHeight(RIGHT_ROW_HEIGHT);
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * (RIGHT_ROW_HEIGHT + RIGHT_ROW_SPACING)));
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * (RIGHT_ROW_HEIGHT + RIGHT_ROW_SPACING)));

    frame.highlight = L:CreateRowHighlight(frame, 0.05);
    frame.separator = L:CreateRowSeparator(frame);

    frame.factionIcon = frame:CreateTexture(nil, "ARTWORK");
    frame.factionIcon:SetSize(16, 16);
    frame.factionIcon:SetPoint("LEFT", frame, "LEFT", 10, 0);
    frame.factionIcon:SetTexture(GOW.Helper:GetFactionIcon(row.faction));

    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    frame.nameText:SetPoint("LEFT", frame.factionIcon, "RIGHT", 8, 5);
    frame.nameText:SetPoint("RIGHT", frame, "RIGHT", -300, 5);
    frame.nameText:SetJustifyH("LEFT");
    frame.nameText:SetWordWrap(false);

    local classColor = GetClassColor(row.classFileName);
    if (classColor) then
        frame.nameText:SetText(string.format("|cff%02x%02x%02x%s|r", classColor.r * 255, classColor.g * 255, classColor.b * 255, row.name or ""));
    else
        frame.nameText:SetText(row.name or "");
    end

    frame.realmText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    frame.realmText:SetPoint("TOPLEFT", frame.nameText, "BOTTOMLEFT", 0, -1);
    frame.realmText:SetPoint("RIGHT", frame.nameText, "RIGHT", 0, -1);
    frame.realmText:SetText("|cff888888" .. (row.realm or "") .. "|r");
    frame.realmText:SetJustifyH("LEFT");
    frame.realmText:SetWordWrap(false);

    frame.levelBadge = self:CreateLevelBadge(frame, "+" .. tostring(row.keystoneLevel or 0));
    frame.levelBadge:SetPoint("RIGHT", frame, "RIGHT", -72, 0);

    frame.inviteButton = self:CreateInviteButton(frame, row);
    frame.inviteButton:SetPoint("RIGHT", frame, "RIGHT", -6, 0);

    frame.dungeonText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    frame.dungeonText:SetPoint("RIGHT", frame.levelBadge, "LEFT", -8, 0);
    frame.dungeonText:SetWidth(150);
    frame.dungeonText:SetJustifyH("RIGHT");
    frame.dungeonText:SetText("|cffaaaaaa" .. (row.dungeonName or "") .. "|r");
    frame.dungeonText:SetWordWrap(false);

    frame:SetScript("OnEnter", function(self)
        self.highlight:Show();
    end);
    frame:SetScript("OnLeave", function(self)
        self.highlight:Hide();
    end);

    return frame;
end

function GoWKeystoneDetails:RenderEmptyRightPanel(panel, message)
    local text = panel.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    text:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 10, -8);
    text:SetPoint("RIGHT", panel.scrollChild, "RIGHT", -10, 0);
    text:SetJustifyH("LEFT");
    text:SetJustifyV("TOP");
    text:SetText("|cff999999" .. message .. "|r");
    panel.scrollChild:SetHeight(60);
end

function GoWKeystoneDetails:Render()
    local containerScrollFrame = self.UI.containerScrollFrame;
    local L = GOW.Layout;

    self:Hide();
    containerScrollFrame:ReleaseChildren();

    local allRows = self:BuildRows();
    local dungeonFilters = self:GetSeasonDungeonFilters(allRows);
    self:NormalizeSelectedDungeon(dungeonFilters);
    local rows = self:FilterRows(allRows);
    if (#allRows == 0) then
        self.CORE:AppendMessage("No keystones found for this guild yet.", false);
        self.CORE:AppendScrollBottomPadding();
        return;
    end

    self.rootHost = self.GUI:Create("SimpleGroup");
    self.rootHost:SetFullWidth(true);
    self.rootHost:SetHeight(PANEL_HEIGHT + 8);
    containerScrollFrame:AddChild(self.rootHost);

    local hostFrame = self.rootHost.frame;
    self.nativeRoot = CreateFrame("Frame", nil, hostFrame);
    self.nativeRoot:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0);
    self.nativeRoot:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -8, 0);
    self.nativeRoot:SetHeight(PANEL_HEIGHT);

    local leftPanel = GOW.Layout:GetContainerPanel(self.nativeRoot, {
        xOffset = 0,
        width = LEFT_PANEL_WIDTH,
        height = PANEL_HEIGHT,
        title = "DUNGEONS",
        headerHeight = HEADER_HEIGHT,
        topInset = 34,
        sideInset = 8,
        bottomInset = 8
    });
    local rightPanel = GOW.Layout:GetContainerPanel(self.nativeRoot, {
        xOffset = LEFT_PANEL_WIDTH + 6,
        width = RIGHT_PANEL_WIDTH,
        height = PANEL_HEIGHT,
        title = "KEYSTONES",
        headerHeight = HEADER_HEIGHT,
        topInset = 34,
        sideInset = 8,
        bottomInset = 8
    });

    local refreshBtn = L:CreateSubFilterBtn(rightPanel, "Refresh", 70);
    refreshBtn:SetPoint("RIGHT", rightPanel.headerBar, "RIGHT", 0, 0);
    refreshBtn:SetScript("OnClick", function()
        GOW.Keystones:Refresh();
        self:Render();
    end);

    for index, filter in ipairs(dungeonFilters) do
        self:CreateLeftFilterRow(leftPanel.scrollChild, filter, index, #dungeonFilters);
    end
    self:UpdatePanelScroll(leftPanel, math.max(#dungeonFilters * LEFT_ROW_HEIGHT, 1));
    leftPanel.scrollChild:SetHeight(math.max(#dungeonFilters * LEFT_ROW_HEIGHT, 1));

    if (#rows == 0) then
        self:RenderEmptyRightPanel(rightPanel, "No keystones found for the selected dungeon.");
        self:UpdatePanelScroll(rightPanel, 60);
    else
        for index, row in ipairs(rows) do
            self:CreateRightRow(rightPanel.scrollChild, row, index);
        end
        local rightHeight = (#rows * (RIGHT_ROW_HEIGHT + RIGHT_ROW_SPACING)) + 8;
        rightPanel.scrollChild:SetHeight(rightHeight);
        self:UpdatePanelScroll(rightPanel, rightHeight);
    end

    self.CORE:AppendScrollBottomPadding();
end
