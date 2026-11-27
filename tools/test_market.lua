-- Tests for Market.lua and Board.lua (pure logic, no WoW API): lifecycle, payment,
-- concurrent claims, duplicate/stale packets, legacy compatibility, notifications.
-- Usage: lua tools/test_market.lua   (from the repository root)
local fails = 0
local function check(label, got, want)
    if got ~= want then fails = fails + 1; print(("FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
    else print("ok   " .. label) end
end

local clockValue = 1700000000
local G = "Realm:Gilde"
local clients, queue = {}, {}

local function client(name, legacy)
    local env = setmetatable({ GetServerTime = function() return clockValue end, time = function() return clockValue end },
        { __index = _G })
    local addon = {}
    local files = legacy and { "Orders.lua", "LegacyBoard" } or { "Orders.lua", "Market.lua", "Board.lua" }
    for _, file in ipairs(files) do
        if file == "LegacyBoard" then
            -- Older client: only understands the legacy snapshot and intent formats.
            local chunk = assert(io.open("tools/fixtures/legacy_board_0961.lua", "r"))
            local code = chunk:read("*a")
            chunk:close()
            local fn = assert(loadstring(code))
            setfenv(fn, env)
            fn("ForeverGuild", addon)
        else
            local fn = assert(loadfile("ForeverGuild/" .. file))
            setfenv(fn, env)
            fn("ForeverGuild", addon)
        end
    end
    local self = { name = name, env = env, addon = addon, board = addon.board, market = addon.market, notes = {}, legacy = legacy }
    self.broadcast = function(message)
        queue[#queue + 1] = { from = name, message = message }
        return true
    end
    self.target = function(to, message)
        queue[#queue + 1] = { from = name, to = to, message = message }
        return true
    end
    if not legacy then
        self.board.observer = function(_, order, events, actor)
            for _, event in ipairs(events) do
                local role = order.owner == name and "o" or (order.crafter == name and "c" or nil)
                if self.market.recipient(event, role) and not (actor == name and event.by == nil) then
                    self.notes[#self.notes + 1] = event.code
                end
            end
        end
    end
    clients[name] = self
    return self
end

local function deliver(drop)
    while #queue > 0 do
        local packet = table.remove(queue, 1)
        for name, target in pairs(clients) do
            if name ~= packet.from and (not packet.to or packet.to == name) and not (drop and drop(packet, name)) then
                target.board.receive(G, name, packet.from, packet.message, packet.to ~= nil, target.broadcast, target.target)
            end
        end
    end
end

local function records(c) return c.board.records(G) end
local function last(c, code)
    for _, value in ipairs(c.notes) do if value == code then return true end end
    return false
end

-- Legacy fixture: Board.lua of 0.9.61 (tools/fixtures) so mixed versions are tested.

local anna, bob, carl, olaf = client("Anna"), client("Bob"), client("Carl"), client("Olaf", true)
local M = anna.market

-- Money ------------------------------------------------------------------------------------
check("2g 50s in copper", M.copper(2, 50, 0), 25000)
check("silver normalizes", M.copper(0, 150, 0), 15000)
check("negative rejected", M.copper(-1, 0, 0), nil)
local g, s, c = M.split(25003)
check("split", g .. "/" .. s .. "/" .. c, "2/50/3")
check("tip per craft x5", M.tipTotal({ tip = 20000, tipEach = true, quantity = 5 }), 100000)

-- Public order with tip and partial materials ------------------------------------------------
local order = anna.board.create(G, "Anna", { recipe = 3914, quantity = 3, days = 7, tip = 55000, pay = "f",
    provided = { [4306] = 6 }, method = 2, dueDays = 3, note = "Bitte rot" }, anna.broadcast)
deliver()
local key = "Anna/" .. order.token
check("bob sees order", records(bob)[key] ~= nil, true)
check("bob sees tip", records(bob)[key].tip, 55000)
check("bob sees provided materials", records(bob)[key].provided and records(bob)[key].provided[4306], 6)
check("bob sees note", records(bob)[key].note, "Bitte rot")
check("legacy client sees public order", records(olaf)[key] ~= nil and records(olaf)[key].state, "O")

-- Concurrent claims: Bob and Carl claim at the same revision; the first one wins.
bob.board.action(records(bob)[key], "Bob", "take", bob.broadcast, bob.target, clockValue, 0, nil, G)
carl.board.action(records(carl)[key], "Carl", "take", carl.broadcast, carl.target, clockValue, 0, nil, G)
check("claim pending for bob", records(bob)[key].intent, "take")
deliver()
check("bob is crafter", records(anna)[key].crafter, "Bob")
check("waiting for materials", records(anna)[key].state, "M")
check("carl sees bob as crafter", records(carl)[key].crafter, "Bob")
check("carl intent cleared", records(carl)[key].intent, nil)
check("anna notified accepted", last(anna, "accepted"), true)
check("deadline set from dueDays", records(anna)[key].due, clockValue + 3 * 86400)
check("legacy client sees in progress", records(olaf)[key].state, "W")

-- Duplicate packet: replaying an older snapshot must not change anything.
local oldPacket = ("B:N:%s:1:3914:3:O::2:0:%d:0:55000:0:0:3:0:0:0:0:0::"):format(order.token, order.expiresAt)
bob.board.receive(G, "Bob", "Anna", oldPacket, false, bob.broadcast)
check("stale snapshot ignored", records(bob)[key].state, "M")

-- Crafter: materials, progress, cost offer -------------------------------------------------------
local function act(c, action, arg, text)
    local ok = c.board.action(records(c)[key], c.name, action, c.broadcast, c.target, clockValue, arg, text, G)
    deliver()
    return ok
end
act(bob, "mats", 2)
check("materials complete -> in progress", records(anna)[key].state, "W")
check("anna notified materials", last(anna, "materials"), true)
act(bob, "progress", 2)
check("progress 2/3", records(anna)[key].crafted, 2)
act(bob, "progress", 9)
check("progress above quantity rejected", records(anna)[key].crafted, 2)
check("pending intent cleared after rejection", records(bob)[key].intent, nil)
act(bob, "cost", 12000)
check("cost offer visible", records(anna)[key].costOffer, 12000)
check("anna notified cost offer", last(anna, "costOffer"), true)
act(anna, "costok")
check("cost agreed", records(bob)[key].cost, 12000)
check("total = tip + cost", M.total(records(bob)[key]), 67000)

-- Changes after acceptance need consent; tip reduction is a proposal, increase is immediate.
act(anna, "propose", 30000, "t")
check("reduction is only a proposal", records(bob)[key].tip, 55000)
check("bob notified proposal", last(bob, "proposal"), true)
act(bob, "reject")
check("proposal rejected keeps tip", records(anna)[key].tip, 55000)
act(anna, "propose", 60000, "t")
check("increase applies at once", records(bob)[key].tip, 60000)

-- Partial handover with mail ----------------------------------------------------------------------
act(bob, "ready")
check("ready for handoff", records(anna)[key].state, "R")
check("anna notified ready", last(anna, "ready"), true)
act(bob, "ship", 2)
check("shipped 2", records(anna)[key].shipped, 2)
act(anna, "received", 2)
check("delivered 2", records(bob)[key].delivered, 2)
check("still open (H)", records(bob)[key].state, "H")
act(bob, "progress", 3)
act(bob, "ship", 3)
act(anna, "received", 3)
check("all delivered but unpaid -> not completed", records(anna)[key].state, "H")
check("payment pending", M.payment(records(anna)[key]), "pending")
act(anna, "paid", 72000)
check("payment unclear until crafter confirms", M.payment(records(bob)[key]), "unclear")
act(bob, "gotpaid", 72000)
check("completed after payment", records(anna)[key].state, "D")
check("both notified done", last(anna, "done") and last(bob, "done"), true)
check("history recorded", #records(bob)[key].log > 8, true)
check("legacy client sees completed", records(olaf)[key].state, "D")

-- Stale packet must not reopen a finished order.
bob.board.receive(G, "Bob", "Anna", ("B:N:%s:999:3914:3:W::2:0:0:0:0:0:0:0:0:0:0:0:0::Bob"):format(order.token), false, bob.broadcast)
check("closed order not reopened", records(bob)[key].state, "D")

-- Duplicate notifications: the store ignores a repeated event ID.
check("notify once", M.notify(G, "x@1:done", { key = key }, clockValue), true)
check("notify duplicate ignored", M.notify(G, "x@1:done", { key = key }, clockValue), false)

-- Direct order: decline, reassign, waive voluntary tip --------------------------------------------
local direct = anna.board.create(G, "Anna", { recipe = 2000, quantity = 1, days = 5, direct = true, crafter = "Bob",
    tip = 10000, pay = "v" }, anna.broadcast)
deliver()
local dkey = "Anna/" .. direct.token
check("legacy client does not see direct order", records(olaf)[dkey], nil)
check("bob notified direct", last(bob, "direct"), true)
check("carl cannot claim direct", carl.board.action(records(carl)[dkey], "Carl", "take", carl.broadcast, carl.target, clockValue, 0, nil, G), true)
deliver()
check("direct order still requested", records(anna)[dkey].state, "Q")
local function actD(c, action, arg, text)
    c.board.action(records(c)[dkey], c.name, action, c.broadcast, c.target, clockValue, arg, text, G)
    deliver()
end
actD(bob, "decline", 0, "Keine Zeit")
check("declined", records(anna)[dkey].state, "J")
check("decline reason", records(anna)[dkey].reply, "Keine Zeit")
actD(anna, "assign", 3, "Carl")
check("assigned to carl", records(carl)[dkey].crafter, "Carl")
check("carl notified", last(carl, "assigned"), true)
actD(carl, "accept")
actD(carl, "ready")
actD(anna, "received")
check("voluntary tip open", records(anna)[dkey].state, "H")
actD(carl, "waive")
check("waived completes", records(anna)[dkey].state, "D")
check("payment waived", M.payment(records(anna)[dkey]), "waived")

-- Cancellation after acceptance needs consent ---------------------------------------------------
local third = anna.board.create(G, "Anna", { recipe = 3000, quantity = 2, days = 5 }, anna.broadcast)
deliver()
local tkey = "Anna/" .. third.token
local function actT(c, action, arg, text)
    c.board.action(records(c)[tkey], c.name, action, c.broadcast, c.target, clockValue, arg, text, G)
    deliver()
end
actT(bob, "take")
check("no materials -> in progress", records(anna)[tkey].state, "W")
actT(anna, "cancel")
check("owner cannot simply cancel accepted order", records(anna)[tkey].state, "W")
actT(anna, "cancelreq")
check("bob notified cancel request", last(bob, "cancelRequest"), true)
actT(bob, "cancelno")
check("dispute after rejected cancel", records(anna)[tkey].dispute, true)
actT(anna, "cancelreq")
actT(bob, "cancelok")
check("cancelled with consent", records(anna)[tkey].state, "X")

-- Expiry and reminders --------------------------------------------------------------------------
local fourth = anna.board.create(G, "Anna", { recipe = 4000, quantity = 1, days = 1 }, anna.broadcast)
deliver()
local fkey = "Anna/" .. fourth.token
local reminders = M.reminders(records(anna), "Anna", clockValue + 3600, function(n) return n == "Anna" end)
local found = false
for _, entry in ipairs(reminders) do if entry.order == records(anna)[fkey] and entry.code == "expiring" then found = true end end
check("expiring reminder", found, true)
check("expiring reminder once", #M.reminders(records(anna), "Anna", clockValue + 3600, function() return false end), 0)
clockValue = clockValue + 2 * 86400
check("open order expires", M.state(records(anna)[fkey], clockValue), "E")
anna.board.action(records(anna)[fkey], "Anna", "extend", anna.broadcast, anna.target, clockValue, 2, nil, G)
deliver()
check("extended order reopened", M.state(records(bob)[fkey], clockValue), "O")

-- Overdue accepted order is flagged, never cancelled automatically.
check("accepted order overdue flag", M.overdue({ state = "W", due = clockValue - 10 }, clockValue), true)

-- Legacy owner: new crafter uses legacy intents.
local legacyOrder = olaf.board.post(G, "Olaf", 5000, 1, true, "alt", olaf.broadcast, 7)
deliver()
local lkey = "Olaf/" .. legacyOrder.token
check("new client sees legacy order", records(bob)[lkey] ~= nil and records(bob)[lkey].ext, nil)
bob.board.action(records(bob)[lkey], "Bob", "take", bob.broadcast, bob.target, clockValue, 0, nil, G)
deliver()
check("legacy owner accepted claim", records(olaf)[lkey].crafter, "Bob")
check("new client sees legacy claim", records(bob)[lkey].state, "W")

-- Tombstones: a locally removed order never comes back through sync (new and old formats).
local doomed = anna.board.create(G, "Anna", { recipe = 6000, quantity = 1, days = 3 }, anna.broadcast)
deliver()
local dkey2 = "Anna/" .. doomed.token
bob.board.removeLocal(G, dkey2, clockValue)
check("removed locally", records(bob)[dkey2], nil)
anna.board.sendSnapshot(records(anna)[dkey2], anna.broadcast)
deliver()
check("later snapshot does not recreate it", records(bob)[dkey2], nil)
anna.board.edit(G, records(anna)[dkey2], { quantity = 2 }, anna.broadcast)
deliver()
check("newer revision does not recreate it either", records(bob)[dkey2], nil)
check("other members still see the order", records(carl)[dkey2] ~= nil, true)
bob.board.removeLocal(G, lkey, clockValue)
olaf.board.tick(G, "Olaf", clockValue + 1000, function() return true end, olaf.broadcast, olaf.target)
deliver()
check("old-format order stays removed", records(bob)[lkey], nil)
-- Legacy direct orders: removal leaves a tombstone, a relayed duplicate is acknowledged but ignored.
bob.env.ForeverGuildOrders = {}
local token, created = bob.addon.orders.accept("Anna", "O:1700000000-77:3914:2", "Anna", G)
check("legacy direct order received", created, true)
bob.addon.orders.removeLocal("Anna/direct/" .. token)
bob.market.remove(G, "Anna/direct/" .. token, clockValue)
local again, recreated = bob.addon.orders.accept("Anna", "O:1700000000-77:3914:2", "Anna", G)
check("relayed duplicate acknowledged", again, token)
check("relayed duplicate not recreated", recreated == false and bob.env.ForeverGuildOrders["Anna/direct/" .. token] == nil, true)

print(fails == 0 and "ALL TESTS PASSED" or (fails .. " FAILURE(S)"))
os.exit(fails == 0 and 0 or 1)
