# MenuTile

A big rounded-square tile with an icon and a label under it: the home screen's menu, gacha style.

Markup: `<a class="sp-tile"><span class="sp-tile__face"><i data-icon="…"></i></span>Label</a>`. Mark the current one with
`aria-current="page"`; it turns royal. Put a notification dot inside the face with `<span class="sp-dot">2</span>`: a number
when there's a count, `!` when something needs doing. Labels are one or two words. Lay tiles in a grid of three or four across.
