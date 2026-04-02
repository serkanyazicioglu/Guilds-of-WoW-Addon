local GOW = GuildsOfWow or {};

local Layout = {};
GOW.Layout = Layout;

Layout.constants = {
    GOW_ACCENT_COLOR = { r = 0.1, g = 0.8, b = 0.3 },
    SUB_ACTIVE_COLOR = { r = 0.1, g = 0.8, b = 0.3, a = 0.3 },
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
    panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -sideInset, bottomInset);
    panel.scrollFrame:EnableMouseWheel(true);
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
    end);

    panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame);
    panel.scrollChild:SetSize(width - (sideInset * 2), 1);
    panel.scrollFrame:SetScrollChild(panel.scrollChild);

    return panel;
end
