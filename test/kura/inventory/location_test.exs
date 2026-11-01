defmodule Kura.Inventory.LocationTest do
  use Kura.DataCase

  alias Kura.Inventory

  setup do
    user =
      Kura.Accounts.create_user!(%{username: "lukas", password: "correct horse battery"},
        authorize?: false
      )

    %{actor: user}
  end

  defp location(actor, name), do: Inventory.create_location!(%{name: name}, actor: actor)

  defp item(actor, name, locations \\ []) do
    Inventory.create_item!(
      %{name: name, tracking: :level, location_ids: Enum.map(locations, & &1.id)},
      actor: actor
    )
  end

  defp place_names(item, actor) do
    item
    |> Ash.load!(:locations, actor: actor)
    |> Map.fetch!(:locations)
    |> Enum.map(&to_string(&1.name))
    |> Enum.sort()
  end

  test "location names are unique, ignoring case", %{actor: actor} do
    location(actor, "Fridge")

    assert {:error, _} = Inventory.create_location(%{name: "FRIDGE"}, actor: actor)
  end

  test "locations are listed ignoring case, with the number of items", %{actor: actor} do
    fridge = location(actor, "fridge")
    location(actor, "Cupboard")
    item(actor, "Tahini", [fridge])
    item(actor, "Butter", [fridge])

    assert [{"Cupboard", 0}, {"fridge", 2}] ==
             actor
             |> then(&Inventory.list_locations!(actor: &1))
             |> Enum.map(&{to_string(&1.name), &1.item_count})
  end

  describe "items and their locations" do
    test "an item can live in several places, and starts with none", %{actor: actor} do
      fridge = location(actor, "Fridge")
      cupboard = location(actor, "Cupboard")

      assert place_names(item(actor, "Rice"), actor) == []

      assert place_names(item(actor, "Tahini", [fridge, cupboard]), actor) == [
               "Cupboard",
               "Fridge"
             ]
    end

    test "locations can be changed, and an update without them leaves them alone", %{actor: actor} do
      fridge = location(actor, "Fridge")
      cupboard = location(actor, "Cupboard")
      tahini = item(actor, "Tahini", [fridge])

      moved = Inventory.update_item!(tahini, %{location_ids: [cupboard.id]}, actor: actor)
      assert place_names(moved, actor) == ["Cupboard"]

      renamed = Inventory.update_item!(moved, %{name: "Tahin"}, actor: actor)
      assert place_names(renamed, actor) == ["Cupboard"]

      cleared = Inventory.update_item!(renamed, %{location_ids: []}, actor: actor)
      assert place_names(cleared, actor) == []
    end

    test "locations do not make items different: the same name and tags is still refused", %{
      actor: actor
    } do
      fridge = location(actor, "Fridge")
      item(actor, "Tahini", [fridge])

      assert {:error, _} =
               Inventory.create_item(%{name: "Tahini", tracking: :level}, actor: actor)
    end

    test "renaming a location shows everywhere", %{actor: actor} do
      fridge = location(actor, "Fridge")
      tahini = item(actor, "Tahini", [fridge])

      Inventory.update_location!(fridge, %{name: "Kühlschrank"}, actor: actor)

      assert place_names(tahini, actor) == ["Kühlschrank"]
    end

    test "deleting a location takes it off its items and deletes nothing else", %{actor: actor} do
      fridge = location(actor, "Fridge")
      cupboard = location(actor, "Cupboard")
      tahini = item(actor, "Tahini", [fridge, cupboard])

      :ok = Inventory.delete_location(fridge, actor: actor)

      assert place_names(tahini, actor) == ["Cupboard"]
      assert {:ok, _} = Inventory.get_item(tahini.id, actor: actor)
    end

    test "one place can be removed from an item", %{actor: actor} do
      fridge = location(actor, "Fridge")
      cupboard = location(actor, "Cupboard")
      tahini = item(actor, "Tahini", [fridge, cupboard])

      link = Inventory.get_item_location!(tahini.id, fridge.id, actor: actor)
      :ok = Inventory.remove_item_location(link, actor: actor)

      assert place_names(tahini, actor) == ["Cupboard"]
    end
  end

  describe "search_items/2" do
    test "finds items by the words of their locations", %{actor: actor} do
      fridge = location(actor, "Fridge")
      item(actor, "Tahini", [fridge])
      item(actor, "Rice")

      names = fn query ->
        actor |> then(&Inventory.search_items!(query, actor: &1)) |> Enum.map(&to_string(&1.name))
      end

      assert ["Tahini"] == names.("fridge")
      assert ["Tahini"] == names.("tahini fri")
      assert [] == names.("rice fridge")
    end
  end

  describe "the lists for the check" do
    test "to_check_at has the items of one location, stalest first", %{actor: actor} do
      fridge = location(actor, "Fridge")
      old = item(actor, "Butter", [fridge])
      item(actor, "Tahini", [fridge])
      item(actor, "Rice")

      past = DateTime.add(DateTime.utc_now(), -30, :day)

      old
      |> Ash.Changeset.for_update(:update, %{}, actor: actor)
      |> Ash.Changeset.force_change_attribute(:stock_checked_at, past)
      |> Ash.update!()

      assert ["Butter", "Tahini"] ==
               fridge.id
               |> Inventory.list_items_to_check_at!(actor: actor)
               |> Enum.map(&to_string(&1.name))
    end

    test "to_check_unplaced has the items without any location", %{actor: actor} do
      fridge = location(actor, "Fridge")
      item(actor, "Tahini", [fridge])
      item(actor, "Rice")

      assert ["Rice"] ==
               [actor: actor]
               |> Inventory.list_items_to_check_unplaced!()
               |> Enum.map(&to_string(&1.name))
    end

    test "to_check_at loads the other locations too", %{actor: actor} do
      fridge = location(actor, "Fridge")
      cupboard = location(actor, "Cupboard")
      item(actor, "Tahini", [fridge, cupboard])

      [tahini] = Inventory.list_items_to_check_at!(fridge.id, actor: actor)

      assert ["Cupboard", "Fridge"] ==
               tahini.locations |> Enum.map(&to_string(&1.name)) |> Enum.sort()
    end
  end
end
