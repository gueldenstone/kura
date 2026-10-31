defmodule Kura.Inventory.ShoppingEntry.Changes.DefaultQuantity do
  @moduledoc "Uses the item's usual amount when no quantity was given."
  use Ash.Resource.Change

  alias Kura.Inventory.Item

  @impl true
  def change(changeset, _opts, context) do
    item_id = Ash.Changeset.get_attribute(changeset, :item_id)

    with nil <- Ash.Changeset.get_attribute(changeset, :quantity),
         true <- is_binary(item_id),
         {:ok, %Item{usual_amount: amount}} <-
           Ash.get(Item, item_id, Ash.Context.to_opts(context)) do
      Ash.Changeset.force_change_attribute(changeset, :quantity, amount)
    else
      _ -> changeset
    end
  end
end
