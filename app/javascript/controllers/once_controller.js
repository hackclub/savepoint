import { Controller } from "@hotwired/stimulus"

// A form that can only be sent once: the button goes inactive on submit and a second submit is ignored.
export default class extends Controller {
  submit(event) {
    if (this.sent) return event.preventDefault()
    this.sent = true
    this.element.querySelectorAll("button").forEach(button => { button.disabled = true })
  }
}
