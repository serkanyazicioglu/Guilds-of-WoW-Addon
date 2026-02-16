local GOW = GuildsOfWow;
local GoWWishlists = {};
GOW.Wishlists = GoWWishlists;

local ns = select(2, ...);

local WishlistIndex = {};

local DifficultyNames = {
    -- Retail raid difficulties
    [3]   = "Normal",       -- 10 Player
    [4]   = "Normal",       -- 25 Player
    [5]   = "Heroic",       -- 10 Player (Heroic)
    [6]   = "Heroic",       -- 25 Player (Heroic)
    [7]   = "LFR",          -- Legacy LFR (pre-SoO)
    [9]   = "Normal",       -- 40 Player
    [14]  = "Normal",       -- Normal (raids)
    [15]  = "Heroic",       -- Heroic (raids)
    [16]  = "Mythic",       -- Mythic (raids)
    [17]  = "LFR",          -- Looking For Raid
    [18]  = "Normal",       -- Event (raid)
    [33]  = "Timewalking",  -- Timewalking (raid)
    [151] = "LFR",          -- Looking For Raid (Timewalking)
    [220] = "Normal",       -- Story (solo raid)
    [241] = "Normal",       -- Lorewalking (raid)
    -- Classic raid difficulties
    [148] = "Normal",       -- 20 Player (ZG, AQ20)
    [175] = "Normal",       -- 10 Player (Classic)
    [176] = "Normal",       -- 25 Player (Classic)
    [193] = "Heroic",       -- 10 Player Heroic (Classic)
    [194] = "Heroic",       -- 25 Player Heroic (Classic)
};

function GoWWishlists:BuildIndex()
    WishlistIndex = {};

    if not ns.WISHLISTS or not ns.WISHLISTS.items then
        return;
    end

    for _, entry in ipairs(ns.WISHLISTS.items) do
        local key = entry.itemId;
        WishlistIndex[key] = WishlistIndex[key] or {};
        table.insert(WishlistIndex[key], entry);
    end

    local count = ns.WISHLISTS.totalItems or 0;
    GOW.Logger:Debug("Wishlist index built: " .. count .. " items indexed.");
end

local function GetCurrentCharacterInfo()
    local name = UnitName("player");
    local realm = GetNormalizedRealmName();
    return name, realm;
end

local function GetCurrentDifficultyName()
    local _, _, difficultyId = GetInstanceInfo();
    return DifficultyNames[difficultyId];
end

function GoWWishlists:FindWishlistMatch(itemId)
    local entries = WishlistIndex[itemId];
    if not entries then
        return nil;
    end

    local charName, charRealm = GetCurrentCharacterInfo();
    local difficulty = GetCurrentDifficultyName();

    for _, entry in ipairs(entries) do
        if entry.characterName == charName
            and entry.characterRealmNormalized == charRealm
            and entry.difficulty == difficulty
            and not entry.isObtained then
            return entry;
        end
    end

    return nil;
end

function GoWWishlists:FindWishlistMatchAny(itemId)
    local entries = WishlistIndex[itemId];
    if not entries then
        return nil;
    end

    local charName, charRealm = GetCurrentCharacterInfo();

    for _, entry in ipairs(entries) do
        if entry.characterName == charName
            and entry.characterRealmNormalized == charRealm
            and not entry.isObtained then
            return entry;
        end
    end

    return nil;
end

local function PrintWishlistAlert(entry, itemLink)
    local bis = entry.isBis and " |cffff8000[BiS]|r" or "";
    local prio = entry.isPriority and " |cffff0000[Priority]|r" or "";

    local msg = itemLink .. " is on your wishlist!" .. bis .. prio;

    if entry.notes and entry.notes ~= "" then
        msg = msg .. " - " .. entry.notes;
    end

    GOW.Logger:PrintSuccessMessage(msg);

    PlaySound(SOUNDKIT.RAID_WARNING);
end

local WishlistOverlays = {};

local function CreateWishlistOverlay(parentFrame)
    local overlay = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate");
    overlay:SetAllPoints(parentFrame);
    overlay:SetFrameLevel(parentFrame:GetFrameLevel() + 10);

    overlay:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    });
    overlay:SetBackdropBorderColor(0, 1, 0, 0.9);

    local glow = overlay:CreateTexture(nil, "BACKGROUND");
    glow:SetAtlas("lootroll-toast-quality-outline-legendary");
    glow:SetAllPoints(parentFrame);
    glow:SetVertexColor(0, 1, 0, 0.35);
    overlay.glow = glow;

    local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    label:SetPoint("RIGHT", parentFrame, "RIGHT", -40, 6);
    label:SetText("|cff00ff00 WISHLIST|r");
    overlay.label = label;

    local tagLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    tagLabel:SetPoint("TOP", label, "BOTTOM", 0, -1);
    overlay.tagLabel = tagLabel;

    overlay:Hide();
    return overlay;
end

local function ShowWishlistOverlay(rollFrame, match)
    if not WishlistOverlays[rollFrame] then
        WishlistOverlays[rollFrame] = CreateWishlistOverlay(rollFrame);

        rollFrame:HookScript("OnHide", function(self)
            if WishlistOverlays[self] then
                WishlistOverlays[self]:Hide();
            end
        end);
    end

    local overlay = WishlistOverlays[rollFrame];

    local tags = {};
    if match.isBis then table.insert(tags, "|cffff8000BiS|r"); end
    if match.isPriority then table.insert(tags, "|cffff0000Priority|r"); end

    if #tags > 0 then
        overlay.tagLabel:SetText(table.concat(tags, " "));
        overlay.tagLabel:Show();
    else
        overlay.tagLabel:Hide();
    end

    overlay:Show();
end

local function FindGroupLootFrame(rollID)
    -- Classic / older retail
    for i = 1, 4 do
        local frame = _G["GroupLootFrame" .. i];
        if frame and frame:IsShown() and frame.rollID == rollID then
            return frame;
        end
    end

    -- Retail
    if GroupLootContainer then
        for i = 1, GroupLootContainer:GetNumChildren() do
            local child = select(i, GroupLootContainer:GetChildren());
            if child and child:IsShown() and child.rollID == rollID then
                return child;
            end
        end
    end

    return nil;
end

local function OnStartLootRoll(rollID)
    if not rollID then
        return;
    end

    local itemLink = C_LootRoll and C_LootRoll.GetItemLink(rollID)
        or select(16, GetLootRollItemInfo(rollID));

    if not itemLink then
        return;
    end

    local itemId = tonumber(itemLink:match("item:(%d+)"));
    if not itemId then
        return;
    end

    local match = GoWWishlists:FindWishlistMatch(itemId);
    if match then
        PrintWishlistAlert(match, itemLink);

        C_Timer.After(0.05, function()
            local rollFrame = FindGroupLootFrame(rollID);
            if rollFrame then
                ShowWishlistOverlay(rollFrame, match);
            end
        end);
    end
end

local function OnTooltipSetItem(tooltip)
    if not tooltip or not tooltip.GetItem then
        return;
    end

    local _, itemLink = tooltip:GetItem();
    if not itemLink then
        return;
    end

    local itemId = tonumber(itemLink:match("item:(%d+)"));
    if not itemId then
        return;
    end

    local match = GoWWishlists:FindWishlistMatch(itemId);
    if match then
        tooltip:AddLine(" ");
        tooltip:AddLine("|cff00ff00Guilds of WoW: On your wishlist!|r");

        if match.isBis then
            tooltip:AddLine("|cffff8000  Best in Slot|r");
        end

        if match.isPriority then
            tooltip:AddLine("|cffff0000  Priority item|r");
        end

        if match.slot then
            tooltip:AddLine("|cffffd100  Slot: " .. match.slot .. "|r");
        end

        if match.characterSpec then
            tooltip:AddLine("|cffffd100  Spec: " .. match.characterSpec .. "|r");
        end

        if match.notes and match.notes ~= "" then
            tooltip:AddLine("|cffaaaaaa  " .. match.notes .. "|r");
        end

        tooltip:Show();
    end
end

function GoWWishlists:Initialize()
    if not ns.WISHLISTS then
        GOW.Logger:Debug("No wishlist data found. Skipping wishlist initialization.");
        return;
    end

    self:BuildIndex();

    local lootFrame = CreateFrame("Frame");
    lootFrame:RegisterEvent("START_LOOT_ROLL");
    lootFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "START_LOOT_ROLL" then
            OnStartLootRoll(...);
        end
    end);

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem);
    else
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem);
    end

    GOW.Logger:Debug("Wishlist module initialized.");
end

function GoWWishlists:HandleSlashCommand(arg)
    if not ns.WISHLISTS then
        GOW.Logger:PrintErrorMessage("No wishlist data found. Make sure db/wishlist.lua is synced.");
        return;
    end

    if not arg or arg == "" or arg == "help" then
        GOW.Logger:PrintMessage("Wishlist commands:");
        GOW.Logger:PrintMessage("  /gow wishlist status  - Show wishlist summary");
        GOW.Logger:PrintMessage("  /gow wishlist list    - List all items for this character");
        return;
    end

    if arg == "status" then
        local charName, charRealm = GetCurrentCharacterInfo();
        local total = ns.WISHLISTS.totalItems or 0;
        local charCount = 0;

        if ns.WISHLISTS.items then
            for _, entry in ipairs(ns.WISHLISTS.items) do
                if entry.characterName == charName and entry.characterRealmNormalized == charRealm and not entry.isObtained then
                    charCount = charCount + 1;
                end
            end
        end

        GOW.Logger:PrintMessage("Wishlist: " .. total .. " total items, " .. charCount .. " remaining for " .. charName .. "-" .. charRealm);
        return;
    end

    if arg == "list" then
        local charName, charRealm = GetCurrentCharacterInfo();
        local found = false;

        if ns.WISHLISTS.items then
            for _, entry in ipairs(ns.WISHLISTS.items) do
                if entry.characterName == charName and entry.characterRealmNormalized == charRealm and not entry.isObtained then
                    local bis = entry.isBis and " |cffff8000[BiS]|r" or "";
                    local prio = entry.isPriority and " |cffff0000[Priority]|r" or "";
                    local line = "  [" .. entry.itemId .. "] " .. (entry.itemName or "Unknown") .. " (" .. (entry.difficulty or "?") .. ", " .. (entry.slot or "?") .. ")" .. bis .. prio;
                    GOW.Logger:PrintMessage(line);
                    found = true;
                end
            end
        end

        if not found then
            GOW.Logger:PrintMessage("No wishlist items found for " .. charName .. "-" .. charRealm);
        end
        return;
    end

    local testItemId = arg:match("^test%s+(%d+)");
    if testItemId then
        testItemId = tonumber(testItemId);
        local match = self:FindWishlistMatch(testItemId) or self:FindWishlistMatchAny(testItemId);

        if match then
            local _, itemLink = C_Item.GetItemInfo(testItemId);
            itemLink = itemLink or ("[Item:" .. testItemId .. "]");
            PrintWishlistAlert(match, itemLink);
            GOW.Logger:PrintMessage("(Test) Match found: " .. (match.itemName or "Unknown") .. " / " .. (match.difficulty or "?") .. " / " .. (match.source or "?"));
        else
            GOW.Logger:PrintMessage("Item " .. testItemId .. " is not on your wishlist for this character.");
        end
        return;
    end

    local testRollItemId = arg:match("^testroll%s*(%d*)");
    if arg:match("^testroll") then
        local charName, charRealm = GetCurrentCharacterInfo();
        local itemsToShow = {};

        if testRollItemId and testRollItemId ~= "" then
            local id = tonumber(testRollItemId);
            local match = self:FindWishlistMatch(id) or self:FindWishlistMatchAny(id);
            if not match then
                GOW.Logger:PrintMessage("Item " .. id .. " is not on your wishlist for this character.");
                return;
            end
            table.insert(itemsToShow, { itemId = id, match = match });
        else
            if not ns.WISHLISTS or not ns.WISHLISTS.items then
                GOW.Logger:PrintMessage("No wishlist items found.");
                return;
            end
            for _, entry in ipairs(ns.WISHLISTS.items) do
                if entry.characterName == charName
                    and entry.characterRealmNormalized == charRealm
                    and not entry.isObtained then
                    table.insert(itemsToShow, { itemId = entry.itemId, match = entry });
                end
            end
            if #itemsToShow == 0 then
                GOW.Logger:PrintMessage("No wishlist items found for " .. charName .. "-" .. charRealm);
                return;
            end
        end

        local pending = #itemsToShow;
        local needsRetry = false;

        for _, item in ipairs(itemsToShow) do
            local itemName = C_Item.GetItemInfo(item.itemId);
            if not itemName then
                C_Item.RequestLoadItemDataByID(item.itemId);
                needsRetry = true;
            end
        end

        if needsRetry then
            GOW.Logger:PrintMessage("Loading item data... run the command again in a moment.");
            return;
        end

        self:ShowMockLootRolls(itemsToShow);
        GOW.Logger:PrintMessage("(TestRoll) Showing " .. #itemsToShow .. " mock loot roll frame(s).");
        return;
    end

    GOW.Logger:PrintErrorMessage("Unknown wishlist command. Type /gow wishlist help");
end


-- //TODO - remove
local MOCK_FRAME_HEIGHT = 54;
local MOCK_FRAME_WIDTH = 340;
local MOCK_FRAME_SPACING = 4;
local MOCK_FRAME_START_Y = -180;

local mockRollFrames = {};

local function CreateMockRollFrame(index)
    local frame = CreateFrame("Frame", "GoWMockLootRollFrame" .. index, UIParent, "BackdropTemplate");
    frame:SetSize(MOCK_FRAME_WIDTH, MOCK_FRAME_HEIGHT);
    frame:SetFrameStrata("DIALOG");
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", frame.StartMoving);
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing);

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    });
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.95);

    local icon = frame:CreateTexture(nil, "ARTWORK");
    icon:SetSize(36, 36);
    icon:SetPoint("LEFT", 8, 0);
    frame.icon = icon;

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    nameText:SetPoint("LEFT", icon, "RIGHT", 8, 6);
    nameText:SetWidth(200);
    nameText:SetJustifyH("LEFT");
    frame.nameText = nameText;

    local subText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2);
    subText:SetWidth(200);
    subText:SetJustifyH("LEFT");
    subText:SetTextColor(0.7, 0.7, 0.7);
    frame.subText = subText;

    local mockLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    mockLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4);
    mockLabel:SetText("|cff888888(Right-click to dismiss)|r");

    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            self:Hide();
        end
    end);

    frame:Hide();
    return frame;
end

local function GetMockRollFrame(index)
    if not mockRollFrames[index] then
        mockRollFrames[index] = CreateMockRollFrame(index);
    end
    return mockRollFrames[index];
end

local function HideAllMockRollFrames()
    for _, frame in ipairs(mockRollFrames) do
        frame:Hide();
    end
end

function GoWWishlists:ShowMockLootRolls(items)
    HideAllMockRollFrames();

    for i, item in ipairs(items) do
        local frame = GetMockRollFrame(i);
        local yOffset = MOCK_FRAME_START_Y - ((i - 1) * (MOCK_FRAME_HEIGHT + MOCK_FRAME_SPACING));

        frame:ClearAllPoints();
        frame:SetPoint("TOP", UIParent, "TOP", 0, yOffset);

        local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(item.itemId);
        frame.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark");
        frame.nameText:SetText(itemLink or itemName or ("Item:" .. item.itemId));
        frame.subText:SetText(
            (item.match.slot or "") .. "  |  " ..
            (item.match.source or "") ..
            (item.match.sourceBoss and (" - " .. item.match.sourceBoss) or "")
        );

        frame.rollID = -(1000 + i);
        frame:Show();

        ShowWishlistOverlay(frame, item.match);
    end

    C_Timer.After(15, function()
        HideAllMockRollFrames();
    end);
end
