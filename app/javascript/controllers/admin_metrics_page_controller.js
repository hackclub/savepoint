import { Controller } from "@hotwired/stimulus"

// The admin home's daily history table (admin/home/history): opens scrolled to its newest day, the column at the right end.
export default class extends Controller {
  connect() {
    this.element.scrollLeft = this.element.scrollWidth
  }
}
