# TextField

A label, a sunken well, and an optional help line. Wrap them in `<label class="sp-field">`; the input is `sp-input` (also on `<textarea>`).

- The label is `sp-label`: short, set in uppercase by CSS. Write it in sentence case in the markup.
- The help line is `sp-help`, under the field, with an `information-fill` icon. Say what's expected, not what's forbidden.
- On error, add `sp-field--error` to the wrapper and swap the help icon to `warning-fill`. The message says what to do:
  "Tell us a bit more: at least 40 characters." Show a live count (`sp-count`) for fields with a minimum.
- Focus lifts the well to `surface` with a royal halo.
