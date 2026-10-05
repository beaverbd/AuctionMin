local ADDON, ns = ...

local DEBOUNCE = 0.5

local pending = {}

local function Enabled()
    return ns.realm and ns.db.learnFromSearches
end

local function OwnersName(owners)
    if type(owners) ~= "table" or #owners == 0 then
        return ""
    elseif #owners == 1 then
        return ns.SellerName(owners[1])
    end
    local names = {}
    for i, owner in ipairs(owners) do
        names[i] = ns.SellerName(owner)
    end
    table.sort(names)
    return table.concat(names, "+")
end

local function ItemKeyID(itemKey)
    return ("%d:%d:%d"):format(itemKey.itemID or 0, itemKey.itemLevel or 0, itemKey.itemSuffix or 0)
end

local function Queue(id, handler, value)
    if pending[id] then
        return
    end
    pending[id] = true
    C_Timer.After(DEBOUNCE, function()
        pending[id] = nil
        if Enabled() then
            handler(value)
        end
    end)
end

local function ProcessCommodity(itemID)
    local complete = C_AuctionHouse.HasFullCommoditySearchResults(itemID)
    local count = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    local counts = {}
    local previous, ascending = 0, true
    for i = 1, count do
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if info and info.quantity and info.quantity > 0 and info.unitPrice and info.unitPrice > 0 then
            local price = info.unitPrice
            if price < previous then
                ascending = false
            end
            previous = price
            counts[price] = (counts[price] or 0) + info.quantity
        end
    end

    local now = ns.Now()
    if complete then
        if next(counts) then
            ns.ApplyPrice(itemID, counts, now)
        elseif ns.realm.items[itemID] then
            ns.realm.items[itemID][4] = 0
        end
    elseif ascending and next(counts) then
        ns.ApplyPrice(itemID, counts, now, C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID))
    end
end

local function ProcessItem(itemKey)
    if not C_AuctionHouse.HasFullItemSearchResults(itemKey) then
        return
    end
    local count = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
    local byKey = {}
    for i = 1, count do
        local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if info and info.buyoutAmount and info.buyoutAmount > 0 and info.quantity and info.quantity > 0 then
            local itemID = info.itemKey and info.itemKey.itemID or itemKey.itemID
            local key = ns.PriceKey(itemID, info.itemLink)
            local data = byKey[key]
            if not data then
                data = { counts = {}, groups = {}, link = type(key) == "string" and info.itemLink or nil }
                byKey[key] = data
            end
            local unitPrice = math.max(1, math.floor(info.buyoutAmount / info.quantity + 0.5))
            data.counts[unitPrice] = (data.counts[unitPrice] or 0) + info.quantity
            local seller = OwnersName(info.owners)
            if seller ~= ns.playerName then
                local band
                if info.timeLeftSeconds and info.timeLeftSeconds > 0 then
                    band = ns.BandForSeconds(info.timeLeftSeconds)
                else
                    band = math.max(0, math.min(3, info.timeLeft or 0))
                end
                ns.AddLot(data.groups, seller, unitPrice, band, info.quantity)
            end
        end
    end

    local now = ns.Now()
    if next(byKey) then
        for key, data in pairs(byKey) do
            ns.ApplyPrice(key, data.counts, now, nil, data.link)
            ns.ObserveLots(key, data.groups, now)
        end
    else
        local key = ns.KeyFromItemKey(itemKey)
        if key then
            if ns.realm.items[key] then
                ns.realm.items[key][4] = 0
            end
            ns.ObserveLots(key, {}, now)
        end
    end
end

local function ProcessBrowse()
    local results = C_AuctionHouse.GetBrowseResults()
    if type(results) ~= "table" then
        return
    end
    local items = ns.realm.items
    for _, result in ipairs(results) do
        local key = ns.KeyFromItemKey(result.itemKey)
        local entry = key and items[key]
        if entry and result.totalQuantity then
            entry[4] = result.totalQuantity
            local info = C_AuctionHouse.GetItemKeyInfo(result.itemKey)
            if info and (info.isCommodity or info.isEquipment) and result.minPrice and result.minPrice > 0 then
                entry[3] = result.minPrice
            end
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED")
frame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
frame:SetScript("OnEvent", function(_, event, arg)
    if not Enabled() then
        return
    end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
        if type(arg) == "number" then
            Queue("c" .. arg, ProcessCommodity, arg)
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
        if type(arg) == "table" then
            Queue("i" .. ItemKeyID(arg), ProcessItem, arg)
        end
    else
        Queue("browse", ProcessBrowse)
    end
end)
