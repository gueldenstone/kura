# 0010. Items are told apart by name and tags

- Status: Accepted
- Date: 2026-11-01

## Context
The same ingredient comes in forms: ground cumin and whole cumin, green and black cardamom, chilli flakes from different places. These ended up in the item name ("Gemahlener Kreuzkümmel"), which made names too long for a phone row and sorted the forms of one ingredient apart. Item names were unique on their own (ADR 0005), so "Kreuzkümmel" could exist only once.

## Decision
- `Kura.Inventory.Tag` is a shared, user-extendable list with a unique, case-insensitive name. `Kura.Inventory.ItemTag` joins items to tags (many-to-many); deleting an item or a tag deletes its join rows.
- An item's **identity is its name plus its set of tags**. SQLite has no set type, so the item stores `tag_key`, the sorted tag ids joined into one string (empty without tags), and the unique identity is `[:name, :tag_key]` with `pre_check?`. This replaces the unique name identity of ADR 0005. `Item.Changes.SetTags` recomputes the key whenever the `tag_ids` argument of create or update is given, in the same action that replaces the relationship. An update without `tag_ids` leaves tags and key alone.
- Renaming a tag changes how items display, never their identity, because the key holds ids.
- Deleting a tag takes it off its items and rewrites their `tag_key`. If that would make two items identical, the delete is refused and the error names the items (`Tag.Changes.RemoveFromItems`).
- The tags of an item are shown as a small line under its name, alphabetically, joined with ` · `. The label (name and tags, as one string, `Item.label/1`) is what the label export prints and what the offline copy shows as the name.
- Search matches when every word of the query is part of the name or of a tag. The inventory orders items by name, then by tag line, ignoring case; SQLite alone would sort capital letters first.
- Typing "cumin ground" in the inventory search offers to add "cumin" with the tag "ground": words equal to a tag name become tags.
- The tags page lives behind a "More" entry (three dots) in the bottom bar, so the bar keeps its three main tabs.

## Consequences
- Existing items keep their long names and an empty `tag_key`; nothing is migrated automatically. Splitting "Gemahlener Kreuzkümmel" into a name and a tag is manual.
- The shopping list's own "new item" form has no tag picker; items created there are untagged and can be tagged in the inventory.
- Two phones changing the tags of items at the same moment could briefly disagree about identity; the unique index still guards the database.
- Locations (`docs/locations.md`) may want the same join pattern.
