// What a phone remembers for offline use, and the rules for changing it.
//
// The saved copy ("snapshot") comes from the server. Check-offs made without a connection are
// kept in a queue and shown on top of the snapshot until they have been sent. Everything here is
// pure apart from the small localStorage wrappers, so it can be tested without a browser page.

const SNAPSHOT_KEY = "kura:snapshot"
const QUEUE_KEY = "kura:queue"

const read = (key, fallback) => {
  try {
    const value = localStorage.getItem(key)
    return value ? JSON.parse(value) : fallback
  } catch {
    return fallback
  }
}

const write = (key, value) => {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // Storage can be full or blocked (private mode); the app still works online.
  }
}

export const loadSnapshot = () => read(SNAPSHOT_KEY, null)
export const saveSnapshot = snapshot => write(SNAPSHOT_KEY, snapshot)
export const loadQueue = () => read(QUEUE_KEY, [])
export const saveQueue = queue => write(QUEUE_KEY, queue)

export const clearAll = () => {
  try {
    localStorage.removeItem(SNAPSHOT_KEY)
    localStorage.removeItem(QUEUE_KEY)
  } catch {
    // nothing to clear
  }
}

// Flipping a check-off that is still queued cancels it: the queue holds the net change since the
// snapshot. Repeating the same change twice (a double tap) does nothing extra.
export function toggleChange(queue, op, entryId, now = Date.now()) {
  const existing = queue.find(change => change.entry_id === entryId)

  if (!existing) return [...queue, {op, entry_id: entryId, ts: now}]
  if (existing.op === op) return queue
  return queue.filter(change => change !== existing)
}

const byName = (a, b) => a.name.localeCompare(b.name, undefined, {sensitivity: "base"})

function restock(item, quantity) {
  if (item.tracking === "count") item.stock_count = (item.stock_count ?? 0) + quantity
  else item.stock_level = "plenty"
  item.empty = false
  item.on_list = false
}

function unstock(item, quantity) {
  if (item.tracking === "count") {
    item.stock_count = Math.max(0, (item.stock_count ?? 0) - quantity)
    item.empty = item.stock_count === 0
  }
  item.on_list = true
}

// The snapshot as it will look once the queued changes have been applied by the server. Changes
// that do not fit the snapshot (an unknown entry, a wrong state) are ignored, as the server would.
export function applyQueue(snapshot, queue) {
  const result = structuredClone(snapshot)
  const items = new Map(result.items.map(item => [item.id, item]))

  for (const {op, entry_id: entryId} of queue) {
    if (op === "check") {
      const index = result.open.findIndex(entry => entry.id === entryId)
      if (index < 0) continue

      const [entry] = result.open.splice(index, 1)
      result.checked.unshift({...entry, checked_at: new Date().toISOString()})
      if (items.has(entry.item_id)) restock(items.get(entry.item_id), entry.quantity)
    } else if (op === "uncheck") {
      const index = result.checked.findIndex(entry => entry.id === entryId)
      if (index < 0) continue

      const [entry] = result.checked.splice(index, 1)
      result.open.push({...entry, checked_at: null})
      result.open.sort(byName)
      if (items.has(entry.item_id)) unstock(items.get(entry.item_id), entry.quantity)
    }
  }

  return result
}

export function matches(item, query) {
  return item.name.toLowerCase().includes(query.trim().toLowerCase())
}
