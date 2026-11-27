-- Tests for BankData.lua with GuildBank.lua (pure logic, client API mocked like the Forever
-- client: item functions only in C_Item).
-- Usage: lua tools/test_bank.lua   (from the repository root)
local fails = 0
local function check(label, got, want)
    if got ~= want then fails = fails + 1; print(("FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
    else print("ok   " .. label) end
end
local now = 1800000000
_G.GetServerTime = function() return now end
_G.UnitFactionGroup = function() return "Horde" end
_G.GetLocale = function() return "deDE" end
local items = {
    [4339] = { "Magiestoffballen", 1, 7, 5 }, [14047] = { "Runenstoff", 1, 7, 5 }, [16204] = { "Leuchtender Illusionsstaub", 2, 7, 12 },
    [1000] = { "Kettenhelm", 2, 4, 3 }, [2000] = { "Runenstofftasche", 2, 1, 0 }, [3000] = { "Muster: Schwarze Kordel", 3, 9, 2 },
    [4000] = { "Elementarfeuer", 1, 7, 10 }, [5000] = { "Arkanitbarren", 2, 7, 7 }, [6000] = { "Großer Heiltrank", 1, 0, 1 },
    [7000] = { "Klinge", 3, 2, 7 }, [8000] = { "Sternschnuppe", 1, 15, 0 }, [9000] = { "Schwere Sprengladung", 1, 7, 2 },
}
_G.C_Item = {
    GetItemInfo = function(key)
        local id = tonumber(tostring(key):match("item:(%d+)")) or key
        local row = items[id]
        if not row then return nil end
        return row[1], "|cff|Hitem:" .. id .. "|h[" .. row[1] .. "]|h|r", row[2], 1, 1, nil, nil, 20, "", 1, 0
    end,
    GetItemInfoInstant = function(id)
        local row = items[id]
        if not row then return id end
        return id, nil, nil, "", 1, row[3], row[4]
    end,
}
_G.ForeverGuildBankCache, _G.ForeverGuildBankGold, _G.ForeverGuildSettings = {}, {}, {}
local addon = {}
for _, file in ipairs({ "Locale.lua", "GuildBank.lua", "BankData.lua" }) do assert(loadfile("ForeverGuild/" .. file))("ForeverGuild", addon) end
local D, B, G = addon.bankData, addon.guildBank, "Gilde"
local key = UnitFactionGroup("player") .. ":" .. G
local function link(id, enchant, suffix)
    return ("|cffffffff|Hitem:%d:%s:0:0:0:0:%s:0|h[x]|h|r"):format(id, enchant or "0", suffix or "0")
end
ForeverGuildBankCache[key] = {
    [1] = { name = "Stoffe", items = { { link = link(14047), quantity = 20 }, { link = link(14047), quantity = 20 },
        { link = link(4339), quantity = 12 } }, at = now - 100 },
    [2] = { name = "Sonstiges", items = { { link = link(14047), quantity = 17 }, { link = link(1000), quantity = 1 },
        { link = link(1000, "1887"), quantity = 1 }, { link = link(7000, "0", "1234"), quantity = 1 }, { link = link(7000), quantity = 1 } },
        at = now - 50 },
}
local stacks = D.stacks(G)
check("all real stacks kept", #stacks, 8)
local merged, byKey = D.merge(stacks)
check("identical items combined", byKey["14047"].quantity, 57)
check("amount per bank tab kept", byKey["14047"].tabs[1] == 40 and byKey["14047"].tabs[2] == 17, true)
check("enchanted variant stays separate", byKey["1000:e1887"] ~= nil and byKey["1000"].quantity == 1, true)
check("random suffix stays separate", byKey["7000:s1234"] ~= nil and byKey["7000"].quantity == 1, true)
check("distinct variants", #merged, 6)
check("vault data unchanged", #ForeverGuildBankCache[key][1].items, 3)

-- Categories from the client's item classes.
local want = { [14047] = "cloth", [16204] = "enchanting", [1000] = "armor", [2000] = "bags", [3000] = "recipes",
    [4000] = "elemental", [5000] = "metal", [6000] = "consumables", [7000] = "weapons", [8000] = "misc", [9000] = "components",
    [999999] = "misc" }
for id, category in pairs(want) do check("category of " .. id, D.categorize(id), category) end
check("13 categories", #D.categories, 13)

-- Newer guild snapshot is shown; an older one does not replace it.
local name = ("Stoffe"):gsub(".", function(c) return ("%02x"):format(c:byte()) end)
B.receive(G, "Bert", ("B:1:%d:%d:1:2:%s"):format(now, now - 10, name))
B.receive(G, "Bert", ("B:1:%d:%d:2:2:%s"):format(now, now - 10, "14047:60"))
local tab1
for _, tab in ipairs(D.tabs(G)) do if tab.index == 1 then tab1 = tab end end
check("newer guild snapshot shown", tab1.sender == "Bert" and tab1.items[1].quantity == 60, true)
check("older snapshot ignored", B.receive(G, "Cora", ("B:1:%d:%d:1:1:%s"):format(now, now - 500, name)), nil)
check("settings default: combine", D.setting("merge"), true)
D.set("merge", false)
check("setting saved", ForeverGuildSettings.guildBank.merge, false)

print(fails == 0 and "\nALL OK" or ("\n%d FAILED"):format(fails))
os.exit(fails == 0 and 0 or 1)
