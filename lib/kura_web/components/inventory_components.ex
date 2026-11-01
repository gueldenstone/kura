defmodule KuraWeb.InventoryComponents do
  @moduledoc "Pieces shared by the inventory and the shopping list."
  use Phoenix.Component

  import KuraWeb.CoreComponents, only: [icon: 1]

  attr :item, :map, required: true, doc: "an item with its tags loaded"
  attr :class, :string, default: nil, doc: "classes for the name"
  attr :locations, :boolean, default: false, doc: "show where the item lives (needs them loaded)"

  @doc "The name of an item, with its tags as a small line below."
  def item_title(assigns) do
    ~H"""
    <span class="min-w-0 flex-1">
      <span class={["block truncate text-[17px] font-bold", @class]}>{@item.name}</span>
      <span
        :if={@item.tags != []}
        data-role="tags"
        class="block truncate text-[13px] leading-tight font-semibold text-base-content/55"
      >
        {Kura.Inventory.Item.tag_line(@item)}
      </span>
      <span
        :if={@locations and @item.locations != []}
        data-role="locations"
        class="flex items-center gap-1 truncate text-[13px] leading-tight font-semibold text-primary/80"
      >
        <.icon name="hero-map-pin-micro" class="size-3.5 shrink-0" />
        <span class="truncate">{Enum.map_join(@item.locations, ", ", &(&1.name |> to_string()))}</span>
      </span>
    </span>
    """
  end

  attr :kind, :string, required: true, values: ~w(tag location)
  attr :label, :string, required: true
  attr :placeholder, :string, required: true
  attr :options, :list, required: true, doc: "everything that can be chosen"
  attr :selected, :list, required: true, doc: "ids of the chosen options"
  attr :query, :string, default: ""
  attr :target, :any, default: nil, doc: "the component that handles the events"

  @doc """
  Picks tags or locations of an item inside its form: the chosen ones as chips, a search box and
  the other options to tap. The chosen ids are submitted as `item[<kind>_ids][]`; the empty one
  makes sure that clearing every chip is submitted too. Events, all with `kind`: `add_chip`,
  `remove_chip`, `create_chip` and `chip_enter` (from the `TagInput` hook).
  """
  def chip_picker(assigns) do
    query = String.trim(assigns.query)

    assigns =
      assign(assigns,
        chosen: Enum.filter(assigns.options, &(&1.id in assigns.selected)),
        available: available(assigns.options, assigns.selected, query),
        new_name: new_name(assigns.options, query)
      )

    ~H"""
    <fieldset id={"#{@kind}-picker"} class="space-y-2 pt-1">
      <legend class="mb-1 text-sm font-semibold">{@label}</legend>
      <input type="hidden" name={"item[#{@kind}_ids][]"} value="" />
      <input :for={id <- @selected} type="hidden" name={"item[#{@kind}_ids][]"} value={id} />
      <div :if={@chosen != []} class="flex flex-wrap gap-1.5">
        <button
          :for={option <- @chosen}
          type="button"
          phx-click="remove_chip"
          phx-target={@target}
          phx-value-kind={@kind}
          phx-value-id={option.id}
          aria-label={"Remove #{option.name}"}
          data-role={"chosen-#{@kind}"}
          class="inline-flex h-8 items-center gap-1 rounded-full bg-primary/10 pr-2 pl-3 text-[13px] font-bold text-primary transition active:scale-95"
        >
          {option.name} <.icon name="hero-x-mark-micro" class="size-4" />
        </button>
      </div>
      <input
        type="text"
        name={"#{@kind}_query"}
        value={@query}
        phx-hook="TagInput"
        phx-target={@target}
        data-kind={@kind}
        id={"#{@kind}-query"}
        placeholder={@placeholder}
        autocomplete="off"
        enterkeyhint="done"
        phx-debounce="150"
        class="h-10 w-full rounded-full border-0 bg-base-100 px-4 text-sm outline-none placeholder:text-base-content/45 focus:ring-2 focus:ring-primary/40"
      />
      <div class="flex max-h-36 flex-wrap gap-1.5 overflow-y-auto">
        <button
          :for={option <- @available}
          type="button"
          phx-click="add_chip"
          phx-target={@target}
          phx-value-kind={@kind}
          phx-value-id={option.id}
          data-role={"available-#{@kind}"}
          class="inline-flex h-8 items-center rounded-full bg-base-300/60 px-3 text-[13px] font-bold transition hover:bg-base-300 active:scale-95"
        >
          {option.name}
        </button>
        <button
          :if={@new_name}
          type="button"
          phx-click="create_chip"
          phx-target={@target}
          phx-value-kind={@kind}
          data-role={"create-#{@kind}"}
          class="inline-flex h-8 items-center gap-1 rounded-full border-2 border-dashed border-primary/40 px-3 text-[13px] font-bold text-primary transition hover:bg-primary/10 active:scale-95"
        >
          <.icon name="hero-plus-micro" class="size-4" /> Create “{@new_name}”
        </button>
      </div>
    </fieldset>
    """
  end

  defp available(options, selected, query) do
    query = String.downcase(query)

    Enum.filter(options, fn option ->
      option.id not in selected and
        String.contains?(String.downcase(to_string(option.name)), query)
    end)
  end

  defp new_name(_tags, ""), do: nil

  defp new_name(tags, query) do
    if Enum.any?(tags, &(String.downcase(to_string(&1.name)) == String.downcase(query))),
      do: nil,
      else: query
  end
end
