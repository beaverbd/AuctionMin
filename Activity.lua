local ADDON, ns = ...

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
    local groups = {}
    for owner, price, b0, b1, b2, b3 in text:gmatch("([^,;]*),(%d+),(%d+),(%d+),(%d+),(%d+)") do
        groups[#groups + 1] = { owner, price, tonumber(b0), tonumber(b1), tonumber(b2), tonumber(b3) }
    end
    return groups
end

local function GroupUnits(group)
    return group[1] + group[2] + group[3] + group[4]
end

local function SoldUnits(previous, current, dt)
    local provenByOwner, previousUnits = {}, {}
    for _, lot in ipairs(previous) do
        local owner, groupKey = lot[1], lot[1] .. "," .. lot[2]
        local units, expirable = 0, 0
        for band = 0, 3 do
            local n = lot[band + 3]
            units = units + n
            if BAND_MIN_REMAINING[band] < dt then
                expirable = expirable + n
            end
        end
        previousUnits[groupKey] = units
        local still = current and current[groupKey]
        local gone = units - (still and GroupUnits(still) or 0)
        provenByOwner[owner] = (provenByOwner[owner] or 0) + math.max(0, gone - expirable)
    end

    local repostedByOwner = {}
    if current then
        for groupKey, group in pairs(current) do
            local owner = group[5]
            local growth = GroupUnits(group) - (previousUnits[groupKey] or 0)
            if growth > 0 and provenByOwner[owner] then
                repostedByOwner[owner] = (repostedByOwner[owner] or 0) + growth
            end
        end
    end

    local sold = 0
    for owner, proven in pairs(provenByOwner) do
        sold = sold + math.max(0, proven - (repostedByOwner[owner] or 0))
    end
    return sold
end

function ns.UpdateActivity(snapshot, currentGroups, now, done)
    local dt = snapshot and snapshot.at and (now - snapshot.at)
    if not dt or dt <= 0 or dt > MAX_GAP then
        done(false)
        return
    end

    local realm = ns.realm
    local activity = realm.activity
    local keys = {}
    for key in pairs(snapshot.data) do
        keys[#keys + 1] = key
    end
    local index = 0

    local function Step()
        local stop = math.min(#keys, index + BATCH_SIZE)
        for i = index + 1, stop do
            local key = keys[i]
            local sold = SoldUnits(ParseGroups(snapshot.data[key]), currentGroups[key], dt)
            local entry = activity[key]
            if entry then
                entry[1] = ns.Decay(entry[1], entry[3], now) + sold
                entry[2] = ns.Decay(entry[2], entry[3], now) + dt
                entry[3] = now
            else
                activity[key] = { sold, dt, now }
            end
        end
        index = stop
        if index < #keys then
            C_Timer.After(0, Step)
        else
            local observed = realm.observed
            observed[1] = ns.Decay(observed[1], observed[2], now) + dt
            observed[2] = now
            done(true)
        end
    end

    Step()
end
