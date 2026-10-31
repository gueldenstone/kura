defmodule Kura.Inventory.ShoppingEntry.Validations.NotOnList do
  @moduledoc "An item can only have one open entry on the shopping list."
  use Ash.Resource.Validation

  require Ash.Query

  alias Kura.Inventory.ShoppingEntry

  @impl true
  def validate(changeset, _opts, context) do
    item_id = Ash.Changeset.get_attribute(changeset, :item_id)

    on_list? =
      item_id &&
        ShoppingEntry
        |> Ash.Query.for_read(:open, %{}, Ash.Context.to_opts(context))
        |> Ash.Query.filter(item_id == ^item_id)
        |> Ash.exists?(Ash.Context.to_opts(context))

    if on_list?,
      do: {:error, field: :item_id, message: "is already on the shopping list"},
      else: :ok
  end
end
