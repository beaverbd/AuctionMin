local ADDON, ns = ...

local RENOTIFY_DROP = 0.9
local ALERT_LINES = 5

local known
local newDeals = {}

local function Money(copper)
    return ns.FormatMoney(math.floor(copper + 0.5))
end

local function GoldOnly(copper)
    if copper >= 10000 then
        copper = math.floor(copper / 10000) * 10000
    end
    return Money(copper)
end

local function SellingRate(key)
    local perDay, _, hasSales, sold = ns.GetActivity(key)
    if perDay and hasSales and not ns.FewSales(sold) then
        return perDay, sold
    end
end

function ns.EvaluateDeal(key, item, now)
    local lots = item[6]
    if type(lots) ~= "string" or now - item[2] > ns.DEAL_MAX_AGE then
        return nil
    end
    local perDay, sold = SellingRate(key)
    if not perDay then
        return nil
    end
    local filters = ns.db.dealFilters
    local resale, basis = ns.ResalePrice(key, item[1])
    if filters.confirmed and basis ~= "sales" then
        return nil
    end

    local limit = resale * (1 - filters.minBelow / 100)
    if filters.maxPrice > 0 then
        limit = math.min(limit, filters.maxPrice)
    end
    local net = resale * (1 - ns.AH_CUT)
    local budget = perDay * ns.RESALE_DAYS
    local units, cost, profit = 0, 0, 0
    for price, count in lots:gmatch("(%d+):(%d+)") do
        price, count = tonumber(price), tonumber(count)
        if price > limit then
            break
        end
        if price >= filters.minPrice then
            units = units + count
            cost = cost + price * count
            local take = math.min(count, budget)
            if take > 0 then
                profit = profit + take * (net - price)
                budget = budget - take
            end
        end
    end
    if units == 0 or profit < math.max(1, filters.minProfit) then
        return nil
    end

    local deal = cost / units
    return {
        key = key,
        deal = deal,
        discount = 1 - deal / resale,
        resale = resale,
        basis = basis,
        tier = basis == "listings" and 2 or 1,
        available = units,
        rate = perDay,
        sold = sold,
        profit = profit,
    }
end

function ns.FindDeals(entries)
    local now = ns.Now()
    for key, item in pairs(ns.realm.items) do
        local entry = ns.EvaluateDeal(key, item, now)
        if entry then
            entries[#entries + 1] = entry
        end
    end
    return entries
end

function ns.DealDiscount(key, unitPrice, quantity)
    local item = key and ns.realm.items[key]
    if not item or not unitPrice or unitPrice <= 0 then
        return nil
    end
    local perDay = SellingRate(key)
    if not perDay then
        return nil
    end
    local filters = ns.db.dealFilters
    if unitPrice < filters.minPrice or (filters.maxPrice > 0 and unitPrice > filters.maxPrice) then
        return nil
    end
    local resale, basis = ns.ResalePrice(key, item[1])
    if filters.confirmed and basis ~= "sales" then
        return nil
    end
    local discount = 1 - unitPrice / resale
    if discount < filters.minBelow / 100 then
        return nil
    end
    if quantity then
        local profit = math.min(quantity, perDay * ns.RESALE_DAYS) * (resale * (1 - ns.AH_CUT) - unitPrice)
        if profit < math.max(1, filters.minProfit) then
            return nil
        end
    end
    return discount, resale
end

local function CurrentDeals()
    local current = {}
    for _, entry in ipairs(ns.FindDeals({})) do
        current[entry.key] = entry
    end
    return current
end

function ns.ResetDealWatch()
    known = {}
    for key, entry in pairs(CurrentDeals()) do
        known[key] = entry.deal
    end
    wipe(newDeals)
end

function ns.SeedDealWatch()
    if not known then
        ns.ResetDealWatch()
    end
end

function ns.IsNewDeal(key)
    return newDeals[key]
end

function ns.DealFiltersChanged()
    if ns.db.watch then
        ns.ResetDealWatch()
    end
    if ns.RefreshTab then
        ns.RefreshTab()
    end
    ns.RefreshHighlights()
end

local function Announce(fresh)
    table.sort(fresh, function(a, b)
        if a.tier ~= b.tier then
            return a.tier < b.tier
        end
        return a.profit > b.profit
    end)
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    if FlashClientIcon then
        FlashClientIcon()
    end
    for i = 1, math.min(#fresh, ALERT_LINES) do
        local entry = fresh[i]
        local link = ns.KeyLink(entry.key) or ("item " .. ns.KeyItemID(entry.key))
        ns.Print("new deal: %s x%s at %s, %d%% below resale, profit %s.", link, FormatLargeNumber(entry.available),
            Money(entry.deal), math.floor(entry.discount * 100 + 0.5), GoldOnly(entry.profit))
    end
    if #fresh > ALERT_LINES then
        ns.Print("%d more new deals in the Deals tab.", #fresh - ALERT_LINES)
    end
end

function ns.CheckNewDeals()
    if not ns.db.watch then
        return
    end
    local current = CurrentDeals()
    local fresh = {}
    wipe(newDeals)
    for key, entry in pairs(current) do
        local before = known and known[key]
        if not before or entry.deal < before * RENOTIFY_DROP then
            fresh[#fresh + 1] = entry
            newDeals[key] = true
        end
    end
    known = {}
    for key, entry in pairs(current) do
        known[key] = entry.deal
    end
    if #fresh > 0 then
        Announce(fresh)
    end
end
