# Roadmap

The MVP (`docs/mvp.md`) is delivered by milestones 1–6. Update this file whenever a milestone changes or completes.

Offline was the riskiest requirement, so it was verified first. The spike passed (see ADR 0003). The spike code has been removed; ADR 0008 describes the real implementation.

## MVP

| # | Milestone | Content | Status |
|---|-----------|---------|--------|
| 1 | Offline spike (throwaway) | Prove on a real phone, in airplane mode: installable PWA, cached read-only shopping list and inventory, queued check-off that syncs on reconnect. Outcome: accept or supersede ADR 0003, with a go/no-go on LiveView | Done: works on iPhone, ADR 0003 accepted, LiveView stays |
| 2 | Foundation | Username/password auth for two users (ADR 0004), mobile app shell with tab bar, `mix kura.user.create` | Done |
| 3 | Inventory | Item catalogue, count and level tracking, mark empty with undo, search, add/edit/delete (ADR 0005). Adding to the shopping list on "empty" comes with milestone 4 | Done |
| 4 | Shopping list | Entries with quantity, add from catalogue or as new item, check-off restocks, undo, hide checked, live sync between phones, inventory marker and tab badge (ADR 0007) | Done |
| 5 | PWA and offline | Installable, offline reads and search, queued offline check-offs that sync on reconnect (ADR 0008). Verified on an iPhone in airplane mode; switching to the offline screens after a signal drop takes a few seconds | Done |
| 6 | Deployment | Dockerfile, release config, GitHub Actions, Dependabot (ADR 0009). Deployed to the owner's VPS | Done |

The MVP is complete and deployed. Changes from real-world use are collected in `docs/feedback.md` and worked on as a batch.

## Next

Planned features after the MVP, in order.

| # | Milestone | Content | Status |
|---|-----------|---------|--------|
| 7 | Label CSV export | Select inventory items and download their names as a plain CSV with the column header `Label`, for label printing | Next |
| 8 | Optional replenishment | Per item: auto-replenish or not. Auto-replenish items go on the shopping list when marked empty; other items ask for confirmation first, since they are not regular stock | Planned |
| 9 | Inventory check mode | Each item tracks when its stock last changed. A guided mode walks through the stalest items, asks to confirm the current stock and offers a quick way to update it | Planned |

## After the MVP (unordered ideas)

- Low-stock thresholds for count items that auto-add to the list
- Categories or store-aisle ordering of the shopping list
- Broader history beyond check-off undo
- Wider offline editing (stock changes, list edits)
- Units for quantities (kg, packs)
- Expiry dates
- Barcode scanning
- Recipes and meal planning
