defmodule Kura.Inventory.Item.Changes.NormalizeStock do
  @moduledoc """
  Keeps only the stock field that matches the item's tracking type and fills in
  a starting value: a count of 1 for count items, "plenty" for level items.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :tracking) do
      :count ->
        changeset
        |> Ash.Changeset.force_change_attribute(:stock_level, nil)
        |> default(:stock_count, 1)

      :level ->
        changeset
        |> Ash.Changeset.force_change_attribute(:stock_count, nil)
        |> default(:stock_level, :plenty)

      _ ->
        changeset
    end
  end

  defp default(changeset, attribute, value) do
    case Ash.Changeset.get_attribute(changeset, attribute) do
      nil -> Ash.Changeset.force_change_attribute(changeset, attribute, value)
      _ -> changeset
    end
  end
end
