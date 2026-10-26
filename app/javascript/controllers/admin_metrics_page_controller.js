import { Controller } from "@hotwired/stimulus"

// The admin numbers table (admin/metrics): opens scrolled to its newest day, the column at the right end.
export default class extends Controller {
  connect() {
    this.element.scrollLeft = this.element.scrollWidth
  }
}
