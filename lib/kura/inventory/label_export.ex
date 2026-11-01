defmodule Kura.Inventory.LabelExport do
  @moduledoc """
  Item names as CSV for label printing: a `Label` column with one row per item. Label software
  imports the file and prints one label per row.
  """

  alias Kura.Inventory.Item

  @header "Label"

  @spec csv([Item.t()]) :: String.t()
  def csv(items) do
    Enum.map_join([@header | Enum.map(items, &to_string(&1.name))], "\r\n", &field/1) <> "\r\n"
  end

  defp field(value) do
    if String.contains?(value, [",", "\"", "\r", "\n"]) do
      ~s("#{String.replace(value, "\"", "\"\"")}")
    else
      value
    end
  end
end
