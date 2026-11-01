# QR codes on containers (specification, not yet built)

Status: specified in conversation with the owner on 2026-11-01, then put on hold by the owner the same day (see the roadmap). Not built. The label export is being tweaked by the owner first; the `Link` column below depends on its final shape. Turn the model decision (the item code) into an ADR when work starts.

## Why
Standing at the fridge or a cupboard with a jar in hand, the owner wants to scan something in real life and update that item in the app within a few taps, without searching for it.

## What gets a code
Items, not locations. The codes go on the containers: jars and deli containers. Not on cupboards or shelves. (A code on a cupboard that opens its check is a possible follow-up once locations exist, see `docs/locations.md`.)

## The pieces
1. **A short code per item.**
   - Six characters from an alphabet without look-alike characters (no 0/O, 1/l/I), unique, assigned when the item is created and never changed, so a reprinted label carries the same code.
   - Existing items get theirs in the migration.
   - Reason for a short code: containers get small labels (about 12mm tape on a PT-P710BT, 180 dpi). The link `https://<host>/i/ab12cd` fits a QR of about 29x29 modules, a full UUID link needs about 37x37, which gets too fine for that printer at that size.
   - The host comes from the endpoint's configured URL, so links are right in production and in development.
2. **A `Link` column in the label export.** Next to the `Label` column, one link per item. In Brother's software a QR code object is bound to that column, so every printed label carries its own code. The app does not draw QR codes itself. I believe P-touch Editor can bind a barcode object to a column of an imported CSV, but that was not verified for the owner's software: test with one label first.
3. **The page behind the link, `/i/:code`.** One thumb-sized screen with:
   - the item's name and tags (and, later, its locations);
   - the usual stock control, and Mark empty with the same rules as the inventory (auto-replenish items go on the list, others get the Add to list offer in the undo bar);
   - a marker when the item is on the shopping list;
   - an Edit button that opens the item form (`ItemFormComponent`) as a sheet.
   It requires a signed-in user. An unknown code says so and links to the inventory. Everything on it is built from existing pieces (`stock_control`, `item_title`, the undo bar, the item form).
4. **Two ways to reach the page, both wanted:**
   - **The phone's camera app**: scan, tap the link. The link opens either the installed PWA or the browser, depending on the platform: on iPhone it opens in Safari (a different storage than the installed app, so the owner logs in there once); on Android an installed PWA can capture it. The app cannot control this, it can only make the page work in both.
   - **A Scan button inside the app**: opens the camera, decodes the code and navigates to the same page, so the owner stays in the app and its session. The decoder has to be bundled into `app.js` (only the app bundles are allowed, no external scripts). The browser's `BarcodeDetector` is not available in Safari, so a bundled JavaScript decoder is needed. Camera permission is asked for on first use. Where the button lives (the More menu, the header of the inventory, or a floating button) is up to the builder; it must be reachable with one thumb.

## Out of scope
- Drawing or printing QR codes from the app.
- Scanning offline, or any offline use of the page.
- Codes for locations, shopping list entries or tags.
- Barcodes of products (a different feature: scanning a shop barcode to find or create an item).

## Notes for the builder
- `Item` gets an attribute `code` with a unique identity. Generate it in the create action and make the retry on collision cheap (31^6 combinations is plenty for one household).
- A route like `live "/i/:code", ItemLive` in the authenticated live session; the quick page can reuse `InventoryLive`'s stock events or become its own LiveView sharing the pieces. Prefer sharing code over copying it.
- Remember the lessons from the item form: a button's own `value` hides a `phx-value-value` in a real browser, and a component that reports to its page through a message needs the tests to wait for the page (`render(view)`).
- The label export (`Kura.Inventory.LabelExport`) writes a single `Label` column: the name followed by the tags worth printing (see the Label export section of `docs/mvp.md`). Add `Link` there once the owner has finished tweaking it; `LabelExport.csv/2` takes the selected items and the whole inventory.
