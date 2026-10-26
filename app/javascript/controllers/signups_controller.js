import { Controller } from "@hotwired/stimulus"

const EVERY = 30000

// Keeps the landing page's sign-up count (in the hero button) current: asks /signups every 30 seconds, not while the tab is hidden, and
// counts up (or down) to a new number unless the person asked for less motion.
export default class extends Controller {
  static targets = [ "count", "label", "join", "fallback" ]
  static values = { url: String, count: Number }

  connect() {
    this.shown = this.countValue
    this.onVisible = () => document.hidden ? this.#stop() : this.#start()
    document.addEventListener("visibilitychange", this.onVisible)
    this.#start()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    this.#stop()
    cancelAnimationFrame(this.frame)
  }

  // Asks now, then every 30 seconds. Coming back to the tab asks again straight away.
  #start() {
    this.#stop()
    if (document.hidden) return
    this.#poll()
    this.timer = setInterval(() => this.#poll(), EVERY)
  }

  #stop() {
    clearInterval(this.timer)
    this.timer = null
  }

  async #poll() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "omit" })
      if (!response.ok) return
      const { count } = await response.json()
      if (Number.isInteger(count) && count >= 0) this.#show(count)
    } catch {
      // Offline or the server is busy: keep the number we have and try again next time.
    }
  }

  #show(count) {
    if (count === this.shown) return
    const from = this.shown
    this.shown = count
    this.joinTarget.hidden = count === 0
    this.fallbackTarget.hidden = count !== 0
    this.labelTarget.textContent = count === 1 ? "person" : "people"
    cancelAnimationFrame(this.frame)
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.countTarget.textContent = count
      return
    }
    const start = performance.now()
    const step = (now) => {
      const t = Math.min(1, (now - start) / 800)
      this.countTarget.textContent = Math.round(from + (count - from) * (1 - (1 - t) ** 3))
      if (t < 1) this.frame = requestAnimationFrame(step)
    }
    this.frame = requestAnimationFrame(step)
    this.countTarget.classList.remove("is-bumped")
    void this.countTarget.offsetWidth
    this.countTarget.classList.add("is-bumped")
  }
}
