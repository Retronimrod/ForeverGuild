local _, addon = ...
-- Groups & events: shared event model, life cycle, sign-ups, waitlist, recurring series,
-- reminders and the guild sync protocol. Pure logic without frames; the WoW API is only
-- reached through arguments, so the module is testable outside the client.
--
-- Sync model (no central server):
--   * The organizer owns the event data (header + text parts) and the decisions about
--     participants. Every change raises the event revision; older data is ignored.
--   * Each member owns their own sign-up (state, role, alternative roles, note) with a
--     member revision. A decision refers to the sign-up revision it was made for, so a
--     sign-up that the organizer has not seen yet is never shown as confirmed.
--   * Cancelled and completed events cannot be reopened by older packets, and locally
--     removed events are kept as tombstones so synchronization cannot bring them back.
local events = {}
addon.events = events

local DAY, HOUR = 86400, 3600
events.MAX_AHEAD = 60 * DAY          -- latest start that is accepted
events.SERIES_AHEAD = 4              -- future occurrences that exist at the same time
events.SERIES_MAX = 12               -- occurrences of one series in total
events.SHARE_EVERY = 150             -- organizer re-share interval (seconds)
events.SIGNUP_SHARE_EVERY = 210      -- member re-share interval for their own sign-up
events.PACKETS_PER_TICK = 6

-- Category catalog: key, English label, description, icon, banner art, default group model.
events.categories = {
    { key = "dungeon", label = "Dungeon", desc = "Dungeon runs, specific bosses or several runs in a row.",
      icon = "Interface\\Icons\\Spell_Arcane_PortalIronForge", art = "DungeonHall", model = "dungeon" },
    { key = "raid", label = "Raid", desc = "Planned raids and guild raids.",
      icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", art = "BlackrockHall", model = "raid", soon = true },
    { key = "quest", label = "Quest group", desc = "Group quests, elite quests and quest chains.",
      icon = "Interface\\Icons\\INV_Misc_Map_01", art = "GuildHall", model = "free" },
    { key = "recipe", label = "Recipe run", desc = "Farm a specific crafting recipe together.",
      icon = "Interface\\Icons\\INV_Scroll_03", art = "GuildProfessions", model = "dungeon" , soon = true },
    { key = "gear", label = "Gear run", desc = "Farm weapons, armor or other items.",
      icon = "Interface\\Icons\\INV_Sword_04", art = "DungeonHall", model = "dungeon" , soon = true },
    { key = "material", label = "Material farming", desc = "Gather cloth, ore, herbs and more together.",
      icon = "Interface\\Icons\\INV_Ore_Copper_01", art = "GuildProfessions", model = "free" , soon = true },
    { key = "rep", label = "Reputation farming", desc = "Raise your standing with a faction together.",
      icon = "Interface\\Icons\\INV_Misc_Token_ArgentDawn", art = "GuildHall", model = "free" },
    { key = "level", label = "Leveling group", desc = "Quest and level up together.",
      icon = "Interface\\Icons\\Spell_Nature_Swiftness", art = "GuildHall", model = "free" , soon = true },
    { key = "profession", label = "Profession group", desc = "Level crafting professions together.",
      icon = "Interface\\Icons\\Trade_BlackSmithing", art = "GuildProfessions", model = "free" , retired = true },
    { key = "worldboss", label = "World boss", desc = "Gather a group for a world boss.",
      icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Green", art = "BlackrockHall", model = "raid" , soon = true },
    { key = "pvp", label = "PvP", desc = "Battlegrounds and PvP together.",
      icon = "Interface\\Icons\\Ability_DualWield", art = "GuildAdministration", model = "free" , soon = true },
    { key = "guild", label = "Guild event", desc = "Guild meetings, contests and celebrations.",
      icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", art = "GuildHall", model = "open" , retired = true },
    { key = "help", label = "Help wanted", desc = "Get help with a personal task.",
      icon = "Interface\\Icons\\INV_Misc_Note_01", art = "GuildHall", model = "free" , retired = true },
    { key = "other", label = "Other", desc = "Any other activity you describe yourself.",
      icon = "Interface\\Icons\\INV_Misc_Bag_10", art = "GuildHall", model = "free" , retired = true },
}
-- Activities offered when creating an event (retired ones stay readable for older events).
events.creatable = {}
events.byCategory = {}
for index, category in ipairs(events.categories) do
    category.order = index
    events.byCategory[category.key] = category
    if not category.retired then events.creatable[#events.creatable + 1] = category end
end
-- Available activities first, "Coming Soon" afterwards (stable within each group).
table.sort(events.creatable, function(a, b)
    if (a.soon or false) ~= (b.soon or false) then return not a.soon end
    return a.order < b.order
end)

events.models = { dungeon = true, raid = true, free = true, open = true, custom = true }
events.goals = { "full", "bosses", "quest", "recipe", "gear", "multi", "custom" }
events.lootRules = { "need", "recipe", "item", "mats", "custom" }
events.roles = { "T", "H", "D" }
local validGoal, validLoot = {}, {}
for _, goal in ipairs(events.goals) do validGoal[goal] = true end
for _, rule in ipairs(events.lootRules) do validLoot[rule] = true end
local validStatus = { open = true, closed = true, started = true, done = true, cancelled = true }
local validState = { ["in"] = true, tent = true, out = true }
local validDecision = { C = true, W = true, R = true, A = true, N = true }

-- Removes characters that would break the packet format or the chat/UI markup.
function events.clean(value, limit)
    value = tostring(value or ""):gsub("[%c|~;]", " "):gsub("%s+", " ")
    value = value:match("^%s*(.-)%s*$")
    if limit and #value > limit then
        value = value:sub(1, limit)
        -- Never cut a multi-byte UTF-8 character in half.
        while #value > 0 and value:byte(#value) >= 128 and value:byte(#value) < 192 do value = value:sub(1, -2) end
        if #value > 0 and value:byte(#value) >= 192 then value = value:sub(1, -2) end
    end
    return value
end

local function num(value)
    value = tonumber(value)
    if not value or value ~= value or value % 1 ~= 0 or value < 0 or value > 4294967295 then return nil end
    return value
end

function events.id(owner, token) return owner .. "/" .. token end

function events.token(now)
    ForeverGuildOrderSequence = (ForeverGuildOrderSequence or 0) + 1
    return ("%.0f-%d"):format(now, ForeverGuildOrderSequence)
end

local function tokenTime(token)
    return token and #token <= 24 and tonumber(token:match("^(%d+)%-%d+$"))
end

-- Storage -----------------------------------------------------------------------------------------

function events.store(guild)
    ForeverGuildEvents = ForeverGuildEvents or {}
    local root = ForeverGuildEvents[guild]
    if not root then
        root = {}
        ForeverGuildEvents[guild] = root
    end
    root.events = root.events or {}
    root.tombs = root.tombs or {}
    root.archived = root.archived or {}
    root.seen = root.seen or {}
    root.series = root.series or {}
    root.read = root.read or {}
    return root
end

function events.all(guild)
    if not guild then return {} end
    return events.store(guild).events
end

-- Life cycle ------------------------------------------------------------------------------------

-- End of an event: start plus a stored duration (older events). New events have no
-- duration, so their end is the start itself; nothing is invented.
function events.ends(ev)
    if ev.mode == "now" then return math.max(ev.expires or ev.starts, ev.starts) + (ev.duration or 0) * 60 end
    return ev.starts + (ev.duration or 0) * 60
end

-- An event that was never started moves to the history this long after its start/end.
-- It is shown as "Expired" there, never as completed; the organizer can still manage it.
events.GRACE = 6 * HOUR

-- Derived state: draft states are never stored; "ready" and "full" depend on the roster.
function events.state(ev, now, counts)
    if ev.status == "cancelled" then return "cancelled" end
    if ev.status == "done" then return "done" end
    if ev.status == "started" then return "started" end
    if ev.mode == "now" and now >= (ev.expires or ev.starts) then return "expired" end
    if ev.mode ~= "now" and now >= events.ends(ev) + events.GRACE then return "expired" end
    if ev.status == "closed" or (ev.deadline and now >= ev.deadline) then return "closed" end
    counts = counts or events.roster(ev).counts
    if counts.full then
        if ev.mode == "now" or ev.starts - now <= 30 * 60 then return "ready" end
        return "full"
    end
    return "open"
end

-- Active events appear in the group search; everything else belongs to the history.
function events.active(ev, now)
    local state = events.state(ev, now)
    if state == "cancelled" or state == "done" or state == "expired" then return false end
    -- A started event stays visible for a while so the organizer can complete it.
    if state == "started" then return now < events.ends(ev) + 2 * events.GRACE end
    return true
end

function events.mayManage(ev, name)
    if not ev or not name then return false end
    if ev.owner == name then return true end
    for _, other in ipairs(ev.coorg or {}) do if other == name then return true end end
    return false
end

-- Roster: combines member sign-ups and organizer decisions -------------------------------------------

local STATUS_ORDER = { confirmed = 1, tentative = 2, attended = 3, signed = 4, waitlist = 5, noshow = 6, rejected = 7, out = 8 }
events.statusOrder = STATUS_ORDER

local function decisionValid(signup, decision)
    if not decision then return false end
    if not signup then return true end -- added by the organizer (or migrated)
    return (decision.mrev or 0) >= (signup.rev or 0)
end

-- Returns { entries, counts } where counts[T/H/D] are occupied role slots, counts.total the
-- occupied places, counts.capacity the places in total (nil = open), counts.full.
function events.roster(ev, eligible)
    local entries, counts = {}, { T = 0, H = 0, D = 0, total = 0, waitlist = 0, pending = 0 }
    local names = {}
    for name in pairs(ev.signups or {}) do names[name] = true end
    for name in pairs(ev.decisions or {}) do names[name] = true end
    for name in pairs(names) do
        if name ~= ev.owner and (not eligible or eligible(name)) then
            local signup, decision = ev.signups and ev.signups[name], ev.decisions and ev.decisions[name]
            local status, role = "signed", signup and signup.role
            local valid = decisionValid(signup, decision)
            if signup and signup.state == "out" then
                status = "out"
            elseif valid then
                local code = decision.d
                status = (code == "C" and (signup and signup.state == "tent" and "tentative" or "confirmed"))
                    or (code == "W" and "waitlist") or (code == "R" and "rejected")
                    or (code == "A" and "attended") or (code == "N" and "noshow") or "signed"
                role = decision.role or role
            end
            entries[#entries + 1] = { name = name, status = status, role = role, signup = signup, decision = decision,
                alt = signup and signup.alt or "", note = signup and signup.note or "", at = signup and signup.at or 0,
                synced = valid }
            if status == "confirmed" or status == "tentative" or status == "attended" then
                counts.total = counts.total + 1
                if role and counts[role] then counts[role] = counts[role] + 1 end
            elseif status == "waitlist" then
                counts.waitlist = counts.waitlist + 1
            elseif status == "signed" then
                counts.pending = counts.pending + 1
            end
        end
    end
    -- The organizer always takes part, with their own role.
    counts.total = counts.total + 1
    if ev.ownerRole and counts[ev.ownerRole] then counts[ev.ownerRole] = counts[ev.ownerRole] + 1 end
    table.sort(entries, function(a, b)
        local first, second = STATUS_ORDER[a.status] or 9, STATUS_ORDER[b.status] or 9
        if first ~= second then return first < second end
        if a.at ~= b.at then return a.at < b.at end
        return a.name < b.name
    end)
    if ev.model == "open" then
        counts.capacity = nil
    elseif ev.slots then
        counts.capacity = ev.slots.T + ev.slots.H + ev.slots.D
        counts.full = counts.T >= ev.slots.T and counts.H >= ev.slots.H and counts.D >= ev.slots.D
    else
        counts.capacity = ev.size
    end
    if counts.capacity and not ev.slots then counts.full = counts.total >= counts.capacity end
    return { entries = entries, counts = counts }
end

-- Free places for a role (nil role = any). Returns a number (math.huge when unlimited).
function events.free(ev, counts, role)
    if ev.model == "open" then return math.huge end
    if ev.slots then
        if role then return math.max(0, (ev.slots[role] or 0) - (counts[role] or 0)) end
        return math.max(0, ev.slots.T - counts.T) + math.max(0, ev.slots.H - counts.H) + math.max(0, ev.slots.D - counts.D)
    end
    return math.max(0, (ev.size or 0) - counts.total)
end

-- Waitlisted members that could take a free role (own or alternative role).
function events.candidates(ev, role)
    local list = {}
    for _, entry in ipairs(events.roster(ev).entries) do
        if entry.status == "waitlist" and (entry.role == role or (entry.alt or ""):find(role, 1, true)) then
            list[#list + 1] = entry
        end
    end
    return list
end

-- Validation and creation -------------------------------------------------------------------------

local function validSlots(slots, total)
    if type(slots) ~= "table" then return false end
    local sum = 0
    for _, role in ipairs(events.roles) do
        local n = slots[role]
        if type(n) ~= "number" or n < 0 or n > 40 or n % 1 ~= 0 then return false end
        sum = sum + n
    end
    return sum >= 1 and sum <= (total or 40)
end

local function validTargets(targets)
    if targets == nil then return true end
    if type(targets) ~= "table" or #targets > 6 then return false end
    for _, target in ipairs(targets) do
        if target.k == "t" then
            if type(target.text) ~= "string" or target.text == "" or #target.text > 48 then return false end
        elseif target.k == "f" then
            -- Reputation goal: faction ID (0 = entered by name), target standing 1-8, faction name.
            if not num(target.id) or not num(target.standing) or target.standing < 1 or target.standing > 8
                or type(target.text) ~= "string" or target.text == "" or #target.text > 48 then return false end
        elseif target.k == "i" or target.k == "q" or target.k == "r" then
            if not num(target.id) or target.id < 1 then return false end
        else
            return false
        end
    end
    return true
end

-- Checks a complete event record; returns true or false plus a reason key.
function events.validate(ev, now)
    if not events.byCategory[ev.cat] then return false, "category" end
    if type(ev.title) ~= "string" or ev.title == "" or #ev.title > 52 then return false, "title" end
    if not num(ev.starts) or ev.starts > now + events.MAX_AHEAD then return false, "start" end
    if ev.mode ~= "now" and ev.mode ~= "plan" then return false, "mode" end
    if ev.mode == "now" and (not num(ev.expires) or ev.expires <= ev.starts or ev.expires > ev.starts + 12 * HOUR) then
        return false, "runtime"
    end
    if ev.duration and (not num(ev.duration) or ev.duration < 10 or ev.duration > 24 * 60) then return false, "duration" end
    if ev.deadline and (not num(ev.deadline) or ev.deadline > ev.starts) then return false, "deadline" end
    if ev.minLevel and (not num(ev.minLevel) or ev.minLevel < 1 or ev.minLevel > 60) then return false, "level" end
    if ev.maxLevel and (not num(ev.maxLevel) or ev.maxLevel < 1 or ev.maxLevel > 60) then return false, "level" end
    if ev.minLevel and ev.maxLevel and ev.minLevel > ev.maxLevel then return false, "level" end
    if not events.models[ev.model] then return false, "model" end
    if ev.model == "dungeon" or ev.model == "raid" or ev.model == "custom" then
        if not validSlots(ev.slots) then return false, "slots" end
        if not ev.ownerRole or (ev.slots[ev.ownerRole] or 0) < 1 then return false, "ownerRole" end
    elseif ev.model == "free" then
        if not num(ev.size) or ev.size < 2 or ev.size > 40 then return false, "size" end
    end
    if ev.goal and not validGoal[ev.goal] then return false, "goal" end
    if ev.runs and (not num(ev.runs) or ev.runs < 1 or ev.runs > 10) then return false, "runs" end
    if ev.dungeon and not (addon.getGroupDungeon and addon.getGroupDungeon(ev.dungeon)) then return false, "dungeon" end
    if not validTargets(ev.targets) then return false, "targets" end
    if ev.loot and (not validLoot[ev.loot.rule]) then return false, "loot" end
    if #(ev.desc or "") > 150 or #(ev.req or "") > 100 or #(ev.place or "") > 60 then return false, "text" end
    return true
end

local COPY = { "cat", "mode", "title", "desc", "req", "place", "starts", "duration", "deadline", "expires", "minLevel",
    "maxLevel", "model", "size", "ownerRole", "approve", "autofill", "partners", "dungeon", "goal", "runs" }

local function copyTargets(targets)
    if not targets then return nil end
    local copy = {}
    for index, target in ipairs(targets) do
        copy[index] = { k = target.k, id = target.id, text = target.text, standing = target.standing }
    end
    return copy
end

function events.copyFields(source)
    local fields = {}
    for _, key in ipairs(COPY) do fields[key] = source[key] end
    if source.slots then fields.slots = { T = source.slots.T, H = source.slots.H, D = source.slots.D } end
    fields.targets = copyTargets(source.targets)
    if source.loot then fields.loot = { rule = source.loot.rule, item = source.loot.item, who = source.loot.who, text = source.loot.text } end
    if source.coorg then
        fields.coorg = {}
        for index, name in ipairs(source.coorg) do fields.coorg[index] = name end
    end
    return fields
end

local function normalize(fields)
    fields.title = events.clean(fields.title, 52)
    fields.desc = events.clean(fields.desc, 150)
    fields.req = events.clean(fields.req, 100)
    fields.place = events.clean(fields.place, 60)
    if fields.model == "open" or fields.model == "free" then fields.slots, fields.ownerRole = nil, fields.ownerRole end
    if fields.model ~= "free" then fields.size = nil end
    if fields.loot then
        fields.loot.text = events.clean(fields.loot.text, 80)
        if fields.loot.who then fields.loot.who = events.clean(fields.loot.who, 48) end
        if fields.loot.who == "" then fields.loot.who = nil end
    end
    for _, target in ipairs(fields.targets or {}) do
        if target.k == "t" or target.k == "f" then target.text = events.clean(target.text, 48) end
    end
end

local function apply(ev, fields)
    for _, key in ipairs(COPY) do ev[key] = fields[key] end
    ev.slots = fields.slots and { T = fields.slots.T, H = fields.slots.H, D = fields.slots.D } or nil
    ev.targets = copyTargets(fields.targets)
    ev.loot = fields.loot and { rule = fields.loot.rule, item = fields.loot.item, who = fields.loot.who, text = fields.loot.text }
end

-- Creates an event (and, for a series, its first occurrences). Returns the first event or nil, reason.
function events.create(guild, owner, fields, now, repeatEvery, repeatCount)
    fields = events.copyFields(fields)
    normalize(fields)
    local category = events.byCategory[fields.cat]
    if not category or category.retired or category.soon then return nil, "category" end
    local ok, reason = events.validate(fields, now)
    if not ok then return nil, reason end
    if fields.mode == "plan" and fields.starts <= now then return nil, "start" end
    local store = events.store(guild)
    local token = events.token(now)
    local ev = { owner = owner, token = token, rev = 1, lootRev = fields.loot and 1 or 0, status = "open",
        signups = {}, decisions = {}, created = now, coorg = fields.coorg }
    apply(ev, fields)
    if repeatEvery and repeatCount and repeatCount > 1 and fields.mode == "plan" then
        repeatCount = math.min(repeatCount, events.SERIES_MAX)
        ev.series = { sid = token, index = 1, total = repeatCount, every = repeatEvery }
        store.series[token] = { owner = owner, every = repeatEvery, total = repeatCount, created = 1,
            fields = events.copyFields(ev), first = ev.starts, cancelledFrom = nil }
    end
    store.events[events.id(owner, token)] = ev
    ev.dirty, ev.nextShare = true, 0
    if ev.series then events.extendSeries(guild, owner, now) end
    return ev
end

-- Organizer side: keeps up to SERIES_AHEAD future occurrences per series.
function events.extendSeries(guild, owner, now)
    local store = events.store(guild)
    local created = {}
    for sid, series in pairs(store.series) do
        if series.owner == owner and series.created < series.total and not series.stopped then
            local future = 0
            for _, ev in pairs(store.events) do
                if ev.series and ev.series.sid == sid and ev.starts > now and ev.status ~= "cancelled" then future = future + 1 end
            end
            while future < events.SERIES_AHEAD and series.created < series.total do
                local index = series.created + 1
                local starts = series.first + (index - 1) * series.every * DAY
                series.created = index
                if starts > now and starts <= now + events.MAX_AHEAD then
                    local fields = events.copyFields(series.fields)
                    local offset = starts - fields.starts
                    fields.starts = starts
                    if fields.deadline then fields.deadline = fields.deadline + offset end
                    local token = events.token(now)
                    local ev = { owner = owner, token = token, rev = 1, lootRev = fields.loot and 1 or 0, status = "open",
                        signups = {}, decisions = {}, created = now, coorg = fields.coorg,
                        series = { sid = sid, index = index, total = series.total, every = series.every } }
                    apply(ev, fields)
                    ev.dirty, ev.nextShare = true, 0
                    store.events[events.id(owner, token)] = ev
                    created[#created + 1] = ev
                    future = future + 1
                elseif starts > now + events.MAX_AHEAD then
                    series.created = index - 1
                    break
                end
            end
        end
    end
    return created
end

-- Organizer edit. Returns a change set { moved, loot } or nil, reason.
function events.edit(ev, fields, now)
    fields = events.copyFields(fields)
    normalize(fields)
    local ok, reason = events.validate(fields, now)
    if not ok then return nil, reason end
    if ev.status == "cancelled" or ev.status == "done" then return nil, "status" end
    local changes = { moved = fields.starts ~= ev.starts }
    local function lootKey(loot) return loot and (loot.rule .. "/" .. tostring(loot.item) .. "/" .. tostring(loot.who) .. "/" .. (loot.text or "")) or "" end
    if lootKey(fields.loot) ~= lootKey(ev.loot) then
        changes.loot = true
        ev.lootRev = (ev.lootRev or 0) + 1
    end
    apply(ev, fields)
    ev.coorg = fields.coorg
    ev.rev = ev.rev + 1
    ev.dirty, ev.nextShare = true, 0
    return changes
end

-- Organizer status change with the allowed transitions only.
local TRANSITIONS = {
    open = { closed = true, started = true, cancelled = true },
    closed = { open = true, started = true, cancelled = true },
    started = { done = true, cancelled = true },
}
function events.setStatus(ev, status, now)
    local allowed = TRANSITIONS[ev.status]
    if not allowed or not allowed[status] then return false end
    if status == "open" and now >= events.ends(ev) + events.GRACE then return false end
    ev.status = status
    ev.rev = ev.rev + 1
    ev.dirty, ev.nextShare = true, 0
    return true
end

-- Applies an edit or cancellation to the following occurrences of a series as well.
function events.seriesMembers(guild, ev, fromHere)
    local list = {}
    if not ev.series then return { ev } end
    for _, other in pairs(events.all(guild)) do
        if other.owner == ev.owner and other.series and other.series.sid == ev.series.sid
            and (not fromHere or other.series.index >= ev.series.index) then
            list[#list + 1] = other
        end
    end
    table.sort(list, function(a, b) return a.series.index < b.series.index end)
    return list
end

function events.stopSeries(guild, ev)
    local series = ev.series and events.store(guild).series[ev.series.sid]
    if series then series.stopped = true end
end

function events.updateSeriesTemplate(guild, ev)
    local series = ev.series and events.store(guild).series[ev.series.sid]
    if not series then return end
    local fields = events.copyFields(ev)
    -- Keep the time of day and the rhythm; the template start follows the edited occurrence.
    series.first = ev.starts - (ev.series.index - 1) * series.every * DAY
    fields.starts = series.first
    if ev.deadline then fields.deadline = series.first - (ev.starts - ev.deadline) end
    series.fields = fields
end

-- Member sign-up ---------------------------------------------------------------------------------

-- fields: state ("in"/"tent"/"out"), role, alt (string of role letters), note, lootAck.
function events.signUp(ev, player, fields, now)
    if ev.owner == player or ev.status == "cancelled" or ev.status == "done" then return nil end
    local state = fields.state
    if not validState[state] then return nil end
    local old = ev.signups[player]
    if state ~= "out" then
        if ev.status ~= "open" or (ev.deadline and now >= ev.deadline) or not events.active(ev, now) then return nil end
        if ev.slots and (not fields.role or (ev.slots[fields.role] or 0) < 1) then return nil end
    elseif not old or old.state == "out" then
        return nil
    end
    local alt = ""
    for _, role in ipairs(events.roles) do
        if (fields.alt or ""):find(role, 1, true) and role ~= fields.role and (not ev.slots or ev.slots[role] > 0) then
            alt = alt .. role
        end
    end
    local signup = { state = state, role = ev.slots and fields.role or nil, alt = alt, note = events.clean(fields.note, 60),
        rev = (old and old.rev or 0) + 1,
        at = (old and old.state ~= "out" and old.at) or now,
        lootAck = fields.lootAck or (old and old.lootAck) or ev.lootRev or 0, mine = true, nextShare = 0 }
    if state == "out" then signup.role, signup.alt = old.role, old.alt end
    ev.signups[player] = signup
    return signup
end

-- Organizer decision about a member. code: C, W, R, A, N or nil (remove the decision).
function events.decide(ev, member, code, role, now)
    if code and not validDecision[code] then return nil end
    if role and ev.slots and (ev.slots[role] or 0) < 1 then return nil end
    local signup = ev.signups[member]
    local old = ev.decisions[member]
    local decision = { d = code or "-", role = role or (signup and signup.role), mrev = signup and signup.rev or 0,
        drev = (old and old.drev or 0) + 1, at = now }
    ev.decisions[member] = decision
    ev.dirty, ev.nextShare = true, ev.nextShare or 0
    decision.pending = true
    return decision
end

-- Organizer client: confirms sign-ups automatically (if enabled), keeps decisions for
-- changes that do not affect the place and fills free places from the waitlist.
-- Processing order is the sign-up time, then the name, so every client agrees.
function events.reconcile(ev, now)
    local changed = {}
    if ev.status ~= "open" and ev.status ~= "closed" then return changed end
    local roster = events.roster(ev)
    for _, entry in ipairs(roster.entries) do
        local signup, decision = entry.signup, entry.decision
        if signup and signup.state ~= "out" and decision and (decision.mrev or 0) < signup.rev then
            -- Same role as before: the place is kept; otherwise the sign-up is decided again.
            local keep = decision.d ~= "-" and (decision.role == signup.role or not ev.slots)
                and not (decision.d == "W" and not ev.approve)
            if keep then
                local again = events.decide(ev, entry.name, decision.d, decision.role, now)
                changed[#changed + 1] = { name = entry.name, decision = again }
            end
        end
    end
    -- Sign-ups whose decision is outdated now count as open again.
    roster = events.roster(ev)
    local counts = roster.counts
    if ev.approve then return changed end
    local function place(entry)
        local wanted = { entry.role }
        for role in (entry.alt or ""):gmatch("[THD]") do wanted[#wanted + 1] = role end
        for _, role in ipairs(wanted) do
            if events.free(ev, counts, ev.slots and role or nil) > 0 then return role or "D" end
        end
        if not ev.slots and events.free(ev, counts) > 0 then return entry.role or "D" end
    end
    local queue = {}
    for _, entry in ipairs(roster.entries) do
        if entry.status == "signed" or (entry.status == "waitlist" and ev.autofill) then queue[#queue + 1] = entry end
    end
    table.sort(queue, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.name < b.name
    end)
    for _, entry in ipairs(queue) do
        local role = place(entry)
        if role then
            if ev.slots then counts[role] = counts[role] + 1 end
            counts.total = counts.total + 1
            changed[#changed + 1] = { name = entry.name, decision = events.decide(ev, entry.name, "C", ev.slots and role or nil, now),
                promoted = entry.status == "waitlist" }
        elseif entry.status == "signed" then
            changed[#changed + 1] = { name = entry.name, decision = events.decide(ev, entry.name, "W", entry.role, now) }
        end
    end
    return changed
end

-- Packets -------------------------------------------------------------------------------------------
-- All packets start with "E" and use "~" as separator. Text fields are cleaned of "~", "|",
-- ";" and control characters. Every packet stays below the 255-byte addon message limit.

local function flagString(ev)
    return (ev.approve and "a" or "") .. (ev.autofill and "f" or "") .. (ev.partners and "p" or "")
end

local function partsMask(ev)
    local mask = 0
    if (ev.desc or "") ~= "" or (ev.req or "") ~= "" then mask = mask + 1 end
    if ev.targets and #ev.targets > 0 then mask = mask + 2 end
    if ev.loot then mask = mask + 4 end
    if ev.coorg and #ev.coorg > 0 then mask = mask + 8 end
    return mask
end

local function encodeTargets(targets)
    local parts = {}
    for _, target in ipairs(targets or {}) do
        if target.k == "t" then parts[#parts + 1] = "t" .. target.text
        elseif target.k == "f" then parts[#parts + 1] = ("f%d,%d,%s"):format(target.id, target.standing, (target.text:gsub(",", " ")))
        else parts[#parts + 1] = target.k .. target.id end
    end
    return table.concat(parts, ";")
end

local function decodeTargets(text)
    local list = {}
    for part in (text or ""):gmatch("[^;]+") do
        local kind, rest = part:sub(1, 1), part:sub(2)
        if kind == "t" then list[#list + 1] = { k = "t", text = rest }
        elseif kind == "f" then
            local id, standing, name = rest:match("^(%d+),(%d),(.+)$")
            if id then list[#list + 1] = { k = "f", id = tonumber(id), standing = tonumber(standing), text = name } end
        elseif (kind == "i" or kind == "q" or kind == "r") and num(rest) then list[#list + 1] = { k = kind, id = num(rest) } end
    end
    return list
end

local function opt(value) return value and ("%.0f"):format(value) or "" end

function events.packets(ev)
    local id = ev.owner .. "~" .. ev.token .. "~" .. ev.rev
    local slots = ev.slots or { T = 0, H = 0, D = 0 }
    local series = ev.series and ("%s,%d,%d,%d"):format(ev.series.sid, ev.series.index, ev.series.total, ev.series.every) or ""
    local list = {
        table.concat({ "EH", id, ev.cat, ev.mode, ev.status, opt(ev.starts), opt(ev.duration), opt(ev.deadline),
            opt(ev.expires), opt(ev.minLevel), opt(ev.maxLevel), ev.model, slots.T, slots.H, slots.D, opt(ev.size),
            ev.ownerRole or "", flagString(ev), opt(ev.dungeon), ev.goal or "", opt(ev.runs), series, partsMask(ev),
            ev.lootRev or 0 }, "~"),
        table.concat({ "ET", id, ev.title, ev.place or "" }, "~"),
    }
    if (ev.desc or "") ~= "" or (ev.req or "") ~= "" then
        list[#list + 1] = table.concat({ "ED", id, ev.desc or "", ev.req or "" }, "~")
    end
    if ev.targets and #ev.targets > 0 then list[#list + 1] = table.concat({ "EG", id, encodeTargets(ev.targets) }, "~") end
    if ev.loot then
        list[#list + 1] = table.concat({ "EL", id, ev.loot.rule, opt(ev.loot.item), ev.loot.who or "", ev.loot.text or "" }, "~")
    end
    if ev.coorg and #ev.coorg > 0 then list[#list + 1] = table.concat({ "EO", id, table.concat(ev.coorg, ";") }, "~") end
    return list
end

function events.signupPacket(ev, signup)
    return table.concat({ "ES", ev.owner, ev.token, signup.rev, signup.state, signup.role or "", signup.alt or "",
        ("%.0f"):format(signup.at), signup.lootAck or 0, signup.note or "" }, "~")
end

function events.decisionPacket(ev, member, decision)
    return table.concat({ "EC", ev.owner, ev.token, member, decision.drev, decision.mrev, decision.d,
        decision.role or "" }, "~")
end

local function split(packet)
    local fields = {}
    for field in (packet .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = field end
    return fields
end

local function emptyNil(value) if value == "" then return nil end return value end

-- Receives one packet. ctx: { player, now, canPost(sender) }. Returns changed (bool) and a
-- list of notifications { code, ev, member } for the UI.
function events.receive(guild, sender, packet, ctx)
    if type(packet) ~= "string" or #packet > 255 or packet:sub(1, 1) ~= "E" then return false end
    local store = events.store(guild)
    local f = split(packet)
    local kind, now, player = f[1], ctx.now, ctx.player
    local notes = {}
    if kind == "EQ" then
        -- Somebody (re)joined: share own events and sign-ups soon.
        for _, ev in pairs(store.events) do
            if ev.owner == player then ev.nextShare = math.min(ev.nextShare or 0, now + math.random(2, 20)) end
            local mine = ev.signups and ev.signups[player]
            if mine and mine.mine then mine.nextShare = math.min(mine.nextShare or 0, now + math.random(5, 30)) end
        end
        return false
    end
    if kind == "ES" or kind == "EC" then
        local owner, token = f[2], f[3]
        if not owner or #owner > 60 or not tokenTime(token) then return false end
        local id = events.id(owner, token)
        if store.tombs[id] then return false end
        local ev = store.events[id]
        if not ev then
            -- Sign-ups can arrive before the event itself; keep them until the header comes.
            ev = { owner = owner, token = token, rev = 0, signups = {}, decisions = {}, stub = true }
            store.events[id] = ev
        end
        if kind == "ES" then
            local rev, state, role, alt, at, lootAck, note = num(f[4]), f[5], emptyNil(f[6]), f[7] or "", num(f[8]), num(f[9]), f[10] or ""
            if sender == owner or not rev or not validState[state] or not at or at > now + 300 then return false end
            if role and not role:match("^[THD]$") then return false end
            if not alt:match("^[THD]*$") or #note > 60 or events.clean(note, 60) ~= note then return false end
            local old = ev.signups[sender]
            if old and old.rev >= rev then return false end
            ev.signups[sender] = { state = state, role = role, alt = alt, note = note, rev = rev, at = at, lootAck = lootAck or 0 }
            if events.mayManage(ev, player) and not ev.stub then
                local wasIn = old and old.state ~= "out"
                if state ~= "out" and not wasIn then notes[#notes + 1] = { code = "signup", ev = ev, member = sender, rev = rev }
                elseif state == "out" and wasIn then notes[#notes + 1] = { code = "withdrawn", ev = ev, member = sender, rev = rev } end
            end
            return true, notes
        end
        local member, drev, mrev, code, role = f[4], num(f[5]), num(f[6]), f[7], emptyNil(f[8])
        if not member or #member > 60 or not drev or not mrev or not (validDecision[code] or code == "-") then return false end
        if role and not role:match("^[THD]$") then return false end
        if not ev.stub and not events.mayManage(ev, sender) then return false end
        if ev.stub and sender ~= owner then return false end
        local old = ev.decisions[member]
        if old and old.drev >= drev then return false end
        ev.decisions[member] = { d = code, role = role, mrev = mrev, drev = drev }
        if member == player and not ev.stub then
            local signup = ev.signups[player]
            if decisionValid(signup, ev.decisions[member]) and not (signup and signup.state == "out") then
                local before = old and old.d
                if code == "C" and before ~= "C" then
                    notes[#notes + 1] = { code = before == "W" and "promoted" or "confirmed", ev = ev, rev = drev }
                elseif code == "R" and before ~= "R" then
                    notes[#notes + 1] = { code = "rejected", ev = ev, rev = drev }
                elseif code == "W" and before ~= "W" then
                    notes[#notes + 1] = { code = "waitlist", ev = ev, rev = drev }
                end
            end
        end
        return true, notes
    end

    local owner, token, rev = f[2], f[3], num(f[4])
    if not owner or #owner > 60 or not tokenTime(token) or not rev or rev < 1 then return false end
    local id = events.id(owner, token)
    if store.tombs[id] then return false end
    local ev = store.events[id]
    if kind == "EH" then
        if not ev or ev.stub then
            if sender ~= owner or not ctx.canPost(sender) then return false end
        elseif not events.mayManage(ev, sender) then
            return false
        end
        if ev and not ev.stub and rev <= ev.rev then return false end
        local cat, mode, status = f[5], f[6], f[7]
        if not events.byCategory[cat] or (mode ~= "now" and mode ~= "plan") or not validStatus[status] then return false end
        local fields = { cat = cat, mode = mode, starts = num(f[8]), duration = num(f[9]), deadline = num(f[10]),
            expires = num(f[11]), minLevel = num(f[12]), maxLevel = num(f[13]), model = f[14],
            size = num(f[18]), ownerRole = emptyNil(f[19]), dungeon = num(f[21]), goal = emptyNil(f[22]),
            runs = num(f[23]), title = "x" }
        local flags = f[20] or ""
        fields.approve, fields.autofill, fields.partners = flags:find("a", 1, true) ~= nil, flags:find("f", 1, true) ~= nil,
            flags:find("p", 1, true) ~= nil
        if fields.model == "dungeon" or fields.model == "raid" or fields.model == "custom" then
            fields.slots = { T = num(f[15]), H = num(f[16]), D = num(f[17]) }
        end
        if not fields.starts or fields.starts > now + events.MAX_AHEAD then return false end
        local created = tokenTime(token)
        if created > now + 300 then return false end
        local ok = events.validate(fields, now)
        if not ok then return false end
        if ev and not ev.stub and (ev.status == "cancelled" or ev.status == "done") and status ~= ev.status then return false end
        local series
        local sid, sindex, stotal, severy = (f[24] or ""):match("^(%d+%-%d+),(%d+),(%d+),(%d+)$")
        if sid then series = { sid = sid, index = tonumber(sindex), total = tonumber(stotal), every = tonumber(severy) } end
        local mask, lootRev = num(f[25]) or 0, num(f[26]) or 0
        local fresh = not ev or ev.stub
        local before = ev and not ev.stub and { starts = ev.starts, status = ev.status, lootRev = ev.lootRev or 0 }
        ev = ev or { owner = owner, token = token, signups = {}, decisions = {} }
        ev.stub = nil
        for key, value in pairs(fields) do if key ~= "title" then ev[key] = value end end
        if fresh then ev.title = ev.title or "" end
        ev.status, ev.rev, ev.series, ev.lootRev, ev.mask = status, rev, series, lootRev, mask
        ev.created = ev.created or created
        ev.received = now
        ev.parts = ev.parts or {}
        -- Parts that the organizer removed with this revision.
        if mask % 2 < 1 and (ev.parts.ED or 0) < rev then ev.desc, ev.req = nil, nil end
        if mask % 4 < 2 and (ev.parts.EG or 0) < rev then ev.targets = nil end
        if mask % 8 < 4 and (ev.parts.EL or 0) < rev then ev.loot = nil end
        if mask % 16 < 8 and (ev.parts.EO or 0) < rev then ev.coorg = nil end
        store.events[id] = ev
        local mine = ev.signups[player]
        local involved = mine and mine.state ~= "out"
        if fresh then
            if owner ~= player then notes[#notes + 1] = { code = "new", ev = ev, rev = rev } end
        elseif involved then
            if before.status ~= status then
                if status == "cancelled" then notes[#notes + 1] = { code = "cancelled", ev = ev, rev = rev }
                elseif status == "started" then notes[#notes + 1] = { code = "started", ev = ev, rev = rev } end
            end
            if before.starts ~= ev.starts and status ~= "cancelled" then notes[#notes + 1] = { code = "moved", ev = ev, rev = rev } end
            if lootRev > before.lootRev then notes[#notes + 1] = { code = "loot", ev = ev, rev = lootRev } end
        end
        return true, notes
    end
    if not ev or ev.stub or not events.mayManage(ev, sender) then
        -- A part before its header: remember it so the header can complete the event.
        if not ev and sender == owner and ctx.canPost(sender) then
            ev = { owner = owner, token = token, rev = 0, signups = {}, decisions = {}, stub = true }
            store.events[id] = ev
        elseif not (ev and ev.stub and sender == owner) then
            return false
        end
    end
    ev.parts = ev.parts or {}
    if (ev.parts[kind] or 0) >= rev or (not ev.stub and rev < ev.rev) then return false end
    if kind == "ET" then
        local title, place = events.clean(f[5], 52), events.clean(f[6], 60)
        if title == "" or title ~= f[5] then return false end
        ev.title, ev.place = title, emptyNil(place)
    elseif kind == "ED" then
        ev.desc, ev.req = emptyNil(events.clean(f[5], 150)), emptyNil(events.clean(f[6], 100))
    elseif kind == "EG" then
        local targets = decodeTargets(f[5])
        if not validTargets(targets) then return false end
        ev.targets = targets
    elseif kind == "EL" then
        if not validLoot[f[5]] then return false end
        ev.loot = { rule = f[5], item = num(f[6]), who = emptyNil(events.clean(f[7], 48)), text = emptyNil(events.clean(f[8], 80)) }
    elseif kind == "EO" then
        local list = {}
        for name in (f[5] or ""):gmatch("[^;]+") do if #list < 3 and #name <= 60 then list[#list + 1] = name end end
        ev.coorg = list
    else
        return false
    end
    ev.parts[kind] = rev
    return true, notes
end

-- Periodic work: re-share own events, own sign-ups and decisions, grow series, prune.
-- send(packet) broadcasts one packet. Returns the number of packets sent.
function events.tick(guild, player, now, send, keepDays)
    local store = events.store(guild)
    local budget = events.PACKETS_PER_TICK
    events.extendSeries(guild, player, now)
    local due = {}
    for id, ev in pairs(store.events) do
        local finished = ev.stub and (tokenTime(ev.token) or 0) < now - 7 * DAY
            or (not ev.stub and events.ends(ev) + (keepDays or 30) * DAY < now)
        if finished then
            store.events[id] = nil
            store.tombs[id] = now
        elseif not ev.stub then
            local shareable = now < events.ends(ev) + DAY
            if ev.owner == player and shareable and ((ev.nextShare or 0) <= now or ev.dirty) then
                due[#due + 1] = { ev = ev, at = ev.dirty and 0 or ev.nextShare or 0 }
            end
            local mine = ev.signups[player]
            if mine and mine.mine and shareable and (mine.nextShare or 0) <= now then
                due[#due + 1] = { ev = ev, signup = mine, at = mine.nextShare or 0 }
            end
            -- Decisions of co-organizers are shared by their own client.
            if ev.owner ~= player and events.mayManage(ev, player) and shareable then
                for member, decision in pairs(ev.decisions) do
                    if decision.pending then due[#due + 1] = { ev = ev, member = member, decision = decision, at = 0 } end
                end
            end
        end
    end
    for id, at in pairs(store.tombs) do if at < now - 90 * DAY then store.tombs[id] = nil end end
    for key, at in pairs(store.seen) do if at < now - 90 * DAY then store.seen[key] = nil end end
    for sid, series in pairs(store.series) do
        if series.first + series.total * series.every * DAY < now - 30 * DAY then store.series[sid] = nil end
    end
    table.sort(due, function(a, b) return a.at < b.at end)
    local sent = 0
    for _, entry in ipairs(due) do
        if sent >= budget then break end
        local ev = entry.ev
        if entry.signup then
            if send(events.signupPacket(ev, entry.signup)) then sent = sent + 1 end
            entry.signup.nextShare = now + events.SIGNUP_SHARE_EVERY + math.random(0, 60)
        elseif entry.decision then
            if send(events.decisionPacket(ev, entry.member, entry.decision)) then sent = sent + 1 end
            entry.decision.pending = nil
        else
            local packets = events.packets(ev)
            for member, decision in pairs(ev.decisions) do
                if decision.pending or not ev.dirty then packets[#packets + 1] = events.decisionPacket(ev, member, decision) end
            end
            -- A full share may exceed the budget; the rest follows with the next tick.
            ev.shareQueue = ev.shareQueue or packets
            while sent < budget and #ev.shareQueue > 0 do
                local packet = table.remove(ev.shareQueue, 1)
                if send(packet) then sent = sent + 1 end
            end
            if #ev.shareQueue == 0 then
                ev.shareQueue = nil
                ev.dirty = nil
                for _, decision in pairs(ev.decisions) do decision.pending = nil end
                ev.nextShare = now + events.SHARE_EVERY + math.random(0, 60)
            end
        end
    end
    return sent
end

-- Sends a change at once (for example right after a click); the tick repeats it later.
function events.flush(ev, send)
    local packets = events.packets(ev)
    for member, decision in pairs(ev.decisions) do
        if decision.pending then packets[#packets + 1] = events.decisionPacket(ev, member, decision); decision.pending = nil end
    end
    for _, packet in ipairs(packets) do send(packet) end
    ev.dirty, ev.shareQueue = nil, nil
end

-- Removes an event from this character's data for good (tombstone against re-sync).
function events.removeLocal(guild, id, now)
    local store = events.store(guild)
    store.events[id] = nil
    store.tombs[id] = now
    store.archived[id] = nil
end

-- Participants that would be affected by a deletion (confirmed, tentative, signed up, waitlist).
function events.hasParticipants(ev)
    for _, entry in ipairs(events.roster(ev).entries) do
        if entry.status ~= "out" and entry.status ~= "rejected" then return true end
    end
    return false
end

-- Deleting: an active event with participants must be cancelled first. An own active event
-- without participants is cancelled for the guild (so it disappears for everybody) and then
-- removed locally with a tombstone, so no later sync can bring it back.
function events.delete(guild, ev, player, now, send)
    local active = events.active(ev, now)
    if active and events.hasParticipants(ev) then return false, "participants" end
    if active then
        if ev.owner ~= player or not events.setStatus(ev, "cancelled", now) then return false, "status" end
        events.flush(ev, send)
    end
    events.removeLocal(guild, events.id(ev.owner, ev.token), now)
    return true
end

function events.archive(guild, id, archived)
    events.store(guild).archived[id] = archived and true or nil
end

-- Notification de-duplication across reloads and repeated syncs.
function events.once(guild, key, now)
    local seen = events.store(guild).seen
    if seen[key] then return false end
    seen[key] = now
    return true
end

-- Reminders due now for events this character takes part in or organizes.
-- offsets: list of minutes before start (0 = at start).
function events.dueReminders(guild, player, now, offsets)
    local list = {}
    for id, ev in pairs(events.all(guild)) do
        if not ev.stub and ev.mode == "plan" and (ev.status == "open" or ev.status == "closed" or ev.status == "started") then
            local mine = ev.owner == player
            if not mine then
                local signup = ev.signups[player]
                local decision = ev.decisions[player]
                mine = signup and signup.state ~= "out" and not (decisionValid(signup, decision) and decision.d == "R")
            end
            if mine then
                for _, offset in ipairs(offsets) do
                    local at = ev.starts - offset * 60
                    -- Only the latest due reminder; never for events that are already over.
                    if now >= at and now < ev.starts + 10 * 60 and now < at + math.max(15 * 60, offset * 6) then
                        local key = ("r:%s:%.0f:%d"):format(id, ev.starts, offset)
                        list[#list + 1] = { key = key, ev = ev, id = id, offset = offset }
                    end
                end
            end
        end
    end
    return list
end

-- Migration of the former dungeon dates (BoardNotes kind "G") into the event view.
-- The old records stay untouched so older ForeverGuild versions keep working; this view
-- maps them 1:1 without inventing data. Returns an event-like table.
function events.fromLegacy(note, eligible)
    local ev = { legacy = true, owner = note.owner, token = note.token, rev = 1, cat = "dungeon", mode = "plan",
        status = note.closed and "cancelled" or "open", title = note.title, desc = note.text ~= "" and note.text or nil,
        starts = note.ends, duration = nil, dungeon = note.activity, model = note.slots and "dungeon" or "open",
        slots = note.slots and { T = note.slots.T, H = note.slots.H, D = note.slots.D } or nil, ownerRole = note.ownerRole,
        signups = {}, decisions = {}, partnerGuild = note.partnerGuild, created = tokenTime(note.token) }
    local queue = addon.boardNotes and addon.boardNotes.placements(note, eligible or function() return true end) or {}
    for _, entry in ipairs(queue) do
        ev.signups[entry.member] = { state = "in", role = entry.reply.role, alt = "", note = "", rev = 1, at = entry.reply.at or 0 }
        ev.decisions[entry.member] = { d = entry.confirmed and "C" or "W", role = entry.reply.role, mrev = 1, drev = 1 }
    end
    return ev
end

-- Fields of a legacy note for "take over into the new format" (organizer only).
function events.legacyFields(note)
    -- Accepts the stored note as well as its event view (fromLegacy).
    local dungeon = note.dungeon or note.activity
    return { cat = "dungeon", mode = "plan", title = note.title, desc = note.desc or note.text, starts = note.starts or note.ends,
        duration = 120, model = note.slots and "dungeon" or "open",
        slots = note.slots and { T = note.slots.T, H = note.slots.H, D = note.slots.D },
        ownerRole = note.ownerRole, dungeon = dungeon, goal = dungeon and "full" or nil }
end

-- Filters ---------------------------------------------------------------------------------------------

-- f: { text, cat, period ("now","today","tomorrow","week","all"), status ("open","full","waitlist"),
--      fits (bool), level, roles (mask string "THD"), role, mine ("in","notin"), organizer, guild ("own","partner") }
function events.matches(ev, f, ctx)
    local now = ctx.now
    if f.cat and f.cat ~= "all" and ev.cat ~= f.cat then return false end
    if f.text and f.text ~= "" then
        local hay = ev.searchText
        if not hay or ev.searchRev ~= ev.rev then
            hay = ctx.lower(table.concat({ ev.title or "", ev.desc or "", ev.place or "", ev.req or "", ctx.extra(ev) or "" }, " "))
            ev.searchText, ev.searchRev = hay, ev.rev
        end
        if not hay:find(ctx.lower(f.text), 1, true) then return false end
    end
    if f.period and f.period ~= "all" then
        local today = ctx.dayStart(now)
        if f.period == "now" and not (ev.mode == "now" or ev.starts <= now + HOUR) then return false end
        if f.period == "today" and ev.starts >= today + DAY then return false end
        if f.period == "tomorrow" and not (ev.starts >= today + DAY and ev.starts < today + 2 * DAY) then return false end
        if f.period == "week" and ev.starts >= today + 7 * DAY then return false end
    end
    local roster = ev.rosterCache or events.roster(ev)
    local counts = roster.counts
    if f.status == "open" and counts.full then return false end
    if f.status == "full" and not counts.full then return false end
    if f.status == "waitlist" and counts.waitlist == 0 then return false end
    if f.fits then
        local level = ctx.level
        if level and ((ev.minLevel and level < ev.minLevel) or (ev.maxLevel and level > ev.maxLevel)) then return false end
        if ev.slots and ctx.roles and ctx.roles ~= "" then
            local any = false
            for role in ctx.roles:gmatch("[THD]") do if events.free(ev, counts, role) > 0 then any = true end end
            if not any then return false end
        end
    end
    if f.role and f.role ~= "any" and ev.slots and events.free(ev, counts, f.role) == 0 then return false end
    if f.mine then
        local signup = ev.signups and ev.signups[ctx.player]
        local signed = (signup and signup.state ~= "out") or ev.owner == ctx.player
        if f.mine == "in" and not signed then return false end
        if f.mine == "notin" and signed then return false end
    end
    if f.organizer and f.organizer ~= "all" and ev.owner ~= f.organizer then return false end
    if f.guild == "own" and ev.partnerGuild then return false end
    if f.guild == "partner" and not ev.partnerGuild then return false end
    return true
end

function events.sorter(key)
    if key == "created" then
        return function(a, b) if (a.created or 0) ~= (b.created or 0) then return (a.created or 0) > (b.created or 0) end return a.id < b.id end
    elseif key == "free" then
        return function(a, b)
            local first, second = a.freeCount or 0, b.freeCount or 0
            if first ~= second then return first > second end
            return a.starts < b.starts
        end
    elseif key == "category" then
        return function(a, b)
            local first, second = events.byCategory[a.cat].order, events.byCategory[b.cat].order
            if first ~= second then return first < second end
            return a.starts < b.starts
        end
    end
    return function(a, b) if a.starts ~= b.starts then return a.starts < b.starts end return a.id < b.id end
end
