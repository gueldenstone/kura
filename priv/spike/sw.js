// THROWAWAY SPIKE (ADR 0003). App shell caching only; data is handled by app.js.
const CACHE = "kura-spike-v1"
const SHELL = ["/spike/", "/spike/app.js", "/spike/manifest.webmanifest", "/spike/icon-192.png"]

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()))
})

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  )
})

// Network first for the shell so edits show up when online; cache when offline.
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url)
  if (e.request.method !== "GET" || !url.pathname.startsWith("/spike/") || url.pathname.startsWith("/spike/api/")) return
  e.respondWith(
    fetch(e.request)
      .then(res => {
        const copy = res.clone()
        caches.open(CACHE).then(c => c.put(e.request, copy))
        return res
      })
      .catch(() => caches.match(e.request, {ignoreSearch: true}))
  )
})
