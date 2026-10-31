# MVP

Goal: never again be in a store unsure whether something is at home, and keep one shared shopping list without retyping items.

## In scope

### Accounts
- Username/password login for two users who share one household's data.
- No public registration; accounts are created by the owner.

### Items (the permanent catalogue)
- Create, rename and delete items. Items persist permanently, also when empty.
- Each item has an optional emoji shown as its icon (items without one show their first letter) and a tracking type:
  - **count**: a number; 0 is empty.
  - **level**: plenty / low / empty.

### Stock
- View the full inventory, with the current stock of each item.
- Adjust stock (set a count, set a level).
- **Mark empty** in one tap; this adds the item to the shopping list.

### Shopping list
- Entries have an item and a quantity.
- Add entries manually, from the catalogue or by creating a new item on the spot; edit quantity; remove entries.
- **Check off** an entry: the item is restocked (count: add the quantity; level: set to plenty) and the entry leaves the open list.
- **Undo a check-off**: checked-off entries stay visible in a "checked off" section; unchecking one reverses its restock (count: subtract the quantity again; level: restore the previous level) and returns it to the open list.
- Checked-off entries stay in the "checked off" section until the next shopping trip starts or the user clears them manually. A **Hide checked items** action clears the section; hidden entries are no longer undoable.
- Both users see the same list; changes show up on the other phone without a reload.

### PWA and offline
- Installable on both phones.
- Inventory and shopping list readable without signal.
- Checking off entries works without signal and syncs when the connection returns (see ADR 0003).

## Out of scope (see roadmap)
Offline editing beyond check-off, recipes and meal planning, barcode scanning, prices, expiry dates, categories or aisle sorting, automatic low-stock thresholds for counts, multiple households, public registration.

## Open questions
- Is a count item automatically "low" at some threshold, or only empty at 0? (MVP: only empty at 0.)
- What exactly starts a "shopping trip"? (Proposal: the first check-off after the previous trip's entries were hidden or after a day has passed; to be settled when building milestone 4.)
