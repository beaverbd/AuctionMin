local ADDON, ns = ...

local LABEL_R, LABEL_G, LABEL_B = 1, 0.82, 0

local function BagStackCount(tooltip)
    if not tooltip.GetProcessingTooltipInfo then
        return
    end
    local info = tooltip:GetProcessingTooltipInfo()
    if not info or info.getterName ~= "GetBagItem" or not info.getterArgs then
        return
    end
    local item = C_Container.GetContainerItemInfo(info.getterArgs[1], info.getterArgs[2])
    return item and item.stackCount
end

local function TooltipLink(data)
    if data.guid and not ns.isSecret(data.guid) then
        local link = C_Item.GetItemLinkByGUID(data.guid)
        if link then
            return link
        end
    end
    if data.hyperlink and not ns.isSecret(data.hyperlink) then
        return data.hyperlink
    end
end

local function OnItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
        return
    end
    local db = ns.db
    if not db or (db.requireShift and tooltip == GameTooltip and not IsShiftKeyDown()) then
        return
    end
    local itemID = data and data.id
    if not itemID or ns.isSecret(itemID) then
        return
    end
    local link = ns.IsEquippable(itemID) and TooltipLink(data) or nil
    local key = ns.PriceKey(itemID, link)
    local price, seenAt = ns.GetPrice(key)
    if not price then
        return
    end

    local value, basis, sales = ns.ValuePrice(key)
    local lines = {}
    if db.showSold and basis == "sales" then
        lines[#lines + 1] = { ("Sells at |cff808080(%s sales)|r"):format(FormatLargeNumber(math.floor(sales + 0.5))),
            ns.FormatMoney(value) }
    end
    if db.showListed then
        lines[#lines + 1] = { "Listed at", ns.FormatMoney(price) }
    end
    if db.showStack then
        local count = BagStackCount(tooltip)
        if count and count > 1 then
            lines[#lines + 1] = { ("Stack of %d"):format(count), ns.FormatMoney(value * count) }
        end
    end
    if db.showActivity then
        local activity = ns.ActivityText(key)
        if activity then
            lines[#lines + 1] = { activity }
        end
    end
    if db.showTrend then
        local change, span = ns.GetTrend(key, price)
        if change then
            lines[#lines + 1] = { ns.TrendText(change, span) }
        end
    end
    if #lines == 0 then
        return
    end

    local title = "Auction House"
    if db.showAge then
        title = title .. " |cff808080(updated " .. ns.FormatAge(ns.Now() - seenAt) .. " ago)|r"
    end
    tooltip:AddLine(" ")
    tooltip:AddLine(title, LABEL_R, LABEL_G, LABEL_B)
    for _, line in ipairs(lines) do
        if line[2] then
            tooltip:AddDoubleLine("   " .. line[1], line[2], 1, 1, 1, 1, 1, 1)
        else
            tooltip:AddLine("   " .. line[1], 1, 1, 1)
        end
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)

local frame = CreateFrame("Frame")
frame:RegisterEvent("MODIFIER_STATE_CHANGED")
frame:SetScript("OnEvent", function(_, _, key)
    if not (ns.db and ns.db.requireShift) or (key ~= "LSHIFT" and key ~= "RSHIFT") then
        return
    end
    if InCombatLockdown() or not GameTooltip:IsShown() or not GameTooltip.RefreshData
        or not GameTooltip:IsTooltipType(Enum.TooltipDataType.Item) then
        return
    end
    GameTooltip:RefreshData()
end)
