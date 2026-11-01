defmodule Kura.Inventory.TagTest do
  use Kura.DataCase

  alias Kura.Inventory
  alias Kura.Inventory.Item

  setup do
    user =
      Kura.Accounts.create_user!(%{username: "lukas", password: "correct horse battery"},
        authorize?: false
      )

    %{actor: user}
  end

  defp tag(actor, name), do: Inventory.create_tag!(%{name: name}, actor: actor)

  defp item(actor, name, tags \\ []) do
    Inventory.create_item!(
      %{name: name, tracking: :level, tag_ids: Enum.map(tags, & &1.id)},
      actor: actor
    )
  end

  defp names(items), do: Enum.map(items, &Item.label/1)

  describe "creating tags" do
    test "tag names are unique, ignoring case", %{actor: actor} do
      tag(actor, "ground")

      assert {:error, _} = Inventory.create_tag(%{name: "GROUND"}, actor: actor)
    end

    test "list_tags is by name with the number of items per tag", %{actor: actor} do
      ground = tag(actor, "ground")
      tag(actor, "Bio")
      item(actor, "Cumin", [ground])
      item(actor, "Pepper", [ground])

      assert [{"Bio", 0}, {"ground", 2}] =
               actor
               |> then(&Inventory.list_tags!(actor: &1))
               |> Enum.map(&{to_string(&1.name), &1.item_count})
    end
  end

  test "tags are listed ignoring case", %{actor: actor} do
    for name <- ["Usbekistan", "ganz", "Bio"], do: tag(actor, name)

    assert ["Bio", "ganz", "Usbekistan"] ==
             actor |> then(&Inventory.list_tags!(actor: &1)) |> Enum.map(&to_string(&1.name))
  end

  describe "items and their tags" do
    test "the same name with different tags makes different items", %{actor: actor} do
      ground = tag(actor, "ground")
      whole = tag(actor, "whole")

      item(actor, "Cumin", [ground])
      item(actor, "Cumin", [whole])
      item(actor, "Cumin")

      assert ["Cumin", "Cumin ground", "Cumin whole"] ==
               actor |> then(&Inventory.search_items!("", actor: &1)) |> names()
    end

    test "the same name with the same tags is refused, whatever the order", %{actor: actor} do
      ground = tag(actor, "ground")
      bio = tag(actor, "Bio")
      item(actor, "Cumin", [ground, bio])

      assert {:error, _} =
               Inventory.create_item(
                 %{name: "cumin", tracking: :level, tag_ids: [bio.id, ground.id]},
                 actor: actor
               )

      assert {:error, _} =
               Inventory.create_item(
                 %{name: "Cumin", tracking: :level, tag_ids: [bio.id, ground.id]},
                 actor: actor
               )
    end

    test "an untagged item still has a unique name", %{actor: actor} do
      item(actor, "Salt")

      assert {:error, _} = Inventory.create_item(%{name: "salt", tracking: :level}, actor: actor)
    end

    test "tags can be changed on an existing item", %{actor: actor} do
      ground = tag(actor, "ground")
      whole = tag(actor, "whole")
      cumin = item(actor, "Cumin", [ground])

      cumin = Inventory.update_item!(cumin, %{tag_ids: [whole.id]}, actor: actor)

      assert ["whole"] ==
               cumin
               |> Ash.load!(:tags, actor: actor)
               |> Map.fetch!(:tags)
               |> Enum.map(&to_string(&1.name))

      cleared = Inventory.update_item!(cumin, %{tag_ids: []}, actor: actor)
      assert cleared.tag_key == ""
      assert [] == (cleared |> Ash.load!(:tags, actor: actor)).tags
    end

    test "an update without tag_ids leaves the tags alone", %{actor: actor} do
      ground = tag(actor, "ground")
      cumin = item(actor, "Cumin", [ground])

      renamed = Inventory.update_item!(cumin, %{name: "Kreuzkümmel"}, actor: actor)

      assert renamed.tag_key == cumin.tag_key
      assert [%{name: name}] = Ash.load!(renamed, :tags, actor: actor).tags
      assert to_string(name) == "ground"
    end

    test "renaming a tag shows everywhere and keeps the identity", %{actor: actor} do
      ground = tag(actor, "ground")
      cumin = item(actor, "Cumin", [ground])

      Inventory.update_tag!(ground, %{name: "milled"}, actor: actor)

      assert ["Cumin milled"] == actor |> then(&Inventory.search_items!("", actor: &1)) |> names()
      assert Inventory.get_item!(cumin.id, actor: actor).tag_key == cumin.tag_key
    end
  end

  describe "ordering items with the same name" do
    test "goes by the tags, ignoring case", %{actor: actor} do
      kapseln = tag(actor, "Kapseln")
      gemahlen = tag(actor, "gemahlen")
      item(actor, "Cardamom", [kapseln])
      item(actor, "Cardamom", [gemahlen])

      assert ["Cardamom gemahlen", "Cardamom Kapseln"] ==
               actor |> then(&Inventory.search_items!("", actor: &1)) |> names()
    end

    test "names are ordered ignoring case too", %{actor: actor} do
      item(actor, "zimt")
      item(actor, "Apple")
      item(actor, "Mint")

      assert ["Apple", "Mint", "zimt"] ==
               actor |> then(&Inventory.search_items!("", actor: &1)) |> names()
    end
  end

  describe "search_items/2 with tags" do
    test "every word has to match the name or a tag", %{actor: actor} do
      ground = tag(actor, "ground")
      whole = tag(actor, "whole")
      item(actor, "Cumin", [ground])
      item(actor, "Cumin", [whole])
      item(actor, "Pepper", [ground])

      search = &(actor |> then(fn a -> Inventory.search_items!(&1, actor: a) end) |> names())

      assert ["Cumin ground"] == search.("cumin ground")
      assert ["Cumin ground", "Pepper ground"] == search.("GROUND")
      assert ["Cumin ground", "Cumin whole"] == search.("cum")
      assert [] == search.("cumin pepper")
    end
  end

  describe "deleting a tag" do
    test "takes it off its items", %{actor: actor} do
      ground = tag(actor, "ground")
      bio = tag(actor, "Bio")
      cumin = item(actor, "Cumin", [ground, bio])

      :ok = Inventory.delete_tag(ground, actor: actor)

      assert ["Cumin Bio"] == actor |> then(&Inventory.search_items!("", actor: &1)) |> names()
      assert Inventory.get_item!(cumin.id, actor: actor).tag_key == Item.tag_key([bio.id])
    end

    test "is refused when two items would become identical", %{actor: actor} do
      ground = tag(actor, "ground")
      item(actor, "Cumin", [ground])
      item(actor, "Cumin")

      assert {:error, error} = Inventory.delete_tag(ground, actor: actor)
      assert Exception.message(error) =~ "would make these items identical"

      assert ["Cumin", "Cumin ground"] ==
               actor |> then(&Inventory.search_items!("", actor: &1)) |> names()

      assert {:ok, _} = Inventory.get_tag(ground.id, actor: actor)
    end
  end
end
