import { Controller } from "@hotwired/stimulus"

// The screenshot slot uploads as soon as you've picked a file.
export default class extends Controller {
  upload() {
    this.element.requestSubmit()
  }
}
