@AGENTS.md

# Kura

Kura manages the contents of a kitchen. It is a small, self-hosted app for two people (the owner and their partner) who share one inventory and one shopping list from their phones.

## Core idea

1. **Inventory** – a permanent catalogue of kitchen items with a rough stock state. Items are never retyped: once created they stay in the catalogue, even when empty.
2. **Marking empty** – when the last of something is used, one tap marks it empty and puts it on the shopping list.
3. **Shopping list** – fed by "empty" items, but also manually editable. Entries carry a quantity. Checking an entry off restocks the item automatically.
4. **In the store** – the motivating scenario is standing in a shop without signal, wondering "do we still have walnuts?". The whole app must be readable offline, and checking items off the list must work offline and sync when the connection returns.

### Stock tracking is per item

Each item chooses how its stock is tracked:

- **count** – a number (e.g. apples). Reaching 0 means empty. Restocking adds the purchased quantity.
- **level** – plenty / low / empty (e.g. walnuts). Restocking sets it to plenty.

## Users and hosting

- Two users, username/password via `ash_authentication`, sharing one household's data.
- Self-hosted on the owner's VPS. Delivered as a PWA used on both phones.

## Stack

Phoenix 1.8 + LiveView, Ash 3 (`ash_sqlite`, `ash_authentication`, `ash_phoenix`). See `docs/adr/`.

## Project rules

- **Document architecture decisions as ADRs** in `docs/adr/` while developing, not afterwards. Any decision that is hard to reverse or that rules out reasonable alternatives gets one (see `docs/adr/README.md`). Update the status of an ADR instead of editing history; supersede it with a new one if the decision changes.
- **Scope is defined by `docs/mvp.md`.** Do not build features outside the MVP without first moving them into it. Planned later work lives in `docs/roadmap.md`.
- **Keep the roadmap current.** When a milestone is done or the plan changes, update `docs/roadmap.md` in the same change.
- Domain logic goes in Ash resources and actions; LiveViews call code interfaces rather than reaching into the data layer.
- Consult the `ash-framework` and `phoenix-framework` skills before domain or web-layer changes.
