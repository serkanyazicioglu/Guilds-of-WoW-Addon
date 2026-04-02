GoWRecruitmentDetails = {}
GoWRecruitmentDetails.__index = GoWRecruitmentDetails

local GOW = GuildsOfWow or {};

local PANEL_HEIGHT = 430;
local LEFT_PANEL_WIDTH = 260;
local RIGHT_PANEL_WIDTH = 680;
local HEADER_HEIGHT = 24;
local LEFT_ROW_HEIGHT = 32;

function GoWRecruitmentDetails:new(core, ui, gui)
    local self = setmetatable({}, GoWRecruitmentDetails);
    self.CORE = core;
    self.UI = ui;
    self.GUI = gui;
    self.selectedApplicationIndex = 1;
    self.nativeRoot = nil;
    self.filteredApplications = {};
    self.guildRoster = nil;
    return self;
end

function GoWRecruitmentDetails:Hide()
    if (self.nativeRoot) then
        self.nativeRoot:Hide();
        self.nativeRoot:SetParent(nil);
        self.nativeRoot = nil;
    end
end

function GoWRecruitmentDetails:UpdatePanelScroll(panel, contentHeight)
    if (not panel or not panel.scrollFrame) then
        return;
    end

    panel.scrollFrame.contentHeight = contentHeight or 0;
    panel.scrollFrame:SetVerticalScroll(0);
end

function GoWRecruitmentDetails:GetApplications()
    return self.filteredApplications or {};
end

function GoWRecruitmentDetails:NormalizeSelection()
    local applications = self:GetApplications();
    if (#applications == 0) then
        self.selectedApplicationIndex = 0;
        return;
    end

    if (not self.selectedApplicationIndex or self.selectedApplicationIndex < 1 or self.selectedApplicationIndex > #applications) then
        self.selectedApplicationIndex = 1;
    end
end

function GoWRecruitmentDetails:SetApplications(applications, guildRoster)
    self.filteredApplications = applications or {};
    self.guildRoster = guildRoster;
    self:NormalizeSelection();
end

function GoWRecruitmentDetails:GetSelectedApplication()
    local applications = self:GetApplications();
    return applications[self.selectedApplicationIndex];
end

function GoWRecruitmentDetails:GetInviteLink(application)
    if (not application) then
        return nil;
    end

    return application.name .. "-" .. application.realmNormalized;
end

function GoWRecruitmentDetails:CreateListRow(parent, application, index, total)
    local L = GOW.Layout;
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate");
    row:SetHeight(LEFT_ROW_HEIGHT);
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * LEFT_ROW_HEIGHT));
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * LEFT_ROW_HEIGHT));

    row.highlight = L:CreateRowHighlight(row, 0.06);
    row.separator = L:CreateRowSeparator(row);

    local isSelected = (index == self.selectedApplicationIndex);
    if (isSelected) then
        L:ApplyBackdrop(row, L.constants.SUB_ACTIVE_COLOR.r, L.constants.SUB_ACTIVE_COLOR.g, L.constants.SUB_ACTIVE_COLOR.b, 0.22, L.constants.GOW_ACCENT_COLOR.r, L.constants.GOW_ACCENT_COLOR.g, L.constants.GOW_ACCENT_COLOR.b, 0.45);
    else
        L:ApplyBackdrop(row, 0, 0, 0, 0, 0, 0, 0, 0);
    end

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    row.nameText:SetPoint("LEFT", row, "LEFT", 10, 6);
    row.nameText:SetPoint("RIGHT", row, "RIGHT", -70, 6);
    row.nameText:SetJustifyH("LEFT");
    row.nameText:SetWordWrap(false);
    row.nameText:SetText(application.name or "");

    row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    row.classText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2);
    row.classText:SetText("|cff888888" .. (application.class or "") .. "|r");
    row.classText:SetJustifyH("LEFT");

    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    row.statusText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    row.statusText:SetJustifyH("RIGHT");
    row.statusText:SetText("|cffaaaaaa" .. (application.status or "") .. "|r");

    row:SetScript("OnEnter", function(selfFrame)
        if (not isSelected) then
            selfFrame.highlight:Show();
        end
    end);
    row:SetScript("OnLeave", function(selfFrame)
        selfFrame.highlight:Hide();
    end);
    row:SetScript("OnClick", function()
        self.selectedApplicationIndex = index;
        self:Render();
    end);

    if (index == total) then
        row.separator:Hide();
    end

    return row;
end

function GoWRecruitmentDetails:AddDetailLine(parent, yOffset, label, value, multiline)
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset);
    labelText:SetJustifyH("LEFT");
    labelText:SetText("|cffffff00" .. label .. ":|r");

    local valueText = parent:CreateFontString(nil, "OVERLAY", multiline and "GameFontNormal" or "GameFontHighlight");
    valueText:SetPoint("TOPLEFT", parent, "TOPLEFT", 120, yOffset);
    valueText:SetPoint("RIGHT", parent, "RIGHT", -16, 0);
    valueText:SetJustifyH("LEFT");
    valueText:SetJustifyV("TOP");
    valueText:SetWordWrap(multiline == true);
    valueText:SetText(value or "");

    local labelHeight = labelText:GetStringHeight() or 16;
    local valueHeight = valueText:GetStringHeight() or 16;
    local rowHeight = math.max(labelHeight, valueHeight);
    local nextOffset = yOffset - rowHeight - (multiline and 12 or 8);

    return nextOffset, labelText, valueText;
end

function GoWRecruitmentDetails:AddDurationDetailLine(parent, yOffset, label, timestamp, fallbackText)
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset);
    labelText:SetJustifyH("LEFT");
    labelText:SetText("|cffffff00" .. label .. ":|r");

    local valueText = GOW.Duration:CreateLabel(parent, {
        fontObject = "GameFontHighlight",
        updateInterval = 30
    });
    valueText:SetPoint("TOPLEFT", parent, "TOPLEFT", 120, yOffset);
    valueText:SetPoint("RIGHT", parent, "RIGHT", -16, 0);
    valueText:SetJustifyH("LEFT");

    if (timestamp and timestamp > 0) then
        valueText:SetTimestamp(timestamp);
        valueText:Start();
        valueText.Refresh = function(self)
            self:SetText(GOW.Duration:Format(self.timestamp));
        end
        valueText:Refresh();
    else
        valueText:SetText(fallbackText or "");
    end

    local rowHeight = math.max(labelText:GetStringHeight() or 16, valueText:GetStringHeight() or 16);
    local nextOffset = yOffset - rowHeight - 8;

    return nextOffset, labelText, valueText;
end

function GoWRecruitmentDetails:CreateActionButton(parent, text, width, isActive, onClick)
    local btn = GOW.Layout:CreateSubFilterBtn(parent, text, width);
    btn:SetHeight(18);
    GOW.Layout:SetButtonActive(btn, isActive);
    if (not isActive) then
        btn.btnText:SetText("|cff888888" .. text .. "|r");
    end
    btn:SetScript("OnClick", function()
        if (isActive and onClick) then
            onClick();
        end
    end);
    return btn;
end

function GoWRecruitmentDetails:RenderDetails(panel, application)
    local content = panel.scrollChild;
    if (not application) then
        local emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        emptyText:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -12);
        emptyText:SetText("|cff999999No recruitment application selected.|r");
        content:SetHeight(60);
        self:UpdatePanelScroll(panel, 60);
        return;
    end

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -12);
    title:SetText(application.name or "");

    local yOffset = -52;
    yOffset = select(1, self:AddDetailLine(content, yOffset, "Message", application.message or ""));
    yOffset = select(1, self:AddDetailLine(content, yOffset, "Class", application.class or ""));
    yOffset = select(1, self:AddDetailLine(content, yOffset, "Applied To", application.appliedTo or ""));
    yOffset = select(1, self:AddDurationDetailLine(content, yOffset, "Applied On", application.appliedOn, application.dateText or ""));
    yOffset = select(1, self:AddDetailLine(content, yOffset, "Status", application.status or ""));

    if (application.reviewedBy and application.reviewedBy ~= "") then
        yOffset = select(1, self:AddDetailLine(content, yOffset, "Reviewed By", application.reviewedBy));
    end

    if (application.responseMessage and application.responseMessage ~= "") then
        yOffset = select(1, self:AddDetailLine(content, yOffset, "Response", application.responseMessage, true));
    end

    local inviteLink = self:GetInviteLink(application);
    local inGuild = (self.guildRoster and self.guildRoster.roster and inviteLink and self.guildRoster.roster[inviteLink]) and true or false;
    local friendInfo = inviteLink and C_FriendList.GetFriendInfo(inviteLink) or nil;

    local buttonRow1 = CreateFrame("Frame", nil, content);
    buttonRow1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yOffset - 10);
    buttonRow1:SetSize(440, 22);

    local inviteToGuildBtn = self:CreateActionButton(buttonRow1, inGuild and "In Guild" or "Invite to Guild", 110, not inGuild, function()
        self.CORE:OpenDialogWithData("CONFIRM_INVITE_TO_GUILD", application.name, nil, inviteLink);
    end);
    inviteToGuildBtn:SetPoint("LEFT", buttonRow1, "LEFT", 0, 0);

    local inviteToPartyBtn = self:CreateActionButton(buttonRow1, "Invite to Party", 110, true, function()
        C_PartyInfo.InviteUnit(inviteLink);
    end);
    inviteToPartyBtn:SetPoint("LEFT", inviteToGuildBtn, "RIGHT", 8, 0);

    local addFriendBtn = self:CreateActionButton(buttonRow1, "Add Friend", 110, friendInfo == nil, function()
        self.CORE:OpenDialogWithData("CONFIRM_ADD_FRIEND", application.name, nil, inviteLink);
    end);
    addFriendBtn:SetPoint("LEFT", inviteToPartyBtn, "RIGHT", 8, 0);

    local buttonRow2 = CreateFrame("Frame", nil, content);
    buttonRow2:SetPoint("TOPLEFT", buttonRow1, "BOTTOMLEFT", 0, -8);
    buttonRow2:SetSize(440, 22);

    local whisperBtn = self:CreateActionButton(buttonRow2, "Whisper", 110, true, function()
        self.CORE:OpenDialogWithData("WHISPER_PLAYER", nil, nil, inviteLink);
    end);
    whisperBtn:SetPoint("LEFT", buttonRow2, "LEFT", 0, 0);

    local copyBtn = self:CreateActionButton(buttonRow2, "Copy Link", 110, true, function()
        self.CORE:OpenDialogWithData("COPY_TEXT", nil, nil, application.webUrl);
    end);
    copyBtn:SetPoint("LEFT", whisperBtn, "RIGHT", 8, 0);

    local finalHeight = math.abs(yOffset) + 90;
    content:SetHeight(math.max(finalHeight, 220));
    self:UpdatePanelScroll(panel, math.max(finalHeight, 220));
end

function GoWRecruitmentDetails:Render()
    local containerScrollFrame = self.UI.containerScrollFrame;

    self:Hide();
    containerScrollFrame:ReleaseChildren();

    local applications = self:GetApplications();
    self:NormalizeSelection();

    if (#applications == 0) then
        self.CORE:AppendMessage("This guild doesn't have any guild recruitment application, or you are not a recruitment manager!", true);
        self.CORE:AppendScrollBottomPadding();
        return;
    end

    local rootHost = self.GUI:Create("SimpleGroup");
    rootHost:SetFullWidth(true);
    rootHost:SetHeight(PANEL_HEIGHT + 8);
    containerScrollFrame:AddChild(rootHost);

    local hostFrame = rootHost.frame;
    self.nativeRoot = CreateFrame("Frame", nil, hostFrame);
    self.nativeRoot:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0);
    self.nativeRoot:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -8, 0);
    self.nativeRoot:SetHeight(PANEL_HEIGHT);

    local leftPanel = GOW.Layout:GetContainerPanel(self.nativeRoot, {
        xOffset = 0,
        width = LEFT_PANEL_WIDTH,
        height = PANEL_HEIGHT,
        title = "APPLICATIONS",
        headerHeight = HEADER_HEIGHT,
        topInset = 34,
        sideInset = 8,
        bottomInset = 8
    });
    local rightPanel = GOW.Layout:GetContainerPanel(self.nativeRoot, {
        xOffset = LEFT_PANEL_WIDTH + 6,
        width = RIGHT_PANEL_WIDTH,
        height = PANEL_HEIGHT,
        title = "DETAILS",
        headerHeight = HEADER_HEIGHT,
        topInset = 34,
        sideInset = 8,
        bottomInset = 8
    });

    for index, application in ipairs(applications) do
        self:CreateListRow(leftPanel.scrollChild, application, index, #applications);
    end

    local leftHeight = math.max(#applications * LEFT_ROW_HEIGHT, 1);
    leftPanel.scrollChild:SetHeight(leftHeight);
    self:UpdatePanelScroll(leftPanel, leftHeight);

    self:RenderDetails(rightPanel, self:GetSelectedApplication());
    self.CORE:AppendScrollBottomPadding();
end
