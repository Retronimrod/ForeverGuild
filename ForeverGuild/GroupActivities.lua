local _, addon = ...
-- Central dungeon database of ForeverGuild (WoW Forever, client 1.60).
-- Source of names (German), level ranges and order: the original WoW Forever group finder,
-- captured in game by the guild (2026-11-27). The position in this list is the sort order.
--
-- Array fields (kept for compatibility): { German name, English name, German zone,
-- English zone, level text, numeric ID }. Named fields: key (stable text ID), min, max,
-- sort, parent and wing (dungeon complex), art (banner number Art/DungeonNN.tga).
-- Numeric IDs are part of the guild message format and never change: dungeons that exist
-- unchanged keep their former ID, the separate wings got new IDs (29-39).
-- English names: the former ForeverGuild names; wings use the Blizzard naming "Complex - Wing".
-- They are not confirmed against an English Forever client (German is binding).
local function entry(sort, key, de, en, deZone, enZone, min, max, id, art, parent, wing)
    return { de, en, deZone, enZone, ("%d–%d"):format(min, max), id, key = key, min = min, max = max, sort = sort,
        art = art or id, parent = parent, wing = wing }
end

addon.groupDungeons = {
    entry(1, "upper_blackrock_spire", "Obere Blackrockspitze", "Upper Blackrock Spire", "Blackrock", "Blackrock Mountain", 59, 60, 29, 23, "blackrock_spire", "upper"),
    entry(2, "scholomance", "Scholomance", "Scholomance", "Westliche Pestländer", "Western Plaguelands", 58, 60, 27),
    entry(3, "stratholme_service", "Stratholme (Dienstbotentor)", "Stratholme - Service Entrance", "Östliche Pestländer", "Eastern Plaguelands", 58, 60, 31, 25, "stratholme", "service"),
    entry(4, "stratholme_main", "Stratholme (Haupttor)", "Stratholme - Main Gate", "Östliche Pestländer", "Eastern Plaguelands", 58, 60, 32, 25, "stratholme", "main"),
    entry(5, "shapers_terrace", "Terrasse des Formers", "Shaper’s Terrace", "Krater von Un’Goro", "Un’Goro Crater", 58, 60, 28),
    entry(6, "dire_maul_north", "Düsterbruch (Nord)", "Dire Maul - North", "Feralas", "Feralas", 56, 60, 33, 24, "dire_maul", "north"),
    entry(7, "dire_maul_west", "Düsterbruch (West)", "Dire Maul - West", "Feralas", "Feralas", 56, 60, 34, 24, "dire_maul", "west"),
    entry(8, "blackmaw_hold", "Schwarzschlundfeste", "Blackmaw Hold", "Azshara", "Azshara", 55, 60, 26),
    entry(9, "lower_blackrock_spire", "Untere Blackrockspitze", "Lower Blackrock Spire", "Blackrock", "Blackrock Mountain", 55, 60, 30, 23, "blackrock_spire", "lower"),
    entry(10, "dire_maul_east", "Düsterbruch (Ost)", "Dire Maul - East", "Feralas", "Feralas", 54, 60, 35, 24, "dire_maul", "east"),
    entry(11, "blackrock_depths", "Blackrocktiefen", "Blackrock Depths", "Blackrock", "Blackrock Mountain", 52, 60, 21),
    entry(12, "sunken_temple", "Versunkener Tempel", "Sunken Temple", "Sümpfe des Elends", "Swamp of Sorrows", 50, 60, 20),
    entry(13, "alcaz_prison", "Gefängnis von Alcaz", "Alcaz Prison", "Marschen von Dustwallow", "Dustwallow Marsh", 48, 55, 22),
    entry(14, "maraudon", "Maraudon", "Maraudon", "Desolace", "Desolace", 46, 55, 19),
    entry(15, "zulfarrak", "Zul'Farrak", "Zul’Farrak", "Tanaris", "Tanaris", 44, 54, 18),
    entry(16, "uldaman", "Uldaman", "Uldaman", "Ödland", "Badlands", 41, 51, 15),
    entry(17, "kroldok_stronghold", "Feste Krol'dok", "Krol’dok Stronghold", "Riverglades", "Riverglades", 40, 47, 17),
    entry(18, "scarlet_cathedral", "Scharlachrote Kathedrale", "Scarlet Monastery - Cathedral", "Tirisfal", "Tirisfal Glades", 38, 46, 36, 13, "scarlet_monastery", "cathedral"),
    entry(19, "razorfen_downs", "Hügel von Razorfen", "Razorfen Downs", "Brachland", "The Barrens", 37, 46, 14),
    entry(20, "scarlet_armory", "Scharlachrote Waffenkammer", "Scarlet Monastery - Armory", "Tirisfal", "Tirisfal Glades", 36, 44, 37, 13, "scarlet_monastery", "armory"),
    entry(21, "drowned_city", "Die Versunkene Stadt", "The Drowned City", "Schlingendorntal", "Stranglethorn Vale", 35, 42, 16),
    entry(22, "scarlet_library", "Scharlachrote Bibliothek", "Scarlet Monastery - Library", "Tirisfal", "Tirisfal Glades", 33, 41, 38, 13, "scarlet_monastery", "library"),
    entry(23, "scarlet_graveyard", "Scharlachroter Friedhof", "Scarlet Monastery - Graveyard", "Tirisfal", "Tirisfal Glades", 30, 38, 39, 13, "scarlet_monastery", "graveyard"),
    entry(24, "gnomeregan", "Gnomeregan", "Gnomeregan", "Dun Morogh", "Dun Morogh", 29, 38, 11),
    entry(25, "razorfen_kraul", "Kral von Razorfen", "Razorfen Kraul", "Brachland", "The Barrens", 29, 38, 9),
    entry(26, "dalaran", "Dalaran", "City of Dalaran", "Alteracgebirge", "Alterac Mountains", 28, 35, 12),
    entry(27, "excavation_site", "Ausgrabungsstätte: Sumpfland", "Excavation Site", "Sumpfland", "Wetlands", 26, 33, 10),
    entry(28, "blackfathom_deeps", "Blackfathom-Tiefe", "Blackfathom Deeps", "Eschental", "Ashenvale", 24, 32, 7),
    entry(29, "shadowfang_keep", "Burg Shadowfang", "Shadowfang Keep", "Silberwald", "Silverpine Forest", 20, 30, 6),
    entry(30, "deadmines", "Todesminen", "The Deadmines", "Westfall", "Westfall", 17, 26, 4),
    entry(31, "wailing_caverns", "Höhlen des Wehklagens", "Wailing Caverns", "Brachland", "The Barrens", 15, 24, 5),
    entry(32, "ruins_of_lordaeron", "Ruinen von Lordaeron", "Ruins of Lordaeron", "Tirisfal", "Tirisfal Glades", 15, 22, 3),
    entry(33, "hall_of_thanes", "Halle der Thanen", "Hall of Thanes", "Dun Morogh", "Dun Morogh", 13, 20, 2),
    entry(34, "ragefire_chasm", "Ragefireabgrund", "Ragefire Chasm", "Orgrimmar", "Orgrimmar", 13, 18, 1),
}

-- Former entries that are no longer offered: combined dungeons (the wing is unknown) and
-- the Stormwind Stockade, which the Forever group finder does not list. Events and dungeon
-- dates that use them stay readable; nobody is assigned to a wing automatically.
addon.legacyDungeons = {
    { "Das Scharlachrote Kloster", "Scarlet Monastery", "Tirisfal", "Tirisfal Glades", "30–46", 13, key = "scarlet_monastery",
        min = 30, max = 46, art = 13, combined = true },
    { "Schwarzfelsspitze", "Blackrock Spire", "Schwarzfels", "Blackrock Mountain", "55–60", 23, key = "blackrock_spire",
        min = 55, max = 60, art = 23, combined = true },
    { "Düsterbruch", "Dire Maul", "Feralas", "Feralas", "54–60", 24, key = "dire_maul", min = 54, max = 60, art = 24, combined = true },
    { "Stratholme", "Stratholme", "Östliche Pestländer", "Eastern Plaguelands", "58–60", 25, key = "stratholme",
        min = 58, max = 60, art = 25, combined = true },
    { "Das Verlies", "Stormwind Stockade", "Sturmwind", "Stormwind City", "23–30", 8, key = "stockade", min = 23, max = 30, art = 8,
        retired = true },
}

-- Former German names of unchanged dungeons, so old event titles show the current name.
local formerNames = {
    ragefire_chasm = "Flammenschlund", hall_of_thanes = "Hall of Thanes", shadowfang_keep = "Burg Schattenfang",
    blackfathom_deeps = "Tiefschwarze Grotte", deadmines = "Die Todesminen", dalaran = "Stadt Dalaran",
    excavation_site = "Excavation Site", drowned_city = "The Drowned City", kroldok_stronghold = "Krol’dok Stronghold",
    blackrock_depths = "Schwarzfelstiefen", alcaz_prison = "Alcaz Prison", blackmaw_hold = "Blackmaw Hold",
    shapers_terrace = "Shaper’s Terrace", razorfen_kraul = "Kral der Klingenhauer", razorfen_downs = "Hügel der Klingenhauer",
    zulfarrak = "Zul’Farrak",
}

local byID, byKey = {}, {}
for _, dungeon in ipairs(addon.groupDungeons) do
    byID[dungeon[6]], byKey[dungeon.key] = dungeon, dungeon
    dungeon.former = formerNames[dungeon.key]
end
for _, dungeon in ipairs(addon.legacyDungeons) do byID[dungeon[6]], byKey[dungeon.key] = dungeon, dungeon end

-- The numeric ID is part of the guild message format (also used by older versions).
function addon.getGroupDungeon(id)
    return byID[id]
end

function addon.getDungeonByKey(key)
    return byKey[key]
end

-- Banner art of a dungeon; wings use the banner of their dungeon complex for now.
function addon.dungeonArt(dungeon)
    return ("Interface\\AddOns\\ForeverGuild\\Art\\Dungeon%02d"):format(dungeon.art or dungeon[6])
end

-- All dungeon artwork is exported at 4:1; fill the frame with a centered crop.
function addon.fitDungeonArtwork(texture, width, height)
    if width <= 0 or height <= 0 then return end
    local ratio = width / (4 * height)
    local x = math.max(0, (1 - ratio) / 2)
    local y = math.max(0, (1 - 1 / ratio) / 2)
    texture:SetTexCoord(x, 1 - x, y, 1 - y)
end
