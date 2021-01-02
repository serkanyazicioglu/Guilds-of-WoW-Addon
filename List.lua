
local GOW = GuildsOfWow

local List = {}
local function newList()
	return GOW.Class:createObject(List, {first = 0, last = -1})
end
GOW.Class:createClass("List", List, newList)


function List:push(value)
	local last = self.last + 1
	self.last = last
	self[last] = value
end

function List:isEmpty()
	if self.first > self.last then
		return true
	else
		return false
	end
end

function List:peek()
	if self:isEmpty() then error("list is empty") end
	return self[self.first]
end

function List:pop()
	local value = self:peek()
	self[self.first] = nil
	self.first = self.first + 1
	return value
end

function List:clear()
	while not self:isEmpty() do
		self:pop()
	end
end
