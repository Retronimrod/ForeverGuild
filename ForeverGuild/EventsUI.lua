local _, addon = ...
-- Groups & events UI: overview with event cards, calendar, my sign-ups, my events, history,
-- detail view with participants and organizer actions, notifications, reminders and
-- settings. The create wizard and the sign-up dialog live in EventWizard.lua.
-- Data access goes through the context from addon.eventContext() (ForeverGuild.lua).
local L = addon.L
local events = addon.events
local UI = {}
addon.eventsUI = UI

local DAY = 86400
local GOLD, MUTED, GREEN, RED, LIGHT = { 1, .82, .24 }, { .62, .57, .50 }, { .45, .86, .45 }, { 1, .45, .35 }, { .93, .87, .74 }
local ART = "Interface\\AddOns\\ForeverGuild\\Art\\"
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local ROLE_CELL = { T = { 0, 1 }, H = { 1, 0 }, D = { 1, 1 } }
local ROLE_NAMES = { T = "Tank", H = "Healer", D = "DPS" }
UI.ROLE_NAMES = ROLE_NAMES
local ART_ASPECT = { DungeonHall = 4, BlackrockHall = 4, GuildHall = 2, GuildProfessions = 2, GuildAdministration = 2 }

local STATUS_LABELS = {
    confirmed = "Confirmed", tentative = "Tentative", attended = "Attended", signed = "Signed up",
    waitlist = "Waitlist", noshow = "Did not show up", rejected = "Declined", out = "Withdrawn",
}
local STATUS_COLORS = {
    confirmed = GREEN, tentative = { .95, .80, .45 }, attended = GREEN, signed = { .89, .73, .42 },
    waitlist = { .61, .78, .90 }, noshow = RED, rejected = RED, out = MUTED,
}
local STATE_LABELS = {
    open = "Sign-up open", closed = "Sign-up closed", full = "Group complete", ready = "Ready to start",
    started = "Started", done = "Completed", cancelled = "Cancelled", expired = "Expired",
}
local STATE_COLORS = {
    open = GREEN, closed = { .95, .80, .45 }, full = { .61, .78, .90 }, ready = GREEN, started = GOLD,
    done = MUTED, cancelled = RED, expired = MUTED,
}
UI.STATUS_LABELS, UI.STATUS_COLORS, UI.STATE_LABELS, UI.STATE_COLORS = STATUS_LABELS, STATUS_COLORS, STATE_LABELS, STATE_COLORS
local GOAL_LABELS = { full = "Full dungeon run", bosses = "Specific bosses", quest = "Quest run", recipe = "Recipe farming",
    gear = "Gear farming", multi = "Several runs in a row", custom = "Custom goal" }
local LOOT_LABELS = { need = "Need before greed", recipe = "Recipe reserved", item = "Item reserved",
    mats = "Split materials", custom = "Custom agreement" }
local MODEL_LABELS = { dungeon = "Classic dungeon group", raid = "Raid group", free = "Free group",
    open = "Open guild event", custom = "Custom group" }
UI.GOAL_LABELS, UI.LOOT_LABELS, UI.MODEL_LABELS = GOAL_LABELS, LOOT_LABELS, MODEL_LABELS
local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local WEEKDAYS_SHORT = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December" }

-- Settings ---------------------------------------------------------------------------------------------
UI.defaults = { view = "overview", runtime = 60, match = true, sound = true, popup = true, chat = true,
    partners = true, fitsOnly = false, archiveDone = true, keepDays = 30, combat = false,
    r1440 = false, r60 = true, r30 = false, r15 = true, r0 = true, prefRoles = "" }

function UI.setting(key)
    local saved = ForeverGuildSettings and ForeverGuildSettings.events
    local value = saved and saved[key]
    if value == nil then return UI.defaults[key] end
    return value
end

function UI.set(key, value)
    ForeverGuildSettings = ForeverGuildSettings or {}
    ForeverGuildSettings.events = ForeverGuildSettings.events or {}
    ForeverGuildSettings.events[key] = value
end

function UI.preferredCategory(key)
    local saved = ForeverGuildSettings and ForeverGuildSettings.events and ForeverGuildSettings.events.cats
    if not saved or next(saved) == nil then return true end
    return saved[key] == true
end

function UI.reminderOffsets()
    local list = {}
    for _, minutes in ipairs({ 1440, 60, 30, 15, 0 }) do
        if UI.setting("r" .. minutes) then list[#list + 1] = minutes end
    end
    return list
end

-- Small helpers ----------------------------------------------------------------------------------------
local function text(parent, font, justify, wrap)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(wrap and true or false)
    return label
end
UI.text = text

local function color(label, c) label:SetTextColor(c[1], c[2], c[3]) end

-- Menu helpers: titles and dividers only when the client's menu system offers them.
local function menuTitle(root, caption) if root.CreateTitle then root:CreateTitle(caption) end end
UI.color = color

function UI.roleIcon(texture, role)
    local cell, coords = 67 / 256, ROLE_CELL[role]
    texture:SetTexture(ROLE_TEXTURE)
    if coords then texture:SetTexCoord(coords[1] * cell, (coords[1] + 1) * cell, coords[2] * cell, (coords[2] + 1) * cell) end
end

function UI.classIcon(texture, class)
    local coords = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]
    if not coords then texture:Hide(); return end
    texture:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    texture:Show()
end

function UI.classColor(ctx, name)
    local member = ctx.member(name)
    local c = member and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
    return c and { c.r, c.g, c.b } or LIGHT
end

-- Fills a texture with a centered crop of an artwork with the given aspect ratio.
function UI.fitArt(texture, aspect, width, height)
    if width <= 0 or height <= 0 then return end
    local ratio = width / (aspect * height)
    local x = math.max(0, (1 - ratio) / 2)
    local y = math.max(0, (1 - 1 / ratio) / 2)
    texture:SetTexCoord(x, 1 - x, y, 1 - y)
end

function UI.banner(ev)
    local category = events.byCategory[ev.cat] or events.byCategory.other
    local dungeon = ev.dungeon and addon.getGroupDungeon(ev.dungeon)
    if dungeon then return addon.dungeonArt(dungeon), 4 end
    return ART .. category.art, ART_ASPECT[category.art] or 2
end

function UI.dayStart(t)
    local parts = date("*t", t)
    parts.hour, parts.min, parts.sec = 0, 0, 0
    return time(parts)
end

function UI.clock(t) return L["TIME_FORMAT"]:format(date("%H:%M", t)) end

function UI.when(t, now)
    local today = UI.dayStart(now)
    if t >= today and t < today + DAY then return L["Today, %s"]:format(UI.clock(t)) end
    if t >= today + DAY and t < today + 2 * DAY then return L["Tomorrow, %s"]:format(UI.clock(t)) end
    if t >= today - DAY and t < today then return L["Yesterday, %s"]:format(UI.clock(t)) end
    local weekday = L[WEEKDAYS[tonumber(date("%w", t)) + 1]]
    if t > today and t < today + 7 * DAY then return ("%s, %s"):format(weekday, UI.clock(t)) end
    return ("%s, %s, %s"):format(weekday, date("%d.%m.", t), UI.clock(t))
end

function UI.longDate(t)
    local parts = date("*t", t)
    return L["DATE_LONG"]:format(L[WEEKDAYS[parts.wday]], parts.day, L[MONTHS[parts.month]], parts.year)
end
UI.MONTHS, UI.WEEKDAYS, UI.WEEKDAYS_SHORT = MONTHS, WEEKDAYS, WEEKDAYS_SHORT

-- "UTC+1" for the explanation of local times.
function UI.zone(now)
    local here, utc = date("*t", now), date("!*t", now)
    here.isdst = false
    local diff = math.floor((time(here) - time(utc)) / 60 + .5)
    local sign = diff < 0 and "-" or "+"
    diff = math.abs(diff)
    if diff % 60 == 0 then return ("UTC%s%d"):format(sign, diff / 60) end
    return ("UTC%s%d:%02d"):format(sign, math.floor(diff / 60), diff % 60)
end

function UI.duration(minutes)
    if not minutes then return nil end
    if minutes < 60 then return L["%d min"]:format(minutes) end
    if minutes % 60 == 0 then return minutes == 60 and L["1 hour"] or L["%d hours"]:format(minutes / 60) end
    return L["%d h %d min"]:format(math.floor(minutes / 60), minutes % 60)
end

function UI.levelText(ev)
    if ev.minLevel and ev.maxLevel then return L["Level %d–%d"]:format(ev.minLevel, ev.maxLevel) end
    if ev.minLevel then return L["Level %d+"]:format(ev.minLevel) end
    if ev.maxLevel then return L["Up to level %d"]:format(ev.maxLevel) end
    local dungeon = ev.dungeon and addon.getGroupDungeon(ev.dungeon)
    if dungeon then return L["Level %d–%d"]:format(dungeon.min, dungeon.max) end
end

function UI.titleOf(ev)
    local dungeon = ev.dungeon and addon.getGroupDungeon(ev.dungeon)
    -- Titles that are just the dungeon name (also a former name) show the current name.
    if dungeon and (ev.title == dungeon[1] or ev.title == dungeon[2] or (dungeon.former and ev.title == dungeon.former)) then
        return dungeon[GetLocale() == "deDE" and 1 or 2]
    end
    return ev.title or ""
end

function UI.categoryLabel(ev)
    local category = events.byCategory[ev.cat] or events.byCategory.other
    return L[category.label]
end

-- Search text of the event's goals (dungeon names, quest and item targets).
function UI.extraText(ctx, ev)
    local parts = {}
    local dungeon = ev.dungeon and addon.getGroupDungeon(ev.dungeon)
    if dungeon then parts[#parts + 1] = dungeon[1] .. " " .. dungeon[2] .. " " .. dungeon[3] .. " " .. dungeon[4] end
    for _, target in ipairs(ev.targets or {}) do parts[#parts + 1] = UI.targetName(ctx, target) end
    return table.concat(parts, " ")
end

local STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
function UI.standingLabel(index)
    return _G["FACTION_STANDING_LABEL" .. tostring(index)] or L[STANDINGS[index] or "Neutral"]
end

function UI.targetName(ctx, target)
    if target.k == "t" then return target.text end
    if target.k == "f" then return L["%s · goal: %s"]:format(target.text, UI.standingLabel(target.standing)) end
    if target.k == "q" then
        local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(target.id)
        return title or L["Quest #%d"]:format(target.id)
    end
    if target.k == "r" then return ctx.recipeName(target.id) or ("#" .. target.id) end
    return ctx.itemName(target.id)
end

function UI.targetIcon(ctx, target)
    if target.k == "i" then return ctx.itemIcon(target.id) end
    if target.k == "q" then return "Interface\\GossipFrame\\AvailableQuestIcon" end
    if target.k == "r" then return "Interface\\Icons\\INV_Scroll_03" end
    if target.k == "f" then return events.byCategory.rep.icon end
    return "Interface\\Icons\\INV_Misc_Note_01"
end

function UI.targetTooltip(owner, ctx, target)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if target.k == "i" then
        GameTooltip:SetHyperlink("item:" .. target.id)
    elseif target.k == "q" then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. target.id)
        if not ok or GameTooltip:NumLines() == 0 then GameTooltip:SetText(UI.targetName(ctx, target)) end
    elseif target.k == "r" and ctx.recipeTooltip then
        ctx.recipeTooltip(target.id)
    else
        GameTooltip:SetText(UI.targetName(ctx, target), 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- Collects every visible event (new format, migrated dungeon dates, partner events).
function UI.collect(ctx)
    local now, guild, list = ctx.clock(), ctx.guild(), {}
    if not guild then return list end
    local function eligible(name) return ctx.isMember(name) end
    local shownLegacy = {}
    for id, ev in pairs(events.all(guild)) do
        if not ev.stub and (ctx.isMember(ev.owner) or ev.owner == ctx.player()) and not ctx.hidden(ev) then
            ev.id, ev.kind = id, "event"
            ev.rosterCache = events.roster(ev, eligible)
            ev.freeCount = events.free(ev, ev.rosterCache.counts)
            list[#list + 1] = ev
            shownLegacy[id] = true
        end
    end
    for _, ev in ipairs(ctx.legacy()) do
        local id = events.id(ev.owner, ev.token)
        if not shownLegacy[id] and not ctx.hidden(ev) then
            ev.id, ev.kind = "legacy:" .. id, "legacy"
            ev.rosterCache = events.roster(ev, eligible)
            ev.freeCount = events.free(ev, ev.rosterCache.counts)
            list[#list + 1] = ev
        end
    end
    if UI.setting("partners") then
        for _, ev in ipairs(ctx.partnerEvents()) do
            ev.kind = "partner"
            ev.rosterCache = events.roster(ev)
            ev.freeCount = 0
            list[#list + 1] = ev
        end
    end
    for _, ev in ipairs(list) do
        ev.stateCache = ev.legacy and (ev.status == "cancelled" and "cancelled" or (now >= ev.starts + 2 * 3600 and "expired" or "open"))
            or events.state(ev, now, ev.rosterCache.counts)
        if ev.kind == "partner" then ev.stateCache = now >= ev.starts + 2 * 3600 and "expired" or (ev.status == "open" and "open" or "closed") end
    end
    UI.cache = list
    return list
end

function UI.isActive(ev, now)
    local state = ev.stateCache
    if state == "cancelled" or state == "done" or state == "expired" then return false end
    if state == "started" then return now < events.ends(ev) + 6 * 3600 end
    return true
end

-- Own status in an event: entry from the roster, or "organizer".
function UI.myStatus(ctx, ev)
    local me = ctx.player()
    if ev.owner == me then return "organizer" end
    for _, entry in ipairs(ev.rosterCache and ev.rosterCache.entries or {}) do
        if entry.name == me then return entry.status, entry end
    end
end

-- "Still looking for one healer and two damage dealers."
function UI.missingText(ev)
    if ev.model == "open" then return L["Everyone is welcome."] end
    local counts = ev.rosterCache.counts
    if counts.full then return L["The group is complete."] end
    if ev.slots then
        local parts = {}
        for _, role in ipairs({ "T", "H", "D" }) do
            local free = events.free(ev, counts, role)
            if free == 1 then parts[#parts + 1] = L["ROLE_ONE_" .. role]
            elseif free > 1 then parts[#parts + 1] = L["ROLE_MANY_" .. role]:format(free) end
        end
        return L["Still looking for %s."]:format(table.concat(parts, L[" and "]))
    end
    local free = events.free(ev, counts)
    return free == 1 and L["One more place free."] or L["%d more places free."]:format(free)
end

-- Notifications -------------------------------------------------------------------------------------
local toast, queue = nil, {}
local NOTE_TEXT = {
    new = "New event: %s", signup = "New sign-up: %s", withdrawn = "%s has withdrawn",
    confirmed = "Your sign-up was confirmed", rejected = "Your sign-up was declined",
    waitlist = "You are on the waitlist", promoted = "A place became free – you are in!",
    moved = "The date has changed", cancelled = "The event was cancelled", started = "The event has started",
    loot = "The loot agreement has changed", soon = "%s",
}

local function showNext(ctx)
    if not toast or toast:IsShown() or #queue == 0 then return end
    if InCombatLockdown and InCombatLockdown() and not UI.setting("combat") then
        C_Timer.After(5, function() showNext(ctx) end)
        return
    end
    local entry = table.remove(queue, 1)
    toast.entry = entry
    toast.headline:SetText(entry.title)
    toast.name:SetText(entry.name or "")
    toast.info:SetText(entry.info or "")
    toast.icon:SetTexture(entry.icon or ctx.icon)
    toast.open:SetShown(entry.id ~= nil or entry.open ~= nil)
    toast.open:SetText(entry.openLabel or L["Open event"])
    toast:Show()
    toast.serial = (toast.serial or 0) + 1
    local serial = toast.serial
    C_Timer.After(16, function()
        if toast.serial == serial and toast:IsShown() and not toast:IsMouseOver() then
            toast:Hide()
            showNext(ctx)
        end
    end)
end

local function buildToast(ctx)
    if toast then return end
    toast = CreateFrame("Frame", "ForeverGuildEventNotice", UIParent, "BackdropTemplate")
    toast:SetSize(360, 150)
    toast:SetPoint("TOP", 0, -150)
    toast:SetFrameStrata("DIALOG")
    toast:SetClampedToScreen(true)
    -- Fully opaque and catches the mouse, so nothing behind it can be clicked.
    local base = toast:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetPoint("TOPLEFT", 5, -5)
    base:SetPoint("BOTTOMRIGHT", -5, 5)
    base:SetColorTexture(.075, .055, .04, 1)
    toast:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    toast:EnableMouse(true)
    toast:Hide()
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(36, 36)
    toast.icon:SetPoint("TOPLEFT", 17, -17)
    toast.icon:SetTexCoord(.06, .94, .06, .94)
    local brand = text(toast, "GameFontDisableSmall")
    brand:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 10, 0)
    brand:SetText(L["ForeverGuild · Groups & events"])
    toast.headline = text(toast, "GameFontNormal", "LEFT", true)
    toast.headline:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3)
    toast.headline:SetPoint("RIGHT", -16, 0)
    toast.name = text(toast, "GameFontHighlight")
    toast.name:SetPoint("TOPLEFT", 17, -64)
    toast.name:SetPoint("RIGHT", -16, 0)
    toast.info = text(toast, "GameFontHighlightSmall", "LEFT", true)
    toast.info:SetPoint("TOPLEFT", toast.name, "BOTTOMLEFT", 0, -4)
    toast.info:SetPoint("RIGHT", -16, 0)
    color(toast.info, { .85, .77, .63 })
    local close = ctx.button(toast, L["Close"], 96, 0, 0, function()
        toast:Hide()
        showNext(ctx)
    end)
    close:ClearAllPoints()
    close:SetPoint("BOTTOMRIGHT", -15, 13)
    toast.open = ctx.button(toast, L["Open event"], 120, 0, 0, function()
        local entry = toast.entry
        toast:Hide()
        if entry and entry.open then entry.open() elseif entry and entry.id then ctx.openEvent(entry.id) end
        showNext(ctx)
    end)
    toast.open:ClearAllPoints()
    toast.open:SetPoint("BOTTOMLEFT", 15, 13)
end

-- Generic pop-up for other ForeverGuild modules (e.g. guild bank requests).
function UI.pushToast(ctx, entry)
    buildToast(ctx)
    queue[#queue + 1] = entry
    while #queue > 6 do table.remove(queue, 1) end
    showNext(ctx)
end

function UI.notify(ctx, code, ev, member, key)
    local guild, now = ctx.guild(), ctx.clock()
    if not guild or not events.once(guild, key, now) then return end
    if code == "new" and (not UI.setting("match") or not UI.preferredCategory(ev.cat)) then return end
    local title = L[NOTE_TEXT[code] or "%s"]
    if code == "new" then title = title:format(UI.categoryLabel(ev))
    elseif code == "signup" or code == "withdrawn" then title = title:format(ctx.displayName(member)) end
    local name = UI.titleOf(ev)
    local roster = ev.rosterCache or events.roster(ev)
    local capacity = roster.counts.capacity
    local info = UI.when(ev.starts, now) .. "  ·  " .. L["Organizer: %s"]:format(ctx.displayName(ev.owner))
    if capacity then info = info .. "\n" .. L["Participants: %d/%d"]:format(roster.counts.total, capacity) end
    if code == "soon" then title = member end
    if UI.setting("chat") then
        print(("|cffffd100ForeverGuild|r · %s – %s (%s)"):format(title, name, UI.when(ev.starts, now)))
    end
    if UI.setting("sound") and PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then pcall(PlaySound, SOUNDKIT.TELL_MESSAGE) end
    if UI.setting("popup") then
        buildToast(ctx)
        queue[#queue + 1] = { title = title, name = name, info = info, id = events.id(ev.owner, ev.token),
            icon = (events.byCategory[ev.cat] or events.byCategory.other).icon }
        while #queue > 6 do table.remove(queue, 1) end
        showNext(ctx)
    end
end

-- Called by the message handler with the notifications of Events.receive.
function UI.received(ctx, notes)
    local me, now = ctx.player(), ctx.clock()
    for _, note in ipairs(notes or {}) do
        local ev = note.ev
        local key = ("%s:%s:%s:%s"):format(note.code, events.id(ev.owner, ev.token), note.member or "", tostring(note.rev))
        if note.code == "new" then
            if ev.owner ~= me and events.active(ev, now) and ctx.isMember(ev.owner) and not ctx.hidden(ev) then
                local level = ctx.myLevel()
                local fits = not ((ev.minLevel and level < ev.minLevel) or (ev.maxLevel and level > ev.maxLevel))
                if fits or not UI.setting("fitsOnly") then UI.notify(ctx, "new", ev, nil, "new:" .. events.id(ev.owner, ev.token)) end
            end
        elseif note.code == "signup" or note.code == "withdrawn" then
            if events.mayManage(ev, me) then
                if not ev.approve and note.code == "signup" then UI.reconcileAndSend(ctx, ev) end
                if note.code == "withdrawn" then UI.reconcileAndSend(ctx, ev) end
                UI.notify(ctx, note.code, ev, note.member, key)
            end
        else
            UI.notify(ctx, note.code, ev, nil, key)
        end
    end
    UI.refresh()
end

-- Organizer: apply automatic decisions and send them right away.
function UI.reconcileAndSend(ctx, ev)
    local changed = events.reconcile(ev, ctx.clock())
    for _, change in ipairs(changed) do
        if ctx.send(events.decisionPacket(ev, change.name, change.decision)) then change.decision.pending = nil end
    end
end

local sessionAsked = false
function UI.tick(ctx)
    local guild, me, now = ctx.guild(), ctx.player(), ctx.clock()
    if not guild or not ctx.ready() then return end
    if not sessionAsked then
        sessionAsked = true
        ctx.send("EQ")
    end
    for _, ev in pairs(events.all(guild)) do
        if not ev.stub and events.mayManage(ev, me) and events.active(ev, now) then
            local changed = events.reconcile(ev, now)
            if #changed > 0 then ev.nextShare = 0 end
        end
    end
    local keep = math.max(7, UI.setting("keepDays"))
    events.tick(guild, me, now, ctx.send, keep)
    for _, reminder in ipairs(events.dueReminders(guild, me, now, UI.reminderOffsets())) do
        local ev = reminder.ev
        local textValue
        if reminder.offset == 0 then textValue = L["Your %s starts now!"]:format(UI.categoryLabel(ev))
        elseif reminder.offset >= 60 then
            textValue = L["Your %s starts in %s!"]:format(UI.categoryLabel(ev), UI.duration(reminder.offset))
        else
            textValue = L["Your %s starts in %d minutes!"]:format(UI.categoryLabel(ev), reminder.offset)
        end
        UI.notify(ctx, "soon", ev, textValue, reminder.key)
    end
    UI.updateBadge(ctx)
end

-- Badge: new events since the last visit and open actions (pending sign-ups to confirm,
-- loot agreements to confirm again). Each event counts once.
function UI.badgeCount(ctx)
    local guild, me, now = ctx.guild(), ctx.player(), ctx.clock()
    if not guild or not UI.setting("counters") then return 0 end
    local store, keys = events.store(guild), {}
    for id, ev in pairs(store.events) do
        if not ev.stub and events.active(ev, now) and ctx.isMember(ev.owner) then
            if ev.owner ~= me and not store.read[id] and UI.preferredCategory(ev.cat) and (ev.created or 0) > now - 3 * DAY then
                keys[id] = true
            end
            if events.mayManage(ev, me) and ev.approve then
                local roster = events.roster(ev)
                if roster.counts.pending > 0 then keys[id] = true end
            end
            local mine = ev.signups[me]
            if mine and mine.state ~= "out" and ev.loot and (mine.lootAck or 0) < (ev.lootRev or 0) then keys[id] = true end
        end
    end
    local count = 0
    for _ in pairs(keys) do count = count + 1 end
    return count
end

function UI.updateBadge(ctx)
    local tab = ctx.boardTab()
    if not tab then return end
    if not tab.eventBadge then
        local badge = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badge:SetPoint("BOTTOMRIGHT", -2, 3)
        badge:SetTextColor(.55, .88, .60)
        tab.eventBadge = badge
    end
    local count = UI.badgeCount(ctx)
    tab.eventBadge:SetText(count > 99 and "99+" or tostring(count))
    tab.eventBadge:SetShown(count > 0)
end

function UI.markRead(ctx, ev)
    local guild = ctx.guild()
    if guild and ev and ev.kind == "event" then
        events.store(guild).read[ev.id] = ctx.clock()
        UI.updateBadge(ctx)
    end
end

-- Actions -----------------------------------------------------------------------------------------------
function UI.sendEvent(ctx, ev)
    events.flush(ev, ctx.send)
    UI.refresh()
end

function UI.sendSignup(ctx, ev, signup)
    if ctx.send(events.signupPacket(ev, signup)) then signup.nextShare = ctx.clock() + events.SIGNUP_SHARE_EVERY end
    UI.refresh()
end

function UI.decide(ctx, ev, member, code, role)
    local decision = events.decide(ev, member, code, role, ctx.clock())
    if decision and ctx.send(events.decisionPacket(ev, member, decision)) then decision.pending = nil end
    UI.refresh()
end

-- Prepared chat text with the event information.
function UI.messageText(ctx, ev)
    local roster = ev.rosterCache or events.roster(ev)
    local parts = { ("[%s] %s – %s"):format(UI.categoryLabel(ev), UI.titleOf(ev), UI.when(ev.starts, ctx.clock())) }
    if ev.place then parts[#parts + 1] = L["Meeting point: %s"]:format(ev.place) end
    if roster.counts.capacity then parts[#parts + 1] = L["Participants: %d/%d"]:format(roster.counts.total, roster.counts.capacity) end
    if ev.model ~= "open" and not roster.counts.full then parts[#parts + 1] = UI.missingText(ev) end
    parts[#parts + 1] = L["Sign up in ForeverGuild under Groups & events."]
    local message = table.concat(parts, " · ")
    if #message > 250 then message = message:sub(1, 247) .. "..." end
    return message
end

local confirmFrame
function UI.confirm(ctx, title, body, accept, labels, second)
    if not confirmFrame then
        local frame = CreateFrame("Frame", "ForeverGuildEventConfirm", UIParent, "BackdropTemplate")
        confirmFrame = frame
        frame:SetSize(420, 170)
        frame:SetPoint("CENTER", 0, 80)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetToplevel(true)
        frame:EnableMouse(true)
        frame:SetClampedToScreen(true)
        local base = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        base:SetPoint("TOPLEFT", 5, -5)
        base:SetPoint("BOTTOMRIGHT", -5, 5)
        base:SetColorTexture(.075, .055, .04, 1)
        frame:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        frame.title = text(frame, "GameFontNormalLarge", "CENTER")
        frame.title:SetPoint("TOP", 0, -20)
        frame.title:SetPoint("LEFT", 18, 0)
        frame.title:SetPoint("RIGHT", -18, 0)
        frame.body = text(frame, "GameFontHighlight", "CENTER", true)
        frame.body:SetPoint("TOPLEFT", 22, -50)
        frame.body:SetPoint("RIGHT", -22, 0)
        frame.cancel = ctx.button(frame, L["Cancel"], 110, 0, 0, function() frame:Hide() end)
        frame.cancel:ClearAllPoints()
        frame.cancel:SetPoint("BOTTOMLEFT", 18, 16)
        frame.ok = ctx.button(frame, "", 130, 0, 0, function() frame:Hide(); if frame.accept then frame.accept(1) end end)
        frame.ok:ClearAllPoints()
        frame.ok:SetPoint("BOTTOMRIGHT", -18, 16)
        frame.alt = ctx.button(frame, "", 130, 0, 0, function() frame:Hide(); if frame.accept then frame.accept(2) end end)
        frame.alt:ClearAllPoints()
        frame.alt:SetPoint("RIGHT", frame.ok, "LEFT", -8, 0)
        tinsert(UISpecialFrames, "ForeverGuildEventConfirm")
    end
    confirmFrame.title:SetText(title)
    confirmFrame.body:SetText(body or "")
    confirmFrame.ok:SetText(labels or L["Confirm"])
    confirmFrame.alt:SetShown(second ~= nil)
    if second then confirmFrame.alt:SetText(second) end
    confirmFrame.accept = accept
    confirmFrame:SetHeight(math.max(150, confirmFrame.body:GetStringHeight() + 110))
    confirmFrame:Show()
    confirmFrame:Raise()
end

local messageFrame
function UI.showMessage(ctx, ev)
    if not messageFrame then
        local frame = CreateFrame("Frame", "ForeverGuildEventMessage", UIParent, "BackdropTemplate")
        messageFrame = frame
        frame:SetSize(520, 176)
        frame:SetPoint("CENTER", 0, 120)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetToplevel(true)
        frame:EnableMouse(true)
        local base = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        base:SetPoint("TOPLEFT", 5, -5)
        base:SetPoint("BOTTOMRIGHT", -5, 5)
        base:SetColorTexture(.075, .055, .04, 1)
        frame:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        local title = text(frame, "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 20, -20)
        title:SetText(L["Message with event details"])
        local hint = text(frame, "GameFontHighlightSmall", "LEFT", true)
        hint:SetPoint("TOPLEFT", 20, -44)
        hint:SetPoint("RIGHT", -20, 0)
        hint:SetText(L["Copy the text with Ctrl+C or post it in the guild chat with one click."])
        frame.box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        frame.box:SetPoint("TOPLEFT", 26, -78)
        frame.box:SetPoint("RIGHT", -22, 0)
        frame.box:SetHeight(26)
        frame.box:SetAutoFocus(false)
        frame.box:SetMaxBytes(255)
        frame.box:SetScript("OnEscapePressed", function() frame:Hide() end)
        local close = ctx.button(frame, L["Close"], 110, 0, 0, function() frame:Hide() end)
        close:ClearAllPoints()
        close:SetPoint("BOTTOMLEFT", 18, 16)
        frame.post = ctx.button(frame, L["Post in guild chat"], 180, 0, 0, function()
            local message = frame.box:GetText()
            if message ~= "" and IsInGuild and IsInGuild() then
                local sender = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
                pcall(sender, message, "GUILD")
                frame:Hide()
            end
        end)
        frame.post:ClearAllPoints()
        frame.post:SetPoint("BOTTOMRIGHT", -18, 16)
        tinsert(UISpecialFrames, "ForeverGuildEventMessage")
    end
    messageFrame.box:SetText(UI.messageText(ctx, ev))
    messageFrame:Show()
    messageFrame.box:SetFocus()
    messageFrame.box:HighlightText()
end

-- Event card ----------------------------------------------------------------------------------------------
local CARD_HEIGHT = 112
local ICONS_CREATE = "Interface\\Icons\\INV_Misc_Note_06"

local function progressBar(parent)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetHeight(14)
    holder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 9, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    holder:SetBackdropColor(.03, .02, .015, .9)
    holder:SetBackdropBorderColor(.62, .47, .26)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("TOPLEFT", 3, -3)
    bar:SetPoint("BOTTOMRIGHT", -3, 3)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(.83, .62, .22)
    bar:SetMinMaxValues(0, 1)
    holder.bar = bar
    holder.label = text(holder, "GameFontHighlightSmall", "CENTER")
    holder.label:SetPoint("CENTER", 0, 0)
    holder.label:SetFontObject(GameFontHighlightSmall)
    return holder
end
UI.progressBar = progressBar

function UI.card(parent, ctx, onSelect, onSignup)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetHeight(CARD_HEIGHT)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    card:SetBackdropColor(.06, .04, .028, 1)
    card:SetBackdropBorderColor(.55, .39, .2)
    card.art = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    card.art:SetPoint("TOPLEFT", 3, -3)
    card.art:SetPoint("BOTTOMRIGHT", -3, 3)
    card.art:SetAlpha(.62)
    card.shade = card:CreateTexture(nil, "BACKGROUND", nil, 2)
    card.shade:SetAllPoints(card.art)
    card.shade:SetColorTexture(1, 1, 1, 1)
    card.shade:SetGradient("HORIZONTAL", CreateColor(.04, .03, .02, .97), CreateColor(.04, .03, .02, .35))
    card.selected = card:CreateTexture(nil, "BORDER")
    card.selected:SetAllPoints(card.art)
    card.selected:SetColorTexture(.95, .7, .25, .14)
    card:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    card:GetHighlightTexture():SetAlpha(.25)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(34, 34)
    card.icon:SetPoint("TOPLEFT", 11, -11)
    card.icon:SetTexCoord(.07, .93, .07, .93)
    card.title = text(card, "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, 1)
    card.title:SetPoint("RIGHT", -150, 0)
    card.kind = text(card, "GameFontNormalSmall", "RIGHT")
    card.kind:SetPoint("TOPRIGHT", -12, -12)
    card.kind:SetWidth(140)
    card.level = text(card, "GameFontHighlightSmall", "RIGHT")
    card.level:SetPoint("TOPRIGHT", card.kind, "BOTTOMRIGHT", 0, -3)
    card.level:SetWidth(140)
    card.when = text(card, "GameFontHighlight")
    card.when:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
    card.when:SetPoint("RIGHT", -150, 0)
    card.organizer = text(card, "GameFontHighlightSmall")
    card.organizer:SetPoint("TOPLEFT", card.when, "BOTTOMLEFT", 0, -3)
    card.organizer:SetPoint("RIGHT", -150, 0)
    color(card.organizer, { .85, .77, .63 })
    card.roles = {}
    for index, role in ipairs({ "T", "H", "D" }) do
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("BOTTOMLEFT", 12 + (index - 1) * 74, 33)
        UI.roleIcon(icon, role)
        local label = text(card, "GameFontHighlightSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        card.roles[role] = { icon = icon, label = label }
    end
    card.progress = progressBar(card)
    card.progress:SetPoint("BOTTOMLEFT", 238, 35)
    card.progress:SetPoint("RIGHT", -150, 0)
    card.status = text(card, "GameFontHighlightSmall")
    card.status:SetPoint("BOTTOMLEFT", 12, 13)
    card.status:SetPoint("RIGHT", -230, 0)
    card.badge = text(card, "GameFontNormalSmall", "RIGHT")
    card.badge:SetPoint("BOTTOMRIGHT", -12, 64)
    card.badge:SetWidth(140)
    card.details = ctx.button(card, L["Details"], 96, 0, 0, function(self) onSelect(self:GetParent().ev) end)
    card.details:ClearAllPoints()
    card.details:SetPoint("BOTTOMRIGHT", -112, 9)
    card.signup = ctx.button(card, L["Sign up"], 96, 0, 0, function(self) onSignup(self:GetParent().ev) end)
    card.signup:ClearAllPoints()
    card.signup:SetPoint("BOTTOMRIGHT", -10, 9)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" and self.ev and self.ev.id then UI.eventMenu(ctx, self.ev, self) else onSelect(self.ev) end
    end)
    card:SetScript("OnSizeChanged", function(self, width, height)
        if self.aspect then UI.fitArt(self.art, self.aspect, width - 6, height - 6) end
    end)
    return card
end

function UI.fillCard(card, ev, ctx, selected)
    local now = ctx.clock()
    card.ev = ev
    local art, aspect = UI.banner(ev)
    card.art:SetTexture(art)
    card.aspect = aspect
    UI.fitArt(card.art, aspect, card:GetWidth() - 6, card:GetHeight() - 6)
    card.selected:SetShown(selected)
    card:SetBackdropBorderColor(selected and 1 or .55, selected and .78 or .39, selected and .35 or .2)
    card.icon:SetTexture((events.byCategory[ev.cat] or events.byCategory.other).icon)
    card.title:SetText(UI.titleOf(ev))
    local kind = UI.categoryLabel(ev)
    if ev.mode == "now" then kind = L["Spontaneous"] .. " · " .. kind end
    card.kind:SetText(kind)
    card.level:SetText(UI.levelText(ev) or "")
    local whenText = ev.mode == "now" and now < ev.starts + 60 and L["Start: now"] or UI.when(ev.starts, now)
    card.when:SetText(whenText)
    local organizer = L["Organizer: %s"]:format(ctx.displayName(ev.owner))
    if ev.partnerGuild then organizer = organizer .. "  ·  " .. ev.partnerGuild end
    if ev.place then organizer = organizer .. "  ·  " .. ev.place end
    if ev.targets and ev.targets[1] and not ev.dungeon then organizer = UI.targetName(ctx, ev.targets[1]) .. "  ·  " .. organizer end
    card.organizer:SetText(organizer)
    local counts = ev.rosterCache.counts
    for _, role in ipairs({ "T", "H", "D" }) do
        local widget = card.roles[role]
        local shown = ev.slots ~= nil and ev.slots[role] > 0
        widget.icon:SetShown(shown)
        widget.label:SetShown(shown)
        if shown then
            widget.label:SetText(("%d/%d"):format(math.min(counts[role], ev.slots[role]), ev.slots[role]))
            color(widget.label, counts[role] >= ev.slots[role] and GREEN or GOLD)
        end
    end
    local capacity = counts.capacity
    card.progress:ClearAllPoints()
    card.progress:SetPoint("BOTTOMLEFT", ev.slots and 238 or 12, 35)
    card.progress:SetPoint("RIGHT", -150, 0)
    card.progress:SetShown(ev.kind ~= "partner")
    if capacity and capacity > 0 then
        card.progress.bar:SetValue(math.min(1, counts.total / capacity))
        card.progress.label:SetText(L["Participants %d/%d"]:format(counts.total, capacity))
    else
        card.progress.bar:SetValue(1)
        card.progress.label:SetText(L["%d participants"]:format(counts.total))
    end
    local state = ev.stateCache
    local status, entry = UI.myStatus(ctx, ev)
    local line
    if ev.kind == "partner" then line = L["Partner guild event – whisper the organizer to take part."]
    elseif state == "open" then line = UI.missingText(ev)
    else line = L[STATE_LABELS[state] or "Sign-up open"] end
    if ev.loot and ev.loot.rule ~= "need" then line = line .. "   |cffffd36c" .. L[LOOT_LABELS[ev.loot.rule]] .. "|r" end
    card.status:SetText(line)
    color(card.status, (state == "open" or state == "ready") and LIGHT or (STATE_COLORS[state] or LIGHT))
    if status == "organizer" then
        card.badge:SetText(L["Your event"])
        color(card.badge, GOLD)
    elseif status then
        card.badge:SetText(L[STATUS_LABELS[status]] .. ((entry and not entry.synced and status == "signed") and (" · " .. L["not yet confirmed"]) or ""))
        color(card.badge, STATUS_COLORS[status] or LIGHT)
    else
        card.badge:SetText(state ~= "open" and L[STATE_LABELS[state]] or "")
        color(card.badge, STATE_COLORS[state] or LIGHT)
    end
    local canSign = ev.kind ~= "partner" and status ~= "organizer" and (state == "open" or state == "full" or state == "ready")
        and (not status or status == "out")
    card.signup:SetShown(canSign)
    card.signup:SetEnabled(ctx.ready())
end

-- Main view -------------------------------------------------------------------------------------------------
local view

local function sectionOf(ev, now)
    local today = UI.dayStart(now)
    if ev.mode == "now" then return 1 end
    if ev.starts < today + DAY then return 2 end
    if ev.starts < today + 8 * DAY then return 3 end
    return 4
end
local SECTION_TITLES = { "SPONTANEOUS GROUPS", "TODAY", "THE NEXT DAYS", "LATER" }

function UI.build(page, ctx)
    view = CreateFrame("Frame", nil, page)
    view.ctx = ctx
    view:SetPoint("TOPLEFT", 17, -48)
    view:SetPoint("BOTTOMRIGHT", -17, 15)
    view.tab = UI.setting("view") == "calendar" and "calendar" or "overview"
    view.filters = { cat = "all", period = "all", sort = "start", fits = UI.setting("fitsOnly") }

    -- Internal tabs ---------------------------------------------------------------------------------------
    local tabs = {}
    view.tabs = tabs
    local tabBar = CreateFrame("Frame", nil, view)
    tabBar:SetPoint("TOPLEFT", 0, 0)
    tabBar:SetSize(640, 30)
    view.tabBar = tabBar
    for _, entry in ipairs({ { "overview", "Overview" }, { "calendar", "Calendar" }, { "mine", "My sign-ups" },
        { "organized", "My events" }, { "history", "History" } }) do
        local tab = CreateFrame("Button", nil, tabBar)
        tab:SetHeight(28)
        tab.background = tab:CreateTexture(nil, "BACKGROUND")
        tab.background:SetAllPoints()
        tab:SetHighlightTexture(ART .. "BoardHeaderTabActive")
        tab:GetHighlightTexture():SetAlpha(.2)
        tab.label = text(tab, "GameFontNormal", "CENTER")
        tab.label:SetPoint("LEFT", 6, -1)
        tab.label:SetPoint("RIGHT", -6, -1)
        tab.label:SetText(L[entry[2]])
        tab.key = entry[1]
        tab:SetScript("OnClick", function() view.tab = entry[1]; UI.refresh() end)
        tabs[#tabs + 1] = tab
    end
    -- Each tab as wide as its caption, so no label is cut off.
    local x = 0
    for _, tab in ipairs(tabs) do
        local tabWidth = math.max(96, math.ceil(tab.label:GetStringWidth()) + 30)
        tab:SetWidth(tabWidth)
        tab:SetPoint("TOPLEFT", x, 0)
        x = x + tabWidth + 2
    end
    tabBar:SetWidth(x)
    view.create = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.create:SetSize(230, 30)
    view.create:SetPoint("TOPRIGHT", 0, 1)
    view.create:SetText("+  " .. L["Create group or event"])
    view.create:SetNormalFontObject(GameFontNormal)
    view.create:SetScript("OnClick", function() UI.openWizard(ctx, {}) end)
    UI.tooltip(view.create, L["Create group or event"], L["Spontaneous group search or planned date – for dungeons, raids, quests, farming and more."])

    -- Filter bar ----------------------------------------------------------------------------------------------
    local filterBar = ctx.contrastPanel(view)
    view.filterBar = filterBar
    filterBar:SetPoint("TOPLEFT", 0, -34)
    filterBar:SetPoint("TOPRIGHT", 0, -34)
    filterBar:SetHeight(40)
    local search = CreateFrame("EditBox", nil, filterBar, "SearchBoxTemplate")
    search:SetSize(190, 22)
    search:SetPoint("LEFT", 14, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:HookScript("OnTextChanged", function(self)
        view.filters.text = self:GetText()
        if view.searchTimer then view.searchTimer:Cancel() end
        view.searchTimer = C_Timer.NewTimer(.25, function() UI.refresh() end)
    end)
    if type(search.Instructions) == "table" then search.Instructions:SetText(L["Search activity..."]) end
    view.search = search
    local dropdown = addon.recipeFinder.widgets.dropdown
    local categoryOptions = function()
        local list = { { "all", L["All activities"] } }
        for _, category in ipairs(events.categories) do list[#list + 1] = { category.key, L[category.label] } end
        return list
    end
    view.catDrop = dropdown(filterBar, 150, categoryOptions, function() return view.filters.cat end,
        function(value) view.filters.cat = value; UI.refresh() end)
    view.catDrop:SetPoint("LEFT", search, "RIGHT", 10, 0)
    view.periodDrop = dropdown(filterBar, 140, function()
        return { { "all", L["Any time"] }, { "today", L["Today"] }, { "tomorrow", L["Tomorrow"] },
            { "week", L["This week"] } }
    end, function() return view.filters.period end, function(value) view.filters.period = value; UI.refresh() end)
    view.periodDrop:SetPoint("LEFT", view.catDrop, "RIGHT", 8, 0)
    -- Further filters and sorting in one menu.
    local more = CreateFrame("DropdownButton", nil, filterBar, "WowStyle1DropdownTemplate")
    more:SetWidth(140)
    more:SetPoint("LEFT", view.periodDrop, "RIGHT", 8, 0)
    if more.SetDefaultText then more:SetDefaultText(L["More filters"]) end
    more:SetupMenu(function(_, root)
        local f = view.filters
        local function radio(label, key, value)
            root:CreateRadio(label, function() return f[key] == value end, function() f[key] = value; UI.refresh() end)
        end
        menuTitle(root, L["Places"])
        radio(L["All"], "status", nil); radio(L["Open places"], "status", "open")
        radio(L["Complete"], "status", "full"); radio(L["With waitlist"], "status", "waitlist")
        menuTitle(root, L["Role"])
        radio(L["Any role"], "role", nil)
        for _, role in ipairs({ "T", "H", "D" }) do radio(L[ROLE_NAMES[role]], "role", role) end
        menuTitle(root, L["Sign-up"])
        radio(L["All"], "mine", nil); radio(L["Signed up"], "mine", "in"); radio(L["Not signed up"], "mine", "notin")
        menuTitle(root, L["Guild"])
        radio(L["All"], "guild", nil); radio(L["Own guild"], "guild", "own"); radio(L["Partner guilds"], "guild", "partner")
        menuTitle(root, L["Organizer"])
        radio(L["All"], "organizer", nil)
        local owners, seen = {}, {}
        for _, ev in ipairs(UI.cache or {}) do
            if not seen[ev.owner] then seen[ev.owner] = true; owners[#owners + 1] = ev.owner end
        end
        table.sort(owners)
        for _, owner in ipairs(owners) do radio(ctx.displayName(owner), "organizer", owner) end
        menuTitle(root, L["Sort by"])
        radio(L["Start time"], "sort", "start"); radio(L["Creation date"], "sort", "created")
        radio(L["Free places"], "sort", "free"); radio(L["Activity type"], "sort", "category")
    end)
    view.more = more
    local fits = CreateFrame("CheckButton", nil, filterBar, "UICheckButtonTemplate")
    fits:SetSize(24, 24)
    fits:SetPoint("LEFT", more, "RIGHT", 10, 0)
    fits:SetChecked(view.filters.fits)
    fits:SetScript("OnClick", function(self) view.filters.fits = self:GetChecked() and true or false; UI.refresh() end)
    local fitsLabel = text(fits, "GameFontHighlightSmall")
    fitsLabel:SetPoint("LEFT", fits, "RIGHT", 2, 0)
    fitsLabel:SetText(L["Suits my character"])
    UI.tooltip(fits, L["Suits my character"], L["Only events whose level range fits your character and that still have a place for one of your roles."])
    view.fits = fits
    local reset = ctx.button(filterBar, L["Reset filters"], 128, 0, 0, function()
        view.filters = { cat = "all", period = "all", sort = "start", fits = false }
        search:SetText("")
        fits:SetChecked(false)
        view.catDrop.Sync(); view.periodDrop.Sync()
        UI.refresh()
    end)
    reset:ClearAllPoints()
    reset:SetPoint("RIGHT", -10, 0)
    view.reset = reset

    -- Body: card list left, details right ----------------------------------------------------------------
    local listPanel = ctx.contrastPanel(view)
    view.listPanel = listPanel
    listPanel:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)
    listPanel:SetPoint("BOTTOM", 0, 0)
    listPanel:SetWidth(560)
    local scroll = CreateFrame("ScrollFrame", nil, listPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(500, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    view.scroll, view.content, view.cards, view.headers = scroll, content, {}, {}
    view.empty = text(content, "GameFontDisable", "CENTER", true)
    view.empty:SetPoint("TOPLEFT", 20, -40)
    view.empty:SetPoint("RIGHT", -20, 0)

    view.detail = UI.buildDetail(view, ctx)
    view.detail:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", 6, 0)
    view.detail:SetPoint("BOTTOMRIGHT", 0, 0)
    view.calendar = UI.buildCalendar(view, ctx)
    view.calendar:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 0, 0)
    view.calendar:SetPoint("BOTTOMRIGHT", 0, 0)
    view:SetScript("OnSizeChanged", function(_, width)
        listPanel:SetWidth(math.max(470, math.floor(width * .56)))
    end)
    view:SetScript("OnShow", function() UI.refresh() end)
    view:SetScript("OnHide", function() UI.closeMenu() end)
    return view
end

function UI.tooltip(control, title, detail)
    control:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if detail then GameTooltip:AddLine(detail, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function inTab(ev, tab, ctx, now)
    local guild = ctx.guild()
    local archived = guild and events.store(guild).archived[ev.id]
    if archived then return tab == "history" end
    local active = UI.isActive(ev, now)
    if tab == "overview" or tab == "calendar" then return active end
    if tab == "mine" then
        local status = UI.myStatus(ctx, ev)
        return status ~= nil and status ~= "organizer" and status ~= "out" and active
    end
    if tab == "organized" then return events.mayManage(ev, ctx.player()) and (active or ev.stateCache == "started") end
    if tab == "history" then return not active end
end

-- Used by the tour: only switches the visible tab, nothing is created or sent.
function UI.showTab(tab)
    if not view then return end
    view.tab = tab
    if view:IsVisible() then UI.render() end
end

function UI.select(id)
    if not view then return end
    view.selection = id
    view.tab = "overview"
    for _, ev in ipairs(UI.cache or UI.collect(view.ctx)) do
        if ev.id == id and not UI.isActive(ev, view.ctx.clock()) then view.tab = "history" end
    end
    UI.refresh()
end

local refreshQueued = false
function UI.refresh()
    if not view or not view:IsVisible() or refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if view and view:IsVisible() then UI.render() end
    end)
end

function UI.render()
    local ctx = view.ctx
    local now = ctx.clock()
    local all = UI.collect(ctx)
    for _, tab in ipairs(view.tabs) do
        local active = tab.key == view.tab
        tab.background:SetTexture(ART .. "BoardHeaderTab" .. (active and "Active" or "Idle"))
        if active then tab.label:SetTextColor(1, .85, .5) else tab.label:SetTextColor(.83, .74, .61) end
    end
    view.create:SetShown(ctx.canPost())
    view.create:SetEnabled(ctx.ready())
    local calendar = view.tab == "calendar"
    view.filterBar:SetShown(not calendar)
    view.listPanel:SetShown(not calendar)
    view.detail:SetShown(not calendar)
    view.calendar:SetShown(calendar)
    if calendar then view.calendar.render(all, now); return end
    local f = view.filters
    local filterCtx = { now = now, player = ctx.player(), lower = ctx.lower, extra = function(ev) return UI.extraText(ctx, ev) end,
        dayStart = UI.dayStart, level = ctx.myLevel(), roles = ctx.myRoles() }
    local shown = {}
    for _, ev in ipairs(all) do
        if inTab(ev, view.tab, ctx, now) and events.matches(ev, f, filterCtx) then shown[#shown + 1] = ev end
    end
    local sorter = events.sorter(f.sort)
    if view.tab == "history" then
        table.sort(shown, function(a, b) if a.starts ~= b.starts then return a.starts > b.starts end return a.id < b.id end)
    else
        table.sort(shown, function(a, b)
            if f.sort == "start" or not f.sort then
                local first, second = sectionOf(a, now), sectionOf(b, now)
                if first ~= second then return first < second end
            end
            return sorter(a, b)
        end)
    end
    -- Selection stays when possible.
    local found
    for _, ev in ipairs(shown) do if ev.id == view.selection then found = ev end end
    if not found then found = shown[1]; view.selection = found and found.id end
    -- Cards with section headers (overview, start time order).
    local y, cardIndex, headerIndex, lastSection = -2, 0, 0, nil
    local width = view.content:GetWidth()
    for _, ev in ipairs(shown) do
        local section = (view.tab == "overview" and (f.sort == "start" or not f.sort)) and sectionOf(ev, now) or nil
        if section and section ~= lastSection then
            lastSection = section
            headerIndex = headerIndex + 1
            local header = view.headers[headerIndex]
            if not header then
                header = text(view.content, "GameFontNormal")
                view.headers[headerIndex] = header
            end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 6, y - 6)
            header:SetText(L[SECTION_TITLES[section]])
            header:Show()
            y = y - 26
        end
        cardIndex = cardIndex + 1
        local card = view.cards[cardIndex]
        if not card then
            card = UI.card(view.content, ctx, function(selected)
                view.selection = selected.id
                UI.markRead(ctx, selected)
                UI.render()
            end, function(selected) UI.openSignup(ctx, selected) end)
            view.cards[cardIndex] = card
        end
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, y)
        card:SetPoint("RIGHT", view.content, "RIGHT", 0, 0)
        card:SetWidth(width)
        UI.fillCard(card, ev, ctx, ev.id == view.selection)
        card:Show()
        y = y - CARD_HEIGHT - 6
    end
    for index = cardIndex + 1, #view.cards do view.cards[index]:Hide() end
    for index = headerIndex + 1, #view.headers do view.headers[index]:Hide() end
    view.content:SetHeight(math.max(1, -y))
    view.empty:SetShown(#shown == 0)
    local emptyTexts = { overview = "No groups or events match your filters. Create one yourself!",
        mine = "You have not signed up for anything yet.", organized = "You are not organizing any events.",
        history = "No past events yet." }
    view.empty:SetText(L[emptyTexts[view.tab] or emptyTexts.overview])
    UI.fillDetail(view.detail, found, ctx)
    if found then UI.markRead(ctx, found) end
end

-- Detail view ---------------------------------------------------------------------------------------------
-- Header with banner, compact info fields, organizer, role columns, optional texts; the
-- content scrolls, the action bar stays at the bottom.
local INFO_ICONS = { when = "Interface\\Icons\\INV_Misc_PocketWatch_01", level = "Interface\\Icons\\INV_Misc_Book_11",
    zone = "Interface\\Icons\\INV_Misc_Map_01", group = "Interface\\Icons\\Spell_Holy_PrayerOfHealing" }
local HEADER_HEIGHT = 104

function UI.buildDetail(parent, ctx)
    local detail = ctx.contrastPanel(parent)
    detail.banner = detail:CreateTexture(nil, "ARTWORK", nil, -3)
    detail.banner:SetPoint("TOPLEFT", 4, -4)
    detail.banner:SetPoint("TOPRIGHT", -4, -4)
    detail.banner:SetHeight(HEADER_HEIGHT)
    local shade = detail:CreateTexture(nil, "ARTWORK", nil, -2)
    shade:SetAllPoints(detail.banner)
    shade:SetColorTexture(1, 1, 1, 1)
    shade:SetGradient("VERTICAL", CreateColor(.03, .022, .016, .97), CreateColor(.03, .022, .016, .25))
    detail.shade = shade
    local edge = detail:CreateTexture(nil, "ARTWORK", nil, -1)
    edge:SetPoint("TOPLEFT", detail.banner, "BOTTOMLEFT")
    edge:SetPoint("TOPRIGHT", detail.banner, "BOTTOMRIGHT")
    edge:SetHeight(2)
    edge:SetColorTexture(.62, .45, .22, .9)
    detail.edge = edge
    detail.icon = detail:CreateTexture(nil, "OVERLAY")
    detail.icon:SetSize(40, 40)
    detail.icon:SetPoint("BOTTOMLEFT", detail.banner, "BOTTOMLEFT", 12, 12)
    detail.icon:SetTexCoord(.07, .93, .07, .93)
    detail.title = text(detail, "GameFontNormalLarge")
    detail.title:SetPoint("LEFT", detail.icon, "RIGHT", 10, 8)
    detail.title:SetPoint("RIGHT", detail.banner, "RIGHT", -12, 0)
    detail.subtitle = text(detail, "GameFontHighlightSmall")
    detail.subtitle:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -3)
    detail.subtitle:SetPoint("RIGHT", detail.banner, "RIGHT", -12, 0)
    detail.state = text(detail, "GameFontNormal", "RIGHT")
    detail.state:SetPoint("TOPRIGHT", detail.banner, "TOPRIGHT", -12, -10)
    detail:HookScript("OnSizeChanged", function(self, width)
        if self.aspect then UI.fitArt(self.banner, self.aspect, width - 8, HEADER_HEIGHT) end
    end)
    local scroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -(HEADER_HEIGHT + 12))
    scroll:SetPoint("BOTTOMRIGHT", -30, 46)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(300, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    detail.scroll, detail.content = scroll, content
    detail.pool = { heading = {}, text = {}, row = {}, line = {}, info = {} }
    detail.empty = text(detail, "GameFontDisable", "CENTER", true)
    detail.empty:SetPoint("CENTER")
    detail.empty:SetWidth(260)
    detail.empty:SetText(L["Select an event to see its details."])
    local bar = detail:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("BOTTOMLEFT", 6, 42)
    bar:SetPoint("BOTTOMRIGHT", -6, 42)
    bar:SetHeight(1)
    bar:SetColorTexture(.5, .35, .17, .8)
    detail.actions = {}
    for index = 1, 4 do
        local control = ctx.button(detail, "", 112, 0, 0, function(self) if self.run then self.run() end end)
        control:ClearAllPoints()
        if index == 1 then control:SetPoint("BOTTOMRIGHT", -10, 12)
        else control:SetPoint("RIGHT", detail.actions[index - 1], "LEFT", -6, 0) end
        detail.actions[index] = control
    end
    detail.manage = ctx.button(detail, L["Actions"] .. "  |TInterface\\ChatFrame\\ChatFrameExpandArrow:12|t", 120, 0, 0, function(self)
        UI.eventMenu(ctx, self.ev, self)
    end)
    detail.manage:ClearAllPoints()
    detail.manage:SetPoint("BOTTOMLEFT", 10, 12)
    UI.tooltip(detail.manage, L["Actions"], L["All actions for this event. Tip: right-click an event card or a participant."])
    return detail
end

local function poolGet(detail, kind, create)
    local pool = detail.pool[kind]
    pool.used = (pool.used or 0) + 1
    local item = pool[pool.used]
    if not item then
        item = create()
        pool[pool.used] = item
    end
    item:Show()
    return item
end

local function memberRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(20)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:GetHighlightTexture():SetAlpha(.35)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 2, 0)
    row.role = row:CreateTexture(nil, "ARTWORK")
    row.role:SetSize(16, 16)
    row.role:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
    row.name = text(row, "GameFontHighlight")
    row.name:SetPoint("LEFT", row.role, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", -4, 0)
    row.status = text(row, "GameFontHighlightSmall", "RIGHT")
    row.status:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnEnter", function(self) if self.tooltip then self.tooltip(self) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return row
end

local function infoField(parent)
    local field = CreateFrame("Frame", nil, parent)
    field:SetHeight(24)
    field.icon = field:CreateTexture(nil, "ARTWORK")
    field.icon:SetSize(20, 20)
    field.icon:SetPoint("LEFT", 0, 0)
    field.icon:SetTexCoord(.07, .93, .07, .93)
    field.label = text(field, "GameFontHighlight")
    field.label:SetPoint("LEFT", field.icon, "RIGHT", 7, 0)
    field.label:SetPoint("RIGHT", -4, 0)
    return field
end

function UI.memberTooltip(ctx, owner, name, entry)
    local member = ctx.member(name)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local c = UI.classColor(ctx, name)
    GameTooltip:SetText(ctx.displayName(name), c[1], c[2], c[3])
    if member then
        GameTooltip:AddLine(L["Level %s · %s"]:format(member.level or "–", member.className or "–"), 1, .91, .74)
        GameTooltip:AddDoubleLine(L["Status"], member.online and L["Online"] or L["Offline"], 1, 1, 1,
            member.online and .45 or .62, member.online and .86 or .57, member.online and .45 or .5)
        if member.online and member.zone and member.zone ~= "" then GameTooltip:AddDoubleLine(L["Zone"], member.zone) end
    end
    if entry then
        if entry.role then GameTooltip:AddDoubleLine(L["Role"], L[ROLE_NAMES[entry.role]]) end
        if entry.alt and entry.alt ~= "" then
            local names = {}
            for role in entry.alt:gmatch("[THD]") do names[#names + 1] = L[ROLE_NAMES[role]] end
            GameTooltip:AddDoubleLine(L["Alternative roles"], table.concat(names, ", "))
        end
        if entry.note and entry.note ~= "" then GameTooltip:AddLine(L["Note: %s"]:format(entry.note), .83, .77, .65, true) end
        if not entry.synced and entry.status == "signed" then
            GameTooltip:AddLine(L["The organizer has not confirmed this sign-up yet."], 1, .75, .35, true)
        end
    end
    GameTooltip:Show()
end

-- Context menu for a participant row (shared component).
function UI.memberMenu(ctx, ev, entry, owner)
    UI.menu(owner, ctx.displayName(entry.name), UI.memberEntries(ctx, ev, entry))
end


function UI.fillDetail(detail, ev, ctx)
    for _, pool in pairs(detail.pool) do
        for index = 1, #pool do pool[index]:Hide() end
        pool.used = 0
    end
    local hasEvent = ev ~= nil
    detail.empty:SetShown(not hasEvent)
    for _, region in ipairs({ detail.banner, detail.shade, detail.edge, detail.icon, detail.title, detail.subtitle,
        detail.state, detail.scroll }) do
        region:SetShown(hasEvent)
    end
    for _, control in ipairs(detail.actions) do control:Hide(); control.run = nil end
    detail.manage:Hide()
    if not ev then return end
    local now = ctx.clock()
    local de = GetLocale() == "deDE"
    local art, aspect = UI.banner(ev)
    detail.banner:SetTexture(art)
    detail.aspect = aspect
    UI.fitArt(detail.banner, aspect, detail:GetWidth() - 8, HEADER_HEIGHT)
    detail.icon:SetTexture((events.byCategory[ev.cat] or events.byCategory.other).icon)
    detail.title:SetText(UI.titleOf(ev))
    local subtitle = UI.categoryLabel(ev)
    if ev.series then subtitle = subtitle .. "  ·  " .. L["Series: date %d of %d"]:format(ev.series.index, ev.series.total) end
    if ev.legacy then subtitle = subtitle .. "  ·  " .. L["Older dungeon date"] end
    if ev.partnerGuild then subtitle = subtitle .. "  ·  " .. ev.partnerGuild end
    detail.subtitle:SetText(subtitle)
    local state = ev.stateCache
    detail.state:SetText(L[STATE_LABELS[state] or "Sign-up open"])
    color(detail.state, STATE_COLORS[state] or LIGHT)

    local content, y = detail.content, -2
    local width = math.max(200, content:GetWidth())
    local function rule()
        local line = poolGet(detail, "line", function()
            local texture = content:CreateTexture(nil, "ARTWORK")
            texture:SetHeight(1)
            texture:SetColorTexture(.5, .35, .17, .6)
            return texture
        end)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 2, y - 6)
        line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, y - 6)
        y = y - 13
    end
    local function heading(caption, right)
        local label = poolGet(detail, "heading", function() return text(content, "GameFontNormal") end)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 4, y - 2)
        label:SetPoint("RIGHT", content, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        label:SetText(caption)
        if right then
            local value = poolGet(detail, "heading", function() return text(content, "GameFontNormal") end)
            value:ClearAllPoints()
            value:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y - 2)
            value:SetJustifyH("RIGHT")
            value:SetText(right)
        end
        y = y - 22
    end
    local function paragraph(value, c)
        local label = poolGet(detail, "text", function() return text(content, "GameFontHighlight", "LEFT", true) end)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 6, y)
        label:SetWidth(width - 12)
        label:SetText(value)
        color(label, c or LIGHT)
        y = y - label:GetStringHeight() - 6
    end
    local function row(x, rowWidth, setup)
        local item = poolGet(detail, "row", function() return memberRow(content) end)
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", x, y)
        item:SetWidth(rowWidth)
        item.tooltip = nil
        item:SetScript("OnClick", nil)
        item.icon:SetTexCoord(0, 1, 0, 1)
        item.icon:Show()
        item.role:Show()
        item.status:SetText("")
        item.name:SetPoint("RIGHT", -4, 0)
        setup(item)
        return item
    end

    -- Info fields: date, level, zone or goal, group size.
    local roster = ev.rosterCache
    local counts = roster.counts
    local fields = {}
    fields[#fields + 1] = { INFO_ICONS.when, UI.when(ev.starts, now) }
    fields[#fields + 1] = { INFO_ICONS.level, UI.levelText(ev) or L["All levels"] }
    local dungeon = ev.dungeon and addon.getGroupDungeon(ev.dungeon)
    if dungeon then
        fields[#fields + 1] = { INFO_ICONS.zone, dungeon[de and 3 or 4] }
    elseif ev.targets and ev.targets[1] then
        fields[#fields + 1] = { UI.targetIcon(ctx, ev.targets[1]), UI.targetName(ctx, ev.targets[1]), ev.targets[1] }
    end
    if ev.kind ~= "partner" then
        fields[#fields + 1] = { INFO_ICONS.group, counts.capacity and L["%d/%d participants"]:format(counts.total, counts.capacity)
            or L["%d participants"]:format(counts.total) }
    end
    local columnWidth = math.floor((width - 8) / 2)
    for index, data in ipairs(fields) do
        local field = poolGet(detail, "info", function() return infoField(content) end)
        local column = (index - 1) % 2
        field:ClearAllPoints()
        field:SetPoint("TOPLEFT", 4 + column * columnWidth, y - math.floor((index - 1) / 2) * 26)
        field:SetWidth(columnWidth - 6)
        field.icon:SetTexture(data[1])
        field.label:SetText(data[2])
        field:EnableMouse(data[3] ~= nil)
        field:SetScript("OnEnter", data[3] and function(self) UI.targetTooltip(self, ctx, data[3]) end or nil)
        field:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    y = y - math.ceil(#fields / 2) * 26
    rule()

    -- Organizer and co-organizers.
    heading(L["ORGANIZER"])
    local function personLine(name, roleKey)
        row(4, width - 8, function(item)
            local member = ctx.member(name)
            UI.classIcon(item.icon, member and member.class)
            if roleKey then UI.roleIcon(item.role, roleKey) else item.role:Hide() end
            item.name:SetText(ctx.displayName(name))
            item.name:SetPoint("RIGHT", -80, 0)
            color(item.name, UI.classColor(ctx, name))
            item.status:SetText(member and (member.online and L["Online"] or L["Offline"]) or "")
            color(item.status, member and member.online and GREEN or MUTED)
            item.tooltip = function(self) UI.memberTooltip(ctx, self, name) end
        end)
        y = y - 21
    end
    personLine(ev.owner, ev.ownerRole)
    for _, name in ipairs(ev.coorg or {}) do personLine(name) end
    rule()

    -- Participants: role columns (side by side when there is room), free places marked.
    local function memberLine(x, rowWidth, entry, suffix)
        row(x, rowWidth, function(item)
            local member = ctx.member(entry.name)
            UI.classIcon(item.icon, member and member.class)
            if entry.role then UI.roleIcon(item.role, entry.role) else item.role:Hide() end
            local label = ctx.displayName(entry.name) .. (suffix or "")
            if entry.status == "tentative" then label = label .. " |cffe6c870(" .. L["tentative"] .. ")|r" end
            if entry.status == "attended" then label = label .. " |TInterface\\Buttons\\UI-CheckBox-Check:14|t" end
            item.name:SetText(label)
            color(item.name, UI.classColor(ctx, entry.name))
            item.tooltip = function(self) UI.memberTooltip(ctx, self, entry.name, entry) end
            if entry.name ~= ev.owner then
                item:SetScript("OnClick", function(self, mouse) if mouse == "RightButton" then UI.memberMenu(ctx, ev, entry, self) end end)
            end
        end)
    end
    local function freeLine(x, rowWidth)
        row(x, rowWidth, function(item)
            item.icon:Hide(); item.role:Hide()
            item.name:SetText(L["Free place"])
            color(item.name, MUTED)
        end)
    end
    local placedStates = { confirmed = true, tentative = true, attended = true }
    local ownerEntry = { name = ev.owner, status = "confirmed", role = ev.ownerRole, synced = true }
    if ev.kind ~= "partner" then
        heading(L["PARTICIPANTS"], counts.capacity and ("%d / %d"):format(counts.total, counts.capacity) or tostring(counts.total))
        if ev.slots then
            local roles = {}
            for _, role in ipairs({ "T", "H", "D" }) do if ev.slots[role] > 0 then roles[#roles + 1] = role end end
            local side = width >= 330 and #roles > 1
            local colWidth = side and math.floor((width - 8 - (#roles - 1) * 8) / #roles) or (width - 8)
            local top, lowest = y, y
            for index, role in ipairs(roles) do
                local x = side and (4 + (index - 1) * (colWidth + 8)) or 4
                if side then y = top end
                local label = poolGet(detail, "heading", function() return text(content, "GameFontNormal") end)
                label:ClearAllPoints()
                label:SetPoint("TOPLEFT", x + 22, y - 2)
                label:SetJustifyH("LEFT")
                label:SetText(("%s  %d/%d"):format(L[ROLE_NAMES[role]], math.min(counts[role], ev.slots[role]), ev.slots[role]))
                color(label, counts[role] >= ev.slots[role] and GREEN or GOLD)
                local icon = poolGet(detail, "info", function() return infoField(content) end)
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", x, y + 2)
                icon:SetWidth(20)
                icon.label:SetText("")
                UI.roleIcon(icon.icon, role)
                icon:EnableMouse(false)
                y = y - 22
                local placed = 0
                if ev.ownerRole == role then memberLine(x, colWidth, ownerEntry); y = y - 20; placed = 1 end
                for _, entry in ipairs(roster.entries) do
                    if placedStates[entry.status] and entry.role == role then memberLine(x, colWidth, entry); y = y - 20; placed = placed + 1 end
                end
                for _ = placed + 1, ev.slots[role] do freeLine(x, colWidth); y = y - 20 end
                lowest = math.min(lowest, y)
                if not side then y = y - 4 end
            end
            y = side and lowest or y
        else
            memberLine(4, width - 8, ownerEntry)
            y = y - 20
            for _, entry in ipairs(roster.entries) do
                if placedStates[entry.status] then memberLine(4, width - 8, entry); y = y - 20 end
            end
            if counts.capacity then
                for _ = counts.total + 1, math.min(counts.capacity, counts.total + 3) do freeLine(4, width - 8); y = y - 20 end
            end
        end
        -- Further states only when somebody is in them.
        local groups = { { "signed", L["SIGNED UP – WAITING FOR CONFIRMATION"] }, { "waitlist", L["WAITLIST"] },
            { "noshow", L["DID NOT SHOW UP"] }, { "rejected", L["DECLINED"] }, { "out", L["WITHDRAWN"] } }
        for _, group in ipairs(groups) do
            local first = true
            for _, entry in ipairs(roster.entries) do
                if entry.status == group[1] then
                    if first then y = y - 4; heading(group[2]); first = false end
                    local suffix = ""
                    if entry.alt ~= "" and group[1] == "waitlist" then
                        local names = { L[ROLE_NAMES[entry.role] or "DPS"] }
                        for role in entry.alt:gmatch("[THD]") do names[#names + 1] = L[ROLE_NAMES[role]] end
                        suffix = "  (" .. table.concat(names, " / ") .. ")"
                    end
                    memberLine(4, width - 8, entry, suffix)
                    y = y - 20
                end
            end
        end
        if ev.kind == "event" and ev.slots and events.mayManage(ev, ctx.player()) then
            for _, role in ipairs({ "T", "H", "D" }) do
                if events.free(ev, counts, role) > 0 then
                    local candidates = events.candidates(ev, role)
                    if #candidates > 0 then
                        local names = {}
                        for _, entry in ipairs(candidates) do names[#names + 1] = ctx.displayName(entry.name) end
                        paragraph(L["Free %s place – could be taken by: %s"]:format(L[ROLE_NAMES[role]], table.concat(names, ", ")), GREEN)
                    end
                end
            end
        end
    else
        paragraph(L["Partner guild event – whisper the organizer to take part."], MUTED)
    end

    -- Texts only when they exist (older events may still carry goals, loot or a meeting point).
    local texts = {}
    if ev.desc then texts[#texts + 1] = { L["DESCRIPTION"], ev.desc } end
    if ev.req then texts[#texts + 1] = { L["REQUIREMENTS"], ev.req } end
    if ev.place then texts[#texts + 1] = { L["MEETING POINT"], ev.place } end
    if ev.loot then
        local lines = { L[LOOT_LABELS[ev.loot.rule]] }
        if ev.loot.who then lines[#lines + 1] = L["Reserved for: %s"]:format(ctx.displayName(ev.loot.who)) end
        if ev.loot.text then lines[#lines + 1] = ev.loot.text end
        texts[#texts + 1] = { L["LOOT AGREEMENT"], table.concat(lines, "\n") }
    end
    if ev.targets and #ev.targets > 1 then
        local names = {}
        for _, target in ipairs(ev.targets) do names[#names + 1] = UI.targetName(ctx, target) end
        texts[#texts + 1] = { L["GOALS"], table.concat(names, "\n") }
    end
    for _, entry in ipairs(texts) do
        rule()
        heading(entry[1])
        paragraph(entry[2])
    end
    content:SetHeight(math.max(1, -y + 8))
    UI.fillActions(detail, ev, ctx)
end

-- Detail view: the most important actions stay visible, everything else is in "Actions"
-- (the same menu as the right click on a card).
function UI.fillActions(detail, ev, ctx)
    local me = ctx.player()
    local list = {}
    local function add(label, run, enabled) list[#list + 1] = { label = label, run = run, enabled = enabled ~= false } end
    local state = ev.stateCache
    local status = UI.myStatus(ctx, ev)
    if ev.kind == "event" and not events.mayManage(ev, me) and ev.status == "open"
        and (state == "open" or state == "full" or state == "ready") then
        if not status or status == "out" then
            add(ev.rosterCache.counts.full and L["Join the waitlist"] or L["Sign up"], function() UI.openSignup(ctx, ev) end, ctx.ready())
        elseif status ~= "rejected" then
            add(L["Withdraw"], function() UI.withdraw(ctx, ev) end, ctx.ready())
            add(L["Change sign-up"], function() UI.openSignup(ctx, ev) end, ctx.ready())
        end
    elseif ev.kind == "event" and events.mayManage(ev, me) and (state == "open" or state == "full" or state == "ready" or state == "closed") then
        add(L["Edit"], function() UI.openWizard(ctx, { edit = ev }) end, ctx.ready())
    elseif ev.kind == "legacy" and ev.owner ~= me and state == "open" then
        add((status and status ~= "out") and L["Leave"] or L["Sign up"], function() ctx.legacyReply(ev) end, ctx.ready())
    end
    for index, control in ipairs(detail.actions) do
        local action = list[index]
        control:SetShown(action ~= nil)
        if action then
            control:SetText(action.label)
            control:SetWidth(math.max(96, math.min(190, control:GetFontString():GetStringWidth() + 28)))
            control:SetText(action.label)
            control.run = action.run
            control:SetEnabled(action.enabled)
        end
    end
    detail.manage:Show()
    detail.manage.ev = ev
end

function UI.cancelEvent(ctx, ev)
    local guild = ctx.guild()
    local function cancel(list)
        for _, other in ipairs(list) do
            if events.setStatus(other, "cancelled", ctx.clock()) then events.flush(other, ctx.send) end
        end
        UI.refresh()
    end
    if ev.series and ev.owner == ctx.player() then
        UI.confirm(ctx, L["Cancel event?"], L["CANCEL_CONFIRM"]:format(UI.titleOf(ev)) .. "\n\n"
            .. L["This date belongs to a series. Cancel only this date or this and all following dates?"],
            function(choice)
                if choice == 2 then
                    events.stopSeries(guild, ev)
                    cancel(events.seriesMembers(guild, ev, true))
                else
                    cancel({ ev })
                end
            end, L["Only this date"], L["All following"])
    else
        UI.confirm(ctx, L["Cancel event?"], L["CANCEL_CONFIRM"]:format(UI.titleOf(ev)), function() cancel({ ev }) end, L["Cancel event"])
    end
end

-- Calendar --------------------------------------------------------------------------------------------------
function UI.buildCalendar(parent, ctx)
    local frame = CreateFrame("Frame", nil, parent)
    frame:Hide()
    local now = ctx.clock()
    local today = date("*t", now)
    frame.year, frame.month, frame.mode = today.year, today.month, "month"
    frame.day = UI.dayStart(now)
    local grid = ctx.contrastPanel(frame)
    grid:SetPoint("TOPLEFT")
    grid:SetPoint("BOTTOMLEFT")
    grid:SetWidth(560)
    frame.grid = grid
    frame.caption = text(grid, "GameFontNormalLarge", "CENTER")
    frame.caption:SetPoint("TOP", 0, -12)
    local previous = ctx.button(grid, "<", 32, 0, 0, function()
        if frame.mode == "week" then frame.day = frame.day - 7 * DAY
        else frame.month = frame.month - 1; if frame.month < 1 then frame.month, frame.year = 12, frame.year - 1 end end
        UI.refresh()
    end)
    previous:ClearAllPoints()
    previous:SetPoint("TOPLEFT", 10, -9)
    UI.tooltip(previous, L["Previous"])
    local nextButton = ctx.button(grid, ">", 32, 0, 0, function()
        if frame.mode == "week" then frame.day = frame.day + 7 * DAY
        else frame.month = frame.month + 1; if frame.month > 12 then frame.month, frame.year = 1, frame.year + 1 end end
        UI.refresh()
    end)
    nextButton:ClearAllPoints()
    nextButton:SetPoint("LEFT", previous, "RIGHT", 4, 0)
    UI.tooltip(nextButton, L["Next"])
    local todayButton = ctx.button(grid, L["Today"], 80, 0, 0, function()
        local t = date("*t", ctx.clock())
        frame.year, frame.month, frame.day = t.year, t.month, UI.dayStart(ctx.clock())
        UI.refresh()
    end)
    todayButton:ClearAllPoints()
    todayButton:SetPoint("TOPRIGHT", -96, -9)
    frame.modeButton = ctx.button(grid, "", 80, 0, 0, function()
        frame.mode = frame.mode == "month" and "week" or "month"
        UI.refresh()
    end)
    frame.modeButton:ClearAllPoints()
    frame.modeButton:SetPoint("TOPRIGHT", -10, -9)
    frame.zone = text(grid, "GameFontDisableSmall", "CENTER")
    frame.zone:SetPoint("BOTTOM", 0, 8)
    frame.heads, frame.cells = {}, {}
    for index = 1, 7 do
        local label = text(grid, "GameFontNormalSmall", "CENTER")
        frame.heads[index] = label
        label:SetText(L[WEEKDAYS_SHORT[index % 7 + 1]])
    end
    for index = 1, 42 do
        local cell = CreateFrame("Button", nil, grid, "BackdropTemplate")
        cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 9, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        cell:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        cell:GetHighlightTexture():SetAlpha(.25)
        cell.number = text(cell, "GameFontHighlight")
        cell.number:SetPoint("TOPLEFT", 5, -4)
        cell.icons, cell.lines = {}, {}
        for slot = 1, 3 do
            local icon = cell:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetTexCoord(.07, .93, .07, .93)
            cell.icons[slot] = icon
        end
        for slot = 1, 5 do
            local line = text(cell, "GameFontHighlightSmall")
            line:SetPoint("LEFT", 5, 0)
            line:SetPoint("RIGHT", -4, 0)
            cell.lines[slot] = line
        end
        cell.more = text(cell, "GameFontDisableSmall", "RIGHT")
        cell.more:SetPoint("BOTTOMRIGHT", -4, 4)
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell:SetScript("OnClick", function(self, mouse)
            frame.day = self.dayStart
            UI.refresh()
            if mouse ~= "RightButton" then return end
            local entries = {}
            for _, ev in ipairs(self.list or {}) do
                entries[#entries + 1] = { text = UI.clock(ev.starts) .. "  " .. UI.titleOf(ev), icon = (events.byCategory[ev.cat] or events.byCategory.other).icon,
                    func = function() UI.eventMenu(ctx, ev, self) end }
            end
            if ctx.canPost() and self.dayStart + DAY > ctx.clock() then
                if #entries > 0 then entries[#entries + 1] = { divider = true } end
                entries[#entries + 1] = { text = L["Create event on this day"], icon = ICONS_CREATE, func = function() UI.openWizard(ctx, { day = self.dayStart }) end }
            end
            if #entries > 0 then UI.menu(self, UI.longDate(self.dayStart), entries) end
        end)
        cell:SetScript("OnEnter", function(self)
            if not self.list or #self.list == 0 then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(UI.longDate(self.dayStart))
            for _, ev in ipairs(self.list) do
                GameTooltip:AddDoubleLine(UI.clock(ev.starts) .. "  " .. UI.titleOf(ev), L[STATE_LABELS[ev.stateCache] or "Sign-up open"],
                    1, 1, 1, .8, .75, .65)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.cells[index] = cell
    end
    -- Day details
    local dayPanel = ctx.contrastPanel(frame)
    dayPanel:SetPoint("TOPLEFT", grid, "TOPRIGHT", 6, 0)
    dayPanel:SetPoint("BOTTOMRIGHT")
    frame.dayTitle = text(dayPanel, "GameFontNormalLarge")
    frame.dayTitle:SetPoint("TOPLEFT", 14, -14)
    frame.dayTitle:SetPoint("RIGHT", -12, 0)
    local scroll = CreateFrame("ScrollFrame", nil, dayPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -44)
    scroll:SetPoint("BOTTOMRIGHT", -30, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(260, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    frame.dayContent, frame.dayRows = content, {}
    frame.dayEmpty = text(dayPanel, "GameFontDisable", "CENTER", true)
    frame.dayEmpty:SetPoint("TOPLEFT", 20, -70)
    frame.dayEmpty:SetPoint("RIGHT", -20, 0)
    frame.dayEmpty:SetText(L["Nothing planned on this day."])
    frame.dayCreate = ctx.button(dayPanel, L["Create event"], 150, 0, 0, function()
        UI.openWizard(ctx, { day = frame.day })
    end)
    frame.dayCreate:ClearAllPoints()
    frame.dayCreate:SetPoint("BOTTOMRIGHT", -10, 12)
    frame:SetScript("OnSizeChanged", function(_, width) grid:SetWidth(math.max(470, math.floor(width * .6))) end)

    frame.render = function(all, current)
        frame.modeButton:SetText(frame.mode == "month" and L["Week"] or L["Month"])
        frame.zone:SetText(L["All times in your local time (%s)."]:format(UI.zone(current)))
        local byDay = {}
        for _, ev in ipairs(all) do
            if ev.kind ~= "partner" or UI.setting("partners") then
                local key = UI.dayStart(ev.starts)
                byDay[key] = byDay[key] or {}
                table.insert(byDay[key], ev)
            end
        end
        for _, list in pairs(byDay) do table.sort(list, function(a, b) return a.starts < b.starts end) end
        local gridWidth, gridHeight = grid:GetWidth(), grid:GetHeight()
        local cellWidth = math.floor((gridWidth - 20) / 7)
        local startDay, rows
        if frame.mode == "month" then
            local first = time({ year = frame.year, month = frame.month, day = 1, hour = 12 })
            local wday = tonumber(date("%w", first)) -- 0 = Sunday
            local offset = (wday + 6) % 7            -- weeks start on Monday
            startDay = UI.dayStart(first - offset * DAY)
            rows = 6
            frame.caption:SetText(("%s %d"):format(L[MONTHS[frame.month]], frame.year))
        else
            local wday = tonumber(date("%w", frame.day + 12 * 3600))
            startDay = UI.dayStart(frame.day - ((wday + 6) % 7) * DAY + 12 * 3600)
            rows = 1
            frame.caption:SetText(L["Week of %s"]:format(date("%d.%m.%Y", startDay + 12 * 3600)))
        end
        local cellHeight = math.floor((gridHeight - 86) / rows)
        for index = 1, 7 do
            frame.heads[index]:ClearAllPoints()
            frame.heads[index]:SetPoint("TOPLEFT", 10 + (index - 1) * cellWidth, -44)
            frame.heads[index]:SetWidth(cellWidth)
        end
        local todayStart = UI.dayStart(current)
        for index, cell in ipairs(frame.cells) do
            local visible = index <= rows * 7
            cell:SetShown(visible)
            if visible then
                local column, line = (index - 1) % 7, math.floor((index - 1) / 7)
                local dayStart = UI.dayStart(startDay + (index - 1) * DAY + 12 * 3600)
                cell.dayStart = dayStart
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", 10 + column * cellWidth, -62 - line * cellHeight)
                cell:SetSize(cellWidth - 2, cellHeight - 2)
                local parts = date("*t", dayStart)
                cell.number:SetText(parts.day)
                local inMonth = frame.mode == "week" or parts.month == frame.month
                cell.number:SetTextColor(inMonth and 1 or .45, inMonth and .92 or .42, inMonth and .75 or .38)
                local list = byDay[dayStart] or {}
                cell.list = list
                local selected = dayStart == frame.day
                local isToday = dayStart == todayStart
                local mine = false
                for _, ev in ipairs(list) do
                    local status = UI.myStatus(ctx, ev)
                    if status and status ~= "out" and status ~= "rejected" then mine = true end
                end
                cell:SetBackdropColor(isToday and .2 or .07, isToday and .15 or .05, isToday and .06 or .035, inMonth and .95 or .6)
                if selected then cell:SetBackdropBorderColor(1, .82, .3)
                elseif mine then cell:SetBackdropBorderColor(.45, .86, .45)
                elseif isToday then cell:SetBackdropBorderColor(.9, .68, .3)
                else cell:SetBackdropBorderColor(.45, .32, .18) end
                for slot, icon in ipairs(cell.icons) do
                    local ev = frame.mode == "month" and list[slot]
                    icon:SetShown(ev and true or false)
                    if ev then
                        icon:ClearAllPoints()
                        icon:SetPoint("BOTTOMLEFT", 4 + (slot - 1) * 18, 4)
                        icon:SetTexture((events.byCategory[ev.cat] or events.byCategory.other).icon)
                        icon:SetDesaturated(ev.stateCache == "cancelled")
                        icon:SetAlpha(ev.stateCache == "cancelled" and .5 or 1)
                    end
                end
                for slot, label in ipairs(cell.lines) do
                    local ev = frame.mode == "week" and list[slot]
                    label:SetShown(ev and true or false)
                    if ev then
                        label:ClearAllPoints()
                        label:SetPoint("TOPLEFT", 5, -24 - (slot - 1) * 30)
                        label:SetPoint("RIGHT", -4, 0)
                        label:SetWordWrap(true)
                        label:SetText(UI.clock(ev.starts) .. "\n" .. UI.titleOf(ev))
                        if ev.stateCache == "cancelled" then color(label, RED) else color(label, LIGHT) end
                    end
                end
                local shownCount = frame.mode == "month" and 3 or 5
                cell.more:SetText(#list > shownCount and ("+" .. (#list - shownCount)) or "")
            end
        end
        -- Day details on the right.
        frame.dayTitle:SetText(UI.longDate(frame.day))
        local list = byDay[frame.day] or {}
        local y = 0
        for index, ev in ipairs(list) do
            local item = frame.dayRows[index]
            if not item then
                item = CreateFrame("Button", nil, content)
                item:SetHeight(46)
                item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                item:GetHighlightTexture():SetAlpha(.3)
                item.icon = item:CreateTexture(nil, "ARTWORK")
                item.icon:SetSize(28, 28)
                item.icon:SetPoint("TOPLEFT", 2, -4)
                item.icon:SetTexCoord(.07, .93, .07, .93)
                item.title = text(item, "GameFontNormal")
                item.title:SetPoint("TOPLEFT", item.icon, "TOPRIGHT", 8, 0)
                item.title:SetPoint("RIGHT", -4, 0)
                item.info = text(item, "GameFontHighlightSmall")
                item.info:SetPoint("TOPLEFT", item.title, "BOTTOMLEFT", 0, -3)
                item.info:SetPoint("RIGHT", -4, 0)
                item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                item:SetScript("OnClick", function(self, mouse)
                    if mouse == "RightButton" then UI.eventMenu(ctx, self.ev, self) else UI.select(self.ev.id) end
                end)
                frame.dayRows[index] = item
            end
            item.ev = ev
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", 0, y)
            item:SetPoint("RIGHT", content, "RIGHT")
            item.icon:SetTexture((events.byCategory[ev.cat] or events.byCategory.other).icon)
            item.title:SetText(UI.clock(ev.starts) .. " – " .. UI.titleOf(ev))
            local counts = ev.rosterCache.counts
            local info = UI.categoryLabel(ev)
            if counts.capacity then info = info .. " · " .. L["%d/%d participants"]:format(counts.total, counts.capacity) end
            local status = UI.myStatus(ctx, ev)
            if ev.stateCache == "cancelled" then info = info .. " · |cffff7359" .. L["Cancelled"] .. "|r"
            elseif status == "organizer" then info = info .. " · " .. L["Your event"]
            elseif status and status ~= "out" then info = info .. " · |cff73dc73" .. L[STATUS_LABELS[status]] .. "|r" end
            item.info:SetText(info)
            item:Show()
            y = y - 50
        end
        for index = #list + 1, #frame.dayRows do frame.dayRows[index]:Hide() end
        content:SetHeight(math.max(1, -y))
        frame.dayEmpty:SetShown(#list == 0)
        frame.dayCreate:SetShown(ctx.canPost() and frame.day + DAY > current)
        frame.dayCreate:SetEnabled(ctx.ready())
    end
    return frame
end

-- Upcoming events for the guild overview -------------------------------------------------------------------
function UI.upcoming(ctx, limit)
    local now, list = ctx.clock(), {}
    for _, ev in ipairs(UI.collect(ctx)) do
        if ev.kind ~= "partner" and UI.isActive(ev, now) and ev.mode == "plan" and ev.starts > now - 3600 then list[#list + 1] = ev end
    end
    table.sort(list, function(a, b) return a.starts < b.starts end)
    while #list > (limit or 3) do table.remove(list) end
    return list
end

-- Settings ------------------------------------------------------------------------------------------------------
function UI.registerSettings(S, ctx)
    local function option(page, key, label, desc, extra)
        local entry = { page = page, kind = "check", label = label, desc = desc, scope = "account", default = UI.defaults[key],
            get = function() return UI.setting(key) end,
            set = function(value) UI.set(key, value); UI.refresh(); if ctx then UI.updateBadge(ctx) end end }
        for k, v in pairs(extra or {}) do entry[k] = v end
        S.add(entry)
    end
    S.page("events", "guild", "Groups & events")
    S.add({ page = "events", kind = "choice", label = L["Default view"], scope = "account", default = "overview",
        desc = L["What Groups & events shows first."], keywords = "kalender calendar übersicht overview",
        options = function() return { { "overview", L["Overview"] }, { "calendar", L["Calendar"] } } end,
        get = function() return UI.setting("view") end, set = function(value) UI.set("view", value) end })
    S.add({ page = "events", kind = "custom", label = L["Preferred activities"], scope = "account",
        desc = L["Notifications about new events and the counter only consider these activities. None selected: all."],
        keywords = "kategorie category aktivität activity",
        build = function(container, entry)
            entry.checks = {}
            for index, category in ipairs(events.categories) do
                local check = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
                check:SetSize(22, 22)
                check:SetPoint("TOPLEFT", 8 + ((index - 1) % 3) * 190, -4 - math.floor((index - 1) / 3) * 24)
                local label = text(check, "GameFontHighlightSmall")
                label:SetPoint("LEFT", check, "RIGHT", 2, 0)
                label:SetText(L[category.label])
                check:SetScript("OnClick", function(self)
                    ForeverGuildSettings = ForeverGuildSettings or {}
                    ForeverGuildSettings.events = ForeverGuildSettings.events or {}
                    ForeverGuildSettings.events.cats = ForeverGuildSettings.events.cats or {}
                    ForeverGuildSettings.events.cats[category.key] = self:GetChecked() and true or nil
                    if ctx then UI.updateBadge(ctx) end
                end)
                entry.checks[category.key] = check
            end
            return 4 + math.ceil(#events.categories / 3) * 24
        end,
        refresh = function(entry)
            local saved = ForeverGuildSettings and ForeverGuildSettings.events and ForeverGuildSettings.events.cats or {}
            for key, check in pairs(entry.checks or {}) do check:SetChecked(saved[key] == true) end
        end })
    S.add({ page = "events", kind = "choice", label = L["Preferred role for sign-ups"], scope = "account", default = "",
        desc = L["Preselected in the sign-up dialog. Without a choice, your saved guild roles are used."],
        options = function()
            return { { "", L["From my guild roles"] }, { "T", L["Tank"] }, { "H", L["Healer"] }, { "D", L["DPS"] } }
        end,
        get = function() return UI.setting("prefRoles") end, set = function(value) UI.set("prefRoles", value) end })
    option("events", "fitsOnly", L["Only show suitable level ranges"],
        L["Preset of the “Suits my character” filter; also limits notifications about new events."])
    option("events", "partners", L["Show partner guild events"], L["Events that partner guilds shared with your guild."])
    option("events", "archiveDone", L["Archive completed events automatically"],
        L["Completed and cancelled events move to the archive of the history after a day."])
    S.add({ page = "events", kind = "number", label = L["Keep past events for (days, 7–90)"], scope = "character",
        desc = L["Older events are removed from this character and do not come back through synchronization."],
        min = 7, max = 90, default = 30,
        get = function() return UI.setting("keepDays") end, set = function(value) UI.set("keepDays", value) end })

    S.page("notifyEvents", "notify", "Groups & events")
    option("notifyEvents", "match", L["New suitable groups and events"], L["When a guild member posts an activity you prefer."])
    option("notifyEvents", "popup", L["Pop-up notifications"], L["Compact window with “Open event”."])
    option("notifyEvents", "chat", L["Chat notifications"], L["A short line in the chat window."])
    option("notifyEvents", "sound", L["Notification sound"], L["Plays the whisper sound of the client."], { keywords = "sound ton audio" })
    option("notifyEvents", "combat", L["Pop-ups during combat (otherwise shown afterwards)"], L["Off: pop-ups wait until combat has ended."])
    option("notifyEvents", "counters", L["Counter at the bulletin board"],
        L["New events and open actions such as sign-ups to confirm. Each event counts once."])
    UI.defaults.counters = true
    for _, entry in ipairs({ { 1440, L["Reminder 24 hours before"] }, { 60, L["Reminder one hour before"] },
        { 30, L["Reminder 30 minutes before"] }, { 15, L["Reminder 15 minutes before"] }, { 0, L["Reminder at the start"] } }) do
        option("notifyEvents", "r" .. entry[1], entry[2], L["For events you organize or signed up for."], { keywords = "erinnerung reminder" })
    end
end

-- Expires automatic archiving: completed/cancelled events older than a day.
function UI.autoArchive(ctx)
    local guild = ctx.guild()
    if not guild or not UI.setting("archiveDone") then return end
    local store, now = events.store(guild), ctx.clock()
    for id, ev in pairs(store.events) do
        if not ev.stub and (ev.status == "done" or ev.status == "cancelled") and events.ends(ev) < now - DAY and store.archived[id] == nil then
            store.archived[id] = true
        end
    end
end

-- Context menu component ------------------------------------------------------------------------------------
-- One shared, fully opaque menu: dark brown background, bronze border, gold title, red
-- destructive entries, grey disabled entries with an explaining tooltip. A full-screen
-- catcher below the menu closes it on any outside click; Escape closes it as well.
-- entries: { text, func, icon, disabled, tooltip, destructive } or { divider = true }
local menu, catcher
local function buildMenu()
    catcher = CreateFrame("Button", "ForeverGuildEventMenuCatcher", UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() menu:Hide() end)
    catcher:Hide()
    menu = CreateFrame("Frame", "ForeverGuildEventMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(20)
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    local base = menu:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetPoint("TOPLEFT", 3, -3)
    base:SetPoint("BOTTOMRIGHT", -3, 3)
    base:SetColorTexture(.09, .062, .042, 1)
    menu:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    menu:SetBackdropBorderColor(.72, .53, .27)
    menu.title = text(menu, "GameFontNormal")
    menu.title:SetPoint("TOPLEFT", 12, -10)
    menu.rows, menu.lines = {}, {}
    menu:SetScript("OnHide", function() catcher:Hide(); GameTooltip:Hide() end)
    tinsert(UISpecialFrames, "ForeverGuildEventMenu")
    menu:Hide()
end

function UI.closeMenu()
    if menu and menu:IsShown() then menu:Hide() end
end

function UI.menu(owner, title, entries)
    if not menu then buildMenu() end
    menu:Hide()
    menu.title:SetText(title or "")
    local y, width, rowIndex, lineIndex = -32, menu.title:GetStringWidth() + 24, 0, 0
    for _, entry in ipairs(entries) do
        if entry.divider then
            lineIndex = lineIndex + 1
            local line = menu.lines[lineIndex]
            if not line then
                line = menu:CreateTexture(nil, "ARTWORK")
                line:SetHeight(1)
                line:SetColorTexture(.45, .31, .16, .9)
                menu.lines[lineIndex] = line
            end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", 10, y - 4)
            line:SetPoint("TOPRIGHT", -10, y - 4)
            line:Show()
            y = y - 9
        else
            rowIndex = rowIndex + 1
            local row = menu.rows[rowIndex]
            if not row then
                row = CreateFrame("Button", nil, menu)
                row:SetHeight(22)
                row.glow = row:CreateTexture(nil, "BACKGROUND")
                row.glow:SetAllPoints()
                row.glow:SetColorTexture(.95, .72, .28, .2)
                row.glow:Hide()
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(16, 16)
                row.icon:SetPoint("LEFT", 6, 0)
                row.icon:SetTexCoord(.07, .93, .07, .93)
                row.label = text(row, "GameFontHighlight")
                row.label:SetPoint("LEFT", 28, 0)
                row:SetScript("OnEnter", function(self)
                    if not self.entry.disabled then self.glow:Show() end
                    if self.entry.tooltip then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(self.entry.text)
                        GameTooltip:AddLine(self.entry.tooltip, 1, 1, 1, true)
                        GameTooltip:Show()
                    end
                end)
                row:SetScript("OnLeave", function(self) self.glow:Hide(); GameTooltip:Hide() end)
                row:SetScript("OnClick", function(self)
                    if self.entry.disabled then return end
                    menu:Hide()
                    if self.entry.func then self.entry.func() end
                end)
                menu.rows[rowIndex] = row
            end
            row.entry = entry
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 6, y)
            row:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
            row.icon:SetShown(entry.icon ~= nil)
            if entry.icon then row.icon:SetTexture(entry.icon) end
            row.label:SetText(entry.text)
            if entry.disabled then color(row.label, MUTED)
            elseif entry.destructive then color(row.label, { 1, .42, .36 })
            else color(row.label, LIGHT) end
            row.glow:Hide()
            row:Show()
            width = math.max(width, row.label:GetStringWidth() + 50)
            y = y - 22
        end
    end
    for index = rowIndex + 1, #menu.rows do menu.rows[index]:Hide() end
    for index = lineIndex + 1, #menu.lines do menu.lines[index]:Hide() end
    menu:SetSize(math.max(190, math.min(380, width)), -y + 10)
    menu:ClearAllPoints()
    local x, cursorY
    if GetCursorPosition then x, cursorY = GetCursorPosition() end
    if x then
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 2, cursorY / scale - 2)
    elseif owner then
        menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    else
        menu:SetPoint("CENTER")
    end
    catcher:Show()
    menu:Show()
    menu:Raise()
end

local ICONS = {
    details = "Interface\\Icons\\INV_Misc_Note_01", edit = "Interface\\Icons\\INV_Feather_05",
    copy = "Interface\\Icons\\INV_Scroll_03", date = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    people = "Interface\\Icons\\INV_Shirt_GuildTabard_01", whisper = "Interface\\Icons\\INV_Letter_02",
    signup = "Interface\\Icons\\Ability_Warrior_BattleShout", cancel = "Interface\\Icons\\Spell_Shadow_SacrificialShield",
    archive = "Interface\\Icons\\INV_Box_01", delete = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    start = "Interface\\Icons\\Ability_Rogue_Sprint", done = "Interface\\Icons\\INV_Misc_Note_02",
    lock = "Interface\\Icons\\INV_Misc_Key_03", invite = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
}
UI.ICONS = ICONS

-- Cancellation with a clear confirmation; for series the scope can be chosen.
function UI.confirmCancel(ctx, ev)
    UI.cancelEvent(ctx, ev)
end

-- Actions of an event, evaluated the same way in every view.
function UI.eventEntries(ctx, ev)
    local me, now = ctx.player(), ctx.clock()
    local list = {}
    local function add(textValue, func, icon, extra)
        local entry = { text = textValue, func = func, icon = icon }
        for key, value in pairs(extra or {}) do entry[key] = value end
        list[#list + 1] = entry
    end
    local function divider() if #list > 0 and not list[#list].divider then list[#list + 1] = { divider = true } end end
    ev.rosterCache = ev.rosterCache or events.roster(ev)
    ev.stateCache = ev.stateCache or events.state(ev, now, ev.rosterCache.counts)
    local state = ev.stateCache
    local active = UI.isActive(ev, now)
    local guild = ctx.guild()
    add(L["Show event details"], function() ctx.openEvent(ev.id) end, ICONS.details)
    if ev.kind == "partner" then
        add(L["Whisper organizer"], function() ctx.whisper(ev.owner) end, ICONS.whisper)
        return list
    end
    if ev.kind == "legacy" then
        if ev.owner == me and active then
            add(L["Take over into the new format"], function() UI.openWizard(ctx, { migrate = ev }) end, ICONS.edit)
            divider()
            add(L["Cancel event"], function() UI.confirm(ctx, L["Cancel event?"], L["CANCEL_CONFIRM"]:format(UI.titleOf(ev)),
                function() ctx.legacyClose(ev) end, L["Cancel event"]) end, ICONS.cancel, { destructive = true })
        elseif ev.owner ~= me then
            local status = UI.myStatus(ctx, ev)
            if active then
                add((status and status ~= "out") and L["Withdraw sign-up"] or L["Sign up"], function() ctx.legacyReply(ev) end, ICONS.signup)
            end
            add(L["Whisper organizer"], function() ctx.whisper(ev.owner) end, ICONS.whisper)
        end
        return list
    end
    local manage = events.mayManage(ev, me)
    local owner = ev.owner == me
    local open = state == "open" or state == "full" or state == "ready" or state == "closed"
    if manage then
        if open then
            add(L["Edit event"], function() UI.openWizard(ctx, { edit = ev }) end, ICONS.edit)
        end
        local copyable = UI.copyable(ev)
        add(L["Copy event"], function() UI.openWizard(ctx, { copy = ev }) end, ICONS.copy, { disabled = not ctx.canPost() or not copyable,
            tooltip = (not copyable and L["This activity is coming soon and cannot be planned yet."])
                or (not ctx.canPost() and L["You are not allowed to post groups and events."]) or nil })
        if open then
            add(L["Move date"], function() UI.openWizard(ctx, { edit = ev, step = 3 }) end, ICONS.date)
            add(L["Manage participants"], function() ctx.openEvent(ev.id) end, ICONS.people)
            if owner then add(L["Manage co-organizers"], function() UI.openWizard(ctx, { edit = ev, step = 3 }) end, ICONS.people) end
        end
        divider()
        if ev.status == "open" and open then
            add(L["Close sign-up"], function() if events.setStatus(ev, "closed", now) then UI.sendEvent(ctx, ev) end end, ICONS.lock)
        elseif ev.status == "closed" and open then
            add(L["Reopen sign-up"], function() if events.setStatus(ev, "open", now) then UI.sendEvent(ctx, ev) end end, ICONS.lock)
        end
        if open then
            add(L["Start event"], function() if events.setStatus(ev, "started", ctx.clock()) then UI.sendEvent(ctx, ev) end end, ICONS.start)
        elseif ev.status == "started" then
            add(L["Complete event"], function()
                UI.confirm(ctx, L["Complete event?"], L["Participants can then be marked as attended or no-show."], function()
                    if events.setStatus(ev, "done", ctx.clock()) then UI.sendEvent(ctx, ev) end
                end, L["Complete event"])
            end, ICONS.done)
        end
        add(L["Message with event details"], function() UI.showMessage(ctx, ev) end, ICONS.whisper)
    else
        local status = UI.myStatus(ctx, ev)
        local signed = status and status ~= "out"
        if ev.status == "open" and (state == "open" or state == "full" or state == "ready") then
            if not signed then
                local full = ev.rosterCache.counts.full
                add(full and L["Join the waitlist"] or L["Sign up"], function() UI.openSignup(ctx, ev) end, ICONS.signup)
                add(L["Sign up tentatively"], function() UI.openSignup(ctx, ev, "tent") end, ICONS.signup)
            elseif status ~= "rejected" then
                add(L["Change sign-up"], function() UI.openSignup(ctx, ev) end, ICONS.edit)
            end
        end
        if signed and status ~= "rejected" and active then
            add(L["Withdraw sign-up"], function() UI.withdraw(ctx, ev) end, ICONS.cancel)
        end
        divider()
        local organizer = ctx.member(ev.owner)
        add(L["Whisper organizer"], function() ctx.whisper(ev.owner) end, ICONS.whisper, { disabled = not (organizer and organizer.online),
            tooltip = not (organizer and organizer.online) and L["The organizer is offline."] or nil })
        if ctx.canPost() then
            add(L["Copy event as template"], function() UI.openWizard(ctx, { copy = ev }) end, ICONS.copy, { disabled = not UI.copyable(ev),
                tooltip = not UI.copyable(ev) and L["This activity is coming soon and cannot be planned yet."] or nil })
        end
    end
    -- Local archive and deletion.
    divider()
    local archived = guild and events.store(guild).archived[ev.id]
    add(archived and L["Restore from archive"] or L["Archive event"], function()
        events.archive(guild, ev.id, not archived)
        UI.refresh()
    end, ICONS.archive, { tooltip = not archived and L["Removes the event from the active overview; it stays in the history."] or nil })
    if owner and active then
        add(L["Cancel event"], function() UI.cancelEvent(ctx, ev) end, ICONS.cancel, { destructive = true })
    end
    if owner or not active then
        local blocked = active and events.hasParticipants(ev)
        add(L["Delete event"], function()
            UI.confirm(ctx, L["Delete event?"], active and L["DELETE_ACTIVE_CONFIRM"]:format(UI.titleOf(ev))
                or L["The event is removed from this character only and does not come back through synchronization."], function()
                if events.delete(guild, ev, me, ctx.clock(), ctx.send) then UI.refresh() end
            end, L["Delete"])
        end, ICONS.delete, { destructive = true, disabled = blocked,
            tooltip = blocked and L["Players have signed up. Cancel the event first so they are informed."] or nil })
    end
    return list
end

-- Only open activities can be planned again from a copy.
function UI.copyable(ev)
    local category = events.byCategory[ev.cat or ""]
    return category ~= nil and not category.soon and not category.retired
end

function UI.eventMenu(ctx, ev, owner)
    if not ev then return end
    UI.menu(owner, UI.titleOf(ev), UI.eventEntries(ctx, ev))
end

function UI.withdraw(ctx, ev)
    UI.confirm(ctx, L["Withdraw sign-up?"], L["The organizer is informed. You can sign up again later if places are free."], function()
        local mine = events.signUp(ev, ctx.player(), { state = "out" }, ctx.clock())
        if mine then UI.sendSignup(ctx, ev, mine) end
    end, L["Withdraw"])
end

-- Actions for a participant row.
function UI.memberEntries(ctx, ev, entry)
    local me = ctx.player()
    local manage = ev.kind == "event" and events.mayManage(ev, me)
    local member = ctx.member(entry.name)
    local online = member and member.online
    local list = {}
    local function add(textValue, func, icon, extra)
        local item = { text = textValue, func = func, icon = icon }
        for key, value in pairs(extra or {}) do item[key] = value end
        list[#list + 1] = item
    end
    add(L["Show character info"], function() ctx.showMember(entry.name) end, ICONS.details, { disabled = member == nil })
    if entry.name ~= me then
        add(L["Whisper"], function() ctx.whisper(entry.name) end, ICONS.whisper, { disabled = not online,
            tooltip = not online and L["This player is offline."] or nil })
        if manage then
            add(L["Invite to group"], function() ctx.invite(entry.name) end, ICONS.invite, { disabled = not (online and ctx.canInvite()),
                tooltip = L["Sends a normal group invitation; the player accepts it in the game."] })
        end
    end
    if manage and entry.name ~= ev.owner and entry.status ~= "out" then
        list[#list + 1] = { divider = true }
        local placed = entry.status == "confirmed" or entry.status == "tentative" or entry.status == "attended"
        if entry.status == "waitlist" then
            add(L["Take from the waitlist"], function() UI.decide(ctx, ev, entry.name, "C", entry.role) end, ICONS.signup)
        elseif not placed then
            add(L["Confirm sign-up"], function() UI.decide(ctx, ev, entry.name, "C", entry.role) end, ICONS.signup)
        end
        if entry.status ~= "rejected" and entry.status ~= "attended" then
            add(L["Decline sign-up"], function() UI.decide(ctx, ev, entry.name, "R", entry.role) end, ICONS.cancel)
        end
        if ev.slots then
            for _, role in ipairs({ "T", "H", "D" }) do
                if ev.slots[role] > 0 and role ~= entry.role then
                    add(L["Change role to %s"]:format(L[ROLE_NAMES[role]]), function()
                        UI.decide(ctx, ev, entry.name, placed and (entry.decision and entry.decision.d or "C") or "C", role)
                    end, ICONS.people)
                end
            end
        end
        if entry.status ~= "waitlist" then
            add(L["Move to waitlist"], function() UI.decide(ctx, ev, entry.name, "W", entry.role) end, ICONS.archive)
        end
        if ev.status == "started" or ev.stateCache == "expired" or ev.status == "done" then
            add(L["Confirm attendance"], function() UI.decide(ctx, ev, entry.name, "A", entry.role) end, ICONS.done)
            add(L["Mark as no-show"], function() UI.decide(ctx, ev, entry.name, "N", entry.role) end, ICONS.cancel)
        end
        list[#list + 1] = { divider = true }
        add(L["Remove participant"], function()
            UI.confirm(ctx, L["Remove participant?"], L["%s is removed from the event and informed."]:format(ctx.displayName(entry.name)),
                function() UI.decide(ctx, ev, entry.name, "R", entry.role) end, L["Remove"])
        end, ICONS.delete, { destructive = true })
    end
    return list
end
