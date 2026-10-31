# Roadmap

The MVP (`docs/mvp.md`) is delivered by milestones 1–5. Update this file whenever a milestone changes or completes.

Offline was the riskiest requirement, so it was verified first. The spike passed (see ADR 0003). The spike code (`/spike`, `priv/spike/`, `KuraWeb.SpikeController`) is kept as reference for milestone 5 and deleted when that ships.

## MVP

| # | Milestone | Content | Status |
|---|-----------|---------|--------|
| 1 | Offline spike (throwaway) | Prove on a real phone, in airplane mode: installable PWA, cached read-only shopping list and inventory, queued check-off that syncs on reconnect. Outcome: accept or supersede ADR 0003, with a go/no-go on LiveView | Done: works on iPhone, ADR 0003 accepted, LiveView stays |
| 2 | Foundation | Auth for two users, app layout, deployment to the VPS | Todo |
| 3 | Inventory | Item catalogue, count and level tracking, mark empty | Todo |
| 4 | Shopping list | Entries with quantity, manual editing, check-off restocks, undo, live sync between phones | Todo |
| 5 | PWA and offline | Productionise the spike: installable, offline reads, queued offline check-offs | Todo |

## After the MVP (unordered ideas)

- Low-stock thresholds for count items that auto-add to the list
- Categories or store-aisle ordering of the shopping list
- Broader history beyond check-off undo
- Wider offline editing (stock changes, list edits)
- Units for quantities (kg, packs)
- Expiry dates
- Barcode scanning
- Recipes and meal planning
