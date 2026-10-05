local ADDON, ns = ...

ns.isSecret = issecretvalue or function() return false end

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

function ns.GetPrice(key)
    local entry = ns.realm and ns.realm.items[key]
    if entry then
        return math.floor(entry[1] + 0.5), entry[2], entry[3]
    end
end

local function CountItems()
    local n = 0
    for _ in pairs(ns.realm.items) do
        n = n + 1
    end
    return n
end

local DB_VERSION = 2

local function InitDB()
    local fresh = AuctionMinDB == nil
    AuctionMinDB = AuctionMinDB or {}
    local db = AuctionMinDB
    if not fresh and (db.version or 1) < DB_VERSION then
        db.realms = nil
        ns.Print("prices are now market prices: stored data was reset, please run a new scan.")
    end
    db.version = DB_VERSION
    if db.auto == nil then
        db.auto = true
    end
    db.lastScanAt = db.lastScanAt or 0
    db.realms = db.realms or {}

    local realmName = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
    local key = realmName .. "-" .. (UnitFactionGroup("player") or "Neutral")
    db.realms[key] = db.realms[key] or { scannedAt = 0, items = {} }

    ns.db = db
    ns.realmKey = key
    ns.realm = db.realms[key]
end

local function PrintStatus()
    local realm = ns.realm
    ns.Print("%s: %d items, last scan %s.", ns.realmKey, CountItems(),
        realm.scannedAt > 0 and (ns.FormatAge(ns.Now() - realm.scannedAt) .. " ago") or "never")
    local left = ns.CooldownLeft()
    ns.Print("auto scan: %s, next full scan %s.", ns.db.auto and "on" or "off",
        left > 0 and ("in " .. SecondsToClock(left)) or "available")
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
        ns.realm.scannedAt = 0
        ns.Print("prices for %s cleared.", ns.realmKey)
    elseif cmd == "" or cmd == "help" then
        PrintHelp()
    else
        local link = msg:match("^%s*(.-)%s*$")
        local itemID = C_Item.GetItemInfoInstant(link)
        if not itemID then
            PrintHelp()
            return
        end
        local price, seenAt, lowest = ns.GetPrice(ns.PriceKey(itemID, link))
        if price then
            ns.Print("%s: market %s, lowest %s (updated %s ago)", link, ns.FormatMoney(price),
                ns.FormatMoney(lowest), ns.FormatAge(ns.Now() - seenAt))
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
