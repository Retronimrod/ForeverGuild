local _, addon = ...
-- Forever dungeon recommendations for the 1.60 client.
-- Each entry contains German and English names, zones, and a recommended level.
addon.groupDungeons = {
    {"Flammenschlund","Ragefire Chasm","Orgrimmar","Orgrimmar","13+",1},
    {"Hall of Thanes","Hall of Thanes","Dun Morogh","Dun Morogh","13–18",2},
    {"Ruinen von Lordaeron","Ruins of Lordaeron","Tirisfal","Tirisfal Glades","15–20",3},
    {"Die Todesminen","The Deadmines","Westfall","Westfall","16+",4},
    {"Höhlen des Wehklagens","Wailing Caverns","Brachland","The Barrens","17+",5},
    {"Burg Schattenfang","Shadowfang Keep","Silberwald","Silverpine Forest","18+",6},
    {"Tiefschwarze Grotte","Blackfathom Deeps","Eschental","Ashenvale","22+",7},
    {"Das Verlies","Stormwind Stockade","Sturmwind","Stormwind City","23+",8},
    {"Kral der Klingenhauer","Razorfen Kraul","Brachland","The Barrens","24+",9},
    {"Excavation Site","Excavation Site","Sumpfland","Wetlands","24–29",10},
    {"Gnomeregan","Gnomeregan","Dun Morogh","Dun Morogh","25+",11},
    {"Stadt Dalaran","City of Dalaran","Alteracgebirge","Alterac Mountains","28–33",12},
    {"Das Scharlachrote Kloster","Scarlet Monastery","Tirisfal","Tirisfal Glades","30+",13},
    {"Hügel der Klingenhauer","Razorfen Downs","Brachland","The Barrens","34+",14},
    {"Uldaman","Uldaman","Ödland","Badlands","35+",15},
    {"The Drowned City","The Drowned City","Schlingendorntal","Stranglethorn Vale","35–40",16},
    {"Krol’dok Stronghold","Krol’dok Stronghold","Riverglades","Riverglades","40–45",17},
    {"Zul’Farrak","Zul’Farrak","Tanaris","Tanaris","42+",18},
    {"Maraudon","Maraudon","Desolace","Desolace","42+",19},
    {"Versunkener Tempel","Sunken Temple","Sümpfe des Elends","Swamp of Sorrows","45+",20},
    {"Schwarzfelstiefen","Blackrock Depths","Schwarzfels","Blackrock Mountain","48+",21},
    {"Alcaz Prison","Alcaz Prison","Marschen von Dustwallow","Dustwallow Marsh","48–53",22},
    {"Schwarzfelsspitze","Blackrock Spire","Schwarzfels","Blackrock Mountain","53+",23},
    {"Düsterbruch","Dire Maul","Feralas","Feralas","54+",24},
    {"Stratholme","Stratholme","Östliche Pestländer","Eastern Plaguelands","55+",25},
    {"Blackmaw Hold","Blackmaw Hold","Azshara","Azshara","55–60",26},
    {"Scholomance","Scholomance","Westliche Pestländer","Western Plaguelands","57+",27},
    {"Shaper’s Terrace","Shaper’s Terrace","Krater von Un’Goro","Un’Goro Crater","58–60",28},
}
-- The activity ID is part of the guild message format.
local byID = {}
for _, entry in ipairs(addon.groupDungeons) do byID[entry[6]] = entry end

function addon.getGroupDungeon(id)
    return byID[id]
end

-- All dungeon artwork is exported at 4:1; fill the frame with a centered crop.
function addon.fitDungeonArtwork(texture, width, height)
    if width <= 0 or height <= 0 then return end
    local ratio = width / (4 * height)
    local x = math.max(0, (1 - ratio) / 2)
    local y = math.max(0, (1 - 1 / ratio) / 2)
    texture:SetTexCoord(x, 1 - x, y, 1 - y)
end
