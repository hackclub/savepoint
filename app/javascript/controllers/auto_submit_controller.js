import { Controller } from "@hotwired/stimulus"

// Submits its form once the page shows, so sign-in runs straight on to the next step. submit() skips Turbo, which
// cannot follow a redirect to another site. The button stays for when scripts don't run.
export default class extends Controller {
  connect() {
    this.element.submit()
  }
}
