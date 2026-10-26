Save Point is a Hack Club program: keep working on a game you stopped (usually your jame gam game), log the hours, and pick prizes
with them. The look is a bubbly gacha-game menu built from the logo: royal blue letters with a periwinkle-to-navy outline, a gold
four-point star, and a copper halo, on a soft sky ground. Everything is round, glossy and pressable. Nothing has a black outline.

## Voice

- Talk to the participant as "you". Plain, warm, short sentences. Excited at the right moments ("Ready to claim"), never pushy.
- Sentence case everywhere. "Save Point" is the only title-case phrase, and it is always two words.
- Hours are the currency. Write them to one decimal with "hrs": "6.5 hrs", "0.5 hrs to go". Never show a dollar price.
- Name things by what people recognise: "your game", "your goal", "ship". Not "submission", "project entity" or "allocation".
- Buttons start with a verb and say what happens: "Ship my game", "Set as my goal", "Join Save Point".
- Errors say what to do: "Tell us a bit more: at least 40 characters." No apologies, no blame.
- No emoji in the interface. Icons do that job.

## Colour

- The ground is `sky` with the diamond checker in `sky-check` (`sp-page`). Content sits on `surface` panels.
- Royal blue (`royal`, `royal-hi`) is the brand: ribbons, the current menu tile, checked boxes, royal buttons. Brand-blue text is `royal-ink`.
- Gold (`gold`, `gold-hi`) is the star: the one main action per screen, the chosen goal, stars, the current step, the current nav item.
  Text on gold is always `on-gold`, never white.
- Copper (`copper`) is the halo: streak flames and the bronze medal. Copper text is `copper-ink`.
- Status colours always come with an icon and a word: `mint` approved and done, `gold` changes needed and warnings, `coral` errors and
  blocking checks, `violet` notifications and digital prizes. Their text tokens are `mint-ink`, `gold-ink`, `coral-ink`, `violet-ink`,
  on the matching `*-soft` fill or on `surface`.
- The dark plate (`frame`) holds meters, stat chips and the bottom nav. Text on it is `on-frame` and `frame-muted`.
- Body text is `ink`; secondary `ink-muted`; placeholders and disabled `ink-faint`.
- The dark theme is a night sky: the same hues, navy grounds, lighter text tokens. Every text pair named in a token's note holds 4.5:1 in both themes.

## Depth: gloss, edge, lip

Raised things (buttons, tiles, chips, the current step) are built in three layers, and this is what makes the look:

1. A top-to-bottom gradient from the `*-hi` token to the fill.
2. A 2px border in the fill's own darker shade (`royal-line`, `gold-line`, `line-strong` for white things). Never black, never grey.
3. A solid lip under it, `--lip-depth` (4px) tall, in the `*-lip` shade, plus a 2px `gloss` highlight inside the top edge.

Pressed, a thing moves down `--press-depth` (3px) and its lip shrinks to 1px. Sunken things (inputs, tracks, wells) are the opposite:
`surface-sunken` with a 2px `shade` inside the top edge. Panels and toasts also float on `shadow-soft`.

## Type

- Display is Rubik, heavy and leaning like the logo: `hero`, `display` and `title` are italic 800 to 900; `heading` is upright 800.
  Numbers that are the point of a card use `number` or `number-sm` with tabular numerals.
- Text is Nunito, rounded: `lead`, `body`, `body-strong`, `small`, `label` (uppercase via CSS), `caption`. Never lighter than 600.
- Running text stays under `prose-max` (640px). Headings get `text-wrap: balance`.
- For big words only, two treatments from the logo and poster: `sp-logo-text` (white-to-blue fill, navy outline) and
  `sp-callout-text` (violet with a white outline). See DisplayText.

## Shape and motion

- Everything is rounded: `radius-md` buttons and inputs, `radius-lg` cards and tiles, `radius-xl` panels and modals,
  `radius-full` pills. No square corners anywhere.
- Ribbons, meters and the player plate lean by `--slant` (−12°), from the logo's italics. Text inside is counter-skewed upright.
- Motion is springy and quick: `cubic-bezier(.3, 1.6, .5, 1)` for pops (checks, toggles, tiles), 80ms for presses, 120–220ms for the rest.
  Meters fill over 600ms. With `prefers-reduced-motion`, everything is instant.
- Sparkles (the logo's four-point star) are for celebrations only: a claimed prize, a finished goal.

## Iconography

MingCute Icon, Fill style, the same set ShaderGator uses (`@iconify-json/mingcute` 1.2.8, Apache-2.0). 24 by 24, single ink,
`currentColor`. Sizes: `icon-sm` (16px) in badges and help lines, `icon-md` (24px) in buttons, rows and nav, `icon-lg` (36px) on
menu tiles. Write `<i data-icon="rocket-fill"></i>` and `SavePoint.mountIcons()` fills it in, or call `SavePoint.icon("rocket-fill")`
for the SVG string. Only the Fill style; never mix in outline icons. The icons in this system are in the Icons asset group.

| Job | Icon |
| --- | --- |
| Hours, time | `time-fill` |
| Streak | `fire-fill` |
| Goal, prize | `flag-1-fill`, `gift-fill` |
| Ship | `rocket-fill` |
| Your game | `game-2-fill`, `save-2-fill` |
| Leaderboard | `trophy-fill` |
| Passed, failed, warning, waiting | `check-fill`, `close-fill`, `warning-fill`, `lock-fill` |

## Layout

- Phones first. Gutters: `space-4` on phones, `space-6` from 600px, `space-8` from 960px. Content stops at `content-max` (1120px).
- `sp-grid` has 4, 6 and 12 columns at those breakpoints, with a `space-6` gap. Main and side on desktop is `sp-span-8` + `sp-span-4`.
- Stack sections with `space-12`; group things inside a panel with `space-4`. Use gap, not margins.
- Phones get the bottom nav, fixed, with the safe-area inset added. Desktop gets a top bar with the logo and the nav under it.
- Controls are at least `control-md` (48px) tall on phones.

## Focus and accessibility

- Every control shows `focus-ring` on keyboard focus: a 3px gap in the ground colour, then 3px of solid navy (gold in the dark theme).
- State is never colour alone: badges and checks carry an icon and a word.
- Meters are `role="meter"` with min, max, now and a label naming the goal.
- Leaderboards show Slack display names only. Most participants are teenagers: show only what a screen needs about a person.
