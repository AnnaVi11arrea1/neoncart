import { Controller } from "@hotwired/stimulus"

// Product photo gallery: click a thumbnail to load it into the big image,
// or step through all photos with the prev/next arrows.
//   <div data-controller="gallery">
//     <img data-gallery-target="main" src="..." alt="...">
//     <button data-action="gallery#prev">‹</button>
//     <button data-action="gallery#next">›</button>
//     <button data-gallery-target="thumb" data-action="gallery#select"
//             data-gallery-index-param="0" data-url="..." data-alt="...">…</button>
//   </div>
export default class extends Controller {
  static targets = ["main", "thumb"]

  connect() {
    this.currentIndex = 0
  }

  select(event) {
    this.show(event.params.index)
  }

  prev() {
    this.show((this.currentIndex - 1 + this.thumbTargets.length) % this.thumbTargets.length)
  }

  next() {
    this.show((this.currentIndex + 1) % this.thumbTargets.length)
  }

  show(index) {
    const thumb = this.thumbTargets[index]
    if (!thumb) return

    this.currentIndex = index
    this.mainTarget.src = thumb.dataset.url
    this.mainTarget.alt = thumb.dataset.alt
    this.thumbTargets.forEach((el, i) => el.classList.toggle("is-active", i === index))
  }
}
