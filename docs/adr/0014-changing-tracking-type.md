# 0014. The tracking type of an item can be changed

- Status: Accepted
- Date: 2026-11-08

## Context
ADR 0005 fixed the tracking type at creation: changing it meant deleting and recreating the item. Since tags (ADR 0010), places (ADR 0011) and items without stock (ADR 0013), recreating loses more and is needed more often: existing items that turn out to be shopping-list-only should become None, and an item may move from a level to a count or back.

## Decision
- The primary `update` action accepts `tracking`, `stock_count` and `stock_level`. One change, `SwitchTracking`, handles them:
  - Same tracking type: stock values given to the update are dropped. Stock keeps changing only through the stock actions.
  - New type: the stock given is used; without it the old stock is carried over by `Item.converted_stock/2` (empty stays empty, any other stock becomes a count of 1 or plenty, none starts like a new item). Then `NormalizeStock` clears the other field (and auto-replenish for None) and `TouchStockChecked` stamps the item, since its stock changed.
- The item form shows the None / Level / Count selector for existing items too. The starting stock control appears only when a different type is picked, prefilled with `converted_stock/2`; otherwise stock is still changed in the list.
- The inventory drops an item's Undo bar when the item changes its type (the remembered stock belongs to the old type), and a check walk drops an item that switched to None.

## Consequences
- Supersedes the "fixed at creation" rule of ADR 0005 and the matching consequence of ADR 0013.
- Shopping entries are left as they are. Unchecking an entry that was checked off before the switch reverses the restock by the new type's rules: a count item loses the quantity, a level item without a remembered level stays as it is. Rare enough to accept.
