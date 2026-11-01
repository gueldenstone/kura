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

### Tags
- Tags are a shared list (for example ground, whole, Usbekistan) that both users extend. An item can have any number of tags. Name plus the set of tags must be unique: "Cumin" tagged ground and "Cumin" tagged whole are two items.
- The inventory, shopping list and check cards show the tags as a small grey line under the name. Items with the same name are ordered by their tags. Search matches the name or any tag, word by word.
- Tags are picked in the item's add and edit forms with a searchable picker; typing a new name offers to create the tag on the spot, and Enter takes the only match. Typing "cumin ground" in the inventory search offers to add "cumin" with the tag "ground".
- The **Tags** page (`/tags`, behind the three-dots **More** entry of the bottom bar) lists the tags with their number of items and lets you add, rename and delete them. Deleting a tag takes it off its items; it is refused when that would make two items identical.
- The label export prints the name and the tags of each selected item on one line.

### Stock
- View the full inventory, with the current stock of each item.
- Adjust stock (set a count, set a level).
- **Mark empty** in one tap. Items with **auto-replenish** on (stock such as spices, pasta, canned goods) are added to the shopping list with their usual amount, unless already on it; the Undo bar takes the entry off again. For other items (one-offs, auto-replenish is off by default) the item is only marked empty and the Undo bar also offers **Add to list**; ignoring it leaves the item off the list. The bar slides away by itself after 10 seconds (restarted by Add to list).
- Each inventory row is one line: the name (tap to edit) and one stock control. Level items use a Plenty / Low / Empty selector, count items a minus / number / plus stepper next to a separate Empty button; stepping a count down to 0 also marks it empty.
- Items that are on the list carry a small cart marker in the inventory.

### Inventory check
- The **Check** tab (`/inventory/check`, the third tab of the bar) is a walk through all items, one card at a time, the ones whose stock was changed or confirmed longest ago first. Each card shows the item, how long ago its stock last changed, the normal stock control, and a progress count ("4 of 23").
- **Still right** confirms the stock and moves on. **Next** (or a swipe left) moves on without confirming; a swipe right or the back button goes to the previous card. **Delete** removes the item after a confirmation. Emptying an item behaves as in the list, including the Add to list offer.
- The end of the walk shows "All checked" with a Done button back to the inventory. Leaving through another tab ends it early; nothing done so far is lost.
- Online only. Every stock change and every confirmation updates the item's last-checked date.

### Label export
- **Select** in the inventory switches to select mode: every row gets a checkbox in place of its stock control, search keeps working and the ticks stay, **Select all** ticks every visible item and **Select none** clears all ticks.
- **Export labels** downloads `labels.csv` with a `Label` header and one item name per line, ordered by name, for import into label printing software (Brother P-touch). Online only.

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
