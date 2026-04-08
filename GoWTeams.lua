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

local buildPresenceMapCached = GOW.Helper:CreateCachedFunction(function(self)
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
end, 2);

function GoWTeams:BuildPresenceMap()
    return buildPresenceMapCached(self);
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

function GoWTeams:CanInviteTeamMember(member, presenceMap)
    local isConnected = select(1, self:GetMemberPresence(member, presenceMap));
    if (not isConnected) then
        return false;
    end

    local currentPlayer = GOW.Helper:GetCurrentCharacterUniqueKey();
    local memberFullName = member.name .. "-" .. (member.realmNormalized or GetNormalizedRealmName());
    if (memberFullName == currentPlayer) then
        return false;
    end

    if (IsInGroup()) then
        local numGroup = GetNumGroupMembers();
        local unitPrefix = IsInRaid() and "raid" or "party";
        for i = 1, numGroup do
            local unitName = UnitName(unitPrefix .. i);
            if (unitName and (unitName == memberFullName or unitName == member.name)) then
                return false;
            end
        end
    end

    return true;
end

function GoWTeams:GetInvitableTeamMembers(members, presenceMap)
    local invitableMembers = {};

    for _, member in ipairs(members or {}) do
        if (self:CanInviteTeamMember(member, presenceMap)) then
            table.insert(invitableMembers, member);
        end
    end

    return invitableMembers;
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
    local canInvite = self:CanInviteTeamMember(member, presenceMap);
    local buttonText = canInvite and "Invite" or "Offline";

    if (member.name == currentPlayerName) then
        buttonText = "You";
    elseif (IsInGroup()) then
        local memberFullName = member.name .. "-" .. (member.realmNormalized or GetNormalizedRealmName());
        for i = 1, GetNumGroupMembers() do
            local unitName = UnitName((IsInRaid() and "raid" or "party") .. i);
            if (unitName and (unitName == memberFullName or unitName == member.name)) then
                buttonText = "Joined";
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
    local invitableMembers = self:GetInvitableTeamMembers(filteredMembers, presenceMap);

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

    local inviteAllButton = L:CreateActionButton(rightPanel, {
        text = "Invite All",
        width = 78,
        isActive = #invitableMembers > 0,
        tooltip = "Invite all currently visible roster members who can be invited.",
        tooltipSubtext = "Follows the selected role filter and skips offline members, yourself, and players already in the group.",
        onClick = function()
            self.CORE:InviteAllTeamMembersToPartyCheck({
                members = invitableMembers,
                totalMembers = #invitableMembers,
            });
        end
    });
    inviteAllButton:SetPoint("RIGHT", rightPanel.headerBar, "RIGHT", 0, 0);

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
end

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

    local rosterIndexMap = {};
    for i = 1, numGuildMembers do
        local liveName = GetGuildRosterInfo(i);
        if (liveName) then
            rosterIndexMap[GoWTeams:GetNormalizedFullName(liveName)] = i;
        end
    end

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
            local rosterIndex = rosterIndexMap[fullName];
            if rosterIndex then
                local verifyName = GetGuildRosterInfo(rosterIndex);
                if not verifyName or GoWTeams:GetNormalizedFullName(verifyName) ~= fullName then
                    rosterIndex = nil;
                    for i = 1, numGuildMembers do
                        local liveName = GetGuildRosterInfo(i);
                        if liveName and GoWTeams:GetNormalizedFullName(liveName) == fullName then
                            rosterIndex = i;
                            break;
                        end
                    end
                end
            end

            if rosterIndex then
                GuildRosterSetOfficerNote(rosterIndex, newNote);
                if (not GOW.DB.profile.reduceEventNotifications) then
                    GOW.Logger:PrintMessage("Updated " .. fullName .. ": " .. newNote);
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
