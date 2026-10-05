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
- An **AuctionMin** tab in the auction house with settings and the most actively traded items, by units or by gold per day.
- Every price shows how old it is, so stale prices are easy to spot.
- Nothing else to install: the libraries it uses are bundled.

## How the market price works

1. Each scan takes the cheapest part of the units listed for an item and uses the middle price of that group, weighted by quantity. A few bait listings can't pull it down, and the result is always a price that is actually listed.
   - The size of that part depends on supply: about 1.5 / √(total units) of it, but at least 5%. With 10 units on sale it's about half of them, with 100 units 15%, from about 1000 units 5%. A rare item needs several cheap listings before the cheap price counts, while for a common reagent a large cheap stack is real supply.
   - The group may grow up to twice that size, but stops early when the price jumps by more than 20%.
2. The new value is blended with the previous one depending on how much time has passed (3 day half-life). One unusual scan can't wreck the price, and scanning every hour gives the same result as scanning once a day.

The lowest buyout from the latest scan is kept as well: `/amin <item link>` prints both.

## How sales activity works

The auction house doesn't report sales, so AuctionMin compares each scan with the previous one:

- Units that disappeared from a seller's listings count as sold, but only if their time left shows they couldn't have expired in between.
- When the same seller lists new units of the item at the same time, they are treated as a cancelled and reposted auction, not a sale.
- Sold units are divided by the observed time and smoothed over days, like the market price.

**To see activity, run at least 3 scans 15-60 minutes apart.** Scans more than 2 hours apart don't count, because most auctions could have expired in between. The more such scans you run over several days, the better the estimates; the AuctionMin tab shows how much scan time they are based on. The previous scan is saved, so logging out between two scans is fine as long as they are less than 2 hours apart.

The numbers are estimates and lean low: a seller who restocks at the same price hides their own sales, and auctions with a bid but no buyout are ignored. They are meant to tell "barely sells" from "sells by the hundreds", not to count every sale.

## Usage

Open the auction house. If the last full scan was more than 15 minutes ago, AuctionMin starts one automatically; otherwise use the **Full scan** button below the auction house window when its timer runs out. Blizzard allows one full scan per 15 minutes per account.

The **AuctionMin** tab next to Buy, Sell and Auctions has these settings:

- Scan when the auction house opens
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
