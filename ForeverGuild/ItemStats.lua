local _, addon = ...
-- Item attributes, usability and comparison with the equipped gear for the recipe search.
-- Attributes come from the client's structured item stats (C_Item.GetItemStats or
-- GetItemStats); usability from the item tooltip. Results are cached per item, so typing
-- in the search never reads tooltips again. Unknown values stay nil and are never treated
-- as zero.
local L = addon.L
local stats = {}
addon.itemStats = stats

-- Stable attribute IDs. `keys` are the stat keys the client may return; the label uses the
-- client's own localized global string when it exists.
stats.attributes = {
    { id = "str", keys = { "ITEM_MOD_STRENGTH_SHORT" }, fallback = "Strength" },
    { id = "agi", keys = { "ITEM_MOD_AGILITY_SHORT" }, fallback = "Agility" },
    { id = "sta", keys = { "ITEM_MOD_STAMINA_SHORT" }, fallback = "Stamina" },
    { id = "int", keys = { "ITEM_MOD_INTELLECT_SHORT" }, fallback = "Intellect" },
    { id = "spi", keys = { "ITEM_MOD_SPIRIT_SHORT" }, fallback = "Spirit" },
    { id = "armor", keys = { "RESISTANCE0_NAME" }, fallback = "Armor" },
    { id = "ap", keys = { "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_MELEE_ATTACK_POWER_SHORT" }, fallback = "Attack power" },
    { id = "crit", keys = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT", "ITEM_MOD_CRIT_SPELL_RATING_SHORT" },
        fallback = "Critical strike" },
    { id = "hit", keys = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT" },
        fallback = "Hit" },
    { id = "spell", keys = { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_POWER_SHORT" }, fallback = "Spell damage" },
    { id = "heal", keys = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" }, fallback = "Healing" },
    { id = "mp5", keys = { "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT" }, fallback = "Mana regeneration" },
    { id = "def", keys = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" }, fallback = "Defense" },
    { id = "fire", keys = { "RESISTANCE2_NAME" }, fallback = "Fire resistance" },
    { id = "nature", keys = { "RESISTANCE3_NAME" }, fallback = "Nature resistance" },
    { id = "frost", keys = { "RESISTANCE4_NAME" }, fallback = "Frost resistance" },
    { id = "shadow", keys = { "RESISTANCE5_NAME" }, fallback = "Shadow resistance" },
    { id = "arcane", keys = { "RESISTANCE6_NAME" }, fallback = "Arcane resistance" },
    { id = "dps", keys = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" }, fallback = "Damage per second" },
}
stats.byId = {}
for _, attribute in ipairs(stats.attributes) do stats.byId[attribute.id] = attribute end

function stats.label(id)
    local attribute = stats.byId[id]
    if not attribute then return id end
    local value = _G[attribute.keys[1]]
    if type(value) == "string" and value ~= "" and not value:find("%%") then return value end
    return L[attribute.fallback]
end

-- Search synonyms (lowercase, German and English) -> attribute ID.
stats.synonyms = {
    ["stärke"] = "str", str = "str", strength = "str", ["beweglichkeit"] = "agi", bewegl = "agi", agi = "agi", agility = "agi",
    ausdauer = "sta", ausd = "sta", sta = "sta", stamina = "sta", stam = "sta", intelligenz = "int", int = "int",
    intellect = "int", willenskraft = "spi", wille = "spi", spi = "spi", spirit = "spi", ["rüstung"] = "armor",
    armor = "armor", armour = "armor", angriffskraft = "ap", ap = "ap", ["attack power"] = "ap", krit = "crit", crit = "crit",
    ["kritische"] = "crit", treffer = "hit", hit = "hit", zauberschaden = "spell", spelldmg = "spell", spell = "spell",
    heilung = "heal", heal = "heal", healing = "heal", mp5 = "mp5", manaregeneration = "mp5", verteidigung = "def",
    defense = "def", defence = "def", feuer = "fire", fire = "fire", natur = "nature", nature = "nature", frost = "frost",
    schatten = "shadow", shadow = "shadow", arkan = "arcane", arcane = "arcane", dps = "dps",
}

local statCache = {}
local function getStats(link)
    local fn = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
    if not fn then return nil end
    local ok, result = pcall(fn, link)
    if ok and type(result) == "table" then return result end
end

-- Attribute values of an item ID or link: table id -> number (0 when the loaded item has no
-- such attribute), or nil while the item is not loaded or the client offers no stat data.
function stats.of(item)
    if not item then return nil end
    local cacheKey = item
    local cached = statCache[cacheKey]
    if cached then return cached end
    local link = type(item) == "number" and ("item:" .. item) or item
    local getInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    local name = getInfo and getInfo(item)
    if not name then return nil end
    local raw = getStats(link)
    if not raw then return nil end
    local values = {}
    for _, attribute in ipairs(stats.attributes) do
        local total = 0
        for _, key in ipairs(attribute.keys) do total = total + (tonumber(raw[key]) or 0) end
        values[attribute.id] = total
    end
    statCache[cacheKey] = values
    return values
end

function stats.available()
    return ((C_Item and C_Item.GetItemStats) or _G.GetItemStats) ~= nil
end

-- Usability from the tooltip: red lines other than the level requirement mean the class or
-- profession cannot use the item. Returns usable (bool or nil when unknown), required level.
local scanner, levelPattern
local usableCache = {}
local function scan(link)
    if not scanner then
        scanner = CreateFrame("GameTooltip", "ForeverGuildScanTooltip", nil, "GameTooltipTemplate")
        local format = _G.ITEM_MIN_LEVEL
        if type(format) == "string" then
            local escaped = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
            levelPattern = "^" .. escaped:gsub("%%d", "(%%d+)") .. "$"
        end
    end
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:ClearLines()
    local ok = pcall(scanner.SetHyperlink, scanner, link)
    if not ok or scanner:NumLines() == 0 then return nil end
    local usable, level = true, nil
    for index = 2, scanner:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local line = _G["ForeverGuildScanTooltipText" .. side .. index]
            local value = line and line:IsShown() and line:GetText()
            if value and value ~= "" then
                local found = levelPattern and value:match(levelPattern)
                if found then
                    level = tonumber(found)
                else
                    local r, g, b = line:GetTextColor()
                    if r and r > .99 and g < .15 and b < .15 then usable = false end
                end
            end
        end
    end
    scanner:Hide()
    return usable, level
end

function stats.usable(itemID)
    if not itemID then return nil end
    local cached = usableCache[itemID]
    if cached then return cached.usable, cached.level end
    local getInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    if not (getInfo and getInfo(itemID)) then return nil end
    local usable, level = scan("item:" .. itemID)
    if usable == nil then return nil end
    usableCache[itemID] = { usable = usable, level = level }
    return usable, level
end

-- Order eligibility ------------------------------------------------------------------------------
-- TRADEABLE: the crafted item can be handed over (no binding, bind on equip/use).
-- NON_TRADEABLE: bind on pickup, soulbound, account- or quest-bound.
-- UNKNOWN: item or tooltip not loaded yet; hidden until the data arrives.
-- Both sources must agree: the structured bind type of the output item (14th return of
-- GetItemInfo) and the binding line of a private, hidden tooltip for that item. A missing
-- binding line in an unloaded tooltip never counts as tradeable.
local NON_TRADEABLE_LINES = { "ITEM_BIND_ON_PICKUP", "ITEM_SOULBOUND", "ITEM_BIND_QUEST", "ITEM_BIND_TO_ACCOUNT",
    "ITEM_BIND_TO_BNETACCOUNT", "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND", "ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP" }
local TRADEABLE_LINES = { "ITEM_BIND_ON_EQUIP", "ITEM_BIND_ON_USE" }
-- Fallbacks only for clients without the global strings (exact full lines, German/English).
local FALLBACK_NON_TRADEABLE = { ["Wird beim Aufheben gebunden"] = true, ["Binds when picked up"] = true,
    ["Seelengebunden"] = true, ["Soulbound"] = true, ["Questgegenstand"] = true, ["Quest Item"] = true }
local bindCache = {}

local function lineSet(keys)
    local set = {}
    for _, key in ipairs(keys) do
        local value = _G[key]
        if type(value) == "string" and value ~= "" then set[value] = true end
    end
    return set
end

local function scanBinding(itemID, name)
    if not scanner then scan("item:" .. itemID) end
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:ClearLines()
    local ok = pcall(scanner.SetHyperlink, scanner, "item:" .. itemID)
    if not ok or scanner:NumLines() == 0 then return nil end
    local first = _G.ForeverGuildScanTooltipTextLeft1
    -- The tooltip only counts as loaded when it shows this very item.
    if not first or first:GetText() ~= name then scanner:Hide() return nil end
    local blocked, allowed = lineSet(NON_TRADEABLE_LINES), lineSet(TRADEABLE_LINES)
    local result = "none"
    for index = 2, math.min(scanner:NumLines(), 8) do
        local line = _G["ForeverGuildScanTooltipTextLeft" .. index]
        local value = line and line:GetText()
        if value then
            if blocked[value] or FALLBACK_NON_TRADEABLE[value] then result = "bound" break end
            if allowed[value] then result = "equip" end
        end
    end
    scanner:Hide()
    return result
end

-- Returns status, reason; only final results are cached (per session, cache version 2).
function stats.bindStatus(itemID)
    if not itemID then return "UNKNOWN", "no output item" end
    local cached = bindCache[itemID]
    if cached then return cached.status, cached.reason end
    local getInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    local name = getInfo and getInfo(itemID)
    if not name then return "UNKNOWN", "item data not loaded" end
    -- 14th return value of GetItemInfo: bind type of the crafted item.
    local bindType = select(14, getInfo(itemID))
    local line = scanBinding(itemID, name)
    local status, reason
    if bindType == 1 or bindType == 4 or line == "bound" then
        status = "NON_TRADEABLE"
        reason = ("bindType=%s tooltip=%s"):format(tostring(bindType), tostring(line))
    elseif line == nil then
        return "UNKNOWN", "tooltip not loaded"
    elseif bindType == 0 or bindType == 2 or bindType == 3 then
        status, reason = "TRADEABLE", ("bindType=%s tooltip=%s"):format(tostring(bindType), line)
    else
        -- Unknown bind type values: only the tooltip is left; without a clear line it stays unknown.
        if line == "equip" then status, reason = "TRADEABLE", "tooltip=equip"
        else return "UNKNOWN", ("bindType=%s tooltip=%s"):format(tostring(bindType), line) end
    end
    bindCache[itemID] = { status = status, reason = reason }
    return status, reason
end

function stats.invalidate()
    statCache, usableCache, bindCache = {}, {}, {}
end

-- Equipped comparison --------------------------------------------------------------------------
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
stats.slots = SLOTS

function stats.weights()
    local saved = ForeverGuildSettings and ForeverGuildSettings.statWeights
    return type(saved) == "table" and saved or {}
end

function stats.hasWeights()
    for _, value in pairs(stats.weights()) do
        if value ~= 0 then return true end
    end
    return false
end

-- Weighted score from the user's own weights; nil without stats or weights.
function stats.score(values)
    if not values or not stats.hasWeights() then return nil end
    local total = 0
    for id, weight in pairs(stats.weights()) do total = total + (values[id] or 0) * weight end
    return total
end

local function equippedValues(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if not link then return {}, nil end
    return stats.of(link), link
end

local function add(target, values)
    for id, value in pairs(values) do target[id] = (target[id] or 0) + value end
end

-- Compares an item with the equipped one of the same slot. For two-slot types (rings,
-- trinkets, one-hand weapons) the weaker equipped item is the reference; a two-hander is
-- compared with main and off hand together. Returns { current, new, diff, itemLevel } or nil.
function stats.compare(itemID, equipLoc)
    local slots = SLOTS[equipLoc or ""]
    local values = stats.of(itemID)
    if not slots or not values then return nil end
    local reference, referenceLink
    if equipLoc == "INVTYPE_2HWEAPON" then
        local main, mainLink = equippedValues(16)
        local off = equippedValues(17)
        if not main or not off then return nil end
        reference, referenceLink = {}, mainLink
        add(reference, main)
        add(reference, off)
    else
        for _, slot in ipairs(slots) do
            local current, link = equippedValues(slot)
            if not current then return nil end
            local score = stats.score(current) or (current.armor or 0) + (current.str or 0) + (current.agi or 0)
                + (current.sta or 0) + (current.int or 0) + (current.spi or 0)
            if not reference or score < reference.score then
                reference = { values = current, score = score, link = link }
            end
        end
        referenceLink = reference.link
        reference = reference.values
    end
    local diff = {}
    for _, attribute in ipairs(stats.attributes) do
        local id = attribute.id
        diff[id] = (values[id] or 0) - (reference[id] or 0)
    end
    local getInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    local _, _, _, newLevel = getInfo("item:" .. itemID)
    local currentLevel = referenceLink and select(4, getInfo(referenceLink)) or 0
    return { current = reference, new = values, diff = diff, itemLevel = (newLevel or 0) - (currentLevel or 0),
        score = stats.score(values) and (stats.score(values) - (stats.score(reference) or 0)) or nil,
        empty = referenceLink == nil }
end
