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
    if (panel.UpdateScrollBar) then
        panel:UpdateScrollBar();
    end
end

function GoWRecruitmentDetails:RenderEmptyState(message, secondaryMessage, displayReloadButton)
    self:Hide();
    self.UI.containerScrollFrame:ReleaseChildren();
    local state = GOW.Layout:RenderWarningState(self.GUI, self.UI.containerScrollFrame, "RECRUITMENT", message, secondaryMessage, displayReloadButton == true);
    self.nativeRoot = state.nativeRoot;
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

    local inviteToGuildBtn = GOW.Layout:CreateActionButton(buttonRow1, {
        text = inGuild and "In Guild" or "Invite to Guild",
        width = 110,
        isActive = not inGuild,
        onClick = function()
        self.CORE:OpenDialogWithData("CONFIRM_INVITE_TO_GUILD", application.name, nil, inviteLink);
        end
    });
    inviteToGuildBtn:SetPoint("LEFT", buttonRow1, "LEFT", 0, 0);

    local inviteToPartyBtn = GOW.Layout:CreateActionButton(buttonRow1, {
        text = "Invite to Party",
        width = 110,
        onClick = function()
        C_PartyInfo.InviteUnit(inviteLink);
        end
    });
    inviteToPartyBtn:SetPoint("LEFT", inviteToGuildBtn, "RIGHT", 8, 0);

    local addFriendBtn = GOW.Layout:CreateActionButton(buttonRow1, {
        text = "Add Friend",
        width = 110,
        isActive = friendInfo == nil,
        onClick = function()
        self.CORE:OpenDialogWithData("CONFIRM_ADD_FRIEND", application.name, nil, inviteLink);
        end
    });
    addFriendBtn:SetPoint("LEFT", inviteToPartyBtn, "RIGHT", 8, 0);

    local buttonRow2 = CreateFrame("Frame", nil, content);
    buttonRow2:SetPoint("TOPLEFT", buttonRow1, "BOTTOMLEFT", 0, -8);
    buttonRow2:SetSize(440, 22);

    local whisperBtn = GOW.Layout:CreateActionButton(buttonRow2, {
        text = "Whisper",
        width = 110,
        onClick = function()
        self.CORE:OpenDialogWithData("WHISPER_PLAYER", nil, nil, inviteLink);
        end
    });
    whisperBtn:SetPoint("LEFT", buttonRow2, "LEFT", 0, 0);

    local copyBtn = GOW.Layout:CreateActionButton(buttonRow2, {
        text = "Copy Link",
        width = 110,
        onClick = function()
        GOW.Layout:ShowCopyUrlDialog(self.GUI, application.webUrl, "Application URL");
        end
    });
    copyBtn:SetPoint("LEFT", whisperBtn, "RIGHT", 8, 0);

    local finalHeight = math.abs(yOffset) + 90;
    content:SetHeight(math.max(finalHeight, 220));
    self:UpdatePanelScroll(panel, math.max(finalHeight, 220));
end

function GoWRecruitmentDetails:Render()
    local containerScrollFrame = self.UI.containerScrollFrame;
    local L = GOW.Layout;

    self:Hide();
    containerScrollFrame:ReleaseChildren();

    local applications = self:GetApplications();
    self:NormalizeSelection();

    if (#applications == 0) then
        self:RenderEmptyState("This guild doesn't have any guild recruitment application, or you are not a recruitment manager!");
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

    local leftPanel = L:GetContainerPanel(self.nativeRoot, {
        xOffset = 0,
        width = LEFT_PANEL_WIDTH,
        height = PANEL_HEIGHT,
        title = "APPLICATIONS",
        headerHeight = HEADER_HEIGHT,
        topInset = 34,
        sideInset = 8,
        bottomInset = 8
    });
    local rightPanel = L:GetContainerPanel(self.nativeRoot, {
        xOffset = LEFT_PANEL_WIDTH + 6,
        width = RIGHT_PANEL_WIDTH,
        height = PANEL_HEIGHT,
        title = "DETAILS",
        headerHeight = HEADER_HEIGHT,
        topInset = 34,
        sideInset = 8,
        bottomInset = 8
    });

    local sidebar = L:CreateSidebarList(leftPanel.scrollChild, {
        rowHeight = LEFT_ROW_HEIGHT,
        getLabel = function(item) return item.name end,
        getSubtitle = function(item) return item.class end,
        getMeta = function(item) return item.status end,
        isSelected = function(item)
            return item == self:GetSelectedApplication();
        end,
        isEnabled = function() return true end,
        onSelect = function(item, index)
            self.selectedApplicationIndex = index;
            self:Render();
        end,
        onPostCreate = function(row, item, index)
            if (row.separator) then
                row.separator:SetDrawLayer("OVERLAY");
                row.separator:SetVertexColor(0.25, 0.25, 0.3, 0.28);
            end
        end,
    });

    local leftHeight = math.max(sidebar:Render(applications), 1);
    leftPanel.scrollChild:SetHeight(leftHeight);
    self:UpdatePanelScroll(leftPanel, leftHeight);

    self:RenderDetails(rightPanel, self:GetSelectedApplication());
    self.CORE:AppendScrollBottomPadding();
end
