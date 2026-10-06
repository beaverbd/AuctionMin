local ADDON, ns = ...

local SHARE_FACTOR = 1.5
local MIN_SHARE = 0.05
local MAX_STEP = 1.2

function ns.SnapshotPrice(prices, counts, total)
    local loaded = 0
    for _, price in ipairs(prices) do
        loaded = loaded + counts[price]
    end
    total = total or loaded

    local share = math.max(MIN_SHARE, SHARE_FACTOR / math.sqrt(total))
    local lower = math.min(total, total * share)
    local upper = math.min(total, lower * 2)
    if loaded < total and loaded < upper then
        return nil
    end

    local taken, units, previous = 0, 0, nil
    for i, price in ipairs(prices) do
        if units >= lower and (units >= upper or price > previous * MAX_STEP) then
            break
        end
        taken = i
        units = units + counts[price]
        previous = price
    end

    local cumulative = 0
    for i = 1, taken do
        cumulative = cumulative + counts[prices[i]]
        if cumulative >= units / 2 then
            return prices[i]
        end
    end
    return prices[taken]
end

local DEAL_LEVELS = 30

local function CheapListings(prices, counts, own, limit)
    local parts = {}
    for _, p in ipairs(prices) do
        if p > limit or #parts >= DEAL_LEVELS then
            break
        end
        local n = counts[p] - (own and own[p] or 0)
        if n > 0 then
            parts[#parts + 1] = p .. ":" .. n
        end
    end
    if #parts > 0 then
        return table.concat(parts, ",")
    end
end

function ns.MarkUnlisted(entry)
    entry[4] = 0
    entry[6] = nil
    entry[7] = nil
end

function ns.ApplyPrice(key, counts, now, total, link, own)
    local prices, loaded = {}, 0
    for price, count in pairs(counts) do
        prices[#prices + 1] = price
        loaded = loaded + count
    end
    if #prices == 0 then
        return
    end
    table.sort(prices)

    local items = ns.realm.items
    local entry = items[key]
    local price = ns.SnapshotPrice(prices, counts, total)
    if price then
        if not entry then
            entry = {}
            items[key] = entry
        end
        entry[1] = price
        entry[2] = now
        local cheap
        if prices[1] <= price * (1 - ns.DEAL_MIN_BELOW) then
            local resale = ns.ResalePrice(key, price)
            cheap = CheapListings(prices, counts, own, resale * (1 - ns.DEAL_MIN_BELOW))
        end
        entry[6], entry[7] = cheap, nil
    elseif not entry then
        return
    end
    entry[3] = prices[1]
    entry[4] = total or loaded
    if link then
        entry[5] = link
    end
    if price then
        ns.RecordPrice(key, price, entry[4], now)
    end
end
