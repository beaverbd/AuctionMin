# AuctionMin

A lightweight auction house price addon for **World of Warcraft: Forever** (interface 16001).

AuctionMin scans the whole auction house and shows the market price and sales activity per item in item tooltips: in your bags, bank, chat links, merchant windows and anywhere else an item tooltip appears.

```
Auction House (updated 2h ago)
   Sells at (2,345 sales)  1s 10c
   Listed at               1s 25c
   Stack of 20               22s
   Sells about 120/day, 3 days of supply
```

## Features

- Full auction house scan with one click, or automatically when you open the auction house.
- **What items really sell for:** the typical price of the sales AuctionMin has seen, next to the price of the current listings; bag tooltips also show the value of the whole stack.
- Sales activity: estimated units sold per day and how many days the current supply would last.
- Learns from what you browse: opening an item in the Buy tab updates its price and activity, even while the full scan is on cooldown.
- An **AuctionMin** tab in the auction house with settings and two lists: the most actively traded items, and **deals**, items listed well below their market price that also sell, with your own filters.
- **Watch mode:** a full scan every time the timer allows it and a sound when new deals show up.
- Deals are highlighted in the Buy tab while you browse.
- Every price shows how old it is, so stale prices are easy to spot.
- Nothing else to install: the libraries it uses are bundled.

## How prices work

**Sells at** is the median price of recent sales: half of the units AuctionMin saw sell went for less, half for more. It shows up once AuctionMin has seen at least 5 sales, and older sales count less (their weight halves every 3 days). Unlike an average, a few expensive sales can't pull it up: if 90% of sales are at 1s and 10% at 20s, it says 1s, not 2.9s. The stack value and gold per day use it whenever it's known. The History view also shows the range most sales fall in.

**Listed at** is the price of the current listings:

AuctionMin takes the cheapest part of the units listed for an item and uses the middle price of that group, weighted by quantity. A few bait listings can't pull it down, and the result is always a price that is actually listed.

- The size of that part depends on supply: about 1.5 / √(total units) of it, but at least 5%. With 10 units on sale it's about half of them, with 100 units 15%, from about 1000 units 5%. A rare item needs several cheap listings before the cheap price counts, while for a common reagent a large cheap stack is real supply.
- The group may grow up to twice that size, but stops early when the price jumps by more than 20%.

The price always comes from the latest full scan or the latest time you opened the item, so it matches what the auction house shows now. The lowest buyout is kept as well: `/amin <item link>` prints both.

## How sales activity works

The auction house doesn't report sales, so AuctionMin compares each scan with the previous one:

- The full scan lists auctions in the order they were created, so AuctionMin follows each auction from one scan to the next: old auctions keep their order and new ones are added at the end. A new auction is never mistaken for an old one, even at the same price.
- An auction that got smaller was partly bought. Those units always count as sold, because an auction can only be cancelled as a whole.
- An auction that disappeared counts as sold only if its time left shows it couldn't have expired in between, and only if no cheaper auction of the same item survived. Buyers take the cheapest units first, so an auction that vanished while cheaper ones are still listed was cancelled or reposted. The full scan on Forever doesn't tell who the sellers are, so this is how reposts are told apart from sales.
- When you open a piece of gear in the Buy tab, the sellers are known, and a seller listing the same item at a new price counts as a repost.
- Sold units are divided by the observed time. Older observations fade (their weight halves every 3 days), so one unusual hour can't dominate for long.

**To see activity, run at least 3 scans 15-60 minutes apart.** Scans more than 2 hours apart don't count, because most auctions could have expired in between. The more such scans you run over several days, the better the estimates; the AuctionMin tab shows how much scan time they are based on. The previous scan is saved, so logging out between two scans is fine as long as they are less than 2 hours apart.

The numbers are estimates and lean low: an auction cancelled while it was the cheapest one looks like a sale, but an auction bought while a cheaper one was still listed doesn't count, and auctions with a bid but no buyout are ignored. They are meant to tell "barely sells" from "sells by the hundreds", not to count every sale. Your own auctions are only recognized in items you open in the Buy tab, because the full scan doesn't name sellers.

## Price history

AuctionMin keeps one point per day for the last 14 days: the market price at the end of the day, how many units were listed and how much sold. Item tooltips show the trend, for example "Price up 12% over 7 days", once there are at least 2 days of history.

Right-click an item in the AuctionMin tab to open its **History**: a 14 day price chart with sales per day below it. Hover a day to see its numbers.

## Deals

The **Deals** list in the AuctionMin tab shows items with units listed well below their expected resale price (20% by default), as long as the item also sells and AuctionMin has seen at least 3 sales, so a single lucky sale can't make an item look busy. It only uses prices from scans and items you opened in the last 2 hours, because cheap auctions don't last, and it leaves your own auctions out when it can tell them apart (in items you opened).

- **Resale** is the lowest of the current listings price, the typical price of recent sales and the 7 day median price. Current listings alone can mislead: if an item always sold for 1g and the cheap ones were just bought out, ten new listings at 10g don't make the last 1g auction a deal, because nobody buys at 10g. Its color shows what the price is based on: green for recent sales, yellow for price history, grey for current listings only. Grey deals are not confirmed yet and are listed last.
- **Deal price** is the average price of the cheap units and **Below** how far under the resale price they are.
- **Profit** estimates what you would make buying the cheapest units first, at most as many as sell in 3 days, and reselling them at the resale price after the 5% auction house cut. Deposits are not included.

### Filters

The bar above the list sets which deals you see:

- **Min profit:** hide deals with a smaller estimated profit.
- **Below:** how far under the resale price a unit must be listed, from 10%, 20% by default.
- **Price:** only units listed within this price range, for example to stay within your budget.
- **Sales confirmed:** only deals whose resale price is confirmed by sales AuctionMin has seen (green).

Amounts can be typed as `1g50s`, `80s`, `25c` or just `2` for 2 gold. An empty box means no limit.

### Watch mode

Turn on **Watch** and leave the auction house open: AuctionMin runs a full scan every time the 15 minute timer runs out. When a scan finds new deals that pass your filters, it plays a sound, flashes the game icon in the taskbar, lists them in chat and marks them **New** in the list. A deal that stays listed isn't announced again unless its price drops further. Buying is always your own click: open the deal from the list and buy it in the Buy tab.

The auction house must stay open, and the game logs you out after a while without any input, so watch mode is for when you're nearby.

### Highlights while you browse

Search results and auction lists in the Buy tab mark units that pass the same filters with a green stripe, and their tooltip shows how far below the resale price they are. Search results only show the cheapest price of each item, so the profit filter applies to the auction lists only. Turn this off with the "Highlight deals in the Buy tab" setting.


## Learning from what you browse

AuctionMin never sends searches of its own; it reads what the auction house shows you:

- **Opening an item** (its list of auctions in the Buy tab) updates the item's market price, lowest buyout and supply the same way a full scan does. Long lists that are only partly loaded still update the price when the cheapest part is loaded.
- **Search results** update the lowest buyout and the number listed for every item in the list.
- **Opening the same piece of gear again** 5 minutes to 2 hours later adds to its sales activity, just like two full scans would. Stackable items don't count here: the auction house merges their auctions by price across sellers, so a seller reposting at a new price would look like a sale.

You can turn this off with the "Learn from items you browse" setting.

## Usage

Open the auction house. If the last full scan was more than 15 minutes ago, AuctionMin starts one automatically; otherwise use the **Full scan** button below the auction house window when its timer runs out. Blizzard allows one full scan per 15 minutes per account.

In the **AuctionMin** tab, click an item in either list to open it in the Buy tab, Shift-click it to link it in chat, or right-click it to see its price history. The tab also has these settings:

- Scan when the auction house opens
- Learn from items you browse
- Stack price in bag tooltips
- Sales activity in tooltips
- Highlight deals in the Buy tab

| Command | Description |
| --- | --- |
| `/amin scan` | Start a full scan (the auction house must be open) |
| `/amin auto` | Toggle the automatic scan when the auction house opens |
| `/amin status` | Show stored item count, last scan time, cooldown and activity data |
| `/amin clear` | Forget prices and activity for the current realm and faction |
| `/amin <item link>` | Print the market price, lowest buyout and activity for an item |

`/auctionmin` works as well.

## Notes

- Prices are kept separately for each realm and faction, so a character on another realm or faction needs its own scan.
- Auctions with a bid but no buyout are ignored.
- Items with random suffixes ("… of the Bear", "… of the Monkey") are priced separately for each suffix, so a valuable variant never shares a price with a cheap one.
- Items missing from the latest scan keep their previous price, shown with its age.
- Updating from 0.1.x resets stored prices once, because they were minimum prices.

## Bundled libraries

- [LibAHTab](https://github.com/TheMouseNest/LibAHTab) by plusmouse (MIT), for the auction house tab
- LibStub (public domain)

## License

[MIT](LICENSE)
