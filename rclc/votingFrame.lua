local RCLootCouncil = _G["RCLootCouncil"];
if not RCLootCouncil then return end

local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local RCGoW = GOW.RCGoW;

local RCVotingFrame = RCLootCouncil:GetModule("RCVotingFrame", true);
if not RCVotingFrame then return end

local GoWVotingColumn = RCGoW:NewModule("GoWVotingColumn", "AceTimer-3.0", "AceEvent-3.0");

local GOW_ICON = "|TInterface\\AddOns\\GuildsOfWoW\\icons\\guilds-of-wow-logo-flag-plain.png:20:20|t";

local TAG_RANK = { BIS = 1, NEED = 2, GREED = 3, MINOR = 4, OFFSPEC = 5, TRANSMOG = 6 };

local activeSession = 1;

local function GetDisplayMode()
    return (GOW.DB and GOW.DB.profile.rclcDisplayMode) or "percent";
end

local function GetActiveItemId()
    local lootTable = RCLootCouncil:GetLootTable();
    if not lootTable or not lootTable[activeSession] then return nil end
    local link = lootTable[activeSession].link;
    if not link then return nil end
    return (C_Item and C_Item.GetItemInfoInstant(link)) or tonumber(link:match("item:(%d+)"));
end

local function RenderWishCell(rowFrame, cellFrame, data, cols, row, realRow, column, fShow, st)
    if not fShow then
        cellFrame.text:SetText("");
        return;
    end

    local rowData = data[realRow];
    if not rowData then
        cellFrame.text:SetText("");
        return;
    end

    local itemId = GetActiveItemId();
    if not itemId then
        cellFrame.text:SetText("");
        return;
    end

    local wish = RCGoW:GetPlayerWish(itemId, rowData.name);
    if not wish then
        cellFrame.text:SetText("|cff666666—|r");
        cellFrame._gowTip = nil;
        return;
    end

    -- Build display string based on current toggle mode
    local display = "";
    local mode = GetDisplayMode();
    if mode == "percent" then
        if wish.gain and wish.gain.percent and wish.gain.percent > 0 then
            display = string.format("|cff00ff00%.2f%%|r", wish.gain.percent);
        end
    elseif mode == "value" then
        if wish.gain and wish.gain.stat and wish.gain.stat > 0 then
            local metric = (wish.gain.metric and wish.gain.metric ~= "") and wish.gain.metric or "DPS";
            display = string.format("|cff00ff00%.1f %s|r", wish.gain.stat, metric);
        end
    else
        local tagInfo = wish.tag and GoWWishlists.constants.TAG_DISPLAY[wish.tag];
        display = tagInfo and string.format("|cff%s%s|r", tagInfo.color, tagInfo.tip) or "";
    end
    cellFrame.text:SetText(display);

    -- Build tooltip content
    local tipLines = {};
    if wish.tag then
        local tagInfo = GoWWishlists.constants.TAG_DISPLAY[wish.tag];
        tinsert(tipLines, "Priority: " .. (tagInfo and tagInfo.tip or wish.tag));
    end
    if wish.difficulty then
        tinsert(tipLines, "Difficulty: " .. wish.difficulty);
    end
    if wish.gain then
        local metric = (wish.gain.metric and wish.gain.metric ~= "") and wish.gain.metric or "DPS";
        if wish.gain.percent and wish.gain.percent > 0 then
            tinsert(tipLines, string.format("%.2f%% %s", wish.gain.percent, metric));
        end
        if wish.gain.stat and wish.gain.stat > 0 then
            tinsert(tipLines, string.format("%.1f %s (raw)", wish.gain.stat, metric));
        end
    end
    if wish.isCatalystItem then
        tinsert(tipLines, "|cff5ef5f5Catalyst Piece|r");
    end
    if wish.notes and wish.notes ~= "" then
        tinsert(tipLines, " ");
        tinsert(tipLines, "|cff00ff00Note:|r " .. wish.notes);
    end
    if wish.officerNotes and wish.officerNotes ~= "" then
        tinsert(tipLines, " ");
        tinsert(tipLines, "|cffff8000Officer Note:|r " .. wish.officerNotes);
    end
    cellFrame._gowTip = #tipLines > 0 and tipLines or nil;

    if not cellFrame._gowTooltip then
        cellFrame:SetScript("OnEnter", function(self)
            if not self._gowTip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Guilds of WoW", 0.1, 0.8, 0.3);
            for _, line in ipairs(self._gowTip) do
                GameTooltip:AddLine(line, 1, 1, 1, true);
            end
            GameTooltip:Show();
        end);
        cellFrame:SetScript("OnLeave", function() GameTooltip:Hide() end);
        cellFrame._gowTooltip = true;
    end
end

local function CompareByPriority(st, rowa, rowb, sortbycol)
    local a = st:GetRow(rowa);
    local b = st:GetRow(rowb);
    if not a or not b then return false end

    local itemId = GetActiveItemId();
    if not itemId then return false end

    local wishA = RCGoW:GetPlayerWish(itemId, a.name);
    local wishB = RCGoW:GetPlayerWish(itemId, b.name);

    local col = st.cols[sortbycol];
    local dir = col and (col.sort or col.defaultsort) or 1;
    local asc = (dir == 1); -- lib-st normalizes to SORT_ASC=1, SORT_DSC=2
    local mode = GetDisplayMode();

    if mode == "percent" then
        local valA = (wishA and wishA.gain and wishA.gain.percent) or 0;
        local valB = (wishB and wishB.gain and wishB.gain.percent) or 0;
        if valA ~= valB then
            if asc then return valA < valB else return valA > valB end
        end
    elseif mode == "value" then
        local valA = (wishA and wishA.gain and wishA.gain.stat) or 0;
        local valB = (wishB and wishB.gain and wishB.gain.stat) or 0;
        if valA ~= valB then
            if asc then return valA < valB else return valA > valB end
        end
    else
        local prioA = wishA and (TAG_RANK[wishA.tag] or 99) or 999;
        local prioB = wishB and (TAG_RANK[wishB.tag] or 99) or 999;
        if prioA ~= prioB then
            if asc then return prioA < prioB else return prioA > prioB end
        end
    end

    -- Tiebreak: use gain percent, following the same sort direction
    local gainA = (wishA and wishA.gain and wishA.gain.percent) or 0;
    local gainB = (wishB and wishB.gain and wishB.gain.percent) or 0;
    if gainA ~= gainB then
        if asc then return gainA < gainB else return gainA > gainB end
    end
    return false;
end

local function InsertGoWColumn()
    if not RCVotingFrame.scrollCols then return end

    -- Don't insert twice
    for _, col in ipairs(RCVotingFrame.scrollCols) do
        if col.colName == "gow" then return end
    end

    tinsert(RCVotingFrame.scrollCols, math.min(8, #RCVotingFrame.scrollCols + 1), {
        name = GOW_ICON,
        colName = "gow",
        width = 80,
        align = "CENTER",
        DoCellUpdate = RenderWishCell,
        comparesort = CompareByPriority,
        defaultsort = "asc",
    });
end

function GoWVotingColumn:OnInitialize()
    if GOW.DB and GOW.DB.profile.showRCLCWishlist == false then return end

    if not RCVotingFrame.scrollCols then
        return self:ScheduleTimer("OnInitialize", 0.5);
    end

    -- Capture existing sortnext references by colName before insertion
    local sortNextMap = {};
    for _, col in ipairs(RCVotingFrame.scrollCols) do
        if col.sortnext then
            sortNextMap[col.colName] = RCVotingFrame.scrollCols[col.sortnext].colName;
        end
    end

    InsertGoWColumn();

    -- Rebuild sortnext indices after column shift
    for i, col in ipairs(RCVotingFrame.scrollCols) do
        if sortNextMap[col.colName] then
            for j, target in ipairs(RCVotingFrame.scrollCols) do
                if target.colName == sortNextMap[col.colName] then
                    col.sortnext = j;
                    break;
                end
            end
        end
    end

    self:RegisterMessage("RCSessionChangedPre", "OnSessionChanged");
    self:ScheduleTimer("AddToggleButton", 1);
end

local function RefreshScrollTable()
    if RCVotingFrame.frame and RCVotingFrame.frame.st then
        RCVotingFrame.frame.st:Refresh();
    end
end

local function SortScrollTable()
    if RCVotingFrame.frame and RCVotingFrame.frame.st then
        RCVotingFrame.frame.st:SortData();
    end
end

function GoWVotingColumn:OnSessionChanged(_, session)
    activeSession = session or 1;
    self:ScheduleTimer(RefreshScrollTable, 0.1);
end

local DISPLAY_MODE_BUTTONS = {
    { value = "percent", label = "%",   tooltip = "Show % upgrade gain" },
    { value = "value",   label = "#",   tooltip = "Show raw stat gain" },
    { value = "tag",     label = "Tag", tooltip = "Show wishlist priority tag" },
};

local function UpdateModeButtons(buttons)
    local mode = GetDisplayMode();
    for _, btn in ipairs(buttons) do
        if btn._gowMode == mode then
            btn._gowHighlight:Show();
            btn._gowFs:SetTextColor(1, 0.84, 0);
        else
            btn._gowHighlight:Hide();
            btn._gowFs:SetTextColor(0.85, 0.85, 0.85);
        end
    end
end

function GoWVotingColumn:AddToggleButton()
    local frame = RCVotingFrame.frame;
    if not frame then
        return self:ScheduleTimer("AddToggleButton", 0.5);
    end
    if frame._gowToggleBtn then return end

    local rclcBtn = frame.disenchant or frame.filter or frame.abort;
    if not rclcBtn then
        return self:ScheduleTimer("AddToggleButton", 0.5);
    end

    local anchor = rclcBtn;
    local children = { (frame.content or frame.frame or frame):GetChildren() };
    for _, child in ipairs(children) do
        if child ~= rclcBtn and child:IsObjectType("Button") and child:GetNumPoints() > 0 then
            local point, relativeTo = child:GetPoint(1);
            if relativeTo == anchor and point == "RIGHT" then
                anchor = child;
            end
        end
    end

    local parent = frame.content or frame.frame or frame;

    local BTN_W, BORDER = 36, 8;
    local INSET = BORDER / 2;
    local BTN_H = rclcBtn:GetHeight() - BORDER;

    local groupFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    groupFrame:SetSize(BTN_W * #DISPLAY_MODE_BUTTONS + BORDER, BTN_H + BORDER);
    groupFrame:SetPoint("RIGHT", anchor, "LEFT", -4, 0);
    groupFrame:SetFrameStrata("DIALOG");
    groupFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = BORDER,
        insets = { left = INSET, right = INSET, top = INSET, bottom = INSET },
    });
    groupFrame:SetBackdropColor(0.12, 0.12, 0.12, 0.9);
    groupFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9);

    local buttons = {};
    for i, opt in ipairs(DISPLAY_MODE_BUTTONS) do
        local btn = CreateFrame("Button", nil, groupFrame);
        btn:SetSize(BTN_W, BTN_H);
        btn:SetPoint("LEFT", groupFrame, "LEFT", INSET + (i - 1) * BTN_W, 0);
        btn._gowMode = opt.value;

        local hl = btn:CreateTexture(nil, "BACKGROUND");
        hl:SetAllPoints(btn);
        hl:SetColorTexture(1, 0.84, 0, 0.15);
        hl:Hide();
        btn._gowHighlight = hl;

        local hover = btn:CreateTexture(nil, "HIGHLIGHT");
        hover:SetAllPoints(btn);
        hover:SetColorTexture(1, 1, 1, 0.08);

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        fs:SetAllPoints(btn);
        fs:SetJustifyH("CENTER");
        fs:SetText(opt.label);
        btn._gowFs = fs;

        if i > 1 then
            local div = groupFrame:CreateTexture(nil, "ARTWORK");
            div:SetSize(1, BTN_H - 6);
            div:SetPoint("LEFT", groupFrame, "LEFT", INSET + (i - 1) * BTN_W, 0);
            div:SetColorTexture(0.5, 0.5, 0.5, 0.6);
        end

        btn:SetScript("OnClick", function()
            if GOW.DB then GOW.DB.profile.rclcDisplayMode = opt.value end
            UpdateModeButtons(buttons);
            SortScrollTable();
        end);
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Guilds of WoW", 0.1, 0.8, 0.3);
            GameTooltip:AddLine(opt.tooltip, 1, 1, 1, true);
            GameTooltip:Show();
        end);
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end);

        buttons[i] = btn;
    end

    UpdateModeButtons(buttons);
    frame._gowToggleBtn = groupFrame;
end

if RCVotingFrame.frame then
    RCVotingFrame.frame:HookScript("OnShow", function()
        if GOW.DB and GOW.DB.profile.showRCLCWishlist == false then return end
        InsertGoWColumn();
        GoWVotingColumn:ScheduleTimer(RefreshScrollTable, 0.1);
    end);
end
