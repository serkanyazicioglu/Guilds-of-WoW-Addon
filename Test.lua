local function createCalendarEvent(event)
    log("createCalendarEvent")
    message('createCalendarEvent!')
	--if event.guildEvent and IsInGuild() then
		--C_Calendar.CreateGuildSignUpEvent()
	--else
	C_Calendar.CreatePlayerEvent()
	--end
	C_Calendar.EventSetTitle(event.title)
	C_Calendar.EventSetDescription(event.description)
	C_Calendar.EventSetType(event.type)
	C_Calendar.EventSetTime(event.hour, event.minute)
	C_Calendar.EventSetDate(event.month, event.day, event.year)
	C_Calendar.MassInviteGuild(event.minLevel, event.maxLevel, event.maxRank)
	--if not event.guildEvent and event.customGuildInvite and IsInGuild() then
		
	--end

	--local cache = RCE.core:getCacheForEventType(event.type)
	--if cache ~= nil then
	--	local textureId = cache[event.raidOrDungeon].difficulties[event.difficulty].index
	--	C_Calendar.EventSetTextureID(textureId)
	--end
end

if (IsInGuild()) then
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
    createCalendarEvent(event)
end