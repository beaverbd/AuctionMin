local ADDON, ns = ...

local SCAN_COOLDOWN = 15 * 60 + 5
local RESPONSE_TIMEOUT = 60
local READ_BATCH_SIZE = 2000
local SAVE_BATCH_SIZE = 500
local MISSING_RETRY_DELAY = 3

local state = "idle"
local token = 0
local button, ticker

local function AuctionHouseOpen()
    return AuctionHouseFrame and AuctionHouseFrame:IsShown()
end

function ns.CooldownLeft()
    return math.max(0, ns.db.lastScanAt + SCAN_COOLDOWN - ns.Now())
end

local function UpdateButton()
    if not button then
        return
    end
    if state == "waiting" then
        button:SetText("Waiting for AH...")
        button:Disable()
    elseif state == "reading" or state == "saving" then
        button:SetText("Reading...")
        button:Disable()
    else
        local left = ns.CooldownLeft()
        if left > 0 then
            button:SetText((ns.db.watch and "Watching " or "Full scan ") .. SecondsToClock(left))
            button:Disable()
        else
            button:SetText("Full scan")
            button:Enable()
        end
    end
end

local function SetState(newState)
    state = newState
    UpdateButton()
end

local function Finish(total, keyCount, skipped, compared)
    SetState("idle")
    if skipped > 0 then
        ns.Print("scan done: %d auctions, %d items with a buyout, %d auctions skipped (item data not loaded).",
            total, keyCount, skipped)
    else
        ns.Print("scan done: %d auctions, %d items with a buyout.", total, keyCount)
    end
    if ns.ObservedSeconds() < ns.MIN_OBSERVED then
        ns.Print("activity needs more data: %s.", ns.SCAN_ADVICE)
    elseif not compared then
        ns.Print("activity: the previous full scan is more than 2 hours old, this scan starts a new comparison.")
    end
    ns.CheckNewDeals()
    if ns.RefreshTab then
        ns.RefreshTab()
    end
    ns.RefreshHighlights()
end

local function Save(scan, total, skipped)
    SetState("saving")
    local realm = ns.realm
    local keys = {}
    for key in pairs(scan.prices) do
        keys[#keys + 1] = key
    end
    local now = ns.Now()
    local previousScanAt = realm.scannedAt
    local index = 0

    local function Step()
        local stop = math.min(#keys, index + SAVE_BATCH_SIZE)
        for i = index + 1, stop do
            local key = keys[i]
            ns.ApplyPrice(key, scan.prices[key], now, nil, scan.links[key], scan.own[key])
        end
        index = stop
        if index < #keys then
            C_Timer.After(0, Step)
            return
        end

        for key, entry in pairs(realm.items) do
            if not scan.prices[key] then
                ns.MarkUnlisted(entry)
            end
        end
        realm.scannedAt = now
        for _, sequence in pairs(scan.sequences) do
            table.sort(sequence, function(a, b) return a[4] < b[4] end)
        end
        ns.ObserveScan(scan.sequences, now, previousScanAt, function(compared)
            Finish(total, #keys, skipped, compared)
        end)
    end

    Step()
end

local requested = {}

local function ReadRow(scan, i)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, ownerFullName, _, itemID =
        C_AuctionHouse.GetReplicateItemInfo(i)
    if not (itemID and buyout and buyout > 0 and count and count > 0) then
        return true
    end
    local key, link = itemID, nil
    if ns.IsEquippable(itemID) then
        link = C_AuctionHouse.GetReplicateItemLink(i)
        if not link then
            if not requested[itemID] then
                requested[itemID] = true
                C_Item.RequestLoadItemDataByID(itemID)
            end
            return false
        end
        key = ns.PriceKey(itemID, link)
    end

    local unitPrice = math.max(1, math.floor(buyout / count + 0.5))
    local counts = scan.prices[key]
    if not counts then
        counts = {}
        scan.prices[key] = counts
        scan.sequences[key] = {}
        if type(key) == "string" then
            scan.links[key] = link
        end
    end
    counts[unitPrice] = (counts[unitPrice] or 0) + count

    local seller = ns.SellerName(ownerFullName or owner)
    if seller ~= ns.playerName then
        local timeLeft = C_AuctionHouse.GetReplicateItemTimeLeft(i) or 1
        local band = math.max(0, math.min(3, timeLeft - 1))
        local sequence = scan.sequences[key]
        sequence[#sequence + 1] = { unitPrice, count, band, i }
    else
        local own = scan.own[key]
        if not own then
            own = {}
            scan.own[key] = own
        end
        own[unitPrice] = (own[unitPrice] or 0) + count
    end
    return true
end

local function ReadResults()
    if state ~= "waiting" then
        return
    end
    SetState("reading")
    local myToken = token
    local total = C_AuctionHouse.GetNumReplicateItems()
    local scan = { prices = {}, sequences = {}, links = {}, own = {} }
    local missing = {}
    local index = 0

    local function Retry()
        if token ~= myToken then
            return
        end
        local skipped = 0
        for _, i in ipairs(missing) do
            if not ReadRow(scan, i) then
                skipped = skipped + 1
            end
        end
        Save(scan, total, skipped)
    end

    local function Step()
        if token ~= myToken then
            return
        end
        local stop = math.min(total, index + READ_BATCH_SIZE)
        for i = index, stop - 1 do
            if not ReadRow(scan, i) then
                missing[#missing + 1] = i
            end
        end
        index = stop
        if index < total then
            C_Timer.After(0, Step)
        elseif #missing > 0 then
            C_Timer.After(MISSING_RETRY_DELAY, Retry)
        else
            Save(scan, total, 0)
        end
    end

    Step()
end

function ns.StartScan(silent)
    if state ~= "idle" then
        return
    end
    if not AuctionHouseOpen() then
        if not silent then
            ns.Print("open the auction house first.")
        end
        return
    end
    local left = ns.CooldownLeft()
    if left > 0 then
        if not silent then
            ns.Print("a full scan is allowed once per 15 minutes, %s left.", SecondsToClock(left))
        end
        return
    end

    token = token + 1
    local myToken = token
    ns.db.lastScanAt = ns.Now()
    SetState("waiting")
    ns.Print("scanning the auction house...")
    C_AuctionHouse.ReplicateItems()

    C_Timer.After(RESPONSE_TIMEOUT, function()
        if state == "waiting" and token == myToken then
            token = token + 1
            SetState("idle")
            ns.Print("the auction house didn't answer. Try again later.")
        end
    end)
end

local function Tick()
    UpdateButton()
    if ns.db.watch and state == "idle" and AuctionHouseOpen() and ns.CooldownLeft() == 0 then
        ns.StartScan(true)
    end
end

local function CreateButton()
    if button or not AuctionHouseFrame then
        return
    end
    button = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
    button:SetSize(150, 22)
    button:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -8, -2)
    button:SetScript("OnClick", function()
        ns.StartScan()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("AuctionMin")
        local scannedAt = ns.realm.scannedAt
        GameTooltip:AddLine(scannedAt > 0 and ("Last scan: " .. ns.FormatAge(ns.Now() - scannedAt) .. " ago") or "No scans yet",
            1, 1, 1)
        if ns.db.watch then
            GameTooltip:AddLine("Watching deals: a new scan starts as soon as the timer runs out.", 0.25, 1, 0.25, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
frame:SetScript("OnEvent", function(_, event)
    if not ns.db then
        return
    end
    if event == "AUCTION_HOUSE_SHOW" then
        C_Timer.After(0, function()
            CreateButton()
            UpdateButton()
            ns.CreateTab()
            ns.InstallHighlights()
            ns.SeedDealWatch()
        end)
        if not ticker then
            ticker = C_Timer.NewTicker(1, Tick)
        end
        if ns.db.auto and ns.CooldownLeft() == 0 then
            C_Timer.After(1, function()
                ns.StartScan(true)
            end)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        if state == "waiting" or state == "reading" then
            token = token + 1
            SetState("idle")
            ns.Print("scan cancelled: the auction house was closed.")
        end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        ReadResults()
    end
end)
