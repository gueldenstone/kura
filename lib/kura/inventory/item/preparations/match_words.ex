defmodule Kura.Inventory.Item.Preparations.MatchWords do
  @moduledoc """
  Keeps the items for which every word of the `query` argument is part of the name or of one of
  the tags or one of the locations, so "cumin ground" finds the ground cumin and "fridge" what lives in the fridge. Items with the same name come out ordered by
  their tags, all ignoring case.
  """
  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, context) do
    words = query |> Ash.Query.get_argument(:query) |> String.split(~r/\s+/, trim: true)

    words
    |> Enum.reduce(query, fn word, query ->
      Ash.Query.filter(
        query,
        contains(name, ^word) or exists(tags, contains(name, ^word)) or
          exists(locations, contains(name, ^word))
      )
    end)
    |> Ash.Query.after_action(fn _query, items ->
      {:ok, items |> Ash.load!(:tags, Ash.Context.to_opts(context)) |> order_by_tags()}
    end)
  end

  # SQLite sorts capital letters first, so the order is settled here, ignoring case.
  defp order_by_tags(items) do
    Enum.sort_by(items, fn item ->
      {item.name |> to_string() |> String.downcase(),
       item |> Kura.Inventory.Item.tag_line() |> String.downcase()}
    end)
  end
end
