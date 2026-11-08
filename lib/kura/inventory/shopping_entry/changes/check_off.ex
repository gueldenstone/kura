defmodule Kura.Inventory.ShoppingEntry.Changes.CheckOff do
  @moduledoc """
  Marks the entry as checked off and restocks its item: a count item gains the entry's quantity,
  a level item goes to plenty (the previous level is kept on the entry for undo), an item without
  stock stays as it is. Entries that were
  checked off over a day ago are cleared first: that is the start of a new shopping trip.
  """
  use Ash.Resource.Change

  alias Kura.Inventory
  alias Kura.Inventory.{Item, ShoppingList}

  @impl true
  def change(changeset, _opts, context) do
    opts = Ash.Context.to_opts(context)

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      item = Ash.get!(Item, changeset.data.item_id, opts)
      ShoppingList.hide_stale_checked(opts[:actor])

      changeset
      |> Ash.Changeset.force_change_attribute(:checked_at, DateTime.utc_now())
      |> Ash.Changeset.force_change_attribute(:previous_level, item.stock_level)
    end)
    |> Ash.Changeset.after_action(fn _changeset, entry ->
      item = Ash.get!(Item, entry.item_id, opts)
      restock(item, entry.quantity, opts)
      {:ok, entry}
    end)
  end

  defp restock(%Item{tracking: :count} = item, quantity, opts),
    do: Inventory.change_item_count!(item, quantity, opts)

  defp restock(%Item{tracking: :level} = item, _quantity, opts),
    do: Inventory.set_item_level!(item, :plenty, opts)

  defp restock(%Item{tracking: :none}, _quantity, _opts), do: :ok
end
