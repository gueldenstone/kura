defmodule Kura.Inventory.LabelExport do
  @moduledoc """
  Items as CSV for label printing: a single `Label` column with the name followed by the tags
  worth printing, separated by spaces, one row per item, ordered by name and then by those tags.
  Label software imports the file and prints one label per row.

  A tag is printed only when its "print on labels" switch is on and it tells items apart: not
  every item of the inventory with the same name has it. "ground" on both of two paprikas is
  noise, "hot" and "sweet" are what the labels need.
  """

  alias Kura.Inventory.Item

  @header ["Label"]

  @doc """
  The CSV for `items`, the selected items. `inventory` is every item with its tags loaded: tags
  are compared with all items of the same name, not just the selected ones.
  """
  @spec csv([Item.t()], [Item.t()]) :: String.t()
  def csv(items, inventory) do
    siblings = Enum.group_by(inventory, &name_key/1)

    rows =
      items
      |> Enum.map(fn item ->
        tags = printed_tags(item, Map.get(siblings, name_key(item), [item]))
        {name_key(item), Enum.join(tags, " ") |> String.downcase(), label(item, tags)}
      end)
      |> Enum.sort()
      |> Enum.map(fn {_name, _tags, label} -> [label] end)

    Enum.map_join([@header | rows], "\r\n", &Enum.map_join(&1, ",", fn value -> field(value) end)) <>
      "\r\n"
  end

  @doc "The tag names to print for `item`, given the items with its name, in alphabetical order."
  def printed_tags(item, siblings) do
    common = siblings |> Enum.map(&tag_ids/1) |> Enum.reduce(&MapSet.intersection/2)

    item.tags
    |> Enum.filter(&(&1.print_on_labels and not MapSet.member?(common, &1.id)))
    |> Enum.map(&to_string(&1.name))
    |> Enum.sort_by(&String.downcase/1)
  end

  defp label(item, tags), do: Enum.join([to_string(item.name) | tags], " ")

  defp tag_ids(item), do: MapSet.new(item.tags, & &1.id)

  defp name_key(item), do: item.name |> to_string() |> String.downcase()

  defp field(value) do
    if String.contains?(value, [",", "\"", "\r", "\n"]) do
      ~s("#{String.replace(value, "\"", "\"\"")}")
    else
      value
    end
  end
end
