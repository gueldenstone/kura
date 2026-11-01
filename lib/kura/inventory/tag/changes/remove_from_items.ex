defmodule Kura.Inventory.Tag.Changes.RemoveFromItems do
  @moduledoc """
  Before a tag is deleted, takes it out of the `tag_key` of the items that carry it. If that would
  leave two items with the same name and the same tags, the tag is not deleted and the error names
  the items that would collide.
  """
  use Ash.Resource.Change

  alias Kura.Inventory.Item

  @impl true
  def change(changeset, _opts, context) do
    opts = Ash.Context.to_opts(context)

    Ash.Changeset.before_action(changeset, fn changeset ->
      tag = changeset.data
      carrying = tag |> Ash.load!([items: [:tags]], opts) |> Map.fetch!(:items)
      carrying_ids = Enum.map(carrying, & &1.id)
      others = Item |> Ash.read!(opts) |> Enum.reject(&(&1.id in carrying_ids))

      updated = Enum.map(carrying, &{&1, new_key(&1, tag)})

      case collisions(updated, others) do
        [] ->
          Enum.each(updated, fn {item, key} -> set_key(item, key, opts) end)
          changeset

        names ->
          Ash.Changeset.add_error(changeset,
            field: :name,
            message: "would make these items identical: #{Enum.join(names, ", ")}"
          )
      end
    end)
  end

  defp new_key(item, tag) do
    item.tags |> Enum.map(& &1.id) |> List.delete(tag.id) |> Item.tag_key()
  end

  defp collisions(updated, others) do
    identities =
      Enum.map(updated, fn {item, key} -> {identity(item, key), item} end) ++
        Enum.map(others, &{identity(&1, &1.tag_key), &1})

    identities
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.filter(fn {_identity, items} -> length(items) > 1 end)
    |> Enum.flat_map(fn {_identity, items} -> Enum.map(items, &to_string(&1.name)) end)
    |> Enum.uniq()
  end

  defp identity(item, key), do: {String.downcase(to_string(item.name)), key}

  defp set_key(item, key, opts) do
    item
    |> Ash.Changeset.for_update(:update, %{}, opts)
    |> Ash.Changeset.force_change_attribute(:tag_key, key)
    |> Ash.update!()
  end
end
