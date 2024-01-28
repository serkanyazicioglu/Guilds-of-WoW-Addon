local GOW = GuildsOfWow;
local ClassHelper = {};
GOW.Class = ClassHelper;

function ClassHelper:createClass(className, class, newFunction)
	GOW[className] = {};
	GOW[className].new = newFunction;
	class.__index = class;
	return GOW[className];
end

function ClassHelper:createSingleton(className, class, initData)
	GOW[className] = {};
	class.__index = class;
	local instance = self:createObject(class, initData);
	GOW[className] = instance;
	return instance;
end

function ClassHelper:createObject(class, initData)
	if initData == nil then
		initData = {};
	end
	setmetatable(initData, class);
	return initData;
end
