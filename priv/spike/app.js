// THROWAWAY SPIKE (ADR 0003): offline read + queued check-off, vanilla JS.
const STATE_KEY = "kura-spike-state"
const QUEUE_KEY = "kura-spike-queue"

const load = (key, fallback) => {
  try { return JSON.parse(localStorage.getItem(key)) ?? fallback } catch { return fallback }
}
const save = (key, value) => localStorage.setItem(key, JSON.stringify(value))

let state = load(STATE_KEY, {shopping: [], inventory: []})
let queue = load(QUEUE_KEY, [])
let online = false

const $ = id => document.getElementById(id)
const esc = s => s.replace(/[&<>"]/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c]))

// Apply queued (unsynced) check-offs on top of the last known server state.
const effective = () => {
  const pending = new Map(queue.map(q => [q.id, q.checked]))
  return state.shopping.map(i => pending.has(i.id) ? {...i, checked: pending.get(i.id)} : i)
}

const render = () => {
  $("status").textContent = (online ? "online" : "OFFLINE") + " · queued: " + queue.length
  $("status").className = online ? "ok" : "off"
  $("shopping").innerHTML = effective().map(i => `
    <li class="${i.checked ? "done" : ""}">
      <label><input type="checkbox" data-id="${i.id}" ${i.checked ? "checked" : ""}>
      ${esc(i.name)} <span class="qty">× ${i.qty}</span></label>
    </li>`).join("")
  $("inventory").innerHTML = state.inventory.map(i =>
    `<li>${esc(i.name)} <span class="qty">${esc(String(i.stock))}</span></li>`).join("")
  $("updated").textContent = state.fetched_at ? "data from " + new Date(state.fetched_at).toLocaleTimeString() : "no data yet"
}

const flush = async () => {
  if (queue.length === 0) return true
  const res = await fetch("/spike/api/check", {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({changes: queue})
  })
  if (!res.ok) throw new Error("sync failed")
  queue = []
  save(QUEUE_KEY, queue)
  return true
}

const refresh = async () => {
  try {
    await flush()
    const res = await fetch("/spike/api/state", {cache: "no-store"})
    if (!res.ok) throw new Error("state failed")
    state = {...(await res.json()), fetched_at: Date.now()}
    save(STATE_KEY, state)
    online = true
  } catch {
    online = false
  }
  render()
}

$("shopping").addEventListener("change", e => {
  const id = Number(e.target.dataset.id)
  queue = queue.filter(q => q.id !== id)
  queue.push({id, checked: e.target.checked, ts: Date.now()})
  save(QUEUE_KEY, queue)
  render()
  refresh()
})

$("sync").addEventListener("click", refresh)
$("reset").addEventListener("click", async () => {
  queue = []; save(QUEUE_KEY, queue)
  await fetch("/spike/api/reset", {method: "POST"}).catch(() => {})
  refresh()
})

window.addEventListener("online", refresh)
window.addEventListener("offline", () => { online = false; render() })
setInterval(refresh, 5000)

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/spike/sw.js", {scope: "/spike/"})
    .then(() => { $("sw").textContent = "service worker: registered" })
    .catch(err => { $("sw").textContent = "service worker: FAILED " + err.message })
} else {
  $("sw").textContent = "service worker: unavailable (" + (window.isSecureContext ? "secure" : "insecure context") + ")"
}

render()
refresh()
