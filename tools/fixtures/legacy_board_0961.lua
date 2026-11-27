local _, addon = ...
local board = {}
addon.board = board

local states = { O = true, W = true, R = true, D = true, X = true }

local function clock()
    return GetServerTime and GetServerTime() or time()
end
local function validToken(token)
    return token and #token <= 24 and token:match("^%d+%-%d+$")
end

local function validNumber(number, maximum)
    return number and number >= 1 and number <= maximum and number % 1 == 0
end

function board.records(guild)
    if not guild then return {} end
    ForeverGuildBoard = ForeverGuildBoard or {}
    ForeverGuildBoard[guild] = ForeverGuildBoard[guild] or {}
    return ForeverGuildBoard[guild]
end

local function id(owner, token)
    return owner .. "/" .. token
end

local function cleanNote(note)
    return (note:gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

function board.state(order, now)
    if order.state == "O" and order.expiresAt and now >= order.expiresAt then return "E" end
    return order.state
end

local function expiration(token, days)
    if validNumber(days, 30) then return tonumber(token:match("^%d+")) + days * 86400 end
end

local function sendSnapshot(order, broadcast)
    if order.days then
        return broadcast(("B:V:%d:%s:%d:%d:%d:%s:%d:%s:%s"):format(order.days, order.token,
            order.revision, order.recipe, order.quantity, order.state,
            order.supplies and 1 or 0, order.crafter or "", order.note))
    end
    return broadcast(("B:S:%s:%d:%d:%d:%s:%d:%s:%s"):format(order.token,
        order.revision, order.recipe, order.quantity, order.state,
        order.supplies and 1 or 0, order.crafter or "", order.note))
end

function board.post(guild, player, recipe, quantity, supplies, note, broadcast, days)
    if not guild or not validNumber(days, 30) then return end
    local _, token = addon.orders.packet(recipe, quantity)
    note = cleanNote(note or "")
    if not token or #note > 68 then return end
    local records = board.records(guild)
    local order = { owner = player, token = token, recipe = recipe, quantity = quantity,
        supplies = supplies, note = note, state = "O", revision = 1, days = days, expiresAt = expiration(token, days) }
    records[id(player, token)] = order
    sendSnapshot(order, broadcast)
    return order
end

local function transition(order, sender, action)
    local state = board.state(order, clock())
    if action == "take" and state == "O" and sender ~= order.owner then
        order.crafter, order.state = sender, "W"
    elseif action == "ready" and state == "W" and sender == order.crafter then
        order.state = "R"
    elseif action == "release" and (state == "W" or state == "R") and sender == order.crafter then
        order.crafter, order.state = nil, "O"
    elseif action == "received" and state == "R" and sender == order.owner then
        order.state = "D"
    elseif action == "cancel" and state == "O" and sender == order.owner then
        order.state = "X"
    else
        return false
    end
    order.revision = order.revision + 1
    if order.state == "D" or order.state == "X" then order.closedAt = clock() end
    order.nextShare = nil
    return true
end

local function sendIntent(order, target, now)
    order.nextAttempt = now + 25
    return target(order.owner, ("B:I:%s:%d:%s"):format(order.token, order.revision, order.intent))
end

function board.action(order, player, action, broadcast, target, now)
    if board.state(order, now) == "E" then return end
    if player == order.owner then
        if transition(order, player, action) then sendSnapshot(order, broadcast); return true end
    elseif not order.intent then
        order.intent = action
        sendIntent(order, target, now)
        return true
    end
end

function board.receive(guild, player, sender, packet, targeted, broadcast)
    local records = board.records(guild)
    if targeted then
        local token, revision, action = packet:match("^B:I:(%d+%-%d+):(%d+):(%l+)$")
        local order = validToken(token) and records[id(player, token)]
        if not order then return end
        if order.revision ~= tonumber(revision) then
            sendSnapshot(order, broadcast)
            return
        end
        if transition(order, sender, action) then
            sendSnapshot(order, broadcast)
            return true
        end
        return
    end

    local days, body = packet:match("^B:V:(%d%d?):(.+)$")
    if days then
        days = tonumber(days)
        if not validNumber(days, 30) then return end
        packet = "B:S:" .. body
    end
    local token, revision, recipe, quantity, state, supplies, crafter, note =
        packet:match("^B:S:(%d+%-%d+):(%d+):(%d+):(%d+):([OWRDX]):([01]):([^:%c|]*):(.*)$")
    revision, recipe, quantity = tonumber(revision), tonumber(recipe), tonumber(quantity)
    if not validToken(token) or not validNumber(revision, 2147483647) or not validNumber(recipe, 2147483647)
        or not validNumber(quantity, 200) or not states[state] or #crafter > 115 or #note > 68
        or cleanNote(note) ~= note or ((state == "O" or state == "X") ~= (crafter == "")) then return end
    local key = id(sender, token)
    local previous = records[key]
    if previous and (previous.revision >= revision or previous.recipe ~= recipe or previous.quantity ~= quantity or previous.days ~= days) then return end
    records[key] = { owner = sender, token = token, recipe = recipe, quantity = quantity,
        state = state, revision = revision, supplies = supplies == "1",
        crafter = crafter ~= "" and crafter or nil, note = note, days = days, expiresAt = expiration(token, days) }
    return true
end

function board.tick(guild, player, now, online, broadcast, target)
    local due = {}
    for _, order in pairs(board.records(guild)) do
        local effective = board.state(order, now)
        local closedAt = order.closedAt or (effective == "E" and order.expiresAt)
        local shareable = not closedAt or now - closedAt <= 14 * 86400
        if effective == "E" then order.intent = nil end
        if order.owner == player and shareable and (order.nextShare or 0) <= now then
            due[#due + 1] = { order = order, at = order.nextShare or 0 }
        elseif order.intent and online(order.owner) and (order.nextAttempt or 0) <= now then
            due[#due + 1] = { order = order, at = order.nextAttempt or 0 }
        end
    end
    table.sort(due, function(a, b) return a.at < b.at end)
    for index = 1, math.min(3, #due) do
        local order = due[index].order
        if order.owner == player then
            local interval = (order.state == "D" or order.state == "X" or board.state(order, now) == "E") and 300 or 90
            order.nextShare = now + (sendSnapshot(order, broadcast) and interval or 15)
        else
            sendIntent(order, target, now)
        end
    end
end
