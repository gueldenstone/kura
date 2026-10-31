# Roadmap

The MVP (`docs/mvp.md`) is delivered by milestones 1–6. Update this file whenever a milestone changes or completes.

Offline was the riskiest requirement, so it was verified first. The spike passed (see ADR 0003). The spike code (`/spike`, `priv/spike/`, `KuraWeb.SpikeController`) is kept as reference for milestone 5 and deleted when that ships.

## MVP

| # | Milestone | Content | Status |
|---|-----------|---------|--------|
| 1 | Offline spike (throwaway) | Prove on a real phone, in airplane mode: installable PWA, cached read-only shopping list and inventory, queued check-off that syncs on reconnect. Outcome: accept or supersede ADR 0003, with a go/no-go on LiveView | Done: works on iPhone, ADR 0003 accepted, LiveView stays |
| 2 | Foundation | Username/password auth for two users (ADR 0004), mobile app shell with tab bar, `mix kura.user.create` | Done |
| 3 | Inventory | Item catalogue, count and level tracking, mark empty with undo, search, add/edit/delete (ADR 0005). Adding to the shopping list on "empty" comes with milestone 4 | Done |
| 4 | Shopping list | Entries with quantity, add from catalogue or as new item, check-off restocks, undo, hide checked, live sync between phones, inventory marker and tab badge (ADR 0007) | Done |
| 5 | PWA and offline | Productionise the spike: installable, offline reads, queued offline check-offs | Todo |
| 6 | Deployment | Dockerfile, release config, Traefik labels, deploy to the VPS over SSH, SQLite on a volume with backups | Todo |

## After the MVP (unordered ideas)

- Low-stock thresholds for count items that auto-add to the list
- Categories or store-aisle ordering of the shopping list
- Broader history beyond check-off undo
- Wider offline editing (stock changes, list edits)
- Units for quantities (kg, packs)
- Expiry dates
- Barcode scanning
- Recipes and meal planning
