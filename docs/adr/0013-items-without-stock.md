# 0013. Items without stock tracking

- Status: Accepted
- Date: 2026-11-08

## Context
Some things are only ever bought when needed (birthday candles, baking paper). They belong in the catalogue so they never have to be retyped and can be added to the shopping list from it, but a level or a count for them is noise: nobody keeps it up to date, and the inventory check would keep asking about it. ADR 0005 has two tracking types and expected a third to need a new stock field.

## Decision
- A third value for `tracking`: `:none`. It needs no new field: both `stock_count` and `stock_level` stay `nil` (`NormalizeStock` clears them) and `auto_replenish` is forced off, because the item never runs out.
- `empty?` is always false for these items. `mark_empty` refuses them, and so do the count and level actions, as before for the wrong type.
- Checking an entry off, or unchecking it, does not touch the item; the entry just moves between the open list and the cart. The offline queue does the same.
- The inventory check leaves them out: all three check reads filter `tracking != :none`, and the place picker counts with a `stock_item_count` aggregate on `Location`. The Locations page still counts all items in a place.
- In the inventory row the stock control is replaced by an **Add to list** button that shows **On list** while the item is on the list (no separate cart marker). The item form offers None next to Level and Count and hides Auto-replenish for these items.
- The tracking type stays fixed at creation (ADR 0005).

## Consequences
- No migration: `tracking` is stored as text and the allowed values are checked in the app.
- Turning an existing item into one without stock still means deleting and recreating it, with its tags and places. If that comes up often, a "change tracking" action is the next step.
- Every place that branches on `tracking` (check-off, uncheck, the stock control, the offline view and state) has a `:none` case.
