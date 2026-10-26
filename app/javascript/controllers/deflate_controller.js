import { Controller } from "@hotwired/stimulus"

// The review form's deflation (D-063). The coding presets fill the approved coding hours with a share of the claimed
// coding, never above the AI cap. The art presets fill the approved art hours with a share of the claimed art. Art is held
// at its percent of the total, so changing coding moves the art limit and lowers the art field when it is over. Values are
// hours, to the hundredth. The reviewer still presses a verdict, and can type any value.
export default class extends Controller {
  static targets = [ "coding", "art", "artMax", "total", "hold" ]
  static values = { claimed: Number, cap: Number, artClaimed: Number, artPercent: Number }

  setCoding(event) {
    const percent = Number(event.currentTarget.dataset.percent)
    this.codingTarget.value = Math.min(this.#round(this.claimedValue * percent / 100), this.capValue)
    this.codingTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.codingTarget.focus()
  }

  setArt(event) {
    const percent = Number(event.currentTarget.dataset.percent)
    this.artTarget.value = this.#round(this.artClaimedValue * percent / 100)
    this.artTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.artTarget.focus()
  }

  changed() { this.#update() }

  #update() {
    const coding = Math.min(Number(this.codingTarget.value) || 0, this.capValue)
    if (!this.hasArtTarget) {
      if (this.hasTotalTarget) this.totalTarget.textContent = this.#round(coding)
      return
    }
    const artMax = this.#round(coding * this.artPercentValue / (100 - this.artPercentValue))
    const allowed = Math.min(this.artClaimedValue, artMax)
    let art = Number(this.artTarget.value) || 0
    const held = art > allowed
    if (held) { art = allowed; this.artTarget.value = allowed }
    this.holdTarget.hidden = !(held || (this.artClaimedValue > artMax && art >= allowed))
    if (this.hasArtMaxTarget) this.artMaxTarget.textContent = artMax
    this.totalTarget.textContent = this.#round(coding + art)
  }

  #round(hours) { return Math.round(hours * 100) / 100 }
}
