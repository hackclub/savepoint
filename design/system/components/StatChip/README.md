# StatChip

A navy pill with a round key on the left and a number: the gacha stat readout. Markup:
`<span class="sp-stat"><span class="sp-stat__key"><i data-icon="time-fill"></i></span>8.6<span class="sp-stat__unit">hrs</span></span>`.

Keys: gold (hours, default), `sp-stat__key--bronze` (streak), `sp-stat__key--mint` (rank). Keep numbers short: one decimal for hours.
Put two or three in a row at the top of a profile or panel; more than that is a table.
