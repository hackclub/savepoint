# Button

A raised, glossy button that sinks when pressed. Use `sp-btn` on a `<button>` or `<a>`.

- **Gold** (`sp-btn--gold`): the one thing this screen is for (join, claim a prize). At most one per view, usually `sp-btn--lg`.
- **Royal** (`sp-btn--royal`): strong actions that aren't the screen's main one, such as shipping.
- **Default** (no modifier): everything else. White to `surface-sunken`, periwinkle `line-strong` edge.
- **Mint** (`sp-btn--mint`): reviewer-side confirmations only (approve hours).
- **Ghost** (`sp-btn--ghost`): dismissals and "not now".
- Sizes: `sp-btn--sm` (36px), default (48px), `sp-btn--lg` (56px).

The consumer provides the label, and optionally an icon as the first child (`<i data-icon="rocket-fill"></i>`).
Labels start with a verb and say what happens: "Ship my game", not "Submit". Disable with the `disabled` attribute;
the button goes flat and faint. The button keeps `--lip-depth` of bottom margin so its lip never overlaps what's below.
