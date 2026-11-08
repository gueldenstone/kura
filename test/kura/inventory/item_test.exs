defmodule Kura.Inventory.ItemTest do
  use Kura.DataCase

  alias Kura.Inventory

  setup do
    user =
      Kura.Accounts.create_user!(%{username: "lukas", password: "correct horse battery"},
        authorize?: false
      )

    %{actor: user}
  end

  defp apples(actor, attrs \\ %{}) do
    Inventory.create_item!(Map.merge(%{name: "Apples", tracking: :count, usual_amount: 6}, attrs),
      actor: actor
    )
  end

  defp walnuts(actor, attrs \\ %{}) do
    Inventory.create_item!(Map.merge(%{name: "Walnuts", tracking: :level}, attrs), actor: actor)
  end

  describe "create_item/2" do
    test "a count item starts with a count of 1 and no level", %{actor: actor} do
      item = apples(actor)

      assert item.tracking == :count
      assert item.stock_count == 1
      assert item.stock_level == nil
      assert item.usual_amount == 6
    end

    test "a level item starts at plenty with no count and a usual amount of 1", %{actor: actor} do
      item = walnuts(actor)

      assert item.tracking == :level
      assert item.stock_level == :plenty
      assert item.stock_count == nil
      assert item.usual_amount == 1
    end

    test "keeps the initial stock that was given", %{actor: actor} do
      assert apples(actor, %{stock_count: 4}).stock_count == 4
      assert walnuts(actor, %{stock_level: :low}).stock_level == :low
    end

    test "ignores stock of the other tracking type", %{actor: actor} do
      item = apples(actor, %{stock_level: :low})

      assert item.stock_level == nil
    end

    test "rejects a blank name", %{actor: actor} do
      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.create_item(%{name: "   ", tracking: :count}, actor: actor)
    end

    test "rejects a name that exists, ignoring case", %{actor: actor} do
      walnuts(actor)

      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.create_item(%{name: "walnuts", tracking: :count}, actor: actor)
    end

    test "rejects a usual amount below 1", %{actor: actor} do
      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.create_item(%{name: "Rice", tracking: :count, usual_amount: 0},
                 actor: actor
               )
    end

    test "rejects a negative count", %{actor: actor} do
      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.create_item(%{name: "Rice", tracking: :count, stock_count: -1},
                 actor: actor
               )
    end
  end

  describe "changing stock" do
    test "change_item_count adds and subtracts", %{actor: actor} do
      item = apples(actor, %{stock_count: 3})

      assert Inventory.change_item_count!(item, 2, actor: actor).stock_count == 5
      assert Inventory.change_item_count!(item, -1, actor: actor).stock_count == 2
    end

    test "change_item_count never goes below zero", %{actor: actor} do
      item = apples(actor, %{stock_count: 1})

      assert Inventory.change_item_count!(item, -5, actor: actor).stock_count == 0
    end

    test "set_item_level sets the level", %{actor: actor} do
      assert Inventory.set_item_level!(walnuts(actor), :low, actor: actor).stock_level == :low
    end

    test "count changes are rejected for level items and vice versa", %{actor: actor} do
      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.change_item_count(walnuts(actor), 1, actor: actor)

      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.set_item_level(apples(actor), :low, actor: actor)
    end

    test "set_item_count sets an exact count", %{actor: actor} do
      assert Inventory.set_item_count!(apples(actor), 9, actor: actor).stock_count == 9
    end
  end

  describe "auto_replenish" do
    test "is off for new items unless asked for", %{actor: actor} do
      refute apples(actor).auto_replenish
      assert walnuts(actor, %{auto_replenish: true}).auto_replenish
    end

    test "can be changed on an existing item", %{actor: actor} do
      item = Inventory.update_item!(apples(actor), %{auto_replenish: true}, actor: actor)

      assert item.auto_replenish
    end
  end

  describe "stock_checked_at" do
    # Pushes the date into the past so that a change visibly moves it forward.
    defp backdate(item, actor, days \\ 30) do
      past = DateTime.add(DateTime.utc_now(), -days, :day)

      item
      |> Ash.Changeset.for_update(:update, %{}, actor: actor)
      |> Ash.Changeset.force_change_attribute(:stock_checked_at, past)
      |> Ash.update!()
    end

    defp touched?(item, actor, change) do
      old = backdate(item, actor)
      new = change.(old)
      DateTime.compare(new.stock_checked_at, old.stock_checked_at) == :gt
    end

    test "starts out as now", %{actor: actor} do
      assert DateTime.diff(DateTime.utc_now(), apples(actor).stock_checked_at, :second) < 5
    end

    test "moves forward when the stock changes or is confirmed", %{actor: actor} do
      assert touched?(apples(actor), actor, &Inventory.change_item_count!(&1, 2, actor: actor))

      assert touched?(
               apples(actor, %{name: "A2"}),
               actor,
               &Inventory.set_item_count!(&1, 9, actor: actor)
             )

      assert touched?(walnuts(actor), actor, &Inventory.set_item_level!(&1, :low, actor: actor))

      assert touched?(
               walnuts(actor, %{name: "W2"}),
               actor,
               &Inventory.mark_item_empty!(&1, actor: actor)
             )

      assert touched?(
               apples(actor, %{name: "A3"}),
               actor,
               &Inventory.confirm_item_stock!(&1, actor: actor)
             )
    end

    test "stays put when only the name changes", %{actor: actor} do
      refute touched?(
               apples(actor),
               actor,
               &Inventory.update_item!(&1, %{name: "Pears"}, actor: actor)
             )
    end

    test "list_items_to_check puts the longest unchecked first", %{actor: actor} do
      backdate(apples(actor, %{name: "Zucchini"}), actor, 30)
      walnuts(actor, %{name: "Almonds"})
      backdate(walnuts(actor, %{name: "Mint"}), actor, 60)

      names = Enum.map(Inventory.list_items_to_check!(actor: actor), &to_string(&1.name))

      assert names == ["Mint", "Zucchini", "Almonds"]
    end
  end

  describe "mark_item_empty/2" do
    test "sets a count item to 0", %{actor: actor} do
      item = Inventory.mark_item_empty!(apples(actor, %{stock_count: 4}), actor: actor)

      assert item.stock_count == 0
    end

    test "sets a level item to empty", %{actor: actor} do
      item = Inventory.mark_item_empty!(walnuts(actor), actor: actor)

      assert item.stock_level == :empty
    end
  end

  describe "the empty? calculation" do
    test "is true for a count of 0 and a level of empty only", %{actor: actor} do
      load = fn item -> Ash.load!(item, :empty?, actor: actor).empty? end

      refute load.(apples(actor, %{stock_count: 2}))
      assert load.(apples(actor, %{name: "Pears", stock_count: 0}))
      refute load.(walnuts(actor, %{stock_level: :low}))
      assert load.(walnuts(actor, %{name: "Almonds", stock_level: :empty}))
    end
  end

  describe "search_items/2" do
    test "returns all items by name when the query is blank", %{actor: actor} do
      walnuts(actor)
      apples(actor)

      assert actor
             |> then(&Inventory.search_items!("", actor: &1))
             |> Enum.map(&to_string(&1.name)) ==
               ["Apples", "Walnuts"]
    end

    test "matches part of the name, ignoring case", %{actor: actor} do
      walnuts(actor)
      apples(actor)

      assert Inventory.search_items!("ALN", actor: actor) |> Enum.map(&to_string(&1.name)) == [
               "Walnuts"
             ]

      assert Inventory.search_items!("zzz", actor: actor) == []
    end
  end

  describe "updating and deleting" do
    test "update_item changes name and usual amount", %{actor: actor} do
      item =
        Inventory.update_item!(apples(actor), %{name: "Green apples", usual_amount: 4},
          actor: actor
        )

      assert to_string(item.name) == "Green apples"
      assert item.usual_amount == 4
      assert item.tracking == :count
    end

    test "delete_item removes the item", %{actor: actor} do
      item = apples(actor)
      :ok = Inventory.delete_item(item, actor: actor)

      assert Inventory.search_items!("", actor: actor) == []
    end
  end

  describe "authorization" do
    test "without a signed-in user nothing is visible and nothing can be changed", %{actor: actor} do
      apples(actor)

      assert Inventory.search_items!("") == []

      assert {:error, %Ash.Error.Forbidden{}} =
               Inventory.create_item(%{name: "Rice", tracking: :count})
    end
  end

  describe "items without stock" do
    defp candles(actor, attrs \\ %{}) do
      Inventory.create_item!(Map.merge(%{name: "Candles", tracking: :none}, attrs), actor: actor)
    end

    test "keep no stock and do not auto-replenish, whatever was given", %{actor: actor} do
      item = candles(actor, %{stock_count: 3, stock_level: :low, auto_replenish: true})

      assert item.tracking == :none
      assert item.stock_count == nil
      assert item.stock_level == nil
      assert item.auto_replenish == false
    end

    test "are never empty and cannot be marked empty or given a stock", %{actor: actor} do
      item = candles(actor)

      assert Ash.load!(item, :empty?, actor: actor).empty? == false
      assert {:error, _} = Inventory.mark_item_empty(item, actor: actor)
      assert {:error, _} = Inventory.change_item_count(item, 1, actor: actor)
      assert {:error, _} = Inventory.set_item_level(item, :plenty, actor: actor)
    end

    test "are left out of the inventory check", %{actor: actor} do
      shelf = Inventory.create_location!(%{name: "Shelf"}, actor: actor)
      candles(actor, %{location_ids: [shelf.id]})
      candles(actor, %{name: "Foil"})

      rice =
        Inventory.create_item!(%{name: "Rice", tracking: :level, location_ids: [shelf.id]},
          actor: actor
        )

      assert Enum.map(Inventory.list_items_to_check!(actor: actor), & &1.id) == [rice.id]

      assert Enum.map(Inventory.list_items_to_check_at!(shelf.id, actor: actor), & &1.id) == [
               rice.id
             ]

      assert Inventory.list_items_to_check_unplaced!(actor: actor) == []

      [shelf] = Inventory.list_locations!(actor: actor, load: [:stock_item_count])
      assert {shelf.item_count, shelf.stock_item_count} == {2, 1}
    end
  end

  describe "changing the tracking type" do
    defp switch(item, attrs, actor), do: Inventory.update_item!(item, attrs, actor: actor)

    test "carries the stock over: empty stays empty, anything else is 1 or plenty", %{
      actor: actor
    } do
      assert %{stock_level: :plenty, stock_count: nil} =
               switch(apples(actor, %{stock_count: 3}), %{tracking: :level}, actor)

      assert %{stock_level: :empty} =
               switch(apples(actor, %{name: "Pears", stock_count: 0}), %{tracking: :level}, actor)

      assert %{stock_count: 1, stock_level: nil} =
               switch(walnuts(actor, %{stock_level: :low}), %{tracking: :count}, actor)

      assert %{stock_count: 0} =
               switch(
                 walnuts(actor, %{name: "Pecans", stock_level: :empty}),
                 %{tracking: :count},
                 actor
               )
    end

    test "takes the stock given for the new type", %{actor: actor} do
      assert %{stock_count: 7} =
               switch(walnuts(actor), %{tracking: :count, stock_count: 7}, actor)

      candles = Inventory.create_item!(%{name: "Candles", tracking: :none}, actor: actor)
      assert %{stock_level: :low} = switch(candles, %{tracking: :level, stock_level: :low}, actor)
    end

    test "to none drops the stock and auto-replenish", %{actor: actor} do
      item = switch(apples(actor, %{auto_replenish: true}), %{tracking: :none}, actor)

      assert %{tracking: :none, stock_count: nil, stock_level: nil, auto_replenish: false} = item
    end

    test "counts as a stock change for the inventory check", %{actor: actor} do
      item =
        Ash.Seed.update!(walnuts(actor), %{stock_checked_at: ~U[2026-01-01 00:00:00.000000Z]})

      assert DateTime.compare(
               switch(item, %{tracking: :count}, actor).stock_checked_at,
               ~U[2026-01-01 00:00:00.000000Z]
             ) == :gt
    end

    test "without a new type the update leaves the stock and its date alone", %{actor: actor} do
      item =
        Ash.Seed.update!(apples(actor, %{stock_count: 3}), %{
          stock_checked_at: ~U[2026-01-01 00:00:00.000000Z]
        })

      item = switch(item, %{tracking: :count, stock_count: 9, name: "Red apples"}, actor)

      assert item.stock_count == 3
      assert item.stock_checked_at == ~U[2026-01-01 00:00:00.000000Z]
    end
  end
end
