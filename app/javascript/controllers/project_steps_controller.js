import { Controller } from "@hotwired/stimulus"

// Opens and closes the setup steps without leaving the page. A click on a step's header fetches the page for that
// step, swaps in its rows, and animates the change: the row that closes shrinks, the row that opens grows, and its
// content is revealed as it does (the same easing as faq_controller.js). Turbo's page transition would crossfade the
// whole page instead. Anything that goes wrong falls back to a normal visit. Reduced motion swaps at once.
export default class extends Controller {
  disconnect() { this.finishAnimations() }

  async open(event) {
    const link = event.target.closest?.("a.project__step-header")
    if (!link || !this.element.contains(link) || event.defaultPrevented) return
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    if (this.loading) return
    this.loading = true
    try {
      const response = await fetch(link.href, { headers: { Accept: "text/html" }, credentials: "same-origin" })
      if (!response.ok || response.redirected) throw new Error("not a plain page")
      const doc = new DOMParser().parseFromString(await response.text(), "text/html")
      const lists = [ ...document.querySelectorAll(".project__steps") ]
      const next = doc.querySelectorAll(".project__steps")[lists.indexOf(this.element)]
      if (!next || next.children.length !== this.element.children.length) throw new Error("page changed")
      this.finishAnimations()
      this.swap(next)
      history.replaceState(history.state, "", link.href)
    } catch {
      window.Turbo ? window.Turbo.visit(link.href) : window.location.assign(link.href)
    } finally {
      this.loading = false
    }
  }

  // Saving your Hackatime projects: the form goes by fetch, then the steps, the summary line, the "Hours from" row and
  // the schedule are swapped for the saved page's, with no page load. Any other trouble falls back to a normal submit.
  async save(event) {
    const form = event.target
    if (!form.matches?.(".project__picker-form") || event.defaultPrevented) return
    event.preventDefault()
    if (this.loading) return
    this.loading = true
    try {
      const response = await fetch(form.action, { method: "POST", body: new FormData(form), headers: { Accept: "text/html" }, credentials: "same-origin" })
      if (!response.ok && response.status !== 422) throw new Error("not saved")
      const doc = new DOMParser().parseFromString(await response.text(), "text/html")
      const lists = [ ...document.querySelectorAll(".project__steps") ]
      const next = doc.querySelectorAll(".project__steps")[lists.indexOf(this.element)]
      if (!next || next.children.length !== this.element.children.length) throw new Error("page changed")
      this.finishAnimations()
      this.swapPart(".project__linked", doc)
      this.swapPart(".project__setup-summary", doc)
      this.swapPart(".project__schedule", doc)
      this.swapPart(".project__note", doc)
      this.swap(next)
      if (!doc.querySelector(".project__setup-done")) document.querySelector(".project__setup-done")?.remove()
      if (response.ok) history.replaceState(history.state, "", response.url)
    } catch {
      form.submit()
    } finally {
      this.loading = false
    }
  }

  swapPart(selector, doc) {
    const current = document.querySelector(selector)
    const fresh = doc.querySelector(selector)
    if (current && fresh) current.replaceWith(document.importNode(fresh, true))
  }

  swap(next) {
    const animate = !window.matchMedia("(prefers-reduced-motion: reduce)").matches && this.element.animate
    const focused = [ ...this.element.children ].findIndex((row) => row.contains(document.activeElement))
    const rows = [ ...this.element.children ].map((row) => ({
      body: row.querySelector(".project__step-body"),
      style: getComputedStyle(row)
    }))
    const before = rows.map((row) => ({ top: row.style.paddingTop, bottom: row.style.paddingBottom, left: row.style.paddingLeft }))
    const olds = [ ...this.element.children ]
    const news = [ ...next.children ].map((row) => document.importNode(row, true))
    olds.forEach((old, i) => old.replaceWith(news[i]))
    if (focused >= 0) news[focused].querySelector(".project__step-header")?.focus({ preventScroll: true })
    if (!animate) return

    news.forEach((row, i) => {
      const body = row.querySelector(".project__step-body")
      const oldBody = rows[i].body
      const gap = parseFloat(getComputedStyle(row).rowGap) || 0
      const padding = getComputedStyle(row)
      row.animate(
        { paddingTop: [ before[i].top, padding.paddingTop ], paddingBottom: [ before[i].bottom, padding.paddingBottom ],
          paddingLeft: [ before[i].left, padding.paddingLeft ] },
        { duration: 260, easing: "cubic-bezier(.4, 0, .2, 1)" }
      )
      if (body && !oldBody) this.grow(body, gap)
      else if (!body && oldBody) this.shrink(row, oldBody, gap)
    })
  }

  grow(body, gap) {
    const height = body.offsetHeight
    body.style.overflow = "hidden"
    const animation = body.animate(
      { height: [ "0px", `${height}px` ], marginTop: [ `${-gap}px`, "0px" ] },
      { duration: 300, easing: "cubic-bezier(.25, 1.12, .4, 1)" }
    )
    body.animate(
      { opacity: [ 0, 1 ], transform: [ "translateY(-6px)", "translateY(0)" ] },
      { duration: 240, delay: 50, easing: "cubic-bezier(.22, 1, .36, 1)", fill: "backwards" }
    )
    animation.onfinish = animation.oncancel = () => { body.style.overflow = "" }
  }

  shrink(row, oldBody, gap) {
    row.append(oldBody)
    const height = oldBody.offsetHeight
    oldBody.style.overflow = "hidden"
    oldBody.style.pointerEvents = "none"
    oldBody.setAttribute("aria-hidden", "true")
    oldBody.inert = true
    const animation = oldBody.animate(
      { height: [ `${height}px`, "0px" ], marginTop: [ "0px", `${-gap}px` ] },
      { duration: 230, easing: "cubic-bezier(.4, 0, .2, 1)", fill: "forwards" }
    )
    oldBody.animate(
      { opacity: [ 1, 0 ], transform: [ "translateY(0)", "translateY(-4px)" ] },
      { duration: 160, easing: "cubic-bezier(.22, 1, .36, 1)", fill: "forwards" }
    )
    animation.onfinish = animation.oncancel = () => oldBody.remove()
  }

  finishAnimations() {
    this.element.getAnimations({ subtree: true }).forEach((animation) => { try { animation.finish() } catch {} })
  }
}
