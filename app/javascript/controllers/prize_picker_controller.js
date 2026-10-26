import { Controller } from "@hotwired/stimulus"
import { chime } from "controllers/goal_chime"

// "Change your prize" on the project page. Pressing it fetches the row of prize tags and grows it open, and pressing it
// again (or a tag) collapses it, with the same heights and easing as the setup steps (project_steps_controller.js) and
// the FAQ. A tag is a form button: picking one sends that form as it is, closes the row, then reloads the page in place
// (no page transition, page_slide_controller.js) so the summary shows the new prize. Without JavaScript, or when
// anything fails, the link and the forms work as plain pages. Reduced motion skips the animation.
export default class extends Controller {
  static targets = [ "picker", "track", "mine" ]

  connect() { this.center() }

  pickerTargetConnected() { this.center() }

  async toggle(event) {
    const link = event.target.closest?.(".project__change-tool")
    if (!link || !this.element.contains(link) || event.defaultPrevented) return
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    if (this.busy) return
    this.busy = true
    try {
      if (this.hasPickerTarget) await this.close(link)
      else await this.open(link)
    } catch {
      window.Turbo ? window.Turbo.visit(link.href) : window.location.assign(link.href)
    } finally {
      this.busy = false
    }
  }

  async open(link) {
    const response = await fetch(link.href, { headers: { Accept: "text/html" }, credentials: "same-origin" })
    if (!response.ok || response.redirected) throw new Error("not a plain page")
    const doc = new DOMParser().parseFromString(await response.text(), "text/html")
    const picker = doc.querySelector(".project__prize-picker")
    if (!picker) throw new Error("no picker")
    const node = document.importNode(picker, true)
    this.element.querySelector(".project__header-links").after(node)
    this.mark(link, true)
    this.center()
    history.replaceState(history.state, "", link.href)
    await this.grow(node)
  }

  async close(link) {
    this.mark(link, false)
    history.replaceState(history.state, "", link.href)
    await this.shrink(this.pickerTarget)
  }

  // A tag was pressed: it turns gold at once (the old one fades back) with a pop and a chime, while its form goes out by
  // fetch, so the row can collapse and the page then reload in place. If the request fails the old tag comes back and the
  // plain form is sent, so the page can say why.
  async pick(event) {
    const form = event.target
    if (!form.matches?.(".project__prize-option") || !this.hasPickerTarget) return
    event.preventDefault()
    if (this.busy) return
    const link = this.element.querySelector(".project__change-tool")
    const button = form.querySelector("button"), old = this.pickerTarget.querySelector("button.is-goal")
    this.busy = true
    this.choose(button, old)
    try {
      const sent = fetch(form.action, { method: "POST", body: new FormData(form), headers: { Accept: "application/json" }, credentials: "same-origin" })
      sent.catch(() => {})
      if (!this.reduced) await new Promise((resolve) => setTimeout(resolve, 260)) // the pop first
      const done = this.shrink(this.pickerTarget)
      const response = await sent
      if (!response.ok) throw new Error("not saved")
      await done
      this.mark(link, false)
      window.Turbo.visit(link.pathname, { action: "replace" })
    } catch {
      if (old) this.choose(old, button, false)
      form.submit()
    }
  }

  // The chosen tag is the gold one now (its aria-pressed too); with motion it pops, and a short chime plays.
  choose(button, old, cheer = true) {
    old?.classList.remove("is-goal")
    old?.setAttribute("aria-pressed", "false")
    button.classList.add("is-goal")
    button.setAttribute("aria-pressed", "true")
    if (!cheer || this.reduced) return
    button.animate([ { transform: "scale(.94)" }, { transform: "scale(1.08) rotate(-2deg)", offset: .5 }, { transform: "none" } ], { duration: 380, easing: "cubic-bezier(.3, 1.6, .5, 1)" })
    chime()
  }

  mark(link, open) {
    link.setAttribute("aria-expanded", open)
    const url = new URL(link.href)
    if (open) url.searchParams.delete("edit"); else url.searchParams.set("edit", "prize")
    link.href = url.pathname + url.search
  }

  // The prize that is yours scrolls to the middle of the row.
  center() {
    if (!this.hasTrackTarget || !this.hasMineTarget) return
    const track = this.trackTarget
    const item = this.mineTarget.closest(".project__prize-option")
    track.scrollLeft = item.offsetLeft - (track.clientWidth - item.offsetWidth) / 2
  }

  get reduced() { return window.matchMedia("(prefers-reduced-motion: reduce)").matches || !this.element.animate }

  // The row gap of the grid the picker sits in (its parent can be display: contents, which has none).
  rowGap(node) {
    return parseFloat(getComputedStyle(node.closest(".project__header") || node.parentElement).rowGap) || 0
  }

  grow(node) {
    if (this.reduced) return
    const gap = this.rowGap(node)
    const height = node.offsetHeight
    node.style.overflow = "hidden"
    const animation = node.animate(
      { height: [ "0px", `${height}px` ], marginTop: [ `${-gap}px`, "0px" ] },
      { duration: 300, easing: "cubic-bezier(.25, 1.12, .4, 1)" }
    )
    node.animate(
      { opacity: [ 0, 1 ], transform: [ "translateY(-6px)", "translateY(0)" ] },
      { duration: 240, delay: 50, easing: "cubic-bezier(.22, 1, .36, 1)", fill: "backwards" }
    )
    return animation.finished.catch(() => {}).then(() => { node.style.overflow = "" })
  }

  shrink(node) {
    if (this.reduced) { node.remove(); return Promise.resolve() }
    const gap = this.rowGap(node)
    const height = node.offsetHeight
    node.style.overflow = "hidden"
    node.inert = true
    const animation = node.animate(
      { height: [ `${height}px`, "0px" ], marginTop: [ "0px", `${-gap}px` ] },
      { duration: 230, easing: "cubic-bezier(.4, 0, .2, 1)", fill: "forwards" }
    )
    node.animate(
      { opacity: [ 1, 0 ], transform: [ "translateY(0)", "translateY(-4px)" ] },
      { duration: 160, easing: "cubic-bezier(.22, 1, .36, 1)", fill: "forwards" }
    )
    return animation.finished.catch(() => {}).then(() => node.remove())
  }
}
