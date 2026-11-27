local _, addon = ...
local orders = {}
addon.orders = orders

local function validRecipe(id)
    return type(id) == "number" and id >= 1 and id <= 2147483647 and id % 1 == 0
end

local function validQuantity(quantity)
    return type(quantity) == "number" and quantity >= 1 and quantity <= 200 and quantity % 1 == 0
end

orders.prefix = "ForeverGuildOrd2"

function orders.packet(recipe, quantity)
    if not validRecipe(recipe) or not validQuantity(quantity) then return end
    ForeverGuildOrderSequence = (ForeverGuildOrderSequence or 0) + 1
    local seconds = GetServerTime and GetServerTime() or time()
    local token = ("%.0f-%d"):format(seconds, ForeverGuildOrderSequence)
    return ("O:%s:%d:%d"):format(token, recipe, quantity), token
end

function orders.accept(sender, message, address, guild)
    if not guild then return end
    if type(sender) ~= "string" or sender == "" or type(message) ~= "string" then return end
    local token, recipe, quantity = message:match("^O:(%d+%-%d+):(%d+):(%d+)$")
    recipe, quantity = tonumber(recipe), tonumber(quantity)
    if not token or #token > 24 or not validRecipe(recipe) or not validQuantity(quantity) then return end
    ForeverGuildOrders = ForeverGuildOrders or {}
    local key = sender .. "/direct/" .. token
    -- Locally removed: acknowledge again so the sender stops, but never recreate it.
    if addon.market and addon.market.isRemoved(guild, key) then return token, false end
    local previous = ForeverGuildOrders[key]
    if previous and (previous.guild or previous.statusGuild) == guild then return token, false end
    if previous and (previous.guild or previous.statusGuild) then return end
    ForeverGuildOrders[key] = { sender = sender, address = address, guild = guild, recipe = recipe, quantity = quantity, received = time(), done = false, unread = true }
    return token, true
end

function orders.belongsToGuild(order, guild)
    return guild ~= nil and (order.guild or order.statusGuild) == guild
end

function orders.unread(guild)
    local count, newest, newestTime = 0, nil, -math.huge
    for key, order in pairs(ForeverGuildOrders or {}) do
        if orders.belongsToGuild(order, guild) and order.unread == true and (order.outgoing or not order.done) then
            count = count + 1
            local notificationTime = order.unreadAt or order.received
            if notificationTime > newestTime or (notificationTime == newestTime and (not newest or key > newest)) then
                newest, newestTime = key, notificationTime
            end
        end
    end
    return count, newest
end

function orders.markRead(key)
    local order = ForeverGuildOrders and ForeverGuildOrders[key]
    if not order or order.unread ~= true then return false end
    order.unread = false
    return true
end

function orders.track(token, recipient, recipe, quantity, professionID, address, guild)
    ForeverGuildOrders = ForeverGuildOrders or {}
    local key = "outgoing/" .. token
    local order = ForeverGuildOrders[key]
    if not order then
        order = { outgoing = true, recipient = recipient, address = address, recipe = recipe, professionID = professionID, quantity = quantity, received = time() }
        ForeverGuildOrders[key] = order
    end
    if guild then
        order.guild = guild
        order.delivery = "waiting"
    end
    return order
end

function orders.hasPending(guild)
    if not guild then return false end
    for _, order in pairs(ForeverGuildOrders or {}) do
        if order.outgoing and order.guild == guild and order.delivery ~= "confirmed" and not order.withdrawn then return true end
    end
    return false
end

function orders.dispatch(guild, members, send, now)
    if not guild then return false end
    local ready, changed = {}, false
    for key, order in pairs(ForeverGuildOrders or {}) do
        if order.outgoing and order.guild == guild and order.delivery ~= "confirmed" and not order.withdrawn then
            local token = key:match("^outgoing/(%d+%-%d+)$")
            local member = members[order.recipient]
            local elapsed = order.lastAttempt and (now - order.lastAttempt) or math.huge
            if order.delivery == "sent" and (not member or not member.online or elapsed >= 8) then
                order.delivery, changed = "waiting", true
            end
            if token and member and member.online and (elapsed >= 45 or elapsed < 0) then
                ready[#ready + 1] = { order = order, token = token, target = member.target or order.address or order.recipient }
            end
        end
    end
    table.sort(ready, function(a, b)
        local first, second = a.order.lastAttempt or 0, b.order.lastAttempt or 0
        if first ~= second then return first < second end
        return a.token < b.token
    end)
    for index = 1, math.min(3, #ready) do
        local candidate = ready[index]
        local order = candidate.order
        order.lastAttempt, order.delivery = now, "sent"
        if not send(candidate.target, ("O:%s:%d:%d"):format(candidate.token, order.recipe, order.quantity))
            and order.delivery ~= "confirmed" then order.delivery = "waiting" end
        changed = true
    end
    return changed
end

function orders.confirm(token, sender, guild)
    local order = ForeverGuildOrders and ForeverGuildOrders["outgoing/" .. token]
    if not order or order.guild ~= guild or not guild or order.recipient ~= sender then return false end
    order.delivery = "confirmed"
    return true
end

function orders.setDone(key, done, guild)
    local order = ForeverGuildOrders and ForeverGuildOrders[key]
    if not order or order.outgoing or not orders.belongsToGuild(order, guild) then return end
    order.done = done
    if not done then order.reopenedAt = time() end
    if guild and key:match("/direct/%d+%-%d+$") then
        order.statusGuild = guild
        order.statusVersion = (order.statusVersion or 0) + 1
        order.statusAttempt = nil
    end
end

-- Legacy sent order: stop delivering it. Once confirmed the old protocol cannot recall it.
function orders.withdraw(key)
    local order = ForeverGuildOrders and ForeverGuildOrders[key]
    if not order or not order.outgoing or order.delivery == "confirmed" then return false end
    order.withdrawn = true
    return true
end

-- Local removal of a legacy order; the tombstone lives in Market.lua.
function orders.removeLocal(key)
    if ForeverGuildOrders then ForeverGuildOrders[key] = nil end
end

function orders.hasStatusPending(guild)
    if not guild then return false end
    for _, order in pairs(ForeverGuildOrders or {}) do
        if order.statusGuild == guild and order.statusVersion ~= order.statusAck then return true end
    end
    return false
end

function orders.sendStatuses(guild, members, send, now)
    local count = 0
    for key, order in pairs(ForeverGuildOrders or {}) do
        if order.statusGuild == guild and order.statusVersion ~= order.statusAck
            and (not order.statusAttempt or now - order.statusAttempt >= 45) then
            local token = key:match("/direct/(%d+%-%d+)$")
            local member = members[order.sender]
            if token and member and member.online then
                order.statusAttempt = now
                send(member.target or order.address or order.sender,
                    ("C:%s:%d:%d"):format(token, order.statusVersion, order.done and 1 or 0))
                count = count + 1
                if count == 3 then return end
            end
        end
    end
end

function orders.receiveStatus(token, sender, revision, done, guild)
    local order = ForeverGuildOrders and ForeverGuildOrders["outgoing/" .. token]
    if not order or order.guild ~= guild or not guild or order.recipient ~= sender then return end
    if revision <= (order.completionVersion or 0) then return order, false end
    order.delivery = "confirmed"
    order.completionVersion = revision
    order.completed = done
    order.unread = done
    order.unreadAt = done and time() or nil
    return order, done
end

function orders.ackStatus(token, sender, revision, guild)
    local order = ForeverGuildOrders and ForeverGuildOrders[sender .. "/direct/" .. token]
    if order and orders.belongsToGuild(order, guild) and order.statusVersion == revision then order.statusAck = revision end
end

local function clientMaterials(recipe)
    local trade = C_TradeSkillUI
    if not trade or not trade.GetRecipeSchematic then return end
    local ok, data = pcall(trade.GetRecipeSchematic, recipe, false)
    if not ok or not data or type(data.reagentSlotSchematics) ~= "table" then return end
    local result = {}
    for _, slot in ipairs(data.reagentSlotSchematics) do
        local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 0
        if (slot.reagentType == nil or slot.reagentType == basic) and (slot.quantityRequired or 0) > 0 then
            local items = {}
            for _, item in ipairs(slot.reagents or {}) do
                if item.itemID and item.itemID > 0 then items[#items + 1] = item.itemID end
            end
            if #items == 0 then return end
            result[#result + 1] = { items = items, count = slot.quantityRequired }
        end
    end
    return result
end

function orders.materials(recipe)
    local live = clientMaterials(recipe)
    if live and #live > 0 then return live end
    local record = addon.recipeCatalog and addon.recipeCatalog[recipe]
    if not record or not record.reagents then return live end
    local items, slots = {}, {}
    for item in pairs(record.reagents) do items[#items + 1] = item end
    table.sort(items)
    for _, item in ipairs(items) do
        slots[#slots + 1] = { items = { item }, count = record.reagents[item] }
    end
    return slots
end

local relayLifetime = 14 * 86400
local relayLimit = 256

local function relayKey(origin, token)
    return origin .. "/" .. token
end

local function relayStore(guild)
    ForeverGuildOrderRelays = ForeverGuildOrderRelays or {}
    local store = ForeverGuildOrderRelays[guild]
    if not store then
        store = { pending = {}, delivered = {} }
        ForeverGuildOrderRelays[guild] = store
    end
    return store
end

local function validToken(token, now)
    local created = token and #token <= 24 and tonumber(token:match("^(%d+)%-%d+$"))
    return created and created <= now + 300 and now - created <= relayLifetime
end

local function shrink(records, now, limit)
    local count, oldestKey, oldest = 0, nil, math.huge
    for key, record in pairs(records) do
        if now - record.seen > relayLifetime then
            records[key] = nil
        else
            count = count + 1
            if record.seen < oldest then oldestKey, oldest = key, record.seen end
        end
    end
    if count >= limit and oldestKey then records[oldestKey] = nil end
end

function orders.parseRelay(message, now)
    if type(message) ~= "string" or #message > 220 then return end
    local kind, token, recipe, quantity, name = message:match("^([QR]):(%d+%-%d+):(%d+):(%d+):([^:%c]+)$")
    recipe, quantity = tonumber(recipe), tonumber(quantity)
    if not kind or not validToken(token, now) or not validRecipe(recipe) or not validQuantity(quantity) then return end
    return kind, token, recipe, quantity, name
end

function orders.cacheRelay(guild, origin, recipient, token, recipe, quantity, now)
    local store = relayStore(guild)
    local key = relayKey(origin, token)
    if store.pending[key] or store.delivered[key] then return false end
    shrink(store.pending, now, relayLimit)
    store.pending[key] = { origin = origin, recipient = recipient, token = token, recipe = recipe, quantity = quantity, seen = now }
    return true
end

function orders.ackRelay(guild, origin, token, recipient, now, isOwn)
    if not validToken(token, now) then return false end
    local store = relayStore(guild)
    local key = relayKey(origin, token)
    local pending = store.pending[key]
    if pending and pending.recipient ~= recipient then return false end
    local confirmed = isOwn and orders.confirm(token, recipient, guild)
    if not pending and not confirmed then return false end
    store.pending[key] = nil
    if not store.delivered[key] then
        shrink(store.delivered, now, relayLimit * 2)
        store.delivered[key] = { seen = now, recipient = recipient }
    end
    return true
end

function orders.relayReceipt(guild, origin, token, recipient, now)
    local store = ForeverGuildOrderRelays and ForeverGuildOrderRelays[guild]
    local record = store and store.delivered[relayKey(origin, token)]
    if not record or record.recipient ~= recipient or now - (record.replayed or 0) < 90 then return false end
    record.replayed = now
    return true
end

function orders.hasRelay(guild)
    local store = ForeverGuildOrderRelays and ForeverGuildOrderRelays[guild]
    return store and next(store.pending) ~= nil
end

local nextShareAt = 0
function orders.sharePending(guild, members, send, now)
    if now < nextShareAt then return end
    local batch = {}
    for key, order in pairs(ForeverGuildOrders or {}) do
        local token = key:match("^outgoing/(%d+%-%d+)$")
        if order.guild == guild and order.outgoing and order.delivery ~= "confirmed" and not order.withdrawn
            and members[order.recipient] and not members[order.recipient].online and validToken(token, now) and now - (order.lastShared or 0) >= 120 then
            batch[#batch + 1] = { order = order, token = token }
        end
    end
    table.sort(batch, function(a, b)
        return (a.order.lastShared or 0) < (b.order.lastShared or 0)
    end)
    if #batch > 0 then nextShareAt = now + 8 end
    for i = 1, math.min(#batch, 2) do
        local entry = batch[i]
        local order = entry.order
        if send(("Q:%s:%d:%d:%s"):format(entry.token, order.recipe, order.quantity, order.recipient)) then
            order.lastShared = now
        end
    end
end

function orders.deliverRelays(guild, members, send, now)
    local store = ForeverGuildOrderRelays and ForeverGuildOrderRelays[guild]
    if not store then return end
    local ready = {}
    for key, relay in pairs(store.pending) do
        if not validToken(relay.token, now) then
            store.pending[key] = nil
        else
            local member = members[relay.recipient]
            if member and member.online and members[relay.origin] and now - (relay.lastAttempt or 0) >= 75 then
                ready[#ready + 1] = relay
            end
        end
    end
    table.sort(ready, function(a, b)
        return (a.lastAttempt or 0) < (b.lastAttempt or 0)
    end)
    for i = 1, math.min(#ready, 2) do
        local relay = ready[i]
        local member = members[relay.recipient]
        relay.lastAttempt = now
        send(member.target or relay.recipient, ("R:%s:%d:%d:%s"):format(
            relay.token, relay.recipe, relay.quantity, relay.origin))
    end
end
