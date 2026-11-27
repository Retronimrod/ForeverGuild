local _, addon = ...
-- Groups & events: create wizard in four steps (activity, details, date & participants,
-- summary) and the sign-up dialog. Nothing is sent before "Publish" / "Sign up".
-- Kept simple on purpose: one goal per activity, description for special arrangements.
local L = addon.L
local events = addon.events
local UI = addon.eventsUI

local DAY = 86400
local ART = "Interface\\AddOns\\ForeverGuild\\Art\\"
local ROLE_INDEX = { T = 1, H = 2, D = 3 }
local ROLE_KEYS = { "T", "H", "D" }
local GOLD, LIGHT, MUTED, RED, GREEN = { 1, .82, .24 }, { .93, .87, .74 }, { .62, .57, .50 }, { 1, .45, .35 }, { .45, .86, .45 }
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"

-- The one activity-specific input of each activity.
local GOALS = {
    quest = { label = "Quest", hint = "Quest name or pick one from your quest log", quests = true },
    recipe = { label = "Recipe you are looking for", hint = "Recipe name – search or type it", items = true },
    gear = { label = "Item you are looking for", hint = "Item name – search or type it", items = true },
    material = { label = "Material you are looking for", hint = "Material name – search or type it", items = true },
    worldboss = { label = "World boss", hint = "Name of the world boss" },
    pvp = { label = "PvP activity", hint = "e.g. a battleground or world PvP" },
}

local wizard

local function text(parent, font, justify, wrap) return UI.text(parent, font, justify, wrap) end

-- Note: SetMaxBytes counts the terminating zero byte, so "bytes" is the visible length + 1.
-- (This was the cause of "27.11.202" and "20:0" in 0.9.66.)
local function input(parent, width, chars, numeric)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 24)
    box:SetAutoFocus(false)
    if chars then box:SetMaxBytes(chars + 1) end
    if numeric then box:SetNumeric(true); box:SetMaxLetters(numeric) end
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    return box
end

local function opaque(frame, edge)
    local base = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetPoint("TOPLEFT", 5, -5)
    base:SetPoint("BOTTOMRIGHT", -5, 5)
    base:SetColorTexture(.075, .055, .04, 1)
    frame:SetBackdrop({ edgeFile = edge or "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = edge and 14 or 26,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    if edge then frame:SetBackdropBorderColor(.72, .53, .27) end
end

local function caption(parent, label, x, y, font)
    local label_ = text(parent, font or "GameFontNormalSmall")
    label_:SetPoint("TOPLEFT", x, y)
    label_:SetText(label)
    return label_
end

local function sectionTitle(parent, label, x, y)
    local title = text(parent, "GameFontNormal")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(label)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("LEFT", title, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    rule:SetColorTexture(.5, .35, .17, .7)
    title.rule = rule
    return title
end

-- Selection tiles: normal, selected (gold frame, glow, check), dimmed (others once one is
-- selected), hover (brighter), unavailable (grey, not clickable), coming soon.
local function tileFrame(parent)
    local tile = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    tile:SetBackdropColor(.05, .035, .025, 1)
    tile.art = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
    tile.art:SetPoint("TOPLEFT", 4, -4)
    tile.art:SetPoint("BOTTOMRIGHT", -4, 4)
    tile.shade = tile:CreateTexture(nil, "BACKGROUND", nil, 2)
    tile.shade:SetAllPoints(tile.art)
    tile.shade:SetColorTexture(1, 1, 1, 1)
    tile.shade:SetGradient("HORIZONTAL", CreateColor(.03, .02, .015, .96), CreateColor(.03, .02, .015, .25))
    tile.glow = tile:CreateTexture(nil, "BORDER")
    tile.glow:SetAllPoints(tile.art)
    tile.glow:SetColorTexture(1, .8, .3, .13)
    tile.check = tile:CreateTexture(nil, "OVERLAY")
    tile.check:SetSize(22, 22)
    tile.check:SetPoint("TOPRIGHT", -6, -5)
    tile.check:SetTexture(CHECK)
    tile.check:SetVertexColor(1, .82, .25)
    tile:SetScript("OnEnter", function(self)
        self.hover = true
        self.applyState()
        if self.tooltipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipTitle)
            if self.tooltipText then GameTooltip:AddLine(self.tooltipText, 1, 1, 1, true) end
            GameTooltip:Show()
        end
    end)
    tile:SetScript("OnLeave", function(self) self.hover = false; self.applyState(); GameTooltip:Hide() end)
    tile.labels = {}
    tile.setState = function(state) tile.state = state; tile.applyState() end
    tile.applyState = function()
        local state, hover = tile.state or "normal", tile.hover
        local selected, dimmed = state == "selected", state == "dimmed"
        local off = state == "disabled" or state == "soon"
        tile.glow:SetShown(selected or (hover and not off))
        tile.glow:SetAlpha(selected and 1 or .5)
        tile.check:SetShown(selected)
        if selected then tile:SetBackdropBorderColor(1, .8, .25)
        elseif off then tile:SetBackdropBorderColor(.3, .28, .25)
        else tile:SetBackdropBorderColor(.5, .36, .18) end
        local artAlpha = selected and .95 or (off and .25 or (dimmed and (hover and .6 or .32) or (hover and .85 or .65)))
        tile.art:SetAlpha(artAlpha)
        tile.art:SetDesaturated(off or (dimmed and not hover))
        if tile.icon then
            tile.icon:SetDesaturated(off or (dimmed and not hover))
            tile.icon:SetAlpha(off and .45 or ((dimmed and not hover) and .6 or 1))
        end
        for _, label in ipairs(tile.labels) do
            label:SetAlpha(off and .5 or ((dimmed and not hover) and .62 or 1))
        end
    end
    return tile
end

local function parseDay(value)
    local d, m, y = (value or ""):match("^%s*(%d%d?)%.(%d%d?)%.(%d%d%d%d)%s*$")
    if not d then return end
    local stamp = time({ day = tonumber(d), month = tonumber(m), year = tonumber(y), hour = 12 })
    local check = date("*t", stamp)
    if check.day ~= tonumber(d) or check.month ~= tonumber(m) then return end
    return UI.dayStart(stamp)
end

-- Local date + hour + minute -> one timestamp (seconds since epoch, the same for every
-- member; each client shows it in its own local time).
local function compose(dayText, hour, minute)
    local day = parseDay(dayText)
    if not day or not hour or not minute then return end
    local parts = date("*t", day)
    parts.hour, parts.min, parts.sec = hour, minute, 0
    return time(parts)
end
UI.parseDate = function(dayText, clock)
    local h, m = (clock or ""):match("^(%d%d?):(%d%d)$")
    return compose(dayText, tonumber(h), tonumber(m))
end

-- Factions of the current character (only what the client reports; nothing invented).
local function factionList()
    local list = {}
    local rep = C_Reputation
    if rep and rep.GetNumFactions and rep.GetFactionDataByIndex then
        for index = 1, rep.GetNumFactions() do
            local data = rep.GetFactionDataByIndex(index)
            if data and data.name and data.factionID and (not data.isHeader or data.isHeaderWithRep) then
                list[#list + 1] = { id = data.factionID, name = data.name, standing = data.reaction,
                    min = data.currentReactionThreshold, max = data.nextReactionThreshold, value = data.currentStanding }
            end
        end
    elseif GetNumFactions and GetFactionInfo then
        for index = 1, GetNumFactions() do
            local name, _, standing, barMin, barMax, barValue, _, _, isHeader, _, hasRep, _, _, factionID = GetFactionInfo(index)
            if name and (not isHeader or hasRep) then
                list[#list + 1] = { id = factionID or 0, name = name, standing = standing, min = barMin, max = barMax, value = barValue }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Draft -----------------------------------------------------------------------------------------------------
local function defaultRole(ctx)
    local preferred = UI.setting("prefRoles")
    if preferred ~= "" then return preferred end
    local roles = ctx.myRoles()
    return roles ~= "" and roles:sub(1, 1) or "D"
end

local function newDraft(ctx, opts)
    local now = ctx.clock()
    local source = opts.edit or opts.copy
    local draft
    if source then
        draft = events.copyFields(source)
        draft.coorg = opts.copy and {} or (source.coorg and { unpack(source.coorg) } or {})
        if opts.copy then
            -- A copy takes over the plan, never the participants, status or date.
            draft.goal, draft.runs, draft.loot, draft.deadline, draft.duration = nil, nil, nil, nil, nil
            -- Activities that are not open yet cannot be created from a copy either.
            local category = events.byCategory[draft.cat or ""]
            if not category or category.soon or category.retired then draft.cat = nil end
            local clock = date("*t", source.starts)
            draft.starts = UI.dayStart(now) + DAY + clock.hour * 3600 + clock.min * 60
        end
    elseif opts.migrate then
        draft = events.legacyFields(opts.migrate)
        draft.ownerRole = draft.ownerRole or defaultRole(ctx)
        draft.coorg = {}
    else
        draft = { model = "dungeon", slots = { T = 1, H = 1, D = 3 }, ownerRole = defaultRole(ctx), size = 5,
            approve = false, autofill = true, coorg = {} }
        local day = opts.day or (UI.dayStart(now) + (date("*t", now).hour >= 19 and DAY or 0))
        draft.starts = day + 20 * 3600
        if draft.starts <= now then draft.starts = UI.dayStart(now) + DAY + 20 * 3600 end
    end
    draft.mode = "plan"
    draft.targets = draft.targets or {}
    if #draft.targets == 1 then draft.target = draft.targets[1] end
    local parts = date("*t", draft.starts)
    draft.hour, draft.minute = parts.hour, parts.min
    draft.deadlineHours = draft.deadline and math.floor((draft.starts - draft.deadline) / 3600 + .5) or 0
    draft.repeatEvery, draft.repeatCount = 0, 4
    return draft
end

local function collect()
    local w, draft = wizard, wizard.draft
    local fields = events.copyFields(draft)
    local creating = not w.opts.edit
    fields.title = w.title:GetText()
    fields.desc = w.desc:GetText()
    fields.req = w.req:GetText()
    fields.minLevel = tonumber(w.minLevel:GetText())
    fields.maxLevel = tonumber(w.maxLevel:GetText())
    if fields.minLevel == 0 then fields.minLevel = nil end
    if fields.maxLevel == 0 then fields.maxLevel = nil end
    fields.mode, fields.expires = "plan", nil
    if creating then fields.duration = nil end
    fields.starts = compose(w.day:GetText(), draft.hour, draft.minute)
    fields.deadline = fields.starts and draft.deadlineHours > 0 and fields.starts - draft.deadlineHours * 3600 or nil
    if draft.cat == "level" then fields.place = w.zone:GetText() elseif creating then fields.place = nil end
    if draft.cat ~= "dungeon" and creating then fields.dungeon = nil end
    if creating then fields.goal, fields.runs, fields.loot = nil, nil, nil end
    if draft.cat == "dungeon" then fields.targets = creating and nil or draft.targets
    elseif draft.target then fields.targets = { draft.target }
    elseif creating then fields.targets = nil end
    if fields.targets and #fields.targets == 0 then fields.targets = nil end
    local slotted = draft.model == "dungeon" or draft.model == "raid" or draft.model == "custom"
    if slotted then
        fields.slots = { T = tonumber(w.slots.T:GetText()) or 0, H = tonumber(w.slots.H:GetText()) or 0, D = tonumber(w.slots.D:GetText()) or 0 }
        fields.size = nil
    elseif draft.model == "free" then
        fields.slots, fields.size = nil, tonumber(w.size:GetText())
    else
        fields.slots, fields.size = nil, nil
    end
    fields.coorg = #draft.coorg > 0 and { unpack(draft.coorg) } or nil
    return fields
end

local REASONS = {
    category = "Choose an activity.", title = "Enter a title.", start = "Choose a date and time in the future (at most 60 days ahead).",
    duration = "Choose a duration.", deadline = "The sign-up deadline must be before the start.",
    level = "Check the level range (1–60, minimum ≤ maximum).", model = "Choose a group model.",
    slots = "Use 1 to 40 places in total.", ownerRole = "Reserve a place for your own role.",
    size = "Choose a group size between 2 and 40.", dungeon = "Choose a dungeon.", faction = "Choose a faction.",
    targets = "Please check your input.", quarter = "Choose the minutes in quarter hours (00, 15, 30, 45).", text = "A text is too long.", status = "This event can no longer be changed.",
}

local function validateStep(ctx, step)
    local draft, editing = wizard.draft, wizard.opts.edit ~= nil
    local category = events.byCategory[draft.cat or ""]
    if not category or ((category.retired or category.soon) and not editing) then return false, "category" end
    if step == 1 then return true end
    local fields = collect(ctx)
    if events.clean(fields.title, 52) == "" then return false, "title" end
    if fields.minLevel and fields.maxLevel and fields.minLevel > fields.maxLevel then return false, "level" end
    if draft.cat == "dungeon" and not draft.dungeon and not editing then return false, "dungeon" end
    if draft.cat == "rep" and not (draft.target and draft.target.k == "f") and not editing then return false, "faction" end
    if step == 2 then return true end
    if not fields.starts then return false, "start" end
    -- An existing date (edited event or taken-over dungeon date) keeps its minute until it is changed.
    local original = (wizard.opts.edit and wizard.opts.edit.starts) or (wizard.opts.migrate and wizard.opts.migrate.starts)
    local unchanged = original ~= nil and math.abs(fields.starts - original) < 60
    if fields.starts <= ctx.clock() and not unchanged then return false, "start" end
    if not unchanged and (draft.minute or 0) % 15 ~= 0 then return false, "quarter" end
    fields.title = events.clean(fields.title, 52)
    return events.validate(fields, ctx.clock())
end

-- Step 1: activity tiles -------------------------------------------------------------------------------------
local function buildTiles(_, body)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints()
    local heading = text(page, "GameFontNormalLarge", "CENTER")
    heading:SetPoint("TOP", 0, -6)
    heading:SetText(L["What would you like to do?"])
    page.tiles = {}
    for index, category in ipairs(events.creatable) do
        local tile = tileFrame(page)
        tile.key, tile.category = category.key, category
        tile.art:SetTexture(ART .. category.art)
        tile.aspect = (category.art == "DungeonHall" or category.art == "BlackrockHall") and 4 or 2
        tile.icon = tile:CreateTexture(nil, "ARTWORK")
        tile.icon:SetSize(category.soon and 30 or 44, category.soon and 30 or 44)
        tile.icon:SetPoint("LEFT", 12, 0)
        tile.icon:SetTexture(category.icon)
        tile.icon:SetTexCoord(.07, .93, .07, .93)
        local label = text(tile, category.soon and "GameFontNormal" or "GameFontNormalLarge")
        label:SetPoint("TOPLEFT", tile.icon, "TOPRIGHT", 10, -1)
        label:SetPoint("RIGHT", -30, 0)
        label:SetText(L[category.label])
        local desc = text(tile, "GameFontHighlightSmall", "LEFT", true)
        desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
        desc:SetPoint("RIGHT", -10, 0)
        desc:SetText(category.soon and L["Coming Soon"] or L[category.desc])
        if category.soon then UI.color(desc, GOLD) end
        tile.labels = { label, desc }
        if category.soon then
            tile.tooltipTitle = L[category.label]
            tile.tooltipText = L["Planning raids will be available with a future ForeverGuild update."]
        end
        tile:SetScript("OnClick", function()
            if category.soon then return end
            local draft = wizard.draft
            local changed = draft.cat ~= category.key
            draft.cat = category.key
            if changed and not wizard.opts.edit then
                draft.model = category.model == "open" and "free" or category.model
                if draft.model == "dungeon" then draft.slots = { T = 1, H = 1, D = 3 } end
                if draft.model == "raid" then draft.slots = { T = 2, H = 5, D = 13 } end
                draft.target, draft.targets = nil, {}
                wizard.loadInputs()
            end
            wizard.refresh()
        end)
        page.tiles[index] = tile
    end
    page.soonTitle = text(page, "GameFontNormal")
    page.soonTitle:SetText(L["COMING SOON"])
    page.soonRule = page:CreateTexture(nil, "ARTWORK")
    page.soonRule:SetHeight(1)
    page.soonRule:SetColorTexture(.5, .35, .17, .7)
    page:SetScript("OnSizeChanged", function(self, width)
        local gap = 12
        local active, soon = {}, {}
        for _, tile in ipairs(self.tiles) do
            if tile.category.soon then soon[#soon + 1] = tile else active[#active + 1] = tile end
        end
        local activeWidth = math.floor((width - 20 - 2 * gap) / 3)
        for index, tile in ipairs(active) do
            local column, line = (index - 1) % 3, math.floor((index - 1) / 3)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", 10 + column * (activeWidth + gap), -38 - line * 108)
            tile:SetSize(activeWidth, 98)
            UI.fitArt(tile.art, tile.aspect, activeWidth - 8, 90)
        end
        local top = -38 - math.ceil(#active / 3) * 108 - 10
        self.soonTitle:ClearAllPoints()
        self.soonTitle:SetPoint("TOPLEFT", 12, top)
        self.soonRule:ClearAllPoints()
        self.soonRule:SetPoint("LEFT", self.soonTitle, "RIGHT", 8, 0)
        self.soonRule:SetPoint("RIGHT", self, "RIGHT", -10, 0)
        local soonWidth = math.floor((width - 20 - 3 * gap) / 4)
        for index, tile in ipairs(soon) do
            local column, line = (index - 1) % 4, math.floor((index - 1) / 4)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", 10 + column * (soonWidth + gap), top - 22 - line * 66)
            tile:SetSize(soonWidth, 58)
            UI.fitArt(tile.art, tile.aspect, soonWidth - 8, 50)
        end
    end)
    return page
end

-- Dungeon choice inside step 2 (no overlay over the step navigation) -----------------------------------------
local function buildDungeonPicker(ctx, body)
    local w = wizard
    local picker = CreateFrame("Frame", nil, body)
    picker:SetAllPoints()
    picker:Hide()
    local title = text(picker, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText(L["Choose dungeon"])
    picker.cancel = ctx.button(picker, L["Keep current dungeon"], 170, 0, 0, function() w.picking = false; w.refresh() end)
    picker.cancel:ClearAllPoints()
    picker.cancel:SetPoint("TOPRIGHT", -4, -2)
    picker.search = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
    picker.search:SetSize(230, 22)
    picker.search:SetPoint("TOPLEFT", 12, -36)
    picker.search:SetAutoFocus(false)
    picker.search:HookScript("OnTextChanged", function() picker.layout() end)
    if type(picker.search.Instructions) == "table" then picker.search.Instructions:SetText(L["Search dungeon ..."]) end
    picker.fits = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
    picker.fits:SetSize(24, 24)
    picker.fits:SetPoint("LEFT", picker.search, "RIGHT", 16, 0)
    picker.fits:SetScript("OnClick", function() picker.layout() end)
    picker:SetScript("OnShow", function() picker.fits:SetChecked(false); picker.search:SetText("") end)
    local fitsLabel = text(picker.fits, "GameFontHighlightSmall")
    fitsLabel:SetPoint("LEFT", picker.fits, "RIGHT", 2, 0)
    fitsLabel:SetText(L["Suits my level"])
    picker.count = text(picker, "GameFontDisableSmall", "RIGHT")
    picker.count:SetPoint("TOPRIGHT", -30, -40)
    local scroll = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -66)
    scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(700, 1)
    scroll:SetScrollChild(content)
    picker.tiles = {}
    local de = GetLocale() == "deDE"
    for index, dungeon in ipairs(ctx.dungeons()) do
        local tile = tileFrame(content)
        tile.dungeon = dungeon
        tile.art:SetTexture(addon.dungeonArt(dungeon))
        local name = text(tile, "GameFontNormalLarge")
        name:SetPoint("TOPLEFT", 14, -12)
        name:SetPoint("RIGHT", -34, 0)
        name:SetText(dungeon[de and 1 or 2])
        local info = text(tile, "GameFontHighlightSmall")
        info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
        info:SetText(L["Level %d–%d"]:format(dungeon.min, dungeon.max) .. "  ·  " .. dungeon[de and 3 or 4])
        tile.labels = { name, info }
        tile:SetScript("OnClick", function()
            local draft = w.draft
            local old = draft.dungeon and addon.getGroupDungeon(draft.dungeon)
            draft.dungeon = dungeon[6]
            w.dungeonCombined = nil
            local current = w.title:GetText()
            if current == "" or (old and (current == old[1] or current == old[2] or current == old.former)) then
                w.title:SetText(dungeon[de and 1 or 2])
            end
            local low, high = tostring(dungeon.min), tostring(dungeon.max)
            local minText, maxText = w.minLevel:GetText(), w.maxLevel:GetText()
            if minText == "" or minText == w.autoMin then w.minLevel:SetText(low or ""); w.autoMin = low or "" end
            if maxText == "" or maxText == w.autoMax then w.maxLevel:SetText(high or ""); w.autoMax = high or "" end
            w.picking = false
            w.refresh()
        end)
        picker.tiles[index] = tile
    end
    picker.layout = function()
        local width = scroll:GetWidth()
        if width <= 0 then return end
        content:SetWidth(width)
        local columns, gap = 2, 10
        local tileWidth = math.floor((width - (columns - 1) * gap) / columns)
        local tileHeight = 66
        -- Search across German and English names and zones; the level filter is optional,
        -- so events for other guild members can still be planned.
        local query = (picker.search:GetText() or ""):lower()
        local level = picker.fits:GetChecked() and ctx.myLevel() or nil
        local shown = 0
        for _, tile in ipairs(picker.tiles) do
            local dungeon = tile.dungeon
            local hay = (dungeon[1] .. " " .. dungeon[2] .. " " .. dungeon[3] .. " " .. dungeon[4]):lower()
            local visible = (query == "" or hay:find(query, 1, true) ~= nil)
                and (not level or (level >= dungeon.min and level <= dungeon.max))
            tile:SetShown(visible)
            tile.position = nil
            if visible then shown = shown + 1; tile.position = shown end
        end
        picker.count:SetText(L["%d dungeons available"]:format(shown))
        for _, tile in ipairs(picker.tiles) do
          if tile.position then
            local index = tile.position
            local column, line = (index - 1) % columns, math.floor((index - 1) / columns)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", column * (tileWidth + gap), -line * (tileHeight + 8))
            tile:SetSize(tileWidth, tileHeight)
            -- Proportional crop of the 4:1 banners, never stretched.
            addon.fitDungeonArtwork(tile.art, tileWidth - 8, tileHeight - 8)
            local selected = w.draft.dungeon == tile.dungeon[6]
            tile.setState(selected and "selected" or (w.draft.dungeon and "dimmed" or "normal"))
          end
        end
        content:SetHeight(math.max(1, math.ceil(shown / columns) * (tileHeight + 8)))
    end
    scroll:HookScript("OnSizeChanged", picker.layout)
    return picker
end

-- Step 2: details ---------------------------------------------------------------------------------------------
local function buildDetails(ctx, body)
    local w = wizard
    local page = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
    page:SetPoint("TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", -26, 0)
    local content = CreateFrame("Frame", nil, page)
    content:SetSize(700, 400)
    page:SetScrollChild(content)
    page:HookScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    w.activityTitle = sectionTitle(content, "", 4, -4)

    -- Dungeon card
    w.dungeonCard = tileFrame(content)
    w.dungeonCard:SetHeight(74)
    w.dungeonCard:SetScript("OnClick", function() w.picking = true; w.refresh() end)
    w.dungeonHint = text(w.dungeonCard, "GameFontNormalSmall", "RIGHT")
    w.dungeonHint:SetPoint("BOTTOMRIGHT", -12, 10)
    w.dungeonName = text(w.dungeonCard, "GameFontNormalLarge")
    w.dungeonName:SetPoint("TOPLEFT", 14, -14)
    w.dungeonInfo = text(w.dungeonCard, "GameFontHighlight")
    w.dungeonInfo:SetPoint("TOPLEFT", w.dungeonName, "BOTTOMLEFT", 0, -5)
    w.dungeonCard.labels = { w.dungeonName, w.dungeonInfo, w.dungeonHint }

    -- Goal input (quest, recipe, item, material, boss, PvP activity)
    w.goalFrame = CreateFrame("Frame", nil, content)
    w.goalFrame:SetHeight(48)
    w.goalLabel = caption(w.goalFrame, "", 0, 0)
    w.goalIcon = w.goalFrame:CreateTexture(nil, "ARTWORK")
    w.goalIcon:SetSize(22, 22)
    w.goalIcon:SetPoint("TOPLEFT", 4, -17)
    w.goalIcon:SetTexCoord(.07, .93, .07, .93)
    w.goalBox = input(w.goalFrame, 360, 48)
    w.goalBox:SetPoint("TOPLEFT", 34, -16)
    w.goalBox:HookScript("OnTextChanged", function(self, user)
        if not user then return end
        local value = events.clean(self:GetText(), 48)
        w.draft.target = value ~= "" and { k = "t", text = value } or nil
        w.refreshGoal()
    end)
    w.goalSearch = ctx.button(w.goalFrame, L["Search"], 110, 0, 0, function(self)
        local list = {}
        local goal = GOALS[w.draft.cat] or {}
        local finder = ctx.finder()
        local top = w.draft.cat == "material" and "material" or nil
        local results = addon.recipeFinder.searchAll(finder, w.goalBox:GetText(), 25, top)
        if top and #results == 0 then results = addon.recipeFinder.searchAll(finder, w.goalBox:GetText(), 25) end
        for _, group in ipairs(results) do
            local target = group.itemID and { k = "i", id = group.itemID } or { k = "r", id = group.recipes[1] }
            list[#list + 1] = { text = group.name, icon = group.icon or UI.targetIcon(ctx, target), func = function()
                w.draft.target = target
                w.goalBox:SetText(group.name)
                w.refreshGoal()
            end }
        end
        if #list == 0 then list[1] = { text = L["Nothing found – the typed name is used."], disabled = true } end
        UI.menu(self, L[goal.label or "Search"], list)
    end)
    w.goalSearch:ClearAllPoints()
    w.goalSearch:SetPoint("LEFT", w.goalBox, "RIGHT", 8, 0)
    w.goalQuests = ctx.button(w.goalFrame, L["From quest log"], 140, 0, 0, function(self)
        local list, log = {}, C_QuestLog
        if log and log.GetNumQuestLogEntries and log.GetInfo then
            for index = 1, log.GetNumQuestLogEntries() do
                local info = log.GetInfo(index)
                if info and not info.isHeader and info.questID and info.questID > 0 and info.title then
                    local label = info.title
                    if info.level and info.level > 0 then label = ("[%d] %s"):format(info.level, label) end
                    if info.suggestedGroup and info.suggestedGroup > 1 then label = label .. "  " .. L["(group %d)"]:format(info.suggestedGroup) end
                    list[#list + 1] = { text = label, icon = "Interface\\GossipFrame\\AvailableQuestIcon", func = function()
                        w.draft.target = { k = "q", id = info.questID }
                        w.goalBox:SetText(info.title)
                        if info.level and info.level > 0 and w.minLevel:GetText() == "" then w.minLevel:SetText(info.level) end
                        w.refreshGoal()
                    end }
                end
            end
        end
        if #list == 0 then list[1] = { text = L["Your quest log is empty."], disabled = true } end
        UI.menu(self, L["Quest log"], list)
    end)
    w.goalQuests:ClearAllPoints()
    w.goalQuests:SetPoint("LEFT", w.goalSearch, "RIGHT", 6, 0)
    w.goalFrame:SetScript("OnEnter", nil)
    w.refreshGoal = function()
        local target = w.draft.target
        w.goalIcon:SetShown(target ~= nil and target.k ~= "t")
        if target and target.k ~= "t" then w.goalIcon:SetTexture(UI.targetIcon(ctx, target)) end
    end

    -- Reputation
    w.repFrame = CreateFrame("Frame", nil, content)
    w.repFrame:SetHeight(128)
    caption(w.repFrame, L["Faction"], 0, 0)
    w.factionBox = input(w.repFrame, 300, 48)
    w.factionBox:SetPoint("TOPLEFT", 6, -16)
    w.factionPick = ctx.button(w.repFrame, L["Choose faction"], 150, 0, 0, function(self)
        local filter = (w.factionBox:GetText() or ""):lower()
        local list = {}
        for _, faction in ipairs(factionList()) do
            if filter == "" or faction.name:lower():find(filter, 1, true) or (w.draft.target and w.draft.target.text == w.factionBox:GetText()) then
                list[#list + 1] = { text = faction.name .. "  |cffbfae8c" .. UI.standingLabel(faction.standing) .. "|r",
                    icon = events.byCategory.rep.icon, func = function()
                        w.draft.target = { k = "f", id = faction.id or 0, text = faction.name,
                            standing = math.max(4, math.min(8, (w.draft.target and w.draft.target.standing) or (faction.standing or 4) + 1)) }
                        w.draft.faction = faction
                        w.factionBox:SetText(faction.name)
                        local current = w.title:GetText()
                        if current == "" or current == w.autoTitle then
                            w.autoTitle = L["%s – reputation farming"]:format(faction.name)
                            w.title:SetText(w.autoTitle)
                        end
                        w.refresh()
                    end }
            end
        end
        local typed = events.clean(w.factionBox:GetText(), 48)
        if typed ~= "" then
            list[#list + 1] = { divider = true }
            list[#list + 1] = { text = L["Use “%s” as faction"]:format(typed), func = function()
                w.draft.target = { k = "f", id = 0, text = typed, standing = (w.draft.target and w.draft.target.standing) or 8 }
                w.draft.faction = nil
                w.refresh()
            end }
        end
        if #list == 0 then list[1] = { text = L["No reputation data from the client – type the faction name."], disabled = true } end
        UI.menu(self, L["Faction"], list)
    end)
    w.factionPick:ClearAllPoints()
    w.factionPick:SetPoint("LEFT", w.factionBox, "RIGHT", 8, 0)
    w.repCurrent = caption(w.repFrame, "", 0, -48)
    w.repBar = UI.progressBar(w.repFrame)
    w.repBar:SetPoint("TOPLEFT", 6, -64)
    w.repBar:SetSize(300, 16)
    w.repBar.bar:SetStatusBarColor(.25, .62, .25)
    local dropdown = addon.recipeFinder.widgets.dropdown
    w.repGoal = dropdown(w.repFrame, 220, function()
        local list = {}
        for standing = 4, 8 do list[#list + 1] = { standing, UI.standingLabel(standing) } end
        return list
    end, function() return w.draft.target and w.draft.target.standing or 8 end, function(value)
        if w.draft.target and w.draft.target.k == "f" then w.draft.target.standing = value end
        w.refresh()
    end)
    w.repGoalLabel = caption(w.repFrame, L["Shared reputation goal"], 330, -48)
    w.repGoal:SetPoint("TOPLEFT", 336, -62)

    -- Leveling: optional zone
    w.zoneFrame = CreateFrame("Frame", nil, content)
    w.zoneFrame:SetHeight(48)
    caption(w.zoneFrame, L["Zone (optional)"], 0, 0)
    w.zone = input(w.zoneFrame, 360, 60)
    w.zone:SetPoint("TOPLEFT", 6, -16)

    -- General
    w.general = CreateFrame("Frame", nil, content)
    w.general:SetHeight(250)
    caption(w.general, L["Title"], 0, 0)
    w.title = input(w.general, 500, 52)
    w.title:SetPoint("TOPLEFT", 6, -16)
    caption(w.general, L["Description"], 0, -48)
    local descFrame = CreateFrame("Button", nil, w.general, "BackdropTemplate")
    descFrame:SetPoint("TOPLEFT", 0, -64)
    descFrame:SetPoint("RIGHT", -6, 0)
    descFrame:SetHeight(76)
    descFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    descFrame:SetBackdropColor(0, 0, 0, .6)
    descFrame:SetBackdropBorderColor(.5, .4, .25)
    w.desc = CreateFrame("EditBox", nil, descFrame)
    w.desc:SetMultiLine(true)
    w.desc:SetAutoFocus(false)
    w.desc:SetMaxBytes(151)
    w.desc:SetFontObject(GameFontHighlight)
    w.desc:SetPoint("TOPLEFT", 8, -7)
    w.desc:SetPoint("BOTTOMRIGHT", -8, 7)
    w.desc:SetScript("OnEscapePressed", w.desc.ClearFocus)
    descFrame:SetScript("OnClick", function() w.desc:SetFocus() end)
    w.descHint = text(w.general, "GameFontDisableSmall")
    w.descHint:SetPoint("TOPLEFT", descFrame, "BOTTOMLEFT", 4, -3)
    w.descHint:SetText(L["Special arrangements (e.g. loot or meeting point) simply go into the description."])
    caption(w.general, L["Required level"], 0, -162)
    w.minLevel = input(w.general, 40, nil, 2)
    w.minLevel:SetPoint("TOPLEFT", 6, -178)
    local to = text(w.general, "GameFontHighlight")
    to:SetPoint("LEFT", w.minLevel, "RIGHT", 8, 0)
    to:SetText(L["to"])
    w.maxLevel = input(w.general, 40, nil, 2)
    w.maxLevel:SetPoint("LEFT", to, "RIGHT", 10, 0)
    caption(w.general, L["Requirements (optional)"], 170, -162)
    w.req = input(w.general, 380, 100)
    w.req:SetPoint("TOPLEFT", 176, -178)

    page.layout = function()
        local cat = w.draft.cat
        local category = events.byCategory[cat or ""]
        w.activityTitle:SetText(category and L[category.label]:upper() or "")
        local y = -30
        local function place(frame, height)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", 4, y)
            frame:SetPoint("RIGHT", content, "RIGHT", -4, 0)
            frame:Show()
            y = y - height
        end
        for _, frame in ipairs({ w.dungeonCard, w.goalFrame, w.repFrame, w.zoneFrame }) do frame:Hide() end
        if cat == "dungeon" then
            place(w.dungeonCard, 84)
        elseif cat == "rep" then
            place(w.repFrame, 100)
        elseif cat == "level" then
            place(w.zoneFrame, 52)
        elseif GOALS[cat] then
            place(w.goalFrame, 52)
        end
        place(w.general, 214)
        content:SetHeight(-y + 6)
    end
    return page
end

-- Small month calendar for the date field ------------------------------------------------------------------------
local function openDatePicker(ctx, anchor)
    local w = wizard
    local picker = w.datePicker
    if not picker then
        picker = CreateFrame("Frame", "ForeverGuildEventDatePicker", w, "BackdropTemplate")
        w.datePicker = picker
        picker:SetSize(236, 214)
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetToplevel(true)
        picker:EnableMouse(true)
        picker:SetClampedToScreen(true)
        opaque(picker, "Interface\\Tooltips\\UI-Tooltip-Border")
        tinsert(UISpecialFrames, "ForeverGuildEventDatePicker")
        picker.caption = text(picker, "GameFontNormal", "CENTER")
        picker.caption:SetPoint("TOP", 0, -12)
        local function shift(delta)
            picker.month = picker.month + delta
            if picker.month < 1 then picker.month, picker.year = 12, picker.year - 1 end
            if picker.month > 12 then picker.month, picker.year = 1, picker.year + 1 end
            picker.render()
        end
        local prev = ctx.button(picker, "<", 28, 8, -6, function() shift(-1) end)
        local nextButton = ctx.button(picker, ">", 28, 200, -6, function() shift(1) end)
        prev:SetHeight(22); nextButton:SetHeight(22)
        picker.days = {}
        for index = 1, 7 do
            local head = text(picker, "GameFontNormalSmall", "CENTER")
            head:SetPoint("TOPLEFT", 10 + (index - 1) * 31, -36)
            head:SetWidth(30)
            head:SetText(L[UI.WEEKDAYS_SHORT[index % 7 + 1]])
        end
        for index = 1, 42 do
            local day = CreateFrame("Button", nil, picker, "BackdropTemplate")
            day:SetSize(29, 22)
            day:SetPoint("TOPLEFT", 10 + ((index - 1) % 7) * 31, -52 - math.floor((index - 1) / 7) * 25)
            day:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            day.label = text(day, "GameFontHighlightSmall", "CENTER")
            day.label:SetAllPoints()
            day:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            day:SetScript("OnClick", function(self)
                if not self.stamp then return end
                w.day:SetText(date("%d.%m.%Y", self.stamp + 12 * 3600))
                picker:Hide()
                w.refresh()
            end)
            picker.days[index] = day
        end
        picker.render = function()
            picker.caption:SetText(("%s %d"):format(L[UI.MONTHS[picker.month]], picker.year))
            local first = time({ year = picker.year, month = picker.month, day = 1, hour = 12 })
            local offset = (tonumber(date("%w", first)) + 6) % 7
            local today = UI.dayStart(ctx.clock())
            local selected = parseDay(w.day:GetText())
            for index, day in ipairs(picker.days) do
                local stamp = UI.dayStart(first + (index - 1 - offset) * DAY)
                local parts = date("*t", stamp + 12 * 3600)
                local inMonth = parts.month == picker.month
                local usable = inMonth and stamp >= today and stamp <= today + 60 * DAY
                day.stamp = usable and stamp or nil
                day.label:SetText(inMonth and parts.day or "")
                day:EnableMouse(usable)
                if stamp == selected and inMonth then day:SetBackdropColor(.75, .55, .18, .9)
                elseif stamp == today and inMonth then day:SetBackdropColor(.3, .22, .1, .9)
                else day:SetBackdropColor(.12, .09, .06, inMonth and .9 or 0) end
                UI.color(day.label, usable and LIGHT or MUTED)
            end
        end
    end
    local current = parseDay(w.day:GetText()) or UI.dayStart(ctx.clock())
    local parts = date("*t", current + 12 * 3600)
    picker.year, picker.month = parts.year, parts.month
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    picker.render()
    picker:Show()
    picker:Raise()
end

-- Guild member list for co-organizers ------------------------------------------------------------------------------
local function openMemberPicker(ctx)
    local w = wizard
    local picker = w.memberPicker
    if not picker then
        picker = CreateFrame("Frame", "ForeverGuildEventMemberPicker", w, "BackdropTemplate")
        w.memberPicker = picker
        picker:SetSize(340, 400)
        picker:SetPoint("CENTER")
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetToplevel(true)
        picker:EnableMouse(true)
        opaque(picker)
        tinsert(UISpecialFrames, "ForeverGuildEventMemberPicker")
        local title = text(picker, "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 20, -18)
        title:SetText(L["Add guild member"])
        local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
        picker.search = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
        picker.search:SetSize(290, 22)
        picker.search:SetPoint("TOPLEFT", 24, -46)
        picker.search:SetAutoFocus(false)
        picker.search:HookScript("OnTextChanged", function() picker.render() end)
        local scroll = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -76)
        scroll:SetPoint("BOTTOMRIGHT", -34, 18)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(280, 1)
        scroll:SetScrollChild(content)
        picker.rows = {}
        picker.render = function()
            local filter = (picker.search:GetText() or ""):lower()
            local taken = { [ctx.player()] = true }
            for _, name in ipairs(w.draft.coorg) do taken[name] = true end
            local list = {}
            for _, member in ipairs(ctx.members()) do
                if not taken[member.name] and (filter == "" or member.displayName:lower():find(filter, 1, true)) then list[#list + 1] = member end
            end
            table.sort(list, function(a, b)
                if a.online ~= b.online then return a.online and true or false end
                return a.displayName < b.displayName
            end)
            for index, member in ipairs(list) do
                local row = picker.rows[index]
                if not row then
                    row = CreateFrame("Button", nil, content)
                    row:SetHeight(22)
                    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(18, 18)
                    row.icon:SetPoint("LEFT", 2, 0)
                    row.name = text(row, "GameFontHighlight")
                    row.name:SetPoint("LEFT", 26, 0)
                    row.info = text(row, "GameFontHighlightSmall", "RIGHT")
                    row.info:SetPoint("RIGHT", -4, 0)
                    row:SetScript("OnClick", function(self)
                        if #w.draft.coorg < 3 then w.draft.coorg[#w.draft.coorg + 1] = self.member.name end
                        picker:Hide()
                        w.refresh()
                    end)
                    picker.rows[index] = row
                end
                row.member = member
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(index - 1) * 23)
                row:SetPoint("RIGHT", content, "RIGHT")
                UI.classIcon(row.icon, member.class)
                row.name:SetText(member.displayName)
                UI.color(row.name, UI.classColor(ctx, member.name))
                row.info:SetText((member.level and (L["Lv. "] .. member.level .. "  ") or "") .. (member.online and L["Online"] or L["Offline"]))
                UI.color(row.info, member.online and GREEN or MUTED)
                row:Show()
            end
            for index = #list + 1, #picker.rows do picker.rows[index]:Hide() end
            content:SetHeight(math.max(1, #list * 23))
        end
    end
    picker.search:SetText("")
    picker.render()
    picker:Show()
    picker:Raise()
end

-- Step 3: date and participants ------------------------------------------------------------------------------------
local function buildSchedule(ctx, body)
    local w = wizard
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints()
    local dropdown = addon.recipeFinder.widgets.dropdown
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", 4, 0)
    left:SetPoint("BOTTOMLEFT", 4, 0)
    left:SetWidth(330)
    sectionTitle(left, L["DATE"], 0, -4)
    caption(left, L["Date"], 0, -28)
    w.day = input(left, 112, 10)
    w.day:SetPoint("TOPLEFT", 6, -44)
    w.day:HookScript("OnTextChanged", function(_, user) if user then w.refreshNav() end end)
    w.dayButton = CreateFrame("Button", nil, left)
    w.dayButton:SetSize(26, 26)
    w.dayButton:SetPoint("LEFT", w.day, "RIGHT", 6, 0)
    w.dayButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Note_06")
    w.dayButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    w.dayButton:SetScript("OnClick", function(self) openDatePicker(ctx, self) end)
    UI.tooltip(w.dayButton, L["Open calendar"])
    caption(left, L["Time"], 180, -28)
    w.hour = dropdown(left, 64, function()
        local list = {}
        for hour = 0, 23 do list[#list + 1] = { hour, ("%02d"):format(hour) } end
        return list
    end, function() return w.draft.hour end, function(value) w.draft.hour = value; w.refresh() end)
    w.hour:SetPoint("TOPLEFT", 184, -42)
    local colon = text(left, "GameFontNormalLarge")
    colon:SetPoint("LEFT", w.hour, "RIGHT", 3, 0)
    colon:SetText(":")
    w.minute = dropdown(left, 64, function()
        local list = {}
        -- Quarter hours; an existing other minute is kept until it is changed on purpose.
        for minute = 0, 45, 15 do list[#list + 1] = { minute, ("%02d"):format(minute) } end
        local current = w.draft.minute
        if current and current % 15 ~= 0 then
            table.insert(list, math.floor(current / 15) + 2, { current, ("%02d"):format(current) })
        end
        return list
    end, function() return w.draft.minute end, function(value) w.draft.minute = value; w.refresh() end)
    w.minute:SetPoint("LEFT", colon, "RIGHT", 3, 0)
    w.when = text(left, "GameFontHighlight", "LEFT", true)
    w.when:SetPoint("TOPLEFT", 2, -80)
    w.when:SetWidth(326)
    w.zoneHint = text(left, "GameFontDisableSmall", "LEFT", true)
    w.zoneHint:SetPoint("TOPLEFT", w.when, "BOTTOMLEFT", 0, -3)
    w.zoneHint:SetWidth(326)
    caption(left, L["Sign-up deadline"], 0, -130)
    w.deadline = dropdown(left, 150, function()
        return { { 0, L["Until the start"] }, { 1, L["1 hour before"] }, { 3, L["3 hours before"] }, { 24, L["1 day before"] } }
    end, function() return w.draft.deadlineHours or 0 end, function(value) w.draft.deadlineHours = value; w.refresh() end)
    w.deadline:SetPoint("TOPLEFT", 4, -144)
    w.repeatLabel = caption(left, L["Repeat"], 0, -182)
    w.repeatEvery = dropdown(left, 150, function()
        return { { 0, L["Once"] }, { 1, L["Daily"] }, { 7, L["Weekly"] }, { 14, L["Every two weeks"] } }
    end, function() return w.draft.repeatEvery or 0 end, function(value) w.draft.repeatEvery = value; w.refresh() end)
    w.repeatEvery:SetPoint("TOPLEFT", 4, -196)
    w.repeatCountLabel = caption(left, L["Number of dates"], 170, -182)
    w.repeatCount = dropdown(left, 150, function()
        local list = {}
        for count = 2, events.SERIES_MAX do list[#list + 1] = { count, L["%d dates"]:format(count) } end
        return list
    end, function() return w.draft.repeatCount or 4 end, function(value) w.draft.repeatCount = value; w.refresh() end)
    w.repeatCount:SetPoint("TOPLEFT", 174, -196)
    w.repeatHint = text(left, "GameFontDisableSmall", "LEFT", true)
    w.repeatHint:SetPoint("TOPLEFT", 2, -228)
    w.repeatHint:SetWidth(326)
    w.repeatHint:SetText(L["Each date gets its own participant list. At most four dates exist in advance; the next ones follow automatically."])

    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 18, 0)
    right:SetPoint("BOTTOMRIGHT", -4, 0)
    sectionTitle(right, L["PARTICIPANTS"], 0, -4)
    caption(right, L["Group model"], 0, -28)
    w.model = dropdown(right, 300, function()
        local list = {}
        for _, key in ipairs({ "dungeon", "raid", "free", "open", "custom" }) do list[#list + 1] = { key, L[UI.MODEL_LABELS[key]] } end
        return list
    end, function() return w.draft.model end, function(value)
        w.draft.model = value
        if value == "dungeon" then for i, role in ipairs(ROLE_KEYS) do w.slots[role]:SetText(({ 1, 1, 3 })[i]) end
        elseif value == "raid" then for i, role in ipairs(ROLE_KEYS) do w.slots[role]:SetText(({ 2, 5, 13 })[i]) end end
        w.refresh()
    end)
    w.model:SetPoint("TOPLEFT", 4, -42)
    -- Places per role: three cards
    w.roleCards = CreateFrame("Frame", nil, right)
    w.roleCards:SetPoint("TOPLEFT", 0, -76)
    w.roleCards:SetSize(390, 72)
    w.slots = {}
    for index, role in ipairs(ROLE_KEYS) do
        local card = CreateFrame("Frame", nil, w.roleCards, "BackdropTemplate")
        card:SetSize(122, 70)
        card:SetPoint("TOPLEFT", (index - 1) * 130, 0)
        card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        card:SetBackdropColor(.06, .045, .03, 1)
        card:SetBackdropBorderColor(.5, .36, .18)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(30, 30)
        icon:SetPoint("TOPLEFT", 8, -8)
        UI.roleIcon(icon, role)
        local label = text(card, "GameFontNormal")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetText(L[UI.ROLE_NAMES[role]])
        local box = input(card, 40, nil, 2)
        box:SetPoint("BOTTOM", 0, 8)
        box:SetJustifyH("CENTER")
        box:HookScript("OnTextChanged", function(_, user) if user then w.refreshNav() end end)
        w.slots[role] = box
    end
    w.sizeFrame = CreateFrame("Frame", nil, right)
    w.sizeFrame:SetPoint("TOPLEFT", 0, -76)
    w.sizeFrame:SetSize(390, 46)
    caption(w.sizeFrame, L["Number of participants (including you, 2–40)"], 0, 0)
    w.size = input(w.sizeFrame, 40, nil, 2)
    w.size:SetPoint("TOPLEFT", 6, -16)
    w.openHint = text(right, "GameFontHighlightSmall", "LEFT", true)
    w.openHint:SetPoint("TOPLEFT", 2, -80)
    w.openHint:SetWidth(380)
    w.openHint:SetText(L["Open event: no limit on participants and no fixed roles."])
    -- Own role, clearly separate from the places
    w.myRoleLabel = caption(right, L["My role"], 0, -154)
    w.myRole = {}
    for index, role in ipairs(ROLE_KEYS) do
        local control = ctx.button(right, L[UI.ROLE_NAMES[role]], 122, (index - 1) * 130, -168, function()
            w.draft.ownerRole = role
            w.refresh()
        end)
        w.myRole[role] = control
    end
    caption(right, L["Sign-up procedure"], 0, -200)
    w.approve = dropdown(right, 320, function()
        return { { false, L["Confirm sign-ups automatically"] }, { true, L["I confirm each sign-up myself"] } }
    end, function() return w.draft.approve and true or false end, function(value) w.draft.approve = value; w.refresh() end)
    w.approve:SetPoint("TOPLEFT", 4, -214)
    w.autofill = CreateFrame("CheckButton", nil, right, "UICheckButtonTemplate")
    w.autofill:SetSize(24, 24)
    w.autofill:SetPoint("TOPLEFT", 0, -244)
    w.autofill:SetScript("OnClick", function(self) w.draft.autofill = self:GetChecked() and true or false end)
    local autofillLabel = text(w.autofill, "GameFontHighlightSmall")
    autofillLabel:SetPoint("LEFT", w.autofill, "RIGHT", 2, 0)
    autofillLabel:SetText(L["Fill free places from the waitlist automatically"])
    w.partners = CreateFrame("CheckButton", nil, right, "UICheckButtonTemplate")
    w.partners:SetSize(24, 24)
    w.partners:SetPoint("TOPLEFT", 0, -266)
    w.partners:SetScript("OnClick", function(self) w.draft.partners = self:GetChecked() and true or false end)
    local partnersLabel = text(w.partners, "GameFontHighlightSmall")
    partnersLabel:SetPoint("LEFT", w.partners, "RIGHT", 2, 0)
    partnersLabel:SetText(L["Also show to partner guilds (they sign up by whisper)"])
    -- Co-organizers from the guild roster
    w.coorgTitle = caption(right, L["CO-ORGANIZERS"], 0, -296, "GameFontNormal")
    w.coorgRows = {}
    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, right)
        row:SetSize(380, 22)
        row:SetPoint("TOPLEFT", 0, -314 - (index - 1) * 23)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 2, 0)
        row.name = text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", 26, 0)
        row.remove = ctx.button(row, L["Remove"], 90, 0, 0, function()
            table.remove(w.draft.coorg, index)
            w.refresh()
        end)
        row.remove:ClearAllPoints()
        row.remove:SetPoint("RIGHT", 0, 0)
        row.remove:SetHeight(20)
        w.coorgRows[index] = row
    end
    w.coorgAdd = ctx.button(right, "+  " .. L["Add guild member"], 210, 0, 0, function() openMemberPicker(ctx) end)
    w.coorgAdd:ClearAllPoints()
    return page
end

-- Step 4: summary ----------------------------------------------------------------------------------------------------
-- A finished-looking preview: large scene of the dungeon (or activity) on top, the same art
-- darkened behind the information blocks, structured lines with icons, no empty fields.
local ROLE_INLINE = { T = "0:67:67:134", H = "67:134:0:67", D = "67:134:67:134" }
local function roleInline(role)
    return ("|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:18:18:0:0:256:256:%s|t"):format(ROLE_INLINE[role])
end
local function iconInline(path) return ("|T%s:18:18:0:0:64:64:5:59:5:59|t"):format(path) end

local function buildSummary(_, body)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints()
    local card = CreateFrame("Frame", nil, page, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 20, -2)
    card:SetPoint("BOTTOMRIGHT", -20, 2)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    card:SetBackdropColor(.05, .037, .026, 1)
    card:SetBackdropBorderColor(.72, .53, .27)
    page.card = card
    -- Same scene, very dark, behind the information blocks.
    page.backdrop = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    page.backdrop:SetPoint("TOPLEFT", 4, -4)
    page.backdrop:SetPoint("BOTTOMRIGHT", -4, 4)
    page.backdrop:SetAlpha(.16)
    page.backdrop:SetDesaturated(true)
    page.hero = card:CreateTexture(nil, "ARTWORK")
    page.hero:SetPoint("TOPLEFT", 4, -4)
    page.hero:SetPoint("TOPRIGHT", -4, -4)
    local shade = card:CreateTexture(nil, "ARTWORK", nil, 1)
    shade:SetAllPoints(page.hero)
    shade:SetColorTexture(1, 1, 1, 1)
    shade:SetGradient("VERTICAL", CreateColor(.05, .037, .026, 1), CreateColor(.05, .037, .026, 0))
    local edge = card:CreateTexture(nil, "ARTWORK", nil, 2)
    edge:SetPoint("TOPLEFT", page.hero, "BOTTOMLEFT")
    edge:SetPoint("TOPRIGHT", page.hero, "BOTTOMRIGHT")
    edge:SetHeight(2)
    edge:SetColorTexture(.62, .45, .22, .9)
    page.icon = card:CreateTexture(nil, "OVERLAY")
    page.icon:SetSize(44, 44)
    page.icon:SetPoint("BOTTOMLEFT", page.hero, "BOTTOMLEFT", 16, 12)
    page.icon:SetTexCoord(.07, .93, .07, .93)
    page.title = text(card, "GameFontNormalLarge")
    page.title:SetPoint("LEFT", page.icon, "RIGHT", 12, 9)
    page.title:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    page.kind = text(card, "GameFontHighlight")
    page.kind:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -4)
    page.kind:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    page.facts = text(card, "GameFontHighlight", "LEFT", true)
    page.facts:SetPoint("TOPLEFT", page.hero, "BOTTOMLEFT", 16, -14)
    page.facts:SetPoint("RIGHT", card, "RIGHT", -18, 0)
    page.facts:SetSpacing(6)
    page.groupTitle = text(card, "GameFontNormal")
    page.groupTitle:SetPoint("TOPLEFT", page.facts, "BOTTOMLEFT", 0, -14)
    page.groupTitle:SetText(L["GROUP COMPOSITION"])
    page.group = text(card, "GameFontHighlight", "LEFT", true)
    page.group:SetPoint("TOPLEFT", page.groupTitle, "BOTTOMLEFT", 0, -8)
    page.group:SetPoint("RIGHT", card, "RIGHT", -18, 0)
    page.group:SetSpacing(6)
    page.notes = text(card, "GameFontHighlight", "LEFT", true)
    page.notes:SetPoint("TOPLEFT", page.group, "BOTTOMLEFT", 0, -14)
    page.notes:SetPoint("RIGHT", card, "RIGHT", -18, 0)
    page.notes:SetSpacing(4)
    -- Banner scenes are 4:1: shown at full width with their own proportions, never stretched.
    card:SetScript("OnSizeChanged", function(_, width)
        local height = math.min(170, math.floor((width - 8) / 4))
        page.hero:SetHeight(height)
        if page.aspect then
            UI.fitArt(page.hero, page.aspect, width - 8, height)
            UI.fitArt(page.backdrop, page.aspect, width - 8, card:GetHeight() - 8)
        end
    end)
    return page
end

local function fillSummary(ctx, fields)
    local page = wizard.pages[4]
    local draft = wizard.draft
    local category = events.byCategory[draft.cat] or events.byCategory.dungeon
    local art, aspect = UI.banner({ cat = draft.cat, dungeon = fields.dungeon })
    page.hero:SetTexture(art)
    page.backdrop:SetTexture(art)
    page.aspect = aspect
    local width = page.card:GetWidth()
    local height = math.min(170, math.floor((width - 8) / 4))
    page.hero:SetHeight(height)
    UI.fitArt(page.hero, aspect, width - 8, height)
    UI.fitArt(page.backdrop, aspect, width - 8, page.card:GetHeight() - 8)
    page.icon:SetTexture(category.icon)
    page.title:SetText(events.clean(fields.title, 52))
    local kind = { L[category.label] }
    local dungeon = fields.dungeon and addon.getGroupDungeon(fields.dungeon)
    if dungeon then kind[#kind + 1] = dungeon[GetLocale() == "deDE" and 3 or 4] end
    if UI.levelText(fields) then kind[#kind + 1] = UI.levelText(fields) end
    page.kind:SetText(table.concat(kind, " · "))
    -- Date, time, organizer, goal
    local facts = {}
    if fields.starts then
        facts[#facts + 1] = iconInline("Interface\\Icons\\INV_Misc_Note_06") .. "  " .. UI.longDate(fields.starts)
            .. "      " .. iconInline("Interface\\Icons\\INV_Misc_PocketWatch_01") .. "  " .. UI.clock(fields.starts)
    end
    local member = ctx.member(ctx.player())
    local coords = CLASS_ICON_TCOORDS and member and CLASS_ICON_TCOORDS[member.class]
    local classIcon = coords and ("|TInterface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes:18:18:0:0:256:256:%d:%d:%d:%d|t  ")
        :format(coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256) or ""
    local c = UI.classColor(ctx, ctx.player())
    facts[#facts + 1] = classIcon .. ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, ctx.displayName(ctx.player()))
        .. "  |cffbfae8c(" .. L["Organizer"] .. ")|r"
    local target = fields.targets and fields.targets[1]
    if target then facts[#facts + 1] = iconInline(UI.targetIcon(ctx, target)) .. "  " .. UI.targetName(ctx, target) end
    if draft.repeatEvery > 0 and not wizard.opts.edit then
        facts[#facts + 1] = L["%s, %d dates"]:format(({ [1] = L["Daily"], [7] = L["Weekly"], [14] = L["Every two weeks"] })[draft.repeatEvery],
            draft.repeatCount)
    end
    page.facts:SetText(table.concat(facts, "\n"))
    -- Group
    local group = {}
    if fields.slots then
        group[#group + 1] = ("%s %d %s      %s %d %s      %s %d %s"):format(roleInline("T"), fields.slots.T, L["Tank"],
            roleInline("H"), fields.slots.H, L["Healer"], roleInline("D"), fields.slots.D, L["DPS"])
        group[#group + 1] = L["Your role: %s"]:format(L[UI.ROLE_NAMES[fields.ownerRole] or "DPS"])
    elseif fields.size then
        group[#group + 1] = L["Up to %d players"]:format(fields.size)
    else
        group[#group + 1] = L["Open event: no limit on participants and no fixed roles."]
    end
    group[#group + 1] = fields.approve and L["You confirm each sign-up yourself."] or L["Sign-ups are confirmed automatically."]
    page.group:SetText(table.concat(group, "\n"))
    local notes = {}
    if fields.desc and fields.desc ~= "" then notes[#notes + 1] = "|cffffd100" .. L["Description"] .. "|r\n" .. fields.desc end
    if fields.req and fields.req ~= "" then notes[#notes + 1] = "|cffffd100" .. L["Requirements"] .. "|r\n" .. fields.req end
    page.notes:SetText(table.concat(notes, "\n\n"))
end

-- Wizard frame -----------------------------------------------------------------------------------------------------
local STEP_LABELS = { "1  Activity", "2  Details", "3  Date & participants", "4  Summary" }

local function build(ctx)
    wizard = CreateFrame("Frame", "ForeverGuildEventWizard", UIParent, "BackdropTemplate")
    local w = wizard
    -- Dropdowns read their value already while they are built (SetupMenu -> GenerateMenu),
    -- so an empty draft must exist before the pages are created.
    w.opts, w.visited = {}, {}
    w.draft = { coorg = {}, targets = {}, repeatEvery = 0, repeatCount = 4, deadlineHours = 0, hour = 20, minute = 0 }
    w:SetSize(820, 640)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    opaque(w)
    tinsert(UISpecialFrames, "ForeverGuildEventWizard")
    local icon = w:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", 20, -18)
    icon:SetTexture(ctx.icon)
    w.heading = text(w, "GameFontNormalLarge")
    w.heading:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    -- Step navigation
    w.stepButtons = {}
    for index, label in ipairs(STEP_LABELS) do
        local step = CreateFrame("Button", nil, w, "BackdropTemplate")
        step:SetSize(186, 30)
        step:SetPoint("TOPLEFT", 22 + (index - 1) * 194, -50)
        step:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        step.glow = step:CreateTexture(nil, "BORDER")
        step.glow:SetPoint("TOPLEFT", 3, -3)
        step.glow:SetPoint("BOTTOMRIGHT", -3, 3)
        step.glow:SetColorTexture(1, .78, .3, .16)
        step.check = step:CreateTexture(nil, "OVERLAY")
        step.check:SetSize(18, 18)
        step.check:SetPoint("LEFT", 8, 0)
        step.check:SetTexture(CHECK)
        step.check:SetVertexColor(.45, .9, .45)
        step.alert = text(step, "GameFontNormal")
        step.alert:SetPoint("LEFT", 10, 0)
        step.alert:SetText("!")
        UI.color(step.alert, RED)
        step.label = text(step, "GameFontNormal", "CENTER")
        step.label:SetPoint("LEFT", 26, 0)
        step.label:SetPoint("RIGHT", -8, 0)
        step.label:SetText(L[label])
        step:SetScript("OnClick", function() w.go(index) end)
        step:SetScript("OnEnter", function(self)
            if self.reason then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(L[label])
                GameTooltip:AddLine(self.reason, 1, .6, .5, true)
                GameTooltip:Show()
            end
        end)
        step:SetScript("OnLeave", function() GameTooltip:Hide() end)
        w.stepButtons[index] = step
    end
    local body = CreateFrame("Frame", nil, w, "BackdropTemplate")
    body:SetPoint("TOPLEFT", 16, -88)
    body:SetPoint("BOTTOMRIGHT", -16, 54)
    body:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    body:SetBackdropColor(.045, .033, .024, 1)
    body:SetBackdropBorderColor(.5, .35, .17)
    local inner = CreateFrame("Frame", nil, body)
    inner:SetPoint("TOPLEFT", 10, -10)
    inner:SetPoint("BOTTOMRIGHT", -10, 10)
    w.pages = { buildTiles(ctx, inner), buildDetails(ctx, inner), buildSchedule(ctx, inner), buildSummary(ctx, inner) }
    w.picker = buildDungeonPicker(ctx, inner)
    w.error = text(w, "GameFontHighlight", "LEFT", true)
    w.error:SetPoint("BOTTOMLEFT", 140, 22)
    w.error:SetPoint("RIGHT", -330, 0)
    UI.color(w.error, RED)
    w.cancel = ctx.button(w, L["Cancel"], 110, 0, 0, function() w:Hide() end)
    w.cancel:ClearAllPoints()
    w.cancel:SetPoint("BOTTOMLEFT", 20, 18)
    w.nextButton = ctx.button(w, "", 190, 0, 0, function()
        if w.step < 4 then w.go(w.step + 1) else w.publish() end
    end)
    w.nextButton:ClearAllPoints()
    w.nextButton:SetPoint("BOTTOMRIGHT", -20, 18)
    w.back = ctx.button(w, L["Back"], 110, 0, 0, function() w.go(w.step - 1) end)
    w.back:ClearAllPoints()
    w.back:SetPoint("RIGHT", w.nextButton, "LEFT", -8, 0)
    w:SetScript("OnHide", function()
        UI.closeMenu()
        if w.datePicker then w.datePicker:Hide() end
        if w.memberPicker then w.memberPicker:Hide() end
    end)

    w.loadInputs = function()
        local draft = w.draft
        w.title:SetText(draft.title or "")
        w.desc:SetText(draft.desc or "")
        w.req:SetText(draft.req or "")
        w.zone:SetText(draft.cat == "level" and draft.place or "")
        w.minLevel:SetText(draft.minLevel and tostring(draft.minLevel) or "")
        w.maxLevel:SetText(draft.maxLevel and tostring(draft.maxLevel) or "")
        w.day:SetText(draft.starts and date("%d.%m.%Y", draft.starts) or "")
        local slots = draft.slots or { T = 1, H = 1, D = 3 }
        for _, role in ipairs(ROLE_KEYS) do w.slots[role]:SetText(tostring(slots[role] or 0)) end
        w.size:SetText(tostring(draft.size or 5))
        local target = draft.target
        w.goalBox:SetText(target and target.k ~= "f" and UI.targetName(ctx, target) or "")
        w.factionBox:SetText(target and target.k == "f" and target.text or "")
        w.autoTitle = nil
    end

    w.storeInputs = function()
        local draft = w.draft
        draft.title, draft.desc, draft.req = w.title:GetText(), w.desc:GetText(), w.req:GetText()
        draft.minLevel, draft.maxLevel = tonumber(w.minLevel:GetText()), tonumber(w.maxLevel:GetText())
        if draft.cat == "level" then draft.place = w.zone:GetText() end
        local slots = { T = tonumber(w.slots.T:GetText()) or 0, H = tonumber(w.slots.H:GetText()) or 0, D = tonumber(w.slots.D:GetText()) or 0 }
        draft.slots, draft.size = slots, tonumber(w.size:GetText())
        local starts = compose(w.day:GetText(), draft.hour, draft.minute)
        if starts then draft.starts = starts end
    end

    -- Step states: current, completed (green check), not reachable (grey), with an error (!).
    w.refreshNav = function()
        local reachable = true
        for index, button in ipairs(w.stepButtons) do
            local ok, reason = true, nil
            if index < 4 then ok, reason = validateStep(ctx, index) end
            local current = index == w.step
            local done = not current and index < 4 and ok and (index < w.step or w.visited[index])
            local failed = not current and w.visited[index] and not ok and index < w.step
            button:SetEnabled(reachable or current)
            button.reason = failed and L[REASONS[reason] or "Please check your input."] or nil
            button.glow:SetShown(current)
            button.check:SetShown(done and not failed)
            button.alert:SetShown(failed)
            if current then
                button:SetBackdropColor(.2, .14, .06, 1)
                button:SetBackdropBorderColor(1, .8, .25)
                button.label:SetTextColor(1, .93, .7)
            elseif reachable then
                button:SetBackdropColor(.08, .06, .04, 1)
                button:SetBackdropBorderColor(failed and .85 or .5, failed and .35 or .37, failed and .25 or .18)
                button.label:SetTextColor(.85, .76, .6)
            else
                button:SetBackdropColor(.05, .04, .03, 1)
                button:SetBackdropBorderColor(.28, .25, .22)
                button.label:SetTextColor(.45, .42, .38)
            end
            if index < 4 and not ok then reachable = false end
        end
    end

    w.refresh = function()
        local draft, step = w.draft, w.step
        local picking = step == 2 and w.picking
        for index, page in ipairs(w.pages) do page:SetShown(index == step and not picking) end
        w.picker:SetShown(picking or false)
        if picking then
            w.picker.cancel:SetShown(draft.dungeon ~= nil)
            w.picker.layout()
        end
        -- Step 1 tiles
        for _, tile in ipairs(w.pages[1].tiles) do
            if tile.category.soon then tile.setState("soon")
            elseif draft.cat == tile.key then tile.setState("selected")
            elseif draft.cat then tile.setState("dimmed")
            else tile.setState("normal") end
        end
        -- Step 2
        w.pages[2].layout()
        local dungeon = draft.dungeon and addon.getGroupDungeon(draft.dungeon)
        local de = GetLocale() == "deDE"
        if dungeon then
            w.dungeonCard.art:SetTexture(addon.dungeonArt(dungeon))
            w.dungeonName:SetText(dungeon[de and 1 or 2])
            if dungeon.combined or dungeon.retired then
                -- Older event with a combined dungeon: the wing is never guessed.
                w.dungeonInfo:SetText(dungeon.combined and L["Please choose the dungeon wing."]
                    or L["This dungeon is no longer in the group finder. Please choose a dungeon."])
                UI.color(w.dungeonInfo, GOLD)
            else
                w.dungeonInfo:SetText(L["Level %d–%d"]:format(dungeon.min, dungeon.max) .. "  ·  " .. dungeon[de and 3 or 4])
                UI.color(w.dungeonInfo, LIGHT)
            end
            w.dungeonHint:SetText(L["Change dungeon"] .. "  |TInterface\\ChatFrame\\ChatFrameExpandArrow:12|t")
        else
            w.dungeonCard.art:SetTexture(ART .. "DungeonHall")
            w.dungeonName:SetText(L["No dungeon chosen yet"])
            w.dungeonInfo:SetText(L["Pick the dungeon from the list."])
            w.dungeonHint:SetText(L["Choose dungeon"] .. "  |TInterface\\ChatFrame\\ChatFrameExpandArrow:12|t")
        end
        w.dungeonCard.setState("normal")
        w.dungeonCard:SetScript("OnSizeChanged", function(self, width, height) addon.fitDungeonArtwork(self.art, width - 8, height - 8) end)
        addon.fitDungeonArtwork(w.dungeonCard.art, w.dungeonCard:GetWidth() - 8, 62)
        local goal = GOALS[draft.cat]
        if goal then
            w.goalLabel:SetText(L[goal.label])
            w.goalSearch:SetShown(goal.items or false)
            w.goalQuests:SetShown(goal.quests or false)
            w.goalBox.hint = L[goal.hint]
            w.refreshGoal()
        end
        local target = draft.target
        local faction = draft.faction
        if draft.cat == "rep" then
            if faction and faction.max and faction.min and faction.max > faction.min then
                w.repCurrent:SetText(L["Your current reputation: %s"]:format(UI.standingLabel(faction.standing)))
                w.repBar.bar:SetValue((faction.value - faction.min) / (faction.max - faction.min))
                w.repBar.label:SetText(("%d / %d"):format(faction.value - faction.min, faction.max - faction.min))
                w.repBar:Show()
            else
                w.repCurrent:SetText(target and target.k == "f" and L["No reputation data of your character for this faction."]
                    or L["Pick a faction your character knows or type its name."])
                w.repBar:Hide()
            end
            w.repGoal.Sync()
        end
        -- Step 3
        local starts = compose(w.day:GetText(), draft.hour, draft.minute)
        w.when:SetText(starts and (UI.longDate(starts) .. ", " .. UI.clock(starts)) or L["Choose a valid date (DD.MM.YYYY)."])
        UI.color(w.when, starts and starts > ctx.clock() and LIGHT or RED)
        w.zoneHint:SetText(L["Your local time (%s). Every guild member sees the date in their own local time."]:format(UI.zone(ctx.clock())))
        for _, control in ipairs({ w.hour, w.minute, w.deadline, w.repeatEvery, w.repeatCount, w.model, w.approve }) do control.Sync() end
        local editing = w.opts.edit ~= nil
        w.repeatEvery:SetShown(not editing)
        w.repeatLabel:SetShown(not editing)
        local repeating = not editing and draft.repeatEvery > 0
        w.repeatCount:SetShown(repeating)
        w.repeatCountLabel:SetShown(repeating)
        w.repeatHint:SetShown(repeating)
        local slotted = draft.model == "dungeon" or draft.model == "raid" or draft.model == "custom"
        w.roleCards:SetShown(slotted)
        w.sizeFrame:SetShown(draft.model == "free")
        w.openHint:SetShown(draft.model == "open")
        w.myRoleLabel:SetShown(slotted)
        for role, control in pairs(w.myRole) do
            control:SetShown(slotted)
            local chosen = draft.ownerRole == role
            control:SetText((chosen and "|T" .. CHECK .. ":16|t " or "") .. L[UI.ROLE_NAMES[role]])
            if chosen then control:LockHighlight() else control:UnlockHighlight() end
        end
        w.autofill:SetChecked(draft.autofill and true or false)
        w.autofill:SetShown(draft.model ~= "open")
        w.partners:SetShown(ctx.partnerActive())
        w.partners:SetChecked(draft.partners and true or false)
        local coorgShown = not editing or w.opts.edit.owner == ctx.player()
        w.coorgTitle:SetShown(coorgShown)
        for index, row in ipairs(w.coorgRows) do
            local name = draft.coorg[index]
            row:SetShown(coorgShown and name ~= nil)
            if name then
                local member = ctx.member(name)
                UI.classIcon(row.icon, member and member.class)
                row.name:SetText(ctx.displayName(name))
                UI.color(row.name, UI.classColor(ctx, name))
            end
        end
        w.coorgAdd:ClearAllPoints()
        w.coorgAdd:SetPoint("TOPLEFT", w.coorgTitle, "BOTTOMLEFT", 0, -4 - #draft.coorg * 23)
        w.coorgAdd:SetShown(coorgShown and #draft.coorg < 3)
        -- Step 4
        if step == 4 then fillSummary(ctx, collect(ctx)) end
        w.back:SetShown(step > 1)
        w.nextButton:SetText(step < 4 and L["Next"] or (w.opts.edit and L["Save changes"] or L["Publish event"]))
        w.nextButton:SetEnabled(step < 4 or ctx.ready())
        w.refreshNav()
    end

    w.go = function(target)
        if target < 1 or target > 4 then return end
        if w.step >= 2 then w.storeInputs() end
        w.visited[w.step] = true
        for check = 1, target - 1 do
            local ok, reason = validateStep(ctx, check)
            if not ok then
                w.step = math.min(w.step, check)
                w.error:SetText(L[REASONS[reason] or "Please check your input."])
                if reason == "dungeon" then w.picking = true end
                w.refresh()
                return
            end
        end
        w.error:SetText("")
        w.step = target
        w.picking = target == 2 and w.draft.cat == "dungeon" and not w.draft.dungeon
        w.refresh()
    end

    w.publish = function()
        w.storeInputs()
        local ok, reason = validateStep(ctx, 3)
        if not ok then w.error:SetText(L[REASONS[reason] or "Please check your input."]); return end
        if not ctx.ready() then w.error:SetText(L["Not connected to the guild channel yet."]); return end
        local fields = collect(ctx)
        local now = ctx.clock()
        local guild = ctx.guild()
        if w.opts.edit then
            local ev = w.opts.edit
            local function apply(list)
                for _, other in ipairs(list) do
                    local copy = events.copyFields(fields)
                    if other ~= ev then
                        copy.starts = other.starts + (fields.starts - ev.starts)
                        if copy.deadline then copy.deadline = copy.starts - (fields.starts - fields.deadline) end
                    end
                    local changes, why = events.edit(other, copy, now)
                    if changes then events.flush(other, ctx.send)
                    elseif other == ev then w.error:SetText(L[REASONS[why] or "Please check your input."]); return false end
                end
                return true
            end
            if ev.series and ev.owner == ctx.player() then
                UI.confirm(ctx, L["Change series?"], L["Apply the changes only to this date or to this and all following dates?"], function(choice)
                    local list = choice == 2 and events.seriesMembers(guild, ev, true) or { ev }
                    if apply(list) then
                        if choice == 2 then events.updateSeriesTemplate(guild, ev) end
                        w:Hide()
                        UI.select(ev.id)
                    end
                end, L["Only this date"], L["All following"])
                return
            end
            if apply({ ev }) then w:Hide(); UI.select(ev.id) end
            return
        end
        local every = w.draft.repeatEvery > 0 and w.draft.repeatEvery or nil
        local ev, why = events.create(guild, ctx.player(), fields, now, every, every and w.draft.repeatCount)
        if not ev then w.error:SetText(L[REASONS[why] or "Please check your input."]); return end
        if w.opts.migrate then
            for name, decision in pairs(w.opts.migrate.decisions or {}) do events.decide(ev, name, decision.d, decision.role, now) end
            ctx.legacyClose(w.opts.migrate, true)
        end
        events.flush(ev, ctx.send)
        w:Hide()
        UI.select(events.id(ev.owner, ev.token))
    end
end

function UI.openWizard(ctx, opts)
    if ctx.inCombat() then return end
    UI.closeMenu()
    if not wizard then build(ctx) end
    local w = wizard
    w.opts = opts or {}
    w.draft = newDraft(ctx, w.opts)
    w.visited, w.picking = {}, false
    local heading = w.opts.edit and L["ForeverGuild · Edit event"] or (w.opts.copy and L["ForeverGuild · Copy event"])
        or L["ForeverGuild · Create group or event"]
    w.heading:SetText(heading)
    w.loadInputs()
    w.error:SetText("")
    w.step = 1
    if w.opts.edit or w.opts.copy or w.opts.migrate then
        w.visited[1], w.visited[2] = true, true
        w.step = w.opts.step or (w.opts.copy and 3 or 2)
        if not w.draft.cat then w.step = 1 end
    end
    if w.datePicker then w.datePicker:Hide() end
    w:Show()
    w:Raise()
    w.refresh()
end

-- Sign-up dialog ------------------------------------------------------------------------------------------------------
local signup
function UI.openSignup(ctx, ev, preset, entry)
    if ctx.inCombat() or not ev or ev.kind ~= "event" then
        if ev and ev.kind == "legacy" then ctx.legacyReply(ev) end
        return
    end
    if not signup then
        signup = CreateFrame("Frame", "ForeverGuildEventSignup", UIParent, "BackdropTemplate")
        local s = signup
        s:SetSize(470, 390)
        s:SetPoint("CENTER", 0, 40)
        s:SetFrameStrata("DIALOG")
        s:SetToplevel(true)
        s:EnableMouse(true)
        s:SetClampedToScreen(true)
        opaque(s)
        tinsert(UISpecialFrames, "ForeverGuildEventSignup")
        s.title = text(s, "GameFontNormalLarge")
        s.title:SetPoint("TOPLEFT", 20, -20)
        s.title:SetPoint("RIGHT", -40, 0)
        s.info = text(s, "GameFontHighlightSmall", "LEFT", true)
        s.info:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -4)
        s.info:SetPoint("RIGHT", -20, 0)
        local close = CreateFrame("Button", nil, s, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
        s.roleTitle = text(s, "GameFontNormal")
        s.roleTitle:SetPoint("TOPLEFT", 20, -66)
        s.roleTitle:SetText(L["Desired role"])
        s.roles, s.alts = {}, {}
        for index, role in ipairs(ROLE_KEYS) do
            local control = ctx.roleControl(s, ROLE_INDEX[role], 26 + (index - 1) * 140, -84)
            control:SetScript("OnClick", function() s.role = role; s.update() end)
            s.roles[role] = control
            local alt = CreateFrame("CheckButton", nil, s, "UICheckButtonTemplate")
            alt:SetSize(22, 22)
            alt:SetPoint("TOPLEFT", control, "BOTTOMLEFT", -4, -2)
            local label = text(alt, "GameFontHighlightSmall")
            label:SetPoint("LEFT", alt, "RIGHT", 1, 0)
            label:SetText(L["also possible"])
            s.alts[role] = alt
        end
        s.noRoles = text(s, "GameFontHighlight", "LEFT", true)
        s.noRoles:SetPoint("TOPLEFT", 20, -90)
        s.noRoles:SetPoint("RIGHT", -20, 0)
        s.noRoles:SetText(L["This activity has no fixed roles – just sign up."])
        s.firm = CreateFrame("CheckButton", nil, s, "UIRadioButtonTemplate")
        s.firm:SetPoint("TOPLEFT", 20, -184)
        local firmLabel = text(s.firm, "GameFontHighlight")
        firmLabel:SetPoint("LEFT", s.firm, "RIGHT", 4, 0)
        firmLabel:SetText(L["I'll be there"])
        s.tent = CreateFrame("CheckButton", nil, s, "UIRadioButtonTemplate")
        s.tent:SetPoint("TOPLEFT", 200, -184)
        local tentLabel = text(s.tent, "GameFontHighlight")
        tentLabel:SetPoint("LEFT", s.tent, "RIGHT", 4, 0)
        tentLabel:SetText(L["Tentative – not sure yet"])
        s.firm:SetScript("OnClick", function() s.state = "in"; s.update() end)
        s.tent:SetScript("OnClick", function() s.state = "tent"; s.update() end)
        s.note = input(s, 410, 60)
        caption(s, L["Note for the organizer (optional)"], 20, -212)
        s.note:SetPoint("TOPLEFT", 26, -228)
        s.loot = text(s, "GameFontHighlightSmall", "LEFT", true)
        s.loot:SetPoint("TOPLEFT", 20, -262)
        s.loot:SetPoint("RIGHT", -20, 0)
        UI.color(s.loot, { 1, .86, .55 })
        s.hint = text(s, "GameFontDisableSmall", "LEFT", true)
        s.hint:SetPoint("BOTTOMLEFT", 20, 50)
        s.hint:SetPoint("RIGHT", -20, 0)
        s.hint:SetText(L["Your sign-up counts as confirmed once the organizer’s client has confirmed it. ForeverGuild never invites you to a group automatically."])
        local cancel = ctx.button(s, L["Cancel"], 110, 0, 0, function() s:Hide() end)
        cancel:ClearAllPoints()
        cancel:SetPoint("BOTTOMLEFT", 18, 16)
        s.ok = ctx.button(s, L["Sign up"], 150, 0, 0, function()
            local current = s.ev
            local result = events.signUp(current, ctx.player(), { state = s.state, role = current.slots and s.role or nil,
                alt = s.altString(), note = s.note:GetText(), lootAck = current.lootRev }, ctx.clock())
            if result then
                UI.sendSignup(ctx, current, result)
                s:Hide()
            else
                s.hint:SetText(L["Sign-up is not possible right now (closed, past or no place for this role)."])
            end
        end)
        s.ok:ClearAllPoints()
        s.ok:SetPoint("BOTTOMRIGHT", -18, 16)
        s.altString = function()
            local result = ""
            for _, role in ipairs(ROLE_KEYS) do
                if s.alts[role]:IsShown() and s.alts[role]:GetChecked() and role ~= s.role then result = result .. role end
            end
            return result
        end
        s.update = function()
            local current = s.ev
            for _, role in ipairs(ROLE_KEYS) do
                local available = current.slots and current.slots[role] > 0
                s.roles[role]:SetShown(available or false)
                s.alts[role]:SetShown((available and role ~= s.role) or false)
                s.roles[role]:Select(s.role == role)
            end
            s.roleTitle:SetShown(current.slots ~= nil)
            s.noRoles:SetShown(current.slots == nil)
            s.firm:SetChecked(s.state == "in")
            s.tent:SetChecked(s.state == "tent")
        end
    end
    local s = signup
    s.ev = ev
    s.title:SetText(UI.titleOf(ev))
    local info = UI.categoryLabel(ev) .. " · " .. UI.when(ev.starts, ctx.clock())
    if ev.req then info = info .. "\n" .. L["Requirements: %s"]:format(ev.req) end
    s.info:SetText(info)
    local mine = ev.signups[ctx.player()]
    local preferred = UI.setting("prefRoles")
    local myRoles = ctx.myRoles()
    s.role = (entry and entry.role) or (mine and mine.state ~= "out" and mine.role)
        or (preferred ~= "" and preferred) or myRoles:sub(1, 1)
    if ev.slots and (s.role == "" or not s.role or (ev.slots[s.role] or 0) == 0) then
        s.role = nil
        for _, role in ipairs(ROLE_KEYS) do
            if not s.role and ev.slots[role] > 0 and (myRoles == "" or myRoles:find(role, 1, true)) then s.role = role end
        end
        for _, role in ipairs(ROLE_KEYS) do if not s.role and ev.slots[role] > 0 then s.role = role end end
    end
    s.state = preset or (mine and mine.state ~= "out" and mine.state) or "in"
    for _, role in ipairs(ROLE_KEYS) do
        local alt = (mine and mine.alt or "")
        if not mine and myRoles:find(role, 1, true) and role ~= s.role then alt = alt .. role end
        s.alts[role]:SetChecked(alt:find(role, 1, true) ~= nil)
    end
    s.note:SetText(mine and mine.state ~= "out" and mine.note or "")
    if ev.loot then
        s.loot:SetText(L["Loot agreement: %s"]:format(L[UI.LOOT_LABELS[ev.loot.rule]] .. (ev.loot.text and (" – " .. ev.loot.text) or ""))
            .. "\n" .. L["By signing up you accept this agreement."])
    else
        s.loot:SetText("")
    end
    s.ok:SetText(mine and mine.state ~= "out" and L["Save sign-up"] or L["Sign up"])
    s.hint:SetText(L["Your sign-up counts as confirmed once the organizer’s client has confirmed it. ForeverGuild never invites you to a group automatically."])
    s.update()
    s:Show()
    s:Raise()
end
