import { Controller } from "@hotwired/stimulus"

// The review form's deflation (D-063). The coding presets fill the approved coding hours with a share of the claimed
// coding, never above the AI cap. The art presets fill the approved art hours with a share of the claimed art. Art is held
// at its percent of the total, so changing coding moves the art limit and lowers the art field when it is over. Values are
// hours, to the hundredth. On a later ship (D-097) the fields hold the new hours: the art limit is read on the earlier
// coding plus the new, less the earlier art, and the total adds the earlier approval back. The reviewer still presses a verdict, and can type any value.
// D-111: at the top coding the art limit is the figure the server works out (Ship::Limits#art_top), what is left of the most the rules
// allow, so the form's own numbers add up to that most to the hundredth.
// D-112: "Why deflated" follows the total. It shows whenever the total falls below the hours claimed (hoursClaimed, the whole project's,
// where `claimed` is the coding alone), and a reason is due only below the most the rules allow.
export default class extends Controller {
  static targets = [ "coding", "art", "artMax", "total", "hold", "why", "whyRequired", "whyOptional" ]
  static values = { claimed: Number, hoursClaimed: Number, cap: Number, artClaimed: Number, artTop: Number, artPercent: Number, earlierCoding: { type: Number, default: 0 }, earlierArt: { type: Number, default: 0 } }

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

  connect() { this.#toggleWhy() }

  changed() { this.#update() }

  #update() {
    const coding = this.#coding()
    if (!this.hasArtTarget) {
      if (this.hasTotalTarget) this.totalTarget.textContent = this.#total(coding, 0)
      this.#toggleWhy()
      return
    }
    const allowed = this.#artAllowed(coding)
    let art = Number(this.artTarget.value) || 0
    const held = art > allowed
    if (held) { art = allowed; this.artTarget.value = allowed }
    this.holdTarget.hidden = !(held || (this.artClaimedValue > this.#artHold(coding) && art >= allowed))
    if (this.hasArtMaxTarget) this.artMaxTarget.textContent = this.#artMax(coding)
    this.totalTarget.textContent = this.#total(coding, art)
    this.#toggleWhy()
  }

  // D-112: "Why deflated" shows when the hours to approve fall below the hours claimed, as the server counts it (Ship#approve_review:
  // claimed > total, a hundredth counts). That takes in the AI cut and the art hold, which the rules make on their own, and the limits'
  // own words sit beside the field. A reason is due (D-106) only below the most the rules allow: elsewhere the reviewer's words are
  // optional. An error on the field keeps it showing. This reads the fields without writing them, so it can run on connect, before
  // #update has held the art to its limit.
  #toggleWhy() {
    if (!this.hasWhyTarget) return
    const coding = this.#coding()
    let art = 0
    let below = this.#short(this.capValue, coding)
    if (this.hasArtTarget) {
      const allowed = this.#artAllowed(coding)
      art = Math.min(Number(this.artTarget.value) || 0, allowed)
      below = below || this.#short(allowed, art)
    }
    const cut = this.#short(this.hoursClaimedValue, this.#total(coding, art))
    this.whyTarget.hidden = !(cut || below || this.whyTarget.querySelector(".ash__error"))
    if (this.hasWhyRequiredTarget) this.whyRequiredTarget.hidden = !below
    if (this.hasWhyOptionalTarget) this.whyOptionalTarget.hidden = below
  }

  // The approved coding as typed, never above the AI cap.
  #coding() { return Math.min(Number(this.codingTarget.value) || 0, this.capValue) }

  // The total the submit button names: the earlier approval (a later ship, D-097) plus the coding and the art, to the hundredth.
  #total(coding, art) { return this.#round(this.earlierCodingValue + this.earlierArtValue + coding + art) }

  // The most art that counts beside this coding: the art hold, not yet rounded.
  #artHold(coding) { return Math.max((this.earlierCodingValue + coding) * this.artPercentValue / (100 - this.artPercentValue) - this.earlierArtValue, 0) }

  // The art hold as the page names it, to the hundredth.
  #artMax(coding) { return this.#round(this.#artHold(coding)) }

  // The art that counts beside this coding. At the top coding it is the server's figure. Below it the claimed art held to the art
  // hold and rounded down, so it never passes the hold (Ship::Limits#art_top).
  #artAllowed(coding) { return coding >= this.capValue ? this.artTopValue : this.#floor(Math.min(this.artClaimedValue, this.#artHold(coding))) }

  // A figure a hundredth or more under its top is a deflation, as the server counts it (Ship::Limits#approve).
  #short(top, value) { return top - value > 0.01 - 1e-9 }

  #round(hours) { return Math.round(hours * 100) / 100 }

  // Down to the hundredth. The small addition keeps 1.53, which a float holds as 152.99999999999997 hundredths, at 1.53.
  #floor(hours) { return Math.floor(hours * 100 + 1e-6) / 100 }
}
