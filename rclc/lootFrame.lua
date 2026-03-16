local RCLootCouncil = _G["RCLootCouncil"];
if not RCLootCouncil then return end

local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;

local RCLootFrame = RCLootCouncil:GetModule("RCLootFrame", true);
if not RCLootFrame then return end

local EntryManager = RCLootFrame.EntryManager;
if not EntryManager then return end

local GOW_ICON = "|TInterface\\AddOns\\GuildsOfWoW\\icons\\guilds-of-wow-logo-flag-plain:12:12|t";

local hookedEntries = {};
local insideHook = false;

local function OnEntryRefreshed(entry)
    if not entry.itemLvl then return end

    local session = entry.item and entry.item.sessions and entry.item.sessions[1];
    if not session then return end

    local lootTable = RCLootCouncil:GetLootTable();
    if not lootTable or not lootTable[session] then return end

    local link = lootTable[session].link;
    if not link then return end

    local itemId = C_Item.GetItemInfoInstant(link);
    if not itemId then return end

    local wish = GoWWishlists:FindWishlistMatch(itemId);
    if not wish then
        if not GOW.consts.ENABLE_DEBUGGING then return end
        wish = GOW.RCGoW and GOW.RCGoW.DEBUG_WISH;
        if not wish then return end
    end

    local label = GoWWishlists:FormatTag(wish.tag) or "Wish";
    if wish.gain and wish.gain.percent and wish.gain.percent > 0 then
        label = label .. string.format(" |cff00ff00+%.1f%%|r", wish.gain.percent);
    end

    local original = entry.itemLvl:GetText() or "";
    if not original:find("GoW") then
        entry.itemLvl:SetText(original .. "  " .. GOW_ICON .. " " .. label);
    end
end

hooksecurefunc(EntryManager, "GetEntry", function(self, item)
    if insideHook then return end
    insideHook = true;

    local entry = self:GetEntry(item);
    if entry and not hookedEntries[entry] then
        hookedEntries[entry] = true;
        hooksecurefunc(entry, "Update", function(e)
            OnEntryRefreshed(e);
        end);
        OnEntryRefreshed(entry);
    end

    insideHook = false;
end);
