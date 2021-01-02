local ADDON_NAME = "GuildsOfWoW"
local VERSION = "v0.0.1beta"
local GOW = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME)
GuildsOfWow = GOW

local enableDebugging = false

GOW.consts = {}
GOW.consts.INVITE_INTERVAL = 5

local ns = select(2, ...)

local Core = {}
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("CALENDAR_NEW_EVENT")
f:RegisterEvent("CALENDAR_UPDATE_EVENT")
f:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
f:RegisterEvent("CALENDAR_UPDATE_GUILD_EVENTS")
f:RegisterEvent("CALENDAR_CLOSE_EVENT")
--f:RegisterEvent("CALENDAR_ACTION_PENDING")
--f:RegisterEvent("CALENDAR_UPDATE_INVITE_LIST")
local isProcessing = false
local isPropogatingUpdate = false
local eventContainer = {}
local eventContainerScroll = {}
local showWindow = true
local isDialogOpen = false
local workQueue = nil

local currentEventsCount = 0
local currentMultiInvitingEvent = nil

GOW.defaults = {
	profile = {
		version = 1,
        minimap = {hide = false}
    }
}

function GOW:OnInitialize()
	self.GUI = LibStub("AceGUI-3.0")
	self.DB = LibStub("AceDB-3.0"):New("GoWDB", GOW.defaults, "Default")
	self.LDB = LibStub("LibDataBroker-1.1")
	self.LDBIcon = LibStub("LibDBIcon-1.0")
	self.CONSOLE = LibStub("AceConsole-3.0")
	self.timers = {}
	LibStub("AceTimer-3.0"):Embed(self.timers)
	self.events = {}
	LibStub("AceEvent-3.0"):Embed(self.events)
	workQueue = self.WorkQueue.new()
	
	local consoleCommandFunc = function(msg, editbox)
		if (msg == "minimap") then
			Core:ToggleMinimap()
		else
			Core:ToggleWindow()
		end
	end
	
	self.CONSOLE:RegisterChatCommand("gow", consoleCommandFunc);

	local dataobj = self.LDB:NewDataObject("gowicon", {
		type = "data source",
		label = "Guilds of WoW",
		text = "Guilds of WoW",
		icon = "Interface\\Icons\\vas_guildfactionchange",
		OnTooltipShow = function(tooltip)
			tooltip:SetText("Guilds of WoW")
			if (ns.UPCOMING_EVENTS ~= nil) then
				tooltip:AddDoubleLine("Upcoming Events", currentEventsCount)
			end
			tooltip:Show()
		end,
		OnClick = function() Core:ToggleWindow() end
	})

	self.LDBIcon:Register("gowicon", dataobj, self.DB.profile.minimap);

	string.lpad = function(str, len, char)
		if char == nil then char = ' ' end
		return str .. string.rep(char, len - #str)
	end

	string.splitByDelimeter = function(str, delimiter)
		result = {};
		for match in (str..delimiter):gmatch("(.-)"..delimiter) do
			table.insert(result, match);
		end
		return result;
	end

	eventContainer = GOW.GUI:Create("Frame")
	eventContainer:SetLayout("Fill")
	eventContainer:SetHeight(550)
	eventContainer:SetTitle("Guilds of WoW")
	eventContainer:SetStatusText("Type /gow for quick access")
	eventContainer:SetCallback("OnClose", function(widget) eventContainer:Hide() end)
	eventContainer:SetCallback("OnEscapePressed", function(widget) eventContainer:Hide() end)
	--tinsert(UISpecialFrames, eventContainer:GetName())
	
	eventContainer:Hide()

	eventContainerScroll = GOW.GUI:Create("ScrollFrame")
	eventContainerScroll:SetLayout("Flow")
	eventContainerScroll:SetFullWidth(true)
	eventContainerScroll:SetFullHeight(true)
	eventContainer:AddChild(eventContainerScroll)

	StaticPopupDialogs["CONFIRM_EVENT_CREATION"] = {
		text = "Are you sure you want to create this event?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			C_Calendar.AddEvent()
			if(currentMultiInvitingEvent ~= nil) then
				Core:InviteMultiplePeopleToEvent()
			end
			Core:DialogClosed()			
		end,
		OnCancel = function ()
			currentMultiInvitingEvent = nil
			Core:DialogClosed()
			C_Calendar.CloseEvent()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }
end

f:SetScript("OnEvent", function(self,event, arg1, arg2)
	if event == "PLAYER_LOGIN" then
		isProcessing = false
	end
	if event == "GUILD_ROSTER_UPDATE" then
		if (isProcessing == false) then
			Core:CreateUpcomingEvents()
		end
	end
	-- if event == "CALENDAR_NEW_EVENT" or event == "CALENDAR_UPDATE_EVENT" or event == "CALENDAR_UPDATE_GUILD_EVENTS" or event == "CALENDAR_CLOSE_EVENT" then
	-- 	isProcessing = false
	-- 	Core:CreateUpcomingEvents()
	-- end
	if event == "CALENDAR_UPDATE_EVENT_LIST" then
		Core:Print("CALENDAR_UPDATE_EVENT_LIST")
		if (isPropogatingUpdate == false) then
			isPropogatingUpdate = true
			Core:CreateUpcomingEvents()
		end
	end

	-- if event == "CALENDAR_ACTION_PENDING" then
	-- 	--Core:Print("CALENDAR_ACTION_PENDING")
	-- 	if (not arg1) then
	-- 		Core:Print("CALENDAR_ACTION_PENDING: false")
	-- 		Core:InviteMultiplePeopleToEvent()
	-- 	else
	-- 		Core:Print("CALENDAR_ACTION_PENDING: true")
	-- 	end
	-- end

	-- if event == "CALENDAR_UPDATE_INVITE_LIST" then
	-- 	Core:Print("CALENDAR_UPDATE_INVITE_LIST")
	-- 	Core:InviteMultiplePeopleToEvent()
	-- end
end)

function Core:ToggleWindow()
	if (eventContainer:IsShown()) then
		eventContainer:Hide()
	else
		isPropogatingUpdate = true
		isProcessing = false
		Core:CreateUpcomingEvents()
		eventContainer:Show()
	end
end

function Core:CreateUpcomingEvents()
	local isInGuild = IsInGuild()

	if (isDialogOpen) then
		return
	end

	if (isInGuild == false) then
		isProcessing = true
		return
	end

	local guildName, _, _, realmName = GetGuildInfo("player")

	if (guildName == nil) then
		return
	end

	currentEventsCount = 0
	isProcessing = true
	eventContainerScroll:ReleaseChildren()

	if (realmName == nil) then
		realmName = GetRealmName()
		--GetNormalizedRealmName()
	end

	local regionId = GetCurrentRegion()

	if (isInGuild and ns.UPCOMING_EVENTS.totalEvents > 0) then
		for i=1, ns.UPCOMING_EVENTS.totalEvents do
			local upcomingEvent = ns.UPCOMING_EVENTS.events[i]

			if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealm and regionId == upcomingEvent.guildRegionId) then
				--Core:CreateCalendarEvent(upcomingEvent)
				Core:AppendCalendarList(upcomingEvent)
			else
				--Core:Print("guildName: ".. guildName)
				--Core:Print("realmName: ".. realmName)
				--Core:Print("regionId: ".. regionId)

				--Core:Print("guildName: ".. upcomingEvent.guild)
				--Core:Print("realmName: ".. upcomingEvent.guildRealm)
				--Core:Print("regionId: ".. upcomingEvent.guildRegionId)

				Core:Print("Event belongs to another guild: " .. upcomingEvent.title)
			end
		end

		--eventContainerScroll:DoLayout()
	end

	showWindow = false
	isPropogatingUpdate = false
end

function Core:searchForEvent(event)
	local serverTime = GetServerTime()

	if (event.eventDate < serverTime) then
		return 0
	end

	C_Calendar.SetAbsMonth(event.month, event.year)

	local numDayEvents = C_Calendar.GetNumDayEvents(0, event.day)

	--Core:Print("events found: " .. numDayEvents .. " : " .. event.day .. "/" .. event.month .. "/" .. event.year)

	if (numDayEvents > 0) then
		for i=1, numDayEvents do
			local dayEvent = C_Calendar.GetDayEvent(0, event.day, i)
			
			if (dayEvent.calendarType == "GUILD_EVENT" or dayEvent.calendarType == "PLAYER") then
				Core:Print("dayEvent: " .. dayEvent.title)

				if (string.match(dayEvent.title, "*" .. event.eventKey)) then
					return i
				end
			end
		end
	end

	return -1
end

function Core:AppendCalendarList(event)
	local fontPath = "Fonts\\FRIZQT__.TTF"
	local fontSize = 12

	local eventGroup = GOW.GUI:Create("InlineGroup")
	eventGroup:SetTitle(event.title)
	eventGroup:SetFullWidth(true)

	local eventDescriptionLabel = GOW.GUI:Create("SFX-Info")
	eventDescriptionLabel:SetLabel("Description")
	eventDescriptionLabel:SetText(event.description)
	eventGroup:AddChild(eventDescriptionLabel)

	local eventDateLabel = GOW.GUI:Create("SFX-Info")
	eventDateLabel:SetLabel("Date")
	eventDateLabel:SetText(event.dateText)
	eventGroup:AddChild(eventDateLabel)

	local eventHourLabel = GOW.GUI:Create("SFX-Info")
	eventHourLabel:SetLabel("Hour")
	eventHourLabel:SetText(event.hourText)
	eventGroup:AddChild(eventHourLabel)

	local eventDurationLabel = GOW.GUI:Create("SFX-Info")
	eventDurationLabel:SetLabel("Duration")
	eventDurationLabel:SetText(event.durationText)
	eventGroup:AddChild(eventDurationLabel)
	
	local levelText = event.minLevel

	if event.minLevel ~= event.maxLevel then
		levelText = levelText .. " -> " .. event.maxLevel
	end

	local eventLevelLabel = GOW.GUI:Create("SFX-Info")
	eventLevelLabel:SetLabel("Level")
	eventLevelLabel:SetText(levelText)
	eventGroup:AddChild(eventLevelLabel)

	if (event.minItemLevel > 0) then
		local eventMinItemLevelLabel = GOW.GUI:Create("SFX-Info")
		eventMinItemLevelLabel:SetLabel("Item Level")
		eventMinItemLevelLabel:SetText(event.minItemLevel .. "+")
		eventGroup:AddChild(eventMinItemLevelLabel)
	end
	
	local eventInvitingMembersLabel = GOW.GUI:Create("SFX-Info")
	eventInvitingMembersLabel:SetLabel("Inviting")

	if (event.isGuildEvent and event.minItemLevel == 0) then
		eventInvitingMembersLabel:SetText("All guildies within level range")
	else 
		eventInvitingMembersLabel:SetText(event.totalMembers .. " members")
	end
	eventGroup:AddChild(eventInvitingMembersLabel)

	local eventIndex = Core:searchForEvent(event)

	local buttonsGroup = GOW.GUI:Create("SimpleGroup")
	buttonsGroup:SetLayout("Flow")
	buttonsGroup:SetFullWidth(true)

	local eventButton = GOW.GUI:Create("Button")

	if eventIndex == 0 then
		eventButton:SetText("Event Passed")
		eventButton:SetDisabled(true)
	elseif eventIndex > 0 then
		eventButton:SetText("Event Created")
		eventButton:SetDisabled(true)
	else
		eventButton:SetText("Create Event")
		eventButton:SetCallback("OnClick", function()
			Core:CreateCalendarEvent(event)
		end)

		currentEventsCount = currentEventsCount + 1

		if (showWindow == true) then
			eventContainer:Show()
		end
	end
	buttonsGroup:AddChild(eventButton)

	local copyLinkButton = GOW.GUI:Create("Button")
	copyLinkButton:SetText("Copy Event Link")
	copyLinkButton:SetCallback("OnClick", function()
		
	end)
	buttonsGroup:AddChild(copyLinkButton)
	eventGroup:AddChild(buttonsGroup)

	eventContainerScroll:AddChild(eventGroup)
end

function Core:OpenDialog(dialogName)
	isDialogOpen = true
	StaticPopup_Show(dialogName)
end

function Core:DialogClosed()
	isDialogOpen = false
end

function Core:CreateCalendarEvent(event)
	if not workQueue:isEmpty() then
		print("|cffFF0000Another event is being formed right now! Please wait for a while and try again...")
		return
	end

	isDialogOpen = true
	local eventIndex = Core:searchForEvent(event)

	if eventIndex >= 0 then
		Core:DialogClosed()
		Core:Print("Event found or passed: " .. event.title)
	else
		C_Calendar.CloseEvent()
		C_Calendar.CreatePlayerEvent()
		C_Calendar.EventSetTitle(event.titleWithKey)
		C_Calendar.EventSetDescription(event.description)
		C_Calendar.EventSetType(event.eventType)
		C_Calendar.EventSetTime(event.hour, event.minute)
		C_Calendar.EventSetDate(event.month, event.day, event.year)

		currentMultiInvitingEvent = nil
		if (event.isGuildEvent and event.minItemLevel == 0) then
			C_Calendar.MassInviteGuild(event.minLevel, event.maxLevel, event.maxRank)
			Core:OpenDialog("CONFIRM_EVENT_CREATION")
		else
			currentMultiInvitingEvent = event
			Core:OpenDialog("CONFIRM_EVENT_CREATION")
		end
	end
end

function Core:InviteMultiplePeopleToEvent()
	if (currentMultiInvitingEvent ~= nil) then
		local event = currentMultiInvitingEvent

		local name, realm = UnitName("player")

		if (realm == nil) then
			realm = GetRealmName()
			--GetNormalizedRealmName()
		end

		local currentPlayer = name .. "-" .. realm

		local numInvites = C_Calendar.GetNumInvites()

		if (numInvites < event.totalMembers) then
			print("|cffffcc00Event invites are being sent in the background! Please wait for all events to complete before logging out.")

			for i=1, event.totalMembers do
				local currentInviteMember = event.inviteMembers[i]
				local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realm

				if (inviteName ~= currentPlayer) then
					workQueue:addTask(function() C_Calendar.EventInvite(inviteName) end, nil, GOW.consts.INVITE_INTERVAL)
				end
			end

			Core:IsEventFormingEnded()
		end
	end
end

function Core:IsEventFormingEnded()
	if workQueue:isEmpty() then
		print("|cff00ff00Event invites are completed.")
	else
		GOW.timers:ScheduleTimer(function() Core:IsEventFormingEnded() end, 10)
	end
end

function Core:ToggleMinimap()
	GOW.DB.profile.minimap.hide = not GOW.DB.profile.minimap.hide
	if GOW.DB.profile.minimap.hide then
		GOW.LDBIcon:Hide("gowicon");
	else
		GOW.LDBIcon:Show("gowicon");
	end
end

function Core:Print(msg)
	if (enableDebugging) then
		print("|cffffcc00" .. msg)
	end
end