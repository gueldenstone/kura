# 0003. PWA with offline reads and queued check-offs

- Status: Accepted
- Date: 2026-10-31

## Context
The motivating use case is being in a store without signal. Required offline behaviour:

- Everything is **readable** offline (inventory and shopping list).
- Only one **write** is required offline: checking items off the shopping list, synced when the connection returns.

LiveView needs a live server connection, so offline support has to come from a service worker and client-side storage rather than from LiveView itself.

## Decision
- Ship as an installable PWA (manifest + service worker).
- The service worker caches the app shell; the last-known inventory and shopping list are cached for offline viewing.
- Offline check-offs are queued client-side and replayed against the server on reconnect.
- Conflicts are resolved last-write-wins; check-offs rarely conflict between two users.

The offline views (shopping list and inventory) are a **separate lightweight client view in plain JS**, served under their own scope with their own service worker. The rest of the app stays LiveView and needs a connection.

## Spike result (2026-10-31)
A throwaway spike (`/spike`, plain JS, in-memory server state) was tested on an iPhone over HTTPS (Tailscale Serve): installed to the home screen, rendered cached data in airplane mode, queued check-offs offline and synced them on reconnect. The approach works, so LiveView stays as the framework. Not verified: a LiveView page served from cache (deliberately not pursued; the separate client view is simpler).

## Validation gate (passed)
Before building the online core, a throwaway spike (roadmap milestone 1) had to show on a real phone in airplane mode that the approach works. If it only works with heavy client-side code that duplicates the app, we supersede this ADR and ADR 0002 and reconsider the framework (for example a client-side-first app with a sync API) instead of forcing LiveView.

## Consequences
- Adds client-side JavaScript beyond plain LiveView, bundled via `app.js` as per project guidelines.
- Full offline editing is explicitly out of scope for the MVP.
- The server must apply a replayed check-off through the real restock action (count: add quantity; level: set to plenty), so the offline client sends intents, not computed stock values.
- Service workers need HTTPS: for phone testing in development use `tailscale serve --bg --https=443 http://localhost:4000`; production sits behind HTTPS on the VPS anyway.
