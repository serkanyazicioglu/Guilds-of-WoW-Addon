local GOW = GuildsOfWow;
local GoWComm = {};
GOW.GoWComm = GoWComm;

local ns = select(2, ...)

local gameVersion = nil;
if GOW and GOW.Core and GOW.Core.GetGowGameVersionId then
    gameVersion = GOW.Core:GetGowGameVersionId();
end

function GOW:OnEnable()
    if not gameVersion or gameVersion ~= 1 then
        return;
    end

    if GOW.eventMessageTimer then
        GOW.timers:CancelTimer(GOW.eventMessageTimer);
    end

    -- Registering the communication prefix for the addon.
    GOW:RegisterComm("GuildsOfWoW", "OnCommReceived");

    -- check events on login
    local initialEvents = GoWComm:GetUpcomingEvents(ns.UPCOMING_EVENTS);
    GoWComm:CheckEvents(initialEvents);

    -- A timer to periodically send the upcoming events data.
    self.eventMessageTimer = self.timers:ScheduleRepeatingTimer(function()
        local events = GoWComm:GetUpcomingEvents(ns.UPCOMING_EVENTS);
        GoWComm:CheckEvents(events);
    end, 300); -- Send every 5 mins.
end

function GOW:OnCommReceived(prefix, message, distribution, sender)
    -- no functionality, is needed for the addon message to work
end

function GoWComm:GetUpcomingEvents(upcomingEvents)
    -- Check if the upcoming events data is available
    if upcomingEvents == nil or upcomingEvents.totalEvents == 0 then
        return;
    end

    local events = {};
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
            };
            table.insert(events, eventData);
        end
    end
    return events
end

function GoWComm:CheckEvents(events)
    if events and #events > 0 then
        GOW.Logger:Debug("Transmitting upcoming events data to guild members.");
        GoWComm:Transmit(events);
    else
        GOW.Logger:Debug("No upcoming events found for transmission.");
    end
end

function GoWComm:Transmit(data)
    if not data or #data == 0 then
        GOW.Logger:Debug("[Addon Message] No data to transmit.");
        return;
    end

    for i = 1, 3 do
        local event = data[i];
        if event then
            GOW.Logger:Debug("Transmitting event: " .. event.title);

            local serialized = GoWComm:Serialize(event);
            if not serialized then
                GOW.Logger:Debug("[Addon Message] Failed to serialize data for transmission.");
                return;
            end

            GOW:SendCommMessage("GuildsOfWoW", serialized, "GUILD");
        end
    end
end

function GoWComm:Serialize(data)
    -- serialize the data using table.concat
    local serializedParts = {};
    for key, value in pairs(data) do
        table.insert(serializedParts, key .. "=" .. tostring(value));
    end
    return table.concat(serializedParts, "&");
end
