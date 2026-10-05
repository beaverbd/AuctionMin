local ADDON, ns = ...

local SCAN_COOLDOWN = 15 * 60 + 5
local RESPONSE_TIMEOUT = 60
local BATCH_SIZE = 2000

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
    elseif state == "reading" then
        button:SetText("Reading...")
        button:Disable()
    else
        local left = ns.CooldownLeft()
        if left > 0 then
            button:SetText("Full scan " .. SecondsToClock(left))
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

local function Finish(minPrices, total)
    local now = ns.Now()
    local items = ns.realm.items
    local n = 0
    for itemID, price in pairs(minPrices) do
        items[itemID] = { price, now }
        n = n + 1
    end
    ns.realm.scannedAt = now
    SetState("idle")
    ns.Print("scan done: %d auctions, %d items with a buyout.", total, n)
end

local function ReadResults()
    if state ~= "waiting" then
        return
    end
    SetState("reading")
    local myToken = token
    local total = C_AuctionHouse.GetNumReplicateItems()
    local minPrices = {}
    local index = 0

    local function Step()
        if token ~= myToken then
            return
        end
        local stop = math.min(total, index + BATCH_SIZE)
        for i = index, stop - 1 do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
            if itemID and buyout and buyout > 0 and count and count > 0 then
                local unitPrice = math.floor(buyout / count + 0.5)
                local best = minPrices[itemID]
                if not best or unitPrice < best then
                    minPrices[itemID] = unitPrice
                end
            end
        end
        index = stop
        if index < total then
            C_Timer.After(0, Step)
        else
            Finish(minPrices, total)
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
        end)
        if not ticker then
            ticker = C_Timer.NewTicker(1, UpdateButton)
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
        if state ~= "idle" then
            token = token + 1
            SetState("idle")
            ns.Print("scan cancelled: the auction house was closed.")
        end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        ReadResults()
    end
end)
