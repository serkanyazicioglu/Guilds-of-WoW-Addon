local GOW = GuildsOfWow;

local WQ = {};
local function newWorkQueue()
	return GOW.Class:createObject(WQ, { runningTimer = nil, queue = GOW.List.new() });
end
GOW.Class:createClass("WorkQueue", WQ, newWorkQueue);

function WQ:prepareNextTask()
	local elem = self.queue:peek();
	if (elem) then
		if (elem.event) then
			GOW.events:RegisterEvent(elem.event, function()
				GOW.events:UnregisterEvent(elem.event);
				self.runningTimer = GOW.timers:ScheduleTimer(function() self:runTask() end, elem.delay);
			end)
		else
			self.runningTimer = GOW.timers:ScheduleTimer(function() self:runTask() end, elem.delay);
		end
	end
end

function WQ:isEmpty()
	return self.queue:isEmpty();
end

function WQ:addTask(funcToCall, waitForEvent, delay)
	if (delay == nil) then
		delay = 0.1;
	end
	local queueWasEmpty = self.queue:isEmpty();
	self.queue:push({ func = funcToCall, event = waitForEvent, delay = delay });

	if (queueWasEmpty) then
		self:prepareNextTask();
	end
end

function WQ:runTask()
	if (self.runningTimer) then
		GOW.timers:CancelTimer(self.runningTimer);
		self.runningTimer = nil;
	end

	local elem = self.queue:pop();
	if (elem) then
		elem.func();
	end

	if (not self.queue:isEmpty()) then
		self:prepareNextTask();
	end
end

function WQ:clearTasks()
	if (self.runningTimer) then
		GOW.timers:CancelTimer(self.runningTimer);
		self.runningTimer = nil;
	end

	while (not self.queue:isEmpty()) do
		local elem = self.queue:pop();
		if elem and elem.event then
			GOW.events:UnregisterEvent(elem.event);
		end
	end

	self.queue = GOW.List.new();
end
