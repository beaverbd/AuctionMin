local ADDON, ns = ...

local category

local SECTIONS = {
    {
        title = "Item tooltips",
        options = {
            { option = "requireShift", label = "Only while holding Shift",
                tooltip = "Show the auction house prices in item tooltips only while you hold Shift. Tooltips of "
                    .. "items linked in chat always show them." },
            { option = "showAge", label = "Data age",
                tooltip = "How long ago the prices were updated, next to the Auction House title." },
            { option = "showSold", label = "Sells at",
                tooltip = "The typical price of recent sales, shown once AuctionMin has seen at least 5 sales." },
            { option = "showListed", label = "Listed at",
                tooltip = "The price of the current listings." },
            { option = "showStack", label = "Stack value",
                tooltip = "The value of the whole stack, in bag tooltips." },
            { option = "showActivity", label = "Sales activity",
                tooltip = "Estimated sales per day and how many days the current supply would last." },
            { option = "showTrend", label = "Price trend",
                tooltip = "How the price changed over the last 7 days." },
        },
    },
    {
        title = "Auction house",
        options = {
            { option = "auto", label = "Scan when the auction house opens",
                tooltip = "Start a full scan when you open the auction house and the 15 minute timer allows it." },
            { option = "learnFromSearches", label = "Learn from items you browse",
                tooltip = "Update prices and sales activity from what the Buy tab shows you." },
            { option = "highlightDeals", label = "Highlight deals in the Buy tab",
                tooltip = "Mark auctions that pass the Deals filters with a green stripe.",
                onChange = function()
                    ns.RefreshHighlights()
                end },
        },
    },
}

function ns.CreateOptions()
    if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
        return
    end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("AuctionMin")
    for _, section in ipairs(SECTIONS) do
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(section.title))
        for _, entry in ipairs(section.options) do
            local setting = Settings.RegisterAddOnSetting(category, "AuctionMin_" .. entry.option, entry.option, ns.db,
                Settings.VarType.Boolean, entry.label, ns.OPTION_DEFAULTS[entry.option])
            setting:SetValueChangedCallback(function()
                if entry.onChange then
                    entry.onChange()
                end
                if ns.RefreshTab then
                    ns.RefreshTab()
                end
            end)
            Settings.CreateCheckbox(category, setting, entry.tooltip)
        end
    end
    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if category then
        Settings.OpenToCategory(category:GetID())
    else
        ns.Print("the settings window isn't available.")
    end
end
