import { Controller } from "@hotwired/stimulus"
import { chime } from "controllers/goal_chime"

// A prize's sheet on /shop. Pressing its tag opens the dialog with the details. A ready prize's Claim button opens it at
// the claim step instead, and "Claim it" in the details goes to that step too. Going back, closing, or a click on the
// backdrop (which lands on the dialog itself) returns it to the details for next time. Without JavaScript the Claim
// button posts the claim as it is.
// Sounds, as on the landing page's claim popup: claim.mp3 as a sheet opens, confirm.mp3 on "Claim it" and on "Set as my
// goal". They are loaded when the shop is, never played then, and played with the browser's say-so: a refusal is silence.
// "Set as my goal" does not wait for the server (setGoal): the button turns into "Your goal" at once, the art bounces, stars
// burst from it, and the sheet closes while its card glides to the first place in the grid (a FLIP). The request goes by
// fetch meanwhile, and if it fails everything goes back and the sheet opens with the error. Reduced motion skips all
// movement, and without JavaScript the button posts the form as it is.
// A claim form is held for 300 ms once its confirm sound starts, so the reload doesn't cut it. No hold with
// reduced motion, or when the browser refuses to play.
const audios = new Map()
const load = (url) => url ? audios.get(url) || audios.set(url, Object.assign(new Audio(url), { volume: 0.6, preload: "auto" })).get(url) : null
const play = (audio) => {
  if (!audio) return
  audio.currentTime = 0
  audio.play()?.catch(() => {})
}

const SPRING = "cubic-bezier(.3, 1.6, .5, 1)" // the sheet's own pop
const GLIDE = "cubic-bezier(.25, 1.12, .4, 1)" // the project page's row growing open
const reduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches || !Element.prototype.animate
const SPARKS = [ "var(--gold-hi)", "var(--gold)", "#fff", "var(--royal-hi)" ]

export default class extends Controller {
  static targets = [ "dialog", "details", "claim", "done", "badge", "go", "name", "confirm", "error", "claimError" ]
  static values = { openSound: String, confirmSound: String, start: { type: String, default: "details" }, autoOpen: Boolean }

  // start: "claim" is a sheet with no details step (the free stickers): it opens, and goes back to, the claim step.
  connect() {
    load(this.openSoundValue)
    load(this.confirmSoundValue)
    if (this.autoOpenValue) this.#autoOpen()
  }

  // The project page's link (/shop?claim=stickers) opens the sheet on its form as the shop loads. The parameter leaves the
  // address, so a reload after the claim doesn't open it again.
  #autoOpen() {
    const url = new URL(window.location.href)
    if (url.searchParams.has("claim")) {
      url.searchParams.delete("claim")
      window.history.replaceState(window.history.state, "", url.pathname + url.search + url.hash)
    }
    this.claim()
  }

  open() {
    if (this.startValue === "claim") return this.claim()
    this.#show("details")
    this.dialogTarget.showModal()
    play(load(this.openSoundValue))
  }

  // The Claim button on the tag: its form would claim at once, so open the claim step instead.
  claim(event) {
    event?.preventDefault()
    if (!this.hasClaimTarget) return this.open()

    this.#show("claim")
    if (!this.dialogTarget.open) {
      this.dialogTarget.showModal()
      play(load(this.openSoundValue))
    }
    this.nameTarget.focus({ preventScroll: true })
    this.nameTarget.select()
  }

  // The claim step's first button. A sheet that starts on the claim step has nothing behind it, so there it closes.
  back() {
    if (this.startValue === "claim") return this.close()
    this.#show("details")
  }

  close() {
    this.dialogTarget.close()
  }

  closeOutside(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  reset() {
    this.#show(this.startValue)
  }

  // The claim: sent by fetch, so what they typed stays put when a field is wrong. Each problem comes back by field and is
  // written under it; a good answer plays the confirm sound and goes on to the shop. Once is enough: a second press would
  // claim it twice. (Without fetch the form posts as it is and the shop says the first problem.)
  submitted(event) {
    if (!window.fetch) { this.confirmTarget.disabled = true; return this.confirmed(event) }

    event.preventDefault()
    if (this.claiming) return
    const form = event.target
    this.claiming = true
    this.confirmTarget.disabled = true
    this.#problems({})
    fetch(form.action, { method: "POST", body: new FormData(form), headers: { Accept: "application/json" }, credentials: "same-origin" })
      .then(async (response) => {
        const body = await response.json().catch(() => ({}))
        if (response.ok && body.redirect) return this.#claimed(body.redirect)

        this.claiming = false
        this.confirmTarget.disabled = false
        this.#problems(body.fields || {}, body.message || "Couldn't claim it. Try again.")
      })
      .catch(() => {
        this.claiming = false
        this.confirmTarget.disabled = false
        this.#problems({}, "Couldn't claim it. Try again.")
      })
  }

  // The claim went through: the sheet turns into "Claimed!" (sound, chime, a hop and stars unless reduced motion), stays long
  // enough to read, then goes on to the shop, where the card is marked. "See it in the shop" goes at once.
  #claimed(url) {
    play(load(this.confirmSoundValue))
    if (!this.hasDoneTarget) return setTimeout(() => { window.location.href = url }, 300)

    this.goTarget.href = url
    this.#show("done")
    this.goTarget.focus({ preventScroll: true })
    const motion = !reduced()
    if (motion) this.#celebrate()
    setTimeout(() => { window.location.href = url }, motion ? 1500 : 900)
  }

  // The badge pops in, the picture hops, and stars burst from the badge. The chime is the goal's, three rising notes.
  #celebrate() {
    chime()
    this.badgeTarget.animate([ { transform: "scale(.4) rotate(-20deg)", opacity: 0 }, { transform: "scale(1.2) rotate(6deg)", opacity: 1, offset: .55 }, { transform: "none", opacity: 1 } ], { duration: 460, easing: SPRING })
    this.element.querySelector(".order-sheet__art img")?.animate(
      [ { transform: "none" }, { transform: "translateY(-26px) scale(.96, 1.06)", offset: .32 }, { transform: "translateY(0) scale(1.07, .92)", offset: .6 }, { transform: "translateY(-8px)", offset: .8 }, { transform: "none" } ],
      { duration: 520, easing: "cubic-bezier(.22, 1, .36, 1)" }
    )
    this.#burst(this.badgeTarget)
  }

  // Each wrong field's words under it, its box red, and the cursor in the first one. A problem with no field of its own
  // (a prize you've bought already) goes under the form.
  #problems(fields, message = "") {
    this.claimTarget.querySelectorAll("[data-field]").forEach((box) => {
      const text = fields[box.dataset.field]
      box.classList.toggle("sp-field--error", !!text)
      const line = box.querySelector("[data-problem]")
      line.textContent = text || ""
      line.hidden = !text
      if (text) box.querySelector("input")?.setAttribute("aria-invalid", "true")
      else box.querySelector("input")?.removeAttribute("aria-invalid")
    })
    if (this.hasClaimErrorTarget) {
      this.claimErrorTarget.textContent = Object.keys(fields).length ? "" : message
      this.claimErrorTarget.hidden = Object.keys(fields).length > 0 || !message
    }
    const first = Object.keys(fields).map((key) => this.claimTarget.querySelector(`[data-field="${key}"] input`)).find(Boolean)
    first?.focus({ preventScroll: false })
  }

  // "Set as my goal": the answer is drawn first, then the request goes by fetch. Sheets and cards are each their own controller,
  // so this one reaches the others through the grid.
  setGoal(event) {
    event.preventDefault()
    if (this.pending || !window.fetch) return event.target.submit()

    const form = event.target, grid = this.element.closest(".shop__grid")
    const before = { goal: grid.querySelector(".shop-prize--goal")?.id, order: [ ...grid.children ] }
    const motion = !reduced()
    this.pending = true
    this.#fail("")
    this.#mark(grid, this.element.id)
    play(load(this.confirmSoundValue))
    if (motion) { chime(); this.#cheer() }

    const sent = fetch(form.action, { method: "POST", body: new FormData(form), headers: { Accept: "application/json" }, credentials: "same-origin" })
      .then((response) => { if (!response.ok) throw new Error("not saved") })
    const settled = new Promise((resolve) => { this.glide = setTimeout(resolve, motion ? 450 : 0) })
    let failed = false
    sent.catch(() => { failed = true; clearTimeout(this.glide); this.glide = null })

    // The sheet gives the celebration its moment, closes, and its card glides to the front.
    settled.then(() => {
      if (failed) return
      if (this.dialogTarget.open) this.dialogTarget.close()
      this.#reorder(grid, this.#goalFirst(grid), motion)
    })
    sent.then(() => { this.pending = false }, () => {
      this.pending = false
      this.#mark(grid, before.goal)
      this.#reorder(grid, before.order, !reduced())
      this.#fail("Couldn't save your goal. Try again.")
      if (!this.dialogTarget.open) this.dialogTarget.showModal()
    })
  }

  // "Set as my goal", or the claim, was sent: its sound, then the form goes on.
  confirmed(event) {
    const form = event?.target, audio = load(this.confirmSoundValue)
    if (!form?.submit || !audio || this.leaving || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return play(audio)

    event.preventDefault()
    this.leaving = true
    let gone = false
    const go = () => {
      if (gone) return
      gone = true
      form.submit()
    }
    audio.currentTime = 0
    const played = audio.play()
    if (!played?.then) return go()
    played.then(() => setTimeout(go, 300), go)
  }

  // Every prize in the grid, drawn as the goal (the key's) or not: its tag's gold, and its sheet's button or "Your goal".
  #mark(grid, id) {
    for (const item of grid.children) {
      const goal = item.id === id
      item.classList.toggle("shop-prize--goal", goal)
      item.querySelector(":scope > .shop-card")?.classList.toggle("is-goal", goal)
      const status = item.querySelector("[data-goal-status]"), form = item.querySelector("[data-goal-form]")
      if (status) status.hidden = !goal
      if (form) form.hidden = goal
    }
  }

  // Your goal first, the rest in their own order.
  #goalFirst(grid) {
    return [ ...grid.children ].sort((a, b) => (b.classList.contains("shop-prize--goal") - a.classList.contains("shop-prize--goal")) || a.dataset.rank - b.dataset.rank)
  }

  // Moves the tags into this order and, with motion, slides each from where it was to where it is (FLIP).
  #reorder(grid, order, motion) {
    const first = new Map(order.map((item) => [ item, item.getBoundingClientRect() ]))
    grid.append(...order)
    if (!motion) return
    order.forEach((item) => {
      const was = first.get(item), now = item.getBoundingClientRect()
      const dx = was.left - now.left, dy = was.top - now.top
      if (!dx && !dy) return
      const goal = item.classList.contains("shop-prize--goal")
      item.animate([ { transform: `translate(${dx}px, ${dy}px)`, zIndex: goal ? 2 : 1 }, { transform: "none", zIndex: goal ? 2 : 1 } ], { duration: 420, easing: GLIDE })
    })
    const goal = grid.querySelector(".shop-prize--goal")
    if (goal && goal.getBoundingClientRect().top < 0) goal.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  // The "Your goal" pill pops in where the button was, its flag waves, stars burst from it, and the picture hops.
  #cheer() {
    const status = this.element.querySelector("[data-goal-status]")
    if (!status) return
    status.animate([ { transform: "scale(.5)", opacity: 0 }, { transform: "scale(1.18)", opacity: 1, offset: .55 }, { transform: "scale(1)", opacity: 1 } ], { duration: 380, easing: SPRING })
    status.querySelector(".sp-icon")?.animate(
      [ { transform: "rotate(-30deg)" }, { transform: "rotate(22deg)", offset: .35 }, { transform: "rotate(-12deg)", offset: .65 }, { transform: "rotate(0)" } ],
      { duration: 520, delay: 120, easing: "ease-out", fill: "backwards" }
    )
    this.element.querySelector(".order-sheet__art img")?.animate(
      [ { transform: "none" }, { transform: "translateY(-26px) scale(.96, 1.06)", offset: .32 }, { transform: "translateY(0) scale(1.07, .92)", offset: .6 }, { transform: "translateY(-8px)", offset: .8 }, { transform: "none" } ],
      { duration: 520, easing: "cubic-bezier(.22, 1, .36, 1)" }
    )
    this.#burst(status)
  }

  #burst(origin) {
    const card = this.element.querySelector(".order-sheet__card"), c = card.getBoundingClientRect(), o = origin.getBoundingClientRect()
    const x = o.left + o.width / 2 - c.left - 3, y = o.top + o.height / 2 - c.top - 3 // the card has a 3px border
    for (let i = 0; i < 12; i++) {
      const spark = document.createElement("span")
      spark.className = "order-sheet__spark"
      spark.setAttribute("aria-hidden", "true")
      spark.style.cssText = `left: ${x}px; top: ${y}px; background: ${SPARKS[i % SPARKS.length]}; width: ${i % 3 ? 12 : 17}px; height: ${i % 3 ? 12 : 17}px;`
      card.append(spark)
      const angle = (i / 12) * Math.PI * 2 + Math.random() * 0.4, reach = 60 + Math.random() * 46, spin = i % 2 ? 1 : -1
      const at = (k, drop = 0) => `translate(calc(-50% + ${Math.cos(angle) * reach * k}px), calc(-50% + ${Math.sin(angle) * reach * k + drop}px))`
      // Out fast (the sheet's own easing), a moment hanging there, then a short fall as it shrinks away.
      spark.animate(
        [ { transform: `${at(0)} scale(.3) rotate(0)`, opacity: 1, easing: "cubic-bezier(.22, 1, .36, 1)" },
          { transform: `${at(1, -12)} scale(1) rotate(${spin * 120}deg)`, opacity: 1, offset: .55, easing: "ease-in" },
          { transform: `${at(1.1, 14)} scale(0) rotate(${spin * 200}deg)`, opacity: 0 } ],
        { duration: 600 }
      ).finished.catch(() => {}).then(() => spark.remove())
    }
  }

  #fail(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = !message
  }

  #show(step) {
    if (this.hasDetailsTarget) this.detailsTarget.hidden = step !== "details"
    if (this.hasClaimTarget) this.claimTarget.hidden = step !== "claim"
    if (this.hasDoneTarget) this.doneTarget.hidden = step !== "done"
  }
}
