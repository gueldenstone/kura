defmodule Kura.Inventory.Item.Changes.SwitchTracking do
  @moduledoc """
  Lets an update change how an item's stock is tracked. The new stock is the one given, or else
  carried over from the old one (see `Kura.Inventory.Item.converted_stock/2`); then the stock is
  normalized for the new type and counts as changed. Without a new tracking type, stock given to
  the update is ignored: stock is changed through the stock actions.
  """
  use Ash.Resource.Change

  alias Kura.Inventory.Item
  alias Kura.Inventory.Item.Changes.{NormalizeStock, TouchStockChecked}

  @impl true
  def change(changeset, opts, context) do
    tracking = Ash.Changeset.get_attribute(changeset, :tracking)

    if tracking == changeset.data.tracking do
      changeset
      |> Ash.Changeset.clear_change(:stock_count)
      |> Ash.Changeset.clear_change(:stock_level)
    else
      changeset
      |> carry_over(Item.converted_stock(changeset.data, tracking))
      |> NormalizeStock.change(opts, context)
      |> TouchStockChecked.change(opts, context)
    end
  end

  defp carry_over(changeset, stock) do
    Enum.reduce(stock, changeset, fn {field, value}, changeset ->
      if Ash.Changeset.changing_attribute?(changeset, field) and
           not is_nil(Ash.Changeset.get_attribute(changeset, field)) do
        changeset
      else
        Ash.Changeset.force_change_attribute(changeset, field, value)
      end
    end)
  end
end
