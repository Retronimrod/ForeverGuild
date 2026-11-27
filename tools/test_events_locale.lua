-- Checks that every UI text of Groups & events has a German translation and an English text.
-- Usage: lua tools/test_events_locale.lua   (from the repository root)
local fails = 0
local function load(locale)
    _G.GetLocale = function() return locale end
    local addon = {}
    assert(loadfile("ForeverGuild/Locale.lua"))("ForeverGuild", addon)
    return addon.L
end
local de, en = load("deDE"), load("enUS")
-- Same in both languages on purpose.
local same = { Dungeon = true, PvP = true, Quest = true, Details = true, Status = true, DETAILS = true, April = true,
    August = true, September = true, November = true, Mo = true, Fr = true, Sa = true, ["Quest #%d"] = true, ["%s"] = true,
    ["2  Details"] = true, Tank = true, Online = true, Offline = true, Zone = true, ["Coming Soon"] = true, ["COMING SOON"] = true, Name = true, Normal = true, ["Gold: %s · %s"] = true, ["    "] = true, Neutral = true }
local keys, seen = {}, {}
for _, file in ipairs({ "ForeverGuild/Events.lua", "ForeverGuild/EventsUI.lua", "ForeverGuild/EventWizard.lua",
    "ForeverGuild/BankData.lua", "ForeverGuild/BankUI.lua" }) do
    local source = assert(io.open(file, "rb")):read("*a")
    for key in source:gmatch('L%["(.-)"%]') do
        if not seen[key] and not key:find('"', 1, true) then seen[key] = true; keys[#keys + 1] = key end
    end
    -- Labels passed to L[] through tables.
    for key in source:gmatch('label = "(.-)"') do if not seen[key] then seen[key] = true; keys[#keys + 1] = key end end
    for key in source:gmatch('desc = "(.-)"') do if not seen[key] then seen[key] = true; keys[#keys + 1] = key end end
end
for _, key in ipairs({ "ROLE_ONE_T", "ROLE_ONE_H", "ROLE_ONE_D", "ROLE_MANY_T", "ROLE_MANY_H", "ROLE_MANY_D", "TIME_FORMAT",
    "DATE_LONG", "TOUR_T_CALENDAR", "TOUR_CALENDAR", "Signed up", "Waitlist", "Withdrawn", "Declined", "Tentative",
    "Expired", "Cancelled", "Completed", "Sign-up open" }) do
    keys[#keys + 1] = key
end
for _, key in ipairs(keys) do
    if de[key] == key and not same[key] then fails = fails + 1; print("no German text: " .. key) end
    if key:find("_", 1, true) and key:match("^[A-Z_]+$") and en[key] == key then fails = fails + 1; print("no English text: " .. key) end
    -- Format placeholders must match.
    local function count(text) return select(2, text:gsub("%%[ds]", "")) end
    if count(de[key]) ~= count(key) and not key:match("^[A-Z_]+$") then
        fails = fails + 1; print("placeholder mismatch: " .. key)
    end
end
print(("%d keys checked"):format(#keys))
print(fails == 0 and "ALL OK" or ("%d FAILED"):format(fails))
os.exit(fails == 0 and 0 or 1)
