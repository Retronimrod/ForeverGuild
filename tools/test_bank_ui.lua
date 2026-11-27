-- Smoke test for BankUI.lua with the permissive frame mock of test_market_ui.lua: builds the
-- guild bank page, renders the category blocks, filters and the empty states. Item functions
-- exist only in C_Item, as in the Forever client. Layout itself needs the game.
-- Usage: lua tools/test_bank_ui.lua   (from the repository root)
local failures = 0
local function check(name, condition, detail)
    io.write((condition and "ok   " or "FAIL ") .. name .. (detail and not condition and (" – " .. tostring(detail)) or "") .. "\n")
    if not condition then failures = failures + 1 end
end
local source = assert(io.open("tools/test_market_ui.lua", "rb")):read("*a")
local mock = source:match("(local timers = {}.-)\nlocal whispered")
assert(loadstring(mock .. "\n_G.__timers = timers\n_G.__object = object"))()
local timers, object = _G.__timers, _G.__object
local createFrame = _G.CreateFrame
_G.CreateFrame = function(...)
    local frame = createFrame(...)
    local highlight = object("Texture")
    frame.GetHighlightTexture = function() return highlight end
    local setPoint = frame.SetPoint
    frame.SetPoint = function(self, point, relative, relPoint, ...)
        if relative == nil and type(relPoint) == "string" then error("SetPoint to a missing anchor: " .. tostring(point), 2) end
        return setPoint(self, point, relative, relPoint, ...)
    end
    frame.SetupMenu = function(_, generator)
        local root
        root = { CreateRadio = function(_, _, isSelected) isSelected(); return root end, CreateButton = function() return root end,
            CreateTitle = function() end, CreateDivider = function() end, CreateCheckbox = function() end, SetScrollMode = function() end }
        generator(frame, root)
    end
    return frame
end
_G.C_Timer.NewTimer = function(_, fn) timers[#timers + 1] = fn; return { Cancel = function() end } end
_G.CreateColor = function() return {} end
_G.UnitLevel = function() return 52 end
_G.UnitFactionGroup = function() return "Horde" end
_G.tinsert = table.insert
local now = 1800000000
_G.GetServerTime = function() return now end
local items = { [4339] = { "Magiestoffballen", 1, 7, 5 }, [14047] = { "Runenstoff", 1, 7, 5 }, [1000] = { "Kettenhelm", 2, 4, 3 },
    [2000] = { "Runenstofftasche", 2, 1, 0 } }
-- Like the Forever client: item functions only in C_Item.
_G.GetItemInfoInstant, _G.GetItemSubClassInfo = nil, nil
_G.C_Item.GetItemInfo = function(key)
    local id = tonumber(tostring(key):match("item:(%d+)")) or key
    local row = items[id]
    if not row then return nil end
    return row[1], "|cff|Hitem:" .. id .. "|h[" .. row[1] .. "]|h|r", row[2], 1, 1, nil, nil, 20, "", 1, 0
end
_G.C_Item.GetItemInfoInstant = function(id) local row = items[id]; if not row then return id end return id, nil, nil, "", 1, row[3], row[4] end
_G.ForeverGuildSettings, _G.ForeverGuildBankCache, _G.ForeverGuildBankGold = {}, {}, {}
local addon = {}
for _, file in ipairs({ "Locale.lua", "ItemStats.lua", "RecipeFinder.lua", "GuildBank.lua", "BankData.lua", "BankUI.lua", "Settings.lua" }) do
    assert(loadfile("ForeverGuild/" .. file))("ForeverGuild", addon)
end
local UI = addon.bankUI
local G = "Gilde"
local key = "Horde:" .. G
local guild = nil
local requested, settingsOpened = false, false
local ctx = {
    guild = function() return guild end, guildName = function() return "Evoke" end, clock = function() return now end,
    lower = string.lower,
    button = function(parent, label, width, _, _, action)
        local control = CreateFrame("Button", nil, parent); control:SetText(label); control:SetWidth(width); control:SetScript("OnClick", action); return control
    end,
    displayName = function(name) return name end, vaultOpen = function() return false end,
    scanVault = function() return true end, requestSnapshot = function() requested = true end,
    openSettings = function() settingsOpened = true end,
}
local page = CreateFrame("Frame", nil, UIParent)
local view = UI.build(page, ctx)
check("bank page built", view ~= nil and view.focus ~= nil)
-- Without guild and without data: clear hints.
UI.render()
check("not in a guild: hint", view.empty:IsShown() and (view.status:GetText() or "") ~= "")
guild = G
UI.render()
check("no bank data: hint", view.empty:IsShown() and (view.empty:GetText() or ""):find("Gildentresor", 1, true) ~= nil, view.empty:GetText())
check("no gold known", (view.gold:GetText() or ""):find("unbekannt", 1, true) ~= nil, view.gold:GetText())
-- With data.
local function link(id) return ("|cffffffff|Hitem:%d:0:0:0:0:0:0:0|h[x]|h|r"):format(id) end
ForeverGuildBankCache[key] = {
    [1] = { name = "Stoffe", items = { { link = link(14047), quantity = 20 }, { link = link(14047), quantity = 17 }, { link = link(4339), quantity = 12 } }, at = now - 600 },
    [2] = { name = "Ausrüstung", items = { { id = 1000, quantity = 1 }, { id = 2000, quantity = 1 } }, at = now - 300, sender = "Bert" },
}
ForeverGuildBankGold[key] = { copper = 486996, at = now - 600 }
UI.render()
check("gold with coin icons", (view.gold:GetText() or ""):find("UI%-GoldIcon") ~= nil and (view.gold:GetText() or ""):find("48", 1, true) ~= nil, view.gold:GetText())
check("last update shown with source", (view.status:GetText() or ""):find("Bert", 1, true) ~= nil, view.status:GetText())
local shownBlocks = 0
for _, block in ipairs(view.blocks) do if block:IsShown() then shownBlocks = shownBlocks + 1 end end
check("one block per non-empty category (cloth, bags, armor)", shownBlocks == 3, shownBlocks)
local function slotsOf(id)
    local found = {}
    for _, slot in ipairs(view.slots) do if slot:IsShown() and slot.entry and slot.entry.id == id then found[#found + 1] = slot end end
    return found
end
local runecloth = slotsOf(14047)[1]
check("identical items combined", runecloth and runecloth.entry.quantity == 37, runecloth and runecloth.entry.quantity)
check("stack count shown", runecloth and runecloth.count:GetText() == 37)
-- Real stacks when combining is off.
view.merge._state.checked = false
view.merge:Click()
UI.render()
check("real stacks without combining", #slotsOf(14047) == 2, #slotsOf(14047))
view.merge._state.checked = true
view.merge:Click()
-- Filters.
local function visibleSlots()
    local count = 0
    for _, slot in ipairs(view.slots) do if slot:IsShown() then count = count + 1 end end
    return count
end
view.filters = { text = "rune" }
UI.render()
check("search by name", visibleSlots() == 2, visibleSlots())
view.filters = { category = "armor" }
UI.render()
check("category filter", visibleSlots() == 1, visibleSlots())
view.filters = { quality = 2 }
UI.render()
check("quality filter", visibleSlots() == 2, visibleSlots())
view.filters = { text = "gibtsnicht" }
UI.render()
check("no match: hint", view.empty:IsShown() and (view.empty:GetText() or ""):find("Suche", 1, true) ~= nil, view.empty:GetText())
view.filters = {}
UI.render()
runecloth = slotsOf(14047)[1]
check("tooltip opens", pcall(runecloth._state.scripts.OnEnter, runecloth))
-- Sync actions and settings.
view.request:Click()
check("guild snapshot requested", requested)
view.gear:Click()
check("gear opens the settings", settingsOpened)
UI.registerSettings(addon.settingsUI)
check("display settings registered", #addon.settingsUI.byPage.bank == 3, #addon.settingsUI.byPage.bank)
local guard = 0
while #timers > 0 and guard < 200 do guard = guard + 1; table.remove(timers, 1)() end
io.write(failures == 0 and "\nALL TESTS PASSED\n" or ("\n%d FAILURE(S)\n"):format(failures))
os.exit(failures == 0 and 0 or 1)
