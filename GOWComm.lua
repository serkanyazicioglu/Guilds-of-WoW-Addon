local GOW = GuildsOfWow;
local GOWComm = {};
GOW.GOWComm = GOWComm;

local ns = select(2, ...)

function GOW:OnEnable()
    if GOW.eventMessageTimer then
        GOW.timers:CancelTimer(GOW.eventMessageTimer);
    end

    -- Registering the communication prefix for the addon.
    GOW:RegisterComm("GuildsOfWoW", "OnCommReceived");

    -- check events on login
    local initialEvents = GOWComm:GetUpcomingEvents(ns.UPCOMING_EVENTS);
    GOWComm:CheckEvents(initialEvents);

    -- A timer to periodically send the upcoming events data.
    self.eventMessageTimer = self.timers:ScheduleRepeatingTimer(function()
        local events = GOWComm:GetUpcomingEvents(ns.UPCOMING_EVENTS);
        GOWComm:CheckEvents(events);
    end, 300); -- Send every 5 mins.
end

function GOW:OnCommReceived(prefix, message, distribution, sender)
    -- no functionality, is needed for the addon message to work
end

function GOWComm:GetUpcomingEvents(upcomingEvents)
    -- Check if the upcoming events data is available
    if (upcomingEvents == nil or upcomingEvents.totalEvents == 0) then
        return;
    end

    local events = {}
    local guildName = GetGuildInfo("player");

    -- grab the next 3 upcoming events for the guild
    for i = 1, 3 do
        local event = upcomingEvents.events[i];
        if event and event.guild == guildName then
            local eventData = {
                title = event.title,
                minLevel = event.minLevel,
                maxLevel = event.maxLevel,
                minItemLevel = event.minItemLevel,
                eventDate = event.eventDate,
                durationText = event.durationText,
                webUrl = event.webUrl,
                team = event.team,
            }
            tinsert(events, eventData)
        end
    end
    return events
end

function GOWComm:CheckEvents(events)
    if (events and #events > 0) then
        GOW.Logger:Debug("Transmitting upcoming events data to guild members.");
        GOWComm:Transmit(events);
    else
        GOW.Logger:Debug("No upcoming events found for transmission.");
    end
end

function GOWComm:Transmit(data)
    if not data or #data == 0 then
        GOW.Logger:Debug("[Addon Message] No data to transmit.");
        return;
    end

    for i = 1, 3 do
        local event = data[i];
        if event then
            GOW.Logger:Debug("Transmitting event: " .. event.title);

            local serialized = GOWComm:Serialize(event);
            if not serialized then
                GOW.Logger:Debug("[Addon Message] Failed to serialize data for transmission.");
                return;
            end

            GOW:SendCommMessage("GuildsOfWoW", serialized, "GUILD");
        end
    end
end

function GOWComm:Serialize(data)
    -- serialize the data using table.concat
    local serializedParts = {};
    for key, value in pairs(data) do
        table.insert(serializedParts, key .. "=" .. tostring(value));
    end
    return table.concat(serializedParts, "&");
end
