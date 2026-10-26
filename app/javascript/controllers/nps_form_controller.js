import { Controller } from "@hotwired/stimulus"

// The NPS questions. The send button of the form around them stays off until a score is picked and each required
// answer holds more than spaces, and the hint says so meanwhile. The server checks again.
export default class extends Controller {
  static targets = [ "hint" ]

  connect() {
    this.check()
  }

  check() {
    const form = this.element.closest("form")
    if (!form) return
    const scored = !!this.element.querySelector("input[type=radio]:checked")
    const answered = [ ...this.element.querySelectorAll("textarea[required]") ].every((field) => field.value.trim() !== "")
    const ready = scored && answered
    form.querySelectorAll("button[type=submit]").forEach((button) => { button.disabled = !ready })
    this.hintTargets.forEach((hint) => { hint.hidden = ready })
  }
}
