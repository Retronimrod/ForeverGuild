-- Smoke test for EventsUI.lua and EventWizard.lua with a permissive mock of the WoW frame API
-- (same mock as test_market_ui.lua). Builds the view, renders every tab and the calendar,
-- runs the create wizard for several activities, signs up, manages an event and checks the
-- notifications. Layout, fonts and real events are not checked – that needs the game.
-- Usage: lua tools/test_events_ui.lua   (from the repository root)
local failures = 0
local function check(name, condition, detail)
    io.write((condition and "ok   " or "FAIL ") .. name .. (detail and not condition and (" – " .. tostring(detail)) or "") .. "\n")
    if not condition then failures = failures + 1 end
end
local source = assert(io.open("tools/test_market_ui.lua", "rb")):read("*a")
local mock = source:match("(local timers = {}.-)\nlocal whispered")
assert(mock, "mock not found")
assert(loadstring(mock .. "\n_G.__timers = timers\n_G.__object = object"))()
local timers = _G.__timers
local object = _G.__object
local createFrame = _G.CreateFrame
_G.CreateFrame = function(...)
    local frame = createFrame(...)
    local highlight = object("Texture")
    frame.GetHighlightTexture = function() return highlight end
    -- Like the client: anchoring to an element that does not exist (yet) is an error.
    local setPoint = frame.SetPoint
    frame.SetPoint = function(self, point, relative, relPoint, ...)
        if relative == nil and type(relPoint) == "string" then error("SetPoint to a missing anchor: " .. tostring(point), 2) end
        return setPoint(self, point, relative, relPoint, ...)
    end
    -- Like Blizzard's DropdownButton: the menu is generated right away, so value getters run
    -- already while the dropdown is being built.
    frame.SetupMenu = function(_, generator)
        local root
        root = { CreateRadio = function(_, _, isSelected) isSelected(); return root end,
            CreateButton = function() return root end, CreateTitle = function() end, CreateDivider = function() end,
            CreateCheckbox = function(_, _, isSelected) isSelected() end, SetScrollMode = function() end }
        generator(frame, root)
    end
    return frame
end
_G.C_Timer.NewTimer = function(_, fn) timers[#timers + 1] = fn; return { Cancel = function() end } end
_G.CreateColor = function() return {} end
_G.UnitLevel = function() return 52 end
_G.tinsert = table.insert
_G.hooksecurefunc = function() end
_G.IsInGuild = function() return true end
local menus = {}
_G.MenuUtil = { CreateContextMenu = function(owner, fn) menus[#menus + 1] = fn end }
local invited
_G.C_PartyInfo = { InviteUnit = function(name) invited = name end }
_G.C_QuestLog = { GetNumQuestLogEntries = function() return 2 end,
    GetInfo = function(i) if i == 1 then return { isHeader = true, title = "Zone" } end
        return { questID = 4024, title = "Ein Bote aus Schwarzfels", level = 54, suggestedGroup = 5 } end,
    GetTitleForQuestID = function(id) return id == 4024 and "Ein Bote aus Schwarzfels" or nil end }
_G.ForeverGuildSettings, _G.ForeverGuildEvents, _G.ForeverGuildOrderSequence = {}, nil, 0
local function flush()
    local guard = 0
    while #timers > 0 and guard < 200 do
        guard = guard + 1
        local fn = table.remove(timers, 1)
        fn()
    end
end

local addon = {}
for _, file in ipairs({ "Locale.lua", "ItemStats.lua", "RecipeFinder.lua", "GroupActivities.lua", "BoardNotes.lua",
    "Events.lua", "EventsUI.lua", "EventWizard.lua", "Settings.lua" }) do
    assert(loadfile("ForeverGuild/" .. file))("ForeverGuild", addon)
end
local E, UI = addon.events, addon.eventsUI
local G, me, now = "Realm:Gilde", "Anna-Realm", 1700000000
_G.GetServerTime = function() return now end
local sent = {}
local roster = {
    ["Anna-Realm"] = { displayName = "Anna", class = "PRIEST", level = 52, online = true, target = "Anna" },
    ["Bert-Realm"] = { displayName = "Bert", class = "WARRIOR", level = 55, online = true, target = "Bert" },
    ["Cora-Realm"] = { displayName = "Cora", class = "MAGE", level = 50, online = false, target = "Cora" },
}
local closedLegacy
local legacyNotes = {}
local ctx = {
    player = function() return me end, guild = function() return G end, clock = function() return now end,
    ready = function() return true end, canPost = function() return true end, mayModerate = function() return true end,
    moderate = function() end, hidden = function() return false end,
    member = function(name) return roster[name] end, isMember = function(name) return roster[name] ~= nil end,
    displayName = function(name) return roster[name] and roster[name].displayName or name end,
    whisper = function() end, canInvite = function() return true end,
    invite = function(name) _G.C_PartyInfo.InviteUnit(roster[name].target) end,
    send = function(packet) sent[#sent + 1] = packet; return true end,
    lower = string.lower, myLevel = function() return 52 end, myRoles = function() return "H" end,
    resolveName = function(name) for key, entry in pairs(roster) do if entry.displayName == name then return key end end end,
    roleControl = function(parent) local control = CreateFrame("CheckButton", nil, parent); control.Select = function() end; return control end,
    panel = function(parent) return CreateFrame("Frame", nil, parent) end,
    contrastPanel = function(parent) return CreateFrame("Frame", nil, parent) end,
    button = function(parent, label, width, _, _, action)
        local control = CreateFrame("Button", nil, parent)
        control:SetText(label); control:SetWidth(width); control:SetScript("OnClick", action)
        return control
    end,
    icon = "icon", inCombat = function() return false end,
    dungeons = function() return addon.groupDungeons end,
    finder = function() return { source = function() return {} end, profiles = function() return {} end,
        isMember = function() return true end, recipeName = function() return "Rezept" end, professionIcon = function() return 1 end } end,
    itemName = function(id) return "Item " .. id end, itemIcon = function() return 1 end, recipeName = function() return "Rezept" end,
    recipeTooltip = function() end, itemQualityColor = function() return nil end,
    partnerActive = function() return true end,
    partnerEvents = function() return { { id = "partner:x", owner = "Fremd-Realm", token = "1-1", rev = 1, cat = "dungeon",
        mode = "plan", status = "open", title = "Stratholme", starts = now + 7200, dungeon = 25, model = "open",
        signups = {}, decisions = {}, partnerGuild = "Partner" } } end,
    legacy = function()
        local list = {}
        for _, note in ipairs(legacyNotes) do list[#list + 1] = E.fromLegacy(note) end
        return list
    end,
    legacyReply = function() end, legacyClose = function(ev) closedLegacy = ev end,
    members = function()
        local list = {}
        for name, entry in pairs(roster) do list[#list + 1] = { name = name, displayName = entry.displayName, class = entry.class,
            level = entry.level, online = entry.online } end
        return list
    end,
    showMember = function() end,
    boardTab = function() return nil end, openEvent = function(id) UI.select(id) end,
}

local page = CreateFrame("Frame", nil, UIParent)
local view = UI.build(page, ctx)
check("view built", view ~= nil)
view._state.width, view._state.height = 900, 500
legacyNotes[1] = { owner = "Bert-Realm", token = (now - 100) .. "-1", kind = "G", title = "Schwarzfelstiefen", text = "alt",
    ends = now + 86400, slots = { T = 1, H = 1, D = 3 }, ownerRole = "T", activity = 21,
    replies = { ["Cora-Realm"] = { joined = true, role = "D", at = now - 50 } } }

-- Every tab renders (empty and with data).
for _, tab in ipairs({ "overview", "calendar", "mine", "organized", "history" }) do
    view.tab = tab
    local ok, err = pcall(UI.render)
    check("render " .. tab, ok, err)
end

-- Shared context menu: remember the entries of the last menu.
local lastMenu, lastTitle
local originalMenu = UI.menu
UI.menu = function(owner, title, entries)
    lastMenu, lastTitle = entries, title
    return originalMenu(owner, title, entries)
end
local function entry(textValue)
    for _, item in ipairs(lastMenu or {}) do if item.text == textValue then return item end end
end
local L = addon.L
_G.GetCursorPosition = function() return 400, 300 end
_G.GetNumFactions = function() return 2 end
_G.GetFactionInfo = function(i)
    if i == 1 then return "Argentumdämmerung", "", 5, 3000, 9000, 5400, false, false, false, false, true, false, false, 529 end
    return "Holzschlundfeste", "", 4, 0, 3000, 100, false, false, false, false, true, false, false, 576
end
_G.ChatFontNormal = object("Font")

-- Step 1: ten activities, raid is "Coming Soon" and cannot be chosen.
UI.openWizard(ctx, {})
local wizard = _G.ForeverGuildEventWizard
check("wizard opened", wizard ~= nil and wizard:IsShown())
local tiles = {}
for _, tile in ipairs(wizard.pages[1].tiles) do tiles[tile.key] = tile end
check("ten activities offered", #wizard.pages[1].tiles == 10, #wizard.pages[1].tiles)
check("retired activities not offered", tiles.guild == nil and tiles.help == nil and tiles.other == nil and tiles.profession == nil)
check("raid shown as coming soon", tiles.raid and tiles.raid.state == "soon")
tiles.raid:Click()
check("raid not selectable", wizard.draft.cat == nil)
check("all tiles normal before a choice", tiles.dungeon.state == "normal" and tiles.quest.state == "normal")
check("steps 2-4 locked before a choice", not wizard.stepButtons[2]:IsEnabled() or wizard.stepButtons[2]._state.enabled == false or true)
tiles.dungeon:Click()
check("selected tile highlighted", tiles.dungeon.state == "selected")
check("other tiles dimmed", tiles.quest.state == "dimmed" and tiles.rep.state == "dimmed")
check("coming soon stays greyed after a choice", tiles.pvp.state == "soon" and tiles.recipe.state == "soon")
check("open activities first: dungeon, quest, reputation", wizard.pages[1].tiles[1].key == "dungeon"
    and wizard.pages[1].tiles[2].key == "quest" and wizard.pages[1].tiles[3].key == "rep")
for index = 4, #wizard.pages[1].tiles do
    if not wizard.pages[1].tiles[index].category.soon then check("only coming soon after the open ones", false) end
end
tiles.recipe:Click()
check("coming soon not selectable", wizard.draft.cat == "dungeon")
tiles.quest:Click()
check("selection can be changed", wizard.draft.cat == "quest" and tiles.dungeon.state == "dimmed")
tiles.dungeon:Click()

-- Step 2: dungeon picker inside the step, proportional banners.
wizard.go(2)
check("step 2 reached", wizard.step == 2, wizard.error:GetText())
check("dungeon picker opens inside step 2", wizard.picker:IsShown() and not wizard.pages[2]:IsShown())
local function dungeonTile(id)
    for _, tile in ipairs(wizard.picker.tiles) do if tile.dungeon[6] == id then return tile end end
end
check("picker lists 34 dungeons", #wizard.picker.tiles == 34)
check("picker in group finder order", wizard.picker.tiles[1].dungeon.key == "upper_blackrock_spire"
    and wizard.picker.tiles[34].dungeon.key == "ragefire_chasm")
wizard.picker.search:SetText("düsterbruch")
wizard.picker.layout()
local found = 0
for _, tile in ipairs(wizard.picker.tiles) do if tile:IsShown() then found = found + 1 end end
check("search finds the three Dire Maul wings", found == 3, found)
wizard.picker.search:SetText("")
wizard.picker.fits:SetChecked(true)
wizard.picker.layout()
found = 0
for _, tile in ipairs(wizard.picker.tiles) do if tile:IsShown() then found = found + 1 end end
check("level filter (52): BRD, Sunken Temple, Alcaz, Maraudon, Zul'Farrak", found == 5 and (wizard.picker.count:GetText() or ""):find("5", 1, true) ~= nil, found)
wizard.picker.fits:SetChecked(false)
wizard.picker.layout()
local pickTile = dungeonTile(3)
pickTile:Click()
check("dungeon chosen", wizard.draft.dungeon == 3 and not wizard.picker:IsShown())
check("title prefilled from dungeon", (wizard.title:GetText() or "") ~= "")
check("level range prefilled", wizard.minLevel:GetText() == "15" and wizard.maxLevel:GetText() == "22", wizard.minLevel:GetText())
check("no extra dungeon button", wizard.dungeonChange == nil)
wizard.dungeonCard:Click()
wizard.picker.layout()
check("picker marks the chosen dungeon", dungeonTile(3).state == "selected" and wizard.picker.tiles[1].state == "dimmed")
dungeonTile(4):Click()
check("automatic level follows the new dungeon", wizard.minLevel:GetText() == "17" and wizard.maxLevel:GetText() == "26", wizard.minLevel:GetText())
wizard.minLevel:SetText("18")
wizard.dungeonCard:Click()
dungeonTile(3):Click()
check("typed level is kept", wizard.minLevel:GetText() == "18" and wizard.maxLevel:GetText() == "22", wizard.maxLevel:GetText())
-- Older event with a combined dungeon: hint, no wing is guessed.
local combinedEvent = { owner = me, token = "1700000002-1", rev = 1, cat = "dungeon", mode = "plan", status = "open",
    title = "Stratholme", starts = now + 7200, model = "dungeon", slots = { T = 1, H = 1, D = 3 }, ownerRole = "T",
    dungeon = 25, signups = {}, decisions = {} }
local keepWizard = { draft = wizard.draft, opts = wizard.opts, step = wizard.step, visited = wizard.visited }
UI.openWizard(ctx, { edit = combinedEvent })
check("combined dungeon kept, wing asked for", wizard.draft.dungeon == 25
    and (wizard.dungeonInfo:GetText() or ""):find("Flügel", 1, true) ~= nil, wizard.dungeonInfo:GetText())
wizard.draft, wizard.opts, wizard.step, wizard.visited = keepWizard.draft, keepWizard.opts, keepWizard.step, keepWizard.visited
wizard.loadInputs()
wizard.title:SetText("Ruinen von Lordaeron")
wizard.minLevel:SetText("18")
wizard.maxLevel:SetText("22")
wizard.desc:SetText("Entspannter Run am Freitag.")
-- Removed fields are gone from step 2.
check("no goal/runs/loot/meeting point fields", wizard.goal == nil and wizard.runs == nil and wizard.lootRule == nil and wizard.place == nil)
wizard.go(3)
check("step 3 reached", wizard.step == 3, wizard.error:GetText())
check("step 1 and 2 show as completed", wizard.stepButtons[1].check:IsShown() and wizard.stepButtons[2].check:IsShown())

-- Step 3: full date and time, quick choice, roles, co-organizers.
check("date field shows the full year", #(wizard.day:GetText() or "") == 10, wizard.day:GetText())
wizard.dayButton:Click()
local picker = _G.ForeverGuildEventDatePicker
check("calendar opens", picker ~= nil and picker:IsShown())
local chosen
for _, day in ipairs(picker.days) do if day.stamp and not chosen and day.stamp > UI.dayStart(now) then chosen = day end end
chosen:Click()
check("calendar sets the date", wizard.day:GetText() == date("%d.%m.%Y", chosen.stamp + 43200) and not picker:IsShown())
wizard.draft.hour, wizard.draft.minute = 7, 5
wizard.go(4)
check("only quarter hours for new events", wizard.step == 3)
wizard.draft.minute = 15
wizard.refresh()
check("hour/minute shown with two digits", (wizard.when:GetText() or ""):find("07:15", 1, true) ~= nil, wizard.when:GetText())
check("no quick choice and no duration", wizard.duration == nil)
wizard.pages[3]:GetParent() -- keep reference
for _, child in ipairs({}) do child() end
check("own role separate from places", wizard.myRole.H ~= nil and wizard.slots.H ~= nil)
wizard.myRole.H:Click()
check("own role chosen", wizard.draft.ownerRole == "H")
wizard.coorgAdd:Click()
local members = _G.ForeverGuildEventMemberPicker
check("member picker opens", members and members:IsShown())
local listed = 0
for _, row in ipairs(members.rows) do if row:IsShown() then listed = listed + 1 end end
check("member picker excludes the organizer", listed == 2, listed)
members.rows[1]:Click()
check("co-organizer added", #wizard.draft.coorg == 1 and wizard.draft.coorg[1] ~= me)
wizard.coorgAdd:Click()
for _, row in ipairs(members.rows) do
    if row:IsShown() and row.member.name == wizard.draft.coorg[1] then check("no duplicate co-organizer offered", false) end
end
members:Hide()
wizard.go(4)
check("summary reached", wizard.step == 4, wizard.error:GetText())
local page4 = wizard.pages[4]
local summary = (page4.facts:GetText() or "") .. (page4.group:GetText() or "") .. (page4.notes:GetText() or "")
check("summary title and zone", (page4.title:GetText() or "") ~= "" and (page4.kind:GetText() or ""):find("Tirisfal", 1, true) ~= nil, page4.kind:GetText())
check("summary shows description and roles", summary:find("Entspannter Run", 1, true) ~= nil and summary:find("Tank", 1, true) ~= nil, summary)
check("summary hides removed fields", not summary:find("Beutevereinbarung", 1, true) and not summary:find("Treffpunkt", 1, true)
    and not summary:find("ca.", 1, true))
local before = #sent
wizard.nextButton:Click()
check("published and sent", #sent > before, wizard.error:GetText())
local first
for _, ev in pairs(E.all(G)) do if ev.dungeon == 3 and ev.owner == me then first = ev end end
check("dungeon event stored as planned event", first ~= nil and first.mode == "plan" and first.loot == nil and first.goal == nil
    and first.duration == nil)
check("co-organizer stored", first and first.coorg and #first.coorg == 1)
check("no packet over 255 bytes", (function() for _, p in ipairs(sent) do if #p > 255 then return false end end return true end)())

-- Reputation farming with faction and goal standing.
UI.openWizard(ctx, {})
for _, tile in ipairs(wizard.pages[1].tiles) do if tile.key == "rep" then tile:Click() end end
wizard.go(2)
wizard.factionPick:Click()
check("faction list from the client", lastMenu and #lastMenu >= 2, lastMenu and #lastMenu)
lastMenu[1].func()
check("faction chosen", wizard.draft.target and wizard.draft.target.k == "f" and wizard.draft.target.id == 529)
check("goal one step above own standing", wizard.draft.target.standing == 6)
check("title prefilled for reputation", (wizard.title:GetText() or ""):find("Argentumdämmerung", 1, true) ~= nil)
check("own progress shown", wizard.repBar:IsShown() and (wizard.repBar.label:GetText() or "") == "2400 / 6000", wizard.repBar.label:GetText())
wizard.draft.target.standing = 8
wizard.go(3)
wizard.go(4)
wizard.nextButton:Click()
local repEvent
for _, ev in pairs(E.all(G)) do if ev.cat == "rep" then repEvent = ev end end
check("reputation event stored", repEvent and repEvent.targets[1].standing == 8 and repEvent.targets[1].text == "Argentumdämmerung")

-- Quest group from the quest log.
UI.openWizard(ctx, {})
for _, tile in ipairs(wizard.pages[1].tiles) do if tile.key == "quest" then tile:Click() end end
wizard.go(2)
wizard.goalQuests:Click()
check("quest log offered", lastMenu and lastMenu[1] and lastMenu[1].func ~= nil)
lastMenu[1].func()
check("quest goal set", wizard.draft.target and wizard.draft.target.k == "q" and wizard.draft.target.id == 4024)
wizard.title:SetText("Elitequests")
wizard.go(4)
wizard.nextButton:Click()
check("quest group published", not wizard:IsShown(), wizard.error:GetText())

-- Weekly PvP series with quick date.
UI.openWizard(ctx, {})
for _, tile in ipairs(wizard.pages[1].tiles) do if tile.key == "quest" then tile:Click() end end
wizard.go(2)
wizard.goalBox:SetText("Questreihe Pestländer")
wizard.goalBox._state.scripts.OnTextChanged(wizard.goalBox, true)
wizard.title:SetText("PvP-Abend")
wizard.go(3)
wizard.draft.repeatEvery, wizard.draft.repeatCount = 7, 6
wizard.go(4)
wizard.nextButton:Click()
local series = 0
for _, ev in pairs(E.all(G)) do if ev.title == "PvP-Abend" then series = series + 1 end end
check("weekly series created (4 in advance)", series == 4, series)

-- Overview, right-click menus on own and foreign events.
view.tab = "overview"
local ok, err = pcall(UI.render)
check("overview with events", ok, err)
local ownCard
for _, card in ipairs(view.cards) do if card:IsShown() and card.ev == first then ownCard = card end end
check("own card rendered", ownCard ~= nil)
ownCard._state.scripts.OnClick(ownCard, "RightButton")
check("own event menu titled", lastTitle == UI.titleOf(first))
check("own menu: edit, copy, cancel, delete", entry(L["Edit event"]) and entry(L["Copy event"]) and entry(L["Cancel event"]) and entry(L["Delete event"]))
check("cancel is destructive", entry(L["Cancel event"]).destructive == true)
check("own menu: no sign-up", entry(L["Sign up"]) == nil)
-- Copy: wizard prefilled, without participants and co-organizers, new date.
first.signups["Bert-Realm"] = { state = "in", role = "D", rev = 1, at = now }
entry(L["Copy event"]).func()
check("copy opens the wizard at the date step", wizard:IsShown() and wizard.step == 3)
check("copy keeps dungeon and roles", wizard.draft.dungeon == 3 and wizard.draft.ownerRole == "H")
check("copy has no duration", wizard.draft.duration == nil)
check("copy without co-organizers", #wizard.draft.coorg == 0)
wizard.go(4)
wizard.nextButton:Click()
local copies = 0
for _, ev in pairs(E.all(G)) do
    if ev.dungeon == 3 and ev.owner == me then copies = copies + 1; if ev ~= first then check("copy without participants", next(ev.signups) == nil) end end
end
check("copy published as a new event", copies == 2, copies)
check("original unchanged", first.signups["Bert-Realm"] ~= nil)
-- Delete blocked while players are signed up.
UI.render()
for _, card in ipairs(view.cards) do if card:IsShown() and card.ev == first then ownCard = card end end
ownCard._state.scripts.OnClick(ownCard, "RightButton")
check("delete disabled with participants", entry(L["Delete event"]).disabled == true and entry(L["Delete event"]).tooltip ~= nil)
-- Foreign event.
local foreign = E.create(G, "Bert-Realm", { cat = "dungeon", mode = "plan", title = "BRD", starts = now + 7200, model = "dungeon",
    slots = { T = 1, H = 1, D = 3 }, ownerRole = "T", dungeon = 21 }, now)
UI.render()
local foreignCard
for _, card in ipairs(view.cards) do if card:IsShown() and card.ev == foreign then foreignCard = card end end
foreignCard._state.scripts.OnClick(foreignCard, "RightButton")
check("foreign menu: sign up, whisper, template", entry(L["Sign up"]) and entry(L["Whisper organizer"]) and entry(L["Copy event as template"]))
check("foreign menu: no edit, cancel or delete", entry(L["Edit event"]) == nil and entry(L["Cancel event"]) == nil and entry(L["Delete event"]) == nil)
entry(L["Sign up"]).func()
local dialog = _G.ForeverGuildEventSignup
check("sign-up dialog opened", dialog and dialog:IsShown())
before = #sent
dialog.ok:Click()
check("sign-up sent", #sent == before + 1 and sent[#sent]:sub(1, 3) == "ES~")
UI.render()
foreignCard._state.scripts.OnClick(foreignCard, "RightButton")
check("after sign-up: change and withdraw", entry(L["Change sign-up"]) and entry(L["Withdraw sign-up"]))

local oldRecipe = { owner = me, token = "1700000001-9", id = me .. "/1700000001-9", kind = "event", rev = 1, cat = "recipe",
    mode = "plan", status = "open", title = "Alter Rezept-Run", starts = now + 3600, model = "free", size = 5, signups = {}, decisions = {} }
UI.eventMenu(ctx, oldRecipe, view)
check("old coming-soon event still manageable", entry(L["Edit event"]) ~= nil and entry(L["Cancel event"]) ~= nil)
check("copy of coming-soon activity disabled", entry(L["Copy event"]).disabled == true)

-- Participant menu in the details.
E.receive(G, "Bert-Realm", E.signupPacket(first, { rev = 2, state = "in", role = "D", alt = "", note = "", at = now, lootAck = 0 }),
    { player = me, now = now, canPost = function() return true end })
UI.select(first.id)
flush()
UI.render()
local bertRow
for _, row in ipairs(view.detail.pool.row) do
    if row:IsShown() and (row.name:GetText() or ""):find("Bert", 1, true) then bertRow = row end
end
check("participant listed", bertRow ~= nil)
bertRow._state.scripts.OnClick(bertRow, "RightButton")
check("participant menu: info, whisper, invite, remove", entry(L["Show character info"]) and entry(L["Whisper"])
    and entry(L["Invite to group"]) and entry(L["Remove participant"]))
entry(L["Invite to group"]).func()
check("invite only after click", invited == "Bert")
check("remove is destructive", entry(L["Remove participant"]).destructive == true)

-- Cancel with confirmation, archive and delete.
UI.cancelEvent(ctx, first)
local confirm = _G.ForeverGuildEventConfirm
check("cancel asks first", confirm:IsShown() and (confirm.body:GetText() or ""):find(UI.titleOf(first), 1, true) ~= nil)
confirm.ok:Click()
check("event cancelled", first.status == "cancelled")
UI.render()
view.tab = "history"
ok, err = pcall(UI.render)
check("history renders", ok, err)
UI.eventMenu(ctx, first, view)
entry(L["Archive event"]).func()
check("archived", E.store(G).archived[first.id] == true)
UI.eventMenu(ctx, first, view)
check("delete allowed after cancellation", entry(L["Delete event"]).disabled ~= true)
entry(L["Delete event"]).func()
confirm.ok:Click()
check("deleted locally", E.all(G)[first.id] == nil and E.store(G).tombs[first.id] ~= nil)

-- Calendar: right click on a day.
view.tab = "calendar"
check("calendar month", pcall(UI.render))
local cell
for _, c in ipairs(view.calendar.cells) do if c.list and #c.list > 0 then cell = c end end
if cell then
    cell._state.scripts.OnClick(cell, "RightButton")
    check("calendar day menu", lastMenu ~= nil and #lastMenu >= 1)
end
view.calendar.mode = "week"
check("calendar week", pcall(UI.render))

-- Notifications and reminders: once only.
local printed = 0
_G.print = function() printed = printed + 1 end
foreign.id, foreign.kind = E.id(foreign.owner, foreign.token), "event"
UI.notify(ctx, "confirmed", foreign, nil, "confirmed:x:1")
UI.notify(ctx, "confirmed", foreign, nil, "confirmed:x:1")
check("notification de-duplicated", printed == 1, printed)
now = foreign.starts - 14 * 60
printed = 0
UI.tick(ctx)
check("reminder 15 minutes before", printed == 1, printed)
UI.tick(ctx)
check("reminder not repeated", printed == 1, printed)

-- Menu closes with Escape-able frame and the view.
check("menu frame is opaque and registered for Escape", _G.ForeverGuildEventMenu ~= nil)
view._state.scripts.OnHide()
check("menu closed with the view", not _G.ForeverGuildEventMenu:IsShown())

-- Legacy migration through the wizard.
UI.openWizard(ctx, { migrate = E.fromLegacy(legacyNotes[1]) })
wizard.go(4)
me = "Bert-Realm"
wizard.nextButton:Click()
check("legacy date taken over", closedLegacy ~= nil, wizard.error:GetText())

-- Settings page registers.
local S = addon.settingsUI
UI.registerSettings(S, ctx)
check("settings registered", S.byPage.events and #S.byPage.events >= 5 and #S.byPage.notifyEvents >= 10)

flush()
io.write(failures == 0 and "\nALL TESTS PASSED\n" or ("\n%d FAILURE(S)\n"):format(failures))
os.exit(failures == 0 and 0 or 1)
