import { Controller } from "@hotwired/stimulus"

// The stats page's chart tooltips: hovering or focusing anything with data-tooltip shows its text just above it.
// Every value is on the page without it too (labels and tables); this is for reading a column at a glance.
export default class extends Controller {
  static targets = ["tip"]

  show({ target }) {
    const mark = target.closest?.("[data-tooltip]")
    if (!mark || !this.element.contains(mark)) return
    this.tipTarget.textContent = mark.dataset.tooltip
    this.tipTarget.hidden = false
    const box = this.element.getBoundingClientRect()
    const at = mark.getBoundingClientRect()
    const tip = this.tipTarget.getBoundingClientRect()
    const left = Math.min(Math.max(at.left + at.width / 2 - tip.width / 2 - box.left, 0), box.width - tip.width)
    this.tipTarget.style.left = `${left}px`
    this.tipTarget.style.top = `${at.top - box.top - tip.height - 8}px`
  }

  hide({ target }) {
    if (target.closest?.("[data-tooltip]")) this.tipTarget.hidden = true
  }
}
