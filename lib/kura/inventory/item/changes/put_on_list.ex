defmodule Kura.Inventory.Item.Changes.PutOnList do
  @moduledoc """
  After the action, puts the item on the shopping list unless it is already there. The entry that
  was created, if any, is attached to the item as `__metadata__.added_entry` so callers can undo it.
  """
  use Ash.Resource.Change

  alias Kura.Inventory.ShoppingList

  @impl true
  def change(changeset, _opts, context) do
    actor = Ash.Context.to_opts(context)[:actor]

    Ash.Changeset.after_action(changeset, fn _changeset, item ->
      added =
        case ShoppingList.put_on_list(item, actor) do
          {:created, entry} -> entry
          {:existing, _entry} -> nil
        end

      {:ok, Ash.Resource.put_metadata(item, :added_entry, added)}
    end)
  end
end
