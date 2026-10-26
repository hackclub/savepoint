import { Controller } from "@hotwired/stimulus"

const DAY = 864e5

// Counts down to the end, every second: days, hours, minutes and seconds in its cells (the landing page's plates),
// or "3d 04h 12m" in its short target (the dock). Says "Ended" once it has.
export default class extends Controller {
  static targets = [ "label", "part", "short" ]
  static values = { endsAt: String }

  connect() {
    this.#tick()
    this.timer = setInterval(() => this.#tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  #tick() {
    const left = Math.max(0, Date.parse(this.endsAtValue) - Date.now())
    const parts = { d: Math.floor(left / DAY), h: Math.floor(left / 36e5) % 24, m: Math.floor(left / 6e4) % 60, s: Math.floor(left / 1e3) % 60 }
    const pad = (n) => String(n).padStart(2, "0")

    this.labelTargets.forEach((label) => label.textContent = left ? "Ends in" : "Ended")
    this.partTargets.forEach((part) => part.textContent = pad(parts[part.dataset.part]))
    this.shortTargets.forEach((short) => short.textContent = left ? `${parts.d}d ${pad(parts.h)}h ${pad(parts.m)}m` : "Ended")
  }
}
