local _, addon = ...
-- Guild-wide recipe search in auction-house style. Builds a local index over the
-- profession data that is already synced (no extra addon messages) and groups
-- recipes by crafted item (or by recipe/spell ID when nothing is crafted).
local L = addon.L
local finder = {}
addon.recipeFinder = finder

local function lowerText(text)
    local value = string.lower(text or "")
    value = value:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü")
    return value
end
finder.lower = lowerText

-- Stable internal categories. Item class/subclass IDs come from the game client.
local WEAPON_SUB = { [15] = "dagger", [7] = "sword", [8] = "sword", [0] = "axe", [1] = "axe", [4] = "mace",
    [5] = "mace", [10] = "staff", [6] = "polearm", [13] = "fist", [2] = "bow", [3] = "gun", [18] = "crossbow",
    [19] = "wand", [16] = "thrown", [20] = "fishing" }
local ARMOR_SUB = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate", [6] = "shield" }
local CONSUMABLE_SUB = { [1] = "potion", [2] = "elixir", [3] = "flask", [5] = "food", [7] = "bandage", [6] = "enhance" }
local TRADE_SUB = { [5] = "cloth", [6] = "leather", [7] = "metal", [1] = "parts", [10] = "elemental", [9] = "herb",
    [12] = "enchanting", [8] = "cooking" }
local SLOT_OF = { INVTYPE_HEAD = "HEAD", INVTYPE_SHOULDER = "SHOULDER", INVTYPE_CLOAK = "CLOAK",
    INVTYPE_CHEST = "CHEST", INVTYPE_ROBE = "CHEST", INVTYPE_WRIST = "WRIST", INVTYPE_HAND = "HAND",
    INVTYPE_WAIST = "WAIST", INVTYPE_LEGS = "LEGS", INVTYPE_FEET = "FEET", INVTYPE_NECK = "NECK",
    INVTYPE_FINGER = "FINGER", INVTYPE_TRINKET = "TRINKET", INVTYPE_SHIELD = "SHIELD",
    INVTYPE_2HWEAPON = "2HWEAPON", INVTYPE_WEAPON = "WEAPON", INVTYPE_WEAPONMAINHAND = "WEAPON",
    INVTYPE_WEAPONOFFHAND = "WEAPON", INVTYPE_HOLDABLE = "OFFHAND", INVTYPE_RANGED = "RANGED",
    INVTYPE_RANGEDRIGHT = "RANGED", INVTYPE_THROWN = "RANGED", INVTYPE_SHIRT = "SHIRT", INVTYPE_BODY = "SHIRT",
    INVTYPE_TABARD = "TABARD" }
local ENCHANT_SLOT = { Bracer = "WRIST", Chest = "CHEST", Cloak = "CLOAK", Boots = "FEET", Gloves = "HAND",
    Shield = "SHIELD", Weapon = "WEAPON", ["2H Weapon"] = "2HWEAPON", Necklace = "NECK", ["Off-Hand"] = "OFFHAND" }

-- top, sub, slot
function finder.classify(classID, subclassID, equipLoc, enchantSlot, hasItem, professionID)
    local slot = equipLoc and SLOT_OF[equipLoc]
    if not hasItem then
        if enchantSlot or professionID == 333 then
            local target = enchantSlot and ENCHANT_SLOT[enchantSlot]
            return "enchant", target or "other", target
        end
        return "misc", "other"
    end
    if classID == 2 then return "weapon", WEAPON_SUB[subclassID] or "other", slot end
    if classID == 4 then
        if slot == "NECK" or slot == "FINGER" or slot == "TRINKET" then return "jewelry", slot, slot end
        if subclassID == 6 then return "armor", "shield", "SHIELD" end
        local sub = ARMOR_SUB[subclassID]
        if not sub and slot == "CLOAK" then sub = "cloth" end
        return "armor", sub or "other", slot
    end
    if classID == 1 then return "container", subclassID == 0 and "bag" or "special" end
    if classID == 11 then return "container", "special" end
    if classID == 0 then
        local sub = CONSUMABLE_SUB[subclassID]
        if sub == "enhance" then return "enchant", "enhance" end
        return "consumable", sub or "other"
    end
    if classID == 7 then
        if subclassID == 2 then return "consumable", "explosive" end
        if subclassID == 3 then return "consumable", "device" end
        return "material", TRADE_SUB[subclassID] or "other"
    end
    if classID == 3 then return "material", "gem" end
    if classID == 5 then return "material", "other" end
    if classID == 8 then return "enchant", "enhance" end
    return "misc", "other"
end

local TREE = {
    { "weapon", { "dagger", "sword", "axe", "mace", "staff", "polearm", "fist", "bow", "gun", "crossbow", "wand",
        "thrown", "fishing", "other" } },
    { "armor", { "cloth", "leather", "mail", "plate", "shield", "other" } },
    { "jewelry", { "FINGER", "NECK", "TRINKET" } },
    { "container", { "bag", "special" } },
    { "consumable", { "potion", "elixir", "flask", "food", "bandage", "explosive", "device", "other" } },
    { "material", { "cloth", "leather", "metal", "parts", "elemental", "herb", "enchanting", "cooking", "gem", "other" } },
    { "enchant", { "WEAPON", "2HWEAPON", "SHIELD", "OFFHAND", "CHEST", "CLOAK", "WRIST", "HAND", "FEET", "NECK",
        "enhance", "other" } },
    { "misc", { "other" } },
}
local ARMOR_SLOTS = { "HEAD", "SHOULDER", "CLOAK", "CHEST", "WRIST", "HAND", "WAIST", "LEGS", "FEET", "other" }
local SLOTTED = { cloth = true, leather = true, mail = true, plate = true, other = true }
finder.TREE, finder.ARMOR_SLOTS = TREE, ARMOR_SLOTS

local TOP_LABEL = { weapon = "Weapons", armor = "Armor", jewelry = "Jewelry", container = "Containers",
    consumable = "Consumables", material = "Trade goods", enchant = "Enchantments", misc = "Miscellaneous" }
local SUB_LABEL = {
    weapon = { dagger = "Daggers", sword = "Swords", axe = "Axes", mace = "Maces", staff = "Staves",
        polearm = "Polearms", fist = "Fist weapons", bow = "Bows", gun = "Guns", crossbow = "Crossbows",
        wand = "Wands", thrown = "Thrown", fishing = "Fishing poles" },
    armor = { cloth = "Cloth", leather = "Leather", mail = "Mail", plate = "Plate", shield = "Shields" },
    container = { bag = "Bags", special = "Special bags" },
    consumable = { potion = "Potions", elixir = "Elixirs", flask = "Flasks", food = "Food & drink",
        bandage = "Bandages", explosive = "Explosives", device = "Devices" },
    material = { cloth = "Cloth", leather = "Leather", metal = "Metal & stone", parts = "Parts",
        elemental = "Elemental", herb = "Herbs", enchanting = "Enchanting materials", cooking = "Cooking ingredients",
        gem = "Gems" },
    enchant = { enhance = "Item enhancements" },
}
local SLOT_GLOBAL = { CLOAK = "INVTYPE_CLOAK", OFFHAND = "INVTYPE_HOLDABLE", ["2HWEAPON"] = "INVTYPE_2HWEAPON",
    RANGED = "INVTYPE_RANGED", SHIRT = "INVTYPE_BODY" }

local function slotLabel(slot)
    if not slot or slot == "other" then return L["Other"] end
    local global = _G[SLOT_GLOBAL[slot] or ("INVTYPE_" .. slot)]
    return type(global) == "string" and global ~= "" and global or slot
end
finder.slotLabel = slotLabel

function finder.label(top, sub, slot)
    if slot then return slotLabel(slot) end
    if sub then
        local key = SUB_LABEL[top] and SUB_LABEL[top][sub]
        if key then return L[key] end
        if sub == "other" then return L["Other"] end
        return slotLabel(sub)
    end
    return L[TOP_LABEL[top] or "Miscellaneous"]
end

-- Search synonyms (German and English) mapped to stable tags. Item, recipe, profession
-- and category names of the running client are searched in addition.
local SYNONYMS = {}
local function synonym(tags, ...)
    for index = 1, select("#", ...) do
        local word = select(index, ...)
        local list = SYNONYMS[word] or {}
        for _, tag in ipairs(tags) do list[#list + 1] = tag end
        SYNONYMS[word] = list
    end
end
synonym({ "p197" }, "schneider", "schneiderei", "schneidern", "tailor", "tailoring")
synonym({ "p164" }, "schmied", "schmiede", "schmiedekunst", "schmieden", "bs", "blacksmith", "blacksmithing")
synonym({ "p165" }, "leder", "lederer", "lederverarbeiter", "lederverarbeitung", "lw", "leatherworking",
    "leatherworker", "leather")
synonym({ "p171" }, "alchi", "alchie", "alchemie", "alchemist", "alch", "alchemy")
synonym({ "p333", "t:enchant" }, "vz", "verzauberer", "verzauberkunst", "verzauberung", "verzauberungen",
    "verzaubern", "enchanting", "enchanter", "enchant", "enchants", "enchantment", "enchantments")
synonym({ "p202" }, "ingi", "ingenieur", "ingenieurskunst", "engi", "engineering", "engineer")
synonym({ "p185" }, "koch", "kochen", "kochkunst", "cooking", "cook")
synonym({ "p129" }, "erstehilfe", "eh", "firstaid")
synonym({ "p186" }, "bergbau", "mining", "miner", "schmelzen", "smelting")
synonym({ "p755" }, "juwe", "juwelier", "juwelenschleifer", "juwelierskunst", "jc", "jewelcrafting")
synonym({ "p773" }, "inschrift", "inschriftenkunde", "ik", "inscription", "scribe")
synonym({ "t:weapon" }, "waffe", "waffen", "weapon", "weapons")
synonym({ "t:armor" }, "rüstung", "ruestung", "rüstungen", "armor", "armour")
synonym({ "t:jewelry" }, "schmuck", "jewelry", "jewellery")
synonym({ "t:container" }, "behälter", "behaelter", "tasche", "taschen", "bag", "bags", "container", "containers")
synonym({ "t:consumable" }, "verbrauchsgut", "verbrauchsgüter", "consumable", "consumables")
synonym({ "t:material" }, "material", "materialien", "handwerksmaterial", "handwerksmaterialien", "mats",
    "tradegoods", "reagent", "reagents")
synonym({ "t:misc" }, "sonstiges", "misc")
synonym({ "s:weapon/dagger" }, "dolch", "dolche", "dagger", "daggers")
synonym({ "s:weapon/sword" }, "schwert", "schwerter", "sword", "swords")
synonym({ "s:weapon/axe" }, "axt", "äxte", "axe", "axes")
synonym({ "s:weapon/mace" }, "streitkolben", "kolben", "mace", "maces")
synonym({ "s:weapon/staff" }, "stab", "stäbe", "kampfstab", "staff", "staves")
synonym({ "s:weapon/polearm" }, "stangenwaffe", "stangenwaffen", "polearm", "polearms")
synonym({ "s:weapon/fist" }, "faustwaffe", "faustwaffen", "fist")
synonym({ "s:weapon/bow" }, "bogen", "bögen", "bow", "bows")
synonym({ "s:weapon/gun" }, "schusswaffe", "schusswaffen", "gewehr", "gewehre", "flinte", "gun", "guns")
synonym({ "s:weapon/crossbow" }, "armbrust", "armbrüste", "crossbow", "crossbows")
synonym({ "s:weapon/wand" }, "zauberstab", "zauberstäbe", "wand", "wands")
synonym({ "f:2h" }, "zweihand", "zweihänder", "zweihändig", "zweihandwaffe", "zweihandwaffen", "2h", "twohand",
    "twohanded")
synonym({ "f:1h" }, "einhand", "einhänder", "einhändig", "einhandwaffe", "einhandwaffen", "1h", "onehand")
synonym({ "m:cloth" }, "stoff", "stoffe", "cloth")
synonym({ "m:leather" }, "leder", "leather")
synonym({ "m:mail" }, "kette", "schwere", "kettenrüstung", "mail")
synonym({ "m:plate" }, "platte", "plattenrüstung", "plate")
synonym({ "m:metal" }, "metall", "metal", "barren", "bar", "bars")
synonym({ "s:armor/shield", "l:SHIELD" }, "schild", "schilde", "shield", "shields")
synonym({ "l:HEAD" }, "kopf", "helm", "helme", "head", "helmet", "helm")
synonym({ "l:SHOULDER" }, "schulter", "schultern", "schulterstück", "schulterstücke", "shoulder", "shoulders")
synonym({ "l:CLOAK" }, "rücken", "ruecken", "umhang", "umhänge", "cape", "mantel", "back", "cloak", "cloaks")
synonym({ "l:CHEST" }, "brust", "brustrüstung", "robe", "roben", "weste", "tunika", "wams", "chest", "vest", "tunic")
synonym({ "l:WRIST" }, "handgelenk", "handgelenke", "armschiene", "armschienen", "armschutz", "wrist", "wrists",
    "bracer", "bracers")
synonym({ "l:HAND" }, "hand", "hände", "haende", "handschuh", "handschuhe", "hands", "glove", "gloves")
synonym({ "l:WAIST" }, "taille", "gürtel", "guertel", "waist", "belt", "belts")
synonym({ "l:LEGS" }, "bein", "beine", "hose", "hosen", "legs", "pants", "leggings")
synonym({ "l:FEET" }, "fuß", "füße", "fuesse", "stiefel", "schuhe", "feet", "boots", "shoes")
synonym({ "l:NECK" }, "hals", "halskette", "halsketten", "amulett", "neck", "necklace", "amulet")
synonym({ "l:FINGER" }, "ring", "ringe", "finger", "rings")
synonym({ "l:TRINKET" }, "schmuckstück", "schmuckstücke", "trinket", "trinkets")
synonym({ "s:consumable/potion" }, "trank", "tränke", "potion", "potions")
synonym({ "s:consumable/elixir" }, "elixier", "elixiere", "elixir", "elixirs")
synonym({ "s:consumable/flask" }, "fläschchen", "flask", "flasks")
synonym({ "s:consumable/food" }, "essen", "nahrung", "speise", "food")
synonym({ "s:consumable/bandage" }, "verband", "verbände", "bandage", "bandages")
synonym({ "s:consumable/explosive" }, "sprengstoff", "sprengstoffe", "bombe", "bomben", "dynamit", "explosive",
    "explosives", "bomb", "bombs")
synonym({ "s:consumable/device" }, "gerät", "geräte", "device", "devices")
synonym({ "s:container/special" }, "spezialtasche", "spezialtaschen")
finder.SYNONYMS = SYNONYMS

local function synonymTags(token)
    local exact = SYNONYMS[token]
    if exact then return exact end
    if #token < 4 then return nil end
    local found
    for word, tags in pairs(SYNONYMS) do
        if #word > #token and word:sub(1, #token) == token then
            found = found or {}
            for _, tag in ipairs(tags) do found[#found + 1] = tag end
        end
    end
    return found
end

-- Structured terms: "lvl>=55", "ilvl>50", "stärke>=10". Field names (German and English).
local FIELDS = { lvl = "level", level = "level", stufe = "level", ilvl = "itemLevel", itemlevel = "itemLevel",
    gs = "itemLevel", skill = "skill", fertigkeit = "skill" }

-- One token: plain text, synonym tags, a compound of two synonyms ("zweihandschwert"), an
-- attribute ("stärke": the item must have it) or a comparison ("lvl>=55").
function finder.parse(text)
    local tokens = {}
    local attributes = addon.itemStats and addon.itemStats.synonyms or {}
    for word in lowerText(text):gmatch("[^%s,;/]+") do
        local name, op, value = word:match("^([^<>=]+)([<>]=?)(%d+)$")
        if not name then name, op, value = word:match("^([^<>=]+)(=)(%d+)$") end
        local token = { text = word }
        if name and (FIELDS[name] or attributes[name]) then
            token.field, token.attr, token.op, token.value = FIELDS[name], attributes[name], op, tonumber(value)
        else
            token.tags = synonymTags(word)
            if attributes[word] and not token.tags then token.attr, token.op, token.value = attributes[word], ">", 0 end
        end
        if not token.tags and not token.field and not token.op then
            for split = 2, #word - 2 do
                local head, tail = SYNONYMS[word:sub(1, split)], synonymTags(word:sub(split + 1))
                if head and tail then
                    token.compound = { head, tail }
                    break
                end
            end
        end
        tokens[#tokens + 1] = token
    end
    return tokens
end

local function anyTag(group, tags)
    for _, tag in ipairs(tags) do
        if group.tags[tag] then return true end
    end
    return false
end

local function compareValue(value, op, limit)
    if value == nil then return false end
    if op == ">" then return value > limit end
    if op == ">=" then return value >= limit end
    if op == "<" then return value < limit end
    if op == "<=" then return value <= limit end
    return value == limit
end

-- Attribute values of a group's item (cached in ItemStats); nil while unknown.
local function groupStats(group, ctx)
    if not group.itemID or not addon.itemStats then return nil end
    local values = addon.itemStats.of(group.itemID)
    if not values and ctx and ctx.requestItem then ctx.requestItem(group.itemID) end
    return values
end
finder.groupStats = groupStats

function finder.tokenMatches(group, token, ctx)
    if token.field then return compareValue(group[token.field], token.op, token.value) end
    if token.attr then
        if token.op == ">" and token.value == 0 and group.haystack:find(token.text, 1, true) then return true end
        local values = groupStats(group, ctx)
        return values ~= nil and compareValue(values[token.attr], token.op, token.value)
    end
    if group.haystack:find(token.text, 1, true) then return true end
    if token.tags and anyTag(group, token.tags) then return true end
    local compound = token.compound
    return compound ~= nil and anyTag(group, compound[1]) and anyTag(group, compound[2])
end

local function groupTags(group)
    local tags = { ["t:" .. group.top] = true, ["s:" .. group.top .. "/" .. group.sub] = true }
    for professionID in pairs(group.professions) do tags["p" .. professionID] = true end
    if group.slot then tags["l:" .. group.slot] = true end
    if group.slot == "2HWEAPON" then tags["f:2h"] = true end
    if group.slot == "WEAPON" then tags["f:1h"] = true end
    if group.top == "armor" or group.top == "material" then
        if group.sub == "cloth" or group.sub == "leather" or group.sub == "mail" or group.sub == "plate"
            or group.sub == "metal" then
            tags["m:" .. group.sub] = true
        end
    end
    return tags
end

-- Item and name metadata; refreshed whenever item data arrives.
local function itemMeta(group, ctx)
    local names = {}
    group.pending = nil
    if group.itemID then
        local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
        local name, quality, itemLevel, requiredLevel, bindType
        if getInfo then
            local _
            name, _, quality, itemLevel, requiredLevel, _, _, _, _, _, _, _, _, bindType = getInfo(group.itemID)
        end
        if not name then
            group.pending = true
            if ctx.requestItem then ctx.requestItem(group.itemID) end
        end
        group.name = name or ctx.recipeName(group.recipes[1])
        group.quality, group.itemLevel, group.level, group.bind = quality, itemLevel, requiredLevel, bindType
        group.trade, group.tradeReason = nil, nil
        if group.level == 0 then group.level = 1 end
    else
        group.name = ctx.recipeName(group.recipes[1])
    end
    names[#names + 1] = group.name
    for _, recipe in ipairs(group.recipes) do names[#names + 1] = ctx.recipeName(recipe) end
    for professionID in pairs(group.professions) do names[#names + 1] = ctx.professionName(professionID) end
    names[#names + 1] = finder.label(group.top)
    names[#names + 1] = finder.label(group.top, group.sub)
    if group.slot then names[#names + 1] = slotLabel(group.slot) end
    if group.subclassName then names[#names + 1] = group.subclassName end
    group.haystack = lowerText(table.concat(names, "\n"))
    -- Neither a loaded item nor a resolvable recipe name: not useful in normal lists.
    group.unresolved = group.name == nil or group.name:match("^#%d+$") ~= nil
end

local recipeMeta = {}
local function describeRecipe(recipe, professionID, ctx)
    local meta = recipeMeta[recipe]
    if meta then return meta end
    local _, outputID, enchantSlot = ctx.recipeDetails(recipe)
    if outputID and outputID < 1 then outputID = nil end
    local classID, subclassID, equipLoc, icon
    if outputID and C_Item and C_Item.GetItemInfoInstant then
        local _
        _, _, _, equipLoc, icon, classID, subclassID = C_Item.GetItemInfoInstant(outputID)
    end
    if outputID and not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(outputID) end
    local top, sub, slot = finder.classify(classID, subclassID, equipLoc, enchantSlot, outputID ~= nil, professionID)
    local subclassName
    if classID and subclassID and C_Item and C_Item.GetItemSubClassInfo then
        subclassName = C_Item.GetItemSubClassInfo(classID, subclassID)
    end
    if not icon and C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(recipe) end
    meta = { key = outputID and ("i" .. outputID) or ("s" .. recipe), itemID = outputID, top = top, sub = sub,
        slot = slot, icon = icon, subclassName = subclassName, equipLoc = equipLoc ~= "" and equipLoc or nil }
    recipeMeta[recipe] = meta
    return meta
end

-- Every search context (guild professions, order picker) keeps its own index; profession
-- changes rebuild it, arriving item data only refreshes the groups that were still pending.
local generation, itemGeneration = 1, 1
function finder.invalidate() generation = generation + 1 end
function finder.invalidateItems() itemGeneration = itemGeneration + 1 end

local function build(ctx)
    local groups, byKey = {}, {}
    local skills = addon.recipeSkills or {}
    local function addRecipe(recipe, professionID)
        local meta = describeRecipe(recipe, professionID, ctx)
        local group = byKey[meta.key]
        if not group then
            group = { key = meta.key, itemID = meta.itemID, top = meta.top, sub = meta.sub,
                slot = meta.slot, icon = meta.icon or ctx.professionIcon(professionID), equipLoc = meta.equipLoc,
                subclassName = meta.subclassName, recipes = {}, recipeSet = {}, professions = {},
                crafters = {}, professionID = professionID }
            byKey[meta.key] = group
            groups[#groups + 1] = group
        end
        if not group.recipeSet[recipe] then
            group.recipeSet[recipe] = true
            group.recipes[#group.recipes + 1] = recipe
            local skill = skills[recipe]
            if skill and (not group.skill or skill < group.skill) then group.skill = skill end
        end
        group.professions[professionID] = true
        return group
    end
    for name, profile in pairs(ctx.profiles()) do
        for professionID, entry in pairs(profile.professions or {}) do
            if type(entry) == "table" and type(entry.recipes) == "table" then
                for recipe in pairs(entry.recipes) do
                    local group = addRecipe(recipe, professionID)
                    if not group.crafters[name] then
                        group.crafters[name] = { name = name, recipe = recipe, professionID = professionID,
                            skill = entry.skill, maximum = entry.maximum, updated = profile.updated, own = profile.own }
                    end
                end
            end
        end
    end
    -- Confirmed recipes without a known crafter (order picker only).
    if ctx.catalogRecipes then
        for recipe, professionID in pairs(ctx.catalogRecipes()) do addRecipe(recipe, professionID) end
    end
    for _, group in ipairs(groups) do
        table.sort(group.recipes)
        group.tags = groupTags(group)
        itemMeta(group, ctx)
    end
    return { groups = groups, byKey = byKey }
end

function finder.ensureIndex(ctx)
    local current = ctx.source and ctx.source()
    local state = ctx.finderState
    if not state then
        state = {}
        ctx.finderState = state
    end
    if not state.index or state.generation ~= generation or current ~= state.source then
        state.index, state.generation, state.itemGeneration, state.source = build(ctx), generation, itemGeneration, current
    elseif state.itemGeneration ~= itemGeneration then
        state.itemGeneration = itemGeneration
        for _, group in ipairs(state.index.groups) do
            if group.pending or group.unresolved or group.trade == "UNKNOWN" then itemMeta(group, ctx) end
        end
    end
    return state.index
end

local function between(value, low, high)
    if not low and not high then return true end
    if not value then return false end
    return (not low or value >= low) and (not high or value <= high)
end

-- Returns the visible crafters of a group (current guild members only), online first.
function finder.crafters(group, ctx)
    local list, online = {}, 0
    for name, crafter in pairs(group.crafters) do
        if ctx.isMember(name) then
            crafter.online = ctx.isOnline(name)
            if crafter.online then online = online + 1 end
            list[#list + 1] = crafter
        end
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) > (b.skill or 0) end
        return a.name < b.name
    end)
    return list, online
end

local SORTERS = {
    name = function(group) return lowerText(group.name) end,
    profession = function(group, ctx) return lowerText(ctx.professionName(group.professionID)) end,
    level = function(group) return group.level or -1 end,
    skill = function(group) return group.skill or -1 end,
    crafters = function(group) return group.crafterCount end,
    online = function(group) return group.onlineCount end,
    value = function(group) return finder.comparisonValue(group) or -math.huge end,
}

-- Equipment filters: armorClass (sub of armor), usable (true = usable by this class),
-- levelMode ("now" = up to the own level, "future" = up to 60), better ("ilvl", "attrs",
-- "score"), attrs { { id, min } }, attrMode ("all"/"any"), includeUncrafted, showUnresolved.
local function equipmentMatch(group, filters, ctx, info)
    local stats = addon.itemStats
    if filters.armorClass and not (group.top == "armor" and group.sub == filters.armorClass) then return false end
    local level = UnitLevel and UnitLevel("player") or 60
    if filters.levelMode == "now" and (not group.level or group.level > level) then return false end
    if filters.levelMode == "future" and (not group.level or group.level > 60) then return false end
    if filters.usable then
        local usable = stats and stats.usable(group.itemID)
        if usable == nil then info.noStats = info.noStats + 1 return false end
        if not usable then return false end
    end
    local attrs = filters.attrs
    local needStats = (attrs and #attrs > 0) or filters.better
    if not needStats then return true end
    local values = groupStats(group, ctx)
    if not values then info.noStats = info.noStats + 1 return false end
    if attrs and #attrs > 0 then
        local any = false
        for _, rule in ipairs(attrs) do
            local hit = (values[rule.id] or 0) > 0 and (values[rule.id] or 0) >= (rule.min or 0)
            if hit then any = true elseif filters.attrMode ~= "any" then return false end
        end
        if filters.attrMode == "any" and not any then return false end
    end
    if filters.better then
        local comparison = stats.compare(group.itemID, group.equipLoc)
        if not comparison then return false end
        group.comparison = comparison
        if filters.better == "ilvl" and comparison.itemLevel <= 0 then return false end
        if filters.better == "score" and not (comparison.score and comparison.score > 0) then return false end
        if filters.better == "attrs" then
            if not attrs or #attrs == 0 then return false end
            for _, rule in ipairs(attrs) do
                if (comparison.diff[rule.id] or 0) <= 0 then return false end
            end
        end
    end
    return true
end

-- filters: text, profession, category {top, sub, slot}, slot, quality, levelMin/Max,
-- itemLevelMin/Max, skillMax, crafter, online ("online"/"offline"), bind ("trade"/"bop"),
-- plus the equipment filters above.
function finder.query(ctx, filters, sortKey, descending)
    local data = finder.ensureIndex(ctx)
    local tokens = finder.parse(filters.text or "")
    local tokenHits = {}
    local results, counts = {}, {}
    local info = { unresolved = 0, pending = 0, noStats = 0, bound = 0, bindUnknown = 0 }
    local category = filters.category or {}
    for _, group in ipairs(data.groups) do
        local crafters, online = finder.crafters(group, ctx)
        group.crafterList, group.crafterCount, group.onlineCount = crafters, #crafters, online
        local ok = #crafters > 0 or (filters.includeUncrafted and ctx.catalogRecipes ~= nil)
        -- Only items that can be handed over (or services such as enchantments) are orderable.
        -- Applied before counts and sorting; no filter or option can bypass it.
        local status = finder.groupTradeStatus(group, ctx)
        if status == "NON_TRADEABLE" then
            info.bound = info.bound + 1
            ok = false
        elseif status == "UNKNOWN" then
            info.bindUnknown = info.bindUnknown + 1
            ok = false
        end
        if group.pending then info.pending = info.pending + 1 end
        if group.unresolved then
            info.unresolved = info.unresolved + 1
            if not filters.showUnresolved then ok = false end
        end
        if ok and filters.profession and not group.professions[filters.profession] then ok = false end
        if ok and filters.slot and group.slot ~= filters.slot then ok = false end
        if ok and filters.quality and (not group.quality or group.quality < filters.quality) then ok = false end
        if ok and not between(group.level, filters.levelMin, filters.levelMax) then ok = false end
        if ok and not between(group.itemLevel, filters.itemLevelMin, filters.itemLevelMax) then ok = false end
        if ok and filters.skillMax and (not group.skill or group.skill > filters.skillMax) then ok = false end
        if ok and filters.crafter and not (group.crafters[filters.crafter] and ctx.isMember(filters.crafter)) then ok = false end
        if ok and filters.online == "online" and online == 0 then ok = false end
        if ok and filters.online == "offline" and online > 0 then ok = false end

        if ok and not equipmentMatch(group, filters, ctx, info) then ok = false end
        if ok then
            for position, token in ipairs(tokens) do
                if finder.tokenMatches(group, token, ctx) then
                    tokenHits[position] = true
                else
                    ok = false
                end
            end
        end
        if ok then
            local top, sub = group.top, group.top .. "/" .. group.sub
            counts[top] = (counts[top] or 0) + 1
            counts[sub] = (counts[sub] or 0) + 1
            if group.top == "armor" then
                local slotKey = sub .. "/" .. (group.slot and SLOTTED[group.sub] and group.slot or "other")
                counts[slotKey] = (counts[slotKey] or 0) + 1
            end
            counts.all = (counts.all or 0) + 1
            if (not category.top or category.top == group.top) and (not category.sub or category.sub == group.sub)
                and (not category.slot or category.slot == (group.slot or "other")) then
                results[#results + 1] = group
            end
        end
    end
    local unknown = {}
    for position, token in ipairs(tokens) do
        if not tokenHits[position] then unknown[#unknown + 1] = token.text end
    end
    local value = SORTERS[sortKey or "name"] or SORTERS.name
    local cache = {}
    for _, group in ipairs(results) do cache[group] = value(group, ctx) end
    local byName = SORTERS.name
    table.sort(results, function(a, b)
        local left, right = cache[a], cache[b]
        if left ~= right then
            if descending then return left > right end
            return left < right
        end
        local nameA, nameB = byName(a), byName(b)
        if nameA ~= nameB then return nameA < nameB end
        return a.key < b.key
    end)
    return results, counts, unknown, #data.groups, info
end

----------------------------------------------------------------------------------------
-- User interface
----------------------------------------------------------------------------------------
local GOLD, MUTED, GREEN = { 1, .82, .24 }, { .55, .51, .45 }, { .35, .9, .4 }
local STALE = 30 * 86400

local function virtualList(parent, rowHeight, createRow, updateRow)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    local rows, data = {}, {}
    local function layout()
        local width, height = scroll:GetWidth(), scroll:GetHeight()
        if width <= 0 then return end
        content:SetWidth(width)
        content:SetHeight(math.max(1, #data * rowHeight))
        local range = math.max(0, #data * rowHeight - height)
        if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
        local first = math.floor(scroll:GetVerticalScroll() / rowHeight)
        local visible = math.ceil(height / rowHeight) + 1
        for slot = 1, visible do
            local row = rows[slot]
            if not row then
                row = createRow(content)
                rows[slot] = row
            end
            local position = first + slot
            local item = data[position]
            if item then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(position - 1) * rowHeight)
                row:SetPoint("RIGHT", content, "RIGHT")
                row:SetHeight(rowHeight)
                updateRow(row, item, position)
                row:Show()
            else
                row:Hide()
            end
        end
        for slot = visible + 1, #rows do rows[slot]:Hide() end
    end
    scroll:HookScript("OnVerticalScroll", layout)
    scroll:HookScript("OnSizeChanged", layout)
    if scroll.ScrollBar then scroll.ScrollBar:HookScript("OnValueChanged", layout) end
    return {
        scroll = scroll,
        set = function(entries, reset)
            data = entries
            if reset then scroll:SetVerticalScroll(0) end
            layout()
        end,
        update = layout,
    }
end

local function text(parent, font, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

local function dropdown(parent, width, options, get, set)
    local control = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    control:SetWidth(width)
    control:SetupMenu(function(_, root)
        if root.SetScrollMode then root:SetScrollMode(360) end
        for _, option in ipairs(options()) do
            root:CreateRadio(option[2], function() return get() == option[1] end, function() set(option[1]) end, option[1])
        end
    end)
    control.Sync = function()
        if control.GenerateMenu then control:GenerateMenu() end
    end
    return control
end

local function numberBox(parent, width, onChange)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnTextChanged", function(_, user) if user then onChange() end end)
    return box
end

local function tooltipFor(control, title, detail)
    control:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if detail then GameTooltip:AddLine(detail, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function itemTooltip(owner, itemID, recipe, ctx)
    if itemID then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. itemID)
        GameTooltip:Show()
        -- Blizzard comparison tooltip with the equipped item, when the client provides it.
        if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
    elseif recipe then
        owner.entry = { recipe = recipe }
        ctx.recipeTooltip(owner)
    end
end

local function qualityColor(quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return GOLD[1], GOLD[2], GOLD[3]
end

local function formatDate(stamp)
    return stamp and date("%d.%m.%y", stamp) or "–"
end

-- opts.picker: order picker (confirmed recipes without crafter selectable, "Post on the
-- bulletin board" in the detail view; ctx.public(recipe, professionID) handles it).
function finder.create(parent, ctx, opts)
    opts = opts or {}
    local view = CreateFrame("Frame", nil, parent)
    local function freshFilters() return { category = {}, includeUncrafted = opts.picker or nil, attrs = {} } end
    local filters, sortKey, descending = freshFilters(), "name", false
    local expanded, selectedKey, results = {}, nil, {}
    local searchSerial, numberSerial = 0, 0

    -- Category navigation -------------------------------------------------------------
    local treePanel = ctx.panel(view)
    treePanel:SetPoint("TOPLEFT")
    treePanel:SetPoint("BOTTOMLEFT")
    treePanel:SetWidth(204)
    local treeTitle = text(treePanel, "GameFontNormal")
    treeTitle:SetPoint("TOPLEFT", 12, -11)
    treeTitle:SetText(L["Categories"])
    local tree
    tree = virtualList(treePanel, 19, function(content)
        local row = CreateFrame("Button", nil, content)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(.82, .58, .22, .28)
        row.label = text(row, "GameFontHighlightSmall")
        row.label:SetPoint("RIGHT", -4, 0)
        row:SetScript("OnClick", function(self)
            local node = self.node
            if node.children then expanded[node.id] = not expanded[node.id] or nil end
            filters.category = { top = node.top, sub = node.sub, slot = node.slot }
            selectedKey = nil
            view.refresh(true)
        end)
        return row
    end, function(row, node)
        row.node = node
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 8 + node.depth * 12, 0)
        row.label:SetPoint("RIGHT", -4, 0)
        local marker = node.children and (expanded[node.id] and "− " or "+ ") or "   "
        row.label:SetText(marker .. node.label .. ("  (%d)"):format(node.count))
        local active = node.active
        row.selected:SetShown(active)
        if active then row.label:SetTextColor(1, 1, 1)
        elseif node.count == 0 then row.label:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        elseif node.depth == 0 then row.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        else row.label:SetTextColor(.92, .88, .80) end
    end)
    tree.scroll:SetPoint("TOPLEFT", 6, -32)
    tree.scroll:SetPoint("BOTTOMRIGHT", -27, 8)

    -- Filter bar ------------------------------------------------------------------------
    -- Controls flow left to right and wrap into another row when the window is narrow,
    -- and every control is sized to its longest caption, so no text has to be cut off.
    local filterPanel = ctx.panel(view)
    filterPanel:SetPoint("TOPLEFT", treePanel, "TOPRIGHT", 7, 0)
    filterPanel:SetPoint("TOPRIGHT")
    filterPanel:SetHeight(66)
    local measure = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    measure:Hide()
    local function textWidth(value, font)
        measure:SetFontObject(font or GameFontHighlight)
        local clean = tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        measure:SetText(clean)
        return measure:GetStringWidth()
    end
    local dropdowns, flowItems = {}, {}
    local function changed() view.refresh(true) end
    local function addDropdown(options, get, set, maximum)
        local control = dropdown(filterPanel, 120, options, get, set)
        dropdowns[#dropdowns + 1] = control
        flowItems[#flowItems + 1] = { frame = control, sized = true, width = function()
            local widest = 0
            for _, option in ipairs(options()) do widest = math.max(widest, textWidth(option[2])) end
            return math.floor(math.min(maximum or 210, math.max(96, widest + 46)))
        end }
        return control
    end

    local search = CreateFrame("EditBox", nil, filterPanel, "InputBoxTemplate")
    search:SetSize(226, 22)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    flowItems[#flowItems + 1] = { frame = search, dx = 6, dy = -2, width = function() return 234 end }
    local placeholder = text(search, "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 2, 0)
    placeholder:SetPoint("RIGHT", -4, 0)
    placeholder:SetText(L["Search item, recipe, profession or category"])
    tooltipFor(search, L["Search"], L["Combine several terms, e.g. “tailor bracers” or “alch healing potion”. Every term must match."])
    search:SetScript("OnTextChanged", function(box)
        placeholder:SetShown(box:GetText() == "")
        searchSerial = searchSerial + 1
        local serial = searchSerial
        C_Timer.After(.2, function()
            if serial ~= searchSerial then return end
            filters.text = box:GetText()
            selectedKey = nil
            local ok, err = pcall(view.refresh, true)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end)
    end)

    addDropdown(function()
        local options, seen = { { 0, L["All professions"] } }, {}
        for _, group in ipairs(finder.ensureIndex(ctx).groups) do
            for professionID in pairs(group.professions) do seen[professionID] = true end
        end
        local list = {}
        for professionID in pairs(seen) do list[#list + 1] = { professionID, ctx.professionName(professionID) } end
        table.sort(list, function(a, b) return a[2] < b[2] end)
        for _, option in ipairs(list) do options[#options + 1] = option end
        return options
    end, function() return filters.profession or 0 end,
        function(value) filters.profession = value ~= 0 and value or nil; changed() end)
    addDropdown(function()
        local options = { { -1, L["Any quality"] } }
        for quality = 1, 5 do
            local name = _G["ITEM_QUALITY" .. quality .. "_DESC"]
            if name then
                local r, g, b = qualityColor(quality)
                options[#options + 1] = { quality, ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255,
                    L["%s or better"]:format(name)) }
            end
        end
        return options
    end, function() return filters.quality or -1 end,
        function(value) filters.quality = value >= 0 and value or nil; changed() end)
    addDropdown(function()
        return { { "all", L["Online and offline"] }, { "online", L["Crafter online"] }, { "offline", L["Only offline crafters"] } }
    end, function() return filters.online or "all" end,
        function(value) filters.online = value ~= "all" and value or nil; changed() end)
    local slotChoices = { "HEAD", "SHOULDER", "CLOAK", "CHEST", "WRIST", "HAND", "WAIST", "LEGS", "FEET", "NECK",
        "FINGER", "TRINKET", "WEAPON", "2HWEAPON", "SHIELD", "OFFHAND", "RANGED" }
    addDropdown(function()
        local options = { { "all", L["All slots"] } }
        for _, slot in ipairs(slotChoices) do options[#options + 1] = { slot, slotLabel(slot) } end
        return options
    end, function() return filters.slot or "all" end,
        function(value) filters.slot = value ~= "all" and value or nil; changed() end)
    addDropdown(function()
        local options, names, seen = { { "all", L["All crafters"] } }, {}, {}
        for _, group in ipairs(finder.ensureIndex(ctx).groups) do
            for name in pairs(group.crafters) do
                if not seen[name] and ctx.isMember(name) then
                    seen[name] = true
                    names[#names + 1] = { name, ctx.displayName(name) }
                end
            end
        end
        table.sort(names, function(a, b) return a[2] < b[2] end)
        for _, option in ipairs(names) do options[#options + 1] = option end
        return options
    end, function() return filters.crafter or "all" end,
        function(value) filters.crafter = value ~= "all" and value or nil; changed() end, 180)

    addDropdown(function()
        return { { "all", L["Any armor class"] }, { "cloth", finder.label("armor", "cloth") },
            { "leather", finder.label("armor", "leather") }, { "mail", finder.label("armor", "mail") },
            { "plate", finder.label("armor", "plate") } }
    end, function() return filters.armorClass or "all" end,
        function(value) filters.armorClass = value ~= "all" and value or nil; changed() end)

    local numbers = {}
    local function readNumbers()
        local function value(box) return tonumber(box:GetText()) end
        filters.levelMin, filters.levelMax = value(numbers.levelMin), value(numbers.levelMax)
        filters.itemLevelMin, filters.itemLevelMax = value(numbers.itemMin), value(numbers.itemMax)
        filters.skillMax = value(numbers.skill)
        numberSerial = numberSerial + 1
        local serial = numberSerial
        C_Timer.After(.3, function()
            if serial == numberSerial then view.refresh(true) end
        end)
    end
    -- Caption plus one or two number boxes, treated as one unit by the flow layout.
    local function numberGroup(caption, hint, first, second)
        local holder = CreateFrame("Frame", nil, filterPanel)
        holder:SetHeight(24)
        holder:EnableMouse(true)
        tooltipFor(holder, caption, hint)
        local label = text(holder, "GameFontNormalSmall")
        label:SetPoint("LEFT")
        label:SetText(caption)
        local labelWidth = math.ceil(label:GetStringWidth())
        local boxes, x = { first, second }, labelWidth + 10
        for position = 1, #boxes do
            local box = numberBox(holder, 32, readNumbers)
            box:SetPoint("LEFT", x, 0)
            numbers[boxes[position]] = box
            x = x + 32 + 10
        end
        flowItems[#flowItems + 1] = { frame = holder, sized = true, width = function() return x - 6 end }
    end
    numberGroup(L["Level"], L["Required character level (min – max). Items without known level are hidden while set."],
        "levelMin", "levelMax")
    numberGroup(L["iLvl"], L["Item level (min – max). Items without known item level are hidden while set."],
        "itemMin", "itemMax")
    numberGroup(L["Max. skill"], L["Highest required profession skill. Recipes without known skill requirement are hidden while set."],
        "skill")
    local advancedShown = false
    local advancedButton = ctx.button(filterPanel, "", 10, 0, 0, function()
        advancedShown = not advancedShown
        view.refresh(false)
    end)
    flowItems[#flowItems + 1] = { frame = advancedButton, dy = -1, width = function()
        return math.ceil(math.max(textWidth(L["Show advanced filters"], GameFontNormal),
            textWidth(L["Hide advanced filters"], GameFontNormal))) + 30 end, sized = true }
    local reset = ctx.button(filterPanel, L["Reset filters"], math.ceil(textWidth(L["Reset filters"], GameFontNormal)) + 30,
        0, 0, function() view.reset() end)
    flowItems[#flowItems + 1] = { frame = reset, dy = -1, width = function() return reset:GetWidth() end }
    local activeText = text(filterPanel, "GameFontHighlightSmall")
    activeText:SetWordWrap(true)

    -- Advanced filters (equipment, attributes, comparison); folded away by default.
    local advanced = ctx.panel(view)
    advanced:SetPoint("TOPLEFT", filterPanel, "BOTTOMLEFT", 0, -5)
    advanced:SetPoint("TOPRIGHT", filterPanel, "BOTTOMRIGHT", 0, -5)
    advanced:SetHeight(70)
    advanced:Hide()
    local advancedItems = {}
    local function advancedDropdown(options, get, set, maximum)
        local control = dropdown(advanced, 120, options, get, set)
        dropdowns[#dropdowns + 1] = control
        advancedItems[#advancedItems + 1] = { frame = control, sized = true, width = function()
            local widest = 0
            for _, option in ipairs(options()) do widest = math.max(widest, textWidth(option[2])) end
            return math.floor(math.min(maximum or 240, math.max(96, widest + 46)))
        end }
        return control
    end
    local function advancedCheck(caption, hint, get, set)
        local holder = CreateFrame("Frame", nil, advanced)
        holder:SetHeight(24)
        local box = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
        box:SetSize(24, 24)
        box:SetPoint("LEFT")
        box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); changed() end)
        local label = text(holder, "GameFontHighlightSmall")
        label:SetPoint("LEFT", box, "RIGHT", 2, 0)
        label:SetText(caption)
        if hint then tooltipFor(box, caption, hint) end
        holder.Sync = function() box:SetChecked(get() and true or false) end
        advancedItems[#advancedItems + 1] = { frame = holder, sized = true, sync = holder.Sync,
            width = function() return math.ceil(textWidth(caption, GameFontHighlightSmall)) + 32 end }
    end
    advancedCheck(L["Usable by my character"], L["Checked with the item tooltip: class, armor and weapon restrictions. Items not loaded yet are hidden while set."],
        function() return filters.usable end, function(value) filters.usable = value or nil end)
    advancedDropdown(function()
        return { { "all", L["Any required level"] }, { "now", L["Usable at my current level"] },
            { "future", L["Also future gear up to level 60"] } }
    end, function() return filters.levelMode or "all" end,
        function(value) filters.levelMode = value ~= "all" and value or nil; changed() end)
    advancedDropdown(function()
        local options = { { "all", L["No comparison filter"] }, { "ilvl", L["Higher item level than equipped"] },
            { "attrs", L["Improves the selected attributes"] } }
        if addon.itemStats and addon.itemStats.hasWeights() then options[#options + 1] = { "score", L["Higher weighted score"] } end
        return options
    end, function() return filters.better or "all" end,
        function(value) filters.better = value ~= "all" and value or nil; changed() end)
    local attributeOptions = function()
        local options = { { "none", L["Choose attribute"] } }
        for _, attribute in ipairs(addon.itemStats and addon.itemStats.attributes or {}) do
            options[#options + 1] = { attribute.id, addon.itemStats.label(attribute.id) }
        end
        return options
    end
    local attributeRows = {}
    local function readAttributes()
        filters.attrs = {}
        for _, row in ipairs(attributeRows) do
            if row.shown and row.id then filters.attrs[#filters.attrs + 1] = { id = row.id, min = tonumber(row.box:GetText()) } end
        end
        numberSerial = numberSerial + 1
        local serial = numberSerial
        C_Timer.After(.3, function() if serial == numberSerial then view.refresh(true) end end)
    end
    for index = 1, 4 do
        local holder = CreateFrame("Frame", nil, advanced)
        holder:SetHeight(24)
        local row = { holder = holder, shown = index == 1 }
        row.drop = dropdown(holder, 150, attributeOptions, function() return row.id or "none" end, function(value)
            row.id = value ~= "none" and value or nil
            readAttributes()
        end)
        row.drop:SetPoint("LEFT")
        dropdowns[#dropdowns + 1] = row.drop
        local atLeast = text(holder, "GameFontHighlightSmall")
        atLeast:SetPoint("LEFT", row.drop, "RIGHT", 6, 0)
        atLeast:SetText(L["at least"])
        row.box = numberBox(holder, 34, readAttributes)
        row.box:SetPoint("LEFT", atLeast, "RIGHT", 8, 0)
        attributeRows[index] = row
        advancedItems[#advancedItems + 1] = { frame = holder, sized = true, visible = function() return row.shown end,
            width = function() return 150 + 12 + math.ceil(textWidth(L["at least"], GameFontHighlightSmall)) + 46 end }
    end
    local addAttribute = ctx.button(advanced, L["+ Attribute"], math.ceil(textWidth(L["+ Attribute"], GameFontNormal)) + 28, 0, 0,
        function()
            for _, row in ipairs(attributeRows) do
                if not row.shown then row.shown = true; break end
            end
            view.refresh(false)
        end)
    advancedItems[#advancedItems + 1] = { frame = addAttribute, dy = -1, width = function() return addAttribute:GetWidth() end }
    advancedCheck(L["At least one attribute is enough"], L["Off: every selected attribute is required. On: one of them is enough."],
        function() return filters.attrMode == "any" end, function(value) filters.attrMode = value and "any" or nil end)
    if opts.picker then
        advancedCheck(L["Include recipes without known crafter"], L["Confirmed recipes nobody in the guild is known to craft yet. Useful for public orders."],
            function() return filters.includeUncrafted end, function(value) filters.includeUncrafted = value or nil end)
    end
    advancedCheck(L["Show incomplete recipe data"], L["Recipes whose name or item could not be resolved by the client. Hidden by default."],
        function() return filters.showUnresolved end, function(value) filters.showUnresolved = value or nil end)
    local statsHint = text(advanced, "GameFontDisableSmall")
    statsHint:SetWordWrap(true)

    local function layoutItems(container, items, startY)
        local available = container:GetWidth()
        if available <= 0 then return startY end
        local x, y = 10, startY
        for _, item in ipairs(items) do
            local visible = not item.visible or item.visible()
            item.frame:SetShown(visible)
            if visible then
                local width = item.width()
                if item.sized then item.frame:SetWidth(width) end
                if x > 10 and x + width > available - 10 then x, y = 10, y - 30 end
                item.frame:ClearAllPoints()
                item.frame:SetPoint("TOPLEFT", x + (item.dx or 0), y + (item.dy or 0))
                x = x + width + 8
            end
        end
        return y
    end
    local function flow()
        local available = filterPanel:GetWidth()
        if available <= 0 then return end
        advancedButton:SetText(advancedShown and L["Hide advanced filters"] or L["Show advanced filters"])
        local y = layoutItems(filterPanel, flowItems, -7)
        activeText:ClearAllPoints()
        activeText:SetPoint("TOPLEFT", 12, y - 30)
        activeText:SetWidth(available - 24)
        local activeHeight = activeText:GetText() ~= "" and (math.ceil(activeText:GetStringHeight()) + 4) or 0
        activeText:SetShown(activeHeight > 0)
        filterPanel:SetHeight(-y + 26 + 7 + activeHeight)
        advanced:SetShown(advancedShown)
        if advancedShown then
            local advancedY = layoutItems(advanced, advancedItems, -7)
            statsHint:ClearAllPoints()
            statsHint:SetPoint("TOPLEFT", 12, advancedY - 30)
            statsHint:SetWidth(available - 24)
            statsHint:SetText(addon.itemStats and addon.itemStats.available() and
                L["Attributes come from the item data of the client; items whose data is not loaded yet are hidden while attribute filters are set. Weapon speed and special effects are not compared."]
                or L["This client provides no structured item attributes; attribute filters are unavailable."])
            advanced:SetHeight(-advancedY + 26 + 7 + math.ceil(statsHint:GetStringHeight()) + 6)
            for _, item in ipairs(advancedItems) do if item.sync then item.sync() end end
        end
    end
    filterPanel:SetScript("OnSizeChanged", flow)
    view.flowFilters = flow

    -- Result table ----------------------------------------------------------------------
    local detail = ctx.panel(view)
    detail:SetPoint("BOTTOMLEFT", treePanel, "BOTTOMRIGHT", 7, 0)
    detail:SetPoint("BOTTOMRIGHT")
    detail:SetHeight(238)
    local resultPanel = ctx.panel(view)
    local function anchorResults()
        local above = advanced:IsShown() and advanced or filterPanel
        resultPanel:ClearAllPoints()
        resultPanel:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -7)
        resultPanel:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -7)
        resultPanel:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, detail:IsShown() and 245 or 0)
    end
    local COLUMNS = {
        { key = "profession", title = L["Profession"], width = 112 },
        { key = "level", title = L["Level"], width = 42, right = true },
        { key = "skill", title = L["Skill"], width = 54, right = true },
        { key = "crafters", title = L["Crafters"], width = 66, right = true },
        { key = "online", title = L["Online"], width = 52, right = true },
        { key = "value", title = L["Value"], width = 48, right = true },
    }
    local ACTION = 0
    local header = CreateFrame("Frame", nil, resultPanel)
    header:SetPoint("TOPLEFT", 8, -7)
    header:SetPoint("TOPRIGHT", -30, -7)
    header:SetHeight(18)
    local headerLine = header:CreateTexture(nil, "ARTWORK")
    headerLine:SetPoint("BOTTOMLEFT", 0, -1)
    headerLine:SetPoint("BOTTOMRIGHT", 0, -1)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(.62, .45, .22, .7)
    local headerButtons = {}
    local function headerButton(key, title, justify)
        local control = CreateFrame("Button", nil, header)
        control:SetHeight(18)
        control.label = text(control, "GameFontNormalSmall", justify)
        control.label:SetAllPoints()
        control.title = title
        control:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        control:SetScript("OnClick", function()
            if sortKey == key then descending = not descending
            else sortKey, descending = key, key ~= "name" and key ~= "profession" end
            view.refresh(false)
        end)
        headerButtons[key] = control
        return control
    end
    local nameHeader = headerButton("name", L["Item"], "LEFT")
    nameHeader:SetPoint("LEFT", 26, 0)
    local offset = ACTION + 6
    for position = #COLUMNS, 1, -1 do
        local column = COLUMNS[position]
        column.offset = offset
        local control = headerButton(column.key, column.title, column.right and "RIGHT" or "LEFT")
        control:SetPoint("RIGHT", -offset, 0)
        control:SetWidth(column.width)
        offset = offset + column.width + 8
    end
    nameHeader:SetPoint("RIGHT", -offset, 0)

    local emptyText = text(resultPanel, "GameFontDisable", "CENTER")
    emptyText:SetPoint("TOPLEFT", 20, -60)
    emptyText:SetPoint("TOPRIGHT", -20, -60)
    emptyText:SetWordWrap(true)
    local statusText = text(resultPanel, "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", 12, 8)
    statusText:SetPoint("BOTTOMRIGHT", -12, 8)

    local resultList
    resultList = virtualList(resultPanel, 22, function(content)
        local row = CreateFrame("Button", nil, content)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(.82, .58, .22, .25)
        row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(1, 1, 1, .035)
        row.marker = row:CreateTexture(nil, "ARTWORK")
        row.marker:SetPoint("TOPLEFT", 0, -2)
        row.marker:SetPoint("BOTTOMLEFT", 0, 2)
        row.marker:SetWidth(3)
        row.marker:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], .9)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(.07, .93, .07, .93)
        row.name = text(row, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 28, 0)
        row.name:SetPoint("RIGHT", -offset, 0)
        row.columns = {}
        for position, column in ipairs(COLUMNS) do
            local label = text(row, "GameFontHighlightSmall", column.right and "RIGHT" or "LEFT")
            label:SetPoint("RIGHT", -column.offset, 0)
            label:SetWidth(column.width)
            row.columns[position] = label
        end
        row:SetScript("OnClick", function(self)
            selectedKey = self.group and self.group.key
            view.refresh(false)
        end)
        row:SetScript("OnEnter", function(self)
            if self.group then itemTooltip(self, self.group.itemID, self.group.recipes[1], ctx) end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, group, position)
        row.group = group
        row.icon:SetTexture(group.icon or 134400)
        row.name:SetText(group.name)
        row.name:SetTextColor(qualityColor(group.quality))
        local value = finder.comparisonValue(group, filters)
        local values = {
            ctx.professionName(group.professionID),
            group.level and tostring(group.level) or "–",
            group.skill and tostring(group.skill) or "–",
            tostring(group.crafterCount),
            tostring(group.onlineCount),
            value and ((value > 0 and "+" or "") .. finder.number(value)) or "–",
        }
        for column, label in ipairs(row.columns) do
            label:SetText(values[column])
            label:SetTextColor(.92, .88, .80)
        end
        if value and value ~= 0 then
            local tint = value > 0 and GREEN or { 1, .4, .35 }
            row.columns[6]:SetTextColor(tint[1], tint[2], tint[3])
        end
        if group.onlineCount > 0 then row.columns[5]:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        else row.columns[5]:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end
        row.marker:SetShown(group.onlineCount > 0)
        row.stripe:SetShown(position % 2 == 0)
        row.selected:SetShown(group.key == selectedKey)
    end)
    resultList.scroll:SetPoint("TOPLEFT", 8, -29)
    resultList.scroll:SetPoint("BOTTOMRIGHT", -30, 26)

    -- Detail view -----------------------------------------------------------------------
    local hero = CreateFrame("Button", nil, detail)
    hero:SetPoint("TOPLEFT", 10, -10)
    hero:SetSize(286, 40)
    local heroIcon = hero:CreateTexture(nil, "ARTWORK")
    heroIcon:SetSize(36, 36)
    heroIcon:SetPoint("LEFT")
    heroIcon:SetTexCoord(.06, .94, .06, .94)
    local heroName = text(hero, "GameFontNormal")
    heroName:SetPoint("TOPLEFT", 44, -3)
    heroName:SetPoint("RIGHT")
    local heroSub = text(hero, "GameFontHighlightSmall")
    heroSub:SetPoint("TOPLEFT", 44, -22)
    heroSub:SetPoint("RIGHT")
    hero:SetScript("OnEnter", function(self)
        if self.group then itemTooltip(self, self.group.itemID, self.group.recipes[1], ctx) end
    end)
    hero:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local facts = text(detail, "GameFontHighlightSmall")
    facts:SetPoint("TOPLEFT", 12, -56)
    facts:SetWidth(284)
    facts:SetWordWrap(true)
    facts:SetSpacing(2)
    local compareText = text(detail, "GameFontHighlightSmall")
    compareText:SetPoint("TOPLEFT", facts, "BOTTOMLEFT", 0, -5)
    compareText:SetWidth(284)
    compareText:SetWordWrap(true)
    compareText:SetSpacing(2)
    local materialsTitle = text(detail, "GameFontNormalSmall")
    materialsTitle:SetPoint("TOPLEFT", compareText, "BOTTOMLEFT", 0, -6)
    materialsTitle:SetText(L["Recipes and materials"])
    local postButton
    if opts.picker then
        postButton = ctx.button(detail, L["Post on the bulletin board"],
            math.ceil(textWidth(L["Post on the bulletin board"], GameFontNormal)) + 30, 0, 0, function()
                local group = detail.group
                if group and ctx.public then ctx.public(group.recipes[1], group.professionID) end
            end)
        postButton:ClearAllPoints()
        postButton:SetPoint("BOTTOMLEFT", 10, 8)
    end
    local materials = virtualList(detail, 17, function(content)
        local row = CreateFrame("Button", nil, content)
        row.label = text(row, "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 2, 0)
        row.label:SetPoint("RIGHT", -2, 0)
        row:SetScript("OnEnter", function(self)
            local entry = self.entry
            if entry.itemID then itemTooltip(self, entry.itemID, nil, ctx)
            elseif entry.recipe then itemTooltip(self, nil, entry.recipe, ctx) end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, entry)
        row.entry = entry
        row.label:SetText(entry.text)
        if entry.recipe then row.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        else row.label:SetTextColor(.92, .88, .80) end
    end)
    materials.scroll:SetPoint("TOPLEFT", materialsTitle, "BOTTOMLEFT", -2, -3)
    materials.scroll:SetPoint("BOTTOMLEFT", 10, postButton and 38 or 10)
    materials.scroll:SetWidth(266)

    local divider = detail:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 306, -10)
    divider:SetPoint("BOTTOMLEFT", 306, 10)
    divider:SetWidth(1)
    divider:SetColorTexture(.62, .45, .22, .55)
    local crafterTitle = text(detail, "GameFontNormal")
    crafterTitle:SetPoint("TOPLEFT", 318, -11)
    crafterTitle:SetPoint("RIGHT", -12, 0)
    local CRAFTER_COLUMNS = { { L["Skill"], 56 }, { L["Status"], 50 }, { L["Updated"], 60 } }
    local crafterHeader = CreateFrame("Frame", nil, detail)
    crafterHeader:SetPoint("TOPLEFT", 316, -32)
    crafterHeader:SetPoint("TOPRIGHT", -32, -32)
    crafterHeader:SetHeight(16)
    -- Button widths follow their (small) captions.
    local whisperWidth = math.ceil(textWidth(L["Whisper#2"], GameFontNormalSmall)) + 24
    local orderWidth = math.ceil(textWidth(L["Place order"], GameFontNormalSmall)) + 24
    local crafterButtons = whisperWidth + orderWidth + 6
    local cursor = crafterButtons + 6
    local headerName = text(crafterHeader, "GameFontNormalSmall")
    headerName:SetPoint("LEFT", 22, 0)
    headerName:SetText(L["Character"])
    for position = #CRAFTER_COLUMNS, 1, -1 do
        local column = CRAFTER_COLUMNS[position]
        local label = text(crafterHeader, "GameFontNormalSmall")
        label:SetPoint("RIGHT", -cursor, 0)
        label:SetWidth(column[2])
        label:SetText(column[1])
        column.offset = cursor
        cursor = cursor + column[2] + 6
    end
    headerName:SetPoint("RIGHT", -cursor, 0)
    local crafterList = virtualList(detail, 22, function(content)
        local row = CreateFrame("Button", nil, content)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetSize(16, 16)
        row.classIcon:SetPoint("LEFT", 2, 0)
        row.name = text(row, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 22, 0)
        row.name:SetPoint("RIGHT", -cursor, 0)
        row.cells = {}
        for position, column in ipairs(CRAFTER_COLUMNS) do
            local label = text(row, "GameFontHighlightSmall")
            label:SetPoint("RIGHT", -column.offset, 0)
            label:SetWidth(column[2])
            row.cells[position] = label
        end
        local function smallFont(control)
            control:SetNormalFontObject(GameFontNormalSmall)
            control:SetHighlightFontObject(GameFontHighlightSmall)
            control:SetDisabledFontObject(GameFontDisableSmall)
            control:SetHeight(20)
        end
        row.order = ctx.button(row, L["Place order"], orderWidth, 0, 0, function(self)
            local crafterEntry = self:GetParent().crafter
            if crafterEntry then ctx.order(crafterEntry.recipe, crafterEntry.name, crafterEntry.professionID) end
        end)
        row.order:ClearAllPoints()
        row.order:SetPoint("RIGHT", -2, 0)
        smallFont(row.order)
        row.whisper = ctx.button(row, L["Whisper#2"], whisperWidth, 0, 0, function(self)
            local crafterEntry = self:GetParent().crafter
            local member = crafterEntry and ctx.member(crafterEntry.name)
            if member and ChatFrame_SendTell then ChatFrame_SendTell(member.target or crafterEntry.name) end
        end)
        row.whisper:ClearAllPoints()
        row.whisper:SetPoint("RIGHT", row.order, "LEFT", -4, 0)
        smallFont(row.whisper)
        row:SetScript("OnEnter", function(self)
            local entry = self.crafter
            if not entry then return end
            local member = ctx.member(entry.name)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(ctx.displayName(entry.name))
            if member and member.className then
                GameTooltip:AddLine(("%s %s"):format(member.level and (L["Level"] .. " " .. member.level) or "",
                    member.className), 1, 1, 1)
            end
            GameTooltip:AddLine(("%s  %s"):format(ctx.professionName(entry.professionID),
                entry.skill and ("%d/%d"):format(entry.skill, entry.maximum or entry.skill) or ""), 1, 1, 1)
            GameTooltip:AddLine(ctx.recipeName(entry.recipe), GOLD[1], GOLD[2], GOLD[3])
            if entry.own then
                GameTooltip:AddLine(L["Your own profession data."], .8, .8, .8, true)
            elseif entry.updated then
                GameTooltip:AddLine(L["Recipes last synced: %s"]:format(date("%d.%m.%Y %H:%M", entry.updated)), .8, .8, .8, true)
            end
            if member and member.zone and member.online then GameTooltip:AddLine(member.zone, .8, .8, .8) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, entry)
        row.crafter = entry
        local member = ctx.member(entry.name)
        local class = member and member.class
        local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            row.classIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            row.classIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            row.classIcon:Show()
        else
            row.classIcon:Hide()
        end
        local level = member and member.level
        row.name:SetText(ctx.displayName(entry.name) .. (level and ("  |cffb8ad99%d|r"):format(level) or ""))
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if entry.online then
            if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
        else
            row.name:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        end
        row.cells[1]:SetText(entry.skill and ("%d/%d"):format(entry.skill, entry.maximum or entry.skill) or "–")
        row.cells[2]:SetText(entry.online and L["Online"] or L["Offline"])
        if entry.online then row.cells[2]:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        else row.cells[2]:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end
        local stale = entry.updated and time() - entry.updated > STALE
        row.cells[3]:SetText(entry.own and L["Current"] or formatDate(entry.updated))
        if stale then row.cells[3]:SetTextColor(1, .55, .25) else row.cells[3]:SetTextColor(.92, .88, .80) end
        local own = entry.name == ctx.player()
        row.whisper:SetEnabled(entry.online and not own and ChatFrame_SendTell ~= nil)
        row.order:SetEnabled(not own and not ctx.inCombat())
    end)
    crafterList.scroll:SetPoint("TOPLEFT", 316, -52)
    crafterList.scroll:SetPoint("BOTTOMRIGHT", -32, 10)

    local function showDetail(group)
        detail:SetShown(group ~= nil)
        anchorResults()
        if not group then return end
        hero.group = group
        detail.group = group
        compareText:SetText(finder.comparisonText(group) or "")
        heroIcon:SetTexture(group.icon or 134400)
        heroName:SetText(group.name)
        heroName:SetTextColor(qualityColor(group.quality))
        local professions = {}
        for professionID in pairs(group.professions) do professions[#professions + 1] = ctx.professionName(professionID) end
        table.sort(professions)
        local rarity = group.quality and _G["ITEM_QUALITY" .. group.quality .. "_DESC"]
        heroSub:SetText(table.concat(professions, ", ") .. (rarity and ("  ·  " .. rarity) or ""))
        local lines = {}
        if group.skill then lines[#lines + 1] = L["Required skill: %d"]:format(group.skill) end
        if group.level then lines[#lines + 1] = L["Required level: %d"]:format(group.level) end
        if group.itemLevel then lines[#lines + 1] = L["Item level: %d"]:format(group.itemLevel) end
        lines[#lines + 1] = finder.label(group.top) .. " › " .. finder.label(group.top, group.sub)
            .. (group.slot and group.top == "armor" and (" › " .. slotLabel(group.slot)) or "")
        facts:SetText(table.concat(lines, "   ·   "))
        local entries = {}
        for _, recipe in ipairs(group.recipes) do
            local skill = addon.recipeSkills and addon.recipeSkills[recipe]
            entries[#entries + 1] = { recipe = recipe, text = ctx.recipeName(recipe) .. (skill and ("  (%d)"):format(skill) or "") }
            for _, material in ipairs(ctx.materialRows(recipe, 1)) do
                entries[#entries + 1] = { itemID = material.itemID, text = "   " .. material.text }
            end
        end
        if #group.recipes > 1 then
            materialsTitle:SetText(L["%d recipe variants and materials"]:format(#group.recipes))
        else
            materialsTitle:SetText(L["Recipes and materials"])
        end
        materials.set(entries, true)
        if group.crafterCount == 0 then
            crafterTitle:SetText("|cffffc060" .. L["No known crafter"] .. "|r")
        else
            crafterTitle:SetText(L["Crafters: %d  ·  online: %d"]:format(group.crafterCount, group.onlineCount))
        end
        crafterList.set(group.crafterList, true)
    end

    -- Tree data -------------------------------------------------------------------------
    local function treeNodes(counts)
        local nodes = {}
        local category = filters.category
        nodes[1] = { id = "all", label = L["All categories"], depth = 0, count = counts.all or 0,
            active = not category.top }
        for _, branch in ipairs(TREE) do
            local top = branch[1]
            local topCount = counts[top] or 0
            nodes[#nodes + 1] = { id = top, top = top, label = finder.label(top), depth = 0, count = topCount,
                children = true, active = category.top == top and not category.sub }
            if expanded[top] then
                for _, sub in ipairs(branch[2]) do
                    local subKey = top .. "/" .. sub
                    local count = counts[subKey] or 0
                    if sub ~= "other" or count > 0 then
                        local slotted = top == "armor" and SLOTTED[sub] and count > 0
                        nodes[#nodes + 1] = { id = subKey, top = top, sub = sub, label = finder.label(top, sub),
                            depth = 1, count = count, children = slotted or nil,
                            active = category.top == top and category.sub == sub and not category.slot }
                        if slotted and expanded[subKey] then
                            for _, slotKey in ipairs(ARMOR_SLOTS) do
                                local slotCount = counts[subKey .. "/" .. slotKey] or 0
                                if slotKey ~= "other" or slotCount > 0 then
                                    nodes[#nodes + 1] = { id = subKey .. "/" .. slotKey, top = top, sub = sub,
                                        slot = slotKey, label = slotLabel(slotKey), depth = 2, count = slotCount,
                                        active = category.top == top and category.sub == sub and category.slot == slotKey }
                                end
                            end
                        end
                    end
                end
            end
        end
        return nodes
    end

    function view.refresh(resetScroll)
        if not view:IsShown() then return end
        local counts, unknown, total, info
        results, counts, unknown, total, info = finder.query(ctx, filters, sortKey, descending)
        activeText:SetText(finder.activeFilters(filters, ctx))
        view.flowFilters()
        tree.set(treeNodes(counts), false)
        for key, control in pairs(headerButtons) do
            local title = key == "name" and L["Item"] or control.title
            if key == sortKey then title = title .. (descending and " v" or " ^") end
            control.label:SetText(title)
        end
        resultList.set(results, resetScroll)
        local selectedGroup
        for _, group in ipairs(results) do
            if group.key == selectedKey then selectedGroup = group end
        end
        if not selectedGroup then selectedKey = nil end
        showDetail(selectedGroup)
        if #results == 0 then
            if total == 0 then
                emptyText:SetText(L["No synced recipes yet. Guild members share their recipes when they open their professions with ForeverGuild."])
            elseif #unknown > 0 then
                emptyText:SetText(L["No recipe matches “%s”."]:format(table.concat(unknown, " ")))
            else
                emptyText:SetText(L["No guild member with synced data knows a matching recipe."])
            end
        end
        emptyText:SetShown(#results == 0)
        local withData, without = ctx.dataCoverage()
        local status = L["%d results · %d recipes indexed · %d members with profession data"]:format(#results, total, withData)
        if without > 0 then
            status = status .. "  ·  " .. L["%d without synced data (not counted as unable to craft)"]:format(without)
        end
        if info.pending > 0 then
            status = L["Loading item data …"] .. "  ·  " .. status
        end
        if info.unresolved > 0 and not filters.showUnresolved then
            status = status .. "  ·  " .. L["%d recipe records incomplete (hidden)"]:format(info.unresolved)
        end
        if info.noStats > 0 then
            status = status .. "  ·  " .. L["%d without loaded attributes"]:format(info.noStats)
        end
        if info.bindUnknown > 0 then
            status = status .. "  ·  " .. L["%d still checking whether they can be handed over"]:format(info.bindUnknown)
        end
        statusText:SetText(status)
    end

    function view.reset()
        filters = freshFilters()
        for _, row in ipairs(attributeRows) do row.id = nil; row.box:SetText(""); row.shown = row == attributeRows[1] end
        search:SetText("")
        for _, box in pairs(numbers) do box:SetText("") end
        selectedKey = nil
        for _, control in ipairs(dropdowns) do control.Sync() end
        view.refresh(true)
    end

    view:SetScript("OnShow", function()
        for _, control in ipairs(dropdowns) do control.Sync() end
    end)
    view.search = search
    view.tree = treePanel
    view.filterPanel = filterPanel
    view.results = resultPanel
    return view
end

-- Trade status of a recipe group: TRADEABLE, NON_TRADEABLE, UNKNOWN or SERVICE. The crafted
-- item decides, never the recipe item; without an output only enchantments count as service.
function finder.tradeStatusOf(itemID, top)
    if itemID then
        if not addon.itemStats then return "UNKNOWN", "no item stats module" end
        return addon.itemStats.bindStatus(itemID)
    end
    if top == "enchant" then return "SERVICE", "enchantment without crafted item" end
    return "UNKNOWN", "no crafted item known"
end

function finder.groupTradeStatus(group, ctx)
    if not group.trade then
        group.trade, group.tradeReason = finder.tradeStatusOf(group.itemID, group.top)
        if group.trade == "UNKNOWN" and group.itemID and ctx and ctx.requestItem then ctx.requestItem(group.itemID) end
    end
    local status = group.trade
    if status == "UNKNOWN" then group.trade = nil end
    return status, group.tradeReason
end

-- Same decision for a single recipe (order dialog, incoming orders).
function finder.recipeTradeStatus(recipe, professionID, ctx)
    local meta = describeRecipe(recipe, professionID, ctx)
    return finder.tradeStatusOf(meta.itemID, meta.top), meta
end

function finder.diagnose(recipe, professionID, ctx)
    local meta = describeRecipe(recipe, professionID, ctx)
    local getInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    local bindType = meta.itemID and getInfo and select(14, getInfo(meta.itemID))
    local status, reason = finder.tradeStatusOf(meta.itemID, meta.top)
    return ("recipe/spell %d · output item %s · category %s · bindType %s · %s (%s)"):format(recipe,
        tostring(meta.itemID), tostring(meta.top), tostring(bindType), status, tostring(reason))
end

function finder.number(value)
    if value % 1 == 0 then return tostring(value) end
    return ("%.1f"):format(value)
end

-- Value column: weighted score difference, else the sum of the selected attribute
-- differences; nil when nothing can be compared.
function finder.comparisonValue(group, filters)
    local stats = addon.itemStats
    if not stats or not group.itemID or not stats.slots[group.equipLoc or ""] then return nil end
    local comparison = group.comparison or stats.compare(group.itemID, group.equipLoc)
    group.comparison = comparison
    if not comparison then return nil end
    if comparison.score then return comparison.score end
    if filters and filters.attrs and #filters.attrs > 0 then
        local total = 0
        for _, rule in ipairs(filters.attrs) do total = total + (comparison.diff[rule.id] or 0) end
        return total
    end
    return nil
end

function finder.comparisonText(group)
    local stats = addon.itemStats
    if not stats or not group.itemID or not stats.slots[group.equipLoc or ""] then return nil end
    local comparison = stats.compare(group.itemID, group.equipLoc)
    if not comparison then return L["Comparison: item data not loaded yet."] end
    local parts = {}
    for _, attribute in ipairs(stats.attributes) do
        local diff = comparison.diff[attribute.id]
        if diff and diff ~= 0 then
            parts[#parts + 1] = ("%s %s%s|r"):format(stats.label(attribute.id), diff > 0 and "|cff59dc59+" or "|cffff6655",
                finder.number(diff))
        end
    end
    local head = comparison.empty and L["Compared with an empty slot:"] or L["Compared with equipped:"]
    if #parts == 0 then return head .. " " .. L["no attribute difference"] end
    local line = head .. " " .. table.concat(parts, " · ")
    if comparison.score then line = line .. "\n" .. L["Weighted score: %s"]:format((comparison.score > 0 and "+" or "") .. finder.number(comparison.score)) end
    return line
end

function finder.activeFilters(filters, ctx)
    local parts = {}
    local category = filters.category or {}
    if category.top then parts[#parts + 1] = finder.label(category.top, category.sub, category.slot) end
    if filters.profession then parts[#parts + 1] = ctx.professionName(filters.profession) end
    if filters.armorClass then parts[#parts + 1] = finder.label("armor", filters.armorClass) end
    if filters.slot then parts[#parts + 1] = slotLabel(filters.slot) end
    if filters.quality then parts[#parts + 1] = _G["ITEM_QUALITY" .. filters.quality .. "_DESC"] or tostring(filters.quality) end
    if filters.levelMin or filters.levelMax then
        parts[#parts + 1] = L["Level"] .. " " .. (filters.levelMin or "1") .. "–" .. (filters.levelMax or "60")
    end
    if filters.usable then parts[#parts + 1] = L["Usable by my character"] end
    if filters.levelMode == "now" then parts[#parts + 1] = L["Usable at my current level"] end
    for _, rule in ipairs(filters.attrs or {}) do
        parts[#parts + 1] = addon.itemStats.label(rule.id) .. (rule.min and (" " .. L["at least"] .. " " .. rule.min) or "")
    end
    if filters.better == "ilvl" then parts[#parts + 1] = L["Higher item level than equipped"]
    elseif filters.better == "attrs" then parts[#parts + 1] = L["Improves the selected attributes"]
    elseif filters.better == "score" then parts[#parts + 1] = L["Higher weighted score"] end
    if filters.online then parts[#parts + 1] = filters.online == "online" and L["Crafter online"] or L["Only offline crafters"] end
    if #parts == 0 then return "" end
    return L["Active filters: "] .. table.concat(parts, " · ")
end

-- Shared building blocks for the crafting marketplace (MarketUI.lua).
function finder.recipeCategory(recipe, professionID, ctx)
    return describeRecipe(recipe, professionID, ctx).top
end
function finder.topCategories()
    local list = {}
    for _, node in ipairs(TREE) do list[#list + 1] = node[1] end
    return list
end
finder.widgets = { virtualList = virtualList, text = text, dropdown = dropdown, numberBox = numberBox,
    tooltipFor = tooltipFor, qualityColor = qualityColor }
