// Include phoenix_html to handle form submissions and "data-confirm" attributes
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Hooks
let Hooks = {}

// Reader hook for scroll detection and image preloading
Hooks.ReaderHook = {
  mounted() {
    this.scrollHandler = this.handleScroll.bind(this)
    window.addEventListener("scroll", this.scrollHandler)

    // Handle preload_images event from server
    this.handleEvent("preload_images", ({urls}) => {
      this.preloadImages(urls)
    })
  },

  destroyed() {
    window.removeEventListener("scroll", this.scrollHandler)
  },

  handleScroll() {
    const scrollTop = window.scrollY
    const windowHeight = window.innerHeight
    const documentHeight = document.documentElement.scrollHeight

    // Check if near bottom (80% scrolled)
    const scrollPercent = (scrollTop + windowHeight) / documentHeight
    if (scrollPercent > 0.8) {
      this.pushEvent("near_bottom", {})
    }
  },

  preloadImages(urls) {
    urls.forEach(url => {
      // Use link prefetch for browser-optimized preloading
      const link = document.createElement('link')
      link.rel = 'prefetch'
      link.as = 'image'
      link.href = url
      document.head.appendChild(link)

      // Also preload with Image object as fallback
      const img = new Image()
      img.src = url
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
