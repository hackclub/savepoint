# HoursMeter

The leaning HP bar that shows hours toward the chosen goal. It fills mint to lime for approved hours, then gold stripes for hours
still in review, and ends at a gold star: the goal.

Set `--approved` and `--pending` as percentages of the goal's hours on `sp-meter`. Add an `sp-meter__tick` with `--at` for each
cheaper prize on the way. The foot line carries the daily pace: (goal hours − hours logged) ÷ days left, to one decimal,
phrased as "1.1 hrs a day gets you there". Give the bar `role="meter"` with min, max and now, and an `aria-label` naming the goal.
