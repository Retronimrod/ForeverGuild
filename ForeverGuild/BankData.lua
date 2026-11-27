local _, addon = ...
-- Guild bank display data: reads the synchronized vault snapshot (GuildBank.lua) without
-- changing it, combines identical items for the display and sorts items into categories.
local data = {}
addon.bankData = data

-- Display settings (saved in ForeverGuildSettings.guildBank).
data.defaults = { merge = true, qualityBorder = true, slotSize = 38 }

function data.setting(key)
    local saved = ForeverGuildSettings and ForeverGuildSettings.guildBank
    local value = saved and saved[key]
    if value == nil then return data.defaults[key] end
    return value
end

function data.set(key, value)
    ForeverGuildSettings = ForeverGuildSettings or {}
    ForeverGuildSettings.guildBank = ForeverGuildSettings.guildBank or {}
    ForeverGuildSettings.guildBank[key] = value
end

-- Items with the same ID but another enchantment or random suffix are different variants
-- and are never combined.
function data.variantKey(item)
    local id, enchant, suffix = (item.link or ""):match("|Hitem:(%d+):([^:]*):[^:]*:[^:]*:[^:]*:[^:]*:([^:]*)")
    id = tonumber(id) or item.id
    if not id then return nil end
    if (enchant or "") == "" or enchant == "0" then enchant = nil end
    if (suffix or "") == "" or suffix == "0" then suffix = nil end
    return id .. (enchant and (":e" .. enchant) or "") .. (suffix and (":s" .. suffix) or ""), id
end

-- Newest data per tab: own scan or a guild member's snapshot, whichever was captured later.
function data.tabs(guild)
    local snapshot = addon.guildBank.snapshot(guild) or {}
    local result = {}
    for index, tab in pairs(snapshot) do
        local current = tab
        if tab.remote and (not tab.at or tab.remote.at > tab.at) then current = tab.remote end
        if type(current) == "table" and current.items then
            result[#result + 1] = { index = index, name = current.name or tab.name, items = current.items, at = current.at,
                sender = current.sender }
        end
    end
    table.sort(result, function(a, b) return a.index < b.index end)
    return result
end

-- One entry per real stack.
function data.stacks(guild)
    local stacks = {}
    for _, tab in ipairs(data.tabs(guild)) do
        for _, item in ipairs(tab.items) do
            local key, id = data.variantKey(item)
            if key then
                stacks[#stacks + 1] = { key = key, id = id, link = item.link, icon = item.icon, quantity = item.quantity,
                    tabs = { [tab.index] = item.quantity }, at = tab.at }
            end
        end
    end
    return stacks
end

-- Display only: one entry per variant with the total and the amount per bank tab.
function data.merge(stacks)
    local byKey, list = {}, {}
    for _, stack in ipairs(stacks) do
        local entry = byKey[stack.key]
        if not entry then
            entry = { key = stack.key, id = stack.id, link = stack.link, icon = stack.icon, quantity = 0, tabs = {}, at = stack.at }
            byKey[stack.key] = entry
            list[#list + 1] = entry
        end
        entry.quantity = entry.quantity + stack.quantity
        for tab, count in pairs(stack.tabs) do entry.tabs[tab] = (entry.tabs[tab] or 0) + count end
        entry.link, entry.icon = entry.link or stack.link, entry.icon or stack.icon
        if stack.at and (not entry.at or stack.at > entry.at) then entry.at = stack.at end
    end
    return list, byKey
end

-- Item information from the client (cached once loaded).
local infoCache = {}
function data.info(id, link)
    local cached = infoCache[link or id]
    if cached and cached.name then return cached end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, itemLink, quality, _, _, _, _, _, equipLoc, texture = getInfo(link or id)
    -- The Forever client offers these through C_Item (as used elsewhere in ForeverGuild).
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local icon, classID, subclassID
    if instant then _, _, _, _, icon, classID, subclassID = instant(id) end
    cached = { name = name, link = itemLink or link, quality = quality, equipLoc = equipLoc, icon = texture or icon,
        classID = classID, subclassID = subclassID }
    if name then infoCache[link or id] = cached end
    return cached
end

-- Categories (stable IDs, display order) from the client's item class and subclass.
data.categories = {
    { id = "bags", label = "Bags", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    { id = "enchanting", label = "Enchanting materials", icon = "Interface\\Icons\\INV_Enchant_DustStrange" },
    { id = "cloth", label = "Cloth#bank", icon = "Interface\\Icons\\INV_Fabric_Linen_01" },
    { id = "herbs", label = "Herbs", icon = "Interface\\Icons\\INV_Misc_Herb_07" },
    { id = "leather", label = "Leather", icon = "Interface\\Icons\\INV_Misc_LeatherScrap_03" },
    { id = "metal", label = "Ores & metals", icon = "Interface\\Icons\\INV_Ore_Copper_01" },
    { id = "elemental", label = "Elemental materials", icon = "Interface\\Icons\\INV_Elemental_Primal_Fire" },
    { id = "components", label = "Crafting components", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { id = "recipes", label = "Recipes", icon = "Interface\\Icons\\INV_Scroll_03" },
    { id = "consumables", label = "Consumables", icon = "Interface\\Icons\\INV_Potion_54" },
    { id = "weapons", label = "Weapons", icon = "Interface\\Icons\\INV_Sword_04" },
    { id = "armor", label = "Armor#bank", icon = "Interface\\Icons\\INV_Chest_Chain" },
    { id = "misc", label = "Miscellaneous", icon = "Interface\\Icons\\INV_Misc_Gear_02" },
}
data.categoryIndex = {}
for index, category in ipairs(data.categories) do data.categoryIndex[category.id] = index end

local TRADE = { [5] = "cloth", [6] = "leather", [7] = "metal", [9] = "herbs", [10] = "elemental", [12] = "enchanting" }
local CLASSES = { [0] = "consumables", [1] = "bags", [2] = "weapons", [4] = "armor", [9] = "recipes" }

function data.categorize(id, link)
    local info = data.info(id, link)
    local classID, sub = info.classID, info.subclassID
    if classID == 7 then return TRADE[sub] or "components" end
    return classID and CLASSES[classID] or "misc"
end
