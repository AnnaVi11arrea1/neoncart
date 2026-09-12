import { Controller } from "@hotwired/stimulus"

// Click a small review photo to see it full-size in an overlay.
//   <div data-controller="lightbox">
//     <img data-lightbox-target="thumb" data-action="lightbox#open" data-full="big.jpg" src="small.jpg">
//   </div>
export default class extends Controller {
  open(event) {
    const overlay = document.createElement("div")
    overlay.className = "lightbox-overlay"
    overlay.innerHTML = `<img src="${event.currentTarget.dataset.full}" alt="${event.currentTarget.alt}">`
    overlay.addEventListener("click", () => overlay.remove())
    document.body.appendChild(overlay)
  }
}
