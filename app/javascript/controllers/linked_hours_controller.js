import { Controller } from "@hotwired/stimulus"

// The "Hours from" row's Change button: opens the Hackatime tick list right under the row and closes it again ("Done"), with the
// height and fade the sidebar sections use (side_sections_controller.js). Reduced motion toggles at once. The button is a real
// link (to the page with the list open), so without JS it still works.
export default class extends Controller {
  static targets = [ "button", "panel", "label" ]
  static values = { open: Boolean }

  toggle(event) {
    event.preventDefault()
    this.run(this.panelTarget.hidden)
  }

  run(opening) {
    const panel = this.panelTarget
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches || !panel.animate
    this.animation?.cancel()
    this.buttonTarget.setAttribute("aria-expanded", String(opening))
    this.labelTarget.textContent = opening ? "Done" : (this.element.querySelector(".project__linked-list") ? "Change" : "Pick")
    if (reduced) { panel.hidden = !opening; return }

    const start = panel.hidden ? 0 : panel.offsetHeight
    panel.hidden = false
    const end = opening ? panel.scrollHeight : 0
    panel.style.overflow = "hidden"
    this.animation = panel.animate(
      [ { height: `${start}px`, opacity: opening ? 0 : 1 }, { height: `${end}px`, opacity: opening ? 1 : 0 } ],
      { duration: opening ? 300 : 230, easing: opening ? "cubic-bezier(.25, 1.12, .4, 1)" : "cubic-bezier(.4, 0, .2, 1)" }
    )
    const animation = this.animation
    animation.onfinish = () => {
      if (this.animation !== animation) return
      panel.style.overflow = ""
      if (!opening) panel.hidden = true
      this.animation = null
    }
  }
}
