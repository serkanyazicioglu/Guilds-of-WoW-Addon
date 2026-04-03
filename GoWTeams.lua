GoWTeams = {}
GoWTeams.__index = GoWTeams
local GOW = GuildsOfWow or {};
LibQTip = LibQTip or LibStub('LibQTip-1.0');

local f = CreateFrame("Frame");
f:RegisterEvent("CHAT_MSG_SYSTEM");

GoWTeamTabContainer = _G.GoWTeamTabContainer;
FRAME_NAME = _G.FRAME_NAME;

local GoWScrollTeamMemberContainer = nil;
local GoWTeamMemberContainer = nil;

function GoWTeams:new(core, ui, gui)
    local self = setmetatable({}, GoWTeams);
    self.CORE = core;
    self.UI = ui;
    self.GUI = gui;
    return self;
end

local roles = (GOW.Helper and GOW.Helper:GetRoles()) or {};

-- these are used to populate the "Filter by Role" dropdown
local rolesForFilter = {
    ["All"] = "All",
    ["Tank"] = "Tank",
    ["Healer"] = "Healer",
    ["DPS"] = "DPS",
};

-- these are used to populate the sort dropdown
local valuesForDropdown = {
    ["Name"] = "Name",
    ["Class"] = "Class",
    ["Spec"] = "Spec",
    ["Armor Token"] = "Armor Token",
    ["Online Status"] = "Online Status",
};

local LIST_PANEL_HEIGHT = 430;
local TEAM_ROW_HEIGHT = 52;
local TEAM_LIST_TOP_PADDING = 8;
local TEAM_DETAIL_PANEL_HEIGHT = 470;
local TEAM_DETAIL_LEFT_WIDTH = 220;
local TEAM_DETAIL_RIGHT_WIDTH = 740;
local TEAM_DETAIL_FILTER_ROW_HEIGHT = 32;
local TEAM_DETAIL_ROSTER_ROW_HEIGHT = 38;

local function GetDisplayRealmName(realmName)
    if (not realmName or realmName == "") then
        return "";
    end

    return tostring(realmName):gsub("(%l)(%u)", "%1 %2");
end

function GoWTeams:Hide()
    if (self.nativeRoot) then
        self.nativeRoot:Hide();
        self.nativeRoot:SetParent(nil);
        self.nativeRoot = nil;
    end

    self.rootHost = nil;
    self.listPanel = nil;
    self.teamRowCount = 0;
end

function GoWTeams:UpdatePanelScroll(panel, contentHeight)
    if (not panel or not panel.scrollFrame) then
        return;
    end

    panel.scrollFrame.contentHeight = contentHeight or 0;
    panel.scrollFrame:SetVerticalScroll(0);
    if (panel.UpdateScrollBar) then
        panel:UpdateScrollBar();
    end
end

function GoWTeams:EnsureListPanel()
    if (self.listPanel and self.nativeRoot and self.rootHost) then
        return;
    end

    local containerScrollFrame = self.UI.containerScrollFrame;
    local L = GOW.Layout;

    self.rootHost = self.GUI:Create("SimpleGroup");
    self.rootHost:SetFullWidth(true);
    self.rootHost:SetFullHeight(true);
    self.rootHost:SetHeight(LIST_PANEL_HEIGHT + 8);
    containerScrollFrame:AddChild(self.rootHost);

    local hostFrame = self.rootHost.frame;
    self.nativeRoot = CreateFrame("Frame", nil, hostFrame);
    self.nativeRoot:SetAllPoints(hostFrame);

    local panelWidth = math.max(880, math.floor(hostFrame:GetWidth() > 0 and hostFrame:GetWidth() or 946));
    self.listPanel = L:GetContainerPanel(self.nativeRoot, {
        title = "TEAMS",
        width = panelWidth,
        height = LIST_PANEL_HEIGHT,
        xOffset = 0,
        topInset = 28,
        sideInset = 10,
        bottomInset = 10,
    });
    self.listPanel:SetPoint("TOPLEFT", self.nativeRoot, "TOPLEFT", 0, -3);
    self.teamRowCount = 0;
end

function GoWTeams:RenderEmptyState(message, secondaryMessage, displayReloadButton)
    self:Hide();
    self.UI.containerScrollFrame:ReleaseChildren();
    local state = GOW.Layout:RenderWarningState(self.GUI, self.UI.containerScrollFrame, "TEAMS", message, secondaryMessage, displayReloadButton == true);
    self.rootHost = state.rootHost;
    self.nativeRoot = state.nativeRoot;
    self.listPanel = state.panel;
    self.teamRowCount = 0;
end

function GoWTeams:ClearNativeChildren(parent)
    if (not parent) then
        return;
    end

    local children = { parent:GetChildren() };
    for _, child in ipairs(children) do
        child:Hide();
        child:SetParent(nil);
    end
end

function GoWTeams:DestroyTeamDetailsRoot()
    if (self.teamDetailsRoot) then
        self.teamDetailsRoot:Hide();
        self.teamDetailsRoot:SetParent(nil);
        self.teamDetailsRoot = nil;
    end
end

function GoWTeams:BuildTeamFilters(teamData)
    local filters = {
        {
            key = "ALL",
            label = "All Roles",
            count = #(teamData.members or {}),
        }
    };

    local counts = {};
    for _, member in ipairs(teamData.members or {}) do
        local teamRole = member.teamRole or "Unknown";
        counts[teamRole] = (counts[teamRole] or 0) + 1;
    end

    local orderedRoles = { "Main", "Alt", "Backup", "Trial" };
    for _, teamRole in ipairs(orderedRoles) do
        table.insert(filters, {
            key = teamRole,
            label = teamRole,
            count = counts[teamRole] or 0,
        });
        counts[teamRole] = nil;
    end

    for teamRole, count in pairs(counts) do
        table.insert(filters, {
            key = teamRole,
            label = teamRole,
            count = count,
        });
    end

    return filters;
end

function GoWTeams:BuildPresenceMap()
    local presenceMap = {};
    local numGuildMembers = GetNumGuildMembers();

    for i = 1, numGuildMembers do
        local name, rankName, _, _, _, _, _, _, online = GetGuildRosterInfo(i);
        if (name) then
            presenceMap[self:GetNormalizedFullName(name)] = {
                online = online,
                guildRankName = rankName,
            };
        end
    end

    if (C_Club and C_Club.GetSubscribedCommunities) then
        local clubs = C_Club.GetSubscribedCommunities();
        if (clubs) then
            for _, club in ipairs(clubs) do
                local clubMembers = C_Club.GetClubMembers(club.clubId);
                if (clubMembers) then
                    for _, clubMember in ipairs(clubMembers) do
                        if (clubMember.name and clubMember.name ~= "") then
                            local normalizedName = self:GetNormalizedFullName(clubMember.name);
                            if (not presenceMap[normalizedName]) then
                                presenceMap[normalizedName] = {
                                    online = clubMember.isOnline,
                                    guildRankName = "Non-Guildie",
                                };
                            end
                        end
                    end
                end
            end
        end
    end

    return presenceMap;
end

function GoWTeams:GetMemberPresence(member, presenceMap)
    local realmNormalized = member.realmNormalized or GetNormalizedRealmName();
    local fullName = member.name .. "-" .. realmNormalized;
    local info = presenceMap[self:GetNormalizedFullName(fullName)];

    if (info) then
        return info.online == true, info.guildRankName or "";
    end

    return false, "Non-Guildie";
end

function GoWTeams:GetFilteredTeamMembers(teamData, selectedFilter, presenceMap)
    local filteredMembers = {};

    for _, member in ipairs(teamData.members or {}) do
        if (selectedFilter == "ALL" or member.teamRole == selectedFilter) then
            table.insert(filteredMembers, member);
        end
    end

    table.sort(filteredMembers, function(a, b)
        local aOnline = select(1, self:GetMemberPresence(a, presenceMap));
        local bOnline = select(1, self:GetMemberPresence(b, presenceMap));
        if (aOnline ~= bOnline) then
            return aOnline and not bOnline;
        end

        if ((a.teamRole or "") ~= (b.teamRole or "")) then
            return (a.teamRole or "") < (b.teamRole or "");
        end

        return (a.name or "") < (b.name or "");
    end);

    return filteredMembers;
end

function GoWTeams:CreateTeamInviteButton(parent, member, canInvite, buttonText)
    local L = GOW.Layout;
    local btn = L:CreateActionButton(parent, {
        text = buttonText,
        width = 76,
        isActive = canInvite,
        onClick = function(selfButton)
        local inviteName = member.name .. "-" .. (member.realmNormalized or GetNormalizedRealmName());
        GOW.Helper:InviteToParty(inviteName);
        selfButton:Disable();
        selfButton.btnText:SetText("Pending");
        selfButton.btnText:SetTextColor(0.65, 0.65, 0.65);
        end
    });

    return btn;
end

function GoWTeams:CreateTeamRosterRow(parent, member, index, total, presenceMap)
    local L = GOW.Layout;
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    row:SetHeight(TEAM_DETAIL_ROSTER_ROW_HEIGHT);
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * TEAM_DETAIL_ROSTER_ROW_HEIGHT));
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * TEAM_DETAIL_ROSTER_ROW_HEIGHT));

    row.highlight = L:CreateRowHighlight(row, 0.04);
    row.separator = L:CreateRowSeparator(row);

    row.factionIcon = row:CreateTexture(nil, "ARTWORK");
    row.factionIcon:SetSize(16, 16);
    row.factionIcon:SetPoint("LEFT", row, "LEFT", 10, 0);
    row.factionIcon:SetTexture(GOW.Helper:GetFactionIcon(member.faction));

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    nameText:SetPoint("LEFT", row.factionIcon, "RIGHT", 8, 5);
    nameText:SetPoint("RIGHT", row, "RIGHT", -590, 5);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);

    local _, classFileName = GetClassInfo(member.classId or 0);
    local classColor = GOW.Helper:GetClassColor(classFileName);
    if (classColor) then
        nameText:SetText(string.format("|cff%02x%02x%02x%s|r", classColor.r * 255, classColor.g * 255, classColor.b * 255, member.name or ""));
    else
        nameText:SetText(member.name or "");
    end

    local realmText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    realmText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -1);
    realmText:SetPoint("RIGHT", nameText, "RIGHT", 0, -1);
    realmText:SetText("|cff888888" .. GetDisplayRealmName(member.realmNormalized) .. "|r");
    realmText:SetJustifyH("LEFT");
    realmText:SetWordWrap(false);

    local specContainer = CreateFrame("Frame", nil, row);
    specContainer:SetPoint("LEFT", row, "LEFT", 200, 0);
    specContainer:SetSize(120, 18);

    local role = roles[member.specRoleId or 0];
    if (role and role.iconTexCoords) then
        local roleIcon = specContainer:CreateTexture(nil, "ARTWORK");
        roleIcon:SetTexture("Interface/LFGFrame/UI-LFG-ICON-PORTRAITROLES");
        roleIcon:SetSize(16, 16);
        roleIcon:SetPoint("LEFT", specContainer, "LEFT", 0, 0);
        roleIcon:SetTexCoord(unpack(role.iconTexCoords));
    end

    local specText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    specText:SetPoint("LEFT", specContainer, "LEFT", 20, 0);
    specText:SetPoint("RIGHT", specContainer, "RIGHT", 0, 0);
    specText:SetJustifyH("LEFT");
    specText:SetWordWrap(false);
    specText:SetText(member.spec or "");

    local groupText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    groupText:SetPoint("LEFT", row, "LEFT", 340, 0);
    groupText:SetWidth(80);
    groupText:SetJustifyH("LEFT");
    groupText:SetText("|cffaaaaaa" .. (member.teamRole or "") .. "|r");

    local tokenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    tokenText:SetPoint("LEFT", row, "LEFT", 420, 0);
    tokenText:SetWidth(100);
    tokenText:SetJustifyH("LEFT");
    tokenText:SetWordWrap(false);
    tokenText:SetText(member.armorToken or "");
    local tokenColorR, tokenColorG, tokenColorB = self:GoWHexToRGB(member.armorTokenColor or "");
    tokenText:SetTextColor(tokenColorR, tokenColorG, tokenColorB);

    local isConnected, guildRankName = self:GetMemberPresence(member, presenceMap);
    local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    rankText:SetPoint("LEFT", row, "LEFT", 525, 0);
    rankText:SetWidth(110);
    rankText:SetJustifyH("LEFT");
    rankText:SetWordWrap(false);
    rankText:SetText("|cffaaaaaa" .. (guildRankName or "") .. "|r");

    local currentPlayerName = UnitName("player");
    local canInvite = isConnected and member.name ~= currentPlayerName;
    local buttonText = canInvite and "Invite" or "Offline";

    if (member.name == currentPlayerName) then
        buttonText = "You";
        canInvite = false;
    elseif (IsInGroup()) then
        local numGroup = GetNumGroupMembers();
        local unitPrefix = IsInRaid() and "raid" or "party";
        local memberFullName = member.name .. "-" .. (member.realmNormalized or GetNormalizedRealmName());
        for i = 1, numGroup do
            local unitName = UnitName(unitPrefix .. i);
            if (unitName and (unitName == memberFullName or unitName == member.name)) then
                buttonText = "Joined";
                canInvite = false;
                break;
            end
        end
    end

    row.inviteButton = self:CreateTeamInviteButton(row, member, canInvite, buttonText);
    row.inviteButton:SetPoint("RIGHT", row, "RIGHT", -6, 0);

    if (index == total) then
        row.separator:Hide();
    end

    return row;
end

function GoWTeams:RenderTeamDetailsPopup(teamData, selectedFilter)
    local L = GOW.Layout;
    local windowFrame = GoWTeamTabContainer.frame;

    self:DestroyTeamDetailsRoot();

    local nativeRoot = CreateFrame("Frame", nil, windowFrame);
    nativeRoot:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 12, -32);
    nativeRoot:SetPoint("BOTTOMRIGHT", windowFrame, "BOTTOMRIGHT", -12, 12);
    self.teamDetailsRoot = nativeRoot;

    local leftPanel = L:GetContainerPanel(nativeRoot, {
        title = "ROLES",
        width = TEAM_DETAIL_LEFT_WIDTH,
        height = TEAM_DETAIL_PANEL_HEIGHT,
        xOffset = 0,
        topInset = 34,
        sideInset = 8,
        bottomInset = 8,
    });
    leftPanel:SetPoint("TOPLEFT", nativeRoot, "TOPLEFT", 6, -6);

    local rightPanel = L:GetContainerPanel(nativeRoot, {
        title = "ROSTER",
        width = TEAM_DETAIL_RIGHT_WIDTH,
        height = TEAM_DETAIL_PANEL_HEIGHT,
        xOffset = TEAM_DETAIL_LEFT_WIDTH + 12,
        topInset = 66,
        sideInset = 8,
        bottomInset = 8,
    });
    rightPanel:SetPoint("TOPLEFT", nativeRoot, "TOPLEFT", TEAM_DETAIL_LEFT_WIDTH + 12, -6);

    local filters = self:BuildTeamFilters(teamData);
    local presenceMap = self:BuildPresenceMap();
    local filteredMembers = self:GetFilteredTeamMembers(teamData, selectedFilter, presenceMap);

    local sidebar = L:CreateSidebarList(leftPanel.scrollChild, {
        rowHeight = TEAM_DETAIL_FILTER_ROW_HEIGHT,
        getLabel = function(item) return item.label end,
        getMeta = function(item) return tostring(item.count or 0) end,
        isSelected = function(item) return item.key == selectedFilter end,
        isEnabled = function(item) return item.key == "ALL" or (item.count or 0) > 0 end,
        isAccent = function(item) return item.key == "ALL" end,
        onSelect = function(item)
            self:RenderTeamDetailsPopup(teamData, item.key);
        end,
    });
    local leftHeight = math.max(sidebar:Render(filters), 1);
    leftPanel.scrollChild:SetHeight(leftHeight);
    leftPanel.scrollFrame.contentHeight = leftHeight;

    local summaryFrame = CreateFrame("Frame", nil, rightPanel);
    summaryFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 10, -30);
    summaryFrame:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -10, -30);
    summaryFrame:SetHeight(28);

    local purposeOffset = 0;
    if (teamData.purpose and teamData.purpose ~= "") then
        local purposeBadge = L:CreateTextBadge(summaryFrame, {
            text = teamData.purpose,
            minWidth = 32,
            paddingX = 10,
        });
        purposeBadge:SetPoint("LEFT", summaryFrame, "LEFT", 0, 0);
        purposeOffset = purposeBadge:GetWidth() + 8;
    end

    local summaryText = summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    summaryText:SetPoint("LEFT", summaryFrame, "LEFT", purposeOffset, 0);
    summaryText:SetPoint("RIGHT", summaryFrame, "RIGHT", 0, 0);
    summaryText:SetJustifyH("LEFT");
    summaryText:SetWordWrap(false);
    summaryText:SetText("|cff888888" .. ((teamData.description and teamData.description ~= "") and teamData.description or "No description provided") .. "|r");

    local headerRow = CreateFrame("Frame", nil, rightPanel.scrollChild);
    headerRow:SetHeight(18);
    headerRow:SetPoint("TOPLEFT", rightPanel.scrollChild, "TOPLEFT", 0, 0);
    headerRow:SetPoint("TOPRIGHT", rightPanel.scrollChild, "TOPRIGHT", 0, 0);

    local function CreateHeaderLabel(text, xOffset, width)
        local label = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        label:SetPoint("LEFT", headerRow, "LEFT", xOffset, 0);
        label:SetWidth(width);
        label:SetJustifyH("LEFT");
        label:SetText("|cffaaaaaa" .. text .. "|r");
    end

    CreateHeaderLabel("Name", 34, 130);
    CreateHeaderLabel("Spec", 200, 120);
    CreateHeaderLabel("Group", 340, 80);
    CreateHeaderLabel("Token", 420, 100);
    CreateHeaderLabel("Rank", 525, 110);

    local rowsAnchor = CreateFrame("Frame", nil, rightPanel.scrollChild);
    rowsAnchor:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4);
    rowsAnchor:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -4);
    rowsAnchor:SetHeight(math.max(1, #filteredMembers * TEAM_DETAIL_ROSTER_ROW_HEIGHT));

    if (#filteredMembers == 0) then
        local emptyText = rightPanel.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        emptyText:SetPoint("TOPLEFT", rowsAnchor, "TOPLEFT", 10, -10);
        emptyText:SetText("|cff888888No team members found.|r");
    else
        for index, member in ipairs(filteredMembers) do
            self:CreateTeamRosterRow(rowsAnchor, member, index, #filteredMembers, presenceMap);
        end
    end

    local contentHeight = 22 + 4 + (#filteredMembers * TEAM_DETAIL_ROSTER_ROW_HEIGHT);
    if (#filteredMembers == 0) then
        contentHeight = 70;
    end
    rightPanel.scrollChild:SetHeight(contentHeight);
    rightPanel.scrollFrame.contentHeight = contentHeight;
end

function GoWTeams:OpenTeamDetails(teamData)
    self.CORE:DestroyTeamContainer();
    C_GuildInfo.GuildRoster();

    GoWTeamTabContainer = self.GUI:Create("Window");
    GoWTeamTabContainer:SetTitle(teamData.name or "Team");
    GoWTeamTabContainer:SetWidth(1000);
    GoWTeamTabContainer:SetHeight(550);
    GoWTeamTabContainer:EnableResize(false);
    GoWTeamTabContainer.frame:SetPoint("CENTER", UIParent, "CENTER", 40, -40);
    GoWTeamTabContainer.frame:SetFrameStrata("HIGH");
    GoWTeamTabContainer:SetLayout("Fill");
    GoWTeamTabContainer.closebutton:SetPoint("TOPRIGHT", -2, -2);
    self:SetBackdrop();

    _G[FRAME_NAME] = GoWTeamTabContainer.frame;
    GoWTeamTabContainer:SetCallback("OnClose", function()
        self:DestroyTeamDetailsRoot();
        self.CORE:DestroyTeamContainer();
    end);

    self:RenderTeamDetailsPopup(teamData, "ALL");
    return;
end
--[[

        -- //SECTION Team Details (TD) - Tables and Variables
        local teamNavItems = {}; -- holds the different team groups (Main, Alt, Backup, Trial) and used to render the nav buttons
        local teamMembers = teamData.members or {};

        -- holds information about the Main group members and roles
        local mainGroupMembers = {};
        local mainGroupTanks = {};
        local mainGroupHealers = {};
        local mainGroupDPS = {};

        -- holds information about the Alt group members and roles
        local altGroupMembers = {};
        local altGroupTanks = {};
        local altGroupHealers = {};
        local altGroupDPS = {};

        -- holds information about the Backup group members and roles
        local backupGroupMembers = {};
        local backupGroupTanks = {};
        local backupGroupHealers = {};
        local backupGroupDPS = {};

        -- holds information about the Trial group members and roles
        local trialGroupMembers = {};
        local trialGroupTanks = {};
        local trialGroupHealers = {};
        local trialGroupDPS = {};

        local filteredMembers = {}; -- holds the filtered members based on the navigation selected
        local totalMembers = 0;     -- holds the total number of members in the team

        -- these are used to trigger a table.insert function that will be used to populate teamNavItems
        local mainGroupFound = false;
        local altGroupFound = false;
        local backupGroupFound = false;
        local trialGroupFound = false;

        local currentFilterValue = "All"; -- holds the current value of the filter dropdown
        local currentSortValue = "None";  -- holds the current value of the sort dropdown
        local isOfflineChecked = false;   -- holds the value of the hide offline members checkbox
        -- //!SECTION

        -- //SECTION - TD - Layout Creation
        GoWTeamTabContainer = self.GUI:Create("Window");
        GoWTeamTabContainer:SetTitle(teamData.name);
        GoWTeamTabContainer:SetWidth(1000);
        GoWTeamTabContainer:SetHeight(550);
        GoWTeamTabContainer:EnableResize(false);
        GoWTeamTabContainer.frame:SetPoint("CENTER", UIParent, "CENTER", 40, -40);
        GoWTeamTabContainer.frame:SetFrameStrata("HIGH");
        GoWTeamTabContainer:SetLayout("Flow");
        GoWTeamTabContainer.closebutton:SetPoint("TOPRIGHT", -2, -2);
        self:SetBackdrop();

        _G[FRAME_NAME] = GoWTeamTabContainer.frame;
        GoWTeamTabContainer:SetCallback("OnClose", function()
            self.CORE:DestroyTeamContainer();
        end);

        -- //STUB TD - Nav Container
        local teamNavContainer = self.GUI:Create("InlineGroup");
        teamNavContainer:SetWidth(200);
        teamNavContainer:SetLayout("Flow");
        teamNavContainer:SetFullHeight(true);
        teamNavContainer:SetPoint("TOP", GoWTeamTabContainer.frame, "TOP", 0, 0);
        GoWTeamTabContainer:AddChild(teamNavContainer);

        -- //STUB TD - Information Container
        local teamInfoContainer = self.GUI:Create("InlineGroup");
        teamInfoContainer:SetLayout("Flow");
        teamInfoContainer:SetWidth(750);
        teamInfoContainer:SetFullHeight(true);
        teamInfoContainer:SetPoint("TOPLEFT", teamNavContainer.frame, "TOPRIGHT", 0, 0);
        GoWTeamTabContainer:AddChild(teamInfoContainer);

        -- //!SECTION

        -- //SECTION - TD - Summary
        -- //STUB Team URL
        local teamURL = self.GUI:Create("SFX-Info-URL");
        teamURL:SetLabel("Team Link");
        teamURL:SetText(teamData.webUrl);
        teamURL:SetDisabled(false);
        teamInfoContainer:AddChild(teamURL);

        -- //STUB Team Description
        local teamDescriptionLabel = self.GUI:Create("SFX-Info");
        teamDescriptionLabel:SetLabel("Description");
        if teamData.description == "" then
            teamDescriptionLabel:SetText("No description provided.");
        else
            teamDescriptionLabel:SetText(teamData.description);
            teamDescriptionLabel:SetCallback("OnEnter", function(self)
                local tooltip = LibQTip:Acquire("TeamDescriptionTooltip", 1, "LEFT");
                GOW.tooltip = tooltip;

                tooltip:AddHeader('|cffffcc00Team Description');
                local line = tooltip:AddLine();
                tooltip:SetCell(line, 1, teamData.description, "LEFT", 1, nil, 0, 0, 300, 50);
                tooltip:SmartAnchorTo(self.frame);
                tooltip:Show();
            end);
            teamDescriptionLabel:SetCallback("OnLeave", function()
                LibQTip:Release(GOW.tooltip);
                GOW.tooltip = nil;
            end);
        end;
        teamDescriptionLabel:SetDisabled(false);
        teamInfoContainer:AddChild(teamDescriptionLabel);

        local roleAndHideOfflineGroup = self.GUI:Create("SimpleGroup");
        roleAndHideOfflineGroup:SetLayout("Flow");
        roleAndHideOfflineGroup:SetWidth(740);
        roleAndHideOfflineGroup:SetHeight(30);
        teamInfoContainer:AddChild(roleAndHideOfflineGroup);

        local marginGap = self.GUI:Create("SimpleGroup");
        marginGap:SetLayout("Flow");
        marginGap:SetHeight(40); -- adds margin
        marginGap:SetWidth(5);

        -- // STUB Hide Offline Members Button
        local hideOfflineMembersCheckBox = self.GUI:Create("CheckBox");
        hideOfflineMembersCheckBox:SetLabel("Hide Offline Members");
        hideOfflineMembersCheckBox:SetValue(isOfflineChecked);
        hideOfflineMembersCheckBox:SetType("checkbox");
        hideOfflineMembersCheckBox:SetDisabled(false);
        hideOfflineMembersCheckBox:SetHeight(18); -- helps with alignment
        hideOfflineMembersCheckBox:SetCallback("OnValueChanged", function()
            if GoWScrollTeamMemberContainer then
                if GoWTeamMemberContainer then
                    GoWTeamMemberContainer:ReleaseChildren();
                end;
                local teamGroup = GoWScrollTeamMemberContainer:GetUserData("teamGroup"); -- used to get the current teamGroup selected from the navigation buttons
                local filterValue = currentFilterValue;
                local checkBoxValue = hideOfflineMembersCheckBox:GetValue();

                -- args: teamGroup, hideOffline, specRole
                RenderFilteredTeamMembers(teamGroup, checkBoxValue, filterValue, currentSortValue);

                isOfflineChecked = checkBoxValue;
                checkBoxValue = not checkBoxValue;
            end;
        end);
        roleAndHideOfflineGroup:AddChild(hideOfflineMembersCheckBox);

        -- //STUB Team Member Container
        GoWScrollTeamMemberContainer = self.GUI:Create("InlineGroup");
        GoWScrollTeamMemberContainer:SetFullHeight(true);
        GoWScrollTeamMemberContainer:SetLayout("Fill");
        GoWScrollTeamMemberContainer:SetFullWidth(true);
        teamInfoContainer:AddChild(GoWScrollTeamMemberContainer);

        GoWTeamMemberContainer = self.GUI:Create("ScrollFrame");
        GoWTeamMemberContainer:SetFullHeight(true);
        GoWTeamMemberContainer:SetLayout("List");
        GoWTeamMemberContainer:SetFullWidth(true);
        GoWScrollTeamMemberContainer:AddChild(GoWTeamMemberContainer);

        -- // STUB Role Filter
        local roleFilter = self.GUI:Create("Dropdown");
        roleFilter:SetLabel("  Filter by Role");
        roleFilter:SetList(rolesForFilter, { "All", "Tank", "Healer", "DPS" });
        roleFilter:SetValue("All");
        roleFilter:SetWidth(150);
        roleFilter.label:SetFontObject(GameFontNormal);
        roleFilter:SetCallback("OnValueChanged", function(key)
            local selectedRole = key:GetValue();

            -- clear the team member container before rendering the filtered members
            if GoWTeamMemberContainer then
                GoWTeamMemberContainer:ReleaseChildren();
            end;

            local teamGroup = nil;
            if GoWScrollTeamMemberContainer then
                -- get the current role selected from the navigation buttons
                teamGroup = GoWScrollTeamMemberContainer:GetUserData("teamGroup");
            end;

            if selectedRole then
                -- render the team members based on the role selected and whether or not the hide offline members checkbox is checked
                RenderFilteredTeamMembers(teamGroup, isOfflineChecked, selectedRole, currentSortValue);

                -- set the current filter value to the selected role
                currentFilterValue = selectedRole;
            end;
        end);

        -- ensures that the OnValueChanged callback is fired when the dropdown is created
        if roleFilter then
            C_Timer.After(0, function() roleFilter:Fire("OnValueChanged") end);
        end;

        roleAndHideOfflineGroup:AddChild(roleFilter, hideOfflineMembersCheckBox);

        roleAndHideOfflineGroup:AddChild(marginGap, hideOfflineMembersCheckBox);

        -- // STUB Sort Dropdown
        local sortDropdown = self.GUI:Create("Dropdown");
        sortDropdown:SetLabel("  Sort by");
        sortDropdown:SetList(valuesForDropdown, { "Name", "Class", "Spec", "Armor Token", "Online Status" });
        sortDropdown:SetValue("Online Status");
        sortDropdown:SetWidth(150);
        sortDropdown.label:SetFontObject(GameFontNormal);
        sortDropdown:SetCallback("OnValueChanged", function(key)
            local selectedValue = key:GetValue();

            -- clear the team member container before rendering the filtered members
            if GoWTeamMemberContainer then
                GoWTeamMemberContainer:ReleaseChildren();
            end;

            local teamGroup = nil;
            if GoWScrollTeamMemberContainer then
                -- get the current role selected from the navigation buttons
                teamGroup = GoWScrollTeamMemberContainer:GetUserData("teamGroup");
            end;

            if selectedValue then
                -- render the team members based on the role selected, whether or not the hide offline members checkbox is checked, the current filter value, and the selected value
                RenderFilteredTeamMembers(teamGroup, isOfflineChecked, currentFilterValue, selectedValue);

                -- set the current dropdown value to the selected value
                currentSortValue = selectedValue;
            end;
        end);

        -- ensures that the OnValueChanged callback is fired when the dropdown is created
        if sortDropdown then
            C_Timer.After(0, function() sortDropdown:Fire("OnValueChanged") end);
        end;
        teamInfoContainer:AddChild(sortDropdown, roleFilter);
        sortDropdown:ClearAllPoints();
        sortDropdown:SetPoint("BOTTOMRIGHT", GoWTeamMemberContainer.frame, "TOPRIGHT", 0, 12);

        -- //SECTION TD - Render Team Members
        -- //STUB (Fn) RenderFilteredTeamMembers
        function RenderFilteredTeamMembers(teamGroup, hideOffline, specRole, sortValue)
            C_GuildInfo.GuildRoster();

            local currentPlayerName = UnitName("player");

            -- if specRole is selected, filter the members based on the specRole
            if specRole then
                if specRole == "All" then
                    if teamGroup == "Main" then
                        filteredMembers = mainGroupMembers;
                    elseif teamGroup == "Alt" then
                        filteredMembers = altGroupMembers;
                    elseif teamGroup == "Backup" then
                        filteredMembers = backupGroupMembers;
                    elseif teamGroup == "Trial" then
                        filteredMembers = trialGroupMembers;
                    end;
                elseif specRole == "Tank" then
                    if teamGroup == "Main" then
                        filteredMembers = mainGroupTanks;
                    elseif teamGroup == "Alt" then
                        filteredMembers = altGroupTanks;
                    elseif teamGroup == "Backup" then
                        filteredMembers = backupGroupTanks;
                    elseif teamGroup == "Trial" then
                        filteredMembers = trialGroupTanks;
                    end;
                elseif specRole == "Healer" then
                    if teamGroup == "Main" then
                        filteredMembers = mainGroupHealers;
                    elseif teamGroup == "Alt" then
                        filteredMembers = altGroupHealers;
                    elseif teamGroup == "Backup" then
                        filteredMembers = backupGroupHealers;
                    elseif teamGroup == "Trial" then
                        filteredMembers = trialGroupHealers;
                    end;
                elseif specRole == "DPS" then
                    if teamGroup == "Main" then
                        filteredMembers = mainGroupDPS;
                    elseif teamGroup == "Alt" then
                        filteredMembers = altGroupDPS;
                    elseif teamGroup == "Backup" then
                        filteredMembers = backupGroupDPS;
                    elseif teamGroup == "Trial" then
                        filteredMembers = trialGroupDPS;
                    end;
                end;
            end;

            -- if sortValue is selected, sort the members based on the sortValue
            if sortValue then
                if sortValue == "Name" then
                    table.sort(filteredMembers, function(a, b)
                        return a.name < b.name;
                    end);
                elseif sortValue == "Class" then
                    table.sort(filteredMembers, function(a, b)
                        return a.classId < b.classId;
                    end);
                elseif sortValue == "Spec" then
                    table.sort(filteredMembers, function(a, b)
                        return a.spec < b.spec;
                    end);
                elseif sortValue == "Armor Token" then
                    table.sort(filteredMembers, function(a, b)
                        return a.armorToken < b.armorToken;
                    end);
                elseif sortValue == "Online Status" then
                    table.sort(filteredMembers, function(a, b)
                        local function isOnline(member)
                            local num = GetNumGuildMembers();
                            for i = 1, num do
                                local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i);
                                local baseName = name and name:match("^(.-)%-") or name;
                                if baseName == member.name then
                                    return online;
                                end;
                            end;
                            return false;
                        end;
                        return isOnline(a) and not isOnline(b);
                    end);
                end;
            end;

            -- a local variable to help us render empty states
            local totalTeamMembers = #filteredMembers;

            local function checkForEmptyState()
                -- Render an empty state if no members are found.
                if totalTeamMembers == 0 then
                    local noMembersLabel = self.GUI:Create("Label");
                    noMembersLabel:SetText("No members found.");
                    noMembersLabel:SetFullWidth(true);
                    noMembersLabel:SetFontObject(GameFontNormal);
                    if GoWTeamMemberContainer then
                        GoWTeamMemberContainer:AddChild(noMembersLabel);
                    end;
                end;
            end;

            checkForEmptyState();

            -- Render each filtered member.
            if filteredMembers then
                -- attempt to find the member in the guild roster
                for _, member in ipairs(filteredMembers) do
                    local isConnected = nil;
                    local numGuildMembers = GetNumGuildMembers();
                    local guildRankName = nil;
                    local isInGuildOrCommunity = false;

                    for i = 1, numGuildMembers do
                        local name, rankName, _, _, _, _, _, _, online = GetGuildRosterInfo(i);
                        -- In guild roster names may include realm (e.g. "Player-Realm"), so compare only the base names
                        local baseName = name and name:match("^(.-)%-") or name;
                        if baseName == (member.name .. "-" .. member.realmNormalized) or baseName == member.name then
                            isConnected = online;
                            guildRankName = rankName;
                            isInGuildOrCommunity = true;
                        end;
                    end;

                    -- If not found in guild, check communities if available
                    if not isConnected and C_Club and C_Club.GetSubscribedCommunities then
                        local clubs = C_Club.GetSubscribedCommunities();
                        if clubs then
                            for _, club in ipairs(clubs) do
                                local clubMembers = C_Club.GetClubMembers(club.clubId);
                                if clubMembers then
                                    for _, clubMember in ipairs(clubMembers) do
                                        if clubMember.name == member.name then
                                            isConnected = clubMember.isOnline;
                                            guildRankName = "Non-Guildie";
                                            isInGuildOrCommunity = true;
                                        end;
                                    end;
                                end;
                                if isConnected then break end;
                            end;
                        end;
                    end;

                    if not isInGuildOrCommunity then
                        guildRankName = "Non-Guildie";
                    end;

                    if not isConnected and hideOffline == true then
                        -- reduce the totalTeamMembers count
                        if totalTeamMembers > 0 then
                            totalTeamMembers = totalTeamMembers - 1;
                            checkForEmptyState();
                        end;
                    else
                        -- //STUB TD - Member Container
                        -- Creates a container to hold the member's information and invite button.
                        local memberContainer = self.GUI:Create("SimpleGroup");
                        memberContainer:SetLayout("Flow");
                        memberContainer:SetFullWidth(true);
                        memberContainer.frame:SetFrameLevel(2);

                        -- Get the class color for the member.
                        local className, classFile, classID = GetClassInfo(member.classId);
                        local classColor = { r = 1, g = 1, b = 1 };
                        if classFile then
                            local GetClassColorFunc = GetClassColorObj or C_ClassColor.GetClassColor;
                            classColor = GetClassColorFunc(classFile);
                        end;
                        local classColorRGB = { r = classColor.r, g = classColor.g, b = classColor.b };

                        -- Create labels for the member's name, spec, guild rank and armor token.
                        local factionIcon = self.GUI:Create("Label");
                        if member.faction == 1 then
                            factionIcon:SetImage(652156);
                        else
                            factionIcon:SetImage(652155);
                        end;
                        factionIcon:SetImageSize(30, 30);
                        factionIcon:SetWidth(30);
                        factionIcon:SetHeight(30);
                        memberContainer:AddChild(factionIcon);

                        local nameLabel = self.GUI:Create("Label");
                        nameLabel:SetWidth(170);
                        nameLabel:SetText(member.name);
                        nameLabel:SetFontObject(GameFontNormal);
                        nameLabel:SetColor(classColorRGB.r, classColorRGB.g, classColorRGB.b);
                        memberContainer:AddChild(nameLabel);

                        local roleAndIconGroup = self.GUI:Create("SimpleGroup");
                        roleAndIconGroup:SetWidth(130);
                        roleAndIconGroup:SetHeight(30);
                        roleAndIconGroup:SetLayout("Flow");

                        local coords = roles[member.specRoleId].iconTexCoords;
                        if coords then
                            local roleIcon = self.GUI:Create("Icon");
                            roleIcon:SetImageSize(16, 16);
                            roleIcon:SetWidth(16);
                            roleIcon:SetHeight(30);
                            roleIcon:SetImage("Interface/LFGFrame/UI-LFG-ICON-PORTRAITROLES");
                            roleIcon.image:SetPoint("TOP", roleIcon.frame, "TOP", -3, -6);
                            roleIcon.image:SetTexCoord(unpack(coords));
                            roleIcon:SetCallback("OnEnter", function(self)
                                local tooltip = LibQTip:Acquire("RoleIconTooltip", 1, "LEFT");
                                GOW.tooltip = tooltip;

                                tooltip:AddHeader('|cffffcc00' .. roles[member.specRoleId].name);
                                tooltip:SmartAnchorTo(self.frame);
                                tooltip:Show();
                            end);
                            roleIcon:SetCallback("OnLeave", function()
                                LibQTip:Release(GOW.tooltip);
                                GOW.tooltip = nil;
                            end);
                            roleAndIconGroup:AddChild(roleIcon);
                        end;

                        local specLabel = self.GUI:Create("Label");
                        specLabel:SetWidth(110);
                        specLabel:SetText(member.spec);
                        specLabel:SetFontObject(GameFontNormal);
                        roleAndIconGroup:AddChild(specLabel);

                        memberContainer:AddChild(roleAndIconGroup);

                        local tokenLabel = self.GUI:Create("Label");
                        tokenLabel:SetWidth(90);
                        tokenLabel:SetText(member.armorToken);
                        local tokenColorR, tokenColorG, tokenColorB = self:GoWHexToRGB(member.armorTokenColor);
                        tokenLabel:SetColor(tokenColorR, tokenColorG, tokenColorB);
                        tokenLabel:SetFontObject(GameFontNormal);
                        memberContainer:AddChild(tokenLabel);

                        local guildRankLabel = self.GUI:Create("Label");
                        guildRankLabel:SetWidth(110);
                        guildRankLabel:SetText(guildRankName);
                        guildRankLabel:SetFontObject(GameFontNormal);
                        memberContainer:AddChild(guildRankLabel);

                        local inviteMember = self.GUI:Create("Button");
                        inviteMember:SetWidth(150);

                        -- Check whether the member is already in the party or raid.
                        C_Timer.After(0, function()
                            if IsInGroup() then
                                local numGroup = GetNumGroupMembers();
                                local unitPrefix = IsInRaid() and "raid" or "party";
                                local memberFullName = (member.name .. "-" .. member.realmNormalized) or member.name;
                                for i = 1, numGroup do
                                    local unitId = unitPrefix .. i;
                                    local unitName = UnitName(unitId);
                                    if unitName and (unitName == memberFullName or unitName == member.name) then
                                        inviteMember:SetText("Joined");
                                        inviteMember:SetDisabled(true);
                                        break
                                    end;
                                end;
                            end;
                        end);

                        if isConnected and member.name ~= currentPlayerName then
                            inviteMember:SetText("Invite");
                            inviteMember:SetDisabled(false);
                        else
                            inviteMember:SetDisabled(true);
                            if member.name == currentPlayerName then
                                inviteMember:SetText("You");
                            else
                                inviteMember:SetText("Offline");
                            end;
                        end;

                        inviteMember:SetCallback("OnClick", function()
                            local playerJoinState = "Pending";
                            C_PartyInfo.InviteUnit(member.name .. "-" .. member.realmNormalized);
                            inviteMember:SetText("Invite Pending");
                            inviteMember:SetDisabled(true);

                            local function eventHandler(self, event, text, ...)
                                if event == "CHAT_MSG_SYSTEM" then
                                    local searchString = "joins the ";
                                    local memberName = (member.name .. "-" .. member.realmNormalized) or member.name;
                                    local joinedGroupString = string.find(text, searchString, 0, true);
                                    local joinedGroupString2 = string.find(text, memberName, 0, true);
                                    if joinedGroupString ~= nil and joinedGroupString2 ~= nil then
                                        inviteMember:SetText("Joined");
                                        inviteMember:SetDisabled(true);
                                        playerJoinState = "Joined";
                                    end;
                                end;
                            end;

                            C_Timer.After(61, function()
                                if playerJoinState == "Pending" then
                                    inviteMember:SetText("Invite");
                                    inviteMember:SetDisabled(false);
                                end;
                            end);

                            f:SetScript("OnEvent", eventHandler);
                        end);

                        if GoWTeamMemberContainer then
                            GoWTeamMemberContainer:AddChild(memberContainer);
                        end;

                        if memberContainer then
                            memberContainer:AddChild(inviteMember);
                        end;
                    end;
                end;
                return filteredMembers, totalMembers;
            end;
        end;

        -- //!SECTION

        -- check if the team has the main, alts, backup, and trial groups and add them to the correct tables
        if teamMembers then
            for _, member in pairs(teamMembers) do
                local teamRole = member.teamRole;

                if teamRole == "Main" then
                    mainGroupFound = true;
                    table.insert(mainGroupMembers, member);
                    if member.specRoleId == 1 then
                        table.insert(mainGroupTanks, member);
                    elseif member.specRoleId == 2 then
                        table.insert(mainGroupHealers, member);
                    elseif member.specRoleId == 3 then
                        table.insert(mainGroupDPS, member);
                    end;
                elseif teamRole == "Alt" then
                    altGroupFound = true;
                    table.insert(altGroupMembers, member);
                    if member.specRoleId == 1 then
                        table.insert(altGroupTanks, member);
                    elseif member.specRoleId == 2 then
                        table.insert(altGroupHealers, member);
                    elseif member.specRoleId == 3 then
                        table.insert(altGroupDPS, member);
                    end;
                elseif teamRole == "Backup" then
                    backupGroupFound = true;
                    table.insert(backupGroupMembers, member);
                    if member.specRoleId == 1 then
                        table.insert(backupGroupTanks, member);
                    elseif member.specRoleId == 2 then
                        table.insert(backupGroupHealers, member);
                    elseif member.specRoleId == 3 then
                        table.insert(backupGroupDPS, member);
                    end;
                elseif teamRole == "Trial" then
                    trialGroupFound = true;
                    table.insert(trialGroupMembers, member);
                    if member.specRoleId == 1 then
                        table.insert(trialGroupTanks, member);
                    elseif member.specRoleId == 2 then
                        table.insert(trialGroupHealers, member);
                    elseif member.specRoleId == 3 then
                        table.insert(trialGroupDPS, member);
                    end;
                end;
            end;
        end;

        if mainGroupFound then
            table.insert(teamNavItems, "Main");
        end;

        if altGroupFound then
            table.insert(teamNavItems, "Alt");
        end;

        if backupGroupFound then
            table.insert(teamNavItems, "Backup");
        end;

        if trialGroupFound then
            table.insert(teamNavItems, "Trial");
        end;

        -- //STUB Render Nav Buttons
        if teamNavItems then
            for _, teamGroup in ipairs(teamNavItems) do
                local teamGroupNavBtn = self.GUI:Create("Button");
                teamGroupNavBtn:SetFullWidth(true);
                teamGroupNavBtn:SetHeight(40);
                teamGroupNavBtn:SetText(teamGroup);
                local teamGroupNavBtnTexture = teamGroupNavBtn.frame:CreateTexture(nil, "BACKGROUND");
                teamGroupNavBtnTexture:SetAllPoints();

                teamGroupNavBtn:SetCallback("OnClick", function()
                    if GoWTeamMemberContainer then
                        GoWTeamMemberContainer:ReleaseChildren();
                    end;

                    hideOfflineMembersCheckBox:SetValue(isOfflineChecked);
                    RenderFilteredTeamMembers(teamGroup, isOfflineChecked, currentFilterValue, currentSortValue);

                    GoWScrollTeamMemberContainer:SetTitle(teamGroup .. " Members");
                    GoWScrollTeamMemberContainer:SetUserData("teamGroup", teamGroup);
                end);

                if teamNavContainer then
                    teamNavContainer:AddChild(teamGroupNavBtn);
                end;

                if teamGroupNavBtn and teamGroup == "Main" then
                    C_Timer.After(0, function() teamGroupNavBtn:Fire("OnClick") end);
                end;
            end;
        end;
    C_GuildInfo.GuildRoster();
end

]]
function GoWTeams:AppendTeam(teamData)
    if (not teamData) then
        return;
    end

    self:EnsureListPanel();

    local L = GOW.Layout;
    local index = (self.teamRowCount or 0) + 1;
    local row = CreateFrame("Button", nil, self.listPanel.scrollChild, "BackdropTemplate");
    row:SetHeight(TEAM_ROW_HEIGHT);
    row:SetPoint("TOPLEFT", self.listPanel.scrollChild, "TOPLEFT", 0, -(TEAM_LIST_TOP_PADDING + ((index - 1) * TEAM_ROW_HEIGHT)));
    row:SetPoint("TOPRIGHT", self.listPanel.scrollChild, "TOPRIGHT", 0, -(TEAM_LIST_TOP_PADDING + ((index - 1) * TEAM_ROW_HEIGHT)));

    row.highlight = L:CreateRowHighlight(row, 0.06);
    row.separator = L:CreateRowSeparator(row);
    L:ApplyBackdrop(row, 0, 0, 0, 0, 0, 0, 0, 0);

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8);
    nameText:SetPoint("RIGHT", row, "RIGHT", -140, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    nameText:SetText(teamData.name or "");

    local detailAnchor = CreateFrame("Frame", nil, row);
    detailAnchor:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4);
    detailAnchor:SetPoint("RIGHT", row, "RIGHT", -140, 0);
    detailAnchor:SetHeight(18);

    local purposeBadge;
    if (teamData.purpose and teamData.purpose ~= "") then
        purposeBadge = L:CreateTextBadge(detailAnchor, {
            text = teamData.purpose,
            minWidth = 28,
            paddingX = 10,
        });
        purposeBadge:SetPoint("LEFT", detailAnchor, "LEFT", 0, 0);
    end

    local detailsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    if (purposeBadge) then
        detailsText:SetPoint("LEFT", purposeBadge, "RIGHT", 8, 0);
    else
        detailsText:SetPoint("LEFT", detailAnchor, "LEFT", 0, 0);
    end
    detailsText:SetPoint("RIGHT", detailAnchor, "RIGHT", 0, 0);
    detailsText:SetJustifyH("LEFT");
    detailsText:SetWordWrap(false);

    local description = teamData.description;
    if (description == nil or description == "") then
        description = "No description provided";
    end
    detailsText:SetText("|cff888888" .. description .. "|r");

    local membersText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    membersText:SetPoint("RIGHT", row, "RIGHT", -110, 0);
    membersText:SetJustifyH("RIGHT");
    membersText:SetText("|cffaaaaaa" .. tostring(teamData.totalMembers or 0) .. "|r");

    local button = L:CreateActionButton(row, {
        text = "View Roster",
        width = 92,
        onClick = function()
            self:OpenTeamDetails(teamData);
        end
    });
    button:SetPoint("RIGHT", row, "RIGHT", -10, 0);

    row:SetScript("OnEnter", function(selfFrame)
        selfFrame.highlight:Show();
    end);
    row:SetScript("OnLeave", function(selfFrame)
        selfFrame.highlight:Hide();
    end);
    row:SetScript("OnClick", function()
        self:OpenTeamDetails(teamData);
    end);

    self.teamRowCount = index;
    self.listPanel.scrollChild:SetHeight(TEAM_LIST_TOP_PADDING + (index * TEAM_ROW_HEIGHT));
    self:UpdatePanelScroll(self.listPanel, TEAM_LIST_TOP_PADDING + (index * TEAM_ROW_HEIGHT));
end

-- //!SECTION

function GoWTeams:GoWHexToRGB(hex)
    hex = hex:gsub("#", "");
    if #hex == 6 then
        local r = tonumber("0x" .. hex:sub(1, 2)) / 255;
        local g = tonumber("0x" .. hex:sub(3, 4)) / 255;
        local b = tonumber("0x" .. hex:sub(5, 6)) / 255;
        return r, g, b;
    else
        return 1, 1, 1;
    end
end

function GoWTeams:SetBackdrop()
    local frame = GoWTeamTabContainer.frame;

    -- Apply BackdropTemplateMixin to allow SetBackdrop()
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin);
    end

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    });

    frame:SetBackdropColor(0, 0, 0, 1);
    frame:SetBackdropBorderColor(1, 1, 1, 1);
end

function GoWTeams:BuildTeamMemberSet(teamData)
    local teamMembers = {};
    for _, member in ipairs(teamData.members or {}) do
        local fullName = member.name .. "-" .. member.realmNormalized;
        teamMembers[fullName] = true;
    end
    return teamMembers;
end

function GoWTeams:GetNormalizedFullName(name)
    local shortName, realm = strsplit("-", name);
    realm = realm or GetNormalizedRealmName();
    return shortName .. "-" .. realm;
end

function GoWTeams:StripTag(note, tag)
    -- Remove any instance of this tag with or without brackets
    local pattern = "%s*%[?" .. tag:gsub("([%-%.%+%*%?%[%]%^%$%%])", "%%%1") .. "%]?%s*";
    return (note or ""):gsub(pattern, " "):gsub("^%s*(.-)%s*$", "%1");
end

function GoWTeams:SyncOfficerNotes(teamData)
    if not teamData or not teamData.id or not teamData.members then
        GOW.Logger:PrintErrorMessage("Invalid teamData passed to SyncOfficerNotes.");
        return;
    end

    if not GoWTeams:CanEditOfficerNote() then
        GOW.Logger:PrintErrorMessage("You do not have permission to edit officer notes.");
        return;
    end

    local guildKey = GOW.Core:GetGuildKey();
    if not guildKey or not GOW.DB.profile.guilds[guildKey] then
        GOW.Logger:PrintErrorMessage("No valid guild profile found.");
        return;
    end

    local cachedRoster = GOW.DB.profile.guilds[guildKey].roster;
    if not cachedRoster or not next(cachedRoster) then
        GOW.Logger:PrintErrorMessage("Cached roster is missing or empty. Refresh the addon first.");
        return;
    end

    local tag = "GoW:" .. tostring(teamData.id);
    local teamMembers = GoWTeams:BuildTeamMemberSet(teamData);
    local numGuildMembers = GetNumGuildMembers();
    local officerNoteLength = 31; -- Maximum length for officer notes

    for name, data in pairs(cachedRoster) do
        local fullName = GoWTeams:GetNormalizedFullName(name);
        local currentNote = data.officerNote or "";
        local newNote = currentNote;

        local tagExists = currentNote:find(tag:gsub("([%-%.%+%*%?%[%]%^%$%%])", "%%%1"), 1, true) ~= nil;

        if teamMembers[fullName] then
            if not tagExists then
                local separator = currentNote ~= "" and " " or "";
                local tagWithSeparator = separator .. tag;

                if (string.len(currentNote) + string.len(tagWithSeparator) > officerNoteLength) then
                    GOW.Logger:PrintMessage("Unable to update " .. fullName .. ": Note exceeds maximum length when attempting to add tag for team " .. "|cFFFFFFFF" .. teamData.name .. "|r.");
                    newNote = currentNote; -- Keep the original note if it exceeds length
                else
                    newNote = currentNote .. tagWithSeparator;
                end
            end
        else
            if tagExists then
                newNote = GoWTeams:StripTag(currentNote, tag);
            end
        end

        newNote = newNote:gsub("^%s*(.-)%s*$", "%1");

        if newNote ~= currentNote then
            -- Find the actual live index to apply the change
            for i = 1, numGuildMembers do
                local liveName = GetGuildRosterInfo(i);
                if GoWTeams:GetNormalizedFullName(liveName) == fullName then
                    GuildRosterSetOfficerNote(i, newNote);
                    if (not GOW.DB.profile.reduceEventNotifications) then
                        GOW.Logger:PrintMessage("Updated " .. fullName .. ": " .. newNote);
                    end
                    break;
                end
            end
        end
    end
end

function GoWTeams:CanEditOfficerNote()
    local GetAddOnMetadataFunc = CanEditOfficerNote or (C_GuildInfo and C_GuildInfo.CanEditOfficerNote);

    if GetAddOnMetadataFunc then
        return GetAddOnMetadataFunc();
    end

    return true;
end
