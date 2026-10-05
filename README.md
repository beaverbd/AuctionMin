# AuctionMin

A lightweight auction house price addon for **World of Warcraft: Forever** (interface 16001).

AuctionMin scans the whole auction house and shows the lowest buyout per item in item tooltips: in your bags, bank, chat links, merchant windows and anywhere else an item tooltip appears.

```
Auction House (scanned 2h ago)
   Per item              1s 25c
   Stack of 20             25s
```

## Features

- Full auction house scan with one click, or automatically when you open the auction house.
- Lowest buyout **per unit**; bag tooltips also show the price for the whole stack.
- Prices are stored per realm and faction and keep their age, so old prices are easy to spot.
- No dependencies and no options window, just tooltips and a few slash commands.

## Usage

Open the auction house. If the last full scan was more than 15 minutes ago, AuctionMin starts one automatically; otherwise use the **Full scan** button below the auction house window when its timer runs out. Blizzard allows one full scan per 15 minutes per account.

| Command | Description |
| --- | --- |
| `/amin scan` | Start a full scan (the auction house must be open) |
| `/amin auto` | Toggle the automatic scan when the auction house opens |
| `/amin status` | Show stored item count, last scan time and cooldown |
| `/amin clear` | Forget prices for the current realm and faction |
| `/amin <item link>` | Print the stored price for an item |

`/auctionmin` works as well.

## Notes

- Auctions with a bid but no buyout are ignored.
- Items with random suffixes ("… of the Bear") share one price: the lowest across all variants.
- Items missing from the latest scan keep their previous price, shown with its age.

## License

[MIT](LICENSE)
