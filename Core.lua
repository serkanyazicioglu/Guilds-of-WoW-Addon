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
	eventContainer:SetLayout("List")
	eventContainer:SetTitle("Guilds of WoW Event Creation")
	eventContainer:SetStatusText("Guilds of WoW. Type /gow for quick access")
	eventContainer:SetCallback("OnClose", function(widget) eventContainer:Hide() end)
	--eventContainer:SetCallback("OnEscapePressed", function(widget) eventContainer:Hide() end)
	--tinsert(UISpecialFrames, eventContainer:GetName())
	
	eventContainer:Hide()
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

	StaticPopupDialogs["EXAMPLE_HELLOWORLD"] = {
		text = "Do you want to greet the world today?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			--GreetTheWorld()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
	  }

	  StaticPopup_Show ("EXAMPLE_HELLOWORLD")

	eventContainer:ReleaseChildren()

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

				-- C_Calendar.OpenEvent(0, event.day, i)
				-- -- local otherEvent = C_Calendar.GetEventInfo()

				-- if (otherEvent ~= nil) then
				-- 	print("description: " .. otherEvent.description)
				-- else 
				-- 	print("event is null")
				-- end

				-- if (otherEvent ~= nil and string.match(otherEvent.description, "*" .. event.eventKey)) then
				-- 	C_Calendar.CloseEvent()
				-- 	return i
				-- end
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

	local eventHeading = GOW.GUI:Create("InteractiveLabel")
	eventHeading:SetText(event.title)
	eventHeading:SetFont(fontPath, 15)
	eventHeading:SetFullWidth(true)
	--eventGroup:AddChild(eventHeading)

	local eventTitleLabel = GOW.GUI:Create("Label")
	eventTitleLabel:SetText(event.description)
	eventTitleLabel:SetFont(fontPath, fontSize)
	eventHeading:SetFullWidth(true)
	eventGroup:AddChild(eventTitleLabel)

	local eventDateLabel = GOW.GUI:Create("Label")
	eventDateLabel:SetText(event.dateText)
	eventDateLabel:SetFont(fontPath, fontSize)
	eventGroup:AddChild(eventDateLabel)
	
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

	eventContainer:AddChild(eventGroup)
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
			--local test = GetGuildInfo("player")
			--if (test == nil)
			-- then
				--   status = false 
			--end

			C_Calendar.CloseEvent()
			C_Calendar.CreatePlayerEvent()
			--end
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
			Core:ShowConfirmWindow(event)
		end
	end
end

function Core:ShowConfirmWindow(event)
	local frame = GOW.GUI:Create("Window")
	--frame:SetCallback("OnClose",function(widget) C_Calendar.AddEvent(); RCE.core:scheduleRepeatCheck(); frame:Release() end)
	--frame:SetCallback("OnClose",function(widget) RCE.core:scheduleRepeatCheck() end)
	frame:SetLayout("List")
	frame:EnableResize(false)
	frame:SetTitle("Guilds of WoW Event Creation")
	frame:SetWidth(400)
	frame:SetHeight(400)
	frame:SetFullHeight(false)
	frame:SetCallback("OnClose", function(widget) GOW.GUI:Release(widget) eventContainer:Show() end)

	local fontPath = "Fonts\\FRIZQT__.TTF"
	local fontSize = 12

	local confirmLabel = GOW.GUI:Create("Label")
	confirmLabel:SetText("A new event is about to be created!")
	confirmLabel:SetFont(fontPath, fontSize)
	frame:AddChild(confirmLabel)

	local eventTitleLabel = GOW.GUI:Create("Label")
	eventTitleLabel:SetText("Event Name: " .. event.title)
	eventTitleLabel:SetFont(fontPath, fontSize)
	--eventTitleLabel:SetWordWrap(true)
	frame:AddChild(eventTitleLabel)

	local eventDescriptionLabel = GOW.GUI:Create("Label")
	eventDescriptionLabel:SetText("Event Description: " .. event.description)
	eventDescriptionLabel:SetFont(fontPath, fontSize)
	frame:AddChild(eventDescriptionLabel)

	local eventDateLabel = GOW.GUI:Create("Label")
	eventDateLabel:SetText("Date: " .. event.dateText)
	eventDateLabel:SetFont(fontPath, fontSize)
	frame:AddChild(eventDateLabel)

	local eventMinLevelLabel = GOW.GUI:Create("Label")
	eventMinLevelLabel:SetText("Min Level: " .. event.minLevel)
	eventMinLevelLabel:SetFont(fontPath, fontSize)
	frame:AddChild(eventMinLevelLabel)

	local eventMaxLevelLabel = GOW.GUI:Create("Label")
	eventMaxLevelLabel:SetText("Max Level: " .. event.maxLevel)
	eventMaxLevelLabel:SetFont(fontPath, fontSize)
	frame:AddChild(eventMaxLevelLabel)

	if (event.minItemLevel > 0) then
		local eventMinItemLevelLabel = GOW.GUI:Create("Label")
		eventMinItemLevelLabel:SetText("Min Item Level: " .. event.minItemLevel)
		eventMinItemLevelLabel:SetFont(fontPath, fontSize)
		frame:AddChild(eventMinItemLevelLabel)
	end
	
	local eventInvitingMembersLabel = GOW.GUI:Create("Label")
	eventInvitingMembersLabel:SetFont(fontPath, fontSize)

	if (event.isGuildEvent and event.minItemLevel == 0) then
		eventInvitingMembersLabel:SetText("Inviting Members: All guildies within level range")
	else 
		eventInvitingMembersLabel:SetText("Inviting Members: " .. event.totalMembers)
	end

	frame:AddChild(eventInvitingMembersLabel)

	local button = GOW.GUI:Create("Button")
	button:SetText("Confirm")
	button:SetCallback("OnClick", function()
		--beforeAddFunc()
		C_Calendar.AddEvent()
		frame:Release()
	end)
	frame:AddChild(button)
	eventContainer:Hide()
	GOW.GUI:SetFocus(frame)

	--PlaySound(SOUNDKIT.READY_CHECK)
end