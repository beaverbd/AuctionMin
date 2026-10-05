local ADDON, ns = ...

local TAB_ID = "AuctionMin"
local SIDE_WIDTH = 180
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 19
local TOP_LIMIT = 200

local COLUMNS = {
    { key = "item", title = "Item", width = 220, justify = "LEFT" },
    { key = "rate", title = "Sells / day", width = 70, justify = "RIGHT", sortable = true },
    { key = "supply", title = "Supply", width = 120, justify = "RIGHT", sortable = true, ascending = true },
    { key = "price", title = "Market price", width = 95, justify = "RIGHT", sortable = true },
    { key = "gold", title = "Gold / day", width = 85, justify = "RIGHT", sortable = true },
}

local SETTINGS = {
    { option = "auto", label = "Scan when the auction house opens" },
    { option = "showStack", label = "Stack price in bag tooltips" },
    { option = "showActivity", label = "Sales activity in tooltips" },
}

local panel
local ui = { rows = {}, checks = {}, headers = {} }
local entries = {}
local offset = 0
local rowCount = 0
local sortKey, sortAscending = "rate", false
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

local function ShowActivityHelp(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Activity data")
    GameTooltip:AddLine("How long AuctionMin has watched sales: the time between your scans, counting only "
        .. "scans less than 2 hours apart.", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Sales per day are estimated from this time. Busy items are accurate after half an hour, "
        .. "slow items need several hours.", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Older data fades: its weight halves every 3 days.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function GoldOnly(copper)
    if copper >= 10000 then
        copper = math.floor(copper / 10000) * 10000
    end
    return ns.FormatMoney(math.floor(copper + 0.5))
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

local function BuildEntries()
    wipe(entries)
    local items = ns.realm.items
    for key in pairs(ns.realm.activity) do
        local perDay, _, hasSales = ns.GetActivity(key)
        local item = items[key]
        if perDay and hasSales and item then
            local price = math.floor(item[1] + 0.5)
            local listed = item[4]
            entries[#entries + 1] = {
                key = key,
                rate = perDay,
                listed = listed,
                supply = listed and (listed / perDay) or math.huge,
                price = price,
                gold = perDay * price,
            }
        end
    end
    table.sort(entries, function(a, b)
        if sortAscending then
            return a[sortKey] < b[sortKey]
        end
        return a[sortKey] > b[sortKey]
    end)
    for i = #entries, TOP_LIMIT + 1, -1 do
        entries[i] = nil
    end
end

local function UpdateHeaders()
    for _, header in ipairs(ui.headers) do
        if header.column.key == sortKey then
            header.Arrow:Show()
            if sortAscending then
                header.Arrow:SetTexCoord(0, 1, 1, 0)
            else
                header.Arrow:SetTexCoord(0, 1, 0, 1)
            end
        else
            header.Arrow:Hide()
        end
    end
end

local function UpdateRows()
    for i, row in ipairs(ui.rows) do
        local entry = entries[offset + i]
        if entry then
            local itemID = KeyItemID(entry.key)
            local link = KeyLink(entry.key)
            row.link = link
            row.icon:SetTexture(C_Item.GetItemIconByID(itemID))
            row.cells.item:SetText(link and link:gsub("|h%[(.-)%]|h", "|h%1|h") or ("|cff999999Item " .. itemID .. "|r"))
            row.cells.rate:SetText(ns.FormatRate(entry.rate))
            row.cells.supply:SetText(SupplyText(entry))
            row.cells.price:SetText(ns.FormatMoney(entry.price))
            row.cells.gold:SetText(GoldOnly(entry.gold))
            row:Show()
        else
            row.link = nil
            row:Hide()
        end
    end

    if #entries > rowCount then
        ui.footer:SetText(("Showing %d-%d of %d, scroll for more"):format(offset + 1,
            math.min(#entries, offset + rowCount), #entries))
    else
        ui.footer:SetText("")
    end
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
    if observed < ns.MIN_OBSERVED then
        ui.activityValue:SetText("Not enough scans yet")
        ui.activityValue:SetTextColor(1, 0.55, 0.2)
        ui.hint:SetTextColor(1, 0.82, 0.5)
        ui.emptyTitle:SetText("No activity data yet")
    else
        ui.activityValue:SetText("Sales tracked over " .. ns.FormatDuration(observed))
        ui.activityValue:SetTextColor(1, 1, 1)
        ui.hint:SetTextColor(0.6, 0.6, 0.6)
        ui.emptyTitle:SetText("No sales seen yet")
    end

    for _, check in ipairs(ui.checks) do
        check:SetChecked(ns.db[check.option])
    end
end

function ns.RefreshTab()
    if not panel or not panel:IsShown() then
        return
    end
    BuildEntries()
    offset = math.max(0, math.min(offset, #entries - rowCount))
    UpdateSide()
    UpdateHeaders()
    UpdateRows()
    local empty = #entries == 0
    ui.emptyTitle:SetShown(empty)
    ui.emptyText:SetShown(empty)
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

local function CreateHeader(parent, column, x)
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
            if sortKey == column.key then
                sortAscending = not sortAscending
            else
                sortKey, sortAscending = column.key, column.ascending or false
            end
            offset = 0
            ns.RefreshTab()
        end)
    else
        header:Disable()
    end
    return header
end

local function CreateRow(list, index)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", list, "RIGHT")

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
    for _, column in ipairs(COLUMNS) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if column.key == "item" then
            cell:SetPoint("LEFT", row, "LEFT", x + ROW_HEIGHT + 8, 0)
            cell:SetWidth(column.width - ROW_HEIGHT - 12)
        else
            cell:SetPoint("LEFT", row, "LEFT", x, 0)
            cell:SetWidth(column.width - 8)
        end
        cell:SetJustifyH(column.justify)
        cell:SetWordWrap(false)
        row.cells[column.key] = cell
        x = x + column.width
    end

    row:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function BuildList()
    local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", SIDE_WIDTH + 18, -36)
    heading:SetText("Most active items")

    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.status:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", -14, -52)
    ui.status:SetJustifyH("RIGHT")

    local inset = CreateInset(panel, "auctionhouse-background-index")
    inset:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", SIDE_WIDTH + 14, -60)
    inset:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -8, 30)

    local headerRow = CreateFrame("Frame", nil, inset)
    headerRow:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    headerRow:SetPoint("RIGHT", inset, "RIGHT", -4, 0)
    headerRow:SetHeight(HEADER_HEIGHT)
    local x = 0
    for _, column in ipairs(COLUMNS) do
        ui.headers[#ui.headers + 1] = CreateHeader(headerRow, column, x)
        x = x + column.width
    end

    ui.list = CreateFrame("Frame", nil, inset)
    ui.list:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -2)
    ui.list:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    ui.list:EnableMouseWheel(true)
    ui.list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(offset - delta * 3, #entries - rowCount))
        UpdateRows()
    end)

    local listHeight = 538 - 60 - 30 - 8 - HEADER_HEIGHT - 2
    rowCount = math.floor(listHeight / ROW_HEIGHT)
    for i = 1, rowCount do
        ui.rows[i] = CreateRow(ui.list, i)
    end

    ui.emptyTitle = ui.list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.emptyTitle:SetPoint("CENTER", ui.list, "CENTER", 0, 12)

    ui.emptyText = ui.list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.emptyText:SetPoint("TOP", ui.emptyTitle, "BOTTOM", 0, -8)
    ui.emptyText:SetWidth(360)
    ui.emptyText:SetText("Items appear here once AuctionMin has seen them sell between your scans.")

    ui.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.footer:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -12, 12)
end

local function BuildPanel()
    panel = CreateFrame("Frame", nil, AuctionHouseFrame)
    panel:SetAllPoints(AuctionHouseFrame)
    panel:SetScript("OnShow", ns.RefreshTab)
    BuildSide()
    BuildList()
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
frame:SetScript("OnEvent", function()
    if refreshQueued or not panel or not panel:IsShown() then
        return
    end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        if panel:IsShown() then
            UpdateRows()
        end
    end)
end)
