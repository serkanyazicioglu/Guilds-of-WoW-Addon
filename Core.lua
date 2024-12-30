local ADDON_NAME = "GuildsOfWoW";
local FRAME_NAME = ADDON_NAME .. "MainFrame";
local GOW = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME);
GuildsOfWow = GOW;

GOW.consts = {
	INVITE_INTERVAL = 2,
	ENABLE_DEBUGGING = false,
	GUILD_EVENT = 1,
	PLAYER_EVENT = 2
};

GOW.defaults = {
	profile = {
		version = 1,
		minimap = { hide = false },
		warnNewEvents = true
	}
}

local getGowGameVersionId = function()
	-- if (GOW.consts.ENABLE_DEBUGGING) then
	-- 	print("WOW_PROJECT_ID: " .. WOW_PROJECT_ID);
	-- end

	if (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) then
		return 1;
	elseif (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) then
		return 2;
	elseif (WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC) then
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

function GetCurrentCharacterUniqueKey()
	local name, characterRealm = UnitName("player");
	if (characterRealm == nil) then
		characterRealm = GetNormalizedRealmName();
	end
	return name .. "-" .. characterRealm;
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
f:RegisterEvent("CALENDAR_ACTION_PENDING");

local isInitialLogin = false;
local isPropogatingUpdate = false;
local containerFrame = nil;
local containerTabs = nil;
local containerScrollFrame = nil;
local currentOpenDialog = nil;

local workQueue = nil;
local persistentWorkQueue = nil;

local processedEvents = nil;
local isEventProcessCompleted = false;
local isNewEventBeingCreated = false;
local isProcessedEventsPrinted = false;
local isCalendarOpened = false;
local isCalendarOpenEventBound = false;

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
		OnClick = GuildsOfWow_OnAddonButtonClick
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
	containerFrame.frame:SetFrameStrata("MEDIUM");
	containerFrame:SetTitle("Guilds of WoW");
	containerFrame:SetStatusText("Type /gow for quick access");
	containerFrame:SetCallback("OnClose", function(widget)
		containerFrame:Hide();
		if (currentOpenDialog) then
			StaticPopup_Hide(currentOpenDialog);
			currentOpenDialog = nil;
		end
	end);
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

	StaticPopupDialogs["NEW_EVENT_FOUND"] = {
		text = "There are events not registered on calendar.\r\n\r\nDo you wish to view Guilds of WoW upcoming events?",
		button1 = YES,
		button2 = NO,
		button3 = "Don't ask again",
		OnAccept = function(self, data)
			containerFrame:Show();
			containerTabs:SelectTab("events");
			Core:DialogClosed();
		end,
		OnCancel = function()
			Core:DialogClosed();
		end,
		OnAlt = function()
			GOW.DB.profile.warnNewEvents = false;
			Core:DialogClosed();
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["CONFIRM_EVENT_CREATION"] = {
		text = "Are you sure you want to create this event on in-game calendar?",
		button1 = ACCEPT,
		button2 = CANCEL,
		OnAccept = function(self, event)
			Core:ConfirmEventCreation(event);
		end,
		OnCancel = function()
			Core:DialogClosed();
		end,
		OnHide = function()
			Core:DialogClosed();
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["CONFIRM_GUILD_EVENT_CREATION"] = {
		text =
		"Are you sure you want to create this guild event on in-game calendar?\r\n\r\n(Note: Guild events RSVP integration only works single direction which is from WoW to GoW.)",
		button1 = ACCEPT,
		button2 = CANCEL,
		OnAccept = function(self, event)
			Core:ConfirmEventCreation(event);
		end,
		OnCancel = function()
			Core:DialogClosed();
		end,
		OnHide = function()
			Core:DialogClosed();
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
		OnAccept = function(self, data)
			C_GuildInfo.Invite(data);
			Core:PrintSuccessMessage("Invitation sent to " .. data);
			Core:DialogClosed();
		end,
		OnCancel = function()
			Core:DialogClosed();
		end,
		OnHide = function()
			Core:DialogClosed();
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		exclusive = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["CONFIRM_ADD_FRIEND"] = {
		text = ADD_CHARACTER_FRIEND,
		button1 = ACCEPT,
		button2 = CANCEL,
		OnAccept = function(self, data)
			C_FriendList.AddFriend(data, "Guilds of WoW recruitment");
			Core:DialogClosed();
		end,
		OnCancel = function()
			Core:DialogClosed();
		end,
		OnHide = function()
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
		OnAccept               = function(self, data)
			local text = self.editBox:GetText();
			if (text ~= nil and text ~= "") then
				SendChatMessage(text, "WHISPER", nil, data);
				Core:DialogClosed();
			end
		end,
		OnCancel               = function()
			Core:DialogClosed();
		end,
		OnHide                 = function()
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
			self.editBox:SetText(data);
			self.editBox:HighlightText();
			self.editBox:SetFocus();
		end,
		OnAccept               = function()
			Core:DialogClosed();
		end,
		OnHide                 = function()
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
		text           = "Are you sure you want to invite %s member(s) to your party?",
		button1        = ACCEPT,
		button2        = CANCEL,
		OnAccept       = function(self, data)
			Core:InviteAllToParty(data);
			Core:DialogClosed();
		end,
		OnCancel       = function()
			Core:DialogClosed();
		end,
		OnHide         = function()
			Core:DialogClosed();
		end,
		timeout        = 0,
		whileDead      = true,
		hideOnEscape   = true,
		exclusive      = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["CONFIRM_INVITE_TEAM_TO_PARTY"] = {
		text           = "Are you sure you want to invite %s member(s) to your party?",
		button1        = ACCEPT,
		button2        = CANCEL,
		OnAccept       = function(self, data)
			Core:InviteAllTeamMembersToParty(data);
			Core:DialogClosed();
		end,
		OnCancel       = function()
			Core:DialogClosed();
		end,
		OnHide         = function()
			Core:DialogClosed();
		end,
		timeout        = 0,
		whileDead      = true,
		hideOnEscape   = true,
		exclusive      = 1,
		preferredIndex = 1
	};

	StaticPopupDialogs["INVITE_TO_PARTY_NOONE_FOUND"] = {
		text                   = "No member from this event is available to invite.",
		button1                = OKAY,
		OnHide                 = function()
			Core:DialogClosed();
		end,
		timeout                = 0,
		enterClicksFirstButton = 1,
		whileDead              = true,
		hideOnEscape           = true,
		exclusive              = 1,
		preferredIndex         = 1
	};

	StaticPopupDialogs["INVITE_TO_PARTY_INVALID_CALENDAR"] = {
		text                   =
		"Only 'Player Event' attendances can be invited via addon. For 'Guild Events' you can create the event and use that event's 'Invite Members' functionality.",
		button1                = OKAY,
		OnHide                 = function()
			Core:DialogClosed();
		end,
		timeout                = 0,
		enterClicksFirstButton = 1,
		whileDead              = true,
		hideOnEscape           = true,
		exclusive              = 1,
		preferredIndex         = 1
	};

	StaticPopupDialogs["INVITE_TO_PARTY_USE_CALENDAR"] = {
		text                   = "This event is also created on calendar. Please use calendar event's 'Invite Members' button.",
		button1                = OKAY,
		OnHide                 = function()
			Core:DialogClosed();
		end,
		timeout                = 0,
		enterClicksFirstButton = 1,
		whileDead              = true,
		hideOnEscape           = true,
		exclusive              = 1,
		preferredIndex         = 1
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
			persistentWorkQueue:addTask(function()
				Core:InitializeEventInvites();
			end, nil, 5);
		else
			Core:InitializeEventInvites();
		end

		if (openRaidLib) then
			openRaidLib.RequestKeystoneDataFromGuild();
		end
	elseif event == "GUILD_ROSTER_UPDATE" then
		Core:SetRosterInfo();
	elseif event == "CALENDAR_ACTION_PENDING" then
		if (tostring(arg1) == "false")  then
			Core:Debug("CALENDAR_ACTION_PENDING: " .. tostring(arg1));
			Core:RefreshUpcomingEventsList();
		end
	elseif event == "CALENDAR_UPDATE_EVENT_LIST" then
		--f:UnregisterEvent("CALENDAR_UPDATE_EVENT_LIST");

		if (CalendarFrame and not isCalendarOpenEventBound) then
			isCalendarOpenEventBound = true;
			hooksecurefunc(CalendarFrame, "Show", function()
				if (isEventProcessCompleted and not isNewEventBeingCreated) then
					Core:Debug("Clearing tasks: CALENDAR_UPDATE_EVENT_LIST");
					workQueue:clearTasks();
				end
				containerFrame:Hide();
			end);
			if (containerFrame:IsShown()) then
				containerFrame:Hide();
			end
		end

		--Core:InitializeEventInvites();
		--Core:RefreshUpcomingEventsList();
	elseif event == "CALENDAR_NEW_EVENT" or event == "CALENDAR_UPDATE_EVENT" or event == "CALENDAR_UPDATE_GUILD_EVENTS" then
		if (CalendarFrame and CalendarFrame:IsShown()) then
			Core:Debug("Calendar frame is open.");
			return;
		end

		if (event == "CALENDAR_UPDATE_GUILD_EVENTS") then
			--f:UnregisterEvent("CALENDAR_UPDATE_GUILD_EVENTS");
			Core:InitializeEventInvites();
		end

		Core:RefreshUpcomingEventsList();
	elseif event == "CALENDAR_OPEN_EVENT" then
		if (CalendarFrame and CalendarFrame:IsShown()) then
			Core:Debug("Calendar frame is open.");
			return;
		end

		if (C_Calendar.IsEventOpen()) then
			local eventInfo = C_Calendar.GetEventInfo();

			if (eventInfo and eventInfo.title and string.len(eventInfo.title) > 0) then
				Core:Debug("CALENDAR_OPEN_EVENT: Opened: " ..
					eventInfo.title .. ". Calendar Type: " .. eventInfo.calendarType);
				Core:ClearEventInvites(false);
				isNewEventBeingCreated = false;

				if (eventInfo.calendarType == "GUILD_EVENT" or eventInfo.calendarType == "PLAYER") then
					local upcomingEvent = Core:FindUpcomingEventFromName(eventInfo.title);

					if (upcomingEvent) then
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
		if (isNewEventBeingCreated) then
			isNewEventBeingCreated = false;

			if (CalendarFrame and CalendarFrame:IsShown()) then
				isEventProcessCompleted = false;
			end
		end

		if (not isEventProcessCompleted) then
			Core:ClearEventInvites(true);
		end
	elseif event == "CALENDAR_UPDATE_INVITE_LIST" then
		if (not isEventProcessCompleted and CalendarFrame and CalendarFrame:IsShown()) then
			Core:Debug("Calendar frame is open.");
			return;
		end

		if (C_Calendar.IsEventOpen()) then
			local eventInfo = C_Calendar.GetEventInfo();

			if (processedEvents:contains(eventInfo.title)) then
				if (eventInfo.title == "") then
					Core:ClearEventInvites(false);
				else
					local upcomingEvent = Core:FindUpcomingEventFromName(eventInfo.title);
					if (upcomingEvent) then
						--processedEvents:remove(eventInfo.title);
						Core:SetAttendance(upcomingEvent, false);
					end
				end
			elseif (workQueue:isEmpty()) then
				Core:Debug("Continuing event attendance and moderation!");
				local upcomingEvent = Core:FindUpcomingEventFromName(eventInfo.title);
				if (upcomingEvent) then
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
		if (CalendarFrame) then
			HideUIPanel(CalendarFrame);
		end
		StaticPopup_Hide("NEW_EVENT_FOUND");

		Core:RefreshApplication();
		containerFrame:Show();
	end
end

function Core:RefreshUpcomingEventsList()
	Core:Debug("RefreshUpcomingEventsList: containerFrame:IsShown(): " .. tostring(containerFrame:IsShown()) .. ". isPropogatingUpdate: " .. tostring(isPropogatingUpdate) .. ". selectedTab: " .. selectedTab .. ". isEventProcessCompleted: " .. tostring(isEventProcessCompleted) .. ". isNewEventBeingCreated: " .. tostring(isNewEventBeingCreated));
	if (containerFrame:IsShown() and isPropogatingUpdate == false and selectedTab == "events" and isEventProcessCompleted and not isNewEventBeingCreated) then
		Core:Debug("Adding to work queue: CreateUpcomingEvents");
		persistentWorkQueue:addTask(function()
			isPropogatingUpdate = true;
			Core:CreateUpcomingEvents();
		end, nil, 2);
	end
end

function Core:CreateUpcomingEvents()
	if (selectedTab ~= "events") then
		Core:Debug("Selected tab is not events.");
		return;
	end

	containerScrollFrame:ReleaseChildren();

	if (ns.UPCOMING_EVENTS == nil) then
		Core:AppendMessage(
			"Upcoming events data is not found! Please make sure your sync app is installed and working properly!", true);
	else
		local isInGuild = IsInGuild();

		if (not isInGuild) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false);
			return;
		end

		local guildName, _, _, realmName = GetGuildInfo("player");

		if (not guildName) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false);
			return;
		end

		if (ns.UPCOMING_EVENTS.totalEvents > 0) then
			if (not isEventProcessCompleted or isNewEventBeingCreated or C_Calendar.IsActionPending()) then
				Core:AppendMessage("Addon is busy right now! Please wait for a while...");
				isPropogatingUpdate = false;
				return;
			end
		end

		Core:Debug("Core:CreateUpcomingEvents");
		if (not realmName) then
			realmName = GetNormalizedRealmName();
		end

		local regionId = GetCurrentRegionByGameVersion();

		local hasAnyData = false;

		if (ns.UPCOMING_EVENTS.totalEvents > 0) then
			Core:ResetCalendar();

			for i = 1, ns.UPCOMING_EVENTS.totalEvents do
				local upcomingEvent = ns.UPCOMING_EVENTS.events[i];

				if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealmNormalized and regionId == upcomingEvent.guildRegionId) then
					if (Core:AppendCalendarList(upcomingEvent)) then
						hasAnyData = true;
					end
				end
			end
		end

		if (not hasAnyData) then
			Core:AppendMessage(
				"This guild either doesn't have any upcoming events that you are a member of, or you are not an event manager!\r\n\r\nGuild: " ..
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

function Core:ResetCalendar()
	local monthInfo = C_Calendar.GetMonthInfo();
	local calendarMonth = monthInfo.month;
	local calendarYear = monthInfo.year;

	local serverTime = C_DateAndTime.GetServerTimeLocal();
	local serverMonth = tonumber(date("%m", serverTime));
	local serverYear = tonumber(date("%Y", serverTime));

	if (calendarMonth ~= serverMonth or calendarYear ~= serverYear) then
		Core:Debug("Resetting calendar to current date. Current: " .. calendarMonth .. "/" .. calendarYear .. " - Server: " .. serverMonth .. "/" .. serverYear);
		C_Calendar.SetAbsMonth(serverMonth, serverYear);
	end
end

function Core:searchForEvent(event)
	local serverTime = C_DateAndTime.GetServerTimeLocal();

	if (CalendarFrame and CalendarFrame:IsShown()) then
		return -2;
	end

	if (event.eventDate < serverTime) then
		return 0;
	end

	--C_Calendar.SetAbsMonth(event.month, event.year);
	--local month, year = C_Calendar.GetMonthInfo();

	local offsetMonths = tonumber(date("%m", event.eventDate)) - tonumber(date("%m", serverTime))

	if (offsetMonths < 0) then
		offsetMonths = offsetMonths + 12;
	end

	local numDayEvents = C_Calendar.GetNumDayEvents(offsetMonths, event.day);

	--Core:Debug("Searching: " .. event.titleWithKey .. ". Found: " .. numDayEvents .. " : " .. event.day .. "/" .. event.month .. "/" .. event.year);

	if (numDayEvents > 0) then
		for i = 1, numDayEvents do
			local dayEvent = C_Calendar.GetDayEvent(offsetMonths, event.day, i);

			if (dayEvent.calendarType == "GUILD_EVENT" or dayEvent.calendarType == "PLAYER") then
				--Core:Debug("dayEvent: " .. dayEvent.title .. " - " .. dayEvent.calendarType);

				if (string.match(dayEvent.title, "*" .. event.eventKey)) then
					return i, offsetMonths, dayEvent;
				end
			end
		end
	end

	return -1
end

function Core:AppendMessage(message, appendReloadUIButton)
	local fontPath = STANDARD_TEXT_FONT;
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
	messageLabel:SetFont(fontPath, fontSize, "");
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
	if not Core:IsInvitedToEvent(event) then
		return false;
	end
	
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
	elseif (event.calendarType == GOW.consts.PLAYER_EVENT) then
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

	if (event.calendarType == GOW.consts.GUILD_EVENT) then
		invitineDetailsText = "All guildies";
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

	local eventIndex, offsetMonths, dayEvent = Core:searchForEvent(event);

	local buttonsGroup = GOW.GUI:Create("SimpleGroup");
	buttonsGroup:SetLayout("Flow");
	buttonsGroup:SetFullWidth(true);

	if (canAddEvent) then
		local eventCalendarTypeLabel = GOW.GUI:Create("SFX-Info");
		eventCalendarTypeLabel:SetLabel("Calendar");
		if (event.calendarType == GOW.consts.GUILD_EVENT) then
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
				if (event.calendarType == GOW.consts.PLAYER_EVENT) then
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
		Core:OpenDialogWithData("COPY_TEXT", nil, nil, event.webUrl);
	end);
	buttonsGroup:AddChild(copyLinkButton);

	if (canAddEvent and eventIndex < 0) then
		local copyKeyButton = GOW.GUI:Create("Button");
		copyKeyButton:SetText("Copy Key");
		copyKeyButton:SetWidth(100);
		copyKeyButton:SetCallback("OnClick", function()
			Core:OpenDialogWithData("COPY_TEXT", nil, nil, event.eventKey);
		end);

		copyKeyButton:SetCallback("OnEnter", function(self)
			local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT");
			GOW.tooltip = tooltip;

			local line = tooltip:AddLine();
			tooltip:SetCell(line, 1,
				"If you've already created an in-game event related to this record, you can append this key to the end of the in-game event title for GoW synchronization.",
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
	return true;
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
		Core:OpenDialogWithData("COPY_TEXT", nil, nil, teamData.webUrl);
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

	local recruitmentApplicationInviteLink = recruitmentApplication.title ..
		"-" .. recruitmentApplication.realmNormalized;

	local inviteToGuildButton = GOW.GUI:Create("Button");
	inviteToGuildButton:SetText("Invite to Guild");
	inviteToGuildButton:SetWidth(140);
	inviteToGuildButton:SetCallback("OnClick", function()
		Core:OpenDialogWithData("CONFIRM_INVITE_TO_GUILD", recruitmentApplication.title, nil,
			recruitmentApplicationInviteLink);
	end);
	buttonsGroup:AddChild(inviteToGuildButton);

	local inviteToPartyButton = GOW.GUI:Create("Button");
	inviteToPartyButton:SetText("Invite to Party");
	inviteToPartyButton:SetWidth(140);
	inviteToPartyButton:SetCallback("OnClick", function()
		C_PartyInfo.InviteUnit(recruitmentApplicationInviteLink);
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
		Core:OpenDialogWithData("CONFIRM_ADD_FRIEND", recruitmentApplication.title, nil,
			recruitmentApplicationInviteLink);
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
		Core:OpenDialogWithData("WHISPER_PLAYER", nil, nil,
			recruitmentApplicationInviteLink);
	end);
	buttonsGroup2:AddChild(whisperButton);

	local copyButton = GOW.GUI:Create("Button");
	copyButton:SetText("Copy Link");
	copyButton:SetWidth(140);
	copyButton:SetCallback("OnClick", function()
		Core:OpenDialogWithData("COPY_TEXT", nil, nil, recruitmentApplication.webUrl);
	end);
	buttonsGroup2:AddChild(copyButton);

	itemGroup:AddChild(buttonsGroup2);

	containerScrollFrame:AddChild(itemGroup);
end

function Core:OpenDialog(dialogName)
	currentOpenDialog = dialogName;
	StaticPopup_Show(dialogName);
end

function Core:OpenDialogWithParams(dialogName, parameterStr)
	currentOpenDialog = dialogName;
	StaticPopup_Show(dialogName, parameterStr);
end

function Core:OpenDialogWithData(dialogName, param1, param2, data)
	currentOpenDialog = dialogName;
	StaticPopup_Show(dialogName, param1, param2, data);
end

function Core:DialogClosed()
	currentOpenDialog = nil;
end

function Core:ShowTooltip(container, header, message)
end

function Core:CreateCalendarEvent(event)
	if (event.calendarType == GOW.consts.PLAYER_EVENT and event.totalMembers >= 100) then
		Core:PrintErrorMessage(
			"You cannot create events with more than 100 members! To proceed, narrow your audience by using filters, binding a team, or disabling filters entirely to create a guild event.");
		return;
	end

	if (not workQueue:isEmpty() or not isEventProcessCompleted or isNewEventBeingCreated) then
		Core:PrintErrorMessage("Addon is busy right now! Please wait for a while and try again...");
		return;
	end
	
	if (event.calendarType == GOW.consts.GUILD_EVENT) then
		Core:OpenDialogWithData("CONFIRM_GUILD_EVENT_CREATION", nil, nil, event);
	else
		Core:OpenDialogWithData("CONFIRM_EVENT_CREATION", nil, nil, event);
	end
end

function Core:ConfirmEventCreation(event)
	if (C_Calendar.IsEventOpen()) then
		C_Calendar.CloseEvent();
	end

	isNewEventBeingCreated = true;
	Core:CreateUpcomingEvents();
	Core:ClearEventInvites(false);

	if (event.calendarType == GOW.consts.GUILD_EVENT) then
		C_Calendar.CreateGuildSignUpEvent();
	else
		C_Calendar.CreatePlayerEvent();
	end
	C_Calendar.EventSetTitle(event.titleWithKey);
	C_Calendar.EventSetDescription(event.description);
	C_Calendar.EventSetType(event.eventType);
	C_Calendar.EventSetTime(event.hour, event.minute);
	C_Calendar.EventSetDate(event.month, event.day, event.year);

	C_Calendar.AddEvent();
	if (event.calendarType == GOW.consts.PLAYER_EVENT) then
		Core:InviteMultiplePeopleToEvent(event);
	else
		Core:EventAttendanceProcessCompleted(event, true);
	end
	Core:DialogClosed();
end

function Core:InviteMultiplePeopleToEvent(event)
	local currentPlayer = GetCurrentCharacterUniqueKey();

	local numInvites = C_Calendar.GetNumInvites();

	if (numInvites < event.totalMembers and numInvites < 100) then
		Core:PrintMessage(
			"Event invites are being processed in the background. Please wait for the process to complete before logging out.");

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

function Core:ClearEventInvites(restartInvites)
	Core:Debug("Invites are canceled! Restart invites: " .. tostring(restartInvites));
	workQueue:clearTasks();

	if (restartInvites) then
		Core:AddCheckEventsTask();
	end
end

local addCheckEventTimer = nil;

function Core:AddCheckEventsTask()
	if (addCheckEventTimer) then
		Core:Debug("Clearing add check event timer.");
		GOW.timers:CancelTimer(addCheckEventTimer);
	end

	addCheckEventTimer = GOW.timers:ScheduleTimer(function()
		if ((CalendarFrame and CalendarFrame:IsShown()) or C_Calendar.IsEventOpen()) then
			Core:Debug("Calendar or an event open! Re-trying checking event invites later...");
			Core:AddCheckEventsTask();
		else
			Core:CheckEventInvites();
		end
	end, 6);
end

function Core:IsInvitedToEvent(upcomingEvent)
	if (upcomingEvent.isEventMember) then
		if (upcomingEvent.calendarType == 1) then
			return true;
		else
			local currentCharacterInvite = GetCurrentCharacterUniqueKey();

			for m = 1, upcomingEvent.totalMembers do
				local currentInviteMember = upcomingEvent.inviteMembers[m];
				if (currentInviteMember and currentCharacterInvite == currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized) then
					return true;
				end
			end
		end
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
				Core:ResetCalendar();
				local hasAnyUninvitedEvent = false;

				for i = 1, ns.UPCOMING_EVENTS.totalEvents do
					local upcomingEvent = ns.UPCOMING_EVENTS.events[i];

					if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealmNormalized and regionId == upcomingEvent.guildRegionId) then
						Core:Debug("Event found for guild: " .. upcomingEvent.titleWithKey);

						if (not processedEvents:contains(upcomingEvent.titleWithKey)) then
							local eventIndex, offsetMonths, dayEvent = Core:searchForEvent(upcomingEvent);

							Core:Debug("Event search result: " .. upcomingEvent.titleWithKey .. ". Result: " .. eventIndex);

							if (eventIndex == -2) then
								Core:Debug("Aborting invites: CheckEventInvites.");
								workQueue:clearTasks();
								return;
							elseif (eventIndex == -1) then
								if (Core:IsInvitedToEvent(upcomingEvent)) then
									hasAnyUninvitedEvent = true;
								end
							elseif (eventIndex > 0) then
								Core:Debug(dayEvent.title .. " creator: " .. dayEvent.modStatus .. " eventIndex:" .. eventIndex);

								if (dayEvent.calendarType == "PLAYER" or dayEvent.calendarType == "GUILD_EVENT") then
									if (dayEvent.modStatus == "CREATOR" or dayEvent.modStatus == "MODERATOR") then
										if (CalendarFrame and CalendarFrame:IsShown()) then
											Core:Debug("Calendar frame is open.");
										else
											Core:Debug("Trying opening event: " .. upcomingEvent.titleWithKey);
											if (not C_Calendar.OpenEvent(offsetMonths, upcomingEvent.day, eventIndex)) then
												Core:Debug("Calendar open event failed. Retrying updates.");
												Core:AddCheckEventsTask();
											end
										end
										return;
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

				if (not isProcessedEventsPrinted) then
					isProcessedEventsPrinted = true;

					if (processedEvents:count() > 0) then
						GOW.DB.profile.guilds[Core:GetGuildKey()].eventsRefreshTime = GetServerTime();
						Core:PrintSuccessMessage("Event invites have been completed. Number of events processed: " ..
							tostring(processedEvents:count()));
					end

					if (containerFrame:IsShown()) then
						Core:CreateUpcomingEvents();
					else
						local canAddEvent = C_Calendar.CanAddEvent();
						if (GOW.DB.profile.warnNewEvents and canAddEvent and hasAnyUninvitedEvent) then
							Core:OpenDialog("NEW_EVENT_FOUND");
						end
					end
				end
				
			end
		else
			Core:Debug("Event is open!");
		end
	else
		Core:Debug("Player is not in a guild!");
	end
end

function Core:FindUpcomingEventFromName(eventTitle)
	Core:Debug("Trying to find event from title: " .. eventTitle);
	local isInGuild = IsInGuild();

	if (isInGuild) then
		local guildName, _, _, realmName = GetGuildInfo("player");

		if (guildName == nil) then
			return nil;
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
		if (upcomingEvent.calendarType == GOW.consts.GUILD_EVENT) then
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
					local responeTimeFormatted = nil;
					if (responseTime) then
						responeTimeFormatted = responseTime.year ..
							"-" ..
							string.lpad(tostring(responseTime.month), 2, '0') ..
							"-" ..
							string.lpad(tostring(responseTime.monthDay), 2, '0') ..
							"T" ..
							string.lpad(tostring(responseTime.hour), 2, '0') ..
							":" ..
							string.lpad(tostring(responseTime.minute), 2, '0');
					end

					currentEventAttendances[attendanceIndex] = {
						name = inviteInfo.name,
						level = inviteInfo.level,
						attendance = inviteInfo.inviteStatus,
						classId = inviteInfo.classID,
						guid = inviteInfo.guid,
						date = responeTimeFormatted
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
			if (containerFrame:IsShown()) then
				Core:CreateUpcomingEvents();
			end
		elseif (not isEventProcessCompleted) then
			Core:PrintMessage("Event RSVP process completed: " .. upcomingEvent.titleWithKey);
		end
	end

	if (closeAfterEnd) then
		C_Calendar.CloseEvent();
	end
end

function Core:InviteAllToPartyCheck(event)
	local me = GetCurrentCharacterUniqueKey();

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
		Core:OpenDialogWithData("CONFIRM_INVITE_TO_PARTY", eligibleMembers, nil, event);
	else
		Core:OpenDialog("INVITE_TO_PARTY_NOONE_FOUND");
	end
end

function Core:InviteAllToParty(event)
	local invitingMembers = {};
	local inviteIndex = 1;

	local me = GetCurrentCharacterUniqueKey();

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
		Core:OpenDialogWithData("CONFIRM_INVITE_TEAM_TO_PARTY", teamData.totalMembers, nil, teamData);
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
			local me = GetCurrentCharacterUniqueKey();
			local isKeystonesEnabled = getGowGameVersionId() == 1;

			GOW.DB.profile.guilds[guildKey].rosterRefreshTime = GetServerTime();
			GOW.DB.profile.guilds[guildKey].motd = GetGuildRosterMOTD();
			GOW.DB.profile.guilds[guildKey].roster = {};
			GOW.DB.profile.guilds[guildKey].ranks = {};

			if (isKeystonesEnabled) then
				GOW.DB.profile.guilds[guildKey].keystones = {};
				GOW.DB.profile.guilds[guildKey].keystonesRefreshTime = nil;
			end

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
						rankIndex = rankIndex,
						officerNote = officernote
					};

					if (isKeystonesEnabled and C_MythicPlus.IsMythicPlusActive()) then
						local keystoneLevel = nil;
						local keystoneMapId = nil;

						if (name == me) then
							keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel();
							keystoneMapId = C_MythicPlus.GetOwnedKeystoneChallengeMapID();
						else
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
						end

						if (keystoneLevel and keystoneMapId) then
							GOW.DB.profile.guilds[guildKey].keystones[name] = {
								keystoneLevel = keystoneLevel,
								keystoneMapId = keystoneMapId,
								date = GetServerTime()
							};

							anyKeystoneFound = true;
						end
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

			if (GOW.DB.profile.guilds[guildKey].eventsRefreshTime and ns.UPCOMING_EVENTS.exportTime and ns.UPCOMING_EVENTS.exportTime < GOW.DB.profile.guilds[guildKey].eventsRefreshTime) then
				isEventProcessCompleted = true;

				Core:PrintMessage("The most recently imported data has already been processed, the RSVP synchronization will be skipped...");
			else
				Core:Debug("Event attendance initial process started!");

				GOW.DB.profile.guilds[guildKey].events = {};
				Core:CheckEventInvites();
			end
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

function GuildsOfWow_OnAddonButtonClick(name, mouseButton)
	if mouseButton == "RightButton" then
		GOW:OpenSettings();
	else
		Core:ToggleWindow();
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
	return colorString .. color .. msg .. "|r";
end
