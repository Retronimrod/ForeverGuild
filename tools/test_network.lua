-- Tests for BoardRights.lua and GuildPartners.lua (pure logic, no WoW API).
-- Usage: lua tools/test_network.lua   (from the repository root)
local addon = {}
assert(loadfile("ForeverGuild/BoardRights.lua"))("ForeverGuild", addon)
assert(loadfile("ForeverGuild/GuildPartners.lua"))("ForeverGuild", addon)
local R, P, fails = addon.boardRights, addon.guildPartners, 0
local function check(label, got, want)
    if got ~= want then fails = fails + 1; print(("FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
    else print("ok   " .. label) end
end
local G, now, yes = "Realm:Gilde", 1000, function() return true end
local no = function() return false end

-- Rights: only the guild master may change roles, revisions must increase, no far-future revisions.
check("non-master role packet rejected", R.receive(G, "Eve", "P:R:2:7:1000", false, yes, now) and true or false, false)
check("master role packet accepted", R.receive(G, "Gm", "P:R:2:7:2000", true, yes, now), true)
check("older revision ignored", R.receive(G, "Gm", "P:R:2:63:1500", true, yes, now), false)
check("far-future revision rejected", R.receive(G, "Gm", "P:R:2:63:999999999", true, yes, now) and true or false, false)
check("role 2 mask stored", R.mask(G, 2), 7)
-- Base profile default 3 = order+group: no news for a normal member, news for officers while unconfigured.
check("member may create order", R.has(G, "M", "M", "order", false, false), true)
check("member may not publish news", R.has(G, "M", "M", "news", false, false), false)
check("officer may publish news by default", R.has(G, "O", "O", "news", true, false), true)
check("master may do everything", R.has(G, "Gm", "Gm", "modNews", false, true), true)
-- Assigning role 2 (bit 1) to a member grants role 2's rights (mask 7 includes news).
R.receive(G, "Gm", "P:M:1:3000:Hans", true, yes, now)
check("assigned role grants news", R.has(G, "Hans", "Hans", "news", false, false), true)
check("non-master cannot assign roles", R.receive(G, "Eve", "P:M:7:4000:Eve", false, yes, now) and true or false, false)
-- Hiding a post requires moderation rights.
check("hide without moderation rejected", R.receive(G, "Eve", "P:X:O:900-1:Owner", false, no, now) and true or false, false)
check("hide with moderation accepted", R.receive(G, "Mod", "P:X:O:900-1:Owner", false, yes, now), true)
check("hidden post recorded with moderator", R.hidden(G, "O", "Owner", "900-1").by, "Mod")

-- Restore: a later P:Y revision with state 0 undoes a hide; older revisions cannot re-hide.
check("restore accepted", R.receive(G, "Mod", "P:Y:O:900-1:2000:0:Owner", false, yes, now), true)
check("restored post no longer hidden", R.hidden(G, "O", "Owner", "900-1"), nil)
check("older hide revision ignored", R.receive(G, "Mod", "P:Y:O:900-1:1500:1:Owner", false, yes, now) and true or false, false)
check("restore without moderation rejected", R.receive(G, "Eve", "P:Y:O:900-1:3000:1:Owner", false, no, now) and true or false, false)
check("re-hide with newer revision", R.receive(G, "Mod", "P:Y:O:900-1:4000:1:Owner", false, yes, now), true)
check("hidden list contains it", #R.hiddenList(G), 1)
-- Pruning: records of posts older than 31 days go, members who left are dropped on the master's client.
R.receive(G, "Mod", "P:Y:G:10-1:5000:1:Old", false, yes, now)
R.prune(G, 10 + 32 * 86400, true, function(key) return key ~= "Hans" end)
check("old hidden record pruned", R.store(G).hidden["G/Old/10-1"], nil)
check("member who left pruned", R.store(G).members.Hans, nil)

-- Partners: code round trip and tamper protection.
local A, B = "Realm:Alpha", "Realm:Beta"
local codeA, codeB = P.code(A, "Anna-Realm"), P.code(B, "Bob-Realm")
check("code decodes", P.decode(codeA).name, "Alpha")
check("tampered code rejected", P.decode((codeA:gsub("Alpha", "Evil"))), nil)

-- Handshake simulation: messages are delivered to the side whose relay was addressed.
local queue, relayOf = {}, { ["Anna-Realm"] = A, ["Bob-Realm"] = B }
local senderOf = { [A] = "Anna-Realm", [B] = "Bob-Realm" }
local function sender(from) return function(relay, msg) queue[#queue + 1] = { to = relayOf[relay], from = senderOf[from], msg = msg }; return true end end
local same = function(a, b) return a == b end
local function deliver()
    while #queue > 0 do
        local m = table.remove(queue, 1)
        P.receive(m.to, m.from, m.msg, now, same, sender(m.to))
    end
end
P.approve(A, codeB, now, sender(A)); deliver()
check("one-sided approval is not confirmed", P.store(A).peers[P.id(B)].confirmed, nil)
P.approve(B, codeA, now, sender(B)); deliver()
now = now + 20; P.tick(A, now, sender(A)); P.tick(B, now, sender(B)); deliver()
check("A confirmed after mutual approval", P.store(A).peers[P.id(B)].confirmed, true)
check("B confirmed after mutual approval", P.store(B).peers[P.id(A)].confirmed, true)
-- A message from anyone other than the registered relay is ignored.
check("foreign sender ignored", P.receive(A, "Mallory-Realm", "P:L:H:" .. P.id(B) .. ":" .. P.id(A) .. ":5:0", now, same, sender(A)), nil)
-- Disconnect propagates.
P.disconnect(A, P.id(B), now, sender(A)); deliver()
check("B sees disconnect", P.store(B).peers[P.id(A)].consent, false)

-- Backoff: unanswered probes double the interval up to 10 minutes.
local C = "Realm:Gamma"
P.approve(C, P.code("Realm:Delta", "Dora-Realm"), now, function() return true end)
local peerD = P.store(C).peers[P.id("Realm:Delta")]
for _ = 1, 8 do P.tick(C, peerD.nextProbe, function() return true end) end
check("backoff capped at 600 s", peerD.backoff, 600)
check("status of unanswered peer is waiting", P.status(peerD, now), "waiting")
check("confirmed but silent for 4 days is inactive", P.status({ consent = true, confirmed = true, lastSeen = 0 }, 4 * 86400), "inactive")
-- Shared partner list: only accepted from the guild master, newer stamps win.
local shared = {}
P.store(A).nextShare = 0
P.shareKnown(A, now, function(packet) shared[#shared + 1] = packet; return true end)
check("master shares partner list", #shared, 1)
check("non-master list packet rejected", P.receiveKnown("Realm:Member", shared[1], false, now), nil)
check("master list packet accepted", P.receiveKnown("Realm:Member", shared[1], true, now), true)
check("member sees partner name", P.store("Realm:Member").known[P.id(B)].name, "Beta")

-- Officer ranks: only the master may set them, 0 means "by rank name".
check("non-master officer rule rejected", R.receive(G, "Eve", "P:O:2:9000", false, yes, now) and true or false, false)
check("master officer rule accepted", R.receive(G, "Gm", "P:O:2:9000", true, yes, now), true)
check("officer rank limit stored", R.officerRank(G), 2)
R.receive(G, "Gm", "P:O:0:9500", true, yes, now)
check("rank 0 means automatic", R.officerRank(G), nil)
now = now + 100
P.approve(A, codeB, now, sender(A)); P.approve(B, codeA, now, sender(B)); deliver()
now = now + 20; P.tick(A, now, sender(A)); P.tick(B, now, sender(B)); deliver()
check("reconnected after disconnect", P.store(A).peers[P.id(B)].confirmed and P.store(B).peers[P.id(A)].confirmed, true)
-- Partner events: only from the confirmed partner relay, members only from trusted senders.
local idA = P.id(A)
local packet = ("P:E:%s:Owner-Realm:%d-1:%d:0:5:Deadmines"):format(idA, now, now + 3600)
check("event from foreign sender rejected", P.receiveEvent(B, "Mallory-Realm", packet, now, same), nil)
check("event from partner relay accepted", P.receiveEvent(B, "Anna-Realm", packet, now, same), true)
check("duplicate event ignored", P.receiveEvent(B, "Anna-Realm", packet, now, same), nil)
local guildPacket = packet:gsub("^P:E:", "P:F:")
check("guild event from untrusted sender rejected", P.receiveGuildEvent("Realm:Member", guildPacket, false, now), nil)
check("guild event from trusted sender accepted", P.receiveGuildEvent("Realm:Member", guildPacket, true, now), true)
local forwarded = {}
P.relayEvents(A, { { owner = "Owner-Realm", token = now .. "-2", ends = now + 3600, closed = false, title = "Run" } },
    now, function(relay, msg) forwarded[#forwarded + 1] = relay .. "|" .. msg; return true end, function() return true end)
check("relay forwards flagged event to partner relay", forwarded[1] and forwarded[1]:match("^Bob%-Realm|P:E:") ~= nil, true)

print(fails == 0 and "\nALL OK" or ("\n" .. fails .. " FAILURE(S)")); os.exit(fails == 0 and 0 or 1)
