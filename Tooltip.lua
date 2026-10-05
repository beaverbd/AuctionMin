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

local function OnItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
        return
    end
    local itemID = data and data.id
    if not itemID or ns.isSecret(itemID) then
        return
    end
    local price, seenAt = ns.GetPrice(itemID)
    if not price then
        return
    end

    local age = ns.FormatAge(ns.Now() - seenAt)
    tooltip:AddLine(" ")
    tooltip:AddLine("Auction House |cff808080(scanned " .. age .. " ago)|r", LABEL_R, LABEL_G, LABEL_B)
    tooltip:AddDoubleLine("   Per item", ns.FormatMoney(price), 1, 1, 1, 1, 1, 1)

    local count = BagStackCount(tooltip)
    if count and count > 1 then
        tooltip:AddDoubleLine(("   Stack of %d"):format(count), ns.FormatMoney(price * count), 1, 1, 1, 1, 1, 1)
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
