local ADDON, ns = ...

ns.isSecret = issecretvalue or function() return false end

ns.HALF_LIFE = 3 * 24 * 60 * 60
ns.MIN_OBSERVED = 25 * 60
ns.SCAN_ADVICE = "run at least 3 scans 15-60 minutes apart; scans more than 2 hours apart don't count"

function ns.Decay(value, since, now)
    return value * 0.5 ^ (math.max(0, now - since) / ns.HALF_LIFE)
end

function ns.Print(fmt, ...)
    print("|cff33ff99AuctionMin|r: " .. fmt:format(...))
end

function ns.Now()
    return GetServerTime()
end

function ns.FormatMoney(copper)
    return GetMoneyString(copper, true)
end

function ns.FormatAge(seconds)
    if seconds < 3600 then
        return ("%dm"):format(math.max(1, math.floor(seconds / 60)))
    elseif seconds < 86400 then
        return ("%dh"):format(math.floor(seconds / 3600))
    end
    return ("%dd"):format(math.floor(seconds / 86400))
end

local equippable = {}

function ns.IsEquippable(itemID)
    local cached = equippable[itemID]
    if cached == nil then
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
        cached = equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
        equippable[itemID] = cached
    end
    return cached
end

function ns.PriceKey(itemID, link)
    if not link or not ns.IsEquippable(itemID) then
        return itemID
    end
    local itemString = link:match("item:([%-%d:]*)")
    if not itemString then
        return itemID
    end
    local fields = { strsplit(":", itemString) }
    local suffix = tonumber(fields[7]) or 0
    local bonusCount = tonumber(fields[13]) or 0
    if suffix == 0 and bonusCount == 0 then
        return itemID
    end
    local key = itemID .. ":" .. suffix
    if bonusCount > 0 then
        key = key .. ":" .. table.concat(fields, ",", 14, math.min(#fields, 13 + bonusCount))
    end
    return key
end

function ns.FormatDuration(seconds)
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then
        return minutes .. " min"
    elseif minutes < 48 * 60 then
        return (("%.1f h"):format(minutes / 60):gsub("%.0 h", " h"))
    end
    return math.floor(minutes / 1440 + 0.5) .. " days"
end

function ns.SellerName(name)
    if type(name) ~= "string" or ns.isSecret(name) then
        return ""
    end
    return name:match("^[^-]*")
end

function ns.KeyFromItemKey(itemKey)
    local itemID = itemKey and itemKey.itemID
    if not itemID then
        return nil
    end
    local suffix = itemKey.itemSuffix or 0
    if suffix == 0 or not ns.IsEquippable(itemID) then
        return itemID
    end
    return itemID .. ":" .. suffix
end

function ns.GetPrice(key)
    local entry = ns.realm and ns.realm.items[key]
    if entry then
        return math.floor(entry[1] + 0.5), entry[2], entry[3], entry[4]
    end
end

function ns.ObservedSeconds()
    local observed = ns.realm and ns.realm.observed
    if not observed then
        return 0
    end
    return ns.Decay(observed[1], observed[2], ns.Now())
end

function ns.GetActivity(key)
    local entry = ns.realm and ns.realm.activity[key]
    if not entry then
        return nil
    end
    local observed = ns.Decay(entry[2], entry[3], ns.Now())
    if observed < ns.MIN_OBSERVED then
        return nil
    end
    return entry[1] / entry[2] * 86400, observed, entry[1] >= 0.5
end

function ns.FormatRate(perDay)
    if perDay < 10 then
        return ("%.1f"):format(perDay)
    end
    return FormatLargeNumber(math.floor(perDay + 0.5))
end

function ns.FormatSupply(listed, perDay)
    if not listed then
        return nil
    elseif listed == 0 then
        return "none listed"
    end
    local days = listed / perDay
    if days < 1 then
        return "<1 day"
    elseif days >= 100 then
        return "100+ days"
    end
    local n = math.floor(days + 0.5)
    return n == 1 and "1 day" or (n .. " days")
end

function ns.ActivityText(key)
    local perDay, observed, hasSales = ns.GetActivity(key)
    if not perDay then
        return nil
    elseif not hasSales then
        return ("No sales seen in %s of tracking"):format(ns.FormatDuration(observed))
    end
    local text = "Sells about " .. ns.FormatRate(perDay) .. "/day"
    local _, _, _, listed = ns.GetPrice(key)
    local supply = ns.FormatSupply(listed, perDay)
    if supply == "none listed" then
        text = text .. ", none listed"
    elseif supply then
        text = text .. ", " .. supply .. " of supply"
    end
    return text
end

local function CountItems()
    local n = 0
    for _ in pairs(ns.realm.items) do
        n = n + 1
    end
    return n
end

local DB_VERSION = 4

local function InitDB()
    local fresh = AuctionMinDB == nil
    AuctionMinDB = AuctionMinDB or {}
    local db = AuctionMinDB
    if not fresh and (db.version or 1) < 2 then
        db.realms = nil
        ns.Print("prices are now market prices: stored data was reset, please run a new scan.")
    elseif not fresh and db.version < DB_VERSION and db.realms then
        for _, realm in pairs(db.realms) do
            realm.snapshot = nil
            if db.version == 3 then
                realm.activity = nil
                realm.lots = nil
                realm.observed = nil
            end
        end
    end
    db.version = DB_VERSION
    for option, default in pairs({ auto = true, showStack = true, showActivity = true, learnFromSearches = true }) do
        if db[option] == nil then
            db[option] = default
        end
    end
    db.lastScanAt = db.lastScanAt or 0
    db.realms = db.realms or {}

    local realmName = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
    local key = realmName .. "-" .. (UnitFactionGroup("player") or "Neutral")
    db.realms[key] = db.realms[key] or { scannedAt = 0, items = {} }
    local realm = db.realms[key]
    realm.activity = realm.activity or {}
    realm.observed = realm.observed or { 0, 0 }
    realm.lots = realm.lots or {}

    ns.playerName = ns.SellerName(UnitName("player"))
    ns.db = db
    ns.realmKey = key
    ns.realm = realm
end

local function PrintStatus()
    local realm = ns.realm
    ns.Print("%s: %d items, last scan %s.", ns.realmKey, CountItems(),
        realm.scannedAt > 0 and (ns.FormatAge(ns.Now() - realm.scannedAt) .. " ago") or "never")
    local left = ns.CooldownLeft()
    ns.Print("auto scan: %s, next full scan %s.", ns.db.auto and "on" or "off",
        left > 0 and ("in " .. SecondsToClock(left)) or "available")
    local observed = ns.ObservedSeconds()
    if observed < ns.MIN_OBSERVED then
        ns.Print("activity: not enough data yet, %s.", ns.SCAN_ADVICE)
    else
        ns.Print("activity: sales tracked over %s.", ns.FormatDuration(observed))
    end
end

local function PrintHelp()
    ns.Print("/amin scan - full scan (auction house must be open)")
    ns.Print("/amin auto - toggle scan on auction house open")
    ns.Print("/amin status - data and cooldown info")
    ns.Print("/amin clear - forget prices for this realm and faction")
    ns.Print("/amin <item link> - print the stored price")
end

SLASH_AUCTIONMIN1 = "/amin"
SLASH_AUCTIONMIN2 = "/auctionmin"
SlashCmdList.AUCTIONMIN = function(msg)
    if not ns.db then
        return
    end
    local cmd = (msg:match("^%s*(%S*)") or ""):lower()
    if cmd == "scan" then
        ns.StartScan()
    elseif cmd == "auto" then
        ns.db.auto = not ns.db.auto
        ns.Print("auto scan %s.", ns.db.auto and "on" or "off")
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "clear" then
        wipe(ns.realm.items)
        wipe(ns.realm.activity)
        ns.realm.observed = { 0, 0 }
        wipe(ns.realm.lots)
        ns.realm.scannedAt = 0
        ns.Print("prices and activity for %s cleared.", ns.realmKey)
    elseif cmd == "" or cmd == "help" then
        PrintHelp()
    else
        local link = msg:match("^%s*(.-)%s*$")
        local itemID = C_Item.GetItemInfoInstant(link)
        if not itemID then
            PrintHelp()
            return
        end
        local key = ns.PriceKey(itemID, link)
        local price, seenAt, lowest = ns.GetPrice(key)
        if price then
            ns.Print("%s: market %s, lowest %s (updated %s ago)", link, ns.FormatMoney(price),
                ns.FormatMoney(lowest), ns.FormatAge(ns.Now() - seenAt))
            ns.Print("%s", ns.ActivityText(key) or ("activity: not enough data yet, " .. ns.SCAN_ADVICE .. "."))
        else
            ns.Print("%s: no price.", link)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    InitDB()
end)
