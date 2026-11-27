-- Tests for Events.lua (pure logic, no WoW API).
-- Usage: lua tools/test_events.lua   (from the repository root)
local addon = {}
_G.ForeverGuildEvents, _G.ForeverGuildOrderSequence = nil, 0
assert(loadfile("ForeverGuild/GroupActivities.lua"))("ForeverGuild", addon)
assert(loadfile("ForeverGuild/BoardNotes.lua"))("ForeverGuild", addon)
assert(loadfile("ForeverGuild/Events.lua"))("ForeverGuild", addon)
local E, fails = addon.events, 0
local function check(label, got, want)
    if got ~= want then fails = fails + 1; print(("FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
    else print("ok   " .. label) end
end
local DAY, now = 86400, 1800000000
local G, Org = "Realm:Gilde", "Org-Realm"
local yes = function() return true end

-- Two clients: the organizer's store and a member's store are separate SavedVariables.
local stores = {}
local function as(name) _G.ForeverGuildEvents = stores[name] or {}; stores[name] = _G.ForeverGuildEvents end
local function deliver(packets, from, to, at)
    local saved = _G.ForeverGuildEvents
    as(to)
    local all = {}
    for _, packet in ipairs(packets) do
        check("packet fits 255 bytes", #packet <= 255, true)
        local _, notes = E.receive(G, from, packet, { player = to, now = at or now, canPost = yes })
        for _, note in ipairs(notes or {}) do all[#all + 1] = note.code end
    end
    _G.ForeverGuildEvents = saved
    return all
end

-- 0. Dungeon database: binding list from the WoW Forever group finder (2026-11-27).
do
    local list = {
        { "Obere Blackrockspitze", 59, 60 }, { "Scholomance", 58, 60 }, { "Stratholme (Dienstbotentor)", 58, 60 },
        { "Stratholme (Haupttor)", 58, 60 }, { "Terrasse des Formers", 58, 60 }, { "Düsterbruch (Nord)", 56, 60 },
        { "Düsterbruch (West)", 56, 60 }, { "Schwarzschlundfeste", 55, 60 }, { "Untere Blackrockspitze", 55, 60 },
        { "Düsterbruch (Ost)", 54, 60 }, { "Blackrocktiefen", 52, 60 }, { "Versunkener Tempel", 50, 60 },
        { "Gefängnis von Alcaz", 48, 55 }, { "Maraudon", 46, 55 }, { "Zul'Farrak", 44, 54 }, { "Uldaman", 41, 51 },
        { "Feste Krol'dok", 40, 47 }, { "Scharlachrote Kathedrale", 38, 46 }, { "Hügel von Razorfen", 37, 46 },
        { "Scharlachrote Waffenkammer", 36, 44 }, { "Die Versunkene Stadt", 35, 42 }, { "Scharlachrote Bibliothek", 33, 41 },
        { "Scharlachroter Friedhof", 30, 38 }, { "Gnomeregan", 29, 38 }, { "Kral von Razorfen", 29, 38 }, { "Dalaran", 28, 35 },
        { "Ausgrabungsstätte: Sumpfland", 26, 33 }, { "Blackfathom-Tiefe", 24, 32 }, { "Burg Shadowfang", 20, 30 },
        { "Todesminen", 17, 26 }, { "Höhlen des Wehklagens", 15, 24 }, { "Ruinen von Lordaeron", 15, 22 },
        { "Halle der Thanen", 13, 20 }, { "Ragefireabgrund", 13, 18 },
    }
    local dungeons = addon.groupDungeons
    check("exactly 34 dungeons", #dungeons, 34)
    local ids, keys, names, wrong = {}, {}, {}, 0
    for index, dungeon in ipairs(dungeons) do
        local want = list[index]
        if dungeon[1] ~= want[1] or dungeon.min ~= want[2] or dungeon.max ~= want[3] or dungeon.sort ~= index
            or dungeon[5] ~= ("%d–%d"):format(want[2], want[3]) then
            wrong = wrong + 1
            print("  mismatch at " .. index .. ": " .. tostring(dungeon[1]))
        end
        if ids[dungeon[6]] or keys[dungeon.key] or names[dungeon[1]] then wrong = wrong + 1 end
        ids[dungeon[6]], keys[dungeon.key], names[dungeon[1]] = true, true, true
        if addon.getGroupDungeon(dungeon[6]) ~= dungeon or addon.getDungeonByKey(dungeon.key) ~= dungeon then wrong = wrong + 1 end
    end
    check("names, levels and order match the group finder; IDs unique", wrong, 0)
    local wings = {}
    for _, dungeon in ipairs(dungeons) do if dungeon.parent then wings[dungeon.parent] = (wings[dungeon.parent] or 0) + 1 end end
    check("three Dire Maul wings", wings.dire_maul, 3)
    check("four Scarlet Monastery wings", wings.scarlet_monastery, 4)
    check("two Stratholme entrances", wings.stratholme, 2)
    check("upper and lower Blackrock Spire", wings.blackrock_spire, 2)
    for _, id in ipairs({ 13, 23, 24, 25, 8 }) do
        local old = addon.getGroupDungeon(id)
        check("former ID " .. id .. " still readable, not offered", old ~= nil and ids[id] == nil, true)
    end
    check("unchanged dungeon keeps its ID (Blackrock Depths 21)", addon.getGroupDungeon(21)[1], "Blackrocktiefen")
    check("wing uses its complex banner", addon.dungeonArt(addon.getDungeonByKey("dire_maul_north")):match("Dungeon24$") ~= nil, true)
end

-- 1. Spontaneous dungeon group (1/1/3) and planned dungeon date.
as(Org)
local dungeon = { cat = "dungeon", mode = "now", title = "Schwarzfelstiefen", starts = now, expires = now + 7200,
    duration = 120, model = "dungeon", slots = { T = 1, H = 1, D = 3 }, ownerRole = "T", dungeon = 21, goal = "recipe",
    targets = { { k = "i", id = 11208 }, { k = "t", text = "Formel: Verzauberung" } },
    loot = { rule = "recipe", item = 11208, who = Org, text = "Rezept für den Organisator" }, desc = "Rezeptfarm" }
local ev, why = E.create(G, Org, dungeon, now)
check("spontaneous dungeon created", ev ~= nil, true)
check("no reason", why, nil)
check("state open", E.state(ev, now), "open")
local planned = E.create(G, Org, { cat = "dungeon", mode = "plan", title = "BRD", starts = now + DAY, duration = 120,
    model = "dungeon", slots = { T = 1, H = 1, D = 3 }, ownerRole = "D" }, now)
check("planned dungeon created", planned ~= nil, true)
check("past start refused", E.create(G, Org, { cat = "other", mode = "plan", title = "x", starts = now - 10, model = "open" }, now), nil)
check("bad level range refused", select(2, E.create(G, Org, { cat = "quest", mode = "plan", title = "x", starts = now + 100,
    model = "free", size = 5, minLevel = 50, maxLevel = 40 }, now)), "level")

-- 2. Raid with a bigger group and a free group / open guild event.
check("raid is coming soon (not creatable)", E.create(G, Org, { cat = "raid", mode = "plan", title = "Raid", starts = now + 2 * DAY,
    model = "raid", slots = { T = 4, H = 10, D = 26 }, ownerRole = "H" }, now), nil)
check("dungeon event with 40 places (custom roles)", E.create(G, Org, { cat = "dungeon", mode = "plan", title = "Azuregos", starts = now + 2 * DAY,
    model = "raid", slots = { T = 4, H = 10, D = 26 }, ownerRole = "H" }, now) ~= nil, true)
check("raid over 40 refused", E.create(G, Org, { cat = "dungeon", mode = "plan", title = "Raid", starts = now + 2 * DAY,
    model = "raid", slots = { T = 5, H = 10, D = 26 }, ownerRole = "H" }, now), nil)
check("retired guild event not creatable", E.create(G, Org, { cat = "guild", mode = "plan", title = "Gildentreffen", starts = now + DAY,
    model = "open" }, now), nil)
check("open quest event", E.create(G, Org, { cat = "quest", mode = "plan", title = "Schlachtfeld", starts = now + DAY,
    model = "open" }, now) ~= nil, true)
-- Reputation goal travels with the event.
local rep = E.create(G, Org, { cat = "rep", mode = "plan", title = "Ruf", starts = now + DAY, model = "free", size = 5,
    targets = { { k = "f", id = 529, standing = 8, text = "Argentumdämmerung" } } }, now)
check("reputation event created", rep ~= nil, true)
do
    local saved = _G.ForeverGuildEvents
    _G.ForeverGuildEvents = {}
    for _, packet in ipairs(E.packets(rep)) do E.receive(G, Org, packet, { player = "Zed", now = now, canPost = yes }) end
    local copyRep = E.all(G)[E.id(Org, rep.token)]
    check("faction goal synced", copyRep and copyRep.targets and copyRep.targets[1].k == "f" and copyRep.targets[1].standing == 8
        and copyRep.targets[1].text == "Argentumdämmerung", true)
    _G.ForeverGuildEvents = saved
end
-- Older events of retired categories stay readable.
do
    local saved = _G.ForeverGuildEvents
    _G.ForeverGuildEvents = {}
    local old = { owner = Org, token = "1799999000-77", rev = 1, cat = "guild", mode = "plan", status = "open", title = "Alt",
        starts = now + DAY, model = "open", signups = {}, decisions = {} }
    for _, packet in ipairs(E.packets(old)) do E.receive(G, Org, packet, { player = "Zed", now = now, canPost = yes }) end
    check("retired category still received", E.all(G)[E.id(Org, old.token)] ~= nil and E.all(G)[E.id(Org, old.token)].cat == "guild", true)
    _G.ForeverGuildEvents = saved
end
-- 3. Recipe run for a bind-on-pickup recipe: targets are plain item IDs, no trade check.
check("recipe run is coming soon", E.create(G, Org, { cat = "recipe", mode = "plan", title = "x", starts = now + DAY,
    model = "free", size = 5 }, now), nil)
check("dungeon with BoP item target", E.create(G, Org, { cat = "dungeon", mode = "plan", title = "Rezeptfarm",
    starts = now + DAY, model = "dungeon", slots = { T = 1, H = 1, D = 3 }, ownerRole = "D",
    targets = { { k = "i", id = 18259 } } }, now) ~= nil, true)
check("quest group with quest targets", E.create(G, Org, { cat = "quest", mode = "plan", title = "Elite", starts = now + DAY,
    model = "free", size = 5, targets = { { k = "q", id = 4024 }, { k = "q", id = 4025 }, { k = "t", text = "Kette" } } }, now) ~= nil, true)

-- Sync to a member.
local packets = E.packets(ev)
local notes = deliver(packets, Org, "Ann")
check("member gets new-event note", notes[1], "new")
as("Ann")
local copy = E.all(G)[E.id(Org, ev.token)]
check("member copy title", copy.title, "Schwarzfelstiefen")
check("member copy targets", copy.targets and #copy.targets, 2)
check("member copy loot", copy.loot and copy.loot.rule, "recipe")
check("member copy desc", copy.desc, "Rezeptfarm")
check("duplicate packets ignored", #deliver(packets, Org, "Ann"), 0)
check("foreign sender cannot edit", (function()
    as("Ann")
    local fake = E.packets(ev)[1]:gsub("~1~dungeon", "~9~dungeon")
    return (E.receive(G, "Mallory", fake, { player = "Ann", now = now, canPost = yes }))
end)(), false)

-- 4. Role-based sign-ups, alternative roles, concurrency, waitlist.
local signers = { { "Ann", "H", "" }, { "Bob", "D", "" }, { "Cid", "D", "" }, { "Dan", "D", "" }, { "Eve", "D", "H" }, { "Fay", "H", "D" } }
local signupPackets = {}
for index, entry in ipairs(signers) do
    as(entry[1])
    if entry[1] ~= "Ann" then deliver(E.packets(ev), Org, entry[1]) end
    as(entry[1])
    local own = E.all(G)[E.id(Org, ev.token)]
    local signup = E.signUp(own, entry[1], { state = "in", role = entry[2], alt = entry[3] }, now + index)
    check("sign-up " .. entry[1], signup ~= nil, true)
    check("unsynced sign-up is not confirmed", E.roster(own).entries[1].status, "signed")
    signupPackets[#signupPackets + 1] = { entry[1], E.signupPacket(own, signup) }
end
-- The organizer receives all sign-ups (simultaneously) and decides in sign-up order.
local organizerNotes = {}
for _, item in ipairs(signupPackets) do
    for _, code in ipairs(deliver({ item[2] }, item[1], Org)) do organizerNotes[#organizerNotes + 1] = code end
end
check("organizer notified of sign-ups", #organizerNotes, 6)
as(Org)
local changed = E.reconcile(ev, now + 10)
local roster = E.roster(ev)
check("tank slot taken by organizer", roster.counts.T, 1)
check("healer confirmed", roster.counts.H, 1)
check("three dps confirmed", roster.counts.D, 3)
check("group full", roster.counts.full, true)
check("state ready (spontaneous, full)", E.state(ev, now + 10), "ready")
local status = {}
for _, entry in ipairs(roster.entries) do status[entry.name] = entry.status end
check("Eve (D, alt H) waits: no free role", status.Eve, "waitlist")
check("Fay waitlisted", status.Fay, "waitlist")
check("changes reported", #changed, 6)
check("healer candidates on waitlist", #E.candidates(ev, "H"), 2)

-- Decisions reach the member; confirmation notification once.
local decisionPackets = {}
for member, decision in pairs(ev.decisions) do decisionPackets[#decisionPackets + 1] = E.decisionPacket(ev, member, decision) end
local annNotes = deliver(decisionPackets, Org, "Ann")
check("Ann notified confirmed", annNotes[1], "confirmed")
check("repeated decisions not notified again", #deliver(decisionPackets, Org, "Ann"), 0)

-- 5. Healer withdraws; waitlist auto-fill only when enabled.
as("Ann")
local annCopy = E.all(G)[E.id(Org, ev.token)]
local out = E.signUp(annCopy, "Ann", { state = "out" }, now + 20)
check("withdraw accepted", out and out.state, "out")
check("organizer notified of withdrawal", deliver({ E.signupPacket(annCopy, out) }, "Ann", Org)[1], "withdrawn")
as(Org)
E.reconcile(ev, now + 21)
check("no auto-fill by default", E.roster(ev).counts.H, 0)
ev.autofill = true
local promoted = E.reconcile(ev, now + 22)
check("auto-fill promotes a healer", E.roster(ev).counts.H, 1)
local promotedName
for _, change in ipairs(promoted) do if change.promoted then promotedName = change.name end end
check("earliest fitting waitlist member promoted", promotedName, "Eve")
-- Stale withdrawal cannot come back: an older sign-up revision is ignored.
local stale = E.signupPacket(annCopy, { state = "in", role = "H", alt = "", note = "", rev = 1, at = now + 1, lootAck = 0 })
as(Org)
check("older sign-up revision ignored", (E.receive(G, "Ann", stale, { player = Org, now = now + 30, canPost = yes })), false)

-- 6. Time change and loot change notify participants; cancelled cannot be revived.
as(Org)
local fields = E.copyFields(ev)
fields.loot = { rule = "item", item = 12345, who = "Bob", text = "" }
local changes = E.edit(ev, fields, now + 40)
check("loot change detected", changes.loot, true)
check("loot revision raised", ev.lootRev, 2)
local bobNotes = deliver(E.packets(ev), Org, "Bob", now + 41)
check("Bob notified of loot change", bobNotes[1], "loot")
local moved = E.copyFields(planned)
moved.starts = planned.starts + 3600
E.edit(planned, moved, now + 50)
as("Bob")
deliver(E.packets(planned), Org, "Bob", now + 50)
as("Bob")
local bobPlanned = E.all(G)[E.id(Org, planned.token)]
E.signUp(bobPlanned, "Bob", { state = "in", role = "D" }, now + 51)
moved.starts = planned.starts + 1800
as(Org)
E.edit(planned, moved, now + 52)
check("Bob notified of moved date", deliver(E.packets(planned), Org, "Bob", now + 53)[1], "moved")
as(Org)
check("cancel allowed", E.setStatus(planned, "cancelled", now + 60), true)
local cancelPackets = E.packets(planned)
check("Bob notified of cancellation", deliver(cancelPackets, Org, "Bob", now + 61)[1], "cancelled")
as(Org)
check("cancelled cannot be reopened", E.setStatus(planned, "open", now + 62), false)
-- An old packet (rev before the cancellation) does not reactivate the event on Bob's side.
as("Bob")
local oldHeader = cancelPackets[1]:gsub("~cancelled~", "~open~"):gsub("^(EH~[^~]+~[^~]+~)(%d+)", function(prefix) return prefix .. "1" end)
check("old header ignored", (E.receive(G, Org, oldHeader, { player = "Bob", now = now + 70, canPost = yes })), false)
check("still cancelled", E.all(G)[E.id(Org, planned.token)].status, "cancelled")

-- 7. Started event is not completed automatically; organizer completes it.
as(Org)
check("start event", E.setStatus(ev, "started", now + 100), true)
check("still started after planned end", E.state(ev, E.ends(ev) + 3600), "started")
check("complete event", E.setStatus(ev, "done", now + 200), true)
check("history state done", E.state(ev, now + 300), "done")
check("done not active", E.active(ev, now + 300), false)

-- 8. Recurring weekly series: own participant lists, limited pre-generation.
as(Org)
local series = E.create(G, Org, { cat = "dungeon", mode = "plan", title = "Dungeon-Abend", starts = now + DAY,
    model = "dungeon", slots = { T = 1, H = 1, D = 3 }, ownerRole = "T" }, now, 7, 10)
local count, distinct = 0, {}
for _, other in pairs(E.all(G)) do
    if other.series and other.series.sid == series.series.sid then count = count + 1; distinct[other.signups] = true end
end
check("series pre-generates 4 occurrences", count, 4)
local lists = 0
for _ in pairs(distinct) do lists = lists + 1 end
check("each occurrence has its own sign-up list", lists, 4)
E.extendSeries(G, Org, now + 8 * DAY)
count = 0
for _, other in pairs(E.all(G)) do if other.series and other.series.sid == series.series.sid then count = count + 1 end end
check("series grows as dates pass (2 passed, 2 new)", count, 6)
check("following occurrences selectable", #E.seriesMembers(G, series, true), 6)

-- 9. Reminders: once per offset, none for past events.
as("Bob")
local soon = { owner = Org, token = "1-1", rev = 1, mode = "plan", status = "open", starts = now + 900, signups = { Bob = { state = "in", rev = 1 } }, decisions = {} }
E.store(G).events["Org-Realm/1-1"] = soon
local due = E.dueReminders(G, "Bob", now, { 1440, 60, 30, 15, 0 })
check("only the latest due reminder (15 min)", #due, 1)
check("reminder dedupe", E.once(G, due[1].key, now) and not E.once(G, due[1].key, now), true)
check("no reminder for past event", #E.dueReminders(G, "Bob", now + 3600, { 15 }), 0)

-- 10. Legacy dungeon dates map 1:1.
local legacy = { owner = "Old", token = "100-1", kind = "G", title = "Stratholme", text = "alt", ends = now + DAY,
    slots = { T = 1, H = 1, D = 3 }, ownerRole = "T", activity = 25,
    replies = { Bob = { joined = true, role = "D", at = 5 }, Cid = { joined = true, role = "T", at = 6 } } }
local view = E.fromLegacy(legacy)
check("legacy dungeon id kept", view.dungeon, 25)
check("legacy owner kept", view.owner, "Old")
local legacyRoster = E.roster(view)
local legacyStatus = {}
for _, entry in ipairs(legacyRoster.entries) do legacyStatus[entry.name] = entry.status end
check("legacy participant confirmed", legacyStatus.Bob, "confirmed")
check("legacy surplus tank waitlisted", legacyStatus.Cid, "waitlist")
check("legacy fields keep start", E.legacyFields(legacy).starts, legacy.ends)

-- 11. Tombstone: locally removed events never come back through sync.
as("Bob")
E.removeLocal(G, E.id(Org, planned.token), now)
check("removed event ignored on re-sync", (E.receive(G, Org, E.packets(planned)[1], { player = "Bob", now = now, canPost = yes })), false)

-- 12. Filters.
local ctx = { now = now, player = "Bob", lower = string.lower, extra = function() return "" end,
    dayStart = function(t) return t - t % DAY end, level = 30, roles = "D" }
as(Org)
local quest = E.create(G, Org, { cat = "quest", mode = "plan", title = "Elitequests", starts = now + 3600, model = "free",
    size = 5, minLevel = 40, maxLevel = 60 }, now)
check("text filter", E.matches(quest, { text = "elite" }, ctx), true)
check("category filter", E.matches(quest, { cat = "raid" }, ctx), false)
check("fits filter: level too low", E.matches(quest, { fits = true }, ctx), false)
ctx.level = 45
check("fits filter: level ok", E.matches(quest, { fits = true }, ctx), true)
check("period today", E.matches(quest, { period = "today" }, ctx), true)

-- 12b. Delete: active with participants needs a cancellation first; deleted stays deleted.
as(Org)
local withPeople = E.create(G, Org, { cat = "dungeon", mode = "plan", title = "Del", starts = now + DAY, model = "dungeon",
    slots = { T = 1, H = 1, D = 3 }, ownerRole = "T" }, now)
withPeople.signups.Bob = { state = "in", role = "D", rev = 1, at = now }
check("delete refused with participants", (E.delete(G, withPeople, Org, now, function() return true end)), false)
local lonely = E.create(G, Org, { cat = "dungeon", mode = "plan", title = "Leer", starts = now + DAY, model = "dungeon",
    slots = { T = 1, H = 1, D = 3 }, ownerRole = "T" }, now)
local deleted = {}
check("delete own empty event", (E.delete(G, lonely, Org, now, function(p) deleted[#deleted + 1] = p; return true end)), true)
check("cancellation sent before deleting", deleted[1] and deleted[1]:find("~cancelled~", 1, true) ~= nil, true)
check("deleted event gone", E.all(G)[E.id(Org, lonely.token)], nil)
check("deleted event not restored", (E.receive(G, Org, E.packets(lonely)[1], { player = Org, now = now, canPost = yes })), false)

-- 13. Text cleaning keeps the packet format intact.
check("separators removed", E.clean("a~b|c;d"), "a b c d")
check("utf8 not cut", E.clean("äääää", 5), "ää")

print(fails == 0 and "\nALL OK" or ("\n%d FAILED"):format(fails))
os.exit(fails == 0 and 0 or 1)
