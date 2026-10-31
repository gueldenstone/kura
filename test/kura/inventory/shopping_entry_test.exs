defmodule Kura.Inventory.ShoppingEntryTest do
  use Kura.DataCase

  alias Kura.Inventory
  alias Kura.Inventory.ShoppingList

  setup do
    user =
      Kura.Accounts.create_user!(%{username: "lukas", password: "correct horse battery"},
        authorize?: false
      )

    %{actor: user}
  end

  defp apples(actor, attrs \\ %{}) do
    Inventory.create_item!(
      Map.merge(%{name: "Apples", tracking: :count, usual_amount: 6, stock_count: 1}, attrs),
      actor: actor
    )
  end

  defp walnuts(actor, attrs \\ %{}) do
    Inventory.create_item!(
      Map.merge(%{name: "Walnuts", tracking: :level, stock_level: :low}, attrs),
      actor: actor
    )
  end

  defp add(actor, item, attrs \\ %{}) do
    Inventory.add_entry!(Map.merge(%{item_id: item.id}, attrs), actor: actor)
  end

  defp stock(actor, item), do: Inventory.get_item!(item.id, actor: actor)

  describe "add_entry/2" do
    test "defaults the quantity to the item's usual amount", %{actor: actor} do
      assert add(actor, apples(actor)).quantity == 6
    end

    test "takes an explicit quantity", %{actor: actor} do
      assert add(actor, apples(actor), %{quantity: 2}).quantity == 2
    end

    test "rejects a quantity below 1", %{actor: actor} do
      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.add_entry(%{item_id: apples(actor).id, quantity: 0}, actor: actor)
    end

    test "rejects a second open entry for the same item", %{actor: actor} do
      item = apples(actor)
      add(actor, item)

      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.add_entry(%{item_id: item.id}, actor: actor)
    end

    test "allows a new open entry while the old one sits in the cart", %{actor: actor} do
      item = apples(actor)
      Inventory.check_off_entry!(add(actor, item), actor: actor)

      assert %{checked_at: nil} = add(actor, item)
    end
  end

  describe "change_entry_quantity/3" do
    test "adds and subtracts", %{actor: actor} do
      entry = add(actor, apples(actor), %{quantity: 3})

      assert Inventory.change_entry_quantity!(entry, 2, actor: actor).quantity == 5
      assert Inventory.change_entry_quantity!(entry, -1, actor: actor).quantity == 2
    end

    test "never goes below 1", %{actor: actor} do
      entry = add(actor, apples(actor), %{quantity: 1})

      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.change_entry_quantity(entry, -1, actor: actor)
    end
  end

  describe "check_off_entry/2" do
    test "adds the quantity to a count item", %{actor: actor} do
      item = apples(actor, %{stock_count: 1})
      entry = Inventory.check_off_entry!(add(actor, item, %{quantity: 4}), actor: actor)

      assert entry.checked_at
      assert stock(actor, item).stock_count == 5
    end

    test "sets a level item to plenty and remembers the level it had", %{actor: actor} do
      item = walnuts(actor, %{stock_level: :low})
      entry = Inventory.check_off_entry!(add(actor, item), actor: actor)

      assert stock(actor, item).stock_level == :plenty
      assert entry.previous_level == :low
    end

    test "starts a new trip: entries checked off over a day ago are cleared", %{actor: actor} do
      old = Inventory.check_off_entry!(add(actor, apples(actor)), actor: actor)
      Ash.Seed.update!(old, %{checked_at: DateTime.add(DateTime.utc_now(), -25, :hour)})
      recent = Inventory.check_off_entry!(add(actor, walnuts(actor)), actor: actor)

      assert Enum.map(Inventory.list_checked_entries!(actor: actor), & &1.id) == [recent.id]
    end

    test "keeps entries checked off earlier today", %{actor: actor} do
      first = Inventory.check_off_entry!(add(actor, apples(actor)), actor: actor)
      second = Inventory.check_off_entry!(add(actor, walnuts(actor)), actor: actor)

      assert Enum.sort(Enum.map(Inventory.list_checked_entries!(actor: actor), & &1.id)) ==
               Enum.sort([first.id, second.id])
    end

    test "cannot be done twice", %{actor: actor} do
      item = apples(actor)
      entry = Inventory.check_off_entry!(add(actor, item), actor: actor)

      assert {:error, %Ash.Error.Invalid{}} = Inventory.check_off_entry(entry, actor: actor)
      assert stock(actor, item).stock_count == 7
    end
  end

  describe "uncheck_entry/2" do
    test "takes the quantity off a count item again", %{actor: actor} do
      item = apples(actor, %{stock_count: 1})
      entry = Inventory.check_off_entry!(add(actor, item, %{quantity: 4}), actor: actor)

      entry = Inventory.uncheck_entry!(entry, actor: actor)

      assert entry.checked_at == nil
      assert stock(actor, item).stock_count == 1
    end

    test "never takes a count below zero", %{actor: actor} do
      item = apples(actor, %{stock_count: 1})
      entry = Inventory.check_off_entry!(add(actor, item, %{quantity: 4}), actor: actor)
      Inventory.set_item_count!(stock(actor, item), 2, actor: actor)

      Inventory.uncheck_entry!(entry, actor: actor)

      assert stock(actor, item).stock_count == 0
    end

    test "puts a level item back to the level it had", %{actor: actor} do
      item = walnuts(actor, %{stock_level: :low})
      entry = Inventory.check_off_entry!(add(actor, item), actor: actor)

      entry = Inventory.uncheck_entry!(entry, actor: actor)

      assert stock(actor, item).stock_level == :low
      assert entry.previous_level == nil
    end

    test "only works on a checked entry", %{actor: actor} do
      entry = add(actor, apples(actor))

      assert {:error, %Ash.Error.Invalid{}} = Inventory.uncheck_entry(entry, actor: actor)
    end
  end

  describe "listing" do
    test "open entries come by item name with the item loaded, checked ones apart", %{
      actor: actor
    } do
      walnut_entry = add(actor, walnuts(actor))
      apple_entry = add(actor, apples(actor))
      rice = Inventory.create_item!(%{name: "Rice", tracking: :level}, actor: actor)
      done = Inventory.check_off_entry!(add(actor, rice), actor: actor)

      open = Inventory.list_open_entries!(actor: actor)
      checked = Inventory.list_checked_entries!(actor: actor)

      assert Enum.map(open, & &1.id) == [apple_entry.id, walnut_entry.id]
      assert to_string(hd(open).item.name) == "Apples"
      assert Enum.map(checked, & &1.id) == [done.id]
    end

    test "nothing is visible without a signed-in user", %{actor: actor} do
      add(actor, apples(actor))

      assert Inventory.list_open_entries!() == []
    end
  end

  describe "ShoppingList.hide_checked/1" do
    test "removes checked entries and leaves open ones", %{actor: actor} do
      open = add(actor, apples(actor))
      done = Inventory.check_off_entry!(add(actor, walnuts(actor)), actor: actor)

      ShoppingList.hide_checked(actor)

      assert Enum.map(Inventory.list_open_entries!(actor: actor), & &1.id) == [open.id]
      assert Inventory.list_checked_entries!(actor: actor) == []
      assert {:error, _} = Ash.get(Inventory.ShoppingEntry, done.id, actor: actor)
    end
  end

  describe "ShoppingList.put_on_list/2" do
    test "creates an entry with the usual amount", %{actor: actor} do
      item = apples(actor)

      assert {:created, entry} = ShoppingList.put_on_list(item, actor)
      assert entry.quantity == 6
    end

    test "returns the existing open entry instead of adding a second", %{actor: actor} do
      item = apples(actor)
      {:created, first} = ShoppingList.put_on_list(item, actor)

      assert {:existing, entry} = ShoppingList.put_on_list(item, actor)
      assert entry.id == first.id
      assert length(Inventory.list_open_entries!(actor: actor)) == 1
    end
  end

  describe "mark_item_empty/2" do
    test "puts the item on the list with its usual amount", %{actor: actor} do
      item = apples(actor, %{stock_count: 3})

      marked = Inventory.mark_item_empty!(item, actor: actor)

      assert marked.stock_count == 0
      assert [entry] = Inventory.list_open_entries!(actor: actor)
      assert entry.item_id == item.id
      assert entry.quantity == 6
      assert marked.__metadata__.added_entry.id == entry.id
    end

    test "does not add a second entry when the item is already on the list", %{actor: actor} do
      item = walnuts(actor)
      existing = add(actor, item, %{quantity: 3})

      marked = Inventory.mark_item_empty!(item, actor: actor)

      assert [entry] = Inventory.list_open_entries!(actor: actor)
      assert entry.id == existing.id
      assert entry.quantity == 3
      assert marked.__metadata__.added_entry == nil
    end
  end

  describe "the on_list? calculation" do
    test "is true only while the item has an open entry", %{actor: actor} do
      item = apples(actor)
      on_list? = fn -> Ash.load!(stock(actor, item), :on_list?, actor: actor).on_list? end

      refute on_list?.()

      entry = add(actor, item)
      assert on_list?.()

      Inventory.check_off_entry!(entry, actor: actor)
      refute on_list?.()
    end
  end

  test "deleting an item removes its entries", %{actor: actor} do
    item = apples(actor)
    add(actor, item)

    :ok = Inventory.delete_item(item, actor: actor)

    assert Inventory.list_open_entries!(actor: actor) == []
  end
end
