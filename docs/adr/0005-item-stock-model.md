# 0005. Items with per-item stock tracking in one resource

- Status: Accepted
- Date: 2026-10-31

## Context
Items are a permanent catalogue. Some are best tracked by a number (apples), others by a rough level (walnuts: plenty, low, empty). Check-off on the shopping list (milestone 4) must restock both kinds.

## Decision
- One Ash resource, `Kura.Inventory.Item`, with a `tracking` attribute (`:count` or `:level`), nullable `stock_count` and `stock_level`, and a `usual_amount` (buy quantity, default 1).
- Only the field matching `tracking` is kept; the other is forced to `nil`. A new count item starts at 1, a new level item at `:plenty`.
- The tracking type is fixed at creation; changing it means deleting and recreating the item.
- "Empty" is a calculation (`empty?`): count 0, or level `:empty`. "Mark empty" is its own action so milestone 4 can attach "put on the shopping list" to it.
- Item names are unique, ignoring case, via an identity with `pre_check?` (SQLite has no real `citext`, see ADR 0004).
- Undo of "mark empty" is held in the LiveView (the previous stock of the last item marked empty), not persisted.
- Database tests run serially: SQLite allows one writer, so async tests fail with "Database busy".

## Consequences
- Adding a third tracking type later means a new value, a new stock field or a union, and new cases in the stock actions.
- Undo is lost on reload and only covers the most recent "mark empty" on that device.
- Two phones changing the same count at once can race (the change reads, then writes). Acceptable for two users; revisit if it bites.
