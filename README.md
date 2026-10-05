# AuctionMin

A lightweight auction house price addon for **World of Warcraft: Forever** (interface 16001).

AuctionMin scans the whole auction house and shows the market price per item in item tooltips: in your bags, bank, chat links, merchant windows and anywhere else an item tooltip appears.

```
Auction market price (updated 2h ago)
   Per item              1s 25c
   Stack of 20             25s
```

## Features

- Full auction house scan with one click, or automatically when you open the auction house.
- Market price **per unit** that ignores single underpriced or overpriced listings; bag tooltips also show the price for the whole stack.
- Every price shows how old it is, so stale prices are easy to spot.
- No dependencies and no options window, just tooltips and a few slash commands.

## How the market price works

1. Each scan takes the cheapest part of the units listed for an item and uses the middle price of that group, weighted by quantity. A few bait listings can't pull it down, and the result is always a price that is actually listed.
   - The size of that part depends on supply: about 1.5 / √(total units) of it, but at least 5%. With 10 units on sale it's about half of them, with 100 units 15%, from about 1000 units 5%. A rare item needs several cheap listings before the cheap price counts, while for a common reagent a large cheap stack is real supply.
   - The group may grow up to twice that size, but stops early when the price jumps by more than 20%.
2. The new value is blended with the previous one depending on how much time has passed (3 day half-life). One unusual scan can't wreck the price, and scanning every hour gives the same result as scanning once a day.

The lowest buyout from the latest scan is kept as well: `/amin <item link>` prints both.

## Usage

Open the auction house. If the last full scan was more than 15 minutes ago, AuctionMin starts one automatically; otherwise use the **Full scan** button below the auction house window when its timer runs out. Blizzard allows one full scan per 15 minutes per account.

| Command | Description |
| --- | --- |
| `/amin scan` | Start a full scan (the auction house must be open) |
| `/amin auto` | Toggle the automatic scan when the auction house opens |
| `/amin status` | Show stored item count, last scan time and cooldown |
| `/amin clear` | Forget prices for the current realm and faction |
| `/amin <item link>` | Print the market price and the lowest buyout for an item |

`/auctionmin` works as well.

## Notes

- Prices are kept separately for each realm and faction, so a character on another realm or faction needs its own scan.
- Auctions with a bid but no buyout are ignored.
- Items with random suffixes ("… of the Bear", "… of the Monkey") are priced separately for each suffix, so a valuable variant never shares a price with a cheap one.
- Items missing from the latest scan keep their previous price, shown with its age.
- Updating from 0.1.x resets stored prices once, because they were minimum prices.

## License

[MIT](LICENSE)
