GoWEventDetails = {}
GoWEventDetails.__index = GoWEventDetails

local GOW = GuildsOfWow or {};
local FRAME_NAME = _G.FRAME_NAME;
local roles = (GOW.Helper and GOW.Helper:GetRoles()) or {};
local LibQTip = LibStub("LibQTip-1.0");

local eventInviteRolesForFilter = {
    ["All"] = "All",
    ["Tank"] = "Tank",
    ["Healer"] = "Healer",
    ["DPS"] = "DPS"
};

local EVENT_ROW_HEIGHT = 68;
local EVENT_LIST_TOP_PADDING = 8;
local EVENT_DETAIL_PANEL_HEIGHT = 470;
local EVENT_DETAIL_LEFT_WIDTH = 220;
local EVENT_DETAIL_RIGHT_WIDTH = 740;
local EVENT_DETAIL_FILTER_ROW_HEIGHT = 32;
local EVENT_DETAIL_ROSTER_ROW_HEIGHT = 38;

local InviteStatuses = {
    {
        EnumCalendarStatus = Enum.CalendarStatus.Available,
        Name = "Attending",
        IsEligibleToAttend = true,
        Color = { r = 0.1, g = 1, b = 0.1 }
    },
    {
        EnumCalendarStatus = Enum.CalendarStatus.Confirmed,
        Name = "Confirmed",
        IsEligibleToAttend = true,
        Color = { r = 0.1, g = 1, b = 0.1 }
    },
    {
        EnumCalendarStatus = Enum.CalendarStatus.Tentative,
        Name = "Tentative",
        IsEligibleToAttend = true,
        Color = { r = 1, g = 0.82, b = 0.2 }
    },
    {
        EnumCalendarStatus = Enum.CalendarStatus.Standby,
        Name = "Benched/Standby",
        IsEligibleToAttend = true,
        Color = { r = 0.3, g = 0.9, b = 1 }
    },
    {
        EnumCalendarStatus = Enum.CalendarStatus.Signedup,
        Name = "Signed Up",
        IsEligibleToAttend = true,
        Color = { r = 0.1, g = 1, b = 0.1 }
    },
    {
        EnumCalendarStatus = Enum.CalendarStatus.Invited,
        Name = "Awaiting Response",
        IsEligibleToAttend = true,
        Color = { r = 0.3, g = 0.9, b = 1 }
    },
    {
        EnumCalendarStatus = Enum.CalendarStatus.NotSignedup,
        Name = "Not Signed Up",
        IsEligibleToAttend = false,
        Color = { r = 1, g = 0.2, b = 0.2 }
    },
    {
        EnumCalendarStatus = Enum.CalendarStatus.Declined,
        Name = "Declined",
        IsEligibleToAttend = false,
        Color = { r = 1, g = 0.2, b = 0.2 }
    },
    {
        EnumCalendarStatus = Enum.CalendarStatus.Out,
        Name = "Out",
        IsEligibleToAttend = false,
        Color = { r = 1, g = 0.2, b = 0.2 }
    }
};

local InviteStatusesByEnum = {};
for _, status in ipairs(InviteStatuses) do
    InviteStatusesByEnum[status.EnumCalendarStatus] = status;
end

function GoWEventDetails:new(core, ui, gui)
    local self = setmetatable({}, GoWEventDetails);
    self.CORE = core;
    self.UI = ui;
    self.GUI = gui;
    self.rootHost = nil;
    self.nativeRoot = nil;
    self.listPanel = nil;
    self.eventRowCount = 0;
    self.eventInviteDialog = nil;
    self.eventInviteRoot = nil;
    self.eventInviteActiveEvent = nil;
    self.eventInviteCurrentRoleFilter = "All";
    self.eventInvitePendingMembers = {};
    return self;
end

function GoWEventDetails:Hide()
    if (self.nativeRoot) then
        self.nativeRoot:Hide();
        self.nativeRoot:SetParent(nil);
        self.nativeRoot = nil;
    end

    self.rootHost = nil;
    self.listPanel = nil;
    self.eventRowCount = 0;
end

function GoWEventDetails:UpdatePanelScroll(panel, contentHeight)
    if (not panel or not panel.scrollFrame) then
        return;
    end

    panel.scrollFrame.contentHeight = contentHeight or 0;
    panel.scrollFrame:SetVerticalScroll(0);
    if (panel.UpdateScrollBar) then
        panel:UpdateScrollBar();
    end
end

function GoWEventDetails:EnsureListPanel()
    if (self.listPanel and self.nativeRoot and self.rootHost) then
        return;
    end

    local containerScrollFrame = self.UI.containerScrollFrame;
    local L = GOW.Layout;

    self.rootHost = self.GUI:Create("SimpleGroup");
    self.rootHost:SetFullWidth(true);
    self.rootHost:SetFullHeight(true);
    containerScrollFrame:AddChild(self.rootHost);

    local hostFrame = self.rootHost.frame;
    self.nativeRoot = CreateFrame("Frame", nil, hostFrame);
    self.nativeRoot:SetAllPoints(hostFrame);

    local panelHeight = math.max(430, math.floor((hostFrame:GetHeight() > 0 and hostFrame:GetHeight() or 440) - 6));
    local panelWidth = math.max(880, math.floor(hostFrame:GetWidth() > 0 and hostFrame:GetWidth() or 946));
    self.listPanel = L:GetContainerPanel(self.nativeRoot, {
        title = "EVENTS",
        width = panelWidth,
        height = panelHeight,
        xOffset = 0,
        topInset = 28,
        sideInset = 10,
        bottomInset = 10,
    });
    self.listPanel:SetPoint("TOPLEFT", self.nativeRoot, "TOPLEFT", 0, -3);
    self.eventRowCount = 0;
end

function GoWEventDetails:GetAudienceText(event)
    if (event.calendarType == GOW.consts.GUILD_EVENT) then
        if (event.isEventMember) then
            return "All guildies";
        end

        return "All guildies, not eligible";
    end

    local totalMembers = event.totalMembers or 0;
    local text = tostring(totalMembers) .. ((totalMembers == 1) and " member" or " members");
    if (not event.isEventMember) then
        text = text .. ", not eligible";
    end

    return text;
end

function GoWEventDetails:RenderEmptyState(message, secondaryMessage, displayReloadButton)
    self:Hide();
    self.UI.containerScrollFrame:ReleaseChildren();
    local state = GOW.Layout:RenderWarningState(self.GUI, self.UI.containerScrollFrame, "EVENTS", message, secondaryMessage, displayReloadButton == true);
    self.rootHost = state.rootHost;
    self.nativeRoot = state.nativeRoot;
    self.listPanel = state.panel;
    self.eventRowCount = 0;
end

function GoWEventDetails:AppendEvent(event)
    if (not event) then
        return false;
    end

    self:EnsureListPanel();

    local L = GOW.Layout;
    local index = (self.eventRowCount or 0) + 1;
    local row = CreateFrame("Frame", nil, self.listPanel.scrollChild, "BackdropTemplate");
    row:SetHeight(EVENT_ROW_HEIGHT);
    row:SetPoint("TOPLEFT", self.listPanel.scrollChild, "TOPLEFT", 0, -(EVENT_LIST_TOP_PADDING + ((index - 1) * EVENT_ROW_HEIGHT)));
    row:SetPoint("TOPRIGHT", self.listPanel.scrollChild, "TOPRIGHT", 0, -(EVENT_LIST_TOP_PADDING + ((index - 1) * EVENT_ROW_HEIGHT)));

    row.highlight = L:CreateRowHighlight(row, 0.06);
    row.separator = L:CreateRowSeparator(row);
    L:ApplyBackdrop(row, 0, 0, 0, 0, 0, 0, 0, 0);

    row:SetScript("OnEnter", function(selfFrame)
        selfFrame.highlight:Show();
    end);
    row:SetScript("OnLeave", function(selfFrame)
        selfFrame.highlight:Hide();
    end);

    local canAddEvent = event.isEventManager and GOW.Helper:IsInGameCalendarAccessible();
    local eventIndex = select(1, self.CORE:searchForEvent(event));
    local hasInviteAction = event.isEventManager and event.eventEndDate >= C_DateAndTime.GetServerTimeLocal();

    local actionWidth = 0;
    local actions = {};

    table.insert(actions, {
        text = "Copy Link",
        width = 90,
        isActive = true,
        onClick = function()
            GOW.Layout:ShowCopyUrlDialog(self.GUI, event.webUrl, "Event URL");
        end
    });
    actionWidth = actionWidth + 90;

    if (canAddEvent and eventIndex < 0) then
        table.insert(actions, {
            text = "Copy Key",
            width = 90,
            isActive = true,
            onClick = function()
                self.CORE:OpenDialogWithData("COPY_TEXT", nil, nil, event.eventKey);
            end
        });
        actionWidth = actionWidth + 98;
    end

    if (hasInviteAction) then
        table.insert(actions, {
            text = "Invite Attendees",
            width = 120,
            isActive = true,
            onClick = function()
                if (eventIndex > 0) then
                    self.CORE:OpenDialog("INVITE_TO_PARTY_USE_CALENDAR");
                else
                    self:OpenEventAttendeesInviteDialog(event);
                end
            end
        });
        actionWidth = actionWidth + 128;
    end

    if (canAddEvent) then
        local createButtonText = "Create Event";
        local createButtonActive = true;
        local createButtonClick = function()
            self.CORE:CreateCalendarEvent(event);
        end

        if (eventIndex == 0) then
            createButtonText = "Event Passed";
            createButtonActive = false;
            createButtonClick = nil;
        elseif (eventIndex > 0) then
            createButtonText = "Event Created";
            createButtonActive = false;
            createButtonClick = nil;
        end

        table.insert(actions, {
            text = createButtonText,
            width = 104,
            isActive = createButtonActive,
            onClick = createButtonClick
        });
        actionWidth = actionWidth + 112;
    end

    local buttonRight = -10;
    for _, action in ipairs(actions) do
        local button = L:CreateActionButton(row, action);
        button:SetPoint("TOPRIGHT", row, "TOPRIGHT", buttonRight, -8);
        buttonRight = buttonRight - action.width - 8;
    end

    local rightInset = math.max(180, actionWidth + 24);

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8);
    nameText:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);
    nameText:SetText(event.title or "");

    local detailAnchor = CreateFrame("Frame", nil, row);
    detailAnchor:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4);
    detailAnchor:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0);
    detailAnchor:SetHeight(18);

    local calendarBadge = L:CreateTextBadge(detailAnchor, {
        text = (event.calendarType == GOW.consts.GUILD_EVENT) and "Guild Event" or "Player Event",
        minWidth = 36,
        paddingX = 10,
    });
    calendarBadge:SetPoint("LEFT", detailAnchor, "LEFT", 0, 0);
    calendarBadge:EnableMouse(true);
    calendarBadge:SetScript("OnEnter", function(selfFrame)
        local tooltip = LibQTip:Acquire("EventCalendarTypeTooltip", 1, "LEFT");
        GOW.tooltip = tooltip;

        tooltip:AddHeader("|cffffcc00About Event Attendances");
        local line = tooltip:AddLine();
        tooltip:SetCell(line, 1, "When no filter is selected in-game addon will create 'Guild Event' and all guildies will be able to sign up. This selection is suitable for large meetings. Site attendance data will not migrate to in-game with this selection but will migrate from game to GoW.\r\n\r\nWhen filtration is enabled or audience is set to team event, addon will create 'Player Event' and will only invite eligible characters. Attendance synchronization will work bidirectional. Player events cannot invite more than 100 members so you should narrow the audience by item level or change audience to team event.", "LEFT", 1, nil, 0, 0, 300, 50);
        tooltip:SmartAnchorTo(selfFrame);
        tooltip:Show();
    end);
    calendarBadge:SetScript("OnLeave", function()
        LibQTip:Release(GOW.tooltip);
        GOW.tooltip = nil;
    end);

    local metaText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    metaText:SetPoint("LEFT", calendarBadge, "RIGHT", 8, 0);
    metaText:SetPoint("RIGHT", detailAnchor, "RIGHT", 0, 0);
    metaText:SetJustifyH("LEFT");
    metaText:SetWordWrap(false);

    local metaParts = {
        (event.dateText or "") .. ((event.hourText and event.hourText ~= "") and (", " .. event.hourText) or ""),
        event.durationText or "",
        self:GetAudienceText(event)
    };
    if (event.team and event.team ~= "") then
        table.insert(metaParts, event.team);
    end
    metaText:SetText("|cffaaaaaa" .. table.concat(metaParts, "  •  ") .. "|r");

    local description = event.description;
    if (description and description ~= "") then
        local descriptionText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        descriptionText:SetPoint("TOPLEFT", detailAnchor, "BOTTOMLEFT", 0, -6);
        descriptionText:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0);
        descriptionText:SetJustifyH("LEFT");
        descriptionText:SetWordWrap(false);
        descriptionText:SetText("|cff888888" .. description .. "|r");
    end

    self.eventRowCount = index;
    self.listPanel.scrollChild:SetHeight(EVENT_LIST_TOP_PADDING + (index * EVENT_ROW_HEIGHT));
    self:UpdatePanelScroll(self.listPanel, EVENT_LIST_TOP_PADDING + (index * EVENT_ROW_HEIGHT));
    return true;
end

function GoWEventDetails:NormalizeCharacterKey(characterName)
    if (characterName == nil) then
        return "";
    end

    return string.lower(string.gsub(characterName, "[^%w]", ""));
end
function GoWEventDetails:GetInviteStatusInfo(inviteStatus)
    if (inviteStatus == nil) then
        return nil;
    end

    return InviteStatusesByEnum[inviteStatus];
end

function GoWEventDetails:GetCharacterKeyFromUnit(unit)
    local name, realm = UnitFullName(unit);
    if (not name) then
        return nil;
    end

    if (realm == nil or realm == "") then
        realm = GetNormalizedRealmName();
    end

    return name .. "-" .. realm;
end

function GoWEventDetails:IsMemberInCurrentGroup(memberKey)
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

function GoWEventDetails:GetGuildOnlineMemberMap()
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

function GoWEventDetails:ShouldInviteRole(roleName, roleFilter)
    if (roleFilter == nil or roleFilter == "All") then
        return true;
    end

    return roleName == roleFilter;
end

function GoWEventDetails:BuildEventInviteRows(event, roleFilter)
    local me = GOW.Helper:GetCurrentCharacterUniqueKey();
    local onlineMap = self:GetGuildOnlineMemberMap();
    local inviteRows = {};
    local inviteMembers = event.inviteMembers or {};
    local maxMembers = event.totalMembers or #inviteMembers;

    for i = 1, maxMembers do
        local currentInviteMember = inviteMembers[i];
        if (currentInviteMember) then
            local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized;
            local roleData = GOW.Helper:GetRole(currentInviteMember.specRoleId);
            local roleName = (roleData and roleData.name) or "Unknown";
            local isSelf = (inviteName == me);
            local isOnline = onlineMap[self:NormalizeCharacterKey(inviteName)] or onlineMap[self:NormalizeCharacterKey(currentInviteMember.name)] or false;
            local inviteStatusInfo = self:GetInviteStatusInfo(currentInviteMember.inviteStatus);
            local isAttendanceEligible = (currentInviteMember.specRoleId > 0 and inviteStatusInfo and inviteStatusInfo.IsEligibleToAttend == true) or false;
            local isInGroup = self:IsMemberInCurrentGroup(inviteName);
            local isInvitePending = self.eventInvitePendingMembers[inviteName] == true;
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

            if (self:ShouldInviteRole(roleName, roleFilter)) then
                table.insert(inviteRows, {
                    inviteName = inviteName,
                    name = currentInviteMember.name,
                    realm = currentInviteMember.realm,
                    classId = currentInviteMember.classId,
                    className = currentInviteMember.class,
                    faction = currentInviteMember.faction,
                    roleName = roleName,
                    roleId = currentInviteMember.specRoleId,
                    specName = currentInviteMember.spec,
                    inviteStatusInfo = inviteStatusInfo,
                    buttonText = buttonText,
                    canInvite = (not isSelf and isAttendanceEligible and not isInGroup and not isInvitePending)
                });
            end
        end
    end
    table.sort(inviteRows, function(a, b)
        return string.lower(a.name or "") < string.lower(b.name or "");
    end);

    return inviteRows;
end

function GoWEventDetails:GetInvitableMemberNames(rows)
    local inviteNames = {};

    for _, row in ipairs(rows) do
        if (row.canInvite) then
            table.insert(inviteNames, row.inviteName);
        end
    end

    return inviteNames;
end

function GoWEventDetails:DestroyEventInviteRoot()
    if (self.eventInviteRoot) then
        self.eventInviteRoot:Hide();
        self.eventInviteRoot:SetParent(nil);
        self.eventInviteRoot = nil;
    end
end

function GoWEventDetails:BuildEventInviteFilters(event)
    local counts = {
        All = 0,
        Tank = 0,
        Healer = 0,
        DPS = 0,
    };

    for _, row in ipairs(self:BuildEventInviteRows(event, "All")) do
        counts.All = counts.All + 1;
        if (counts[row.roleName] ~= nil) then
            counts[row.roleName] = counts[row.roleName] + 1;
        end
    end

    return {
        { key = "All", label = "All Roles", count = counts.All },
        { key = "Tank", label = "Tank", count = counts.Tank },
        { key = "Healer", label = "Healer", count = counts.Healer },
        { key = "DPS", label = "DPS", count = counts.DPS },
    };
end

function GoWEventDetails:CreateEventInviteButton(parent, row)
    local L = GOW.Layout;
    return L:CreateActionButton(parent, {
        text = row.canInvite and "Invite" or row.buttonText,
        width = 76,
        isActive = row.canInvite,
        onClick = function()
            GOW.Helper:InviteToParty(row.inviteName);
            self.eventInvitePendingMembers[row.inviteName] = true;
            self:RenderEventInviteRows();

            C_Timer.After(60, function()
                self.eventInvitePendingMembers[row.inviteName] = nil;
                if (self.eventInviteDialog and self.eventInviteDialog:IsShown()) then
                    self:RenderEventInviteRows();
                end
            end);
        end
    });
end

function GoWEventDetails:CreateEventInviteRow(parent, row, index, total)
    local L = GOW.Layout;
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    frame:SetHeight(EVENT_DETAIL_ROSTER_ROW_HEIGHT);
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * EVENT_DETAIL_ROSTER_ROW_HEIGHT));
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * EVENT_DETAIL_ROSTER_ROW_HEIGHT));

    frame.highlight = L:CreateRowHighlight(frame, 0.04);
    frame.separator = L:CreateRowSeparator(frame);

    frame.factionIcon = frame:CreateTexture(nil, "ARTWORK");
    frame.factionIcon:SetSize(16, 16);
    frame.factionIcon:SetPoint("LEFT", frame, "LEFT", 10, 0);
    frame.factionIcon:SetTexture(GOW.Helper:GetFactionIcon(row.faction));

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    nameText:SetPoint("LEFT", frame.factionIcon, "RIGHT", 8, 0);
    nameText:SetWidth(135);
    nameText:SetJustifyH("LEFT");
    nameText:SetWordWrap(false);

    local _, classFile = GetClassInfo(row.classId or 0);
    local classColor = GOW.Helper:GetClassColor(classFile);
    if (classColor) then
        nameText:SetText(string.format("|cff%02x%02x%02x%s|r", classColor.r * 255, classColor.g * 255, classColor.b * 255, row.name or ""));
    else
        nameText:SetText(row.name or "");
    end

    local realmText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    realmText:SetPoint("LEFT", frame, "LEFT", 170, 0);
    realmText:SetWidth(130);
    realmText:SetJustifyH("LEFT");
    realmText:SetWordWrap(false);
    realmText:SetText("|cffaaaaaa" .. (row.realm or "") .. "|r");

    local classText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    classText:SetPoint("LEFT", frame, "LEFT", 300, 0);
    classText:SetWidth(100);
    classText:SetJustifyH("LEFT");
    classText:SetWordWrap(false);
    classText:SetText("|cffdddddd" .. (row.className or (GetClassInfo(row.classId or 0) or "Unknown")) .. "|r");

    local roleContainer = CreateFrame("Frame", nil, frame);
    roleContainer:SetPoint("LEFT", frame, "LEFT", 405, 0);
    roleContainer:SetSize(120, 18);

    local roleData = roles[row.roleId];
    if (roleData and roleData.iconTexCoords) then
        local roleIcon = roleContainer:CreateTexture(nil, "ARTWORK");
        roleIcon:SetTexture("Interface/LFGFrame/UI-LFG-ICON-PORTRAITROLES");
        roleIcon:SetSize(16, 16);
        roleIcon:SetPoint("LEFT", roleContainer, "LEFT", 0, 0);
        roleIcon:SetTexCoord(unpack(roleData.iconTexCoords));
    end

    local specText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    specText:SetPoint("LEFT", roleContainer, "LEFT", 20, 0);
    specText:SetWidth(100);
    specText:SetJustifyH("LEFT");
    specText:SetWordWrap(false);
    specText:SetText(row.specName or row.roleName or "");

    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    statusText:SetPoint("LEFT", frame, "LEFT", 535, 0);
    statusText:SetWidth(125);
    statusText:SetJustifyH("LEFT");
    statusText:SetWordWrap(false);
    statusText:SetText((row.inviteStatusInfo and row.inviteStatusInfo.Name) or "Unknown");
    if (row.inviteStatusInfo and row.inviteStatusInfo.Color) then
        statusText:SetTextColor(row.inviteStatusInfo.Color.r, row.inviteStatusInfo.Color.g, row.inviteStatusInfo.Color.b);
    end

    frame.inviteButton = self:CreateEventInviteButton(frame, row);
    frame.inviteButton:SetPoint("RIGHT", frame, "RIGHT", -6, 0);

    if (index == total) then
        frame.separator:Hide();
    end

    return frame;
end

function GoWEventDetails:RenderEventInviteRows()
    if (self.eventInviteDialog == nil or self.eventInviteActiveEvent == nil) then
        return;
    end

    local L = GOW.Layout;
    local windowFrame = self.eventInviteDialog.frame;
    local currentEvent = self.eventInviteActiveEvent;
    local currentRows = self:BuildEventInviteRows(currentEvent, self.eventInviteCurrentRoleFilter);
    local inviteAllMembers = self:GetInvitableMemberNames(currentRows);
    local filters = self:BuildEventInviteFilters(currentEvent);

    self:DestroyEventInviteRoot();

    local nativeRoot = CreateFrame("Frame", nil, windowFrame);
    nativeRoot:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 12, -32);
    nativeRoot:SetPoint("BOTTOMRIGHT", windowFrame, "BOTTOMRIGHT", -12, 12);
    self.eventInviteRoot = nativeRoot;

    local leftPanel = L:GetContainerPanel(nativeRoot, {
        title = "ROLES",
        width = EVENT_DETAIL_LEFT_WIDTH,
        height = EVENT_DETAIL_PANEL_HEIGHT,
        xOffset = 0,
        topInset = 34,
        sideInset = 8,
        bottomInset = 8,
    });
    leftPanel:SetPoint("TOPLEFT", nativeRoot, "TOPLEFT", 6, -6);

    local rightPanel = L:GetContainerPanel(nativeRoot, {
        title = "ATTENDANCE",
        width = EVENT_DETAIL_RIGHT_WIDTH,
        height = EVENT_DETAIL_PANEL_HEIGHT,
        xOffset = EVENT_DETAIL_LEFT_WIDTH + 12,
        topInset = 66,
        sideInset = 8,
        bottomInset = 8,
    });
    rightPanel:SetPoint("TOPLEFT", nativeRoot, "TOPLEFT", EVENT_DETAIL_LEFT_WIDTH + 12, -6);

    local inviteAllButton = L:CreateActionButton(rightPanel, {
        text = "Invite Members",
        width = 120,
        isActive = #inviteAllMembers > 0,
        onClick = function()
            if (#inviteAllMembers > 0) then
                self.CORE:OpenDialogWithData("CONFIRM_INVITE_TO_PARTY", #inviteAllMembers, nil, { inviteNames = inviteAllMembers });
            else
                self.CORE:OpenDialog("INVITE_TO_PARTY_NOONE_FOUND");
            end
        end
    });
    inviteAllButton:SetPoint("RIGHT", rightPanel.headerBar, "RIGHT", 0, 0);

    local sidebar = L:CreateSidebarList(leftPanel.scrollChild, {
        rowHeight = EVENT_DETAIL_FILTER_ROW_HEIGHT,
        getLabel = function(item) return item.label end,
        getMeta = function(item) return tostring(item.count or 0) end,
        isSelected = function(item) return item.key == self.eventInviteCurrentRoleFilter end,
        isEnabled = function(item) return item.key == "All" or (item.count or 0) > 0 end,
        isAccent = function(item) return item.key == "All" end,
        onSelect = function(item)
            self.eventInviteCurrentRoleFilter = item.key;
            self:RenderEventInviteRows();
        end,
    });
    local leftHeight = math.max(sidebar:Render(filters), 1);
    leftPanel.scrollChild:SetHeight(leftHeight);
    self:UpdatePanelScroll(leftPanel, leftHeight);

    local summaryFrame = CreateFrame("Frame", nil, rightPanel);
    summaryFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 10, -30);
    summaryFrame:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -10, -30);
    summaryFrame:SetHeight(28);

    local audienceBadge = L:CreateTextBadge(summaryFrame, {
        text = self:GetAudienceText(currentEvent),
        minWidth = 32,
        paddingX = 10,
    });
    audienceBadge:SetPoint("LEFT", summaryFrame, "LEFT", 0, 0);

    local summaryText = summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    summaryText:SetPoint("LEFT", audienceBadge, "RIGHT", 8, 0);
    summaryText:SetPoint("RIGHT", summaryFrame, "RIGHT", 0, 0);
    summaryText:SetJustifyH("LEFT");
    summaryText:SetWordWrap(false);
    summaryText:SetText("|cff888888" .. (currentEvent.title or "") .. "|r");

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

    CreateHeaderLabel("Name", 34, 135);
    CreateHeaderLabel("Realm", 170, 130);
    CreateHeaderLabel("Class", 300, 100);
    CreateHeaderLabel("Role", 405, 120);
    CreateHeaderLabel("Status", 535, 125);

    local rowsAnchor = CreateFrame("Frame", nil, rightPanel.scrollChild);
    rowsAnchor:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4);
    rowsAnchor:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -4);
    rowsAnchor:SetHeight(math.max(1, #currentRows * EVENT_DETAIL_ROSTER_ROW_HEIGHT));

    if (#currentRows == 0) then
        local emptyText = rightPanel.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        emptyText:SetPoint("TOPLEFT", rowsAnchor, "TOPLEFT", 10, -10);
        emptyText:SetText("|cff888888No attendees found for this role.|r");
    else
        for index, row in ipairs(currentRows) do
            self:CreateEventInviteRow(rowsAnchor, row, index, #currentRows);
        end
    end

    local contentHeight = 22 + 4 + (#currentRows * EVENT_DETAIL_ROSTER_ROW_HEIGHT);
    if (#currentRows == 0) then
        contentHeight = 70;
    end
    rightPanel.scrollChild:SetHeight(contentHeight);
    self:UpdatePanelScroll(rightPanel, contentHeight);
end

function GoWEventDetails:SetBackdrop()
    local frame = self.eventInviteDialog and self.eventInviteDialog.frame;
    if (not frame) then
        return;
    end

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

function GoWEventDetails:OpenEventAttendeesInviteDialog(event)
    local inviteMembers = event.inviteMembers or {};
    local inviteMembersCount = event.totalMembers or #inviteMembers;

    if (inviteMembersCount <= 0) then
        self.CORE:OpenDialog("INVITE_TO_PARTY_NOONE_FOUND");
        return;
    end

    if (self.eventInviteDialog == nil) then
        self.eventInviteDialog = self.GUI:Create("Window");
        self.eventInviteDialog:SetWidth(1000);
        self.eventInviteDialog:SetHeight(550);
        self.eventInviteDialog:EnableResize(false);
        self.eventInviteDialog.frame:SetPoint("CENTER", UIParent, "CENTER", 40, -40);
        self.eventInviteDialog.frame:SetFrameStrata("HIGH");
        self.eventInviteDialog:SetLayout("Flow");
        self.eventInviteDialog.closebutton:SetPoint("TOPRIGHT", -2, -2);
        self:SetBackdrop();
        self.eventInviteDialog:SetCallback("OnClose", function()
            self:DestroyEventInviteRoot();
            self:DestroyEventInviteDialog();
        end);
    end

    self.eventInviteActiveEvent = event;
    self.eventInviteCurrentRoleFilter = "All";
    self.eventInvitePendingMembers = {};
    self.eventInviteDialog:SetTitle(event.title);
    _G[FRAME_NAME] = self.eventInviteDialog.frame;

    self:RenderEventInviteRows();
    self.eventInviteDialog:Show();
end

function GoWEventDetails:DestroyEventInviteDialog()
    if (self.eventInviteDialog) then
        self:DestroyEventInviteRoot();
        self.eventInviteDialog:ReleaseChildren();
        self.eventInviteDialog:Release();
        self.eventInviteDialog = nil;
        self.eventInviteActiveEvent = nil;
        self.eventInvitePendingMembers = {};

        if (self.UI and self.UI.containerFrame and self.UI.containerFrame.frame) then
            _G[FRAME_NAME] = self.UI.containerFrame.frame;
        end
    end
end

function GoWEventDetails:GetAttendeesToInvite(event)
    local rows = self:BuildEventInviteRows(event, "All");
    return self:GetInvitableMemberNames(rows);
end

function GoWEventDetails:InviteAllToPartyCheck(event)
    local eligibleMembers = self:GetAttendeesToInvite(event);
    local eligibleMembersCount = #eligibleMembers;

    if (eligibleMembersCount > 0) then
        self.CORE:OpenDialogWithData("CONFIRM_INVITE_TO_PARTY", eligibleMembersCount, nil, { inviteNames = eligibleMembers });
    else
        self.CORE:OpenDialog("INVITE_TO_PARTY_NOONE_FOUND");
    end
end

function GoWEventDetails:InviteAllToParty(data)
    local eligibleMembers = {};

    if (data and data.inviteNames) then
        eligibleMembers = data.inviteNames;
    else
        eligibleMembers = self:GetAttendeesToInvite(data);
    end

    for _, inviteName in ipairs(eligibleMembers) do
        GOW.Helper:InviteToParty(inviteName);
        self.eventInvitePendingMembers[inviteName] = true;
    end

    if (self.eventInviteDialog and self.eventInviteDialog:IsShown()) then
        self:RenderEventInviteRows();
    end
end


