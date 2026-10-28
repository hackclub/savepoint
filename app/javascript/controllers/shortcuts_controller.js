import { Controller } from "@hotwired/stimulus"

// Single-key shortcuts for the review page (D-063). An element with data-shortcut="x" is clicked (or focused, for a
// field) when x is pressed outside a text field. data-shortcut-confirm needs two presses within 1.5 s, for the verdicts
// that end a stage. A verdict picker (data-shortcut-submit, D-106) works the other way: the first press picks it, and while
// it is picked (aria-pressed) another press clicks the submit button its selector names. Ctrl+Enter works inside text fields too.
export default class extends Controller {
  connect() {
    this.onKey = this.onKey.bind(this)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    this.disarm()
  }

  onKey(event) {
    if (event.metaKey || event.altKey) return
    const typing = event.target.closest("input, textarea, select")
    let key = event.key.toLowerCase()
    if (event.ctrlKey && key === "enter") key = "ctrl+enter"
    else if (typing || event.ctrlKey) return

    const target = this.element.querySelector(`[data-shortcut="${CSS.escape(key)}"]`)
    if (!target || target.disabled) return
    event.preventDefault()

    if (target.matches("input, textarea, select")) return target.closest("[hidden]") ? undefined : target.focus()
    if (target.dataset.shortcutSubmit && target.getAttribute("aria-pressed") === "true") {
      const submit = document.querySelector(target.dataset.shortcutSubmit)
      return submit && !submit.hidden ? submit.click() : undefined
    }
    if ("shortcutConfirm" in target.dataset && this.armed !== target) return this.arm(target)

    this.disarm()
    target.click()
  }

  arm(target) {
    this.disarm()
    this.armed = target
    target.classList.add("is-armed")
    this.armTimer = setTimeout(() => this.disarm(), 1500)
  }

  disarm() {
    if (this.armed) this.armed.classList.remove("is-armed")
    this.armed = null
    clearTimeout(this.armTimer)
  }
}
