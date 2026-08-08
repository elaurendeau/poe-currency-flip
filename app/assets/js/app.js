// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Favorites are a personal, per-browser preference with no user-account
// system (docs/PRD.md § 7.10 / TECH_STACK.md) -- stored client-side only,
// same as the React version's useFavoriteRoutes hook. The server has no
// way to read localStorage itself, so this hook reports the saved set on
// mount and persists it again whenever the server pushes an update.
const FAVORITES_STORAGE_KEY = "poe-flip-finder:favorite-routes"

function loadFavoritesFromStorage() {
  try {
    const raw = window.localStorage.getItem(FAVORITES_STORAGE_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed.filter((item) => typeof item === "string") : []
  } catch {
    return []
  }
}

// Technique filters, sort column/direction, and threshold values are also a
// personal, per-browser preference (docs/PRD.md § 7.8/7.9) -- same
// client-storage treatment as Favorites above, so they survive a full page
// reload instead of resetting to the hardcoded defaults every time.
const DISPLAY_PREFERENCES_STORAGE_KEY = "poe-flip-finder:display-preferences"

function loadDisplayPreferencesFromStorage() {
  try {
    const raw = window.localStorage.getItem(DISPLAY_PREFERENCES_STORAGE_KEY)
    if (!raw) return {}
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
  } catch {
    return {}
  }
}

const Hooks = {
  FavoritesStorage: {
    mounted() {
      this.pushEvent("favorites_loaded", {route_keys: loadFavoritesFromStorage()})
      this.handleEvent("persist_favorites", ({route_keys}) => {
        window.localStorage.setItem(FAVORITES_STORAGE_KEY, JSON.stringify(route_keys))
      })
    },
  },

  DisplayPreferencesStorage: {
    mounted() {
      this.pushEvent("display_preferences_loaded", loadDisplayPreferencesFromStorage())
      this.handleEvent("persist_display_preferences", (prefs) => {
        window.localStorage.setItem(DISPLAY_PREFERENCES_STORAGE_KEY, JSON.stringify(prefs))
      })
    },
  },

  // docs/PRD.md § 7.6/7.11 pin timestamps to the browser's *local* time,
  // which a server-rendered LiveView can't know on its own -- reports the
  // same offset-in-minutes JS's own Date.getTimezoneOffset() is built
  // from, sign-flipped to match the conventional "ahead of UTC is
  // positive" reading.
  LocalTimezone: {
    mounted() {
      this.pushEvent("local_timezone_offset", {utc_offset_minutes: -new Date().getTimezoneOffset()})
    },
  },

  // Generic right-click menu positioning -- no business logic, mirrors
  // useRowContextMenu.ts. What the menu item actually does (toggling a
  // favorite) is server-side, driven by phx-click on the menu item itself.
  RowContextMenu: {
    mounted() {
      this.el.addEventListener("contextmenu", (event) => {
        event.preventDefault()
        this.pushEvent("open_context_menu", {
          route_key: this.el.dataset.routeKey,
          x: event.clientX,
          y: event.clientY,
        })
      })
    },
  },
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Closing the context menu on an outside click (matching the mockup's own
// reference script) is handled server-side via phx-click-away on the menu
// element itself -- no custom JS needed here.

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
