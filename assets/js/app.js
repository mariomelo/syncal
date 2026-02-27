import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/syncal"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// ── Hooks ──────────────────────────────────────────────────────────────────

// Detects browser timezone and sends to LiveView once on mount.
// Won't override an already-logged-in user's stored preference.
const TimezoneDetect = {
  mounted() {
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (timezone) this.pushEvent("detect_timezone", { timezone })
  }
}

// Reads stored session from localStorage and sends to LiveView on mount.
// Both HomeLive and InquiryLive handle the "restore_session" event.
const RestoreSession = {
  mounted() {
    const name = localStorage.getItem("syncal_name") || ""
    const participantId = localStorage.getItem("syncal_participant_id") || ""
    if (name) this.pushEvent("restore_session", { name, participant_id: participantId })
  }
}

// ── LiveSocket ─────────────────────────────────────────────────────────────

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, TimezoneDetect, RestoreSession},
})

// ── Session persistence via localStorage ──────────────────────────────────

window.addEventListener("phx:store_user", (e) => {
  localStorage.setItem("syncal_name", e.detail.name)
  localStorage.setItem("syncal_participant_id", e.detail.participant_id)
})

window.addEventListener("phx:clear_user", () => {
  localStorage.removeItem("syncal_name")
  localStorage.removeItem("syncal_participant_id")
})

// ── Progress bar ───────────────────────────────────────────────────────────

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)
    window.liveReloader = reloader
  })
}
