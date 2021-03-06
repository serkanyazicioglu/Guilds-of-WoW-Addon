local ADDON_NAME = "GuildsOfWoW"
local GOW = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME)
GuildsOfWow = GOW

local enableDebugging = false

GOW.consts = {}
GOW.consts.INVITE_INTERVAL = 3

local ns = select(2, ...)

local Core = {}
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("CALENDAR_NEW_EVENT")
f:RegisterEvent("CALENDAR_UPDATE_EVENT")
f:RegisterEvent("CALENDAR_UPDATE_GUILD_EVENTS")
f:RegisterEvent("CALENDAR_OPEN_EVENT")
f:RegisterEvent("CALENDAR_CLOSE_EVENT")
f:RegisterEvent("FRIENDLIST_UPDATE")
f:RegisterEvent("CALENDAR_UPDATE_INVITE_LIST")
local isProcessing = false
local isPropogatingUpdate = false
local containerFrame = {}
local containerTabs = {}
local containerScrollFrame = {}

local currentCharName = ""
local currentCharRealm = ""

local isDialogOpen = false
local workQueue = nil
local persistentWorkQueue = nil

local currentMultiInvitingEvent = nil
local processedEvents = nil

local recruitmentCharacter = nil
local recruitmenNotes = nil

local invitingToPartyEvent = nil

local isEventAttendancesChecked = false

local copyText = ""

GOW.defaults = {
	profile = {
		version = 1,
        minimap = {hide = false}
    }
}

local selectedTab = "audittable";
local tabs = {
	{ value = "audittable", text = "Audit" },
	{ value = "events", text = "Upcoming Events" },
	{ value = "recruitmentApps", text = "Recruitment Applications" },
}

local LibQTip = LibStub('LibQTip-1.0')

function GOW:OnInitialize()
	self.GUI = LibStub("AceGUI-3.0")
	self.DB = LibStub("AceDB-3.0"):New("GoWDB", GOW.defaults, "Default")
	self.LDB = LibStub("LibDataBroker-1.1")
	self.LDBIcon = LibStub("LibDBIcon-1.0")
	self.CONSOLE = LibStub("AceConsole-3.0")
	self.SCROLLINGTABLE = LibStub("ScrollingTable");
	self.timers = {}
	LibStub("AceTimer-3.0"):Embed(self.timers)
	self.events = {}
	LibStub("AceEvent-3.0"):Embed(self.events)
	workQueue = self.WorkQueue.new()
	persistentWorkQueue = self.WorkQueue.new()
	processedEvents = GOW.List.new()
	
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
			tooltip:Show()
		end,
		OnClick = function() Core:ToggleWindow() end
	})

	self.LDBIcon:Register("gowicon", dataobj, self.DB.profile.minimap);

	string.lpad = function(str, len, char)
		if char == nil then char = ' ' end
		return string.rep(char, len - #str) .. str
	end

	string.splitByDelimeter = function(str, delimiter)
		result = {};
		for match in (str..delimiter):gmatch("(.-)"..delimiter) do
			table.insert(result, match);
		end
		return result;
	end

	containerFrame = GOW.GUI:Create("Frame")
	containerFrame:SetLayout("Fill")
	containerFrame:SetHeight(550)
	containerFrame:SetTitle("Guilds of WoW")
	containerFrame:SetStatusText("Type /gow for quick access")
	containerFrame:SetCallback("OnClose", function(widget) containerFrame:Hide() end)
	containerFrame:SetCallback("OnEscapePressed", function(widget) containerFrame:Hide() end)
	--tinsert(UISpecialFrames, containerFrame:GetName())
	containerFrame:Hide()

	containerTabs = GOW.GUI:Create("TabGroup")
	containerTabs:SetTabs(tabs)
	containerTabs:SelectTab(selectedTab)
	containerTabs:SetCallback("OnGroupSelected", function(frame, event, value) Core:ToggleTabs(value) end)
	containerFrame:AddChild(containerTabs)

	containerScrollFrame = GOW.GUI:Create("ScrollFrame")
	containerScrollFrame:SetLayout("Flow")
	containerScrollFrame:SetFullWidth(true)
	containerScrollFrame:SetFullHeight(true)
	containerTabs:AddChild(containerScrollFrame)

	-- local closeButton = CreateFrame("Button", "$parentClose", f, "UIPanelCloseButton")
	-- closeButton:SetSize(24, 24)
	-- closeButton:SetPoint("TOPRIGHT")
	-- closeButton:SetScript("OnClick", function(self) self:GetParent():Hide() end)
	-- containerFrame:AddChild(closeButton)

	-- local close = CreateFrame("Button", nil, nil, "UIPanelCloseButton")
	-- close:SetPoint("TOPRIGHT", 2, 1)
	-- containerFrame:AddChild(close)

	if (ns.UPCOMING_EVENTS == nil or ns.RECRUITMENT_APPLICATIONS == nil) then
		print("|cffffff00Guilds of WoW: |cffFF0000Data is not fetched! Please make sure your sync app is installed and working properly.")
	end

	StaticPopupDialogs["CONFIRM_EVENT_CREATION"] = {
		text = "Are you sure you want to create this event on in-game calendar?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			C_Calendar.AddEvent()
			if (currentMultiInvitingEvent ~= nil and currentMultiInvitingEvent.isManualInvite) then
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

	  StaticPopupDialogs["CONFIRM_INVITE_TO_GUILD"] = {
		text = "Are you sure you want to invite %s to your guild?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			GuildInvite(recruitmentCharacter)
			recruitmentCharacter = nil
			Core:DialogClosed()			
		end,
		OnCancel = function ()
			recruitmentCharacter = nil
			Core:DialogClosed()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }

	  StaticPopupDialogs["CONFIRM_ADD_FRIEND"] = {
		text = "Are you sure you want to add %s to your friend list?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			C_FriendList.AddFriend(recruitmentCharacter, recruitmenNotes)
			recruitmentCharacter = nil
			Core:DialogClosed()
		end,
		OnCancel = function ()
			recruitmentCharacter = nil
			Core:DialogClosed()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }

	  StaticPopupDialogs["WHISPER_PLAYER"] = {
		text = "Type your message",
		button1 = "Send",
		button2 = "Cancel",
		OnAccept = function(self, data, data2)
			local text = self.editBox:GetText()

			if (text ~= nil and text ~= "") then
				SendChatMessage(text, "WHISPER", nil, recruitmentCharacter);
				recruitmentCharacter = nil
				Core:DialogClosed()
			end
		end,
		OnCancel = function ()
			recruitmentCharacter = nil
			Core:DialogClosed()
		end,
		timeout = 100,
		enterClicksFirstButton = true,
		whileDead = true,
		hideOnEscape = true,
		hasEditBox  = true,
		preferredIndex = 3
	  }

	  StaticPopupDialogs["COPY_TEXT"] = {
		text = "Select & copy following text",
		button1 = "Done",
		OnShow = function (self, data)
			self.editBox:SetText(copyText)
			self.editBox:HighlightText()
		end,
		OnAccept = function()
			Core:DialogClosed()
		end,
		timeout = 0,
		enterClicksFirstButton = true,
		whileDead = true,
		hideOnEscape = true,
		hasEditBox  = true,
		preferredIndex = 1
	  }

	  StaticPopupDialogs["CONFIRM_INVITE_TO_PARTY"] = {
		text = "Are you sure you want to invite %s member(s) to your party?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			Core:InviteAllToParty(invitingToPartyEvent)
			invitingToPartyEvent = nil
			Core:DialogClosed()			
		end,
		OnCancel = function ()
			invitingToPartyEvent = nil
			Core:DialogClosed()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }

	  StaticPopupDialogs["INVITE_TO_PARTY_NOONE_FOUND"] = {
		text = "No member from this event is available to invite!",
		button1 = "Okay",
		timeout = 0,
		enterClicksFirstButton = true,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }

	  StaticPopupDialogs["INVITE_TO_PARTY_INVALID_CALENDAR"] = {
		text = "Only 'Player Event' attendances can be invited via addon! For 'Guild Events' you can create the event and use that event's 'invite members' functionality.",
		button1 = "Okay",
		timeout = 0,
		enterClicksFirstButton = true,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }

	  StaticPopupDialogs["INVITE_TO_PARTY_USE_CALENDAR"] = {
		text = "This event is also created on calendar! Please use the calendar event's 'invite members' button.",
		button1 = "Okay",
		timeout = 0,
		enterClicksFirstButton = true,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }
end

f:SetScript("OnEvent", function(self,event, arg1, arg2)
	Core:Print(event)

	if event == "PLAYER_LOGIN" then
		isProcessing = false

		local name, realm = UnitName("player")

		if (realm == nil) then
			realm = GetNormalizedRealmName()
		end

		currentCharName = name
		currentCharRealm = realm
	elseif event == "GUILD_ROSTER_UPDATE" then
		Core:SetRosterInfo()
	elseif event == "CALENDAR_UPDATE_GUILD_EVENTS" then
		if (isProcessing == false and selectedTab == "events") then
			--Core:CreateRecruitmentApplications()
			persistentWorkQueue:addTask(function() Core:CreateUpcomingEvents() end, nil, 2)

			if (ns.UPCOMING_EVENTS ~= nil and ns.UPCOMING_EVENTS.totalEvents > 0) then
				Core:CheckEventInvites()
			end
		end
	elseif event == "CALENDAR_OPEN_EVENT" then
		local canAddEvent = C_Calendar.IsEventOpen() --C_Calendar.CanAddEvent()
		
		if (canAddEvent) then
			local eventInfo = C_Calendar.GetEventInfo()
			
			Core:Print("Is event open:" .. tostring(C_Calendar.IsEventOpen()))

			if (eventInfo ~= nil) then
				Core:Print("CALENDAR_OPEN_EVENT: Opened: " .. eventInfo.title .. " . Calendar Type: " .. eventInfo.calendarType)
				Core:ClearEventInvites(false)

				if (eventInfo.calendarType == "GUILD_EVENT" or eventInfo.calendarType == "PLAYER") then
					local upcomingEvent = Core:FindUpcomingEventFromName(eventInfo.title)

					if (upcomingEvent ~= nil) then
						if (eventInfo.calendarType == "PLAYER") then
							--processedEvents:remove(upcomingEvent.titleWithKey)
							Core:CreateEventInvites(upcomingEvent, true)
						else
							Core:SetAttendance(upcomingEvent, true)
						end
					else
						Core:Print("Event couldn't be found!")
					end
				else 
					Core:Print("Not suitable calendar type")
				end
			end
		end
	elseif event == "CALENDAR_NEW_EVENT" or event == "CALENDAR_UPDATE_EVENT" then
		if (isPropogatingUpdate == false and selectedTab == "events") then
			persistentWorkQueue:addTask(function() isPropogatingUpdate = true Core:CreateUpcomingEvents() end, nil, 2)
		end
	elseif event == "CALENDAR_CLOSE_EVENT" then
		Core:ClearEventInvites(true)

		if (isPropogatingUpdate == false and selectedTab == "events") then
			persistentWorkQueue:addTask(function() isPropogatingUpdate = true Core:CreateUpcomingEvents() end, nil, 2)
		end
	elseif event == "CALENDAR_UPDATE_INVITE_LIST" then
		Core:Print("CALENDAR_UPDATE_INVITE_LIST")
		if (C_Calendar.IsEventOpen()) then
			local eventInfo = C_Calendar.GetEventInfo()

			if (eventInfo.title == "") then
				Core:ClearEventInvites(false)
			else
				processedEvents:remove(eventInfo.title)
			end
		end
	elseif event == "FRIENDLIST_UPDATE" then
		Core:CreateRecruitmentApplications()
	end
end)

function Core:ToggleTabs(tabKey)
	selectedTab = tabKey
	Core:RefreshApplication()
end

function Core:RefreshApplication()
	isPropogatingUpdate = true
	isProcessing = false

	if (selectedTab == "events") then
		Core:CreateUpcomingEvents()
	elseif (selectedTab == "audittable") then
		Core:CreateAuditTable()
	elseif (selectedTab == "recruitmentApps") then
		Core:CreateRecruitmentApplications()
	end
end

function Core:ToggleWindow()
	if (containerFrame:IsShown()) then
		containerFrame:Hide()
	else
		Core:RefreshApplication()
		containerFrame:Show()
	end
end

function Core:CreateUpcomingEvents()
	if (selectedTab ~= "events") then
		return
	end

	if (ns.UPCOMING_EVENTS == nil) then
		containerScrollFrame:ReleaseChildren()
		Core:AppendMessage("Upcoming events data is not found! Please make sure your sync app is installed and working properly!", true)
	else
		local isInGuild = IsInGuild()

		if (isDialogOpen) then
			return
		end

		if (isInGuild == false) then
			isProcessing = true
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false)
			return
		end

		local guildName, _, _, realmName = GetGuildInfo("player")

		if (guildName == nil) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false)
			return
		end

		Core:Print("Core:CreateUpcomingEvents")
		isProcessing = true
		containerScrollFrame:ReleaseChildren()

		if (realmName == nil) then
			realmName = GetNormalizedRealmName()
		end

		local regionId = GetCurrentRegion()

		local hasAnyData = false

		if (isInGuild and ns.UPCOMING_EVENTS.totalEvents > 0) then
			for i=1, ns.UPCOMING_EVENTS.totalEvents do
				local upcomingEvent = ns.UPCOMING_EVENTS.events[i]

				if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealmNormalized and regionId == upcomingEvent.guildRegionId) then
					hasAnyData = true
					Core:AppendCalendarList(upcomingEvent)
				end
			end
		end

		if (not hasAnyData) then
			Core:AppendMessage("This guild doesn't have any upcoming event or you are not an event manager!\r\n\r\nGuild: " .. guildName .. " / " .. realmName, true)
		end
	end

	isPropogatingUpdate = false
end

function Core:CreateRecruitmentApplications()
	if (selectedTab ~= "recruitmentApps") then
		return
	end

	if(ns.RECRUITMENT_APPLICATIONS == nil) then
		containerScrollFrame:ReleaseChildren()
		Core:AppendMessage("Recruitment applications data is not found! Please make sure your sync app is installed and working properly!", true)
	else
		local isInGuild = IsInGuild()

		if (isInGuild == false) then
			isProcessing = true
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false)
			return
		end

		local guildName, _, _, realmName = GetGuildInfo("player")

		if (guildName == nil) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false)
			return
		end

		isProcessing = true
		containerScrollFrame:ReleaseChildren()

		if (realmName == nil) then
			realmName = GetNormalizedRealmName()
		end

		local regionId = GetCurrentRegion()

		local hasAnyData = false

		if (isInGuild and ns.RECRUITMENT_APPLICATIONS.totalApplications > 0) then
			for i=1, ns.RECRUITMENT_APPLICATIONS.totalApplications do
				local recruitmentApplication = ns.RECRUITMENT_APPLICATIONS.recruitmentApplications[i]

				if (guildName == recruitmentApplication.guild and realmName == recruitmentApplication.guildRealmNormalized and regionId == recruitmentApplication.guildRegionId) then
					hasAnyData = true
					Core:AppendRecruitmentList(recruitmentApplication)
				end
			end

			--containerScrollFrame:DoLayout()
		end

		if (not hasAnyData) then
			Core:AppendMessage("This guild doesn't have any guild recruitment application or you are not a recruitment manager!\r\n\r\nGuild: " .. guildName .. " / " .. realmName, true)
		end
	end
	
	isPropogatingUpdate = false
end

function Core:CreateAuditTable()
	if (selectedTab ~= "audittable") then
		return
	end

	if(ns.GUILD_AUDIT == nil) then
		containerScrollFrame:ReleaseChildren()
		Core:AppendMessage("Aduit data is not found! Please make sure your sync app is installed and working properly!", true)
	else
		local isInGuild = IsInGuild()

		if (isInGuild == false) then
			isProcessing = true
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false)
			return
		end

		local guildName, _, _, realmName = GetGuildInfo("player")

		if (guildName == nil) then
			Core:AppendMessage("This character is not in a guild! You must be a guild member to use this feature.", false)
			return
		end

		local name, realm = UnitName("player")

		isProcessing = true
		containerScrollFrame:ReleaseChildren()

		if (realmName == nil) then
			realmName = GetNormalizedRealmName()
		end

		local regionId = GetCurrentRegion()

		local hasAnyData = false

		local fontPath = "Fonts\\FRIZQT__.TTF"

		if (isInGuild and ns.GUILD_AUDIT.totalGuilds > 0) then
			for i=1, ns.GUILD_AUDIT.totalGuilds do
				local auditGuild = ns.GUILD_AUDIT.guilds[i]

				if (guildName == auditGuild.guild and realmName == auditGuild.guildRealmNormalized and regionId == auditGuild.guildRegionId) then
					
					if (auditGuild.totalMembers == 0) then
						Core:AppendMessage("Audit data is expired. Please recalculate your audit report on GoW portal.", true)
						return
					end

					hasAnyData = true

					local currentAuditData = nil

					local highestItemLevel = 0
					local highestCovenantLevel = 0
					local highestLegendaryLevel = 0
					local maxNormalKills = 0
					local maxHeroicKills = 0
					local maxMythicKills = 0
					local mythicDungeons = 0
					local maxMythicPlus = 0
					local maxWeeklyScore = 0
					local maxScore = 0

					 for m=1, auditGuild.totalMembers do
					 	local currentMember = auditGuild.members[m]
					
						 if (currentMember.title == name) then
							currentAuditData = currentMember
						 end

						 if (currentMember.ilvlEq > highestItemLevel) then
							highestItemLevel = currentMember.ilvlEq	 
						 end

						 if (currentMember.covenantLevel > highestCovenantLevel) then
							highestCovenantLevel = currentMember.covenantLevel
						 end

						 if (currentMember.legendary > highestLegendaryLevel) then
							highestLegendaryLevel = currentMember.legendary
						 end

						 if (currentMember.normalKills > maxNormalKills) then
							maxNormalKills = currentMember.normalKills
						 end

						 if (currentMember.heroicKills > maxHeroicKills) then
							maxHeroicKills = currentMember.heroicKills
						 end

						 if (currentMember.mythicKills > maxMythicKills) then
							maxMythicKills = currentMember.mythicKills
						 end

						 if (currentMember.weeklyScore > maxWeeklyScore) then
							maxWeeklyScore = currentMember.weeklyScore
						 end

						 if (currentMember.score > maxScore) then
							maxScore = currentMember.score
						 end
					 end

					 if (currentAuditData) then

						local avgItemLevel, avgItemLevelEquipped, avgItemLevelPvp = GetAverageItemLevel()

						local covenantId = C_Covenants.GetActiveCovenantID()
						local renownLevel = 0

						if (covenantId > 0) then
							renownLevel = C_CovenantSanctumUI.GetRenownLevel()
							local covenantData = C_Covenants.GetCovenantData(covenantId)
						end

						Core:InsertAuditCell("Weekly Score", currentAuditData.weeklyScore, maxWeeklyScore, "Max. weekly score in your guild.")
						Core:InsertAuditCell("General Score", currentAuditData.score, maxScore, "Max. general score in your guild.")

						Core:InsertAuditCell("Item Level Equipped", avgItemLevelEquipped, highestItemLevel, "Max. item level in your guild.")
						Core:InsertAuditCell("Renown Level", renownLevel, highestCovenantLevel, "Max. renown level in your guild.")
						
						if (currentAuditData.gearAudit == 0) then
							Core:InsertAuditCell("Gear Audit", currentAuditData.gearAudit, "Your audit check is valid!", nil)
						else
							Core:InsertAuditCell("Gear Audit", currentAuditData.gearAudit, "Hover to view your gear audit!", nil)
						end

						Core:InsertAuditCell("Legendary", currentAuditData.legendary, highestLegendaryLevel, "Highest legendary level in your guild.")

						if (currentAuditData.profession1Id ~= "0") then
							Core:InsertAuditCell("Profession 1", currentAuditData.profession1SkillPoints .. " / " .. currentAuditData.profession1MaxSkillPoints, currentAuditData.profession1SkillRatio .. "%", "Profession completion.")
						else
							Core:InsertAuditCell("Profession 1", "0", "Your first profession is not selected!", nil)
						end

						if (currentAuditData.profession2Id ~= "0") then
							Core:InsertAuditCell("Profession 2", currentAuditData.profession2SkillPoints .. " / " .. currentAuditData.profession2MaxSkillPoints, currentAuditData.profession2SkillRatio .. "%", "Profession completion.")
						else
							Core:InsertAuditCell("Profession 2", "0", "Your second profession is not selected!", nil)
						end
						
						Core:InsertAuditCell("Weekly Normal Raid Kills", currentAuditData.normalKills, maxNormalKills, "Max. normal raid kills in your guild within this week.", 200)
						Core:InsertAuditCell("Weekly Heroic Raid Kills", currentAuditData.heroicKills, maxHeroicKills, "Max. heroic raid kills in your guild within this week.", 200)
						Core:InsertAuditCell("Weekly Mythic Raid Kills", currentAuditData.mythicKills, maxMythicKills, "Max. mythic raid kills in your guild within this week.", 200)

						Core:InsertAuditCell("Mythic Dungeons Completed This Week", currentAuditData.mythicDungeonsCompleted, mythicDungeons, "Max. mythic dungeons completed in your guild within this week.")
						Core:InsertAuditCell("Max Mythic+ Completed This Week", currentAuditData.maxMythicPlusCompleted, maxMythicPlus, "Max. mythic+ level completed in your guild within this week.")
					 else
						Core:AppendMessage("This character's audit data is not found!", true)
						return
					 end
				end
			end
		end

		if (not hasAnyData) then
			Core:AppendMessage("This guild doesn't have any audit data or audit report has expired!\r\n\r\nGuild: " .. guildName .. " / " .. realmName, true)
		end
	end
	
	isPropogatingUpdate = false
end

function Core:InsertAuditCell(groupTitle, value, highestValue, highestValueTooltip, width)
	local fontPath = "Fonts\\FRIZQT__.TTF"

	local groupFrame = GOW.GUI:Create("InlineGroup")
	groupFrame:SetTitle(groupTitle)
	groupFrame:SetLayout("List")

	if (not width) then
		width = 300
	end

	groupFrame:SetWidth(width)

	local label1 = GOW.GUI:Create("Label")
	label1:SetText(value)
	label1:SetFont(fontPath, 28)
	groupFrame:AddChild(label1)
	label1:ClearAllPoints()
	label1:SetPoint("CENTER", groupFrame.frame, "CENTER", -8, -4)

	if (highestValue) then
		local label2 = GOW.GUI:Create("InteractiveLabel")
		label2:SetText(highestValue)
		label2:SetFont(fontPath, 11)
		if(highestValueTooltip) then
			label2:SetCallback("OnEnter", function(self)
				local tooltip = LibQTip:Acquire("ItemLevelTooltip", 1, "LEFT")
				GOW.tooltip = tooltip
				
				local line = tooltip:AddLine()
				tooltip:SetCell(line, 1, highestValueTooltip, "LEFT", 1, nil, 0, 0, 300, 50)
				tooltip:SmartAnchorTo(self.frame)
				tooltip:Show()
			end)
			label2:SetCallback("OnLeave", function()
				LibQTip:Release(GOW.tooltip)
				GOW.tooltip = nil
			end)
		end
		groupFrame:AddChild(label2)
	end

	containerScrollFrame:AddChild(groupFrame)
end

function Core:searchForEvent(event)
	local serverTime = C_DateAndTime.GetServerTimeLocal()

	if (event.eventDate < serverTime) then
		return 0
	end

	C_Calendar.SetAbsMonth(event.month, event.year)

	local monthIndex = 0 -- tonumber(date("%m", event.eventDate)) - tonumber(date("%m", serverTime))

	local numDayEvents = C_Calendar.GetNumDayEvents(monthIndex, event.day)

	--Core:Print("events found: " .. numDayEvents .. " : " .. event.day .. "/" .. event.month .. "/" .. event.year)

	if (numDayEvents > 0) then
		for i=1, numDayEvents do
			local dayEvent = C_Calendar.GetDayEvent(monthIndex, event.day, i)
			
			if (dayEvent.calendarType == "GUILD_EVENT" or dayEvent.calendarType == "PLAYER") then
				--Core:Print("dayEvent: " .. dayEvent.title)

				if (string.match(dayEvent.title, "*" .. event.eventKey)) then
					return i
				end
			end
		end
	end

	return -1
end

function Core:AppendMessage(message, appendReloadUIButton)
	local fontPath = "Fonts\\FRIZQT__.TTF"
	local fontSize = 13

	local itemGroup = GOW.GUI:Create("SimpleGroup")
	--itemGroup:SetLayout("Line")
	itemGroup:SetFullWidth(true)
	itemGroup:SetFullHeight(true)

	local blankMargin = GOW.GUI:Create("SimpleGroup")
	blankMargin:SetLayout("Line")
	blankMargin:SetFullWidth(true)
	blankMargin:SetHeight(10)
	itemGroup:AddChild(blankMargin)

	local messageLabel = GOW.GUI:Create("Label")
	messageLabel:SetText(message)
	messageLabel:SetFullWidth(true)
	messageLabel:SetFont(fontPath, fontSize)
	itemGroup:AddChild(messageLabel)

	if(appendReloadUIButton) then
		local blankMargin2 = GOW.GUI:Create("SimpleGroup")
		blankMargin2:SetLayout("Line")
		blankMargin2:SetFullWidth(true)
		blankMargin2:SetHeight(10)
		itemGroup:AddChild(blankMargin2)

		local reloadUIButton = GOW.GUI:Create("Button")
		reloadUIButton:SetText("Reload UI")
		reloadUIButton:SetCallback("OnClick", function()
			ReloadUI()
		end)
		itemGroup:AddChild(reloadUIButton)
	end

	containerScrollFrame:AddChild(itemGroup)
end

function Core:AppendCalendarList(event)
	local itemGroup = GOW.GUI:Create("InlineGroup")
	itemGroup:SetTitle(event.title)
	itemGroup:SetFullWidth(true)

	local descriptionLabel = GOW.GUI:Create("SFX-Info")
	descriptionLabel:SetLabel("Description")
	descriptionLabel:SetText(event.description)
	descriptionLabel:SetDisabled(false)
	descriptionLabel:SetCallback("OnEnter", function(self)
		local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT")
		GOW.tooltip = tooltip
		
		tooltip:AddHeader('|cffffcc00Event Description')
		local line = tooltip:AddLine()
		tooltip:SetCell(line, 1, event.description, "LEFT", 1, nil, 0, 0, 300, 50)
		tooltip:SmartAnchorTo(self.frame)
		tooltip:Show()
	end)
	descriptionLabel:SetCallback("OnLeave", function()
		LibQTip:Release(GOW.tooltip)
		GOW.tooltip = nil
	end)
	itemGroup:AddChild(descriptionLabel)

	local dateLabel = GOW.GUI:Create("SFX-Info")
	dateLabel:SetLabel("Date")
	dateLabel:SetText(event.dateText)
	itemGroup:AddChild(dateLabel)

	local eventHourLabel = GOW.GUI:Create("SFX-Info")
	eventHourLabel:SetLabel("Hour")
	eventHourLabel:SetText(event.hourText)
	itemGroup:AddChild(eventHourLabel)

	local eventDurationLabel = GOW.GUI:Create("SFX-Info")
	eventDurationLabel:SetLabel("Duration")
	eventDurationLabel:SetText(event.durationText)
	itemGroup:AddChild(eventDurationLabel)
	
	if (event.team ~= "") then
		local teamLabel = GOW.GUI:Create("SFX-Info")
		teamLabel:SetLabel("Team")
		teamLabel:SetText(event.team)
		itemGroup:AddChild(teamLabel)
	elseif (event.calendarType == 2) then
		local levelText = event.minLevel

		if event.minLevel ~= event.maxLevel then
			levelText = levelText .. " -> " .. event.maxLevel
		end

		local eventLevelLabel = GOW.GUI:Create("SFX-Info")
		eventLevelLabel:SetLabel("Level")
		eventLevelLabel:SetText(levelText)
		itemGroup:AddChild(eventLevelLabel)

		if (event.minItemLevel > 0) then
			local eventMinItemLevelLabel = GOW.GUI:Create("SFX-Info")
			eventMinItemLevelLabel:SetLabel("Item Level")
			eventMinItemLevelLabel:SetText(event.minItemLevel .. "+")
			itemGroup:AddChild(eventMinItemLevelLabel)
		end
	end
	
	local isEventMember = event.isEventMember
	local canAddEvent = event.isEventManager

	local eventInvitingMembersLabel = GOW.GUI:Create("SFX-Info")
	eventInvitingMembersLabel:SetLabel("Inviting")

	local invitineDetailsText = ""

	if (event.calendarType == 1) then
		invitineDetailsText = "All guildies"
	elseif (not event.isManualInvite) then
		invitineDetailsText = "All guildies within level range"
	else
		if (event.totalMembers > 1) then
			invitineDetailsText = event.totalMembers .. " members"
		else
			invitineDetailsText = event.totalMembers .. " member"
		end
	end

	if (not isEventMember) then
		invitineDetailsText = invitineDetailsText .. " (You are not eligible for this event)"
	end

	eventInvitingMembersLabel:SetText(invitineDetailsText)
	itemGroup:AddChild(eventInvitingMembersLabel)

	local eventIndex = Core:searchForEvent(event)

	local buttonsGroup = GOW.GUI:Create("SimpleGroup")
	buttonsGroup:SetLayout("Flow")
	buttonsGroup:SetFullWidth(true)

	if (canAddEvent) then
		local eventCalendarTypeLabel = GOW.GUI:Create("SFX-Info")
		eventCalendarTypeLabel:SetLabel("Calendar")
		if(event.calendarType == 1) then
			eventCalendarTypeLabel:SetText("Guild Event")
		else
			eventCalendarTypeLabel:SetText("Player Event")
		end
		eventCalendarTypeLabel:SetDisabled(false)
		eventCalendarTypeLabel:SetCallback("OnEnter", function(self)
			local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT")
			GOW.tooltip = tooltip
			
			tooltip:AddHeader('|cffffcc00About Event Attendances')
			local line = tooltip:AddLine()
			tooltip:SetCell(line, 1, "When no filter is selected in-game addon will create 'Guild Event' and all guildies will be able to sign up. This selection is suitable for large meetings. Site attendance data will not migrate to in-game with this selection but will migrate from game to GoW.\r\n\r\nWhen filtration is enabled or audience is set to team event, addon will create 'Player Event' and will only invite eligible characters. Attendance synchronization will work bidirectional. Player events cannot invite more than 100 members so you should narrow the audience by item level or change audience to team event.", "LEFT", 1, nil, 0, 0, 300, 50)
			tooltip:SmartAnchorTo(self.frame)
			tooltip:Show()
		end)
		eventCalendarTypeLabel:SetCallback("OnLeave", function()
			LibQTip:Release(GOW.tooltip)
			GOW.tooltip = nil
		end)
		itemGroup:AddChild(eventCalendarTypeLabel)

		local eventButton = GOW.GUI:Create("Button")

		if eventIndex == 0 then
			eventButton:SetText("Event Passed")
			eventButton:SetDisabled(true)
		elseif eventIndex > 0 then
			eventButton:SetText("Event Created")
			eventButton:SetDisabled(true)
		else
			eventButton:SetText("Create In-Game Event")
			eventButton:SetCallback("OnClick", function()
				Core:CreateCalendarEvent(event)
			end)

			eventButton:SetCallback("OnEnter", function(self)
				local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT")
				GOW.tooltip = tooltip
				
				local line = tooltip:AddLine()
				tooltip:SetCell(line, 1, "You can create an in-game calendar event to integrate Guilds of WoW attendance data with in-game calendar. This synchronization will work bidirectional.", "LEFT", 1, nil, 0, 0, 300, 50)
				tooltip:SmartAnchorTo(self.frame)
				tooltip:Show()
			end)
			eventButton:SetCallback("OnLeave", function()
				LibQTip:Release(GOW.tooltip)
				GOW.tooltip = nil
			end)
		end
		buttonsGroup:AddChild(eventButton)

		if (event.eventEndDate >= C_DateAndTime.GetServerTimeLocal()) then
			local inviteButton = GOW.GUI:Create("Button")
			inviteButton:SetWidth(140)
			inviteButton:SetText("Invite Players")
			inviteButton:SetCallback("OnClick", function()
				if (event.calendarType == 2) then
					if (eventIndex > 0) then
						Core:OpenDialog("INVITE_TO_PARTY_USE_CALENDAR")
					else
						Core:InviteAllToPartyCheck(event)
					end
				else
					Core:OpenDialog("INVITE_TO_PARTY_INVALID_CALENDAR")
				end
			end)

			inviteButton:SetCallback("OnEnter", function(self)
				local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT")
				GOW.tooltip = tooltip
				
				local line = tooltip:AddLine()
				tooltip:SetCell(line, 1, "You can invite attendees directly into your party or raid.", "LEFT", 1, nil, 0, 0, 300, 50)
				tooltip:SmartAnchorTo(self.frame)
				tooltip:Show()
			end)
			inviteButton:SetCallback("OnLeave", function()
				LibQTip:Release(GOW.tooltip)
				GOW.tooltip = nil
			end)
			buttonsGroup:AddChild(inviteButton)
		end
		
	end

	local copyLinkButton = GOW.GUI:Create("Button")
	copyLinkButton:SetText("Copy Link")
	copyLinkButton:SetWidth(100)
	copyLinkButton:SetCallback("OnClick", function()
		copyText = event.webUrl
		Core:OpenDialog("COPY_TEXT")
	end)
	buttonsGroup:AddChild(copyLinkButton)

	if (canAddEvent and eventIndex < 0) then
		local copyKeyButton = GOW.GUI:Create("Button")
		copyKeyButton:SetText("Copy Key")
		copyKeyButton:SetWidth(100)
		copyKeyButton:SetCallback("OnClick", function()
			copyText = event.eventKey
			Core:OpenDialog("COPY_TEXT")
		end)

		copyKeyButton:SetCallback("OnEnter", function(self)
			local tooltip = LibQTip:Acquire("EventMessageTooltip", 1, "LEFT")
			GOW.tooltip = tooltip
			
			local line = tooltip:AddLine()
			tooltip:SetCell(line, 1, "If you already created an in-game event related to this record, you can append this key to the end of event title in-game for GoW synchronization.", "LEFT", 1, nil, 0, 0, 300, 50)
			tooltip:SmartAnchorTo(self.frame)
			tooltip:Show()
		end)
		copyKeyButton:SetCallback("OnLeave", function()
			LibQTip:Release(GOW.tooltip)
			GOW.tooltip = nil
		end)

		buttonsGroup:AddChild(copyKeyButton)
	end

	itemGroup:AddChild(buttonsGroup)

	containerScrollFrame:AddChild(itemGroup)
end

function Core:AppendRecruitmentList(recruitmentApplication)
	local itemGroup = GOW.GUI:Create("InlineGroup")
	itemGroup:SetTitle(recruitmentApplication.title)
	itemGroup:SetFullWidth(true)

	local messageLabel = GOW.GUI:Create("SFX-Info")
	messageLabel:SetLabel("Message")
	messageLabel:SetDisabled(false)
	messageLabel:SetText(recruitmentApplication.message)
	messageLabel:SetCallback("OnEnter", function(self)
		local tooltip = LibQTip:Acquire("RecruitmentMessageTooltip", 1, "LEFT")
		GOW.tooltip = tooltip
		
		tooltip:AddHeader('|cffffcc00Message')
		local line = tooltip:AddLine()
		tooltip:SetCell(line, 1, recruitmentApplication.message, "LEFT", 1, nil, 0, 0, 300, 50)
		tooltip:SmartAnchorTo(self.frame)
		tooltip:Show()
	end)
	messageLabel:SetCallback("OnLeave", function()
		LibQTip:Release(GOW.tooltip)
		GOW.tooltip = nil
	end)
	itemGroup:AddChild(messageLabel)

	local classLabel = GOW.GUI:Create("SFX-Info")
	classLabel:SetLabel("Class")
	classLabel:SetText(recruitmentApplication.classTitle)
	itemGroup:AddChild(classLabel)

	local dateLabel = GOW.GUI:Create("SFX-Info")
	dateLabel:SetLabel("Date")
	dateLabel:SetText(recruitmentApplication.dateText)
	itemGroup:AddChild(dateLabel)

	local statusLabel = GOW.GUI:Create("SFX-Info")
	statusLabel:SetLabel("Status")
	statusLabel:SetText(recruitmentApplication.status)
	itemGroup:AddChild(statusLabel)

	if (recruitmentApplication.reviewedBy ~= "" and recruitmentApplication.reviewedBy ~= nil) then
		local reviewedByLabel = GOW.GUI:Create("SFX-Info")
		reviewedByLabel:SetLabel("Reviewer")
		reviewedByLabel:SetText(recruitmentApplication.reviewedBy)
		itemGroup:AddChild(reviewedByLabel)
	end

	if (recruitmentApplication.responseMessage ~= "" and recruitmentApplication.responseMessage ~= nil) then
		local responseMessageLabel = GOW.GUI:Create("SFX-Info")
		responseMessageLabel:SetLabel("Response")
		responseMessageLabel:SetDisabled(false)
		responseMessageLabel:SetText(recruitmentApplication.responseMessage)
		responseMessageLabel:SetCallback("OnEnter", function(self)
			local tooltip = LibQTip:Acquire("RecruitmentResponseMessageTooltip", 1, "LEFT")
			GOW.tooltip = tooltip
			
			tooltip:AddHeader('|cffffcc00Response Message')
			local line = tooltip:AddLine()
			tooltip:SetCell(line, 1, recruitmentApplication.responseMessage, "LEFT", 1, nil, 0, 0, 300, 50)
			tooltip:SmartAnchorTo(self.frame)
			tooltip:Show()
		end)
		responseMessageLabel:SetCallback("OnLeave", function()
			LibQTip:Release(GOW.tooltip)
			GOW.tooltip = nil
		end)
		itemGroup:AddChild(responseMessageLabel)
	end

	local buttonsGroup = GOW.GUI:Create("SimpleGroup")
	buttonsGroup:SetLayout("Flow")
	buttonsGroup:SetFullWidth(true)

	local inviteToGuildButton = GOW.GUI:Create("Button")
	inviteToGuildButton:SetText("Invite to Guild")
	inviteToGuildButton:SetWidth(140)
	inviteToGuildButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized
		Core:OpenDialog("CONFIRM_INVITE_TO_GUILD", recruitmentApplication.title)
	end)
	buttonsGroup:AddChild(inviteToGuildButton)

	local inviteToPartyButton = GOW.GUI:Create("Button")
	inviteToPartyButton:SetText("Invite to Party")
	inviteToPartyButton:SetWidth(140)
	inviteToPartyButton:SetCallback("OnClick", function()
		C_PartyInfo.InviteUnit(recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized)
	end)
	buttonsGroup:AddChild(inviteToPartyButton)

	local friendInfo = C_FriendList.GetFriendInfo(recruitmentApplication.title)

	local addFriendButton = GOW.GUI:Create("Button")
	addFriendButton:SetText("Add Friend")
	addFriendButton:SetWidth(140)
	
	if (friendInfo ~= nil) then
		addFriendButton:SetDisabled(true)
	end

	addFriendButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized
		recruitmenNotes = "Guilds of WoW recruitment"
		Core:OpenDialog("CONFIRM_ADD_FRIEND", recruitmentApplication.title)
	end)
	buttonsGroup:AddChild(addFriendButton)
	itemGroup:AddChild(buttonsGroup)

	local buttonsGroup2 = GOW.GUI:Create("SimpleGroup")
	buttonsGroup2:SetLayout("Flow")
	buttonsGroup2:SetFullWidth(true)

	local whisperButton = GOW.GUI:Create("Button")
	whisperButton:SetText("Whisper")
	whisperButton:SetWidth(140)
	whisperButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized
		Core:OpenDialog("WHISPER_PLAYER")
	end)
	buttonsGroup2:AddChild(whisperButton)

	local copyButton = GOW.GUI:Create("Button")
	copyButton:SetText("Copy Link")
	copyButton:SetWidth(140)
	copyButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmNormalized
		copyText = recruitmentApplication.webUrl
		Core:OpenDialog("COPY_TEXT")
	end)
	buttonsGroup2:AddChild(copyButton)

	itemGroup:AddChild(buttonsGroup2)

	containerScrollFrame:AddChild(itemGroup)
end

function Core:OpenDialog(dialogName)
	isDialogOpen = true
	StaticPopup_Show(dialogName)
end
function Core:OpenDialog(dialogName, parameterStr)
	isDialogOpen = true
	StaticPopup_Show(dialogName, parameterStr)
end

function Core:DialogClosed()
	isDialogOpen = false
end

function Core:ShowTooltip(container, header, message)
end

function Core:CreateCalendarEvent(event)
	if (event.calendarType == 2 and event.totalMembers >= 100) then
		print("|cffFF0000You cannot create events with more than 100 members! Please narrow your audience by filtering or binding a team or disabling filtering at all to create a guild event.")
		return
	end

	if not workQueue:isEmpty() then
		print("|cffFF0000Addon is busy right now! Please wait for a while and try again...")
		return
	end

	isDialogOpen = true
	local eventIndex = Core:searchForEvent(event)

	if eventIndex >= 0 then
		Core:DialogClosed()
		Core:Print("Event found or passed: " .. event.title)
	else
		Core:ClearEventInvites(false)
		C_Calendar.CloseEvent()
		if (event.calendarType == 1) then
			C_Calendar.CreateGuildSignUpEvent()
		else
			C_Calendar.CreatePlayerEvent()
		end
		C_Calendar.EventSetTitle(event.titleWithKey)
		C_Calendar.EventSetDescription(event.description)
		C_Calendar.EventSetType(event.eventType)
		C_Calendar.EventSetTime(event.hour, event.minute)
		C_Calendar.EventSetDate(event.month, event.day, event.year)

		currentMultiInvitingEvent = nil
		if (event.calendarType == 2 and not event.isManualInvite) then
			C_Calendar.MassInviteGuild(event.minLevel, event.maxLevel, event.maxRank)
		else
			currentMultiInvitingEvent = event
		end

		Core:OpenDialog("CONFIRM_EVENT_CREATION")
	end
end

function Core:InviteMultiplePeopleToEvent()
	if (currentMultiInvitingEvent ~= nil) then
		local event = currentMultiInvitingEvent

		local name, realm = UnitName("player")

		if (realm == nil) then
			realm = GetNormalizedRealmName()
		end

		local currentPlayer = name .. "-" .. realm

		local numInvites = C_Calendar.GetNumInvites()

		if (numInvites < event.totalMembers and numInvites < 100) then
			print("|cffffcc00Event invites are being sent in the background! Please wait for all events to complete before logging out.")

			for i=1, event.totalMembers do
				local currentInviteMember = event.inviteMembers[i]
				local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized

				if (inviteName ~= currentPlayer) then
					workQueue:addTask(function() C_Calendar.EventInvite(inviteName) end, nil, GOW.consts.INVITE_INTERVAL)
				end
			end

			--Core:IsEventFormingEnded()
		end
	end
end

function Core:IsEventFormingEnded()
	if workQueue:isEmpty() then
		--print("|cff00ff00Event invites are completed.")
		Core:StartEventInvites()
	else
		GOW.timers:ScheduleTimer(function() Core:IsEventFormingEnded() end, 10)
	end
end

function Core:ClearEventInvites(restartInvites)
	currentMultiInvitingEvent = nil
	workQueue:clearTasks()
	Core:Print("Invites are canceled!")

	if (restartInvites) then
		Core:AddCheckEventsTask()
	end
end

function Core:AddCheckEventsTask()
	workQueue:addTask(function() 
		if (not C_Calendar.IsEventOpen()) 
			then 
				Core:CheckEventInvites() 
			else
				Core:AddCheckEventsTask()
		end
	end, nil, 10)
end

function Core:CheckEventInvites()
	
	Core:Print("Starting event invites!")

	local isInGuild = IsInGuild()

	if (isInGuild) then
		local isEventOpen = false --C_Calendar.IsEventOpen()

		if (not isEventOpen) then
			local guildName, _, _, realmName = GetGuildInfo("player")

			if (guildName == nil) then
				return
			end

			if (realmName == nil) then
				realmName = GetNormalizedRealmName()
			end

			local regionId = GetCurrentRegion()

			Core:Print("Guild name: " .. guildName .. ". Region id: " .. regionId)

			for i=1, ns.UPCOMING_EVENTS.totalEvents do
				local upcomingEvent = ns.UPCOMING_EVENTS.events[i]

				Core:Print("Checking event: " .. upcomingEvent.titleWithKey)

				if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealmNormalized and regionId == upcomingEvent.guildRegionId) then

					--Core:Print("Event found for guild: " .. upcomingEvent.titleWithKey)

					if (not processedEvents:contains(upcomingEvent.titleWithKey)) then
						local eventIndex = Core:searchForEvent(upcomingEvent)

						Core:Print("Event search result: " .. upcomingEvent.titleWithKey .. ". Result: " .. eventIndex)

						if (eventIndex > 0) then
							isEventAttendancesChecked = true;

							local dayEvent = C_Calendar.GetDayEvent(0, upcomingEvent.day, eventIndex)
							Core:Print(dayEvent.title .. " creator: " .. dayEvent.modStatus .. " eventIndex:" .. eventIndex)
							
							if (dayEvent.calendarType == "PLAYER" or dayEvent.calendarType == "GUILD_EVENT") then
								if (dayEvent.modStatus == "CREATOR" or dayEvent.modStatus == "MODERATOR") then
									Core:Print("Trying opening event: " .. upcomingEvent.titleWithKey)
									workQueue:addTask(function() C_Calendar.OpenEvent(0, upcomingEvent.day, eventIndex) end, nil, 3)
									return
									--Core:CreateEventInvites(upcomingEvent)
								else
									Core:Print("Not creator or moderator!")
								end
							else
								Core:Print("Not player event!")
							end
						end
					end
				end
			end
		else
			Core:Print("Event is open!")
		end
	else
		Core:Print("Player is not in a guild!")
	end

	--print("|cffffff00Guilds of WoW: |cff00ff00Calendar event processing completed!")
end

function Core:FindUpcomingEventFromName(eventTitle)
	Core:Print("Trying to find event from title: " .. eventTitle)
	local isInGuild = IsInGuild()

	if (isInGuild) then
		local guildName, _, _, realmName = GetGuildInfo("player")

		if (guildName == nil) then
			return
		end

		if (realmName == nil) then
			realmName = GetNormalizedRealmName()
		end

		local regionId = GetCurrentRegion()

		for i=1, ns.UPCOMING_EVENTS.totalEvents do
			local upcomingEvent = ns.UPCOMING_EVENTS.events[i]

			if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealmNormalized and regionId == upcomingEvent.guildRegionId) then
				if (string.match(eventTitle, "*" .. upcomingEvent.eventKey)) then
					Core:Print("Upcoming event found: " .. upcomingEvent.title)
					return upcomingEvent
				end
			end
		end
	end

	return nil
end

function Core:CreateEventInvites(upcomingEvent, closeAfterEnd)
	if (processedEvents:contains(upcomingEvent.titleWithKey)) then
		Core:Print("Processed queue contains event!")
		return false
	end

	Core:Print("Processing event: " .. upcomingEvent.titleWithKey)

	local canSendInvite = C_Calendar.EventCanEdit()
	if (canSendInvite) then
		if (not upcomingEvent.isManualInvite) then
			Core:SetAttendance(upcomingEvent, closeAfterEnd)
			return
		end

		local invitesNum = C_Calendar.GetNumInvites()

		if (invitesNum >= 100) then
			Core:SetAttendance(upcomingEvent, closeAfterEnd)
			return
		end

		Core:Print("CreateEventInvites: " .. upcomingEvent.titleWithKey .. ". Currently invited members: " .. invitesNum)

		local invitedCount = 0

		for m=1, upcomingEvent.totalMembers do
			local currentInviteMember = upcomingEvent.inviteMembers[m]
			local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized
			local isMemberInvited = false

			for a=1, invitesNum do
				local inviteInfo = C_Calendar.EventGetInvite(a)

				if (inviteInfo and inviteInfo.name ~= nil) then
					if (string.find(inviteInfo.name, "-")) then
						Core:Print("Character with dash! " .. inviteInfo.name)

						if (inviteInfo.name == inviteName) then
							isMemberInvited = true
							Core:Print("Member is invited with realm name: " .. inviteInfo.name)
						end
					else
						if (inviteInfo.name == currentInviteMember.name and inviteInfo.level == currentInviteMember.level and inviteInfo.classID == currentInviteMember.classId) then
							Core:Print("Member is invited: " .. inviteInfo.name)
							isMemberInvited = true
						end
					end
				end
			end

			if (not isMemberInvited) then
				Core:Print("Inviting: " .. inviteName .. "-"..currentInviteMember.level .."-"..currentInviteMember.classId)
				workQueue:addTask(function() C_Calendar.EventInvite(inviteName) end, nil, GOW.consts.INVITE_INTERVAL)
				
				invitedCount = invitedCount + 1
			end
		end

		if (invitedCount > 0) then
			Core:Print("CreateEventInvites Ended: " .. upcomingEvent.title .. ". Invited: " .. tostring(invitedCount))
			workQueue:addTask(function() Core:Print("Event invites completed: " .. upcomingEvent.titleWithKey) Core:SetAttendance(upcomingEvent, closeAfterEnd) end, nil, 10)
		else 
			Core:SetAttendance(upcomingEvent, closeAfterEnd)
		end
	else 
		Core:Print("Cannot invite to this event!")
	end
end

function Core:SetAttendance(upcomingEvent, closeAfterEnd)
	if (processedEvents:contains(upcomingEvent.titleWithKey)) then
		Core:Print("Processed queue contains event!")
		return false
	end

	local canSendInvite = C_Calendar.EventCanEdit()
	if (canSendInvite) then
		local invitesNum = C_Calendar.GetNumInvites()

		Core:Print("SetAttendance: " .. upcomingEvent.titleWithKey .. ". Currently invited members: " .. invitesNum)

		local attendanceChangedCount = 0

		local currentEventAttendances = {}
		local attendanceIndex = 1

		for a=1, invitesNum do
			local inviteInfo = C_Calendar.EventGetInvite(a)
			--local responseTime = C_Calendar.EventGetInviteResponseTime(a)

			if (inviteInfo.inviteStatus > 1) then
				currentEventAttendances[attendanceIndex] = {
					name = inviteInfo.name,
					level = inviteInfo.level,
					attendance = inviteInfo.inviteStatus,
					classId = inviteInfo.classID,
					guid = inviteInfo.guid,
					--responseTime = responseTime.year .. "-" .. string.lpad(tostring(responseTime.month), 2, '0') .. "-" .. string.lpad(tostring(responseTime.monthDay), 2, '0') .. "T" .. string.lpad(tostring(responseTime.hour), 2, '0') .. ":" .. string.lpad(tostring(responseTime.minute), 2, '0')
				}

				attendanceIndex = attendanceIndex + 1
			end
			
			if (upcomingEvent.calendarType == 2) then
				for m=1, upcomingEvent.totalMembers do
					local currentInviteMember = upcomingEvent.inviteMembers[m]
		
					if (currentInviteMember) then
						if (currentInviteMember.isManager or currentInviteMember.attendance > 1) then
							if (inviteInfo.name == currentInviteMember.name and inviteInfo.level == currentInviteMember.level and inviteInfo.classID == currentInviteMember.classId) then
								local isInvitationChanged = false

								if (currentInviteMember.isManager) then
									if (inviteInfo.modStatus ~= "CREATOR" and inviteInfo.modStatus ~= "MODERATOR") then
										isInvitationChanged = true
										Core:Print("Setting member as moderator: " .. upcomingEvent.title .. ". Title: " .. inviteInfo.name)
										workQueue:addTask(function() C_Calendar.EventSetModerator(a) end, nil, GOW.consts.INVITE_INTERVAL)
									end
								end

								if (currentInviteMember.forceUpdate or (currentInviteMember.attendance > 1 and inviteInfo.inviteStatus == 1)) then
									isInvitationChanged = true
									Core:Print("Setting member attendance: " .. upcomingEvent.title .. ". Title: " .. inviteInfo.name .. ". GoWAttendance: " .. tostring(currentInviteMember.attendance) .. ". In-Game Attendance: " .. tostring(inviteInfo.inviteStatus))
									workQueue:addTask(function() C_Calendar.EventSetInviteStatus(a, currentInviteMember.attendance - 1) end, nil, GOW.consts.INVITE_INTERVAL)
								end
							
								if (isInvitationChanged) then
									attendanceChangedCount = attendanceChangedCount + 1
								end
							end
						end
					end
				end
			end
		end

		local guildKey = Core:GetGuildKey()

		if (GOW.DB.profile.guilds[guildKey].events == nil) then
			GOW.DB.profile.guilds[guildKey].events = { }
		end

		local eventId = tostring(upcomingEvent.id)

		if (GOW.DB.profile.guilds[guildKey].events[eventId] == nil) then
			GOW.DB.profile.guilds[guildKey].events[eventId] = { }
		end

		GOW.DB.profile.guilds[guildKey].events[eventId].refreshTime = GetServerTime()

		if (GOW.DB.profile.guilds[guildKey].events[eventId].attendances == nil) then
			GOW.DB.profile.guilds[guildKey].events[eventId].attendances = { }
		end

		GOW.DB.profile.guilds[guildKey].events[eventId].attendances = currentEventAttendances

		if (attendanceChangedCount > 0) then
			Core:Print("SetAttendance Ended: " .. upcomingEvent.title .. ". SetAttendance: " .. tostring(attendanceChangedCount))
			workQueue:addTask(function() Core:Print("Event attendances completed: " .. upcomingEvent.titleWithKey) if (closeAfterEnd) then processedEvents:push(upcomingEvent.titleWithKey) C_Calendar.CloseEvent() end end, nil, 10)
		else 
			if (closeAfterEnd) then
				processedEvents:push(upcomingEvent.titleWithKey)
				C_Calendar.CloseEvent()
			end
		end
	else 
		Core:Print("Cannot set attendance to this event!")
	end
end

function Core:InviteAllToPartyCheck(event)
	local name, realm = UnitName("player")
	realm = GetNormalizedRealmName()
	local me = name .. "-" .. realm
	
	local eligibleMembers = 0

	for i=1, event.totalMembers do
		local currentInviteMember = event.inviteMembers[i]
		
		if (currentInviteMember.attendance == 2 or currentInviteMember.attendance == 4 or currentInviteMember.attendance == 9) then
			local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized

			if (inviteName ~= me) then
				eligibleMembers = eligibleMembers + 1
			end
		end
	end

	if (eligibleMembers > 0) then
		invitingToPartyEvent = event
		Core:OpenDialog("CONFIRM_INVITE_TO_PARTY", eligibleMembers)
	else
		Core:OpenDialog("INVITE_TO_PARTY_NOONE_FOUND")
	end
end

function Core:InviteAllToParty(event)
	local invitingMembers = {}
	local inviteIndex = 1

	local name, realm = UnitName("player")
		realm = GetNormalizedRealmName()
		local me = name .. "-" .. realm

	for i=1, event.totalMembers do
		local currentInviteMember = event.inviteMembers[i]

		if (currentInviteMember.attendance == 2 or currentInviteMember.attendance == 4 or currentInviteMember.attendance == 9) then
			local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realmNormalized

			invitingMembers[inviteIndex] = inviteName
			inviteIndex = inviteIndex + 1
		end
	end

	Core:Print("inviteIndex: " .. inviteIndex)

	if (inviteIndex > 1) then
		-- if (inviteIndex > 5) then
		-- 	local allowed = C_PartyInfo.AllowedToDoPartyConversion(true)

		-- 	--if (allowed) then
		-- 		C_PartyInfo.ConvertToRaid()
		-- 	-- else
		-- 	-- 	Core:Print("ConvertToRaid not allowed")
		-- 	-- end
		-- end

		for a=1, inviteIndex - 1 do
			local inviteName = invitingMembers[a]
			if (inviteName ~= me) then
				if not IsInRaid() and GetNumGroupMembers() == 5 then 
					C_PartyInfo.ConvertToRaid()
				end

				C_PartyInfo.InviteUnit(inviteName)
			end
		end
	end
end

function Core:GetGuildKey()
	local guildName, _, _, realmName = GetGuildInfo("player")

	if (guildName == nil) then
		return nil
	end

	if (realmName == nil) then
		realmName = GetNormalizedRealmName()
	end

	local regionId = GetCurrentRegion()

	local guildKey = guildName .. "-" .. regionId .. "-"  .. realmName

	if (GOW.DB.profile.guilds == nil) then
		GOW.DB.profile.guilds = {}
	end

	if (GOW.DB.profile.guilds[guildKey] == nil) then
		GOW.DB.profile.guilds[guildKey] = { }
	end

	return guildKey
end

local rosterUpdates = 0

function Core:SetRosterInfo()
	local numTotalMembers, numOnlineMaxLevelMembers, numOnlineMembers = GetNumGuildMembers();

	if (numTotalMembers > 0) then
		local guildKey = Core:GetGuildKey()

		if (guildKey) then
			--local guildMOTD = GetGuildRosterMOTD();

			rosterUpdates = rosterUpdates + 1

			if (rosterUpdates >= 3 and not isEventAttendancesChecked and ns.UPCOMING_EVENTS ~= nil and ns.UPCOMING_EVENTS.totalEvents > 0) then
				Core:Print("Checking attendances")
				Core:CheckEventInvites()
			end

			if (GOW.DB.profile.guilds[guildKey].roster == nil) then
				GOW.DB.profile.guilds[guildKey].roster = { }
			end

			GOW.DB.profile.guilds[guildKey].rosterRefreshTime = GetServerTime()
			GOW.DB.profile.guilds[guildKey].motd = GetGuildRosterMOTD()

			for i=1, numTotalMembers do
				local name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName, achievementPoints, achievementRank, isMobile, isSoREligible, standingID, guid = GetGuildRosterInfo(i);
				if (name) then
					local years, months, days, hours = GetGuildRosterLastOnline(i);

					if (years == nil) then
						years = 0
					end

					if (months == nil) then
						months = 0
					end

					if (days == nil) then
						days = 0
					end

					if (hours == nil) then
						hours = 0
					end

					GOW.DB.profile.guilds[guildKey].roster[name] = { }
					GOW.DB.profile.guilds[guildKey].roster[name].guid = guid;
					GOW.DB.profile.guilds[guildKey].roster[name].note = note;
					GOW.DB.profile.guilds[guildKey].roster[name].rank = rank;
					GOW.DB.profile.guilds[guildKey].roster[name].rankIndex = rankIndex;
					GOW.DB.profile.guilds[guildKey].roster[name].officerNote = officernote;
					GOW.DB.profile.guilds[guildKey].roster[name].lastOnlineYears = years;
					GOW.DB.profile.guilds[guildKey].roster[name].lastOnlineMonths = months;
					GOW.DB.profile.guilds[guildKey].roster[name].lastOnlineDays = days;
					GOW.DB.profile.guilds[guildKey].roster[name].lastOnlineHours = hours;
				end
			end
		end
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