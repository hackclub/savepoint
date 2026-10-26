# PageLayout

How a page goes together: the `sp-page` checker ground, an `sp-container` (max `content-max`, gutters `space-4` on phones,
`space-6` from 600px, `space-8` from 960px), a top bar, then panels on `sp-grid`.

The grid is 4 columns on phones, 6 from 600px and 12 from 960px, with a `space-6` gap. Children span the full width until 960px;
from there use `sp-span-8` + `sp-span-4` for main and side, or `sp-span-6` twice. Leave `space-12` between rows of panels so
ribbons don't touch the panel above. On phones, add the `BottomNav` fixed to the bottom and pad the page by its height.
