# MVP

Goal: never again be in a store unsure whether something is at home, and keep one shared shopping list without retyping items.

## In scope

### Accounts
- Username/password login for two users who share one household's data.
- No public registration; accounts are created by the owner.

### Items (the permanent catalogue)
- Create, rename and delete items. Items persist permanently, also when empty.
- Each item has a name and a tracking type (items have no icon):
  - **count**: a number; 0 is empty.
  - **level**: plenty / low / empty.
- **One item form everywhere** (`KuraWeb.ItemFormComponent`): name, tags, stock (new items only: Level or Count with the starting stock), usual amount to buy as a stepper, an Auto-replenish switch, and Delete (existing items only). In the inventory it opens inline, in the row for an existing item and as a card above the list for a new one; from the shopping list's add prompt and from the **Edit** button on a check card it opens as a sheet over the page (Save and Cancel stay at the bottom, Escape closes). Added from the shopping list, the new item also goes on the list.

### Tags
- Tags are a shared list (for example ground, whole, Usbekistan) that both users extend. An item can have any number of tags. Name plus the set of tags must be unique: "Cumin" tagged ground and "Cumin" tagged whole are two items.
- The inventory, shopping list and check cards show the tags as a small grey line under the name. Items with the same name are ordered by their tags. Search matches the name or any tag, word by word.
- Tags are picked in the item's add and edit forms with a searchable picker; typing a new name offers to create the tag on the spot, and Enter takes the only match. Typing "cumin ground" in the inventory search offers to add "cumin" with the tag "ground".
- The **Tags** page (`/tags`, behind the three-dots **More** entry of the bottom bar) lists the tags with their number of items and lets you add, rename and delete them. Deleting a tag takes it off its items; it is refused when that would make two items identical.
- The label export writes the tags worth printing after the name in its `Label` column (see Label export).

### Stock
- View the full inventory, with the current stock of each item.
- Adjust stock (set a count, set a level).
- **Mark empty** in one tap. Items with **auto-replenish** on (stock such as spices, pasta, canned goods) are added to the shopping list with their usual amount, unless already on it; the Undo bar takes the entry off again. For other items (one-offs, auto-replenish is off by default) the item is only marked empty and the Undo bar also offers **Add to list**; ignoring it leaves the item off the list. The bar slides away by itself after 10 seconds (restarted by Add to list).
- Each inventory row is one line: the name (tap to edit) and one stock control. Level items use a Plenty / Low / Empty selector, count items a minus / number / plus stepper next to a separate Empty button; stepping a count down to 0 also marks it empty.
- Items that are on the list carry a small cart marker in the inventory.

### Locations
- Locations are a shared list (a drawer, a cupboard shelf, the fridge) that both users extend. An item can live in several places, or in none yet; the stock stays per item. Names are unique, ignoring case.
- The **Locations** page (`/locations`, behind the three-dots **More** entry, next to Tags) lists them with their number of items and lets you add, rename and delete them. Deleting takes the place off its items and nothing else.
- In the item form, **Where it lives** picks places with the same searchable chips as tags, and creates a new place on the spot.
- Search matches words in the name, the tags and the places. While a search is active, rows show the places of an item as a line with a pin under its name.

### Inventory check
- The **Check** tab (`/inventory/check`) starts with a picker: every place with its number of items, **Not placed yet** (items without a place) and **Everything** (all items). Choosing one walks it at `/inventory/check/:scope`.
- The walk is one card at a time, the items whose stock was changed or confirmed longest ago first. Each card shows the item, how long ago its stock last changed, the normal stock control, and a progress count ("4 of 23"). The place being checked is named under the title with a **Change place** link.
- When an item also lives somewhere else, its card says so: "Also in Cupboard 2. Count what is there too, the stock is for the whole item." Confirming or changing the stock makes the item fresh, so in its other place it moves to the back of the list and says its stock was changed today.
- **Not here anymore** (in a place's walk) removes just that place from the item and moves on; an item without any place becomes unplaced.
- **Still right** confirms the stock and moves on. **Next** (or a swipe left) moves on without confirming; a swipe right or the back button goes to the previous card. **Edit** opens the item form as a sheet. **Delete** removes the item after a confirmation. Emptying an item behaves as in the list, including the Add to list offer.
- The end of the walk shows "All checked" with a Done button back to the places. Leaving through another tab ends it early; nothing done so far is lost.
- Online only. Every stock change and every confirmation updates the item's last-checked date.

### Label export
- **Select** in the inventory switches to select mode: every row gets a checkbox in place of its stock control, search keeps working and the ticks stay, **Select all** ticks every visible item and **Select none** clears all ticks.
- **Export labels** downloads `labels.csv` with one column, `Label`: the item name followed by the tags worth printing, separated by spaces (for example `Paprika scharf`), one item per line ordered by name and then by those tags, for import into label printing software (Brother P-touch). Online only.
- **Which tags print:** a tag is exported only if its **Print on labels** switch (per tag, on by default, in the tag's card on the Tags page; a tag that is off shows "not printed" in the list) is on, and not every item in the inventory with the same name has it. So an item with a unique name prints no tags, and "ground" on both of two paprikas stays off while "hot" and "sweet" print. The comparison covers the whole inventory, not just the selected items. The app shows all tags everywhere else.

### Shopping list
- Entries have an item and a quantity.
- Add entries manually, from the catalogue or by creating a new item on the spot; edit quantity; remove entries.
- **Check off** an entry: the item is restocked (count: add the quantity; level: set to plenty) and the entry leaves the open list.
- **Undo a check-off**: checked-off entries stay visible in a "checked off" section; unchecking one reverses its restock (count: subtract the quantity again; level: restore the previous level) and returns it to the open list.
- Checked-off entries stay in the "In the cart" section until the next shopping trip starts (the first check-off after a day has passed) or the user taps **Hide checked**. Hidden entries are no longer undoable.
- The Shopping list tab shows how many entries are still open.
- Both users see the same list; changes show up on the other phone without a reload.

### PWA and offline
- Installable on both phones (home screen icon, no browser bars).
- Inventory and shopping list readable without signal.
- Checking off entries works without signal and syncs when the connection returns (see ADR 0003).

## Out of scope (see roadmap)
Offline editing beyond check-off, recipes and meal planning, barcode scanning, prices, expiry dates, categories or aisle sorting, automatic low-stock thresholds for counts, multiple households, public registration.

## Open questions
- Is a count item automatically "low" at some threshold, or only empty at 0? (MVP: only empty at 0.)
