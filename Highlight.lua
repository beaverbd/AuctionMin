local ADDON, ns = ...

local sources = {}
local installed = false

local function RowDeal(kind, rowData)
    if kind == "browse" then
        return ns.KeyFromItemKey(rowData.itemKey), rowData.minPrice
    elseif kind == "commodity" then
        local quantity = (rowData.quantity or 0) - (rowData.numOwnerItems or 0)
        if quantity <= 0 then
            return nil
        end
        return rowData.itemID, rowData.unitPrice, quantity
    end
    local itemID = rowData.itemKey and rowData.itemKey.itemID
    if not itemID or rowData.containsOwnerItem or not rowData.buyoutAmount or not rowData.quantity
        or rowData.quantity <= 0 then
        return nil
    end
    return ns.PriceKey(itemID, rowData.itemLink), rowData.buyoutAmount / rowData.quantity, rowData.quantity
end

local function OnEnter(frame)
    local deal = frame.auctionMinDeal
    if not deal then
        return
    end
    if GameTooltip:GetOwner() == frame and GameTooltip:IsShown() then
        GameTooltip:AddLine(" ")
    else
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    end
    GameTooltip:AddLine(("AuctionMin deal: %d%% below the resale price of %s"):format(
        math.floor(deal.discount * 100 + 0.5), ns.FormatMoney(math.floor(deal.resale + 0.5))), 0.25, 1, 0.25)
    GameTooltip:Show()
end

local function OnLeave(frame)
    if frame.auctionMinDeal and GameTooltip:GetOwner() == frame then
        GameTooltip:Hide()
    end
end

local function Mark(frame, discount, resale)
    if not discount then
        frame.auctionMinDeal = nil
        if frame.auctionMinTint then
            frame.auctionMinTint:Hide()
            frame.auctionMinBar:Hide()
        end
        return
    end
    if not frame.auctionMinTint then
        local tint = frame:CreateTexture(nil, "OVERLAY", nil, -1)
        tint:SetColorTexture(0.25, 1, 0.25, 0.12)
        tint:SetBlendMode("ADD")
        tint:SetAllPoints()
        frame.auctionMinTint = tint
        local bar = frame:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(0.3, 1, 0.3, 0.9)
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("BOTTOMLEFT")
        bar:SetWidth(3)
        frame.auctionMinBar = bar
        frame:HookScript("OnEnter", OnEnter)
        frame:HookScript("OnLeave", OnLeave)
    end
    frame.auctionMinDeal = { discount = discount, resale = resale }
    frame.auctionMinTint:Show()
    frame.auctionMinBar:Show()
end

local function Evaluate(source, elementData)
    if not (ns.realm and ns.db.highlightDeals) or type(elementData) ~= "number" or not source.list.getEntry then
        return nil
    end
    local rowData = source.list.getEntry(elementData)
    if type(rowData) ~= "table" then
        return nil
    end
    local key, unitPrice, quantity = RowDeal(source.kind, rowData)
    if key then
        return ns.DealDiscount(key, unitPrice, quantity)
    end
end

local function Update(source, frame, elementData)
    local ok, discount, resale = pcall(Evaluate, source, elementData)
    if not ok then
        geterrorhandler()(discount)
        discount = nil
    end
    Mark(frame, discount, resale)
end

function ns.RefreshHighlights()
    for _, source in ipairs(sources) do
        if source.list.isInitialized and source.list:IsVisible() then
            source.list.ScrollBox:ForEachFrame(function(frame, elementData)
                Update(source, frame, elementData)
            end)
        end
    end
end

function ns.InstallHighlights()
    if installed or not AuctionHouseFrame then
        return
    end
    installed = true
    local lists = {
        { AuctionHouseFrame.BrowseResultsFrame, "browse" },
        { AuctionHouseFrame.CommoditiesBuyFrame, "commodity" },
        { AuctionHouseFrame.ItemBuyFrame, "item" },
    }
    for _, entry in ipairs(lists) do
        local list = entry[1] and entry[1].ItemList
        if list and list.ScrollBox then
            local source = { list = list, kind = entry[2] }
            sources[#sources + 1] = source
            ScrollUtil.AddInitializedFrameCallback(list.ScrollBox, function(_, frame, elementData)
                Update(source, frame, elementData)
            end, source)
        end
    end
end
