"""Writes the Save Point style sheet into design/system (except design-system.json, which records the artifact's uploaded assets).

Run from the repository root: python3 design/build/make.py
"""
import json, os, pathlib
import tokens, make_color_icons

ROOT = pathlib.Path(__file__).resolve().parent.parent / "system"
MINGCUTE = pathlib.Path.home() / "Documents/Developer/hackatime-editor/node_modules/@iconify-json/mingcute/icons.json"

ICONS = """home-4-fill game-2-fill save-2-fill star-fill sparkles-fill trophy-fill medal-fill gift-fill coin-fill fire-fill
time-fill calendar-fill check-fill check-circle-fill close-fill close-circle-fill warning-fill information-fill question-fill
lock-fill add-fill edit-2-fill search-fill settings-3-fill notification-fill user-3-fill heart-fill left-fill right-fill
down-fill up-fill arrow-up-fill arrow-down-fill refresh-2-fill upload-2-fill external-link-fill link-fill pic-fill
github-fill git-commit-fill steam-fill keyboard-fill mouse-fill palette-fill rocket-fill send-plane-fill truck-fill
play-fill pause-fill flag-1-fill chart-bar-fill shopping-bag-1-fill lightning-fill more-1-fill loading-fill""".split()

ASSET_INK = "#2a43c4"  # royal-ink, light theme


def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def icons():
    data = json.loads(MINGCUTE.read_text())
    bodies = {}
    for name in ICONS:
        icon = data["icons"][name]
        assert icon.get("width", data.get("width", 24)) == 24
        bodies[name] = icon["body"]
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">{icon["body"].replace("currentColor", ASSET_INK)}</svg>\n'
        write(f"assets/Icons/{name}.svg", svg)
    write("assets/Icons/README.md", f"""# Icons

MingCute Icon, Fill style: the same set ShaderGator uses (`@iconify-json/mingcute` 1.2.8, by MingCute Design, Apache-2.0).
Each is a 24 by 24 single-ink SVG. These files are drawn in `royal-ink` ({ASSET_INK}) so they read on the light ground;
in the product, inline them with `fill="currentColor"` through `SavePoint.icon(name)` or `<i data-icon="name"></i>`
so they take the text colour. Need one that isn't here? Take it from the same set, Fill style, and add it to `components/bundle.js`.
""")
    for name in ICONS:
        assert "</script" not in bodies[name] and "<!--" not in bodies[name]
    js = ["/* @ds-bundle: {\"format\":4,\"namespace\":\"SavePoint\",\"components\":[]} */",
          "/* Save Point icons: MingCute Icon (Fill), by MingCute Design, Apache-2.0. Each body is the inside of a 24 by 24 SVG painted with currentColor. */",
          "window.SavePoint = (function () {",
          "  var icons = " + json.dumps(bodies, indent=None, separators=(",", ":")) + ";",
          "  function icon(name, label) {",
          "    var body = icons[name];",
          "    if (!body) return '';",
          "    var a11y = label ? ' role=\"img\" aria-label=\"' + String(label).replace(/\"/g, '&quot;') + '\"' : ' aria-hidden=\"true\"';",
          "    return '<svg class=\"sp-icon\" viewBox=\"0 0 24 24\" focusable=\"false\"' + a11y + '>' + body + '</svg>';",
          "  }",
          "  function mountIcons(root) {",
          "    var els = (root || document).querySelectorAll('[data-icon]');",
          "    for (var i = 0; i < els.length; i++) {",
          "      var el = els[i];",
          "      if (el.firstChild) continue;",
          "      el.innerHTML = icon(el.getAttribute('data-icon'), el.getAttribute('data-icon-label'));",
          "    }",
          "  }",
          "  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { mountIcons(); });",
          "  else mountIcons();",
          "  return { icons: icons, icon: icon, mountIcons: mountIcons };",
          "})();",
          ""]
    write("components/bundle.js", "\n".join(js))


def i(name, cls=""):
    c = f' class="{cls}"' if cls else ""
    return f'<i data-icon="{name}"{c}></i>'


def preview(group, height, body, title, subtitle=None):
    sub = f' subtitle="{subtitle}"' if subtitle else ""
    return f"""<!-- @dsCard group="{group}" height={height}{sub} -->
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>{title}</title></head>
<body>
{body}
<script>window.SavePoint && SavePoint.mountIcons();</script>
</body>
</html>
"""


def stars(on, total=5, sm=False):
    cls = "sp-stars sp-stars--sm" if sm else "sp-stars"
    inner = "".join(i("star-fill", "is-on") for _ in range(on)) + "".join(i("star-fill", "is-off") for _ in range(total - on))
    return f'<span class="{cls}" role="img" aria-label="{on} of {total} stars">{inner}</span>'


COMPONENTS = {}


def comp(name, group, height, body, readme):
    COMPONENTS[name] = (group, height, body, readme)


comp("Button", "Actions", 120, f"""<div class="sp-demo">
  <button class="sp-btn sp-btn--gold sp-btn--lg" id="b1">{i("save-2-fill")}Join Save Point</button>
  <button class="sp-btn sp-btn--royal" id="b2">{i("rocket-fill")}Ship my game</button>
  <button class="sp-btn" id="b3">{i("gift-fill")}See prizes</button>
  <button class="sp-btn sp-btn--mint" id="b4">{i("check-fill")}Approve 6.5 hrs</button>
  <button class="sp-btn sp-btn--sm" id="b5">{i("edit-2-fill")}Edit</button>
  <button class="sp-btn sp-btn--ghost" id="b6">Not now</button>
  <button class="sp-btn sp-btn--royal" id="b7" disabled>Ship my game</button>
</div>""", """# Button

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
""")

comp("IconButton", "Actions", 96, f"""<div class="sp-demo">
  <button class="sp-btn sp-iconbtn" id="ib1" aria-label="Close">{i("close-fill")}</button>
  <button class="sp-btn sp-iconbtn sp-btn--royal" id="ib2" aria-label="Previous prize">{i("left-fill")}</button>
  <button class="sp-btn sp-iconbtn sp-btn--royal" id="ib3" aria-label="Next prize">{i("right-fill")}</button>
  <button class="sp-btn sp-iconbtn sp-btn--gold" id="ib4" aria-label="Add a Hackatime project">{i("add-fill")}</button>
  <button class="sp-btn sp-iconbtn sp-btn--sm" id="ib5" aria-label="More">{i("more-1-fill")}</button>
  <button class="sp-btn sp-iconbtn sp-btn--sm" id="ib6" aria-label="Refresh hours">{i("refresh-2-fill")}</button>
</div>""", """# IconButton

A round button holding one icon: close, previous and next, add, more. Add `sp-iconbtn` to an `sp-btn` and keep the colour modifiers.

The consumer provides the icon and an `aria-label` that says what it does ("Close", "Next prize"). Use it only where the icon is
unmistakable; anything else gets a labelled `Button`. The close button sits on a modal's top-right corner, half outside it.
""")

comp("MenuTile", "Actions", 150, f"""<nav class="sp-demo" aria-label="Menu">
  <a class="sp-tile" href="#" aria-current="page"><span class="sp-tile__face">{i("game-2-fill")}</span>My game</a>
  <a class="sp-tile" href="#"><span class="sp-tile__face">{i("gift-fill")}<span class="sp-dot">!</span></span>Prizes</a>
  <a class="sp-tile" href="#"><span class="sp-tile__face">{i("trophy-fill")}</span>Leaderboard</a>
  <a class="sp-tile" href="#"><span class="sp-tile__face">{i("rocket-fill")}<span class="sp-dot">2</span></span>Ship</a>
  <a class="sp-tile" href="#"><span class="sp-tile__face">{i("question-fill")}</span>Help</a>
</nav>""", """# MenuTile

A big rounded-square tile with an icon and a label under it: the home screen's menu, gacha style.

Markup: `<a class="sp-tile"><span class="sp-tile__face"><i data-icon="…"></i></span>Label</a>`. Mark the current one with
`aria-current="page"`; it turns royal. Put a notification dot inside the face with `<span class="sp-dot">2</span>`: a number
when there's a count, `!` when something needs doing. Labels are one or two words. Lay tiles in a grid of three or four across.
""")

comp("TextField", "Inputs", 250, f"""<div class="sp-demo sp-demo--form">
  <label class="sp-field"><span class="sp-label">Game title</span><input class="sp-input" id="tf1" value="Moth &amp; Lantern"></label>
  <label class="sp-field"><span class="sp-label">Repo link</span><input class="sp-input" id="tf2" placeholder="https://github.com/you/your-game"><span class="sp-help">{i("information-fill")}Anyone should be able to open it without signing in.</span></label>
  <label class="sp-field sp-field--error"><span class="sp-label">What did you change since last time?</span><textarea class="sp-input" id="tf3">fixed bugs</textarea><span class="sp-help">{i("warning-fill")}Tell us a bit more: at least 40 characters.<span class="sp-count">10 / 40</span></span></label>
</div>""", """# TextField

A label, a sunken well, and an optional help line. Wrap them in `<label class="sp-field">`; the input is `sp-input` (also on `<textarea>`).

- The label is `sp-label`: short, set in uppercase by CSS. Write it in sentence case in the markup.
- The help line is `sp-help`, under the field, with an `information-fill` icon. Say what's expected, not what's forbidden.
- On error, add `sp-field--error` to the wrapper and swap the help icon to `warning-fill`. The message says what to do:
  "Tell us a bit more: at least 40 characters." Show a live count (`sp-count`) for fields with a minimum.
- Focus lifts the well to `surface` with a royal halo.
""")

comp("Select", "Inputs", 120, f"""<div class="sp-demo sp-demo--form">
  <label class="sp-field"><span class="sp-label">When do you build?</span><span class="sp-select"><select class="sp-input" id="sel1"><option>After school</option><option selected>Evenings</option><option>Late at night</option><option>Weekends</option></select>{i("down-fill")}</span></label>
  <label class="sp-field"><span class="sp-label">Hackatime project</span><span class="sp-select"><select class="sp-input" id="sel2"><option>moth-and-lantern</option><option>jamegam-entry</option></select>{i("down-fill")}</span></label>
</div>""", """# Select

A native `<select>` styled as a field, with a `down-fill` chevron. Markup: `<span class="sp-select"><select class="sp-input">…</select><i data-icon="down-fill"></i></span>`
inside an `sp-field`. Use it for five or more options; for two to four, use `Segmented`.
""")

comp("Choice", "Inputs", 170, f"""<div class="sp-demo" style="align-items:flex-start;gap:48px">
  <fieldset class="sp-fieldset"><legend class="sp-label">Where can people play it?</legend>
    <label class="sp-choice"><input type="checkbox" class="sp-check" id="c1" checked> In the browser</label>
    <label class="sp-choice"><input type="checkbox" class="sp-check" id="c2"> Windows download</label>
    <label class="sp-choice"><input type="checkbox" class="sp-check" id="c3" disabled> Mac download</label>
  </fieldset>
  <fieldset class="sp-fieldset"><legend class="sp-label">Engine</legend>
    <label class="sp-choice"><input type="radio" class="sp-radio" name="eng" id="r1" checked> Godot</label>
    <label class="sp-choice"><input type="radio" class="sp-radio" name="eng" id="r2"> Unity</label>
    <label class="sp-choice"><input type="radio" class="sp-radio" name="eng" id="r3"> Something else</label>
  </fieldset>
</div>""", """# Choice

Checkboxes (`sp-check`) and radios (`sp-radio`) on native inputs, checked in royal with a springy pop.

Wrap each in `<label class="sp-choice">` so the text is clickable, and group them in `<fieldset class="sp-fieldset">` with a
`<legend class="sp-label">`. Checkboxes are for independent yes/no answers; radios for one of several.
""")

comp("Switch", "Inputs", 110, f"""<div class="sp-demo sp-demo--col">
  <label class="sp-choice"><input type="checkbox" role="switch" class="sp-switch" id="sw1" checked> Remind me at my build time</label>
  <label class="sp-choice"><input type="checkbox" role="switch" class="sp-switch" id="sw2"> Show me on the leaderboard</label>
</div>""", """# Switch

An on/off setting that takes effect at once: `<input type="checkbox" role="switch" class="sp-switch">` inside an `sp-choice` label.
On is mint. Use it for settings (reminders, leaderboard visibility), never for answers in a form; those are `Choice`.
""")

comp("Segmented", "Inputs", 110, f"""<div class="sp-demo">
  <div class="sp-field"><span class="sp-label" id="pace">Daily pace</span>
    <div class="sp-seg" role="radiogroup" aria-labelledby="pace">
      <label><input type="radio" name="pace" id="p1"><span>30 min</span></label>
      <label><input type="radio" name="pace" id="p2" checked><span>1 hr</span></label>
      <label><input type="radio" name="pace" id="p3"><span>2 hrs</span></label>
      <label><input type="radio" name="pace" id="p4"><span>3 hrs</span></label>
    </div>
  </div>
</div>""", """# Segmented

Two to four options in one sunken pill; the chosen one is a raised gold chip. Built on radios, so it works with the keyboard
and in forms: `<div class="sp-seg" role="radiogroup">` holding `<label><input type="radio"><span>Label</span></label>`.
Use it for pace, filters ("This week" / "All time"), and other short, exclusive choices.
""")

comp("Badge", "Status", 80, f"""<div class="sp-demo">
  <span class="sp-badge">{i("time-fill")}In review</span>
  <span class="sp-badge sp-badge--gold">{i("edit-2-fill")}Changes needed</span>
  <span class="sp-badge sp-badge--mint">{i("check-circle-fill")}Approved</span>
  <span class="sp-badge sp-badge--coral">{i("close-circle-fill")}Can't ship yet</span>
  <span class="sp-badge sp-badge--violet">{i("sparkles-fill")}Digital prize</span>
</div>""", """# Badge

A soft pill that names a state. Always an icon and a word; colour is never the only signal.

| State | Class | Icon |
| --- | --- | --- |
| In review | `sp-badge` | `time-fill` |
| Changes needed | `sp-badge--gold` | `edit-2-fill` |
| Approved | `sp-badge--mint` | `check-circle-fill` |
| Blocked, error | `sp-badge--coral` | `close-circle-fill` |
| Digital prize, new | `sp-badge--violet` | `sparkles-fill` |
""")

comp("StatChip", "Status", 80, f"""<div class="sp-demo">
  <span class="sp-stat"><span class="sp-stat__key">{i("time-fill")}</span>8.6<span class="sp-stat__unit">hrs</span></span>
  <span class="sp-stat"><span class="sp-stat__key sp-stat__key--bronze">{i("fire-fill")}</span>5<span class="sp-stat__unit">day streak</span></span>
  <span class="sp-stat"><span class="sp-stat__key sp-stat__key--mint">#</span>12<span class="sp-stat__unit">this week</span></span>
</div>""", """# StatChip

A navy pill with a round key on the left and a number: the gacha stat readout. Markup:
`<span class="sp-stat"><span class="sp-stat__key"><i data-icon="time-fill"></i></span>8.6<span class="sp-stat__unit">hrs</span></span>`.

Keys: gold (hours, default), `sp-stat__key--bronze` (streak), `sp-stat__key--mint` (rank). Keep numbers short: one decimal for hours.
Put two or three in a row at the top of a profile or panel; more than that is a table.
""")

comp("Stars", "Status", 90, f"""<div class="sp-demo">
  {stars(3)}
  {stars(5)}
  {stars(2, sm=True)}
</div>""", """# Stars

A row of gold stars with a drop under each, from the logo's star. `<span class="sp-stars" role="img" aria-label="3 of 5 stars">`
holding `<i data-icon="star-fill" class="is-on">` and `class="is-off"` items. `sp-stars--sm` for inline use.

Stars mean streak rewards earned: one star per streak milestone (3, 5, 7, 10 days). Don't use them for ratings or rarity.
""")

comp("Toast", "Status", 190, f"""<div class="sp-demo sp-demo--col">
  <div class="sp-toast" role="status"><span class="sp-toast__icon">{i("check-fill")}</span>Saved. Your goal is the Aula F75.</div>
  <div class="sp-toast sp-toast--gold" role="status"><span class="sp-toast__icon">{i("fire-fill")}</span>Day 4 of your streak. Keep it going.</div>
  <div class="sp-toast sp-toast--coral" role="alert"><span class="sp-toast__icon">{i("warning-fill")}</span>Hackatime didn't answer. Try again in a minute.</div>
</div>""", """# Toast

A floating pill that confirms what just happened. Mint for done, gold for streaks and rewards, coral for something that failed.
Add `is-entering` when it appears for a short springy pop. Use `role="status"`, or `role="alert"` for coral.

Say what happened in a few words, past tense: "Saved." Failures say what to do next. Toasts leave after five seconds,
except coral ones, which stay until dismissed.
""")

comp("HoursMeter", "Progress", 170, f"""<div class="sp-demo sp-demo--col">
  <div class="sp-meter" style="--approved:36%;--pending:18%">
    <div class="sp-meter__top"><span class="sp-meter__now">6.5 <small>/ 12 hrs</small></span><span class="sp-meter__goal">{i("keyboard-fill")}Goal: Aula F75</span></div>
    <div class="sp-meter__bar" role="meter" aria-label="Hours toward the Aula F75" aria-valuemin="0" aria-valuemax="12" aria-valuenow="6.5">
      <div class="sp-meter__track"><span class="sp-meter__fill"></span><span class="sp-meter__pending"></span><span class="sp-meter__tick" style="--at:29%"></span><span class="sp-meter__tick" style="--at:42%"></span><span class="sp-meter__tick" style="--at:71%"></span></div>
      <span class="sp-meter__end">{i("star-fill")}</span>
    </div>
    <div class="sp-meter__foot"><span><span class="sp-key"></span>4.3 approved</span><span><span class="sp-key sp-key--gold"></span>2.2 in review</span><span class="sp-meter__pace">1.1 hrs a day gets you there</span></div>
  </div>
</div>""", """# HoursMeter

The leaning HP bar that shows hours toward the chosen goal. It fills mint to lime for approved hours, then gold stripes for hours
still in review, and ends at a gold star: the goal.

Set `--approved` and `--pending` as percentages of the goal's hours on `sp-meter`. Add an `sp-meter__tick` with `--at` for each
cheaper prize on the way. The foot line carries the daily pace: (goal hours − hours logged) ÷ days left, to one decimal,
phrased as "1.1 hrs a day gets you there". Give the bar `role="meter"` with min, max and now, and an `aria-label` naming the goal.
""")

comp("PlayerPlate", "Progress", 120, f"""<div class="sp-demo">
  <div class="sp-plate">
    <span class="sp-plate__avatar">ML</span>
    <div class="sp-plate__main">
      <div class="sp-plate__row"><span class="sp-plate__name">moth_lantern</span>{stars(3, sm=True)}</div>
      <div class="sp-plate__bar" style="--approved:36%;--pending:18%"><span class="sp-meter__fill"></span><span class="sp-meter__pending"></span></div>
      <div class="sp-plate__nums"><b>6.5</b> / 12 hrs</div>
    </div>
  </div>
</div>""", """# PlayerPlate

A leaning navy plate with an avatar, name, streak stars and a slim hours bar: the participant's header on their own page and the
top of a review. The plate leans with `--slant`; everything inside is counter-skewed so text stays upright.

Provide the avatar (an `<img>` from Slack, or two initials), the display name, stars earned, and `--approved` / `--pending` on
`sp-plate__bar`. One plate per screen.
""")

comp("Stepper", "Progress", 120, f"""<div class="sp-demo sp-demo--col">
  <ol class="sp-steps" aria-label="Getting started">
    <li class="sp-step is-done"><span class="sp-step__dot">{i("check-fill")}</span>Pick your game</li>
    <li class="sp-step is-done"><span class="sp-step__dot">{i("check-fill")}</span>Link Hackatime</li>
    <li class="sp-step is-current" aria-current="step"><span class="sp-step__dot">3</span>Choose a goal</li>
    <li class="sp-step"><span class="sp-step__dot">4</span>Set your pace</li>
    <li class="sp-step"><span class="sp-step__dot">5</span>Sign</li>
  </ol>
</div>""", """# Stepper

Joining, step by step: done steps are mint with a check, the current one gold with a halo, later ones sunken.
`<ol class="sp-steps">` of `<li class="sp-step is-done|is-current">` holding `<span class="sp-step__dot">` and a label.
Mark the current one `aria-current="step"`. Up to five steps; labels are two or three words.
""")

days = [("Sun", "25", "is-built", "fire-fill"), ("Mon", "26", "is-built", "fire-fill"), ("Tue", "27", "", None), ("Wed", "28", "is-built", "fire-fill"),
        ("Thu", "29", "is-today", None), ("Fri", "30", "", None), ("Sat", "31", "", None), ("Sun", "1", "", None), ("Mon", "2", "", None), ("Tue", "3", "is-due", "flag-1-fill")]
day_html = "\n".join(f'    <li class="sp-day {c}">{d}<b>{n}</b>{i(ic) if ic else ""}</li>' for d, n, c, ic in days)
comp("DayStrip", "Progress", 150, f"""<div class="sp-demo sp-demo--col">
  <ol class="sp-days" aria-label="Your days in Save Point (example dates)">
{day_html}
  </ol>
</div>""", """# DayStrip

Every day of the program as a cell: built days are cream with a copper flame, today has a royal ring, the deadline is violet
with a flag. A day counts as built at 20 minutes logged. The program is short, so show all of its days at once.
`<ol class="sp-days">` of `<li class="sp-day is-built|is-today|is-due">Weekday<b>Date</b><i data-icon="fire-fill"></i></li>`.
""")

comp("Panel", "Content", 220, f"""<div class="sp-demo sp-page" style="padding-top:40px">
  <section class="sp-panel" style="flex:1;min-width:280px">
    <h2 class="sp-ribbon"><span>{i("save-2-fill")}Your save</span></h2>
    <p style="margin:0">Moth &amp; Lantern, from the jame gam. Hours count from the day Save Point starts.</p>
    <div class="sp-cluster">
      <span class="sp-stat"><span class="sp-stat__key">{i("time-fill")}</span>6.5<span class="sp-stat__unit">hrs</span></span>
      <span class="sp-stat"><span class="sp-stat__key sp-stat__key--bronze">{i("fire-fill")}</span>3<span class="sp-stat__unit">day streak</span></span>
    </div>
  </section>
  <section class="sp-panel" style="flex:1;min-width:240px">
    <h2 class="sp-ribbon sp-ribbon--gold"><span>{i("gift-fill")}Next prize</span></h2>
    <p style="margin:0">8BitDo Ultimate 2C is 0.5 hrs away.</p>
  </section>
</div>""", """# Panel

The white card everything sits in, with a leaning ribbon for its title hanging over the top edge. `<section class="sp-panel">` with
`<h2 class="sp-ribbon"><span>Title</span></h2>` as its first child. Royal ribbons for the page's own sections; one gold
ribbon (`sp-ribbon--gold`) for what's rewarding (the next prize). Panels sit on the `sp-page` checker ground with a
`space-12` gap above each, so the ribbon has room.
""")

prizes = [
    ("Aseprite", "palette-fill", "3.5", "is-ready", f'{i("gift-fill")}Ready to claim', '<span class="sp-badge sp-badge--violet sp-prize__tag">Digital</span>', ""),
    ("8BitDo Ultimate 2C", "game-2-fill", "5", "is-goal", f'{i("time-fill")}0.5 hrs to go', "", '<span class="sp-prize__flag">Your goal</span>'),
    ("Aula F75 keyboard", "keyboard-fill", "12", "", f'{i("lock-fill")}5.5 hrs to go', "", ""),
    ("Steam $25", "steam-fill", "4.5", "is-claimed", f'{i("check-circle-fill")}Claimed', '<span class="sp-badge sp-badge--violet sp-prize__tag">Digital</span>', ""),
]
prize_html = "\n".join(f"""    <a class="sp-prize {state}" href="#"><div class="sp-prize__art">{i(icon)}{tag}{flag}</div><div class="sp-prize__body"><h3 class="sp-prize__name">{name}</h3><p class="sp-prize__hrs">{hrs} <small>hrs</small></p></div><div class="sp-prize__state">{line}</div></a>"""
                       for name, icon, hrs, state, line, tag, flag in prizes)
comp("PrizeCard", "Content", 330, f"""<div class="sp-demo sp-demo--col">
  <div class="sp-prizes">
{prize_html}
  </div>
</div>""", """# PrizeCard

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
""")

comp("ShipChecklist", "Content", 470, f"""<div class="sp-demo sp-demo--col">
  <section class="sp-checklist" aria-labelledby="ship-h">
    <div class="sp-checklist__head"><h3 id="ship-h">Ready to ship?</h3><span class="sp-badge">{i("check-fill")}4 of 7</span></div>
    <ol>
      <li class="sp-item is-ok"><span class="sp-item__mark">{i("check-fill")}</span><span class="sp-item__title">Hackatime is linked</span></li>
      <li class="sp-item is-ok"><span class="sp-item__mark">{i("check-fill")}</span><span class="sp-item__title">New hours since the start: 6.5</span></li>
      <li class="sp-item is-fail"><span class="sp-item__mark">{i("close-fill")}</span><span class="sp-item__title">Your repo is public</span><p class="sp-item__tip">A public link where anyone can read your game's code. On GitHub, the repository needs to be public.</p>
        <label class="sp-field"><span class="sp-label">Repo link</span><input class="sp-input" id="ck1" value="https://github.com/moth/lantern"></label></li>
      <li class="sp-item is-warn"><span class="sp-item__mark">{i("warning-fill")}</span><span class="sp-item__title">Playable on itch.io</span><p class="sp-item__tip">This doesn't stop you shipping. itch.io is where people find games, so it's best.</p></li>
      <li class="sp-item is-wait"><span class="sp-item__mark">{i("lock-fill")}</span><span class="sp-item__title">README says how to play</span><p class="sp-item__tip">Waits for your repo link.</p></li>
    </ol>
  </section>
</div>""", """# ShipChecklist

The interactive ship checker: every check that blocks shipping or warns, each with the one field that fixes it right there.

| State | Class | Mark |
| --- | --- | --- |
| Passed | `is-ok` | mint `check-fill` |
| Blocks shipping | `is-fail` | coral `close-fill`, plus its tip and field |
| Warning only | `is-warn` | gold `warning-fill`, plus its tip |
| Waiting on another step | `is-wait` | `lock-fill`, dashed |
| Couldn't run | `is-warn` | tip: "We couldn't check this just now. Try again in a minute." |

A step's title says what's true when it passes ("Your repo is public"). Its tip says why, or where to go. A step fixed while
the list is open stays ticked in place. The header badge counts passed checks. Ship stays disabled until no `is-fail` remains.
""")

board = [("1", "pixelmoth", "21.5", "up", "2"), ("2", "tilde", "19.0", "", "—"), ("3", "quietfox", "17.2", "down", "1"), ("7", "moth_lantern (you)", "6.5", "up", "4")]
rows = []
for rank, name, hrs, d, n in board:
    rk = f"sp-rank sp-rank--{rank}" if rank in "123" else "sp-rank"
    you = " is-you" if "(you)" in name else ""
    initials = name[:2].upper()
    if d == "up":
        delta = f'<span class="sp-delta sp-delta--up" aria-label="up {n} since yesterday">{i("arrow-up-fill")}{n}</span>'
    elif d == "down":
        delta = f'<span class="sp-delta sp-delta--down" aria-label="down {n} since yesterday">{i("arrow-down-fill")}{n}</span>'
    else:
        delta = f'<span class="sp-delta">{n}</span>'
    rows.append(f'    <li class="sp-row{you}"><span class="{rk}">{rank}</span><span class="sp-avatar">{initials}</span><span class="sp-row__name">{name}</span><span class="sp-row__hrs">{hrs} <small>hrs</small></span>{delta}</li>')
comp("Leaderboard", "Content", 290, f"""<div class="sp-demo sp-demo--col">
  <ol class="sp-board" aria-label="Hours this week">
{chr(10).join(rows)}
  </ol>
</div>""", """# Leaderboard

Pill rows ranked by hours this week: gold, silver and bronze medals for the top three, your own row in `gold-soft`, and the change
since yesterday in mint (up) or coral (down) with an arrow icon. `<ol class="sp-board">` of
`<li class="sp-row">` holding `sp-rank`, `sp-avatar`, `sp-row__name`, `sp-row__hrs`, `sp-delta`.

Always show the viewer's row, even when they're not in the top ten (show the top rows, then theirs). Names are Slack display
names; never show anything else about a person here.
""")

comp("FAQ", "Content", 250, f"""<div class="sp-demo sp-demo--col">
  <div class="sp-faq">
    <details open id="q1"><summary>Which hours count?{i("down-fill")}</summary><div>Hours you log in Hackatime on your game from the day Save Point starts. Time from before that, or time another Hack Club program already counted, doesn't.</div></details>
    <details id="q2"><summary>Can I keep working on my jame gam game?{i("down-fill")}</summary><div>Yes, that's what Save Point is for. Everything after your jame gam submission counts here.</div></details>
    <details id="q3"><summary>Can I get more than one prize?{i("down-fill")}</summary><div>Yes. Approved hours work like money: spend them on any prizes they cover, one of each.</div></details>
  </div>
</div>""", """# FAQ

Questions that open in place, on native `<details>`/`<summary>`, so they work without script. Put a `down-fill` icon last in the
summary; it flips when open. Write questions the way a participant would ask them, and answer in two sentences or fewer.
""")

comp("Modal", "Content", 420, f"""<div class="sp-scrim">
  <div class="sp-modal" role="dialog" aria-modal="true" aria-labelledby="m-h">
    <button class="sp-btn sp-iconbtn sp-modal__close" id="mc" aria-label="Close">{i("close-fill")}</button>
    <div class="sp-modal__head"><h2 id="m-h">Make this your goal?</h2><p>You can change it any time.</p></div>
    <div class="sp-modal__body">
      <div class="sp-cluster"><span class="sp-stat"><span class="sp-stat__key">{i("keyboard-fill")}</span>12<span class="sp-stat__unit">hrs</span></span><strong>Aula F75 keyboard</strong></div>
      <p style="margin:0">At your pace that's about 1.1 hrs a day until the end.</p>
      <div class="sp-modal__actions"><button class="sp-btn sp-btn--ghost" id="m1">Not now</button><button class="sp-btn sp-btn--gold" id="m2">{i("flag-1-fill")}Set as my goal</button></div>
    </div>
  </div>
</div>""", """# Modal

A bubbly popup: royal header with a scalloped edge, white body, a round close button on the corner. Use it to confirm a choice
(set a goal, claim a prize) or show a celebration. `role="dialog"`, `aria-modal="true"`, labelled by its heading; trap focus
inside and return it on close. The main action is gold and sits last; "Not now" is a ghost button before it.
Lay it on `sp-scrim`, which tints the page with `royal-glow`.
""")

comp("DisplayText", "Content", 230, f"""<div class="sp-demo sp-demo--col" style="gap:8px">
  <span class="sp-logo-text" style="font-size:72px;line-height:1.05">Save Point</span>
  <span class="sp-callout-text" style="font-size:30px;line-height:40px">Continue a game you stopped working on</span>
  <span class="sp-callout-text" style="font-size:30px;line-height:40px">Get a prize!</span>
</div>""", """# DisplayText

Two text treatments taken from the logo and the launch poster, for big words only.

- `sp-logo-text`: Rubik Black italic, white to `logo-fill` gradient, thick `logo-line` outline. For the wordmark when the image
  can't be used, and at most one other headline per page. 48px and up.
- `sp-callout-text`: Rubik ExtraBold italic in `violet-ink` with a thick white outline, like the poster's tagline. For a
  one-line hook on the landing page or a celebration. 24px and up.

Never set body copy, buttons or anything under 24px in either. Use the real logo image (`assets/Logos`) wherever it fits.
""")

comp("BottomNav", "Navigation", 110, f"""<div class="sp-demo">
  <nav class="sp-nav" aria-label="Main">
    <a href="#" aria-current="page">{i("home-4-fill")}Home</a>
    <a href="#">{i("game-2-fill")}My game</a>
    <a href="#">{i("gift-fill")}Prizes<span class="sp-dot">1</span></a>
    <a href="#">{i("trophy-fill")}Board</a>
    <a href="#">{i("question-fill")}Help</a>
  </nav>
</div>""", """# BottomNav

The navy pill nav: icon over label, dashed dividers, the current page a raised gold chip. On phones it's fixed to the bottom
of the screen (add `env(safe-area-inset-bottom)` to its offset); on desktop it sits centred under the top bar.
`<nav class="sp-nav">` of `<a>` links; mark the current one `aria-current="page"`. Four or five items, one word each.
""")

comp("PageLayout", "Layout", 520, f"""<div class="sp-page" style="min-height:520px">
  <div class="sp-container">
    <header class="sp-topbar"><a class="sp-topbar__logo sp-logo-text" href="#">Save Point</a>
      <div class="sp-cluster"><span class="sp-stat"><span class="sp-stat__key">{i("time-fill")}</span>6.5<span class="sp-stat__unit">hrs</span></span><button class="sp-btn sp-iconbtn sp-btn--sm" id="pl0" aria-label="Settings">{i("settings-3-fill")}</button></div></header>
    <div class="sp-grid" style="padding-top:24px">
      <section class="sp-panel sp-span-8"><h2 class="sp-ribbon"><span>{i("save-2-fill")}Your save</span></h2>
        <div class="sp-meter" style="--approved:36%;--pending:18%"><div class="sp-meter__top"><span class="sp-meter__now">6.5 <small>/ 12 hrs</small></span><span class="sp-meter__goal">{i("keyboard-fill")}Goal: Aula F75</span></div>
        <div class="sp-meter__bar"><div class="sp-meter__track"><span class="sp-meter__fill"></span><span class="sp-meter__pending"></span></div><span class="sp-meter__end">{i("star-fill")}</span></div></div></section>
      <section class="sp-panel sp-span-4"><h2 class="sp-ribbon sp-ribbon--gold"><span>{i("rocket-fill")}Ship</span></h2>
        <p style="margin:0">4 of 7 checks pass.</p><button class="sp-btn sp-btn--royal" id="pl1">Open the checklist</button></section>
    </div>
  </div>
</div>""", """# PageLayout

How a page goes together: the `sp-page` checker ground, an `sp-container` (max `content-max`, gutters `space-4` on phones,
`space-6` from 600px, `space-8` from 960px), a top bar, then panels on `sp-grid`.

The grid is 4 columns on phones, 6 from 600px and 12 from 960px, with a `space-6` gap. Children span the full width until 960px;
from there use `sp-span-8` + `sp-span-4` for main and side, or `sp-span-6` twice. Leave `space-12` between rows of panels so
ribbons don't touch the panel above. On phones, add the `BottomNav` fixed to the bottom and pad the page by its height.
""")


README = """Save Point is a Hack Club program: keep working on a game you stopped (usually your jame gam game), log the hours, and pick prizes
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
"""

LOGO_README = """# Logos

- `save-point-logo.png`: the full-colour Save Point logo (1988 × 816, transparent). Royal letters with a periwinkle-to-navy outline,
  a gold four-point star, a copper halo, and "hack club" in copper above the halo's left arm. Use it on `sky`, `surface` or any light ground at 160px wide or more; on the dark
  theme it keeps its own white outline. Never recolour, stretch or redraw it. Below 160px, set "Save Point" with `sp-logo-text`.
"""

COVER = """<!-- @dsCard height=300 -->
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Save Point</title>
<style>
  html, body { margin: 0; height: 100%; }
  body { background: var(--sky); color: var(--ink); font-family: var(--font-body); overflow: hidden; }
  .cover { position: relative; height: 300px; overflow: hidden; }
  .art { position: absolute; top: 0; left: 480px; width: 480px; height: 300px; overflow: hidden; }
  .art svg { display: block; width: 480px; height: 300px; }
  .royal { fill: var(--royal); }
  .gold { fill: var(--gold); }
  .tint { fill: var(--royal-soft); }
  .glass { fill: var(--logo-fill); }
  .halo { fill: none; stroke: var(--copper); stroke-width: 16; stroke-linecap: round; }
  .spark { fill: var(--gold-hi); }
  .spark.on-light { fill: var(--gold); }
  .words { position: absolute; left: 32px; right: 32px; bottom: 32px; max-width: 440px; }
  .name { margin: 0; font-family: var(--font-display); font-style: italic; font-weight: 900; font-size: 112px; line-height: .92; letter-spacing: -0.01em; color: var(--ink); }
  .tag { margin: 12px 0 0 4px; font-size: 14px; line-height: 20px; font-weight: 700; color: var(--ink-muted); }
</style>
</head>
<body>
<div class="cover">
<div class="art" aria-hidden="true">
<svg viewBox="0 0 480 300" width="480" height="300">
<!--
  blocks      royal 136x264 bled off the top (the letters) · gold 112 disc (the star) · logo-fill 168x232 bled off the right (the glass fill) · royal-soft 112x56 (relief) — about 40% of 960x300
  arrangement one tall royal slab with satellites; bottoms on one line space-8 above the edge; space-4 gutters
  pattern     the logo's four-point star: ten sparkles in gold-hi and gold, plus the copper halo arc from the logo crossing slab, disc and glass — "the star and the halo are the brand"
  scales      sides in space-4 and space-8 multiples; corners radius-lg (24) on blocks, radius-md (16) on the tint; the disc's rx is half its side
-->
<rect class="royal" x="16" y="-24" width="136" height="292" rx="24"/>
<rect class="tint" x="168" y="24" width="112" height="56" rx="16"/>
<rect class="gold" x="168" y="156" width="112" height="112" rx="56"/>
<rect class="glass" x="296" y="36" width="200" height="232" rx="24"/>
<path class="halo" d="M 40 150 C 120 70, 360 60, 460 132"/>
<path class="spark" d="M84 96 Q84 112 100 112 Q84 112 84 128 Q84 112 68 112 Q84 112 84 96 Z"/>
<path class="spark" d="M60 176 Q60 184 68 184 Q60 184 60 192 Q60 184 52 184 Q60 184 60 176 Z"/>
<path class="spark" d="M116 212 Q116 222 126 222 Q116 222 116 232 Q116 222 106 222 Q116 222 116 212 Z"/>
<path class="spark" d="M224 176 Q224 212 260 212 Q224 212 224 248 Q224 212 188 212 Q224 212 224 176 Z"/>
<path class="spark on-light" d="M352 92 Q352 116 376 116 Q352 116 352 140 Q352 116 328 116 Q352 116 352 92 Z"/>
<path class="spark on-light" d="M420 168 Q420 180 432 180 Q420 180 420 192 Q420 180 408 180 Q420 180 420 168 Z"/>
<path class="spark on-light" d="M388 220 Q388 228 396 228 Q388 228 388 236 Q388 228 380 228 Q388 228 388 220 Z"/>
<path class="spark on-light" d="M448 64 Q448 72 456 72 Q448 72 448 80 Q448 72 440 72 Q448 72 448 64 Z"/>
<path class="spark on-light" d="M224 40 Q224 52 236 52 Q224 52 224 64 Q224 52 212 52 Q224 52 224 40 Z"/>
<path class="spark" d="M132 40 Q132 48 140 48 Q132 48 132 56 Q132 48 124 48 Q132 48 132 40 Z"/>
</svg>
</div>
<div class="words">
<h1 class="name">Save<br>Point</h1>
<p class="tag">Continue a game you stopped working on. Get a prize.</p>
</div>
</div>
</body>
</html>
"""


def main():
    write("tokens.json", json.dumps(tokens.tokens_json(), indent=2) + "\n")
    icons()
    make_color_icons.main()
    write("README.md", README)
    write("assets/Logos/README.md", LOGO_README)
    for name, (group, height, body, readme) in COMPONENTS.items():
        write(f"components/{name}/preview.html", preview(group, height, body, f"{name} — preview"))
        write(f"components/{name}/README.md", readme)
    write("components/Cover/preview.html", COVER)
    bad = tokens.contrast_report()
    print("contrast:", bad or "all pass")
    print("components:", len(COMPONENTS), "icons:", len(ICONS))


if __name__ == "__main__":
    main()
