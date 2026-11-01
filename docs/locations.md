# Locations (specification and notes on the build)

Status: built, milestone 11 of `docs/roadmap.md`; the model decision is ADR 0011 and the behaviour is described in `docs/mvp.md`. This file keeps the reasoning and the original specification.

Where the build differs from the specification below:
- Locations have **no sort position**. The lists are ordered by name, ignoring case; nothing in the app lets a person reorder them, so a position would have been unused.
- The check route is `/inventory/check` (picker) and `/inventory/check/:scope` (walk; the scope is a location id, `unplaced` or `all`).
- The picker for locations is the same `chip_picker` component as for tags; its events carry a `kind` ("tag" or "location").

## Why
The inventory check (milestone 9) walks all items stalest first. It works better cupboard by cupboard ("what is still in this drawer?"), and "where are the walnuts?" should be answerable from the inventory.

## The kitchen
Two bigger cupboards with drawers, a fridge, a freezer, a spice cupboard and some open rolling carts for sauces.

## Granularity rule
A location is the smallest place you would open and look through in one go: a drawer, a cupboard shelf, the fridge, the freezer, the spice cupboard, one rack of a cart. The check goes location by location, so one location is one look.

## Model
- `Location` resource: a unique, case-insensitive name. A shared list that both users extend, like tags (ADR 0010).
- `ItemLocation` joins items to locations (many-to-many). An item can live in several places, for example a spare pack in the freezer next to the one in the cupboard.
- **Stock stays per item.** Locations only say where to look; there is no amount per place. Per-place amounts would be a different and much larger model (it changes ADR 0005).
- Locations are separate from tags. Tags say what an item is and are part of its identity (ADR 0010); locations say where it lives and are not.
- Existing items start unplaced.
- Deleting a location takes it off its items; they do not collide with anything, because locations are not part of identity.

## Behaviour
### Locations page
Behind the three-dots More menu next to Tags. Lists the locations with their number of items; add, rename and delete (with a confirmation that says how many items lose the place). Locations are also created on the spot from the item form's picker.

### Item form
The same `ItemFormComponent` gets a second searchable picker for locations, built like the tag picker (chips for the chosen ones, search, tap to add, "Create" for a new name).

### The check
- The Check tab starts with a **picker**: every location with its item count, plus **Unplaced** (items without a location) and **Everything** (today's walk over all items).
- Choosing one walks only the items there, stalest first, with the existing card: stock control, Still right, Next, Edit, Delete, swipe left and right.
- **Hint for other places.** An item with other locations shows a line on its card, for example "Also in: Cupboard 2. Count what is there too, the stock is for the whole item." This is what makes the overall stock right when an item is in two places.
- **No double checking.** Confirming or changing an item's stock makes it fresh. In the check of its other location it moves to the back of the list (stalest first) and the card says the stock was last changed today, so it is recognised instead of recounted.
- **Not here anymore** on a card removes only that location from the item. If it was the last one, the item becomes unplaced.
- The route carries the chosen location, for example `/inventory/check` for the picker and `/inventory/check/:location` for the walk (final shape is up to the builder).

### Search and display
- Search matches words in the name, the tags and the locations, like it does for name and tags now.
- Inventory rows stay as compact as today. The locations of an item show as a third small line only while a search is active, since that is when the question is "where is it?".
- The shopping list, labels and the offline copy do not change. The offline copy cannot search by location.

## Out of scope
- Amounts per location.
- A tree of locations (cupboard containing drawers). A nullable `parent_id` can be added later without breaking anything.
- Offline editing or checking by location.

## Notes for the builder
- Reuse the tag picker: generalise `KuraWeb.InventoryComponents.tag_picker/1` into a picker that takes the list, the chosen ids and the event names instead of copying it.
- The check currently loads all items stalest first (`Item.to_check`); it needs a variant that takes a location (or none, or "unplaced").
- The Add-an-item search prompt does not need to know about locations.
- Remember the two lessons from the item form: a button's own `value` hides a `phx-value-value` in a real browser (use another name), and a component that tells its page "saved" through a message needs the tests to wait for the page (`render(view)`).
