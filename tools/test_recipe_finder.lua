-- Regression tests for the guild recipe search (RecipeFinder.lua) without a game client.
-- Run from the repository root: lua tools/test_recipe_finder.lua
local failures = 0
local function check(name, condition)
    print((condition and "ok   " or "FAIL ") .. name)
    if not condition then failures = failures + 1 end
end

-- Item data: id -> name, quality, itemLevel, requiredLevel, bindType, equipLoc, classID, subclassID
local items = {
    [100] = { "Glänzende Fesseln", 3, 52, 47, 2, "INVTYPE_WRIST", 4, 1 },
    [101] = { "Runenstofftasche", 2, 55, 0, 2, "INVTYPE_BAG", 1, 0 },
    [102] = { "Großer Heiltrank", 1, 31, 21, 0, "", 0, 1 },
    [103] = { "Arkanitschnitter", 4, 63, 58, 1, "INVTYPE_2HWEAPON", 2, 1 },
    [104] = { "Großschwert der Wut", 3, 50, 45, 2, "INVTYPE_2HWEAPON", 2, 8 },
    [105] = { "Lederhandschuhe", 2, 20, 15, 2, "INVTYPE_HAND", 4, 2 },
}
_G.C_Item = {
    GetItemInfo = function(id)
        local item = items[id]
        if not item then return nil end
        return item[1], nil, item[2], item[3], item[4], nil, nil, nil, item[6], nil, nil, item[7], item[8], item[5]
    end,
    GetItemInfoInstant = function(id)
        local item = items[id]
        if not item then return nil end
        return id, nil, nil, item[6], 1000 + id, item[7], item[8]
    end,
    GetItemSubClassInfo = function(classID, subclassID) return "sub" .. classID .. "-" .. subclassID end,
}
_G.INVTYPE_WRIST, _G.INVTYPE_HAND = "Handgelenke", "Hände"

local addon = { L = setmetatable({}, { __index = function(_, key) return key end }) }
addon.recipeSkills = { [1] = 275, [2] = 260, [3] = 215, [4] = 300, [6] = 200 }
assert(loadfile("ForeverGuild/RecipeFinder.lua"))("ForeverGuild", addon)
local itemStats = { [100] = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 40 },
    [104] = { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 41.5 }, [105] = {} }
_G.C_Item.GetItemStats = function(link)
    return itemStats[tonumber(tostring(link):match("item:(%d+)"))]
end
-- Hidden scan tooltip: first line is the item name, second the binding line of its bind type.
_G.ITEM_BIND_ON_PICKUP, _G.ITEM_BIND_ON_EQUIP = "Wird beim Aufheben gebunden", "Wird beim Anlegen gebunden"
local tooltipItem
local bindLines = { [1] = _G.ITEM_BIND_ON_PICKUP, [2] = _G.ITEM_BIND_ON_EQUIP }
local function line(index)
    return { GetText = function()
        local item = tooltipItem and items[tooltipItem]
        if not item then return nil end
        if index == 1 then return item[1] end
        return bindLines[item.tooltipBind or item[5]]
    end, IsShown = function() return true end, GetTextColor = function() return 1, 1, 1 end }
end
_G.ForeverGuildScanTooltipTextLeft1, _G.ForeverGuildScanTooltipTextLeft2 = line(1), line(2)
_G.UIParent = {}
_G.CreateFrame = function()
    return { SetOwner = function() end, ClearLines = function() end, Hide = function() end,
        SetHyperlink = function(_, link) tooltipItem = tonumber(link:match("item:(%d+)")) end,
        NumLines = function() return tooltipItem and items[tooltipItem] and 2 or 0 end }
end
assert(loadfile("ForeverGuild/ItemStats.lua"))("ForeverGuild", addon)
local finder = addon.recipeFinder

-- recipe -> outputID, enchantSlot
local outputs = { [1] = 100, [2] = 101, [3] = 102, [4] = 103, [5] = 101, [6] = 104, [7] = nil, [8] = 105 }
local slots = { [7] = "Bracer" }
local recipeNames = { [1] = "Glänzende Fesseln", [2] = "Runenstofftasche", [3] = "Großer Heiltrank",
    [4] = "Arkanitschnitter", [5] = "Runenstofftasche (Variante)", [6] = "Großschwert der Wut",
    [7] = "Armschiene - Große Stärke", [8] = "Lederhandschuhe" }
local professionNames = { [197] = "Schneiderei", [171] = "Alchemie", [164] = "Schmiedekunst",
    [333] = "Verzauberkunst", [165] = "Lederverarbeitung" }
local function set(...)
    local result = {}
    for index = 1, select("#", ...) do result[select(index, ...)] = true end
    return result
end
local database = {
    ["Anna-Realm"] = { updated = 1, professions = { [197] = { skill = 300, maximum = 300, recipes = set(1, 2) } } },
    ["Bert-Realm"] = { updated = 2, professions = { [197] = { skill = 280, maximum = 300, recipes = set(2, 5) },
        [333] = { skill = 290, maximum = 300, recipes = set(7) } } },
    ["Cara-Realm"] = { updated = 3, professions = { [171] = { skill = 250, maximum = 300, recipes = set(3) } } },
    ["Dirk-Realm"] = { updated = 4, professions = { [164] = { skill = 300, maximum = 300, recipes = set(4, 6) } } },
    ["Gone-Realm"] = { updated = 5, professions = { [165] = { skill = 300, maximum = 300, recipes = set(8) } } },
}
local roster = { ["Anna-Realm"] = { online = true }, ["Bert-Realm"] = { online = false },
    ["Cara-Realm"] = { online = false }, ["Dirk-Realm"] = { online = true } }
local ctx = {
    source = function() return database end,
    profiles = function() return database end,
    isMember = function(name) return roster[name] ~= nil end,
    isOnline = function(name) return roster[name] ~= nil and roster[name].online end,
    recipeDetails = function(id) return "spell:" .. id, outputs[id], slots[id] end,
    recipeName = function(id) return recipeNames[id] end,
    professionName = function(id) return professionNames[id] or tostring(id) end,
    professionIcon = function() return 1 end,
}

local function search(filters)
    local results, counts, unknown = finder.query(ctx, filters, "name", false)
    local names = {}
    for _, group in ipairs(results) do names[#names + 1] = group.name end
    return results, names, counts, unknown
end
local function has(names, value)
    for _, name in ipairs(names) do if name == value then return true end end
    return false
end

local results, names = search({ text = "schneider armschienen" })
check("tailor + bracers finds cloth bracers without the word in the name", #results == 1 and names[1] == "Glänzende Fesseln")
_, names = search({ text = "Schneiderei Handgelenke" })
check("profession + slot name", #names == 1 and names[1] == "Glänzende Fesseln")
_, names = search({ text = "stoff armschienen" })
check("material + slot synonym", #names == 1 and names[1] == "Glänzende Fesseln")
_, names = search({ text = "alchi heiltrank" })
check("abbreviation + partial item name", #names == 1 and names[1] == "Großer Heiltrank")
_, names = search({ text = "schmied zweihandschwert" })
check("compound synonym (two-hand + sword)", #names == 1 and names[1] == "Großschwert der Wut")
_, names = search({ text = "schmied zweihand" })
check("two-hand search lists only the tradeable sword (axe is bind on pickup)", #names == 1 and names[1] == "Großschwert der Wut")
_, names = search({ text = "vz armschienen" })
check("enchant without item is found by slot", #names == 1 and names[1] == "Armschiene - Große Stärke")
local _, _, _, unknown = search({ text = "schneider xyzzy" })
check("unknown term is reported and not ignored", #search({ text = "schneider xyzzy" }) == 0 and unknown[1] == "xyzzy")
_, names = search({ text = "runenstofftasche" })
check("item search by name", #names == 1)
results = search({ text = "tasche" })
check("variants merge into one item", #results == 1 and #results[1].recipes == 2 and results[1].crafterCount == 2)
check("online count per item", results[1].onlineCount == 1)
_, names = search({ text = "lederhandschuhe" })
check("former guild member is not listed as crafter", #names == 0)
_, names = search({ category = { top = "armor", sub = "cloth", slot = "WRIST" } })
check("category path armor/cloth/wrist", #names == 1)
local _, _, counts = search({})
check("category counts exclude bind-on-pickup items", counts.armor == 1 and counts.weapon == 1
    and counts["armor/cloth/WRIST"] == 1 and counts.all == 5)
_, names = search({ profession = 197, quality = 3 })
check("profession + quality filter", #names == 1 and names[1] == "Glänzende Fesseln")
_, names = search({ levelMin = 45, levelMax = 60 })
check("level range filter", #names == 2)
_, names = search({ skillMax = 260 })
check("skill filter hides unknown skill", has(names, "Runenstofftasche") and has(names, "Großer Heiltrank")
    and not has(names, "Armschiene - Große Stärke"))
_, names = search({ online = "offline" })
check("offline-only filter", #names == 2 and has(names, "Großer Heiltrank"))
_, names = search({ crafter = "Bert-Realm" })
check("crafter filter", #names == 2)
_, names = search({ bind = "bop" })
check("an old binding filter value cannot show bind-on-pickup items", #names == 6 - 1 or not has(names, "Arkanitschnitter"))
results = search({ text = "tasche" })
local crafters = finder.crafters(results[1], ctx)
check("online crafters first", crafters[1].name == "Anna-Realm")

-- Newly learned recipe after invalidation
database["Cara-Realm"].professions[171].recipes[9] = true
outputs[9], recipeNames[9] = 102, "Großer Heiltrank (neu)"
finder.invalidate()
results = search({ text = "heiltrank" })
check("new recipe joins the item after invalidate", #results == 1 and #results[1].recipes == 2)

-- Attributes: free text, comparisons and the attribute filter (unknown stats never count as 0)
_, names = search({ text = "stärke" })
check("attribute word finds items with strength", has(names, "Glänzende Fesseln") and has(names, "Großschwert der Wut")
    and not has(names, "Großer Heiltrank"))
_, names = search({ text = "stärke>=15" })
check("structured attribute comparison", #names == 1 and names[1] == "Großschwert der Wut")
_, names = search({ text = "lvl>=46 str" })
check("level comparison combined with attribute", #names == 1 and names[1] == "Glänzende Fesseln")
_, names = search({ attrs = { { id = "str", min = 15 } } })
check("attribute filter with minimum", #names == 1 and names[1] == "Großschwert der Wut")
_, names = search({ attrs = { { id = "agi" }, { id = "sta" } }, attrMode = "any" })
check("any-of attribute filter", #names == 1 and names[1] == "Glänzende Fesseln")
_, names = search({ attrs = { { id = "agi" }, { id = "sta" } } })
check("all-of attribute filter", #names == 0)
_, names = search({ armorClass = "cloth" })
check("armor class filter", #names == 1 and names[1] == "Glänzende Fesseln")

-- Unresolved recipe IDs are hidden by default, available on demand
database["Cara-Realm"].professions[171].recipes[1252979] = true
slots[1252979] = "Cloak"
finder.invalidate()
local _, info
results, _, _, _, info = finder.query(ctx, {}, "name", false)
local found = false
for _, group in ipairs(results) do if group.name == nil or group.name:match("^#") then found = true end end
check("unresolved recipe hidden", not found)
_, _, _, _, info = finder.query(ctx, {}, "name", false)
check("unresolved recipe counted", info.unresolved == 1)
results = finder.query(ctx, { showUnresolved = true }, "name", false)
check("unresolved recipe on demand", #results >= 1)
recipeNames[1252979] = "Neues Rezept"
finder.invalidateItems()
_, names = search({ text = "neues rezept" })
check("name arriving later resolves the entry", #names == 1)

-- Order picker: confirmed recipes without crafter are optional
ctx.catalogRecipes = function() return { [3] = 171, [11] = 197 } end
outputs[11], recipeNames[11] = nil, "Katalogrezept"
slots[11] = "Boots"
finder.invalidate()
_, names = search({ text = "katalogrezept" })
check("catalog recipe hidden without option", #names == 0)
_, names = search({ text = "katalogrezept", includeUncrafted = true })
check("catalog recipe without crafter selectable", #names == 1)
ctx.catalogRecipes = nil
finder.invalidate()

-- Orderability: bind-on-pickup outputs are never listed, whatever the filters say.
_, names = search({ text = "arkanitschnitter" })
check("bind-on-pickup item excluded", #names == 0)
_, names = search({ text = "arkanitschnitter", includeUncrafted = true, showUnresolved = true })
check("options cannot bypass the exclusion", #names == 0)
_, names = search({ text = "fesseln" })
check("bind-on-equip bracers stay visible", #names == 1)
_, names = search({ text = "runenstofftasche" })
check("bags stay visible", #names == 1)
_, names = search({ text = "große stärke" })
check("enchantment without item counts as service", #names == 1)
-- Structured data says tradeable but the tooltip shows bind on pickup: not orderable.
items[105].tooltipBind = 1
addon.itemStats.invalidate()
finder.invalidateItems()
_, names = search({ text = "lederhandschuhe" })
check("tooltip bind on pickup wins over the bind type", not has(names, "Lederhandschuhe"))
items[105].tooltipBind = nil
addon.itemStats.invalidate()
-- Unloaded tooltip: unknown, hidden until data arrives.
local realLine = _G.ForeverGuildScanTooltipTextLeft1
_G.ForeverGuildScanTooltipTextLeft1 = { GetText = function() return nil end }
addon.itemStats.invalidate()
finder.invalidate()
local _, _, _, _, infoUnknown = finder.query(ctx, { text = "fesseln" }, "name", false)
check("unloaded tooltip is unknown, not tradeable", infoUnknown.bindUnknown >= 1)
_G.ForeverGuildScanTooltipTextLeft1 = realLine
finder.invalidateItems()
finder.query(ctx, {}, "name", false)
_, names = search({ text = "fesseln" })
check("item reappears after its data arrived", #names == 1)

-- Large data set stays fast enough for interactive use
for member = 1, 400 do
    local recipes = {}
    for recipe = 1, 60 do recipes[1000 + (member * 7 + recipe) % 3000] = true end
    database["M" .. member .. "-Realm"] = { updated = 1, professions = { [197] = { skill = 300, maximum = 300, recipes = recipes } } }
    roster["M" .. member .. "-Realm"] = { online = member % 3 == 0 }
end
for id = 1000, 3999 do outputs[id] = nil; recipeNames[id] = "Rezept " .. id end
finder.invalidate()
local started = os.clock()
finder.query(ctx, {}, "name", false)
local build = os.clock() - started
started = os.clock()
for _ = 1, 10 do finder.query(ctx, { text = "rezept 12" }, "crafters", true) end
local perQuery = (os.clock() - started) / 10
print(("     index build %.3fs, query %.3fs (3000 recipes, 400 members)"):format(build, perQuery))
check("large guild query under 0.25s", perQuery < .25)

print(failures == 0 and "\nALL OK" or ("\n" .. failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
