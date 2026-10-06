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

local function SerializeSequence(sequence)
    local parts = {}
    for i, lot in ipairs(sequence) do
        parts[i] = ("%.0f:%d:%d"):format(lot[1], lot[2], lot[3])
    end
    return table.concat(parts, ",")
end

local function ParseSequence(text)
    local sequence = {}
    for price, count, band in text:gmatch("(%d+):(%d+):(%d)") do
        sequence[#sequence + 1] = { tonumber(price), tonumber(count), tonumber(band) }
    end
    return sequence
end

local function LotsFromSequence(sequence)
    local byPrice, lots = {}, {}
    for _, lot in ipairs(sequence) do
        local price = tostring(lot[1])
        local entry = byPrice[price]
        if not entry then
            entry = { "", price, 0, 0, 0, 0 }
            byPrice[price] = entry
            lots[#lots + 1] = entry
        end
        entry[lot[3] + 3] = entry[lot[3] + 3] + lot[2]
    end
    return lots
end

local function GroupsFromSequence(sequence)
    local groups = {}
    for _, lot in ipairs(sequence) do
        ns.AddLot(groups, "", lot[1], lot[3], lot[2])
    end
    return groups
end

local function Compatible(before, after)
    return after[1] == before[1] and after[2] <= before[2] and after[3] <= before[3]
end

local function TrackedSold(previous, current, dt)
    local matchedPrevious, matchedCurrent = {}, {}
    local j = 1
    for i, lot in ipairs(previous) do
        local candidate = current[j]
        if candidate and Compatible(lot, candidate) then
            matchedPrevious[i], matchedCurrent[j] = j, true
            j = j + 1
        end
    end

    local unmatchedByPrice = {}
    for k, lot in ipairs(current) do
        if not matchedCurrent[k] then
            local list = unmatchedByPrice[lot[1]]
            if not list then
                list = {}
                unmatchedByPrice[lot[1]] = list
            end
            list[#list + 1] = k
        end
    end
    for i, lot in ipairs(previous) do
        local list = not matchedPrevious[i] and unmatchedByPrice[lot[1]]
        if list then
            for n, k in ipairs(list) do
                if Compatible(lot, current[k]) then
                    matchedPrevious[i] = k
                    table.remove(list, n)
                    break
                end
            end
        end
    end

    local cheapest = math.huge
    local sold, soldByPrice = 0, {}
    local function Add(price, units)
        sold = sold + units
        soldByPrice[price] = (soldByPrice[price] or 0) + units
    end
    for i, k in pairs(matchedPrevious) do
        local lot = previous[i]
        cheapest = math.min(cheapest, lot[1])
        local bought = lot[2] - current[k][2]
        if bought > 0 then
            Add(lot[1], bought)
        end
    end
    for i, lot in ipairs(previous) do
        if not matchedPrevious[i] and BAND_MIN_REMAINING[lot[3]] >= dt and lot[1] <= cheapest then
            Add(lot[1], lot[2])
        end
    end
    if sold > 0 then
        return sold, soldByPrice
    end
    return 0
end

local function GroupUnits(group)
    return group[1] + group[2] + group[3] + group[4]
end

local NO_BANDS = { 0, 0, 0, 0 }

local function Survivors(previousBands, currentBands)
    local pool, survivors = 0, 0
    for band = 4, 1, -1 do
        pool = pool + previousBands[band]
        local take = math.min(currentBands[band], pool)
        pool = pool - take
        survivors = survivors + take
    end
    return survivors
end

local function SoldCheapestFirst(previousByPrice, expirableByPrice, previousBands, currentBands)
    local prices = {}
    for price in pairs(previousByPrice) do
        prices[#prices + 1] = price
    end
    table.sort(prices, function(a, b) return tonumber(a) < tonumber(b) end)

    local sold, soldByPrice = 0, {}
    for _, price in ipairs(prices) do
        local still = Survivors(previousBands[price], currentBands[price] or NO_BANDS)
        local proven = math.max(0, previousByPrice[price] - still - expirableByPrice[price])
        if proven > 0 then
            sold = sold + proven
            soldByPrice[tonumber(price)] = proven
        end
        if still > 0 then
            break
        end
    end
    if sold > 0 then
        return sold, soldByPrice
    end
    return 0
end

local function HasUnknownSellers(previous, current)
    for _, lot in ipairs(previous) do
        if lot[1] == "" then
            return true
        end
    end
    for _, group in pairs(current) do
        if group[5] == "" then
            return true
        end
    end
    return false
end

local function SoldUnits(previous, current, dt)
    local previousByPrice, expirableByPrice, previousByGroup, previousBands = {}, {}, {}, {}
    for _, lot in ipairs(previous) do
        local price = lot[2]
        local bands = previousBands[price]
        if not bands then
            bands = { 0, 0, 0, 0 }
            previousBands[price] = bands
        end
        local units, expirable = 0, 0
        for band = 0, 3 do
            local n = lot[band + 3]
            units = units + n
            bands[band + 1] = bands[band + 1] + n
            if BAND_MIN_REMAINING[band] < dt then
                expirable = expirable + n
            end
        end
        previousByPrice[price] = (previousByPrice[price] or 0) + units
        expirableByPrice[price] = (expirableByPrice[price] or 0) + expirable
        previousByGroup[lot[1] .. "," .. price] = units
    end

    local currentByPrice, currentBands = {}, {}
    for groupKey, group in pairs(current) do
        local price = groupKey:match(",(%d+)$")
        currentByPrice[price] = (currentByPrice[price] or 0) + GroupUnits(group)
        local bands = currentBands[price]
        if not bands then
            bands = { 0, 0, 0, 0 }
            currentBands[price] = bands
        end
        for band = 1, 4 do
            bands[band] = bands[band] + group[band]
        end
    end

    if HasUnknownSellers(previous, current) then
        return SoldCheapestFirst(previousByPrice, expirableByPrice, previousBands, currentBands)
    end

    local proven, goneByPrice = 0, {}
    for price, units in pairs(previousByPrice) do
        local gone = math.max(0, units - (currentByPrice[price] or 0) - expirableByPrice[price])
        if gone > 0 then
            proven = proven + gone
            goneByPrice[tonumber(price)] = gone
        end
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
    local sold = math.max(0, proven - reposted)
    if sold > 0 then
        local share = sold / proven
        for price, gone in pairs(goneByPrice) do
            goneByPrice[price] = gone * share
        end
        return sold, goneByPrice
    end
    return 0
end

local BUCKET_STEP = math.log(1.05)

local function ParseDistribution(text)
    local buckets = {}
    if type(text) == "string" then
        for bucket, units, value in text:gmatch("(%-?%d+):([%d.]+):([%d.]+)") do
            buckets[tonumber(bucket)] = { tonumber(units), tonumber(value) }
        end
    end
    return buckets
end

local function AddToDistribution(entry, soldByPrice, now)
    local buckets = ParseDistribution(entry[6])
    local factor = entry[7] and 0.5 ^ (math.max(0, now - entry[7]) / ns.HALF_LIFE) or 1
    for _, bucket in pairs(buckets) do
        bucket[1], bucket[2] = bucket[1] * factor, bucket[2] * factor
    end
    for price, units in pairs(soldByPrice) do
        local index = math.floor(math.log(price) / BUCKET_STEP)
        local bucket = buckets[index]
        if not bucket then
            bucket = { 0, 0 }
            buckets[index] = bucket
        end
        bucket[1], bucket[2] = bucket[1] + units, bucket[2] + units * price
    end
    local parts = {}
    for index, bucket in pairs(buckets) do
        if bucket[1] >= 0.01 then
            parts[#parts + 1] = ("%d:%.2f:%.0f"):format(index, bucket[1], bucket[2])
        end
    end
    entry[6], entry[7] = table.concat(parts, ";"), now
end

function ns.SoldDistribution(key)
    local entry = ns.realm and ns.realm.activity[key]
    if not entry or not entry[6] then
        return nil
    end
    local buckets = ParseDistribution(entry[6])
    local list, total = {}, 0
    for index, bucket in pairs(buckets) do
        list[#list + 1] = { index, bucket[1], bucket[2] / bucket[1] }
        total = total + bucket[1]
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local factor = 0.5 ^ (math.max(0, ns.Now() - entry[7]) / ns.HALF_LIFE)
    return list, total, total * factor
end

local function AddActivity(key, sold, soldByPrice, dt, now)
    local activity = ns.realm.activity
    local entry = activity[key]
    if entry then
        local since = entry[3]
        entry[1] = ns.Decay(entry[1], since, now) + sold
        entry[2] = ns.Decay(entry[2], since, now) + dt
        entry[3] = now
    else
        entry = { sold, dt, now }
        activity[key] = entry
    end
    if soldByPrice then
        AddToDistribution(entry, soldByPrice, now)
    end
    ns.RecordSales(key, sold, dt, now)
end

function ns.ObserveLots(key, groups, now, sequence)
    local lots = ns.realm.lots
    local previous = lots[key]
    local compared = false
    if previous then
        local dt = now - previous.at
        if dt < MIN_GAP then
            return false
        end
        if dt <= MAX_GAP then
            local sold, soldByPrice
            if sequence and previous.seq then
                sold, soldByPrice = TrackedSold(ParseSequence(previous.seq), sequence, dt)
            else
                local before = previous.seq and LotsFromSequence(ParseSequence(previous.seq))
                    or ParseGroups(previous.data or "")
                sold, soldByPrice = SoldUnits(before, sequence and GroupsFromSequence(sequence) or groups, dt)
            end
            AddActivity(key, sold, soldByPrice, dt, now)
            compared = true
        end
    end
    if sequence then
        lots[key] = #sequence > 0 and { at = now, seq = SerializeSequence(sequence) } or nil
    elseif next(groups) then
        lots[key] = { at = now, data = ns.SerializeGroups(groups) }
    else
        lots[key] = nil
    end
    return compared
end

function ns.ObserveScan(scanSequences, now, previousScanAt, done)
    local realm = ns.realm
    local keys = {}
    for key in pairs(scanSequences) do
        keys[#keys + 1] = key
    end
    for key in pairs(realm.lots) do
        if not scanSequences[key] then
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
            if ns.ObserveLots(key, nil, now, scanSequences[key] or empty) then
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
