import { Controller } from "@hotwired/stimulus"

// A time in your own time zone, as "Wed Nov 4, 2026, 9:00 pm (AEDT)". The server writes it in UTC until this runs.
export default class extends Controller {
  static values = { at: String, timeOnly: Boolean }

  connect() {
    const at = new Date(this.atValue)
    const day = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", year: "numeric" }).format(at)
    const time = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(at)
      .replace(/\s?([AP])M/, (_, half) => ` ${half.toLowerCase()}m`)
    const zone = new Intl.DateTimeFormat(navigator.language || undefined, { timeZoneName: "short" }).formatToParts(at)
      .find((part) => part.type === "timeZoneName")?.value

    if (this.timeOnlyValue) return this.element.textContent = time

    this.element.textContent = `${day}, ${time}${zone ? ` (${zone})` : ""}`
  }
}
