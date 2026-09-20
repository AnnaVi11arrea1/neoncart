import { Controller } from "@hotwired/stimulus"

// Product gallery: click a thumbnail to load it into the main slot, or step
// through everything with the prev/next arrows. A slide is a photo, an
// uploaded video, a YouTube embed, or a "watch on TikTok" link — see
// Product#gallery_items and ApplicationHelper#gallery_media_tag, which
// render the very same four shapes server-side for the first slide.
//   <div data-controller="gallery">
//     <div data-gallery-target="main">...initial slide markup...</div>
//     <button data-action="gallery#prev">‹</button>
//     <button data-action="gallery#next">›</button>
//     <button data-gallery-target="thumb" data-action="gallery#select"
//             data-gallery-index-param="0"
//             data-type="image|video-file|video-embed|video-link"
//             data-url="..." data-alt="...">…</button>
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
    const { type, url, alt } = thumb.dataset
    this.mainTarget.innerHTML = this.renderSlide(type, url, alt)
    this.thumbTargets.forEach((el, i) => el.classList.toggle("is-active", i === index))
  }

  renderSlide(type, url, alt) {
    const safeAlt = alt ? alt.replace(/"/g, "&quot;") : ""
    switch (type) {
      case "video-file":
        return `<video src="${url}" controls playsinline class="product-page__video"></video>`
      case "video-embed":
        return `<iframe src="${url}" class="product-page__video-embed" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen frameborder="0"></iframe>`
      case "video-link":
        return `<a href="${url}" target="_blank" rel="noopener" class="product-page__video-link">▶ Watch on ${safeAlt}</a>`
      default:
        return `<img src="${url}" alt="${safeAlt}" class="product-page__main-img">`
    }
  }
}
