local RCLootCouncil = _G["RCLootCouncil"];
if not RCLootCouncil then return end

local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local RCGoW = GOW.RCGoW;

local RCVotingFrame = RCLootCouncil:GetModule("RCVotingFrame", true);
if not RCVotingFrame then return end

local GoWVotingColumn = RCGoW:NewModule("GoWVotingColumn", "AceTimer-3.0", "AceEvent-3.0");

local GOW_ICON = "|TInterface\\AddOns\\GuildsOfWoW\\icons\\guilds-of-wow-logo-flag-plain.png:20:20|t";

local activeSession = 1;

local function GetDisplayMode()
    local mode = (GOW.DB and GOW.DB.profile.rclcDisplayMode) or "percent";
    return (mode == "tag") and "percent" or mode;
end

local function GetShowTag()
    return GOW.DB == nil or GOW.DB.profile.rclcShowTag ~= false;
end

local function GetShowNote()
    return GOW.DB == nil or GOW.DB.profile.rclcShowNote ~= false;
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

    local mode = GetDisplayMode();
    if mode == "percent" and wish.gain and wish.gain.percent and wish.gain.percent > 0 then
        cellFrame.text:SetText(string.format("|cff00ff00%.2f%%|r", wish.gain.percent));
    elseif mode == "value" and wish.gain and wish.gain.stat and wish.gain.stat > 0 then
        local metric = (wish.gain.metric and wish.gain.metric ~= "") and wish.gain.metric or "DPS";
        cellFrame.text:SetText(string.format("|cff00ff00%.1f %s|r", wish.gain.stat, metric));
    else
        cellFrame.text:SetText("");
    end

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

local function RenderTagCell(rowFrame, cellFrame, data, cols, row, realRow, column, fShow, st)
    if not fShow then
        cellFrame.text:SetText("");
        cellFrame._gowTagText = nil;
        return;
    end

    local rowData = data[realRow];
    if not rowData then cellFrame.text:SetText("|cff666666—|r"); cellFrame._gowTagText = nil; return end

    if not GetShowTag() then
        cellFrame.text:SetText("|cff666666—|r");
        cellFrame._gowTagText = nil;
        return;
    end

    local itemId = GetActiveItemId();
    if not itemId then cellFrame.text:SetText("|cff666666—|r"); cellFrame._gowTagText = nil; return end

    local wish = RCGoW:GetPlayerWish(itemId, rowData.name);
    if not wish or not wish.tag then cellFrame.text:SetText("|cff666666—|r"); cellFrame._gowTagText = nil; return end

    local tagInfo = GoWWishlists.constants.TAG_DISPLAY[wish.tag];
    cellFrame.text:SetText(tagInfo and string.format("|cff%s%s|r", tagInfo.color, tagInfo.label) or wish.tag);
    cellFrame._gowTagText = tagInfo and tagInfo.tip or wish.tag;

    if not cellFrame._gowTagTooltip then
        cellFrame:SetScript("OnEnter", function(self)
            if not self._gowTagText then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Guilds of WoW", 0.1, 0.8, 0.3);
            GameTooltip:AddLine(self._gowTagText, 1, 1, 1, true);
            GameTooltip:Show();
        end);
        cellFrame:SetScript("OnLeave", function() GameTooltip:Hide() end);
        cellFrame._gowTagTooltip = true;
    end
end

local function RenderNoteCell(rowFrame, cellFrame, data, cols, row, realRow, column, fShow, st)
    if not fShow then
        cellFrame.text:SetText("");
        cellFrame._gowNoteText = nil;
        return;
    end

    local rowData = data[realRow];
    if not rowData then cellFrame.text:SetText("|cff666666—|r"); cellFrame._gowNoteText = nil; return end

    if not GetShowNote() then
        cellFrame.text:SetText("|cff666666—|r");
        cellFrame._gowNoteText = nil;
        return;
    end

    local itemId = GetActiveItemId();
    if not itemId then cellFrame.text:SetText("|cff666666—|r"); cellFrame._gowNoteText = nil; return end

    local wish = RCGoW:GetPlayerWish(itemId, rowData.name);
    if not wish or not wish.notes or wish.notes == "" then
        cellFrame.text:SetText("|cff666666—|r");
        cellFrame._gowNoteText = nil;
        return;
    end

    cellFrame.text:SetText("|TInterface\\Buttons\\UI-GuildButton-PublicNote-Up:16:16|t");
    if not cellFrame._gowNoteTooltip then
        cellFrame:SetScript("OnEnter", function(self)
            if not self._gowNoteText then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Guilds of WoW", 0.1, 0.8, 0.3);
            GameTooltip:AddLine(self._gowNoteText, 1, 1, 1, true);
            GameTooltip:Show();
        end);
        cellFrame:SetScript("OnLeave", function() GameTooltip:Hide() end);
        cellFrame._gowNoteTooltip = true;
    end
    cellFrame._gowNoteText = wish.notes;
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

    local isSimEnabled = GOW.Helper:IsSimEnabled();
    local hasGain, hasTag, hasNote = false, false, false;
    for _, col in ipairs(RCVotingFrame.scrollCols) do
        if col.colName == "gow"     then hasGain = true end
        if col.colName == "gowtag"  then hasTag  = true end
        if col.colName == "gownote" then hasNote = true end
    end
    -- Return early only when all applicable columns are already present:
    -- gain column is only applicable when sim is enabled.
    if (not isSimEnabled or hasGain) and hasTag and hasNote then return end

    local insertPos = math.min(8, #RCVotingFrame.scrollCols + 1);

    if isSimEnabled and not hasGain then
        tinsert(RCVotingFrame.scrollCols, insertPos, {
            name = GOW_ICON,
            colName = "gow",
            width = 80,
            align = "CENTER",
            DoCellUpdate = RenderWishCell,
            comparesort = CompareByPriority,
            defaultsort = "asc",
        });
    end

    if not hasTag then
        local tagPos = insertPos;
        if isSimEnabled then
            for i, col in ipairs(RCVotingFrame.scrollCols) do
                if col.colName == "gow" then tagPos = i + 1; break end
            end
        end
        tinsert(RCVotingFrame.scrollCols, tagPos, {
            name = GOW_ICON,
            colName = "gowtag",
            width = 45,
            align = "CENTER",
            DoCellUpdate = RenderTagCell,
        });
    end

    if not hasNote then
        local notePos = insertPos;
        for i, col in ipairs(RCVotingFrame.scrollCols) do
            if col.colName == "gowtag" then notePos = i + 1; break end
        end
        tinsert(RCVotingFrame.scrollCols, notePos, {
            name = GOW_ICON,
            colName = "gownote",
            width = 45,
            align = "CENTER",
            DoCellUpdate = RenderNoteCell,
        });
    end
end

function GoWVotingColumn:OnInitialize()
    if GOW.DB and GOW.DB.profile.showRCLCWishlist == false then return end

    -- Migrate old "tag" display mode (removed in tbc-wishlists) to "percent"
    if GOW.DB and GOW.DB.profile.rclcDisplayMode == "tag" then
        GOW.DB.profile.rclcDisplayMode = "percent";
    end

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
    { value = "percent", label = "%", tooltip = "Show % upgrade gain" },
    { value = "value",   label = "#", tooltip = "Show raw stat gain" },
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

local function CreateToggleButton(parent, xOffset, btnW, btnH, label, getShown, profileKey, tooltip)
    local btn = CreateFrame("Button", nil, parent);
    btn:SetSize(btnW, btnH);
    btn:SetPoint("LEFT", parent, "LEFT", xOffset, 0);

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
    fs:SetText(label);
    btn._gowFs = fs;

    local function UpdateToggle()
        local shown = getShown();
        if shown then
            btn._gowHighlight:Show();
            btn._gowFs:SetTextColor(1, 0.84, 0);
        else
            btn._gowHighlight:Hide();
            btn._gowFs:SetTextColor(0.85, 0.85, 0.85);
        end
    end

    btn:SetScript("OnClick", function()
        if GOW.DB then GOW.DB.profile[profileKey] = not getShown() end
        UpdateToggle();
        RefreshScrollTable();
    end);
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:AddLine("Guilds of WoW", 0.1, 0.8, 0.3);
        GameTooltip:AddLine(tooltip, 1, 1, 1, true);
        GameTooltip:Show();
    end);
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end);

    UpdateToggle();
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

    local isSimEnabled = GOW.Helper:IsSimEnabled();
    local numModeButtons = isSimEnabled and #DISPLAY_MODE_BUTTONS or 0;

    local groupFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    groupFrame:SetSize(BTN_W * (numModeButtons + 2) + BORDER, BTN_H + BORDER);
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
    if isSimEnabled then
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
    end

    -- Tag toggle (divider only needed when mode buttons precede it)
    if numModeButtons > 0 then
        local tagDiv = groupFrame:CreateTexture(nil, "ARTWORK");
        tagDiv:SetSize(1, BTN_H - 2);
        tagDiv:SetPoint("LEFT", groupFrame, "LEFT", INSET + numModeButtons * BTN_W, 0);
        tagDiv:SetColorTexture(0.7, 0.7, 0.7, 0.8);
    end
    CreateToggleButton(groupFrame, INSET + numModeButtons * BTN_W, BTN_W, BTN_H,
        "Tag", GetShowTag, "rclcShowTag", "Show priority tag in column");

    -- Note toggle
    local noteDiv = groupFrame:CreateTexture(nil, "ARTWORK");
    noteDiv:SetSize(1, BTN_H - 6);
    noteDiv:SetPoint("LEFT", groupFrame, "LEFT", INSET + (numModeButtons + 1) * BTN_W, 0);
    noteDiv:SetColorTexture(0.5, 0.5, 0.5, 0.6);
    CreateToggleButton(groupFrame, INSET + (numModeButtons + 1) * BTN_W, BTN_W, BTN_H,
        "Note", GetShowNote, "rclcShowNote", "Show notes in column");

    frame._gowToggleBtn = groupFrame;
end

if RCVotingFrame.frame then
    RCVotingFrame.frame:HookScript("OnShow", function()
        if GOW.DB and GOW.DB.profile.showRCLCWishlist == false then return end
        InsertGoWColumn();
        GoWVotingColumn:ScheduleTimer(RefreshScrollTable, 0.1);
    end);
end
