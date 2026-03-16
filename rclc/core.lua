local RCLootCouncil = _G["RCLootCouncil"];
if not RCLootCouncil then return end

local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;

local RCGoW = RCLootCouncil:NewModule("RCGoW", "AceTimer-3.0", "AceEvent-3.0");
GOW.RCGoW = RCGoW;

local DEBUG_WISH = {
    tag = "BIS",
    difficulty = "Mythic",
    notes = "Debug: fake wishlist entry",
    gain = { percent = 12.5, stat = 350, metric = "DPS" },
};
RCGoW.DEBUG_WISH = DEBUG_WISH;

function RCGoW:OnInitialize()
    GOW.Logger:Debug("RCLootCouncil integration active.");
end

local function SplitFullName(fullName)
    if not fullName then return nil, nil end
    local name, realm = fullName:match("^([^%-]+)%-?(.*)$");
    return name, (realm and realm ~= "") and realm or nil;
end

function RCGoW:GetPlayerWish(itemId, playerFullName)
    if GOW.DB and GOW.DB.profile.showRCLCWishlist == false then return nil end

    local data = GoWWishlists.state.guildWishlistData;
    if not data or not data.wishlists then return nil end

    local playerName, playerRealm = SplitFullName(playerFullName);
    if not playerName then return nil end

    local matches = {};

    for _, charEntry in ipairs(data.wishlists) do
        local nameMatch = charEntry.name == playerName;
        local realmMatch = not playerRealm
            or (charEntry.realmName and charEntry.realmName:gsub("%s", "") == playerRealm);
        if nameMatch and realmMatch then
            for _, item in ipairs(charEntry.wishlist) do
                if item.itemId == itemId and not item.isObtained then
                    table.insert(matches, item);
                end
            end
            break;
        end
    end

    if #matches == 0 then
        if GOW.consts.ENABLE_DEBUGGING then return DEBUG_WISH end
        return nil;
    end

    local currentDiff = GoWWishlists:GetCurrentDifficultyName();
    for _, m in ipairs(matches) do
        if m.difficulty == currentDiff then return m end
    end

    return nil;
end
