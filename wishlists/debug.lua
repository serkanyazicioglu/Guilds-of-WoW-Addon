local GOW = GuildsOfWow;
local GoWWishlists = GOW.Wishlists;
local ns = select(2, ...);

-- /gow wltest -- exercises the wishlist matchers against the loaded export.
-- Deliberately NOT gated behind ENABLE_DEBUGGING: that flag makes
-- BuildWishlistIndex take the first personal and guild entry regardless of who
-- is logged in, which would invalidate every identity check below.

local PASS = "|cff00ff00PASS|r";
local FAIL = "|cffff0000FAIL|r";
local SKIP = "|cff888888SKIP|r";

-- ok == nil records a skip.
local function Check(run, ok, label, detail)
    local tag;
    if ok == nil then
        tag = SKIP;
        run.skipped = run.skipped + 1;
    elseif ok then
        tag = PASS;
        run.passed = run.passed + 1;
    else
        tag = FAIL;
        run.failed = run.failed + 1;
    end
    print("  " .. tag .. "  " .. label .. (detail and ("  |cff888888" .. detail .. "|r") or ""));
end

local function CountBy(items)
    local withBonus, withIlvl = 0, 0;
    for _, entry in ipairs(items) do
        if entry.bonusIds and #entry.bonusIds > 0 then withBonus = withBonus + 1 end
        if entry.itemLevel then withIlvl = withIlvl + 1 end
    end
    return withBonus, withIlvl;
end

local function FirstTestable(items)
    for _, entry in ipairs(items) do
        local variantIds = GoWWishlists:GetVariantBonusIds(entry);
        if not entry.isObtained and variantIds and #variantIds > 0 then
            return entry;
        end
    end
end

function GoWWishlists:RunWishlistTests()
    local run = { passed = 0, failed = 0, skipped = 0 };
    GOW.Logger:PrintMessage("[wltest] wishlist matcher checks");

    local items = self.state.allItems or {};
    local withBonus, withIlvl = CountBy(items);
    Check(run, #items > 0, "export: personal items loaded",
        string.format("%d items, bonusIds %d, itemLevel %d", #items, withBonus, withIlvl));

    if #items == 0 then
        GOW.Logger:PrintErrorMessage("[wltest] no personal wishlist data -- nothing to test");
        return;
    end

    -- Identity ------------------------------------------------------------
    local info = self.state.currentCharInfo;
    Check(run, self:HasPersonalWishlistEntry(), "character: export matches this character",
        info and (info.name .. "-" .. info.realmNormalized) or "?");

    local exportRealm;
    for _, charEntry in ipairs(ns.WISHLISTS and ns.WISHLISTS.personalWishlists or {}) do
        if info and charEntry.name and charEntry.name:lower() == info.nameLower then
            exportRealm = charEntry.realmNameNormalized;
        end
    end
    if exportRealm then
        Check(run, exportRealm == GetNormalizedRealmName(), "realm: export normalization matches client",
            exportRealm .. " vs " .. GetNormalizedRealmName());
    else
        Check(run, nil, "realm: no personal entry for this character");
    end

    local playerGuild = GetGuildInfo("player");
    local guildData = self.state.guildWishlistData;
    if not playerGuild then
        Check(run, nil, "guild: player is not in a guild");
    else
        Check(run, guildData ~= nil and guildData.guild == playerGuild, "guild: resolved entry matches player guild",
            (guildData and guildData.guild or "nil") .. " vs " .. playerGuild);
    end

    -- Matchers ------------------------------------------------------------
    -- A wrong-variant link must carry an id the export recognises; an unrecognised id
    -- deliberately falls back to difficulty matching instead of rejecting.
    local known = self:GetKnownVariantBonusIds();
    local function ForeignVariantId(itemId)
        local own = {};
        for _, candidate in ipairs(self.state.wishlistIndex[itemId] or {}) do
            for _, id in ipairs(self:GetVariantBonusIds(candidate) or {}) do own[id] = true end
        end
        for id in pairs(known) do
            if not own[id] then return id end
        end
    end

    local tested, linkOk, exactOk, negOk, findOk, findNegOk, fallbackOk = 0, 0, 0, 0, 0, 0, 0;
    for _, entry in ipairs(items) do
        local variantIds = self:GetVariantBonusIds(entry);
        if not entry.isObtained and variantIds and #variantIds > 0 then
            tested = tested + 1;

            local link = self:BuildItemLink(entry.itemId, variantIds);
            local bonusIdSet = link and self:GetBonusIdsFromLink(link);
            if bonusIdSet then linkOk = linkOk + 1 end
            if bonusIdSet and self:EntryMatchesBonusIds(entry, bonusIdSet) then exactOk = exactOk + 1 end
            if not self:EntryMatchesBonusIds(entry, { [99999] = true }) then negOk = negOk + 1 end

            if self:FindWishlistMatch(entry.itemId, link) then findOk = findOk + 1 end

            local foreignId = ForeignVariantId(entry.itemId);
            if foreignId and not self:FindWishlistMatch(entry.itemId, self:BuildItemLink(entry.itemId, { foreignId })) then
                findNegOk = findNegOk + 1;
            end

            -- An Encounter Journal style link must behave exactly like having no link.
            local ejLink = self:BuildItemLink(entry.itemId, { 3524 });
            if self:FindWishlistMatch(entry.itemId, ejLink) == self:FindWishlistMatch(entry.itemId, nil) then
                fallbackOk = fallbackOk + 1;
            end
        end
    end

    if tested == 0 then
        Check(run, nil, "matchers: no unobtained items carry bonusIds");
    else
        local total = "/" .. tested;
        Check(run, linkOk == tested, "link: BuildItemLink round-trips through GetBonusIdsFromLink", linkOk .. total);
        Check(run, exactOk == tested, "bonus ids: exact variant matches", exactOk .. total);
        Check(run, negOk == tested, "bonus ids: foreign id rejected", negOk .. total);
        Check(run, findOk == tested, "FindWishlistMatch: exact link hits", findOk .. total);
        Check(run, findNegOk == tested, "FindWishlistMatch: wrong-variant link misses", findNegOk .. total);
        Check(run, fallbackOk == tested, "FindWishlistMatch: unrecognised link falls back to difficulty", fallbackOk .. total);
    end

    -- Difficulties the client can never name (+10+, Voidforged, ...) -------
    local raidDiffs = {};
    for _, name in pairs(self.constants.DIFFICULTY_NAMES) do raidDiffs[name] = true end

    local odd, oddHit = 0, 0;
    for _, entry in ipairs(items) do
        local variantIds = self:GetVariantBonusIds(entry);
        if not entry.isObtained and entry.difficulty and not raidDiffs[entry.difficulty]
            and variantIds and #variantIds > 0 then
            odd = odd + 1;
            if self:FindWishlistMatch(entry.itemId, self:BuildItemLink(entry.itemId, variantIds)) then
                oddHit = oddHit + 1;
            end
        end
    end
    if odd == 0 then
        Check(run, nil, "non-raid difficulties: none in this wishlist");
    else
        Check(run, oddHit == odd, "non-raid difficulties are reachable", oddHit .. "/" .. odd);
    end

    -- MarkWishlistObtained, with the mutation rolled back ------------------
    local target = FirstTestable(items);
    if not target then
        Check(run, nil, "MarkWishlistObtained: no candidate");
    else
        local restore = {};
        for _, entry in ipairs(items) do
            if entry.itemId == target.itemId then restore[entry] = entry.isObtained end
        end

        local marked = self:MarkWishlistObtained(target.itemId, nil,
            self:BuildItemLink(target.itemId, self:GetVariantBonusIds(target)));

        local flipped = false;
        for entry, previous in pairs(restore) do
            if entry.isObtained and not previous then flipped = true end
            entry.isObtained = previous;
        end

        Check(run, marked and flipped, "MarkWishlistObtained: exact variant marks (rolled back)",
            target.itemId .. " " .. tostring(target.difficulty));
    end

    -- Guild path ----------------------------------------------------------
    local RCGoW = GOW.RCGoW;
    if not RCGoW then
        Check(run, nil, "GetPlayerWish: RCLootCouncil not loaded");
    elseif not guildData or not guildData.wishlists then
        Check(run, nil, "GetPlayerWish: no guild wishlist data");
    else
        local tried, hits = 0, 0;
        for _, charEntry in ipairs(guildData.wishlists) do
            for _, item in ipairs(charEntry.wishlist) do
                local variantIds = self:GetVariantBonusIds(item);
                if not item.isObtained and variantIds and #variantIds > 0 then
                    tried = tried + 1;
                    local fullName = charEntry.name .. "-" .. (charEntry.realmNameNormalized or "");
                    local link = self:BuildItemLink(item.itemId, variantIds);
                    if RCGoW:GetPlayerWish(item.itemId, fullName, link) then hits = hits + 1 end
                    break;
                end
            end
        end
        if tried == 0 then
            Check(run, nil, "GetPlayerWish: no roster items carry bonusIds");
        else
            Check(run, hits == tried, "GetPlayerWish: roster members resolve their own wishes", hits .. "/" .. tried);
        end
    end

    local summary = string.format("[wltest] %d passed, %d failed, %d skipped", run.passed, run.failed, run.skipped);
    if run.failed > 0 then
        GOW.Logger:PrintErrorMessage(summary);
    else
        GOW.Logger:PrintSuccessMessage(summary);
    end
end
