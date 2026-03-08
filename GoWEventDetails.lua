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
    self.eventInviteDialog = nil;
    self.eventInviteActiveEvent = nil;
    self.eventInviteCurrentRoleFilter = "All";
    self.eventInvitePendingMembers = {};
    return self;
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

function GoWEventDetails:RenderEventInviteRows()
    if (self.eventInviteDialog == nil or self.eventInviteActiveEvent == nil) then
        return;
    end

    self.eventInviteDialog:ReleaseChildren();

    local controlsGroup = self.GUI:Create("SimpleGroup");
    controlsGroup:SetLayout("Flow");
    controlsGroup:SetWidth(740);
    controlsGroup:SetHeight(30);

    local roleFilter = self.GUI:Create("Dropdown");
    roleFilter:SetLabel("  Filter by Role");
    roleFilter:SetList(eventInviteRolesForFilter, { "All", "Tank", "Healer", "DPS" });
    roleFilter:SetValue(self.eventInviteCurrentRoleFilter);
    roleFilter:SetWidth(150);
    roleFilter.label:SetFontObject(GameFontNormal);
    roleFilter:SetCallback("OnValueChanged", function(widget)
        self.eventInviteCurrentRoleFilter = widget:GetValue() or "All";
        self:RenderEventInviteRows();
    end);
    controlsGroup:AddChild(roleFilter);

    local currentRows = self:BuildEventInviteRows(self.eventInviteActiveEvent, self.eventInviteCurrentRoleFilter);
    local inviteAllMembers = self:GetInvitableMemberNames(currentRows);

    local marginGap = self.GUI:Create("SimpleGroup");
    marginGap:SetLayout("Flow");
    marginGap:SetHeight(40);
    marginGap:SetWidth(5);
    controlsGroup:AddChild(marginGap);

    local inviteAllButton = self.GUI:Create("Button");
    inviteAllButton:SetText("Invite Members");
    inviteAllButton:SetWidth(150);
    inviteAllButton:SetDisabled(#inviteAllMembers == 0);
    inviteAllButton:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP");
        GameTooltip:SetText("Invite Attending and Confirmed players to your Party.", 1, 1, 1, 1, true);
        GameTooltip:Show();
    end);
    inviteAllButton:SetCallback("OnLeave", function()
        GameTooltip:Hide();
    end);
    inviteAllButton:SetCallback("OnClick", function()
        if (#inviteAllMembers > 0) then
            self.CORE:OpenDialogWithData("CONFIRM_INVITE_TO_PARTY", #inviteAllMembers, nil, { inviteNames = inviteAllMembers });
        else
            self.CORE:OpenDialog("INVITE_TO_PARTY_NOONE_FOUND");
        end
    end);
    controlsGroup:AddChild(inviteAllButton);

    self.eventInviteDialog:AddChild(controlsGroup);

    local eventRosterContainer = self.GUI:Create("InlineGroup");
    eventRosterContainer:SetFullHeight(true);
    eventRosterContainer:SetLayout("Fill");
    eventRosterContainer:SetFullWidth(true);
    self.eventInviteDialog:AddChild(eventRosterContainer);

    local rowsContainer = self.GUI:Create("ScrollFrame");
    rowsContainer:SetFullHeight(true);
    rowsContainer:SetLayout("List");
    rowsContainer:SetFullWidth(true);
    eventRosterContainer:AddChild(rowsContainer);

    local headerRow = self.GUI:Create("SimpleGroup");
    headerRow:SetLayout("Flow");
    headerRow:SetFullWidth(true);
    headerRow:SetHeight(24);
    headerRow.frame:SetFrameLevel(2);

    local headerColorR = (NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.r) or 1;
    local headerColorG = (NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.g) or 0.82;
    local headerColorB = (NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.b) or 0;

    local factionHeaderSpacer = self.GUI:Create("Label");
    factionHeaderSpacer:SetText(" ");
    factionHeaderSpacer:SetWidth(30);
    headerRow:AddChild(factionHeaderSpacer);

    local nameHeader = self.GUI:Create("Label");
    nameHeader:SetText("Name");
    nameHeader:SetWidth(160);
    nameHeader:SetFontObject(GameFontNormal);
    nameHeader:SetColor(headerColorR, headerColorG, headerColorB);
    headerRow:AddChild(nameHeader);

    local classHeader = self.GUI:Create("Label");
    classHeader:SetText("Class");
    classHeader:SetWidth(130);
    classHeader:SetFontObject(GameFontNormal);
    classHeader:SetColor(headerColorR, headerColorG, headerColorB);
    headerRow:AddChild(classHeader);

    local roleHeader = self.GUI:Create("Label");
    roleHeader:SetText("Role");
    roleHeader:SetWidth(130);
    roleHeader:SetFontObject(GameFontNormal);
    roleHeader:SetColor(headerColorR, headerColorG, headerColorB);
    headerRow:AddChild(roleHeader);

    local statusHeader = self.GUI:Create("Label");
    statusHeader:SetText("Invitation Status");
    statusHeader:SetWidth(180);
    statusHeader:SetFontObject(GameFontNormal);
    statusHeader:SetColor(headerColorR, headerColorG, headerColorB);
    headerRow:AddChild(statusHeader);

    rowsContainer:AddChild(headerRow);

    for _, row in ipairs(currentRows) do
        local memberContainer = self.GUI:Create("SimpleGroup");
        memberContainer:SetLayout("Flow");
        memberContainer:SetFullWidth(true);
        memberContainer:SetHeight(30);
        memberContainer.frame:SetFrameLevel(2);

        local factionIcon = self.GUI:Create("Label");
        if row.faction == 1 then
            factionIcon:SetImage(652156);
        else
            factionIcon:SetImage(652155);
        end;
        factionIcon:SetImageSize(30, 30);
        factionIcon:SetWidth(30);
        factionIcon:SetHeight(30);
        memberContainer:AddChild(factionIcon);

        local memberNameLabel = self.GUI:Create("Label");
        memberNameLabel:SetWidth(160);
        memberNameLabel:SetText(row.name);
        memberNameLabel:SetFontObject(GameFontNormal);

        local _, classFile = GetClassInfo(row.classId);
        if (classFile) then
            local getClassColor = GetClassColorObj or C_ClassColor.GetClassColor;
            local classColor = getClassColor(classFile);
            memberNameLabel:SetColor(classColor.r, classColor.g, classColor.b);
        end
        memberContainer:AddChild(memberNameLabel);

        local classLabel = self.GUI:Create("Label");
        classLabel:SetWidth(130);
        classLabel:SetText(row.className or (GetClassInfo(row.classId) or "Unknown"));
        classLabel:SetFontObject(GameFontNormal);
        memberContainer:AddChild(classLabel);

        local roleAndIconGroup = self.GUI:Create("SimpleGroup");
        roleAndIconGroup:SetWidth(130);
        roleAndIconGroup:SetHeight(30);
        roleAndIconGroup:SetLayout("Flow");

        local roleData = roles[row.roleId];
        local coords = roleData and roleData.iconTexCoords;
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

                tooltip:AddHeader("|cffffcc00" .. (roleData.name or row.roleName or "Role"));
                tooltip:SmartAnchorTo(self.frame);
                tooltip:Show();
            end);
            roleIcon:SetCallback("OnLeave", function()
                LibQTip:Release(GOW.tooltip);
                GOW.tooltip = nil;
            end);
            roleAndIconGroup:AddChild(roleIcon);
        end

        local specLabel = self.GUI:Create("Label");
        specLabel:SetWidth(110);
        specLabel:SetText(row.specName);
        specLabel:SetFontObject(GameFontNormal);
        roleAndIconGroup:AddChild(specLabel);

        memberContainer:AddChild(roleAndIconGroup);

        local rowIsAttendanceEligible = row.roleId > 0 and row.inviteStatusInfo and row.inviteStatusInfo.IsEligibleToAttend == true;
        local statusLabel = self.GUI:Create("Label");
        statusLabel:SetWidth(180);
        statusLabel:SetText((row.inviteStatusInfo and row.inviteStatusInfo.Name) or "Unknown");
        statusLabel:SetFontObject(GameFontNormal);
        if (row.inviteStatusInfo and row.inviteStatusInfo.Color) then
            statusLabel:SetColor(row.inviteStatusInfo.Color.r, row.inviteStatusInfo.Color.g, row.inviteStatusInfo.Color.b);
        end
        memberContainer:AddChild(statusLabel);

        if (rowIsAttendanceEligible) then
            local inviteButton = self.GUI:Create("Button");
            inviteButton:SetWidth(125);
            if (row.canInvite) then
                inviteButton:SetText("Invite");
                inviteButton:SetDisabled(false);
            else
                inviteButton:SetText(row.buttonText);
                inviteButton:SetDisabled(true);
            end

            inviteButton:SetCallback("OnClick", function()
                GOW.Helper:InviteToParty(row.inviteName);
                self.eventInvitePendingMembers[row.inviteName] = true;
                self:RenderEventInviteRows();

                C_Timer.After(60, function()
                    self.eventInvitePendingMembers[row.inviteName] = nil;
                    if (self.eventInviteDialog and self.eventInviteDialog:IsShown()) then
                        self:RenderEventInviteRows();
                    end
                end);
            end);
            memberContainer:AddChild(inviteButton);
        else
            local buttonSpacer = self.GUI:Create("Label");
            buttonSpacer:SetText("");
            buttonSpacer:SetWidth(110);
            memberContainer:AddChild(buttonSpacer);
        end

        rowsContainer:AddChild(memberContainer);
    end
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


