import { Controller } from "@hotwired/stimulus"

// The admin ship page's screenshot editor (admin/ships/_snapshot_edit), after playground's. Each change saves at once to
// Admin::ShipScreenshotsController, which answers JSON. The first screenshot is the cover. Files chosen from the add button
// upload one after another, each in its own cell with a progress bar. A screenshot moves by drag or by the arrow keys, and
// the order saves after each move. A click or Enter on one replaces it, and its x or Delete removes it. The server checks
// every file again.
export default class extends Controller {
  static targets = ["list", "add", "template", "input", "status"]
  static values = { url: String, orderUrl: String, max: Number, types: String, maxBytes: Number }

  connect() {
    this.queue = Promise.resolve()
    this.errors = []
    this.relabel()
  }

  get thumbs() { return [...this.listTarget.children] }
  get settled() { return this.thumbs.filter((thumb) => !thumb.classList.contains("is-pending")) }
  get full() { return this.thumbs.length >= this.maxValue }

  // Adding, from the add button.
  pick() {
    if (this.full) return
    this.replacing = null
    this.inputTarget.click()
  }

  chosen() {
    const files = [...this.inputTarget.files]
    this.inputTarget.value = ""
    const thumb = this.replacing
    this.replacing = null
    this.take(files, thumb)
  }

  // Replacing one, by a click on it.
  pickFor(event) {
    const thumb = event.currentTarget
    if (this.dragged || event.target.closest(".ash__thumb-remove") || thumb.classList.contains("is-pending")) return
    this.replacing = thumb
    this.inputTarget.click()
  }

  // The first file replaces the screenshot given, if any, and the rest go on the end. One past the room there is
  // waits its turn, when a file ahead of it may have failed and left room.
  take(files, replacing = null) {
    if (!files.length) return
    this.errors = []
    this.say("")
    if (replacing) this.enqueue(files.shift(), replacing, replacing.dataset.id)
    for (const file of files) {
      this.queue = this.queue.then(() => {
        if (this.full) return this.fail(file, `A ship holds up to ${this.maxValue} screenshots. Remove one to add another.`)
        const thumb = this.newThumb()
        thumb.classList.add("is-busy")
        return this.upload(file, thumb, null)
      })
    }
  }

  newThumb() {
    const thumb = this.templateTarget.content.firstElementChild.cloneNode(true)
    thumb.classList.add("is-pending")
    this.listTarget.append(thumb)
    this.state(thumb, "Waiting")
    this.relabel()
    return thumb
  }

  enqueue(file, thumb, replace) {
    thumb.classList.add("is-busy")
    this.queue = this.queue.then(() => this.upload(file, thumb, replace))
  }

  async upload(file, thumb, replace) {
    const image = thumb.querySelector("img")
    const before = image.getAttribute("src")
    let preview
    try {
      this.check(file)
      preview = URL.createObjectURL(file)
      image.src = preview
      const body = await this.send(file, thumb, replace)
      image.src = body.url
      thumb.dataset.id = body.id
      this.settle(thumb)
      if (!this.errors.length) this.say("Uploaded.")
    } catch (error) {
      this.fail(file, error.message)
      // Nothing was saved: a replaced screenshot comes back, a new one goes.
      if (replace) {
        if (before) image.src = before
        this.settle(thumb)
      } else {
        thumb.remove()
      }
    } finally {
      if (preview) URL.revokeObjectURL(preview)
      this.relabel()
    }
  }

  check(file) {
    if (!this.typesValue.split(",").includes(file.type)) throw new Error("Use a PNG, JPEG or WebP screenshot, not a GIF.")
    if (file.size > this.maxBytesValue) throw new Error(`Use a screenshot under ${Math.round(this.maxBytesValue / 1048576)} MB.`)
  }

  send(file, thumb, replace) {
    return new Promise((resolve, reject) => {
      const form = new FormData()
      form.append("screenshot", file, file.name)
      if (replace) form.append("replace", replace)
      const xhr = new XMLHttpRequest()
      xhr.open("POST", this.urlValue)
      const token = document.querySelector("meta[name=csrf-token]")?.content
      if (token) xhr.setRequestHeader("X-CSRF-Token", token)
      xhr.setRequestHeader("Accept", "application/json")
      xhr.upload.onprogress = (e) => { if (e.lengthComputable) this.progress(thumb, e.loaded / e.total) }
      xhr.onload = () => {
        let body = {}
        try { body = JSON.parse(xhr.responseText) } catch {}
        if (xhr.status === 201) resolve(body)
        else reject(new Error(body.error || `The upload failed (${xhr.status}).`))
      }
      xhr.onerror = () => reject(new Error("The upload failed. Check your connection."))
      this.state(thumb, "Uploading")
      xhr.send(form)
    })
  }

  async remove(event) {
    event.stopPropagation()
    const thumb = event.currentTarget.closest(".ash__thumb")
    if (thumb.classList.contains("is-busy") || !thumb.dataset.id) return
    thumb.classList.add("is-busy")
    try {
      const response = await this.request("DELETE", `${this.urlValue}/${encodeURIComponent(thumb.dataset.id)}`)
      if (!response.ok && response.status !== 404) throw new Error(await this.problem(response, "Removing it failed."))
      const next = thumb.nextElementSibling || thumb.previousElementSibling
      thumb.remove()
      ;(next || this.addTarget).focus()
      this.say("Removed.")
    } catch (error) {
      thumb.classList.remove("is-busy")
      this.say(error.message, true)
    }
    this.relabel()
  }

  // Keys on a focused screenshot. The remove button's keys are its own.
  key(event) {
    const thumb = event.currentTarget
    if (event.target !== thumb || thumb.classList.contains("is-pending")) return
    const step = { ArrowLeft: -1, ArrowUp: -1, ArrowRight: 1, ArrowDown: 1 }[event.key]
    if (step) {
      event.preventDefault()
      this.move(thumb, step)
    } else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.replacing = thumb
      this.inputTarget.click()
    } else if (event.key === "Delete" || event.key === "Backspace") {
      event.preventDefault()
      thumb.querySelector(".ash__thumb-remove").click()
    }
  }

  move(thumb, step) {
    const settled = this.settled
    const to = settled.indexOf(thumb) + step
    if (to < 0 || to >= settled.length) return
    if (step < 0) settled[to].before(thumb)
    else settled[to].after(thumb)
    thumb.focus()
    this.relabel()
    this.say(`Moved to ${to + 1} of ${settled.length}.`)
    this.saveOrder()
  }

  // A drag by mouse, pen or finger moves a screenshot among the others. A press that barely moves is a click, which
  // replaces it. The document follows the pointer, because a pointer capture would end as the cell moves in the page.
  grab(event) {
    const thumb = event.currentTarget
    if (!event.isPrimary || event.button !== 0 || event.target.closest(".ash__thumb-remove") || thumb.classList.contains("is-pending")) return
    const start = { x: event.clientX, y: event.clientY }
    const order = this.settled.map((t) => t.dataset.id).join()
    this.dragged = false
    const move = (e) => {
      if (e.pointerId !== event.pointerId) return
      if (!this.dragged) {
        if (Math.hypot(e.clientX - start.x, e.clientY - start.y) < 6) return
        this.dragged = true
        thumb.classList.add("is-dragging")
      }
      const over = document.elementFromPoint(e.clientX, e.clientY)?.closest(".ash__thumb")
      if (!over || over === thumb || over.parentElement !== this.listTarget || over.classList.contains("is-pending")) return
      const box = over.getBoundingClientRect()
      if (e.clientX < box.left + box.width / 2) over.before(thumb)
      else over.after(thumb)
    }
    const end = (e) => {
      if (e.pointerId !== event.pointerId) return
      document.removeEventListener("pointermove", move)
      document.removeEventListener("pointerup", end)
      document.removeEventListener("pointercancel", end)
      thumb.classList.remove("is-dragging")
      if (this.dragged) {
        thumb.focus()
        this.relabel()
        if (this.settled.map((t) => t.dataset.id).join() !== order) this.saveOrder()
      }
      // The click that ends a drag replaces nothing.
      setTimeout(() => { this.dragged = false })
    }
    document.addEventListener("pointermove", move)
    document.addEventListener("pointerup", end)
    document.addEventListener("pointercancel", end)
  }

  // The order saves after the uploads ahead of it, with the list as it is then, so a move made during an upload counts it too.
  saveOrder() {
    this.orderChanged = true
    this.queue = this.queue.then(async () => {
      if (!this.orderChanged) return
      this.orderChanged = false
      try {
        const response = await this.request("PATCH", this.orderUrlValue, { ids: this.settled.map((thumb) => thumb.dataset.id) })
        if (!response.ok) throw new Error(await this.problem(response, "Saving the order failed."))
      } catch (error) {
        this.say(error.message, true)
      }
    })
  }

  request(method, url, body) {
    const headers = { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "" }
    if (body) headers["Content-Type"] = "application/json"
    return fetch(url, { method, headers, body: body && JSON.stringify(body) })
  }

  async problem(response, fallback) {
    const body = await response.json().catch(() => ({}))
    return body.error || `${fallback} (${response.status})`
  }

  // Each screenshot's name says where it stands, and the first is the cover. The add button shows while there is room.
  relabel() {
    const thumbs = this.thumbs
    thumbs.forEach((thumb, i) => {
      const name = `Screenshot ${i + 1} of ${thumbs.length}`
      thumb.setAttribute("aria-label", i === 0 ? `${name}, the cover` : name)
      thumb.classList.toggle("ash__thumb--cover", i === 0)
    })
    this.addTarget.hidden = this.full
  }

  state(thumb, text) {
    const caption = thumb.querySelector(".ash__thumb-state")
    caption.textContent = text
    caption.hidden = !text
  }

  progress(thumb, fraction) {
    const bar = thumb.querySelector("progress")
    bar.hidden = false
    bar.value = fraction
  }

  settle(thumb) {
    thumb.classList.remove("is-pending", "is-busy")
    thumb.querySelector("progress").hidden = true
    this.state(thumb, "")
  }

  // A file that could not be saved, named, so a batch says which.
  fail(file, message) {
    this.errors.push(`${file.name}: ${message}`)
    this.say(this.errors.join("\n"), true)
  }

  say(message, error = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("ash__shot-status--error", error)
  }
}
