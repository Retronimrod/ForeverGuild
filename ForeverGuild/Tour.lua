local _, addon = ...
-- Introduction tour in the style of the Blizzard tutorial windows. One opaque information box
-- sits next to the explained element, a gold frame marks that element and the rest of the
-- explained window is dimmed slightly. A small window manager remembers which ForeverGuild
-- windows were open, shows only what the current station needs and restores the previous
-- state at the end. The tour never saves, creates orders or changes guild data. Progress is
-- saved account-wide in ForeverGuildSettings.tour by stable station ID.
local L = addon.L
local tour = {}
addon.tour = tour

local BOX_WIDTH, SIDE, VERTICAL, GAP, MIN_HEIGHT = 480, 24, 20, 16, 300
local welcome, box, highlight, dim
local ctx, steps, current
local active, generation, pausedByCombat = false, 0, false
local saved                   -- window state at tour start
local opened                  -- window opened for the current station

-- Previous versions saved a step number; map it to the station of that version.
local LEGACY_ORDER = { "welcome", "character", "roster", "professions", "equipment", "orders", "board", "bank", "groups",
    "admin", "notify", "settings" }

local function state()
    ForeverGuildSettings = ForeverGuildSettings or {}
    ForeverGuildSettings.tour = ForeverGuildSettings.tour or {}
    local data = ForeverGuildSettings.tour
    if data.step and not data.stepId then
        data.stepId = LEGACY_ORDER[data.step] or "welcome"
    end
    return data
end

local function save(id, done)
    local data = state()
    data.stepId, data.step, data.done, data.seen = id, nil, done or nil, true
end

local function icons() return addon.moduleIcons or {} end

-- Stations in display order with their concrete target frames. Stations with `tab` are shown
-- in the main window; stations with `open` show only that separate window.
local function buildSteps()
    local window = ctx.window()
    local list = {
        { id = "welcome", welcome = true },
        { id = "character", title = "TOUR_T_CHARACTER", text = "TOUR_CHARACTER", icon = icons().roster, keep = "setup",
            open = function() return ctx.openSetup(saved and saved.setup) end,
            target = function(_, frame) return frame and frame.choiceArea end },
        { id = "roster", title = "TOUR_T_ROSTER", text = "TOUR_ROSTER", tab = "roster", icon = icons().roster,
            target = function(w) return w.rosterMembers end },
        { id = "professions", title = "TOUR_T_PROFESSIONS", text = "TOUR_PROFESSIONS", tab = "professions",
            icon = icons().professions, target = function(w) return w.finder and w.finder.filterPanel end },
        { id = "equipment", title = "TOUR_T_EQUIPMENT", text = "TOUR_EQUIPMENT", tab = "professions",
            icon = icons().professions, target = function(w) return w.finder and w.finder.tree end },
        { id = "orders", title = "TOUR_T_ORDERS", text = "TOUR_ORDERS", tab = "orders", icon = icons().orders,
            target = function(w) return w.orderCards end },
        { id = "board", title = "TOUR_T_BOARD", text = "TOUR_BOARD", tab = "board", icon = icons().board,
            prepare = function(w) if w.showBoardSection then w.showBoardSection("orders") end end,
            target = function(w) return w.boardOrders and w.boardOrders.listPanel end },
        { id = "groups", title = "TOUR_T_GROUPS", text = "TOUR_GROUPS", tab = "board", icon = icons().groups,
            prepare = function(w) if w.showBoardSection then w.showBoardSection("G") end end,
            target = function(w) return w.groupList end },
    }
    if window and window.bank then
        list[#list + 1] = { id = "bank", title = "TOUR_T_BANK", text = "TOUR_BANK", tab = "bank", icon = icons().bank,
            target = function(w) return w.bankFocus end }
    end
    if window and window.admin and ctx.officer() then
        list[#list + 1] = { id = "admin", title = "TOUR_T_ADMIN", text = "TOUR_ADMIN", tab = "admin", icon = icons().admin,
            target = function(w) return w.admin end }
    end
    list[#list + 1] = { id = "notify", title = "TOUR_T_NOTIFY", text = "TOUR_NOTIFY", icon = icons().notify, keep = "notes",
        open = function() return ctx.openNotes() end, target = function(_, frame) return frame end }
    list[#list + 1] = { id = "settings", title = "TOUR_T_SETTINGS", text = "TOUR_SETTINGS", icon = icons().settings,
        keep = "settings", open = function() return ctx.openSettings() end,
        target = function(_, frame) return frame and frame.nav end }
    list[#list + 1] = { id = "finish", title = "TOUR_T_FINISH", text = "TOUR_FINISH", tab = "professions", icon = ctx.icon }
    return list
end

local function indexOf(id)
    for index, entry in ipairs(steps or {}) do
        if entry.id == id then return index end
    end
    return 1
end

-- Window state ------------------------------------------------------------------------------------
local function closeMenus()
    if GameTooltip then GameTooltip:Hide() end
    if CloseDropDownMenus then pcall(CloseDropDownMenus) end
    local manager = Menu and Menu.GetManager and Menu.GetManager()
    if manager and manager.CloseMenus then pcall(manager.CloseMenus, manager) end
end

local function shown(frame) return frame ~= nil and frame.IsShown ~= nil and frame:IsShown() end

local function rememberWindows()
    saved = { main = ctx.mainShown(), tab = ctx.currentTab(), setup = shown(ctx.setupWindow()),
        settings = shown(ctx.settingsWindow()), notes = shown(ctx.notesWindow()), others = {} }
    for _, frame in pairs(ctx.otherWindows()) do
        if shown(frame) then saved.others[#saved.others + 1] = frame end
    end
end

-- Hides every ForeverGuild window the current station does not need.
local function onlyShow(keep)
    for _, frame in pairs(ctx.otherWindows()) do
        if shown(frame) then frame:Hide() end
    end
    if keep ~= "setup" and shown(ctx.setupWindow()) then ctx.setupWindow():Hide() end
    if keep ~= "settings" and shown(ctx.settingsWindow()) then ctx.settingsWindow():Hide() end
    if keep ~= "notes" and shown(ctx.notesWindow()) then ctx.notesWindow():Hide() end
    if keep ~= "main" and ctx.mainShown() then ctx.hideMain() end
end

local function restoreWindows()
    if not saved then return end
    local previous = saved
    saved = nil
    onlyShow(nil)
    ctx.restoreMain(previous.main, previous.tab)
    if previous.setup and ctx.setupWindow() then ctx.setupWindow():Show() end
    if previous.settings then ctx.openSettings() end
    if previous.notes then ctx.openNotes() end
    for _, frame in ipairs(previous.others) do frame:Show() end
end

-- Frames -----------------------------------------------------------------------------------------
local function sizedFont(label, template, size)
    local path, _, flags = template:GetFont()
    if path then label:SetFont(path, size, flags) end
end

-- Swallows clicks and the mouse wheel on the whole visible area (also empty space and text).
local function blockInput(frame)
    frame:EnableMouse(true)
    if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
    if frame.SetHitRectInsets then frame:SetHitRectInsets(0, 0, 0, 0) end
    frame:SetScript("OnMouseDown", function() end)
    frame:SetScript("OnMouseUp", function() end)
    frame:SetScript("OnMouseWheel", function() end)
end

-- Opaque window: solid dark brown base, a very faint emblem in a corner, the dialog border
-- on top and a soft shadow just outside. Alpha is not inherited from any parent.
local function opaqueFrame(name)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    if frame.SetIgnoreParentAlpha then frame:SetIgnoreParentAlpha(true) end
    frame:SetAlpha(1)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetPoint("TOPLEFT", -7, 7)
    shadow:SetPoint("BOTTOMRIGHT", 9, -9)
    shadow:SetColorTexture(0, 0, 0, .6)
    local base = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    base:SetPoint("TOPLEFT", 4, -4)
    base:SetPoint("BOTTOMRIGHT", -4, 4)
    base:SetColorTexture(.078, .054, .035, 1)
    local art = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    art:SetPoint("BOTTOMRIGHT", -8, 8)
    art:SetSize(150, 150)
    art:SetTexture("Interface\\AddOns\\ForeverGuild\\Art\\ForeverGuildEmblem")
    art:SetAlpha(.045)
    frame:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 28,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    blockInput(frame)
    return frame
end

local function tourButton(parent, label, action)
    local control = ctx.button(parent, label, 10, 0, 0, action)
    control:SetHeight(28)
    control.Fit = function(self, caption, minimum)
        self:SetText(caption)
        self:SetWidth(math.max(minimum or 120, math.ceil(addon.marketUI.textWidth(caption, GameFontNormal)) + 36))
    end
    control:Fit(label)
    return control
end

local show

local function buildWelcome()
    welcome = opaqueFrame("ForeverGuildWelcome")
    welcome:SetSize(560, 420)
    welcome:SetPoint("CENTER", 0, 40)
    welcome:SetFrameLevel(1500)
    table.insert(UISpecialFrames, "ForeverGuildWelcome")
    local logo = welcome:CreateTexture(nil, "ARTWORK")
    logo:SetSize(96, 96)
    logo:SetPoint("TOP", 0, -30)
    logo:SetTexture(ctx.icon)
    local title = welcome:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", logo, "BOTTOM", 0, -12)
    sizedFont(title, GameFontNormalLarge, 21)
    title:SetText(L["Welcome to ForeverGuild!"])
    welcome.body = welcome:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    welcome.body:SetPoint("TOP", title, "BOTTOM", 0, -16)
    welcome.body:SetWidth(560 - 2 * 40)
    welcome.body:SetSpacing(4)
    sizedFont(welcome.body, GameFontHighlight, 14)
    welcome.body:SetTextColor(.96, .93, .86)
    welcome.body:SetText(L["TOUR_WELCOME"])
    welcome.step = welcome:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    welcome.step:SetPoint("BOTTOM", 0, VERTICAL + 4)
    welcome.step:SetTextColor(.95, .84, .58)
    local start = tourButton(welcome, L["Start tour"], function() show(2) end)
    start:ClearAllPoints()
    start:SetPoint("BOTTOMRIGHT", welcome, "BOTTOM", -8, 56)
    local skip = tourButton(welcome, L["Skip"], function()
        save("welcome", true)
        tour.stop()
        print("ForeverGuild · " .. L["You can start the tour any time under Settings, Introduction tour."])
    end)
    skip:ClearAllPoints()
    skip:SetPoint("BOTTOMLEFT", welcome, "BOTTOM", 8, 56)
end

local function buildBox()
    box = opaqueFrame("ForeverGuildTourStep")
    box:SetWidth(BOX_WIDTH)
    box:SetFrameLevel(1500)
    -- Header: logo, caption, close button (= continue later) and a rule.
    local logo = box:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("TOPLEFT", SIDE, -VERTICAL)
    logo:SetTexture(ctx.icon)
    local caption = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    caption:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    caption:SetText(L["ForeverGuild – Introduction"])
    local ok, close = pcall(CreateFrame, "Button", nil, box, "UIPanelCloseButton")
    if ok and close then
        close:SetPoint("TOPRIGHT", -6, -6)
        close:SetScript("OnClick", function() tour.later() end)
    end
    local rule = box:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", SIDE, -VERTICAL - 32)
    rule:SetPoint("TOPRIGHT", -SIDE, -VERTICAL - 32)
    rule:SetHeight(1)
    rule:SetColorTexture(.62, .45, .22, .9)
    -- Module icon and title.
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetSize(34, 34)
    box.icon:SetPoint("TOPLEFT", SIDE, -VERTICAL - 46)
    box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    box.title:SetPoint("LEFT", box.icon, "RIGHT", 12, 0)
    box.title:SetPoint("RIGHT", -SIDE, 0)
    box.title:SetJustifyH("LEFT")
    sizedFont(box.title, GameFontNormalLarge, 19)
    -- Text in a scroll area, so small screens get a scrollbar instead of tiny fonts.
    box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    box.textChild = CreateFrame("Frame", nil, box.scroll)
    box.textChild:SetSize(BOX_WIDTH - 2 * SIDE, 10)
    box.scroll:SetScrollChild(box.textChild)
    box.body = box.textChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.body:SetPoint("TOPLEFT")
    box.body:SetWidth(BOX_WIDTH - 2 * SIDE)
    box.body:SetJustifyH("LEFT")
    box.body:SetSpacing(4)
    sizedFont(box.body, GameFontHighlight, 14)
    box.body:SetTextColor(.96, .93, .86)
    -- Progress.
    box.progressLabel = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.progressLabel:SetJustifyH("LEFT")
    box.progressLabel:SetTextColor(.95, .84, .58)
    box.bar = CreateFrame("StatusBar", nil, box, "BackdropTemplate")
    box.bar:SetHeight(16)
    box.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    box.bar:SetStatusBarColor(.86, .62, .20)
    local barBack = box.bar:CreateTexture(nil, "BACKGROUND")
    barBack:SetAllPoints()
    barBack:SetColorTexture(.16, .11, .07, 1)
    box.bar:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    box.bar:SetBackdropBorderColor(.62, .45, .22, 1)
    -- Two separate button rows of equal height.
    box.back = tourButton(box, L["Back"], function() show(current - 1) end)
    box.nextButton = tourButton(box, L["Next"], function() show(current + 1) end)
    box.later = tourButton(box, L["Continue later"], function() tour.later() end)
    box.finish = tourButton(box, L["End tour"], function() tour.finish() end)
end

local function layoutBox(step, total, entry)
    box.icon:SetTexture(entry.icon or ctx.icon)
    box.title:SetText(L[entry.title])
    box.body:SetText(L[entry.text])
    local textHeight = math.ceil(box.body:GetStringHeight()) + 4
    box.textChild:SetHeight(textHeight)
    -- Fixed parts: header (52), title row (34 + 14), progress (18 + 6 + 16 + 16), buttons (28 + 8 + 28).
    local fixed = VERTICAL + 52 + 34 + 14 + 18 + 6 + 16 + 16 + 28 + 8 + 28 + VERTICAL
    local maxText = math.max(80, math.floor(UIParent:GetHeight() * .8) - fixed)
    local visibleText = math.min(textHeight, maxText)
    local y = VERTICAL + 52 + 34 + 14
    box.scroll:ClearAllPoints()
    box.scroll:SetPoint("TOPLEFT", SIDE, -y)
    box.scroll:SetSize(BOX_WIDTH - 2 * SIDE, visibleText)
    box.scroll:SetVerticalScroll(0)
    if box.scroll.ScrollBar then box.scroll.ScrollBar:SetShown(textHeight > visibleText) end
    y = y + visibleText + 14
    box.progressLabel:ClearAllPoints()
    box.progressLabel:SetPoint("TOPLEFT", SIDE, -y)
    box.progressLabel:SetText(L["Step %d of %d"]:format(step, total))
    y = y + 18 + 6
    box.bar:ClearAllPoints()
    box.bar:SetPoint("TOPLEFT", SIDE, -y)
    box.bar:SetPoint("TOPRIGHT", -SIDE, -y)
    box.bar:SetMinMaxValues(0, total)
    box.bar:SetValue(step)
    y = y + 16 + 16
    local last = step == total
    box.back:SetEnabled(step > 2)
    box.back:Fit(L["Back"])
    box.back:ClearAllPoints()
    box.back:SetPoint("TOPLEFT", SIDE, -y)
    box.nextButton:Fit(last and L["Complete introduction"] or L["Next"])
    box.nextButton:ClearAllPoints()
    box.nextButton:SetPoint("TOPRIGHT", -SIDE, -y)
    y = y + 28 + 8
    box.later:Fit(L["Continue later"])
    box.later:ClearAllPoints()
    box.later:SetPoint("TOPLEFT", SIDE, -y)
    box.later:SetShown(not last)
    box.finish:Fit(L["End tour"])
    box.finish:ClearAllPoints()
    box.finish:SetPoint("TOPRIGHT", -SIDE, -y)
    y = y + 28 + VERTICAL
    box:SetHeight(math.max(MIN_HEIGHT, math.ceil(y)))
end

-- Geometry ----------------------------------------------------------------------------------------
local function rectOf(frame)
    if not frame or not frame.GetLeft or not frame:IsVisible() then return nil end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not left or not right or not top or not bottom or right - left < 2 or top - bottom < 2 then return nil end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return { left = left * scale, right = right * scale, top = top * scale, bottom = bottom * scale }
end

local function overlaps(a, b)
    return a.left < b.right and a.right > b.left and a.top > b.bottom and a.bottom < b.top
end

-- Areas the box keeps clear of: the target, the quest tracker and the side navigation.
local function obstacles(target)
    local list = { target }
    for _, name in ipairs({ "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }) do
        local rect = rectOf(_G[name])
        if rect then list[#list + 1] = rect end
    end
    local window = ctx.window()
    for _, key in ipairs({ "rosterTab", "ordersTab", "boardTab", "bankTab", "helpTab", "adminTab", "professionTab", "logTab" }) do
        local rect = window and rectOf(window[key])
        if rect then list[#list + 1] = rect end
    end
    return list
end

local function placeBox(target, container)
    local width, height = box:GetWidth(), box:GetHeight()
    local screen = { left = 8, right = UIParent:GetWidth() - 8, top = UIParent:GetHeight() - 8, bottom = 8 }
    local blocked = obstacles(target)
    local function clamp(value, low, high) return math.max(low, math.min(value, high)) end
    local function free(spot)
        local rect = { left = spot.x, right = spot.x + width, top = spot.top, bottom = spot.top - height }
        if rect.left < screen.left or rect.right > screen.right or rect.top > screen.top or rect.bottom < screen.bottom then
            return false
        end
        for _, obstacle in ipairs(blocked) do
            if overlaps(rect, obstacle) then return false end
        end
        return true
    end
    local function try(bounds)
        if not bounds then return nil end
        local vertical = clamp(target.top, bounds.bottom + height, bounds.top)
        local horizontal = clamp((target.left + target.right - width) / 2, bounds.left, bounds.right - width)
        local candidates = {
            { x = target.right + GAP, top = vertical }, { x = target.left - GAP - width, top = vertical },
            { x = horizontal, top = target.bottom - GAP }, { x = horizontal, top = target.top + GAP + height },
        }
        for _, spot in ipairs(candidates) do
            if spot.x >= bounds.left and spot.x + width <= bounds.right and spot.top <= bounds.top
                and spot.top - height >= bounds.bottom and free(spot) then
                return spot
            end
        end
    end
    local inner = container and { left = container.left + 12, right = container.right - 12,
        top = container.top - 30, bottom = container.bottom + 12 }
    local spot = try(inner) or try(screen)
    if not spot then
        -- Last resort: inside the explained window, on the side farther from the target.
        local bounds = inner or screen
        local x = (target.left - bounds.left > bounds.right - target.right) and bounds.left or bounds.right - width
        spot = { x = clamp(x, screen.left, screen.right - width),
            top = clamp(bounds.bottom + height, screen.bottom + height, screen.top) }
    end
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot.x, spot.top)
end

-- Light dimming of the explained window around the target; it takes no mouse input.
local function placeDim(target, containerFrame)
    if not dim then
        dim = CreateFrame("Frame", nil, UIParent)
        dim:EnableMouse(false)
        dim.parts = {}
        for index = 1, 4 do
            local part = dim:CreateTexture(nil, "OVERLAY")
            part:SetColorTexture(0, 0, 0, .4)
            dim.parts[index] = part
        end
    end
    local container = rectOf(containerFrame)
    if not container or not target or target.left < container.left - 1 or target.right > container.right + 1
        or target.top > container.top + 1 or target.bottom < container.bottom - 1 then
        dim:Hide()
        return
    end
    dim:SetParent(containerFrame)
    dim:SetScale(UIParent:GetEffectiveScale() / containerFrame:GetEffectiveScale())
    dim:SetFrameStrata(containerFrame:GetFrameStrata())
    dim:SetFrameLevel(math.min(1400, containerFrame:GetFrameLevel() + 400))
    dim:ClearAllPoints()
    dim:SetAllPoints(containerFrame)
    local function put(part, left, right, top, bottom)
        if right - left < 1 or top - bottom < 1 then part:Hide() return end
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        part:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right, bottom)
        part:Show()
    end
    local pad = 6
    put(dim.parts[1], container.left, container.right, container.top, target.top + pad)
    put(dim.parts[2], container.left, container.right, target.bottom - pad, container.bottom)
    put(dim.parts[3], container.left, target.left - pad, target.top + pad, target.bottom - pad)
    put(dim.parts[4], target.right + pad, container.right, target.top + pad, target.bottom - pad)
    dim:Show()
end

local function placeHighlight(targetFrame)
    if not highlight then
        highlight = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        highlight:EnableMouse(false)
        highlight:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
        highlight:SetBackdropBorderColor(1, .82, .2, 1)
    end
    highlight:SetFrameStrata("FULLSCREEN_DIALOG")
    highlight:SetFrameLevel(1490)
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -5, 5)
    highlight:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", 5, -5)
    highlight:Show()
end

local function hideOverlay()
    if welcome then welcome:Hide() end
    if box then box:Hide() end
    if highlight then highlight:Hide() end
    if dim then dim:Hide() end
end

-- Measures the target once it is laid out. `token` drops callbacks of older stations.
local function position(entry, token, attempt)
    if token ~= generation or not active or not box or not box:IsShown() then return end
    local window = ctx.window()
    local targetFrame = entry.target and entry.target(window, opened)
    local target = rectOf(targetFrame)
    if entry.target and not target and (attempt or 0) < 6 then
        C_Timer.After(.1, function() position(entry, token, (attempt or 0) + 1) end)
        return
    end
    local containerFrame = opened or window
    if target then
        placeHighlight(targetFrame)
        placeDim(target, containerFrame)
        placeBox(target, rectOf(containerFrame))
    else
        -- No target (or it does not exist): explain without a misleading highlight.
        if highlight then highlight:Hide() end
        if dim then dim:Hide() end
        box:ClearAllPoints()
        if rectOf(containerFrame) then box:SetPoint("CENTER", containerFrame, "CENTER") else box:SetPoint("CENTER") end
    end
end

-- Re-measures when an explained window moves, changes size or is shown again.
local hooked = {}
local function follow(frame)
    if not frame or hooked[frame] then return end
    hooked[frame] = true
    local function again()
        if active and steps and steps[current] and box and box:IsShown() then
            local token = generation
            C_Timer.After(0, function() position(steps[current], token) end)
        end
    end
    frame:HookScript("OnSizeChanged", again)
    if frame:GetScript("OnDragStop") then frame:HookScript("OnDragStop", again) end
    frame:HookScript("OnShow", again)
end

show = function(step)
    if ctx.inCombat() then
        tour.pauseForCombat()
        return
    end
    if not active then
        active = true
        rememberWindows()
    end
    generation = generation + 1
    local token = generation
    steps = buildSteps()
    step = math.max(1, math.min(step or 1, #steps))
    current = step
    local entry = steps[step]
    save(entry.id)
    hideOverlay()
    closeMenus()
    opened = nil
    if entry.welcome then
        onlyShow(nil)
        if not welcome then buildWelcome() end
        welcome.step:SetText(L["Step %d of %d"]:format(1, #steps))
        welcome:Show()
        welcome:Raise()
        return
    end
    if entry.open then
        onlyShow(entry.keep)
        opened = entry.open()
        follow(opened)
    else
        onlyShow("main")
        ctx.openTab(entry.tab)
        local window = ctx.window()
        if entry.prepare and window then entry.prepare(window) end
        follow(window)
    end
    if not box then buildBox() end
    layoutBox(step, #steps, entry)
    box:ClearAllPoints()
    box:SetPoint("CENTER")
    box:Show()
    box:Raise()
    -- Wait for the page to be laid out before measuring and highlighting.
    C_Timer.After(0, function() position(entry, token) end)
end

-- Removes every tour element and restores the windows of the tour start.
function tour.stop()
    active = false
    generation = generation + 1
    hideOverlay()
    closeMenus()
    opened = nil
    restoreWindows()
end

function tour.later(silent)
    if steps and steps[current] then save(steps[current].id) end
    tour.stop()
    if not silent then print("ForeverGuild · " .. L["Continue the tour under Settings, Introduction tour."]) end
end

function tour.finish()
    save("finish", true)
    tour.stop()
end

function tour.start(context, step)
    ctx = context
    if ctx.inCombat() then
        print("ForeverGuild · " .. L["The tour continues after combat."])
        pausedByCombat = true
        return
    end
    steps = buildSteps()
    local data = state()
    if not step then step = data.done and 1 or indexOf(data.stepId or "welcome") end
    show(step)
end

function tour.resumable()
    local data = ForeverGuildSettings and ForeverGuildSettings.tour
    if not data or data.done then return false end
    local id = data.stepId or (data.step and LEGACY_ORDER[data.step])
    return id ~= nil and id ~= "welcome"
end

-- Combat: ForeverGuild already closed its windows; only remove the overlay and keep the
-- station. Windows are not reopened during combat.
function tour.pauseForCombat()
    if active then
        pausedByCombat = true
        if steps and steps[current] then save(steps[current].id) end
        active = false
        generation = generation + 1
        hideOverlay()
        opened, saved = nil, nil
    end
end

-- First start: new accounts get the welcome window once; existing users only a hint.
function tour.maybeWelcome(context, existingUser)
    ctx = context
    local data = state()
    if data.seen or data.hinted then return end
    if existingUser then
        data.hinted = true
        print("ForeverGuild · " .. L["New: an introduction tour shows all features. Start it under Settings, Introduction tour."])
        return
    end
    if ctx.inCombat() then return end
    steps = buildSteps()
    show(1)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pausedByCombat and ctx then
            pausedByCombat = false
            C_Timer.After(1, function() if not ctx.inCombat() then tour.start(ctx) end end)
        end
    elseif active and steps and steps[current] and box and box:IsShown() then
        local token = generation
        C_Timer.After(0, function() position(steps[current], token) end)
    end
end)
