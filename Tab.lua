local ADDON, ns = ...

local TAB_ID = "AuctionMin"
local SIDE_WIDTH = 180
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 19
local TOP_LIMIT = 200

local SETTINGS = {
    { option = "auto", label = "Scan when the auction house opens" },
    { option = "learnFromSearches", label = "Learn from items you browse" },
    { option = "showStack", label = "Stack price in bag tooltips" },
    { option = "showActivity", label = "Sales activity in tooltips" },
}

local RATE_HELP = "Estimated units sold per day. Grey when fewer than 3 sales were seen, so it's only a rough guess."
local HISTORY_DAYS = 14
local DAY = 24 * 60 * 60
local PRICE_COLOR = { 1, 0.82, 0 }
local SALES_COLOR = { 0.35, 0.65, 1 }

local panel
local ui = { checks = {} }
local views = {}
local activeView
local historyTabID
local historyKey
local refreshQueued = false

local function CreateInset(parent, atlas)
    local inset = CreateFrame("Frame", nil, parent)
    inset.layoutType = "InsetFrameTemplate"
    inset.Background = inset:CreateTexture(nil, "BACKGROUND")
    inset.Background:SetAtlas(atlas)
    inset.Background:SetPoint("TOPLEFT", 3, -3)
    inset.Background:SetPoint("BOTTOMRIGHT", -3, 3)
    inset.NineSlice = CreateFrame("Frame", nil, inset, "NineSlicePanelTemplate")
    inset.NineSlice:SetAllPoints()
    return inset
end

local function KeyItemID(key)
    if type(key) == "number" then
        return key
    end
    return tonumber(key:match("^(%d+)"))
end

local function KeyLink(key)
    if type(key) == "string" then
        local entry = ns.realm.items[key]
        return entry and entry[5]
    end
    local _, link = C_Item.GetItemInfo(key)
    if not link then
        C_Item.RequestLoadItemDataByID(key)
    end
    return link
end

local pendingOpen

local function NotLoaded(itemID)
    C_Item.RequestLoadItemDataByID(itemID)
    ns.Print("item data is still loading, click it again in a moment.")
end

local function SelectResult(itemKey, minPrice)
    local ok = pcall(AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame,
        { itemKey = itemKey, minPrice = minPrice or 0, totalQuantity = 0 })
    if not ok then
        ns.Print("couldn't open this item in the Buy tab.")
    end
end

local function OpenInBuy(key, link, minPrice)
    local itemID = KeyItemID(key)
    local itemKey = ns.KnownItemKey(key, itemID)
    if itemKey then
        if not C_AuctionHouse.GetItemKeyInfo(itemKey) then
            NotLoaded(itemID)
            return
        end
    else
        local plain = C_AuctionHouse.MakeItemKey(itemID, 0, 0, 0)
        local info = C_AuctionHouse.GetItemKeyInfo(plain)
        if not info then
            NotLoaded(itemID)
            return
        end
        if info.isCommodity then
            itemKey = plain
        end
    end

    local name = not itemKey and ((link and link:match("|h%[(.-)%]|h")) or C_Item.GetItemNameByID(itemID))
    if not itemKey and not name then
        NotLoaded(itemID)
        return
    end

    local buyTab = AuctionHouseFrame.Tabs and AuctionHouseFrame.Tabs[1]
    if buyTab then
        buyTab:Click()
    end
    if itemKey then
        SelectResult(itemKey, minPrice)
        return
    end
    pendingOpen = { itemID = itemID, name = name, minPrice = minPrice, expires = GetTime() + 10 }
    AuctionHouseFrame.SearchBar:SetSearchText(name)
    AuctionHouseFrame.SearchBar:StartSearch()
end

local function OpenPendingResult()
    if not pendingOpen then
        return
    end
    if GetTime() > pendingOpen.expires then
        pendingOpen = nil
        return
    end
    local results = C_AuctionHouse.GetBrowseResults()
    local match, fallback, count = nil, nil, 0
    for _, result in ipairs(results or {}) do
        if result.itemKey and result.itemKey.itemID == pendingOpen.itemID then
            count = count + 1
            fallback = result
            local info = C_AuctionHouse.GetItemKeyInfo(result.itemKey)
            if info and info.itemName == pendingOpen.name then
                match = result
                break
            end
        end
    end
    match = match or (count == 1 and fallback) or nil
    if match then
        local minPrice = match.minPrice or pendingOpen.minPrice
        pendingOpen = nil
        SelectResult(match.itemKey, minPrice)
    end
end

local function InsertChatLink(link)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        ChatFrameUtil.InsertLink(link)
    elseif ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
    end
end

local function Money(copper)
    return ns.FormatMoney(math.floor(copper + 0.5))
end

local function GoldOnly(copper)
    if copper >= 10000 then
        copper = math.floor(copper / 10000) * 10000
    end
    return Money(copper)
end

local function RateText(entry)
    local text = ns.FormatRate(entry.rate)
    if ns.FewSales(entry.sold) then
        return "|cff999999" .. text .. "|r"
    end
    return text
end

local function SupplyText(entry)
    if not entry.listed then
        return "?"
    elseif entry.listed == 0 then
        return "|cff999999none listed|r"
    end
    local days = entry.supply
    local short
    if days < 1 then
        short = "<1d"
    elseif days >= 100 then
        short = "100+d"
    else
        short = math.floor(days + 0.5) .. "d"
    end
    return FormatLargeNumber(entry.listed) .. " |cff999999(" .. short .. ")|r"
end

local function ShowHelp(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(title)
    for i = 1, select("#", ...) do
        local text = select(i, ...)
        if i > 1 then
            GameTooltip:AddLine(" ")
        end
        GameTooltip:AddLine(text, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function BuildActivity(entries)
    local items = ns.realm.items
    for key in pairs(ns.realm.activity) do
        local perDay, _, hasSales, sold = ns.GetActivity(key)
        local item = items[key]
        if perDay and hasSales and item then
            local price = math.floor(item[1] + 0.5)
            local listed = item[4]
            entries[#entries + 1] = {
                key = key,
                rate = perDay,
                sold = sold,
                listed = listed,
                supply = listed and (listed / perDay) or math.huge,
                price = price,
                gold = perDay * price,
            }
        end
    end
end

local function BuildDeals(entries)
    local now = ns.Now()
    for key, item in pairs(ns.realm.items) do
        local units = item[6]
        if units and item[7] and now - item[2] <= ns.DEAL_MAX_AGE then
            local perDay, _, hasSales, sold = ns.GetActivity(key)
            if perDay and hasSales then
                local market = item[1]
                local deal = item[7] / units
                local margin = market * (1 - ns.AH_CUT) - deal
                local profit = math.min(units, perDay * ns.RESALE_DAYS) * margin
                if profit >= 1 then
                    entries[#entries + 1] = {
                        key = key,
                        deal = deal,
                        discount = 1 - deal / market,
                        price = market,
                        available = units,
                        rate = perDay,
                        sold = sold,
                        profit = profit,
                    }
                end
            end
        end
    end
end

local VIEWS = {
    {
        title = "Most active",
        build = BuildActivity,
        sortKey = "rate",
        columns = {
            { key = "item", title = "Item", width = 220 },
            { key = "rate", title = "Sells / day", width = 70, sortable = true,
                render = RateText, help = RATE_HELP },
            { key = "supply", title = "Supply", width = 120, sortable = true, ascending = true, render = SupplyText,
                help = "Units listed now and how many days they would last at the current sales rate." },
            { key = "price", title = "Market price", width = 95, sortable = true,
                render = function(e) return Money(e.price) end },
            { key = "gold", title = "Gold / day", width = 85, sortable = true,
                render = function(e) return GoldOnly(e.gold) end,
                help = "Sales per day times the market price: how much gold this item moves." },
        },
        empty = function(enough)
            if enough then
                return "No sales seen yet", "Items appear here once AuctionMin has seen them sell between your scans."
            end
            return "No activity data yet", "Items appear here once AuctionMin has seen them sell between your scans."
        end,
    },
    {
        title = "Deals",
        build = BuildDeals,
        sortKey = "profit",
        columns = {
            { key = "item", title = "Item", width = 180 },
            { key = "deal", title = "Deal price", width = 85, sortable = true, ascending = true,
                render = function(e) return Money(e.deal) end,
                help = "Average price of the units listed at least 20% below the market price, your own auctions left out." },
            { key = "discount", title = "Below", width = 55, sortable = true,
                render = function(e) return ("-%d%%"):format(math.floor(e.discount * 100 + 0.5)) end },
            { key = "price", title = "Market", width = 85, sortable = true,
                render = function(e) return Money(e.price) end },
            { key = "available", title = "Units", width = 50, sortable = true,
                render = function(e) return FormatLargeNumber(e.available) end },
            { key = "rate", title = "Sells / day", width = 65, sortable = true,
                render = RateText, help = RATE_HELP },
            { key = "profit", title = "Profit", width = 70, sortable = true,
                render = function(e) return GoldOnly(e.profit) end,
                help = "Buying the cheap units, at most what sells in 3 days, and reselling them at the market price "
                    .. "after the 5% auction house cut. Deposits are not included." },
        },
        empty = function(enough)
            if enough then
                return "No deals right now",
                    "Deals are items listed at least 20% below their market price that also sell. They come from "
                    .. "scans and items you opened in the last 2 hours."
            end
            return "No activity data yet", "Deals need sales activity: " .. ns.SCAN_ADVICE .. "."
        end,
    },
}

local function UpdateHeaders(view)
    for _, header in ipairs(view.headers) do
        if header.column.key == view.sortKey then
            header.Arrow:Show()
            if view.sortAscending then
                header.Arrow:SetTexCoord(0, 1, 1, 0)
            else
                header.Arrow:SetTexCoord(0, 1, 0, 1)
            end
        else
            header.Arrow:Hide()
        end
    end
end

local function UpdateRows(view)
    local entries = view.entries
    for i, row in ipairs(view.rows) do
        local entry = entries[view.offset + i]
        if entry then
            local itemID = KeyItemID(entry.key)
            local link = KeyLink(entry.key)
            row.link = link
            row.key = entry.key
            row.minPrice = entry.deal or entry.price
            row.icon:SetTexture(C_Item.GetItemIconByID(itemID))
            row.cells.item:SetText(link and link:gsub("|h%[(.-)%]|h", "|h%1|h") or ("|cff999999Item " .. itemID .. "|r"))
            for _, column in ipairs(view.config.columns) do
                if column.render then
                    row.cells[column.key]:SetText(column.render(entry))
                end
            end
            row:Show()
        else
            row.link = nil
            row:Hide()
        end
    end

    if #entries > #view.rows then
        ui.footer:SetText(("Showing %d-%d of %d, scroll for more"):format(view.offset + 1,
            math.min(#entries, view.offset + #view.rows), #entries))
    else
        ui.footer:SetText("")
    end
end

local function RefreshView(view, enough)
    local entries = view.entries
    wipe(entries)
    view.config.build(entries)
    local sortKey, ascending = view.sortKey, view.sortAscending
    table.sort(entries, function(a, b)
        if ascending then
            return a[sortKey] < b[sortKey]
        end
        return a[sortKey] > b[sortKey]
    end)
    for i = #entries, TOP_LIMIT + 1, -1 do
        entries[i] = nil
    end
    view.offset = math.max(0, math.min(view.offset, #entries - #view.rows))

    UpdateHeaders(view)
    UpdateRows(view)
    local title, text = view.config.empty(enough)
    view.emptyTitle:SetText(title)
    view.emptyText:SetText(text)
    view.emptyTitle:SetShown(#entries == 0)
    view.emptyText:SetShown(#entries == 0)
end

local function UpdateSide()
    local realm = ns.realm
    local count = 0
    for _ in pairs(realm.items) do
        count = count + 1
    end
    local last = realm.scannedAt > 0 and (ns.FormatAge(ns.Now() - realm.scannedAt) .. " ago") or "never"
    ui.status:SetText(("%s items priced, last scan %s"):format(FormatLargeNumber(count), last))

    local observed = ns.ObservedSeconds()
    local enough = observed >= ns.MIN_OBSERVED
    if enough then
        ui.activityValue:SetText("Sales tracked over " .. ns.FormatDuration(observed))
        ui.activityValue:SetTextColor(1, 1, 1)
        ui.hint:SetTextColor(0.6, 0.6, 0.6)
    else
        ui.activityValue:SetText("Not enough scans yet")
        ui.activityValue:SetTextColor(1, 0.55, 0.2)
        ui.hint:SetTextColor(1, 0.82, 0.5)
    end

    for _, check in ipairs(ui.checks) do
        check:SetChecked(ns.db[check.option])
    end
    return enough
end

function ns.RefreshTab()
    if not panel or not panel:IsShown() or not activeView then
        return
    end
    local enough = UpdateSide()
    activeView.refresh(enough)
end

local function ShowActivityHelp(owner)
    ShowHelp(owner, "Activity data",
        "How long AuctionMin has watched sales: the time between your scans, counting only scans less than "
            .. "2 hours apart.",
        "Sales per day are estimated from this time. Busy items are accurate after half an hour, slow items need "
            .. "several hours.",
        "|cff999999Older data fades: its weight halves every 3 days.|r")
end

local function BuildSide()
    local side = CreateInset(panel, "auctionhouse-background-categories")
    side:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 8, -60)
    side:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT", 8, 30)
    side:SetWidth(SIDE_WIDTH)

    local textWidth = SIDE_WIDTH - 24

    local activityTitle = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activityTitle:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -12)
    activityTitle:SetText("Activity data")

    ui.activityValue = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.activityValue:SetPoint("TOPLEFT", activityTitle, "BOTTOMLEFT", 0, -6)
    ui.activityValue:SetWidth(textWidth)
    ui.activityValue:SetJustifyH("LEFT")

    ui.hint = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.hint:SetPoint("TOPLEFT", ui.activityValue, "BOTTOMLEFT", 0, -8)
    ui.hint:SetWidth(textWidth)
    ui.hint:SetJustifyH("LEFT")
    ui.hint:SetSpacing(2)
    ui.hint:SetText("Run at least 3 scans 15-60 minutes apart. Scans more than 2 hours apart don't count.")

    local help = CreateFrame("Frame", nil, side)
    help:SetPoint("TOPLEFT", activityTitle, "TOPLEFT", -4, 4)
    help:SetPoint("BOTTOMLEFT", ui.hint, "BOTTOMLEFT", -4, -4)
    help:SetPoint("RIGHT", side, "RIGHT", -8, 0)
    help:EnableMouse(true)
    help:SetScript("OnEnter", ShowActivityHelp)
    help:SetScript("OnLeave", GameTooltip_Hide)

    local settingsTitle = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsTitle:SetPoint("TOPLEFT", ui.hint, "BOTTOMLEFT", 0, -20)
    settingsTitle:SetText("Settings")

    local anchor, anchorOffset = settingsTitle, -6
    for i, setting in ipairs(SETTINGS) do
        local check = CreateFrame("CheckButton", nil, side, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", i == 1 and -4 or 0, anchorOffset)
        check.Text:SetFontObject("GameFontHighlightSmall")
        check.Text:SetWidth(textWidth - 22)
        check.Text:SetJustifyH("LEFT")
        check.Text:SetText(setting.label)
        check.option = setting.option
        check:SetScript("OnClick", function(self)
            ns.db[self.option] = self:GetChecked() and true or false
        end)
        ui.checks[i] = check
        anchor, anchorOffset = check, -8
    end
end

local function CreateHeader(view, parent, column, x)
    local header = CreateFrame("Button", nil, parent, "ColumnDisplayButtonShortTemplate")
    header:SetSize(column.width, HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
    header:SetText(column.title)
    header.column = column
    header.Arrow = header:CreateTexture(nil, "OVERLAY")
    header.Arrow:SetAtlas("auctionhouse-ui-sortarrow", true)
    header.Arrow:SetPoint("LEFT", header:GetFontString(), "RIGHT", 3, 0)
    header.Arrow:Hide()
    if column.sortable then
        header:SetScript("OnClick", function()
            if view.sortKey == column.key then
                view.sortAscending = not view.sortAscending
            else
                view.sortKey, view.sortAscending = column.key, column.ascending or false
            end
            view.offset = 0
            ns.RefreshTab()
        end)
    else
        header:Disable()
    end
    if column.help then
        header:SetScript("OnEnter", function(self)
            ShowHelp(self, column.title, column.help)
        end)
        header:SetScript("OnLeave", GameTooltip_Hide)
    end
    return header
end

local function CreateRow(view, index)
    local row = CreateFrame("Button", nil, view.list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", view.list, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", view.list, "RIGHT")

    if index % 2 == 1 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAtlas("auctionhouse-rowstripe-1")
        stripe:SetAllPoints()
    end
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("auctionhouse-ui-row-highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)

    row.cells = {}
    local x = 0
    for _, column in ipairs(view.config.columns) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if column.key == "item" then
            cell:SetPoint("LEFT", row, "LEFT", x + ROW_HEIGHT + 8, 0)
            cell:SetWidth(column.width - ROW_HEIGHT - 12)
            cell:SetJustifyH("LEFT")
        else
            cell:SetPoint("LEFT", row, "LEFT", x, 0)
            cell:SetWidth(column.width - 8)
            cell:SetJustifyH("RIGHT")
        end
        cell:SetWordWrap(false)
        row.cells[column.key] = cell
        x = x + column.width
    end

    row:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to open in the Buy tab", 0.25, 1, 0.25)
            GameTooltip:AddLine("Right-click for price history", 0.25, 1, 0.25)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if not self.key then
            return
        end
        if button == "RightButton" then
            GameTooltip:Hide()
            ns.ShowHistory(self.key)
            return
        end
        if self.link and IsModifiedClick("CHATLINK") then
            InsertChatLink(self.link)
            return
        end
        GameTooltip:Hide()
        OpenInBuy(self.key, self.link, self.minPrice)
    end)
    return row
end

local function CreateView(inset, config)
    local view = { config = config, entries = {}, offset = 0, rows = {}, headers = {},
        sortKey = config.sortKey, sortAscending = false }

    view.frame = CreateFrame("Frame", nil, inset)
    view.frame:SetAllPoints()

    local headerRow = CreateFrame("Frame", nil, view.frame)
    headerRow:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    headerRow:SetPoint("RIGHT", inset, "RIGHT", -4, 0)
    headerRow:SetHeight(HEADER_HEIGHT)
    local x = 0
    for _, column in ipairs(config.columns) do
        view.headers[#view.headers + 1] = CreateHeader(view, headerRow, column, x)
        x = x + column.width
    end

    view.list = CreateFrame("Frame", nil, view.frame)
    view.list:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -2)
    view.list:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    view.list:EnableMouseWheel(true)
    view.list:SetScript("OnMouseWheel", function(_, delta)
        view.offset = math.max(0, math.min(view.offset - delta * 3, #view.entries - #view.rows))
        UpdateRows(view)
    end)

    local listHeight = 538 - 60 - 30 - 8 - HEADER_HEIGHT - 2
    for i = 1, math.floor(listHeight / ROW_HEIGHT) do
        view.rows[i] = CreateRow(view, i)
    end

    view.emptyTitle = view.list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.emptyTitle:SetPoint("CENTER", view.list, "CENTER", 0, 12)

    view.emptyText = view.list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.emptyText:SetPoint("TOP", view.emptyTitle, "BOTTOM", 0, -8)
    view.emptyText:SetWidth(380)

    view.refresh = function(enough)
        RefreshView(view, enough)
    end
    view.frame:Hide()
    return view
end

local function Acquire(pool, index, create)
    local object = pool[index]
    if not object then
        object = create()
        pool[index] = object
    end
    object:Show()
    return object
end

local function HideFrom(pool, index)
    for i = index, #pool do
        pool[i]:Hide()
    end
end

local function ShowDayTooltip(hit)
    GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
    GameTooltip:AddLine(date("%A, %b %d", hit.day * DAY + DAY / 2))
    local point = hit.point
    if not point then
        GameTooltip:AddLine("No data for this day", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddDoubleLine("Market price", Money(point.price), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Listed", FormatLargeNumber(point.listed), 1, 0.82, 0, 1, 1, 1)
        if hit.rate then
            GameTooltip:AddDoubleLine("Sales", "about " .. ns.FormatRate(hit.rate) .. "/day", 1, 0.82, 0, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine("Sales", "not tracked", 1, 0.82, 0, 0.6, 0.6, 0.6)
        end
    end
    GameTooltip:Show()
end

local function CreateChart(parent, title, top, height)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, top)
    label:SetText(title)

    local chart = CreateFrame("Frame", nil, parent)
    chart:SetPoint("TOPLEFT", parent, "TOPLEFT", 84, top - 16)
    chart:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, top - 16)
    chart:SetHeight(height)

    local background = chart:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.3)

    for _, point in ipairs({ "TOP", "BOTTOM" }) do
        local rule = chart:CreateTexture(nil, "BORDER")
        rule:SetColorTexture(1, 1, 1, 0.08)
        rule:SetHeight(1)
        rule:SetPoint(point .. "LEFT")
        rule:SetPoint(point .. "RIGHT")
    end

    chart.maxLabel = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chart.maxLabel:SetPoint("TOPRIGHT", chart, "TOPLEFT", -6, 0)
    chart.minLabel = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chart.minLabel:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", -6, 0)
    return chart
end

local function DrawCharts(view, points)
    local today = ns.Today()
    local first = today - HISTORY_DAYS + 1
    local byDay = {}
    local low, high = math.huge, 0
    for _, point in ipairs(points) do
        if point.day >= first then
            byDay[point.day] = point
            low = math.min(low, point.price)
            high = math.max(high, point.price)
        end
    end
    if high == 0 then
        return false
    end
    if high == low then
        low, high = low * 0.9, high * 1.1 + 1
    end
    local padding = (high - low) * 0.1
    low, high = math.max(0, low - padding), high + padding

    local price, sales = view.priceChart, view.salesChart
    local width = price:GetWidth()
    if width <= 0 then
        width = 490
    end
    local column = width / HISTORY_DAYS
    local priceHeight, salesHeight = price:GetHeight(), sales:GetHeight()
    local function X(day)
        return (day - first + 0.5) * column
    end
    local function Y(value)
        return (value - low) / (high - low) * priceHeight
    end

    local lineCount, dotCount, previousX, previousY = 0, 0, nil, nil
    local rates, maxRate = {}, 0
    for day = first, today do
        local point = byDay[day]
        if point then
            local x, y = X(day), Y(point.price)
            if previousX then
                lineCount = lineCount + 1
                local line = Acquire(view.lines, lineCount, function()
                    local created = price:CreateLine(nil, "ARTWORK")
                    created:SetThickness(2)
                    created:SetColorTexture(PRICE_COLOR[1], PRICE_COLOR[2], PRICE_COLOR[3], 1)
                    return created
                end)
                line:SetStartPoint("BOTTOMLEFT", price, previousX, previousY)
                line:SetEndPoint("BOTTOMLEFT", price, x, y)
            end
            dotCount = dotCount + 1
            local dot = Acquire(view.dots, dotCount, function()
                local created = price:CreateTexture(nil, "OVERLAY")
                created:SetSize(5, 5)
                created:SetColorTexture(PRICE_COLOR[1], PRICE_COLOR[2], PRICE_COLOR[3], 1)
                return created
            end)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", price, "BOTTOMLEFT", x, y)
            previousX, previousY = x, y

            if point.observed >= 10 * 60 then
                local rate = point.sold / point.observed * DAY
                rates[day] = rate
                maxRate = math.max(maxRate, rate)
            end
        end
    end
    HideFrom(view.lines, lineCount + 1)
    HideFrom(view.dots, dotCount + 1)
    price.maxLabel:SetText(Money(high))
    price.minLabel:SetText(Money(low))

    local barCount = 0
    for day = first, today do
        local rate = rates[day]
        if rate then
            barCount = barCount + 1
            local bar = Acquire(view.bars, barCount, function()
                local created = sales:CreateTexture(nil, "ARTWORK")
                created:SetColorTexture(SALES_COLOR[1], SALES_COLOR[2], SALES_COLOR[3], 0.85)
                return created
            end)
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", sales, "BOTTOMLEFT", X(day) - column * 0.3, 0)
            bar:SetSize(column * 0.6, maxRate > 0 and math.max(1, rate / maxRate * salesHeight) or 1)
        end
    end
    HideFrom(view.bars, barCount + 1)
    sales.maxLabel:SetText(maxRate > 0 and (ns.FormatRate(maxRate) .. "/day") or "not tracked")
    sales.minLabel:SetText(maxRate > 0 and "0" or "")

    local labels = { { first, date("%b %d", first * DAY + DAY / 2) }, { first + 7, date("%b %d", (first + 7) * DAY + DAY / 2) },
        { today, "Today" } }
    for i, label in ipairs(labels) do
        view.dayLabels[i]:ClearAllPoints()
        view.dayLabels[i]:SetPoint("TOP", sales, "BOTTOMLEFT", X(label[1]), -4)
        view.dayLabels[i]:SetText(label[2])
    end

    for i = 1, HISTORY_DAYS do
        local day = first + i - 1
        local hit = view.hits[i]
        hit:ClearAllPoints()
        hit:SetPoint("TOPLEFT", price, "TOPLEFT", (i - 1) * column, 0)
        hit:SetPoint("BOTTOM", sales, "BOTTOM")
        hit:SetWidth(column)
        hit.day, hit.point, hit.rate = day, byDay[day], rates[day]
    end
    return true
end

local function DrawHistory(view)
    ui.footer:SetText("")
    local key = historyKey
    view.header:SetShown(key ~= nil)
    view.charts:Hide()

    if not key then
        view.emptyTitle:SetText("No item selected")
        view.emptyText:SetText("Right-click an item in Most active or Deals to see its price history.")
        view.emptyTitle:Show()
        view.emptyText:Show()
        return
    end

    local link = KeyLink(key)
    view.icon:SetTexture(C_Item.GetItemIconByID(KeyItemID(key)))
    view.name:SetText(link and link:gsub("|h%[(.-)%]|h", "|h%1|h") or ("Item " .. KeyItemID(key)))
    local price = ns.GetPrice(key)
    view.summary:SetText(price and ("Market price now: " .. Money(price)) or "")
    local change, span = ns.GetTrend(key, price)
    view.trend:SetText(change and ns.TrendText(change, span) or "Trend appears after 2 days of history")

    local shown = view.frame:IsShown() and DrawCharts(view, ns.GetHistory(key))
    view.charts:SetShown(shown)
    view.emptyTitle:SetShown(not shown)
    view.emptyText:SetShown(not shown)
    if not shown then
        view.emptyTitle:SetText("No history yet")
        view.emptyText:SetText("AuctionMin keeps one point per day for 14 days, from your scans and the items you open.")
    end
end

local function CreateHistoryView(inset)
    local view = { lines = {}, dots = {}, bars = {}, hits = {}, dayLabels = {} }
    view.frame = CreateFrame("Frame", nil, inset)
    view.frame:SetAllPoints()

    view.header = CreateFrame("Frame", nil, view.frame)
    view.header:SetAllPoints()
    view.icon = view.header:CreateTexture(nil, "ARTWORK")
    view.icon:SetSize(32, 32)
    view.icon:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -12)
    view.name = view.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.name:SetPoint("LEFT", view.icon, "RIGHT", 10, 0)
    view.name:SetWidth(300)
    view.name:SetJustifyH("LEFT")
    view.name:SetWordWrap(false)
    view.summary = view.header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    view.summary:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -16, -14)
    view.trend = view.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.trend:SetPoint("TOPRIGHT", view.summary, "BOTTOMRIGHT", 0, -4)

    view.charts = CreateFrame("Frame", nil, view.frame)
    view.charts:SetAllPoints()
    view.priceChart = CreateChart(view.charts, "Market price", -60, 190)
    view.salesChart = CreateChart(view.charts, "Sales per day", -288, 80)
    for i = 1, 3 do
        view.dayLabels[i] = view.charts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    end
    for i = 1, HISTORY_DAYS do
        local hit = CreateFrame("Button", nil, view.charts)
        hit:SetFrameLevel(view.priceChart:GetFrameLevel() + 5)
        local highlight = hit:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.06)
        hit:SetScript("OnEnter", ShowDayTooltip)
        hit:SetScript("OnLeave", GameTooltip_Hide)
        view.hits[i] = hit
    end

    view.emptyTitle = view.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.emptyTitle:SetPoint("CENTER", inset, "CENTER", 0, 12)
    view.emptyText = view.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.emptyText:SetPoint("TOP", view.emptyTitle, "BOTTOM", 0, -8)
    view.emptyText:SetWidth(380)

    view.refresh = function()
        DrawHistory(view)
    end
    view.frame:Hide()
    return view
end

local function BuildMain()
    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.status:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", -14, -52)
    ui.status:SetJustifyH("RIGHT")

    local inset = CreateInset(panel, "auctionhouse-background-index")
    inset:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", SIDE_WIDTH + 14, -60)
    inset:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -8, 30)

    for i, config in ipairs(VIEWS) do
        views[i] = CreateView(inset, config)
    end
    views[#views + 1] = CreateHistoryView(inset)

    ui.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.footer:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -12, 12)

    local tabs = CreateFrame("Frame", nil, panel, "AuctionMinTabSystemTemplate")
    tabs:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 6, -3)
    tabs:SetTabSelectedCallback(function(tabID)
        if activeView then
            activeView.frame:Hide()
        end
        activeView = views[tabID]
        activeView.frame:Show()
        ns.RefreshTab()
        return false
    end)
    for _, config in ipairs(VIEWS) do
        tabs:AddTab(config.title)
    end
    historyTabID = tabs:AddTab("History")
    ui.tabs = tabs
    tabs:SetTab(1)
end

function ns.ShowHistory(key)
    historyKey = key
    if ui.tabs then
        ui.tabs:SetTab(historyTabID)
    end
end

local function BuildPanel()
    panel = CreateFrame("Frame", nil, AuctionHouseFrame)
    panel:SetAllPoints(AuctionHouseFrame)
    panel:SetScript("OnShow", ns.RefreshTab)
    BuildSide()
    BuildMain()
end

function ns.CreateTab()
    if panel or not AuctionHouseFrame then
        return
    end
    local LibAHTab = LibStub("LibAHTab-1-0")
    if LibAHTab:DoesIDExist(TAB_ID) then
        return
    end
    BuildPanel()
    LibAHTab:CreateTab(TAB_ID, panel, "AuctionMin", "AuctionMin")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
frame:SetScript("OnEvent", function(_, event)
    if event ~= "GET_ITEM_INFO_RECEIVED" then
        if pendingOpen then
            C_Timer.After(0, OpenPendingResult)
        end
        return
    end
    if refreshQueued or not panel or not panel:IsShown() or not activeView then
        return
    end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        if panel:IsShown() then
            if activeView.rows then
                UpdateRows(activeView)
            else
                activeView.refresh()
            end
        end
    end)
end)
