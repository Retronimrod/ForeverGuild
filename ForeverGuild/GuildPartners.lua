local _, addon = ...
local partners = {}
addon.guildPartners = partners

local function parts(value)
    return value:match("^([^:]+):(.+)$")
end

function partners.id(guild)
    local a, b = 5381, 40699
    for i = 1, #guild do
        local byte = guild:byte(i)
        a = (a * 131 + byte) % 2147483647
        b = (b * 137 + byte) % 2147483629
    end
    return ("%08X%08X"):format(a, b)
end

local function cleanField(value, limit)
    return value and value ~= "" and #value <= limit and not value:find("[;|%c]")
end

function partners.code(guild, relay)
    local realm, name = parts(guild)
    if not cleanField(realm, 45) or not cleanField(name, 70) or not cleanField(relay, 100) then return end
    return ("FG1;%s;%s;%s;%s"):format(partners.id(guild), realm, name, relay)
end

function partners.decode(code)
    if type(code) ~= "string" or #code > 235 then return end
    local id, realm, name, relay = code:match("^%s*FG1;([0-9A-F]+);([^;]+);([^;]+);([^;]+)%s*$")
    relay = relay and relay:match("^%s*(.-)%s*$")
    if not id or #id ~= 16 or not cleanField(realm, 45) or not cleanField(name, 70)
        or not cleanField(relay, 100) or id ~= partners.id(realm .. ":" .. name) then return end
    return { id = id, realm = realm, name = name, relay = relay }
end

function partners.store(guild)
    if not guild then return end
    ForeverGuildPartners = ForeverGuildPartners or {}
    local state = ForeverGuildPartners[guild]
    if not state then
        state = { peers = {}, serial = 0, known = {} }
        ForeverGuildPartners[guild] = state
    end
    state.known = state.known or {}
    return state
end

local function transmit(guild, peer, kind, send)
    return send(peer.relay, ("P:L:%s:%s:%s:%.0f:%.0f"):format(kind, partners.id(guild),
        peer.id, peer.epoch, peer.remoteEpoch or 0))
end

function partners.approve(guild, code, now, send)
    local peer = partners.decode(code)
    if not peer or peer.id == partners.id(guild) then return end
    local state = partners.store(guild)
    local previous = state.peers[peer.id]
    if previous and previous.consent and previous.relay == peer.relay then return previous end
    state.serial = math.max(state.serial + 1, now * 1000)
    peer.epoch = state.serial
    peer.blockedEpoch = previous and (previous.blockedEpoch or 0) or 0
    peer.consent = true
    peer.nextProbe = now + 12
    state.peers[peer.id] = peer
    transmit(guild, peer, "H", send)
    return peer
end

function partners.disconnect(guild, id, now, send)
    local peer = partners.store(guild).peers[id]
    if not peer or not peer.consent then return end
    peer.consent, peer.confirmed, peer.revoking = false, nil, true
    peer.blockedEpoch = math.max(peer.blockedEpoch or 0, peer.remoteEpoch or 0)
    peer.nextProbe = now + 12
    transmit(guild, peer, "X", send)
    return true
end

function partners.receive(guild, sender, message, now, sameRelay, send)
    local kind, from, to, remoteEpoch, echoedEpoch =
        message:match("^P:L:([HKXY]):([0-9A-F]+):([0-9A-F]+):(%d+):(%d+)$")
    if not kind or to ~= partners.id(guild) then return end
    local peer = partners.store(guild).peers[from]
    if not peer or not sameRelay(sender, peer.relay) then return end
    remoteEpoch, echoedEpoch = tonumber(remoteEpoch), tonumber(echoedEpoch)
    if remoteEpoch < 1 or remoteEpoch > (now + 300) * 1000 then return end
    if kind == "Y" then
        if peer.revoking and echoedEpoch == peer.epoch and remoteEpoch == peer.remoteEpoch then
            peer.revoking = nil
            return true
        end
        return
    end
    if kind == "X" then
        if remoteEpoch ~= peer.remoteEpoch or echoedEpoch ~= peer.epoch then return end
        peer.consent, peer.confirmed, peer.revoking = false, nil, nil
        peer.blockedEpoch = math.max(peer.blockedEpoch or 0, remoteEpoch)
        transmit(guild, peer, "Y", send)
        return true
    end
    if not peer.consent or remoteEpoch <= (peer.blockedEpoch or 0)
        or remoteEpoch < (peer.remoteEpoch or 0) then return end
    if kind == "K" and echoedEpoch ~= peer.epoch then return end
    if remoteEpoch ~= peer.remoteEpoch then
        peer.remoteEpoch, peer.confirmed = remoteEpoch, nil
    end
    if kind == "H" then
        transmit(guild, peer, "K", send)
    end
    peer.pending, peer.backoff = nil, nil
    if echoedEpoch == peer.epoch then
        peer.confirmed, peer.lastSeen = true, now
    end
    return true
end

function partners.tick(guild, now, send)
    local due = {}
    for _, peer in pairs(partners.store(guild).peers) do
        if (peer.consent or peer.revoking) and (peer.nextProbe or 0) <= now then due[#due+1] = peer end
    end
    table.sort(due, function(a,b) return (a.nextProbe or 0) < (b.nextProbe or 0) end)
    for i = 1, math.min(3, #due) do
        local peer = due[i]
        -- No answer since the last probe: the relay is probably offline, so back off
        -- (18 s doubling up to 10 min) instead of whispering every few seconds.
        if peer.pending then peer.backoff = math.min(600, (peer.backoff or 18) * 2) end
        transmit(guild, peer, peer.revoking and "X" or "H", send)
        peer.pending = true
        peer.nextProbe = now + (peer.backoff or (peer.confirmed and 55 or 18))
    end
end

-- Seconds of silence after which a confirmed partnership is shown as inactive.
partners.inactiveAfter = 3 * 86400

function partners.status(peer, now)
    if not peer.consent then return "disconnected" end
    if not peer.confirmed then return "waiting" end
    if now - (peer.lastSeen or 0) > partners.inactiveAfter then return "inactive" end
    if now - (peer.lastSeen or 0) > 120 then return "unreachable" end
    return "connected"
end

-- The guild master shares the partner list with the guild so every member can see it.
-- Packet: P:G:<id>:<0|1>:<stamp>:<realm>:<name>, accepted only from the guild master.
function partners.shareKnown(guild, now, broadcast)
    local state = partners.store(guild)
    if (state.nextShare or 0) > now then return end
    state.nextShare = now + 300
    for id, peer in pairs(state.peers) do
        local active = peer.consent and peer.confirmed and 1 or 0
        broadcast(("P:G:%s:%d:%.0f:%s:%s"):format(id, active, now, peer.realm, peer.name))
    end
    if state.relay then broadcast("P:Q:" .. state.relay) end
end

-- Members learn which character relays partner events (announced by the guild master).
function partners.receiveRelay(guild, packet, fromMaster)
    local relay = fromMaster and packet:match("^P:Q:([^:%c|]+)$")
    if not relay or #relay > 115 then return end
    partners.store(guild).announcedRelay = relay
    return true
end

function partners.receiveKnown(guild, packet, fromMaster, now)
    if not fromMaster then return end
    local id, active, stamp, realm, name = packet:match("^P:G:([0-9A-F]+):([01]):(%d+):([^:;|%c]+):([^;|%c]+)$")
    stamp = tonumber(stamp)
    if not id or #id ~= 16 or #realm > 45 or #name > 70 or stamp > now + 300 then return end
    local known = partners.store(guild).known
    if known[id] and known[id].stamp >= stamp then return end
    known[id] = { realm = realm, name = name, active = active == "1", stamp = stamp }
    return true
end

-- Shared dungeon events (read-only for the partner guild). Flow: the event owner flags
-- the event (P:S, guild channel), the own relay whispers it to each confirmed partner
-- relay (P:E), and the receiving relay announces it in its guild (P:F). Sign-ups stay
-- with the organizer (whisper); nothing is written into the other guild's board.
local function parseEvent(prefix, message)
    local from, owner, token, ends, closed, activity, title = message:match("^" .. prefix
        .. ":([0-9A-F]+):([^:%c|]+):(%d+%-%d+):(%d+):([01]):(%d+):([^:%c|]+)$")
    if not from or #from ~= 16 or #owner > 115 or #token > 24 or #title > 52 then return end
    activity = tonumber(activity)
    return from, { owner = owner, token = token, ends = tonumber(ends), closed = closed == "1",
        activity = activity > 0 and activity or nil, title = title }
end

local function eventPacket(prefix, from, event)
    return ("%s:%s:%s:%s:%.0f:%d:%d:%s"):format(prefix, from, event.owner, event.token, event.ends,
        event.closed and 1 or 0, event.activity or 0, event.title)
end

local function storeEvent(state, from, event, now)
    if event.ends <= now or event.ends > now + 31 * 86400 then return end
    local id = from .. "/" .. event.owner .. "/" .. event.token
    local previous = state.events[id]
    if previous and previous.ends == event.ends and previous.closed == event.closed then return end
    event.from, event.nextShare = from, 0
    state.events[id] = event
    return true
end

function partners.events(guild)
    local state = partners.store(guild)
    state.events = state.events or {}
    state.flags = state.flags or {}
    return state.events, state.flags
end

-- Relay side: P:E from a confirmed partner relay.
function partners.receiveEvent(guild, sender, message, now, sameRelay)
    local from, event = parseEvent("P:E", message)
    local peer = from and partners.store(guild).peers[from]
    if not peer or not peer.consent or not peer.confirmed or not sameRelay(sender, peer.relay) then return end
    partners.events(guild)
    return storeEvent(partners.store(guild), from, event, now)
end

-- Member side: P:F inside the own guild, only from a trusted sender (guild master or relay).
function partners.receiveGuildEvent(guild, message, trusted, now)
    if not trusted then return end
    local from, event = parseEvent("P:F", message)
    if not from then return end
    partners.events(guild)
    return storeEvent(partners.store(guild), from, event, now)
end

-- Relay side: forward own flagged events to every confirmed partner and re-announce
-- received partner events in the own guild. At most three messages per call.
function partners.relayEvents(guild, ownEvents, now, send, broadcast)
    local state, sent = partners.store(guild), 0
    local events = partners.events(guild)
    for id, event in pairs(events) do
        if event.ends <= now then events[id] = nil end
    end
    local own = partners.id(guild)
    state.forwardAt = state.forwardAt or {}
    for key, at in pairs(state.forwardAt) do
        if at < now - 86400 then state.forwardAt[key] = nil end
    end
    for _, event in ipairs(ownEvents) do
        for peerID, peer in pairs(state.peers) do
            if sent >= 3 then return end
            local key = event.owner .. "/" .. event.token .. "/" .. peerID
            if peer.consent and peer.confirmed and (state.forwardAt[key] or 0) <= now then
                state.forwardAt[key] = now + 300
                send(peer.relay, eventPacket("P:E", own, event))
                sent = sent + 1
            end
        end
    end
    for _, event in pairs(events) do
        if sent >= 3 then return end
        if (event.nextShare or 0) <= now then
            event.nextShare = now + 300
            broadcast(eventPacket("P:F", event.from, event))
            sent = sent + 1
        end
    end
end
