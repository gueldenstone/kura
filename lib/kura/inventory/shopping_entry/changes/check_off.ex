defmodule Kura.Inventory.ShoppingEntry.Changes.CheckOff do
  @moduledoc """
  Marks the entry as checked off and restocks its item: a count item gains the entry's quantity,
  a level item goes to plenty (the previous level is kept on the entry for undo).
  """
  use Ash.Resource.Change

  alias Kura.Inventory
  alias Kura.Inventory.Item

  @impl true
  def change(changeset, _opts, context) do
    opts = Ash.Context.to_opts(context)

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      item = Ash.get!(Item, changeset.data.item_id, opts)

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
end
