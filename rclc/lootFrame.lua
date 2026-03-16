local RCLootCouncil = _G["RCLootCouncil"];
if not RCLootCouncil then return end

local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local RCGoW = GOW.RCGoW;

local RCLootFrame = RCLootCouncil:GetModule("RCLootFrame", true);
if not RCLootFrame then return end

local GoWLootFrame = RCGoW:NewModule("GoWLootFrame", "AceTimer-3.0");

local GOW_ICON = "|TInterface\\AddOns\\GuildsOfWoW\\icons\\guilds-of-wow-logo-flag-plain.png:16:16|t";

local insideHook = false;
local hookedFrames = {};

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
        if not GOW.consts.ENABLE_DEBUGGING then return end
        wish = GOW.RCGoW and GOW.RCGoW.GetDebugWish();
        if not wish then return end
    end

    local label = GoWWishlists:FormatTag(wish.tag) or "Wish";
    if wish.gain and wish.gain.percent and wish.gain.percent > 0 then
        label = label .. string.format(" |cff00ff00%.1f%%|r", wish.gain.percent);
        if wish.gain.stat then
            label = label .. string.format(" |cff00ff00(%d %s)|r", wish.gain.stat, wish.gain.metric or "");
        end
    end

    entry.itemLvl:SetText(entry._gowBaseText .. "  " .. GOW_ICON .. " " .. label);
end

local function HookGetEntry(self, item)
    if insideHook then return end
    insideHook = true;

    local entry = self:GetEntry(item);
    if entry then
        if not hookedFrames[entry] then
            hookedFrames[entry] = true;
            hooksecurefunc(entry, "Update", function(e)
                OnEntryRefreshed(e);
            end);
        end
        OnEntryRefreshed(entry);
    end

    insideHook = false;
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
