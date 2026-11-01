# 0011. Items live in locations, stock stays per item

- Status: Accepted
- Date: 2026-11-01

## Context
The inventory check (milestone 9) walks all items stalest first. It works better place by place ("what is still in this drawer?"), and "where are the walnuts?" should be answerable. The same item can live in more than one place, for example a spare pack in the freezer next to the one in the cupboard.

## Decision
- `Kura.Inventory.Location` is a shared, user-extendable list with a unique, case-insensitive name, like tags (ADR 0010). It has no sort position: the lists are ordered by name, ignoring case, because nothing lets a person reorder them.
- `Kura.Inventory.ItemLocation` joins items to locations (many-to-many). Deleting an item or a location deletes its join rows, nothing else.
- **Stock stays per item.** A location only says where to look; there is no amount per place (that would change ADR 0005).
- **Locations are not part of an item's identity.** Identity stays name plus tags (ADR 0010). Items are changed through `location_ids` on the create and update actions, which replace the set (`manage_relationship` with `:append_and_remove`); an update without `location_ids` leaves them alone.
- Search matches when every word is part of the name, a tag or a location. The inventory shows an item's places under its name only while a search is active.
- The check is scoped: `/inventory/check` is a picker of places (with item counts), plus "not placed yet" and "everything"; `/inventory/check/:scope` walks one scope, where the scope is a location id, `unplaced` or `all`. The items come from the read actions `to_check_at`, `to_check_unplaced` and `to_check`, all stalest first.
- On a card in a place, the other places of the item are named ("Also in Cupboard 2, count what is there too"). Confirming or changing the stock makes the item fresh everywhere, so in the other place it moves to the back of the list. "Not here anymore" removes only that place from the item.
- Locations have a page behind the three-dots More menu, next to Tags. The item form picks them with the same chip picker as tags.

## Consequences
- Existing items start unplaced; nothing is migrated.
- If an item is physically in two places, the person counts both and enters one total. The app cannot tell which pack is where.
- The offline copy and the label export do not know about locations.
- A tree of locations (a cupboard containing drawers) is possible later with a nullable `parent_id`; nothing here prevents it.
