import { Controller } from "@hotwired/stimulus"

// Keeps this admin's claim on a ship alive while its review page is open (Admin::ClaimsController#heartbeat). If another
// admin has taken the ship over, the banner shows who instead of letting this one keep typing into a lost claim.
export default class extends Controller {
  static values = { url: String, id: Number, stage: String, interval: { type: Number, default: 30000 } }
  static targets = [ "banner", "holder" ]

  connect() {
    this.timer = setInterval(() => this.beat(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async beat() {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const body = new URLSearchParams({ id: this.idValue, stage: this.stageValue })
    const response = await fetch(this.urlValue, { method: "POST", body, headers: { "X-CSRF-Token": token, Accept: "application/json" } })
    if (!response.ok) return

    const claim = await response.json()
    if (!claim.ok && this.hasBannerTarget) {
      this.bannerTarget.hidden = false
      if (this.hasHolderTarget) this.holderTarget.textContent = claim.holder
    }
  }
}
