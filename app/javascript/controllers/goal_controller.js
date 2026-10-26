import { Controller } from "@hotwired/stimulus"

const DAY = 864e5

// The landing page's prizes. Each shows the pace a day it takes from now to the end; picking one makes it your goal
// (remembered in localStorage) and opens the claim popup with a pop. "Claim it" goes on to onboarding, and the pick
// waits in localStorage as sp-claim for it.
export default class extends Controller {
  static targets = [ "card", "pace", "dialog",
                     "claimImage", "claimName", "claimKind", "claimPace", "claimTotal", "claimDays", "claimPrice" ]
  static values = { startsAt: String, endsAt: String, sound: String, confirmSound: String }

  connect() {
    this.paceTargets.forEach((pace) => pace.innerHTML = this.#paceHtml(parseFloat(pace.dataset.hours)))
    const saved = this.#read("sp-goal")
    this.#pick(this.#card(saved) || this.cardTargets.find((card) => card.classList.contains("is-goal")) || this.cardTargets[0])
  }

  claim({ currentTarget }) {
    this.#open(currentTarget)
  }

  claimFromReel(event) {
    event.preventDefault()
    this.#open(this.#card(event.params.key))
  }

  close() {
    this.dialogTarget.close()
  }

  // A click on the backdrop lands on the dialog itself.
  closeOutside(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  remember(event) {
    if (this.current) this.#write("sp-claim", this.current.dataset.key)
    this.#confirm(event)
  }

  #open(card) {
    if (!card) return

    this.#pick(card)
    this.current = card
    this.claimImageTarget.hidden = !card.dataset.img
    if (card.dataset.img) this.claimImageTarget.src = card.dataset.img
    this.claimNameTarget.textContent = card.dataset.name
    this.claimKindTarget.textContent = card.dataset.kind
    this.claimPaceTarget.innerHTML = this.#paceHtml(parseFloat(card.dataset.hours))
    this.claimTotalTarget.textContent = card.dataset.hours
    this.claimPriceTarget.textContent = card.dataset.hours
    this.claimDaysTarget.textContent = Math.round(this.#pace(0).days)
    this.dialogTarget.showModal()
    this.#pop()
    this.#loadConfirm()
  }

  #pick(card) {
    this.cardTargets.forEach((other) => other.classList.toggle("is-goal", other === card))
    this.#write("sp-goal", card.dataset.key)
  }

  // Minutes a day, rounded up to 5, over the days left (the whole run before it starts).
  #pace(hours) {
    const from = Math.max(Date.now(), Date.parse(this.startsAtValue))
    const days = Math.max(1, (Date.parse(this.endsAtValue) - from) / DAY)
    return { minutes: Math.ceil(hours * 60 / days / 5) * 5, days }
  }

  #paceHtml(hours) {
    const { minutes } = this.#pace(hours)
    const h = Math.floor(minutes / 60), m = minutes % 60
    const parts = [ h && `${h}<small> hr</small>`, m && `${m}<small> min</small>` ].filter(Boolean)
    return `${parts.join(" ")}<small> a day</small>`
  }

  #pop() {
    this.sound ||= Object.assign(new Audio(this.soundValue), { volume: 0.6, preload: "auto" })
    this.sound.currentTime = 0
    this.sound.play()?.catch(() => {})
  }

  // Preload the confirm sound with the popup so it starts at once.
  #loadConfirm() {
    if (!this.confirmSoundValue) return null
    return this.confirmAudio ||= Object.assign(new Audio(this.confirmSoundValue), { volume: 0.6, preload: "auto" })
  }

  // Play the confirm on "Claim it" and hold the navigation ~300 ms so the attack is heard. Modifier and middle
  // clicks go through untouched; a blocked play() navigates at once.
  #confirm(event) {
    const link = event?.currentTarget, audio = this.#loadConfirm()
    if (!link || !audio || this.leaving) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button > 0) return

    event.preventDefault()
    this.leaving = true
    let gone = false
    const go = () => {
      if (gone) return
      gone = true
      this.leaving = false
      window.Turbo ? window.Turbo.visit(link.href) : window.location.href = link.href
    }
    audio.currentTime = 0
    const played = audio.play()
    if (!played?.then) return go()
    played.then(() => setTimeout(go, 300), go)
  }

  #card(key) {
    return key && this.cardTargets.find((card) => card.dataset.key === key)
  }

  #read(key) {
    try { return localStorage.getItem(key) } catch { return null }
  }

  #write(key, value) {
    try { localStorage.setItem(key, value) } catch {}
  }
}
