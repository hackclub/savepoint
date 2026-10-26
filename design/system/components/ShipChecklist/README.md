# ShipChecklist

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
