defmodule Kura.Inventory.ShoppingList do
  @moduledoc "Operations on the shopping list as a whole."

  require Ash.Query

  alias Kura.Inventory
  alias Kura.Inventory.{Item, ShoppingEntry}

  @doc """
  Puts an item on the list with its usual amount, unless it is already there.

  Returns `{:created, entry}` or `{:existing, entry}`.
  """
  def put_on_list(%Item{id: item_id}, actor) do
    existing =
      ShoppingEntry
      |> Ash.Query.for_read(:open, %{}, actor: actor)
      |> Ash.Query.filter(item_id == ^item_id)
      |> Ash.read_one!(actor: actor)

    case existing do
      nil -> {:created, Inventory.add_entry!(%{item_id: item_id}, actor: actor)}
      entry -> {:existing, entry}
    end
  end

  @doc "Deletes all checked-off entries. They can no longer be unchecked."
  def hide_checked(actor) do
    actor
    |> then(&Inventory.list_checked_entries!(actor: &1))
    |> Ash.bulk_destroy!(:destroy, %{}, actor: actor, return_errors?: true)

    :ok
  end
end
