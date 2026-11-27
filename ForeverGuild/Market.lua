local _, addon = ...
-- Crafting marketplace: shared order model, lifecycle rules, payment bookkeeping,
-- history and notification bookkeeping. Pure logic without frames; Board.lua carries
-- the records over the existing guild order channel.
local market = {}
addon.market = market

-- First version that understands the extended order packets (B:N/B:A/B:J).
market.protocol = "0.9.62"
local MAX_MONEY = 9999999999
local DAY = 86400

-- Money -----------------------------------------------------------------------------
-- All amounts are whole copper values; silver and copper above 99 are normalized.
function market.copper(gold, silver, copper)
    gold, silver, copper = tonumber(gold) or 0, tonumber(silver) or 0, tonumber(copper) or 0
    if gold < 0 or silver < 0 or copper < 0 then return nil end
    local total = math.floor(gold) * 10000 + math.floor(silver) * 100 + math.floor(copper)
    if total > MAX_MONEY then return nil end
    return total
end

function market.split(total)
    total = math.max(0, math.floor(tonumber(total) or 0))
    return math.floor(total / 10000), math.floor(total / 100) % 100, total % 100
end

local coins = {
    "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t",
    "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t",
    "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
}
market.coins = coins

function market.money(total)
    local values, parts = { market.split(total) }, {}
    for index = 1, 3 do
        if values[index] > 0 then parts[#parts + 1] = ("%.0f%s"):format(values[index], coins[index]) end
    end
    if #parts == 0 then parts[1] = "0" .. coins[3] end
    return table.concat(parts, " ")
end

function market.validMoney(value)
    return type(value) == "number" and value >= 0 and value <= MAX_MONEY and value % 1 == 0
end

-- States ------------------------------------------------------------------------------
-- Stable IDs: O open (board), Q requested (direct), M waiting for materials, W in progress,
-- R ready for handoff, H handoff running, D completed, X cancelled/withdrawn, J declined.
-- E (expired) is derived from the posting deadline and never stored.
market.states = { O = true, Q = true, M = true, W = true, R = true, H = true, D = true, X = true, J = true }
market.accepted = { M = true, W = true, R = true, H = true }
market.closed = { D = true, X = true, J = true, E = true }
market.methods = { "trade", "mail", "cod", "custom" }

function market.state(order, now)
    if (order.state == "O" or order.state == "Q") and order.expiresAt and now >= order.expiresAt then return "E" end
    return order.state
end

function market.overdue(order, now)
    return market.accepted[order.state] == true and (order.due or 0) > 0 and now > order.due
end

function market.tipTotal(order)
    local tip = order.tip or 0
    if order.tipEach then return tip * (order.quantity or 1) end
    return tip
end

function market.total(order)
    return market.tipTotal(order) + (order.cost or 0)
end

function market.settled(order)
    local total = market.total(order)
    return total <= 0 or order.waived == true or (order.paidGot or 0) >= total
end

-- Payment status shown to both sides. No gold is ever held by the addon.
function market.payment(order)
    local total = market.total(order)
    if total <= 0 then return "none" end
    if order.waived then return "waived" end
    local got, sent = order.paidGot or 0, order.paidSent or 0
    if got >= total then return "paid" end
    if sent > got then return "unclear" end
    if got > 0 then return "partial" end
    if (order.delivered or 0) > 0 or order.state == "R" or order.state == "H" then return "pending" end
    return "agreed"
end

function market.needsMaterials(order)
    if order.provided then
        for _, count in pairs(order.provided) do
            if count > 0 then return true end
        end
        return false
    end
    return order.supplies == true
end

-- "all", "some" or "none" provided by the requester; nil when unknown (legacy orders).
function market.supplyLevel(order, slots)
    if not order.provided then
        if order.ext then return "none" end
        if order.supplies == nil then return nil end
        return order.supplies and "all" or "none"
    end
    local any, all = false, true
    for _, slot in ipairs(slots or {}) do
        local id = slot.items and slot.items[1]
        local provided = id and order.provided[id] or 0
        if provided > 0 then any = true end
        if provided < slot.count * (order.quantity or 1) then all = false end
    end
    if not slots or #slots == 0 then
        for _, count in pairs(order.provided) do if count > 0 then return "some" end end
        return "none"
    end
    if all and any then return "all" end
    return any and "some" or "none"
end

-- Lifecycle ----------------------------------------------------------------------------
local function start(order, now)
    order.state = market.needsMaterials(order) and "M" or "W"
    order.acceptedAt = now
    order.due = (order.dueDays or 0) > 0 and now + order.dueDays * DAY or 0
end

local function finish(order, now)
    if (order.delivered or 0) >= order.quantity and market.settled(order) then
        order.state, order.closedAt = "D", now
        order.cancelBy, order.proposal = nil, nil
    end
end

local proposalFields = { q = true, t = true, m = true, d = true }

local function validProposal(order, field, value)
    if field == "q" then return value >= 1 and value <= 200 and value >= (order.delivered or 0) end
    if field == "t" then return market.validMoney(value) end
    if field == "m" then return value >= 1 and value <= #market.methods end
    if field == "d" then return value >= 0 and value <= 30 end
end

local function applyField(order, field, value, now)
    if field == "q" then
        order.quantity = value
        if (order.crafted or 0) > value then order.crafted = value end
    elseif field == "t" then
        order.tip = value
    elseif field == "m" then
        order.method = value
    elseif field == "d" then
        order.dueDays = value
        order.due = value > 0 and now + value * DAY or 0
    end
end

-- Owner-side transition for extended orders. `actor` is the roster key of the
-- character that requested the change; only the requester's client calls this.
function market.apply(order, actor, action, arg, text, now)
    local state = market.state(order, now)
    local owner = actor == order.owner
    local crafter = order.crafter ~= nil and actor == order.crafter
    local active = market.accepted[state] == true
    local value = tonumber(arg) or 0
    if value < 0 or value % 1 ~= 0 then return false end
    if action == "take" then
        if owner or order.direct or state ~= "O" then return false end
        order.crafter = actor
        start(order, now)
    elseif action == "accept" then
        if not crafter or state ~= "Q" then return false end
        start(order, now)
    elseif action == "decline" then
        if not crafter or state ~= "Q" then return false end
        order.state, order.closedAt, order.reply = "J", now, text
    elseif action == "release" then
        if not crafter or not active or (order.crafted or 0) > 0 or (order.matState or 0) > 0
            or (order.shipped or 0) > 0 or (order.delivered or 0) > 0 then return false end
        if order.direct then
            order.state, order.closedAt, order.reply = "J", now, text
        else
            order.crafter, order.state, order.due = nil, "O", 0
        end
        order.cancelBy, order.proposal, order.costOffer, order.missing = nil, nil, 0, nil
    elseif action == "mats" then
        if not crafter or not active or value < 1 or value > 2 then return false end
        order.matState = math.max(order.matState or 0, value)
        if value == 2 then
            order.missing = nil
            if order.state == "M" then order.state = "W" end
        end
    elseif action == "missing" then
        if not crafter or (state ~= "M" and state ~= "W") then return false end
        order.missing, order.state = true, "M"
    elseif action == "start" then
        if not crafter or state ~= "M" then return false end
        order.state = "W"
    elseif action == "progress" then
        if not crafter or not active or value > order.quantity or value < (order.delivered or 0) then return false end
        order.crafted = value
        if order.state == "M" then order.state = "W" end
    elseif action == "ready" then
        if not crafter or (state ~= "M" and state ~= "W" and state ~= "H") then return false end
        if (order.crafted or 0) <= (order.delivered or 0) then order.crafted = order.quantity end
        order.state, order.missing = "R", nil
    elseif action == "ship" then
        if not crafter or (state ~= "R" and state ~= "H") or value < 1 or value > (order.crafted or 0)
            or value < (order.delivered or 0) then return false end
        order.shipped, order.state = value, "H"
        order.shippedAt = now
    elseif action == "received" then
        if not owner or (state ~= "R" and state ~= "H") then return false end
        if value == 0 then value = math.max(order.crafted or 0, order.quantity) end
        if value > order.quantity or value < (order.delivered or 0) then return false end
        order.delivered = value
        order.crafted = math.max(order.crafted or 0, value)
        order.shipped = math.max(order.shipped or 0, value)
        order.state = "H"
        finish(order, now)
    elseif action == "paid" then
        if not owner or not active or not market.validMoney(value) or market.total(order) <= 0 then return false end
        order.paidSent = value
    elseif action == "gotpaid" then
        if not crafter or not active or not market.validMoney(value) or market.total(order) <= 0 then return false end
        order.paidGot = value
        order.paidSent = math.max(order.paidSent or 0, value)
        finish(order, now)
    elseif action == "waive" then
        if not crafter or not active or market.total(order) <= 0 then return false end
        order.waived = true
        finish(order, now)
    elseif action == "cost" then
        if not crafter or (state ~= "Q" and not active) or value < 1 or not market.validMoney(value) then return false end
        order.costOffer = value
    elseif action == "costok" or action == "costno" then
        if not owner or (order.costOffer or 0) <= 0 then return false end
        if action == "costok" then order.cost = order.costOffer end
        order.costOffer = 0
    elseif action == "propose" then
        local field = text
        if not active or not (owner or crafter) or not proposalFields[field] or not validProposal(order, field, value) then return false end
        -- Changes that only help the crafter take effect immediately.
        local generous = owner and ((field == "t" and value >= (order.tip or 0))
            or (field == "d" and value > 0 and now + value * DAY >= (order.due or 0) and (order.due or 0) > 0))
        if generous then
            applyField(order, field, value, now)
        else
            order.proposal = { f = field, v = value, by = owner and "o" or "c" }
        end
    elseif action == "agree" or action == "reject" then
        local proposal = order.proposal
        if not proposal or not active then return false end
        if not ((proposal.by == "o" and crafter) or (proposal.by == "c" and owner)) then return false end
        if action == "agree" then
            if not validProposal(order, proposal.f, proposal.v) then return false end
            applyField(order, proposal.f, proposal.v, now)
        end
        order.proposal = nil
        order.lastAnswer = action
    elseif action == "cancel" then
        if not owner or (state ~= "O" and state ~= "Q" and state ~= "E") then return false end
        order.state, order.closedAt = "X", now
    elseif action == "cancelreq" then
        if not active or not (owner or crafter) or order.cancelBy then return false end
        order.cancelBy = owner and "o" or "c"
    elseif action == "cancelok" or action == "cancelno" then
        local by = order.cancelBy
        if not active or not by or not ((by == "o" and crafter) or (by == "c" and owner)) then return false end
        order.cancelBy = nil
        if action == "cancelok" then
            order.state, order.closedAt, order.proposal = "X", now, nil
        else
            order.dispute = true
        end
    elseif action == "resolve" then
        if not order.dispute or not (owner or crafter) then return false end
        order.dispute = nil
    elseif action == "extend" then
        if not owner or value < 1 or value > 30 then return false end
        if state == "O" or state == "Q" or state == "E" then
            order.expiresAt = math.max(now, state == "E" and now or (order.expiresAt or now)) + value * DAY
        elseif active then
            order.due = math.max(order.due or 0, now) + value * DAY
        else
            return false
        end
    elseif action == "repost" or action == "assign" then
        if not owner or (state ~= "J" and state ~= "E" and state ~= "Q") or value < 1 or value > 30 then return false end
        if action == "assign" then
            if type(text) ~= "string" or text == "" or text == order.owner or #text > 60 then return false end
            order.direct, order.crafter, order.state = true, text, "Q"
        else
            order.direct, order.crafter, order.state = false, nil, "O"
        end
        order.expiresAt, order.closedAt, order.reply, order.costOffer = now + value * DAY, nil, nil, 0
    else
        return false
    end
    return true
end

-- Pre-acceptance edit by the requester. Returns false when the order may no longer change.
function market.edit(order, fields, now)
    local state = market.state(order, now)
    if state ~= "O" and state ~= "Q" and state ~= "E" then return false end
    for _, key in ipairs({ "quantity", "tip", "tipEach", "pay", "cost", "method", "dueDays", "provided", "supplies", "note" }) do
        if fields[key] ~= nil then order[key] = fields[key] end
    end
    if fields.days then order.expiresAt = now + fields.days * DAY end
    return true
end

-- History and events ---------------------------------------------------------------------
local tracked = { "state", "crafter", "crafted", "shipped", "delivered", "matState", "missing", "costOffer", "cost",
    "paidSent", "paidGot", "waived", "cancelBy", "dispute", "tip", "quantity", "due", "expiresAt", "method" }

function market.capture(order)
    if not order then return nil end
    local copy = {}
    for _, key in ipairs(tracked) do copy[key] = order[key] end
    local proposal = order.proposal
    copy.proposal = proposal and (proposal.f .. proposal.v .. proposal.by) or nil
    return copy
end

-- Returns the events between two captures; `by` is "o" (requester), "c" (crafter) or nil.
function market.diff(before, order)
    local events = {}
    local function add(code, by, value) events[#events + 1] = { code = code, by = by, n = value } end
    if not before then
        add(order.direct and "direct" or "posted", "o")
        return events
    end
    local from, to = before.state, order.state
    if from ~= to then
        if (from == "O" or from == "Q") and market.accepted[to] then add("accepted", "c")
        elseif to == "J" then add("declined", "c")
        elseif to == "O" and market.accepted[from] then add("released", "c")
        elseif to == "O" then add("reposted", "o")
        elseif to == "Q" then add("assigned", "o")
        elseif to == "W" and from == "M" and (order.matState or 0) < 2 then add("started", "c")
        elseif to == "R" then add("ready", "c")
        elseif to == "M" and order.missing then add("missing", "c")
        elseif to == "D" then add("done")
        elseif to == "X" then add(market.accepted[from] and "cancelled" or "withdrawn", market.accepted[from] and nil or "o")
        end
    end
    local function grew(key) return (order[key] or 0) > (before[key] or 0) end
    if grew("crafted") then add((order.crafted or 0) >= order.quantity and "craftedAll" or "progress", "c", order.crafted) end
    if grew("shipped") then add("shipped", "c", order.shipped) end
    if grew("delivered") then add("received", "o", order.delivered) end
    if grew("matState") then add("materials", "c", order.matState) end
    if order.missing and not before.missing and to == from then add("missing", "c") end
    if (order.costOffer or 0) > 0 and order.costOffer ~= before.costOffer then add("costOffer", "c", order.costOffer) end
    if (order.cost or 0) ~= (before.cost or 0) then add("costAgreed", "o", order.cost)
    elseif (before.costOffer or 0) > 0 and (order.costOffer or 0) == 0 then add("costRejected", "o") end
    if grew("paidSent") then add("paid", "o", order.paidSent) end
    if grew("paidGot") then add("paymentReceived", "c", order.paidGot) end
    if order.waived and not before.waived then add("waived", "c") end
    local proposal = order.proposal and (order.proposal.f .. order.proposal.v .. order.proposal.by)
    if proposal and proposal ~= before.proposal then add("proposal", order.proposal.by, order.proposal.v) end
    if before.proposal and not proposal then
        local proposer = before.proposal:sub(-1)
        local changed = order.quantity ~= before.quantity or order.tip ~= before.tip or order.method ~= before.method or order.due ~= before.due
        add(changed and "agreed" or "rejected", proposer == "o" and "c" or "o")
    elseif not proposal and (order.tip ~= before.tip or order.quantity ~= before.quantity or order.method ~= before.method) then
        add("changed", "o")
    end
    if (order.due or 0) > (before.due or 0) and (before.due or 0) > 0 and not before.proposal then add("extended", "o") end
    if (order.expiresAt or 0) > (before.expiresAt or 0) and (from == to) and (before.expiresAt or 0) > 0 then add("extended", "o") end
    if order.cancelBy and order.cancelBy ~= before.cancelBy then add("cancelRequest", order.cancelBy) end
    if before.cancelBy and not order.cancelBy and to ~= "X" then add("cancelRejected", before.cancelBy == "o" and "c" or "o") end
    if order.dispute and not before.dispute and not events[1] then add("dispute") end
    if before.dispute and not order.dispute then add("resolved") end
    return events
end

function market.log(order, events, now, names)
    if #events == 0 then return end
    order.log = order.log or {}
    for _, event in ipairs(events) do
        local who = event.by == "o" and order.owner or (event.by == "c" and (order.crafter or (names and names.crafter))) or nil
        order.log[#order.log + 1] = { at = now, code = event.code, by = who, n = event.n }
    end
    while #order.log > 60 do table.remove(order.log, 1) end
end

-- Recipient of an event: the other party than its originator, or both.
function market.recipient(event, role)
    if not role then return false end
    if event.by == nil then return true end
    return (event.by == "o" and role == "c") or (event.by == "c" and role == "o")
end

-- Notification type for settings; events without a type only go into the history.
market.notifyTypes = {
    direct = "direct", assigned = "direct", posted = "match", accepted = "accepted", declined = "declined",
    released = "declined", proposal = "proposal", agreed = "proposal", rejected = "proposal",
    costOffer = "costOffer", costAgreed = "costOffer", costRejected = "costOffer", missing = "missing",
    materials = "materials", craftedAll = "crafted", progress = "progress", ready = "ready", shipped = "shipped",
    received = "received", paid = "paid", paymentReceived = "paid", waived = "paid", done = "done",
    cancelRequest = "cancelRequest", cancelRejected = "cancelRequest", cancelled = "cancelled", withdrawn = "cancelled",
    expiring = "expiring", overdue = "overdue", lost = "accepted", handover = "handover",
}
market.typeOrder = { "direct", "match", "accepted", "declined", "proposal", "costOffer", "missing", "materials",
    "progress", "crafted", "ready", "shipped", "received", "paid", "done", "expiring", "overdue", "cancelRequest",
    "cancelled", "handover" }

-- Settings ----------------------------------------------------------------------------------
market.defaults = {
    days = 7, method = 1, boardView = "open", onlyCraftable = false, sound = true, popup = true, chat = true,
    combat = false, remindHandover = true, remindOverdue = true, counters = true, keepDays = 30,
}
market.typeDefaults = { match = false, progress = false }

function market.setting(key)
    local saved = ForeverGuildSettings and ForeverGuildSettings.market
    local value = saved and saved[key]
    if value == nil then return market.defaults[key] end
    return value
end

function market.set(key, value)
    ForeverGuildSettings = ForeverGuildSettings or {}
    ForeverGuildSettings.market = ForeverGuildSettings.market or {}
    ForeverGuildSettings.market[key] = value
end

function market.typeEnabled(kind)
    local saved = ForeverGuildSettings and ForeverGuildSettings.market and ForeverGuildSettings.market.types
    local value = saved and saved[kind]
    if value == nil then return market.typeDefaults[kind] ~= false end
    return value
end

function market.setType(kind, value)
    market.set("types", (ForeverGuildSettings.market and ForeverGuildSettings.market.types) or {})
    ForeverGuildSettings.market.types[kind] = value
end

-- Notification store --------------------------------------------------------------------------
local function store()
    ForeverGuildMarket = type(ForeverGuildMarket) == "table" and ForeverGuildMarket or {}
    ForeverGuildMarket.notes = ForeverGuildMarket.notes or {}
    ForeverGuildMarket.seen = ForeverGuildMarket.seen or {}
    ForeverGuildMarket.versions = ForeverGuildMarket.versions or {}
    return ForeverGuildMarket
end

function market.notes(guild)
    local data = store()
    if not guild then return {} end
    data.notes[guild] = data.notes[guild] or {}
    return data.notes[guild]
end

-- Adds a notification once per event ID; duplicate sync messages are ignored.
function market.notify(guild, id, entry, now)
    local data = store()
    if not guild or data.seen[id] then return false end
    data.seen[id] = now
    entry.id, entry.at, entry.read = id, now, false
    local list = market.notes(guild)
    table.insert(list, 1, entry)
    while #list > 120 do table.remove(list) end
    return true
end

function market.unread(guild)
    local count = 0
    for _, entry in ipairs(market.notes(guild)) do
        if not entry.read then count = count + 1 end
    end
    return count
end

function market.markRead(guild, key)
    local changed = false
    for _, entry in ipairs(market.notes(guild)) do
        if not entry.read and (key == nil or entry.key == key) then entry.read, changed = true, true end
    end
    return changed
end

function market.pruneSeen(now)
    local data = store()
    for id, at in pairs(data.seen) do
        if now - at > 90 * DAY then data.seen[id] = nil end
    end
end

-- Local archive and tombstones. Both only affect this character's view: archived orders
-- move to the history, removed orders are deleted locally and a tombstone keeps later
-- or duplicated sync messages from bringing them back. Nothing is sent to the guild.
local TOMBSTONE_DAYS = 180
local function localView(guild)
    local data = store()
    data.view = data.view or {}
    data.view[guild] = data.view[guild] or { archived = {}, removed = {} }
    return data.view[guild]
end

function market.isArchived(guild, key)
    return guild ~= nil and localView(guild).archived[key] ~= nil
end

function market.archive(guild, key, now, archived)
    if not guild then return end
    localView(guild).archived[key] = archived ~= false and now or nil
end

function market.isRemoved(guild, key)
    return guild ~= nil and localView(guild).removed[key] ~= nil
end

function market.remove(guild, key, now)
    if not guild then return end
    local view = localView(guild)
    view.removed[key] = now
    view.archived[key] = nil
end

function market.pruneTombstones(guild, now)
    if not guild then return end
    local view = localView(guild)
    for key, at in pairs(view.removed) do
        if now - at > TOMBSTONE_DAYS * DAY then view.removed[key] = nil end
    end
end

-- Version knowledge survives a reload so offline crafters still get extended orders.
function market.noteVersion(guild, name, version)
    if not guild or not name or not version then return end
    local data = store()
    data.versions[guild] = data.versions[guild] or {}
    data.versions[guild][name] = version
end

local function versionNumber(version)
    local a, b, c = tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c)
end

function market.supports(guild, name)
    local data = store()
    local version = data.versions[guild] and data.versions[guild][name]
    local number = versionNumber(version)
    return number ~= nil and number >= versionNumber(market.protocol)
end

-- Reminders: once per order and kind, saved with the order.
function market.reminders(records, player, now, same)
    local due = {}
    for _, order in pairs(records) do
        local state = market.state(order, now)
        local reminded = order.reminded or {}
        if order.owner == player and (state == "O" or state == "Q") and order.expiresAt
            and order.expiresAt - now < DAY and order.expiresAt > now and not reminded.expiring then
            reminded.expiring = true
            due[#due + 1] = { order = order, code = "expiring" }
        end
        if market.overdue(order, now) and (order.owner == player or same(order.crafter)) and not reminded.overdue then
            reminded.overdue = true
            due[#due + 1] = { order = order, code = "overdue" }
        end
        if next(reminded) then order.reminded = reminded end
    end
    return due
end

-- Does the current player have something to do on this order?
function market.needsAction(order, isOwner, isCrafter, now)
    local state = market.state(order, now)
    if order.intent then return false end
    if isCrafter then
        if state == "Q" then return true end
        if order.proposal and order.proposal.by == "o" then return true end
        if order.cancelBy == "o" then return true end
        if state == "M" and market.needsMaterials(order) and (order.matState or 0) < 2 then return false end
        return false
    end
    if isOwner then
        if (order.costOffer or 0) > 0 then return true end
        if order.proposal and order.proposal.by == "c" then return true end
        if order.cancelBy == "c" then return true end
        if state == "R" or (state == "H" and (order.shipped or 0) > (order.delivered or 0)) then return true end
        if state == "J" or state == "E" then return true end
    end
    return false
end
