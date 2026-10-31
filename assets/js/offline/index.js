// Offline support for Kura.
//
// Online, nothing changes: the LiveView app runs as usual and keeps a saved copy of the inventory
// and the shopping list in this phone's storage (the server pushes it after every change). With no
// connection, the service worker serves the offline screens (`#offline-root`, drawn by view.js)
// from that saved copy. Check-offs made there are queued and sent as soon as the server answers.

import {
  loadSnapshot, saveSnapshot, loadQueue, saveQueue, clearAll, toggleChange, applyQueue
} from "./state.js"
import {fetchSnapshot, pushQueue} from "./sync.js"
import {page, shoppingList, inventory, inventoryRows, noData} from "./view.js"

const RETRY_MS = 5000
const DISCONNECT_GRACE_MS = 4000

export function setupOffline(liveSocket) {
  registerServiceWorker()

  // The server pushes a fresh saved copy whenever anything changes.
  window.addEventListener("phx:kura:snapshot", event => saveSnapshot(event.detail))

  // Signing out also forgets what this phone saved.
  document.addEventListener("click", event => {
    if (event.target.closest('a[href="/sign-out"]')) clearAll()
  })

  const root = document.getElementById("offline-root")

  if (root) {
    mountOfflineView(root)
  } else {
    sendQueuedChanges()
    window.addEventListener("online", sendQueuedChanges)
    leaveForOfflineScreensWhenDisconnected(liveSocket)
  }
}

function registerServiceWorker() {
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/sw.js", {scope: "/"}).catch(() => {})
  }
}

// Check-offs that are still queued (from an earlier offline session) go out when the app is online.
async function sendQueuedChanges() {
  const queue = loadQueue()
  if (queue.length === 0) return

  try {
    const {status, snapshot} = await pushQueue(queue)
    if (status === 200) {
      saveQueue([])
      saveSnapshot(snapshot)
    }
  } catch {
    // Still offline; they stay queued.
  }
}

// When the LiveView connection is gone, reload: the service worker then answers the navigation
// with the offline screens instead of the browser's error page. LiveView keeps retrying with
// growing pauses and reports every failed attempt, so the check is scheduled once per outage and
// not pushed back by each retry. The phone's own "offline" event starts it sooner.
function leaveForOfflineScreensWhenDisconnected(liveSocket) {
  let timer = null

  const schedule = delay => {
    if (timer) return
    timer = setTimeout(check, delay)
  }

  const check = async () => {
    timer = null
    if (liveSocket.isConnected() || !navigator.serviceWorker?.controller) return

    try {
      await fetchSnapshot()
    } catch {
      window.location.reload()
    }
  }

  const socket = liveSocket.getSocket()
  socket.onClose(() => schedule(DISCONNECT_GRACE_MS))
  socket.onError(() => schedule(DISCONNECT_GRACE_MS))
  socket.onOpen(() => {
    clearTimeout(timer)
    timer = null
  })

  window.addEventListener("offline", () => {
    clearTimeout(timer)
    timer = null
    schedule(500)
  })
}

function mountOfflineView(root) {
  const model = {
    tab: window.location.pathname.startsWith("/inventory") ? "inventory" : "list",
    query: "",
    status: "offline",
    snapshot: loadSnapshot(),
    queue: loadQueue()
  }

  const appPath = model.tab === "inventory" ? "/inventory" : "/shopping-list"

  const render = () => {
    if (!model.snapshot) {
      root.innerHTML = page({status: model.status, queued: 0, tab: model.tab, openCount: 0, content: noData()})
      return
    }

    const view = applyQueue(model.snapshot, model.queue)
    const content = model.tab === "inventory" ? inventory(view, model.query) : shoppingList(view)

    root.innerHTML = page({
      status: model.status,
      queued: model.queue.length,
      tab: model.tab,
      openCount: view.open.length,
      content
    })

    root.querySelector("#offline-search")?.focus({preventScroll: true})
  }

  root.addEventListener("click", event => {
    const target = event.target.closest("[data-action]")
    if (!target) return

    const {action, id, tab} = target.dataset

    if (action === "tab") {
      model.tab = tab
      window.history.replaceState(null, "", tab === "inventory" ? "/inventory" : "/shopping-list")
    } else if (action === "check" || action === "uncheck") {
      model.queue = toggleChange(model.queue, action, id)
      saveQueue(model.queue)
    }

    render()
  })

  // Typing only redraws the list, so the search box keeps its focus and the keyboard stays up.
  root.addEventListener("input", event => {
    if (event.target.id !== "offline-search") return

    model.query = event.target.value
    root.querySelector("#offline-inventory").innerHTML = inventoryRows(
      applyQueue(model.snapshot, model.queue).items,
      model.query
    )
  })

  const show = status => {
    if (model.status === status) return
    model.status = status
    render()
  }

  // Look for the server now and every few seconds. Once it answers, send what was queued and
  // go back to the real app. Nothing is redrawn while the server stays unreachable.
  async function reconnect() {
    try {
      const probe = await fetchSnapshot()
      if (probe.status === 401) return show("signed-out")

      let latest = probe.snapshot

      if (model.queue.length > 0) {
        show("syncing")
        const sent = await pushQueue(model.queue)

        if (sent.status === 401) return show("signed-out")
        if (sent.status === 200) {
          model.queue = []
          saveQueue([])
          latest = sent.snapshot
        }
      }

      if (latest) saveSnapshot(latest)
      window.location.replace(appPath)
    } catch {
      show("offline")
    }
  }

  render()
  window.addEventListener("online", reconnect)
  setInterval(reconnect, RETRY_MS)
  reconnect()
}
