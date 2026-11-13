# Feedback

Things noticed while using the deployed app that should be different. Entries are collected here and worked on as a whole. Mark an entry done (`[x]`) once it is fixed.

## Open

_Nothing open._

## Done

- [x] The phones kept getting signed out, also after the remember-me cookie was read back (2026-11-08). A session token that had run out blocked the cookie, "Remember me" was unticked by default, and the cookie was never renewed. Fixed in ADR 0015.
- [x] The stock tracking option "level" should be the default when adding an item (was "count"). Since 2026-11-08 the default is "none" (items without stock, ADR 0013).
- [x] "None" (no stock) should be the default tracking when adding an item.
- [x] Adding a newly bought item should be doable from the keyboard on a laptop: type the name into the search bar and press Enter to add it, instead of clicking "Add new", so adding a bunch of things is faster. Enter does the same as clicking "Add": it opens the add form (level by default) so tracking can be changed before adding; an existing name does nothing.
- [x] When adding an item, the current stock should be settable right away (count number or level) instead of only afterwards.
- [x] Mobile: inventory cards ran past the right screen edge when an item name was long (grid column grew to the unwrapped name). Fixed with `grid-cols-1` on the inventory and shopping list grids.
- [x] Navigating between the tabs in the installed PWA showed the browser controls. iOS saves the app with the page URL you are on, and `/` only redirected to `/shopping-list`, so the install ended up scoped to one path. The shopping list now lives at `/` itself; `/shopping-list` redirects there for existing shortcuts. The app has to be removed from the Home Screen and added again from `/` after deploying.
- [x] Inventory cards: no icon, one compact row, one combined stock control (Plenty / Low / Empty selector, or a count stepper with a separate Empty button; stepping to 0 also marks the item empty), no subtitle. Tap the name to edit. The offline inventory matches.
- [x] Icons removed everywhere: the emoji field and database column, the shopping list icons and first-letter tiles, and the offline copies.
- [x] Tapping the name of an expanded inventory card closes it again.
