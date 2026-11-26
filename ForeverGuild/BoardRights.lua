local _, addon = ...
local rights = {}
addon.boardRights = rights
rights.flags = { order = 1, group = 2, news = 4, modOrder = 8, modGroup = 16, modNews = 32 }
rights.labels = {
    {"order", "Handwerksaufträge erstellen", "Create Open Orders"},
    {"group", "Dungeon-Termine erstellen", "Create Dungeon Events"},
    {"news", "Mitteilungen veröffentlichen", "Publish Announcements"},
    {"modOrder", "Handwerksaufträge moderieren", "Moderate Orders"},
    {"modGroup", "Dungeon-Termine moderieren", "Moderate Events"},
    {"modNews", "Mitteilungen moderieren", "Moderate Announcements"},
}
local defaults = {3, 63, 19, 11}
local function bit(mask, flag)
    return math.floor(mask / flag) % 2 == 1
end
function rights.store(guild)
    ForeverGuildBoardRights = ForeverGuildBoardRights or {}
    local state = ForeverGuildBoardRights[guild]
    if not state then
        state = { roles = {}, members = {}, hidden = {} }
        ForeverGuildBoardRights[guild] = state
    end
    return state
end

function rights.mask(guild, role)
    local row = rights.store(guild).roles[role]
    return row and row.value or defaults[role]
end

function rights.memberMask(guild, member)
    local row = rights.store(guild).members[member]
    return row and row.value or 0
end

function rights.has(guild, member, key, rule, officer, master)
    if not guild or not member then return false end
    if master then return true end
    local flag = rights.flags[rule]
    if not flag then return false end
    if bit(rights.mask(guild, 1), flag) then return true end
    if rule == "news" and officer and not rights.store(guild).roles[1] then return true end
    local mask = rights.memberMask(guild, key)
    for role = 2, 4 do
        if bit(mask, 2^(role-2)) and bit(rights.mask(guild, role), flag) then return true end
    end
    return false
end

local function write(records, id, revision, value, packet)
    local previous = records[id]
    if previous and previous.revision >= revision then return false end
    records[id] = { revision = revision, value = value, packet = packet }
    return true
end

function rights.receive(guild, sender, packet, master, canModerate, now)
    local state = rights.store(guild)
    local role, mask, rev = packet:match("^P:R:([1-4]):(%d+):(%d+)$")
    if role and master and tonumber(mask) <= 63 and tonumber(rev) <= now*1000+300000 then
        return write(state.roles, tonumber(role), tonumber(rev), tonumber(mask), packet)
    end
    -- P:O: which guild ranks count as officers (0 = by rank name, n = ranks 1..n), master only.
    local officerRank, officerRev = packet:match("^P:O:(%d+):(%d+)$")
    if officerRank and master and tonumber(officerRank) <= 9 and tonumber(officerRev) <= now*1000+300000 then
        local previous = state.officer
        if previous and previous.revision >= tonumber(officerRev) then return false end
        state.officer = { revision = tonumber(officerRev), value = tonumber(officerRank), packet = packet }
        return true
    end
    local subject
    mask, rev, subject = packet:match("^P:M:([0-7]):(%d+):([^:%c|]+)$")
    if subject and master and #subject <= 115 and tonumber(rev) <= now*1000+300000 then
        return write(state.members, subject, tonumber(rev), tonumber(mask), packet)
    end
    -- P:X is the original hide packet (no revision, treated as revision 0). P:Y carries a
    -- revision and a state (1 = hidden, 0 = restored), so a hide can be undone later.
    local kind, token, owner = packet:match("^P:X:([OGA]):(%d+%-%d+):([^:%c|]+)$")
    local active, revision = true, 0
    if not kind then
        local flag
        kind, token, rev, flag, owner = packet:match("^P:Y:([OGA]):(%d+%-%d+):(%d+):([01]):([^:%c|]+)$")
        revision, active = tonumber(rev), flag == "1"
        if revision and revision > now * 1000 + 300000 then return end
    end
    local created = token and tonumber(token:match("^%d+"))
    if not owner or #owner > 115 or #token > 24 or created > now + 300 or not canModerate(kind) then return end
    local id = kind .. "/" .. owner .. "/" .. token
    local previous = state.hidden[id]
    if previous and (previous.revision or 0) >= revision then return end
    state.hidden[id] = { packet = packet, by = sender, at = now, revision = revision, active = active,
        created = created, kind = kind, owner = owner, token = token }
    return true
end

function rights.officerRank(guild)
    local row = guild and rights.store(guild).officer
    return row and row.value > 0 and row.value or nil
end

function rights.hidden(guild, kind, owner, token)
    local row = guild and rights.store(guild).hidden[kind .. "/" .. owner .. "/" .. token]
    return row and row.active ~= false and row or nil
end

function rights.hiddenList(guild)
    local rows = {}
    for _, row in pairs(rights.store(guild).hidden) do
        if row.active ~= false and row.owner then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b) return (a.at or 0) > (b.at or 0) end)
    return rows
end

-- Board posts live at most 30 days; their moderation records can go a day later. Member
-- assignments of characters no longer in the guild are dropped on the master's client,
-- which is the only one that re-shares them.
function rights.prune(guild, now, master, isMember)
    local state = rights.store(guild)
    for id, row in pairs(state.hidden) do
        local created = row.created or tonumber((row.packet or ""):match("(%d+)%-%d+"))
        if created and created < now - 31 * 86400 then state.hidden[id] = nil end
    end
    if master and isMember then
        for key in pairs(state.members) do
            if not isMember(key) then state.members[key] = nil end
        end
    end
end

function rights.tick(guild, player, master, now, canModerate, broadcast)
    local state, due = rights.store(guild), {}
    local function collect(list, allowed)
        for _, row in pairs(list) do
            if allowed(row) and (row.nextShare or 0) <= now then due[#due+1] = row end
        end
    end
    if master then
        collect(state.roles, function() return true end)
        collect(state.members, function() return true end)
        if state.officer then collect({ state.officer }, function() return true end) end
    end
    collect(state.hidden, function(row)
        return row.by == player and canModerate(row.packet:sub(5,5))
    end)
    table.sort(due, function(a,b) return (a.nextShare or 0) < (b.nextShare or 0) end)
    for i = 1, math.min(3,#due) do
        local row = due[i]
        row.nextShare = now + (broadcast(row.packet) and 100 or 18)
    end
end
