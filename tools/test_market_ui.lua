-- Smoke test for MarketUI.lua with a permissive mock of the WoW frame API.
-- It builds the dialog, order management, board view, notifications and settings and
-- runs every context action once, so nil errors and typos surface without a client.
-- This does not replace an in-game test (layout, fonts and real events are not checked).
-- Usage: lua tools/test_market_ui.lua   (from the repository root)
local failures = 0
local function check(name, condition)
    io.write((condition and "ok   " or "FAIL ") .. name .. "\n")
    if not condition then failures = failures + 1 end
end

local timers = {}
local function object(kind)
    local state = { text = "", shown = true, width = 420, height = 300, scripts = {}, checked = false, kind = kind }
    local proxy = {}
    local methods = {
        SetText = function(_, value) state.text = value end,
        GetText = function() return state.text end,
        GetWidth = function() return state.width end,
        GetHeight = function() return state.height end,
        GetSize = function() return state.width, state.height end,
        SetWidth = function(_, value) state.width = value end,
        SetHeight = function(_, value) state.height = value end,
        SetSize = function(_, w, h) state.width, state.height = w, h end,
        GetStringWidth = function() return #tostring(state.text) * 6 end,
        GetStringHeight = function() return 14 end,
        SetScript = function(_, name, fn) state.scripts[name] = fn end,
        HookScript = function(_, name, fn) state.scripts[name] = fn end,
        GetScript = function(_, name) return state.scripts[name] end,
        Show = function() state.shown = true end,
        Hide = function() state.shown = false end,
        SetShown = function(_, value) state.shown = value and true or false end,
        IsShown = function() return state.shown end,
        IsVisible = function() return state.shown end,
        IsMouseOver = function() return false end,
        -- Screen geometry for the tour placement (UIParent units, scale 1).
        GetLeft = function() return state.left or 100 end,
        GetRight = function() return (state.left or 100) + state.width end,
        GetTop = function() return state.top or 800 end,
        GetBottom = function() return (state.top or 800) - state.height end,
        GetEffectiveScale = function() return 1 end,
        GetFrameLevel = function() return state.level or 5 end,
        SetFrameLevel = function(_, value) state.level = value end,
        GetFrameStrata = function() return "DIALOG" end,
        SetPoint = function(_, point, relative, relPoint, x, y)
            state.points = state.points or {}
            state.points[#state.points + 1] = { point, relative, relPoint, x, y }
            if point == "TOPLEFT" and relative == UIParent and relPoint == "BOTTOMLEFT" then state.left, state.top = x, y end
        end,
        ClearAllPoints = function() state.points = {} end,
        GetPoint = function(_, index)
            local found = state.points and state.points[index or 1]
            if found then return found[1], found[2], found[3], found[4], found[5] end
        end,
        GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
        GetChecked = function() return state.checked end,
        SetChecked = function(_, value) state.checked = value end,
        GetVerticalScroll = function() return 0 end,
        CreateTexture = function() return object("Texture") end,
        CreateFontString = function() return object("FontString") end,
        GetFontString = function() return object("FontString") end,
        GetParent = function() return state.parent end,
        SetupMenu = function(_, fn) state.menu = fn end,
        Click = function(self) if state.scripts.OnClick then state.scripts.OnClick(self) end end,
    }
    setmetatable(proxy, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if key == "_state" then return state end
        -- Like real widgets: methods are capitalized, other fields are nil until set.
        if type(key) == "string" and key:match("^%u") then return function() return nil end end
        return nil
    end })
    return proxy
end
_G.CreateFrame = function(kind, name, parent)
    local frame = object(kind)
    frame._state.parent = parent
    if name then _G[name] = frame end
    if kind == "ScrollFrame" then frame.ScrollBar = object("Slider") end
    return frame
end
_G.UIParent = object("Frame")
_G.GameTooltip = object("GameTooltip")
_G.UISpecialFrames = {}
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
_G.GetLocale = function() return "deDE" end
_G.GetServerTime = function() return 1700000000 end
_G.InCombatLockdown = function() return false end
_G.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0, g = 1, b = 0 }, [3] = { r = 0, g = .4, b = 1 } }
for quality = 1, 5 do _G["ITEM_QUALITY" .. quality .. "_DESC"] = "Q" .. quality end
for _, font in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontDisable", "GameFontNormalSmall",
    "GameFontHighlightSmall", "GameFontDisableSmall", "GameFontNormalLarge" }) do _G[font] = object("Font") end
_G.C_Item = { GetItemInfo = function() return nil end, GetItemIconByID = function() return 134400 end }
_G.date = os.date
_G.time = os.time
_G.print = function() end
local whispered
_G.ChatFrame_SendTell = function(name) whispered = name end

local addon = {}
_G.UnitLevel = function() return 52 end
_G.GetInventoryItemLink = function() return nil end
_G.ForeverGuildSettings = {}
for _, file in ipairs({ "Locale.lua", "ItemStats.lua", "RecipeFinder.lua", "Orders.lua", "Market.lua", "Board.lua",
    "GroupActivities.lua", "BoardNotes.lua", "Events.lua", "EventsUI.lua", "EventWizard.lua",
    "MarketUI.lua", "Settings.lua", "Tour.lua" }) do
    assert(loadfile("ForeverGuild/" .. file))("ForeverGuild", addon)
end
local UI, board, market = addon.marketUI, addon.board, addon.market
local G, me = "Realm:Gilde", "Anna"
local sent = {}
local knows = { [3914] = true }
local ctx = {
    player = function() return me end, guild = function() return G end, clock = function() return 1700000000 end,
    normalize = function(name) return name end, same = function(name) return name == me end,
    key = function(order) return board.id(order.owner, order.token) end,
    ready = function() return true end, canPost = function() return true end,
    isOnline = function(name) return name == "Bob" end, displayName = function(name) return name or "–" end,
    whisper = function(name) ChatFrame_SendTell(name) end,
    describe = function(order) return { name = "Rote Magiestofftasche", profession = "Schneiderei", professionID = 197,
        quality = 2, itemID = 10050, icon = 133652, color = { r = 0, g = 1, b = 0 }, rarity = "Q2" } end,
    recipeName = function() return "Rote Magiestofftasche" end, recipeTooltip = function() end,
    skill = function() return 235 end,
    materials = function() return { { items = { 4339 }, count = 2 }, { items = { 2604, 2605 }, count = 1 } } end,
    itemName = function(id) return "Item " .. id end, itemIcon = function() return 134400 end,
    knows = function(recipe) return knows[recipe] == true end,
    crafters = function() return { { name = "Bob", label = "Bob online", online = true }, { name = "Carl", label = "Carl" } } end,
    supportsMarket = function(name) return name ~= "Carl" end,
    hidden = function() return false end, mayModerate = function() return false end, moderate = function() end,
    legacyOrders = function() return { ["Dora/direct/1-1"] = { sender = "Dora", recipe = 3914, quantity = 2, received = 1699990000,
        guild = G, done = false, unread = true } } end,
    belongs = function(order) return order.guild == G end, legacyRead = function() end,
    isArchived = function(key) return market.isArchived(G, key) end,
    archive = function(key, value) market.archive(G, key, 1700000000, value) end,
    removeLocal = function(key, legacy) if legacy then market.remove(G, key, 1700000000) else board.removeLocal(G, key, 1700000000) end end,
    legacyWithdraw = function() end,
    legacySetDone = function() end, legacySend = function(name) sent.legacy = name end,
    create = function(fields) return board.create(G, me, fields, function(message) sent[#sent + 1] = message; return true end) end,
    editOrder = function(order, fields) return board.edit(G, order, fields, function() return true end) end,
    act = function(order, action, arg, text)
        sent.last = action
        board.action(order, me, action, function() return true end, function() return true end, 1700000000, arg, text, G)
    end,
    openCatalog = function() end, openTab = function() end, openOrder = function(key) sent.opened = key end,
    refresh = function() end, updateNotice = function() end, finder = function() return { recipeDetails = function() return nil end,
        requestItem = function() end, recipeName = function() return "x" end, professionName = function() return "p" end,
        professionIcon = function() return 1 end } end,
    panel = function() return CreateFrame("Frame") end, contrastPanel = function() return CreateFrame("Frame") end,
    button = function(_, label, width)
        local control = CreateFrame("Button")
        control:SetText(label)
        control:SetWidth(width)
        return control
    end,
    pageBackdrop = function() end, icon = "icon", inCombat = function() return false end,
}

ctx.edit = function(order) UI.openDialog(ctx, { order = order }) end
ctx.reorder = function(order) UI.openDialog(ctx, { copy = order }) end

local ok, err = pcall(function()
    UI.attach(ctx)
    -- Dialog: direct order, public order, legacy target.
    local dialog = UI.openDialog(ctx, { recipe = 3914, crafter = "Bob", professionID = 197 })
    check("dialog opens for direct order", dialog ~= nil and dialog.crafter == "Bob")
    dialog.tipBox.boxes[1]:SetText("2")
    dialog.tipBox.boxes[2]:SetText("50")
    dialog.pay = "f"
    dialog.tipEach = true
    dialog.quantity:SetText("5")
    UI.updateDialog(ctx)
    check("dialog valid", dialog.valid == true)
    UI.provideAll(dialog, true)
    UI.submitDialog(ctx)
    local created
    for _, order in pairs(board.records(G)) do created = order end
    check("direct order created", created and created.direct and created.crafter == "Bob")
    check("tip per craft stored as copper", created and created.tip == 25000 and created.tipEach == true)
    check("materials provided stored", created and created.provided[4339] == 10)
    check("opened created order", sent.opened ~= nil)
    UI.openDialog(ctx, { recipe = 3914, crafter = "Carl" })
    check("legacy target detected", dialog.legacyTarget == true)
    UI.submitDialog(ctx)
    check("legacy target uses old path", sent.legacy == "Carl")
    UI.openDialog(ctx, { recipe = 3914, public = true })
    UI.submitDialog(ctx)
    UI.openDialog(ctx, { order = created })
    check("edit dialog prefilled", dialog.quantity:GetText() == "5")
    UI.submitDialog(ctx)

    -- Foreign public order the player can claim, plus an accepted one where the player crafts.
    local foreign = { ext = true, owner = "Bob", token = "1699999000-1", recipe = 3914, quantity = 3, state = "O", revision = 1,
        expiresAt = 1700500000, tip = 55000, pay = "f", cost = 0, costOffer = 0, method = 1, crafted = 0, shipped = 0,
        delivered = 0, paidSent = 0, paidGot = 0, matState = 0, provided = { [4339] = 6 }, note = "Bitte rot" }
    board.records(G)["Bob/1699999000-1"] = foreign
    local working = { ext = true, owner = "Bob", token = "1699999000-2", recipe = 3914, quantity = 4, state = "W", revision = 3,
        crafter = "Anna", tip = 10000, tipEach = true, pay = "v", cost = 2000, costOffer = 0, method = 2, crafted = 1,
        shipped = 0, delivered = 0, paidSent = 0, paidGot = 0, matState = 2, due = 1699999999, provided = {},
        log = { { at = 1699999000, code = "accepted", by = "Anna" } }, proposal = { f = "q", v = 5, by = "o" } }
    board.records(G)["Bob/1699999000-2"] = working

    local window = CreateFrame("Frame")
    window.ordersTab = CreateFrame("Button")
    UI.buildManager(window, ctx)
    for _, tab in ipairs({ "incoming", "accepted", "mine", "handoff", "history" }) do
        window.setOrderTab(tab)
        window.refreshOrders()
    end
    check("manager refreshes all tabs", true)
    window.selectOrder("Bob/1699999000-2")
    window.refreshOrders()
    window.openUnreadOrders()

    local page = CreateFrame("Frame")
    local view = UI.buildBoard(page, ctx)
    view.refresh()
    check("board refresh", true)

    -- Every action for several roles and states runs without errors (prompts confirm immediately).
    local originalPrompt = UI.prompt
    UI.prompt = function(c, spec)
        originalPrompt(c, spec)
        local value = spec.kind == "money" and 1000 or (spec.kind == "text" and "Grund")
            or (spec.kind == "choice" and spec.options[1][1]) or (spec.kind == "proposal" and 5) or spec.default or 1
        spec.confirm(value, spec.kind == "proposal" and "q" or nil)
    end
    local function runAll(order, label)
        local actions = UI.actions(ctx, order, 1700000000)
        for _, action in ipairs(actions) do
            if action.run and not action.disabled then action.run() end
        end
        check("actions run: " .. label .. " (" .. #actions .. ")", #actions > 0)
    end
    runAll(foreign, "foreign open order")
    runAll(working, "crafter in progress")
    runAll(created, "own direct request")
    created.state = "R"; created.crafter = "Bob"
    runAll(created, "own order ready")
    created.state = "J"
    runAll(created, "own declined order")
    created.state = "D"
    runAll(created, "own completed order")
    local legacyEntry = setmetatable({ key = "Dora/direct/1-1" }, { __index = { sender = "Dora", recipe = 3914, quantity = 2,
        received = 1699990000, done = false } })
    check("legacy incoming actions incl. archive/remove", #UI.actions(ctx, nil, 1700000000, legacyEntry) == 4)
    for _, action in ipairs(UI.actions(ctx, nil, 1700000000, legacyEntry)) do if action.run then action.run() end end
    check("legacy order removed locally", market.isRemoved(G, "Dora/direct/1-1"))
    local outgoing = setmetatable({ key = "outgoing/1-2" }, { __index = { outgoing = true, recipient = "Bob", recipe = 3914,
        quantity = 1, received = 1699990000, delivery = "waiting" } })
    check("legacy outgoing: withdraw, recreate, archive, remove", #UI.actions(ctx, nil, 1700000000, outgoing) == 5)
    local legacyDetail = UI.detail(CreateFrame("Frame"), ctx)
    legacyDetail.set(nil, outgoing)
    check("legacy detail renders", true)
    UI.prompt = originalPrompt
    UI.prompt(ctx, { title = "x", kind = "proposal", options = { { "t", "Tip" } }, values = { t = 1 }, confirm = function() end })

    -- Notifications and history.
    UI.notify(ctx, working, "ready", nil, 4)
    UI.notify(ctx, working, "ready", nil, 4)
    check("notification stored once", market.unread(G) >= 1)
    UI.showNotes(ctx)
    UI.tick(ctx)
    -- Central settings window: register pages, open every page, search, restore defaults.
    local S = addon.settingsUI
    UI.registerSettings(S, ctx)
    S.page("ui", "general", "User interface")
    S.add({ page = "ui", kind = "check", label = "Show minimap icon", desc = "Left-click opens ForeverGuild.",
        scope = "account", get = function() return true end, set = function() end, default = true })
    S.add({ page = "ui", kind = "button", label = "Start tour", action = function() end })
    local settingsCtx = { inCombat = function() return false end, icon = "icon", panel = ctx.panel,
        contrastPanel = ctx.contrastPanel, button = ctx.button, version = "0.9.63", market = ctx }
    S.open(settingsCtx, "orders")
    for _, page in ipairs(S.pages) do S.showPage(page.id) end
    check("every settings page renders", #S.pages >= 6)
    local window = _G.ForeverGuildSettingsWindow or nil
    _ = window
    UI.prompt = function(_, spec) spec.confirm(true) end
    market.set("days", 12)
    S.showPage("orders")
    local defaultsRun = false
    for _, entry in ipairs(S.byPage.orders) do if entry.default ~= nil then entry.set(entry.default); defaultsRun = true end end
    check("defaults restore market days", defaultsRun and market.setting("days") == 7)
    UI.prompt = originalPrompt
    -- Data management buttons run their confirmations.
    UI.prompt = function(_, spec) spec.confirm(true) end
    local manager = CreateFrame("Frame")
    UI.buildDataManagement(manager, ctx)
    UI.showLegacyOrders(ctx)
    UI.prompt = originalPrompt
    check("data management built", true)
    -- Order picker in picker mode with catalog recipes and the advanced filters.
    local pickerCtx = { source = function() return {} end, profiles = function() return {} end,
        isMember = function() return true end, isOnline = function() return false end, member = function() return nil end,
        displayName = function(name) return name end, dataCoverage = function() return 0, 0 end,
        player = function() return me end, recipeName = function(id) return "Rezept " .. id end,
        recipeDetails = function() return nil end, professionName = function() return "Schneiderei" end,
        professionIcon = function() return 1 end, requestItem = function() end, recipeTooltip = function() end,
        materialRows = function() return {} end, order = function() end, public = function() end,
        panel = ctx.panel, button = ctx.button, inCombat = function() return false end,
        catalogRecipes = function() return { [3914] = 197 } end }
    local picker = addon.recipeFinder.create(CreateFrame("Frame"), pickerCtx, { picker = true })
    picker.refresh(true)
    check("picker lists catalog recipe without crafter", true)
    -- Tour: welcome, stations, continue later, finish.
    UIParent:SetSize(1920, 1080)
    local fakeWindow = CreateFrame("Frame")
    fakeWindow:SetSize(1100, 700)
    fakeWindow._state.left, fakeWindow._state.top = 400, 900
    local function child(left, top, width, height)
        local frame = CreateFrame("Frame")
        frame:SetSize(width, height)
        frame._state.left, frame._state.top = left, top
        return frame
    end
    fakeWindow.rosterMembers = child(420, 850, 400, 600)
    fakeWindow.orderCards = child(420, 830, 392, 600)
    fakeWindow.boardOrders = { listPanel = child(420, 760, 600, 520) }
    fakeWindow.groupList = child(430, 780, 335, 560)
    fakeWindow.bank, fakeWindow.admin = child(420, 860, 1060, 640), child(420, 860, 1060, 640)
    fakeWindow.bankFocus = child(430, 800, 700, 560)
    fakeWindow.finder = { filterPanel = child(640, 860, 840, 70), tree = child(420, 860, 204, 640) }
    local sections = {}
    fakeWindow.showBoardSection = function(key) sections[#sections + 1] = key end
    local setup = child(700, 800, 500, 566)
    setup.choiceArea = child(712, 745, 476, 200)
    setup:Hide()
    local settingsFrame = child(500, 900, 900, 620)
    settingsFrame.nav = child(512, 834, 200, 510)
    local notes = child(600, 700, 520, 460)
    notes:Hide()
    local mainShown, tab, shownWith = false, "roster", {}
    local tourCtx = { window = function() return fakeWindow end, inCombat = function() return false end,
        icon = "icon", button = ctx.button, officer = function() return true end,
        openTab = function(value) mainShown, tab = true, value end,
        openSetup = function() setup:Show(); return setup end,
        openNotes = function() notes:Show(); return notes end,
        openSettings = function() settingsFrame:Show(); return settingsFrame end,
        setupWindow = function() return setup end, settingsWindow = function() return settingsFrame end,
        notesWindow = function() return notes end, currentTab = function() return tab end,
        mainShown = function() return mainShown end, hideMain = function() mainShown = false end,
        restoreMain = function(wasShown, previous) mainShown, tab = wasShown, previous end,
        otherWindows = function() return {} end }
    local function runTimers()
        for _ = 1, 8 do
            local pending = timers
            timers = {}
            for _, fn in ipairs(pending) do fn() end
        end
    end
    addon.tour.maybeWelcome(tourCtx, false)
    check("welcome shown for a new account", _G.ForeverGuildSettings.tour.seen == true)
    addon.tour.stop()
    -- Started from the settings window, which must not stay open behind the tour.
    settingsFrame:Show()
    addon.tour.start(tourCtx, 2)
    runTimers()
    local boxFrame = _G.ForeverGuildTourStep
    shownWith.character = { setup = setup._state.shown, settings = settingsFrame._state.shown, main = mainShown }
    check("character step: only the setup dialog is shown", shownWith.character.setup and not shownWith.character.settings
        and not shownWith.character.main)
    local s = boxFrame._state
    local l, r, t, b = s.left, s.left + s.width, s.top, s.top - s.height
    local area = setup.choiceArea._state
    local overlaps = l < area.left + area.width and r > area.left and t > area.top - area.height and b < area.top
    check("tour box fully on screen", l >= 0 and r <= 1920 and b >= 0 and t <= 1080)
    check("tour box does not cover the role area", not overlaps)
    check("tour box size (width 480, height >= 300)", s.width == 480 and s.height >= 300)
    check("box swallows clicks and the mouse wheel", s.scripts.OnMouseDown ~= nil and s.scripts.OnMouseWheel ~= nil)
    local order = {}
    for step = 3, 20 do
        addon.tour.start(tourCtx, step)
        runTimers()
        order[#order + 1] = _G.ForeverGuildSettings.tour.stepId
    end
    local boardIndex, groupIndex
    for index, id in ipairs(order) do
        if id == "board" then boardIndex = index end
        if id == "groups" then groupIndex = index end
    end
    check("group search directly follows the bulletin board", boardIndex and groupIndex == boardIndex + 1)
    check("board station switches back to crafting orders, groups to group search",
        sections[1] == "orders" and sections[2] == "G")
    check("last station is the finish", order[#order] == "finish")
    check("setup dialog closed after its station", setup._state.shown == false)
    addon.tour.finish()
    check("finishing hides the box", boxFrame._state.shown == false)
    check("settings window restored after the tour", settingsFrame._state.shown == true and setup._state.shown == false)
    -- Saved progress from 0.9.63/0.9.64 (step number) is migrated to a station ID.
    _G.ForeverGuildSettings.tour = { step = 7, seen = true }
    check("old progress migrated to a station", addon.tour.resumable() and true or false)
    addon.tour.start(tourCtx)
    runTimers()
    check("resumes at the bulletin board", _G.ForeverGuildSettings.tour.stepId == "board")
    addon.tour.stop()
    _G.ForeverGuildSettings.tour = nil
    addon.tour.maybeWelcome(tourCtx, true)
    check("existing users only get a hint", _G.ForeverGuildSettings.tour.hinted == true and not _G.ForeverGuildSettings.tour.seen)
    for _ = 1, 5 do
        local pending = timers
        timers = {}
        for _, fn in ipairs(pending) do fn() end
    end
    check("whisper uses context", whispered ~= nil)
end)
if not ok then
    failures = failures + 1
    io.write("FAIL runtime error: " .. tostring(err) .. "\n")
end
io.write((failures == 0 and "ALL TESTS PASSED" or (failures .. " FAILURE(S)")) .. "\n")
os.exit(failures == 0 and 0 or 1)
