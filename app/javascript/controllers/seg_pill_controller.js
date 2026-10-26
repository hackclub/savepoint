import { Controller } from "@hotwired/stimulus"

// The gold pill of a segmented choice (radios inside labels), sliding to the option you pick. The pill is one element
// laid under the options; this moves it to the checked option's box. The first placement and any resize jump there
// with no slide (the transition only runs once data-ready is set). Reduced motion: it always jumps.
// For choices that load a page (links), see transitions.css instead: the pill glides inside a view transition.
export default class extends Controller {
  static targets = [ "pill" ]
  static values = { option: String }

  connect() {
    this.place = () => this.#place()
    this.observer = new ResizeObserver(() => this.#place({ jump: true }))
    this.observer.observe(this.element)
    this.element.addEventListener("change", this.place)
    // Whoever restored a remembered choice (focus_controller.js) did it without a change event: look again next frame.
    requestAnimationFrame(() => {
      this.#place({ jump: true })
      this.element.dataset.ready = ""
    })
  }

  disconnect() {
    this.observer.disconnect()
    this.element.removeEventListener("change", this.place)
    delete this.element.dataset.ready
  }

  #place({ jump = false } = {}) {
    const checked = this.element.querySelector(":checked")
    const option = checked?.closest(this.optionValue)
    this.pillTarget.hidden = !option
    if (!option) return
    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches
    const style = this.pillTarget.style
    if (jump || reduced) style.transition = "none"
    style.inlineSize = `${option.offsetWidth}px`
    style.blockSize = `${option.offsetHeight}px`
    style.transform = `translate(${option.offsetLeft}px, ${option.offsetTop}px)`
    if (jump || reduced) {
      void this.pillTarget.offsetWidth
      style.transition = ""
    }
  }
}
