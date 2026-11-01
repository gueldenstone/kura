defmodule Kura.Inventory.Item.Changes.TouchStockChecked do
  @moduledoc "Stamps the item with the time its stock was last changed or confirmed."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(changeset, :stock_checked_at, DateTime.utc_now())
  end
end
