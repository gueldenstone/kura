defmodule Kura.Inventory.ShoppingEntry.Changes.Uncheck do
  @moduledoc "Reverses `CheckOff`: takes the quantity off a count item, restores a level item's level."
  use Ash.Resource.Change

  alias Kura.Inventory
  alias Kura.Inventory.Item

  @impl true
  def change(changeset, _opts, context) do
    opts = Ash.Context.to_opts(context)
    previous_level = changeset.data.previous_level

    changeset
    |> Ash.Changeset.force_change_attribute(:checked_at, nil)
    |> Ash.Changeset.force_change_attribute(:previous_level, nil)
    |> Ash.Changeset.after_action(fn _changeset, entry ->
      item = Ash.get!(Item, entry.item_id, opts)
      unstock(item, entry.quantity, previous_level, opts)
      {:ok, entry}
    end)
  end

  defp unstock(%Item{tracking: :count} = item, quantity, _previous_level, opts),
    do: Inventory.change_item_count!(item, -quantity, opts)

  defp unstock(%Item{tracking: :level} = item, _quantity, previous_level, opts)
       when not is_nil(previous_level),
       do: Inventory.set_item_level!(item, previous_level, opts)

  defp unstock(%Item{tracking: :level}, _quantity, nil, _opts), do: :ok
  defp unstock(%Item{tracking: :none}, _quantity, _previous_level, _opts), do: :ok
end
