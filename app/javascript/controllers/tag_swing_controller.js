import { Controller } from "@hotwired/stimulus"

// A prize tag swings from its clip in the direction the cursor moves across it, more the faster it moves, up to a hard
// limit. Not real physics: the angle eases toward a target that decays back to 0, so it settles without wobbling.
// The angle goes to --swing (the CSS `rotate` property, which composes with the card's own transform). The frame loop
// runs only while the tag is moving. Mouse and pen only, and not with reduced motion.
const MAX_DEGREES = 8
const DEGREES_PER_PX_MS = 7 // degrees of swing for a cursor speed of 1px per ms
const TARGET_DECAY_MS = 140 // the target falls to 1/e of itself in this long
const EASE_MS = 80 // the angle closes 1/e of its gap to the target in this long
const SMOOTHING = 0.5 // how much of the latest cursor speed joins the running speed

export default class extends Controller {
  connect() {
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.angle = 0
    this.target = 0
    this.speed = 0
    this.lastEvent = null
    this.lastFrame = null
    this.frame = null
    this.move = this.move.bind(this)
    this.step = this.step.bind(this)
    this.element.addEventListener("pointermove", this.move)
  }

  disconnect() {
    this.element.removeEventListener("pointermove", this.move)
    if (this.frame) cancelAnimationFrame(this.frame)
    this.element.style.removeProperty("--swing")
  }

  move(event) {
    if (event.pointerType === "touch" || this.reduced.matches) return
    const previous = this.lastEvent
    this.lastEvent = event.timeStamp
    if (previous === null || event.timeStamp - previous > 100) return // the first move of a pass has no speed yet
    const dt = Math.max(event.timeStamp - previous, 1)
    this.speed += (event.movementX / dt - this.speed) * SMOOTHING
    const swing = Math.max(-MAX_DEGREES, Math.min(MAX_DEGREES, this.speed * DEGREES_PER_PX_MS))
    // A tag dragged along swings its foot the way the cursor goes, which is a turn against the clock for rightward.
    this.target = -swing
    if (!this.frame) {
      this.lastFrame = null
      this.frame = requestAnimationFrame(this.step)
    }
  }

  step(now) {
    const dt = this.lastFrame === null ? 16 : Math.min(now - this.lastFrame, 50)
    this.lastFrame = now
    this.target *= Math.exp(-dt / TARGET_DECAY_MS)
    this.speed *= Math.exp(-dt / TARGET_DECAY_MS)
    this.angle += (this.target - this.angle) * (1 - Math.exp(-dt / EASE_MS))
    if (Math.abs(this.angle) < 0.02 && Math.abs(this.target) < 0.02) {
      this.angle = this.target = this.speed = 0
      this.frame = null
      this.lastEvent = null
      this.element.style.removeProperty("--swing")
      return
    }
    this.element.style.setProperty("--swing", `${this.angle.toFixed(2)}deg`)
    this.frame = requestAnimationFrame(this.step)
  }
}
