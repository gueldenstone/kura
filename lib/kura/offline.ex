defmodule Kura.Offline do
  @moduledoc """
  What the phones need to work without a connection.

  `snapshot/1` is the saved copy of the inventory and the shopping list that each phone keeps;
  `apply_changes/2` takes the check-offs that were queued while offline and applies them through
  the normal actions, so restocking follows exactly the same rules as when online.
  """

  alias Kura.Inventory

  @doc "The inventory and the shopping list as plain data that encodes to JSON."
  def snapshot(actor) do
    %{
      generated_at: DateTime.to_iso8601(DateTime.utc_now()),
      items: actor |> inventory_items() |> Enum.map(&item/1),
      open: [actor: actor] |> Inventory.list_open_entries!() |> Enum.map(&entry/1),
      checked: [actor: actor] |> Inventory.list_checked_entries!() |> Enum.map(&entry/1)
    }
  end

  @doc """
  Applies queued changes in order. A change is `%{"op" => "check" | "uncheck", "entry_id" => id}`.
  Changes that no longer make sense (the entry was removed or hidden, is already checked, ...) are
  skipped. Returns the number of applied and skipped changes.
  """
  def apply_changes(actor, changes) do
    changes
    |> Enum.map(&apply_change(actor, &1))
    |> Enum.reduce(%{applied: 0, skipped: 0}, fn
      :ok, acc -> %{acc | applied: acc.applied + 1}
      :skipped, acc -> %{acc | skipped: acc.skipped + 1}
    end)
  end

  defp apply_change(actor, %{"op" => op, "entry_id" => entry_id})
       when op in ["check", "uncheck"] do
    with {:ok, entry} <- Inventory.get_entry(entry_id, actor: actor),
         {:ok, _entry} <- run(op, entry, actor) do
      :ok
    else
      _ -> :skipped
    end
  end

  defp apply_change(_actor, _change), do: :skipped

  defp run("check", entry, actor), do: Inventory.check_off_entry(entry, actor: actor)
  defp run("uncheck", entry, actor), do: Inventory.uncheck_entry(entry, actor: actor)

  defp inventory_items(actor) do
    Inventory.search_items!("", actor: actor, load: [:empty?, :on_list?])
  end

  defp item(item) do
    %{
      id: item.id,
      name: Kura.Inventory.Item.label(item),
      tracking: to_string(item.tracking),
      stock_count: item.stock_count,
      stock_level: item.stock_level && to_string(item.stock_level),
      usual_amount: item.usual_amount,
      empty: item.empty?,
      on_list: item.on_list?
    }
  end

  defp entry(entry) do
    %{
      id: entry.id,
      item_id: entry.item_id,
      name: Kura.Inventory.Item.label(entry.item),
      quantity: entry.quantity,
      checked_at: entry.checked_at && DateTime.to_iso8601(entry.checked_at)
    }
  end
end
