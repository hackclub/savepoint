# BottomNav

The navy pill nav: icon over label, dashed dividers, the current page a raised gold chip. On phones it's fixed to the bottom
of the screen (add `env(safe-area-inset-bottom)` to its offset); on desktop it sits centred under the top bar.
`<nav class="sp-nav">` of `<a>` links; mark the current one `aria-current="page"`. Four or five items, one word each.
