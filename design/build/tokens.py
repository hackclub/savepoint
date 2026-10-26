"""Save Point tokens: one list, written to project/tokens.json by make.py, and checked for contrast."""

# name, light, dark, usage. A dark value of None means the same as light.
COLORS = [
    # Ground and surfaces
    ("sky", "#eaf0ff", "#0c1442", "Page ground. Lay the diamond checker over it with `sky-check`."),
    ("sky-check", "#dde6ff", "#111b55", "The checker squares on `sky`, and on prize-card art. Decoration only."),
    ("surface", "#ffffff", "#172163", "Panels, cards, list rows, modals, and an input that has focus."),
    ("surface-sunken", "#eef2fd", "#0f1850", "Wells: inputs at rest, meter and switch tracks, idle day cells, a card's footer strip."),
    ("line", "#cdd7f6", "#2e3c8a", "Decorative borders and the lip under panels and rows. Never the only thing marking a control."),
    ("line-strong", "#7085d6", "#6a7fd6", "Borders of controls (inputs, checkboxes, secondary buttons, tiles): 3:1 on `surface` and `surface-sunken`. The logo's periwinkle outline."),
    ("line-lip", "#5468c0", "#0a1038", "The 4px lip under secondary buttons, icon buttons and menu tiles."),
    ("ink", "#121c5e", "#f0f3ff", "Body text and headings, on `sky`, `surface`, `surface-sunken` and every `*-soft` fill."),
    ("ink-muted", "#4b5797", "#b0bbec", "Secondary text: help lines, labels, metadata. On `sky`, `surface` and `surface-sunken`."),
    ("ink-faint", "#5c67a0", "#8f9bd2", "Placeholders, disabled labels, future steps. On `surface` and `surface-sunken` only."),
    ("knob", "#ffffff", "#f0f3ff", "The switch knob."),
    ("gloss", "#ffffffb3", "#ffffff40", "The 2px highlight along the top inside edge of raised things (inset shadow)."),
    ("shade", "#1b247014", "#00000033", "The 2px shadow along the top inside edge of sunken things (inset shadow)."),
    # The dark plate (meters, bottom nav, stat chips)
    ("frame", "#1b2470", "#070b2a", "The deep-navy plate behind meters, stat chips and the bottom nav."),
    ("frame-track", "#2f3a94", "#1c2363", "Empty track inside a meter, dividers on `frame`."),
    ("frame-lip", "#0e1450", "#02041a", "Lip under `frame` plates."),
    ("frame-muted", "#b8c2f0", "#b9c3f2", "Secondary text and idle icons on `frame`."),
    ("on-frame", "#ffffff", None, "Primary text and numbers on `frame`."),
    # Logo
    ("logo-line", "#0a2290", None, "The logo's navy outline. Use for the logo-style display text stroke only."),
    ("logo-fill", "#a9c9fa", None, "The bottom of the logo letters' fill. Use for the logo-style display text and large brand blocks."),
    # Royal blue: the brand
    ("royal-hi", "#4f6be0", "#4c68e6", "Top of a royal fill (gradient start)."),
    ("royal", "#2f4bd0", "#3550d4", "Primary brand fill: royal buttons, the current menu tile, ribbons, checked boxes."),
    ("royal-line", "#2840b8", "#2c45c4", "Border of a royal fill."),
    ("royal-lip", "#1a2c8f", "#16236f", "Lip under a royal fill."),
    ("on-royal", "#ffffff", None, "Text and icons on a royal fill (`royal-hi` to `royal`)."),
    ("royal-ink", "#2a43c4", "#9db0ff", "Brand-blue text, links and icons on `sky`, `surface`, `surface-sunken` and `royal-soft`."),
    ("royal-soft", "#dfe6fc", "#24318a", "Tinted fill: the in-review badge, selected rows, avatar fallbacks."),
    ("royal-glow", "#2f4bd033", "#8aa2ff40", "The soft halo around a focused input and today's day cell."),
    # Gold: the star, the main call to action, goals
    ("gold-hi", "#ffe58a", "#ffe27a", "Top of a gold fill."),
    ("gold", "#ffc727", "#ffc21f", "The one main action per screen, the chosen goal, stars, the current step. The logo's star."),
    ("gold-line", "#e9a514", "#e0a010", "Border of a gold fill; the ring on a ready prize."),
    ("gold-lip", "#c47f08", "#8f5a00", "Lip under a gold fill; the drop under stars."),
    ("on-gold", "#4a2300", None, "Text and icons on a gold fill (`gold-hi` to `gold`)."),
    ("gold-ink", "#8a5200", "#ffd966", "Gold text on `surface` and `gold-soft` (the changes-needed badge)."),
    ("gold-soft", "#fff4cc", "#3d3110", "Tinted fill: changes-needed badge, your own leaderboard row, the halo on the current step."),
    # Copper: the halo
    ("copper", "#c86018", "#e07a30", "The logo's halo. Decoration and streak fire icons; not for text."),
    ("copper-ink", "#a14a0d", "#ffa25a", "Copper text on `surface`, `cream` and `gold-soft` (streak counts)."),
    ("cream", "#fff6dc", "#3a2a16", "The halo's light. A built day cell; warm callouts."),
    ("bronze-hi", "#f6b27a", None, "Top of the third-place medal."),
    ("bronze", "#dc8240", None, "Third-place medal; the streak key on a stat chip."),
    ("on-bronze", "#3a1600", None, "Text on `bronze-hi` to `bronze`."),
    ("silver-hi", "#ffffff", None, "Top of the second-place medal."),
    ("silver", "#c8d0ec", None, "Second-place medal."),
    ("on-silver", "#2b3466", None, "Text on `silver-hi` to `silver`."),
    # Status
    ("mint-hi", "#7ee8b2", "#6fe0a8", "Top of a mint fill."),
    ("mint", "#27bd78", "#22b06e", "Done and approved: finished steps, checked-off ship checks, a switch that is on, approved hours."),
    ("mint-line", "#1aa064", "#1a9a5e", "Border of a mint fill."),
    ("mint-lip", "#127a49", "#0c5a35", "Lip under a mint fill."),
    ("on-mint", "#053a22", None, "Text and icons on a mint fill."),
    ("mint-ink", "#0d6b40", "#7cf0b6", "Mint text on `surface` and `mint-soft` (approved badge, rank gains)."),
    ("mint-soft", "#dbf7e9", "#113f2e", "Tinted fill behind `mint-ink`."),
    ("lime", "#c6f03a", None, "The bright end of the hours meter's fill. Decoration only."),
    ("coral", "#ef4a68", "#ff6f88", "Errors and blocking ship checks: the field border and the mark. Always with an icon and words."),
    ("coral-ink", "#b3213f", "#ff9aac", "Error text on `surface` and `coral-soft`."),
    ("coral-soft", "#ffe2e7", "#4a1628", "Tinted fill behind `coral-ink`: a field with an error, a failing check's mark."),
    ("violet", "#7b5cf0", "#7356ea", "Notification dots and digital prizes. The tagline purple."),
    ("on-violet", "#ffffff", None, "Text on a `violet` fill (the count in a notification dot)."),
    ("violet-ink", "#5a3bd6", "#c4b5ff", "Violet text on `surface` and `violet-soft`; the tagline outline style."),
    ("violet-soft", "#ece6ff", "#2e2266", "Tinted fill behind `violet-ink`; the deadline day cell."),
]

# Text pairs to check: (fg, bg, minimum ratio)
PAIRS = [
    ("ink", "sky", 4.5), ("ink", "surface", 4.5), ("ink", "surface-sunken", 4.5), ("ink", "gold-soft", 4.5), ("ink", "royal-soft", 4.5),
    ("ink-muted", "sky", 4.5), ("ink-muted", "surface", 4.5), ("ink-muted", "surface-sunken", 4.5),
    ("ink-faint", "surface", 4.5), ("ink-faint", "surface-sunken", 4.5),
    ("line-strong", "surface", 3), ("line-strong", "surface-sunken", 3),
    ("on-frame", "frame", 4.5), ("frame-muted", "frame", 4.5), ("frame-muted", "frame-track", 3),
    ("on-royal", "royal-hi", 4.5), ("on-royal", "royal", 4.5),
    ("royal-ink", "sky", 4.5), ("royal-ink", "surface", 4.5), ("royal-ink", "surface-sunken", 4.5), ("royal-ink", "royal-soft", 4.5),
    ("on-gold", "gold-hi", 4.5), ("on-gold", "gold", 4.5),
    ("gold-ink", "surface", 4.5), ("gold-ink", "gold-soft", 4.5),
    ("copper-ink", "surface", 4.5), ("copper-ink", "cream", 4.5), ("copper-ink", "gold-soft", 4.5),
    ("on-bronze", "bronze-hi", 4.5), ("on-bronze", "bronze", 4.5), ("on-silver", "silver", 4.5),
    ("on-mint", "mint-hi", 4.5), ("on-mint", "mint", 4.5),
    ("mint-ink", "surface", 4.5), ("mint-ink", "mint-soft", 4.5),
    ("coral-ink", "surface", 4.5), ("coral-ink", "coral-soft", 4.5), ("coral", "surface", 3),
    ("on-violet", "violet", 4.5), ("violet-ink", "surface", 4.5), ("violet-ink", "violet-soft", 4.5),
    ("gold", "frame", 3), ("violet-ink", "sky", 4.5),
]

SHADOWS = [
    ("shadow-soft", "0 10px 24px -8px #1b24704d", "0 12px 28px -8px #000000a6", "The float under panels, toasts and modals, added to their lip."),
    ("focus-ring", "0 0 0 3px #ffffff, 0 0 0 6px #1a2c8f", "0 0 0 3px #0c1442, 0 0 0 6px #ffd23f",
     "Keyboard focus on every control: a 3px gap in the ground colour, then 3px of solid navy (gold in dark). Add it to the control's own shadows."),
]

SPACING = [
    ("space-1", "4px", "Icon to label inside a badge."),
    ("space-2", "8px", "Icon to label in buttons; gaps inside chips and tiles."),
    ("space-3", "12px", "Between related controls in a row; list row padding."),
    ("space-4", "16px", "Phone page gutter; gap between stacked fields."),
    ("space-5", "20px", "Button side padding; ribbon inset."),
    ("space-6", "24px", "Panel padding; grid gap; tablet gutter."),
    ("space-8", "32px", "Desktop gutter; panel top padding under a ribbon."),
    ("space-10", "40px", "Between groups inside a section."),
    ("space-12", "48px", "Between sections on a page."),
    ("space-16", "64px", "Above and below the landing hero."),
]

RADII = [
    ("radius-xs", "8px", "Checkboxes."),
    ("radius-sm", "12px", "Small buttons, meter bars, day cells."),
    ("radius-md", "16px", "Buttons and inputs."),
    ("radius-lg", "24px", "Cards, menu tiles, FAQ rows."),
    ("radius-xl", "32px", "Panels and modals."),
    ("radius-full", "9999px", "Pills: badges, chips, toasts, the bottom nav, leaderboard rows, avatars."),
]

SIZES = [
    ("control-sm", "36px", "Small button and icon button height."),
    ("control-md", "48px", "Default button, input and icon button height. The touch target floor on phones."),
    ("control-lg", "56px", "The main call to action on a screen."),
    ("icon-sm", "16px", "Icons inside badges and help lines."),
    ("icon-md", "24px", "Icons in buttons, rows and the nav."),
    ("icon-lg", "36px", "Icons on menu tiles."),
    ("content-max", "1120px", "Widest a page's content gets."),
    ("prose-max", "640px", "Widest a block of running text gets."),
]

SHAPE = [
    ("slant", "-12deg", "The lean of ribbons, meters and player plates (`skewX`), from the logo's italic letters. Counter-skew the text inside."),
    ("lip-depth", "4px", "Height of the solid lip under raised things."),
    ("press-depth", "3px", "How far a raised thing moves down when pressed; its lip shrinks by the same amount."),
]

FONTS = [
    {"family": "Rubik", "file": "fonts/Rubik-latin.woff2", "weight": "300 900", "style": "normal"},
    {"family": "Rubik", "file": "fonts/Rubik-Italic-latin.woff2", "weight": "300 900", "style": "italic"},
    {"family": "Nunito", "file": "fonts/Nunito-latin.woff2", "weight": "200 1000", "style": "normal"},
]

FAMILIES = {
    "display": "\"Rubik\", \"Arial Rounded MT Bold\", system-ui, sans-serif",
    "body": "\"Nunito\", ui-rounded, \"Arial Rounded MT Bold\", system-ui, sans-serif",
}

TYPE_GROUPS = [
    {"name": "Display", "family": "display", "note": "Rubik, heavy and leaning like the logo. Italic for anything that shouts; upright for card headings.", "styles": [
        {"name": "hero", "fontSize": "64px", "lineHeight": "60px", "fontWeight": 900, "fontStyle": "italic", "letterSpacing": "-0.01em",
         "sample": "Continue a game you stopped working on", "usage": "The landing headline only, one per page. Drop to `display` under 600px wide."},
        {"name": "display", "fontSize": "44px", "lineHeight": "48px", "fontWeight": 900, "fontStyle": "italic",
         "sample": "Your save", "usage": "Page titles."},
        {"name": "title", "fontSize": "30px", "lineHeight": "34px", "fontWeight": 800, "fontStyle": "italic",
         "sample": "Pick a prize", "usage": "Section titles and modal titles."},
        {"name": "heading", "fontSize": "22px", "lineHeight": "28px", "fontWeight": 800,
         "sample": "Ready to ship?", "usage": "Card and panel headings."},
        {"name": "number", "fontSize": "28px", "lineHeight": "32px", "fontWeight": 800, "fontStyle": "italic",
         "sample": "6.5 / 12 hrs", "usage": "Hours and counts that are the point of a card. Always with tabular numerals."},
        {"name": "number-sm", "fontSize": "18px", "lineHeight": "22px", "fontWeight": 800, "fontStyle": "italic",
         "sample": "8.6 hrs", "usage": "Numbers in stat chips, ribbons and leaderboard rows."},
    ]},
    {"name": "Text", "family": "body", "note": "Nunito, rounded and friendly. Never lighter than 600: thin text looks wrong next to the chunky shapes.", "styles": [
        {"name": "lead", "fontSize": "20px", "lineHeight": "30px", "fontWeight": 700,
         "sample": "Keep building the game you made in the jame gam. Every hour you log gets you closer to a prize.", "usage": "The paragraph under a hero or page title."},
        {"name": "body", "fontSize": "16px", "lineHeight": "24px", "fontWeight": 600,
         "sample": "Hours you log in Hackatime from the day Save Point starts count toward your prize.", "usage": "Everything else."},
        {"name": "body-strong", "fontSize": "16px", "lineHeight": "24px", "fontWeight": 800,
         "sample": "Your repo is public", "usage": "Button labels, list item titles, emphasis."},
        {"name": "small", "fontSize": "14px", "lineHeight": "20px", "fontWeight": 600,
         "sample": "A public link where anyone can read your game's code.", "usage": "Help lines, tips, secondary rows."},
        {"name": "label", "fontSize": "13px", "lineHeight": "16px", "fontWeight": 800, "letterSpacing": "0.06em",
         "sample": "DAILY PACE", "usage": "Field labels and eyebrows, set in uppercase with CSS."},
        {"name": "caption", "fontSize": "12px", "lineHeight": "16px", "fontWeight": 700,
         "sample": "Updated 4 min ago", "usage": "Timestamps, nav labels, tiny metadata."},
    ]},
]


def tokens_json():
    color_tokens = []
    for name, light, dark, usage in COLORS:
        value = light if dark is None else {"light": light, "dark": dark}
        color_tokens.append({"name": name, "value": value, "usage": usage})
    return {
        "name": "Save Point",
        "version": 1,
        "color": {"themes": [{"id": "light", "name": "Light"}, {"id": "dark", "name": "Dark"}], "tokens": color_tokens},
        "type": {"fonts": FONTS, "families": FAMILIES, "groups": TYPE_GROUPS},
        "spacing": {"note": "4px base. Lay siblings out with gap, not margins.", "tokens": [{"name": n, "value": v, "usage": u} for n, v, u in SPACING]},
        "radius": {"note": "Everything is rounded. Nothing in Save Point has a square corner.", "tokens": [{"name": n, "value": v, "usage": u} for n, v, u in RADII]},
        "shadow": {"note": "Depth is a solid lip in the fill's own darker shade, plus a soft float. Never a black outline.",
                   "tokens": [{"name": n, "value": {"light": l, "dark": d}, "usage": u} for n, l, d, u in SHADOWS]},
        "size": {"note": "Control heights, icon sizes and page widths.", "tokens": [{"name": n, "value": v, "usage": u} for n, v, u in SIZES]},
        "shape": {"note": "The lean and the press.", "tokens": [{"name": n, "value": v, "usage": u} for n, v, u in SHAPE]},
    }


def _lum(hexv):
    h = hexv.lstrip("#")[:6]
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast_report():
    vals = {n: (l, d or l) for n, l, d, _ in COLORS}
    bad = []
    for fg, bg, need in PAIRS:
        for i, theme in enumerate(("light", "dark")):
            a, b = _lum(vals[fg][i]), _lum(vals[bg][i])
            ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
            if ratio < need:
                bad.append(f"{theme}: {fg} on {bg} = {ratio:.2f} (needs {need})")
    return bad
