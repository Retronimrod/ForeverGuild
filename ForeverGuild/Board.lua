local _, addon = ...
local board = {}
addon.board = board
local market = addon.market

-- Shared order store for the bulletin board and the crafting marketplace.
-- The requester's client is authoritative: other clients send intents (B:I legacy,
-- B:J extended) and only a snapshot with a higher revision makes a change binding.
-- Packets: B:S/B:V legacy snapshot (still sent for public orders so older clients keep
-- working), B:N extended state, B:A attachments (materials provided, reply, note).
local legacyStates = { O = true, W = true, R = true, D = true, X = true }
local legacyMap = { O = "O", M = "W", W = "W", R = "R", H = "R", D = "D", X = "X" }
local legacyActions = { take = true, ready = true, release = true, received = true, cancel = true }

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
board.id = id

local function cleanNote(note)
    return (note:gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end
board.cleanNote = cleanNote

local function cleanReply(text)
    if type(text) ~= "string" then return nil end
    text = cleanNote(text):gsub(":", " ")
    if text == "" then return nil end
    return text:sub(1, 60)
end

function board.state(order, now)
    return market.state(order, now)
end

local function expiration(token, days)
    if validNumber(days, 30) then return tonumber(token:match("^%d+")) + days * 86400 end
end

local function notify(guild, order, before, localActor)
    local events = market.diff(before, order)
    market.log(order, events, clock())
    if board.observer then board.observer(guild, order, events, localActor) end
end

-- Encoding --------------------------------------------------------------------------------
local function flags(order)
    local list = {}
    if order.direct then list[#list + 1] = "d" end
    if order.tipEach then list[#list + 1] = "e" end
    if order.pay == "v" then list[#list + 1] = "v" elseif order.pay == "f" then list[#list + 1] = "f" end
    if order.supplies then list[#list + 1] = "s" end
    if order.waived then list[#list + 1] = "w" end
    if order.dispute then list[#list + 1] = "x" end
    if order.missing then list[#list + 1] = "n" end
    if order.cancelBy == "o" then list[#list + 1] = "O" elseif order.cancelBy == "c" then list[#list + 1] = "C" end
    return table.concat(list)
end

local function providedText(order)
    local items = {}
    for item in pairs(order.provided or {}) do items[#items + 1] = item end
    table.sort(items)
    local parts = {}
    for _, item in ipairs(items) do
        if order.provided[item] > 0 and #parts < 10 then parts[#parts + 1] = item .. "*" .. order.provided[item] end
    end
    return table.concat(parts, ",")
end

local function legacyDays(order)
    local created = tonumber(order.token:match("^%d+")) or clock()
    local days = math.ceil(((order.expiresAt or created) - created) / 86400)
    return math.max(1, math.min(30, days))
end

local function sendSnapshot(order, broadcast)
    if not order.ext then
        if order.days then
            return broadcast(("B:V:%d:%s:%d:%d:%d:%s:%d:%s:%s"):format(order.days, order.token,
                order.revision, order.recipe, order.quantity, order.state,
                order.supplies and 1 or 0, order.crafter or "", order.note))
        end
        return broadcast(("B:S:%s:%d:%d:%d:%s:%d:%s:%s"):format(order.token,
            order.revision, order.recipe, order.quantity, order.state,
            order.supplies and 1 or 0, order.crafter or "", order.note))
    end
    local proposal = order.proposal and (order.proposal.f .. order.proposal.v .. order.proposal.by) or ""
    local sent = broadcast(("B:N:%s:%d:%d:%d:%s:%s:%d:%d:%.0f:%.0f:%.0f:%.0f:%.0f:%d:%d:%d:%d:%.0f:%.0f:%s:%s"):format(
        order.token, order.revision, order.recipe, order.quantity, order.state, flags(order), order.method or 1,
        order.matState or 0, order.expiresAt or 0, order.due or 0, order.tip or 0, order.cost or 0, order.costOffer or 0,
        order.dueDays or 0, order.crafted or 0, order.shipped or 0, order.delivered or 0, order.paidSent or 0,
        order.paidGot or 0, proposal, order.crafter or ""))
    broadcast(("B:A:%s:%d:%s:%s:%s"):format(order.token, order.revision, providedText(order),
        order.reply or "", order.note or ""))
    -- Older clients still see public orders in their simplified form.
    local legacy = legacyMap[order.state]
    if not order.direct and legacy then
        local crafter = (legacy == "O" or legacy == "X") and "" or (order.crafter or "")
        if crafter ~= "" or legacy == "O" or legacy == "X" then
            broadcast(("B:V:%d:%s:%d:%d:%d:%s:%d:%s:%s"):format(legacyDays(order), order.token, order.revision,
                order.recipe, math.min(order.quantity, 200), legacy, order.supplies and 1 or 0, crafter, order.note or ""))
        end
    end
    return sent
end
board.sendSnapshot = sendSnapshot

-- Creation and edits ------------------------------------------------------------------------
-- fields: recipe, quantity, note, days, direct, crafter, tip, tipEach, pay ("n"/"v"/"f"),
-- cost, provided {itemID = total}, method (1-4), dueDays, supplies
function board.create(guild, player, fields, broadcast)
    local days = fields.days
    if not guild or not validNumber(days, 30) then return end
    local _, token = addon.orders.packet(fields.recipe, fields.quantity)
    local note = cleanNote(fields.note or "")
    if not token or #note > 68 then return end
    if fields.direct and (type(fields.crafter) ~= "string" or fields.crafter == "" or fields.crafter == player) then return end
    local order = { ext = true, owner = player, token = token, recipe = fields.recipe, quantity = fields.quantity,
        note = note, state = fields.direct and "Q" or "O", revision = 1, expiresAt = expiration(token, days),
        direct = fields.direct and true or nil, crafter = fields.direct and fields.crafter or nil,
        tip = fields.tip or 0, tipEach = fields.tipEach and true or nil, pay = fields.pay or "n",
        cost = fields.cost or 0, costOffer = 0, provided = fields.provided or {}, method = fields.method or 1,
        dueDays = fields.dueDays or 0, due = 0, supplies = fields.supplies and true or nil,
        crafted = 0, shipped = 0, delivered = 0, paidSent = 0, paidGot = 0, matState = 0, created = clock() }
    board.records(guild)[id(player, token)] = order
    notify(guild, order, nil, true)
    sendSnapshot(order, broadcast)
    return order
end

function board.edit(guild, order, fields, broadcast)
    if not order.ext then return false end
    local before = market.capture(order)
    if fields.note then
        fields.note = cleanNote(fields.note)
        if #fields.note > 68 then return false end
    end
    if not market.edit(order, fields, clock()) then return false end
    order.revision = order.revision + 1
    order.nextShare = nil
    notify(guild, order, before, true)
    sendSnapshot(order, broadcast)
    return true
end

-- Legacy transition for orders created by older clients.
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
    return true
end

local function change(guild, order, sender, action, arg, text)
    local before = market.capture(order)
    local ok
    if order.ext then
        ok = market.apply(order, sender, action, arg, text, clock())
    else
        ok = legacyActions[action] and transition(order, sender, action)
    end
    if not ok then return false end
    order.revision = order.revision + 1
    if market.closed[order.state] and not order.closedAt then order.closedAt = clock() end
    order.nextShare = nil
    notify(guild, order, before, sender)
    return true
end

local function sendIntent(order, target, now)
    order.nextAttempt = now + 25
    order.attempts = (order.attempts or 0) + 1
    if order.ext then
        return target(order.owner, ("B:J:%s:%d:%s:%d:%s"):format(order.token, order.revision, order.intent,
            order.intentArg or 0, order.intentText or ""))
    end
    return target(order.owner, ("B:I:%s:%d:%s"):format(order.token, order.revision, order.intent))
end

-- Requests a change. The requester applies it immediately; anybody else sends an
-- intent that stays pending until the requester's snapshot confirms it.
function board.action(order, player, action, broadcast, target, now, arg, text, guild)
    if player == order.owner then
        if change(guild, order, player, action, arg, cleanReply(text) or text) then
            sendSnapshot(order, broadcast)
            return true
        end
        return false
    end
    if order.intent then return false end
    if not order.ext and not legacyActions[action] then return false end
    if board.state(order, now) == "E" and action == "take" then return false end
    order.intent, order.intentArg, order.intentText, order.attempts = action, tonumber(arg) or 0, cleanReply(text), 0
    sendIntent(order, target, now)
    return true
end

-- Receiving --------------------------------------------------------------------------------------
board.pendingAttach = {}

local function applyAttachment(order, attachment)
    if (order.attachRev or 0) > attachment.revision then return end
    order.attachRev = attachment.revision
    order.provided, order.reply, order.note = attachment.provided, attachment.reply, attachment.note
end

local function parseProvided(text)
    local provided = {}
    for item, count in text:gmatch("(%d+)%*(%d+)") do
        item, count = tonumber(item), tonumber(count)
        if validNumber(item, 2147483647) and validNumber(count, 20000) then provided[item] = count end
    end
    return provided
end

local function receiveExtended(guild, records, sender, packet)
    local token, revision, recipe, quantity, state, flagText, method, matState, expiresAt, due, tip, cost, costOffer,
        dueDays, crafted, shipped, delivered, paidSent, paidGot, proposal, crafter = packet:match(
        "^B:N:(%d+%-%d+):(%d+):(%d+):(%d+):(%u):(%a*):(%d):(%d):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%w*):([^:%c|]*)$")
    if not token or not validToken(token) or #crafter > 115 or #flagText > 12 then return end
    revision, recipe, quantity = tonumber(revision), tonumber(recipe), tonumber(quantity)
    if not validNumber(revision, 2147483647) or not validNumber(recipe, 2147483647) or not validNumber(quantity, 200)
        or not market.states[state] then return end
    local numbers = { tonumber(expiresAt), tonumber(due), tonumber(tip), tonumber(cost), tonumber(costOffer),
        tonumber(paidSent), tonumber(paidGot) }
    for _, value in ipairs(numbers) do
        if not market.validMoney(value) then return end
    end
    local counts = { tonumber(crafted), tonumber(shipped), tonumber(delivered) }
    for _, value in ipairs(counts) do
        if value > quantity then return end
    end
    local direct = flagText:find("d", 1, true) ~= nil
    if (state == "O" and crafter ~= "") or ((state == "Q" or market.accepted[state]) and crafter == "") then return end
    if direct and state == "O" then return end
    local key = id(sender, token)
    if market.isRemoved(guild, key) then return end
    local order = records[key]
    if order and order.ext and order.revision >= revision then return end
    -- A stale or forged packet must never reopen a finished order.
    if order and (order.state == "D" or order.state == "X") and state ~= order.state then return end
    if order and order.recipe ~= recipe then return end
    local before = order and order.ext and market.capture(order) or nil
    local claimed = order and order.intent == "take"
    if not order then
        order = { owner = sender, token = token, recipe = recipe }
        records[key] = order
    end
    order.ext, order.revision, order.quantity, order.state = true, revision, quantity, state
    order.direct = direct or nil
    order.tipEach = flagText:find("e", 1, true) ~= nil or nil
    order.pay = flagText:find("f", 1, true) and "f" or (flagText:find("v", 1, true) and "v" or "n")
    order.supplies = flagText:find("s", 1, true) ~= nil or nil
    order.waived = flagText:find("w", 1, true) ~= nil or nil
    order.dispute = flagText:find("x", 1, true) ~= nil or nil
    order.missing = flagText:find("n", 1, true) ~= nil or nil
    order.cancelBy = flagText:find("O", 1, true) and "o" or (flagText:find("C", 1, true) and "c" or nil)
    order.method = math.max(1, math.min(#market.methods, tonumber(method)))
    order.matState = math.min(2, tonumber(matState))
    order.expiresAt = numbers[1] > 0 and numbers[1] or nil
    order.due, order.tip, order.cost, order.costOffer = numbers[2], numbers[3], numbers[4], numbers[5]
    order.dueDays = math.min(30, tonumber(dueDays))
    order.crafted, order.shipped, order.delivered = counts[1], counts[2], counts[3]
    order.paidSent, order.paidGot = numbers[6], numbers[7]
    local field, value, by = proposal:match("^([qtmd])(%d+)([oc])$")
    order.proposal = field and { f = field, v = tonumber(value), by = by } or nil
    order.crafter = crafter ~= "" and crafter or nil
    order.intent, order.intentArg, order.intentText, order.attempts = nil, nil, nil, nil
    if market.closed[state] and not order.closedAt then order.closedAt = clock() end
    local attachment = board.pendingAttach[key]
    if attachment then
        board.pendingAttach[key] = nil
        applyAttachment(order, attachment)
    end
    notify(guild, order, before, nil)
    if claimed and board.observer and board.lost then board.lost(guild, order) end
    return true
end

local function receiveAttachment(guild, records, sender, packet)
    local token, revision, provided, reply, note = packet:match("^B:A:(%d+%-%d+):(%d+):([%d%*,]*):([^:%c|]*):(.*)$")
    revision = tonumber(revision)
    if not validToken(token) or not validNumber(revision, 2147483647) or #provided > 140 or #reply > 60
        or #note > 68 or cleanNote(note) ~= note then return end
    local attachment = { revision = revision, provided = parseProvided(provided), reply = reply ~= "" and reply or nil, note = note }
    local key = id(sender, token)
    if market.isRemoved(guild, key) then return end
    local order = records[key]
    if order and order.ext then
        applyAttachment(order, attachment)
        return true
    end
    board.pendingAttach[key] = attachment
end

function board.receive(guild, player, sender, packet, targeted, broadcast, target)
    local records = board.records(guild)
    if targeted and packet:sub(1, 4) == "B:K:" then
        -- The requester refused our intent (invalid or outdated); end the pending state.
        local token = packet:match("^B:K:(%d+%-%d+):%d+$")
        local order = validToken(token) and records[id(sender, token)]
        if order and order.intent then
            market.log(order, { { code = "unconfirmed" } }, clock())
            order.intent, order.intentArg, order.intentText, order.attempts = nil, nil, nil, nil
            return true
        end
        return
    end
    if targeted then
        local token, revision, action, arg, text = packet:match("^B:J:(%d+%-%d+):(%d+):(%l+):(%d+):([^:%c|]*)$")
        if not token then
            token, revision, action = packet:match("^B:I:(%d+%-%d+):(%d+):(%l+)$")
        end
        local order = validToken(token) and records[id(player, token)]
        if not order or #action > 12 then return end
        if order.revision ~= tonumber(revision) then
            sendSnapshot(order, broadcast)
            return
        end
        if change(guild, order, sender, action, tonumber(arg) or 0, cleanReply(text)) then
            sendSnapshot(order, broadcast)
            return true
        end
        -- Rejected: tell the sender so the pending intent ends; older clients ignore B:K.
        if target and order.ext then target(sender, ("B:K:%s:%d"):format(order.token, order.revision)) end
        sendSnapshot(order, broadcast)
        return
    end
    if packet:sub(1, 4) == "B:N:" then return receiveExtended(guild, records, sender, packet) end
    if packet:sub(1, 4) == "B:A:" then return receiveAttachment(guild, records, sender, packet) end

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
        or not validNumber(quantity, 200) or not legacyStates[state] or #crafter > 115 or #note > 68
        or cleanNote(note) ~= note or ((state == "O" or state == "X") ~= (crafter == "")) then return end
    local key = id(sender, token)
    if market.isRemoved(guild, key) then return end
    local previous = records[key]
    -- Extended orders also send the legacy form; their B:N snapshot is authoritative.
    if previous and previous.ext then return end
    if previous and (previous.revision >= revision or previous.recipe ~= recipe or previous.quantity ~= quantity or previous.days ~= days) then return end
    local before = previous and market.capture(previous) or nil
    local order = { owner = sender, token = token, recipe = recipe, quantity = quantity,
        state = state, revision = revision, supplies = supplies == "1",
        crafter = crafter ~= "" and crafter or nil, note = note, days = days, expiresAt = expiration(token, days) }
    if previous then
        order.log, order.reminded = previous.log, previous.reminded
    end
    if (state == "D" or state == "X") then order.closedAt = previous and previous.closedAt or clock() end
    records[key] = order
    notify(guild, order, before, nil)
    if previous and previous.intent == "take" and board.lost then board.lost(guild, order) end
    return true
end

-- Local removal (this character only): deletes the record and leaves a tombstone.
function board.removeLocal(guild, key, now)
    board.records(guild)[key] = nil
    board.pendingAttach[key] = nil
    market.remove(guild, key, now)
end

function board.tick(guild, player, now, online, broadcast, target)
    local due = {}
    local records = board.records(guild)
    local keep = math.max(14, market.setting("keepDays") or 30) * 86400
    for key, order in pairs(records) do
        local effective = board.state(order, now)
        local closedAt = order.closedAt or (effective == "E" and order.expiresAt)
        local shareable = not closedAt or now - closedAt <= 14 * 86400
        if closedAt and now - closedAt > keep and not order.intent then
            records[key] = nil
        else
            if effective == "E" and order.intent == "take" then order.intent = nil end
            if order.intent and (order.attempts or 0) >= 6 then
                order.intent, order.intentArg, order.intentText, order.attempts = nil, nil, nil, nil
                market.log(order, { { code = "unconfirmed" } }, now)
            end
            if order.owner == player and shareable and (order.nextShare or 0) <= now then
                due[#due + 1] = { order = order, at = order.nextShare or 0 }
            elseif order.intent and online(order.owner) and (order.nextAttempt or 0) <= now then
                due[#due + 1] = { order = order, at = order.nextAttempt or 0 }
            end
        end
    end
    table.sort(due, function(a, b) return a.at < b.at end)
    for index = 1, math.min(3, #due) do
        local order = due[index].order
        if order.owner == player then
            local interval = (market.closed[order.state] or board.state(order, now) == "E") and 300 or 90
            order.nextShare = now + (sendSnapshot(order, broadcast) and interval or 15)
        else
            sendIntent(order, target, now)
        end
    end
end
