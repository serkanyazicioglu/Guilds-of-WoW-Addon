local RCLootCouncil = _G["RCLootCouncil"];
if not RCLootCouncil then return end

local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local RCGoW = GOW.RCGoW;

local RCVotingFrame = RCLootCouncil:GetModule("RCVotingFrame", true);
if not RCVotingFrame then return end

local GoWVotingColumn = RCGoW:NewModule("GoWVotingColumn", "AceTimer-3.0", "AceEvent-3.0");

local GOW_ICON = "|TInterface\\AddOns\\GuildsOfWoW\\icons\\guilds-of-wow-logo-flag-plain:16:16|t";

local TAG_RANK = { BIS = 1, NEED = 2, GREED = 3, MINOR = 4, OFFSPEC = 5, TRANSMOG = 6 };

local activeSession = 1;

local function GetActiveItemId()
    local lootTable = RCLootCouncil:GetLootTable();
    if not lootTable or not lootTable[activeSession] then return nil end
    local link = lootTable[activeSession].link;
    if not link then return nil end
    return C_Item.GetItemInfoInstant(link);
end

--- DoCellUpdate callback — renders wish tag + gain% for each row.
--- Note: param "st" is the lib-st scroll table widget (not Lua's table lib).
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
        cellFrame.text:SetText("");
        cellFrame._gowTip = nil;
        return;
    end

    -- Build display string: tag + gain%
    local display = GoWWishlists:FormatTag(wish.tag) or "";
    if wish.gain and wish.gain.percent and wish.gain.percent > 0 then
        display = display .. " " .. string.format("|cff00ff00+%.1f%%|r", wish.gain.percent);
    end
    cellFrame.text:SetText(display ~= "" and display or "|cff666666?|r");

    -- Build tooltip content
    local tipLines = {};
    if wish.tag then
        local tagInfo = GoWWishlists.constants.TAG_DISPLAY[wish.tag];
        tinsert(tipLines, "Priority: " .. (tagInfo and tagInfo.tip or wish.tag));
    end
    if wish.difficulty then
        tinsert(tipLines, "Difficulty: " .. wish.difficulty);
    end
    if wish.gain and wish.gain.percent and wish.gain.percent > 0 then
        local metric = (wish.gain.metric and wish.gain.metric ~= "") and wish.gain.metric or "DPS";
        tinsert(tipLines, string.format("+%.1f%% %s", wish.gain.percent, metric));
    end
    if wish.notes and wish.notes ~= "" then
        tinsert(tipLines, " ");
        tinsert(tipLines, "Note: " .. wish.notes);
    end
    cellFrame._gowTip = #tipLines > 0 and tipLines or nil;

    -- Attach tooltip handlers once per cell frame
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

--- Sort comparator — orders by tag priority then gain%.
local function CompareByPriority(st, rowa, rowb, sortbycol)
    local a = st:GetRow(rowa);
    local b = st:GetRow(rowb);
    if not a or not b then return false end

    local itemId = GetActiveItemId();
    if not itemId then return false end

    local wishA = RCGoW:GetPlayerWish(itemId, a.name);
    local wishB = RCGoW:GetPlayerWish(itemId, b.name);

    local prioA = wishA and (TAG_RANK[wishA.tag] or 99) or 999;
    local prioB = wishB and (TAG_RANK[wishB.tag] or 99) or 999;

    if prioA ~= prioB then
        local dir = st.cols[sortbycol].sort or "asc";
        if dir:lower() == "asc" then
            return prioA < prioB;
        else
            return prioA > prioB;
        end
    end

    -- Tiebreak: higher gain wins
    local gainA = (wishA and wishA.gain and wishA.gain.percent) or 0;
    local gainB = (wishB and wishB.gain and wishB.gain.percent) or 0;
    return gainA > gainB;
end

local function InsertGoWColumn()
    if not RCVotingFrame.scrollCols then return end

    -- Don't insert twice
    for _, col in ipairs(RCVotingFrame.scrollCols) do
        if col.colName == "gow" then return end
    end

    tinsert(RCVotingFrame.scrollCols, 8, {
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
end

function GoWVotingColumn:OnSessionChanged(_, session)
    activeSession = session or 1;
end

-- Fallback: re-check on voting frame show
if RCVotingFrame.frame then
    RCVotingFrame.frame:HookScript("OnShow", InsertGoWColumn);
end
