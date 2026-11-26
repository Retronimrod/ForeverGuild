local _, addon = ...
local orderBook = addon and addon.orders
local guildBank, guildBankOpen = addon and addon.guildBank, false
local bankScan, startBankScan, scanVisibleBank, requestBankSnapshot
local lastBankRequest, lastBankReply = -60, -60
local showOrderMenu, showOrderDialog, orderMenu, orderDialog, orderChannel
local orderNotice, updateOrderNotice
local addonVersion = "0.9.59"
local settingsWindow, minimapIcon, guildShortcut
local updateGuildShortcut
local prefix, rolePrefix = "ForeverGuild1", "ForeverGuildRole"
local roleChannel, memberRoles, roleRecords
local canEditMember
local receiveRole
local rosterSelected
local frame = CreateFrame("Frame")
local trade = C_TradeSkillUI
local chat = C_ChatInfo
local de = GetLocale() == "deDE"
local L = addon.L
local guildKey, database, player, playerGivenName, registered
local pending, response, scanPending = {}, false, false
local queue, sending, sequence = {}, false, 0
local lastRequest, lastPublish, lastGuildQuery = -60, -60, -300
local backgroundScan
local window, search
local selected, activeTab = nil, "roster"
local roster, expanded, collapsedCategories = {}, {}, {}
local logEvent
local refresh
local utf8Lower = strlower or string.lower

local function diagnose(level, area, detail)
    ForeverGuildDiagnostics = ForeverGuildDiagnostics or {}
    local history = ForeverGuildDiagnostics
    local clean = tostring(detail):gsub("|", "/"):gsub("[%c]", " ")
    history[#history + 1] = { at = time(), level = level, area = area, detail = clean:sub(1, 450) }
    if #history > 400 then table.remove(history, 1) end
end

local function preference(key)
    return not ForeverGuildSettings or ForeverGuildSettings[key] ~= false
end

local function uiInCombat()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function reportError(area, err)
    diagnose("ERROR", area, err)
    if geterrorhandler then geterrorhandler()(err) end
end

local function after(delay, callback)
    C_Timer.After(delay, function()
        local ok, err = pcall(callback)
        if not ok then reportError("timer", err) end
    end)
end

local function registerMessagePrefix(value)
    if not chat or not chat.RegisterAddonMessagePrefix then return false end
    local ok, result = pcall(chat.RegisterAddonMessagePrefix, value)
    local codes = Enum and Enum.RegisterAddonMessagePrefixResult
    local success = codes and codes.Success or 0
    local duplicate = codes and codes.DuplicatePrefix or 1
    if ok and (result == true or result == success or result == duplicate) then return true end
    if chat.IsAddonMessagePrefixRegistered then
        local checked, active = pcall(chat.IsAddonMessagePrefixRegistered, value)
        return checked and active == true
    end
    return false
end

local function guildIdentity()
    local name, _, _, realm = GetGuildInfo("player")
    if not name or name == "" or (IsInGuild and not IsInGuild()) then return end
    return (realm or GetNormalizedRealmName()) .. ":" .. name
end

local function fullName(name, realm)
    local character, suffix = name:match("^([^-]+)%-(.*)$")
    character = (character or name):match("^%s*(.-)%s*$")
    realm = suffix or realm
    if not realm or not realm:find("[^%s%-]") then realm = GetNormalizedRealmName() end
    local normalizedRealm = realm:gsub("[%s%-]", "")
    local givenName = character:match("^%S+")
    -- Forever may report a surname in the roster and addon messages only.
    if player and givenName and utf8Lower(givenName) == playerGivenName then
        return player
    end
    return character .. "-" .. normalizedRealm
end

local function roleMemberKey(name)
    local key = fullName(name)
    if key == player or roster[key] then return key end
    local first, surname, realm = key:match("^([^%s%-]+)([^%-]*)%-(.+)$")
    if not first then return key end
    local match
    for candidate in pairs(roster) do
        local other, otherSurname, candidateRealm = candidate:match("^([^%s%-]+)([^%-]*)%-(.+)$")
        if other and utf8Lower(other) == utf8Lower(first) and utf8Lower(candidateRealm) == utf8Lower(realm)
            and (surname == "" or otherSurname == "" or utf8Lower(surname) == utf8Lower(otherSurname)) then
            if match then return key end
            match = candidate
        end
    end
    return match or key
end

local function normalizeRoleRecords()
    local aliases = {}
    for key in pairs(roleRecords or {}) do
        local target = roleMemberKey(key)
        if target ~= key then aliases[key] = target end
    end
    for alias, target in pairs(aliases) do
        local record, current = roleRecords[alias], roleRecords[target]
        if not current or record.revision > current.revision then roleRecords[target] = record end
        roleRecords[alias] = nil
    end
    for key, record in pairs(roleRecords or {}) do
        if record.author then record.author = roleMemberKey(record.author) end
    end
    local legacyAliases = {}
    for key in pairs(memberRoles or {}) do
        local target = roleMemberKey(key)
        if target ~= key then legacyAliases[key] = target end
    end
    for alias, target in pairs(legacyAliases) do
        if memberRoles[target] == nil then memberRoles[target] = memberRoles[alias] end
        memberRoles[alias] = nil
    end
end

local function normalizeProfiles()
    local normalized = {}
    for name, data in pairs(database) do
        local key = fullName(name)
        local previous = normalized[key]
        if key ~= player and (not previous or data.updated > previous.updated) then
            normalized[key] = data
        end
    end
    for key in pairs(database) do database[key] = nil end
    for key, data in pairs(normalized) do database[key] = data end
end

local refreshQueued = false
local function queueRefresh()
    if refreshQueued or not window or not window:IsShown() then return end
    refreshQueued = true
    after(.08, function()
        refreshQueued = false
        refresh()
    end)
end

local function sendNext()
    local message = table.remove(queue, 1)
    if message and guildIdentity() == guildKey and database then
        if message:sub(1, 2) == "B:" and not preference("bankShare") then
            after(0, sendNext)
            return
        end
        local channelPrefix = message:match("^[RAS]:") and rolePrefix or prefix
        local ok, status = pcall(chat.SendAddonMessage, channelPrefix, message, "GUILD")
        local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
        if not ok or (status ~= nil and status ~= success and status ~= true) then
            diagnose("ERROR", "send", status)
        end
        after(0.25, sendNext)
    else
        queue = {}
        sending = false
    end
end

local function enqueue(messages)
    if not registered or #queue + #messages > 140 then
        diagnose("WARN", "queue", "Message batch could not be queued")
        return false
    end
    for _, message in ipairs(messages) do queue[#queue + 1] = message end
    if not sending then
        sending = true
        sendNext()
    end
    return true
end

local function writeProfile()
    local lines = {}
    for id, profession in pairs(ForeverGuildCharacter) do
        local ids = {}
        for recipe in pairs(profession.recipes) do ids[#ids + 1] = recipe end
        table.sort(ids)
        lines[#lines + 1] = table.concat({
            id, profession.skill, profession.maximum, profession.scanned and 1 or 0, table.concat(ids, ",")
        }, ":")
    end
    table.sort(lines)
    return table.concat(lines, ";")
end

local function readProfile(payload)
    local profile = {}
    if payload == "-" then return profile end
    if payload == "" then return end
    local count = 0
    for line in payload:gmatch("[^;]+") do
        local id, skill, maximum, scanned, recipes = line:match("^(%d+):(%d+):(%d+):([01]):([%d,]*)$")
        if not id then return end
        id, skill, maximum = tonumber(id), tonumber(skill), tonumber(maximum)
        count = count + 1
        if count > 16 or profile[id] or id > 100000 or skill > 1000 or maximum > 1000 then return end
        local profession = { skill = skill, maximum = maximum, scanned = scanned == "1", recipes = {} }
        for recipe in recipes:gmatch("%d+") do
            local recipeID = tonumber(recipe)
            if recipeID < 1 or recipeID > 2147483647 then return end
            profession.recipes[recipeID] = true
        end
        profile[id] = profession
    end
    if count > 0 then return profile end
end

local function selfRoleMessage(record)
    return ("S:%.0f:%d:%d"):format(record.revision, record.mask, record.spec)
end

local function publishRoles()
    if not database or not roleChannel then return end
    local own = roleRecords[player]
    if own and own.author == player then enqueue({ selfRoleMessage(own) }) end
    enqueue({ "R:" .. (own and own.mask or ForeverGuildOwnRoles or 0) })
    for target, record in pairs(roleRecords) do
        if record.author == player and canEditMember(target) then
            enqueue({ ("A:%.0f:%d:%d:%s"):format(record.revision, record.mask, record.spec, target) })
        end
    end
end

local function publish()
    if not database or not registered then return end
    publishRoles()
    local payload = writeProfile()
    if payload == "" then payload = "-" end
    local count = math.ceil(#payload / 210)
    if count > 60 then
        diagnose("WARN", "publish", "Profile exceeds transfer size")
        return
    end
    sequence = sequence + 1
    local messages = {}
    for index = 1, count do
        messages[index] = ("D:%d:%d:%d:%s"):format(sequence, index, count, payload:sub((index - 1) * 210 + 1, index * 210))
    end
    enqueue(messages)
    diagnose("INFO", "publish", ("%d chunks, %d bytes queued"):format(count, #payload))
    lastPublish = GetTime()
    logEvent(L["Sent own profession data"])
end

local function schedulePublish(delay)
    if response or not database then return end
    response = true
    after(delay, function()
        response = false
        if GetTime() - lastPublish >= 3 then publish() end
    end)
end

local function updateGuild()
    local key = guildIdentity()
    if key == guildKey then return end
    guildKey, database, pending, queue = key, nil, {}, {}
    guildBankOpen, bankScan = false, nil
    lastBankRequest, lastBankReply = -60, -60
    if guildBank then guildBank.reset() end
    memberRoles, roleRecords, rosterSelected = nil, nil, nil
    lastRequest, lastPublish, lastGuildQuery = -60, -60, -300
    if key then
        ForeverGuildDB[key] = ForeverGuildDB[key] or {}
        database = ForeverGuildDB[key]
        ForeverGuildRoles[key] = ForeverGuildRoles[key] or {}
        memberRoles = ForeverGuildRoles[key]
        ForeverGuildRoleRecords[key] = ForeverGuildRoleRecords[key] or {}
        roleRecords = ForeverGuildRoleRecords[key]
        normalizeProfiles()
    end
    diagnose("INFO", "guild", key and "Guild profile loaded" or "No active guild")
    selected, roster = nil, {}
    if orderDialog then orderDialog.delivery = nil; orderDialog:Hide() end
    if orderMenu then orderMenu:Hide() end
    if updateOrderNotice then updateOrderNotice() end
    refresh()
end

local function requestSync()
    if not database or not registered or GetTime() - lastRequest < 20 then return end
    lastRequest = GetTime()
    lastGuildQuery = lastRequest
    enqueue({ "Q" })
    logEvent(L["Requested guild sync"])
    publish()
    return true
end

local professionIDs = { 129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393, 755 }
local function updateSkills()
    if not GetProfessions or not GetProfessionInfo then
        if not trade or not trade.GetProfessionInfoBySkillLineID then return end
        for _, id in ipairs(professionIDs) do
            local info = trade.GetProfessionInfoBySkillLineID(id)
            if info and info.skillLevel and info.skillLevel > 0 then
                local entry = ForeverGuildCharacter[id] or { recipes = {} }
                entry.skill, entry.maximum = info.skillLevel, info.maxSkillLevel or info.skillLevel
                ForeverGuildCharacter[id] = entry
            end
        end
        return
    end
    local known = {}
    for _, index in pairs({ GetProfessions() }) do
        local _, _, skill, maximum, _, _, id = GetProfessionInfo(index)
        if id and skill and maximum then
            local entry = ForeverGuildCharacter[id] or { recipes = {} }
            entry.skill, entry.maximum = skill, maximum
            known[id] = entry
        end
    end
    if next(known) then ForeverGuildCharacter = known end
end

local function scanProfession(expectedID)
    if not trade or not trade.GetBaseProfessionInfo or not trade.GetRecipeInfo then return end
    local getIDs = trade.GetAllRecipeIDs or trade.GetFilteredRecipeIDs
    if not getIDs then return end
    if trade.IsTradeSkillReady and not trade.IsTradeSkillReady() then return end
    if (trade.IsTradeSkillLinked and trade.IsTradeSkillLinked())
        or (trade.IsTradeSkillGuild and trade.IsTradeSkillGuild())
        or (trade.IsNPCCrafting and trade.IsNPCCrafting()) then return end
    local info = trade.GetBaseProfessionInfo()
    if not info or not info.professionID or not info.skillLevel or info.skillLevel < 1 then return end
    if expectedID and info.professionID ~= expectedID then return end
    local ids = getIDs()
    if not ids or #ids == 0 then return end
    local learned = {}
    local previous = ForeverGuildCharacter[info.professionID]
    if not trade.GetAllRecipeIDs and previous then
        for id in pairs(previous.recipes or {}) do learned[id] = true end
    end
    local totalLearned = 0
    for _, id in ipairs(ids) do
        local recipe = trade.GetRecipeInfo(id)
        if not recipe then return end
        learned[id] = recipe.learned and true or nil
        if not addon.recipeCatalog[id] and not ForeverGuildDiscoveredRecipes[id] then
            local ok, schematic
            if trade.GetRecipeSchematic then ok, schematic = pcall(trade.GetRecipeSchematic, id, false) end
            ForeverGuildDiscoveredRecipes[id] = { profession = info.professionID,
                output = ok and schematic and schematic.outputItemID or nil,
                name = recipe.name, locale = GetLocale() }
        end
    end
    for _ in pairs(learned) do totalLearned = totalLearned + 1 end
    ForeverGuildCharacter[info.professionID] = {
        skill = info.skillLevel,
        maximum = info.maxSkillLevel or info.skillLevel,
        scanned = true,
        recipes = learned,
    }
    diagnose("INFO", "scan", ("Profession %d, %d learned recipes"):format(info.professionID, totalLearned))
    return true
end

local function scheduleScan()
    if scanPending or backgroundScan then return end
    scanPending = true
    after(0.4, function()
        scanPending = false
        if backgroundScan then return end
        local previous = writeProfile()
        updateSkills()
        scanProfession()
        if writeProfile() ~= previous then
            refresh()
            schedulePublish(math.max(1, 4 - (GetTime() - lastPublish)))
        end
    end)
end

local craftingProfessions = { 129, 164, 165, 171, 185, 186, 197, 202, 333, 755 }

local function professionWindow()
    return _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame
end

local function silenceProfessionWindow()
    local visible = professionWindow()
    if not backgroundScan or not visible or not visible:IsShown() or backgroundScan.window then return end
    backgroundScan.window, backgroundScan.alpha = visible, visible:GetAlpha()
    visible:SetAlpha(0)
end

local function finishBackgroundScan()
    local job = backgroundScan
    backgroundScan = nil
    if writeProfile() ~= job.before then
        refresh()
        schedulePublish(math.max(1, 4 - (GetTime() - lastPublish)))
    end
    if job.scanned > 0 then
        logEvent((L["Professions scanned in background · "]) .. job.scanned)
    end
end

local function scanNextProfession()
    local job = backgroundScan
    local visible = professionWindow()
    if not database or guildKey ~= job.guild or (InCombatLockdown and InCombatLockdown())
        or (visible and visible:IsShown()) or #job.ids == 0 then
        finishBackgroundScan()
        return
    end
    local professionID = table.remove(job.ids, 1)
    local ok, opened = pcall(trade.OpenTradeSkill, professionID)
    if not ok or not opened then
        diagnose("WARN", "scan", ("OpenTradeSkill %d: %s"):format(professionID, tostring(opened)))
        after(.2, scanNextProfession)
        return
    end
    silenceProfessionWindow()
    local attempts = 0
    local function collect()
        attempts = attempts + 1
        silenceProfessionWindow()
        local captured = scanProfession(professionID)
        if not captured and attempts < 8 then
            after(.2, collect)
            return
        end
        if captured then job.scanned = job.scanned + 1
        else diagnose("WARN", "scan", ("Profession %d: recipe data not ready"):format(professionID)) end
        local windowOpened = job.window
        local info = trade.GetBaseProfessionInfo()
        if captured or not info or info.professionID == professionID or not info.professionID or info.professionID == 0 then
            pcall(trade.CloseTradeSkill)
        end
        if windowOpened then windowOpened:SetAlpha(job.alpha) end
        job.window, job.alpha = nil, nil
        after(.2, scanNextProfession)
    end
    after(.2, collect)
end

local function scanInBackground()
    if ForeverGuildBackgroundScan ~= true or backgroundScan or not database or not trade or not trade.OpenTradeSkill
        or not trade.CloseTradeSkill or not trade.GetBaseProfessionInfo
        or (InCombatLockdown and InCombatLockdown()) then return end
    local visible = professionWindow()
    if visible and visible:IsShown() then return end
    local before = writeProfile()
    updateSkills()
    local ids = {}
    for _, id in ipairs(craftingProfessions) do
        if ForeverGuildCharacter[id] then ids[#ids + 1] = id end
    end
    backgroundScan = { guild = guildKey, ids = ids, before = before, scanned = 0 }
    scanNextProfession()
    return true
end

local scanGeneration = 0
local function queueBackgroundScan(delay)
    scanGeneration = scanGeneration + 1
    local generation = scanGeneration
    after(delay, function()
        if generation == scanGeneration then scanInBackground() end
    end)
end

local function periodicSync()
    if preference("periodicSync") and database and GetTime() - lastGuildQuery >= 240 then requestSync() end
    after(300 + math.random(0, 60), periodicSync)
end

local function receive(message, sender)
    sender = fullName(sender)
    if not database or sender == player then return end
    if message == "Q" then
        lastGuildQuery = GetTime()
        schedulePublish(3 + math.random() * 9)
        return
    end
    local transfer, index, total, data = message:match("^D:(%d+):(%d+):(%d+):([%d:;,%-]+)$")
    if not transfer then diagnose("WARN", "receive", "Invalid message format"); return end
    index, total = tonumber(index), tonumber(total)
    if total < 1 or total > 60 or index < 1 or index > total or #data > 210 then
        diagnose("WARN", "receive", "Invalid transfer bounds")
        return
    end
    local now = GetTime()
    local batch = pending[sender]
    if not batch or now - batch.started > 40 or batch.transfer ~= transfer then
        batch = { transfer = transfer, started = now, total = total, parts = {}, received = 0 }
        pending[sender] = batch
        after(41, function()
            if pending[sender] == batch then
                pending[sender] = nil
                diagnose("WARN", "receive", ("Incomplete transfer: %d/%d chunks"):format(batch.received, batch.total))
            end
        end)
    end
    if total ~= batch.total or batch.parts[index] then return end
    batch.parts[index] = data
    batch.received = batch.received + 1
    if batch.received == total then
        pending[sender] = nil
        local profile = readProfile(table.concat(batch.parts))
        if profile then
            database[sender] = { professions = profile, updated = time() }
            logEvent((L["Received profession data · "]) .. sender:match("^[^-]+"))
            queueRefresh()
        else
            diagnose("WARN", "receive", "Invalid profession profile")
        end
    end
end

local professionNames = {
    [129] = {"Erste Hilfe", "First Aid"}, [164] = {"Schmiedekunst", "Blacksmithing"},
    [165] = {"Lederverarbeitung", "Leatherworking"}, [171] = {"Alchemie", "Alchemy"},
    [182] = {"Kräuterkunde", "Herbalism"}, [185] = {"Kochkunst", "Cooking"},
    [186] = {"Bergbau", "Mining"}, [197] = {"Schneiderei", "Tailoring"},
    [202] = {"Ingenieurskunst", "Engineering"}, [333] = {"Verzauberkunst", "Enchanting"},
    [356] = {"Angeln", "Fishing"}, [393] = {"Kürschnerei", "Skinning"},
    [755] = {"Juwelenschleifen", "Jewelcrafting"},
}

local function professionName(id)
    local info = trade and trade.GetProfessionInfoBySkillLineID and trade.GetProfessionInfoBySkillLineID(id)
    if info and info.professionName and info.professionName ~= "" then return info.professionName end
    return professionNames[id] and professionNames[id][de and 1 or 2] or tostring(id)
end

local recipeNames = {}
local function recipeName(id)
    if recipeNames[id] then return recipeNames[id] end
    local record = addon.recipeCatalog[id]
    local locale = GetLocale()
    if record and record.name and (locale == "deDE" or locale == "enUS" or locale == "enGB") then
        return record.name
    end
    local found = ForeverGuildDiscoveredRecipes and ForeverGuildDiscoveredRecipes[id]
    if found and found.locale == locale and found.name and found.name ~= "" then return found.name end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if not name or name == "" then
        local info = trade and trade.GetRecipeInfo and trade.GetRecipeInfo(id)
        name = info and info.name
    end
    if name and name ~= "" then
        recipeNames[id] = name
        return name
    end
    return record and record.name or ("#" .. id)
end

local function updateRoster()
    if not database or not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local current = {}
    for index = 1, GetNumGuildMembers() do
        local name, rank, rankIndex, level, class, zone, _, _, online, _, classFile = GetGuildRosterInfo(index)
        if type(name) == "string" then
            local key = fullName(name)
            local displayName = name:match("^[^-]+")
            local previous = current[key]
            if not previous or #displayName > #previous.displayName then
                local offline
                if not online and GetGuildRosterLastOnline then
                    local years, months, days, hours = GetGuildRosterLastOnline(index)
                    if years then
                        offline = ("%dy %dm %dd %dh"):format(years, months or 0, days or 0, hours or 0)
                    end
                end
                current[key] = { class = classFile, className = class, displayName = displayName, online = online,
                    rank = rank, rankIndex = rankIndex, level = level, zone = zone, offline = offline, target = name }
            end
        end
    end
    if next(current) then
        roster = current
        normalizeRoleRecords()
    end
end

local function officer(member)
    if not member then return false end
    -- The guild master can define which ranks count as officers (shared via P:O);
    -- without that, the rank name decides as before.
    local limit = guildKey and addon.boardRights and addon.boardRights.officerRank(guildKey)
    if limit then return member.rankIndex ~= nil and member.rankIndex <= limit end
    local rank = utf8Lower(member.rank or "")
    return member.rankIndex == 0 or rank == "offizier" or rank == "officer"
end

canEditMember = function(target)
    return target ~= nil and roleRecords ~= nil and roleChannel and
        (target == player or (roster[target] ~= nil and officer(roster[player]))) or false
end

addon.memberVersions = {}
function addon.isOlderVersion(version)
    if not version then return false end
    local a = { version:match("^(%d+)%.(%d+)%.(%d+)$") }
    local b = { addonVersion:match("^(%d+)%.(%d+)%.(%d+)$") }
    if #a < 3 or #b < 3 then return false end
    for i = 1, 3 do
        if tonumber(a[i]) ~= tonumber(b[i]) then return tonumber(a[i]) < tonumber(b[i]) end
    end
    return false
end

function addon.boardCan(rule, key)
    key = key or player
    local member = roster[key]
    return addon.boardRights.has(guildKey, member, key, rule, officer(member), member and member.rankIndex == 0)
end

function addon.boardMayModerate(kind, key)
    local permission = ({ O = "modOrder", G = "modGroup", A = "modNews" })[kind]
    return permission and addon.boardCan(permission, key)
end

local function roleNow()
    return (GetServerTime and GetServerTime() or time()) * 1000
end

local function ownSpec(target)
    local record = roleRecords and roleRecords[target]
    return record and record.spec or 0
end

local function memberMask(target)
    local record = roleRecords and roleRecords[target]
    if record then return record.mask end
    if target == player then return ForeverGuildOwnRoles or 0 end
    return memberRoles and memberRoles[target] or 0
end

local function editMember(target, mask, spec)
    updateRoster()
    if not canEditMember(target) then return end
    local previous = roleRecords[target]
    local revision = math.max(roleNow(), previous and previous.revision + 1 or 0)
    roleRecords[target] = { revision = revision, mask = mask, spec = spec, author = player }
    if target == player then ForeverGuildOwnRoles = mask end
    if target == player then enqueue({ selfRoleMessage(roleRecords[target]) }) end
    enqueue({ ("A:%.0f:%d:%d:%s"):format(revision, mask, spec, target) })
    if target == player then enqueue({ "R:" .. mask }) end
end

receiveRole = function(message, sender)
    local author = roleMemberKey(sender)
    if author == player then return end
    local revision, mask, spec = message:match("^S:(%d+):([0-7]):([0-3])$")
    local target = author
    if not revision then
        local rawTarget
        revision, mask, spec, rawTarget = message:match("^A:(%d+):([0-7]):([0-3]):([^:]+)$")
        if not revision then
            local legacy = tonumber(message:match("^R:([0-7])$"))
            if legacy and not roleRecords[author] then memberRoles[author] = legacy end
            return
        end
        target = roleMemberKey(rawTarget)
        if author ~= target then
            updateRoster()
            author, target = roleMemberKey(sender), roleMemberKey(rawTarget)
            if author ~= target and (not officer(roster[author]) or (target ~= player and not roster[target])) then
                if C_GuildInfo and C_GuildInfo.GuildRoster and not roster[author] then C_GuildInfo.GuildRoster() end
                diagnose("WARN", "roles", "Rejected unverified roster edit")
                return
            end
        end
    end
    revision = tonumber(revision)
    if revision > roleNow() + 60000 then return end
    local previous = roleRecords[target]
    if previous and (revision < previous.revision or
        (revision == previous.revision and author <= previous.author)) then return end
    roleRecords[target] = { revision = revision, mask = tonumber(mask), spec = tonumber(spec), author = author }
    if target == player then ForeverGuildOwnRoles = tonumber(mask) end
end

logEvent = function(message)
    diagnose("INFO", "activity", message)
    if not guildKey then return end
    local history = ForeverGuildLog[guildKey] or {}
    ForeverGuildLog[guildKey] = history
    table.insert(history, 1, { at = time(), message = message })
    if #history > 150 then table.remove(history) end
    if activeTab == "log" then queueRefresh() end
end

local function panel(parent, alpha, name, fillOpacity)
    local box = CreateFrame("Frame", name, parent, "BackdropTemplate")
    local base = box:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetPoint("TOPLEFT", 2, -2)
    base:SetPoint("BOTTOMRIGHT", -2, 2)
    if fillOpacity then base:SetColorTexture(.055, .037, .025, fillOpacity)
    else base:SetColorTexture(.105, .078, .055, 1) end
    box:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    box:SetBackdropColor(.34, .25, .17, alpha or .32)
    box:SetBackdropBorderColor(.50, .34, .17)
    return box
end

local function contrastPanel(parent)
    return panel(parent, .18, nil, .83)
end

local function pageBackdrop(page, asset, aspect, opacity)
    local art = page:CreateTexture(nil, "BACKGROUND", nil, -4)
    art:SetPoint("TOPLEFT", 4, -4)
    art:SetPoint("BOTTOMRIGHT", -4, 4)
    art:SetTexture("Interface\\AddOns\\ForeverGuild\\Art\\" .. asset)
    art:SetAlpha(opacity)
    local function crop(_, width, height)
        if width <= 8 or height <= 8 then return end
        local scale = (width - 8) / ((height - 8) * aspect)
        if scale >= 1 then
            art:SetTexCoord(0, 1, 1 - 1 / scale, 1)
        else
            local margin = (1 - scale) / 2
            art:SetTexCoord(margin, 1 - margin, 0, 1)
        end
    end
    page:HookScript("OnSizeChanged", crop)
    crop(page, page:GetSize())
end

local skillColors = {
    [129] = {.42, .72, .26}, [164] = {.67, .53, .37}, [165] = {.72, .46, .26},
    [171] = {.48, .73, .29}, [182] = {.48, .64, .30}, [185] = {.55, .68, .73},
    [186] = {.58, .60, .65}, [197] = {.48, .39, .92}, [202] = {.78, .56, .30},
    [333] = {.88, .46, .25}, [356] = {.36, .59, .88}, [393] = {.69, .48, .34},
    [755] = {.50, .72, .77},
}
local defaultSkillColor = {.73, .51, .24}

local function createSkillScale(parent, width)
    local track = CreateFrame("Frame", nil, parent)
    track:SetSize(width, 13)
    track:SetPoint("RIGHT", -19, 0)
    local base = track:CreateTexture(nil, "BACKGROUND")
    base:SetAllPoints()
    base:SetAtlas("UI-HUD-ExperienceBar-Background")
    local rim = track:CreateTexture(nil, "OVERLAY")
    rim:SetAllPoints()
    rim:SetAtlas("UI-HUD-ExperienceBar-Frame")
    local fillWidth = width - 4
    track.fill = track:CreateTexture(nil, "ARTWORK")
    track.fill:SetPoint("LEFT", 2, 0)
    track.fill:SetHeight(8)
    track.fill:SetColorTexture(1, 1, 1, 1)
    for index = 1, 9 do
        local tick = track:CreateTexture(nil, "ARTWORK", nil, 1)
        tick:SetPoint("CENTER", track, "LEFT", 2 + index * fillWidth / 10, 0)
        tick:SetSize(1, 8)
        tick:SetColorTexture(.10, .065, .04, .75)
    end
    track.labels = {}
    for index = 1, 3 do
        local label = track:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOP", track, "BOTTOMLEFT", 2 + index * fillWidth / 3 - (index == 3 and 8 or 0), -2)
        label:SetTextColor(.83, .74, .59)
        track.labels[index] = label
    end
    track.marker = track:CreateTexture(nil, "OVERLAY", nil, 2)
    track.marker:SetSize(1, 19)
    track.marker:SetColorTexture(1, .79, .32, 1)
    local diamond = track:CreateTexture(nil, "OVERLAY", nil, 2)
    diamond:SetSize(5, 5)
    diamond:SetPoint("TOP", track.marker)
    diamond:SetColorTexture(1, .79, .32, 1)
    diamond:SetRotation(math.pi / 4)
    track.value = track:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    track.value:SetPoint("BOTTOM", diamond, "TOP", 0, 1)
    track.width = fillWidth
    return track
end

local function setSkillScale(track, skill, professionID)
    local progress = math.min(1, math.max(0, skill / 300))
    local fillWidth = track.width * progress
    local color = skillColors[professionID] or defaultSkillColor
    track.fill:SetShown(fillWidth > 0)
    if fillWidth > 0 then
        track.fill:SetWidth(fillWidth)
        track.fill:SetGradient("VERTICAL", CreateColor(color[1] * .38, color[2] * .38, color[3] * .38, 1),
            CreateColor(color[1], color[2], color[3], 1))
    end
    for index, label in ipairs(track.labels) do label:SetText(index * 100) end
    local position = 2 + fillWidth
    track.marker:ClearAllPoints()
    track.marker:SetPoint("CENTER", track, "LEFT", position, 1)
    track.value:SetText(skill)
end

local function list(parent, left, top, right, bottom, width, rowHeight, tooltip)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", left, top)
    scroll:SetPoint("BOTTOMRIGHT", right, bottom)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(_, newWidth)
        if newWidth > 0 then content:SetWidth(newWidth) end
    end)
    if scroll:GetWidth() > 0 then content:SetWidth(scroll:GetWidth()) end
    local rows = {}
    return function(entries)
        local height = 0
        for index, entry in ipairs(entries) do
            local row = rows[index]
            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetSize(width, rowHeight)
                row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                row.tint = row:CreateTexture(nil, "BACKGROUND")
                row.tint:SetAllPoints()
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(rowHeight - 4, rowHeight - 4)
                row.icon:SetPoint("LEFT", 3, 0)
                row.check = row:CreateTexture(nil, "OVERLAY")
                row.check:SetSize(17, 17)
                row.check:SetPoint("RIGHT", -5, 0)
                row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                row.check:SetVertexColor(.32, 1, .38)
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.label:SetPoint("RIGHT", -4, 0)
                row.label:SetJustifyH("LEFT")
                row.label:SetWordWrap(false)
                row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                row:SetScript("OnClick", function(self, mouseButton)
                    if mouseButton == "RightButton" then
                        if self.entry.recipe and self.entry.crafter then showOrderMenu(self) end
                    else
                        if orderMenu then orderMenu:Hide() end
                        if self.entry.action then self.entry.action() end
                    end
                end)
                if tooltip then
                    row:SetScript("OnEnter", tooltip)
                    row:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end
                rows[index] = row
            end
            local isCard = entry.maximum ~= nil
            local isCategory = entry.category == true
            local size = isCard and 67 or (isCategory and 23 or rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -height)
            row:SetPoint("TOPRIGHT", 0, -height)
            row:SetHeight(size)
            height = height + size + (isCard and 4 or (isCategory and 2 or 0))
            row.icon:SetSize(isCard and 35 or rowHeight - 4, isCard and 35 or rowHeight - 4)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", isCard and 13 or (entry.recipe and 18 or 5), 0)
            row.entry = entry
            if entry.columns then
                row.columns = row.columns or {}
                for index, entryColumn in ipairs(entry.columns) do
                    local column = row.columns[index]
                    if not column then
                        column = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        column:SetJustifyH("LEFT")
                        column:SetWordWrap(false)
                        row.columns[index] = column
                    end
                    column:ClearAllPoints()
                    column:SetPoint("LEFT", entryColumn[1], 0)
                    column:SetWidth(entryColumn[2])
                    column:SetText(entryColumn[3])
                    column:Show()
                end
            elseif row.columns then
                for _, column in ipairs(row.columns) do column:Hide() end
            end
            if isCard and not row.card then
                row.card = contrastPanel(row)
                row.card:SetAllPoints()
                row.card:SetFrameLevel(row:GetFrameLevel() - 1)
                row.bar = createSkillScale(row, math.floor(width * .59))
            end
            if row.card then
                row.card:SetShown(isCard)
                row.bar:SetShown(isCard)
            end
            if isCard then
                setSkillScale(row.bar, entry.skill, entry.professionID)
            end
            if isCategory and not row.categoryBar then
                row.categoryBar = panel(row)
                row.categoryBar:SetPoint("TOPLEFT", 2, -1)
                row.categoryBar:SetPoint("BOTTOMRIGHT", -3, 1)
                row.categoryBar:SetFrameLevel(row:GetFrameLevel() - 1)
                row.categoryBar:SetBackdropBorderColor(.58, .40, .22, 1)
                local face = row.categoryBar:CreateTexture(nil, "ARTWORK")
                face:SetPoint("TOPLEFT", 3, -3)
                face:SetPoint("BOTTOMRIGHT", -3, 3)
                face:SetColorTexture(.19, .10, .045, .9)
                row.categoryMinus = row:CreateTexture(nil, "OVERLAY")
                row.categoryMinus:SetSize(11, 2)
                row.categoryMinus:SetPoint("RIGHT", -12, 0)
                row.categoryMinus:SetColorTexture(1, .79, .19)
                row.categoryPlus = row:CreateTexture(nil, "OVERLAY")
                row.categoryPlus:SetSize(2, 11)
                row.categoryPlus:SetPoint("CENTER", row.categoryMinus, "CENTER")
                row.categoryPlus:SetColorTexture(1, .79, .19)
            end
            if row.categoryBar then
                row.categoryBar:SetShown(isCategory)
                row.categoryMinus:SetShown(isCategory and entry.action ~= nil)
                row.categoryPlus:SetShown(isCategory and entry.collapsed == true)
            end
            local canOrder = orderBook and entry.recipe ~= nil and entry.crafter ~= nil
            if canOrder and not row.orderButton then
                local control = CreateFrame("Button", nil, row)
                control:SetSize(105, 20)
                control:SetPoint("RIGHT", -7, 0)
                local hover = control:CreateTexture(nil, "HIGHLIGHT")
                hover:SetAllPoints()
                hover:SetColorTexture(.82, .53, .20, .20)
                local icon = control:CreateTexture(nil, "ARTWORK")
                icon:SetSize(17, 17)
                icon:SetPoint("LEFT", 6, 0)
                icon:SetTexture("Interface\\AddOns\\ForeverGuild\\Art\\TabOrders")
                local caption = control:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                caption:SetPoint("LEFT", icon, "RIGHT", 5, 0)
                caption:SetTextColor(.95, .77, .44)
                caption:SetText(L["Place order"])
                control:SetScript("OnClick", function()
                    if orderMenu then orderMenu:Hide() end
                    GameTooltip:Hide()
                    local order = row.entry
                    showOrderDialog(order.recipe, order.crafter, order.professionID)
                end)
                row.orderButton = control
            end
            if row.orderButton then row.orderButton:SetShown(canOrder and true or false) end
            row.label:SetFontObject(isCategory and GameFontNormal or GameFontHighlightSmall)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", entry.icon and row.icon or row, entry.icon and "RIGHT" or "LEFT", entry.icon and 9 or (entry.labelOffset or 7), 0)
            if entry.columns then
                row.label:SetWidth(entry.labelWidth)
            else
                row.label:SetPoint("RIGHT", isCard and -math.floor(width * .64) or (canOrder and -120 or ((entry.synced or isCategory) and -27 or -8)), 0)
            end
            row.check:ClearAllPoints()
            if entry.checkOffset then
                row.check:SetPoint("CENTER", row, "LEFT", entry.checkOffset, 0)
            else
                row.check:SetPoint("RIGHT", -5, 0)
            end
            row.check:SetShown(entry.synced == true)
            row.label:SetText(entry.text)
            local color = entry.color
            if color then row.label:SetTextColor(color.r, color.g, color.b) else row.label:SetTextColor(1, .89, .72) end
            row.icon:SetTexture(entry.icon)
            row.tint:SetColorTexture(entry.selected and .48 or .30, .22, .10,
                (isCard or isCategory) and 0 or (entry.selected and .65 or (index % 2 == 0 and .16 or .05)))
            if entry.boardCard and not row.boardCard then
                local card = panel(row, .25, nil, .96)
                card:SetFrameLevel(row:GetFrameLevel())
                card:SetPoint("TOPLEFT", 3, -2)
                card:SetPoint("BOTTOMRIGHT", -4, 2)
                row.boardCard = card
                row.boardSubtitle = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.boardSubtitle:SetPoint("TOPLEFT", 46, -30)
                row.boardSubtitle:SetPoint("RIGHT", -33, 0)
                row.boardSubtitle:SetJustifyH("LEFT")
                row.boardSubtitle:SetWordWrap(false)
                row.boardArt = card:CreateTexture(nil, "ARTWORK", nil, -4)
                row.boardArt:SetPoint("TOPRIGHT", -3, -3)
                row.boardArt:SetWidth(208)
                row.boardArt:SetPoint("BOTTOMRIGHT", -3, 3)
                row.boardArt:SetAlpha(.78)
                row.boardShade = card:CreateTexture(nil, "ARTWORK", nil, -3)
                row.boardShade:SetAllPoints(row.boardArt)
                row.boardShade:SetColorTexture(1, 1, 1, 1)
                row.boardShade:SetGradient("HORIZONTAL", CreateColor(.055,.037,.025,1), CreateColor(.055,.037,.025,.10))
                -- Keep the row text in front of the card artwork.
                card:SetFrameLevel(math.max(0, row:GetFrameLevel() - 1))
                row.boardPin = row:CreateTexture(nil, "OVERLAY")
                row.boardPin:SetSize(13, 13)
                row.boardPin:SetPoint("TOPRIGHT", -11, -7)
                row.boardPin:SetTexture("Interface\\AddOns\\ForeverGuild\\Art\\BoardPin")
            end
            if row.boardCard then
                row.boardCard:SetShown(entry.boardCard == true)
                row.boardSubtitle:SetShown(entry.boardCard == true)
                row.boardPin:SetShown(entry.boardCard == true)
                row.boardArt:SetShown(entry.boardCard == true and entry.banner ~= nil)
                row.boardShade:SetShown(entry.boardCard == true and entry.banner ~= nil)
                if entry.banner then
                    row.boardArt:SetTexture(entry.banner)
                    addon.fitDungeonArtwork(row.boardArt, 208, size - 10)
                end
            end
            row:GetHighlightTexture():SetAlpha(entry.boardCard and .14 or 1)
            if entry.boardCard then
                local frame = row.boardCard
                if entry.selected then frame:SetBackdropBorderColor(.82, .59, .28, 1)
                else frame:SetBackdropBorderColor(.44, .31, .21, .9) end
                row.label:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", 46, -12)
                row.label:SetPoint("RIGHT", -32, 0)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", 11, 0)
                row.icon:SetSize(26, 26)
                row.boardSubtitle:SetText(entry.subtitle or "")
                local tone = entry.statusColor or { r = .76, g = .67, b = .55 }
                row.boardSubtitle:SetTextColor(tone.r, tone.g, tone.b)
                row.tint:SetColorTexture(0, 0, 0, 0)
            end
            row:Show()
        end
        for index = #entries + 1, #rows do rows[index]:Hide() end
        content:SetHeight(math.max(1, height))
        local range = math.max(0, content:GetHeight() - scroll:GetHeight())
        if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
    end, scroll
end

local function recipeDetails(id)
    local recipe = trade and trade.GetRecipeLink and trade.GetRecipeLink(id)
    if recipe == "" then recipe = nil end
    local schematic = trade and trade.GetRecipeSchematic and trade.GetRecipeSchematic(id, false)
    local outputID = schematic and schematic.outputItemID
    local catalog = addon.recipeCatalog[id] or (ForeverGuildDiscoveredRecipes and ForeverGuildDiscoveredRecipes[id])
    local known = addon.recipeOutputs and addon.recipeOutputs[id]
    if not known and catalog then known = catalog.output end
    if not outputID or outputID < 1 then
        outputID = type(known) == "table" and known[1] or (type(known) == "number" and known or nil)
    end
    if not outputID and trade and trade.GetRecipeItemLink then
        local output = trade.GetRecipeItemLink(id)
        if output then outputID = tonumber(output:match("|Hitem:(%d+)")) end
    end
    return recipe or ("spell:" .. id), outputID, type(known) == "table" and known[2] or nil
end

local function recipeTooltip(row)
    local id = row.entry.recipe
    if not id then return end
    local recipe = recipeDetails(id)
    local tooltip = GameTooltip
    tooltip:SetOwner(row, "ANCHOR_NONE")
    tooltip:SetHyperlink(recipe:match("|H(.-)|h") or recipe)

    local parentScale = UIParent:GetEffectiveScale()
    local rowScale = row:GetEffectiveScale() / parentScale
    local tooltipScale = tooltip:GetEffectiveScale() / parentScale
    local screenWidth, screenHeight = UIParent:GetSize()
    local width, height = tooltip:GetWidth() * tooltipScale, tooltip:GetHeight() * tooltipScale
    local margin = 8
    local x = row:GetLeft() * rowScale - width - margin
    if x < margin then x = row:GetRight() * rowScale + margin end
    x = math.max(margin, math.min(x, screenWidth - width - margin))
    local y = math.min(screenHeight - margin, math.max(height + margin, row:GetTop() * rowScale))
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local gold = { r = 1, g = .82, b = .24 }
local muted = { r = .65, g = .60, b = .53 }
local professionIcons = {
    [129] = 135966, [164] = 136241, [165] = 133611, [171] = 136240,
    [182] = 136246, [185] = 133971, [186] = 136248, [197] = 136249,
    [202] = 136243, [333] = 136244, [356] = 136245, [393] = 134366, [755] = 134071,
}

local enchantSlots = {
    Bracer = "Armschienen", Cloak = "Umhang", Chest = "Brust", Boots = "Stiefel",
    Gloves = "Handschuhe", Shield = "Schild", Weapon = "Waffe", ["2H Weapon"] = "Zweihandwaffe",
    Ring = "Ring", Helm = "Kopf", Shoulders = "Schultern", Belt = "Gürtel",
}

local itemDetails, pendingItems = {}, {}
local recipeLoad = { ids = {}, total = 0, remaining = 0, failed = 0 }

local function recipeItemDetails(itemID)
    if not itemID then return end
    local details = itemDetails[itemID]
    if not details and not pendingItems[itemID] then
        local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
        if getItemInfo then
            local name, _, quality, _, requiredLevel = getItemInfo(itemID)
            if quality ~= nil then
                details = { name = name, quality = quality, level = requiredLevel }
                itemDetails[itemID] = details
            else
                pendingItems[itemID] = true
                if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
            end
        end
    end
    if details then return ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[details.quality], details.level, details.quality end
end

local function preloadRecipeItems()
    local items, seen = {}, {}
    local function add(id)
        if type(id) == "number" and id > 0 and not seen[id] and not itemDetails[id] then
            seen[id] = true
            items[#items + 1] = id
        end
    end
    local function addRecipe(recipe)
        local record = addon.recipeCatalog[recipe]
        if record then
            add(record.output)
            for id in pairs(record.reagents or {}) do add(id) end
        end
        local output = addon.recipeOutputs[recipe]
        add(type(output) == "table" and output[1] or output)
    end
    -- Warm the visible order data before the rest of the catalog.
    for _, order in pairs(addon.board.records(guildKey)) do addRecipe(order.recipe) end
    for _, order in pairs(ForeverGuildOrders or {}) do
        if orderBook.belongsToGuild(order, guildKey) then addRecipe(order.recipe) end
    end
    for recipe, record in pairs(addon.recipeCatalog) do
        addRecipe(recipe)
        if not record.name and C_Spell and C_Spell.RequestLoadSpellData then
            pcall(C_Spell.RequestLoadSpellData, recipe)
        end
    end
    for _, record in pairs(ForeverGuildDiscoveredRecipes) do add(record.output) end

    recipeLoad.ids, recipeLoad.total, recipeLoad.remaining = seen, #items, #items
    recipeLoad.failed = 0
    local function finish(id, loaded)
        local state = recipeLoad.ids[id]
        if state == "missing" then
            if loaded then
                recipeLoad.failed = recipeLoad.failed - 1
                recipeLoad.ids[id] = nil
            end
        elseif state then
            recipeLoad.remaining = recipeLoad.remaining - 1
            recipeLoad.ids[id] = not loaded and "missing" or nil
            if not loaded then recipeLoad.failed = recipeLoad.failed + 1 end
        end
    end
    recipeLoad.finish = finish

    local index = 1
    local function batch()
        for i = index, math.min(index + 39, #items) do
            local id = items[i]
            recipeItemDetails(id)
            if itemDetails[id] then finish(id, true) end
        end
        local catalog = window and window.boardCatalog
        if catalog and catalog:IsShown() then catalog.updateProgress() end
        index = index + 40
        if index <= #items then after(.10, batch) end
    end
    batch()
    if #items > 0 then
        after(25, function()
            for id in pairs(recipeLoad.ids) do finish(id, itemDetails[id] ~= nil) end
            local catalog = window and window.boardCatalog
            if catalog and catalog:IsShown() then catalog.updateProgress() end
        end)
    end
end

local function recipePresentation(id, title, professionID)
    local _, outputID, enchantSlot = recipeDetails(id)
    local _, _, _, equipment, itemIcon, classID, subclassID
    if outputID and C_Item and C_Item.GetItemInfoInstant then
        _, _, _, equipment, itemIcon, classID, subclassID = C_Item.GetItemInfoInstant(outputID)
    end
    if not itemIcon and outputID and C_Item and C_Item.GetItemIconByID then
        itemIcon = C_Item.GetItemIconByID(outputID)
    end
    local info = trade and trade.GetRecipeInfo and trade.GetRecipeInfo(id)
    local category
    if enchantSlot then category = de and (enchantSlots[enchantSlot] or enchantSlot) or enchantSlot end
    if not category and professionID == 333 then
        local lower = utf8Lower(title)
        if lower:find("^runenverziert") or lower:find("^runed.+rod$") then
            category = L["Runed enchanting rods"]
        end
    end
    if not category and professionID == 333 then category = title:match("^(.-)%s+%-[%s]+") end
    if not category and equipment and equipment ~= "" then category = _G[equipment] end
    if not category and classID and subclassID and subclassID ~= 0 and C_Item.GetItemSubClassInfo then
        category = C_Item.GetItemSubClassInfo(classID, subclassID)
    end
    if not category and info and info.categoryID and trade.GetCategoryInfo then
        local group = trade.GetCategoryInfo(info.categoryID, true)
        if type(group) == "table" and group.name ~= "" and group.name ~= professionName(professionID) then category = group.name end
    end
    local icon = itemIcon or (info and info.icon)
    if not icon and not outputID and C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(id) end
    if not icon or icon == 134400 then icon = professionIcons[professionID] or 134400 end
    local color, requiredLevel, quality = recipeItemDetails(outputID)
    local requiredSkill = addon and addon.recipeSkills and addon.recipeSkills[id]
    return category or (L["Other recipes"]), icon, color, requiredSkill, requiredLevel, quality, outputID
end

local function selectSideTab(tab, active)
    if tab.SetChecked then tab:SetChecked(active) end
    if tab.SelectedTexture then tab.SelectedTexture:SetShown(active) end
end

local roles = {
    { bit = 1, label = "Tank", column = 0, row = 1 },
    { bit = 2, label = L["Healer"], column = 1, row = 0 },
    { bit = 4, label = L["DPS"], column = 1, row = 1 },
}

local function hasRole(mask, bit)
    return math.floor((mask or 0) / bit) % 2 == 1
end

local function roleText(mask)
    local labels = {}
    for _, role in ipairs(roles) do
        if hasRole(mask, role.bit) then labels[#labels + 1] = role.label end
    end
    return #labels > 0 and table.concat(labels, " / ") or "–"
end

local specs = {
    WARRIOR = {{"Waffen","Arms"},{"Furor","Fury"},{"Schutz","Protection"}},
    PALADIN = {{"Heilig","Holy"},{"Schutz","Protection"},{"Vergeltung","Retribution"}},
    HUNTER = {{"Tierherrschaft","Beast Mastery"},{"Treffsicherheit","Marksmanship"},{"Überleben","Survival"}},
    ROGUE = {{"Meucheln","Assassination"},{"Kampf","Combat"},{"Täuschung","Subtlety"}},
    PRIEST = {{"Disziplin","Discipline"},{"Heilig","Holy"},{"Schatten","Shadow"}},
    SHAMAN = {{"Elementar","Elemental"},{"Verstärkung","Enhancement"},{"Wiederherstellung","Restoration"}},
    MAGE = {{"Arkan","Arcane"},{"Feuer","Fire"},{"Frost","Frost"}},
    WARLOCK = {{"Gebrechen","Affliction"},{"Dämonologie","Demonology"},{"Zerstörung","Destruction"}},
    DRUID = {{"Gleichgewicht","Balance"},{"Wilder Kampf","Feral Combat"},{"Wiederherstellung","Restoration"}},
}

local talentIcons = {
    WARRIOR = {"Ability_Warrior_SavageBlow", "Ability_Warrior_InnerRage", "INV_Shield_06"},
    PALADIN = {"Spell_Holy_HolyBolt", "Spell_Holy_DevotionAura", "Spell_Holy_AuraOfLight"},
    HUNTER = {"Ability_Hunter_BeastTaming", "Ability_Marksmanship", "Ability_Hunter_SwiftStrike"},
    ROGUE = {"Ability_Rogue_Eviscerate", "Ability_BackStab", "Ability_Stealth"},
    PRIEST = {"Spell_Holy_WordFortitude", "Spell_Holy_HolyBolt", "Spell_Shadow_ShadowWordPain"},
    SHAMAN = {"Spell_Nature_Lightning", "Spell_Nature_LightningShield", "Spell_Nature_MagicImmunity"},
    MAGE = {"Spell_Holy_MagicalSentry", "Spell_Fire_FireBolt02", "Spell_Frost_FrostBolt02"},
    WARLOCK = {"Spell_Shadow_DeathCoil", "Spell_Shadow_Metamorphosis", "Spell_Shadow_RainOfFire"},
    DRUID = {"Spell_Nature_StarFall", "Ability_Racial_BearForm", "Spell_Nature_HealingTouch"},
}

local talentBackgrounds = {
    WARRIOR = {"WarriorArms", "WarriorFury", "WarriorProtection"},
    PALADIN = {"PaladinHoly", "PaladinProtection", "PaladinCombat"},
    HUNTER = {"HunterBeastMastery", "HunterMarksmanship", "HunterSurvival"},
    ROGUE = {"RogueAssassination", "RogueCombat", "RogueSubtlety"},
    PRIEST = {"PriestDiscipline", "PriestHoly", "PriestShadow"},
    SHAMAN = {"ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration"},
    MAGE = {"MageArcane", "MageFire", "MageFrost"},
    WARLOCK = {"WarlockCurses", "WarlockSummoning", "WarlockDestruction"},
    DRUID = {"DruidBalance", "DruidFeralCombat", "DruidRestoration"},
}

local function specializationArt(class, index, own)
    local icons = talentIcons[class]
    local backgrounds = talentBackgrounds[class]
    local icon = icons and ("Interface\\Icons\\" .. icons[index]) or 134400
    local background = backgrounds and backgrounds[index]
    if own and GetTalentTabInfo then
        local _, nameOrIcon, pointsOrDescription, nativeIcon, _, nativeBackground = GetTalentTabInfo(index)
        if type(pointsOrDescription) == "number" then
            nativeIcon, nativeBackground = nameOrIcon, nativeIcon
        end
        if type(nativeIcon) == "string" or type(nativeIcon) == "number" then icon = nativeIcon end
        if type(nativeBackground) == "string" and nativeBackground ~= "" then background = nativeBackground end
        if type(nativeBackground) == "number" and nativeBackground > 0 then background = nativeBackground end
    end
    if type(background) == "string" and not background:find("\\", 1, true) then
        background = "Interface\\TalentFrame\\" .. background .. "-TopLeft"
    end
    return icon, background
end

local function specName(class, index)
    local options = specs[class]
    return options and options[index] and options[index][de and 1 or 2]
end

local function refreshRosterView()
    window.rosterGuildName:SetText(guildKey and GetGuildInfo("player") or (L["No guild"]))
    local stats, totalCount, onlineCount, master, officers = window.rosterGuildStats, 0, 0, nil, {}
    local outdated = 0
    for key, member in pairs(roster) do
        if addon.isOlderVersion(addon.memberVersions[key]) then outdated = outdated + 1 end
        totalCount = totalCount + 1
        if member.online then onlineCount = onlineCount + 1 end
        if member.rankIndex == 0 then master = member.displayName
        elseif officer(member) then officers[#officers + 1] = member.displayName end
    end
    table.sort(officers)
    stats.officers = officers
    stats.counts:SetText(guildKey and ((L["%d members · %d online"]):format(totalCount, onlineCount)
        .. (outdated > 0 and ((L[" · %d outdated"]):format(outdated)) or "")) or "")
    stats.leaders:SetText(guildKey and master and ((L["Guild master: %s · %d officers"])
        :format(master, #officers)) or "")
    local query = utf8Lower(window.rosterSearch:GetText())
    local members, rows, pinned, selection = {}, {}, {}, nil
    local onlineOnly = window.onlineOnly:GetChecked()
    for name, member in pairs(roster) do
        local mask = memberMask(name)
        local searchable = table.concat({member.displayName, member.rank or "", member.className or "", roleText(mask), specName(member.class, ownSpec(name)) or ""}, " ")
        if name == player or ((not onlineOnly or member.online) and utf8Lower(searchable):find(query, 1, true)) then
            members[#members + 1] = { name = name, member = member, roles = mask }
        end
    end
    local sortKey = window.rosterSort
    table.sort(members, function(a, b)
        if a.name == player then return b.name ~= player end
        if b.name == player then return false end
        local av = a.member[sortKey]
        local bv = b.member[sortKey]
        if sortKey == "spec" then
            av = specName(a.member.class, ownSpec(a.name))
            bv = specName(b.member.class, ownSpec(b.name))
        end
        if sortKey == "level" then av, bv = av or 0, bv or 0
        elseif sortKey == "rankIndex" then av, bv = av or 99, bv or 99
        elseif sortKey == "online" then av, bv = av and 1 or 0, bv and 1 or 0
        else av, bv = av or "", bv or "" end
        if av == bv then return a.name < b.name end
        if window.rosterReverse then return av > bv end
        return av < bv
    end)
    for _, entry in ipairs(members) do
        if entry.name == rosterSelected then selection = entry end
    end
    selection = selection or members[1]
    rosterSelected = selection and selection.name
    for _, entry in ipairs(members) do
        local name, member = entry.name, entry.member
        local online = member.online or name == player
        local destination = name == player and pinned or rows
        local values = { tostring(member.level or "–"), member.className or "–", member.rank or "–",
            roleText(entry.roles), specName(member.class, ownSpec(name)) or "–", online and "Online" or "Offline" }
        if addon.isOlderVersion(addon.memberVersions[name]) then values[6] = values[6] .. " · v" .. addon.memberVersions[name] end
        local columns = {}
        for index, value in ipairs(values) do
            local field = window.rosterColumns[index == 1 and 1 or index + 1]
            columns[index] = { field.x, field.width - 5, value }
        end
        destination[#destination + 1] = {
            text = member.displayName, selected = name == rosterSelected,
            color = online and (RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class] or gold) or muted,
            synced = database and database[name] ~= nil,
            labelOffset = window.rosterColumns[2].x,
            labelWidth = window.rosterColumns[2].width - 8,
            checkOffset = window.rosterColumns[8].x + window.rosterColumns[8].width / 2 - 4,
            columns = columns,
            action = function()
                if rosterSelected ~= name then window.rosterDetailScroll:SetVerticalScroll(0) end
                rosterSelected = name
                refresh()
            end,
        }
    end
    window.renderPinnedMember(pinned)
    window.renderRoster(rows)

    local member = selection and selection.member
    local own = rosterSelected ~= nil and rosterSelected == player
    local profile = own and { professions = ForeverGuildCharacter } or (database and rosterSelected and database[rosterSelected])
    window.rosterName:SetText(member and member.displayName or (L["No results"]))
    local presence = member and ((own or member.online) and (member.zone and member.zone ~= "" and member.zone or "Online")
        or (member.offline and ((L["Last online: "]) .. member.offline) or "Offline"))
    window.profileRank:SetText(member and member.rank or "–")
    window.profileClass:SetText(member and ((member.className or "–") .. "  ·  " .. (member.level or "–")) or "–")
    window.profilePresence:SetText(presence or "–")
    window.profileSync:SetText(profile and profile.updated and date("%d.%m.%Y %H:%M", profile.updated) or "–")
    local professions = {}
    for id, data in pairs(profile and profile.professions or {}) do
        professions[#professions + 1] = { name = professionName(id), icon = professionIcons[id],
            skill = data.skill, maximum = data.maximum }
    end
    table.sort(professions, function(a, b) return a.name < b.name end)
    window.renderProfileProfessions(professions)
    window.rosterRecipes:SetEnabled(profile ~= nil and #professions > 0)
    window.rosterWhisper:SetEnabled(member ~= nil and not own and member.online == true and ChatFrame_SendTell ~= nil)
    local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
    window.rosterInvite:SetEnabled(member ~= nil and not own and member.online == true and invite ~= nil)
    local editable = canEditMember(rosterSelected)
    window.rolesHeading:SetText(own and (L["My roles and specialization"])
        or (L["Roles and specialization"]))
    for index, check in ipairs(window.roleChecks) do
        check:Select(hasRole(memberMask(rosterSelected), roles[index].bit))
        check:SetEnabled(editable)
    end
    for index, control in ipairs(window.specButtons) do
        local name = member and specName(member.class, index)
        control:SetShown(name ~= nil)
        if name then
            control:SetTitle(name)
            control:SetTalentArt(specializationArt(member.class, index, own))
            control:Select(ownSpec(rosterSelected) == index)
            control:SetEnabled(editable)
        end
    end
end

refresh = function()
    if not window or not window:IsShown() or not window.renderPlayers or not window.log then return end
    local logOpen = activeTab == "log"
    local rosterOpen = activeTab == "roster"
    local adminOpen = activeTab == "admin"
    local ordersOpen = activeTab == "orders"
    local helpOpen = activeTab == "help"
    local bankOpen = activeTab == "bank"
    local boardOpen = activeTab == "board"
    if window.board then
        window.board:SetShown(boardOpen)
        selectSideTab(window.boardTab, boardOpen)
    end
    if window.bank then
        window.bank:SetShown(bankOpen)
        selectSideTab(window.bankTab, bankOpen)
    end
    if window.help then
        window.help:SetShown(helpOpen)
        selectSideTab(window.helpTab, helpOpen)
    end
    if orderMenu and (ordersOpen or adminOpen or logOpen or rosterOpen or helpOpen or bankOpen or boardOpen) then orderMenu:Hide() end
    if window.orders then
        window.orders:SetShown(ordersOpen)
        selectSideTab(window.ordersTab, ordersOpen)
    end
    if window.admin then
        window.admin:SetShown(adminOpen)
        selectSideTab(window.adminTab, adminOpen)
    end
    window.professions:SetShown(not logOpen and not rosterOpen and not adminOpen and not ordersOpen and not helpOpen and not bankOpen and not boardOpen)
    window.rosterView:SetShown(rosterOpen)
    selectSideTab(window.rosterTab, rosterOpen)
    window.log:SetShown(logOpen)
    selectSideTab(window.professionTab, not logOpen and not rosterOpen and not adminOpen and not ordersOpen and not helpOpen and not bankOpen and not boardOpen)
    selectSideTab(window.logTab, logOpen)
    if helpOpen then return end
    if boardOpen then window.refreshBoard(); return end
    if bankOpen then window.refreshBank(); return end
    if ordersOpen then window.refreshOrders(); return end
    if adminOpen then window.refreshAdmin(); return end
    if rosterOpen then refreshRosterView(); return end
    if logOpen then
        local rows = {}
        for _, entry in ipairs(ForeverGuildLog[guildKey] or {}) do
            rows[#rows + 1] = { text = date("%d.%m.%Y  %H:%M:%S", entry.at) .. "    " .. entry.message }
        end
        if #rows == 0 then rows[1] = { text = L["No events yet."], color = muted } end
        window.renderLog(rows)
        return
    end

    local query = utf8Lower(search:GetText())
    local function matches(value) return utf8Lower(value):find(query, 1, true) end
    local profiles = {}
    for name in pairs(roster) do profiles[name] = {} end
    for name, profile in pairs(database or {}) do
        if not next(roster) or roster[name] then profiles[name] = profile end
    end
    if player then profiles[player] = { professions = ForeverGuildCharacter } end

    local names, online, total = {}, 0, 0
    for name, profile in pairs(profiles) do
        total = total + 1
        if name == player or (roster[name] and roster[name].online) then online = online + 1 end
        local rows = {}
        local matchesCharacter = matches(roster[name] and roster[name].displayName or name)
        for professionID, entry in pairs(profile.professions or {}) do
            local profession = professionName(professionID)
            local showAll = matchesCharacter or matches(profession)
            local recipes
            if not showAll then
                for recipe in pairs(entry.recipes) do
                    local title = recipeName(recipe)
                    if matches(title) then
                        recipes = recipes or {}
                        recipes[#recipes + 1] = { text = title, recipe = recipe }
                    end
                end
            end
            if showAll or recipes then
                rows[#rows + 1] = { id = professionID, name = profession, entry = entry, recipes = recipes }
            end
        end
        if matchesCharacter or #rows > 0 then
            table.sort(rows, function(a, b) return a.name < b.name end)
            names[#names + 1] = { name = name, professions = rows, updated = profile.updated }
        end
    end
    table.sort(names, function(a, b)
        local aOnline = a.name == player or (roster[a.name] and roster[a.name].online) or false
        local bOnline = b.name == player or (roster[b.name] and roster[b.name].online) or false
        if aOnline ~= bOnline then return aOnline end
        return a.name < b.name
    end)

    local current
    for _, candidate in ipairs(names) do
        if candidate.name == (selected or player) then current = candidate end
    end
    current = current or names[1]
    selected = current and current.name
    local players = {}
    for _, candidate in ipairs(names) do
        local name = candidate.name
        local member = roster[name] or {}
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
        local isOnline = name == player or member.online
        players[#players + 1] = {
            text = member.displayName or name:match("^[^-]+"), selected = selected == name,
            synced = database and database[name] ~= nil,
            color = isOnline and (classColor or gold) or muted,
            action = function()
                selected = name
                window.recipeScroll:SetVerticalScroll(0)
                refresh()
            end,
        }
    end
    window.rosterLabel:SetText(("%d/%d online"):format(online, total))
    window.renderPlayers(players)

    local rows = {}
    local title = L["No results"]
    if current then
        local member = roster[current.name]
        title = member and member.displayName or current.name:match("^[^-]+")
    end
    if current and current.updated then title = title .. "   ·   " .. date("%d.%m.%Y %H:%M", current.updated) end
    window.memberLabel:SetText(title)
    for _, profession in ipairs(current and current.professions or {}) do
        local entry = profession.entry
        local key = current.name .. ":" .. profession.id
        local opened = query ~= "" or expanded[key]
        rows[#rows + 1] = {
            text = profession.name .. (opened and "  −" or "  +"),
            color = gold, icon = professionIcons[profession.id],
            skill = entry.skill, maximum = entry.maximum, professionID = profession.id,
            action = function()
                expanded[key] = not expanded[key]
                refresh()
            end,
        }
        if opened then
            local recipes = profession.recipes
            if not recipes then
                recipes = {}
                for id in pairs(entry.recipes) do
                    recipes[#recipes + 1] = { text = recipeName(id), recipe = id }
                end
            end
            local groups, titles = {}, {}
            for _, recipe in ipairs(recipes) do
                local category, icon, color, skill, level = recipePresentation(recipe.recipe, recipe.text, profession.id)
                if not groups[category] then
                    groups[category] = {}
                    titles[#titles + 1] = category
                end
                local entries = groups[category]
                entries[#entries + 1] = { text = recipe.text, recipe = recipe.recipe, icon = icon, color = color,
                    requiredSkill = skill or math.huge, requiredLevel = level or math.huge,
                    crafter = current.name, professionID = profession.id }
            end
            table.sort(titles)
            for _, category in ipairs(titles) do
                local categoryKey = key .. ":" .. category
                local collapsed = collapsedCategories[categoryKey] == true
                rows[#rows + 1] = {
                    text = category, color = gold, category = true, collapsed = collapsed,
                    action = function()
                        collapsedCategories[categoryKey] = not collapsed or nil
                        refresh()
                    end,
                }
                if not collapsed then
                    local entries = groups[category]
                    table.sort(entries, function(a, b)
                        if a.requiredSkill ~= b.requiredSkill then return a.requiredSkill < b.requiredSkill end
                        if a.requiredLevel ~= b.requiredLevel then return a.requiredLevel < b.requiredLevel end
                        if a.text ~= b.text then return a.text < b.text end
                        return a.recipe < b.recipe
                    end)
                    for _, recipe in ipairs(entries) do rows[#rows + 1] = recipe end
                end
            end
            if #recipes == 0 then
                local status = entry.scanned and (L["No recipes recorded"])
                    or (L["Recipes not scanned yet"])
                rows[#rows + 1] = { text = "    " .. status, color = muted }
            end
            rows[#rows + 1] = { text = "" }
        end
    end
    if current and #rows == 0 then
        rows[1] = { text = L["No profession data received yet."], color = muted }
    end
    window.renderRecipes(rows)
end

local function heading(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function button(parent, text, width, x, y, action)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 24)
    control:SetPoint("TOPLEFT", x, y)
    control:SetText(text)
    control:SetScript("OnClick", action)
    return control
end

local addonIcon = "Interface\\AddOns\\ForeverGuild\\Art\\ForeverGuildEmblem"
local exportFrame

local function showDiagnostics()
    if uiInCombat() then return end
    if not exportFrame then
        exportFrame = CreateFrame("Frame", "ForeverGuildDiagnosticsWindow", UIParent, "PortraitFrameTemplate")
        exportFrame:SetSize(740, 460)
        exportFrame:SetPoint("CENTER")
        exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        exportFrame:SetClampedToScreen(true)
        exportFrame:SetTitle(L["ForeverGuild · Diagnostic export"])
        exportFrame:SetPortraitToAsset(addonIcon)
        table.insert(UISpecialFrames, "ForeverGuildDiagnosticsWindow")
        heading(exportFrame, L["Press Ctrl+C to copy the selected log."], 18, -43)
        local scroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -66)
        scroll:SetPoint("BOTTOMRIGHT", -35, 14)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetWidth(685)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
        scroll:SetScrollChild(edit)
        exportFrame.edit = edit
    end
    local version, build, _, interface = GetBuildInfo()
    local lines = { ("ForeverGuild %s | WoW %s (%s), Interface %s | %s"):format(
        addonVersion, tostring(version), tostring(build), tostring(interface), GetLocale()) }
    for _, entry in ipairs(ForeverGuildDiagnostics or {}) do
        lines[#lines + 1] = ("%s [%s] %s: %s"):format(date("%Y-%m-%d %H:%M:%S", entry.at),
            entry.level, entry.area, entry.detail)
    end
    local edit = exportFrame.edit
    edit:SetText(table.concat(lines, "\n"))
    edit:SetHeight(math.max(350, #lines * 22))
    exportFrame:Show()
    edit:SetFocus()
    edit:HighlightText()
end

local function iconTooltip(control, title, detail)
    control:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if detail then GameTooltip:AddLine(detail, 1, 1, 1) end
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local roleAtlas = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"

local function roleControl(parent, role, x, y)
    local control = CreateFrame("CheckButton", nil, parent)
    control:SetSize(64, 60)
    control:SetPoint("TOPLEFT", x, y)
    local art = control:CreateTexture(nil, "ARTWORK")
    art:SetSize(64, 64)
    art:SetPoint("CENTER", 0, 2)
    art:SetTexture(roleAtlas)
    local cell = 67 / 256
    art:SetTexCoord(role.column * cell, (role.column + 1) * cell,
        role.row * cell, (role.row + 1) * cell)
    local check = control:CreateTexture(nil, "OVERLAY")
    check:SetSize(19, 19)
    check:SetPoint("BOTTOMLEFT", 2, 3)
    local checkbox = control:CreateTexture(nil, "ARTWORK", nil, 2)
    checkbox:SetAllPoints(check)
    checkbox:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    control:SetCheckedTexture(check)
    control:SetDisabledCheckedTexture(check)
    local function update()
        local active = control:GetChecked()
        art:SetAlpha(active and 1 or .78)
    end
    function control:Select(checked)
        self:SetChecked(checked)
        update()
    end
    iconTooltip(control, role.label)
    control:HookScript("OnEnter", function() art:SetAlpha(1) end)
    control:HookScript("OnLeave", update)
    return control
end

local function talentCard(parent, width, x, y, action, wide)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(width, wide and 46 or 83)
    card:SetPoint("TOPLEFT", x, y)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2} })
    card:SetBackdropColor(.064, .040, .026, 1)
    local background = card:CreateTexture(nil, "ARTWORK")
    background:SetPoint("TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", -3, 3)
    background:SetTexCoord(.04, .94, .05, wide and .31 or .65)
    local veil = card:CreateTexture(nil, "ARTWORK", nil, 1)
    veil:SetAllPoints(background)
    veil:SetColorTexture(1, 1, 1, 1)
    if wide then
        veil:SetGradient("HORIZONTAL", CreateColor(.07, .045, .03, .76), CreateColor(.07, .045, .03, .12))
    else
        veil:SetGradient("VERTICAL", CreateColor(.07, .045, .03, .93), CreateColor(.07, .045, .03, .12))
    end

    local medallion = CreateFrame("Frame", nil, card)
    medallion:SetSize(38, 38)
    if wide then medallion:SetPoint("LEFT", 9, 0) else medallion:SetPoint("TOP", 0, -7) end
    local function circularTexture(size, layer)
        local texture = medallion:CreateTexture(nil, "ARTWORK", nil, layer)
        texture:SetSize(size, size)
        texture:SetPoint("CENTER")
        local mask = medallion:CreateMaskTexture()
        mask:SetAllPoints(texture)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        texture:AddMaskTexture(mask)
        return texture
    end
    local rim = circularTexture(38, 0)
    rim:SetColorTexture(1, 1, 1, 1)
    local inset = circularTexture(34, 1)
    inset:SetColorTexture(.085, .049, .025, 1)
    local icon = circularTexture(30, 2)
    icon:SetTexCoord(.08, .92, .08, .92)
    function card:SetTalentArt(texture, backdrop)
        icon:SetTexture(texture)
        background:SetTexture(backdrop or "Interface\\DialogFrame\\UI-DialogBox-Background")
    end

    local label = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", wide and 57 or 5, wide and -3 or -53)
    label:SetPoint("BOTTOMRIGHT", wide and -27 or -5, 4)
    label:SetJustifyH(wide and "LEFT" or "CENTER")
    if wide then label:SetFontObject(GameFontHighlight) end
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(true)
    function card:SetTitle(title) label:SetText(title) end
    local check = card:CreateTexture(nil, "OVERLAY")
    check:SetSize(18, 18)
    if wide then check:SetPoint("RIGHT", -10, 0) else check:SetPoint("TOPRIGHT", -4, -4) end
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    function card:Select(selected)
        self.selected = selected
        self:SetBackdropBorderColor(selected and .95 or .44, selected and .68 or .28, selected and .28 or .14)
        label:SetTextColor(1, selected and .83 or .94, selected and .38 or .83)
        background:SetAlpha(selected and .95 or .66)
        check:SetShown(selected)
        rim:SetGradient("VERTICAL", CreateColor(.33, .20, .10, 1),
            selected and CreateColor(1, .80, .41, 1) or CreateColor(.69, .50, .29, 1))
    end
    card:Select(false)
    card:SetScript("OnClick", action)
    card:SetScript("OnEnter", function()
        if card:IsEnabled() then background:SetAlpha(1) end
    end)
    card:SetScript("OnLeave", function() background:SetAlpha(card.selected and .95 or .66) end)
    return card
end

local function sideTab(parent, index, icon, title, action)
    local ok, tab = pcall(CreateFrame, "Frame", nil, parent, "LargeSideTabButtonTemplate")
    if not ok then
        tab = panel(parent)
        tab:SetSize(50, 50)
        tab.Icon = tab:CreateTexture(nil, "ARTWORK")
        tab.Icon:SetPoint("TOPLEFT", 3, -3)
        tab.Icon:SetPoint("BOTTOMRIGHT", -3, 3)
        tab.SelectedTexture = tab:CreateTexture(nil, "OVERLAY")
        tab.SelectedTexture:SetAllPoints()
        tab.SelectedTexture:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        tab.SelectedTexture:SetBlendMode("ADD")
        tab.SelectedTexture:SetVertexColor(1, .76, .25)
    end
    tab.fillToInterior = false
    tab:ClearAllPoints()
    if index > 0 then
        tab:SetPoint("TOPLEFT", parent, "TOPRIGHT", -6, -60 - (index - 1) * (tab:GetHeight() + 2))
    else
        tab:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", -6, 60 + (-index - 1) * (tab:GetHeight() + 2))
    end
    tab:SetFrameLevel(parent:GetFrameLevel() + 5)
    tab.Icon:ClearAllPoints()
    tab.Icon:SetPoint("CENTER", tab, "CENTER", -1, 0)
    tab.Icon:SetSize(42, 42)
    tab.Icon:SetTexture(icon)
    tab.Icon:SetTexCoord(0, 1, 0, 1)
    selectSideTab(tab, false)
    local click = CreateFrame("Button", nil, tab)
    click:SetAllPoints()
    click:SetScript("OnClick", action)
    iconTooltip(click, title)
    return tab
end

local function buildRosterView()
    local root = panel(window, 0)
    window.rosterView = root
    root:SetPoint("TOPLEFT", 14, -46)
    root:SetPoint("BOTTOMRIGHT", -14, 13)
    pageBackdrop(root, "GuildHall", 1.5, .85)
    local members = contrastPanel(root)
    members:SetPoint("TOPLEFT", 9, -9)
    members:SetPoint("BOTTOMLEFT", 9, 9)
    members:SetPoint("TOPRIGHT", root, "TOPRIGHT", -353, -9)
    local guildBanner = contrastPanel(members)
    guildBanner:SetPoint("TOPLEFT", 10, -10)
    guildBanner:SetPoint("TOPRIGHT", -10, -10)
    guildBanner:SetHeight(54)
    local emblem = guildBanner:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(46, 46)
    emblem:SetPoint("LEFT", 8, 0)
    emblem:SetTexture("Interface\\AddOns\\ForeverGuild\\Art\\TabRoster")
    window.rosterGuildName = heading(guildBanner, "", 62, -9)
    window.rosterGuildName:SetFontObject(GameFontNormalLarge)
    local guildStats = CreateFrame("Frame", nil, guildBanner)
    guildStats:SetPoint("TOPRIGHT", -10, -8)
    guildStats:SetPoint("BOTTOMRIGHT", -10, 8)
    guildStats:SetWidth(250)
    guildStats.counts = guildStats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guildStats.counts:SetPoint("TOPRIGHT")
    guildStats.counts:SetJustifyH("RIGHT")
    guildStats.leaders = guildStats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    guildStats.leaders:SetPoint("BOTTOMRIGHT")
    guildStats.leaders:SetJustifyH("RIGHT")
    guildStats.leaders:SetWidth(250)
    guildStats.leaders:SetWordWrap(false)
    guildStats:SetScript("OnEnter", function(self)
        if not self.officers or #self.officers == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(L["Officers"])
        for _, name in ipairs(self.officers) do GameTooltip:AddLine(name, 1, 1, 1) end
        GameTooltip:Show()
    end)
    guildStats:SetScript("OnLeave", function() GameTooltip:Hide() end)
    window.rosterGuildStats = guildStats
    window.rosterGuildName:SetPoint("RIGHT", guildStats, "LEFT", -8, 0)
    window.rosterGuildName:SetJustifyH("LEFT")
    window.rosterGuildName:SetWordWrap(false)
    heading(guildBanner, L["Guild members"], 63, -32)
    local filter = CreateFrame("EditBox", nil, members, "InputBoxTemplate")
    filter:SetSize(352, 24)
    filter:SetPoint("TOPLEFT", 19, -74)
    filter:SetAutoFocus(false)
    filter:SetScript("OnEscapePressed", filter.ClearFocus)
    filter:SetScript("OnTextChanged", refresh)
    window.rosterSearch = filter
    local online = CreateFrame("CheckButton", nil, members, "UICheckButtonTemplate")
    online:SetPoint("TOPLEFT", 382, -69)
    online:SetScript("OnClick", refresh)
    heading(members, L["Online only"], 412, -80)
    window.onlineOnly = online
    local headers = {
        { L["Level"], 37, "level", 0 }, { "Name", 99, "displayName", .27 },
        { L["Class"], 65, "className", .14 }, { L["Guild rank"], 73, "rankIndex", .16 },
        { L["Roles"], 56, nil, .15 }, { L["Specialization"], 91, "spec", .28 },
        { "Status", 50, "online", 0 }, { "Sync", 41, nil, 0 },
    }
    window.rosterColumns = {}
    for index, header in ipairs(headers) do
        local label, key = header[1], header[3]
        local column = CreateFrame("Button", nil, members)
        column:SetHeight(24)
        window.rosterColumns[index] = { control = column }
        local text = heading(column, label, 0, -5)
        if key then
            column:SetScript("OnClick", function()
                window.rosterReverse = window.rosterSort == key and not window.rosterReverse
                window.rosterSort = key
                refresh()
            end)
            column:SetScript("OnEnter", function() text:SetTextColor(1, .96, .77) end)
            column:SetScript("OnLeave", function() text:SetTextColor(1, .82, .24) end)
        end
    end
    local function layoutColumns()
        local extra = math.max(0, members:GetWidth() - 584)
        local x = 7
        for index, header in ipairs(headers) do
            local field = window.rosterColumns[index]
            field.x, field.width = x, header[2] + math.floor(extra * header[4])
            field.control:ClearAllPoints()
            field.control:SetPoint("TOPLEFT", 10 + x, -105)
            field.control:SetWidth(field.width)
            x = x + field.width
        end
    end
    layoutColumns()
    members:HookScript("OnSizeChanged", function()
        layoutColumns()
        if window.renderRoster then refresh() end
    end)
    local rule = members:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 13, -129)
    rule:SetPoint("TOPRIGHT", -35, -129)
    rule:SetHeight(1)
    rule:SetColorTexture(.53, .36, .18, .8)

    window.rosterSort, window.rosterReverse = "online", true
    local pinnedScroll
    window.renderPinnedMember, pinnedScroll = list(members, 10, -134, -36, 0, 538, 23)
    pinnedScroll:ClearAllPoints()
    pinnedScroll:SetPoint("TOPLEFT", 10, -134)
    pinnedScroll:SetPoint("TOPRIGHT", -36, -134)
    pinnedScroll:SetHeight(23)
    if pinnedScroll.ScrollBar then pinnedScroll.ScrollBar:Hide() end
    pinnedScroll:EnableMouseWheel(false)
    window.renderRoster = list(members, 10, -159, -36, 14, 538, 23)

    local detailPanel = panel(root, 0, nil, .53)
    detailPanel:SetPoint("TOPLEFT", members, "TOPRIGHT", 7, 0)
    detailPanel:SetPoint("BOTTOMRIGHT", -9, 9)
    local detailScroll = CreateFrame("ScrollFrame", nil, detailPanel, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", 9, -9)
    detailScroll:SetPoint("BOTTOMRIGHT", -29, 9)
    local details = CreateFrame("Frame", nil, detailScroll)
    details:SetSize(299, 1)
    detailScroll:SetScrollChild(details)
    window.rosterDetailScroll = detailScroll

    local profileCard = contrastPanel(details)
    profileCard:SetPoint("TOPLEFT")
    profileCard:SetPoint("TOPRIGHT")
    profileCard:SetHeight(126)
    window.rosterName = profileCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    window.rosterName:SetPoint("TOPLEFT", 12, -11)
    window.rosterName:SetPoint("RIGHT", -10, 0)
    window.rosterName:SetJustifyH("LEFT")
    local function field(caption, x, y, width)
        local label = profileCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", x, y)
        label:SetText(caption)
        local value = profileCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPLEFT", x, y - 14)
        value:SetWidth(width)
        value:SetJustifyH("LEFT")
        value:SetWordWrap(false)
        return value
    end
    window.profileRank = field(L["Guild rank"], 12, -40, 125)
    window.profileClass = field(L["Class and level"], 154, -40, 133)
    window.profilePresence = field(L["Location"], 12, -82, 135)
    window.profileSync = field(L["Profession sync"], 154, -82, 133)

    local careers = contrastPanel(details)
    careers:SetPoint("TOPLEFT", profileCard, "BOTTOMLEFT", 0, -8)
    careers:SetPoint("TOPRIGHT", profileCard, "BOTTOMRIGHT", 0, -8)
    heading(careers, L["Professions"], 12, -9)
    local careerRows = {}
    local controls = CreateFrame("Frame", nil, details)
    controls:SetPoint("TOPLEFT", careers, "BOTTOMLEFT", 0, -8)
    controls:SetSize(299, 296)
    window.renderProfileProfessions = function(professions)
        local rows = professions
        if #rows == 0 then rows = {{ name = L["No profession data available"] }} end
        for index, entry in ipairs(rows) do
            local row = careerRows[index]
            if not row then
                row = CreateFrame("Frame", nil, careers)
                row:SetPoint("TOPLEFT", 8, -29 - (index - 1) * 24)
                row:SetPoint("TOPRIGHT", -8, -29 - (index - 1) * 24)
                row:SetHeight(22)
                local shade = row:CreateTexture(nil, "BACKGROUND")
                shade:SetAllPoints()
                shade:SetColorTexture(.31, .20, .10, index % 2 == 0 and .18 or .07)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(17, 17)
                row.icon:SetPoint("LEFT", 5, 0)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.name:SetPoint("LEFT", 29, 0)
                row.skill = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.skill:SetPoint("RIGHT", -8, 0)
                careerRows[index] = row
            end
            row.icon:SetTexture(entry.icon)
            row.name:SetText(entry.name)
            row.skill:SetText(entry.skill and ("%d / %d"):format(entry.skill, entry.maximum) or "")
            row:Show()
        end
        for i = #rows + 1, #careerRows do careerRows[i]:Hide() end
        local height = 34 + #rows * 24
        careers:SetHeight(height)
        details:SetHeight(126 + 8 + height + 8 + 296)
        detailScroll:SetVerticalScroll(math.min(detailScroll:GetVerticalScroll(),
            math.max(0, details:GetHeight() - detailScroll:GetHeight())))
    end
    window.rosterRecipes = button(controls, L["Show recipes"], 122, 2, 0, function()
        if not rosterSelected then return end
        selected = rosterSelected
        search:SetText("")
        window.recipeScroll:SetVerticalScroll(0)
        activeTab = "professions"
        refresh()
    end)
    window.rosterWhisper = button(controls, L["Whisper"], 82, 126, 0, function()
        local member = roster[rosterSelected]
        if member and ChatFrame_SendTell then ChatFrame_SendTell(member.target) end
    end)
    window.rosterInvite = button(controls, L["Invite"], 86, 210, 0, function()
        local member = roster[rosterSelected]
        local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
        if member and invite then invite(member.target) end
    end)
    window.rolesHeading = heading(controls, "", 1, -41)
    window.roleChecks, window.specButtons = {}, {}
    for index, role in ipairs(roles) do
        local x = (299 - 64) / 2 + (index - 2) * 84
        local check = roleControl(controls, role, x, -63)
        window.roleChecks[index] = check
        check:SetScript("OnClick", function(self)
            local mask = memberMask(rosterSelected)
            local wasSet = hasRole(mask, role.bit)
            local isSet = self:GetChecked() and true or false
            if isSet ~= wasSet then
                editMember(rosterSelected, mask + (isSet and role.bit or -role.bit), ownSpec(rosterSelected))
            end
            refresh()
        end)
    end
    for index = 1, 3 do
        local choice = index
        local control = talentCard(controls, 295, 2, -133 - (index - 1) * 52, function()
            local current = ownSpec(rosterSelected)
            editMember(rosterSelected, memberMask(rosterSelected), current == choice and 0 or choice)
            refresh()
        end, true)
        window.specButtons[index] = control
    end
end

local setupDialog, setupMask, setupSpec

local function prepareProfessionButtons(dialog)
    if InCombatLockdown and InCombatLockdown() then
        dialog.status:SetText(L["Open professions after combat."])
        return
    end
    updateSkills()
    local spells = {}
    if GetProfessions and GetProfessionInfo and C_SpellBook and C_SpellBook.GetSpellBookItemInfo
        and Enum and Enum.SpellBookSpellBank then
        for _, index in pairs({ GetProfessions() }) do
            local _, _, _, _, _, offset, id = GetProfessionInfo(index)
            if id and offset then
                local entry = C_SpellBook.GetSpellBookItemInfo(offset + 1, Enum.SpellBookSpellBank.Player)
                if entry then spells[id] = entry.spellID end
            end
        end
    end
    local count, missing = 0, 0
    for _, id in ipairs(craftingProfessions) do
        if ForeverGuildCharacter[id] then
            if spells[id] then
                count = count + 1
                local control = dialog.professionButtons[count]
                if not control then
                    control = CreateFrame("Button", nil, dialog.professionArea, "UIPanelButtonTemplate,SecureActionButtonTemplate")
                    control:SetSize(210, 23)
                    control:SetPoint("TOPLEFT", 16 + ((count - 1) % 2) * 222, -26 * math.floor((count - 1) / 2))
                    control:RegisterForClicks("AnyUp", "AnyDown")
                    control:SetAttribute("type", "spell")
                    dialog.professionButtons[count] = control
                end
                control:SetAttribute("spell", spells[id])
                control:SetText(professionName(id))
                control:Show()
            else
                missing = missing + 1
            end
        end
    end
    for index = count + 1, #dialog.professionButtons do dialog.professionButtons[index]:Hide() end
    if count == 0 then
        dialog.status:SetText(L["Open your professions in the spellbook, then click Sync guild."])
    elseif missing > 0 then
        dialog.status:SetText(L["Click each profession. Open any missing professions in the spellbook."])
    else
        dialog.status:SetText(L["Click each profession separately, then sync the guild."])
    end
end

local function showSetup()
    if uiInCombat() then return end
    if not player then return end
    local class = roster[player] and roster[player].class
    if not class and UnitClass then
        local _, classFile = UnitClass("player")
        class = classFile
    end
    if not setupDialog then
        local dialog = CreateFrame("Frame", "ForeverGuildSetupWindow", UIParent, "PortraitFrameTemplate")
        setupDialog = dialog
        dialog:SetSize(500, 566)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetClampedToScreen(true)
        dialog:SetTitle(L["ForeverGuild · Character setup"])
        dialog:SetPortraitToAsset(addonIcon)
        table.insert(UISpecialFrames, "ForeverGuildSetupWindow")

        local body = panel(dialog)
        body:SetPoint("TOPLEFT", 12, -47)
        body:SetPoint("BOTTOMRIGHT", -12, 12)
        dialog.character = heading(body, "", 17, -17)
        local subtitle = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        subtitle:SetPoint("TOPLEFT", 17, -39)
        subtitle:SetPoint("RIGHT", -17, 0)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetText(L["Choose your roles and current specialization for the guild roster."])
        dialog.roles, dialog.specs = {}, {}
        for index, role in ipairs(roles) do
            local x = (476 - 64) / 2 + (index - 2) * 105
            local check = roleControl(body, role, x, -63)
            check:SetScript("OnClick", function(self)
                local checked = self:GetChecked() and true or false
                if checked ~= hasRole(setupMask, role.bit) then
                    setupMask = setupMask + (checked and role.bit or -role.bit)
                end
                self:Select(checked)
            end)
            dialog.roles[index] = check
        end
        heading(body, L["Specialization"], 17, -128)
        for index = 1, 3 do
            local choice = index
            local control = talentCard(body, 143, 16 + (index - 1) * 148, -147, function()
                setupSpec = setupSpec == choice and 0 or choice
                for i, specButton in ipairs(dialog.specs) do specButton:Select(setupSpec == i) end
            end)
                dialog.specs[index] = control
        end
        dialog.professionArea = CreateFrame("Frame", nil, body)
        dialog.professionArea:SetPoint("TOPLEFT", 0, -331)
        dialog.professionArea:SetPoint("BOTTOMRIGHT", 0, 45)
        dialog.professionButtons = {}
        dialog.scan = button(body, L["Scan professions"], 210, 16, -267, function()
            prepareProfessionButtons(dialog)
        end)
        dialog.sync = button(body, L["Sync guild"], 210, 238, -267, function()
            if requestSync() then
                dialog.status:SetText(L["Guild sync requested."])
            else
                schedulePublish(math.max(1, 4 - (GetTime() - lastPublish)))
                dialog.status:SetText(L["Profession data queued for publication."])
            end
        end)
        dialog.status = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dialog.status:SetPoint("TOPLEFT", 17, -301)
        dialog.status:SetPoint("RIGHT", -17, 0)
        dialog.status:SetJustifyH("LEFT")
        dialog.save = button(body, L["Save"], 112, 347, -472, function()
            editMember(player, setupMask, setupSpec)
            refresh()
            dialog:Hide()
        end)
        button(body, L["Later"], 100, 240, -472, function() dialog:Hide() end)
    end
    setupMask, setupSpec = memberMask(player), ownSpec(player)
    setupDialog.character:SetText(roster[player] and roster[player].displayName or player:match("^[^-]+"))
    for index, check in ipairs(setupDialog.roles) do check:Select(hasRole(setupMask, roles[index].bit)) end
    for index, control in ipairs(setupDialog.specs) do
        local label = specName(class, index)
        control:SetShown(label ~= nil)
        control:SetTitle(label or "")
        if label then control:SetTalentArt(specializationArt(class, index, true)) end
        control:Select(setupSpec == index)
    end
    setupDialog.status:SetText("")
    setupDialog.scan:SetEnabled(database ~= nil)
    setupDialog.sync:SetEnabled(database ~= nil and registered == true)
    setupDialog.save:SetEnabled(canEditMember(player))
    setupDialog:Show()
end

local function maybeShowSetup()
    if not UIParent or not preference("setupPrompt") or not canEditMember(player) or ForeverGuildSetupShown
        or (InCombatLockdown and InCombatLockdown()) then return end
    if memberMask(player) ~= 0 or ownSpec(player) ~= 0 then return end
    showSetup()
    ForeverGuildSetupShown = true
end

local function showSettings()
    if uiInCombat() then return end
    if settingsWindow then
        settingsWindow:SetShown(not settingsWindow:IsShown())
        return
    end
    local dialog = CreateFrame("Frame", "ForeverGuildSettingsWindow", UIParent, "PortraitFrameTemplate")
    settingsWindow = dialog
    dialog:SetSize(690, 397)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetTitle(L["ForeverGuild · Settings"])
    dialog:SetPortraitToAsset(addonIcon)
    table.insert(UISpecialFrames, "ForeverGuildSettingsWindow")

    local sidebar = panel(dialog)
    sidebar:SetPoint("TOPLEFT", 12, -52)
    sidebar:SetPoint("BOTTOMLEFT", 12, 13)
    sidebar:SetWidth(154)
    local content = panel(dialog)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    content:SetPoint("BOTTOMRIGHT", -13, 13)
    heading(sidebar, "v" .. addonVersion, 15, -306)

    local pages, navigation = {}, {}
    local function page(title)
        local index = #pages + 1
        local section = CreateFrame("Frame", nil, content)
        section:SetAllPoints()
        pages[index] = section
        heading(section, title, 17, -16)
        local tab = button(sidebar, title, 134, 10, -13 - (index - 1) * 34, function()
            for i, item in ipairs(pages) do
                item:SetShown(i == index)
                navigation[i]:SetEnabled(i ~= index)
            end
        end)
        navigation[index] = tab
        section:SetShown(index == 1)
        tab:SetEnabled(index ~= 1)
        return section
    end
    local function paragraph(parent, message, y)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 18, y)
        label:SetPoint("RIGHT", -18, 0)
        label:SetJustifyH("LEFT")
        label:SetText(message)
        return label
    end
    local function checkbox(parent, title, detail, y, enabled, update)
        local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 15, y)
        heading(parent, title, 45, y - 9)
        paragraph(parent, detail, y - 31)
        check:SetChecked(enabled)
        check:SetScript("OnClick", function(self) update(self:GetChecked() and true or false) end)
        return check
    end
    local function setPreference(key, value)
        ForeverGuildSettings = ForeverGuildSettings or {}
        ForeverGuildSettings[key] = value
    end

    local general = page(L["General"])
    checkbox(general, L["Show minimap icon"],
        L["Left-click opens ForeverGuild. Right-click opens the diagnostic export."],
        -47, preference("minimap"), function(value)
            setPreference("minimap", value)
            if minimapIcon then minimapIcon:SetShown(value) end
        end)
    checkbox(general, L["First-login setup prompt"],
        L["Shown once for a character without roles or a specialization."],
        -108, preference("setupPrompt"), function(value) setPreference("setupPrompt", value) end)
    checkbox(general, L["Guild button opens ForeverGuild"],
        L["Opens ForeverGuild from the guild icon on the WoW menu bar."],
        -169, ForeverGuildSettings and ForeverGuildSettings.guildShortcut == true, function(value)
            setPreference("guildShortcut", value)
            updateGuildShortcut()
        end)
    button(general, L["Character setup"], 184, 17, -238, function()
        dialog:Hide()
        showSetup()
    end)
    paragraph(general, L["Commands: /fguild · /fguild setup · /fguild settings"], -280)

    local sync = page(L["Guild sync"])
    checkbox(sync, L["Periodic guild sync"],
        L["Requests updated guild data about every five minutes."],
        -47, preference("periodicSync"), function(value) setPreference("periodicSync", value) end)
    local scan = checkbox(sync, L["Open professions automatically"],
        L["Optional per character. WoW may block automatic opening."],
        -108, ForeverGuildBackgroundScan == true, function(value)
            ForeverGuildBackgroundScan = value
            if value then queueBackgroundScan(.5)
            elseif backgroundScan then backgroundScan.ids = {} end
        end)
    paragraph(sync, L["Opening a profession normally captures its recipes. Received profiles remain available locally."], -180)
    local status = paragraph(sync, "", -268)
    button(sync, L["Sync now"], 156, 17, -224, function()
        local requested = requestSync()
        if database and registered then
            status:SetText(requested and (L["Guild sync requested."])
                or (L["A sync was requested less than 20 seconds ago."]))
        else
            status:SetText(L["The guild channel is currently unavailable."])
        end
    end)

    local bankSettings = page(L["Guild bank"])
    checkbox(bankSettings, L["Request guild snapshot automatically"],
        L["Requests the latest shared stock when ForeverGuild or the bank tab opens."],
        -47, preference("bankAutoRequest"), function(value) setPreference("bankAutoRequest", value) end)
    checkbox(bankSettings, L["Share bank stock automatically"],
        L["Shares scanned tabs and the balance with the entire guild."],
        -120, preference("bankShare"), function(value)
            setPreference("bankShare", value)
            if guildBank then guildBank.beginScan() end
        end)
    paragraph(bankSettings, L["Sharing includes tabs that only certain ranks can view directly in WoW."], -193)
    button(bankSettings, L["Request guild snapshot"], 183, 17, -243, function()
        requestBankSnapshot()
    end)

    local info = page(L["Info and diagnostics"])
    local state = paragraph(info, "", -48)
    paragraph(info, L["The diagnostic log retains up to 400 events per character. Copy the export when troubleshooting."], -121)
    button(info, L["Export diagnostics"], 177, 17, -174, function()
        dialog:Hide()
        showDiagnostics()
    end)
    paragraph(info, L["Roles and specialization belong to each character. Guild masters and officers can edit them for other members."], -226)
    local function updateInfo()
        local profiles = 0
        for _ in pairs(database or {}) do profiles = profiles + 1 end
        scan:SetChecked(ForeverGuildBackgroundScan == true)
        state:SetText((L["Version %s\nReceived profession profiles: %d\nDiagnostic entries: %d"]):format(
            addonVersion, profiles, #(ForeverGuildDiagnostics or {})))
    end
    info:SetScript("OnShow", updateInfo)
    dialog:SetScript("OnShow", updateInfo)
    updateInfo()
end

local function resizeMainWindow()
    if not window then return end
    local width, height = UIParent:GetSize()
    window:SetSize(math.min(1248, math.max(960, width - 96)),
        math.min(767, math.max(590, height - 24)))
end

local function guildAPI(method, legacy)
    return (C_GuildInfo and C_GuildInfo[method]) or (legacy and _G[legacy])
end

local function guildPermission(method)
    local check = guildAPI(method, method)
    if not check then return false end
    local ok, allowed = pcall(check)
    return ok and (allowed == true or allowed == 1)
end

local function readGuildNote(memberKey, officerNote)
    if not guildKey or guildIdentity() ~= guildKey or not memberKey
        or not GetNumGuildMembers or not GetGuildRosterInfo then return end
    if officerNote and not guildPermission("CanViewOfficerNote") then return end
    for index = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, public, private, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(index)
        if type(name) == "string" and fullName(name) == memberKey then
            return (officerNote and (private or "") or (public or "")), index, guid
        end
    end
end

local function openNativeGuild()
    local native = _G.GuildMicroButton or _G.CommunitiesMicroButton
    if native and native.Click then
        native:Click()
        return true
    end
    local open = _G.ToggleGuildFrame or _G.ToggleCommunitiesFrame
    if open then open(); return true end
    return false
end

local function writeGuildField(kind, target, value)
    if not guildKey or guildIdentity() ~= guildKey then return false end
    if kind == "motd" then
        local action = guildAPI("SetMOTD", "GuildSetMOTD")
        if action and guildPermission("CanEditMOTD") then return action(value) ~= false end
        return false
    end
    local isOfficer = kind == "officer"
    local permission = isOfficer and "CanEditOfficerNote" or "CanEditPublicNote"
    if not guildPermission(permission) then return false end
    local _, index, guid = readGuildNote(target, isOfficer)
    if not index then return false end
    if guid and C_GuildInfo and C_GuildInfo.SetNote then
        return C_GuildInfo.SetNote(guid, value, not isOfficer) ~= false
    end
    local action = isOfficer and _G.GuildRosterSetOfficerNote or not isOfficer and _G.GuildRosterSetPublicNote
    if action then return action(index, value) ~= false end
    return false
end

local function buildGuildAdmin()
    local admin = panel(window, 0)
    window.admin = admin
    admin:SetPoint("TOPLEFT", 14, -46)
    admin:SetPoint("BOTTOMRIGHT", -14, 13)
    pageBackdrop(admin, "GuildAdministration", 1.5, .88)
    local members = contrastPanel(admin)
    members:SetPoint("TOPLEFT", 17, -51)
    members:SetPoint("BOTTOMLEFT", 17, 17)
    members:SetWidth(252)
    heading(admin, L["Guild management"], 16, -16)
    local direct = button(admin, L["Open WoW guild management"], 235, 0, 0, function()
        local ok, opened = pcall(openNativeGuild)
        if ok and opened then window:Hide()
        else admin.status:SetText(L["Could not open the WoW guild window."]) end
    end)
    direct:ClearAllPoints()
    direct:SetPoint("TOPRIGHT", -14, -10)

    local filter = CreateFrame("EditBox", nil, members, "InputBoxTemplate")
    filter:SetSize(218, 25)
    filter:SetPoint("TOPLEFT", 15, -12)
    filter:SetAutoFocus(false)
    filter:SetScript("OnEscapePressed", filter.ClearFocus)
    local renderMembers = list(members, 8, -46, -26, 9, 218, 23)
    local content = contrastPanel(admin)
    content:SetPoint("TOPLEFT", members, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", -17, 17)
    admin.status = heading(content, "", 14, -324)
    local subject = heading(content, "", 14, -130)
    local selection, previous, previousGuild
    local function editor(title, y, kind, limit)
        heading(content, title, 14, y)
        local input = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", 19, y - 24)
        input:SetPoint("TOPRIGHT", -145, y - 24)
        input:SetHeight(27)
        input:SetMaxBytes(limit)
        input:SetAutoFocus(false)
        input:SetScript("OnEscapePressed", input.ClearFocus)
        local save = button(content, L["Save"], 110, 0, 0, function()
            local target = selection
            admin.lastEdit = GetTime()
            admin.blockedEdit = false
            local ok, sent = pcall(writeGuildField, kind, target, input:GetText())
            if admin.blockedEdit then return end
            if not ok or not sent then
                admin.status:SetText(L["Unable to edit. Use the WoW guild window."])
                diagnose("WARN", "guild admin", kind .. " update rejected")
            else
                admin.status:SetText(L["Change submitted to WoW."])
                diagnose("INFO", "guild admin", kind .. " update requested")
                input:ClearFocus()
            end
        end)
        save:ClearAllPoints()
        save:SetPoint("LEFT", input, "RIGHT", 12, 0)
        return { input = input, button = save }
    end
    local motd = editor(L["Guild message of the day"], -15, "motd", 128)
    local public = editor(L["Public note"], -161, "public", 31)
    local officer = editor(L["Officer note"], -238, "officer", 31)
    local function setEditor(slot, value, editable, reset)
        if reset or not editable then slot.input:ClearFocus() end
        if not slot.input:HasFocus() then slot.input:SetText(value or "") end
        slot.input:EnableMouse(editable)
        slot.button:SetEnabled(editable)
    end

    local rights = addon.buildBoardRights(admin)
    local partners = addon.buildGuildPartners(admin)
    local adminTab = 1
    local tabs = {}
    for index, caption in ipairs({L["Overview"], L["Roles & permissions"], L["Partner guilds"]}) do
        local tab = CreateFrame("Button", nil, admin)
        tab:SetSize(145, 31)
        tab:SetPoint("TOPLEFT", 177 + (index-1)*147, -8)
        local texture = tab:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER")
        label:SetText(caption)
        tab:SetScript("OnClick", function()
            adminTab = index
            window.refreshAdmin()
        end)
        tabs[index] = function(active)
            texture:SetTexture("Interface\\AddOns\\ForeverGuild\\Art\\BoardHeaderTab" .. (active and "Active" or "Idle"))
            label:SetTextColor(active and 1 or .83, active and .85 or .74, active and .50 or .61)
        end
    end

    window.refreshAdmin = function()
        for index, selectTab in ipairs(tabs) do selectTab(index == adminTab) end
        members:SetShown(adminTab == 1)
        content:SetShown(adminTab == 1)
        direct:SetShown(adminTab == 1)
        rights:SetShown(adminTab == 2)
        partners:SetShown(adminTab == 3)
        if adminTab == 2 then rights.load(); return end
        if adminTab == 3 then partners.load(); return end
        local changedGuild = previousGuild ~= guildKey
        if changedGuild then
            selection, previous = nil, nil
            previousGuild = guildKey
            admin.status:SetText("")
        end
        local query, names, rows = utf8Lower(filter:GetText()), {}, {}
        for name, member in pairs(roster) do
            if utf8Lower(member.displayName):find(query, 1, true) then names[#names + 1] = name end
        end
        table.sort(names)
        if not selection or not roster[selection] then selection = names[1] end
        for _, name in ipairs(names) do
            local member = roster[name]
            rows[#rows + 1] = { text = member.displayName, selected = selection == name, action = function()
                selection = name
                admin.status:SetText("")
                window.refreshAdmin()
            end }
        end
        renderMembers(rows)
        local getMOTD = guildAPI("GetMOTD", "GetGuildRosterMOTD")
        local selected = selection and roster[selection]
        local reset = previous ~= selection or changedGuild
        previous = selection
        subject:SetText(selected and selected.displayName or (L["No member selected"]))
        local publicText, publicIndex, publicGuid = readGuildNote(selection, false)
        local officerText, officerIndex, officerGuid = readGuildNote(selection, true)
        local setNote = C_GuildInfo and C_GuildInfo.SetNote
        setEditor(motd, database and getMOTD and getMOTD(),
            database ~= nil and guildAPI("SetMOTD", "GuildSetMOTD") ~= nil and guildPermission("CanEditMOTD"), changedGuild)
        setEditor(public, publicText, publicIndex ~= nil and guildPermission("CanEditPublicNote")
            and ((publicGuid ~= nil and setNote ~= nil) or _G.GuildRosterSetPublicNote ~= nil), reset)
        setEditor(officer, officerText, officerIndex ~= nil and guildPermission("CanEditOfficerNote")
            and ((officerGuid ~= nil and setNote ~= nil) or _G.GuildRosterSetOfficerNote ~= nil), reset)
    end
    filter:SetScript("OnTextChanged", window.refreshAdmin)
end

local function orderItemTooltip(frame)
    local item = frame.entry
    if not item or not item.itemID then return end
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink("item:" .. item.itemID)
    GameTooltip:Show()
end

local function materialRows(recipe, quantity)
    if not recipe then return {} end
    local materials = orderBook.materials(recipe)
    if not materials then
        return {{ text = L["Materials are unavailable. Check with the crafter."] }}
    end
    if #materials == 0 then
        return {{ text = L["No required materials listed."] }}
    end
    local getName = C_Item and C_Item.GetItemNameByID
    local rows = {}
    for _, slot in ipairs(materials) do
        for index, id in ipairs(slot.items) do
            recipeItemDetails(id)
            local cached = itemDetails[id]
            local name = (cached and cached.name) or (getName and getName(id)) or ("Item #" .. id)
            local alternative = index > 1 and (L["   or "]) or ""
            rows[#rows + 1] = { itemID = id, text = ("%s%d × %s"):format(alternative, slot.count * quantity, name) }
        end
    end
    return rows
end

local function orderText(parent, x, y, right)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetPoint("RIGHT", -right, 0)
    label:SetJustifyH("LEFT")
    label:SetSpacing(4)
    return label
end

local function sendOrderMessage(target, message)
    if not orderChannel or not database or guildKey ~= guildIdentity() then return false end
    -- WoW enforces guild membership for the transport. Targeted packets are
    -- routed by the receiving addon, never sent as cross-guild whispers.
    if target then
        local member = roster[roleMemberKey(target)]
        if not member or not member.online then return false end
        message = "T:" .. member.target .. ":" .. message
    end
    if #message > 255 then return false end
    local ok, result = pcall(chat.SendAddonMessage, orderBook.prefix, message, "GUILD")
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    return ok and (result == nil or result == success or result == true)
end

local function broadcastOrder(message)
    return sendOrderMessage(nil, message)
end

local function orderClock()
    return GetServerTime and GetServerTime() or time()
end

function addon.boardPolicySend(packet)
    if not orderChannel or not database or guildKey ~= guildIdentity() then return end
    local member = roster[player]
    if addon.boardRights.receive(guildKey, player, packet, member and member.rankIndex == 0,
        function(kind) return addon.boardMayModerate(kind) end, orderClock()) then
        broadcastOrder(packet)
        queueRefresh()
        return true
    end
end

function addon.boardSetHidden(kind, owner, token, hide)
    if not addon.boardMayModerate(kind) or not guildKey then return end
    local previous = addon.boardRights.store(guildKey).hidden[kind .. "/" .. owner .. "/" .. token]
    local revision = math.max(orderClock() * 1000, (previous and previous.revision or 0) + 1)
    return addon.boardPolicySend(("P:Y:%s:%s:%.0f:%d:%s"):format(kind, token, revision, hide and 1 or 0, owner))
end

function addon.boardModerate(kind, owner, token)
    return addon.boardSetHidden(kind, owner, token, true)
end

function addon.boardRestore(kind, owner, token)
    return addon.boardSetHidden(kind, owner, token, false)
end

function addon.buildBoardRights(admin)
    local body = contrastPanel(admin)
    body:SetPoint("TOPLEFT", 17, -51)
    body:SetPoint("BOTTOMRIGHT", -17, 17)
    admin.rights = body
        local rolesList = { L["Member defaults"], L["Board moderators"], L["Dungeon planners"], L["Order moderators"] }
        local roleDescriptions = { L["This profile applies to every guild member. Assigned roles add to these permissions."], L["For members who oversee crafting orders, dungeon events and announcements on the bulletin board."], L["For members who organize dungeon events and moderate other members’ events when needed."], L["For members who oversee open crafting orders on the bulletin board. Direct orders are separate."] }
        local role, selected = 1, nil
        local filters, permissions, assignments = {}, {}, {}
        heading(body, L["Role profile"], 16, -18)
        local rolePanel = contrastPanel(body)
        rolePanel:SetPoint("TOPLEFT", 14, -41)
        rolePanel:SetSize(218, 223)
        heading(body, L["Permissions"], 253, -18)
        heading(body, L["Guild members"], 558, -18)
        local function actionButton(label, width, x, y, callback)
            local control = CreateFrame("Button", nil, body, "BackdropTemplate")
            control:SetSize(width, 27)
            control:SetPoint("TOPLEFT", x, y)
            control:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10})
            control:SetBackdropColor(.16, .11, .07, 1)
            control:SetBackdropBorderColor(.57, .41, .24, 1)
            control:SetNormalFontObject(GameFontNormal)
            control:SetDisabledFontObject(GameFontDisable)
            control:SetHighlightFontObject(GameFontHighlight)
            control:SetText(label)
            control:SetScript("OnClick", callback)
            return control
        end
        for idx, caption in ipairs(rolesList) do
            filters[idx] = actionButton(caption, 178, 21, -50 - (idx-1)*43, function()
                role = idx
                body.load()
            end)
            local help = CreateFrame("Button", nil, body)
            help:SetSize(18, 22)
            help:SetPoint("LEFT", filters[idx], "RIGHT", 2, 0)
            local mark = help:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            mark:SetPoint("CENTER")
            mark:SetText("!")
            mark:SetTextColor(1, .82, 0)
            help:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
                GameTooltip:SetText(caption)
                GameTooltip:AddLine(roleDescriptions[idx], 1, 1, 1, true)
                local mask = guildKey and addon.boardRights.mask(guildKey, idx) or 0
                GameTooltip:AddLine(L["Currently enabled for this role"], 1, .82, 0, true)
                local any
                for _, entry in ipairs(addon.boardRights.labels) do
                    local flag = addon.boardRights.flags[entry[1]]
                    if math.floor(mask / flag) % 2 == 1 then
                        GameTooltip:AddLine(entry[de and 2 or 3], .85, .85, .85, true)
                        any = true
                    end
                end
                if not any then GameTooltip:AddLine(L["None"], .8, .8, .8) end
                GameTooltip:Show()
            end)
            help:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        for idx, entry in ipairs(addon.boardRights.labels) do
            local check = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", 251, -41 - (idx-1)*30)
            heading(body, entry[de and 2 or 3], 281, -49 - (idx-1)*30)
            permissions[idx] = check
        end
        local function revision(previous)
            return math.max(orderClock()*1000, (previous and previous.revision or 0) + 1)
        end
        local function master()
            return roster[player] and roster[player].rankIndex == 0 and guildKey == guildIdentity() and orderChannel
        end
        local saveRole = actionButton(L["Save role permissions"], 175, 253, -237, function()
            if not master() then return end
            local mask = 0
            for idx, check in ipairs(permissions) do
                if check:GetChecked() then mask = mask + addon.boardRights.flags[addon.boardRights.labels[idx][1]] end
            end
            local previous = addon.boardRights.store(guildKey).roles[role]
            addon.boardPolicySend(("P:R:%d:%d:%.0f"):format(role, mask, revision(previous)))
            body.load()
        end)
        local function rankNames()
            local names, highest = {}, 0
            for _, member in pairs(roster) do
                if member.rankIndex then
                    names[member.rankIndex] = names[member.rankIndex] or member.rank
                    highest = math.max(highest, member.rankIndex)
                end
            end
            return names, highest
        end
        local officerButton = actionButton("", 196, 21, -226, function()
            if not master() then return end
            local _, highest = rankNames()
            local current = addon.boardRights.officerRank(guildKey) or 0
            local nextValue = current + 1
            if nextValue >= highest then nextValue = 0 end
            local previous = addon.boardRights.store(guildKey).officer
            addon.boardPolicySend(("P:O:%d:%.0f"):format(nextValue, revision(previous)))
            body.load()
        end)
        officerButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText(L["Officer ranks"])
            GameTooltip:AddLine(L["Sets which guild ranks count as officers. “Automatic” detects ranks named Officer."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        officerButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local members = contrastPanel(body)
        members:SetPoint("TOPLEFT", 555, -41)
        members:SetPoint("BOTTOMRIGHT", -14, 99)
        local render = list(members, 7, -7, -28, 8, 302, 22)
        for idx = 2, 4 do
            local check = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
            check:SetPoint("BOTTOMLEFT", 12+(idx-2)*209, 53)
            heading(check, rolesList[idx], 28, -9)
            assignments[idx] = check
        end
        local feedback = orderText(body, 17, -292, 14)
        local saveMember = actionButton(L["Save assignment"], 175, 0, 0, function()
            if not master() or not roster[selected] then return end
            local mask = 0
            for idx, check in pairs(assignments) do if check:GetChecked() then mask = mask + 2^(idx-2) end end
            local previous = addon.boardRights.store(guildKey).members[selected]
            addon.boardPolicySend(("P:M:%d:%.0f:%s"):format(mask, revision(previous), selected))
            body.load()
        end)
        saveMember:ClearAllPoints()
        saveMember:SetPoint("BOTTOMRIGHT", -15, 14)
        body.load = function()
            if not guildKey then return end
            local editable = not not master()
            local mask = addon.boardRights.mask(guildKey, role)
            for idx, check in ipairs(permissions) do
                local flag = addon.boardRights.flags[addon.boardRights.labels[idx][1]]
                check:SetChecked(math.floor(mask/flag)%2 == 1)
                check:SetEnabled(editable)
            end
            for idx, control in ipairs(filters) do
                local active = idx == role
                control:SetBackdropColor(active and .28 or .12, active and .18 or .08, active and .09 or .05, 1)
                control:SetBackdropBorderColor(active and .88 or .44, active and .62 or .30, .19, 1)
            end
            local keys, rows = {}, {}
            for key in pairs(roster) do keys[#keys+1] = key end
            table.sort(keys, function(a,b) return roster[a].displayName < roster[b].displayName end)
            if not roster[selected] then selected = keys[1] end
            for _, key in ipairs(keys) do
                rows[#rows+1] = {text = roster[key].displayName, selected = selected == key,
                    action = function() selected = key; body.load() end}
            end
            render(rows)
            local assigned = selected and addon.boardRights.memberMask(guildKey, selected) or 0
            for idx, check in pairs(assignments) do
                check:SetChecked(math.floor(assigned/(2^(idx-2)))%2 == 1)
                check:SetEnabled(editable and selected ~= nil)
            end
            saveMember:SetEnabled(editable and selected ~= nil)
            saveRole:SetEnabled(editable)
            local limit = addon.boardRights.officerRank(guildKey)
            local names = rankNames()
            officerButton:SetText(limit and ((L["Officers: up to %s"]):format(names[limit] or ("#" .. limit)))
                or (L["Officers: automatic"]))
            officerButton:SetEnabled(editable)
            local text = editable and (L["Select a member and assign roles below."])
                or (L["The guild master can edit permissions."])
            -- Officers may publish announcements only until the base profile is saved once;
            -- make that implicit rule visible instead of letting it change silently.
            local baseSaved = addon.boardRights.store(guildKey).roles[1] ~= nil
            local baseNews = math.floor(addon.boardRights.mask(guildKey, 1) / addon.boardRights.flags.news) % 2 == 1
            if not baseSaved then
                text = text .. "\n" .. (L["Officers may publish announcements until the member defaults are saved once."])
            elseif not baseNews then
                text = text .. "\n" .. (L["Officers no longer have their own announcement right – assign a role if needed."])
            end
            feedback:SetText(text)
        end
    body:Hide()
    return body
end

function addon.partnerMaster()
    return guildKey and guildKey == guildIdentity() and roster[player] and roster[player].rankIndex == 0
end

-- The character that handles partner messages: the guild master, or a relay the guild
-- master chose (e.g. a twink on the same account, which shares the saved partner data).
function addon.partnerRelay()
    local state = guildKey and addon.guildPartners.store(guildKey)
    return state and state.relay or player
end

function addon.partnerActive()
    if not guildKey or guildKey ~= guildIdentity() or not roster[player] then return false end
    if roster[player].rankIndex == 0 then return true end
    local relay = addon.guildPartners.store(guildKey).relay
    return relay ~= nil and utf8Lower(fullName(relay)) == utf8Lower(player)
end

addon.partnerProbedAt = {}
function addon.sendPartnerMessage(target, packet)
    if not addon.partnerActive() or not orderChannel or not chat or not chat.SendAddonMessage then return false end
    addon.partnerProbedAt[utf8Lower(target)] = GetTime()
    local ok, result = pcall(chat.SendAddonMessage, orderBook.prefix, packet, "WHISPER", target)
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    return ok and (result == nil or result == true or result == success)
end

do
    local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    local format = ERR_CHAT_PLAYER_NOT_FOUND_S
    if addFilter and format then
        local pattern = "^" .. (format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%s", "(.+)")) .. "$"
        addFilter("CHAT_MSG_SYSTEM", function(_, _, message)
            local name = type(message) == "string" and message:match(pattern)
            local probed = name and (addon.partnerProbedAt[utf8Lower(name)] or addon.partnerProbedAt[utf8Lower(fullName(name))])
            return probed ~= nil and GetTime() - probed < 5
        end)
    end
end

function addon.buildGuildPartners(admin)
    local pane = contrastPanel(admin)
    pane:SetPoint("TOPLEFT", 17, -51)
    pane:SetPoint("BOTTOMRIGHT", -17, 17)
    local left = contrastPanel(pane)
    left:SetPoint("TOPLEFT", 10, -10)
    left:SetPoint("BOTTOMLEFT", 10, 10)
    left:SetWidth(290)
    heading(left, L["Partner guilds"], 13, -12)
    local render = list(left, 8, -43, -26, 8, 250, 26)
    local right = contrastPanel(pane)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", -10, 10)

    local function input(y, caption)
        heading(right, caption, 14, y)
        local box = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", 19, y - 23)
        box:SetPoint("TOPRIGHT", -18, y - 23)
        box:SetHeight(26)
        box:SetAutoFocus(false)
        box:SetMaxBytes(235)
        box:SetScript("OnEscapePressed", box.ClearFocus)
        return box
    end
    local ownID = orderText(right, 14, -13, 14)
    local code = input(-42, L["Your connection code · Ctrl+C to copy"])
    local incoming = input(-110, L["Other guild’s connection code"])
    local preview = orderText(right, 14, -180, 14)
    local status = orderText(right, 14, -276, 14)
    local relayInput = input(-318, L["Relay (guild master or a twink on this account)"])
    relayInput:SetPoint("TOPRIGHT", -150, -341)
    local relaySave = button(right, L["Apply"], 120, 0, 0, function()
        if not addon.partnerMaster() then return end
        local name = relayInput:GetText():match("^%s*(.-)%s*$")
        addon.guildPartners.store(guildKey).relay = name ~= "" and fullName(name) or nil
        relayInput:ClearFocus()
        pane.load()
    end)
    relaySave:ClearAllPoints()
    relaySave:SetPoint("LEFT", relayInput, "RIGHT", 10, 0)
    local selected
    local function describe(peer, now)
        local state = addon.guildPartners.status(peer, now)
        local seen = peer.lastSeen and date("%d.%m. %H:%M", peer.lastSeen)
        local suffix = seen and ((L[" · last seen "]) .. seen) or ""
        if state == "disconnected" then return L["Disconnected"] end
        if state == "waiting" then return L["Waiting for the other guild"] end
        if state == "inactive" then return (L["Inactive"]) .. suffix end
        if state == "unreachable" then return (L["Confirmed · Relay unavailable"]) .. suffix end
        return L["Connected"]
    end
    local confirm = button(right, L["Confirm connection"], 188, 14, -227, function()
        if not addon.partnerMaster() or not orderChannel then return end
        local peer = addon.guildPartners.approve(guildKey, incoming:GetText(), orderClock(), addon.sendPartnerMessage)
        if peer then
            selected = peer.id
            incoming:ClearFocus()
            incoming:SetText("")
            pane.load()
        end
    end)
    local remove = button(right, L["Disconnect"], 170, 216, -227, function()
        if not addon.partnerMaster() or not orderChannel or not selected then return end
        addon.guildPartners.disconnect(guildKey, selected, orderClock(), addon.sendPartnerMessage)
        pane.load()
    end)
    local ownCode, lastGuild
    code:SetScript("OnTextChanged", function(self)
        if ownCode and self:GetText() ~= ownCode then self:SetText(ownCode) end
    end)
    code:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    local function updatePreview()
        local decoded = addon.guildPartners.decode(incoming:GetText())
        local valid = decoded and guildKey and decoded.id ~= addon.guildPartners.id(guildKey)
        confirm:SetEnabled(not not (valid and addon.partnerMaster() and orderChannel))
        if valid then
            local ownRealm = guildKey and guildKey:match("^([^:]+):")
            local hint = ownRealm and decoded.realm ~= ownRealm and ("\n" .. (L["Different realm: only works if the realms are connected and players can whisper each other."])) or ""
            preview:SetText(("%s · %s\n%s %s%s"):format(decoded.name, decoded.realm,
                L["Relay:"], decoded.relay, hint))
        elseif incoming:GetText() ~= "" then
            preview:SetText(L["Invalid or own connection code."])
        else
            preview:SetText(L["Both guild masters must confirm the other guild’s code."])
        end
    end
    incoming:SetScript("OnTextChanged", updatePreview)
    pane.load = function()
        if lastGuild ~= guildKey then
            lastGuild, selected = guildKey, nil
            incoming:SetText("")
        end
        local master = addon.partnerMaster()
        local relay = master and (addon.guildPartners.store(guildKey).relay or roster[player].target or player)
        ownCode = relay and addon.guildPartners.code(guildKey, relay) or ""
        if code:GetText() ~= ownCode then code:SetText(ownCode) end
        ownID:SetText(guildKey and ((L["Guild ID: "]) .. addon.guildPartners.id(guildKey)) or "")
        code:SetEnabled(ownCode ~= "")
        incoming:SetEnabled(not not master)
        if guildKey and not relayInput:HasFocus() then
            relayInput:SetText(addon.guildPartners.store(guildKey).relay or player or "")
        end
        relayInput:SetEnabled(not not master)
        relaySave:SetEnabled(not not master)
        updatePreview()
        local saved = guildKey and (master and addon.guildPartners.store(guildKey).peers
            or addon.guildPartners.store(guildKey).known) or {}
        local keys, rows = {}, {}
        for id in pairs(saved) do keys[#keys + 1] = id end
        table.sort(keys, function(a, b) return saved[a].name < saved[b].name end)
        if not saved[selected] then selected = keys[1] end
        for _, id in ipairs(keys) do
            rows[#rows + 1] = { text = saved[id].name .. " · " .. saved[id].realm,
                selected = selected == id, action = function() selected = id; pane.load() end }
        end
        if #rows == 0 then rows[1] = { text = L["No connections configured."], color = muted } end
        render(rows)
        local peer = saved[selected]
        remove:SetEnabled(not not (peer and peer.consent and orderChannel))
        if not master then
            local known = peer and (peer.active and (L["Active partner guild"])
                or (L["Not active"]))
            status:SetText((known and (peer.name .. " · " .. known .. "\n") or "")
                .. (L["Only the guild master can establish a connection."]))
        elseif peer then
            status:SetText(peer.name .. " · " .. describe(peer, orderClock()))
        else
            status:SetText(L["The connection does not share bulletin board posts yet."])
        end
    end
    pane:Hide()
    return pane
end

function addon.partnerTick()
    local now = orderClock()
    if (addon.nextVersionShare or 0) <= now then
        addon.nextVersionShare = now + 600
        broadcastOrder("P:V:" .. addonVersion)
    end
    local notes = addon.boardNotes.records(guildKey)
    local _, flags = addon.guildPartners.events(guildKey)
    addon.partnerFlagNext = addon.partnerFlagNext or {}
    local own, sent = {}, 0
    for id, at in pairs(flags) do
        local note = notes[id]
        if not note or note.ends <= now then
            if at < now - 31 * 86400 then flags[id] = nil end
        elseif note.kind == "G" and not addon.boardRights.hidden(guildKey, note.kind, note.owner, note.token) then
            own[#own + 1] = { owner = note.owner, token = note.token, ends = note.ends, closed = note.closed,
                activity = note.activity, title = note.title }
            if note.owner == player and sent < 2 and (addon.partnerFlagNext[id] or 0) <= now then
                addon.partnerFlagNext[id] = now + 300
                broadcastOrder("P:S:" .. note.token)
                sent = sent + 1
            end
        end
    end
    if addon.partnerActive() then
        addon.guildPartners.relayEvents(guildKey, own, now, addon.sendPartnerMessage, broadcastOrder)
    end
end

local function dispatchOrders()
    if orderChannel and database and guildKey == guildIdentity() then
        local now = orderClock()
        orderBook.sharePending(guildKey, roster, broadcastOrder, now)
        orderBook.sendStatuses(guildKey, roster, sendOrderMessage, now)
        if orderBook.dispatch(guildKey, roster, sendOrderMessage, now) and activeTab == "orders" then
            queueRefresh()
        end
    end
end

local nextOrderRegistration = 0
local function pollOrders()
    if guildKey and not orderChannel and GetTime() >= nextOrderRegistration then
        nextOrderRegistration = GetTime() + 60
        orderChannel = registerMessagePrefix(orderBook.prefix)
    end
    if orderBook.hasPending(guildKey) or orderBook.hasRelay(guildKey) or orderBook.hasStatusPending(guildKey) then
        updateRoster()
        dispatchOrders()
        if orderChannel and database and guildKey == guildIdentity() then
            orderBook.deliverRelays(guildKey, roster, sendOrderMessage, orderClock())
        end
    end
    if orderChannel and database and guildKey == guildIdentity() then
        addon.board.tick(guildKey, player, orderClock(),
            function(key) return roster[key] and roster[key].online end, broadcastOrder, sendOrderMessage)
        addon.boardNotes.tick(guildKey, player, orderClock(), addon.boardCan("news"), broadcastOrder)
        addon.boardRights.tick(guildKey, player, roster[player] and roster[player].rankIndex == 0, orderClock(),
            function(kind) return addon.boardMayModerate(kind) end, broadcastOrder)
        if addon.partnerActive() then addon.guildPartners.tick(guildKey, orderClock(), addon.sendPartnerMessage) end
        if addon.partnerMaster() then addon.guildPartners.shareKnown(guildKey, orderClock(), broadcastOrder) end
        addon.partnerTick()
        local master = roster[player] and roster[player].rankIndex == 0
        addon.boardRights.prune(guildKey, orderClock(), master, next(roster) and function(key) return roster[key] ~= nil end)
        if activeTab == "board" or activeTab == "admin" then queueRefresh() end
    end
    after(15 + math.random(0, 8), pollOrders)
end

local function showOrderConfirmation(key, token)
    if activeTab == "orders" then queueRefresh() end
    local dialog = orderDialog
    if dialog and dialog.delivery and dialog.delivery.key == key and dialog.delivery.token == token then
        dialog.prepare:SetEnabled(false)
        dialog.status:SetText(L["The crafter received the order."])
    end
end

local function acceptOrder(origin, message, address)
    local token, created = orderBook.accept(origin, message, address, guildKey)
    if created then
        if updateOrderNotice then updateOrderNotice() end
        if activeTab == "orders" then queueRefresh() end
        local member = roster[origin]
        print((L["ForeverGuild · New crafting order from %s."])
            :format(member and member.displayName or origin))
    end
    return token
end

local function receiveOrderMessage(sender, message)
    local destination, payload = message:match("^T:([^:%c]+):(.+)$")
    if destination and fullName(destination) ~= player then return end
    local key = roleMemberKey(sender)
    if key == player or not database or guildKey ~= guildIdentity() then return end
    if not roster[key] then
        updateRoster()
        key = roleMemberKey(sender)
    end
    if not roster[key] then return end
    local boardPacket = payload or message
    local fromMaster = roster[key].rankIndex == 0
    if not destination and boardPacket:sub(1, 4) == "P:V:" then
        local version = boardPacket:match("^P:V:(%d+%.%d+%.%d+)$")
        if version then addon.memberVersions[key] = version end
        return
    end
    if not destination and boardPacket:sub(1, 4) == "P:S:" then
        local token = boardPacket:match("^P:S:(%d+%-%d+)$")
        if token and #token <= 24 then
            local _, flags = addon.guildPartners.events(guildKey)
            flags[key .. "/" .. token] = orderClock()
        end
        return
    end
    if not destination and boardPacket:sub(1, 4) == "P:Q:" then
        addon.guildPartners.receiveRelay(guildKey, boardPacket, fromMaster)
        return
    end
    if not destination and boardPacket:sub(1, 4) == "P:F:" then
        local relay = addon.guildPartners.store(guildKey).announcedRelay
        local trusted = fromMaster or (relay ~= nil and utf8Lower(fullName(relay)) == utf8Lower(key))
        if addon.guildPartners.receiveGuildEvent(guildKey, boardPacket, trusted, orderClock()) and activeTab == "board" then
            queueRefresh()
        end
        return
    end
    if boardPacket:sub(1, 4) == "P:G:" then
        if not destination and addon.guildPartners.receiveKnown(guildKey, boardPacket, roster[key].rankIndex == 0, orderClock())
            and activeTab == "admin" then queueRefresh() end
        return
    end
    if boardPacket:sub(1, 2) == "P:" then
        if not destination and addon.boardRights.receive(guildKey, key, boardPacket, roster[key].rankIndex == 0,
            function(kind) return addon.boardMayModerate(kind, key) end, orderClock()) then
            queueRefresh()
            if window and window.admin and window.admin.rights and window.admin.rights:IsVisible() then window.admin.rights.load() end
        end
        return
    end
    if boardPacket:sub(1, 2) == "M:" then
        local token, closed = boardPacket:match("^M:N:([^:]+):G:%d+:([01]):")
        if token and not addon.boardCan("group", key)
            and (closed ~= "1" or not addon.boardNotes.records(guildKey)[key .. "/" .. token]) then return end
        if not destination and addon.boardNotes.receive(guildKey, key, boardPacket, addon.boardCan("news", key), orderClock())
            and activeTab == "board" then queueRefresh() end
        return
    end
    if boardPacket:sub(1, 2) == "B:" then
        if not destination and not addon.boardCan("order", key) then
            local token = boardPacket:match("^B:S:(%d+%-%d+):") or boardPacket:match("^B:V:%d+:(%d+%-%d+):")
            if not token or not addon.board.records(guildKey)[key .. "/" .. token] then return end
        end
        if addon.board.receive(guildKey, player, key, boardPacket, destination ~= nil, broadcastOrder)
            and activeTab == "board" then queueRefresh() end
        return
    end
    local now = orderClock()

    if not destination then
        local confirmedToken, original = message:match("^K:(%d+%-%d+):([^:%c]+)$")
        if confirmedToken and #original < 130 then
            local origin = roleMemberKey(original)
            if orderBook.ackRelay(guildKey, origin, confirmedToken, key, now, origin == player) and origin == player then
                showOrderConfirmation(key, confirmedToken)
            end
            return
        end
        local kind, token, recipe, quantity, target = orderBook.parseRelay(message, now)
        if kind ~= "Q" then return end
        local recipient = roleMemberKey(target)
        if recipient == player then
            if acceptOrder(key, ("O:%s:%d:%d"):format(token, recipe, quantity), sender) then
                broadcastOrder("K:" .. token .. ":" .. key)
            end
        elseif recipient ~= key and roster[recipient] then
            if orderBook.relayReceipt(guildKey, key, token, recipient, now) then
                sendOrderMessage(sender, "D:" .. token .. ":" .. recipient)
            else
                orderBook.cacheRelay(guildKey, key, recipient, token, recipe, quantity, now)
            end
        end
        return
    end

    message = payload
    local statusToken, statusVersion, statusFlag = message:match("^C:(%d+%-%d+):(%d+):([01])$")
    if statusToken then
        local revision = tonumber(statusVersion)
        if #statusToken > 24 or revision < 1 or revision > 2147483647 then return end
        local order, notify = orderBook.receiveStatus(statusToken, key, revision, statusFlag == "1", guildKey)
        if order then
            sendOrderMessage(sender, ("F:%s:%d"):format(statusToken, revision))
            if updateOrderNotice then updateOrderNotice() end
            if activeTab == "orders" then queueRefresh() end
            if notify then
                local member = roster[key]
                print((L["ForeverGuild · %s marked your order for %s as complete."])
                    :format(member and member.displayName or key, recipeName(order.recipe)))
            end
        end
        return
    end
    local statusAck, acknowledgedVersion = message:match("^F:(%d+%-%d+):(%d+)$")
    if statusAck then
        orderBook.ackStatus(statusAck, key, tonumber(acknowledgedVersion), guildKey)
        return
    end
    local receipt, relayedRecipient = message:match("^D:(%d+%-%d+):([^:%c]+)$")
    if receipt then
        local recipient = roleMemberKey(relayedRecipient)
        if roster[recipient] and orderBook.confirm(receipt, recipient, guildKey) then showOrderConfirmation(recipient, receipt) end
        return
    end
    local ack = message:match("^A:(%d+%-%d+)$")
    if ack then
        if orderBook.confirm(ack, key, guildKey) then showOrderConfirmation(key, ack) end
        return
    end

    local kind, token, recipe, quantity, original = orderBook.parseRelay(message, now)
    if kind == "R" then
        local origin = roleMemberKey(original)
        local member = roster[origin]
        if origin ~= player and member and acceptOrder(origin, ("O:%s:%d:%d"):format(token, recipe, quantity), member.target) then
            broadcastOrder("K:" .. token .. ":" .. origin)
        end
        return
    end
    token = acceptOrder(key, message, sender)
    if token then
        sendOrderMessage(sender, "A:" .. token)
        broadcastOrder("K:" .. token .. ":" .. key)
    end
end

showOrderDialog = function(recipe, owner, professionID, boardOnly)
    if uiInCombat() then return end
    local crafters = {}
    if boardOnly then
        -- Open orders do not need a preselected crafter.
    elseif owner and owner ~= player then
        crafters[1] = owner
    else
        for name, profile in pairs(database or {}) do
            local profession = profile.professions[professionID]
            if name ~= player and roster[name] and profession and profession.recipes[recipe] then
                crafters[#crafters + 1] = name
            end
        end
        table.sort(crafters)
    end
    if not orderDialog then
        local dialog = CreateFrame("Frame", "ForeverGuildOrderWindow", UIParent, "PortraitFrameTemplate")
        orderDialog = dialog
        dialog:SetSize(560, 488)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetClampedToScreen(true)
        dialog:SetPortraitToAsset(addonIcon)
        dialog:SetTitle(L["ForeverGuild · Crafting order"])
        table.insert(UISpecialFrames, "ForeverGuildOrderWindow")
        local body = panel(dialog)
        body:SetPoint("TOPLEFT", 12, -45)
        body:SetPoint("BOTTOMRIGHT", -12, 13)
        pageBackdrop(body, "GuildAdministration", 1.5, .88)

        local hero = contrastPanel(body)
        hero:SetPoint("TOPLEFT", 10, -10)
        hero:SetPoint("TOPRIGHT", -10, -10)
        hero:SetHeight(66)
        hero:EnableMouse(true)
        hero:SetScript("OnEnter", recipeTooltip)
        hero:SetScript("OnLeave", function() GameTooltip:Hide() end)
        dialog.hero = hero
        dialog.itemIcon = hero:CreateTexture(nil, "ARTWORK")
        dialog.itemIcon:SetSize(42, 42)
        dialog.itemIcon:SetPoint("LEFT", 12, 0)
        dialog.itemIcon:SetTexCoord(.06, .94, .06, .94)
        dialog.name = heading(hero, "", 65, -13)
        dialog.name:SetFontObject(GameFontNormalLarge)
        dialog.name:SetPoint("RIGHT", hero, "RIGHT", -12, 0)
        dialog.name:SetJustifyH("LEFT")
        dialog.name:SetWordWrap(false)
        dialog.subtitle = heading(hero, "", 66, -40)

        local fields = contrastPanel(body)
        fields:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -8)
        fields:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -8)
        fields:SetHeight(60)
        heading(fields, L["Crafter"], 12, -9)
        heading(fields, L["Crafts"], 376, -9)
        local quantity = CreateFrame("EditBox", nil, fields, "InputBoxTemplate")
        quantity:SetSize(103, 23)
        quantity:SetPoint("TOPLEFT", 382, -26)
        quantity:SetAutoFocus(false)
        quantity:SetNumeric(true)
        quantity:SetMaxLetters(3)
        quantity:SetScript("OnEscapePressed", quantity.ClearFocus)
        dialog.quantity = quantity
        local function update()
            local count = tonumber(quantity:GetText())
            local days = tonumber(dialog.boardDays:GetText())
            local target = dialog.crafters[dialog.crafterIndex]
            local member = target and roster[target]
            dialog.targetName:SetText(dialog.boardOnly and (L["Open to the guild"])
                or (member and member.displayName or target or (L["No crafter found"])))
            local canSwitch = #dialog.crafters > 1
            dialog.target:SetEnabled(canSwitch)
            dialog.targetArrow:SetShown(canSwitch)
            dialog.renderMaterials(materialRows(dialog.recipe, count and count >= 1 and count <= 200 and count or 1))
            dialog.prepare:SetEnabled(database ~= nil and target ~= nil and count ~= nil and count >= 1 and count <= 200)
            dialog.prepare:SetShown(not dialog.boardOnly)
            dialog.post:SetEnabled(addon.boardCan("order") and database ~= nil and orderChannel and count ~= nil and count >= 1 and count <= 200
                and days ~= nil and days >= 1 and days <= 30 and days % 1 == 0)
            dialog.delivery = nil
            dialog.status:SetText(dialog.boardOnly
                and (L["The deadline applies while the order is open."])
                or (L["If the crafter is offline, the order stays queued."]))
        end
        local crafter = panel(fields, .5, nil, .95)
        crafter:SetPoint("TOPLEFT", 12, -27)
        crafter:SetSize(342, 23)
        dialog.targetName = heading(crafter, "", 8, -5)
        dialog.targetName:SetPoint("RIGHT", crafter, "RIGHT", -25, 0)
        dialog.targetName:SetWordWrap(false)
        dialog.targetName:SetJustifyH("LEFT")
        dialog.targetArrow = heading(crafter, "›", 0, 0)
        dialog.targetArrow:ClearAllPoints()
        dialog.targetArrow:SetPoint("RIGHT", -9, 0)
        dialog.target = CreateFrame("Button", nil, crafter)
        dialog.target:SetAllPoints()
        local hover = dialog.target:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(.82, .53, .20, .17)
        iconTooltip(dialog.target, L["Switch to the next crafter"])
        dialog.target:SetScript("OnClick", function()
            if #dialog.crafters < 2 then return end
            dialog.crafterIndex = dialog.crafterIndex % #dialog.crafters + 1
            update()
        end)

        local materials = contrastPanel(body)
        materials:SetPoint("TOPLEFT", fields, "BOTTOMLEFT", 0, -8)
        materials:SetPoint("TOPRIGHT", fields, "BOTTOMRIGHT", 0, -8)
        materials:SetPoint("BOTTOM", 0, 153)
        heading(materials, L["Required materials"], 12, -10)
        dialog.renderMaterials = list(materials, 9, -28, -30, 9, 477, 20, orderItemTooltip)
        dialog.refreshMaterials = function()
            local count = tonumber(quantity:GetText())
            dialog.renderMaterials(materialRows(dialog.recipe, count and count >= 1 and count <= 200 and count or 1))
        end
        local footer = contrastPanel(body)
        footer:SetPoint("TOPLEFT", materials, "BOTTOMLEFT", 0, -8)
        footer:SetPoint("BOTTOMRIGHT", -10, 10)
        dialog.status = orderText(footer, 12, -9, 12)
        dialog.status:SetFontObject(GameFontHighlightSmall)
        dialog.status:SetTextColor(.87, .77, .63)
        dialog.prepare = button(footer, L["Send order"], 163, 0, 0, function()
            local key = dialog.crafters[dialog.crafterIndex]
            if not key or not database or guildKey ~= guildIdentity() then return end
            local target = roster[key] and roster[key].target or key
            local count = tonumber(quantity:GetText())
            local _, token = orderBook.packet(dialog.recipe, count)
            if not token then return end
            dialog.delivery = { key = key, token = token }
            orderBook.track(token, key, dialog.recipe, count, dialog.professionID, target, guildKey)
            dialog.prepare:SetEnabled(false)
            if orderChannel then
                dialog.status:SetText(L["Order saved. Online guild clients can forward it to the crafter."])
            else
                dialog.status:SetText(L["Order saved. ForeverGuild is waiting for the addon channel."])
            end
            if activeTab == "orders" then queueRefresh() end
            dispatchOrders()
        end)
        dialog.prepare:ClearAllPoints()
        dialog.prepare:SetPoint("BOTTOMRIGHT", -10, 8)
        local supplies = CreateFrame("CheckButton", nil, footer, "UICheckButtonTemplate")
        supplies:SetPoint("TOPLEFT", 9, -29)
        heading(footer, L["I provide the materials"], 39, -37)
        local note = CreateFrame("EditBox", nil, footer, "InputBoxTemplate")
        note:SetSize(217, 23)
        note:SetPoint("TOPRIGHT", -12, -32)
        note:SetMaxBytes(68)
        note:SetAutoFocus(false)
        note:SetScript("OnEscapePressed", note.ClearFocus)
        local placeholder = heading(note, L["Optional board note"], 1, -5)
        note:SetScript("OnTextChanged", function(box) placeholder:SetShown(box:GetText() == "") end)
        heading(footer, L["Duration in days (1–30)"], 13, -70)
        local days = CreateFrame("EditBox", nil, footer, "InputBoxTemplate")
        days:SetSize(55, 23)
        days:SetPoint("TOPLEFT", 176, -65)
        days:SetNumeric(true)
        days:SetMaxLetters(2)
        days:SetAutoFocus(false)
        days:SetScript("OnEscapePressed", days.ClearFocus)
        days:SetScript("OnTextChanged", function()
            if dialog.recipe then update() end
        end)
        dialog.boardDays = days
        dialog.boardSupplies, dialog.boardNote = supplies, note
        dialog.post = button(footer, L["Post to bulletin board"], 205, 12, 0, function()
            if not database or guildKey ~= guildIdentity() or not orderChannel then return end
            if not addon.boardCan("order") then return end
            local order = addon.board.post(guildKey, player, dialog.recipe, tonumber(quantity:GetText()),
                not not supplies:GetChecked(), note:GetText(), broadcastOrder, tonumber(days:GetText()))
            if not order then return end
            note:ClearFocus()
            dialog:Hide()
            activeTab = "board"
            refresh()
        end)
        dialog.post:ClearAllPoints()
        dialog.post:SetPoint("BOTTOMLEFT", 9, 8)
        dialog.update = update
        quantity:SetScript("OnTextChanged", function() if dialog.recipe then update() end end)
    end
    orderDialog.recipe, orderDialog.crafters, orderDialog.crafterIndex = recipe, crafters, 1
    orderDialog.professionID = professionID
    orderDialog.boardOnly = boardOnly
    local name = recipeName(recipe)
    local _, icon, color, _, _, quality = recipePresentation(recipe, name, professionID)
    orderDialog.name:SetText(name)
    color = color or gold
    orderDialog.name:SetTextColor(color.r, color.g, color.b)
    orderDialog.itemIcon:SetTexture(icon)
    orderDialog.hero.entry = { recipe = recipe }
    local rarity = quality and _G["ITEM_QUALITY" .. quality .. "_DESC"]
    orderDialog.subtitle:SetText(professionName(professionID) .. (rarity and ("  ·  " .. rarity) or ""))
    orderDialog.status:SetText("")
    orderDialog.boardSupplies:SetChecked(true)
    orderDialog.boardNote:SetText("")
    orderDialog.boardDays:SetText("7")
    orderDialog.quantity:SetText("1")
    orderDialog.update()
    orderDialog:Show()
end

showOrderMenu = function(row)
    if uiInCombat() then return end
    if not orderBook then return end
    if not orderMenu then
        orderMenu = panel(UIParent)
        orderMenu:SetSize(164, 34)
        orderMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        orderMenu:SetClampedToScreen(true)
        button(orderMenu, L["Place order#2"], 152, 6, -5, function()
            local entry = orderMenu.entry
            orderMenu:Hide()
            showOrderDialog(entry.recipe, entry.crafter, entry.professionID)
        end)
    end
    if orderMenu:IsShown() and orderMenu.anchor == row then orderMenu:Hide(); return end
    orderMenu.entry, orderMenu.anchor = row.entry, row
    orderMenu:ClearAllPoints()
    orderMenu:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 24, 0)
    orderMenu:Show()
    GameTooltip:Hide()
end

local function describeOrderRecipe(order)
    local id = order.recipe
    local catalog = addon.recipeCatalog[id] or ForeverGuildDiscoveredRecipes[id]
    local profession = order.professionID or (catalog and catalog.profession) or addon.recipeProfessions[id]
    if not profession and trade and trade.GetProfessionInfoByRecipeID then
        local ok, info = pcall(trade.GetProfessionInfoByRecipeID, id)
        if ok and info and info.professionID and info.professionID > 0 then profession = info.professionID end
    end
    local name = recipeName(id)
    local _, icon, color, _, _, quality, itemID = recipePresentation(id, name, profession)
    return { name = name, profession = profession and professionName(profession),
        itemID = itemID, recipeID = id, icon = icon, color = color, rarity = quality and _G["ITEM_QUALITY" .. quality .. "_DESC"] }
end


local function buildOrders()
    if not orderBook then return end
    local page = panel(window, 0)
    window.orders = page
    page:SetPoint("TOPLEFT", 14, -46)
    page:SetPoint("BOTTOMRIGHT", -14, 13)
    pageBackdrop(page, "GuildAdministration", 1.5, .88)
    heading(page, L["Crafting orders"], 17, -14)
    local notice = heading(page, "", 360, -43)
    local outgoing, selection = false, nil
    local function readOrder(key)
        if orderBook.markRead(key) and updateOrderNotice then updateOrderNotice() end
    end
    local function selectDirection(value)
        outgoing, selection = value, nil
        notice:SetText("")
        window.refreshOrders()
    end
    local mine = button(page, L["My orders"], 150, 16, -36, function() selectDirection(false) end)
    local sent = button(page, L["Sent orders"], 170, 172, -36, function() selectDirection(true) end)
    local left = contrastPanel(page)
    left:SetPoint("TOPLEFT", 17, -75)
    left:SetPoint("BOTTOMLEFT", 17, 17)
    left:SetWidth(390)
    local right = panel(page, 0, nil, .06)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 9, 0)
    right:SetPoint("BOTTOMRIGHT", -17, 17)
    local showCompleted = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    showCompleted:SetPoint("TOPLEFT", 8, -8)
    local completedLabel = heading(left, L["Completed only"], 38, -18)
    local render = list(left, 8, -42, -33, 10, 349, 26, orderItemTooltip)
    local hero = contrastPanel(right)
    hero:SetPoint("TOPLEFT", 11, -11)
    hero:SetPoint("TOPRIGHT", -11, -11)
    hero:SetHeight(76)
    hero:EnableMouse(true)
    hero:SetScript("OnEnter", orderItemTooltip)
    hero:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local itemIcon = hero:CreateTexture(nil, "ARTWORK")
    itemIcon:SetSize(46, 46)
    itemIcon:SetPoint("LEFT", 14, 0)
    itemIcon:SetTexCoord(.06, .94, .06, .94)
    local title = hero:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 75, -16)
    title:SetPoint("RIGHT", -14, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    local subtitle = heading(hero, "", 76, -44)

    local facts = contrastPanel(right)
    facts:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -8)
    facts:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -8)
    facts:SetHeight(115)
    local function fact(x, y, caption)
        local label = heading(facts, caption or "", x, y)
        local value = orderText(facts, x, y - 16, 12)
        return value, label
    end
    local contact, contactLabel = fact(14, -12)
    local timestamp, timeLabel = fact(234, -12)
    local crafts = fact(14, -62, L["Crafts"])
    local status = fact(234, -62, "Status")
    local ingredients = contrastPanel(right)
    ingredients:SetPoint("TOPLEFT", facts, "BOTTOMLEFT", 0, -9)
    ingredients:SetPoint("TOPRIGHT", facts, "BOTTOMRIGHT", 0, -9)
    ingredients:SetPoint("BOTTOM", 0, 48)
    heading(ingredients, L["Materials"], 14, -12)
    local renderIngredients = list(ingredients, 9, -33, -32, 9, 390, 18, orderItemTooltip)
    local done = button(right, "", 200, 146, -380, function()
        local order = ForeverGuildOrders and ForeverGuildOrders[selection]
        if order and not order.outgoing then
            readOrder(selection)
            orderBook.setDone(selection, not order.done, guildKey)
            dispatchOrders()
            if not order.done then
                notice:SetText((L["%s was reopened."]):format(recipeName(order.recipe)))
            else
                notice:SetText("")
            end
            window.refreshOrders()
        end
    end)
    local whisper = button(right, L["Whisper#2"], 120, 17, -380, function()
        local order = ForeverGuildOrders and ForeverGuildOrders[selection]
        if not order or not orderBook.belongsToGuild(order, guildKey) or guildKey ~= guildIdentity() or not ChatFrame_SendTell then return end
        local key = order.outgoing and order.recipient or order.sender
        local member = roster[key]
        ChatFrame_SendTell((member and member.target) or order.address or key)
    end)
    whisper:ClearAllPoints()
    whisper:SetPoint("BOTTOMLEFT", 13, 12)
    done:ClearAllPoints()
    done:SetPoint("BOTTOMRIGHT", -13, 12)
    window.refreshOrders = function()
        mine:SetEnabled(outgoing)
        sent:SetEnabled(not outgoing)
        showCompleted:SetShown(not outgoing)
        completedLabel:SetShown(not outgoing)
        local visible = {}
        for key, order in pairs(ForeverGuildOrders or {}) do
            if orderBook.belongsToGuild(order, guildKey) and (order.outgoing == true) == outgoing and (outgoing or (order.done == true) == (showCompleted:GetChecked() and true or false)) then
                visible[#visible + 1] = key
            end
        end
        table.sort(visible, function(a, b)
            local first, second = ForeverGuildOrders[a], ForeverGuildOrders[b]
            if first.received == second.received then return a < b end
            return first.received > second.received
        end)
        local rows, selectedOrder = {}, nil
        for _, key in ipairs(visible) do
            local order = ForeverGuildOrders[key]
            if key == selection then selectedOrder = order end
        end
        if not selectedOrder then
            selection = visible[1]
            selectedOrder = selection and ForeverGuildOrders[selection]
        end
        local groups, labels, selectedRecipe = {}, {}, nil
        for _, key in ipairs(visible) do
            local order = ForeverGuildOrders[key]
            local name = order.recipient or order.sender
            local member = roster[fullName(name)]
            local label = member and member.displayName or name:match("^[^-]+")
            if not groups[label] then groups[label] = {}; labels[#labels + 1] = label end
            local recipe = describeOrderRecipe(order)
            if key == selection then selectedRecipe = recipe end
            local entries = groups[label]
            local marker = order.unread and not order.done and (L["  |cffffd36cNew|r"]) or ""
            entries[#entries + 1] = { text = ("%d × %s%s"):format(order.quantity, recipe.name, marker),
                icon = recipe.icon, itemID = recipe.itemID, selected = selection == key,
                color = recipe.color or (order.done and muted or nil),
                action = function()
                    selection = key
                    readOrder(key)
                    window.refreshOrders()
                end }
        end
        table.sort(labels, function(a, b) return utf8Lower(a) < utf8Lower(b) end)
        for _, name in ipairs(labels) do
            rows[#rows + 1] = { text = name, color = gold, category = true }
            for _, row in ipairs(groups[name]) do rows[#rows + 1] = row end
        end
        render(rows)
        title:SetText(selectedRecipe and selectedRecipe.name or (L["No orders"]))
        hero.entry = selectedRecipe
        itemIcon:SetTexture(selectedRecipe and selectedRecipe.icon)
        local color = selectedRecipe and selectedRecipe.color or gold
        title:SetTextColor(color.r, color.g, color.b)
        subtitle:SetText(selectedRecipe and ((selectedRecipe.profession or "–")
            .. (selectedRecipe.rarity and ("  ·  " .. selectedRecipe.rarity) or "")) or "")
        contactLabel:SetText(outgoing and (L["Recipient"]) or (L["Requested by"]))
        timeLabel:SetText(outgoing and (L["Created"]) or (L["Received"]))
        contact:SetText(selectedOrder and (selectedOrder.recipient or selectedOrder.sender):match("^[^-]+") or "–")
        timestamp:SetText(selectedOrder and date("%d.%m.%Y  %H:%M", selectedOrder.received) or "–")
        crafts:SetText(selectedOrder and tostring(selectedOrder.quantity) or "–")
        local deliveryLabels = {
            confirmed = L["Delivered"],
            waiting = L["Waiting for recipient"],
            sent = L["Awaiting confirmation"],
            unconfirmed = L["No confirmation"],
            failed = L["Send failed"],
        }
        local state = selectedOrder and (outgoing and (selectedOrder.completed and (L["Completed"])
            or (selectedOrder.completionVersion and (L["Reopened"]) or deliveryLabels[selectedOrder.delivery]))
            or (selectedOrder.done and (L["Completed"])
                or (selectedOrder.reopenedAt and (L["Reopened"]) or (L["Open"]))))
        status:SetText(state or "–")
        if selectedOrder and (selectedOrder.done or selectedOrder.delivery == "confirmed") then
            status:SetTextColor(.57, .83, .37)
        else
            status:SetTextColor(1, .83, .51)
        end
        whisper:SetEnabled(selectedOrder ~= nil and ChatFrame_SendTell ~= nil)
        renderIngredients(materialRows(selectedOrder and selectedOrder.recipe, selectedOrder and selectedOrder.quantity))
        done:SetShown(not outgoing)
        done:SetEnabled(selectedOrder ~= nil and not outgoing)
        done:SetText(selectedOrder and selectedOrder.done and (L["Reopen"]) or (L["Mark completed"]))
    end
    window.openUnreadOrders = function()
        showCompleted:SetChecked(false)
        local _, newest = orderBook.unread(guildKey)
        outgoing = newest ~= nil and ForeverGuildOrders[newest].outgoing == true
        selection = newest
        if newest then readOrder(newest) end
        notice:SetText("")
        activeTab = "orders"
        refresh()
    end
    showCompleted:SetScript("OnClick", window.refreshOrders)
end

local function openBoardCatalog()
    if uiInCombat() then return end
    local dialog = window.boardCatalog
    if not dialog then
        dialog = CreateFrame("Frame", "ForeverGuildBoardCatalog", UIParent, "PortraitFrameTemplate")
        window.boardCatalog = dialog
        table.insert(UISpecialFrames, "ForeverGuildBoardCatalog")
        local availableWidth, availableHeight = UIParent:GetSize()
        local width = math.min(1050, availableWidth - 44)
        local height = math.min(680, availableHeight - 44)
        dialog:SetSize(width, height)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetClampedToScreen(true)
        dialog:SetTitle(L["Bulletin board · Choose recipe"])
        dialog:SetPortraitToAsset(addonIcon)
        local body = panel(dialog)
        body:SetPoint("TOPLEFT", 12, -45)
        body:SetPoint("BOTTOMRIGHT", -12, 13)
        pageBackdrop(body, "GuildProfessions", 1.5, .88)
        local categories = contrastPanel(body)
        categories:SetPoint("TOPLEFT", 8, -8)
        categories:SetPoint("BOTTOMLEFT", 8, 8)
        categories:SetWidth(176)
        local types = contrastPanel(body)
        types:SetPoint("TOPLEFT", categories, "TOPRIGHT", 8, 0)
        types:SetPoint("BOTTOMLEFT", categories, "BOTTOMRIGHT", 8, 0)
        types:SetWidth(172)
        local results = contrastPanel(body)
        results:SetPoint("TOPLEFT", types, "TOPRIGHT", 8, 0)
        results:SetPoint("BOTTOMRIGHT", -8, 8)

        heading(categories, L["Professions"], 12, -12)
        heading(types, L["Categories"], 12, -12)
        heading(results, L["Recipe name, item name or recipe ID"], 12, -12)
        local input = CreateFrame("EditBox", nil, results, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", 17, -32)
        input:SetPoint("TOPRIGHT", -14, -32)
        input:SetHeight(24)
        input:SetMaxBytes(100)
        input:SetAutoFocus(false)
        input:SetScript("OnEscapePressed", input.ClearFocus)
        local renderCategories = list(categories, 8, -34, -26, 8, 140, 24)
        local renderTypes = list(types, 8, -34, -26, 8, 135, 24)
        local renderResults, resultsScroll = list(results, 8, -89, -28, 44, math.max(120, width - 440), 24, recipeTooltip)
        local progress = CreateFrame("StatusBar", nil, results)
        progress:SetPoint("TOPLEFT", 12, -62)
        progress:SetPoint("TOPRIGHT", -12, -62)
        progress:SetHeight(18)
        progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        progress:SetStatusBarColor(.26, .50, .27)
        local progressBackground = progress:CreateTexture(nil, "BACKGROUND")
        progressBackground:SetAllPoints()
        progressBackground:SetColorTexture(.1, .08, .06, 1)
        local progressText = progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        progressText:SetPoint("CENTER")
        dialog.updateProgress = function()
            progress:SetShown(recipeLoad.remaining > 0 or recipeLoad.failed > 0)
            progress:SetMinMaxValues(0, math.max(1, recipeLoad.total))
            local ready = recipeLoad.total - recipeLoad.remaining - recipeLoad.failed
            progress:SetValue(ready)
            progressText:SetText(recipeLoad.remaining > 0
                and (L["Loading item data · %d / %d"]):format(ready, recipeLoad.total)
                or (L["%d item records still unavailable"]):format(recipeLoad.failed))
        end
        local status = heading(results, "", 97, 0)
        status:ClearAllPoints()
        status:SetPoint("BOTTOMLEFT", 97, 15)
        status:SetPoint("RIGHT", -97, 0)
        status:SetJustifyH("CENTER")
        local profession, category, page, matching = nil, nil, 1, {}
        local function turnPage(offset)
            page = page + offset
            resultsScroll:SetVerticalScroll(0)
            dialog.renderResults()
        end
        local prev = button(results, L["Previous"], 80, 0, 0, function() turnPage(-1) end)
        local nextPage = button(results, L["Next"], 80, 0, 0, function() turnPage(1) end)
        prev:ClearAllPoints()
        nextPage:ClearAllPoints()
        prev:SetPoint("BOTTOMLEFT", 10, 10)
        nextPage:SetPoint("BOTTOMRIGHT", -10, 10)

        local catalog, professions
        local typeCache = {}
        local armor = {
            [0] = L["Jewelry & accessories"],
            [1] = L["Cloth"],
            [2] = L["Leather"],
            [3] = L["Mail"],
            [4] = L["Plate"],
            [6] = L["Shields"],
        }
        local function outputFor(id)
            local record = addon.recipeCatalog[id] or ForeverGuildDiscoveredRecipes[id]
            local output = (record and record.output) or addon.recipeOutputs[id]
            if type(output) == "table" then return output[1] end
            return output
        end
        local function recipeType(id, skill)
            local output = outputFor(id)
            if output and typeCache[output] then return typeCache[output] end
            if output and C_Item and C_Item.GetItemInfoInstant then
                local _, itemClass, itemSubclass, _, _, classID, subclassID = C_Item.GetItemInfoInstant(output)
                local label = (classID == 4 and armor[subclassID])
                    or (classID == 2 and (L["Weapons"]))
                if not label and classID and classID < 16 then label = itemClass end
                if not label or label == "" then label = itemSubclass end
                if label and label ~= "" then
                    typeCache[output] = label
                    return label
                end
            end
            if not output and skill == 333 then return L["Enchantments"] end
            return L["Other recipes"]
        end
        local function rebuildCatalog()
            catalog, professions = {}, {}
            local function add(id, skill)
                if not catalog[id] and skill then
                    catalog[id] = skill
                    professions[skill] = true
                end
            end
            for id, record in pairs(addon.recipeCatalog) do add(id, record.profession) end
            for id, record in pairs(ForeverGuildDiscoveredRecipes) do add(id, record.profession) end
            local function merge(profile)
                for skill, data in pairs(profile or {}) do
                    for id in pairs(data.recipes or {}) do add(id, skill) end
                end
            end
            merge(ForeverGuildCharacter)
            for member, profile in pairs(database or {}) do
                if roster[member] then merge(profile.professions) end
            end
        end

        dialog.renderResults = function()
            local pageSize = 60
            local totalPages = math.max(1, math.ceil(#matching / pageSize))
            page = math.max(1, math.min(page, totalPages))
            local rows = {}
            for index = (page - 1) * pageSize + 1, math.min(page * pageSize, #matching) do
                local entry = matching[index]
                local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.id)
                if icon == 134400 then icon = nil end
                local color = recipeItemDetails(outputFor(entry.id))
                rows[#rows + 1] = { text = entry.name .. "  ·  " .. entry.category,
                    icon = icon or professionIcons[entry.skill], recipe = entry.id, color = color,
                    action = function()
                        input:ClearFocus()
                        dialog:Hide()
                        showOrderDialog(entry.id, nil, entry.skill, true)
                    end }
            end
            if #rows == 0 then rows[1] = { text = L["No matching recipes."], color = muted } end
            renderResults(rows)
            prev:SetEnabled(page > 1)
            nextPage:SetEnabled(page < totalPages)
            status:SetText((L["%d matches · %d / %d"]):format(#matching, page, totalPages))
        end

        local function filter(preservePosition)
            matching = {}
            if not preservePosition then page = 1 end
            local query = utf8Lower(input:GetText():match("^%s*(.-)%s*$"))
            local idQuery = tonumber(query:match("^#?(%d+)$"))
            if idQuery and idQuery >= 1 and idQuery <= 2147483647 and not catalog[idQuery]
                and trade and trade.GetProfessionInfoByRecipeID then
                local ok, info = pcall(trade.GetProfessionInfoByRecipeID, idQuery)
                local skill = ok and info and info.professionID
                if skill and skill > 0 then
                    catalog[idQuery], professions[skill] = skill, true
                end
            end
            local availableTypes = {}
            for id, skill in pairs(catalog) do
                if not profession or skill == profession then
                    local label = recipeType(id, skill)
                    availableTypes[label] = true
                    local name = recipeName(id)
                    if name ~= "#" .. id or idQuery == id or query == "" then
                        local lower = utf8Lower(name)
                        local output = outputFor(id)
                        local cached = output and itemDetails[output]
                        local itemName = cached and cached.name
                        if (not category or label == category)
                            and (query == "" or idQuery == id or lower:find(query, 1, true)
                                or (itemName and utf8Lower(itemName):find(query, 1, true))) then
                            matching[#matching + 1] = { id = id, skill = skill, name = name,
                                sortName = lower, category = label }
                        end
                    end
                end
            end
            table.sort(matching, function(a, b)
                if a.sortName == b.sortName then return a.id < b.id end
                return a.sortName < b.sortName
            end)
            local labels = {}
            for label in pairs(availableTypes) do labels[#labels + 1] = label end
            table.sort(labels, function(a, b) return utf8Lower(a) < utf8Lower(b) end)
            local typeRows = { { text = L["All categories"], selected = not category,
                action = function() category = nil; filter() end } }
            for _, label in ipairs(labels) do
                typeRows[#typeRows + 1] = { text = label, selected = category == label,
                    action = function() category = label; filter() end }
            end
            renderTypes(typeRows)
            if not preservePosition then resultsScroll:SetVerticalScroll(0) end
            dialog.renderResults()
        end

        local function showCategories()
            local skills = {}
            for skill in pairs(professions) do skills[#skills + 1] = { id = skill, name = professionName(skill) } end
            table.sort(skills, function(a, b) return utf8Lower(a.name) < utf8Lower(b.name) end)
            local rows = { { text = L["All professions"], selected = not profession,
                action = function() profession, category = nil, nil; dialog.refresh() end } }
            for _, skill in ipairs(skills) do
                rows[#rows + 1] = { text = skill.name, selected = profession == skill.id,
                    icon = professionIcons[skill.id], action = function() profession, category = skill.id, nil; dialog.refresh() end }
            end
            renderCategories(rows)
        end
        dialog.refresh = function()
            showCategories()
            filter()
        end
        dialog.prepare = function()
            dialog.updateProgress()
            rebuildCatalog()
            profession, category = nil, nil
            input:SetText("")
            dialog.refresh()
        end
        local itemRefreshQueued
        dialog.queueItemRefresh = function()
            if itemRefreshQueued then return end
            itemRefreshQueued = true
            after(.6, function()
                itemRefreshQueued = false
                if dialog:IsShown() then filter(true) end
            end)
        end
        local filterQueued
        input:SetScript("OnTextChanged", function()
            if filterQueued then return end
            filterQueued = true
            after(.15, function()
                filterQueued = false
                if dialog:IsShown() then filter() end
            end)
        end)
    end
    dialog.prepare()
    dialog:Show()
end

local function openGroupComposer(onPosted)
    if uiInCombat() then return end
    local dialog = window.groupComposer
    if not dialog then
        dialog = CreateFrame("Frame", "ForeverGuildGroupComposer", UIParent, "PortraitFrameTemplate")
        window.groupComposer = dialog
        table.insert(UISpecialFrames, "ForeverGuildGroupComposer")
        dialog:SetSize(620, 530)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetClampedToScreen(true)
        dialog:SetPortraitToAsset(addonIcon)
        dialog:SetTitle(L["ForeverGuild · Dungeon Finder"])
        local body = panel(dialog)
        body:SetPoint("TOPLEFT", 12, -44)
        body:SetPoint("BOTTOMRIGHT", -12, 13)
        pageBackdrop(body, "GuildHall", 1.5, .65)

        local roleBar = contrastPanel(body)
        roleBar:SetPoint("TOPLEFT", 11, -10)
        roleBar:SetPoint("TOPRIGHT", -11, -10)
        roleBar:SetHeight(91)
        heading(roleBar, L["My role"], 12, -12)
        local controls, ownRole = {}, 3
        local roleKeys = { "T", "H", "D" }
        for i, role in ipairs(roles) do
            local control = roleControl(roleBar, role, 130 + (i - 1) * 132, -7)
            controls[i] = control
            control:SetScript("OnClick", function()
                ownRole = i
                for index, other in ipairs(controls) do other:Select(index == i) end
            end)
            local caption = heading(roleBar, role.label, 0, 0)
            caption:ClearAllPoints()
            caption:SetPoint("TOP", control, "BOTTOM", 0, -3)
        end

        local content = contrastPanel(body)
        content:SetPoint("TOPLEFT", roleBar, "BOTTOMLEFT", 0, -9)
        content:SetPoint("TOPRIGHT", roleBar, "BOTTOMRIGHT", 0, -9)
        content:SetPoint("BOTTOM", 0, 49)
        local label = heading(content, "", 14, -12)
        label:SetFontObject(GameFontNormalLarge)
        local activityPane = CreateFrame("Frame", nil, content)
        activityPane:SetAllPoints()
        local form = CreateFrame("Frame", nil, content)
        form:SetAllPoints()
        local render, activityScroll = list(activityPane, 12, -45, -31, 12, 500, 57)

        local function field(caption, y, bytes)
            heading(form, caption, 14, y)
            local input = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
            input:SetPoint("TOPLEFT", 20, y - 19)
            input:SetPoint("TOPRIGHT", -17, y - 19)
            input:SetHeight(26)
            input:SetMaxBytes(bytes)
            input:SetAutoFocus(false)
            input:SetScript("OnEscapePressed", input.ClearFocus)
            return input
        end
        local subject = field(L["Title"], -47, 52)
        local schedule = field(L["Start · DD.MM.YYYY HH:MM (your local time)"], -98, 24)
        local description = field(L["Details (optional)"], -149, 112)
        heading(form, L["Role slots (including you)"], 14, -200)
        local slotInputs = {}
        for i, role in ipairs(roles) do
            local x = 15 + (i - 1) * 145
            heading(form, role.label, x, -229)
            local input = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
            input:SetSize(40, 24)
            input:SetPoint("TOPLEFT", x + 65, -224)
            input:SetAutoFocus(false)
            input:SetNumeric(true)
            input:SetMaxLetters(2)
            input:SetScript("OnEscapePressed", input.ClearFocus)
            slotInputs[roleKeys[i]] = input
        end
        local errorText = orderText(form, 15, -263, 15)
        errorText:SetTextColor(1, .65, .38)
        local choosing, activityID = true, nil
        local function eventTime()
            local d, m, y, h, minute = schedule:GetText():match("^(%d%d)%.(%d%d)%.(%d%d%d%d)%s+(%d%d):(%d%d)$")
            if not d then return end
            local ok, timestamp = pcall(time, {day = tonumber(d), month = tonumber(m), year = tonumber(y),
                hour = tonumber(h), min = tonumber(minute), sec = 0})
            if ok and timestamp and date("%d.%m.%Y %H:%M", timestamp) == d .. "." .. m .. "." .. y .. " " .. h .. ":" .. minute then
                return timestamp
            end
        end

        local publish = button(body, L["Publish event"], 182, 0, 0, function()
            if uiInCombat() or not orderChannel or not database or guildKey ~= guildIdentity() then return end
            if not addon.boardCan("group") then return end
            local slots, total = {}, 0
            for role, input in pairs(slotInputs) do
                local count = tonumber(input:GetText())
                if not count or count < 0 or count > 40 or count % 1 ~= 0 then
                    errorText:SetText(L["Enter a slot count for each role."])
                    return
                end
                slots[role], total = count, total + count
            end
            local role = roleKeys[ownRole]
            if total > 40 or slots[role] == 0 then
                errorText:SetText(L["Use at most 40 slots and reserve a slot for your own role."])
                return
            end
            local posted = addon.boardNotes.post(guildKey, player, "G", subject:GetText(), description:GetText(), eventTime(),
                false, orderClock(), broadcastOrder, slots, role, activityID)
            if posted then
                if dialog.sharePartners:GetChecked() then
                    local _, flags = addon.guildPartners.events(guildKey)
                    flags[player .. "/" .. posted.token] = orderClock()
                    broadcastOrder("P:S:" .. posted.token)
                end
                dialog:Hide()
                dialog.onPosted()
            else
                errorText:SetText(L["Enter a title without a colon and a valid start within the next 30 days."])
            end
        end)
        publish:ClearAllPoints()
        publish:SetPoint("BOTTOMRIGHT", -12, 11)

        local function showPicker(picking)
            choosing = picking
            activityPane:SetShown(picking)
            form:SetShown(not picking)
            publish:SetShown(not picking)
            if dialog.sharePartners then dialog.sharePartners:SetShown(not picking) end
            label:SetText(picking and (L["Choose dungeon"]) or "")
            errorText:SetText("")
        end
        local sharePartners = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
        sharePartners:SetPoint("BOTTOMLEFT", 136, 12)
        heading(sharePartners, L["Also for partner guilds"], 28, -7)
        dialog.sharePartners = sharePartners
        local back = button(body, L["Back"], 117, 0, 0, function()
            if choosing then dialog:Hide() else showPicker(true) end
        end)
        back:ClearAllPoints()
        back:SetPoint("BOTTOMLEFT", 12, 11)

        local rows = {}
        for _, dungeon in ipairs(addon.groupDungeons) do
            local name = dungeon[de and 1 or 2]
            local details = dungeon[de and 3 or 4] .. " · " .. (L["Level "]) .. dungeon[5]
            local id = dungeon[6]
            rows[#rows + 1] = { text = name, subtitle = details, boardCard = true,
                banner = ("Interface\\AddOns\\ForeverGuild\\Art\\Dungeon%02d"):format(id),
                action = function()
                    activityID = id
                    subject:SetText(name)
                    showPicker(false)
                    label:SetText(details)
                end }
        end
        render(rows)
        dialog.reset = function()
            ownRole = 3
            for i, role in ipairs(roles) do
                if hasRole(memberMask(player), role.bit) then ownRole = i; break end
            end
            for i, control in ipairs(controls) do control:Select(i == ownRole) end
            slotInputs.T:SetText("1")
            slotInputs.H:SetText("1")
            slotInputs.D:SetText("3")
            description:SetText("")
            schedule:SetText(date("%d.%m.%Y", orderClock() + 86400) .. " 20:00")
            activityID = nil
            activityScroll:SetVerticalScroll(0)
            showPicker(true)
        end
    end
    dialog.onPosted = onPosted
    dialog.reset()
    dialog:Show()
end

local function buildBoardNotes(page)
    local function dungeonFor(note)
        if note.activity then return addon.getGroupDungeon(note.activity) end
        local title = utf8Lower(note.title)
        for _, dungeon in ipairs(addon.groupDungeons) do
            if title == utf8Lower(dungeon[1]) or title == utf8Lower(dungeon[2]) then return dungeon end
        end
    end

    local function groupBanner(note, dungeon)
        if dungeon then return ("Dungeon%02d"):format(dungeon[6]) end
        local title = utf8Lower(note.title)
        local text = utf8Lower(note.text)
        if title:find("schwarzfels", 1, true) or title:find("blackrock", 1, true)
            or text:match("^schwarzfels%s") or text:match("^blackrock mountain%s") then
            return "BlackrockHall"
        end
        return "DungeonHall"
    end

    local function titleFor(note, dungeon)
        if dungeon and (note.title == dungeon[1] or note.title == dungeon[2]) then
            return dungeon[de and 1 or 2]
        end
        return note.title
    end

    local function groupMemberTooltip(row)
        local key = row.entry and row.entry.member
        local member = key and roster[key]
        if not member then return end
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class] or gold
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(member.displayName, color.r, color.g, color.b)
        GameTooltip:AddLine((L["Level %s · %s"]):format(
            member.level or "–", member.className or "–"), 1, .91, .74)
        local spec = specName(member.class, ownSpec(key))
        GameTooltip:AddDoubleLine(L["Specialization"],
            spec or (L["Not set"]))
        GameTooltip:AddDoubleLine(L["Guild rank"], member.rank or "–")
        if member.zone and member.zone ~= "" and member.online then
            GameTooltip:AddDoubleLine(L["Zone"], member.zone)
        end
        GameTooltip:AddDoubleLine("Status", member.online and "Online" or "Offline")
        local note = readGuildNote(key, false)
        if note and note ~= "" then
            GameTooltip:AddLine((L["Guild note: "]) .. note, .83, .77, .65, true)
        end
        GameTooltip:Show()
    end

    local pane = contrastPanel(page)
    pane:SetPoint("TOPLEFT", 17, -75)
    pane:SetPoint("BOTTOMRIGHT", -17, 17)
    local left = contrastPanel(pane)
    left:SetPoint("TOPLEFT", 8, -8)
    left:SetPoint("BOTTOMLEFT", 8, 8)
    left:SetWidth(335)
    local render = list(left, 8, -8, -30, 8, 299, 53)
    local detail = contrastPanel(pane)
    detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    detail:SetPoint("BOTTOMRIGHT", -8, 8)
    local banner = detail:CreateTexture(nil, "ARTWORK", nil, -3)
    banner:SetPoint("TOPLEFT", 3, -3)
    banner:SetPoint("TOPRIGHT", -3, -3)
    banner:SetHeight(154)
    detail:HookScript("OnSizeChanged", function(_, width)
        addon.fitDungeonArtwork(banner, width - 6, 154)
    end)
    banner:SetAlpha(.83)
    local shade = detail:CreateTexture(nil, "ARTWORK", nil, -2)
    shade:SetAllPoints(banner)
    shade:SetColorTexture(1, 1, 1, 1)
    shade:SetGradient("HORIZONTAL", CreateColor(.045, .033, .025, .98), CreateColor(.045, .033, .025, .14))
    local edge = detail:CreateTexture(nil, "ARTWORK", nil, -1)
    edge:SetPoint("TOPLEFT", banner, "BOTTOMLEFT")
    edge:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT")
    edge:SetHeight(1)
    edge:SetColorTexture(.49, .34, .18, .8)
    local title = orderText(detail, 16, -18, 16)
    title:SetFontObject(GameFontNormalLarge)
    local information = orderText(detail, 14, -48, 14)
    local body = orderText(detail, 14, -95, 14)
    local signup = contrastPanel(detail)
    signup:SetPoint("TOPLEFT", 12, -174)
    signup:SetPoint("BOTTOMRIGHT", -12, 52)
    heading(signup, L["Sign-ups"], 10, -10)
    local renderSignups = list(signup, 8, -29, -28, 7, 360, 25, groupMemberTooltip)
    local function memberRow(key, suffix)
        local member = roster[key]
        local color = member and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
        local label = (member and member.displayName or key) .. (suffix or "")
        if member and member.level then label = label .. "   ·   " .. (L["Lv. "]) .. member.level end
        return { text = label, color = color, member = key, labelOffset = 12 }
    end

    local selection
    local post = button(detail, L["Plan dungeon run"], 190, 0, 0, function()
        openGroupComposer(function() pane.refresh() end)
    end)
    post:ClearAllPoints()
    post:SetPoint("BOTTOMLEFT", 11, 12)
    local roleNames = { T = L["Tank"], H = L["Healer"], D = L["DPS"] }
    local roleOrder = { "T", "H", "D" }
    local selectedRole, previousNote
    local rolePicker = button(detail, "", 128, 0, 0, function()
        local note = addon.boardNotes.records(guildKey)[selection]
        if not note or not note.slots then return end
        local start = 0
        for i, role in ipairs(roleOrder) do if role == selectedRole then start = i end end
        for i = 1, #roleOrder do
            local role = roleOrder[(start + i - 1) % #roleOrder + 1]
            if note.slots[role] > 0 then selectedRole = role; break end
        end
        pane.refresh()
    end)
    rolePicker:ClearAllPoints()
    rolePicker:SetPoint("BOTTOMRIGHT", -135, 12)
    local reply = button(detail, "", 118, 0, 0, function()
        local note = addon.boardNotes.records(guildKey)[selection]
        if note and orderChannel and guildKey == guildIdentity() then
            addon.boardNotes.reply(note, player, orderClock(), broadcastOrder, note.slots and selectedRole)
            pane.refresh()
        end
    end)
    reply:ClearAllPoints()
    reply:SetPoint("BOTTOMRIGHT", -11, 12)
    local remove = button(detail, L["Unpin"], 128, 0, 0, function()
        local note = addon.boardNotes.records(guildKey)[selection]
        if note and orderChannel and guildKey == guildIdentity() then
            if note.owner == player then addon.boardNotes.close(note, player, broadcastOrder)
            else addon.boardModerate(note.kind, note.owner, note.token) end
            pane.refresh()
        end
    end)
    remove:ClearAllPoints()
    remove:SetPoint("BOTTOMRIGHT", -11, 12)

    local function name(member)
        return (roster[member] and roster[member].displayName) or member
    end
    local lastGuild
    pane.refresh = function()
        if lastGuild ~= guildKey then
            selection, lastGuild = nil, guildKey
        end
        local records = {}
        for id, note in pairs(addon.boardNotes.records(guildKey)) do records[id] = note end
        local known = guildKey and addon.guildPartners.store(guildKey).known or {}
        for id, event in pairs(guildKey and addon.guildPartners.events(guildKey) or {}) do
            local partner = known[event.from]
            records["partner/" .. id] = { owner = event.owner, token = event.token, kind = "G", ends = event.ends,
                closed = event.closed, title = event.title, text = "", replies = {}, activity = event.activity,
                partnerGuild = partner and partner.name or "?" }
        end
        local now, keys, rows = orderClock(), {}, {}
        local found
        for id, note in pairs(records) do
            if note.kind == "G" and not note.closed and note.ends > now and (roster[note.owner] or note.partnerGuild)
                and not addon.boardRights.hidden(guildKey, note.kind, note.owner, note.token) then
                keys[#keys + 1] = id
                if selection == id then found = true end
            end
        end
        table.sort(keys, function(a, b)
            if records[a].ends == records[b].ends then return a < b end
            return records[a].ends < records[b].ends
        end)
        if not found then selection = keys[1] end
        for _, id in ipairs(keys) do
            local note = records[id]
            local dungeon = dungeonFor(note)
            rows[#rows + 1] = { text = titleFor(note, dungeon), boardCard = true,
                banner = dungeon and ("Interface\\AddOns\\ForeverGuild\\Art\\Dungeon%02d"):format(dungeon[6]),
                icon = "Interface\\AddOns\\ForeverGuild\\Art\\" .. "TabRoster",
                subtitle = date("%d.%m. %H:%M", note.ends) .. "  ·  " .. name(note.owner)
                    .. (note.partnerGuild and ("  ·  " .. note.partnerGuild) or ""),
                selected = selection == id,
                action = function() selection = id; pane.refresh() end }
        end
        if #rows == 0 then rows[1] = { text = L["No dungeon events planned."], color = muted } end
        render(rows)
        local note = records[selection]
        local showBanner = note ~= nil
        local dungeon = showBanner and dungeonFor(note)
        banner:SetShown(showBanner)
        shade:SetShown(showBanner)
        edge:SetShown(showBanner)
        if showBanner then
            banner:SetTexture("Interface\\AddOns\\ForeverGuild\\Art\\" .. groupBanner(note, dungeon))
            addon.fitDungeonArtwork(banner, detail:GetWidth() - 6, 154)
        end
        title:SetText(note and titleFor(note, dungeon) or "")
        information:SetText(note and ((L["By "]) .. name(note.owner)
            .. ("\n" .. date("%d.%m.%Y %H:%M", note.ends) .. (L[" · local time"]))) or "")
        local dungeonDetails = dungeon and (dungeon[de and 3 or 4] .. " · "
            .. (L["Level "]) .. dungeon[5])
        local details = note and note.text or ""
        if note and note.partnerGuild then
            details = (L["Event of partner guild %s. Sign up by whispering the organizer."]):format(note.partnerGuild)
        end
        if dungeonDetails then
            if not note.activity then
                local german = dungeon[3] .. " · Stufe " .. dungeon[5]
                local english = dungeon[4] .. " · Level " .. dungeon[5]
                for _, prefix in ipairs({german, english}) do
                    if details == prefix or details:sub(1, #prefix + 1) == prefix .. "\n" then
                        details = details:sub(#prefix + 2)
                        break
                    end
                end
            end
            details = dungeonDetails .. (details ~= "" and ("\n" .. details) or "")
        end
        body:SetText(details)
        signup:SetShown(note ~= nil)
        local members, placed = {}, {}
        if note then
            local queue, assigned, counts = addon.boardNotes.placements(note, function(member) return roster[member] ~= nil end)
            placed = assigned
            if note.slots then
                for _, role in ipairs(roleOrder) do
                    if note.slots[role] > 0 then
                        members[#members + 1] = { text = ("%s   %d / %d"):format(roleNames[role], counts[role], note.slots[role]),
                            category = true, color = counts[role] < note.slots[role] and gold or {r=.64,g=.83,b=.68} }
                    end
                    if note.ownerRole == role then
                        members[#members + 1] = memberRow(note.owner, L[" · Organizer"])
                    end
                    for _, entry in ipairs(queue) do
                        if entry.confirmed and entry.reply.role == role then members[#members + 1] = memberRow(entry.member) end
                    end
                end
                local waitlist = false
                for _, entry in ipairs(queue) do
                    if not entry.confirmed then
                        if not waitlist then
                            members[#members + 1] = { text = L["Waitlist"], category = true }
                            waitlist = true
                        end
                        local role = roleNames[entry.reply.role] or (L["Role missing"])
                        members[#members + 1] = memberRow(entry.member, " · " .. role)
                    end
                end
            else
                members[1] = memberRow(note.owner, L[" · Organizer"])
                for _, entry in ipairs(queue) do members[#members + 1] = memberRow(entry.member) end
            end
        end
        renderSignups(members)
        local answer = note and note.replies[player]
        if previousNote ~= selection then
            previousNote, selectedRole = selection, nil
        end
        if note and note.slots and (not selectedRole or note.slots[selectedRole] == 0) then
            for _, role in ipairs({"D", "T", "H"}) do
                if note.slots[role] > 0 then selectedRole = role; break end
            end
        end
        rolePicker:SetShown(note ~= nil and note.slots ~= nil and note.owner ~= player and not (answer and answer.joined))
        rolePicker:SetText((L["Role: "]) .. (roleNames[selectedRole] or "–"))
        if answer and answer.joined and note.slots and not placed[player] then
            reply:SetText(L["Leave waitlist"])
        else
            reply:SetText(answer and answer.joined and (L["Leave"]) or (L["Join"]))
        end
        reply:SetShown(note ~= nil and note.owner ~= player)
        remove:SetText(L["Cancel event"])
        if note and note.owner ~= player then remove:SetText(L["Hide"]) end
        remove:SetShown(note ~= nil and (note.owner == player or addon.boardMayModerate(note.kind)))
        reply:SetEnabled(not not orderChannel)
        remove:SetEnabled(not not orderChannel)
        if note and note.partnerGuild then
            reply:Hide(); remove:Hide(); rolePicker:Hide()
        end
        post:SetShown(addon.boardCan("group"))
        post:SetEnabled(database ~= nil and not not orderChannel)
    end
    return pane, pane.refresh
end

function addon.showHiddenPosts(parent)
    local dialog = addon.hiddenDialog
    if not dialog then
        dialog = contrastPanel(parent)
        addon.hiddenDialog = dialog
        dialog:SetSize(430, 330)
        dialog:SetPoint("CENTER")
        dialog:SetFrameLevel(parent:GetFrameLevel() + 40)
        dialog:EnableMouse(true)
        heading(dialog, L["Hidden posts"], 14, -12)
        dialog.render = list(dialog, 8, -38, -8, 48, 390, 24)
        dialog.restore = button(dialog, L["Restore"], 150, 0, 0, function()
            local row = dialog.selected
            if row and addon.boardRestore(row.kind, row.owner, row.token) then
                dialog.selected = nil
                queueRefresh()
            end
            dialog.load()
        end)
        dialog.restore:ClearAllPoints()
        dialog.restore:SetPoint("BOTTOMRIGHT", -12, 12)
        local close = button(dialog, L["Close"], 110, 0, 0, function() dialog:Hide() end)
        close:ClearAllPoints()
        close:SetPoint("BOTTOMLEFT", 12, 12)
        dialog.load = function()
            local kinds = { O = L["Order"], G = L["Event"], A = L["Announcement"] }
            local rows = {}
            for _, row in ipairs(guildKey and addon.boardRights.hiddenList(guildKey) or {}) do
                rows[#rows + 1] = { text = ("%s · %s · %s %s"):format(kinds[row.kind] or row.kind,
                    (roster[row.owner] and roster[row.owner].displayName) or row.owner,
                    L["by"], (roster[row.by] and roster[row.by].displayName) or row.by or "?"),
                    selected = dialog.selected == row, action = function() dialog.selected = row; dialog.load() end }
            end
            if #rows == 0 then rows[1] = { text = L["No hidden posts."], color = muted } end
            dialog.render(rows)
            dialog.restore:SetEnabled(dialog.selected ~= nil and addon.boardMayModerate(dialog.selected.kind) and true or false)
        end
    end
    dialog.selected = nil
    dialog.load()
    dialog:Show()
end

local function buildBoard()
    local page = panel(window, 0)
    window.board = page
    page:SetPoint("TOPLEFT", 14, -46)
    page:SetPoint("BOTTOMRIGHT", -14, 13)
    pageBackdrop(page, "GuildAdministration", 1.5, .88)
    heading(page, L["Bulletin board"], 18, -14):SetFontObject(GameFontNormalLarge)

    local section = "orders"
    local notesPane, refreshNotes = buildBoardNotes(page)
    local rail = page:CreateTexture(nil, "ARTWORK")
    rail:SetPoint("TOPLEFT", 18, -38)
    rail:SetPoint("TOPRIGHT", -18, -38)
    rail:SetHeight(1)
    rail:SetColorTexture(.50, .35, .19, .9)
    local hiddenButton = button(page, L["Hidden posts"], 190, 0, 0, function()
        addon.showHiddenPosts(page)
    end)
    hiddenButton:ClearAllPoints()
    hiddenButton:SetPoint("TOPRIGHT", -18, -8)
    page:HookScript("OnShow", function()
        hiddenButton:SetShown(guildKey ~= nil and (addon.boardMayModerate("O") or addon.boardMayModerate("G")
            or addon.boardMayModerate("A")) and true or false)
    end)
    local sections = {}
    for index, entry in ipairs({
        { "orders", L["Crafting orders"], "TabOrders" },
        { "G", L["Find a group"], "TabRoster" },
    }) do
        local key, caption, asset = entry[1], entry[2], entry[3]
        local tab = CreateFrame("Button", nil, page)
        tab:SetSize(174, 33)
        tab:SetPoint("BOTTOMLEFT", rail, "TOPLEFT", 234 + (index - 1) * 175, -1)
        local background = tab:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        local tabArt = "Interface\\AddOns\\ForeverGuild\\Art\\BoardHeaderTab"
        tab:SetHighlightTexture(tabArt .. "Active")
        tab:GetHighlightTexture():SetAlpha(.2)

        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetSize(19, 19)
        icon:SetPoint("LEFT", 12, -2)
        icon:SetTexture("Interface\\AddOns\\ForeverGuild\\Art\\" .. asset)
        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
        label:SetPoint("RIGHT", tab, "RIGHT", -10, 0)
        label:SetJustifyH("LEFT")
        label:SetText(caption)

        tab:SetScript("OnClick", function()
            section = key
            window.refreshBoard()
        end)
        sections[key] = function(active)
            background:SetTexture(tabArt .. (active and "Active" or "Idle"))
            if active then
                label:SetTextColor(1, .85, .50)
            else
                label:SetTextColor(.83, .74, .61)
            end
        end
    end
    local create = button(page, L["Place new order"], 210, 0, 0, openBoardCatalog)
    create:ClearAllPoints()
    create:SetPoint("TOPRIGHT", -17, -44)
    local view, selection = "active", nil
    local filters = {}
    for index, choice in ipairs({
        { "active", L["On the board"] },
        { "mine", L["My orders"] },
        { "history", L["History"] },
    }) do
        local mode, caption = choice[1], choice[2]
        filters[mode] = button(page, caption, 126, 17 + (index - 1) * 132, -44, function()
            view, selection = mode, nil
            window.refreshBoard()
        end)
    end

    local left = contrastPanel(page)
    left:SetPoint("TOPLEFT", 17, -75)
    left:SetPoint("BOTTOMLEFT", 17, 17)
    left:SetWidth(365)
    local searchOrders = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
    searchOrders:SetPoint("TOPLEFT", 15, -13)
    searchOrders:SetPoint("TOPRIGHT", -17, -13)
    searchOrders:SetHeight(24)
    searchOrders:SetAutoFocus(false)
    searchOrders:SetMaxBytes(80)
    searchOrders:SetScript("OnEscapePressed", searchOrders.ClearFocus)
    local placeholder = heading(searchOrders, L["Search orders"], 4, -5)
    searchOrders:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        window.refreshBoard()
    end)
    local render = list(left, 9, -47, -32, 10, 325, 53, orderItemTooltip)

    local detail = panel(page, .34, nil, .96)
    detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    detail:SetPoint("BOTTOMRIGHT", -17, 17)
    local summary = contrastPanel(detail)
    summary:SetPoint("TOPLEFT", 10, -10)
    summary:SetPoint("TOPRIGHT", -10, -10)
    summary:SetHeight(166)
    local pin = summary:CreateTexture(nil, "ARTWORK")
    pin:SetTexture("Interface\\ICONS\\INV_Misc_Note_01")
    pin:SetSize(32, 32)
    pin:SetPoint("TOPLEFT", 12, -12)
    local title = orderText(summary, 55, -13, 14)
    title:SetFontObject(GameFontNormalLarge)
    local statusText = orderText(summary, 56, -37, 14)
    local facts = orderText(summary, 13, -64, 13)
    local note = orderText(summary, 13, -124, 13)
    note:SetTextColor(.83, .72, .57)
    local ingredients = contrastPanel(detail)
    ingredients:SetPoint("TOPLEFT", 10, -194)
    ingredients:SetPoint("BOTTOMRIGHT", -10, 77)
    heading(ingredients, L["Materials"], 10, -9)
    local renderMaterials = list(ingredients, 9, -28, -32, 8, 380, 20, orderItemTooltip)
    local hint = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 43)
    hint:SetPoint("RIGHT", -14, 0)
    hint:SetJustifyH("LEFT")

    local function act(action)
        local order = addon.board.records(guildKey)[selection]
        if not order or guildKey ~= guildIdentity() or not orderChannel then return end
        if action == "moderate" then addon.boardModerate("O", order.owner, order.token)
        else addon.board.action(order, player, action, broadcastOrder, sendOrderMessage, orderClock()) end
        window.refreshBoard()
    end
    local mainAction, secondaryAction
    local primary = button(detail, "", 210, 0, 0, function() act(mainAction) end)
    primary:ClearAllPoints()
    primary:SetPoint("BOTTOMRIGHT", -11, 11)
    local secondary = button(detail, "", 142, 0, 0, function() act(secondaryAction) end)
    secondary:ClearAllPoints()
    secondary:SetPoint("BOTTOMLEFT", 11, 11)

    local labels = {
        O = L["Open"], W = L["In progress"],
        R = L["Ready for handoff"],
        D = L["Completed#2"], X = L["Withdrawn"],
        E = L["Expired"],
    }
    local stateOrder = { O = 1, W = 2, R = 3, D = 4, X = 5, E = 6 }
    local stateColors = {
        O = {r=.89,g=.73,b=.42}, W = {r=.61,g=.78,b=.90}, R = {r=.60,g=.83,b=.62},
        D = {r=.60,g=.83,b=.62}, X = muted, E = muted,
    }
    local function display(key)
        local member = roster[key]
        return member and member.displayName or key or "–"
    end
    local function knowsRecipe(id)
        for _, profession in pairs(ForeverGuildCharacter or {}) do
            if profession.recipes and profession.recipes[id] then return true end
        end
        return false
    end

    window.refreshBoard = function()
        for key, setActive in pairs(sections) do setActive(key == section) end
        local showOrders = section == "orders"
        notesPane:SetShown(not showOrders)
        create:SetShown(showOrders)
        left:SetShown(showOrders)
        detail:SetShown(showOrders)
        for mode, control in pairs(filters) do
            control:SetShown(showOrders)
            control:SetEnabled(mode ~= view)
        end
        if not showOrders then refreshNotes(); return end
        local records = addon.board.records(guildKey)
        local now = orderClock()
        create:SetEnabled(database ~= nil and not not orderChannel and addon.boardCan("order"))
        local keys, rows = {}, {}
        local query = utf8Lower(searchOrders:GetText():match("^%s*(.-)%s*$"))
        for key, order in pairs(records) do
            local state = addon.board.state(order, now)
            local closed = state == "D" or state == "X" or state == "E"
            local own = order.owner == player or order.crafter == player or order.intent == "take"
            if not addon.boardRights.hidden(guildKey, "O", order.owner, order.token)
                and ((view == "history" and closed) or (not closed and (view == "active" or own))) then
                if query == "" or utf8Lower(recipeName(order.recipe)):find(query, 1, true)
                    or utf8Lower(display(order.owner)):find(query, 1, true)
                    or utf8Lower(display(order.crafter)):find(query, 1, true) then
                    keys[#keys + 1] = key
                end
            end
        end
        table.sort(keys, function(a, b)
            local first, second = records[a], records[b]
            local firstState = stateOrder[addon.board.state(first, now)]
            local secondState = stateOrder[addon.board.state(second, now)]
            if firstState ~= secondState then return firstState < secondState end
            local firstTime = tonumber(first.token:match("^%d+")) or 0
            local secondTime = tonumber(second.token:match("^%d+")) or 0
            if firstTime == secondTime then return a > b end
            return firstTime > secondTime
        end)
        local found
        for _, key in ipairs(keys) do if key == selection then found = true; break end end
        if not found then selection = keys[1] end
        local priorState
        for _, key in ipairs(keys) do
            local order = records[key]
            local state = addon.board.state(order, now)
            if priorState ~= state then
                rows[#rows + 1] = { text = labels[state], color = stateColors[state], category = true }
                priorState = state
            end
            local recipe = describeOrderRecipe(order)
            rows[#rows + 1] = { text = ("%d × %s"):format(order.quantity, recipe.name),
                subtitle = display(order.owner) .. (order.crafter and (" · " .. display(order.crafter)) or ""),
                color = recipe.color, boardCard = true, statusColor = stateColors[state],
                icon = recipe.icon, itemID = recipe.itemID, selected = key == selection,
                action = function() selection = key; window.refreshBoard() end }
        end
        if #rows == 0 then
            rows[1] = { text = L["No orders in this view."], color = muted }
        end
        render(rows)
        local order = records[selection]
        title:SetText(order and ("%d × %s"):format(order.quantity, recipeName(order.recipe))
            or (L["No order selected"]))
        local state = order and addon.board.state(order, now)
        statusText:SetText(state and labels[state] or "")
        if state then
            local tone = stateColors[state]
            statusText:SetTextColor(tone.r, tone.g, tone.b)
        end
        local deadline = order and order.expiresAt and ("\n" .. (L["Open until: "])
            .. date("%d.%m.%Y %H:%M", order.expiresAt)) or ""
        facts:SetText(order and ((L["Requester: %s   ·   Crafter: %s\n%s"]):format(
            display(order.owner), display(order.crafter),
            order.supplies and (L["The requester provides materials."])
                or (L["The crafter provides materials."])) .. deadline) or "")
        note:SetText(order and order.note or "")
        ingredients:SetShown(order ~= nil)
        renderMaterials(materialRows(order and order.recipe, order and order.quantity))
        local caption, alternate, message
        mainAction, secondaryAction = nil, nil
        if state == "E" then
            message = L["The deadline has passed."]
        elseif order and order.intent then
            message = L["Waiting for the requester's confirmation."]
        elseif order and order.state == "O" then
            if order.owner == player then
                secondaryAction, alternate = "cancel", L["Withdraw"]
            elseif knowsRecipe(order.recipe) then
                mainAction, caption = "take", L["Claim order"]
                if not (roster[order.owner] and roster[order.owner].online) then
                    message = L["Your claim is confirmed when you are both online."]
                end
            else
                message = L["Recipe missing. Open your professions to update known recipes."]
            end
        elseif order and order.crafter == player and (order.state == "W" or order.state == "R") then
            secondaryAction, alternate = "release", L["Release"]
            if order.state == "W" then
                mainAction, caption = "ready", L["Ready for handoff#2"]
            end
        elseif order and order.owner == player and order.state == "R" then
            mainAction, caption = "received", L["Received#2"]
        end
        if order and not secondaryAction and order.owner ~= player and addon.boardMayModerate("O") then
            secondaryAction, alternate = "moderate", L["Hide"]
        end
        hint:SetText(message or "")
        primary:SetShown(mainAction ~= nil)
        secondary:SetShown(secondaryAction ~= nil)
        primary:SetText(caption or "")
        secondary:SetText(alternate or "")
        primary:SetEnabled(not not orderChannel)
        secondary:SetEnabled(not not orderChannel)
    end
end

requestBankSnapshot = function()
    if guildBank and guildKey and guildKey == guildIdentity() and GetTime() - lastBankRequest >= 30 and enqueue({"BQ"}) then
        lastBankRequest = GetTime()
    end
end

local function buildGuildBank()
    local page = panel(window, 0)
    window.bank = page
    page:SetPoint("TOPLEFT", 14, -46)
    page:SetPoint("BOTTOMRIGHT", -14, 13)
    pageBackdrop(page, "GuildAdministration", 1.5, .88)
    local pane = contrastPanel(page)
    pane:SetPoint("TOPLEFT", 10, -10)
    pane:SetPoint("BOTTOMRIGHT", -10, 10)
    local title = heading(pane, L["Guild bank"], 14, -12)
    title:SetFontObject(GameFontNormalLarge)
    local hint = orderText(pane, 14, -37, 14)
    local balance = heading(pane, "", 0, 0)
    balance:ClearAllPoints()
    balance:SetPoint("TOPRIGHT", -15, -14)
    balance:SetFontObject(GameFontNormalLarge)
    local searchBank = CreateFrame("EditBox", nil, pane, "InputBoxTemplate")
    searchBank:SetSize(260, 24)
    searchBank:SetPoint("TOPLEFT", 18, -75)
    searchBank:SetAutoFocus(false)
    searchBank:SetScript("OnEscapePressed", searchBank.ClearFocus)
    heading(pane, L["Find an item"], 289, -81)
    local sync = button(pane, L["Request guild snapshot"], 170, 0, 0, requestBankSnapshot)
    sync:ClearAllPoints()
    sync:SetPoint("TOPRIGHT", -15, -74)
    local read = button(pane, L["Scan open vault"], 140, 0, 0, function()
        if scanVisibleBank() then window.refreshBank() end
    end)
    read:ClearAllPoints()
    read:SetPoint("RIGHT", sync, "LEFT", -8, 0)
    local settings = contrastPanel(pane)
    settings:SetPoint("TOPRIGHT", -12, -110)
    settings:SetPoint("BOTTOMRIGHT", -12, 12)
    settings:SetWidth(233)
    heading(settings, L["Bank settings"], 12, -12)
    local access = orderText(settings, 12, -54, 12)
    local native = button(settings, L["Show WoW guild vault"], 204, 12, -26, function()
        if GuildBankFrame and GuildBankFrame:IsShown() then window:Hide() end
    end)
    local inventory = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    inventory:SetPoint("TOPLEFT", 12, -111)
    inventory:SetPoint("BOTTOMRIGHT", settings, "BOTTOMLEFT", -29, 0)
    local content = CreateFrame("Frame", nil, inventory)
    content:SetSize(1, 1)
    inventory:SetScrollChild(content)
    local blocks, slots = {}, {}
    local chosen, lastGuild
    local tabButtons = list(settings, 10, -180, -30, 10, 185, 27)
    local function slotFor(index)
        if slots[index] then return slots[index] end
        local slot = CreateFrame("Button", nil, content, "BackdropTemplate")
        slot:SetSize(37, 37)
        slot:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8})
        slot:SetBackdropColor(.12, .08, .05, 1)
        slot:SetBackdropBorderColor(.60, .40, .19, 1)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetPoint("TOPLEFT", 3, -3)
        slot.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        slot.icon:SetTexCoord(.06, .94, .06, .94)
        slot.amount = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        slot.amount:SetPoint("BOTTOMRIGHT", -3, 2)
        slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        slot:SetScript("OnEnter", orderItemTooltip)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        slots[index] = slot
        return slot
    end
    window.refreshBank = function()
        local liveGuild = guildIdentity()
        if liveGuild ~= lastGuild then
            lastGuild, chosen = liveGuild, nil
            searchBank:ClearFocus()
            inventory:SetVerticalScroll(0)
        end
        local tabs = guildBank.snapshot(liveGuild) or {}
        local money = guildBank.balance(liveGuild)
        balance:SetText(money and guildBank.formatBalance(money.copper)
            or (L["Balance  –"]))
        if not liveGuild then
            hint:SetText(L["You are not in a guild."])
        elseif not guildBank.available() then
            hint:SetText(L["The guild bank API is unavailable."])
        else
            hint:SetText(L["Stock is synced when the guild vault is opened."])
        end
        local indexList, tabRows = {}, {}
        for index in pairs(tabs) do indexList[#indexList + 1] = index end
        table.sort(indexList)
        if not tabs[chosen] then chosen = indexList[1] end
        local selectedTab = tabs[chosen]
        local viewable, deposit, remaining
        if chosen and guildBankOpen and GetGuildBankTabInfo then
            local _, _, canView, canDeposit, _, withdrawals = GetGuildBankTabInfo(chosen)
            viewable, deposit, remaining = canView, canDeposit, withdrawals
        end
        native:SetEnabled(GuildBankFrame and GuildBankFrame:IsShown() or false)
        local function yesNo(value)
            if value == nil then return "–" end
            return (value == true or value == 1) and (L["Yes"]) or (L["No"])
        end
        access:SetText((L["Selected tab\nViewable  %s\nDeposits  %s\nWithdrawals left  %s\n\nBank tabs"]):format(
            yesNo(viewable), yesNo(deposit), remaining == -1 and (L["Unlimited"]) or tostring(remaining or "–")))
        for _, index in ipairs(indexList) do
            local tab = tabs[index]
            tabRows[#tabRows + 1] = { text = tab.name, icon = tab.icon, selected = index == chosen,
                action = function() chosen = index; inventory:SetVerticalScroll(0); window.refreshBank() end }
        end
        tabButtons(tabRows)
        local groups, groupOrder = {}, {}
        local query = utf8Lower(searchBank:GetText())
        local instantInfo = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
        local fullInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
        local getClass = C_Item and C_Item.GetItemClassInfo or GetItemClassInfo
        local getSubclass = C_Item and C_Item.GetItemSubClassInfo or GetItemSubClassInfo
        for _, index in ipairs(indexList) do
            if query ~= "" or index == chosen then
                local localTab = tabs[index]
                local tab = localTab.remote and localTab.remote.at > localTab.at and localTab.remote or localTab
                for _, item in ipairs(tab.items) do
                    local id = item.id or tonumber(item.link:match("|Hitem:(%d+)"))
                    if id then
                        local name = item.link and item.link:match("%[(.-)%]")
                        local class, subclass, icon, classID, subclassID
                        if instantInfo then
                            local _, label, sublabel, _, texture, kind, subkind = instantInfo(id)
                            class, subclass, icon, classID, subclassID = label, sublabel, texture, kind, subkind
                            if classID and getClass then class = getClass(classID) or class end
                            if classID and subclassID and getSubclass then subclass = getSubclass(classID, subclassID) or subclass end
                        end
                        if fullInfo and (not name or not class or not subclass) then
                            local itemName, _, _, _, _, label, sublabel = fullInfo(id)
                            name, class, subclass = name or itemName, class or label, subclass or sublabel
                            if not itemName then pendingItems[id] = true end
                        end
                        name = name or ("Item #%d"):format(id)
                        if utf8Lower(name):find(query, 1, true) then
                            local pending = type(class) ~= "string" or class == ""
                            class = pending and (L["Uncategorized"]) or class
                            local key = class
                            local group = groups[key]
                            if not group then
                                group = { name = class, pending = pending, sections = {}, order = {} }
                                groups[key] = group
                                groupOrder[#groupOrder + 1] = group
                            end
                            if pending or type(subclass) ~= "string" or subclass == class then subclass = "" end
                            if not group.sections[subclass] then
                                group.sections[subclass] = {}
                                group.order[#group.order + 1] = subclass
                            end
                            local section = group.sections[subclass]
                            section[#section + 1] = { itemID = id, name = name, quantity = item.quantity, icon = item.icon or icon }
                        end
                    end
                end
            end
        end
        table.sort(groupOrder, function(a, b)
            if a.pending ~= b.pending then return not a.pending end
            return utf8Lower(a.name) < utf8Lower(b.name)
        end)
        local width = math.max(80, inventory:GetWidth())
        content:SetWidth(width)
        local columns = math.max(1, math.floor((width - 16) / 42))
        local y, used, labels = 9, 0, 0
        local function caption(text, secondary)
            labels = labels + 1
            if not blocks[labels] then blocks[labels] = heading(content, "", 0, 0) end
            local label = blocks[labels]
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", secondary and 16 or 9, -y)
            label:SetFontObject(secondary and GameFontHighlightSmall or GameFontNormal)
            label:SetText(text)
            label:Show()
            y = y + 21
        end
        if query ~= "" then
            caption(L["Search results across all tabs"])
        elseif selectedTab then
            local current = selectedTab.remote and selectedTab.remote.at > selectedTab.at and selectedTab.remote or selectedTab
            caption(current.name .. "  ·  " .. date("%d.%m.%Y %H:%M", current.at))
        end
        for _, group in ipairs(groupOrder) do
            caption(group.name)
            table.sort(group.order, function(a, b) return utf8Lower(a) < utf8Lower(b) end)
            for _, section in ipairs(group.order) do
                local items = group.sections[section]
                table.sort(items, function(a, b) return utf8Lower(a.name) < utf8Lower(b.name) end)
                if section ~= "" then caption(section, true) end
                for index, item in ipairs(items) do
                    used = used + 1
                    local slot = slotFor(used)
                    slot.entry = item
                    slot:ClearAllPoints()
                    slot:SetPoint("TOPLEFT", 8 + ((index - 1) % columns) * 42, -y - math.floor((index - 1) / columns) * 42)
                    slot.icon:SetTexture(item.icon or 134400)
                    slot.amount:SetText(item.quantity > 1 and tostring(item.quantity) or "")
                    slot:Show()
                end
                y = y + math.ceil(#items / columns) * 42 + 8
            end
            y = y + 6
        end
        if used == 0 then
            caption(query ~= "" and (L["No matching items."])
                or selectedTab and (L["This tab is empty."])
                or (L["No bank tabs scanned yet."]))
        end
        for i = used + 1, #slots do slots[i]:Hide() end
        for i = labels + 1, #blocks do blocks[i]:Hide() end
        content:SetHeight(math.max(1, y + 10))
    end
    inventory:HookScript("OnSizeChanged", function()
        if activeTab == "bank" then queueRefresh() end
    end)
    searchBank:SetScript("OnTextChanged", window.refreshBank)
end

local function buildHelp()
    local page = panel(window, 0)
    window.help = page
    page:SetPoint("TOPLEFT", 14, -46)
    page:SetPoint("BOTTOMRIGHT", -14, 13)
    pageBackdrop(page, "GuildAdministration", 1.5, .88)
    heading(page, L["ForeverGuild help"], 19, -15)
    local navigation = contrastPanel(page)
    navigation:SetPoint("TOPLEFT", 17, -44)
    navigation:SetPoint("BOTTOMLEFT", 17, 17)
    navigation:SetWidth(212)
    local details = contrastPanel(page)
    details:SetPoint("TOPLEFT", navigation, "TOPRIGHT", 12, 0)
    details:SetPoint("BOTTOMRIGHT", -17, 17)
    local title = heading(details, "", 20, -20)
    title:SetFontObject(GameFontNormalLarge)
    local summary = orderText(details, 20, -56, 20)
    local actions = orderText(details, 20, -115, 20)
    local topics = {
        {L["Guild professions"],
            L["Find recipes and crafters in your guild."],
            L["1. Search for an item or select a guild member on the right.\n\n2. Expand a profession and, if needed, a recipe category.\n\n3. Click Place order next to the recipe. Choose the quantity, check the materials and send the order."]},
        {L["Guild roster"],
            L["See who is online and which roles and specializations are listed."],
            L["Select your character to set your roles and specialization. Guild leaders and officers can also edit other members."]},
        {L["Guild management"],
            L["Read the guild message and any member notes you can view."],
            L["With the relevant WoW permissions, you can edit the message and notes. Open WoW guild management for ranks and other guild actions."]},
        {L["Crafting orders"],
            L["Track incoming and sent orders."],
            L["My orders lists incoming orders. You can whisper the requester and mark an order complete. Sent orders shows the status of your requests. The minimap envelope opens new orders and completion notifications.\n\nTo offer an order to the guild, open the bulletin board and click Place new order. Select a recipe, quantity, and a duration of 1 to 30 days."]},
        {"Log",
            L["Check when ForeverGuild synchronized data."],
            L["Use Export diagnostics to copy the logs for a bug report."]},
        {L["Settings"],
            L["Customize ForeverGuild with the gear icon in the top right."],
            L["From there you can start guild sync, set up your character and change minimap icon visibility."]},
        {L["Guild bank"],
            L["Browse the latest known stock and check the balance."],
            L["Open the guild vault to scan it. In the addon, select a tab or search across all tabs. Bank settings show the selected tab’s permissions when WoW provides them."]},
    }
    local illustrations = {
        {"GuideProfessions", 1.61861}, {"GuideRoster", 1.61358},
        {"GuideAdministration", 1.61780}, {"GuideOrders", 1.56414},
        {"GuideLog", 1.57143}, {"GuideSettings", 1.70297}, {"GuildAdministration", 1.5},
    }
    local topicIcons = {
        "TabProfessions", "TabRoster", "TabAdministration",
        "TabOrders", "TabLog", "SettingsGear", "Interface\\Icons\\INV_Misc_Coin_01",
    }
    local advice = { L["The dialog lists materials for the selected quantity. After sending, check Crafting orders under Sent orders. Pending orders are queued for later delivery."], L["Use search and Online only to filter the roster. Select a member to see their professions and choose Show recipes to browse them."], L["Select a character on the left to edit member notes. Public and officer notes each have their own save button."], L["Use Completed only to find finished orders. Reopen moves an order back to the active list. Hover the result or any material to see its item tooltip."], L["After a failed sync, export the diagnostics and share the log with a description of the problem."], L["Under Guild bank, you can separately configure automatic requests and sharing."], L["The saved snapshot is available with the vault closed. Automatic sync uses the WoW guild channel. Both options are under Settings, then Guild bank."] }
    local icon = details:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("TOPLEFT", 18, -15)
    title:ClearAllPoints()
    title:SetPoint("LEFT", icon, "RIGHT", 9, 0)
    local tip = orderText(details, 20, -265, 20)
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -16)
    tip:SetPoint("RIGHT", details, "RIGHT", -20, 0)
    tip:SetTextColor(.94, .80, .58)
    local artwork = CreateFrame("Frame", nil, details)
    artwork:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, -18)
    artwork:SetPoint("BOTTOMRIGHT", details, "BOTTOMRIGHT", -20, 20)
    local illustration = artwork:CreateTexture(nil, "ARTWORK")
    local aspect = 1
    local function layoutIllustration()
        local width, height = artwork:GetSize()
        local fittedWidth = math.max(1, math.min(width, height * aspect))
        illustration:SetSize(fittedWidth, fittedWidth / aspect)
    end
    illustration:SetPoint("TOP", artwork)
    artwork:SetScript("OnSizeChanged", layoutIllustration)
    local artPath = "Interface\\AddOns\\ForeverGuild\\Art\\"
    local function showScreenshot(asset, ratio)
        illustration:SetTexture(artPath .. asset)
        aspect = ratio
        layoutIllustration()
    end
    local showOrderExample = false
    local example
    example = button(details, L["Order dialog"], 140, 0, 0, function()
        showOrderExample = not showOrderExample
        if showOrderExample then
            showScreenshot("GuideOrderDialog", 1.61649)
            example:SetText(L["Professions overview"])
        else
            showScreenshot(unpack(illustrations[1]))
            example:SetText(L["Order dialog"])
        end
    end)
    example:ClearAllPoints()
    example:SetPoint("TOPRIGHT", -20, -20)
    local screenshotLanguage = details:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    screenshotLanguage:SetText("Screenshots shown in German")
    screenshotLanguage:SetPoint("BOTTOMRIGHT", -20, 6)
    screenshotLanguage:SetShown(not de)
    local buttons = {}
    local function selectTopic(index)
        for i, control in ipairs(buttons) do
            local active = i == index
            control:SetBackdropColor(.29, .17, .055, active and 1 or .55)
            control:SetBackdropBorderColor(.73, .47, .19, active and 1 or .60)
            control.marker:SetShown(active)
        end
        local topic = topics[index]
        title:SetText(topic[1])
        icon:SetTexture(index == 7 and topicIcons[index] or artPath .. topicIcons[index])
        showScreenshot(unpack(illustrations[index]))
        showOrderExample = false
        example:SetText(L["Order dialog"])
        example:SetShown(index == 1)
        summary:SetText(topic[2])
        actions:SetText(topic[3])
        tip:SetText(advice[index])
    end
    heading(navigation, L["Guide topics"], 13, -13):SetFontObject(GameFontNormalLarge)
    local groups = {
        {L["Crafting"], 1, 4},
        {L["Guild"], 2, 3, 7},
        {L["Other"], 5, 6},
    }
    local y = -40
    for _, group in ipairs(groups) do
        local category = panel(navigation, .8, nil, .96)
        category:SetPoint("TOPLEFT", 13, y)
        category:SetSize(186, 22)
        heading(category, group[1], 7, -4)
        y = y - 26
        for position = 2, #group do
            local index = group[position]
            local control = CreateFrame("Button", nil, navigation, "BackdropTemplate")
            control:SetPoint("TOPLEFT", 13, y)
            control:SetSize(186, 26)
            control:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            local caption = control:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            caption:SetPoint("LEFT", 9, 0)
            caption:SetText(topics[index][1])
            control.marker = control:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            control.marker:SetPoint("RIGHT", -9, 0)
            control.marker:SetText("›")
            local hover = control:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(.88, .60, .21, .16)
            control:SetScript("OnClick", function() selectTopic(index) end)
            buttons[index] = control
            y = y - 30
        end
        y = y - 6
    end
    selectTopic(1)
end

local function toggle()
    if uiInCombat() then return end
    if window then
        if window:IsShown() then window:Hide() else window:Show() end
        return
    end
    window = CreateFrame("Frame", "ForeverGuildWindow", UIParent, "PortraitFrameTemplate")
    table.insert(UISpecialFrames, "ForeverGuildWindow")
    resizeMainWindow()
    local gear = button(window, "", 27, 0, 0, showSettings)
    gear:ClearAllPoints()
    gear:SetSize(27, 18)
    if window.CloseButton then
        gear:SetPoint("RIGHT", window.CloseButton, "LEFT", -4, 0)
        gear:SetFrameLevel(window.CloseButton:GetFrameLevel() + 2)
    else
        gear:SetPoint("TOPRIGHT", -34, -5)
        gear:SetFrameLevel(window:GetFrameLevel() + 5)
    end
    local gearIcon = gear:CreateTexture(nil, "OVERLAY")
    gearIcon:SetSize(16, 16)
    gearIcon:SetPoint("CENTER")
    gearIcon:SetTexture("Interface\\AddOns\\ForeverGuild\\Art\\SettingsGear")
    iconTooltip(gear, L["Settings"])
    window:SetPoint("CENTER")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:SetClampRectInsets(0, 42, 0, 0)
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetTitle("Forever Guild")
    window:SetPortraitToAsset(addonIcon)
    local opaque = window:CreateTexture(nil, "BACKGROUND", nil, -8)
    opaque:SetPoint("TOPLEFT", 8, -26)
    opaque:SetPoint("BOTTOMRIGHT", -5, 5)
    opaque:SetColorTexture(.094, .072, .055, 1)

    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if load and not (InCombatLockdown and InCombatLockdown()) then pcall(load, "Blizzard_Professions") end
    window.professionTab = sideTab(window, 2, "Interface\\AddOns\\ForeverGuild\\Art\\TabProfessions", L["Guild professions"], function()
        activeTab = "professions"
        refresh()
    end)
    window.logTab = sideTab(window, -3, "Interface\\AddOns\\ForeverGuild\\Art\\TabLog", "Log", function()
        activeTab = "log"
        refresh()
    end)
    window.rosterTab = sideTab(window, 1, "Interface\\AddOns\\ForeverGuild\\Art\\TabRoster", L["Guild roster"], function()
        updateRoster()
        activeTab = "roster"
        if database and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        refresh()
    end)

    window.adminTab = sideTab(window, -2, "Interface\\AddOns\\ForeverGuild\\Art\\TabAdministration", L["Guild management"], function()
        updateRoster()
        activeTab = "admin"
        if database and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        refresh()
    end)
    buildGuildAdmin()
    if orderBook then
        window.ordersTab = sideTab(window, 3, "Interface\\AddOns\\ForeverGuild\\Art\\TabOrders", L["Crafting orders"], function()
            activeTab = "orders"
            refresh()
        end)
        buildOrders()
        window.boardTab = sideTab(window, 5, "Interface\\ICONS\\INV_Misc_Note_01", L["Bulletin board"], function()
            activeTab = "board"
            refresh()
        end)
        buildBoard()
    end

    if guildBank then
        window.bankTab = sideTab(window, 4, "Interface\\ICONS\\INV_Misc_Coin_01", L["Guild bank"], function()
            activeTab = "bank"
            if preference("bankAutoRequest") then requestBankSnapshot() end
            scanVisibleBank()
            refresh()
        end)
        buildGuildBank()
    end

    window.helpTab = sideTab(window, -1, "Interface\\AddOns\\ForeverGuild\\Art\\TabHelp", L["Help"], function()
        activeTab = "help"
        refresh()
    end)
    buildHelp()

    window.professions = panel(window, 0)
    window.professions:SetPoint("TOPLEFT", 14, -46)
    window.professions:SetPoint("BOTTOMRIGHT", -14, 13)
    pageBackdrop(window.professions, "GuildProfessions", 1.5, .88)
    local guildPanel = contrastPanel(window.professions)
    guildPanel:SetPoint("TOPRIGHT", -9, -9)
    guildPanel:SetPoint("BOTTOMRIGHT", -9, 9)
    guildPanel:SetWidth(285)
    heading(guildPanel, L["Guild members"], 14, -13)
    window.rosterLabel = heading(guildPanel, "", 14, -33)
    local recipePanel = panel(window.professions, 0, nil, .72)
    recipePanel:SetPoint("TOPLEFT", 9, -9)
    recipePanel:SetPoint("BOTTOMRIGHT", guildPanel, "BOTTOMLEFT", -7, 0)
    window.memberLabel = heading(recipePanel, "", 14, -44)
    local orderHint = orderText(recipePanel, 14, -64, 31)
    orderHint:SetFontObject(GameFontHighlightSmall)
    orderHint:SetText(L["Expand a profession and click Place order next to the recipe you want."])
    search = CreateFrame("EditBox", nil, recipePanel, "InputBoxTemplate")
    search:SetSize(320, 24)
    search:SetPoint("TOPLEFT", 19, -10)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    heading(recipePanel, L["Character, profession or recipe"], 355, -16)
    window.renderPlayers = list(guildPanel, 12, -56, -35, 14, 237, 21)
    window.renderRecipes, window.recipeScroll = list(recipePanel, 12, -87, -36, 14, 590, 24, recipeTooltip)
    search:SetScript("OnTextChanged", function()
        window.recipeScroll:SetVerticalScroll(0)
        refresh()
    end)

    buildRosterView()
    window.log = panel(window)
    window.log:SetPoint("TOPLEFT", 14, -46)
    window.log:SetPoint("BOTTOMRIGHT", -14, 13)
    heading(window.log, L["Sync and received data"], 13, -13)
    local export = button(window.log, L["Export diagnostics"], 160, 750, -9, showDiagnostics)
    export:ClearAllPoints()
    export:SetPoint("TOPRIGHT", -18, -9)
    window.renderLog = list(window.log, 13, -38, -36, 14, 879, 23)
    window:SetScript("OnHide", function()
        if orderMenu then orderMenu:Hide() end
        GameTooltip:Hide()
    end)
    local function showRoster()
        activeTab = "roster"
        updateRoster()
        if database and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        if preference("bankAutoRequest") then requestBankSnapshot() end
        refresh()
    end
    window:SetScript("OnShow", showRoster)
    showRoster()
end

updateGuildShortcut = function()
    local enabled = ForeverGuildSettings and ForeverGuildSettings.guildShortcut == true
    if not enabled then
        if guildShortcut then guildShortcut:Hide() end
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    local native = _G.GuildMicroButton or _G.CommunitiesMicroButton
    if not native then return end
    if not guildShortcut then
        local shortcut = CreateFrame("Button", nil, native)
        shortcut:SetAllPoints()
        shortcut:SetFrameLevel(native:GetFrameLevel() + 8)
        shortcut:RegisterForClicks("LeftButtonUp")
        local backing = shortcut:CreateTexture(nil, "ARTWORK")
        backing:SetSize(20, 24)
        backing:SetPoint("CENTER", 0, -1)
        backing:SetColorTexture(.055, .030, .017, 1)

        local emblem = shortcut:CreateTexture(nil, "ARTWORK", nil, 1)
        emblem:SetSize(20, 20)
        emblem:SetPoint("CENTER", backing, "CENTER")
        emblem:SetTexture(addonIcon)
        emblem:SetTexCoord(.035, .965, .035, .965)

        local highlight = shortcut:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(backing)
        highlight:SetColorTexture(.94, .65, .29, .18)
        highlight:SetBlendMode("ADD")
        shortcut:SetScript("OnClick", function()
            local ok, err = pcall(toggle)
            if not ok then reportError("guild shortcut", err) end
        end)
        iconTooltip(shortcut, "ForeverGuild", L["Opens the guild overview."])
        guildShortcut = shortcut
    end
    guildShortcut:Show()
end

local function createMinimapIcon()
    if not Minimap then return end
    local icon = CreateFrame("Button", "ForeverGuildMinimapButton", Minimap)
    minimapIcon = icon
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 8, -8)
    icon:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local image = icon:CreateTexture(nil, "ARTWORK")
    image:SetSize(21, 21)
    image:SetPoint("CENTER")
    image:SetTexture(addonIcon)
    local border = icon:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    icon:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    icon:SetScript("OnClick", function(_, mouseButton)
        local action = mouseButton == "RightButton" and showDiagnostics or toggle
        local ok, err = pcall(action)
        if not ok then reportError("minimap", err) end
    end)
    iconTooltip(icon, "ForeverGuild", L["Left click: overview · Right click: diagnostic export"])
    icon:SetShown(preference("minimap"))
end

updateOrderNotice = function()
    if not orderNotice then return end
    local total = orderBook.unread(guildKey)
    orderNotice.counter:SetText(total > 99 and "99+" or tostring(total))
    orderNotice.counter:SetShown(total > 1)
    orderNotice:SetShown(total > 0)
end

local function createOrderNotice()
    if not Minimap or not orderBook or orderNotice then return end
    local icon = CreateFrame("Button", "ForeverGuildOrderNotification", Minimap, "BackdropTemplate")
    orderNotice = icon
    icon:SetSize(31, 31)
    local native = _G.MiniMapMailFrame
    if native then icon:SetPoint("TOP", native, "BOTTOM", 0, -4)
    else icon:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -1, -30) end
    icon:SetFrameLevel(Minimap:GetFrameLevel() + 9)
    icon:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    icon:SetBackdropColor(.10, .065, .03, 1)
    icon:SetBackdropBorderColor(.87, .60, .25, 1)
    local letter = icon:CreateTexture(nil, "ARTWORK")
    letter:SetSize(24, 24)
    letter:SetPoint("CENTER")
    local mailIcon = _G.MiniMapMailIcon
    local atlas = mailIcon and mailIcon.GetAtlas and mailIcon:GetAtlas()
    if atlas then
        letter:SetAtlas(atlas)
    else
        letter:SetTexture((mailIcon and mailIcon.GetTexture and mailIcon:GetTexture()) or "Interface\\Icons\\INV_Letter_15")
    end
    icon.counter = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icon.counter:SetPoint("BOTTOMRIGHT", 5, -2)
    icon.counter:SetTextColor(1, .85, .43)
    icon:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local total = orderBook.unread(guildKey)
        GameTooltip:SetText(L["Order notifications"])
        GameTooltip:AddLine((L["Unread: %d"]):format(total), 1, 1, 1)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon:SetScript("OnClick", function()
        if uiInCombat() then return end
        if not window or not window:IsShown() then toggle() end
        if window and window:IsShown() and window.openUnreadOrders then window.openUnreadOrders() end
        GameTooltip:Hide()
    end)
    updateOrderNotice()
end

local function captureBankGold()
    if guildBankOpen and guildKey == guildIdentity() and guildBank.captureBalance(guildKey) then
        if preference("bankShare") then guildBank.shareBalance(guildKey, enqueue) end
        if activeTab == "bank" then queueRefresh() end
    end
end

local function captureBankTab(index, populatedOnly)
    local changed, captured = guildBank.capture(guildKey, index, populatedOnly)
    if captured and preference("bankShare") then
        guildBank.queueShare(captured)
        guildBank.share(guildKey, enqueue)
    end
    if changed and activeTab == "bank" then queueRefresh() end
    return captured ~= nil
end

local function guildBankInteraction()
    return Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
end

scanVisibleBank = function()
    local interaction = guildBankInteraction()
    local manager = C_PlayerInteractionManager
    local interacting = interaction and manager and manager.IsInteractingWithNpcOfType
        and manager.IsInteractingWithNpcOfType(interaction)
    local nativeVisible = GuildBankFrame and GuildBankFrame:IsShown()
    if not guildBank or not guildKey or guildKey ~= guildIdentity()
        or not (guildBankOpen or interacting or nativeVisible) then return end
    local found = false
    local count = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    for index = 1, math.min(count, 8) do
        if captureBankTab(index, true) then found = true end
    end
    if count == 0 then found = captureBankTab(nil, true) end
    return found
end

local function queryBankTabs(scan, first)
    if bankScan ~= scan or not guildBankOpen or scan.guild ~= guildIdentity() then return end
    local index = guildBank.queryNext(first)
    if not index then
        bankScan = nil
        local current = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
        if scan.original and scan.original > 0 and scan.index == current and current ~= scan.original and SetCurrentGuildBankTab then
            local ok = pcall(SetCurrentGuildBankTab, scan.original)
            if ok and QueryGuildBankTab and GetCurrentGuildBankTab() == scan.original then
                pcall(QueryGuildBankTab, scan.original)
            end
        end
        return
    end
    scan.index, scan.received = index, false
    after(3, function()
        if bankScan == scan and scan.index == index then
            if GetCurrentGuildBankTab() == index then queryBankTabs(scan, index + 1)
            else bankScan = nil end
        end
    end)
end

startBankScan = function()
    if guildBankOpen then return end
    guildBankOpen = guildBank ~= nil and guildKey ~= nil and guildKey == guildIdentity()
    if not guildBankOpen then return end
    guildBank.beginScan()
    local scan = { guild = guildKey }
    bankScan = scan
    after(.7, function()
        if bankScan ~= scan or scan.guild ~= guildIdentity() then return end
        scanVisibleBank()
        captureBankGold()
        scan.original = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
        queryBankTabs(scan, 1)
    end)
    local openedGuild = guildKey
    after(2, function()
        if guildBankOpen and openedGuild == guildKey then scanVisibleBank() end
    end)
end

local function initializePlayer()
    ForeverGuildDB = ForeverGuildDB or {}
    ForeverGuildSettings = ForeverGuildSettings or {}
    ForeverGuildRoles = ForeverGuildRoles or {}
    ForeverGuildRoleRecords = ForeverGuildRoleRecords or {}
    ForeverGuildLog = ForeverGuildLog or {}
    ForeverGuildCharacter = ForeverGuildCharacter or {}
    ForeverGuildDiscoveredRecipes = ForeverGuildDiscoveredRecipes or {}
    player = fullName(UnitFullName("player"))
    playerGivenName = utf8Lower(player:match("^[^%s%-]+"))
    registered = registerMessagePrefix(prefix)
    roleChannel = registerMessagePrefix(rolePrefix)
    orderChannel = orderBook and registerMessagePrefix(orderBook.prefix)
    if orderBook and not orderChannel then diagnose("WARN", "orders", "Addon channel unavailable; local queue remains active") end
    updateSkills()
    diagnose(registered and "INFO" or "WARN", "login", registered and "Addon channel registered" or "Addon channel registration failed")
    updateGuild()
    ForeverGuildItemCache = ForeverGuildItemCache or {}
    local cacheKey = tostring(select(2, GetBuildInfo())) .. ":" .. GetLocale()
    if ForeverGuildItemCache.key ~= cacheKey or type(ForeverGuildItemCache.items) ~= "table" then
        ForeverGuildItemCache = { key = cacheKey, items = {} }
    end
    itemDetails = ForeverGuildItemCache.items
    preloadRecipeItems()
    createMinimapIcon()
    createOrderNotice()
    updateGuildShortcut()
    after(5, requestSync)
    queueBackgroundScan(8)
    after(6, maybeShowSetup)
    after(300 + math.random(0, 60), periodicSync)
    if orderBook then after(5, pollOrders) end
end

local function handleItemData(itemID, success)
    if recipeLoad.finish then recipeLoad.finish(itemID, not not success) end
    if pendingItems[itemID] then
        pendingItems[itemID] = nil
        if success then
            recipeItemDetails(itemID)
            queueRefresh()
            local catalog = window and window.boardCatalog
            if catalog and catalog:IsShown() then
                catalog.updateProgress()
                catalog.queueItemRefresh()
            end
            local dialog = orderDialog
            if dialog and dialog:IsShown() and not dialog.itemRefreshPending then
                dialog.itemRefreshPending = true
                after(.25, function()
                    dialog.itemRefreshPending = nil
                    if dialog:IsShown() then dialog.refreshMaterials() end
                end)
            end
        end
    end
end

-- Explicit two-client transport probe. It does not transmit board or guild data.
function addon.partnerProbe(target, incoming)
    local probe = addon.probe
    if not orderChannel or not chat or not chat.SendAddonMessage or not target then return end
    if incoming then
        if not probe or probe.untilTime < GetTime() or fullName(target) ~= probe.key then return end
        if incoming == "P:PROBE" then
            pcall(chat.SendAddonMessage, orderBook.prefix, "P:PROBE_ACK", "WHISPER", target)
        elseif incoming ~= "P:PROBE_ACK" then return end
        print((L["ForeverGuild · Partner probe received from %s."]):format(target))
        return
    end
    target = target:match("^%s*(.-)%s*$")
    if target == "" or #target > 115 or target:find("[%c|:]") then return end
    addon.probe = { key = fullName(target), untilTime = GetTime() + 120 }
    local ok, result = pcall(chat.SendAddonMessage, orderBook.prefix, "P:PROBE", "WHISPER", target)
    local accepted = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    if ok and (result == nil or result == true or result == accepted) then
        print(L["ForeverGuild · Partner probe sent. Waiting for a reply."])
    else
        print(L["ForeverGuild · The WoW client did not send the partner probe."])
    end
end

local function handleGuildMessage(incomingPrefix, message, channel, sender)
    if channel == "WHISPER" and orderBook and incomingPrefix == orderBook.prefix
        and sender and message:sub(1, 4) == "P:E:" then
        if addon.partnerActive() and addon.guildPartners.receiveEvent(guildKey, sender, message, orderClock(),
            function(actual, expected) return utf8Lower(fullName(actual)) == utf8Lower(fullName(expected)) end)
            and activeTab == "board" then
            queueRefresh()
        end
        return
    end
    if channel == "WHISPER" and orderBook and incomingPrefix == orderBook.prefix
        and sender and message:sub(1, 4) == "P:L:" then
        if addon.partnerActive() and addon.guildPartners.receive(guildKey, sender, message, orderClock(),
            function(actual, expected) return utf8Lower(fullName(actual)) == utf8Lower(fullName(expected)) end,
            addon.sendPartnerMessage) and activeTab == "admin" then
            queueRefresh()
        end
        return
    end
    if channel == "WHISPER" and orderBook and incomingPrefix == orderBook.prefix
        and (message == "P:PROBE" or message == "P:PROBE_ACK") then
        addon.partnerProbe(sender, message)
        return
    end
    if channel ~= "GUILD" or not database or not sender or guildKey ~= guildIdentity() then return end
    if orderBook and incomingPrefix == orderBook.prefix then
        receiveOrderMessage(sender, message)
    elseif incomingPrefix == prefix then
        if guildBank and (message == "BQ" or message:sub(1, 2) == "B:") then
            local member = roleMemberKey(sender)
            if member == player then return end
            if not roster[member] then updateRoster(); member = roleMemberKey(sender) end
            if not roster[member] then return end
            if message == "BQ" then
                if preference("bankShare") and GetTime() - lastBankReply >= 30 then
                    lastBankReply = GetTime()
                    guildBank.share(guildKey, enqueue, true)
                end
            elseif guildBank.receive(guildKey, member, message) and activeTab == "bank" then
                queueRefresh()
            end
        else
            receive(message, sender)
        end
    elseif incomingPrefix == rolePrefix and memberRoles then
        receiveRole(message, sender)
        if activeTab == "roster" then queueRefresh() end
    end
end

local function closeCombatWindows()
    for _, dialog in pairs({ window, settingsWindow, setupDialog, exportFrame,
        orderDialog, orderMenu, window and window.boardCatalog, window and window.groupComposer }) do
        if dialog:IsShown() then dialog:Hide() end
    end
end

local function onEvent(_, event, ...)
    if event == "PLAYER_LOGIN" then
        initializePlayer()
    elseif event == "PLAYER_GUILD_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" then
            updateGuildShortcut()
            createOrderNotice()
        end
        local previous = guildKey
        updateGuild()
        if guildKey and guildKey ~= previous then
            after(5, requestSync)
            queueBackgroundScan(8)
            after(6, maybeShowSetup)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        closeCombatWindows()
    elseif event == "PLAYER_REGEN_ENABLED" then
        updateGuildShortcut()
        maybeShowSetup()
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        local spellID, success = ...
        if success and addon.recipeCatalog[spellID] and not addon.recipeCatalog[spellID].name then
            local catalog = window and window.boardCatalog
            if catalog and catalog:IsShown() then catalog.queueItemRefresh() end
            queueRefresh()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        handleItemData(...)
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        resizeMainWindow()
    elseif event == "GUILDBANKFRAME_OPENED" or event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if event == "GUILDBANKFRAME_OPENED" or (guildBankInteraction() and (...) == guildBankInteraction()) then
            startBankScan()
        end
    elseif event == "GUILDBANKFRAME_CLOSED" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if event == "GUILDBANKFRAME_CLOSED" or (guildBankInteraction() and (...) == guildBankInteraction()) then
            guildBankOpen, bankScan = false, nil
        end
    elseif event == "GUILDBANK_UPDATE_MONEY" then
        captureBankGold()
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        if guildBankOpen and guildKey == guildIdentity() then
            local scan = bankScan
            if scan and scan.index then
                local index = scan.index
                if GetCurrentGuildBankTab() ~= index then
                    bankScan = nil
                    captureBankTab()
                elseif not scan.received then
                    scan.received = true
                    local function finishTab()
                        if bankScan ~= scan or scan.index ~= index or scan.guild ~= guildIdentity() then return end
                        if GetCurrentGuildBankTab() ~= index then bankScan = nil; return end
                        if captureBankTab(index) then
                            queryBankTabs(scan, index + 1)
                        else
                            scan.received = false
                        end
                    end
                    after(.25, finishTab)
                end
            else
                captureBankTab()
            end
        end
    elseif event == "GUILD_MOTD" then
        if activeTab == "admin" or activeTab == "board" then queueRefresh() end
    elseif event == "GUILD_ROSTER_UPDATE" then
        updateRoster()
        dispatchOrders()
        refresh()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addonName, blockedAction = ...
        if addonName == "ForeverGuild" and window and window.admin and window.admin.lastEdit
            and GetTime() - window.admin.lastEdit < 3 then
            window.admin.blockedEdit = true
            window.admin.status:SetText(L["WoW blocked the change. Open WoW guild management."])
        end
        if addonName == "ForeverGuild" then diagnose("ERROR", event, blockedAction) end
        if addonName == "ForeverGuild" and backgroundScan then
            ForeverGuildBackgroundScan = false
            backgroundScan.ids = {}
            logEvent(L["Automatic profession opening was blocked by the client"])
        end
    elseif event == "CHAT_MSG_ADDON" then
        handleGuildMessage(...)
    elseif backgroundScan then
        silenceProfessionWindow()
    elseif event == "NEW_RECIPE_LEARNED" then
        scheduleScan()
        queueBackgroundScan(1)
    else
        scheduleScan()
    end
end

frame:SetScript("OnEvent", function(...)
    local _, event = ...
    local ok, err = pcall(onEvent, ...)
    if not ok then reportError(event, err) end
end)

for _, event in ipairs({
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_MONEY",
    "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "SPELL_DATA_LOAD_RESULT", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "GUILD_MOTD", "CHAT_MSG_ADDON",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "NEW_RECIPE_LEARNED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "SKILL_LINES_CHANGED",
}) do
    pcall(frame.RegisterEvent, frame, event)
end

SLASH_FOREVERGUILD1 = "/fguild"
SlashCmdList.FOREVERGUILD = function(message)
    local partner = message:match("^partnertest%s+(.+)$")
    if partner then addon.partnerProbe(partner); return end
    if message == "hidden" or message:match("^restore%s+%d+$") then
        local rows = guildKey and addon.boardRights.hiddenList(guildKey) or {}
        local index = tonumber(message:match("(%d+)$"))
        if index then
            local row = rows[index]
            if row and addon.boardRestore(row.kind, row.owner, row.token) then
                print(L["ForeverGuild · Post restored."])
            else
                print(L["ForeverGuild · Cannot restore (unknown number or missing permission)."])
            end
            return
        end
        local kinds = { O = L["Order"], G = L["Event"], A = L["Announcement"] }
        if #rows == 0 then print(L["ForeverGuild · No hidden posts."]) end
        for i, row in ipairs(rows) do
            print(("%d. %s · %s · %s %s"):format(i, kinds[row.kind] or row.kind, row.owner,
                L["hidden by"], row.by or "?"))
        end
        if #rows > 0 then print(L["Restore: /fguild restore <number>"]) end
        return
    end
    local relayName = message:match("^partnerrelay%s*(.*)$")
    if relayName then
        if not addon.partnerMaster() then
            print(L["ForeverGuild · Only the guild master can set the relay."])
            return
        end
        local state = addon.guildPartners.store(guildKey)
        state.relay = relayName ~= "" and fullName(relayName) or nil
        print((L["ForeverGuild · Relay: %s. Partner guilds need your new connection code afterwards."]):format(state.relay or player))
        return
    end
    if message == "settings" then
        showSettings()
        return
    end
    if message == "setup" then
        showSetup()
        return
    end
    if message == "debug" then
        local ok, err = pcall(showDiagnostics)
        if not ok then reportError("export", err) end
        return
    end
    if message == "scan on" or message == "scan off" then
        ForeverGuildBackgroundScan = message == "scan on"
        if ForeverGuildBackgroundScan then queueBackgroundScan(.5)
        elseif backgroundScan then backgroundScan.ids = {} end
        print(ForeverGuildBackgroundScan and L["ForeverGuild · Background scan enabled"]
            or L["ForeverGuild · Background scan disabled"])
        return
    end
    local ok, err = pcall(toggle)
    if not ok then reportError("window", err) end
end
