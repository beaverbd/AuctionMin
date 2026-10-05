# AuctionMin

A lightweight auction house price addon for **World of Warcraft: Forever** (interface 16001).

AuctionMin scans the whole auction house and shows the market price and sales activity per item in item tooltips: in your bags, bank, chat links, merchant windows and anywhere else an item tooltip appears.

```
Auction market price (updated 2h ago)
   Per item              1s 25c
   Stack of 20             25s
   Sells about 120/day, 3 days of supply
```

## Features

- Full auction house scan with one click, or automatically when you open the auction house.
- Market price **per unit** that ignores single underpriced or overpriced listings; bag tooltips also show the price for the whole stack.
- Sales activity: estimated units sold per day and how many days the current supply would last.
- Learns from what you browse: opening an item in the Buy tab updates its price and activity, even while the full scan is on cooldown.
- An **AuctionMin** tab in the auction house with settings and two lists: the most actively traded items, and **deals**, items listed well below their market price that also sell.
- Every price shows how old it is, so stale prices are easy to spot.
- Nothing else to install: the libraries it uses are bundled.

## How the market price works

AuctionMin takes the cheapest part of the units listed for an item and uses the middle price of that group, weighted by quantity. A few bait listings can't pull it down, and the result is always a price that is actually listed.

- The size of that part depends on supply: about 1.5 / √(total units) of it, but at least 5%. With 10 units on sale it's about half of them, with 100 units 15%, from about 1000 units 5%. A rare item needs several cheap listings before the cheap price counts, while for a common reagent a large cheap stack is real supply.
- The group may grow up to twice that size, but stops early when the price jumps by more than 20%.

The price always comes from the latest full scan or the latest time you opened the item, so it matches what the auction house shows now. The lowest buyout is kept as well: `/amin <item link>` prints both.

## How sales activity works

The auction house doesn't report sales, so AuctionMin compares each scan with the previous one:

- Units that disappeared from a seller's listings count as sold, but only if their time left shows they couldn't have expired in between.
- When the same seller lists new units of the item at the same time, they are treated as a cancelled and reposted auction, not a sale.
- Sold units are divided by the observed time. Older observations fade (their weight halves every 3 days), so one unusual hour can't dominate for long.

**To see activity, run at least 3 scans 15-60 minutes apart.** Scans more than 2 hours apart don't count, because most auctions could have expired in between. The more such scans you run over several days, the better the estimates; the AuctionMin tab shows how much scan time they are based on. The previous scan is saved, so logging out between two scans is fine as long as they are less than 2 hours apart.

The numbers are estimates and lean low: a seller who restocks at the same price hides their own sales, and auctions with a bid but no buyout are ignored. They are meant to tell "barely sells" from "sells by the hundreds", not to count every sale. Your own auctions are left out of activity.

## Price history

AuctionMin keeps one point per day for the last 14 days: the market price at the end of the day, how many units were listed and how much sold. Item tooltips show the trend, for example "Price up 12% over 7 days", once there are at least 2 days of history.

Right-click an item in the AuctionMin tab to open its **History**: a 14 day price chart with sales per day below it. Hover a day to see its numbers.

## Deals

The **Deals** list in the AuctionMin tab shows items with units listed at least 20% below their market price, as long as the item also sells. It only uses prices from scans and items you opened in the last 2 hours, because cheap auctions don't last, and it leaves your own auctions out.

- **Deal price** is the average price of those cheap units and **Below** how far under the market price they are.
- **Profit** estimates what you would make buying the cheap units, at most as many as sell in 3 days, and reselling them at the market price after the 5% auction house cut. Deposits are not included.

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
