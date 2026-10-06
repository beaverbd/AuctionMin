local ADDON, ns = ...

local KEEP_DAYS = 14
local DAY = 24 * 60 * 60
local TREND_DAYS = 7
local MIN_TREND_DAYS = 2

local function Today(now)
    return math.floor(now / DAY)
end

local function Encode(point)
    return ("%d:%.0f:%d:%.1f:%d"):format(point.day, point.price, point.listed, point.sold, point.observed)
end

local function Decode(segment)
    local day, price, listed, sold, observed = segment:match("^(%d+):(%d+):(%d+):([%d.]+):(%d+)$")
    if day then
        return { day = tonumber(day), price = tonumber(price), listed = tonumber(listed),
            sold = tonumber(sold), observed = tonumber(observed) }
    end
end

local function UpdateToday(key, now, update)
    local history = ns.realm.history
    local day = Today(now)
    local text = history[key]
    local head, point = "", nil

    if text then
        local lastComma = text:match(".*(),")
        local last = Decode(lastComma and text:sub(lastComma + 1) or text)
        if last and last.day == day then
            point = last
            head = lastComma and text:sub(1, lastComma) or ""
        else
            head = text .. ","
            local cutoff = day - KEEP_DAYS + 1
            while true do
                local first = tonumber(head:match("^(%d+):"))
                if not first or first >= cutoff then
                    break
                end
                head = head:gsub("^[^,]*,", "", 1)
            end
            if last then
                point = { day = day, price = last.price, listed = last.listed, sold = 0, observed = 0 }
            end
        end
    end

    point = point or { day = day, price = 0, listed = 0, sold = 0, observed = 0 }
    update(point)
    history[key] = head .. Encode(point)
end

function ns.RecordPrice(key, price, listed, now)
    UpdateToday(key, now, function(point)
        point.price = math.floor(price + 0.5)
        point.listed = listed or point.listed
    end)
end

function ns.RecordSales(key, sold, observed, now)
    UpdateToday(key, now, function(point)
        point.sold = point.sold + sold
        point.observed = point.observed + observed
    end)
end

function ns.GetHistory(key)
    local text = ns.realm and ns.realm.history[key]
    local points = {}
    if text then
        for segment in text:gmatch("[^,]+") do
            local point = Decode(segment)
            if point and point.price > 0 then
                points[#points + 1] = point
            end
        end
    end
    return points
end

function ns.Today()
    return Today(ns.Now())
end

function ns.GetTrend(key, currentPrice)
    local points = ns.GetHistory(key)
    if #points < 2 or not currentPrice then
        return nil
    end
    local today = Today(ns.Now())
    local past
    for _, point in ipairs(points) do
        if point.day <= today - TREND_DAYS then
            past = point
        elseif not past then
            past = point
            break
        else
            break
        end
    end
    local span = past and (today - past.day) or 0
    if span < MIN_TREND_DAYS or past.price <= 0 then
        return nil
    end
    return (currentPrice - past.price) / past.price, span
end

function ns.HistoryMedian(key)
    local today = Today(ns.Now())
    local prices = {}
    for _, point in ipairs(ns.GetHistory(key)) do
        if point.day > today - TREND_DAYS then
            prices[#prices + 1] = point.price
        end
    end
    if #prices < MIN_TREND_DAYS then
        return nil
    end
    table.sort(prices)
    return prices[math.ceil(#prices / 2)]
end

function ns.TrendText(change, span)
    local days = span == 1 and "1 day" or (span .. " days")
    local percent = math.floor(math.abs(change) * 100 + 0.5)
    if percent < 3 then
        return "Price stable over " .. days
    end
    return ("Price %s %.0f%% over %s"):format(change > 0 and "up" or "down", percent, days)
end
