defmodule KuraWeb.InventoryComponents do
  @moduledoc "Pieces shared by the inventory and the shopping list."
  use Phoenix.Component

  import KuraWeb.CoreComponents, only: [input: 1]

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
      <.input field={@form[:auto_replenish]} type="checkbox" label="Auto-replenish when empty" />
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
