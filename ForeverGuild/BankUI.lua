local _, addon = ...
-- Guild bank page: header with the vault icon, last capture and the gold of the guild bank,
-- the existing sync actions, a compact filter bar and the stock in category blocks that are
-- arranged side by side like Baganator. Display only; the vault data is not changed.
local L = addon.L
local data = addon.bankData
local UI = {}
addon.bankUI = UI

local ART = "Interface\\AddOns\\ForeverGuild\\Art\\"
local GAP, PADDING = 4, 10

local view

local function text(parent, font, justify, wrap)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(wrap and true or false)
    return label
end

local function frameBox(parent)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(.075, .055, .038, .94)
    box:SetBackdropBorderColor(.62, .45, .22)
    return box
end

local function tooltip(control, title, detail)
    control:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title)
        if detail then GameTooltip:AddLine(detail, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Gold of the guild bank with the original coin icons.
function UI.money(copper)
    copper = math.floor(copper + .5)
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local icon = "|TInterface\\MoneyFrame\\UI-%sIcon:16:16:2:0|t"
    local parts = {}
    if gold > 0 then parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold) .. icon:format("Gold") end
    if gold > 0 or silver > 0 then parts[#parts + 1] = silver .. icon:format("Silver") end
    parts[#parts + 1] = rest .. icon:format("Copper")
    return table.concat(parts, "  ")
end

local function qualityColor(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return c and { c.r, c.g, c.b }
end

-- Item slot: classic inventory slot, quality border, stack count, original tooltip.
local function slotTooltip(self)
    local entry = self.entry
    if not entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local itemString = entry.link and entry.link:match("|H(item:[^|]+)|h")
    GameTooltip:SetHyperlink(itemString or ("item:" .. entry.id))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Guild bank: %d"]:format(entry.quantity), 1, .82, .24)
    local names = {}
    for _, tab in ipairs(data.tabs(view.ctx.guild())) do names[tab.index] = tab.name end
    local tabs = {}
    for index, count in pairs(entry.tabs or {}) do tabs[#tabs + 1] = { index = index, count = count } end
    table.sort(tabs, function(a, b) return a.index < b.index end)
    for _, tab in ipairs(tabs) do
        GameTooltip:AddDoubleLine("  " .. (names[tab.index] or L["Bank tab %d"]:format(tab.index)), tostring(tab.count), .85, .77, .63, .85, .77, .63)
    end
    if entry.at then GameTooltip:AddLine(L["Last updated: %s"]:format(date("%d.%m.%Y, %H:%M", entry.at)), .62, .57, .5) end
    GameTooltip:Show()
end

local function newSlot(parent)
    local slot = CreateFrame("Button", nil, parent, "BackdropTemplate")
    slot:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    slot:SetBackdropColor(.09, .065, .045, 1)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 3, -3)
    slot.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    slot.icon:SetTexCoord(.07, .93, .07, .93)
    slot.count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    slot.count:SetPoint("BOTTOMRIGHT", -3, 3)
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot:SetScript("OnEnter", slotTooltip)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Shift-click puts the item link into the chat, as everywhere in WoW.
    slot:SetScript("OnClick", function(self)
        if self.entry and self.entry.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.entry.link)
        end
    end)
    return slot
end

local function fillSlot(slot, entry, size)
    slot:SetSize(size, size)
    slot.entry = entry
    local info = data.info(entry.id, entry.link)
    slot.icon:SetTexture(entry.icon or info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    slot.count:SetText(entry.quantity > 1 and (entry.quantity >= 10000 and (math.floor(entry.quantity / 1000) .. "k") or entry.quantity) or "")
    local c = data.setting("qualityBorder") and info.quality and info.quality >= 2 and qualityColor(info.quality)
    if c then slot:SetBackdropBorderColor(c[1], c[2], c[3]) else slot:SetBackdropBorderColor(.55, .4, .2) end
end

-- Page --------------------------------------------------------------------------------------------------
function UI.build(page, ctx)
    view = CreateFrame("Frame", nil, page)
    view.ctx = ctx
    view:SetPoint("TOPLEFT", 12, -10)
    view:SetPoint("BOTTOMRIGHT", -12, 10)
    view.filters = {}
    view:SetScript("OnShow", function() UI.refresh() end)

    -- Header: vault icon, name, last capture; gold and sync actions on the right.
    local header = frameBox(view)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(74)
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(52, 52)
    icon:SetPoint("LEFT", 12, 0)
    icon:SetTexture(ART .. "GuildBank")
    view.title = text(header, "GameFontNormalLarge")
    view.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -6)
    view.status = text(header, "GameFontHighlight")
    view.status:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -6)
    view.gold = text(header, "GameFontHighlightLarge", "RIGHT")
    view.gold:SetPoint("TOPRIGHT", -14, -12)
    view.goldCaption = text(header, "GameFontNormalSmall", "RIGHT")
    view.goldCaption:SetPoint("RIGHT", view.gold, "LEFT", -10, 0)
    view.goldCaption:SetText(L["Gold balance:"])
    view.gear = CreateFrame("Button", nil, header)
    view.gear:SetSize(22, 22)
    view.gear:SetPoint("BOTTOMRIGHT", -12, 10)
    view.gear:SetNormalTexture(ART .. "SettingsGear")
    view.gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    view.gear:SetScript("OnClick", function() ctx.openSettings() end)
    tooltip(view.gear, L["Guild bank settings"])
    view.request = ctx.button(header, L["Request guild snapshot"], 170, 0, 0, function() ctx.requestSnapshot(); UI.refresh() end)
    view.request:ClearAllPoints()
    view.request:SetPoint("RIGHT", view.gear, "LEFT", -8, 0)
    tooltip(view.request, L["Request guild snapshot"], L["Guild members who share their bank data send their newest capture."])
    view.scan = ctx.button(header, L["Scan open vault"], 150, 0, 0, function() if ctx.scanVault() then UI.refresh() end end)
    view.scan:ClearAllPoints()
    view.scan:SetPoint("RIGHT", view.request, "LEFT", -6, 0)
    tooltip(view.scan, L["Scan open vault"], L["Only possible while the guild vault is open. Opening the vault also syncs automatically."])

    -- Filter bar: search, category, quality, combine identical items.
    local bar = frameBox(view)
    bar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    bar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -6)
    bar:SetHeight(40)
    local search = CreateFrame("EditBox", nil, bar, "SearchBoxTemplate")
    search:SetSize(220, 22)
    search:SetPoint("LEFT", 14, 0)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(self)
        view.filters.text = self:GetText()
        if view.timer then view.timer:Cancel() end
        view.timer = C_Timer.NewTimer(.2, function() UI.refresh() end)
    end)
    if type(search.Instructions) == "table" then search.Instructions:SetText(L["Search item ..."]) end
    local dropdown = addon.recipeFinder.widgets.dropdown
    view.category = dropdown(bar, 190, function()
        local list = { { "all", L["All categories"] } }
        for _, category in ipairs(data.categories) do list[#list + 1] = { category.id, L[category.label] } end
        return list
    end, function() return view.filters.category or "all" end, function(value)
        view.filters.category = value ~= "all" and value or nil
        UI.refresh()
    end)
    view.category:SetPoint("LEFT", search, "RIGHT", 12, 0)
    view.quality = dropdown(bar, 150, function()
        local list = { { -1, L["All qualities"] } }
        for quality = 0, 5 do list[#list + 1] = { quality, _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality) } end
        return list
    end, function() return view.filters.quality or -1 end, function(value)
        view.filters.quality = value >= 0 and value or nil
        UI.refresh()
    end)
    view.quality:SetPoint("LEFT", view.category, "RIGHT", 8, 0)
    view.merge = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
    view.merge:SetSize(24, 24)
    view.merge:SetPoint("LEFT", view.quality, "RIGHT", 14, 0)
    view.merge:SetScript("OnClick", function(self) data.set("merge", self:GetChecked() and true or false); UI.refresh() end)
    local mergeLabel = text(view.merge, "GameFontHighlightSmall")
    mergeLabel:SetPoint("LEFT", view.merge, "RIGHT", 2, 0)
    mergeLabel:SetText(L["Combine identical items"])
    tooltip(view.merge, L["Combine identical items"], L["Shows stacks of the same item as one entry. Items with another enchantment or random bonus stay separate; the tooltip lists the bank tabs."])

    -- Stock: scrollable area with category blocks.
    local box = frameBox(view)
    box:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    box:SetPoint("BOTTOMRIGHT", 0, 22)
    box:SetBackdropColor(.05, .037, .026, .82)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 1)
    scroll:SetScrollChild(content)
    -- Only a changed width rearranges the blocks (no permanent OnUpdate).
    scroll:HookScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
        if view:IsVisible() and view.lastWidth ~= math.floor(width) then
            view.lastWidth = math.floor(width)
            UI.refresh()
        end
    end)
    view.content, view.blocks, view.slots = content, {}, {}
    view.focus = box
    view.empty = text(content, "GameFontDisable", "CENTER", true)
    view.empty:SetPoint("TOPLEFT", 30, -50)
    view.empty:SetPoint("RIGHT", -30, 0)
    view.footer = text(view, "GameFontDisableSmall")
    view.footer:SetPoint("BOTTOMLEFT", 6, 4)
    view.footer:SetPoint("RIGHT", -6, 0)
    return view
end

local refreshQueued
function UI.refresh()
    if not view or not view:IsVisible() or refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if view and view:IsVisible() then UI.render() end
    end)
end

-- Entries after search and filters; merged or as real stacks.
function UI.entries(ctx)
    local guild = ctx.guild()
    if not guild then return {} end
    local stacks = data.stacks(guild)
    local list = data.setting("merge") and (data.merge(stacks)) or stacks
    local f = view.filters
    local query = ctx.lower(f.text or ""):match("^%s*(.-)%s*$")
    local result = {}
    for _, entry in ipairs(list) do
        local info = data.info(entry.id, entry.link)
        entry.category = data.categorize(entry.id, entry.link)
        local ok = (query == "" or (info.name and ctx.lower(info.name):find(query, 1, true) ~= nil) or tostring(entry.id) == query)
            and (not f.category or entry.category == f.category)
            and (not f.quality or info.quality == f.quality)
        if ok then result[#result + 1] = entry end
    end
    table.sort(result, function(a, b)
        local ia, ib = data.info(a.id, a.link), data.info(b.id, b.link)
        if (ia.quality or 0) ~= (ib.quality or 0) then return (ia.quality or 0) > (ib.quality or 0) end
        local na, nb = ia.name or ("~" .. a.id), ib.name or ("~" .. b.id)
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)
    return result
end

function UI.render()
    local ctx = view.ctx
    local guild = ctx.guild()
    view.title:SetText(guild and L["Guild bank %s"]:format(ctx.guildName()) or L["Guild bank"])
    -- Last successful capture (the newest bank tab), not the time it was received.
    local newest, sender
    local tabs = guild and data.tabs(guild) or {}
    for _, tab in ipairs(tabs) do
        if tab.at and (not newest or tab.at > newest) then newest, sender = tab.at, tab.sender end
    end
    if not guild then
        view.status:SetText(L["You are not in a guild."])
    elseif not newest then
        view.status:SetText(L["No bank data yet. Open the guild vault or request the guild's snapshot."])
    else
        view.status:SetText(L["Last update: %s"]:format(date("%d.%m.%Y · %H:%M", newest))
            .. (sender and ("   |cff9b9389" .. L["from %s"]:format(ctx.displayName(sender)) .. "|r") or ""))
    end
    local balance = guild and addon.guildBank.balance(guild)
    view.gold:SetText(balance and UI.money(balance.copper) or "|cff9b9389" .. L["unknown"] .. "|r")
    view.scan:SetEnabled(ctx.vaultOpen())
    view.merge:SetChecked(data.setting("merge"))
    view.category.Sync(); view.quality.Sync()

    local entries = UI.entries(ctx)
    local size = data.setting("slotSize")
    local width = math.max(220, view.content:GetWidth())
    local byCategory = {}
    for _, entry in ipairs(entries) do
        byCategory[entry.category] = byCategory[entry.category] or {}
        table.insert(byCategory[entry.category], entry)
    end
    -- Blocks sized by their items, placed side by side and wrapped by the available width.
    local maxColumns = math.max(1, math.floor((width - 2 * PADDING + GAP) / (size + GAP)))
    local x, y, rowHeight, used, blockIndex = 0, 0, 0, 0, 0
    for _, category in ipairs(data.categories) do
        local list = byCategory[category.id]
        if list then
            blockIndex = blockIndex + 1
            local block = view.blocks[blockIndex]
            if not block then
                block = frameBox(view.content)
                block.icon = block:CreateTexture(nil, "ARTWORK")
                block.icon:SetSize(16, 16)
                block.icon:SetPoint("TOPLEFT", 9, -8)
                block.icon:SetTexCoord(.07, .93, .07, .93)
                block.title = text(block, "GameFontNormal")
                block.title:SetPoint("LEFT", block.icon, "RIGHT", 6, 0)
                block.count = text(block, "GameFontDisableSmall", "RIGHT")
                block.count:SetPoint("TOPRIGHT", -10, -10)
                view.blocks[blockIndex] = block
            end
            block.title:SetText(L[category.label])
            -- At least four columns, and wide enough for the heading.
            local wanted = math.max(4, math.ceil((block.title:GetStringWidth() + 70 - 2 * PADDING + GAP) / (size + GAP)))
            local columns = math.min(maxColumns, math.max(#list, wanted))
            local rows = math.ceil(#list / columns)
            local blockWidth = columns * (size + GAP) - GAP + 2 * PADDING
            local blockHeight = 30 + rows * (size + GAP) - GAP + PADDING
            if x > 0 and x + blockWidth > width then x, y, rowHeight = 0, y + rowHeight + 8, 0 end
            block:ClearAllPoints()
            block:SetPoint("TOPLEFT", x, -y)
            block:SetSize(blockWidth, blockHeight)
            block.icon:SetTexture(category.icon)
            block.count:SetText(#list)
            block:Show()
            for position, entry in ipairs(list) do
                used = used + 1
                local slot = view.slots[used]
                if not slot then
                    slot = newSlot(view.content)
                    view.slots[used] = slot
                end
                slot:SetParent(block)
                slot:SetFrameLevel(block:GetFrameLevel() + 2)
                local column, line = (position - 1) % columns, math.floor((position - 1) / columns)
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", block, "TOPLEFT", PADDING + column * (size + GAP), -30 - line * (size + GAP))
                fillSlot(slot, entry, size)
                slot:Show()
            end
            x = x + blockWidth + 8
            rowHeight = math.max(rowHeight, blockHeight)
        end
    end
    for index = blockIndex + 1, #view.blocks do view.blocks[index]:Hide() end
    for index = used + 1, #view.slots do view.slots[index]:Hide() end
    view.content:SetHeight(math.max(1, y + rowHeight + 8))
    view.empty:SetShown(blockIndex == 0)
    if not guild then view.empty:SetText(L["You are not in a guild."])
    elseif #tabs == 0 then view.empty:SetText(L["No bank data yet. Open the guild vault or request the guild's snapshot."])
    else view.empty:SetText(L["No items match your search."]) end
    local stacks = 0
    for _, tab in ipairs(tabs) do stacks = stacks + #tab.items end
    view.footer:SetText(#tabs > 0 and L["Last synchronized guild bank stock · %d items in %d stacks"]:format(#entries, stacks) or "")
end

-- Display options in the central settings (page "Guild bank", next to the sync options).
function UI.registerSettings(S)
    S.page("bank", "guild", "Guild bank") -- already created by ForeverGuild.lua; kept for standalone use
    local function option(key, label, desc)
        S.add({ page = "bank", kind = "check", label = label, desc = desc, scope = "account", default = data.defaults[key],
            get = function() return data.setting(key) end, set = function(value) data.set(key, value); UI.refresh() end })
    end
    option("merge", L["Combine identical items"], L["Shows stacks of the same item as one entry. Items with another enchantment or random bonus stay separate; the tooltip lists the bank tabs."])
    option("qualityBorder", L["Quality borders"], L["Colours the item slots by item quality."])
    S.add({ page = "bank", kind = "choice", label = L["Item size"], scope = "account", default = 38,
        desc = L["Size of the item slots in the guild bank."],
        options = function() return { { 34, L["Small"] }, { 38, L["Normal"] }, { 42, L["Large"] } } end,
        get = function() return data.setting("slotSize") end, set = function(value) data.set("slotSize", value); UI.refresh() end })
end
