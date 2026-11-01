defmodule KuraWeb.InventoryComponents do
  @moduledoc "Pieces shared by the inventory and the shopping list."
  use Phoenix.Component

  import KuraWeb.CoreComponents, only: [icon: 1, input: 1]

  @doc "The text shown in an item's tile: its emoji, or the first letter of its name."
  def tile_text(%{emoji: emoji}) when is_binary(emoji), do: emoji
  def tile_text(%{name: name}), do: name |> to_string() |> String.first() |> String.upcase()

  attr :item, :map, required: true, doc: "needs `name` and `emoji`"
  attr :dimmed, :boolean, default: false
  attr :on_list, :boolean, default: false, doc: "show the small cart marker"

  def item_tile(assigns) do
    ~H"""
    <span
      data-role="tile"
      class="relative grid size-12 shrink-0 place-items-center rounded-2xl bg-base-300/60 text-2xl font-bold text-base-content/70"
    >
      <span class={@dimmed && "opacity-60 grayscale"}>{tile_text(@item)}</span>
      <span
        :if={@on_list}
        data-role="on-list"
        title="On the shopping list"
        class="absolute -top-1.5 -right-1.5 grid size-[22px] place-items-center rounded-full border-[2.5px] border-base-100 bg-primary text-primary-content"
      >
        <.icon name="hero-shopping-cart-solid" class="size-2.5" />
      </span>
    </span>
    """
  end

  attr :form, :any, required: true

  @doc "The form for a new item. Events: `validate_new`, `create`, `cancel_add`."
  def new_item_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="new-item-form"
      phx-change="validate_new"
      phx-submit="create"
      class="mb-3 space-y-1 rounded-box bg-base-100 p-4 shadow-card"
    >
      <.input field={@form[:name]} type="text" label="Name" />
      <.input
        field={@form[:emoji]}
        type="text"
        label="Emoji (optional)"
        placeholder="Use your emoji keyboard"
        autocomplete="off"
        phx-mounted={Phoenix.LiveView.JS.focus()}
      />
      <.input
        field={@form[:tracking]}
        type="select"
        label="Track stock as"
        options={[{"A count (e.g. apples)", :count}, {"A level: plenty, low, empty", :level}]}
      />
      <.input
        :if={to_string(@form[:tracking].value) == "count"}
        field={@form[:stock_count]}
        type="number"
        label="In stock now"
        min="0"
      />
      <.input
        :if={to_string(@form[:tracking].value) == "level"}
        field={@form[:stock_level]}
        type="select"
        label="In stock now"
        options={[{"Plenty", :plenty}, {"Running low", :low}, {"Empty", :empty}]}
      />
      <.input field={@form[:usual_amount]} type="number" label="Usual amount to buy" min="1" />
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary rounded-full">Add item</button>
        <button type="button" phx-click="cancel_add" class="btn btn-ghost rounded-full">
          Cancel
        </button>
      </div>
    </.form>
    """
  end
end
