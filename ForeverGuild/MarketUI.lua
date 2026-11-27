local _, addon = ...
-- Crafting marketplace UI: order dialog, personal order management, bulletin board
-- cards, notifications and settings. Uses the shared order model (Market.lua/Board.lua);
-- all data access goes through the context from addon.marketContext().
local L = addon.L
local market = addon.market
local UI = {}
addon.marketUI = UI

local GOLD, MUTED, GREEN, RED = { 1, .82, .24 }, { .62, .57, .50 }, { .45, .86, .45 }, { 1, .45, .35 }
local DAY = 86400
local STATE_COLORS = {
    O = { .89, .73, .42 }, Q = { .95, .80, .45 }, M = { .85, .66, .40 }, W = { .61, .78, .90 },
    R = { .55, .88, .60 }, H = { .55, .88, .60 }, D = { .50, .78, .52 }, X = MUTED, J = MUTED, E = MUTED,
}
local STATE_LABELS = {
    O = "Open", Q = "Request sent", M = "Waiting for materials", W = "In progress", R = "Ready for handoff",
    H = "Handoff in progress", D = "Completed#2", X = "Cancelled", J = "Declined", E = "Expired",
}
local METHOD_LABELS = { "Personal trade", "Mail", "Cash on delivery", "Custom arrangement" }
local PAYMENT_LABELS = {
    none = "No payment required", agreed = "Payment agreed", pending = "Payment outstanding",
    partial = "Partly paid", paid = "Fully paid", unclear = "Payment unclear", waived = "Payment waived",
}
local PAY_KINDS = { { "n", "No payment" }, { "v", "Voluntary tip" }, { "f", "Fixed crafting fee" } }
local EVENT_LABELS = {
    posted = "Order posted", direct = "New direct crafting order", assigned = "New direct crafting order",
    accepted = "Order accepted", declined = "Order declined", released = "Order released by the crafter",
    reposted = "Posted on the bulletin board again", started = "Work started", ready = "Ready for handoff",
    missing = "Missing materials reported", done = "Order completed", cancelled = "Order cancelled",
    withdrawn = "Order withdrawn", progress = "Crafting progress updated", craftedAll = "All items crafted",
    shipped = "Items handed over or sent", received = "Receipt confirmed", materials = "Materials received",
    costOffer = "Material cost proposed", costAgreed = "Material cost accepted", costRejected = "Material cost declined",
    paid = "Payment reported", paymentReceived = "Payment receipt confirmed", waived = "Payment waived",
    proposal = "Change proposed", agreed = "Change accepted", rejected = "Change declined", changed = "Order details changed",
    extended = "Deadline extended", cancelRequest = "Cancellation requested", cancelRejected = "Cancellation declined – clarification needed",
    dispute = "Clarification needed", resolved = "Clarification resolved", unconfirmed = "Request not confirmed by the requester",
    expiring = "Your posting expires soon", overdue = "Completion deadline passed", lost = "Another crafter took the order",
    handover = "Handoff still pending", match = "New order you can craft",
}
local MONEY_EVENTS = { costOffer = true, costAgreed = true, paid = true, paymentReceived = true }
local COUNT_EVENTS = { progress = true, craftedAll = true, shipped = true, received = true }
UI.eventLabels = EVENT_LABELS

local function widgets() return addon.recipeFinder.widgets end

local function color(fontString, rgb)
    fontString:SetTextColor(rgb[1] or rgb.r, rgb[2] or rgb.g, rgb[3] or rgb.b)
end

local function text(parent, font, justify, wrap)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(wrap and true or false)
    if wrap then label:SetJustifyV("TOP") end
    return label
end

local measure
local function textWidth(value, font)
    if not measure then
        measure = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        measure:Hide()
    end
    measure:SetFontObject(font or GameFontNormal)
    measure:SetText((tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "WW")))
    return measure:GetStringWidth()
end
UI.textWidth = textWidth

local function fittedButton(ctx, parent, label, action, minimum)
    local control = ctx.button(parent, label, math.max(minimum or 80, math.ceil(textWidth(label)) + 28), 0, 0, action)
    control.Resize = function(self, caption)
        self:SetWidth(math.max(minimum or 80, math.ceil(textWidth(caption)) + 28))
        self:SetText(caption)
    end
    return control
end

local function moneyBoxes(parent, onChange)
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(214, 22)
    local boxes, x = {}, 0
    for index, width in ipairs({ 62, 30, 30 }) do
        local box = CreateFrame("EditBox", nil, group, "InputBoxTemplate")
        box:SetSize(width, 20)
        box:SetPoint("LEFT", x + 6, 0)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(index == 1 and 6 or 2)
        box:SetJustifyH("RIGHT")
        box:SetScript("OnEscapePressed", box.ClearFocus)
        box:SetScript("OnEnterPressed", box.ClearFocus)
        box:SetScript("OnTextChanged", function(_, user) if user and onChange then onChange() end end)
        local coin = group:CreateTexture(nil, "ARTWORK")
        coin:SetSize(13, 13)
        coin:SetPoint("LEFT", box, "RIGHT", 3, 0)
        coin:SetTexture(({ "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon",
            "Interface\\MoneyFrame\\UI-CopperIcon" })[index])
        boxes[index] = box
        x = x + width + 26
    end
    group.boxes = boxes
    group.Get = function()
        return market.copper(boxes[1]:GetText(), boxes[2]:GetText(), boxes[3]:GetText())
    end
    group.Set = function(_, value)
        local gold, silver, copper = market.split(value or 0)
        boxes[1]:SetText(gold > 0 and ("%.0f"):format(gold) or "")
        boxes[2]:SetText(silver > 0 and tostring(silver) or "")
        boxes[3]:SetText(copper > 0 and tostring(copper) or "")
    end
    group.SetEnabled = function(_, enabled)
        for _, box in ipairs(boxes) do
            box:SetEnabled(enabled)
            box:SetAlpha(enabled and 1 or .45)
        end
    end
    return group
end

local function progressBar(parent, width)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width or 200, 12)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(.08, .06, .04, .9)
    local border = bar:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(.45, .32, .16, .9)
    back:SetDrawLayer("BACKGROUND", 1)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetColorTexture(.85, .62, .22, 1)
    local label = text(bar, "GameFontHighlightSmall", "LEFT")
    label:SetPoint("LEFT", bar, "RIGHT", 8, 0)
    bar.label = label
    bar.Set = function(self, value, maximum, caption, tint)
        local ratio = maximum and maximum > 0 and math.max(0, math.min(1, value / maximum)) or 0
        local inner = math.max(1, self:GetWidth() - 2)
        fill:SetWidth(math.max(.1, inner * ratio))
        fill:SetShown(ratio > 0)
        local rgb = tint or (ratio >= 1 and GREEN or { .85, .62, .22 })
        fill:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
        label:SetText(caption or ("%d / %d"):format(value, maximum or 0))
    end
    return bar
end

-- Order presentation ---------------------------------------------------------------------------
local function roleOf(order, ctx)
    if not order then return nil end
    if order.owner == ctx.player() then return "o" end
    if ctx.same(order.crafter) then return "c" end
end
UI.roleOf = roleOf

function UI.stateText(order, now)
    local state = market.state(order, now)
    local label, tint = L[STATE_LABELS[state] or "Open"], STATE_COLORS[state] or GOLD
    if order.intent then
        return L["Waiting for confirmation"], { 1, .75, .35 }
    end
    if order.cancelBy and market.accepted[state] then return L["Cancellation requested"], RED end
    if order.dispute and not market.closed[state] then return L["Clarification needed"], RED end
    if state == "W" and (order.crafted or 0) > 0 and (order.crafted or 0) < order.quantity then
        label = L["Partly crafted"]
    elseif state == "H" and (order.delivered or 0) >= order.quantity then
        label, tint = L["Payment outstanding"], { 1, .75, .35 }
    end
    if order.ext and market.overdue(order, now) then label = label .. " · " .. L["Overdue"]; tint = RED end
    return label, tint
end

local function remaining(stamp, now)
    if not stamp or stamp <= 0 then return nil end
    local left = stamp - now
    if left <= 0 then return L["Expired"] end
    if left >= DAY then return L["%d days left"]:format(math.floor(left / DAY)) end
    return L["%d h left"]:format(math.max(1, math.floor(left / 3600)))
end

function UI.remainingText(order, now)
    local state = market.state(order, now)
    if state == "O" or state == "Q" then return remaining(order.expiresAt, now) end
    if market.accepted[state] and (order.due or 0) > 0 then
        local left = remaining(order.due, now)
        return left and (L["Deadline: "] .. left)
    end
end

function UI.tipText(order)
    if not order.ext then return nil end
    local total = market.total(order)
    if total <= 0 then return nil end
    local tip = market.tipTotal(order)
    local textValue = market.money(total)
    if order.tipEach and tip > 0 then
        textValue = textValue .. "  |cffbfb29a(" .. market.money(order.tip) .. " " .. L["per craft"] .. ")|r"
    end
    return textValue
end

local function itemLine(order, ctx)
    local recipe = ctx.describe(order)
    return ("%d × %s"):format(order.quantity, recipe.name), recipe
end

local function eventText(entry, order)
    local label = L[EVENT_LABELS[entry.code] or entry.code]
    if entry.code == "materials" then
        label = entry.n == 2 and L["Materials received completely"] or L["Materials partly received"]
    elseif MONEY_EVENTS[entry.code] and entry.n then
        label = label .. ": " .. market.money(entry.n)
    elseif COUNT_EVENTS[entry.code] and entry.n then
        label = label .. (": %d / %d"):format(entry.n, order and order.quantity or entry.n)
    end
    return label
end
UI.eventText = eventText

-- Notifications ------------------------------------------------------------------------------------
local toast, toastQueue = nil, {}

local function showNextToast(ctx)
    if not toast or toast:IsShown() or #toastQueue == 0 then return end
    if InCombatLockdown and InCombatLockdown() and not market.setting("combat") then
        C_Timer.After(5, function() showNextToast(ctx) end)
        return
    end
    local entry = table.remove(toastQueue, 1)
    toast.entry = entry
    toast.headline:SetText(entry.title)
    toast.item:SetText(entry.item or "")
    if entry.itemColor then color(toast.item, entry.itemColor) end
    toast.person:SetText(entry.person or "")
    toast.icon:SetTexture(entry.icon or ctx.icon)
    toast.open:SetShown(entry.key ~= nil)
    toast:Show()
    toast.serial = (toast.serial or 0) + 1
    local serial = toast.serial
    C_Timer.After(14, function()
        if toast.serial == serial and toast:IsShown() and not toast:IsMouseOver() then
            toast:Hide()
            showNextToast(ctx)
        end
    end)
end

local function buildToast(ctx)
    if toast then return end
    toast = CreateFrame("Frame", "ForeverGuildMarketNotice", UIParent, "BackdropTemplate")
    toast:SetSize(340, 124)
    toast:SetPoint("TOP", 0, -118)
    toast:SetFrameStrata("DIALOG")
    toast:SetClampedToScreen(true)
    toast:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24, tileSize = 32, tile = true,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    toast:EnableMouse(true)
    toast:Hide()
    local icon = toast:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("TOPLEFT", 16, -16)
    icon:SetTexCoord(.06, .94, .06, .94)
    toast.icon = icon
    local brand = text(toast, "GameFontDisableSmall")
    brand:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, 0)
    brand:SetText("ForeverGuild")
    toast.headline = text(toast, "GameFontNormal")
    toast.headline:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3)
    toast.headline:SetPoint("RIGHT", -16, 0)
    toast.item = text(toast, "GameFontHighlight")
    toast.item:SetPoint("TOPLEFT", 16, -58)
    toast.item:SetPoint("RIGHT", -16, 0)
    toast.person = text(toast, "GameFontHighlightSmall")
    toast.person:SetPoint("TOPLEFT", toast.item, "BOTTOMLEFT", 0, -4)
    toast.person:SetPoint("RIGHT", -16, 0)
    color(toast.person, { .85, .77, .63 })
    local close = fittedButton(ctx, toast, L["Close"], function()
        toast:Hide()
        showNextToast(ctx)
    end, 80)
    close:ClearAllPoints()
    close:SetPoint("BOTTOMRIGHT", -14, 12)
    toast.open = fittedButton(ctx, toast, L["Open order"], function()
        local entry = toast.entry
        toast:Hide()
        if entry and entry.key then ctx.openOrder(entry.key) end
        showNextToast(ctx)
    end, 100)
    toast.open:ClearAllPoints()
    toast.open:SetPoint("BOTTOMLEFT", 14, 12)
end

-- Stores a notification (deduplicated by event ID) and shows it as configured.
function UI.notify(ctx, order, code, value, revision)
    local guild = ctx.guild()
    local kind = market.notifyTypes[code]
    if not guild or not kind then return end
    local key = order and ctx.key(order)
    local id = ("%s@%s:%s"):format(key or "-", tostring(revision or (order and order.revision) or 0), code)
    if code == "expiring" or code == "overdue" or code == "handover" then
        id = ("%s:%s:%s"):format(key or "-", code, tostring(order and (order.due or order.expiresAt) or 0))
    end
    local itemText, recipe = nil, nil
    if order then itemText, recipe = itemLine(order, ctx) end
    local role = roleOf(order, ctx)
    local other = order and (role == "o" and order.crafter or order.owner)
    local person = other and ((role == "o" and L["Crafter: %s"] or L["Requester: %s"]):format(ctx.displayName(other))) or nil
    local title = eventText({ code = code, n = value }, order)
    local stored = market.notify(guild, id, { key = key, code = code, n = value, item = itemText, person = person }, ctx.clock())
    if not stored then return end
    ctx.updateNotice()
    if not market.typeEnabled(kind) then return end
    if market.setting("chat") then
        print(("|cffffd100ForeverGuild|r · %s%s%s"):format(title, itemText and (" – " .. itemText) or "",
            other and (" (" .. ctx.displayName(other) .. ")") or ""))
    end
    if market.setting("sound") and PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
        pcall(PlaySound, SOUNDKIT.TELL_MESSAGE)
    end
    if market.setting("popup") then
        buildToast(ctx)
        toastQueue[#toastQueue + 1] = { key = key, title = title, item = itemText, person = person,
            icon = recipe and recipe.icon, itemColor = recipe and recipe.color }
        while #toastQueue > 6 do table.remove(toastQueue, 1) end
        showNextToast(ctx)
    end
end

-- Hooks the shared order store: history entries become notifications for the right party.
function UI.attach(ctx)
    addon.board.observer = function(guild, order, events, actor)
        if guild ~= ctx.guild() then return end
        local role = roleOf(order, ctx)
        local me = ctx.player()
        local now = ctx.clock()
        for _, event in ipairs(events) do
            local code = event.code
            if code == "posted" then
                if not order.direct and order.owner ~= me and market.state(order, now) == "O" and ctx.knows(order.recipe)
                    and not ctx.hidden(order) then
                    UI.notify(ctx, order, "match", nil, order.revision)
                end
            elseif code == "direct" or code == "assigned" then
                if role == "c" and market.state(order, now) == "Q" then UI.notify(ctx, order, code, nil, order.revision) end
            elseif market.recipient(event, role) and not (actor == me and event.by == nil) then
                UI.notify(ctx, order, code, event.n, order.revision)
            end
        end
        ctx.refresh()
    end
    addon.board.lost = function(guild, order)
        if guild == ctx.guild() and order.crafter and not ctx.same(order.crafter) and order.state ~= "O" then
            UI.notify(ctx, order, "lost", nil, order.revision)
        end
    end
end

local handoverReminded = {}
function UI.tick(ctx)
    local guild = ctx.guild()
    if not guild then return end
    local now = ctx.clock()
    local records = addon.board.records(guild)
    if market.setting("remindOverdue") then
        for _, entry in ipairs(market.reminders(records, ctx.player(), now, ctx.same)) do
            UI.notify(ctx, entry.order, entry.code)
        end
    end
    if market.setting("remindHandover") then
        for key, order in pairs(records) do
            local role = roleOf(order, ctx)
            if order.ext and role and (order.state == "R" or order.state == "H") and not handoverReminded[key]
                and now - (order.acceptedAt or now) >= 0 then
                handoverReminded[key] = true
                if (role == "o" and order.state == "R") or (role == "c" and order.state == "H" and not market.settled(order)) then
                    UI.notify(ctx, order, "handover", nil, order.revision)
                end
            end
        end
    end
    market.pruneSeen(now)
end

-- Prompt -------------------------------------------------------------------------------------------
local prompt
local function buildPrompt(ctx)
    if prompt then return prompt end
    prompt = CreateFrame("Frame", "ForeverGuildMarketPrompt", UIParent, "BackdropTemplate")
    prompt:SetSize(390, 200)
    prompt:SetPoint("CENTER", 0, 80)
    prompt:SetFrameStrata("FULLSCREEN_DIALOG")
    prompt:SetToplevel(true)
    prompt:SetClampedToScreen(true)
    prompt:EnableMouse(true)
    prompt:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24, tileSize = 32, tile = true,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    table.insert(UISpecialFrames, "ForeverGuildMarketPrompt")
    prompt.title = text(prompt, "GameFontNormal", "CENTER")
    prompt.title:SetPoint("TOP", 0, -18)
    prompt.title:SetPoint("LEFT", 18, 0)
    prompt.title:SetPoint("RIGHT", -18, 0)
    prompt.body = text(prompt, "GameFontHighlightSmall", "LEFT", true)
    prompt.body:SetPoint("TOPLEFT", 20, -42)
    prompt.body:SetPoint("RIGHT", -20, 0)
    prompt.count = CreateFrame("EditBox", nil, prompt, "InputBoxTemplate")
    prompt.count:SetSize(60, 20)
    prompt.count:SetAutoFocus(false)
    prompt.count:SetNumeric(true)
    prompt.count:SetMaxLetters(3)
    prompt.count:SetScript("OnEscapePressed", prompt.count.ClearFocus)
    prompt.money = moneyBoxes(prompt)
    prompt.line = CreateFrame("EditBox", nil, prompt, "InputBoxTemplate")
    prompt.line:SetSize(330, 20)
    prompt.line:SetAutoFocus(false)
    prompt.line:SetMaxBytes(60)
    prompt.line:SetScript("OnEscapePressed", prompt.line.ClearFocus)
    prompt.choiceValue = nil
    prompt.choice = widgets().dropdown(prompt, 230, function() return prompt.options or {} end,
        function() return prompt.choiceValue end, function(value)
            prompt.choiceValue = value
            if prompt.onChoice then prompt.onChoice(value) end
        end)
    prompt.hint = text(prompt, "GameFontDisableSmall", "LEFT", true)
    prompt.ok = fittedButton(ctx, prompt, L["Confirm"], function()
        local spec = prompt.spec
        local value
        if spec.kind == "count" or spec.kind == "days" then value = tonumber(prompt.count:GetText())
        elseif spec.kind == "money" then value = prompt.money.Get()
        elseif spec.kind == "text" then value = prompt.line:GetText()
        elseif spec.kind == "choice" then value = prompt.choiceValue
        elseif spec.kind == "proposal" then
            local field = prompt.choiceValue
            if field == "t" then value = prompt.money.Get()
            elseif field == "m" then value = prompt.methodValue
            else value = tonumber(prompt.count:GetText()) end
        elseif spec.kind == "confirm" then value = true end
        if spec.kind ~= "text" and spec.kind ~= "confirm" and value == nil then return end
        if (spec.kind == "count" or spec.kind == "days") and (value < (spec.min or 0) or value > (spec.max or 200)) then return end
        prompt:Hide()
        spec.confirm(value, prompt.choiceValue)
    end, 100)
    prompt.cancel = fittedButton(ctx, prompt, L["Cancel"], function() prompt:Hide() end, 100)
    prompt.method = widgets().dropdown(prompt, 200, function()
        local options = {}
        for index, label in ipairs(METHOD_LABELS) do options[index] = { index, L[label] } end
        return options
    end, function() return prompt.methodValue end, function(value) prompt.methodValue = value end)
    return prompt
end

-- spec: title, text, kind (count/days/money/text/choice/proposal/confirm), min, max, default,
-- options (choice), confirm(value, choice), hint
function UI.prompt(ctx, spec)
    if ctx.inCombat() then return end
    local frame = buildPrompt(ctx)
    frame.spec = spec
    frame.title:SetText(spec.title)
    frame.body:SetText(spec.text or "")
    local bodyHeight = (spec.text and spec.text ~= "") and math.ceil(frame.body:GetStringHeight()) or 0
    local y = -46 - bodyHeight
    for _, control in ipairs({ frame.count, frame.money, frame.line, frame.choice, frame.method }) do control:Hide() end
    frame.options, frame.onChoice = spec.options, nil
    local function place(control, x)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", x or 26, y)
        control:Show()
    end
    if spec.kind == "count" or spec.kind == "days" then
        frame.count:SetText(spec.default and tostring(spec.default) or "")
        place(frame.count)
        y = y - 30
    elseif spec.kind == "money" then
        frame.money:Set(spec.default or 0)
        place(frame.money, 14)
        y = y - 30
    elseif spec.kind == "text" then
        frame.line:SetText(spec.default or "")
        place(frame.line)
        y = y - 30
    elseif spec.kind == "choice" then
        frame.choiceValue = spec.default or (spec.options[1] and spec.options[1][1])
        place(frame.choice, 22)
        frame.choice.Sync()
        y = y - 34
    elseif spec.kind == "proposal" then
        frame.choiceValue = spec.default or "q"
        frame.methodValue = spec.method or 1
        place(frame.choice, 22)
        frame.choice.Sync()
        y = y - 34
        local valueY = y
        frame.onChoice = function(field)
            for _, control in ipairs({ frame.count, frame.money, frame.method }) do control:Hide() end
            y = valueY
            if field == "t" then
                frame.money:Set(spec.values and spec.values.t or 0)
                place(frame.money, 14)
            elseif field == "m" then
                place(frame.method, 22)
                frame.method.Sync()
            else
                frame.count:SetText(tostring(spec.values and spec.values[field] or ""))
                place(frame.count)
            end
        end
        frame.onChoice(frame.choiceValue)
        y = valueY - 34
    end
    frame.hint:SetText(spec.hint or "")
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOPLEFT", 20, y - 2)
    frame.hint:SetPoint("RIGHT", -20, 0)
    local hintHeight = (spec.hint and spec.hint ~= "") and (math.ceil(frame.hint:GetStringHeight()) + 8) or 0
    frame.ok:Resize(spec.okLabel or L["Confirm"])
    frame.ok:ClearAllPoints()
    frame.ok:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 18)
    frame.cancel:ClearAllPoints()
    frame.cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 6, 18)
    frame:SetHeight(-y + hintHeight + 58)
    frame:Show()
    frame:Raise()
end

-- Actions --------------------------------------------------------------------------------------------
-- Returns the context-dependent actions for the current player. Each action:
-- { label, run = function(), tip = optional tooltip }
function UI.actions(ctx, order, now, legacyEntry)
    local list = {}
    local function add(label, run, tip, primary) list[#list + 1] = { label = label, run = run, tip = tip, primary = primary } end
    if legacyEntry then
        -- Direct orders of older versions: everything the old protocol allows, plus local cleanup.
        local entry = legacyEntry
        local archived = ctx.isArchived(entry.key)
        add(L["Whisper#2"], function() ctx.whisper(entry.outgoing and entry.recipient or entry.sender) end)
        if not entry.outgoing and not archived then
            add(entry.done and L["Reopen"] or L["Mark completed"], function() ctx.legacySetDone(entry.key, not entry.done) end,
                L["Tells the requester (older version) that the order is complete."], true)
        end
        if entry.outgoing and not archived and entry.delivery ~= "confirmed" and not entry.withdrawn then
            add(L["Withdraw"], function()
                UI.prompt(ctx, { title = L["Withdraw order?"], kind = "confirm", text = itemLine(entry, ctx),
                    hint = L["The order is no longer delivered. Guild members who already cached it may still pass it on."],
                    confirm = function() ctx.legacyWithdraw(entry.key) end })
            end, nil, true)
        end
        if entry.outgoing then
            add(L["Create again"], function() ctx.reorder({ recipe = entry.recipe, quantity = entry.quantity, direct = true,
                crafter = entry.recipient }) end, L["Opens the order dialog with the same recipe, quantity and crafter."])
        end
        UI.cleanupActions(ctx, add, entry.key, true, entry, archived)
        return list
    end
    if not order then return list end
    local role = roleOf(order, ctx)
    local state = market.state(order, now)
    local key = ctx.key(order)
    if ctx.isArchived(key) then
        UI.cleanupActions(ctx, add, key, false, order, true)
        if role == "o" then add(L["Order again"], function() ctx.reorder(order) end) end
        return list
    end
    local function act(action, arg, textValue)
        ctx.act(order, action, arg, textValue)
    end
    local orderable, tradeStatus = UI.orderable(ctx, order.recipe)
    local counterpart = role == "o" and order.crafter or order.owner
    if counterpart and role then
        add(L["Whisper#2"], function() ctx.whisper(counterpart) end,
            ctx.isOnline(counterpart) and L["Online"] or L["Offline – the whisper may not arrive."])
    end
    if order.intent then return list end
    local function money(title, hint, default, run)
        return function()
            UI.prompt(ctx, { title = title, kind = "money", default = default, hint = hint, confirm = run })
        end
    end
    local function count(title, hint, default, low, high, run)
        return function()
            UI.prompt(ctx, { title = title, kind = "count", default = default, min = low, max = high, hint = hint, confirm = run })
        end
    end
    if not order.ext then
        -- Orders from older ForeverGuild versions support the simple workflow only.
        if state == "O" and role == "o" then add(L["Withdraw"], function() act("cancel") end)
        elseif state == "O" and not role then
            if ctx.knows(order.recipe) then add(L["Claim order"], function() act("take") end, nil, true) end
        elseif role == "c" and order.state == "W" then
            add(L["Ready for handoff#2"], function() act("ready") end, nil, true)
            add(L["Release"], function() act("release") end)
        elseif role == "c" and order.state == "R" then add(L["Release"], function() act("release") end)
        elseif role == "o" and order.state == "R" then add(L["Received#2"], function() act("received") end, nil, true) end
        -- Old-format board orders that are closed, expired or foreign can always be cleaned up locally.
        if market.closed[state] or role ~= "o" then UI.cleanupActions(ctx, add, key, false, order, false) end
        return list
    end
    if role == "o" then
        if state == "O" or state == "Q" then
            add(L["Edit"], function() ctx.edit(order) end, nil, true)
            add(L["Withdraw"], function()
                UI.prompt(ctx, { title = L["Withdraw order?"], kind = "confirm", text = itemLine(order, ctx),
                    confirm = function() act("cancel") end })
            end)
            add(L["Extend"], count(L["Extend posting"], L["Days from now (1–30)."], 7, 1, 30, function(v) act("extend", v) end))
        elseif state == "E" then
            add(L["Reopen"], count(L["Reopen order"], L["Days from now (1–30)."], 7, 1, 30, function(v) act("extend", v) end), nil, true)
            add(L["Withdraw"], function() act("cancel") end)
        elseif state == "J" then
            add(L["Post on the bulletin board"], count(L["Post on the bulletin board"], L["Days from now (1–30)."], 7, 1, 30,
                function(v) act("repost", v) end), nil, true)
            add(L["Assign to another crafter"], function()
                local options = {}
                for _, crafter in ipairs(ctx.crafters(order.recipe)) do
                    if not ctx.same(crafter.name) and crafter.name ~= order.crafter then options[#options + 1] = { crafter.name, crafter.label } end
                end
                if #options == 0 then
                    UI.prompt(ctx, { title = L["Assign to another crafter"], kind = "confirm",
                        text = L["No other guild member is known to craft this recipe."], confirm = function() end })
                    return
                end
                UI.prompt(ctx, { title = L["Assign to another crafter"], kind = "choice", options = options,
                    hint = L["The order is sent as a new direct request."], confirm = function(name) act("assign", 7, name) end })
            end)
        end
        if market.accepted[state] then
            if (order.costOffer or 0) > 0 then
                add(L["Accept material cost"], function() act("costok") end, market.money(order.costOffer), true)
                add(L["Decline material cost"], function() act("costno") end)
            end
            if order.proposal and order.proposal.by == "c" then
                add(L["Accept change"], function() act("agree") end, UI.proposalText(order), true)
                add(L["Decline change"], function() act("reject") end)
            end
            if order.cancelBy == "c" then
                add(L["Agree to cancellation"], function() act("cancelok") end, nil, true)
                add(L["Refuse cancellation"], function() act("cancelno") end)
            end
            if state == "R" or state == "H" then
                add(L["Confirm receipt"], count(L["Confirm receipt"], L["Total number of items you have received so far."],
                    math.max(order.shipped or 0, order.crafted or 0), math.max(1, order.delivered or 0), order.quantity,
                    function(v) act("received", v) end), nil, true)
            end
            if market.total(order) > 0 and not order.waived and (order.paidGot or 0) < market.total(order) then
                add(L["Confirm payment"], money(L["Confirm payment"], L["Total amount you have paid to the crafter. ForeverGuild does not move any gold."],
                    market.total(order), function(v) act("paid", v) end))
            end
            if not order.proposal then
                add(L["Propose change"], function() UI.proposalPrompt(ctx, order) end)
            end
            add(L["Extend deadline"], count(L["Extend deadline"], L["Days added to the completion deadline (1–30)."], 3, 1, 30,
                function(v) act("extend", v) end))
            if not order.cancelBy then
                add(L["Request cancellation"], function()
                    UI.prompt(ctx, { title = L["Request cancellation"], kind = "confirm",
                        text = L["The crafter must agree. Materials or items already handed over stay recorded in the history."],
                        confirm = function() act("cancelreq") end })
                end)
            end
        end
        if state == "D" or state == "X" then
            add(L["Order again"], function() ctx.reorder(order) end, nil, true)
        end
        if market.closed[state] then UI.cleanupActions(ctx, add, key, false, order, false) end
    elseif role == "c" then
    if state == "Q" and not orderable then
            list[#list + 1] = { label = L["Accept order"], disabled = true, tip = UI.unorderableText(tradeStatus) }
    elseif state == "Q" then
            add(L["Accept order"], function()
                UI.prompt(ctx, { title = L["Accept order"], kind = "confirm", text = UI.summary(ctx, order),
                    confirm = function() act("accept") end })
            end, nil, true)
            add(L["Decline"], function()
                UI.prompt(ctx, { title = L["Decline order"], kind = "text", hint = L["Optional reason (visible to the requester)."],
                    confirm = function(reason) act("decline", 0, reason) end })
            end)
            add(L["Propose material cost"], money(L["Propose material cost"], L["Reimbursement for materials you provide yourself. The requester must agree."],
                order.costOffer, function(v) if v > 0 then act("cost", v) end end))
        end
        if market.accepted[state] then
            if order.proposal and order.proposal.by == "o" then
                add(L["Accept change"], function() act("agree") end, UI.proposalText(order), true)
                add(L["Decline change"], function() act("reject") end)
            end
            if order.cancelBy == "o" then
                add(L["Agree to cancellation"], function() act("cancelok") end, nil, true)
                add(L["Refuse cancellation"], function() act("cancelno") end)
            end
            if state == "M" and (order.matState or 0) < 2 then
                add(L["Materials received"], function() act("mats", 2) end, L["All promised materials have arrived."], true)
                if (order.matState or 0) < 1 then
                    add(L["Partly received"], function() act("mats", 1) end)
                end
                if not market.needsMaterials(order) or order.missing then
                    add(L["Start without materials"], function() act("start") end)
                end
            end
            if state == "M" or state == "W" or (state == "H" and (order.crafted or 0) < order.quantity) then
                add(L["Update progress"], count(L["Update progress"], L["Number of crafts completed so far."],
                    order.crafted or 0, order.delivered or 0, order.quantity, function(v) act("progress", v) end), nil, state == "W")
                if state == "W" then add(L["Report missing materials"], function() act("missing") end) end
                add(L["Ready for handoff#2"], function() act("ready") end,
                    L["Marks the crafted items as ready. The requester is notified."], state ~= "W")
            end
            if state == "R" or state == "H" then
                local verb = (order.method == 2 or order.method == 3) and L["Report shipment"] or L["Report handoff"]
                add(verb, count(verb, L["Total number of items handed over or sent so far."], order.crafted or order.quantity,
                    math.max(1, order.delivered or 0), order.crafted or order.quantity, function(v) act("ship", v) end), nil, state == "R")
            end
            if market.total(order) > 0 and not order.waived and (order.paidGot or 0) < market.total(order) then
                add(L["Confirm payment received"], money(L["Confirm payment received"], L["Total amount you have received so far."],
                    math.max(order.paidSent or 0, market.total(order)), function(v) act("gotpaid", v) end))
                add(L["Waive payment"], function()
                    UI.prompt(ctx, { title = L["Waive payment"], kind = "confirm",
                        text = L["The order can be completed without payment."], confirm = function() act("waive") end })
                end)
            end
            if (order.cost or 0) == 0 and (order.costOffer or 0) == 0 then
                add(L["Propose material cost"], money(L["Propose material cost"], L["Reimbursement for materials you provide yourself. The requester must agree."],
                    0, function(v) if v > 0 then act("cost", v) end end))
            end
            if not order.proposal then add(L["Propose change"], function() UI.proposalPrompt(ctx, order) end) end
            if (order.crafted or 0) == 0 and (order.matState or 0) == 0 and (order.shipped or 0) == 0 then
                add(L["Release"], function()
                    UI.prompt(ctx, { title = L["Release order"], kind = "text", hint = L["Optional reason (visible to the requester)."],
                        confirm = function(reason) act("release", 0, reason) end })
                end)
            elseif not order.cancelBy then
                add(L["Request cancellation"], function() act("cancelreq") end)
            end
        end
    elseif state == "O" and not order.direct then
        if not orderable then
            list[#list + 1] = { label = L["Accept order"], disabled = true, tip = UI.unorderableText(tradeStatus) }
        elseif ctx.knows(order.recipe) then
            add(L["Accept order"], function() UI.confirmTake(ctx, order) end, nil, true)
        else
            list[#list + 1] = { label = L["Accept order"], disabled = true,
                tip = L["Recipe missing. Open your professions to update known recipes."] }
        end
        add(L["Whisper#2"], function() ctx.whisper(order.owner) end)
    end
    if role == "c" and market.closed[state] then UI.cleanupActions(ctx, add, key, false, order, false) end
    if order.dispute and role then add(L["Mark as resolved"], function() act("resolve") end) end
    if not role and ctx.mayModerate() and order.owner ~= ctx.player() then
        add(L["Hide"], function() ctx.moderate(order) end)
    end
    return list
end

-- Local cleanup (only this character's view): archive, restore, remove. A removal leaves a
-- tombstone so later sync messages cannot bring the order back.
function UI.cleanupActions(ctx, add, key, legacy, subject, archived)
    if archived then
        add(L["Restore"], function() ctx.archive(key, false) end, L["Moves the order back out of the archive."])
    else
        add(L["Archive"], function() ctx.archive(key, true) end,
            L["Moves the order into the history of this character. Nothing changes for other players."])
    end
    add(L["Remove locally"], function()
        UI.prompt(ctx, { title = L["Remove order locally?"], kind = "confirm", text = itemLine(subject, ctx),
            hint = L["Only removed from this character's view; the order itself is not cancelled for anyone else. It will not come back through later synchronization."],
            confirm = function() ctx.removeLocal(key, legacy) end })
    end, L["Removes the order from this character only."])
end

function UI.proposalText(order)
    local proposal = order.proposal
    if not proposal then return nil end
    if proposal.f == "q" then return L["New quantity: %d"]:format(proposal.v) end
    if proposal.f == "t" then return L["New payment: %s"]:format(market.money(proposal.v)) end
    if proposal.f == "m" then return L["New handoff: %s"]:format(L[METHOD_LABELS[proposal.v] or "Custom arrangement"]) end
    if proposal.f == "d" then return L["New deadline: %d days from agreement"]:format(proposal.v) end
end

function UI.proposalPrompt(ctx, order)
    UI.prompt(ctx, { title = L["Propose change"], kind = "proposal",
        options = { { "q", L["Number of crafts"] }, { "t", L["Crafting fee"] }, { "m", L["Handoff method"] }, { "d", L["Completion deadline (days)"] } },
        values = { q = order.quantity, t = order.tip or 0, d = order.dueDays or 0 }, method = order.method or 1,
        hint = L["The other party must confirm. Agreed payments cannot be reduced one-sidedly."],
        confirm = function(value, field) if value then ctx.act(order, "propose", value, field) end end })
end

function UI.summary(ctx, order)
    local lines = { (itemLine(order, ctx)) }
    local tip = UI.tipText(order)
    lines[#lines + 1] = L["Payment: %s"]:format(tip or L["None"])
    local level = market.supplyLevel(order, ctx.materials(order.recipe))
    lines[#lines + 1] = L["Materials: %s"]:format(UI.supplyText(level))
    lines[#lines + 1] = L["Handoff: %s"]:format(L[METHOD_LABELS[order.method or 1]])
    if (order.dueDays or 0) > 0 then lines[#lines + 1] = L["Completion deadline: %d days after acceptance"]:format(order.dueDays) end
    if order.note and order.note ~= "" then lines[#lines + 1] = "„" .. order.note .. "“" end
    return table.concat(lines, "\n")
end

function UI.supplyText(level)
    if level == "all" then return L["Provided by the requester"] end
    if level == "some" then return L["Partly provided"] end
    if level == "none" then return L["Provided by the crafter"] end
    return L["Unknown"]
end

function UI.orderable(ctx, recipe, professionID)
    local status = ctx.orderStatus and ctx.orderStatus(recipe, professionID) or "TRADEABLE"
    return status == "TRADEABLE" or status == "SERVICE", status
end

function UI.unorderableText(status)
    if status == "NON_TRADEABLE" then return L["Binds when picked up: this item cannot be handed over and therefore not ordered."] end
    return L["Item data is still loading; the item can be ordered once it is confirmed to be tradeable."]
end

function UI.confirmTake(ctx, order)
    UI.prompt(ctx, { title = L["Accept order"], kind = "confirm", text = UI.summary(ctx, order),
        hint = L["The order is binding once the requester's client confirms it. Payment happens at handoff between players."],
        confirm = function() ctx.act(order, "take") end })
end

-- Detail view ------------------------------------------------------------------------------------------
local SECTIONS = { "overview", "people", "crafting", "materials", "payment", "handoff", "history" }
local SECTION_TITLES = { overview = "Order overview", people = "Participants", crafting = "Crafting",
    materials = "Materials", payment = "Payment", handoff = "Handoff", history = "Order history" }

function UI.detail(parent, ctx)
    local view = { sections = {}, materialRows = {} }
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    view.scroll, view.content = scroll, content

    local hero = CreateFrame("Frame", nil, content)
    hero:SetHeight(56)
    hero:SetPoint("TOPLEFT", 4, -4)
    hero:SetPoint("RIGHT", content, "RIGHT", -4, 0)
    hero:EnableMouse(true)
    hero:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            GameTooltip:Show()
        elseif self.recipe then
            self.entry = { recipe = self.recipe }
            ctx.recipeTooltip(self)
        end
    end)
    hero:SetScript("OnLeave", function() GameTooltip:Hide() end)
    view.icon = hero:CreateTexture(nil, "ARTWORK")
    view.icon:SetSize(40, 40)
    view.icon:SetPoint("LEFT", 6, 0)
    view.icon:SetTexCoord(.06, .94, .06, .94)
    view.title = text(hero, "GameFontNormalLarge")
    view.title:SetPoint("TOPLEFT", view.icon, "TOPRIGHT", 10, -1)
    view.title:SetPoint("RIGHT", -6, 0)
    view.subtitle = text(hero, "GameFontHighlightSmall")
    view.subtitle:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -4)
    view.subtitle:SetPoint("RIGHT", -6, 0)
    view.status = text(hero, "GameFontNormal")
    view.status:SetPoint("TOPLEFT", view.subtitle, "BOTTOMLEFT", 0, -3)
    view.status:SetPoint("RIGHT", -6, 0)
    view.hero = hero

    for _, key in ipairs(SECTIONS) do
        local box = ctx.contrastPanel(content)
        local title = text(box, "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText(L[SECTION_TITLES[key]])
        local body = text(box, "GameFontHighlightSmall", "LEFT", true)
        body:SetPoint("TOPLEFT", 11, -27)
        body:SetPoint("RIGHT", -11, 0)
        body:SetSpacing(3)
        view.sections[key] = { box = box, body = body }
    end
    view.craftBar = progressBar(view.sections.crafting.box, 170)
    view.handBar = progressBar(view.sections.handoff.box, 170)
    view.empty = text(content, "GameFontDisable", "CENTER", true)
    view.empty:SetPoint("TOPLEFT", 10, -30)
    view.empty:SetPoint("RIGHT", content, "RIGHT", -10, 0)

    local function materialRow(index)
        local row = view.materialRows[index]
        if row then return row end
        row = CreateFrame("Button", nil, view.sections.materials.box)
        row:SetHeight(18)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(.06, .94, .06, .94)
        row.label = text(row, "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT")
        row:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        view.materialRows[index] = row
        return row
    end

    local function layout()
        local width = scroll:GetWidth()
        if width <= 0 then return end
        content:SetWidth(width)
        -- The item header always gets its own block; every section follows below the previous one.
        local y = -10
        if hero:IsShown() then
            local textHeight = view.title:GetStringHeight() + view.subtitle:GetStringHeight() + view.status:GetStringHeight() + 7
            local heroHeight = math.max(48, math.ceil(textHeight) + 8)
            hero:SetHeight(heroHeight)
            y = -(4 + heroHeight + 8)
        end
        for _, key in ipairs(SECTIONS) do
            local section = view.sections[key]
            if section.box:IsShown() then
                section.box:ClearAllPoints()
                section.box:SetPoint("TOPLEFT", 2, y)
                section.box:SetPoint("RIGHT", content, "RIGHT", -2, 0)
                local height = 34 + math.ceil(section.body:GetStringHeight()) + (section.extra or 0)
                section.box:SetHeight(height)
                y = y - height - 6
            end
        end
        content:SetHeight(-y + 4)
    end
    view.layout = layout
    scroll:HookScript("OnSizeChanged", function() layout(); if view.order or view.legacy then view.set(view.order, view.legacy) end end)

    function view.set(order, legacy)
        view.order, view.legacy = order, legacy
        local now = ctx.clock()
        local show = order ~= nil or legacy ~= nil
        hero:SetShown(show)
        view.empty:SetShown(not show)
        for _, key in ipairs(SECTIONS) do view.sections[key].box:SetShown(false); view.sections[key].extra = 0 end
        if not show then
            view.empty:SetText(L["Select an order to see its details."])
            layout()
            return
        end
        local subject = order or legacy
        local recipe = ctx.describe(subject)
        view.icon:SetTexture(recipe.icon)
        hero.itemID, hero.recipe = recipe.itemID, subject.recipe
        view.title:SetText(("%d × %s"):format(subject.quantity, recipe.name))
        color(view.title, recipe.color and { recipe.color.r, recipe.color.g, recipe.color.b } or GOLD)
        view.subtitle:SetText((recipe.profession or "–") .. (recipe.rarity and ("  ·  " .. recipe.rarity) or ""))
        local function put(key, value)
            local section = view.sections[key]
            section.box:SetShown(true)
            section.body:SetText(value)
        end
        if legacy then
            -- Older direct order, shown in the current layout from the data it really has.
            local status = UI.legacyStatus(legacy)
            view.status:SetText(status)
            color(view.status, (legacy.done or legacy.completed) and GREEN or GOLD)
            local who = legacy.outgoing and legacy.recipient or legacy.sender
            local created = tonumber((legacy.key or ""):match("(%d+)%-%d+$")) or legacy.received
            local overview = { L["Direct crafting order (older ForeverGuild version)"],
                L["Created: %s"]:format(date("%d.%m.%Y %H:%M", created)),
                L["Order ID: %s"]:format((legacy.key or ""):match("(%d+%-%d+)$") or "–") }
            if ctx.isArchived(legacy.key) then overview[#overview + 1] = "|cff9b9389" .. L["Archived on this character."] .. "|r" end
            put("overview", table.concat(overview, "\n"))
            put("people", (legacy.outgoing and L["Requester: %s"]:format(ctx.displayName(ctx.player())) .. "\n"
                .. L["Crafter: %s"]:format(ctx.displayName(who))
                or L["Requester: %s"]:format(ctx.displayName(who)) .. "\n" .. L["Crafter: %s"]:format(ctx.displayName(ctx.player()))))
            UI.fillMaterials(view, ctx, legacy, materialRow)
            put("payment", L["Unknown – older versions did not record payment, material arrangement or handoff."])
            layout()
            return
        end
        local label, tint = UI.stateText(order, now)
        view.status:SetText(label)
        color(view.status, tint)
        local state = market.state(order, now)
        local overview = {}
        overview[#overview + 1] = order.direct and L["Direct crafting order"] or L["Public order on the bulletin board"]
        if order.ext then
            overview[#overview + 1] = L["Created: %s"]:format(date("%d.%m.%Y %H:%M", order.created or tonumber(order.token:match("^%d+")) or now))
        end
        local left = UI.remainingText(order, now)
        if left then overview[#overview + 1] = left end
        if order.expiresAt and (state == "O" or state == "Q" or state == "E") then
            overview[#overview + 1] = L["Open until: "] .. date("%d.%m.%Y %H:%M", order.expiresAt)
        end
        if (order.due or 0) > 0 then overview[#overview + 1] = L["Completion deadline: %s"]:format(date("%d.%m.%Y %H:%M", order.due))
        elseif (order.dueDays or 0) > 0 and not market.accepted[state] then
            overview[#overview + 1] = L["Completion deadline: %d days after acceptance"]:format(order.dueDays)
        end
        if order.intent then overview[#overview + 1] = "|cffffc060" .. L["Your request is waiting for the requester's client. It is binding once confirmed."] .. "|r" end
        if order.proposal then overview[#overview + 1] = "|cffffc060" .. L["Proposed change: "] .. UI.proposalText(order) .. "|r" end
        if order.reply then overview[#overview + 1] = L["Reply: %s"]:format(order.reply) end
        if order.note and order.note ~= "" then overview[#overview + 1] = "|cffd8c39e„" .. order.note .. "“|r" end
        put("overview", table.concat(overview, "\n"))
        local crafter = order.crafter and ctx.displayName(order.crafter) or (order.direct and "–" or L["Open to the guild"])
        local function online(name)
            if not name then return "" end
            return ctx.isOnline(name) and ("  |cff73dc73" .. L["Online"] .. "|r") or ("  |cff9b9389" .. L["Offline"] .. "|r")
        end
        put("people", L["Requester: %s"]:format(ctx.displayName(order.owner)) .. online(order.owner) .. "\n"
            .. L["Crafter: %s"]:format(crafter) .. online(order.crafter))
        if order.ext then
            local crafted = order.crafted or 0
            put("crafting", L["Crafts ordered: %d"]:format(order.quantity) .. "\n" .. L["Still to craft: %d"]:format(math.max(0, order.quantity - crafted))
                .. "\n" .. L["The amount of items per craft is defined by the recipe."])
            local section = view.sections.crafting
            view.craftBar:ClearAllPoints()
            view.craftBar:SetPoint("TOPLEFT", section.body, "BOTTOMLEFT", 0, -8)
            view.craftBar:SetWidth(math.max(80, math.min(240, (scroll:GetWidth() or 300) - 110)))
            view.craftBar:Set(crafted, order.quantity)
            section.extra = 22
        end
        UI.fillMaterials(view, ctx, order, materialRow)
        if order.ext then
            local payment = {}
            local kind = order.pay == "f" and L["Fixed crafting fee"] or (order.pay == "v" and L["Voluntary tip"] or L["No payment"])
            payment[#payment + 1] = kind .. ((order.tip or 0) > 0 and (": " .. market.money(market.tipTotal(order))) or "")
            if order.tipEach and (order.tip or 0) > 0 then payment[#payment + 1] = L["(%s per craft)"]:format(market.money(order.tip)) end
            if (order.cost or 0) > 0 then payment[#payment + 1] = L["Material reimbursement: %s"]:format(market.money(order.cost)) end
            if (order.costOffer or 0) > 0 then payment[#payment + 1] = "|cffffc060" .. L["Proposed material cost: %s"]:format(market.money(order.costOffer)) .. "|r" end
            payment[#payment + 1] = L["Total: %s"]:format(market.money(market.total(order)))
            if (order.paidSent or 0) > 0 or (order.paidGot or 0) > 0 then
                payment[#payment + 1] = L["Reported paid: %s · confirmed received: %s"]:format(market.money(order.paidSent or 0), market.money(order.paidGot or 0))
            end
            payment[#payment + 1] = L["Status: %s"]:format(L[PAYMENT_LABELS[market.payment(order)]])
            payment[#payment + 1] = "|cff9b9389" .. L["Paid by the players at handoff. ForeverGuild does not hold or guarantee any gold."] .. "|r"
            put("payment", table.concat(payment, "\n"))
            local handoff = { L["Handoff: %s"]:format(L[METHOD_LABELS[order.method or 1]]) }
            handoff[#handoff + 1] = L["Crafted %d · handed over or sent %d · received %d"]:format(order.crafted or 0, order.shipped or 0, order.delivered or 0)
            handoff[#handoff + 1] = L["Still to hand over: %d"]:format(math.max(0, order.quantity - (order.delivered or 0)))
            if order.shippedAt then handoff[#handoff + 1] = L["Last shipment: %s"]:format(date("%d.%m.%Y %H:%M", order.shippedAt)) end
            local orderable, status = UI.orderable(ctx, order.recipe)
            if not orderable then handoff[#handoff + 1] = "|cffff7a5c" .. UI.unorderableText(status) .. "|r" end
            put("handoff", table.concat(handoff, "\n"))
            local section = view.sections.handoff
            view.handBar:ClearAllPoints()
            view.handBar:SetPoint("TOPLEFT", section.body, "BOTTOMLEFT", 0, -8)
            view.handBar:SetWidth(math.max(80, math.min(240, (scroll:GetWidth() or 300) - 110)))
            view.handBar:Set(order.delivered or 0, order.quantity)
            section.extra = 22
        else
            put("payment", L["Not recorded for orders from older ForeverGuild versions."])
        end
        local history = {}
        for index = #(order.log or {}), math.max(1, #(order.log or {}) - 29), -1 do
            local entry = order.log[index]
            local who = entry.by and (ctx.displayName(entry.by) .. ": ") or ""
            history[#history + 1] = ("|cffbfb29a%s|r  %s%s"):format(date("%d.%m.%Y – %H:%M", entry.at), who, eventText(entry, order))
        end
        if #history == 0 then history[1] = L["No entries yet."] end
        put("history", table.concat(history, "\n"))
        layout()
    end
    return view
end

function UI.fillMaterials(view, ctx, order, rowFor)
    local section = view.sections.materials
    section.box:SetShown(true)
    for _, row in ipairs(view.materialRows) do row:Hide() end
    local slots = ctx.materials(order.recipe)
    if not slots or #slots == 0 then
        section.body:SetText(slots and L["No required materials listed."] or L["Materials are unavailable. Check with the crafter."])
        return
    end
    local level = market.supplyLevel(order, slots)
    local summary = UI.supplyText(level)
    if order.ext then
        local states = { [0] = L["Not yet confirmed by the crafter"], L["Partly received"], L["Received completely"] }
        if market.needsMaterials(order) then summary = summary .. "  ·  " .. states[order.matState or 0] end
        if order.missing then summary = summary .. "\n|cffff7a5c" .. L["The crafter reported missing materials."] .. "|r" end
    end
    section.body:SetText(summary)
    local y = 0
    for index, slot in ipairs(slots) do
        local row = rowFor(index)
        local item = slot.items[1]
        local needed = slot.count * order.quantity
        local provided = order.provided and order.provided[item] or (order.supplies and not order.provided and needed) or 0
        if not order.ext and not order.provided then provided = nil end
        row.itemID = item
        row.icon:SetTexture(ctx.itemIcon(item))
        local name = ctx.itemName(item)
        if #slot.items > 1 then name = name .. " " .. L["(or alternative)"] end
        local detail = provided and ("  |cffbfb29a" .. L["requester %d · crafter %d"]:format(provided, math.max(0, needed - provided)) .. "|r") or ""
        row.label:SetText(("%d × %s%s"):format(needed, name, detail))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", section.body, "BOTTOMLEFT", 0, -6 - y)
        row:SetPoint("RIGHT", section.box, "RIGHT", -10, 0)
        row:Show()
        y = y + 20
    end
    section.extra = y + 4
end

-- Action bar: fitted buttons that wrap into a second row when needed.
function UI.actionBar(parent, ctx)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(32)
    local pool = {}
    function bar.set(actions)
        for _, control in ipairs(pool) do control:Hide() end
        local width = bar:GetWidth()
        local x, y = 0, 0
        for index = #actions, 1, -1 do
            local action = actions[index]
            local control = pool[index]
            if not control then
                control = fittedButton(ctx, bar, "", function(self) if self.action and self.action.run then self.action.run() end end, 70)
                control:SetScript("OnEnter", function(self)
                    local tip = self.action and self.action.tip
                    if not tip then return end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(self.action.label)
                    GameTooltip:AddLine(tip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                control:SetScript("OnLeave", function() GameTooltip:Hide() end)
                pool[index] = control
            end
            control.action = action
            control:Resize(action.label)
            control:SetEnabled(not action.disabled)
            if control:GetWidth() + x > width and x > 0 then x, y = 0, y + 28 end
            control:ClearAllPoints()
            control:SetPoint("BOTTOMRIGHT", -x, y)
            control:Show()
            x = x + control:GetWidth() + 6
        end
        bar:SetHeight(#actions > 0 and (y + 26) or 1)
    end
    return bar
end

-- Order dialog -----------------------------------------------------------------------------------------
local dialog

local function section(parent, ctx, title)
    local box = ctx.contrastPanel(parent)
    local label = text(box, "GameFontNormal")
    label:SetPoint("TOPLEFT", 10, -8)
    label:SetText(title)
    box.title = label
    return box
end

local function smallLabel(parent, value, font)
    local label = text(parent, font or "GameFontHighlightSmall")
    label:SetText(value or "")
    return label
end

local function buildDialog(ctx)
    local frame = CreateFrame("Frame", "ForeverGuildOrderWindow", UIParent, "PortraitFrameTemplate")
    dialog = frame
    local screenHeight = UIParent:GetHeight() or 768
    frame:SetSize(640, math.max(420, math.min(680, screenHeight - 70)))
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetPortraitToAsset(ctx.icon)
    frame:SetTitle(L["ForeverGuild · Crafting order"])
    table.insert(UISpecialFrames, "ForeverGuildOrderWindow")
    local body = ctx.panel(frame)
    body:SetPoint("TOPLEFT", 12, -45)
    body:SetPoint("BOTTOMRIGHT", -12, 13)
    ctx.pageBackdrop(body, "GuildAdministration", 1.5, .88)

    local footer = ctx.contrastPanel(body)
    footer:SetPoint("BOTTOMLEFT", 8, 8)
    footer:SetPoint("BOTTOMRIGHT", -8, 8)
    footer:SetHeight(58)
    frame.summary = text(footer, "GameFontHighlightSmall", "LEFT", true)
    frame.summary:SetPoint("TOPLEFT", 12, -9)
    frame.summary:SetPoint("BOTTOMRIGHT", -200, 8)
    frame.submit = fittedButton(ctx, footer, L["Send order"], function() UI.submitDialog(ctx) end, 170)
    frame.submit:ClearAllPoints()
    frame.submit:SetPoint("RIGHT", -12, 0)

    local scroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -24, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 10)
    scroll:SetScrollChild(content)
    frame.scroll, frame.content = scroll, content
    local function changed() UI.updateDialog(ctx) end
    frame.changed = changed

    -- 1 Item and recipe
    local hero = section(content, ctx, L["Item and recipe"])
    hero:SetHeight(82)
    hero:EnableMouse(true)
    hero:SetScript("OnEnter", function(self)
        if frame.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. frame.itemID)
            GameTooltip:Show()
        else
            self.entry = { recipe = frame.recipe }
            ctx.recipeTooltip(self)
        end
    end)
    hero:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.icon = hero:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(40, 40)
    frame.icon:SetPoint("TOPLEFT", 12, -30)
    frame.icon:SetTexCoord(.06, .94, .06, .94)
    frame.name = text(hero, "GameFontNormalLarge")
    frame.name:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, 0)
    frame.name:SetPoint("RIGHT", -12, 0)
    frame.recipeInfo = text(hero, "GameFontHighlightSmall")
    frame.recipeInfo:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -5)
    frame.recipeInfo:SetPoint("RIGHT", -12, 0)

    -- 2 Order type and crafter
    local kind = section(content, ctx, L["Order type and crafter"])
    kind:SetHeight(92)
    frame.directButton = fittedButton(ctx, kind, L["Direct order"], function() frame.public = false; changed() end, 150)
    frame.directButton:ClearAllPoints()
    frame.directButton:SetPoint("TOPLEFT", 12, -30)
    frame.publicButton = fittedButton(ctx, kind, L["Bulletin board"], function() frame.public = true; changed() end, 150)
    frame.publicButton:ClearAllPoints()
    frame.publicButton:SetPoint("LEFT", frame.directButton, "RIGHT", 6, 0)
    frame.crafterDrop = widgets().dropdown(kind, 250, function()
        local options = {}
        for _, crafter in ipairs(frame.crafters or {}) do options[#options + 1] = { crafter.name, crafter.label } end
        if #options == 0 then options[1] = { "", L["No crafter found"] } end
        return options
    end, function() return frame.crafter or "" end, function(value)
        if value ~= "" then frame.crafter = value end
        changed()
    end)
    frame.crafterDrop:SetPoint("TOPLEFT", 14, -60)
    frame.kindHint = text(kind, "GameFontHighlightSmall", "LEFT", true)
    frame.kindHint:SetPoint("TOPLEFT", 280, -62)
    frame.kindHint:SetPoint("RIGHT", -12, 0)

    -- 3 Quantity
    local amount = section(content, ctx, L["Number of crafts"])
    amount:SetHeight(58)
    frame.quantity = CreateFrame("EditBox", nil, amount, "InputBoxTemplate")
    frame.quantity:SetSize(46, 20)
    frame.quantity:SetPoint("TOPLEFT", 18, -30)
    frame.quantity:SetAutoFocus(false)
    frame.quantity:SetNumeric(true)
    frame.quantity:SetMaxLetters(3)
    frame.quantity:SetScript("OnEscapePressed", frame.quantity.ClearFocus)
    frame.quantity:SetScript("OnTextChanged", function(_, user) if user then UI.resetProvision(frame); changed() end end)
    local quantityHint = smallLabel(amount, L["Crafts (1–200). The amount of items per craft is defined by the recipe."])
    quantityHint:SetPoint("LEFT", frame.quantity, "RIGHT", 12, 0)
    quantityHint:SetPoint("RIGHT", -12, 0)
    quantityHint:SetWordWrap(true)

    -- 4 Materials
    local materials = section(content, ctx, L["Required materials"])
    frame.materials = materials
    frame.allButton = fittedButton(ctx, materials, L["I provide all"], function() UI.provideAll(frame, true); changed() end, 90)
    frame.noneButton = fittedButton(ctx, materials, L["I provide none"], function() UI.provideAll(frame, false); changed() end, 90)
    frame.noneButton:ClearAllPoints()
    frame.noneButton:SetPoint("TOPRIGHT", -10, -5)
    frame.allButton:ClearAllPoints()
    frame.allButton:SetPoint("RIGHT", frame.noneButton, "LEFT", -6, 0)
    local headers = { { L["Material"], 34 }, { L["Needed"], 300 }, { L["I provide"], 370 }, { L["Crafter provides"], 450 } }
    for _, header in ipairs(headers) do
        local label = smallLabel(materials, header[1], "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", header[2], -34)
    end
    frame.materialRows = {}
    frame.materialHint = text(materials, "GameFontHighlightSmall", "LEFT", true)
    frame.materialHint:SetPoint("RIGHT", -12, 0)

    -- 5 Payment
    local pay = section(content, ctx, L["Tip and crafting fee"])
    pay:SetHeight(176)
    frame.payDrop = widgets().dropdown(pay, 200, function()
        local options = {}
        for index, entry in ipairs(PAY_KINDS) do options[index] = { entry[1], L[entry[2]] } end
        return options
    end, function() return frame.pay end, function(value) frame.pay = value; changed() end)
    frame.payDrop:SetPoint("TOPLEFT", 14, -30)
    frame.tipBox = moneyBoxes(pay, changed)
    frame.tipBox:SetPoint("TOPLEFT", 222, -31)
    frame.totalMode = fittedButton(ctx, pay, L["For the whole order"], function() frame.tipEach = false; changed() end, 120)
    frame.totalMode:ClearAllPoints()
    frame.totalMode:SetPoint("TOPLEFT", 14, -62)
    frame.eachMode = fittedButton(ctx, pay, L["Per craft"], function() frame.tipEach = true; changed() end, 120)
    frame.eachMode:ClearAllPoints()
    frame.eachMode:SetPoint("LEFT", frame.totalMode, "RIGHT", 6, 0)
    local costLabel = smallLabel(pay, L["Material reimbursement"], "GameFontNormalSmall")
    costLabel:SetPoint("TOPLEFT", 16, -98)
    frame.costBox = moneyBoxes(pay, changed)
    frame.costBox:SetPoint("TOPLEFT", 222, -94)
    frame.payTotal = text(pay, "GameFontNormal", "LEFT")
    frame.payTotal:SetPoint("TOPLEFT", 16, -124)
    frame.payTotal:SetPoint("RIGHT", -12, 0)
    local escrow = smallLabel(pay, L["Paid by the players at handoff. ForeverGuild does not hold or guarantee any gold."])
    escrow:SetPoint("TOPLEFT", 16, -144)
    escrow:SetPoint("RIGHT", -12, 0)
    escrow:SetWordWrap(true)
    color(escrow, MUTED)

    -- 6 Handoff
    local handoff = section(content, ctx, L["Handoff method"])
    handoff:SetHeight(66)
    frame.methodDrop = widgets().dropdown(handoff, 200, function()
        local options = {}
        for index, label in ipairs(METHOD_LABELS) do options[index] = { index, L[label] } end
        return options
    end, function() return frame.method end, function(value) frame.method = value; changed() end)
    frame.methodDrop:SetPoint("TOPLEFT", 14, -30)
    frame.methodHint = text(handoff, "GameFontHighlightSmall", "LEFT", true)
    frame.methodHint:SetPoint("TOPLEFT", 228, -30)
    frame.methodHint:SetPoint("RIGHT", -12, 0)

    -- 7 Message
    local message = section(content, ctx, L["Additional message"])
    message:SetHeight(58)
    frame.note = CreateFrame("EditBox", nil, message, "InputBoxTemplate")
    frame.note:SetPoint("TOPLEFT", 18, -30)
    frame.note:SetPoint("RIGHT", -14, 0)
    frame.note:SetHeight(20)
    frame.note:SetAutoFocus(false)
    frame.note:SetMaxBytes(68)
    frame.note:SetScript("OnEscapePressed", frame.note.ClearFocus)

    -- 8 Duration and deadline
    local timing = section(content, ctx, L["Duration and confirmation"])
    timing:SetHeight(62)
    local daysLabel = smallLabel(timing, L["Posting open for (days, 1–30)"], "GameFontNormalSmall")
    daysLabel:SetPoint("TOPLEFT", 16, -36)
    frame.days = CreateFrame("EditBox", nil, timing, "InputBoxTemplate")
    frame.days:SetSize(34, 20)
    frame.days:SetPoint("LEFT", daysLabel, "RIGHT", 10, 0)
    frame.days:SetNumeric(true)
    frame.days:SetMaxLetters(2)
    frame.days:SetAutoFocus(false)
    frame.days:SetScript("OnTextChanged", function(_, user) if user then changed() end end)
    local dueLabel = smallLabel(timing, L["Completion deadline (days, 0 = none)"], "GameFontNormalSmall")
    dueLabel:SetPoint("LEFT", frame.days, "RIGHT", 22, 0)
    frame.dueDays = CreateFrame("EditBox", nil, timing, "InputBoxTemplate")
    frame.dueDays:SetSize(34, 20)
    frame.dueDays:SetPoint("LEFT", dueLabel, "RIGHT", 10, 0)
    frame.dueDays:SetNumeric(true)
    frame.dueDays:SetMaxLetters(2)
    frame.dueDays:SetAutoFocus(false)
    frame.dueDays:SetScript("OnTextChanged", function(_, user) if user then changed() end end)

    frame.blocks = { hero, kind, amount, materials, pay, handoff, message, timing }
    scroll:HookScript("OnSizeChanged", function(_, width)
        if width and width > 0 then content:SetWidth(width) end
        UI.layoutDialog(frame)
    end)
    frame:SetScript("OnHide", function() frame.order = nil end)
    return frame
end

function UI.layoutDialog(frame)
    local y = 0
    for _, block in ipairs(frame.blocks) do
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", 0, y)
        block:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
        y = y - block:GetHeight() - 6
    end
    frame.content:SetHeight(-y)
end

function UI.resetProvision(frame)
    local quantity = tonumber(frame.quantity:GetText()) or 1
    for _, row in ipairs(frame.materialRows) do
        if row:IsShown() and row.slot then
            local needed = row.slot.count * math.max(1, math.min(200, quantity))
            local value = tonumber(row.box:GetText()) or 0
            if frame.provideMode == "all" or value > needed then row.box:SetText(tostring(needed)) end
        end
    end
end

function UI.provideAll(frame, all)
    frame.provideMode = all and "all" or "none"
    local quantity = math.max(1, math.min(200, tonumber(frame.quantity:GetText()) or 1))
    for _, row in ipairs(frame.materialRows) do
        if row.slot then row.box:SetText(all and tostring(row.slot.count * quantity) or "0") end
    end
end

local function materialRow(frame, ctx, index)
    local row = frame.materialRows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, frame.materials)
    row:SetHeight(22)
    local iconButton = CreateFrame("Button", nil, row)
    iconButton:SetSize(18, 18)
    iconButton:SetPoint("LEFT", 12, 0)
    row.icon = iconButton:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints()
    row.icon:SetTexCoord(.06, .94, .06, .94)
    iconButton:SetScript("OnEnter", function(self)
        if not row.slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. row.slot.items[1])
        if #row.slot.items > 1 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Alternatives:"], 1, .82, 0)
            for alt = 2, #row.slot.items do GameTooltip:AddLine(ctx.itemName(row.slot.items[alt]), 1, 1, 1) end
        end
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.name = text(row, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 34, 0)
    row.name:SetWidth(258)
    row.needed = text(row, "GameFontHighlightSmall", "RIGHT")
    row.needed:SetPoint("LEFT", 300, 0)
    row.needed:SetWidth(40)
    row.box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.box:SetSize(44, 18)
    row.box:SetPoint("LEFT", 376, 0)
    row.box:SetAutoFocus(false)
    row.box:SetNumeric(true)
    row.box:SetMaxLetters(5)
    row.box:SetScript("OnEscapePressed", row.box.ClearFocus)
    row.box:SetScript("OnTextChanged", function(_, user)
        if user then frame.provideMode = nil; frame.changed() end
    end)
    row.crafter = text(row, "GameFontHighlightSmall", "RIGHT")
    row.crafter:SetPoint("LEFT", 450, 0)
    row.crafter:SetWidth(40)
    frame.materialRows[index] = row
    return row
end

function UI.updateDialog(ctx)
    local frame = dialog
    if not frame or not frame.recipe then return end
    local quantity = tonumber(frame.quantity:GetText())
    local validQuantity = quantity and quantity >= 1 and quantity <= 200
    local count = validQuantity and quantity or 1
    local editing = frame.order ~= nil
    -- Type and crafter
    frame.directButton:SetEnabled(frame.public and not editing and #frame.crafters > 0)
    frame.publicButton:SetEnabled(not frame.public and not editing and ctx.canPost())
    frame.crafterDrop:SetShown(not frame.public)
    if not frame.public and frame.crafterDrop.Sync then frame.crafterDrop.Sync() end
    local legacyTarget = not frame.public and frame.crafter and not ctx.supportsMarket(frame.crafter)
    frame.legacyTarget = legacyTarget
    if frame.public then
        frame.kindHint:ClearAllPoints()
        frame.kindHint:SetPoint("TOPLEFT", 14, -62)
        frame.kindHint:SetPoint("RIGHT", -12, 0)
        frame.kindHint:SetText(L["Open to every crafter of the guild who knows the recipe."])
    else
        frame.kindHint:ClearAllPoints()
        frame.kindHint:SetPoint("TOPLEFT", 280, -58)
        frame.kindHint:SetPoint("RIGHT", -12, 0)
        if #frame.crafters == 0 then
            frame.kindHint:SetText(L["No guild member is known to craft this recipe. Post it on the bulletin board instead."])
        elseif legacyTarget then
            frame.kindHint:SetText("|cffffc060" .. L["This crafter uses an older or unknown ForeverGuild version: only recipe and quantity are sent; the order is queued while offline."] .. "|r")
        else
            frame.kindHint:SetText(ctx.isOnline(frame.crafter) and L["Crafter is online."] or L["Crafter is offline. The order arrives when you are both online."])
        end
    end
    -- Materials
    local slots = ctx.materials(frame.recipe)
    local rowCount = slots and #slots or 0
    for index = 1, rowCount do
        local slot = slots[index]
        local row = materialRow(frame, ctx, index)
        local fresh = row.slot == nil or row.slot.items[1] ~= slot.items[1]
        row.slot = slot
        row.icon:SetTexture(ctx.itemIcon(slot.items[1]))
        local name = ctx.itemName(slot.items[1])
        if #slot.items > 1 then name = name .. " " .. L["(or alternative)"] end
        row.name:SetText(name)
        local needed = slot.count * count
        row.needed:SetText(tostring(needed))
        if fresh and row.box:GetText() == "" then row.box:SetText(tostring(needed)) end
        local provided = math.min(needed, tonumber(row.box:GetText()) or 0)
        row.crafter:SetText(tostring(needed - provided))
        color(row.crafter, needed - provided > 0 and GOLD or MUTED)
        row.box:SetEnabled(not legacyTarget)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -50 - (index - 1) * 24)
        row:SetPoint("RIGHT", frame.materials, "RIGHT", 0, 0)
        row:Show()
    end
    for index = rowCount + 1, #frame.materialRows do frame.materialRows[index]:Hide(); frame.materialRows[index].slot = nil end
    frame.allButton:SetShown(rowCount > 0 and not legacyTarget)
    frame.noneButton:SetShown(rowCount > 0 and not legacyTarget)
    frame.materialHint:ClearAllPoints()
    frame.materialHint:SetPoint("TOPLEFT", 14, -52 - rowCount * 24)
    frame.materialHint:SetPoint("RIGHT", -12, 0)
    if not slots then
        frame.materialHint:SetText(L["Materials are unavailable. Check with the crafter."])
    elseif rowCount == 0 then
        frame.materialHint:SetText(L["No required materials listed."])
    else
        frame.materialHint:SetText(L["Enter how many of each material you hand over. The crafter brings the rest."])
    end
    frame.materials:SetHeight(76 + rowCount * 24 + math.ceil(frame.materialHint:GetStringHeight()))
    -- Payment
    local payEnabled = frame.pay ~= "n" and not legacyTarget
    frame.tipBox:SetEnabled(payEnabled)
    frame.totalMode:SetEnabled(payEnabled and frame.tipEach)
    frame.eachMode:SetEnabled(payEnabled and not frame.tipEach)
    frame.costBox:SetEnabled(not legacyTarget)
    frame.payDrop:SetEnabled(not legacyTarget)
    local tip = payEnabled and frame.tipBox.Get() or 0
    local cost = frame.costBox.Get()
    local tipTotal = tip and (frame.tipEach and tip * count or tip)
    if tipTotal and cost then
        frame.payTotal:SetText(L["Crafting fee %s  ·  Materials %s  ·  Total %s"]:format(market.money(tipTotal),
            market.money(cost), "|cffffd100" .. market.money(tipTotal + cost) .. "|r"))
    else
        frame.payTotal:SetText("|cffff7a5c" .. L["Invalid amount."] .. "|r")
    end
    -- Handoff hint
    local orderable, tradeStatus = UI.orderable(ctx, frame.recipe, frame.professionID)
    frame.orderable, frame.tradeStatus = orderable, tradeStatus
    local methodHints = { L["Items and payment are exchanged in a trade window."], L["The crafter sends the items by mail."],
        L["Sent by mail with cash on delivery when the mailbox offers it."], L["Agree on the handoff by whisper."] }
    local hint = methodHints[frame.method] or ""
    if not orderable then hint = "|cffff7a5c" .. UI.unorderableText(tradeStatus) .. "|r" end
    frame.methodHint:SetText(hint)
    frame.methodDrop:SetEnabled(not legacyTarget)
    frame.note:SetEnabled(not legacyTarget)
    -- Validation and summary
    local days, dueDays = tonumber(frame.days:GetText()), tonumber(frame.dueDays:GetText() ~= "" and frame.dueDays:GetText() or "0")
    local valid = validQuantity and tipTotal ~= nil and cost ~= nil and days and days >= 1 and days <= 30 and dueDays and dueDays <= 30
    if not frame.public and not frame.crafter then valid = false end
    for index = 1, rowCount do
        local row = frame.materialRows[index]
        if (tonumber(row.box:GetText()) or 0) > row.slot.count * count then valid = false end
    end
    if not editing and not ctx.ready() then valid = false end
    if not frame.orderable then valid = false end
    if frame.public and not ctx.canPost() then valid = false end
    frame.valid = valid
    frame.submit:SetEnabled(valid and true or false)
    frame.submit:Resize(editing and L["Save changes"] or (frame.public and L["Post on the bulletin board"] or L["Send order"]))
    local summary
    if not frame.orderable then
        summary = "|cffff7a5c" .. UI.unorderableText(frame.tradeStatus) .. "|r"
    elseif not ctx.ready() then
        summary = L["The addon channel is not available yet. Please try again shortly."]
    elseif frame.public and not ctx.canPost() then
        summary = L["You may not post orders on the bulletin board."]
    elseif not validQuantity then
        summary = L["Enter 1–200 crafts."]
    elseif not valid then
        summary = L["Please check the highlighted entries."]
    else
        summary = L["%d crafts · payment %s · handoff: %s"]:format(count, market.money((tipTotal or 0) + (cost or 0)),
            L[METHOD_LABELS[frame.method] or "Custom arrangement"])
    end
    frame.summary:SetText(summary)
    UI.layoutDialog(frame)
end

function UI.submitDialog(ctx)
    local frame = dialog
    UI.updateDialog(ctx)
    -- Checked again right before sending: old dialogs or links cannot order bound items.
    if not frame.valid or not UI.orderable(ctx, frame.recipe, frame.professionID) then return end
    local count = tonumber(frame.quantity:GetText())
    local provided, all = {}, true
    for _, row in ipairs(frame.materialRows) do
        if row:IsShown() and row.slot then
            local value = tonumber(row.box:GetText()) or 0
            if value > 0 then provided[row.slot.items[1]] = value end
            if value < row.slot.count * count then all = false end
        end
    end
    local tip = frame.pay ~= "n" and frame.tipBox.Get() or 0
    local fields = { recipe = frame.recipe, quantity = count, note = frame.note:GetText(), days = tonumber(frame.days:GetText()),
        direct = not frame.public, crafter = not frame.public and frame.crafter or nil, tip = tip, tipEach = frame.tipEach and tip > 0,
        pay = tip > 0 and frame.pay or "n", cost = frame.costBox.Get(), provided = provided, method = frame.method,
        dueDays = tonumber(frame.dueDays:GetText()) or 0, supplies = all and next(provided) ~= nil }
    frame.note:ClearFocus()
    if frame.order then
        if ctx.editOrder(frame.order, fields) then frame:Hide() end
        return
    end
    if not frame.public and frame.legacyTarget then
        ctx.legacySend(frame.crafter, frame.recipe, count, frame.professionID)
        frame:Hide()
        ctx.openTab("mine")
        return
    end
    local order = ctx.create(fields)
    if order then
        frame:Hide()
        ctx.openOrder(ctx.key(order))
    end
end

-- opts: recipe, crafter, professionID, public, order (edit), copy (reorder)
function UI.openDialog(ctx, opts)
    if ctx.inCombat() then return dialog end
    local frame = dialog or buildDialog(ctx)
    local source = opts.order or opts.copy
    frame.recipe = opts.recipe or (source and source.recipe)
    frame.professionID = opts.professionID
    frame.order = opts.order
    frame.crafters = ctx.crafters(frame.recipe, opts.professionID)
    local preset = opts.crafter or (source and source.direct and source.crafter)
    frame.public = opts.public or (source and not source.direct) or false
    if not preset and not frame.public and #frame.crafters == 0 then frame.public = true end
    frame.crafter = nil
    for _, crafter in ipairs(frame.crafters) do
        if preset and ctx.normalize(crafter.name) == ctx.normalize(preset) then frame.crafter = crafter.name end
    end
    if preset and not frame.crafter and not ctx.same(preset) then
        table.insert(frame.crafters, 1, { name = preset, label = ctx.displayName(preset) })
        frame.crafter = preset
    end
    if not frame.crafter and frame.crafters[1] then frame.crafter = frame.crafters[1].name end
    local recipe = ctx.describe({ recipe = frame.recipe, professionID = opts.professionID })
    frame.itemID = recipe.itemID
    frame.icon:SetTexture(recipe.icon)
    frame.name:SetText(recipe.name)
    color(frame.name, recipe.color and { recipe.color.r, recipe.color.g, recipe.color.b } or GOLD)
    local info = { recipe.profession or "–" }
    if recipe.rarity then info[#info + 1] = recipe.rarity end
    local skill = ctx.skill(frame.recipe)
    if skill then info[#info + 1] = L["Skill %d"]:format(skill) end
    if ctx.recipeName(frame.recipe) ~= recipe.name then info[#info + 1] = L["Recipe: %s"]:format(ctx.recipeName(frame.recipe)) end
    frame.recipeInfo:SetText(table.concat(info, "  ·  "))
    frame.quantity:SetText(tostring(source and source.quantity or 1))
    frame.pay = source and source.ext and source.pay or "n"
    frame.tipEach = source and source.tipEach or false
    frame.tipBox:Set(source and source.tip or 0)
    frame.costBox:Set(source and source.cost or 0)
    frame.method = source and source.method or market.setting("method") or 1
    frame.note:SetText(source and source.note or "")
    local now = ctx.clock()
    local days = opts.order and opts.order.expiresAt and math.max(1, math.min(30, math.ceil((opts.order.expiresAt - now) / DAY)))
    frame.days:SetText(tostring(days or market.setting("days") or 7))
    frame.dueDays:SetText(tostring(source and source.dueDays or 0))
    frame.provideMode = nil
    for _, row in ipairs(frame.materialRows) do row.slot = nil; row.box:SetText("") end
    UI.updateDialog(ctx)
    if source and source.provided then
        for _, row in ipairs(frame.materialRows) do
            if row.slot then row.box:SetText(tostring(source.provided[row.slot.items[1]] or 0)) end
        end
    end
    frame:SetTitle(opts.order and L["ForeverGuild · Edit crafting order"] or L["ForeverGuild · Crafting order"])
    UI.updateDialog(ctx)
    frame.scroll:SetVerticalScroll(0)
    frame.crafterDrop.Sync()
    frame.payDrop.Sync()
    frame.methodDrop.Sync()
    frame:Show()
    return frame
end

-- Personal order management ----------------------------------------------------------------------------
local TABS = {
    { "incoming", "Incoming orders" }, { "accepted", "My accepted orders" }, { "mine", "My orders" },
    { "handoff", "Ready for handoff" }, { "history", "History" },
}

function UI.legacyStatus(legacy)
    if legacy.done or legacy.completed then return L["Completed"] end
    if legacy.withdrawn then return L["Withdrawn"] end
    if legacy.outgoing then
        return legacy.delivery == "confirmed" and L["Delivered"] or L["Waiting for recipient"]
    end
    return L["Open"]
end

-- All orders of the current player: shared records where the player takes part (or has a
-- pending claim) and direct orders of older versions. Archived ones only show in History.
function UI.entries(ctx)
    local now, list, guild = ctx.clock(), {}, ctx.guild()
    for key, order in pairs(addon.board.records(guild)) do
        local role = roleOf(order, ctx)
        if not role and order.intent then role = "p" end
        if role and not ctx.hidden(order) then
            list[#list + 1] = { key = key, order = order, role = role, state = market.state(order, now),
                archived = market.isArchived(guild, key), pending = order.intent ~= nil }
        end
    end
    for key, order in pairs(ctx.legacyOrders() or {}) do
        if ctx.belongs(order) and not market.isRemoved(guild, key) then
            -- Read-only view with the key; the saved record itself stays unchanged.
            local view = setmetatable({ key = key }, { __index = order })
            local finished = order.done or order.completed or order.withdrawn
            list[#list + 1] = { key = key, legacy = view, role = order.outgoing and "o" or "c",
                state = finished and "D" or "W", archived = market.isArchived(guild, key) }
        end
    end
    return list
end

function UI.inTab(entry, tab)
    local state, role = entry.state, entry.role
    if entry.archived then return tab == "history" end
    if entry.legacy then
        if tab == "history" then return state == "D" end
        if state == "D" then return false end
        return (tab == "incoming" and role == "c") or (tab == "mine" and role == "o")
    end
    if entry.pending and role == "p" then return tab == "accepted" end
    local closed = market.closed[state]
    if tab == "history" then return closed end
    if closed and not (role == "o" and (state == "E" or state == "J")) then return false end
    if tab == "incoming" then return role == "c" and state == "Q" end
    if tab == "accepted" then return role == "c" and market.accepted[state] end
    if tab == "mine" then return role == "o" end
    if tab == "handoff" then return state == "R" or state == "H" end
end

function UI.buildManager(window, ctx)
    local page = ctx.panel(window, 0)
    window.orders = page
    page:SetPoint("TOPLEFT", 14, -46)
    page:SetPoint("BOTTOMRIGHT", -14, 13)
    ctx.pageBackdrop(page, "GuildAdministration", 1.5, .88)
    local title = text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetText(L["Crafting orders"])
    local counters = text(page, "GameFontHighlightSmall")
    counters:SetPoint("LEFT", title, "RIGHT", 22, 0)
    local state = { tab = "incoming", selection = nil, explicit = false }
    local tabButtons = {}
    local previous
    for _, entry in ipairs(TABS) do
        local key = entry[1]
        local control = fittedButton(ctx, page, L[entry[2]], function()
            state.tab, state.selection, state.explicit = key, nil, true
            window.refreshOrders()
        end, 110)
        control:ClearAllPoints()
        if previous then control:SetPoint("LEFT", previous, "RIGHT", 4, 0) else control:SetPoint("TOPLEFT", 17, -40) end
        previous = control
        control.key = key
        tabButtons[#tabButtons + 1] = control
    end
    local notesButton = fittedButton(ctx, page, L["Notifications"], function() UI.showNotes(ctx) end, 120)
    notesButton:ClearAllPoints()
    notesButton:SetPoint("TOPRIGHT", -17, -10)

    local left = ctx.contrastPanel(page)
    left:SetPoint("TOPLEFT", 17, -72)
    left:SetPoint("BOTTOMLEFT", 17, 17)
    left:SetWidth(392)
    window.orderCards = left
    local right = ctx.contrastPanel(page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -17, 17)
    local empty = text(left, "GameFontDisable", "CENTER", true)
    empty:SetPoint("TOPLEFT", 16, -30)
    empty:SetPoint("RIGHT", -16, 0)

    local detail = UI.detail(right, ctx)
    local actions = UI.actionBar(right, ctx)
    actions:SetPoint("BOTTOMLEFT", 10, 10)
    actions:SetPoint("BOTTOMRIGHT", -10, 10)
    detail.scroll:SetPoint("TOPLEFT", 8, -8)
    detail.scroll:SetPoint("BOTTOMRIGHT", actions, "TOPRIGHT", -20, 6)

    local cards = widgets().virtualList(left, 64, function(parent)
        return UI.card(parent, ctx, function(row)
            state.selection = row.entry.key
            if row.entry.legacy then ctx.legacyRead(row.entry.key) end
            if market.markRead(ctx.guild(), row.entry.key) then ctx.updateNotice() end
            window.refreshOrders()
        end)
    end, function(row, entry) UI.fillCard(row, entry, ctx, entry.key == state.selection) end)
    cards.scroll:SetPoint("TOPLEFT", 6, -6)
    cards.scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    window.refreshOrders = function()
        local now = ctx.clock()
        local all = UI.entries(ctx)
        local counts = UI.counts(ctx, all, now)
        local function counter(label, value, highlight)
            local tint = value > 0 and highlight and "|cffffd100" or "|cffbfb29a"
            return ("%s%s: %d|r"):format(tint, label, value)
        end
        counters:SetText(counter(L["New requests"], counts.incoming, true) .. "     " .. counter(L["In progress"], counts.accepted)
            .. "     " .. counter(L["Handoffs"], counts.handoff, true) .. "     " .. counter(L["Awaiting confirmation"], counts.pending)
            .. "     " .. counter(L["Action needed"], counts.action, true))
        local unread = market.unread(ctx.guild())
        notesButton:Resize(unread > 0 and L["Notifications (%d)"]:format(unread) or L["Notifications"])
        local visible = {}
        for _, entry in ipairs(all) do
            if UI.inTab(entry, state.tab) then visible[#visible + 1] = entry end
        end
        table.sort(visible, function(a, b)
            if (a.action and 1 or 0) ~= (b.action and 1 or 0) then return a.action and true or false end
            local first = a.order and (tonumber(a.order.token:match("^%d+")) or 0) or a.legacy.received or 0
            local second = b.order and (tonumber(b.order.token:match("^%d+")) or 0) or b.legacy.received or 0
            if first == second then return a.key > b.key end
            return first > second
        end)
        local selected
        for _, entry in ipairs(visible) do if entry.key == state.selection then selected = entry end end
        if not selected then
            selected = visible[1]
            state.selection = selected and selected.key
        end
        for index, control in ipairs(tabButtons) do
            local count = 0
            for _, entry in ipairs(all) do if UI.inTab(entry, control.key) and (entry.action or (control.key == "incoming")) then count = count + 1 end end
            local caption = L[TABS[index][2]]
            if count > 0 and control.key ~= "history" then caption = caption .. (" |cffffd100(%d)|r"):format(count) end
            control:Resize(caption)
            control:SetEnabled(control.key ~= state.tab)
        end
        empty:SetText(#visible == 0 and L["No orders in this view."] or "")
        cards.set(visible)
        detail.set(selected and selected.order, selected and selected.legacy)
        actions.set(UI.actions(ctx, selected and selected.order, now, selected and selected.legacy))
        if selected and market.markRead(ctx.guild(), selected.key) then ctx.updateNotice() end
        UI.updateBadge(window, ctx)
    end
    window.selectOrder = function(key)
        local all = UI.entries(ctx)
        for _, entry in ipairs(all) do
            if entry.key == key then
                for _, tab in ipairs({ "incoming", "accepted", "handoff", "mine", "history" }) do
                    if UI.inTab(entry, tab) then state.tab = tab; break end
                end
            end
        end
        state.selection = key
    end
    window.openUnreadOrders = function()
        local notes = market.notes(ctx.guild())
        local newest
        for _, entry in ipairs(notes) do if not entry.read and entry.key then newest = entry.key; break end end
        if newest then
            window.selectOrder(newest)
        else
            local _, legacyNewest = addon.orders.unread(ctx.guild())
            if legacyNewest then window.selectOrder(legacyNewest); ctx.legacyRead(legacyNewest) end
        end
        ctx.openTab(nil)
    end
    window.setOrderTab = function(tab)
        if tab then state.tab, state.selection = tab, nil end
    end
    return page
end

-- Counters from the real order data. Each order counts once per counter; a pending claim
-- is neither "in progress" nor a handoff until the requester's client confirms it.
function UI.counts(ctx, all, now)
    all = all or UI.entries(ctx)
    now = now or ctx.clock()
    local counts = { incoming = 0, accepted = 0, handoff = 0, pending = 0, action = 0, keys = {} }
    for _, entry in ipairs(all) do
        if not entry.archived then
            local order = entry.order
            if entry.pending then
                counts.pending = counts.pending + 1
            elseif entry.legacy then
                if entry.role == "c" and entry.state ~= "D" then counts.incoming = counts.incoming + 1 end
            else
                if entry.role == "c" and entry.state == "Q" then counts.incoming = counts.incoming + 1 end
                if entry.role == "c" and (entry.state == "M" or entry.state == "W") then counts.accepted = counts.accepted + 1 end
                if entry.state == "R" or entry.state == "H" then counts.handoff = counts.handoff + 1 end
            end
            entry.action = order and not entry.pending and market.needsAction(order, entry.role == "o", entry.role == "c", now)
                or (entry.legacy and entry.legacy.unread == true and entry.state ~= "D") or false
            if entry.action then
                counts.action = counts.action + 1
                counts.keys[entry.key] = true
            end
        end
    end
    return counts
end

function UI.updateBadge(window, ctx)
    local tab = window and window.ordersTab
    if not tab then return end
    if not tab.marketBadge then
        local badge = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badge:SetPoint("TOPRIGHT", -2, -2)
        badge:SetTextColor(1, .82, .25)
        tab.marketBadge = badge
    end
    -- Unique orders that need an action or carry an unread notification; never counted twice.
    local count = 0
    if market.setting("counters") then
        local keys = UI.counts(ctx).keys
        for _, note in ipairs(market.notes(ctx.guild())) do
            if not note.read then keys[note.key or note.id] = true end
        end
        for _ in pairs(keys) do count = count + 1 end
    end
    tab.marketBadge:SetText(count > 99 and "99+" or tostring(count))
    tab.marketBadge:SetShown(count > 0)
end

-- Card for the order lists (manager and board share the layout).
function UI.card(parent, _, onClick, tall)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    row:SetBackdropColor(.10, .07, .045, .92)
    row:SetBackdropBorderColor(.45, .32, .17, .9)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 3, -3)
    highlight:SetPoint("BOTTOMRIGHT", -3, 3)
    highlight:SetColorTexture(.82, .53, .20, .12)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(34, 34)
    row.icon:SetPoint("TOPLEFT", 9, -9)
    row.icon:SetTexCoord(.06, .94, .06, .94)
    row.title = text(row, "GameFontNormal")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, 0)
    row.title:SetPoint("RIGHT", -112, 0)
    row.status = text(row, "GameFontNormalSmall", "RIGHT")
    row.status:SetPoint("TOPRIGHT", -10, -10)
    row.status:SetWidth(104)
    row.line2 = text(row, "GameFontHighlightSmall")
    row.line2:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.line2:SetPoint("RIGHT", -10, 0)
    row.line3 = text(row, "GameFontHighlightSmall")
    row.line3:SetPoint("TOPLEFT", row.line2, "BOTTOMLEFT", 0, -4)
    row.line3:SetPoint("RIGHT", -96, 0)
    row.right3 = text(row, "GameFontHighlightSmall", "RIGHT")
    row.right3:SetPoint("TOPRIGHT", row.status, "BOTTOMRIGHT", 0, -20)
    color(row.right3, { .85, .77, .63 })
    row.bar = progressBar(row, 80)
    row.bar.label:Hide()
    row.bar:SetHeight(5)
    row.bar:SetPoint("BOTTOMRIGHT", -12, 9)
    row.badge = text(row, "GameFontNormalLarge", "CENTER")
    row.badge:SetPoint("CENTER", row.icon, "TOPRIGHT", -1, -1)
    row.badge:SetText("!")
    color(row.badge, { 1, .82, .1 })
    if tall then
        row.line4 = text(row, "GameFontHighlightSmall")
        row.line4:SetPoint("TOPLEFT", row.line3, "BOTTOMLEFT", 0, -4)
        row.line4:SetPoint("RIGHT", -10, 0)
    end
    row:SetScript("OnClick", function(self) onClick(self) end)
    row:SetScript("OnEnter", function(self)
        local itemID = self.itemID
        if not itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function UI.fillCard(row, entry, ctx, selected)
    row.entry = entry
    local now = ctx.clock()
    local subject = entry.order or entry.legacy
    local recipe = ctx.describe(subject)
    row.itemID = recipe.itemID
    row.icon:SetTexture(recipe.icon)
    row.title:SetText(("%d × %s"):format(subject.quantity, recipe.name))
    color(row.title, recipe.color and { recipe.color.r, recipe.color.g, recipe.color.b } or GOLD)
    row:SetBackdropBorderColor(selected and .95 or .45, selected and .70 or .32, selected and .30 or .17, selected and 1 or .9)
    row:SetBackdropColor(selected and .20 or .10, selected and .13 or .07, selected and .07 or .045, .94)
    local unread = false
    for _, note in ipairs(market.notes(ctx.guild())) do
        if note.key == entry.key and not note.read then unread = true; break end
    end
    if entry.legacy then
        local legacy = entry.legacy
        local who = legacy.outgoing and legacy.recipient or legacy.sender
        row.status:SetText(UI.legacyStatus(legacy))
        color(row.status, entry.state == "D" and GREEN or GOLD)
        row.line2:SetText((legacy.outgoing and L["Crafter: %s"] or L["Requester: %s"]):format(ctx.displayName(who)))
        row.line3:SetText("|cff9b9389" .. L["Older ForeverGuild version"] .. (entry.archived and (" · " .. L["Archived"]) or "") .. "|r")
        row.right3:SetText(date("%d.%m.%y", legacy.received))
        row.bar:Hide()
        row.badge:SetShown(legacy.unread == true)
        return
    end
    local order = entry.order
    local label, tint = UI.stateText(order, now)
    row.status:SetText(label)
    color(row.status, tint)
    local role = entry.role or roleOf(order, ctx)
    local person
    if role == "o" then
        person = order.crafter and L["Crafter: %s"]:format(ctx.displayName(order.crafter)) or L["Open to the guild"]
    else
        person = L["Requester: %s"]:format(ctx.displayName(order.owner))
    end
    local online = (role == "o" and order.crafter) or (role ~= "o" and order.owner)
    if online and ctx.isOnline(online) then person = person .. "  |TInterface\\FriendsFrame\\StatusIcon-Online:12:12|t" end
    row.line2:SetText(person .. "   |cffbfb29a" .. (recipe.profession or "") .. "|r")
    local tip = UI.tipText(order)
    local payment = tip and (L["Payment: %s"]:format(tip))
        or ("|cff9b9389" .. (order.ext and L["No payment"] or L["Payment unknown"]) .. "|r")
    if entry.archived then payment = payment .. "   |cff9b9389" .. L["Archived"] .. "|r" end
    row.line3:SetText(payment)
    row.right3:SetText(UI.remainingText(order, now) or "")
    if market.accepted[order.state] or order.state == "D" then
        row.bar:Show()
        local handoff = order.state == "R" or order.state == "H" or order.state == "D"
        row.bar:Set(handoff and (order.delivered or 0) or (order.crafted or 0), order.quantity)
    else
        row.bar:Hide()
    end
    row.badge:SetShown(entry.action or unread)
    if not market.closed[order.state] and not UI.orderable(ctx, order.recipe) then
        row.line3:SetText(row.line3:GetText() .. "   |cffff7a5c" .. L["Cannot be handed over"] .. "|r")
    end
    if row.line4 then
        local slots = ctx.materials(order.recipe)
        local materials = L["Materials: %s"]:format(UI.supplyText(market.supplyLevel(order, slots)))
        if ctx.knows(order.recipe) and order.owner ~= ctx.player() then
            materials = materials .. "   |cff73dc73" .. L["You can craft this"] .. "|r"
        end
        row.line4:SetText(materials)
    end
end

-- Notification history ------------------------------------------------------------------------------------
local notesFrame
function UI.showNotes(ctx)
    if ctx.inCombat() then return end
    if not notesFrame then
        notesFrame = CreateFrame("Frame", "ForeverGuildMarketNotes", UIParent, "PortraitFrameTemplate")
        notesFrame:SetSize(520, 460)
        notesFrame:SetPoint("CENTER", 120, 0)
        notesFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        notesFrame:SetClampedToScreen(true)
        notesFrame:SetPortraitToAsset(ctx.icon)
        notesFrame:SetTitle(L["ForeverGuild · Notifications"])
        table.insert(UISpecialFrames, "ForeverGuildMarketNotes")
        local body = ctx.contrastPanel(notesFrame)
        body:SetPoint("TOPLEFT", 12, -45)
        body:SetPoint("BOTTOMRIGHT", -12, 44)
        notesFrame.list = widgets().virtualList(body, 46, function(parent)
            local row = CreateFrame("Button", nil, parent)
            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(.82, .53, .20, .12)
            row.dot = row:CreateTexture(nil, "ARTWORK")
            row.dot:SetSize(8, 8)
            row.dot:SetPoint("LEFT", 6, 6)
            row.dot:SetColorTexture(1, .82, .25, 1)
            row.title = text(row, "GameFontNormal")
            row.title:SetPoint("TOPLEFT", 20, -5)
            row.title:SetPoint("RIGHT", -90, 0)
            row.time = text(row, "GameFontHighlightSmall", "RIGHT")
            row.time:SetPoint("TOPRIGHT", -6, -6)
            row.detail = text(row, "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
            row.detail:SetPoint("RIGHT", -6, 0)
            row:SetScript("OnClick", function(self)
                local entry = self.entry
                entry.read = true
                ctx.updateNotice()
                if entry.key then
                    notesFrame:Hide()
                    ctx.openOrder(entry.key)
                else
                    UI.showNotes(ctx)
                end
            end)
            return row
        end, function(row, entry)
            row.entry = entry
            row.dot:SetShown(not entry.read)
            row.title:SetText(eventText({ code = entry.code, n = entry.n }, nil))
            color(row.title, entry.read and MUTED or GOLD)
            row.time:SetText(date("%d.%m. %H:%M", entry.at))
            row.detail:SetText((entry.item or "") .. (entry.person and ("   |cffbfb29a" .. entry.person .. "|r") or ""))
        end)
        notesFrame.list.scroll:SetPoint("TOPLEFT", 8, -8)
        notesFrame.list.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
        local readAll = fittedButton(ctx, notesFrame, L["Mark all as read"], function()
            market.markRead(ctx.guild())
            ctx.updateNotice()
            UI.showNotes(ctx)
        end, 140)
        readAll:ClearAllPoints()
        readAll:SetPoint("BOTTOMRIGHT", -14, 14)
        notesFrame.empty = text(body, "GameFontDisable", "CENTER")
        notesFrame.empty:SetPoint("CENTER")
        notesFrame.empty:SetText(L["No notifications yet."])
    end
    local notes = market.notes(ctx.guild())
    notesFrame.empty:SetShown(#notes == 0)
    notesFrame.list.set(notes)
    notesFrame:Show()
end

-- Bulletin board -----------------------------------------------------------------------------------------
local SORTS = { { "new", "Newest first" }, { "old", "Oldest first" }, { "pay", "Highest payment" },
    { "payEach", "Highest payment per craft" }, { "ends", "Shortest time left" }, { "profession", "Profession" } }
local VIEWS = { { "open", "Open orders" }, { "active", "Accepted and in progress" }, { "ready", "Ready for handoff" },
    { "all", "All active orders" }, { "history", "History" } }

function UI.buildBoard(page, ctx)
    local view = CreateFrame("Frame", nil, page)
    view:SetPoint("TOPLEFT", 14, -44)
    view:SetPoint("BOTTOMRIGHT", -14, 14)
    local filters = { view = market.setting("boardView") or "open", sort = "new", craftable = market.setting("onlyCraftable") }
    local state = { selection = nil, serial = 0 }
    local W = widgets()

    local bar = ctx.contrastPanel(view)
    bar:SetPoint("TOPLEFT", 3, 0)
    bar:SetPoint("TOPRIGHT", -3, 0)
    bar:SetHeight(66)
    local items = {}
    local function refresh() view.refresh() end
    local search = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    search:SetSize(190, 22)
    search:SetAutoFocus(false)
    search:SetMaxBytes(80)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    local placeholder = text(search, "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 2, 0)
    placeholder:SetText(L["Search orders"])
    search:SetScript("OnTextChanged", function(box)
        placeholder:SetShown(box:GetText() == "")
        state.serial = state.serial + 1
        local serial = state.serial
        C_Timer.After(.2, function() if serial == state.serial then refresh() end end)
    end)
    items[#items + 1] = { frame = search, width = 198, dx = 6 }
    local dropdowns = {}
    local function addDropdown(options, key, maximum, default)
        local control = W.dropdown(bar, 120, options, function() return filters[key] or default end, function(value)
            filters[key] = value ~= default and value or nil
            state.selection = nil
            refresh()
        end)
        dropdowns[#dropdowns + 1] = control
        items[#items + 1] = { frame = control, sized = true, width = function()
            local widest = 0
            for _, option in ipairs(options()) do widest = math.max(widest, textWidth(option[2], GameFontHighlight)) end
            return math.floor(math.min(maximum or 210, math.max(96, widest + 46)))
        end }
        return control
    end
    addDropdown(function()
        local options = {}
        for index, entry in ipairs(VIEWS) do options[index] = { entry[1], L[entry[2]] } end
        return options
    end, "view", 220, "open")
    filters.view = market.setting("boardView") or "open"
    addDropdown(function()
        local options, seen = { { 0, L["All professions"] } }, {}
        for _, order in pairs(addon.board.records(ctx.guild())) do
            local recipe = ctx.describe(order)
            if recipe.professionID and not seen[recipe.professionID] then
                seen[recipe.professionID] = true
                options[#options + 1] = { recipe.professionID, recipe.profession or "?" }
            end
        end
        table.sort(options, function(a, b) if a[1] == 0 then return true elseif b[1] == 0 then return false end return a[2] < b[2] end)
        return options
    end, "profession", 200, 0)
    addDropdown(function()
        local options = { { "all", L["All categories"] } }
        for _, top in ipairs(addon.recipeFinder.topCategories()) do options[#options + 1] = { top, addon.recipeFinder.label(top) } end
        return options
    end, "category", 200, "all")
    addDropdown(function()
        local options = { { -1, L["Any quality"] } }
        for quality = 1, 5 do
            local name = _G["ITEM_QUALITY" .. quality .. "_DESC"]
            if name then
                local r, g, b = W.qualityColor(quality)
                options[#options + 1] = { quality, ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, L["%s or better"]:format(name)) }
            end
        end
        return options
    end, "quality", 200, -1)
    addDropdown(function()
        return { { "any", L["Any material arrangement"] }, { "requester", L["Requester provides materials"] },
            { "crafter", L["Crafter provides materials"] } }
    end, "materials", 230, "any")
    addDropdown(function()
        local options = {}
        for index, entry in ipairs(SORTS) do options[index] = { entry[1], L[entry[2]] } end
        return options
    end, "sort", 230, "new")
    filters.sort = "new"
    local function check(caption, key, hint)
        local holder = CreateFrame("Frame", nil, bar)
        holder:SetHeight(24)
        local control = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
        control:SetSize(24, 24)
        control:SetPoint("LEFT")
        control:SetChecked(filters[key] and true or false)
        control:SetScript("OnClick", function(self) filters[key] = self:GetChecked() and true or nil; state.selection = nil; refresh() end)
        local label = text(holder, "GameFontHighlightSmall")
        label:SetPoint("LEFT", control, "RIGHT", 2, 0)
        label:SetText(caption)
        W.tooltipFor(control, caption, hint)
        local width = math.ceil(label:GetStringWidth()) + 30
        items[#items + 1] = { frame = holder, sized = true, width = function() return width end }
    end
    check(L["Only orders I can craft"], "craftable", L["Recipes your character knows according to the last profession scan."])
    check(L["Only with payment"], "paid")
    local minHolder = CreateFrame("Frame", nil, bar)
    minHolder:SetHeight(24)
    local minLabel = text(minHolder, "GameFontNormalSmall")
    minLabel:SetPoint("LEFT")
    minLabel:SetText(L["Min. payment"])
    local minBox = CreateFrame("EditBox", nil, minHolder, "InputBoxTemplate")
    minBox:SetSize(46, 20)
    minBox:SetPoint("LEFT", minLabel, "RIGHT", 10, 0)
    minBox:SetAutoFocus(false)
    minBox:SetNumeric(true)
    minBox:SetMaxLetters(6)
    minBox:SetScript("OnEscapePressed", minBox.ClearFocus)
    minBox:SetScript("OnTextChanged", function(_, user)
        if not user then return end
        filters.minPay = (tonumber(minBox:GetText()) or 0) * 10000
        state.serial = state.serial + 1
        local serial = state.serial
        C_Timer.After(.3, function() if serial == state.serial then refresh() end end)
    end)
    local coin = minHolder:CreateTexture(nil, "ARTWORK")
    coin:SetSize(13, 13)
    coin:SetPoint("LEFT", minBox, "RIGHT", 3, 0)
    coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    local minWidth = math.ceil(minLabel:GetStringWidth()) + 80
    items[#items + 1] = { frame = minHolder, sized = true, width = function() return minWidth end }
    local create = fittedButton(ctx, bar, L["Place new order"], function() ctx.openCatalog() end, 120)
    items[#items + 1] = { frame = create, width = function() return create:GetWidth() end, dy = -1 }
    view.create = create

    local function flow()
        local available = bar:GetWidth()
        if available <= 0 then return end
        local x, y = 10, -7
        for _, item in ipairs(items) do
            local width = type(item.width) == "function" and item.width() or item.width
            if item.sized then item.frame:SetWidth(width) end
            if x > 10 and x + width > available - 10 then x, y = 10, y - 30 end
            item.frame:ClearAllPoints()
            item.frame:SetPoint("TOPLEFT", x + (item.dx or 0), y + (item.dy or 0))
            x = x + width + 8
        end
        bar:SetHeight(-y + 33)
    end
    bar:SetScript("OnSizeChanged", flow)

    local listPanel = ctx.contrastPanel(view)
    listPanel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    listPanel:SetPoint("BOTTOMLEFT", 3, 3)
    view.listPanel = listPanel
    local detailPanel = ctx.contrastPanel(view)
    detailPanel:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", 7, 0)
    detailPanel:SetPoint("BOTTOMRIGHT", -3, 3)
    detailPanel:SetWidth(360)
    view:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then listPanel:SetWidth(math.max(380, width - 6 - 7 - 380)) end
    end)
    local empty = text(listPanel, "GameFontDisable", "CENTER", true)
    empty:SetPoint("TOPLEFT", 16, -30)
    empty:SetPoint("RIGHT", -16, 0)
    local detail = UI.detail(detailPanel, ctx)
    local actions = UI.actionBar(detailPanel, ctx)
    actions:SetPoint("BOTTOMLEFT", 10, 10)
    actions:SetPoint("BOTTOMRIGHT", -10, 10)
    detail.scroll:SetPoint("TOPLEFT", 8, -8)
    detail.scroll:SetPoint("BOTTOMRIGHT", actions, "TOPRIGHT", -20, 6)

    local cards = W.virtualList(listPanel, 106, function(parent)
        local row = UI.card(parent, ctx, function(self)
            state.selection = self.entry.key
            refresh()
        end, true)
        row.details = fittedButton(ctx, row, L["Details"], function(self)
            state.selection = self:GetParent().entry.key
            refresh()
        end, 80)
        row.details:ClearAllPoints()
        row.details:SetPoint("BOTTOMLEFT", 52, 8)
        row.accept = fittedButton(ctx, row, L["Accept order"], function(self)
            local entry = self:GetParent().entry
            state.selection = entry.key
            refresh()
            UI.confirmTake(ctx, entry.order)
        end, 110)
        row.accept:ClearAllPoints()
        row.accept:SetPoint("LEFT", row.details, "RIGHT", 6, 0)
        row.bar:ClearAllPoints()
        row.bar:SetPoint("BOTTOMRIGHT", -12, 14)
        return row
    end, function(row, entry)
        UI.fillCard(row, entry, ctx, entry.key == state.selection)
        local order = entry.order
        local own = order.owner == ctx.player()
        local canTake = order.state == "O" and not own and not order.intent and market.state(order, ctx.clock()) == "O"
            and ctx.knows(order.recipe) and UI.orderable(ctx, order.recipe)
        row.accept:SetShown(canTake)
        if order.intent == "take" then
            row.status:SetText(L["Waiting for confirmation"])
        elseif order.crafter and not own and not ctx.same(order.crafter) and market.accepted[order.state] then
            row.line3:SetText(row.line3:GetText() .. "   |cff9b9389" .. L["Taken by %s"]:format(ctx.displayName(order.crafter)) .. "|r")
        end
    end)
    cards.scroll:SetPoint("TOPLEFT", 6, -6)
    cards.scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local function matches(entry, query)
        local order = entry.order
        local current = entry.state
        local mode = filters.view or "open"
        if mode == "open" and current ~= "O" then return false end
        if mode == "active" and not market.accepted[current] then return false end
        if mode == "ready" and current ~= "R" and current ~= "H" then return false end
        if mode == "all" and market.closed[current] then return false end
        if mode == "history" and not market.closed[current] then return false end
        local recipe = entry.recipe
        if filters.profession and recipe.professionID ~= filters.profession then return false end
        if filters.category and addon.recipeFinder.recipeCategory(order.recipe, recipe.professionID, ctx.finder()) ~= filters.category then return false end
        if filters.quality and filters.quality >= 0 and (recipe.quality or -1) < filters.quality then return false end
        if filters.craftable and not ctx.knows(order.recipe) then return false end
        local total = order.ext and market.total(order) or 0
        if filters.paid and total <= 0 then return false end
        if filters.minPay and filters.minPay > 0 and total < filters.minPay then return false end
        if filters.materials then
            local level = market.supplyLevel(order, ctx.materials(order.recipe))
            if filters.materials == "requester" and level ~= "all" and level ~= "some" then return false end
            if filters.materials == "crafter" and level ~= "none" and level ~= "some" then return false end
        end
        if query ~= "" then
            local haystack = (recipe.name .. "\n" .. (recipe.profession or "") .. "\n" .. ctx.displayName(order.owner) .. "\n"
                .. (order.crafter and ctx.displayName(order.crafter) or "") .. "\n" .. (order.note or "")):lower()
            for word in query:gmatch("%S+") do
                if not haystack:find(word, 1, true) then return false end
            end
        end
        return true
    end

    function view.refresh()
        flow()
        local now = ctx.clock()
        local query = (search:GetText() or ""):lower():match("^%s*(.-)%s*$")
        local visible = {}
        for key, order in pairs(addon.board.records(ctx.guild())) do
            if not order.direct and not ctx.hidden(order) then
                local entry = { key = key, order = order, state = market.state(order, now), role = roleOf(order, ctx) }
                entry.recipe = ctx.describe(order)
                if matches(entry, query) then visible[#visible + 1] = entry end
            end
        end
        local sort = filters.sort or "new"
        local function created(entry) return tonumber(entry.order.token:match("^%d+")) or 0 end
        table.sort(visible, function(a, b)
            local x, y
            if sort == "old" then x, y = -created(a), -created(b)
            elseif sort == "pay" then x, y = a.order.ext and market.total(a.order) or 0, b.order.ext and market.total(b.order) or 0
            elseif sort == "payEach" then
                x = a.order.ext and market.total(a.order) / a.order.quantity or 0
                y = b.order.ext and market.total(b.order) / b.order.quantity or 0
            elseif sort == "ends" then x, y = -(a.order.expiresAt or math.huge), -(b.order.expiresAt or math.huge)
            elseif sort == "profession" then
                x, y = a.recipe.profession or "", b.recipe.profession or ""
                if x ~= y then return x < y end
                x, y = created(a), created(b)
            else x, y = created(a), created(b) end
            if x == y then return a.key > b.key end
            return x > y
        end)
        local selected
        for _, entry in ipairs(visible) do if entry.key == state.selection then selected = entry end end
        if not selected then
            selected = visible[1]
            state.selection = selected and selected.key
        end
        empty:SetText(#visible == 0 and L["No orders in this view."] or "")
        cards.set(visible)
        detail.set(selected and selected.order)
        actions.set(UI.actions(ctx, selected and selected.order, now))
        create:SetEnabled(ctx.ready() and ctx.canPost())
    end
    view:SetScript("OnShow", function()
        for _, control in ipairs(dropdowns) do control.Sync() end
    end)
    return view
end

-- Settings ----------------------------------------------------------------------------------------------
local TYPE_LABELS = {
    direct = "New direct order", match = "New order I can craft", accepted = "Order accepted or taken",
    declined = "Order declined or released", proposal = "Change proposals", costOffer = "Material cost",
    missing = "Missing materials", materials = "Materials received", progress = "Crafting progress",
    crafted = "Crafting finished", ready = "Ready for handoff", shipped = "Items sent", received = "Items received",
    paid = "Payment", done = "Order completed", expiring = "Posting expires soon", overdue = "Deadline passed",
    cancelRequest = "Cancellation requests", cancelled = "Order cancelled", handover = "Pending handoffs",
}

local function marketOption(S, page, key, label, desc, extra)
    local entry = { page = page, kind = "check", label = label, desc = desc, scope = "account",
        get = function() return market.setting(key) end, set = function(value) market.set(key, value) end,
        default = market.defaults[key] }
    for field, value in pairs(extra or {}) do entry[field] = value end
    S.add(entry)
end

-- Registers the crafting order, marketplace, notification and data pages in the central
-- settings window (Settings.lua). Values stay in ForeverGuildSettings.market.
function UI.registerSettings(S, ctx)
    S.page("orders", "guild", "Crafting orders")
    S.add({ page = "orders", kind = "number", label = L["Default posting duration (days, 1–30)"], scope = "account",
        desc = L["Preset for new orders; it can be changed in the order dialog."], min = 1, max = 30, default = 7,
        get = function() return market.setting("days") end, set = function(value) market.set("days", value) end })
    local methods = {}
    for index, label in ipairs(METHOD_LABELS) do methods[index] = { index, L[label] } end
    S.add({ page = "orders", kind = "choice", label = L["Default handoff method"], scope = "account", default = 1,
        desc = L["Preset for new orders."], options = function() return methods end,
        get = function() return market.setting("method") end, set = function(value) market.set("method", value) end })
    S.add({ page = "orders", kind = "number", label = L["Keep closed orders for (days, 14–365)"], scope = "character",
        desc = L["Completed, cancelled and expired orders are removed from this character afterwards."],
        info = L["Requesters keep sharing a closed order for 14 days, so shorter periods are not possible."],
        min = 14, max = 365, default = 30,
        get = function() return market.setting("keepDays") end, set = function(value) market.set("keepDays", value) end })

    S.page("market", "guild", "Marketplace")
    local views = {}
    for index, entry in ipairs(VIEWS) do views[index] = { entry[1], L[entry[2]] } end
    S.add({ page = "market", kind = "choice", label = L["Default bulletin board view"], scope = "account", default = "open",
        desc = L["Which orders the bulletin board shows first."], options = function() return views end,
        get = function() return market.setting("boardView") end, set = function(value) market.set("boardView", value) end })
    marketOption(S, "market", "onlyCraftable", L["Show only orders I can craft"],
        L["Preset of the bulletin board filter, based on the recipes your character knows."])

    S.page("notifyGeneral", "notify", "General")
    marketOption(S, "notifyGeneral", "popup", L["Pop-up notifications"], L["Compact window with “Open order”."])
    marketOption(S, "notifyGeneral", "chat", L["Chat notifications"], L["A short line in the chat window."])
    marketOption(S, "notifyGeneral", "sound", L["Notification sound"], L["Plays the whisper sound of the client."],
        { keywords = "sound ton audio" })
    marketOption(S, "notifyGeneral", "combat", L["Pop-ups during combat (otherwise shown afterwards)"],
        L["Off: pop-ups wait until combat has ended."])
    marketOption(S, "notifyGeneral", "counters", L["Show unread counters"],
        L["Counters at the navigation and the minimap envelope. Each order counts once."])

    S.page("notifyOrders", "notify", "Crafting orders")
    marketOption(S, "notifyOrders", "remindHandover", L["Remind me of pending handoffs"],
        L["Once per session for orders that are ready for handoff."])
    marketOption(S, "notifyOrders", "remindOverdue", L["Remind me of expiring and overdue orders"],
        L["Once per order when the posting expires within a day or the completion deadline has passed."])
    S.add({ page = "notifyOrders", kind = "custom", label = L["Notification types"], scope = "account",
        desc = L["Disabled types still appear in the notification history."],
        build = function(container, entry)
            entry.checks = {}
            for index, kind in ipairs(market.typeOrder) do
                local check = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
                check:SetSize(22, 22)
                check:SetPoint("TOPLEFT", ((index - 1) % 2) * 230, -math.floor((index - 1) / 2) * 23)
                check:SetScript("OnClick", function(self) market.setType(kind, self:GetChecked() and true or false) end)
                local label = text(container, "GameFontHighlightSmall")
                label:SetPoint("LEFT", check, "RIGHT", 2, 0)
                label:SetText(L[TYPE_LABELS[kind]])
                entry.checks[kind] = check
            end
        end,
        height = function() return math.ceil(#market.typeOrder / 2) * 23 + 4 end,
        refresh = function(entry) for kind, check in pairs(entry.checks) do check:SetChecked(market.typeEnabled(kind)) end end })

    S.page("data", "system", "Data management")
    S.add({ page = "data", kind = "custom", label = L["Manage order data"], scope = "character",
        desc = L["Every action shows the affected orders first. Active orders are never included; removals only affect this character."],
        build = function(container) UI.buildDataManagement(container, ctx) end,
        height = function() return 6 * 30 end })
    S.add({ page = "data", kind = "text", label = L["Data protection"], scope = "guild",
        desc = L["Order data travels over the WoW guild addon channel. It is not encrypted and the server does not guarantee delivery; direct orders are only shown to the two participants."] })
end

local function cleanupList(ctx, predicate)
    local list = {}
    for _, entry in ipairs(UI.entries(ctx)) do
        if predicate(entry) then list[#list + 1] = entry end
    end
    return list
end

local function entryName(entry, ctx)
    local subject = entry.order or entry.legacy
    return (itemLine(subject, ctx))
end

local function confirmCleanup(ctx, title, list, apply, hint)
    if #list == 0 then
        UI.prompt(ctx, { title = title, kind = "confirm", text = L["No orders are affected."], confirm = function() end })
        return
    end
    local lines = {}
    for index, entry in ipairs(list) do
        if index > 12 then
            lines[#lines + 1] = L["… and %d more"]:format(#list - 12)
            break
        end
        lines[#lines + 1] = "· " .. entryName(entry, ctx)
    end
    UI.prompt(ctx, { title = title, kind = "confirm", text = L["%d orders:"]:format(#list) .. "\n" .. table.concat(lines, "\n"),
        hint = hint, confirm = function()
            for _, entry in ipairs(list) do apply(entry) end
            ctx.refresh()
            ctx.updateNotice()
        end })
end

function UI.buildDataManagement(container, ctx)
    local actions = {
        { L["Archive completed orders"], function()
            confirmCleanup(ctx, L["Archive completed orders"], cleanupList(ctx, function(entry)
                return not entry.archived and entry.state == "D" end), function(entry) ctx.archive(entry.key, true) end,
                L["Archived orders move to the history; nothing changes for other players."])
        end },
        { L["Clean up cancelled orders"], function()
            confirmCleanup(ctx, L["Clean up cancelled orders"], cleanupList(ctx, function(entry)
                return entry.order ~= nil and (entry.state == "X" or entry.state == "J") end),
                function(entry) ctx.removeLocal(entry.key, false) end,
                L["Removed locally; later sync messages cannot bring them back."])
        end },
        { L["Clean up expired orders"], function()
            confirmCleanup(ctx, L["Clean up expired orders"], cleanupList(ctx, function(entry)
                return entry.order ~= nil and entry.state == "E" end), function(entry) ctx.removeLocal(entry.key, false) end,
                L["Expired postings are removed from this character. Your own expired postings are no longer shared."])
        end },
        { L["Show older, not fully compatible orders"], function() UI.showLegacyOrders(ctx) end },
        { L["Delete archived orders"], function()
            confirmCleanup(ctx, L["Delete archived orders"], cleanupList(ctx, function(entry) return entry.archived end),
                function(entry) ctx.removeLocal(entry.key, entry.legacy ~= nil) end,
                L["Permanently deletes the archived orders on this character."])
        end },
    }
    for index, action in ipairs(actions) do
        local control = fittedButton(ctx, container, action[1], action[2], 260)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", 0, -(index - 1) * 30)
    end
end

-- Older orders (direct orders of older versions and old-format board orders) with a
-- selection for local removal or archiving.
local legacyFrame
function UI.showLegacyOrders(ctx)
    if ctx.inCombat() then return end
    if not legacyFrame then
        legacyFrame = CreateFrame("Frame", "ForeverGuildLegacyOrders", UIParent, "PortraitFrameTemplate")
        legacyFrame:SetSize(560, 440)
        legacyFrame:SetPoint("CENTER", 80, 0)
        legacyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        legacyFrame:SetToplevel(true)
        legacyFrame:SetClampedToScreen(true)
        legacyFrame:SetPortraitToAsset(ctx.icon)
        legacyFrame:SetTitle(L["ForeverGuild · Older orders"])
        table.insert(UISpecialFrames, "ForeverGuildLegacyOrders")
        local body = ctx.contrastPanel(legacyFrame)
        body:SetPoint("TOPLEFT", 12, -45)
        body:SetPoint("BOTTOMRIGHT", -12, 46)
        legacyFrame.selected = {}
        legacyFrame.list = widgets().virtualList(body, 26, function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(22, 22)
            row.check:SetPoint("LEFT", 2, 0)
            row.check:SetScript("OnClick", function(self) legacyFrame.selected[row.entry.key] = self:GetChecked() or nil end)
            row.label = text(row, "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            return row
        end, function(row, entry)
            row.entry = entry
            row.check:SetChecked(legacyFrame.selected[entry.key] and true or false)
            local subject = entry.order or entry.legacy
            local status = entry.legacy and UI.legacyStatus(entry.legacy) or (UI.stateText(entry.order, ctx.clock()))
            row.label:SetText(("%s   |cffbfb29a%s%s|r"):format(entryName(entry, ctx), status,
                entry.archived and (" · " .. L["Archived"]) or ""))
            row.itemID = subject and subject.recipe
        end)
        legacyFrame.list.scroll:SetPoint("TOPLEFT", 6, -6)
        legacyFrame.list.scroll:SetPoint("BOTTOMRIGHT", -26, 6)
        legacyFrame.empty = text(body, "GameFontDisable")
        legacyFrame.empty:SetPoint("CENTER")
        legacyFrame.empty:SetText(L["No older orders found."])
        local function selection()
            local list = {}
            for _, entry in ipairs(legacyFrame.entries or {}) do
                if legacyFrame.selected[entry.key] then list[#list + 1] = entry end
            end
            return list
        end
        local remove = fittedButton(ctx, legacyFrame, L["Remove selected locally"], function()
            confirmCleanup(ctx, L["Remove selected locally"], selection(), function(entry)
                ctx.removeLocal(entry.key, entry.legacy ~= nil)
                legacyFrame.selected[entry.key] = nil
            end, L["Only removed from this character's view; the order itself is not cancelled for anyone else. It will not come back through later synchronization."])
        end, 150)
        remove:ClearAllPoints()
        remove:SetPoint("BOTTOMRIGHT", -14, 14)
        local archive = fittedButton(ctx, legacyFrame, L["Archive selected"], function()
            for _, entry in ipairs(selection()) do ctx.archive(entry.key, true) end
            UI.showLegacyOrders(ctx)
        end, 120)
        archive:ClearAllPoints()
        archive:SetPoint("RIGHT", remove, "LEFT", -6, 0)
        legacyFrame:SetScript("OnShow", function() C_Timer.After(0, function() UI.showLegacyOrders(ctx) end) end)
    end
    local entries = {}
    for _, entry in ipairs(UI.entries(ctx)) do
        if entry.legacy or (entry.order and not entry.order.ext) then entries[#entries + 1] = entry end
    end
    legacyFrame.entries = entries
    legacyFrame.empty:SetShown(#entries == 0)
    legacyFrame.list.set(entries)
    if not legacyFrame:IsShown() then legacyFrame:Show() end
end
