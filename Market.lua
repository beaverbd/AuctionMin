local ADDON, ns = ...

local SHARE_FACTOR = 1.5
local MIN_SHARE = 0.05
local MAX_STEP = 1.2

function ns.SnapshotPrice(prices, counts)
    local total = 0
    for _, price in ipairs(prices) do
        total = total + counts[price]
    end

    local share = math.max(MIN_SHARE, SHARE_FACTOR / math.sqrt(total))
    local lower = math.min(total, total * share)
    local upper = math.min(total, lower * 2)
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

function ns.BlendMarket(previous, previousAt, snapshot, now)
    if not previous then
        return snapshot
    end
    local weight = 1 - 0.5 ^ (math.max(0, now - previousAt) / ns.HALF_LIFE)
    return previous + weight * (snapshot - previous)
end
