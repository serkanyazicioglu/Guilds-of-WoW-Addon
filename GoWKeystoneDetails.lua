GoWKeystoneDetails = {}
GoWKeystoneDetails.__index = GoWKeystoneDetails

local GOW = GuildsOfWow or {};

function GoWKeystoneDetails:new(core, ui, gui)
    local self = setmetatable({}, GoWKeystoneDetails);
    self.CORE = core;
    self.UI = ui;
    self.GUI = gui;
    self.pendingMembers = {};
    return self;
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

function GoWKeystoneDetails:GetInvitableNames(rows)
    local inviteNames = {};

    for _, row in ipairs(rows) do
        if (row.canInvite) then
            table.insert(inviteNames, row.inviteName);
        end
    end

    return inviteNames;
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
            keystoneLevel = entry.keystoneLevel,
            dungeonName = entry.dungeonName,
            canInvite = (not isSelf and isOnline and not isInGroup and not isInvitePending),
            buttonText = buttonText
        });
    end

    return rows;
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

function GoWKeystoneDetails:Render()
    local containerScrollFrame = self.UI.containerScrollFrame;
    containerScrollFrame:ReleaseChildren();

    local controlsGroup = self.GUI:Create("SimpleGroup");
    controlsGroup:SetLayout("Flow");
    controlsGroup:SetFullWidth(true);
    controlsGroup:SetHeight(30);

    local rows = self:BuildRows();
    local inviteAllMembers = self:GetInvitableNames(rows);
    local refreshButton = self.GUI:Create("Button");
    refreshButton:SetText("Refresh");
    refreshButton:SetWidth(120);
    refreshButton:SetCallback("OnClick", function()
        GOW.Keystones:Refresh();
        self:Render();
    end);
    controlsGroup:AddChild(refreshButton);

    local controlsSpacer = self.GUI:Create("SimpleGroup");
    controlsSpacer:SetLayout("Flow");
    controlsSpacer:SetWidth(10);
    controlsSpacer:SetHeight(30);
    controlsGroup:AddChild(controlsSpacer);

    local inviteAllButton = self.GUI:Create("Button");
    inviteAllButton:SetText("Invite Members");
    inviteAllButton:SetWidth(150);
    inviteAllButton:SetDisabled(#inviteAllMembers == 0);
    inviteAllButton:SetCallback("OnClick", function()
        if (#inviteAllMembers == 0) then
            self.CORE:OpenDialog("INVITE_TO_PARTY_NOONE_FOUND");
            return;
        end

        for _, inviteName in ipairs(inviteAllMembers) do
            self:InviteName(inviteName);
        end
        self:Render();
    end);
    controlsGroup:AddChild(inviteAllButton);
    containerScrollFrame:AddChild(controlsGroup);

    if (#rows == 0) then
        self.CORE:AppendMessage("No keystones found for this guild yet.", false);
        self.CORE:AppendScrollBottomPadding();
        return;
    end

    local listContainer = self.GUI:Create("InlineGroup");
    listContainer:SetTitle("Guild Keystones");
    listContainer:SetFullWidth(true);
    listContainer:SetLayout("List");
    containerScrollFrame:AddChild(listContainer);

    local headerRow = self.GUI:Create("SimpleGroup");
    headerRow:SetLayout("Flow");
    headerRow:SetFullWidth(true);
    headerRow:SetHeight(24);

    local function MakeHeader(text, width)
        local header = self.GUI:Create("Label");
        header:SetText(text);
        header:SetWidth(width);
        header:SetFontObject(GameFontNormal);
        return header;
    end

    headerRow:AddChild(MakeHeader("Name", 240));
    headerRow:AddChild(MakeHeader("Level", 80));
    headerRow:AddChild(MakeHeader("Dungeon", 350));
    headerRow:AddChild(MakeHeader("", 125));
    listContainer:AddChild(headerRow);

    for _, row in ipairs(rows) do
        local memberRow = self.GUI:Create("SimpleGroup");
        memberRow:SetLayout("Flow");
        memberRow:SetFullWidth(true);
        memberRow:SetHeight(30);

        local nameLabel = self.GUI:Create("Label");
        nameLabel:SetText(row.name or "");
        nameLabel:SetWidth(240);
        nameLabel:SetFontObject(GameFontNormal);
        memberRow:AddChild(nameLabel);

        local levelLabel = self.GUI:Create("Label");
        levelLabel:SetText(tostring(row.keystoneLevel or ""));
        levelLabel:SetWidth(80);
        levelLabel:SetFontObject(GameFontNormal);
        memberRow:AddChild(levelLabel);

        local dungeonLabel = self.GUI:Create("Label");
        dungeonLabel:SetText(row.dungeonName or "");
        dungeonLabel:SetWidth(350);
        dungeonLabel:SetFontObject(GameFontNormal);
        memberRow:AddChild(dungeonLabel);

        local inviteButton = self.GUI:Create("Button");
        inviteButton:SetWidth(125);
        inviteButton:SetText(row.canInvite and "Invite" or row.buttonText);
        inviteButton:SetDisabled(not row.canInvite);
        inviteButton:SetCallback("OnClick", function()
            self:InviteName(row.inviteName);
            self:Render();
        end);
        memberRow:AddChild(inviteButton);

        listContainer:AddChild(memberRow);
    end

    self.CORE:AppendScrollBottomPadding();
end
