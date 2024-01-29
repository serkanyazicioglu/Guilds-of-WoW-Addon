local ADDON_NAME = "GuildsOfWoW";
local FRAME_NAME = ADDON_NAME .. "MainFrame";
local GOW = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME);
GuildsOfWow = GOW;

GOW.consts = {
	INVITE_INTERVAL = 2,
	ENABLE_DEBUGGING = false
};

GOW.defaults = {
	profile = {
		version = 1,
		minimap = { hide = false }
	}
}

local getGowGameVersionId = function()
	if (GOW.consts.ENABLE_DEBUGGING) then
		print("WOW_PROJECT_ID: " .. WOW_PROJECT_ID);
	end

	if (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) then
		return 1;
	elseif (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) then
		return 2;
	elseif (WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC) then
		return 3;
	end

	return nil;
end

function GetCurrentRegionByGameVersion()
	local regionId = GetCurrentRegion();

	if (getGowGameVersionId() == 3) then
		return tonumber("4" .. tostring(regionId));
	elseif (getGowGameVersionId() == 2) then
		return tonumber("8" .. tostring(regionId));
	end

	return regionId;
end

local openRaidLib = nil;
if (getGowGameVersionId() == 1) then
	openRaidLib = LibStub:GetLibrary("LibOpenRaid-1.0");
end

local ns = select(2, ...);

local Core = {};
local f = CreateFrame("Frame");
f:RegisterEvent("PLAYER_ENTERING_WORLD");
f:RegisterEvent("FIRST_FRAME_RENDERED");
f:RegisterEvent("GUILD_ROSTER_UPDATE");
f:RegisterEvent("FRIENDLIST_UPDATE");
f:RegisterEvent("CALENDAR_UPDATE_GUILD_EVENTS");
f:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST");
f:RegisterEvent("CALENDAR_NEW_EVENT");
f:RegisterEvent("CALENDAR_UPDATE_EVENT");
f:RegisterEvent("CALENDAR_UPDATE_INVITE_LIST");
f:RegisterEvent("CALENDAR_OPEN_EVENT");
f:RegisterEvent("CALENDAR_CLOSE_EVENT");

local isInitialLogin = false;
local isPropogatingUpdate = false;
local containerFrame = {};
local containerTabs = {};
local containerScrollFrame = {};

local workQueue = nil;
local persistentWorkQueue = nil;

local currentMultiInvitingEvent = nil;
local processedEvents = nil;
local isEventProcessCompleted = false;
local isNewEventBeingCreated = false;
local isProcessedEventsPrinted = false;
local isCalendarOpened = false;
local recruitmentCharacter = nil;
local recruitmenNotes = nil;

local invitingToPartyEvent = nil;
local invitingToPartyTeam = nil;

local copyText = "";

local selectedTab = "events";
local tabs = {
	{ value = "events",          text = "Upcoming Events" },
	{ value = "teams",           text = "Teams" },
	{ value = "recruitmentApps", text = "Recruitment Applications" },
};

local LibQTip = LibStub('LibQTip-1.0');

function GOW:OnInitialize()
	self.GUI = LibStub("AceGUI-3.0");
	self.DB = LibStub("AceDB-3.0"):New("GoWDB", GOW.defaults, "Default");
	self.LDB = LibStub("LibDataBroker-1.1");
	self.LDBIcon = LibStub("LibDBIcon-1.0");
	self.CONSOLE = LibStub("AceConsole-3.0");
	self.SCROLLINGTABLE = LibStub("ScrollingTable");
	self.timers = {};
	LibStub("AceTimer-3.0"):Embed(self.timers);
	self.events = {};
	LibStub("AceEvent-3.0"):Embed(self.events);
	workQueue = self.WorkQueue.new();
	persistentWorkQueue = self.WorkQueue.new();
	processedEvents = GOW.List.new();

	local consoleCommandFunc = function(msg, editbox)
		if (msg == "minimap") then
			Core:ToggleMinimap();
		else
			Core:ToggleWindow();
		end
	end

	self.CONSOLE:RegisterChatCommand("gow", consoleCommandFunc);

	local dataobj = self.LDB:NewDataObject("gowicon", {
		type = "data source",
		label = "Guilds of WoW",
		text = "Guilds of WoW",
		icon = "Interface\\Addons\\GuildsOfWoW\\icons\\VAS_GuildFactionChange.tga",
		OnTooltipShow = function(tooltip)
			tooltip:SetText("Guilds of WoW");
			tooltip:Show();
		end,
		OnClick = function() Core:ToggleWindow() end
	});

	self.LDBIcon:Register("gowicon", dataobj, self.DB.profile.minimap);

	string.lpad = function(str, len, char)
		if char == nil then char = ' ' end
		return string.rep(char, len - #str) .. str;
	end

	string.splitByDelimeter = function(str, delimiter)
		local result = {};
		for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
			table.insert(result, match);
		end
		return result;
	end

	containerFrame = GOW.GUI:Create("Frame");
	containerFrame:SetLayout("Fill");
	containerFrame:SetHeight(550);
	containerFrame:SetTitle("Guilds of WoW");
	containerFrame:SetStatusText("Type /gow for quick access");
	containerFrame:SetCallback("OnClose", function(widget) containerFrame:Hide() end);
	containerFrame:SetCallback("OnEscapePressed", function(widget) containerFrame:Hide() end);
	containerFrame:Hide();

	_G[FRAME_NAME] = containerFrame.frame;
	tinsert(UISpecialFrames, FRAME_NAME);

	containerTabs = GOW.GUI:Create("TabGroup");
	containerTabs:SetTabs(tabs);
	containerTabs:SelectTab(selectedTab);
	containerTabs:SetCallback("OnGroupSelected", function(frame, event, value) Core:ToggleTabs(value) end);
	containerFrame:AddChild(containerTabs);

	containerScrollFrame = GOW.GUI:Create("ScrollFrame");
	containerScrollFrame:SetLayout("Flow");
	containerScrollFrame:SetFullWidth(true);
	containerScrollFrame:SetFullHeight(true);
	containerTabs:AddChild(containerScrollFrame);

	if (ns.UPCOMING_EVENTS == nil or ns.TEAMS == nil or ns.RECRUITMENT_APPLICATIONS == nil) then
		Core:PrintErrorMessage("Data is not fetched! Please make sure your sync app is installed and working properly.");
	end

	StaticPopupDialogs["CONFIRM_EVENT_CREATION"] = {
		text = "Are you sure you want to create this event on in-game calendar?",
		button1 = ACCEPT,
		button2 = CANCEL,
		OnAccept = function()
			isNewEventBeingCreated = true;
			C_Calendar.AddEvent();
			if (currentMultiInvitingEvent ~= nil and currentMultiInvitingEvent.isManualInvite) then
				Core:InviteMultiplePeopleToEvent();
			end
			Core:DialogClosed();
		end,
		OnCancel = function()
			currentMultiInvitingEvent = nil;
			Core:DialogClosed();
			C_Calendar.CloseEvent();
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["CONFIRM_GUILD_EVENT_CREATION"] = {
		text =
		"Are you sure you want to create this guild event on in-game calendar? (Note: Guild events RSVP integration only works single direction which is from WoW to GoW.)",
		button1 = ACCEPT,
		button2 = CANCEL,
		OnAccept = function()
			isNewEventBeingCreated = true;
			C_Calendar.AddEvent();
			if (currentMultiInvitingEvent ~= nil) then
				if (currentMultiInvitingEvent.isManualInvite) then
					Core:InviteMultiplePeopleToEvent();
				else
					Core:EventAttendanceProcessCompleted(currentMultiInvitingEvent, true);
				end
			end
			Core:DialogClosed();
		end,
		OnCancel = function()
			currentMultiInvitingEvent = nil;
			Core:DialogClosed();
			C_Calendar.CloseEvent();
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["CONFIRM_INVITE_TO_GUILD"] = {
		text = "Are you sure you want to invite %s to your guild?",
		button1 = ACCEPT,
		button2 = CANCEL,
		OnAccept = function()
			GuildInvite(recruitmentCharacter);
			recruitmentCharacter = nil;
			Core:DialogClosed();
		end,
		OnCancel = function()
			recruitmentCharacter = nil;
			Core:DialogClosed();
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["CONFIRM_ADD_FRIEND"] = {
		text = "Are you sure you want to add %s to your friend list?",
		button1 = ACCEPT,
		button2 = CANCEL,
		OnAccept = function()
			C_FriendList.AddFriend(recruitmentCharacter, recruitmenNotes);
			recruitmentCharacter = nil;
			Core:DialogClosed();
		end,
		OnCancel = function()
			recruitmentCharacter = nil;
			Core:DialogClosed();
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["WHISPER_PLAYER"] = {
		text                   = "Type your message",
		button1                = "Send",
		button2                = CANCEL,
		OnAccept               = function(self, data, data2)
			local text = self.editBox:GetText();

			if (text ~= nil and text ~= "") then
				SendChatMessage(text, "WHISPER", nil, recruitmentCharacter);
				recruitmentCharacter = nil;
				Core:DialogClosed();
			end
		end,
		OnCancel               = function()
			recruitmentCharacter = nil;
			Core:DialogClosed();
		end,
		EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
		timeout                = 100,
		enterClicksFirstButton = 1,
		whileDead              = 1,
		hideOnEscape           = 1,
		hasEditBox             = 1,
		exclusive              = 1,
		preferredIndex         = 3
	};

	StaticPopupDialogs["COPY_TEXT"] = {
		text                   = "Select & copy following text",
		button1                = DONE,
		OnShow                 = function(self, data)
			self.editBox:SetText(copyText);
			self.editBox:HighlightText();
			self.editBox:SetFocus();
		end,
		OnAccept               = function()
			Core:DialogClosed();
		end,
		EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
		timeout                = 0,
		whileDead              = 1,
		hideOnEscape           = 1,
		hasEditBox             = 1,
		exclusive              = 1,
		preferredIndex         = 1
	};

	StaticPopupDialogs["CONFIRM_INVITE_TO_PARTY"] = {
		text = "Are you sure you want to invite %s member(s) to your party?",
		button1 = ACCEPT,
		button2 = CANCEL,
		OnAccept = function()
			Core:InviteAllToParty(invitingToPartyEvent);
			invitingToPartyEvent = nil;
			Core:DialogClosed();
		end,
		OnCancel = function()
			invitingToPartyEvent = nil;
			Core:DialogClosed();
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["CONFIRM_INVITE_TEAM_TO_PARTY"] = {
		text = "Are you sure you want to invite %s member(s) to your party?",
		button1 = ACCEPT,
		button2 = CANCEL,
		OnAccept = function()
			Core:InviteAllTeamMembersToParty(invitingToPartyTeam);
			invitingToPartyTeam = nil;
			Core:DialogClosed();
		end,
		OnCancel = function()
			invitingToPartyTeam = nil;
			Core:DialogClosed();
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["INVITE_TO_PARTY_NOONE_FOUND"] = {
		text = "No member from this event is available to invite!",
		button1 = OKAY,
		timeout = 0,
		enterClicksFirstButton = 1,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["INVITE_TO_PARTY_INVALID_CALENDAR"] = {
		text =
		"Only 'Player Event' attendances can be invited via addon! For 'Guild Events' you can create the event and use that event's 'invite members' functionality.",
		button1 = OKAY,
		timeout = 0,
		enterClicksFirstButton = 1,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["INVITE_TO_PARTY_USE_CALENDAR"] = {
		text = "This event is also created on calendar! Please use the calendar event's 'invite members' button.",
		button1 = OKAY,
		timeout = 0,
		enterClicksFirstButton = 1,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};
end

f:SetScript("OnEvent", function(self, event, arg1, arg2)
	Core:Debug(event);

	if event == "PLAYER_ENTERING_WORLD" then
		isInitialLogin = arg1;

		Core:Debug(tostring(arg1));
		Core:Debug(tostring(arg2));
	elseif event == "FIRST_FRAME_RENDERED" then
		isCalendarOpened = true;

		if (isInitialLogin) then
			Core:Debug("Opening Calendar");
			C_Calendar.OpenCalendar();
		else
			Core:Debug("Triggering event invites for reload");
			Core:InitializeEventInvites();
		end

		if (openRaidLib) then
			openRaidLib.RequestKeystoneDataFromGuild();
		end
		--C_Calendar.GetNumDayEvents(0, 1)
		--workQueue:addTask(function() Core:Debug("Opening Calendar") C_Calendar.OpenCalendar() C_Calendar.GetNumDayEvents(0, 1) C_Calendar.GetGuildEventInfo(0) end, nil, 30)
	elseif event == "GUILD_ROSTER_UPDATE" then
		Core:SetRosterInfo();
	elseif event == "CALENDAR_UPDATE_EVENT_LIST" then
		--f:UnregisterEvent("CALENDAR_UPDATE_EVENT_LIST");
		Core:InitializeEventInvites();
	elseif event == "CALENDAR_NEW_EVENT" or event == "CALENDAR_UPDATE_EVENT" or event == "CALENDAR_UPDATE_GUILD_EVENTS" then
		if (event == "CALENDAR_UPDATE_GUILD_EVENTS") then
			--f:UnregisterEvent("CALENDAR_UPDATE_GUILD_EVENTS");
			Core:InitializeEventInvites();
		end

		if (isPropogatingUpdate == false and selectedTab == "events") then
			persistentWorkQueue:addTask(function()
				isPropogatingUpdate = true;
				Core:CreateUpcomingEvents();
			end, nil, 2);
		end
	elseif event == "CALENDAR_OPEN_EVENT" then
		if (C_Calendar.IsEventOpen()) then
			local eventInfo = C_Calendar.GetEventInfo();

			if (eventInfo ~= nil) then
				Core:Debug("CALENDAR_OPEN_EVENT: Opened: " ..
					eventInfo.title .. " . Calendar Type: " .. eventInfo.calendarType);
				Core:ClearEventInvites(false);
				isNewEventBeingCreated = false;

				if (eventInfo.calendarType == "GUILD_EVENT" or eventInfo.calendarType == "PLAYER") then
					local upcomingEvent = Core:FindUpcomingEventFromName(eventInfo.title);

					if (upcomingEvent ~= nil) then
						if (eventInfo.isLocked) then
							if (not upcomingEvent.isLocked) then
								C_Calendar.EventClearLocked();
							end
						else
							if (upcomingEvent.isLocked) then
								C_Calendar.EventSetLocked();
							end
						end

						if (eventInfo.calendarType == "PLAYER") then
							--processedEvents:remove(upcomingEvent.titleWithKey)
							Core:CreateEventInvites(upcomingEvent, not isEventProcessCompleted);
						else
							Core:SetAttendance(upcomingEvent, not isEventProcessCompleted);
						end
					else
						Core:Debug("Event couldn't be found!");
					end
				else
					Core:Debug("Not suitable calendar type!");
				end
			else
				Core:Debug("Event info is null!");
			end
		else
			Core:Debug("Event is not open!");
			workQueue:addTask(function()
				Core:Debug("Checking attendances");
				Core:CheckEventInvites();
			end, nil, 10);
		end
	elseif event == "CALENDAR_CLOSE_EVENT" then
		isNewEventBeingCreated = false;
		if (isEventProcessCompleted == false) then
			Core:ClearEventInvites(true);
		end

		if (isEventProcessCompleted and isPropogatingUpdate == false and selectedTab == "events") then
			persistentWorkQueue:addTask(function()
				isPropogatingUpdate = true;
				Core:CreateUpcomingEvents();
			end, nil, 2);
		end
	elseif event == "CALENDAR_UPDATE_INVITE_LIST" then
		if (C_Calendar.IsEventOpen()) then
			local eventInfo = C_Calendar.GetEventInfo();

			if (processedEvents:contains(eventInfo.title)) then
				if (eventInfo.title == "") then
					Core:ClearEventInvites(false);
				else
					local upcomingEvent = Core:FindUpcomingEventFromName(eventInfo.title);
					if (upcomingEvent ~= nil) then
						--processedEvents:remove(eventInfo.title);
						Core:SetAttendance(upcomingEvent, false);
					end
				end
			elseif (workQueue:isEmpty()) then
				Core:Debug("Continuing event attendance and moderation!");
				local upcomingEvent = Core:FindUpcomingEventFromName(eventInfo.title);
				if (upcomingEvent ~= nil) then
					Core:SetAttendance(upcomingEvent, false);
				end
			end
		end
	elseif event == "FRIENDLIST_UPDATE" then
		Core:CreateRecruitmentApplications();
	end
end)

function Core:ToggleTabs(tabKey)
	selectedTab = tabKey;
	Core:RefreshApplication();
end

function Core:RefreshApplication()
	isPropogatingUpdate = true;

	if (selectedTab == "events") then
		Core:CreateUpcomingEvents();
	elseif (selectedTab == "teams") then
		Core:CreateTeams();
	elseif (selectedTab == "recruitmentApps") then
		Core:CreateRecruitmentApplications();
	end
end

function Core:ToggleWindow()
	if (containerFrame:IsShown()) then
		containerFrame:Hide();
	else
		Core:RefreshApplication()
		containerFrame:Show();
	end
end

function Core:CreateUpcomingEvents()
	if (selectedTab ~= "events") then
		return;
	end

	if (ns.UPCOMING_EVENTS == nil) then
		containerScrollFrame:ReleaseChildren();
		Core:AppendMessage(
			"Upcoming events data is not found! Please make sure your sync app is installed and working properly!", true);
	else
		local isInGuild = IsInGuild();

		if (isInGuild == false) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false);
			return;
		end

		local guildName, _, _, realmName = GetGuildInfo("player");

		if (guildName == nil) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false);
			return;
		end

		Core:Debug("Core:CreateUpcomingEvents");
		containerScrollFrame:ReleaseChildren();

		if (realmName == nil) then
			realmName = GetNormalizedRealmName();
		end

		local regionId = GetCurrentRegionByGameVersion();

		local hasAnyData = false;

		if (isInGuild and ns.UPCOMING_EVENTS.totalEvents > 0) then
			for i = 1, ns.UPCOMING_EVENTS.totalEvents do
				local upcomingEvent = ns.UPCOMING_EVENTS.events[i];

				if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealmNormalized and regionId == upcomingEvent.guildRegionId) then
					hasAnyData = true;
					Core:AppendCalendarList(upcomingEvent);
				end
			end
		end

		if (not hasAnyData) then
			Core:AppendMessage(
				"This guild doesn't have any upcoming event or you are not an event manager!\r\n\r\nGuild: " ..
				guildName .. " / " .. realmName, true);
		end
	end

	isPropogatingUpdate = false;
end

function Core:CreateTeams()
	if (selectedTab ~= "teams") then
		return;
	end

	if (ns.TEAMS == nil) then
		containerScrollFrame:ReleaseChildren();
		Core:AppendMessage("Team data is not found! Please make sure your sync app is installed and working properly!",
			true);
	else
		local isInGuild = IsInGuild();

		if (isInGuild == false) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false);
			return;
		end

		local guildName, _, _, realmName = GetGuildInfo("player");

		if (guildName == nil) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false);
			return;
		end

		containerScrollFrame:ReleaseChildren();

		if (realmName == nil) then
			realmName = GetNormalizedRealmName();
		end

		local regionId = GetCurrentRegionByGameVersion();

		local hasAnyData = false;

		if (isInGuild and ns.TEAMS.totalTeams > 0) then
			for i = 1, ns.TEAMS.totalTeams do
				local team = ns.TEAMS.teams[i];

				if (guildName == team.guild and realmName == team.guildRealmNormalized and regionId == team.guildRegionId) then
					hasAnyData = true;
					Core:AppendTeam(team);
				end
			end

			--containerScrollFrame:DoLayout();
		end

		if (not hasAnyData) then
			Core:AppendMessage(
				"This guild doesn't have any team or you are not a roster manager!\r\n\r\nGuild: " ..
				guildName .. " / " .. realmName, true);
		end
	end

	isPropogatingUpdate = false;
end

function Core:CreateRecruitmentApplications()
	if (selectedTab ~= "recruitmentApps") then
		return;
	end

	if (ns.RECRUITMENT_APPLICATIONS == nil) then
		containerScrollFrame:ReleaseChildren();
		Core:AppendMessage(
			"Recruitment applications data is not found! Please make sure your sync app is installed and working properly!",
			true);
	else
		local isInGuild = IsInGuild();

		if (isInGuild == false) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false);
			return;
		end

		local guildName, _, _, realmName = GetGuildInfo("player");

		if (guildName == nil) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false);
			return;
		end

		containerScrollFrame:ReleaseChildren();

		if (realmName == nil) then
			realmName = GetNormalizedRealmName();
		end

		local regionId = GetCurrentRegionByGameVersion();

		local hasAnyData = false;

		if (isInGuild and ns.RECRUITMENT_APPLICATIONS.totalApplications > 0) then
			for i = 1, ns.RECRUITMENT_APPLICATIONS.totalApplications do
				local recruitmentApplication = ns.RECRUITMENT_APPLICATIONS.recruitmentApplications[i]

				if (guildName == recruitmentApplication.guild and realmName == recruitmentApplication.guildRealmNormalized and regionId == recruitmentApplication.guildRegionId) then
					hasAnyData = true;
					Core:AppendRecruitmentList(recruitmentApplication);
				end
			end

			--containerScrollFrame:DoLayout()
		end

		if (not hasAnyData) then
			Core:AppendMessage(
				"This guild doesn't have any guild recruitment application or you are not a recruitment manager!\r\n\r\nGuild: " ..
				guildName .. " / " .. realmName, true);
		end
	end

	isPropogatingUpdate = false;
end

function Core:searchForEvent(event)
	local serverTime = C_DateAndTime.GetServerTimeLocal();

	if (event.eventDate < serverTime) then
		return 0;
	end

	C_Calendar.SetAbsMonth(event.month, event.year);

	local monthIndex = 0; -- tonumber(date("%m", event.eventDate)) - tonumber(date("%m", serverTime))

	local numDayEvents = C_Calendar.GetNumDayEvents(monthIndex, event.day);

	Core:Debug("Searching: " ..
		event.titleWithKey ..
		". Found: " .. numDayEvents .. " : " .. event.day .. "/" .. event.month .. "/" .. event.year);

	if (numDayEvents > 0) then
		for i = 1, numDayEvents do
			local dayEvent = C_Calendar.GetDayEvent(monthIndex, event.day, i);

			if (dayEvent.calendarType == "GUILD_EVENT" or dayEvent.calendarType == "PLAYER") then
				Core:Debug("dayEvent: " .. dayEvent.title .. " - " .. dayEvent.calendarType);

				if (string.match(dayEvent.title, "*" .. event.eventKey)) then
					return i;
				end
			end
		end
	end

	return -1
end

function Core:AppendMessage(message, appendReloadUIButton)
	local fontPath = "Fonts\\FRIZQT__.TTF";
	local fontSize = 13;

	local itemGroup = GOW.GUI:Create("SimpleGroup");
	--itemGroup:SetLayout("Line");
	itemGroup:SetFullWidth(true);
	itemGroup:SetFullHeight(true);

	local blankMargin = GOW.GUI:Create("SimpleGroup");
	blankMargin:SetLayout("Line");
	blankMargin:SetFullWidth(true);
	blankMargin:SetHeight(10);
	itemGroup:AddChild(blankMargin);

	local messageLabel = GOW.GUI:Create("Label");
	messageLabel:SetText(message);
	messageLabel:SetFullWidth(true);
	--messageLabel:SetFont(fontPath, fontSize);
	itemGroup:AddChild(messageLabel);

	if (appendReloadUIButton) then
		local blankMargin2 = GOW.GUI:Create("SimpleGroup");
		blankMargin2:SetLayout("Line");
		blankMargin2:SetFullWidth(true);
		blankMargin2:SetHeight(10);
		itemGroup:AddChild(blankMargin2);

		local reloadUIButton = GOW.GUI:Create("Button");
		reloadUIButton:SetText("Reload UI");
		reloadUIButton:SetCallback("OnClick", function()
			ReloadUI();
		end);
		itemGroup:AddChild(reloadUIButton);
	end

	containerScrollFrame:AddChild(itemGroup);
end

function Core:AppendCalendarList(event)
	local itemGroup = GOW.GUI:Create("InlineGroup");
	itemGroup:SetTitle(event.title);
	itemGroup:SetFullWidth(true);

	if (event.description ~= nil and event.description ~= "") then
		local descriptionLabel = GOW.GUI:Create("SFX-Info");
		descriptionLabel:SetLabel("Description");
		descriptionLabel:SetText(event.description);
		descriptionLabel:SetDisabled(false);
		descriptionLabel:SetCallback("OnEnter", function(self)
			local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT");
			GOW.tooltip = tooltip;

			tooltip:AddHeader('|cffffcc00Event Description');
			local line = tooltip:AddLine();
			tooltip:SetCell(line, 1, event.description, "LEFT", 1, nil, 0, 0, 300, 50);
			tooltip:SmartAnchorTo(self.frame);
			tooltip:Show();
		end);
		descriptionLabel:SetCallback("OnLeave", function()
			LibQTip:Release(GOW.tooltip);
			GOW.tooltip = nil;
		end);
		itemGroup:AddChild(descriptionLabel);
	end

	local dateLabel = GOW.GUI:Create("SFX-Info");
	dateLabel:SetLabel("Date");
	dateLabel:SetText(event.dateText .. ", " .. event.hourText);
	dateLabel:SetDisabled(false);
	dateLabel:SetCallback("OnEnter", function(self)
		local tooltip = LibQTip:Acquire("EventDateTooltip", 1, "LEFT");
		GOW.tooltip = tooltip;

		tooltip:AddHeader('|cffffcc00All dates are realm time.');
		tooltip:SmartAnchorTo(self.frame);
		tooltip:Show();
	end);
	dateLabel:SetCallback("OnLeave", function()
		LibQTip:Release(GOW.tooltip);
		GOW.tooltip = nil;
	end);
	itemGroup:AddChild(dateLabel);

	local eventDurationLabel = GOW.GUI:Create("SFX-Info");
	eventDurationLabel:SetLabel("Duration");
	eventDurationLabel:SetText(event.durationText);
	itemGroup:AddChild(eventDurationLabel);

	if (event.team ~= "") then
		local teamLabel = GOW.GUI:Create("SFX-Info");
		teamLabel:SetLabel("Team");
		teamLabel:SetText(event.team);
		itemGroup:AddChild(teamLabel);
	elseif (event.calendarType == 2) then
		local levelText = event.minLevel;

		if event.minLevel ~= event.maxLevel then
			levelText = levelText .. " -> " .. event.maxLevel;
		end

		local eventLevelLabel = GOW.GUI:Create("SFX-Info");
		eventLevelLabel:SetLabel("Level");
		eventLevelLabel:SetText(levelText);
		itemGroup:AddChild(eventLevelLabel);

		if (event.minItemLevel > 0) then
			local eventMinItemLevelLabel = GOW.GUI:Create("SFX-Info");
			eventMinItemLevelLabel:SetLabel("Item Level");
			eventMinItemLevelLabel:SetText(event.minItemLevel .. "+");
			itemGroup:AddChild(eventMinItemLevelLabel);
		end
	end

	local isEventMember = event.isEventMember;
	local canAddEvent = event.isEventManager;

	local eventInvitingMembersLabel = GOW.GUI:Create("SFX-Info");
	eventInvitingMembersLabel:SetLabel("Inviting");

	local invitineDetailsText = "";

	if (event.calendarType == 1) then
		invitineDetailsText = "All guildies";
	elseif (not event.isManualInvite) then
		invitineDetailsText = "All guildies within level range";
	else
		if (event.totalMembers > 1) then
			invitineDetailsText = event.totalMembers .. " members";
		else
			invitineDetailsText = event.totalMembers .. " member";
		end
	end

	if (not isEventMember) then
		invitineDetailsText = invitineDetailsText .. " (You are not eligible for this event)";
	end

	eventInvitingMembersLabel:SetText(invitineDetailsText);
	itemGroup:AddChild(eventInvitingMembersLabel);

	local eventIndex = Core:searchForEvent(event);

	local buttonsGroup = GOW.GUI:Create("SimpleGroup");
	buttonsGroup:SetLayout("Flow");
	buttonsGroup:SetFullWidth(true);

	if (canAddEvent) then
		local eventCalendarTypeLabel = GOW.GUI:Create("SFX-Info");
		eventCalendarTypeLabel:SetLabel("Calendar");
		if (event.calendarType == 1) then
			eventCalendarTypeLabel:SetText("Guild Event");
		else
			eventCalendarTypeLabel:SetText("Player Event");
		end
		eventCalendarTypeLabel:SetDisabled(false);
		eventCalendarTypeLabel:SetCallback("OnEnter", function(self)
			local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT");
			GOW.tooltip = tooltip;

			tooltip:AddHeader('|cffffcc00About Event Attendances');
			local line = tooltip:AddLine();
			tooltip:SetCell(line, 1,
				"When no filter is selected in-game addon will create 'Guild Event' and all guildies will be able to sign up. This selection is suitable for large meetings. Site attendance data will not migrate to in-game with this selection but will migrate from game to GoW.\r\n\r\nWhen filtration is enabled or audience is set to team event, addon will create 'Player Event' and will only invite eligible characters. Attendance synchronization will work bidirectional. Player events cannot invite more than 100 members so you should narrow the audience by item level or change audience to team event.",
				"LEFT", 1, nil, 0, 0, 300, 50);
			tooltip:SmartAnchorTo(self.frame);
			tooltip:Show();
		end);
		eventCalendarTypeLabel:SetCallback("OnLeave", function()
			LibQTip:Release(GOW.tooltip);
			GOW.tooltip = nil;
		end);
		itemGroup:AddChild(eventCalendarTypeLabel);

		local eventButton = GOW.GUI:Create("Button");

		if eventIndex == 0 then
			eventButton:SetText("Event Passed");
			eventButton:SetDisabled(true);
		elseif eventIndex > 0 then
			eventButton:SetText("Event Created");
			eventButton:SetDisabled(true);
		else
			if (not isNewEventBeingCreated and processedEvents:contains(event.titleWithKey)) then
				processedEvents:remove(event.titleWithKey);
			end

			eventButton:SetText("Create In-Game Event");
			eventButton:SetCallback("OnClick", function()
				Core:CreateCalendarEvent(event);
			end);

			eventButton:SetCallback("OnEnter", function(self)
				local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT");
				GOW.tooltip = tooltip;

				local line = tooltip:AddLine();
				tooltip:SetCell(line, 1,
					"You can create an in-game calendar event to integrate Guilds of WoW attendance data with in-game calendar. This synchronization will work bidirectional.",
					"LEFT", 1, nil, 0, 0, 300, 50);
				tooltip:SmartAnchorTo(self.frame);
				tooltip:Show();
			end);
			eventButton:SetCallback("OnLeave", function()
				LibQTip:Release(GOW.tooltip);
				GOW.tooltip = nil;
			end);
		end
		buttonsGroup:AddChild(eventButton);

		if (event.eventEndDate >= C_DateAndTime.GetServerTimeLocal()) then
			local inviteButton = GOW.GUI:Create("Button");
			inviteButton:SetWidth(140);
			inviteButton:SetText("Invite Attendees");
			inviteButton:SetCallback("OnClick", function()
				if (event.calendarType == 2) then
					if (eventIndex > 0) then
						Core:OpenDialog("INVITE_TO_PARTY_USE_CALENDAR");
					else
						Core:InviteAllToPartyCheck(event);
					end
				else
					Core:OpenDialog("INVITE_TO_PARTY_INVALID_CALENDAR");
				end
			end);

			inviteButton:SetCallback("OnEnter", function(self)
				local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT");
				GOW.tooltip = tooltip;

				local line = tooltip:AddLine();
				tooltip:SetCell(line, 1, "You can invite attendees directly into your party or raid.", "LEFT", 1, nil, 0,
					0, 300, 50);
				tooltip:SmartAnchorTo(self.frame);
				tooltip:Show();
			end);
			inviteButton:SetCallback("OnLeave", function()
				LibQTip:Release(GOW.tooltip);
				GOW.tooltip = nil;
			end);
			buttonsGroup:AddChild(inviteButton);
		end
	end

	local copyLinkButton = GOW.GUI:Create("Button");
	copyLinkButton:SetText("Copy Link");
	copyLinkButton:SetWidth(100);
	copyLinkButton:SetCallback("OnClick", function()
		copyText = event.webUrl;
		Core:OpenDialog("COPY_TEXT");
	end);
	buttonsGroup:AddChild(copyLinkButton);

	if (canAddEvent and eventIndex < 0) then
		local copyKeyButton = GOW.GUI:Create("Button");
		copyKeyButton:SetText("Copy Key");
		copyKeyButton:SetWidth(100);
		copyKeyButton:SetCallback("OnClick", function()
			copyText = event.eventKey;
			Core:OpenDialog("COPY_TEXT");
		end);

		copyKeyButton:SetCallback("OnEnter", function(self)
			local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT");
			GOW.tooltip = tooltip;

			local line = tooltip:AddLine();
			tooltip:SetCell(line, 1,
				"If you already created an in-game event related to this record, you can append this key to the end of event title in-game for GoW synchronization.",
				"LEFT", 1, nil, 0, 0, 300, 50);
			tooltip:SmartAnchorTo(self.frame);
			tooltip:Show();
		end);
		copyKeyButton:SetCallback("OnLeave", function()
			LibQTip:Release(GOW.tooltip);
			GOW.tooltip = nil;
		end);

		buttonsGroup:AddChild(copyKeyButton);
	end

	itemGroup:AddChild(buttonsGroup);

	containerScrollFrame:AddChild(itemGroup);
end

function Core:AppendTeam(teamData)
	local itemGroup = GOW.GUI:Create("InlineGroup");
	itemGroup:SetTitle(teamData.title);
	itemGroup:SetFullWidth(true);

	if (teamData.description ~= nil and teamData.description ~= "") then
		local teamDescriptionLabel = GOW.GUI:Create("SFX-Info");
		teamDescriptionLabel:SetLabel("Description");
		teamDescriptionLabel:SetDisabled(false);
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
		itemGroup:AddChild(teamDescriptionLabel);
	end

	local membersLabel = GOW.GUI:Create("SFX-Info");
	membersLabel:SetLabel("Members");
	membersLabel:SetText(teamData.totalMembers);
	itemGroup:AddChild(membersLabel);

	local buttonsGroup = GOW.GUI:Create("SimpleGroup");
	buttonsGroup:SetLayout("Flow");
	buttonsGroup:SetFullWidth(true);

	local inviteToPartyButton = GOW.GUI:Create("Button");
	inviteToPartyButton:SetText("Invite Team");
	inviteToPartyButton:SetWidth(200);
	inviteToPartyButton:SetCallback("OnClick", function()
		Core:InviteAllTeamMembersToPartyCheck(teamData);
	end);
	buttonsGroup:AddChild(inviteToPartyButton);

	local copyButton = GOW.GUI:Create("Button");
	copyButton:SetText("Copy Link");
	copyButton:SetWidth(100);
	copyButton:SetCallback("OnClick", function()
		copyText = teamData.webUrl;
		Core:OpenDialog("COPY_TEXT");
	end);
	buttonsGroup:AddChild(copyButton);

	itemGroup:AddChild(buttonsGroup);

	containerScrollFrame:AddChild(itemGroup);
end

function Core:AppendRecruitmentList(recruitmentApplication)
	local itemGroup = GOW.GUI:Create("InlineGroup");
	itemGroup:SetTitle(recruitmentApplication.title);
	itemGroup:SetFullWidth(true);

	local messageLabel = GOW.GUI:Create("SFX-Info");
	messageLabel:SetLabel("Message");
	messageLabel:SetDisabled(false);
	messageLabel:SetText(recruitmentApplication.message);
	messageLabel:SetCallback("OnEnter", function(self)
		local tooltip = LibQTip:Acquire("RecruitmentMessageTooltip", 1, "LEFT");
		GOW.tooltip = tooltip;

		tooltip:AddHeader('|cffffcc00Message');
		local line = tooltip:AddLine();
		tooltip:SetCell(line, 1, recruitmentApplication.message, "LEFT", 1, nil, 0, 0, 300, 50);
		tooltip:SmartAnchorTo(self.frame);
		tooltip:Show();
	end);
	messageLabel:SetCallback("OnLeave", function()
		LibQTip:Release(GOW.tooltip);
		GOW.tooltip = nil;
	end);
	itemGroup:AddChild(messageLabel);

	local classLabel = GOW.GUI:Create("SFX-Info");
	classLabel:SetLabel("Class");
	classLabel:SetText(recruitmentApplication.classTitle);
	itemGroup:AddChild(classLabel);

	local dateLabel = GOW.GUI:Create("SFX-Info");
	dateLabel:SetLabel("Date");
	dateLabel:SetText(recruitmentApplication.dateText);
	itemGroup:AddChild(dateLabel);

	local statusLabel = GOW.GUI:Create("SFX-Info");
	statusLabel:SetLabel("Status");
	statusLabel:SetText(recruitmentApplication.status);
	itemGroup:AddChild(statusLabel);

	if (recruitmentApplication.reviewedBy ~= "" and recruitmentApplication.reviewedBy ~= nil) then
		local reviewedByLabel = GOW.GUI:Create("SFX-Info");
		reviewedByLabel:SetLabel("Reviewer");
		reviewedByLabel:SetText(recruitmentApplication.reviewedBy);
		itemGroup:AddChild(reviewedByLabel);
	end

	if (recruitmentApplication.responseMessage ~= "" and recruitmentApplication.responseMessage ~= nil) then
		local responseMessageLabel = GOW.GUI:Create("SFX-Info");
		responseMessageLabel:SetLabel("Response");
		responseMessageLabel:SetDisabled(false);
		responseMessageLabel:SetText(recruitmentApplication.responseMessage);
		responseMessageLabel:SetCallback("OnEnter", function(self)
			local tooltip = LibQTip:Acquire("RecruitmentResponseMessageTooltip", 1, "LEFT");
			GOW.tooltip = tooltip;

			tooltip:AddHeader('|cffffcc00Response Message');
			local line = tooltip:AddLine();
			tooltip:SetCell(line, 1, recruitmentApplication.responseMessage, "LEFT", 1, nil, 0, 0, 300, 50);
			tooltip:SmartAnchorTo(self.frame);
			tooltip:Show();
		end);
		responseMessageLabel:SetCallback("OnLeave", function()
			LibQTip:Release(GOW.tooltip);
			GOW.tooltip = nil;
		end);
		itemGroup:AddChild(responseMessageLabel);
	end

	local buttonsGroup = GOW.GUI:Create("SimpleGroup");
	buttonsGroup:SetLayout("Flow");
	buttonsGroup:SetFullWidth(true);

	local inviteToGuildButton = GOW.GUI:Create("Button");
	inviteToGuildButton:SetText("Invite to Guild");
	inviteToGuildButton:SetWidth(140);
	inviteToGuildButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized;
		Core:OpenDialog("CONFIRM_INVITE_TO_GUILD", recruitmentApplication.title);
	end);
	buttonsGroup:AddChild(inviteToGuildButton);

	local inviteToPartyButton = GOW.GUI:Create("Button");
	inviteToPartyButton:SetText("Invite to Party");
	inviteToPartyButton:SetWidth(140);
	inviteToPartyButton:SetCallback("OnClick", function()
		C_PartyInfo.InviteUnit(recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized);
	end);
	buttonsGroup:AddChild(inviteToPartyButton);

	local friendInfo = C_FriendList.GetFriendInfo(recruitmentApplication.title);

	local addFriendButton = GOW.GUI:Create("Button");
	addFriendButton:SetText("Add Friend");
	addFriendButton:SetWidth(140);

	if (friendInfo ~= nil) then
		addFriendButton:SetDisabled(true);
	end

	addFriendButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized;
		recruitmenNotes = "Guilds of WoW recruitment";
		Core:OpenDialog("CONFIRM_ADD_FRIEND", recruitmentApplication.title);
	end);
	buttonsGroup:AddChild(addFriendButton);
	itemGroup:AddChild(buttonsGroup);

	local buttonsGroup2 = GOW.GUI:Create("SimpleGroup");
	buttonsGroup2:SetLayout("Flow");
	buttonsGroup2:SetFullWidth(true);

	local whisperButton = GOW.GUI:Create("Button");
	whisperButton:SetText("Whisper");
	whisperButton:SetWidth(140);
	whisperButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized;
		Core:OpenDialog("WHISPER_PLAYER");
	end);
	buttonsGroup2:AddChild(whisperButton);

	local copyButton = GOW.GUI:Create("Button");
	copyButton:SetText("Copy Link");
	copyButton:SetWidth(140);
	copyButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized;
		copyText = recruitmentApplication.webUrl;
		Core:OpenDialog("COPY_TEXT");
	end);
	buttonsGroup2:AddChild(copyButton);

	itemGroup:AddChild(buttonsGroup2);

	containerScrollFrame:AddChild(itemGroup);
end

function Core:OpenDialog(dialogName)
	StaticPopup_Show(dialogName);
end

function Core:OpenDialog(dialogName, parameterStr)
	StaticPopup_Show(dialogName, parameterStr);
end

function Core:DialogClosed()
end

function Core:ShowTooltip(container, header, message)
end

function Core:CreateCalendarEvent(event)
	if (event.calendarType == 2 and event.totalMembers >= 100) then
		Core:PrintErrorMessage(
			"You cannot create events with more than 100 members! Please narrow your audience by filtering or binding a team or disabling filtering at all to create a guild event.");
		return;
	end

	if (not workQueue:isEmpty() or not isEventProcessCompleted or isNewEventBeingCreated) then
		Core:PrintErrorMessage("Addon is busy right now! Please wait for a while and try again...");
		return;
	end

	local eventIndex = Core:searchForEvent(event);

	if eventIndex >= 0 then
		Core:DialogClosed();
		Core:Debug("Event found or passed: " .. event.title);
	else
		Core:ClearEventInvites(false);
		C_Calendar.CloseEvent();
		if (event.calendarType == 1) then
			C_Calendar.CreateGuildSignUpEvent();
		else
			C_Calendar.CreatePlayerEvent();
		end
		C_Calendar.EventSetTitle(event.titleWithKey);
		C_Calendar.EventSetDescription(event.description);
		C_Calendar.EventSetType(event.eventType);
		C_Calendar.EventSetTime(event.hour, event.minute);
		C_Calendar.EventSetDate(event.month, event.day, event.year);

		currentMultiInvitingEvent = nil;
		if (event.calendarType == 2 and not event.isManualInvite) then
			C_Calendar.MassInviteGuild(event.minLevel, event.maxLevel, event.maxRank);
		else
			currentMultiInvitingEvent = event;
		end

		if (event.calendarType == 1) then
			Core:OpenDialog("CONFIRM_GUILD_EVENT_CREATION");
		else
			Core:OpenDialog("CONFIRM_EVENT_CREATION");
		end
	end
end

function Core:InviteMultiplePeopleToEvent()
	if (currentMultiInvitingEvent ~= nil) then
		local event = currentMultiInvitingEvent;

		local name, realm = UnitName("player");

		if (realm == nil) then
			realm = GetNormalizedRealmName();
		end

		local currentPlayer = name .. "-" .. realm;

		local numInvites = C_Calendar.GetNumInvites();

		if (numInvites < event.totalMembers and numInvites < 100) then
			Core:PrintMessage(
				"Event invites are being sent in the background! Please wait for process to complete before logging out.");

			for i = 1, event.totalMembers do
				local currentInviteMember = event.inviteMembers[i];
				local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized;

				if (inviteName ~= currentPlayer) then
					workQueue:addTask(function() C_Calendar.EventInvite(inviteName) end, nil, GOW.consts.INVITE_INTERVAL);
				end
			end
		else
			Core:EventAttendanceProcessCompleted(event, true);
		end
	end
end

function Core:ClearEventInvites(restartInvites)
	currentMultiInvitingEvent = nil;
	workQueue:clearTasks();
	workQueue = GOW.WorkQueue.new();
	Core:Debug("Invites are canceled! Restart invites: " .. tostring(restartInvites));

	if (restartInvites) then
		Core:Debug("AddCheckEventsTask is called!");
		workQueue:addTask(function()
			Core:Debug("Check invites task started...");
			if (not C_Calendar.IsEventOpen()) then
				Core:CheckEventInvites();
			else
				Core:Debug("There is an event open! Re-trying checking event invites later...");
				Core:AddCheckEventsTask();
			end
		end, nil, 6);
	end
end

function Core:CheckEventInvites()
	Core:Debug("Starting event invites!");

	local isInGuild = IsInGuild();

	if (isInGuild) then
		local isEventOpen = false; --C_Calendar.IsEventOpen()

		if (not isEventOpen) then
			local guildName, _, _, realmName = GetGuildInfo("player");

			if (guildName == nil) then
				Core:Debug("Guild name is null");
				return;
			end

			if (realmName == nil) then
				realmName = GetNormalizedRealmName();
			end

			local regionId = GetCurrentRegionByGameVersion();

			Core:Debug("Guild name: " .. guildName .. ". Region id: " .. regionId);

			if (ns.UPCOMING_EVENTS.totalEvents) then
				for i = 1, ns.UPCOMING_EVENTS.totalEvents do
					local upcomingEvent = ns.UPCOMING_EVENTS.events[i];

					Core:Debug("Checking event: " .. upcomingEvent.titleWithKey);

					if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealmNormalized and regionId == upcomingEvent.guildRegionId) then
						--Core:Debug("Event found for guild: " .. upcomingEvent.titleWithKey);

						if (not processedEvents:contains(upcomingEvent.titleWithKey)) then
							local eventIndex = Core:searchForEvent(upcomingEvent);

							Core:Debug("Event search result: " ..
								upcomingEvent.titleWithKey .. ". Result: " .. eventIndex);

							if (eventIndex > 0) then
								local dayEvent = C_Calendar.GetDayEvent(0, upcomingEvent.day, eventIndex);
								Core:Debug(dayEvent.title ..
									" creator: " .. dayEvent.modStatus .. " eventIndex:" .. eventIndex);

								if (dayEvent.calendarType == "PLAYER" or dayEvent.calendarType == "GUILD_EVENT") then
									if (dayEvent.modStatus == "CREATOR" or dayEvent.modStatus == "MODERATOR") then
										Core:Debug("Trying opening event: " .. upcomingEvent.titleWithKey);
										workQueue:addTask(
											function() C_Calendar.OpenEvent(0, upcomingEvent.day, eventIndex) end, nil, 3);
										return;
										--Core:CreateEventInvites(upcomingEvent);
									else
										Core:Debug("Not creator or moderator!");
									end
								else
									Core:Debug("Not player event!");
								end
							end
						end
					end
				end

				Core:Debug("|cff00ff00Event process is completed!");
				isEventProcessCompleted = true;
				if (not isProcessedEventsPrinted and processedEvents:count() > 0) then
					isProcessedEventsPrinted = true;
					Core:PrintSuccessMessage("Event invites are completed. Number of events: " ..
						tostring(processedEvents:count()));
				end
			end
		else
			Core:Debug("Event is open!");
		end
	else
		Core:Debug("Player is not in a guild!");
	end

	--print("|cffffff00Guilds of WoW: |cff00ff00Calendar event processing completed!");
end

function Core:FindUpcomingEventFromName(eventTitle)
	Core:Debug("Trying to find event from title: " .. eventTitle);
	local isInGuild = IsInGuild();

	if (isInGuild) then
		local guildName, _, _, realmName = GetGuildInfo("player");

		if (guildName == nil) then
			return;
		end

		if (realmName == nil) then
			realmName = GetNormalizedRealmName();
		end

		local regionId = GetCurrentRegionByGameVersion();

		for i = 1, ns.UPCOMING_EVENTS.totalEvents do
			local upcomingEvent = ns.UPCOMING_EVENTS.events[i];

			if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealmNormalized and regionId == upcomingEvent.guildRegionId) then
				if (string.match(eventTitle, "*" .. upcomingEvent.eventKey)) then
					Core:Debug("Upcoming event found: " .. upcomingEvent.title);
					return upcomingEvent;
				end
			end
		end
	end

	return nil;
end

function Core:CreateEventInvites(upcomingEvent, closeAfterEnd)
	if (processedEvents:contains(upcomingEvent.titleWithKey)) then
		Core:Debug("Processed queue contains event!");
		return false;
	end

	Core:Debug("Processing event: " .. upcomingEvent.titleWithKey);

	local canSendInvite = C_Calendar.EventCanEdit();
	if (canSendInvite) then
		if (not upcomingEvent.isManualInvite) then
			Core:SetAttendance(upcomingEvent, closeAfterEnd);
			return;
		end

		local invitesNum = C_Calendar.GetNumInvites();

		if (invitesNum >= 100) then
			Core:SetAttendance(upcomingEvent, closeAfterEnd);
			return;
		end

		Core:Debug("CreateEventInvites: " .. upcomingEvent.titleWithKey .. ". Currently invited members: " .. invitesNum);

		local invitedCount = 0;

		for m = 1, upcomingEvent.totalMembers do
			local currentInviteMember = upcomingEvent.inviteMembers[m];
			local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized;
			local isMemberInvited = false;

			for a = 1, invitesNum do
				local inviteInfo = C_Calendar.EventGetInvite(a);

				if (inviteInfo and inviteInfo.name ~= nil) then
					if (string.find(inviteInfo.name, "-")) then
						--Core:Debug("Character with dash! " .. inviteInfo.name);

						if (inviteInfo.name == inviteName) then
							isMemberInvited = true;
							--Core:Debug("Member is invited with realm name: " .. inviteInfo.name);
						end
					else
						if (inviteInfo.name == currentInviteMember.name and inviteInfo.level == currentInviteMember.level and inviteInfo.classID == currentInviteMember.classId) then
							--Core:Debug("Member is invited: " .. inviteInfo.name);
							isMemberInvited = true;
						end
					end
				end
			end

			if (not isMemberInvited) then
				Core:Debug("Inviting: " ..
					inviteName .. "-" .. currentInviteMember.level .. "-" .. currentInviteMember.classId);
				workQueue:addTask(function() C_Calendar.EventInvite(inviteName) end, nil, GOW.consts.INVITE_INTERVAL);

				invitedCount = invitedCount + 1;
			end
		end

		if (invitedCount > 0) then
			Core:Debug("CreateEventInvites Ended: " .. upcomingEvent.title .. ". Invited: " .. tostring(invitedCount));
			workQueue:addTask(
				function()
					Core:Debug("Event invites completed: " .. upcomingEvent.titleWithKey);
					Core:SetAttendance(upcomingEvent, closeAfterEnd);
				end, nil, 10);
		else
			Core:SetAttendance(upcomingEvent, closeAfterEnd);
		end
	else
		Core:Debug("Cannot invite to this event!");
	end
end

function Core:SetAttendance(upcomingEvent, closeAfterEnd)
	local canSendInvite = C_Calendar.EventCanEdit();
	if (canSendInvite) then
		local invitesNum = C_Calendar.GetNumInvites();

		Core:Debug("SetAttendance: " .. upcomingEvent.titleWithKey .. ". Currently invited members: " .. invitesNum);

		local attendanceChangedCount = 0;
		local currentEventAttendances = {};
		local attendanceIndex = 1;
		local processAttendanceValues = (not processedEvents:contains(upcomingEvent.titleWithKey) and upcomingEvent.calendarType == 2);

		for a = 1, invitesNum do
			local inviteInfo = C_Calendar.EventGetInvite(a);

			if (inviteInfo.name) then
				if (inviteInfo.inviteStatus > 0) then
					local responseTime = C_Calendar.EventGetInviteResponseTime(a);
					local responeTimeText = nil;
					if (responseTime) then
						responeTimeText = responseTime.year ..
							"-" ..
							string.lpad(tostring(responseTime.month), 2, '0') ..
							"-" ..
							string.lpad(tostring(responseTime.monthDay), 2, '0') ..
							"T" ..
							string.lpad(tostring(responseTime.hour), 2, '0') ..
							":" .. string.lpad(tostring(responseTime.minute), 2, '0');
					end

					currentEventAttendances[attendanceIndex] = {
						name = inviteInfo.name,
						level = inviteInfo.level,
						attendance = inviteInfo.inviteStatus,
						classId = inviteInfo.classID,
						guid = inviteInfo.guid,
						date = responeTimeText
					};

					attendanceIndex = attendanceIndex + 1;
				end

				if (processAttendanceValues) then
					local isInvitationChanged = Core:SetAttendanceValues(upcomingEvent, inviteInfo, a);
					if (isInvitationChanged) then
						Core:Debug("Invitation changed");
						attendanceChangedCount = attendanceChangedCount + 1;
					end
				end
			end
		end

		local guildKey = Core:GetGuildKey();

		if (GOW.DB.profile.guilds[guildKey].events == nil) then
			GOW.DB.profile.guilds[guildKey].events = {};
		end

		local eventId = tostring(upcomingEvent.id);

		if (GOW.DB.profile.guilds[guildKey].events[eventId] == nil) then
			GOW.DB.profile.guilds[guildKey].events[eventId] = {};
		end

		GOW.DB.profile.guilds[guildKey].events[eventId].refreshTime = GetServerTime();

		if (GOW.DB.profile.guilds[guildKey].events[eventId].attendances == nil) then
			GOW.DB.profile.guilds[guildKey].events[eventId].attendances = {};
		end

		GOW.DB.profile.guilds[guildKey].events[eventId].attendances = currentEventAttendances;

		if (attendanceChangedCount > 0) then
			Core:Debug("SetAttendance Ended: " ..
				upcomingEvent.title .. ". SetAttendance: " .. tostring(attendanceChangedCount));
			workQueue:addTask(function() Core:EventAttendanceProcessCompleted(upcomingEvent, closeAfterEnd) end, nil,
				GOW.consts.INVITE_INTERVAL);
		else
			Core:EventAttendanceProcessCompleted(upcomingEvent, closeAfterEnd);
		end
	else
		Core:Debug("Cannot set attendance to this event!");
	end
end

function Core:SetAttendanceValues(upcomingEvent, inviteInfo, inviteIndex)
	for m = 1, upcomingEvent.totalMembers do
		local currentInviteMember = upcomingEvent.inviteMembers[m];

		if (currentInviteMember) then
			if (currentInviteMember.isManager or currentInviteMember.attendance > 1) then
				local isFound = false;

				if (string.find(inviteInfo.name, "-")) then
					isFound = inviteInfo.name == currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized;
				else
					isFound = inviteInfo.name == currentInviteMember.name and
						inviteInfo.level == currentInviteMember.level and
						inviteInfo.classID == currentInviteMember.classId;
				end

				if (isFound) then
					local isInvitationChanged = false;

					if (currentInviteMember.isManager) then
						if (inviteInfo.modStatus ~= "CREATOR" and inviteInfo.modStatus ~= "MODERATOR") then
							isInvitationChanged = true;
							Core:Debug("Setting member as moderator: " ..
								upcomingEvent.title .. ". Title: " .. inviteInfo.name);
							workQueue:addTask(function() C_Calendar.EventSetModerator(inviteIndex) end, nil,
								GOW.consts.INVITE_INTERVAL);
						end
					end

					if (currentInviteMember.forceUpdate or (currentInviteMember.attendance > 1 and inviteInfo.inviteStatus == 0)) then
						isInvitationChanged = true;
						Core:Debug("Setting member attendance: " ..
							upcomingEvent.title ..
							". Title: " ..
							inviteInfo.name ..
							". GoWAttendance: " ..
							tostring(currentInviteMember.attendance) ..
							". In-Game Attendance: " .. tostring(inviteInfo.inviteStatus));
						workQueue:addTask(
							function() C_Calendar.EventSetInviteStatus(inviteIndex, currentInviteMember.attendance - 1) end,
							nil, GOW.consts.INVITE_INTERVAL);
					end

					return isInvitationChanged;
				end
			end
		end
	end

	return false;
end

function Core:EventAttendanceProcessCompleted(upcomingEvent, closeAfterEnd)
	Core:Debug("Event attendances process completed: " .. upcomingEvent.titleWithKey);

	if (not processedEvents:contains(upcomingEvent.titleWithKey)) then
		processedEvents:push(upcomingEvent.titleWithKey);

		if (isNewEventBeingCreated) then
			Core:PrintSuccessMessage("New event is successfully created: " .. upcomingEvent.titleWithKey);
			isNewEventBeingCreated = false;
		elseif (not isEventProcessCompleted) then
			Core:PrintMessage("Event RSVP process completed: " .. upcomingEvent.titleWithKey);
		end
	end

	if (closeAfterEnd) then
		C_Calendar.CloseEvent();
	end
end

function Core:InviteAllToPartyCheck(event)
	local name, _ = UnitName("player");
	local me = name .. "-" .. GetNormalizedRealmName();

	local eligibleMembers = 0;

	for i = 1, event.totalMembers do
		local currentInviteMember = event.inviteMembers[i];

		if (currentInviteMember.attendance == 2 or currentInviteMember.attendance == 4 or currentInviteMember.attendance == 9) then
			local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized;

			if (inviteName ~= me) then
				eligibleMembers = eligibleMembers + 1;
			end
		end
	end

	if (eligibleMembers > 0) then
		invitingToPartyEvent = event;
		Core:OpenDialog("CONFIRM_INVITE_TO_PARTY", eligibleMembers);
	else
		Core:OpenDialog("INVITE_TO_PARTY_NOONE_FOUND");
	end
end

function Core:InviteAllToParty(event)
	local invitingMembers = {};
	local inviteIndex = 1;

	local name, _ = UnitName("player");
	local me = name .. "-" .. GetNormalizedRealmName();

	for i = 1, event.totalMembers do
		local currentInviteMember = event.inviteMembers[i];

		if (currentInviteMember.attendance == 2 or currentInviteMember.attendance == 4 or currentInviteMember.attendance == 9) then
			local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized;

			invitingMembers[inviteIndex] = inviteName;
			inviteIndex = inviteIndex + 1;
		end
	end

	Core:Debug("inviteIndex: " .. inviteIndex);

	if (inviteIndex > 1) then
		-- if (inviteIndex > 5) then
		-- 	local allowed = C_PartyInfo.AllowedToDoPartyConversion(true);

		-- 	--if (allowed) then
		-- 		C_PartyInfo.ConvertToRaid();
		-- 	-- else
		-- 	-- 	Core:Debug("ConvertToRaid not allowed");
		-- 	-- end
		-- end

		for a = 1, inviteIndex - 1 do
			local inviteName = invitingMembers[a];
			if (inviteName ~= me) then
				if not IsInRaid() and GetNumGroupMembers() == 5 then
					C_PartyInfo.ConvertToRaid();
				end

				C_PartyInfo.InviteUnit(inviteName);
			end
		end
	end
end

function Core:InviteAllTeamMembersToPartyCheck(teamData)
	if (teamData.totalMembers > 0) then
		invitingToPartyTeam = teamData;
		Core:OpenDialog("CONFIRM_INVITE_TEAM_TO_PARTY", teamData.totalMembers);
	else
		Core:OpenDialog("INVITE_TO_PARTY_NOONE_FOUND");
	end
end

function Core:InviteAllTeamMembersToParty(teamData)
	local invitingMembers = {};
	local inviteIndex = 1;

	for i = 1, teamData.totalMembers do
		local currentInviteMember = teamData.members[i];

		local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized;

		invitingMembers[inviteIndex] = inviteName;
		inviteIndex = inviteIndex + 1;
	end

	Core:Debug("inviteIndex: " .. inviteIndex);

	if (inviteIndex > 1) then
		-- if (inviteIndex > 5) then
		-- 	local allowed = C_PartyInfo.AllowedToDoPartyConversion(true);

		-- 	--if (allowed) then
		-- 		C_PartyInfo.ConvertToRaid();
		-- 	-- else
		-- 	-- 	Core:Debug("ConvertToRaid not allowed");
		-- 	-- end
		-- end

		for a = 1, inviteIndex - 1 do
			local inviteName = invitingMembers[a];
			if (inviteName ~= me) then
				if not IsInRaid() and GetNumGroupMembers() == 5 then
					C_PartyInfo.ConvertToRaid();
				end

				C_PartyInfo.InviteUnit(inviteName);
			end
		end
	end
end

function Core:GetGuildKey()
	local guildName, _, _, realmName = GetGuildInfo("player");

	if (guildName == nil) then
		return nil;
	end

	if (realmName == nil) then
		realmName = GetNormalizedRealmName();
	end

	local regionId = GetCurrentRegionByGameVersion();
	local guildKey = guildName .. "-" .. regionId .. "-" .. realmName;

	if (GOW.DB.profile.guilds == nil) then
		GOW.DB.profile.guilds = {};
	end

	if (GOW.DB.profile.guilds[guildKey] == nil) then
		GOW.DB.profile.guilds[guildKey] = {};
	end

	return guildKey;
end

function Core:SetRosterInfo()
	local numTotalMembers, _, _ = GetNumGuildMembers();

	if (numTotalMembers > 0) then
		local guildKey = Core:GetGuildKey();

		if (guildKey) then
			GOW.DB.profile.guilds[guildKey].rosterRefreshTime = GetServerTime();
			GOW.DB.profile.guilds[guildKey].motd = GetGuildRosterMOTD();
			GOW.DB.profile.guilds[guildKey].roster = {};
			GOW.DB.profile.guilds[guildKey].ranks = {};
			GOW.DB.profile.guilds[guildKey].keystones = {};
			GOW.DB.profile.guilds[guildKey].keystonesRefreshTime = nil;

			local keystoneData = nil;

			if (openRaidLib) then
				keystoneData = openRaidLib.GetAllKeystonesInfo();
			end
			local anyKeystoneFound = false;

			for i = 1, numTotalMembers do
				local name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName, achievementPoints, achievementRank, isMobile, isSoREligible, standingID, guid =
					GetGuildRosterInfo(i);
				if (name) then
					GOW.DB.profile.guilds[guildKey].roster[name] = {
						guid = guid,
						note = note,
						rank = rank,
						rankIndex = rankIndex,
						officerNote = officernote
					};

					local keystoneLevel = nil;
					local keystoneMapId = nil;

					if (C_AddOns.IsAddOnLoaded("AstralKeys") and AstralKeys) then
						if (level >= _G['AstralEngine'].EXPANSION_LEVEL) then
							keystoneLevel = _G['AstralEngine'].GetCharacterKeyLevel(name);
							keystoneMapId = _G['AstralEngine'].GetCharacterMapID(name);
						end
					end

					if (openRaidLib and keystoneData) then
						if (keystoneData) then
							for unitName, keystoneInfo in pairs(keystoneData) do
								if (keystoneInfo.level > 0) then
									local unitNameToCheck = unitName;

									if (not string.match(unitNameToCheck, "-")) then
										unitNameToCheck = unitNameToCheck .. "-" .. GetNormalizedRealmName();
									end

									if (unitNameToCheck == name) then
										keystoneLevel = keystoneInfo.level;
										keystoneMapId = keystoneInfo.challengeMapID;
									end
								end
							end
						end
					end

					if (keystoneLevel and keystoneMapId) then
						GOW.DB.profile.guilds[guildKey].keystones[name] = {
							keystoneLevel = keystoneLevel,
							keystoneMapId = keystoneMapId
						};

						anyKeystoneFound = true;
					end
				end
			end

			if (anyKeystoneFound) then
				GOW.DB.profile.guilds[guildKey].keystonesRefreshTime = GetServerTime();
			end

			local numTotalRanks = GuildControlGetNumRanks();

			for i = 1, numTotalRanks do
				local rankName = GuildControlGetRankName(i);

				if (rankName) then
					GOW.DB.profile.guilds[guildKey].ranks[i] = {
						index = i,
						name = rankName
					};
				end
			end
		end
	end
end

local isEventAttendancesInitialProcessStarted = false;
function Core:InitializeEventInvites()
	if (isCalendarOpened) then
		local guildKey = Core:GetGuildKey();

		if (guildKey and not isEventAttendancesInitialProcessStarted and ns.UPCOMING_EVENTS ~= nil and ns.UPCOMING_EVENTS.totalEvents > 0) then
			isEventAttendancesInitialProcessStarted = true;
			Core:Debug("Event attendance initial process started!");

			GOW.DB.profile.guilds[guildKey].events = {};
			Core:CheckEventInvites();
		end
	end
end

function Core:ToggleMinimap()
	GOW.DB.profile.minimap.hide = not GOW.DB.profile.minimap.hide;
	if GOW.DB.profile.minimap.hide then
		GOW.LDBIcon:Hide("gowicon");
	else
		GOW.LDBIcon:Show("gowicon");
	end
end

function Core:Debug(msg)
	if (GOW.consts.ENABLE_DEBUGGING) then
		Core:PrintMessage(" [DEBUG] " .. msg);
	end
end

function Core:PrintMessage(msg)
	print(Core:GetColoredStringWithBranding("ffcc00", msg));
end

function Core:PrintSuccessMessage(msg)
	print(Core:GetColoredStringWithBranding("00ff00", msg));
end

function Core:PrintErrorMessage(msg)
	print(Core:GetColoredStringWithBranding("ff0000", msg));
end

function Core:GetColoredStringWithBranding(color, msg)
	return Core:GetColoredString("00ff00", "Guilds of WoW: ") .. Core:GetColoredString(color, msg);
end

function Core:GetColoredString(color, msg)
	local colorString = "|cff";
	return colorString .. color .. msg .."|r";
end
