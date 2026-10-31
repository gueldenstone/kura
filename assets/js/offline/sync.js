// Talking to the server about the saved copy and the queued check-offs.
//
// A network error, a timeout or a 502-504 from a proxy in front of a stopped app all mean the
// same thing: the server cannot be reached. These functions throw for those cases and return
// `{status, snapshot}` for any real answer, so callers only have to tell "reachable" from not.

const TIMEOUT_MS = 5000

async function request(path, options = {}) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS)

  try {
    const response = await fetch(path, {
      credentials: "same-origin",
      cache: "no-store",
      signal: controller.signal,
      ...options,
      headers: {accept: "application/json", ...options.headers}
    })

    if (response.status >= 502 && response.status <= 504) throw new Error("server unreachable")

    const body = await response.json().catch(() => null)
    return {status: response.status, body}
  } finally {
    clearTimeout(timer)
  }
}

// The current saved copy. `snapshot` is null unless the answer was 200 (401 means signed out).
export async function fetchSnapshot() {
  const {status, body} = await request("/offline/state")
  return {status, snapshot: status === 200 ? body : null}
}

// Sends the queued check-offs; the server answers with a fresh saved copy.
export async function pushQueue(queue) {
  const {status, body} = await request("/offline/sync", {
    method: "POST",
    headers: {"content-type": "application/json", "x-kura-offline": "1"},
    body: JSON.stringify({changes: queue.map(({op, entry_id}) => ({op, entry_id}))})
  })

  return {status, snapshot: status === 200 ? body.snapshot : null}
}
