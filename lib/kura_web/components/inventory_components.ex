defmodule KuraWeb.InventoryComponents do
  @moduledoc "Pieces shared by the inventory and the shopping list."
  use Phoenix.Component

  import KuraWeb.CoreComponents, only: [icon: 1]

  attr :item, :map, required: true, doc: "an item with its tags loaded"
  attr :class, :string, default: nil, doc: "classes for the name"

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
    </span>
    """
  end

  attr :tags, :list, required: true, doc: "all tags"
  attr :selected, :list, required: true, doc: "ids of the tags the item has"
  attr :query, :string, default: ""
  attr :target, :any, default: nil, doc: "the component that handles the events"

  @doc """
  Picks the tags of an item inside its form: the chosen tags as chips, a search box and the other
  tags to tap. The chosen ids are submitted as `item[tag_ids][]`; the empty one makes sure that
  clearing every tag is submitted too. Events: `add_tag`, `remove_tag`, `create_tag`, `tag_enter`.
  """
  def tag_picker(assigns) do
    query = String.trim(assigns.query)

    assigns =
      assign(assigns,
        chosen: Enum.filter(assigns.tags, &(&1.id in assigns.selected)),
        available: available_tags(assigns.tags, assigns.selected, query),
        new_name: new_tag_name(assigns.tags, query)
      )

    ~H"""
    <fieldset id="tag-picker" class="space-y-2 pt-1">
      <legend class="mb-1 text-sm font-semibold">Tags</legend>
      <input type="hidden" name="item[tag_ids][]" value="" />
      <input :for={id <- @selected} type="hidden" name="item[tag_ids][]" value={id} />
      <div :if={@chosen != []} class="flex flex-wrap gap-1.5">
        <button
          :for={tag <- @chosen}
          type="button"
          phx-click="remove_tag"
          phx-target={@target}
          phx-value-id={tag.id}
          aria-label={"Remove #{tag.name}"}
          data-role="chosen-tag"
          class="inline-flex h-8 items-center gap-1 rounded-full bg-primary/10 pr-2 pl-3 text-[13px] font-bold text-primary transition active:scale-95"
        >
          {tag.name} <.icon name="hero-x-mark-micro" class="size-4" />
        </button>
      </div>
      <input
        type="text"
        name="tag_query"
        value={@query}
        phx-hook="TagInput"
        phx-target={@target}
        id="tag-query"
        placeholder="Search or add a tag"
        autocomplete="off"
        enterkeyhint="done"
        phx-debounce="150"
        class="h-10 w-full rounded-full border-0 bg-base-100 px-4 text-sm outline-none placeholder:text-base-content/45 focus:ring-2 focus:ring-primary/40"
      />
      <div class="flex max-h-36 flex-wrap gap-1.5 overflow-y-auto">
        <button
          :for={tag <- @available}
          type="button"
          phx-click="add_tag"
          phx-target={@target}
          phx-value-id={tag.id}
          data-role="available-tag"
          class="inline-flex h-8 items-center rounded-full bg-base-300/60 px-3 text-[13px] font-bold transition hover:bg-base-300 active:scale-95"
        >
          {tag.name}
        </button>
        <button
          :if={@new_name}
          type="button"
          phx-click="create_tag"
          phx-target={@target}
          data-role="create-tag"
          class="inline-flex h-8 items-center gap-1 rounded-full border-2 border-dashed border-primary/40 px-3 text-[13px] font-bold text-primary transition hover:bg-primary/10 active:scale-95"
        >
          <.icon name="hero-plus-micro" class="size-4" /> Create “{@new_name}”
        </button>
      </div>
    </fieldset>
    """
  end

  defp available_tags(tags, selected, query) do
    query = String.downcase(query)

    Enum.filter(tags, fn tag ->
      tag.id not in selected and String.contains?(String.downcase(to_string(tag.name)), query)
    end)
  end

  defp new_tag_name(_tags, ""), do: nil

  defp new_tag_name(tags, query) do
    if Enum.any?(tags, &(String.downcase(to_string(&1.name)) == String.downcase(query))),
      do: nil,
      else: query
  end
end
