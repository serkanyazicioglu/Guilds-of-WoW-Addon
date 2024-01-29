local GOW = GuildsOfWow;

local WQ = {};
local function newWorkQueue()
	return GOW.Class:createObject(WQ, { runningTimer = nil, queue = GOW.List.new() });
end
GOW.Class:createClass("WorkQueue", WQ, newWorkQueue);

function WQ:prepareNextTask()
	local elem = self.queue:peek();
	if elem then
		if elem.event then
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
	if delay == nil then
		delay = 0.1;
	end
	local queueWasEmpty = self.queue:isEmpty();
	local elem = { func = funcToCall, event = waitForEvent, delay = delay };
	self.queue:push(elem);

	if queueWasEmpty then
		self:prepareNextTask();
	end
end

function WQ:runTask()
	local elem = self.queue:peek();
	if (elem ~= nil) then
		elem.func();
	end
	self.queue:pop();

	if not self.queue:isEmpty() then
		self:prepareNextTask();
	else
		self.runningTimer = nil;
	end
end

function WQ:clearTasks()
	if self.queue:isEmpty() then
		return;
	end

	local elem = self.queue:pop();

	if self.runningTimer then
		GOW.timers:CancelTimer(self.runningTimer);
	end

	if elem.event then
		GOW.events:UnregisterEvent(elem.event);
	end

	self.queue = GOW.List.new();
end
