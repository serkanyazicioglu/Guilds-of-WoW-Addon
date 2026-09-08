local GOW = GuildsOfWow;
local Manager = {};

GOW.Class:createSingleton("AttendanceManager", Manager, {
	pendingEvents = {},
	queue = {},
	timers = {},
	openEventRetries = {},
});

local function cancelTimer(self, name)
	if (self.timers[name]) then
		GOW.timers:CancelTimer(self.timers[name]);
		self.timers[name] = nil;
	end
end

local function schedule(self, name, callback, delay)
	cancelTimer(self, name);
	self.timers[name] = GOW.timers:ScheduleTimer(function()
		self.timers[name] = nil;
		callback();
	end, delay);
end

function Manager:Initialize(upcomingEvents)
	self.upcomingEvents = upcomingEvents;
	if (not self.periodicTimer) then
		self.periodicTimer = GOW.timers:ScheduleRepeatingTimer(function()
			self:RequestCapture("periodic refresh");
		end, GOW.consts.ATTENDANCE_REFRESH_INTERVAL);
	end
end

function Manager:SetWorkQueue(workQueue)
	self.workQueue = workQueue;
end

function Manager:RequestCapture(reason, upcomingEvent)
	if (not self.upcomingEvents or not GOW.Helper:IsInGameCalendarAccessible()) then return; end
	if (upcomingEvent) then
		self.pendingEvents[upcomingEvent.titleWithKey] = upcomingEvent;
	else
		self.pendingAll = true;
	end
	GOW.Logger:Debug("Attendance capture requested: " .. tostring(reason));
	if (not self.running) then
		schedule(self, "start", function() self:StartCapture(); end, GOW.consts.ATTENDANCE_REFRESH_DEBOUNCE);
	end
end

function Manager:BuildQueue()
	local result = {};
	local guildName, _, _, realmName = GetGuildInfo("player");
	if (not guildName) then return result; end
	realmName = realmName or GetNormalizedRealmName();
	local regionId = GOW.Helper:GetCurrentRegionByGameVersion();
	local serverTime = C_DateAndTime.GetServerTimeLocal();

	for i = 1, self.upcomingEvents.totalEvents or 0 do
		local upcomingEvent = self.upcomingEvents.events[i];
		if ((self.pendingAll or self.pendingEvents[upcomingEvent.titleWithKey])
			and upcomingEvent.eventDate >= serverTime
			and guildName == upcomingEvent.guild
			and realmName == upcomingEvent.guildRealmNormalized
			and regionId == upcomingEvent.guildRegionId) then
			table.insert(result, upcomingEvent);
		end
	end
	self.pendingAll = false;
	self.pendingEvents = {};
	return result;
end

function Manager:StartCapture()
	if (self.running or (not self.pendingAll and next(self.pendingEvents) == nil)) then return; end
	if (not GOW.Core:IsAttendanceCaptureSafe()) then
		schedule(self, "start", function() self:StartCapture(); end, GOW.consts.ATTENDANCE_REFRESH_RETRY_DELAY);
		return;
	end
	self.queue = self:BuildQueue();
	self.running = true;
	self:ProcessNext();
end

function Manager:ProcessNext()
	if (not self.running) then return; end
	if (not GOW.Core:IsAttendanceCaptureSafe()) then
		self.pendingAll = true;
		self:FinishCapture();
		return;
	end

	local upcomingEvent = table.remove(self.queue, 1);
	if (not upcomingEvent) then
		self:FinishCapture();
		return;
	end

	local eventIndex, offsetMonths, dayEvent = GOW.Core:searchForEvent(upcomingEvent);
	if (eventIndex == -2) then
		table.insert(self.queue, 1, upcomingEvent);
		schedule(self, "next", function() self:ProcessNext(); end, GOW.consts.ATTENDANCE_REFRESH_RETRY_DELAY);
	elseif (eventIndex <= 0 or not GOW.Helper:IsPlayerCreatedInGameEvent(dayEvent) or not GOW.Helper:IsInGameEventAdmin(dayEvent)) then
		self:ProcessNext();
	else
		self.currentEvent = upcomingEvent;
		self.currentRetryCount = 0;
		self.currentCaptured = false;
		if (not C_Calendar.OpenEvent(offsetMonths, upcomingEvent.day, eventIndex)) then
			self.currentEvent = nil;
			table.insert(self.queue, 1, upcomingEvent);
			schedule(self, "next", function() self:ProcessNext(); end, GOW.consts.ATTENDANCE_REFRESH_RETRY_DELAY);
		end
	end
end

function Manager:FinishCapture()
	self.running = false;
	self.queue = {};
	self.currentEvent = nil;
	self.currentCaptured = false;
	if (self.pendingAll or next(self.pendingEvents) ~= nil) then
		schedule(self, "start", function() self:StartCapture(); end, GOW.consts.ATTENDANCE_REFRESH_RETRY_DELAY);
	end
end

function Manager:ScheduleCurrentRead(delay)
	schedule(self, "read", function() self:CaptureCurrent(); end, delay);
end

function Manager:OnCalendarOpenEvent()
	if (self.running and self.currentEvent) then
		self:ScheduleCurrentRead(GOW.consts.ATTENDANCE_REFRESH_DEBOUNCE);
		return true;
	end

	if (GOW.Core:IsEventSynchronizationCompleted() and not GOW.Core:IsNewEventBeingCreated()) then
		self:TrackUserOpenEvent();
		return self.userEvent ~= nil;
	end
	return false;
end

function Manager:OnCalendarReady()
	if (self.running and self.currentEvent) then
		self:ScheduleCurrentRead(GOW.consts.ATTENDANCE_REFRESH_DEBOUNCE);
	elseif (C_Calendar.IsEventOpen()) then
		self:TrackUserOpenEvent();
		if (self.userEvent) then
			GOW.Logger:Debug("Calendar action completed for tracked event: " .. self.userEvent.titleWithKey);
			self:CaptureUserOpenEvent(nil);
		end
	end
end

function Manager:OnInviteListUpdated(hasCompleteList)
	if (self.running and self.currentEvent) then
		if (hasCompleteList == false) then
			self:RetryCurrent("invite list is incomplete");
		else
			self:ScheduleCurrentRead(GOW.consts.ATTENDANCE_REFRESH_DEBOUNCE);
		end
		return true;
	end

	if (GOW.Core:IsEventSynchronizationCompleted() and C_Calendar.IsEventOpen()) then
		self:TrackUserOpenEvent();
		if (self.userEvent) then
			self:CaptureUserOpenEvent(hasCompleteList);
			return true;
		end
	end
	return false;
end

function Manager:CaptureCurrent()
	local upcomingEvent = self.currentEvent;
	local eventInfo = C_Calendar.IsEventOpen() and C_Calendar.GetEventInfo() or nil;
	if (not upcomingEvent or not eventInfo or eventInfo.title ~= upcomingEvent.titleWithKey) then
		self:RetryCurrent("event is not ready");
		return;
	end

	local _, attendances, readError = self:ReadCurrentInviteData();
	if (not attendances) then
		self:RetryCurrent(readError);
		return;
	end
	self:SaveSnapshot(upcomingEvent, attendances);
	self.currentCaptured = true;
	C_Calendar.CloseEvent();
end

function Manager:RetryCurrent(reason)
	if (not self.currentEvent) then return; end
	self.currentRetryCount = self.currentRetryCount + 1;
	if (self.currentRetryCount <= GOW.consts.ATTENDANCE_REFRESH_MAX_RETRIES) then
		GOW.Logger:Debug("Retrying attendance capture: " .. tostring(reason));
		self:ScheduleCurrentRead(GOW.consts.ATTENDANCE_REFRESH_RETRY_DELAY);
		return;
	end

	GOW.Logger:Debug("Skipping attendance capture: " .. tostring(reason));
	self.currentCaptured = true;
	if (C_Calendar.IsEventOpen()) then
		C_Calendar.CloseEvent();
	else
		self.currentEvent = nil;
		self:ProcessNext();
	end
end

function Manager:OnCalendarCloseEvent()
	if (self.running and self.currentEvent) then
		cancelTimer(self, "read");
		if (not self.currentCaptured) then
			self.pendingEvents[self.currentEvent.titleWithKey] = self.currentEvent;
		end
		self.currentEvent = nil;
		self.currentCaptured = false;
		schedule(self, "next", function() self:ProcessNext(); end, GOW.consts.ATTENDANCE_REFRESH_DEBOUNCE);
		return true;
	end

	if (not self.userEvent and C_Calendar.IsEventOpen()) then
		self:TrackUserOpenEvent();
	end

	local eventToCapture = self.userEvent;
	local wasDirty = self.userEventDirty;
	cancelTimer(self, "user");
	self.userEvent = nil;
	self.userEventDirty = false;
	self.userRetryCount = 0;
	if (eventToCapture) then
		local reason = wasDirty and "dirty event closed" or "tracked event closed";
		self:RequestCapture(reason, eventToCapture);
	else
		-- WoW can close the event before exposing enough information to identify it.
		-- Fall back to a coalesced full scan so an RSVP change is never missed.
		self:RequestCapture("untracked calendar event closed; full refresh fallback");
	end
	return false;
end

function Manager:OnCalendarShown()
	if (self.running) then
		cancelTimer(self, "read");
		self.pendingAll = true;
		self.userEvent = self.currentEvent;
		self.userEventDirty = false;
		self.running = false;
		self.queue = {};
		self.currentEvent = nil;
		schedule(self, "start", function() self:StartCapture(); end, GOW.consts.ATTENDANCE_REFRESH_RETRY_DELAY);
	end
end

function Manager:OnCalendarChanged(eventName)
	if (self.running) then
		self.pendingAll = true;
		return;
	end
	if (GOW.Core:IsEventSynchronizationCompleted() and C_Calendar.IsEventOpen()) then
		self:TrackUserOpenEvent();
		if (self.userEvent) then
			self.userEventDirty = true;
		end
	else
		self:RequestCapture(eventName);
	end
end

function Manager:TrackUserOpenEvent()
	if (self.running) then return false; end
	if (not C_Calendar.IsEventOpen()) then
		GOW.Logger:Debug("Cannot track calendar event because no event is open.");
		return false;
	end

	local eventInfo = C_Calendar.GetEventInfo();
	if (not eventInfo or not eventInfo.title or eventInfo.title == "") then
		GOW.Logger:Debug("Cannot track open calendar event because its event info is unavailable.");
		return false;
	end
	if (not GOW.Helper:IsPlayerCreatedInGameEvent(eventInfo)) then
		GOW.Logger:Debug("Open calendar event is not a Player or Guild event: " .. tostring(eventInfo.title));
		return false;
	end
	if (not GOW.Helper:IsInGameEventAdmin(eventInfo)) then
		GOW.Logger:Debug("Open calendar event is not managed by the current player: " .. tostring(eventInfo.title)
			.. ". modStatus: " .. tostring(eventInfo.modStatus));
		return false;
	end

	local upcomingEvent = GOW.Core:FindUpcomingEventFromName(eventInfo.title);
	if (upcomingEvent and self.userEvent and self.userEvent.titleWithKey ~= upcomingEvent.titleWithKey) then
		if (self.userEventDirty) then
			self:RequestCapture("user switched calendar events before snapshot", self.userEvent);
		end
		cancelTimer(self, "user");
		self.userEventDirty = false;
		self.userRetryCount = 0;
	end
	self.userEvent = upcomingEvent;
	if (upcomingEvent) then
		GOW.Logger:Debug("Tracking user-open calendar event: " .. upcomingEvent.titleWithKey);
		return true;
	end

	GOW.Logger:Debug("Open calendar event is not a current GoW event: " .. tostring(eventInfo.title));
	return false;
end

function Manager:CaptureUserOpenEvent(hasCompleteList)
	local upcomingEvent = self.userEvent;
	if (not upcomingEvent) then return; end
	self.userEventDirty = true;
	if (hasCompleteList == false) then
		self.userRetryCount = self.userRetryCount + 1;
		if (self.userRetryCount <= GOW.consts.ATTENDANCE_REFRESH_MAX_RETRIES) then
			schedule(self, "user", function() self:CaptureUserOpenEvent(nil); end, GOW.consts.ATTENDANCE_REFRESH_RETRY_DELAY);
		end
		return;
	end

	schedule(self, "user", function()
		if (not C_Calendar.IsEventOpen()) then
			self:RequestCapture("calendar closed before snapshot", upcomingEvent);
			return;
		end
		local eventInfo = C_Calendar.GetEventInfo();
		if (not eventInfo or eventInfo.title ~= upcomingEvent.titleWithKey) then
			self:RequestCapture("another calendar event opened before snapshot", upcomingEvent);
			return;
		end
		local _, attendances, readError = self:ReadCurrentInviteData();
		if (attendances) then
			self:SaveSnapshot(upcomingEvent, attendances);
			self.userEventDirty = false;
			self.userRetryCount = 0;
		else
			self.userRetryCount = self.userRetryCount + 1;
			if (self.userRetryCount <= GOW.consts.ATTENDANCE_REFRESH_MAX_RETRIES) then
				GOW.Logger:Debug("Retrying user-open attendance snapshot: " .. tostring(readError));
				self:CaptureUserOpenEvent(nil);
			end
		end
	end, GOW.consts.ATTENDANCE_REFRESH_DEBOUNCE);
end

function Manager:ReadCurrentInviteData()
	if (not C_Calendar.IsEventOpen() or C_Calendar.IsActionPending()) then return nil, nil, "calendar action pending"; end
	if (C_Calendar.AreNamesReady and not C_Calendar.AreNamesReady()) then return nil, nil, "invite names are not ready"; end

	local invitesNum = C_Calendar.GetNumInvites();
	local inviteRows, attendances = {}, {};
	for inviteIndex = 1, invitesNum do
		local inviteInfo = C_Calendar.EventGetInvite(inviteIndex);
		if (not inviteInfo or not inviteInfo.name or inviteInfo.name == "" or inviteInfo.inviteStatus == nil) then
			return nil, nil, "invite list contains an incomplete row";
		end
		inviteRows[inviteIndex] = inviteInfo;
		if (inviteInfo.inviteStatus > Enum.CalendarStatus.Invited) then
			local responseTime = C_Calendar.EventGetInviteResponseTime(inviteIndex);
			local responseTimeFormatted = nil;
			if (responseTime) then
				responseTimeFormatted = responseTime.year .. "-" .. string.lpad(tostring(responseTime.month), 2, '0') .. "-" .. string.lpad(tostring(responseTime.monthDay), 2, '0') .. "T" .. string.lpad(tostring(responseTime.hour), 2, '0') .. ":" .. string.lpad(tostring(responseTime.minute), 2, '0');
			end
			table.insert(attendances, { name = inviteInfo.name, level = inviteInfo.level, attendance = inviteInfo.inviteStatus, classId = inviteInfo.classID, guid = inviteInfo.guid, date = responseTimeFormatted });
		end
	end
	if (C_Calendar.GetNumInvites() ~= invitesNum) then return nil, nil, "invite list changed while it was being read"; end
	return inviteRows, attendances, nil;
end

function Manager:SaveSnapshot(upcomingEvent, attendances)
	local guildKey = GOW.Core:GetGuildKey();
	if (not guildKey) then return false; end
	local guildData = GOW.DB.profile.guilds[guildKey];
	local eventId, refreshTime = tostring(upcomingEvent.id), GetServerTime();
	guildData.events = guildData.events or {};
	guildData.events[eventId] = guildData.events[eventId] or {};
	guildData.events[eventId].refreshTime = refreshTime;
	guildData.events[eventId].attendances = attendances;
	guildData.eventsRefreshTime = refreshTime;
	GOW.Logger:Debug("Captured event attendances: " .. upcomingEvent.titleWithKey .. ". Attendances: " .. tostring(#attendances));
	return true;
end

function Manager:InviteMultiplePeopleToEvent(upcomingEvent)
	local currentPlayer = GOW.Helper:GetCurrentCharacterUniqueKey();
	local invitesNum = C_Calendar.GetNumInvites();
	if (invitesNum >= upcomingEvent.totalMembers or invitesNum >= 100) then
		GOW.Core:EventAttendanceProcessCompleted(upcomingEvent, true);
		return;
	end

	GOW.Logger:PrintMessage("Event invites are being processed in the background. Please wait for the process to complete before logging out.");
	for i = 1, upcomingEvent.totalMembers do
		local member = upcomingEvent.inviteMembers[i];
		local inviteName = member.name .. "-" .. member.realmNormalized;
		if (not GOW.Helper:AreCharacterNamesEqual(inviteName, currentPlayer)) then
			self.workQueue:addTask(function() C_Calendar.EventInvite(inviteName); end, nil, GOW.consts.INVITE_INTERVAL);
		end
	end
end

function Manager:CreateEventInvites(upcomingEvent, closeAfterEnd)
	if (GOW.Core:IsEventProcessed(upcomingEvent.titleWithKey)) then return; end
	if (not C_Calendar.EventCanEdit()) then
		self:RetryOpenEvent(upcomingEvent, function()
			self:CreateEventInvites(upcomingEvent, closeAfterEnd);
		end, function()
			self:HandleOpenEventFailure(upcomingEvent, "calendar event did not become editable", closeAfterEnd);
		end);
		return;
	end
	if (upcomingEvent.calendarType == GOW.consts.GUILD_EVENT) then
		self:SetAttendance(upcomingEvent, closeAfterEnd, false);
		return;
	end

	local inviteRows, _, readError = self:ReadCurrentInviteData();
	if (not inviteRows) then
		self:RetryOpenEvent(upcomingEvent, function() self:CreateEventInvites(upcomingEvent, closeAfterEnd); end, function()
			self:HandleOpenEventFailure(upcomingEvent, readError, closeAfterEnd);
		end);
		return;
	end
	if (#inviteRows >= 100) then
		self:SetAttendance(upcomingEvent, closeAfterEnd, true);
		return;
	end

	local invitedCount = 0;
	for m = 1, upcomingEvent.totalMembers do
		local member = upcomingEvent.inviteMembers[m];
		local inviteName = member.name .. "-" .. member.realmNormalized;
		local isInvited = false;
		for a = 1, #inviteRows do
			local inviteInfo = inviteRows[a];
			isInvited = (string.find(inviteInfo.name, "-") and GOW.Helper:AreCharacterNamesEqual(inviteInfo.name, inviteName))
				or (inviteInfo.name == member.name and inviteInfo.level == member.level and inviteInfo.classID == member.classId);
			if (isInvited) then
				break
			end
		end
		if (not isInvited) then
			self.workQueue:addTask(function() C_Calendar.EventInvite(inviteName); end, nil, GOW.consts.INVITE_INTERVAL);
			invitedCount = invitedCount + 1;
		end
	end

	if (invitedCount > 0) then
		self.workQueue:addTask(function() self:SetAttendance(upcomingEvent, closeAfterEnd, true); end, nil, 10);
	else
		self:SetAttendance(upcomingEvent, closeAfterEnd, true);
	end
end

function Manager:SetAttendance(upcomingEvent, closeAfterEnd, applyImportedValues)
	if (not C_Calendar.EventCanEdit()) then
		self:RetryOpenEvent(upcomingEvent, function()
			self:SetAttendance(upcomingEvent, closeAfterEnd, applyImportedValues);
		end, function()
			if (applyImportedValues) then
				self:HandleImportFailure(upcomingEvent, "calendar event did not become editable", closeAfterEnd);
			else
				self:RequestCapture("calendar event was not editable", upcomingEvent);
				GOW.Core:EventAttendanceProcessCompleted(upcomingEvent, closeAfterEnd);
			end
		end);
		return;
	end
	local inviteRows, attendances, readError = self:ReadCurrentInviteData();
	if (not inviteRows) then
		GOW.Logger:Debug("Attendance list is not ready: " .. tostring(readError));
		self:RetryOpenEvent(upcomingEvent, function()
			self:SetAttendance(upcomingEvent, closeAfterEnd, applyImportedValues);
		end, function()
			if (applyImportedValues) then
				self:HandleImportFailure(upcomingEvent, readError, closeAfterEnd);
			else
				self:RequestCapture("attendance read failed", upcomingEvent);
				GOW.Core:EventAttendanceProcessCompleted(upcomingEvent, closeAfterEnd);
			end
		end);
		return;
	end
	self:ResetOpenEventRetry(upcomingEvent);

	local changedCount = 0;
	if (applyImportedValues
		and upcomingEvent.calendarType == GOW.consts.PLAYER_EVENT
		and not GOW.Core:IsEventProcessed(upcomingEvent.titleWithKey)) then
		for inviteIndex = 1, #inviteRows do
			if (self:SetAttendanceValue(upcomingEvent, inviteRows[inviteIndex], inviteIndex)) then
				changedCount = changedCount + 1;
			end
		end
	end

	self:SaveSnapshot(upcomingEvent, attendances);
	if (changedCount > 0) then
		self.workQueue:addTask(function()
			self:SetAttendance(upcomingEvent, closeAfterEnd, false);
		end, nil, GOW.consts.INVITE_INTERVAL);
	else
		GOW.Core:EventAttendanceProcessCompleted(upcomingEvent, closeAfterEnd);
	end
end

function Manager:SetAttendanceValue(upcomingEvent, inviteInfo, inviteIndex)
	for m = 1, upcomingEvent.totalMembers do
		local member = upcomingEvent.inviteMembers[m];
		if (member and (member.isManager or member.inviteStatus > Enum.CalendarStatus.Invited)) then
			local isMatch = (string.find(inviteInfo.name, "-") and GOW.Helper:AreCharacterNamesEqual(inviteInfo.name, member.name .. "-" .. member.realmNormalized))
				or (inviteInfo.name == member.name and inviteInfo.level == member.level and inviteInfo.classID == member.classId);
			if (isMatch) then
				local changed = false;
				if (member.isManager and not GOW.Helper:IsInGameEventAdmin(inviteInfo)) then
					changed = true;
					self.workQueue:addTask(function() C_Calendar.EventSetModerator(inviteIndex); end, nil, GOW.consts.INVITE_INTERVAL);
				end
				if (member.forceUpdate or (member.inviteStatus > Enum.CalendarStatus.Invited and inviteInfo.inviteStatus == Enum.CalendarStatus.Invited)) then
					if (not (member.inviteStatus == Enum.CalendarStatus.Available and inviteInfo.inviteStatus == Enum.CalendarStatus.Confirmed)
						and member.inviteStatus ~= inviteInfo.inviteStatus) then
						changed = true;
						self.workQueue:addTask(function() C_Calendar.EventSetInviteStatus(inviteIndex, member.inviteStatus); end, nil, GOW.consts.INVITE_INTERVAL);
					end
				end
				return changed;
			end
		end
	end
	return false;
end

function Manager:RetryOpenEvent(upcomingEvent, retryCallback, failedCallback)
	local eventKey = upcomingEvent.titleWithKey;
	local retryCount = (self.openEventRetries[eventKey] or 0) + 1;
	self.openEventRetries[eventKey] = retryCount;
	if (retryCount > GOW.consts.ATTENDANCE_REFRESH_MAX_RETRIES) then
		self.openEventRetries[eventKey] = nil;
		cancelTimer(self, "openRetry");
		failedCallback();
	else
		schedule(self, "openRetry", function()
			local eventInfo = C_Calendar.IsEventOpen() and C_Calendar.GetEventInfo() or nil;
			if (eventInfo and eventInfo.title == upcomingEvent.titleWithKey) then
				retryCallback();
			else
				self.openEventRetries[eventKey] = nil;
				failedCallback();
			end
		end, GOW.consts.ATTENDANCE_REFRESH_RETRY_DELAY);
	end
end

function Manager:ResetOpenEventRetry(upcomingEvent)
	self.openEventRetries[upcomingEvent.titleWithKey] = nil;
	cancelTimer(self, "openRetry");
end

function Manager:RetryIncompleteOpenEvent(closeAfterEnd)
	if (not C_Calendar.IsEventOpen()) then return; end
	local eventInfo = C_Calendar.GetEventInfo();
	local upcomingEvent = eventInfo and GOW.Core:FindUpcomingEventFromName(eventInfo.title) or nil;
	if (not upcomingEvent) then return; end

	self:RetryOpenEvent(upcomingEvent, function()
		self:CreateEventInvites(upcomingEvent, closeAfterEnd);
	end, function()
		self:HandleOpenEventFailure(upcomingEvent, "invite list remained incomplete", closeAfterEnd);
	end);
end

function Manager:HandleOpenEventFailure(upcomingEvent, reason, closeAfterEnd)
	if (closeAfterEnd) then
		self:HandleImportFailure(upcomingEvent, reason, closeAfterEnd);
	else
		self:RequestCapture("event attendance update failed", upcomingEvent);
		GOW.Core:EventAttendanceProcessCompleted(upcomingEvent, closeAfterEnd);
	end
end

function Manager:HandleImportFailure(upcomingEvent, reason, closeAfterEnd)
	self.importFailed = true;
	self.failedImportEvents = self.failedImportEvents or {};
	self.failedImportEvents[upcomingEvent.titleWithKey] = true;
	local guildKey = GOW.Core:GetGuildKey();
	if (guildKey) then
		GOW.DB.profile.guilds[guildKey].attendanceSyncError = {
			event = upcomingEvent.titleWithKey,
			reason = tostring(reason),
			time = GetServerTime(),
		};
	end
	GOW.Core:EventAttendanceProcessFailed(upcomingEvent, closeAfterEnd);
end

function Manager:OnLegacyImportCompleted()
	local guildKey = GOW.Core:GetGuildKey();
	if (guildKey and self.importFailed) then
		GOW.Logger:PrintErrorMessage("Some event RSVP data could not be imported. The addon will retry automatically.");
		local failedEvents = self.failedImportEvents or {};
		self.failedImportEvents = {};
		schedule(self, "importRetry", function()
			self.importFailed = false;
			GOW.Core:RetryEventImports(failedEvents);
		end, GOW.consts.ATTENDANCE_REFRESH_INTERVAL);
	elseif (guildKey and self.upcomingEvents and self.upcomingEvents.exportTime) then
		GOW.DB.profile.guilds[guildKey].lastAppliedEventsExportTime = self.upcomingEvents.exportTime;
		GOW.DB.profile.guilds[guildKey].attendanceSyncError = nil;
	end
	self:RequestCapture("initial import completed");
end
