# Colour icons

MingCute Icon (`@iconify-json/mingcute` 1.2.8, by MingCute Design, Apache-2.0), redrawn as chunky, saturated stickers in Save
Point's palette, the way the hourglass (`hours.png`) is coloured: a rim a little darker than the body in the same hue, a
top-lit gradient body, a thin lighter bevel inside the edge, and the icon's holes set in as details in a strongly contrasting
colour (cream on a dark body, a deep colour on a light one). Each is a 24 by 24 layered SVG with its gradients' ids prefixed
by `spc-<name>`, so several can be inlined on one page.

They are decorative illustrations, 48px or larger: the steps on the landing page, empty states, headers. For an icon in text
or on a control, use the single-ink Icons set.

Built by `design/build/make_color_icons.py` from a per-icon spec (palettes, which parts are details, what to enlarge or fill
under). Edit the spec, run it, then `bin/rails style_sheet:sync` to copy them into the app.
