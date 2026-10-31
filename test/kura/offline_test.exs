defmodule Kura.OfflineTest do
  use Kura.DataCase

  alias Kura.{Inventory, Offline}

  setup do
    user =
      Kura.Accounts.create_user!(%{username: "lukas", password: "correct horse battery"},
        authorize?: false
      )

    %{actor: user}
  end

  defp item(actor, attrs),
    do: Inventory.create_item!(Map.merge(%{tracking: :count}, attrs), actor: actor)

  defp on_list(actor, item, attrs \\ %{}),
    do: Inventory.add_entry!(Map.merge(%{item_id: item.id}, attrs), actor: actor)

  describe "snapshot/1" do
    test "describes the inventory and the shopping list in plain, JSON-friendly data", %{
      actor: actor
    } do
      apples = item(actor, %{name: "Apples", emoji: "🍎", stock_count: 0, usual_amount: 6})
      walnuts = item(actor, %{name: "Walnuts", tracking: :level, stock_level: :low})
      rice = item(actor, %{name: "Rice", tracking: :level})
      entry = on_list(actor, apples)
      done = Inventory.check_off_entry!(on_list(actor, rice), actor: actor)

      snapshot = Offline.snapshot(actor)

      assert {:ok, _, _} = DateTime.from_iso8601(snapshot.generated_at)

      assert [
               %{
                 name: "Apples",
                 emoji: "🍎",
                 tracking: "count",
                 stock_count: 0,
                 empty: true,
                 on_list: true
               },
               %{
                 name: "Rice",
                 emoji: nil,
                 tracking: "level",
                 stock_level: "plenty",
                 on_list: false
               },
               %{name: "Walnuts", tracking: "level", stock_level: "low", empty: false}
             ] =
               Enum.map(
                 snapshot.items,
                 &Map.take(&1, [
                   :name,
                   :emoji,
                   :tracking,
                   :stock_count,
                   :stock_level,
                   :empty,
                   :on_list
                 ])
               )

      assert [%{id: entry_id, item_id: apples_id, name: "Apples", emoji: "🍎", quantity: 6}] =
               snapshot.open

      assert entry_id == entry.id
      assert apples_id == apples.id
      assert [%{id: done_id, name: "Rice", quantity: 1}] = snapshot.checked
      assert done_id == done.id
      assert walnuts.id in Enum.map(snapshot.items, & &1.id)
      assert {:ok, _json} = Jason.encode(snapshot)
    end

    test "is empty when there is nothing yet", %{actor: actor} do
      assert %{items: [], open: [], checked: []} = Offline.snapshot(actor)
    end
  end

  describe "apply_changes/2" do
    test "checks off and unchecks entries through the real restock rules", %{actor: actor} do
      apples = item(actor, %{name: "Apples", stock_count: 1})
      entry = on_list(actor, apples, %{quantity: 4})

      Offline.apply_changes(actor, [%{"op" => "check", "entry_id" => entry.id}])
      assert Inventory.get_item!(apples.id, actor: actor).stock_count == 5

      Offline.apply_changes(actor, [%{"op" => "uncheck", "entry_id" => entry.id}])
      assert Inventory.get_item!(apples.id, actor: actor).stock_count == 1
    end

    test "applies changes in order", %{actor: actor} do
      apples = item(actor, %{name: "Apples", stock_count: 1})
      entry = on_list(actor, apples, %{quantity: 2})

      result =
        Offline.apply_changes(actor, [
          %{"op" => "check", "entry_id" => entry.id},
          %{"op" => "uncheck", "entry_id" => entry.id},
          %{"op" => "check", "entry_id" => entry.id}
        ])

      assert result == %{applied: 3, skipped: 0}
      assert Inventory.get_item!(apples.id, actor: actor).stock_count == 3
    end

    test "skips changes that no longer make sense", %{actor: actor} do
      apples = item(actor, %{name: "Apples", stock_count: 1})
      entry = on_list(actor, apples, %{quantity: 2})
      Inventory.check_off_entry!(entry, actor: actor)

      result =
        Offline.apply_changes(actor, [
          %{"op" => "check", "entry_id" => entry.id},
          %{"op" => "check", "entry_id" => Ash.UUID.generate()},
          %{"op" => "dance", "entry_id" => entry.id},
          %{"nonsense" => true}
        ])

      assert result == %{applied: 0, skipped: 4}
      assert Inventory.get_item!(apples.id, actor: actor).stock_count == 3
    end
  end
end
