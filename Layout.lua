local GOW = GuildsOfWow or {};

local Layout = {};
GOW.Layout = Layout;

Layout.constants = {
    GOW_ACCENT_COLOR = { r = 0.1, g = 0.8, b = 0.3 },
    SUB_ACTIVE_COLOR = { r = 0.1, g = 0.8, b = 0.3, a = 0.3 },
    SUB_ACTIVE_HOVER_COLOR = { r = 0.14, g = 0.9, b = 0.36, a = 0.42 },
    SUB_INACTIVE_COLOR = { r = 0.15, g = 0.15, b = 0.18, a = 0.8 },
    STANDARD_BACKDROP = {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    },
};

function Layout:ApplyBackdrop(frame, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    frame:SetBackdrop(self.constants.STANDARD_BACKDROP);
    frame:SetBackdropColor(bgR, bgG, bgB, bgA or 1);
    frame:SetBackdropBorderColor(borderR, borderG, borderB, borderA or 1);
end

function Layout:CreateSubFilterBtn(parent, label, width)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate");
    btn:SetHeight(18);
    btn:SetWidth(width);
    self:ApplyBackdrop(btn, self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a, 0.3, 0.3, 0.3, 0.4);

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    btnText:SetPoint("CENTER", btn, "CENTER", 0, 0);
    btnText:SetText(label);
    btn.btnText = btnText;

    return btn;
end

function Layout:CreateActionButton(parent, options)
    local opts = type(options) == "table" and options or {};
    local text = opts.text or "";
    local width = opts.width or 110;
    local isActive = opts.isActive ~= false;
    local onClick = opts.onClick;

    local btn = self:CreateSubFilterBtn(parent, text, width);
    btn:SetHeight(opts.height or 18);
    btn:SetWidth(width);
    self:SetButtonActive(btn, isActive);
    btn.isActionActive = isActive;

    if (not isActive) then
        btn.btnText:SetText("|cff888888" .. text .. "|r");
    end

    if (isActive) then
        btn:Enable();
    else
        btn:Disable();
    end

    btn:SetScript("OnClick", function()
        if (not isActive or not onClick) then
            return;
        end

        onClick(btn);
    end);
    btn:SetScript("OnEnter", function(selfButton)
        if (not selfButton.isActionActive) then
            return;
        end

        selfButton:SetBackdropColor(self.constants.SUB_ACTIVE_HOVER_COLOR.r, self.constants.SUB_ACTIVE_HOVER_COLOR.g, self.constants.SUB_ACTIVE_HOVER_COLOR.b, self.constants.SUB_ACTIVE_HOVER_COLOR.a);
        selfButton:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.75);
    end);
    btn:SetScript("OnLeave", function(selfButton)
        self:SetButtonActive(selfButton, selfButton.isActionActive);
    end);

    return btn;
end

function Layout:SetButtonActive(btn, isActive)
    if (isActive) then
        btn:SetBackdropColor(self.constants.SUB_ACTIVE_COLOR.r, self.constants.SUB_ACTIVE_COLOR.g, self.constants.SUB_ACTIVE_COLOR.b, self.constants.SUB_ACTIVE_COLOR.a);
        btn:SetBackdropBorderColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.5);
    else
        btn:SetBackdropColor(self.constants.SUB_INACTIVE_COLOR.r, self.constants.SUB_INACTIVE_COLOR.g, self.constants.SUB_INACTIVE_COLOR.b, self.constants.SUB_INACTIVE_COLOR.a);
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4);
    end
end

function Layout:CreateRowHighlight(frame, alpha)
    local highlight = frame:CreateTexture(nil, "BACKGROUND");
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8");
    highlight:SetAllPoints();
    highlight:SetVertexColor(1, 1, 1, alpha or 0.04);
    highlight:Hide();
    return highlight;
end

function Layout:CreateRowSeparator(parent)
    local sep = parent:CreateTexture(nil, "ARTWORK");
    sep:SetTexture("Interface\\Buttons\\WHITE8x8");
    sep:SetVertexColor(0.25, 0.25, 0.3, 0.15);
    sep:SetHeight(1);
    sep:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 6, 0);
    sep:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 0);
    return sep;
end

function Layout:CreateTextBadge(parent, options)
    local opts = type(options) == "table" and options or {};
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    local height = opts.height or 16;
    badge:SetHeight(height);
    badge:SetBackdrop(self.constants.STANDARD_BACKDROP);
    badge:SetBackdropColor(opts.bgR or 0.05, opts.bgG or 0.15, opts.bgB or 0.05, opts.bgA or 0.85);
    badge:SetBackdropBorderColor(opts.borderR or 0.1, opts.borderG or 0.8, opts.borderB or 0.3, opts.borderA or 0.6);

    local text = badge:CreateFontString(nil, "OVERLAY", opts.fontObject or "GameFontNormalSmall");
    text:SetPoint("CENTER", badge, "CENTER", 0, 0);
    text:SetJustifyH("CENTER");
    badge.text = text;

    function badge:SetLabel(label)
        local value = label or "";
        text:SetText(value);
        badge:SetWidth(math.max(opts.minWidth or 24, text:GetStringWidth() + (opts.paddingX or 12)));
    end

    badge:SetLabel(opts.text or "");
    return badge;
end

function Layout:CreateSidebarList(parent, options)
    local opts = type(options) == "table" and options or {};
    local sidebar = {
        parent = parent,
        rowHeight = opts.rowHeight or 32,
        getLabel = opts.getLabel or function(item) return item.label or item.name or "" end,
        getSubtitle = opts.getSubtitle,
        getMeta = opts.getMeta,
        onPostCreate = opts.onPostCreate,
        isSelected = opts.isSelected or function() return false end,
        isEnabled = opts.isEnabled or function(item) return item.enabled ~= false end,
        isAccent = opts.isAccent or function() return false end,
        onSelect = opts.onSelect or function() end,
    };

    function sidebar:Render(items)
        local total = #(items or {});

        for index, item in ipairs(items or {}) do
            local row = CreateFrame("Button", nil, self.parent, "BackdropTemplate");
            row:SetHeight(self.rowHeight);
            row:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, -((index - 1) * self.rowHeight));
            row:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", 0, -((index - 1) * self.rowHeight));

            row.highlight = Layout:CreateRowHighlight(row, 0.06);
            row.separator = Layout:CreateRowSeparator(row);

            local label = self.getLabel(item) or "";
            local meta = self.getMeta and self.getMeta(item) or nil;
            local isEnabled = self.isEnabled(item) == true;
            local isSelected = isEnabled and self.isSelected(item) == true;
            local isAccent = isEnabled and self.isAccent(item) == true;

            if (isSelected) then
                Layout:ApplyBackdrop(row, Layout.constants.SUB_ACTIVE_COLOR.r, Layout.constants.SUB_ACTIVE_COLOR.g, Layout.constants.SUB_ACTIVE_COLOR.b, 0.22, Layout.constants.GOW_ACCENT_COLOR.r, Layout.constants.GOW_ACCENT_COLOR.g, Layout.constants.GOW_ACCENT_COLOR.b, 0.45);
            else
                Layout:ApplyBackdrop(row, 0, 0, 0, 0, 0, 0, 0, 0);
            end

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
            local subtitle = self.getSubtitle and self.getSubtitle(item) or nil;

            if (subtitle and subtitle ~= "") then
                row.nameText:SetPoint("LEFT", row, "LEFT", 10, 6);
                row.nameText:SetPoint("RIGHT", row, "RIGHT", meta and -70 or -42, 6);
            else
                row.nameText:SetPoint("LEFT", row, "LEFT", 10, 0);
                row.nameText:SetPoint("RIGHT", row, "RIGHT", -42, 0);
            end
            row.nameText:SetJustifyH("LEFT");
            row.nameText:SetWordWrap(false);

            if (meta ~= nil and meta ~= "") then
                row.metaText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
                row.metaText:SetPoint("RIGHT", row, "RIGHT", -8, 0);
                row.metaText:SetJustifyH("RIGHT");
                row.metaText:SetText("|cffaaaaaa" .. meta .. "|r");
            end

            if (not isEnabled) then
                row.nameText:SetText("|cff666666" .. label .. "|r");
                if (row.metaText) then
                    row.metaText:SetText("|cff666666" .. tostring(meta or "") .. "|r");
                end
            elseif (isSelected) then
                row.nameText:SetText("|cffb9f3c8" .. label .. "|r");
                if (row.metaText) then
                    row.metaText:SetText("|cffb9f3c8" .. tostring(meta or "") .. "|r");
                end
            elseif (isAccent) then
                row.nameText:SetText("|cffffd100" .. label .. "|r");
                if (row.metaText) then
                    row.metaText:SetText("|cffd7d7d7" .. tostring(meta or "") .. "|r");
                end
            else
                row.nameText:SetText("|cffdddddd" .. label .. "|r");
                if (row.metaText) then
                    row.metaText:SetText("|cff9a9a9a" .. tostring(meta or "") .. "|r");
                end
            end

            if (subtitle and subtitle ~= "") then
                row.subtitleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
                row.subtitleText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2);
                row.subtitleText:SetText("|cff888888" .. subtitle .. "|r");
                row.subtitleText:SetJustifyH("LEFT");
            end

            row:SetScript("OnEnter", function(selfFrame)
                if (isEnabled and not isSelected) then
                    selfFrame.highlight:Show();
                end
            end);
            row:SetScript("OnLeave", function(selfFrame)
                selfFrame.highlight:Hide();
            end);
            row:SetScript("OnClick", function()
                if (not isEnabled) then
                    return;
                end

                self.onSelect(item, index);
            end);

            if (index == total) then
                row.separator:Hide();
            end

            if (self.onPostCreate) then
                self.onPostCreate(row, item, index);
            end
        end

        return (total * self.rowHeight);
    end

    return sidebar;
end

function Layout:ShowCopyUrlDialog(gui, url, title)
    local frameName = _G.FRAME_NAME;

    if (self.copyUrlDialog) then
        self.copyUrlDialog:ReleaseChildren();
        self.copyUrlDialog:Release();
        self.copyUrlDialog = nil;
    end

    local dialog = gui:Create("Window");
    dialog:SetTitle(title or "Copy URL");
    dialog:SetWidth(720);
    dialog:SetHeight(90);
    dialog:EnableResize(false);
    dialog:SetLayout("Flow");
    dialog.frame:SetFrameStrata("DIALOG");
    dialog.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
    dialog.previousEscapeFrame = frameName and _G[frameName] or nil;

    local urlWidget = gui:Create("SFX-Info-URL");
    urlWidget:SetLabel("URL");
    urlWidget:SetText(url or "");
    urlWidget:SetDisabled(false);
    urlWidget:SetFullWidth(true);
    dialog:AddChild(urlWidget);

    if (frameName) then
        _G[frameName] = dialog.frame;
    end

    dialog:SetCallback("OnClose", function(widget)
        widget:ReleaseChildren();
        widget:Release();
        if (self.copyUrlDialog == widget) then
            self.copyUrlDialog = nil;
        end
        if (frameName) then
            _G[frameName] = widget.previousEscapeFrame;
        end
    end);

    self.copyUrlDialog = dialog;
    return dialog;
end

function Layout:GetContainerPanel(parent, options)
    local opts = type(options) == "table" and options or {};

    local width = opts.width or 300;
    local height = opts.height or 430;
    local xOffset = opts.xOffset or 0;
    local title = opts.title or "";
    local topInset = opts.topInset or 34;
    local sideInset = opts.sideInset or 8;
    local bottomInset = opts.bottomInset or 8;
    local headerHeight = opts.headerHeight or 24;
    local scrollBarWidth = opts.scrollBarWidth or 4;
    local scrollBarGap = opts.scrollBarGap or 1;

    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    panel:SetSize(width, height);
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, 0);

    self:ApplyBackdrop(panel, 0.08, 0.08, 0.1, 0.96, 0.22, 0.22, 0.26, 0.9);

    panel.headerBg = panel:CreateTexture(nil, "ARTWORK");
    panel.headerBg:SetTexture("Interface\\Buttons\\WHITE8x8");
    panel.headerBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1);
    panel.headerBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1);
    panel.headerBg:SetHeight(26);
    panel.headerBg:SetVertexColor(0.12, 0.12, 0.15, 0.92);

    panel.headerDivider = panel:CreateTexture(nil, "ARTWORK");
    panel.headerDivider:SetTexture("Interface\\Buttons\\WHITE8x8");
    panel.headerDivider:SetPoint("TOPLEFT", panel.headerBg, "BOTTOMLEFT", 0, 0);
    panel.headerDivider:SetPoint("TOPRIGHT", panel.headerBg, "BOTTOMRIGHT", 0, 0);
    panel.headerDivider:SetHeight(1);
    panel.headerDivider:SetVertexColor(0.18, 0.18, 0.22, 0.9);

    panel.headerText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    panel.headerText:SetPoint("LEFT", panel.headerBg, "LEFT", 14, 0);
    panel.headerText:SetPoint("CENTER", panel.headerBg, "CENTER", 0, 0);
    panel.headerText:SetText(title);
    panel.headerText:SetTextColor(0.84, 0.84, 0.84);
    panel.headerText:SetJustifyH("LEFT");
    panel.headerText:SetScale(0.82);

    panel.headerBar = CreateFrame("Frame", nil, panel);
    panel.headerBar:SetPoint("TOPLEFT", panel, "TOPLEFT", sideInset, -5);
    panel.headerBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -sideInset, -5);
    panel.headerBar:SetHeight(16);

    panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel);
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", sideInset, -topInset);
    panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(sideInset + scrollBarWidth + scrollBarGap), bottomInset);
    panel.scrollFrame:EnableMouseWheel(true);
    panel.scrollFrame.contentHeight = 0;

    panel.scrollBar = CreateFrame("Slider", nil, panel, "BackdropTemplate");
    panel.scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -sideInset, -topInset);
    panel.scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -sideInset, bottomInset);
    panel.scrollBar:SetWidth(scrollBarWidth);
    panel.scrollBar:SetOrientation("VERTICAL");
    panel.scrollBar:SetMinMaxValues(0, 0);
    panel.scrollBar:SetValueStep(1);
    panel.scrollBar:SetObeyStepOnDrag(false);
    panel.scrollBar:SetValue(0);
    self:ApplyBackdrop(panel.scrollBar, 0.05, 0.05, 0.07, 0.9, 0.2, 0.2, 0.24, 0.8);

    panel.scrollBar.thumb = panel.scrollBar:CreateTexture(nil, "OVERLAY");
    panel.scrollBar.thumb:SetTexture("Interface\\Buttons\\WHITE8x8");
    panel.scrollBar.thumb:SetVertexColor(self.constants.GOW_ACCENT_COLOR.r, self.constants.GOW_ACCENT_COLOR.g, self.constants.GOW_ACCENT_COLOR.b, 0.75);
    panel.scrollBar.thumb:SetSize(math.max(2, scrollBarWidth - 2), 24);
    panel.scrollBar:SetThumbTexture(panel.scrollBar.thumb);
    panel.scrollBar:Hide();

    panel.scrollBar:SetScript("OnValueChanged", function(selfBar, value)
        panel.scrollFrame:SetVerticalScroll(value or 0);
    end);

    panel.scrollFrame:SetScript("OnVerticalScroll", function(selfFrame, offset)
        selfFrame:SetVerticalScroll(offset);
        if (panel.scrollBar and panel.scrollBar:IsShown()) then
            panel.scrollBar:SetValue(offset);
        end
    end);

    function panel:UpdateScrollBar()
        local maxScroll = math.max(0, (self.scrollFrame.contentHeight or 0) - self.scrollFrame:GetHeight());
        self.scrollBar:SetMinMaxValues(0, maxScroll);

        if (maxScroll > 0) then
            self.scrollBar:Show();
        else
            self.scrollBar:Hide();
            self.scrollFrame:SetVerticalScroll(0);
        end

        local current = self.scrollFrame:GetVerticalScroll() or 0;
        if (current > maxScroll) then
            current = maxScroll;
            self.scrollFrame:SetVerticalScroll(current);
        end
        self.scrollBar:SetValue(current);
    end

    panel.scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0;
        local maxScroll = math.max(0, (self.contentHeight or 0) - self:GetHeight());
        local nextScroll = current - (delta * 30);
        if (nextScroll < 0) then
            nextScroll = 0;
        elseif (nextScroll > maxScroll) then
            nextScroll = maxScroll;
        end
        self:SetVerticalScroll(nextScroll);
        panel:UpdateScrollBar();
    end);

    panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame);
    panel.scrollChild:SetSize(width - (sideInset * 2) - scrollBarWidth - scrollBarGap, 1);
    panel.scrollFrame:SetScrollChild(panel.scrollChild);

    return panel;
end
