# PrizeCard

One prize: art on a checker, its name, its price in hours, and a state strip. The list is sorted by hours, fewest first.

| State | Class | Strip |
| --- | --- | --- |
| Not enough hours yet | (none) | `lock-fill` "5.5 hrs to go" |
| The chosen goal | `is-goal` + `sp-prize__flag` "Your goal" | hours to go |
| Enough approved hours | `is-ready` | gold, `gift-fill` "Ready to claim" |
| Bought | `is-claimed` | mint, "Claimed" |

Put the product's photo, cut out on a transparent background, as an `<img>` in `sp-prize__art` (the preview uses icons).
Mark digital prizes with a violet "Digital" badge as `sp-prize__tag`. Prices are hours only; never show dollars.
Lay cards out in `sp-prizes`, a grid that fits as many 168px columns as there's room for.
