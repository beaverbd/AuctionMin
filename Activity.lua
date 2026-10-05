local ADDON, ns = ...

local MIN_GAP = 5 * 60
local MAX_GAP = 2 * 60 * 60
local BATCH_SIZE = 300
local BAND_MIN_REMAINING = { [0] = 0, [1] = 30 * 60, [2] = 2 * 60 * 60, [3] = 12 * 60 * 60 }

if C_AuctionHouse and C_AuctionHouse.GetTimeLeftBandInfo then
    for band = 0, 3 do
        local ok, minSeconds = pcall(C_AuctionHouse.GetTimeLeftBandInfo, band)
        if ok and type(minSeconds) == "number" then
            BAND_MIN_REMAINING[band] = minSeconds
        end
    end
end

function ns.BandForSeconds(seconds)
    if not seconds or seconds <= 0 then
        return 0
    end
    for band = 3, 1, -1 do
        if seconds >= BAND_MIN_REMAINING[band] then
            return band
        end
    end
    return 0
end

function ns.AddLot(groups, owner, price, band, count)
    local groupKey = owner .. "," .. price
    local group = groups[groupKey]
    if not group then
        group = { 0, 0, 0, 0, owner }
        groups[groupKey] = group
    end
    group[band + 1] = group[band + 1] + count
end

function ns.SerializeGroups(groups)
    local parts = {}
    for groupKey, group in pairs(groups) do
        parts[#parts + 1] = ("%s,%d,%d,%d,%d"):format(groupKey, group[1], group[2], group[3], group[4])
    end
    return table.concat(parts, ";")
end

local function ParseGroups(text)
    local lots = {}
    for owner, price, b0, b1, b2, b3 in text:gmatch("([^,;]*),(%d+),(%d+),(%d+),(%d+),(%d+)") do
        lots[#lots + 1] = { owner, price, tonumber(b0), tonumber(b1), tonumber(b2), tonumber(b3) }
    end
    return lots
end

local function GroupUnits(group)
    return group[1] + group[2] + group[3] + group[4]
end

local function SoldUnits(previous, current, dt)
    local previousByPrice, expirableByPrice, previousByGroup = {}, {}, {}
    for _, lot in ipairs(previous) do
        local price = lot[2]
        local units, expirable = 0, 0
        for band = 0, 3 do
            local n = lot[band + 3]
            units = units + n
            if BAND_MIN_REMAINING[band] < dt then
                expirable = expirable + n
            end
        end
        previousByPrice[price] = (previousByPrice[price] or 0) + units
        expirableByPrice[price] = (expirableByPrice[price] or 0) + expirable
        previousByGroup[lot[1] .. "," .. price] = units
    end

    local currentByPrice = {}
    for groupKey, group in pairs(current) do
        local price = groupKey:match(",(%d+)$")
        currentByPrice[price] = (currentByPrice[price] or 0) + GroupUnits(group)
    end

    local proven = 0
    for price, units in pairs(previousByPrice) do
        proven = proven + math.max(0, units - (currentByPrice[price] or 0) - expirableByPrice[price])
    end
    if proven == 0 then
        return 0
    end

    local shrinkByOwner = {}
    for _, lot in ipairs(previous) do
        local groupKey = lot[1] .. "," .. lot[2]
        local still = current[groupKey]
        local shrink = previousByGroup[groupKey] - (still and GroupUnits(still) or 0)
        if shrink > 0 then
            shrinkByOwner[lot[1]] = (shrinkByOwner[lot[1]] or 0) + shrink
        end
    end
    local growthByOwner = {}
    for groupKey, group in pairs(current) do
        local owner = group[5]
        if shrinkByOwner[owner] then
            local growth = GroupUnits(group) - (previousByGroup[groupKey] or 0)
            if growth > 0 then
                growthByOwner[owner] = (growthByOwner[owner] or 0) + growth
            end
        end
    end

    local reposted = 0
    for owner, shrink in pairs(shrinkByOwner) do
        reposted = reposted + math.min(shrink, growthByOwner[owner] or 0)
    end
    return math.max(0, proven - reposted)
end

local function AddActivity(key, sold, dt, now)
    local activity = ns.realm.activity
    local entry = activity[key]
    if entry then
        entry[1] = ns.Decay(entry[1], entry[3], now) + sold
        entry[2] = ns.Decay(entry[2], entry[3], now) + dt
        entry[3] = now
    else
        activity[key] = { sold, dt, now }
    end
    ns.RecordSales(key, sold, dt, now)
end

function ns.ObserveLots(key, groups, now)
    local lots = ns.realm.lots
    local previous = lots[key]
    local compared = false
    if previous then
        local dt = now - previous.at
        if dt < MIN_GAP then
            return false
        end
        if dt <= MAX_GAP then
            AddActivity(key, SoldUnits(ParseGroups(previous.data), groups, dt), dt, now)
            compared = true
        end
    end
    if next(groups) then
        lots[key] = { at = now, data = ns.SerializeGroups(groups) }
    else
        lots[key] = nil
    end
    return compared
end

function ns.ObserveScan(scanGroups, now, previousScanAt, done)
    local realm = ns.realm
    local keys = {}
    for key in pairs(scanGroups) do
        keys[#keys + 1] = key
    end
    for key in pairs(realm.lots) do
        if not scanGroups[key] then
            keys[#keys + 1] = key
        end
    end
    local empty = {}
    local index = 0
    local comparedKeys = 0

    local function Step()
        local stop = math.min(#keys, index + BATCH_SIZE)
        for i = index + 1, stop do
            local key = keys[i]
            if ns.ObserveLots(key, scanGroups[key] or empty, now) then
                comparedKeys = comparedKeys + 1
            end
        end
        index = stop
        if index < #keys then
            C_Timer.After(0, Step)
            return
        end

        local dt = now - previousScanAt
        local compared = comparedKeys > 0 and previousScanAt > 0 and dt > 0 and dt <= MAX_GAP
        if compared then
            local observed = realm.observed
            observed[1] = ns.Decay(observed[1], observed[2], now) + dt
            observed[2] = now
        end
        done(compared)
    end

    Step()
end
