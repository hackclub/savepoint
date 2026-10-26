import { Controller } from "@hotwired/stimulus"

// Rolls the hero's last word like a scrolling list cropped to one row. The words are stacked in one column (the first
// word again at the end), and each tick moves the column up one row. On the repeated last row the column snaps back to
// row 0 with no transition, so the loop is invisible. The window's width follows the current word so the line stays
// centred. Does nothing when the person asks for reduced motion, and pauses while the tab is hidden.
export default class extends Controller {
  static targets = [ "track", "word" ]

  connect() {
    this.index = 0
    this.reduced = matchMedia("(prefers-reduced-motion: reduce)")
    this.onVisibility = () => document.hidden ? this.#stop() : this.#start()
    this.onResize = () => this.#fit()
    document.addEventListener("visibilitychange", this.onVisibility)
    addEventListener("resize", this.onResize)
    this.#fit()
    document.fonts?.ready.then(() => this.#fit())
    // Transitions start only after the first paint, so nothing moves on load.
    this.frame = requestAnimationFrame(() => requestAnimationFrame(() => this.element.classList.add("is-ready")))
    this.#start()
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
    clearTimeout(this.snapTimer)
    document.removeEventListener("visibilitychange", this.onVisibility)
    removeEventListener("resize", this.onResize)
    this.#stop()
  }

  #fit() {
    this.element.style.width = `${this.wordTargets[this.index].offsetWidth}px`
  }

  #start() {
    this.#stop()
    if (this.reduced.matches || this.wordTargets.length < 2 || document.hidden) return
    this.timer = setInterval(() => this.#next(), 2500)
  }

  #stop() {
    clearInterval(this.timer)
    this.timer = null
  }

  #next() {
    this.index += 1
    this.trackTarget.style.setProperty("--i", this.index)
    this.#fit()
    if (this.index === this.wordTargets.length - 1) this.snapTimer = setTimeout(() => this.#snap(), 560)
  }

  // On the repeated last row, jump back to row 0 in one frame, with the transition off.
  #snap() {
    this.element.classList.add("is-snapping")
    this.index = 0
    this.trackTarget.style.setProperty("--i", 0)
    void this.trackTarget.offsetWidth
    this.element.classList.remove("is-snapping")
  }
}
