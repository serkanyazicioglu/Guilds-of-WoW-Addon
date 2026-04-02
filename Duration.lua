local GOW = GuildsOfWow or {};

local Duration = {};
GOW.Duration = Duration;

local function FormatRelativeTime(timestamp)
    if (not timestamp or timestamp <= 0) then
        return "";
    end

    local now = GetServerTime and GetServerTime() or time();
    local delta = math.max(0, now - timestamp);

    if (delta < 60) then
        return delta .. "s ago";
    elseif (delta < 3600) then
        return math.floor(delta / 60) .. "m ago";
    elseif (delta < 86400) then
        return math.floor(delta / 3600) .. "h ago";
    elseif (delta < 604800) then
        return math.floor(delta / 86400) .. "d ago";
    else
        return date("%d %B", timestamp);
    end
end

function Duration:Format(timestamp)
    return FormatRelativeTime(timestamp);
end

function Duration:CreateLabel(parent, options)
    local opts = type(options) == "table" and options or {};
    local label = parent:CreateFontString(nil, "OVERLAY", opts.fontObject or "GameFontHighlight");
    label.timestamp = nil;
    label.updateInterval = opts.updateInterval or 30;
    label.ticker = nil;

    function label:Refresh()
        self:SetText(Duration:Format(self.timestamp));
    end

    function label:SetTimestamp(timestamp)
        self.timestamp = timestamp;
        self:Refresh();
    end

    function label:Stop()
        if (self.ticker) then
            self.ticker:Cancel();
            self.ticker = nil;
        end
    end

    function label:Start()
        self:Stop();
        self:Refresh();
        self.ticker = C_Timer.NewTicker(self.updateInterval, function()
            if (self:IsShown()) then
                self:Refresh();
            end
        end);
    end

    label:HookScript("OnHide", function(self)
        self:Stop();
    end);

    label:HookScript("OnShow", function(self)
        if (self.timestamp) then
            self:Start();
        end
    end);

    return label;
end
