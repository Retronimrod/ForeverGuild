local _, addon = ...
local bank = {}
addon.guildBank = bank

function bank.available()
    return GetCurrentGuildBankTab and GetGuildBankTabInfo and GetGuildBankItemInfo and GetGuildBankItemLink
end

local function scope(guild)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return guild and faction and (faction .. ":" .. guild)
end

function bank.snapshot(guild)
    local key = scope(guild)
    return key and ForeverGuildBankCache and ForeverGuildBankCache[key]
end

function bank.balance(guild)
    local key = scope(guild)
    return key and ForeverGuildBankGold and ForeverGuildBankGold[key]
end

function bank.formatBalance(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local remainder = copper % 100
    return ("%d |TInterface\\MoneyFrame\\UI-GoldIcon:14:14|t   %d |TInterface\\MoneyFrame\\UI-SilverIcon:14:14|t   %d |TInterface\\MoneyFrame\\UI-CopperIcon:14:14|t"):format(gold, silver, remainder)
end

function bank.captureBalance(guild)
    local key = scope(guild)
    local copper = GetGuildBankMoney and GetGuildBankMoney()
    if not key or type(copper) ~= "number" or copper < 0 then return false end
    ForeverGuildBankGold = ForeverGuildBankGold or {}
    local previous = bank.balance(guild)
    if previous and not previous.sender and previous.copper == copper then return false end
    ForeverGuildBankGold[key] = { copper = copper, at = GetServerTime and GetServerTime() or time() }
    return true
end

function bank.capture(guild, index, populatedOnly)
    local key = scope(guild)
    if not key or not bank.available() then return end
    local tabs = bank.snapshot(guild)
    local changed = false
    local count = GetNumGuildBankTabs and GetNumGuildBankTabs()
    if tabs and count and count > 0 then
        for other in pairs(tabs) do
            local _, _, allowed = GetGuildBankTabInfo(other)
            if other > count or ((allowed == false or allowed == 0) and not tabs[other].sender) then
                tabs[other] = other <= count and tabs[other].remote or nil
                changed = true
            end
        end
    end
    index = index or GetCurrentGuildBankTab()
    if not index or index < 1 then return changed end
    local name, icon, canView = GetGuildBankTabInfo(index)
    if not name or (canView ~= true and canView ~= 1) then return changed end
    local items = {}
    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB or 98 do
        local texture, quantity = GetGuildBankItemInfo(index, slot)
        local link = GetGuildBankItemLink(index, slot)
        if link then
            items[#items + 1] = { icon = texture, link = link, quantity = math.max(1, quantity or 1) }
        elseif texture or (quantity and quantity > 0) then
            -- An incomplete response should not replace an existing snapshot.
            return changed
        end
    end
    if populatedOnly and #items == 0 then return changed end
    ForeverGuildBankCache = ForeverGuildBankCache or {}
    tabs = tabs or {}
    ForeverGuildBankCache[key] = tabs
    local previous = tabs[index]
    tabs[index] = { name = name, icon = icon, items = items, at = GetServerTime and GetServerTime() or time(), share = true, remote = previous and (previous.sender and previous or previous.remote) }
    return true, index
end

local incoming = {}
local published = {}
local pending = {}

local function clock()
    return GetServerTime and GetServerTime() or time()
end

function bank.reset()
    incoming, published, pending = {}, {}, {}
end

function bank.beginScan()
    published = {}
end

function bank.queryNext(first)
    if not bank.available() or not QueryGuildBankTab or not GetNumGuildBankTabs then return end
    for index = first, math.min(GetNumGuildBankTabs() or 0, 8) do
        local _, _, allowed = GetGuildBankTabInfo(index)
        if allowed == true or allowed == 1 then
            local selected = GetCurrentGuildBankTab() == index
            if not selected and SetCurrentGuildBankTab then
                local ok, result = pcall(SetCurrentGuildBankTab, index)
                selected = ok and result ~= false and GetCurrentGuildBankTab() == index
            end
            if selected then
                local ok, result = pcall(QueryGuildBankTab, index)
                if ok and result ~= false then return index end
            end
        end
    end
end

function bank.queueShare(index)
    if index then pending[index] = true end
end

function bank.shareBalance(guild, send)
    local balance = bank.balance(guild)
    if balance and not balance.sender then
        send({("B:G:%d:%d"):format(balance.at, balance.copper)})
    end
end

function bank.share(guild, send, repeatAll)
    if repeatAll then bank.shareBalance(guild, send) end
    local tabs = bank.snapshot(guild) or {}
    for index, tab in pairs(tabs) do
        if tab.share and (repeatAll or pending[index]) then
            local entries = {}
            for _, item in ipairs(tab.items) do
                local id = item.id or (item.link and tonumber(item.link:match("|Hitem:(%d+)")))
                if id then entries[#entries + 1] = id .. ":" .. item.quantity end
            end
            local encodedName = tab.name:sub(1, 60):gsub(".", function(c) return ("%02x"):format(c:byte()) end)
            local parts = {encodedName}
            local current = ""
            for _, entry in ipairs(entries) do
                if #current + #entry + 1 > 180 then parts[#parts + 1], current = current, "" end
                current = current .. (current == "" and "" or ",") .. entry
            end
            if current ~= "" then parts[#parts + 1] = current end
            local payload = table.concat(parts, ";")
            if repeatAll or published[index] ~= payload then
                local stamp = clock()
                local messages = {}
                for i, part in ipairs(parts) do
                    messages[i] = ("B:%d:%d:%d:%d:%d:%s"):format(index, stamp, tab.at, i, #parts, part)
                end
                if send(messages) then published[index], pending[index] = payload, nil end
            else
                pending[index] = nil
            end
        end
    end
end

function bank.receive(guild, sender, message)
    local key = scope(guild)
    if not key then return end
    local at, copper = message:match("^B:G:(%d+):(%d+)$")
    if at then
        at, copper = tonumber(at), tonumber(copper)
        if at < 1 or at > clock() + 120 or copper > 1e14 then return end
        local previous = bank.balance(guild)
        if previous and previous.at >= at then return end
        ForeverGuildBankGold = ForeverGuildBankGold or {}
        ForeverGuildBankGold[key] = { at = at, copper = copper, sender = sender }
        return true
    end
    local index, stamp, captured, part, total, data = message:match("^B:(%d+):(%d+):(%d+):(%d+):(%d+):(.+)$")
    captured = tonumber(captured)
    index, stamp, part, total = tonumber(index), tonumber(stamp), tonumber(part), tonumber(total)
    local now = clock()
    if not index or index < 1 or index > 8 or math.abs(stamp - now) > 120
        or captured < 1 or captured > now + 120 or total < 1 or total > 12 or part < 1 or part > total or #data > 180 then return end
    local id = sender .. ":" .. index
    local batch = incoming[id]
    if not batch or batch.stamp ~= stamp or batch.captured ~= captured or batch.total ~= total then
        batch = { stamp = stamp, captured = captured, total = total, parts = {} }
        incoming[id] = batch
    end
    batch.parts[part] = data
    for i = 1, total do if not batch.parts[i] then return end end
    incoming[id] = nil
    local name = batch.parts[1]
    if #name > 120 or #name % 2 ~= 0 or name:find("[^0-9a-f]") then return end
    name = name:gsub("..", function(hex) return string.char(tonumber(hex, 16)) end)
    if name:find("[%c|]") then return end
    local items = {}
    for i = 2, total do
        for entry in batch.parts[i]:gmatch("[^,]+") do
            local itemID, quantity = entry:match("^(%d+):(%d+)$")
            itemID, quantity = tonumber(itemID), tonumber(quantity)
            if not itemID or itemID < 1 or itemID > 2147483647 or quantity < 1 or quantity > 100000 or #items >= 98 then return end
            items[#items + 1] = { id = itemID, quantity = quantity }
        end
    end
    ForeverGuildBankCache = ForeverGuildBankCache or {}
    local tabs = ForeverGuildBankCache[key] or {}
    ForeverGuildBankCache[key] = tabs
    local previous = tabs[index]
    local current = previous and (previous.remote or previous)
    if current and current.at >= captured then return end
    local snapshot = { name = name, items = items, at = captured, sender = sender }
    if previous and not previous.sender then
        previous.remote = snapshot
    else
        tabs[index] = snapshot
    end
    return true
end
