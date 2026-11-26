local _, addon = ...
local notes = {}
addon.boardNotes = notes

local day = 86400
local function tokenTime(token)
    return token and #token <= 24 and tonumber(token:match("^(%d+)%-%d+$"))
end

local function clean(text)
    return (text:gsub("[%c|]", " "):match("^%s*(.-)%s*$"))
end

function notes.records(guild)
    if not guild then return {} end
    ForeverGuildBoardNotes = ForeverGuildBoardNotes or {}
    ForeverGuildBoardNotes[guild] = ForeverGuildBoardNotes[guild] or {}
    return ForeverGuildBoardNotes[guild]
end

local function key(owner, token)
    return owner .. "/" .. token
end

local function validSlots(slots, role)
    if type(slots) ~= "table" or not slots[role] or slots[role] < 1 then return false end
    local total = 0
    for _, key in ipairs({"T", "H", "D"}) do
        local n = slots[key]
        if type(n) ~= "number" or n < 0 or n > 40 or n % 1 ~= 0 then return false end
        total = total + n
    end
    return total <= 40
end

function notes.placements(note, eligible)
    local counts, queue, placed = { T = 0, H = 0, D = 0 }, {}, {}
    if note.slots then counts[note.ownerRole] = 1 end
    for member, reply in pairs(note.replies) do
        if reply.joined and eligible(member) then queue[#queue+1] = { member = member, reply = reply } end
    end
    table.sort(queue, function(a, b)
        local first, second = a.reply.at or 0, b.reply.at or 0
        if first == second then return a.member < b.member end
        return first < second
    end)
    for _, entry in ipairs(queue) do
        local role = entry.reply.role
        entry.confirmed = not note.slots or (role and counts[role] < note.slots[role]) or false
        if entry.confirmed and role then counts[role] = counts[role] + 1 end
        placed[entry.member] = entry.confirmed
    end
    return queue, placed, counts
end

local function send(note, broadcast)
    local text = note.text
    if note.activity then text = ("~A%d~%s"):format(note.activity, text) end
    if note.slots then
        text = ("~R%d,%d,%d,%s~%s"):format(note.slots.T, note.slots.H, note.slots.D, note.ownerRole, text)
    end
    return broadcast(("M:N:%s:%s:%d:%d:%s:%s"):format(note.token, note.kind, note.ends,
        note.closed and 1 or 0, note.title, text))
end

local function sendReply(note, reply, broadcast)
    if reply.role then
        return broadcast(("M:J:%s:%s:%d:%d:%s:%d"):format(note.owner, note.token,
            reply.revision, reply.joined and 1 or 0, reply.role, reply.at))
    end
    return broadcast(("M:R:%s:%s:%d:%d"):format(note.owner, note.token,
        reply.revision, reply.joined and 1 or 0))
end

function notes.post(guild, player, kind, title, text, starts, leader, now, broadcast, slots, role, activity)
    title, text = clean(title), clean(text)
    if not guild or not player or (kind ~= "G" and (kind ~= "A" or not leader))
        or title == "" or #title > 52 or title:find(":", 1, true) or #text > 140 then return end
    if slots and (kind ~= "G" or not validSlots(slots, role) or #text > 124) then return end
    if activity and (kind ~= "G" or not addon.getGroupDungeon(activity) or #text > 112) then return end
    local ends = kind == "A" and now + 30 * day or starts
    if not ends or ends <= now or ends > now + 30 * day then return end
    local _, token = addon.orders.packet(1, 1)
    local note = { owner = player, token = token, kind = kind, title = title, text = text,
        ends = ends, replies = {}, slots = slots, ownerRole = role, activity = activity }
    notes.records(guild)[key(player, token)] = note
    send(note, broadcast)
    return note
end

function notes.close(note, player, broadcast)
    if note.owner ~= player or note.closed then return end
    note.closed, note.nextShare = true, nil
    send(note, broadcast)
end

function notes.reply(note, player, now, broadcast, role)
    if note.kind ~= "G" or note.closed or note.ends <= now or note.owner == player then return end
    local old = note.replies[player]
    local joined = not (old and old.joined)
    if not joined then role = old.role end
    if joined and note.slots and (not role or (note.slots[role] or 0) == 0) then return end
    local reply = { joined = joined, revision = (old and old.revision or 0) + 1, role = role, at = now }
    note.replies[player] = reply
    sendReply(note, reply, broadcast)
end

function notes.receive(guild, sender, packet, leader, now)
    local records = notes.records(guild)
    local token, kind, ends, closed, title, body =
        packet:match("^M:N:(%d+%-%d+):([AG]):(%d+):([01]):([^:]+):(.*)$")
    if token then
        local created = tokenTime(token)
        ends = tonumber(ends)
        if not created or created > now + 300 or ends <= created or ends > created + 30 * day + 300
            or ends <= now or (kind == "A" and not leader) or #title > 52 or #body > 140
            or clean(title) ~= title or clean(body) ~= body then return end
        local t, h, d, role, text = body:match("^~R(%d+),(%d+),(%d+),([THD])~(.*)$")
        local slots
        if kind == "G" and t then
            slots = { T = tonumber(t), H = tonumber(h), D = tonumber(d) }
            if not validSlots(slots, role) then return end
            body = text
        end
        local activity, description = body:match("^~A(%d+)~(.*)$")
        activity = tonumber(activity)
        if kind == "G" and activity and addon.getGroupDungeon(activity) then
            body = description
        else
            activity = nil
        end
        local id = key(sender, token)
        local note = records[id]
        if note then
            if note.kind ~= kind or note.ends ~= ends or closed ~= "1" or note.closed then return end
            note.closed = true
        else
            records[id] = { owner = sender, token = token, kind = kind, ends = ends, closed = closed == "1",
                title = title, text = body, replies = {}, slots = slots, ownerRole = role, activity = activity }
        end
        return true
    end

    local owner, groupToken, revision, joined = packet:match("^M:R:([^:%c|]+):(%d+%-%d+):(%d+):([01])$")
    local role, at
    if not owner then
        owner, groupToken, revision, joined, role, at =
            packet:match("^M:J:([^:%c|]+):(%d+%-%d+):(%d+):([01]):([THD]):(%d+)$")
        at = tonumber(at)
        if not at or at > now + 300 or at < (tokenTime(groupToken) or math.huge) then return end
    end
    if not owner or #owner > 115 or not tokenTime(groupToken) or owner == sender then return end
    local note = records[key(owner, groupToken)]
    revision = tonumber(revision)
    if not note or note.kind ~= "G" or note.closed or note.ends <= now or revision < 1 or revision > 2147483647 then return end
    if role and (not note.slots or note.slots[role] < 1 or at >= note.ends) then return end
    local previous = note.replies[sender]
    if previous and previous.revision >= revision then return end
    note.replies[sender] = { revision = revision, joined = joined == "1", role = role, at = at }
    return true
end

function notes.tick(guild, player, now, leader, broadcast)
    local records = notes.records(guild)
    local due = {}
    for id, note in pairs(records) do
        if note.ends <= now then
            records[id] = nil
        elseif note.owner == player and (note.kind ~= "A" or leader) and (note.nextShare or 0) <= now then
            due[#due + 1] = { node = note, at = note.nextShare or 0 }
        elseif not note.closed and note.replies[player] then
            local reply = note.replies[player]
            if (reply.nextShare or 0) <= now then
                due[#due + 1] = { node = note, reply = reply, at = reply.nextShare or 0 }
            end
        end
    end
    table.sort(due, function(a, b) return a.at < b.at end)
    for index = 1, math.min(2, #due) do
        local entry = due[index]
        if entry.reply then
            entry.reply.nextShare = now + (sendReply(entry.node, entry.reply, broadcast) and 90 or 15)
        else
            entry.node.nextShare = now + (send(entry.node, broadcast) and 90 or 15)
        end
    end
end
