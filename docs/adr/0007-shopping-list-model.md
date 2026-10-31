# 0007. Shopping list model and live sync

- Status: Accepted
- Date: 2026-10-31

## Context
The shopping list must stay in step with the inventory: marking something empty lists it, checking it off restocks it, and both phones should see changes without reloading.

## Decision
- `Kura.Inventory.ShoppingEntry` (same domain as `Item`) belongs to an item and carries a `quantity`, a `checked_at` (set while it is "in the cart") and the `previous_level` of a level item before check-off.
- An item has at most one **open** entry. This is enforced by a validation (`NotOnList`), not a database constraint. `ShoppingList.put_on_list/2` returns the existing entry instead of adding a second one.
- **Check-off** restocks inside the same transaction: a count item gains the quantity, a level item goes to plenty. **Uncheck** reverses it (count minus quantity, never below 0; level back to `previous_level`).
- **Hide checked** deletes the checked entries; they can no longer be unchecked. Entries checked off more than 24 hours ago are also deleted at the next check-off; that is what "a new shopping trip starts" means.
- `mark_empty` on an item calls `put_on_list` and returns the entry it created in `__metadata__.added_entry`, so the inventory's undo can remove exactly that entry.
- Entries die with their item (`on_delete: :delete`).
- **Live sync:** both resources publish every create, update and destroy to the topic `kitchen:changed` through `Ash.Notifier.PubSub` on `KuraWeb.Endpoint`. LiveViews subscribe and simply reload their data; `KuraWeb.LiveListCount` does the same for the open-entry badge in the tab bar.

## Consequences
- Two phones adding the same item at the same instant could create two open entries (no database constraint). Acceptable for two users.
- Reloading on every change is simple but not minimal; fine at this size.
- Offline check-off (milestone 5) must replay `check_off` against the server and cope with entries that were hidden or removed meanwhile.
