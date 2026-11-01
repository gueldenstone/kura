# Locations (design notes, not yet scheduled)

Status: exploring. Nothing is decided and nothing is built. Not part of the MVP; see the roadmap ideas. Turn the decisions below into an ADR when the work starts.

## Why
The inventory check (milestone 9) walks all items stalest first. It would work better cupboard by cupboard ("what is still in this drawer?"), and "where are the walnuts?" would be answerable from the inventory.

## The kitchen
Two bigger cupboards with drawers, a fridge, a freezer, a spice cupboard and some open rolling carts for sauces.

## Granularity rule (proposed)
A location is the smallest place you would open and look through in one go: a drawer, a cupboard shelf, the fridge, the freezer, the spice cupboard, one rack of a cart. The check goes location by location, so one location is one look.

## Model (proposed, not decided)
- `Location` resource: name and a sort position.
- Items get a location. Existing items start unplaced; the check can offer "Unplaced" as its own stop.
- The list is flat to start with (names such as "Left cupboard, drawer 2"). A nullable `parent_id` can be added later to group drawers under a cupboard without breaking anything.

## What it would change
- Check: pick a location, or go through them in order, and see only its items.
- Inventory: show and set where an item lives, filter by location, and show the location in search results.

## Open question
The same item can live in more than one place (for example a spare pack in the freezer next to the one in the cupboard). That rules out a single `location_id` on the item. Candidates to compare when this is picked up:
- A join between items and locations (an item has several places), possibly with a stock amount per place. This changes the stock model of ADR 0005, since stock is per item today.
- An item with one primary location, and "spare" entries as separate items.

Decide this before building anything: it is the hard-to-reverse part.
