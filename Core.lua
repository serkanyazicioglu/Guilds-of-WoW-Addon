local ADDON_NAME = "GuildsOfWoW"
local VERSION = "v0.0.1beta"
local GOW = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME)
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
local isProcessing = false
local isPropogatingUpdate = false
local eventContainer = {}
local eventContainerScroll = {}

function GOW:OnInitialize()
	self.GUI = LibStub("AceGUI-3.0")
	--self.DB = LibStub("AceDB-3.0"):New("GoWDB")
	self.CONSOLE = LibStub("AceConsole-3.0")
	
	local consoleCommandFunc = function(msg, editbox)
		isProcessing = false
		Core:CreateUpcomingEvents()
	end
	
	self.CONSOLE:RegisterChatCommand("gow", consoleCommandFunc)

	string.lpad = function(str, len, char)
		if char == nil then char = ' ' end
		return str .. string.rep(char, len - #str)
	end

	eventContainer = GOW.GUI:Create("Frame")
	eventContainer:SetLayout("Fill")
	eventContainer:SetHeight(550)
	eventContainer:SetTitle("Guilds of WoW Event Creation")
	eventContainer:SetStatusText("Guilds of WoW. Type /gow for quick access")
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
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	  }
end

f:SetScript("OnEvent", function(self,event, ...)
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
		print("CALENDAR_UPDATE_EVENT_LIST")
		if (isPropogatingUpdate == false) then
			isPropogatingUpdate = true
			Core:CreateUpcomingEvents()
		end
	end
end)

function Core:CreateUpcomingEvents()
	local isInGuild = IsInGuild()

	if (isInGuild) then
		print("IsInGuild.")
	else
		isProcessing = true
		return
	end

	eventContainerScroll:ReleaseChildren()

	local guildName, _, _, realmName = GetGuildInfo("player")

	if (guildName == nil) then
		return
	end

	isProcessing = true

	if (realmName == nil) then
		realmName = GetRealmName()
		--GetNormalizedRealmName()
	end

	local regionId = GetCurrentRegion()

	print("totalEvents: " .. ns.UPCOMING_EVENTS.totalEvents)

	if (IsInGuild() and ns.UPCOMING_EVENTS.totalEvents > 0) then
		for i=1, ns.UPCOMING_EVENTS.totalEvents do
			local upcomingEvent = ns.UPCOMING_EVENTS.events[i]

			if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealm and regionId == upcomingEvent.guildRegionId) then
				--Core:CreateCalendarEvent(upcomingEvent)
				Core:AppendCalendarList(upcomingEvent)
			else
				print("guildName: ".. guildName)
				print("realmName: ".. realmName)
				print("regionId: ".. regionId)

				print("guildName: ".. upcomingEvent.guild)
				print("realmName: ".. upcomingEvent.guildRealm)
				print("regionId: ".. upcomingEvent.guildRegionId)

				print("Event belongs to another guild")
			end
		end

		eventContainerScroll:DoLayout()
	end

	isPropogatingUpdate = false
end

function Core:searchForEvent(event)
	C_Calendar.SetAbsMonth(event.month, event.year)

	local numDayEvents = C_Calendar.GetNumDayEvents(0, event.day)

	print("events found: " .. numDayEvents .. " : " .. event.day .. "/" .. event.month .. "/" .. event.year)

	if (numDayEvents > 0) then
		for i=1, numDayEvents do
			local dayEvent = C_Calendar.GetDayEvent(0, event.day, i)
			
			if (dayEvent.calendarType == "GUILD_EVENT" or dayEvent.calendarType == "PLAYER") then
				print("dayEvent: " .. dayEvent.title)

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

	local button = GOW.GUI:Create("Button")

	if eventIndex >= 0 then
		button:SetText("Event Created")
		button:SetDisabled(true)
	else
		button:SetText("Create Event")
		button:SetCallback("OnClick", function()
			eventContainer:Hide()
			Core:CreateCalendarEvent(event)
		end)
		eventContainer:Show()
	end
	eventGroup:AddChild(button)

	eventContainerScroll:AddChild(eventGroup)
end

function Core:CreateCalendarEvent(event)
	local eventIndex = Core:searchForEvent(event)

	if eventIndex >= 0 then
		print("Event found: " .. event.title)
	else
		local serverTime = GetServerTime()

		if (event.eventDate < serverTime) then
			print("Event passed: " .. event.id)
		else
			print("Creating event: ".. event.id .. " : " .. event.title .. " : " .. event.eventKey)
			C_Calendar.CloseEvent()
			C_Calendar.CreatePlayerEvent()
			C_Calendar.EventSetTitle(event.titleWithKey)
			C_Calendar.EventSetDescription(event.description)
			C_Calendar.EventSetType(event.eventType)
			C_Calendar.EventSetTime(event.hour, event.minute)
			C_Calendar.EventSetDate(event.month, event.day, event.year)

			if (event.isGuildEvent and event.minItemLevel == 0) then
				C_Calendar.MassInviteGuild(event.minLevel, event.maxLevel, event.maxRank)
			else 
				for i=1, event.totalMembers do
					C_Calendar.EventInvite(event.inviteMembers[i].characterName)
				end
			end
			
			StaticPopup_Show ("CONFIRM_EVENT_CREATION")
		end
	end
end