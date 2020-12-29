local GowGuildEvents = {}
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")

function GowGuildEvents:CreateUpcomingEvents()
	if (IsInGuild()) then
		SendChatMessage("Hi Guild222!", "GUILD");

		local event = {}
		event.title = "test event"
		event.description = "test description"
		event.type = Enum.CalendarEventType.Other
		event.minLevel = 1
		event.maxLevel = 60
		event.hour = 23
		event.minute = 0
		event.day = 29
		event.month = 12
		event.year = 2020
		event.maxRank = 8

		GowGuildEvents:CreateCalendarEvent(event)
	else
		print("Not in guild!")
	end
end

function GowGuildEvents:CreateCalendarEvent(event)
    print("createCalendarEvent!")
	--if event.guildEvent and IsInGuild() then
		--C_Calendar.CreateGuildSignUpEvent()
	--else
	C_Calendar.CreatePlayerEvent()
	--end
	C_Calendar.EventSetTitle(event.title)
	--C_Calendar.EventSetDescription(event.description)
	--C_Calendar.EventSetType(event.type)
	C_Calendar.EventSetTime(event.hour, event.minute)
	C_Calendar.EventSetDate(event.month, event.day, event.year)
	--C_Calendar.MassInviteGuild(event.minLevel, event.maxLevel, event.maxRank)
	C_Calendar.AddEvent()
	print("event created!")
	--if not event.guildEvent and event.customGuildInvite and IsInGuild() then
		
	--end

	--local cache = RCE.core:getCacheForEventType(event.type)
	--if cache ~= nil then
	--	local textureId = cache[event.raidOrDungeon].difficulties[event.difficulty].index
	--	C_Calendar.EventSetTextureID(textureId)
	--end
end

f:SetScript("OnEvent", function(self,event, ...)
    if event == "PLAYER_LOGIN" then
		print("Executing guild events...")
		GowGuildEvents:CreateUpcomingEvents()
	end
end)

