local RCLootCouncil = _G["RCLootCouncil"];
if not RCLootCouncil then return end

local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local RCGoW = GOW.RCGoW;

local RCLootFrame = RCLootCouncil:GetModule("RCLootFrame", true);
if not RCLootFrame then return end

local GoWLootFrame = RCGoW:NewModule("GoWLootFrame", "AceTimer-3.0");

local GOW_ICON = "|TInterface\\AddOns\\GuildsOfWoW\\icons\\guilds-of-wow-logo-flag-plain.png:16:16|t";

local function OnEntryRefreshed(entry)
    if GOW.DB and GOW.DB.profile.showRCLCWishlist == false then return end
    if not entry.itemLvl then return end

    local currentText = entry.itemLvl:GetText() or "";
    if currentText:find(GOW_ICON, 1, true) then return end

    entry._gowBaseText = currentText;

    local lootTable = RCLootCouncil:GetLootTable();
    if not lootTable then return end

    local sessions = entry.item and entry.item.sessions;
    if not sessions then return end

    local itemId;
    for _, session in ipairs(sessions) do
        if lootTable[session] and lootTable[session].link then
            itemId = C_Item.GetItemInfoInstant(lootTable[session].link);
            if itemId then break end
        end
    end
    if not itemId then return end

    local wish = GoWWishlists:FindWishlistMatch(itemId);
    if not wish then
        if GOW.consts.ENABLE_DEBUGGING then
            wish = GOW.RCGoW and GOW.RCGoW.GetDebugWish();
        end
        if not wish then
            entry.itemLvl:SetText(entry._gowBaseText .. "  " .. GOW_ICON .. " |cff666666—|r");
            return;
        end
    end

    local tagInfo = wish.tag and GoWWishlists.constants.TAG_DISPLAY[wish.tag];
    local label = tagInfo and string.format("|cff%s%s|r", tagInfo.color, tagInfo.tip) or "Wish";
    if wish.gain and wish.gain.percent and wish.gain.percent > 0 then
        label = label .. string.format(" |cff00ff00%.1f%%|r", wish.gain.percent);
        if wish.gain.stat then
            label = label .. string.format(" |cff00ff00(%.1f %s)|r", wish.gain.stat, wish.gain.metric or "");
        end
    end

    if wish.isCatalystItem then
        label = label .. " |cff5ef5f5(Cata)|r";
    end

    entry.itemLvl:SetText(entry._gowBaseText .. "  " .. GOW_ICON .. " " .. label);

    -- Add tooltip overlay for GoW wish info
    if not entry._gowTipFrame then
        local tipFrame = CreateFrame("Frame", nil, entry);
        tipFrame:SetPoint("TOPLEFT", entry.itemLvl, "TOPLEFT", 0, 0);
        tipFrame:SetPoint("BOTTOMRIGHT", entry.itemLvl, "BOTTOMRIGHT", 0, 0);
        tipFrame:EnableMouse(true);
        tipFrame:SetScript("OnEnter", function(self)
            if not self._gowTip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine("Guilds of WoW", 0.1, 0.8, 0.3);
            for _, line in ipairs(self._gowTip) do
                GameTooltip:AddLine(line, 1, 1, 1, true);
            end
            GameTooltip:Show();
        end);
        tipFrame:SetScript("OnLeave", function() GameTooltip:Hide() end);
        entry._gowTipFrame = tipFrame;
    end

    local tipLines = {};
    if tagInfo then table.insert(tipLines, "Priority: " .. tagInfo.tip) end
    if wish.difficulty then table.insert(tipLines, "Difficulty: " .. wish.difficulty) end
    if wish.gain then
        local metric = (wish.gain.metric and wish.gain.metric ~= "") and wish.gain.metric or "DPS";
        if wish.gain.percent and wish.gain.percent > 0 then
            table.insert(tipLines, string.format("%.1f%% %s", wish.gain.percent, metric));
        end
        if wish.gain.stat and wish.gain.stat > 0 then
            table.insert(tipLines, string.format("%.1f %s (raw)", wish.gain.stat, metric));
        end
    end
    if wish.isCatalystItem then
        table.insert(tipLines, "|cff5ef5f5Catalyst Piece|r");
    end
    if wish.notes and wish.notes ~= "" then
        table.insert(tipLines, " ");
        table.insert(tipLines, "Note: " .. wish.notes);
    end
    entry._gowTipFrame._gowTip = #tipLines > 0 and tipLines or nil;
end

local prototypeHooked = false;

local function HookGetEntry(entryManager, item)
    if not item then return end

    local entry = entryManager.entries and entryManager.entries[item];
    if not entry then return end

    if not prototypeHooked then
        local mt = getmetatable(entry);
        local proto = mt and mt.__index;
        if proto and type(proto.Update) == "function" then
            hooksecurefunc(proto, "Update", function(e)
                OnEntryRefreshed(e);
            end);
            prototypeHooked = true;
        end
    end

    OnEntryRefreshed(entry);
end

function GoWLootFrame:OnEnable()
    self:HookEntryManager();
end

function GoWLootFrame:HookEntryManager()
    local EntryManager = RCLootFrame.EntryManager;
    if not EntryManager then
        return self:ScheduleTimer("HookEntryManager", 0.5);
    end

    hooksecurefunc(EntryManager, "GetEntry", HookGetEntry);
end
