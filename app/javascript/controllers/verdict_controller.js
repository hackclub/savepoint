import { Controller } from "@hotwired/stimulus"

// The review form's four verdicts (D-106). Only the buttons show at first. Picking one reveals that verdict's fields and one
// submit button named for it, and a second press of its key submits (shortcuts_controller.js reads aria-pressed). The fields
// stay in the one form, so what was typed survives a change of mind and the server still gets every field it did before.
// D-112: the judgement and the note to the participant are in no group (they are not `fields` targets), so they show from the start
// and under every verdict, and their keys always focus them.
const SUBMIT_CLASSES = { approved: "sp-btn--mint", rejected: "ash__verdict-btn--coral", banned: "ash__verdict-btn--ban" }

export default class extends Controller {
  static targets = [ "pick", "fields", "submit" ]
  static values = { picked: String }

  connect() { this.#show() }

  pick(event) {
    this.pickedValue = event.currentTarget.dataset.verdict
    this.#show()
  }

  #show() {
    const picked = this.pickedValue
    this.pickTargets.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.verdict === picked)))
    this.fieldsTargets.forEach((group) => { group.hidden = !group.dataset.verdictFor.split(" ").includes(picked) })
    this.submitTarget.hidden = !picked
    this.submitTarget.value = picked
    this.submitTarget.querySelectorAll("[data-verdict-label]").forEach((label) => { label.hidden = label.dataset.verdictLabel !== picked })
    Object.values(SUBMIT_CLASSES).forEach((name) => this.submitTarget.classList.remove(name))
    if (SUBMIT_CLASSES[picked]) this.submitTarget.classList.add(SUBMIT_CLASSES[picked])
  }
}
