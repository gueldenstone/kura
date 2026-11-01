defmodule Kura.Inventory.Item.Changes.SetTags do
  @moduledoc """
  Replaces the item's tags with the ones in the `tag_ids` argument, when it is given, and keeps
  `tag_key` in step. `tag_key` is the sorted tag ids as one string; it is what lets a unique
  identity on name and tags work in SQLite, which has no set type.
  """
  use Ash.Resource.Change

  alias Kura.Inventory.Item

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_argument(changeset, :tag_ids) do
      {:ok, ids} when is_list(ids) ->
        ids = Enum.uniq(ids)

        changeset
        |> Ash.Changeset.force_change_attribute(:tag_key, Item.tag_key(ids))
        |> Ash.Changeset.manage_relationship(:tags, ids, type: :append_and_remove)

      _ ->
        changeset
    end
  end
end
