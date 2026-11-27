local _, addon = ...
-- Central settings window: grouped categories, search across labels, descriptions and
-- categories, scope badges and info tooltips. Pages and entries are registered by the
-- modules that own the settings (ForeverGuild.lua, MarketUI.lua); values are read and
-- written through the entries' own get/set, so existing saved settings stay untouched.
local L = addon.L
local S = { pages = {}, entries = {}, byPage = {} }
addon.settingsUI = S

S.groups = {
    { id = "general", title = "General" }, { id = "guild", title = "Guild features" },
    { id = "notify", title = "Notifications" }, { id = "system", title = "Data & system" },
    { id = "help", title = "Help & information" },
}
local SCOPES = { character = "Character", account = "Account", guild = "Guild", master = "Guild master only" }

function S.page(id, group, title)
    if S.byPage[id] then return end
    S.pages[#S.pages + 1] = { id = id, group = group, title = title }
    S.byPage[id] = {}
end

-- entry: page, kind (check/number/choice/button/text/custom), label, desc, info, scope,
-- get, set, default, options (choice), min/max (number), action (button), build (custom),
-- enabled (function), refresh (custom)
function S.add(entry)
    S.entries[#S.entries + 1] = entry
    local list = S.byPage[entry.page]
    list[#list + 1] = entry
end

local function text(parent, font, wrap)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(wrap and true or false)
    return label
end

local frame
local ctx

local function enabledOf(entry)
    return not entry.enabled or entry.enabled()
end

local function buildEntry(container, entry)
    local holder = CreateFrame("Frame", nil, container)
    entry.frame = holder
    local glow = holder:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints()
    glow:SetColorTexture(1, .82, .25, .16)
    glow:Hide()
    holder.glow = glow
    local x = 8
    local control
    if entry.kind == "check" then
        control = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
        control:SetSize(26, 26)
        control:SetPoint("TOPLEFT", 4, -2)
        control:SetScript("OnClick", function(self) entry.set(self:GetChecked() and true or false) end)
        x = 34
    end
    local title = text(holder, "GameFontNormal")
    title:SetPoint("TOPLEFT", x, -7)
    title:SetText(entry.label or "")
    local badge = text(holder, "GameFontDisableSmall")
    badge:SetPoint("LEFT", title, "RIGHT", 8, 0)
    badge:SetText(entry.scope and ("(" .. L[SCOPES[entry.scope]] .. ")") or "")
    if entry.info then
        local info = CreateFrame("Button", nil, holder)
        info:SetSize(16, 16)
        info:SetPoint("LEFT", badge, "RIGHT", 6, 0)
        local mark = text(info, "GameFontNormal")
        mark:SetPoint("CENTER")
        mark:SetText("?")
        mark:SetTextColor(1, .82, 0)
        info:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(entry.label)
            GameTooltip:AddLine(entry.info, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        info:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local y = -26
    if entry.kind == "number" then
        control = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
        control:SetSize(52, 20)
        control:SetPoint("TOPLEFT", x + 6, y)
        control:SetAutoFocus(false)
        control:SetNumeric(true)
        control:SetMaxLetters(4)
        control:SetScript("OnEscapePressed", control.ClearFocus)
        control:SetScript("OnTextChanged", function(self, user)
            local value = tonumber(self:GetText())
            if user and value and value >= (entry.min or 0) and value <= (entry.max or 9999) then entry.set(value) end
        end)
        y = y - 24
    elseif entry.kind == "choice" then
        control = addon.recipeFinder.widgets.dropdown(holder, entry.width or 220, entry.options,
            entry.get, function(value) entry.set(value); if entry.after then entry.after(value) end end)
        control:SetPoint("TOPLEFT", x, y)
        y = y - 30
    elseif entry.kind == "button" then
        local caption = entry.buttonLabel or entry.label
        control = ctx.button(holder, caption, 120, x, y, function() entry.action(entry) end)
        control:SetWidth(math.max(120, math.ceil(addon.marketUI.textWidth(caption)) + 30))
        title:SetShown(entry.buttonLabel ~= nil)
        if not entry.buttonLabel then y = -4; control:ClearAllPoints(); control:SetPoint("TOPLEFT", x, -4) end
        y = y - 28
    elseif entry.kind == "custom" then
        control = CreateFrame("Frame", nil, holder)
        control:SetPoint("TOPLEFT", x, y)
        control:SetPoint("RIGHT", -8, 0)
        entry.build(control, entry)
    end
    local desc = text(holder, "GameFontHighlightSmall", true)
    desc:SetPoint("TOPLEFT", x, y - 2)
    desc:SetPoint("RIGHT", -10, 0)
    desc:SetText(entry.desc or "")
    desc:SetTextColor(.85, .78, .66)
    entry.control, entry.descLabel, entry.offset = control, desc, y
    entry.layout = function(width)
        holder:SetWidth(width)
        local height = -entry.offset + 4
        if entry.kind == "custom" then
            local customHeight = entry.height and entry.height() or 40
            control:SetHeight(customHeight)
            desc:ClearAllPoints()
            desc:SetPoint("TOPLEFT", x, entry.offset - customHeight - 4)
            desc:SetPoint("RIGHT", -10, 0)
            height = height + customHeight + 4
        end
        if (entry.desc or "") ~= "" then height = height + math.ceil(desc:GetStringHeight()) + 4 end
        holder:SetHeight(height + 8)
        return height + 8
    end
    entry.sync = function()
        local enabled = enabledOf(entry)
        if entry.kind == "check" then
            control:SetChecked(entry.get() and true or false)
            control:SetEnabled(enabled)
        elseif entry.kind == "number" then
            if not control:HasFocus() then control:SetText(tostring(entry.get() or "")) end
            control:SetEnabled(enabled)
        elseif entry.kind == "choice" then
            control.Sync()
            if control.SetEnabled then control:SetEnabled(enabled) end
        elseif entry.kind == "button" then
            control:SetEnabled(enabled)
        elseif entry.refresh then
            entry.refresh(entry)
        end
        title:SetTextColor(enabled and 1 or .55, enabled and .82 or .52, enabled and 0 or .45)
    end
    return holder
end

local function showPage(id, highlight)
    if frame.searchBox:GetText() ~= "" then
        frame.switching = true
        frame.searchBox:SetText("")
        frame.switching = nil
    end
    frame.current = id
    for _, page in ipairs(S.pages) do
        if page.button then page.button:SetEnabled(page.id ~= id) end
        if page.content then page.content:Hide() end
    end
    frame.results:Hide()
    local page
    for _, candidate in ipairs(S.pages) do if candidate.id == id then page = candidate end end
    if not page then return end
    if not page.content then
        page.content = CreateFrame("Frame", nil, frame.scrollChild)
        page.content:SetPoint("TOPLEFT")
        page.content:SetPoint("RIGHT")
        page.heading = text(page.content, "GameFontNormalLarge")
        page.heading:SetPoint("TOPLEFT", 8, -6)
        page.heading:SetText(L[page.title])
        for _, entry in ipairs(S.byPage[id]) do buildEntry(page.content, entry) end
    end
    page.content:Show()
    local width = math.max(200, frame.scroll:GetWidth() - 4)
    local y = -34
    for _, entry in ipairs(S.byPage[id]) do
        entry.sync()
        entry.frame:ClearAllPoints()
        entry.frame:SetPoint("TOPLEFT", 0, y)
        y = y - entry.layout(width) - 4
    end
    page.content:SetSize(width, -y + 10)
    frame.scrollChild:SetSize(width, -y + 10)
    frame.scroll:SetVerticalScroll(0)
    frame.pageTitle = L[page.title]
    if highlight and highlight.frame then
        -- Short, non-blinking highlight of the found setting.
        highlight.frame.glow:Show()
        local offset = select(5, highlight.frame:GetPoint(1)) or 0
        frame.scroll:SetVerticalScroll(math.max(0, math.min(frame.scroll:GetVerticalScrollRange() or 0, -offset - 40)))
        C_Timer.After(2.5, function() highlight.frame.glow:Hide() end)
    end
end
S.showPage = showPage

local function runSearch(query)
    query = query:lower():match("^%s*(.-)%s*$")
    if query == "" then
        frame.results:Hide()
        if frame.current then showPage(frame.current) end
        return
    end
    for _, page in ipairs(S.pages) do if page.content then page.content:Hide() end end
    local hits = {}
    for _, entry in ipairs(S.entries) do
        local pageTitle
        for _, page in ipairs(S.pages) do if page.id == entry.page then pageTitle = L[page.title] end end
        local haystack = ((entry.label or "") .. "\n" .. (entry.desc or "") .. "\n" .. (entry.info or "") .. "\n"
            .. (pageTitle or "") .. "\n" .. (entry.keywords or "")):lower()
        local ok = true
        for word in query:gmatch("%S+") do
            if not haystack:find(word, 1, true) then ok = false end
        end
        if ok then hits[#hits + 1] = { entry = entry, page = pageTitle } end
    end
    frame.results:Show()
    for _, row in ipairs(frame.resultRows) do row:Hide() end
    for index, hit in ipairs(hits) do
        local row = frame.resultRows[index]
        if not row then
            row = CreateFrame("Button", nil, frame.results)
            row:SetHeight(36)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.title = text(row, "GameFontNormal")
            row.title:SetPoint("TOPLEFT", 8, -4)
            row.title:SetPoint("RIGHT", -8, 0)
            row.sub = text(row, "GameFontHighlightSmall")
            row.sub:SetPoint("TOPLEFT", 8, -20)
            row.sub:SetPoint("RIGHT", -8, 0)
            row:SetScript("OnClick", function(self) showPage(self.hit.entry.page, self.hit.entry) end)
            frame.resultRows[index] = row
        end
        row.hit = hit
        row.title:SetText(hit.entry.label or hit.entry.buttonLabel or "")
        row.sub:SetText((hit.page or "") .. (hit.entry.desc and ("  ·  " .. hit.entry.desc) or ""))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -6 - (index - 1) * 38)
        row:SetPoint("RIGHT")
        row:Show()
    end
    frame.noResults:SetShown(#hits == 0)
    local width = math.max(200, frame.scroll:GetWidth() - 4)
    frame.results:SetSize(width, math.max(40, #hits * 38 + 12))
    frame.scrollChild:SetSize(width, math.max(40, #hits * 38 + 12))
    frame.scroll:SetVerticalScroll(0)
end

function S.open(context, pageId)
    ctx = context
    if ctx.inCombat() then return end
    if frame then
        frame:Show()
        showPage(pageId or frame.current or S.pages[1].id)
        return
    end
    frame = CreateFrame("Frame", "ForeverGuildSettingsWindow", UIParent, "PortraitFrameTemplate")
    local width, height = UIParent:GetSize()
    frame:SetSize(math.min(900, width - 60), math.min(620, height - 60))
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetTitle(L["ForeverGuild · Settings"])
    frame:SetPortraitToAsset(ctx.icon)
    table.insert(UISpecialFrames, "ForeverGuildSettingsWindow")

    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", 74, -38)
    search:SetPoint("TOPRIGHT", -20, -38)
    search:SetHeight(22)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    local placeholder = text(search, "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 4, 0)
    placeholder:SetText(L["Search settings…"])
    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        if not frame.switching then runSearch(self:GetText()) end
    end)
    frame.searchBox = search

    local nav = ctx.panel(frame)
    frame.nav = nav
    nav:SetPoint("TOPLEFT", 12, -66)
    nav:SetPoint("BOTTOMLEFT", 12, 44)
    nav:SetWidth(200)
    local navScroll = CreateFrame("ScrollFrame", nil, nav, "UIPanelScrollFrameTemplate")
    navScroll:SetPoint("TOPLEFT", 6, -6)
    navScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local navChild = CreateFrame("Frame", nil, navScroll)
    navChild:SetSize(166, 10)
    navScroll:SetScrollChild(navChild)
    local y = -2
    for _, group in ipairs(S.groups) do
        local any = false
        for _, page in ipairs(S.pages) do if page.group == group.id then any = true end end
        if any then
            local heading = text(navChild, "GameFontNormalSmall")
            heading:SetPoint("TOPLEFT", 4, y - 4)
            heading:SetText(L[group.title]:upper())
            heading:SetTextColor(.75, .62, .40)
            y = y - 22
            for _, page in ipairs(S.pages) do
                if page.group == group.id then
                    local control = CreateFrame("Button", nil, navChild)
                    control:SetSize(160, 20)
                    control:SetPoint("TOPLEFT", 6, y)
                    control:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    control:SetNormalFontObject(GameFontHighlightSmall)
                    control:SetDisabledFontObject(GameFontNormal)
                    control:SetText(L[page.title])
                    control:GetFontString():ClearAllPoints()
                    control:GetFontString():SetPoint("LEFT", 10, 0)
                    control:SetScript("OnClick", function() showPage(page.id) end)
                    page.button = control
                    y = y - 21
                end
            end
            y = y - 6
        end
    end
    navChild:SetHeight(-y + 4)

    local content = ctx.contrastPanel(frame)
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", -12, 44)
    local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 10)
    scroll:SetScrollChild(child)
    frame.scroll, frame.scrollChild = scroll, child
    frame.results = CreateFrame("Frame", nil, child)
    frame.results:SetPoint("TOPLEFT")
    frame.results:Hide()
    frame.resultRows = {}
    frame.noResults = text(frame.results, "GameFontDisable")
    frame.noResults:SetPoint("TOPLEFT", 10, -10)
    frame.noResults:SetText(L["No setting matches the search."])

    local version = text(frame, "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", 20, 18)
    version:SetText("ForeverGuild v" .. ctx.version)
    local close = ctx.button(frame, L["Close"], 110, 0, 0, function() frame:Hide() end)
    close:ClearAllPoints()
    close:SetPoint("BOTTOMRIGHT", -16, 12)
    local defaults = ctx.button(frame, L["Defaults"], math.ceil(addon.marketUI.textWidth(L["Defaults"])) + 34, 0, 0, function()
        local page = frame.current
        local affected = {}
        for _, entry in ipairs(S.byPage[page] or {}) do
            if entry.default ~= nil and entry.set and enabledOf(entry) then affected[#affected + 1] = entry end
        end
        if #affected == 0 then return end
        local names = {}
        for _, entry in ipairs(affected) do names[#names + 1] = "· " .. entry.label end
        addon.marketUI.prompt(ctx.market, { title = L["Restore defaults for this page?"], kind = "confirm",
            text = table.concat(names, "\n"), confirm = function()
                for _, entry in ipairs(affected) do entry.set(entry.default) end
                showPage(page)
            end })
    end)
    defaults:ClearAllPoints()
    defaults:SetPoint("BOTTOM", 0, 12)
    frame:SetScript("OnShow", function() if frame.current then showPage(frame.current) end end)
    showPage(pageId or S.pages[1].id)
end

function S.toggle(context, pageId)
    if frame and frame:IsShown() and not pageId then frame:Hide() return end
    S.open(context, pageId)
end
