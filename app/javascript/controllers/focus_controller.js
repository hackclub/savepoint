import { Controller } from "@hotwired/stimulus"
import { Radio, TRACKS } from "focus/radio"

const BREAK_SECONDS = 5 * 60
// Hackatime's checked this often while you're locked in (and whenever you hit refresh).
const SYNC_EVERY = 3 * 60 * 1000
const LENGTH_KEY = "save-point:pomodoro-minutes"
// Looking for a pomodoro your buddy started (on your project page), and who's in once you're in one together.
const BUDDY_WATCH_EVERY = 20 * 1000
const TOGETHER_POLL_EVERY = 10 * 1000
// The pomodoro opens out of the button you pressed and closes back into the Start button, over the same 320ms and curve
// as the nav's slide (transitions.css). Reduced motion: it appears and goes at once.
const OPEN_MS = 320
const EASE = "cubic-bezier(.22, 1, .36, 1)"

// A pomodoro: lock in for as long as you picked, over the whole page, with the radio playing. Your
// Hackatime hours along the top keep themselves up to date. When a round's done it chimes, and you
// can go again, take a five-minute break or head back.
export default class extends Controller {
  static targets = [ "overlay", "label", "title", "clock", "bar", "note", "toggle", "toggleLabel", "end", "live", "done",
                     "tracked", "sync", "synced", "trackTag",
                     "trackName", "trackNumber", "equalizer", "music", "length", "together", "buddyLive", "buddyLiveText",
                     "stickers", "stickersCounting", "stickersEarned", "stickerBar", "stickerFill", "stickerCount" ]
  static values = { title: String, hoursUrl: String, tracks: Object, buddyUrl: String, buddyName: String }

  connect() {
    this.track = 0
    this.equalizerTarget.innerHTML = "<span></span>".repeat(20)
    const saved = read(LENGTH_KEY)
    const remembered = this.lengthTargets.find((input) => input.value === saved)
    if (remembered) remembered.checked = true
    // With a buddy, keep an eye out for a pomodoro they start, to join.
    if (this.buddyUrlValue) this.watcher = setInterval(() => this.#checkBuddy(), BUDDY_WATCH_EVERY)
  }

  disconnect() {
    this.#stop()
    clearInterval(this.watcher)
  }

  get minutes() {
    return Number(this.lengthTargets.find((input) => input.checked)?.value || 25)
  }

  pickLength() {
    write(LENGTH_KEY, String(this.minutes))
  }

  // On your own.
  start(event) {
    this.together = false
    this.#open({}, event?.currentTarget)
  }

  // A pomodoro your buddy can join: started on the server, so you both count down to the same end.
  async startWithBuddy(event) {
    const from = event?.currentTarget
    const status = await this.#buddyRequest("POST", this.buddyUrlValue, { minutes: this.minutes })
    if (status?.live) this.#openTogether(status, from)
  }

  async joinBuddy(event) {
    const from = event?.currentTarget
    const status = await this.#buddyRequest("POST", `${this.buddyUrlValue}/join`)
    if (status?.live) this.#openTogether(status, from)
    else this.buddyLiveTarget.hidden = true
  }

  #openTogether(status, from) {
    this.together = true
    this.buddyLiveTarget.hidden = true
    const left = Math.max(1, Math.round((Date.parse(status.ends_at) - Date.parse(status.now)) / 1000))
    this.#open({ left, total: status.minutes * 60 }, from)
    this.#showTogether(status)
    this.togetherPoll = setInterval(() => this.#checkBuddy(), TOGETHER_POLL_EVERY)
  }

  // "Another round" from the done screen opens nothing new (the overlay is up already): only a hidden overlay opens out.
  #open(timing, from) {
    this.#stop()
    const opening = this.overlayTarget.hidden
    this.overlayTarget.hidden = false
    if (opening) this.#reveal("open", from)
    try {
      this.radio = new Radio(this.tracksValue)
      this.radio.onTrack = () => this.#render()
      this.radio.setTrack(this.track)
      this.radio.play()
    } catch {
      this.radio = null // no Web Audio: the timer still works
    }
    this.session = { round: 1, built: 0 }
    this.#round(timing)
    this.ticker = setInterval(() => this.#tick(), 1000)
    this.syncer = setInterval(() => this.syncHours(), SYNC_EVERY)
    this.syncHours()
    this.#equalize()
    this.toggleTarget.focus()
  }

  toggle() {
    this.session.running = !this.session.running
    this.#render()
  }

  // Ends the round (or skips the break).
  end() {
    if (this.session.phase === "break") return this.#round()
    this.#finish()
  }

  again() {
    if (this.together) return this.startWithBuddy()
    this.session.built = 0
    this.#round()
  }

  takeBreak() {
    Object.assign(this.session, { phase: "break", left: BREAK_SECONDS, total: BREAK_SECONDS, running: true })
    this.#render()
  }

  exit() {
    this.#stop()
    this.#reveal("close")
  }

  // The overlay grows from a circle at the button (open) and shrinks back into the Start button (close). Pressing Start
  // again while it closes just cancels the close.
  #reveal(way, from) {
    const overlay = this.overlayTarget
    this.reveal?.cancel()
    this.reveal = null
    // The button you pressed, unless it is gone (the Join button hides as the pomodoro starts): then the Start button.
    const start = this.element.querySelector(".project__start")
    const button = way === "open" && from?.offsetParent ? from : start
    if (matchMedia("(prefers-reduced-motion: reduce)").matches || !button?.isConnected) {
      overlay.hidden = way === "close"
      return
    }
    const box = button.getBoundingClientRect()
    const at = `${box.left + box.width / 2}px ${box.top + box.height / 2}px`
    const full = `circle(${Math.hypot(innerWidth, innerHeight)}px at ${at})`
    const none = `circle(0px at ${at})`
    const frames = way === "open" ? [ { clipPath: none }, { clipPath: full } ] : [ { clipPath: full }, { clipPath: none } ]
    const animation = this.reveal = overlay.animate(frames, { duration: OPEN_MS, easing: EASE, fill: "both" })
    animation.onfinish = () => {
      this.reveal = null
      if (way === "close") overlay.hidden = true
      animation.cancel()
    }
  }

  key(event) {
    if (event.key === "Escape" && !this.overlayTarget.hidden) this.exit()
  }

  music() {
    if (!this.radio) return
    this.radio.playing ? this.radio.pause() : this.radio.play()
    setTimeout(() => this.#render(), 50)
  }

  nextTrack() {
    this.track = (this.track + 1) % TRACKS.length
    this.radio?.setTrack(this.track)
    this.#render()
  }

  // Asks for your hours from Hackatime (asking Hackatime itself when you hit refresh), spinning while it does.
  async syncHours(event) {
    if (this.syncing) return
    this.syncing = true
    this.syncTarget.toggleAttribute("data-syncing", true)
    try {
      const url = event ? `${this.hoursUrlValue}?refresh=1` : this.hoursUrlValue
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(response.statusText)
      const { label, stickers } = await response.json()
      this.trackedTarget.textContent = label
      this.#renderStickers(stickers)
      this.syncedAt = Date.now()
      this.syncTarget.removeAttribute("data-failed")
    } catch {
      this.syncTarget.toggleAttribute("data-failed", true)
    } finally {
      this.syncing = false
      this.syncTarget.toggleAttribute("data-syncing", false)
      this.#renderSynced()
    }
  }

  // A round of focus, as long as you picked (or what's left of one with your buddy). The first is round 1; every one
  // after counts up.
  #round({ left, total } = {}) {
    const seconds = this.minutes * 60
    if (this.started) this.session.round += 1
    this.started = true
    Object.assign(this.session, { phase: "focus", left: left ?? seconds, total: total ?? seconds, running: true })
    this.#render()
  }

  #tick() {
    const session = this.session
    this.#renderSynced()
    this.#expireStickers()
    if (!session.running || session.phase === "done") return
    session.left -= 1
    if (session.phase === "focus") session.built += 1
    if (session.left > 0) return this.#render()
    session.phase === "focus" ? this.#finish() : this.#round()
  }

  #finish() {
    Object.assign(this.session, { phase: "done", running: false, left: 0 })
    if (this.radio?.playing) this.radio.chime()
    this.syncHours()
    this.#render()
  }

  // End pomodoro: the done screen's buttons rise in as the round's buttons go, rather than swapping at once.
  #settleIn() {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return
    this.doneTarget.animate([ { opacity: 0, transform: "translateY(16px)" }, { opacity: 1, transform: "none" } ], { duration: OPEN_MS, easing: EASE })
  }

  #equalize() {
    const bars = Array.from(this.equalizerTarget.children)
    const levels = this.radio ? this.radio.levels(bars.length) : bars.map(() => 0)
    bars.forEach((bar, index) => bar.style.blockSize = `${3 + levels[index] * 29}px`)
    this.frame = requestAnimationFrame(() => this.#equalize())
  }

  #render() {
    const { phase, running, round, built, left, total } = this.session
    const done = phase === "done"
    const onBreak = phase === "break"
    const playing = Boolean(this.radio?.playing)
    if (this.radio) this.track = this.radio.track

    const lockedIn = this.together ? `Locked in with ${this.buddyNameValue}` : "Locked in"
    this.labelTarget.textContent = done ? "Pomodoro done" : onBreak ? "Break" : `${running ? lockedIn : "Paused"} · round ${round}`
    this.titleTarget.textContent = done ? (built < 60 ? "Pomodoro done." : `${Math.round(built / 60)} min logged.`)
      : onBreak ? "Take a break." : this.titleValue
    this.clockTarget.textContent = clock(done ? built : left)
    this.barTarget.style.inlineSize = done ? "100%" : `${(1 - left / total) * 100}%`
    this.barTarget.toggleAttribute("data-break", onBreak)
    this.noteTarget.textContent = done ? "Hackatime already logged it. Nothing to submit."
      : onBreak ? "Music keeps going. The next round starts on its own." : ""
    this.noteTarget.hidden = !done && !onBreak
    this.toggleLabelTarget.textContent = running ? "Pause" : "Resume"
    this.toggleTarget.setAttribute("aria-pressed", String(!running))
    this.endTarget.textContent = onBreak ? "Skip break" : "End pomodoro"
    const arriving = done && this.doneTarget.hidden
    this.liveTarget.hidden = done
    this.doneTarget.hidden = !done
    if (arriving) this.#settleIn()
    this.overlayTarget.toggleAttribute("data-music", playing)

    const track = TRACKS[this.track]
    this.trackTagTarget.textContent = track.tag
    this.trackTagTarget.style.background = track.color
    this.trackNameTarget.textContent = track.name
    this.trackNumberTarget.textContent = `track ${this.track + 1} of ${TRACKS.length}`
    this.musicTarget.setAttribute("aria-pressed", String(playing))
    this.musicTarget.setAttribute("aria-label", playing ? "Pause music" : "Play music")
  }

  // The free stickers' strip (D-051), from what the hours endpoint says: progress while counting, the earned look (with a
  // small pop) once they're earned, gone when it's claimed or there's no promise.
  #renderStickers(stickers) {
    if (!this.hasStickersTarget) return
    if (!stickers || stickers.kind === "claimed") {
      this.stickersTarget.hidden = true
      return
    }
    if (stickers.kind === "earned") {
      const arriving = this.stickersTarget.dataset.kind !== "earned"
      this.stickersTarget.dataset.kind = "earned"
      if (this.hasStickersCountingTarget) this.stickersCountingTarget.hidden = true
      this.stickersEarnedTarget.hidden = false
      if (arriving && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
        this.stickersTarget.toggleAttribute("data-pop", false)
        void this.stickersTarget.offsetWidth
        this.stickersTarget.toggleAttribute("data-pop", true)
      }
      return
    }
    if (stickers.minutes == null || !this.hasStickerFillTarget) return
    this.stickerFillTarget.style.inlineSize = `${stickers.percent}%`
    this.stickerBarTarget.setAttribute("aria-valuenow", String(stickers.minutes))
    this.stickerBarTarget.hidden = false
    this.stickerCountTarget.hidden = false
    this.stickerCountTarget.textContent = stickers.text
  }

  // The hour ran out without earning them: the strip goes.
  #expireStickers() {
    if (!this.hasStickersTarget || this.stickersTarget.dataset.kind !== "counting") return
    const deadline = Date.parse(this.stickersTarget.dataset.deadline)
    if (deadline && Date.now() >= deadline) this.stickersTarget.hidden = true
  }

  // "just now", "2 min ago", or that it couldn't.
  #renderSynced() {
    if (this.syncTarget.hasAttribute("data-failed")) return this.syncedTarget.textContent = "couldn't reach Hackatime"
    if (!this.syncedAt) return
    const minutes = Math.floor((Date.now() - this.syncedAt) / 60000)
    this.syncedTarget.textContent = minutes < 1 ? "just now" : `${minutes} min ago`
  }

  // How your buddy's pomodoro is going: whether there's one to join, or (in one together) whether they're in.
  async #checkBuddy() {
    const status = await this.#buddyRequest("GET", this.buddyUrlValue)
    if (!status) return
    if (this.together && !this.overlayTarget.hidden) return this.#showTogether(status)

    const waiting = status.live && !status.you_in
    this.buddyLiveTarget.hidden = !waiting
    if (waiting) this.buddyLiveTextTarget.textContent = `${status.buddy} started a ${status.minutes}-min pomodoro. Join in.`
  }

  #showTogether(status) {
    const name = status.buddy || this.buddyNameValue
    this.togetherTarget.hidden = false
    this.togetherTarget.toggleAttribute("data-in", Boolean(status.live && status.buddy_in))
    this.togetherTarget.textContent = !status.live ? `with ${name} · done` : status.buddy_in ? `with ${name} · in` : `waiting for ${name}`
  }

  async #buddyRequest(method, url, body) {
    try {
      const response = await fetch(url, {
        method,
        headers: { Accept: "application/json", "Content-Type": "application/json",
                   "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        body: body ? JSON.stringify(body) : undefined
      })
      return await response.json()
    } catch {
      return null
    }
  }

  #stop() {
    clearInterval(this.ticker)
    clearInterval(this.syncer)
    clearInterval(this.togetherPoll)
    if (this.hasTogetherTarget) this.togetherTarget.hidden = true
    cancelAnimationFrame(this.frame)
    this.radio?.close()
    this.radio = null
    this.started = false
  }
}

function clock(seconds) {
  const pad = (number) => String(number).padStart(2, "0")
  const h = Math.floor(seconds / 3600), m = Math.floor(seconds % 3600 / 60), s = seconds % 60
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
}

// localStorage can be off (private windows, blocked storage); then it just doesn't remember.
function read(key) {
  try { return localStorage.getItem(key) } catch { return null }
}

function write(key, value) {
  try { localStorage.setItem(key, value) } catch {}
}
