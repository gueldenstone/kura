defmodule KuraWeb.InventoryLive do
  use KuraWeb, :live_view

  alias Kura.Inventory
  alias Kura.Inventory.Item

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Inventory")
      |> assign(query: "", new_form: nil, editing: nil, edit_form: nil, undo: nil)
      |> assign_search_form()
      |> load_items()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket |> assign(query: query, new_form: nil) |> assign_search_form() |> load_items()}
  end

  def handle_event("open_add", _params, socket) do
    form =
      AshPhoenix.Form.for_create(Item, :create,
        as: "item",
        actor: actor(socket),
        params: %{"name" => String.trim(socket.assigns.query), "tracking" => "count"}
      )

    {:noreply, assign(socket, new_form: to_form(form))}
  end

  def handle_event("validate_new", %{"item" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.new_form.source, params)
    {:noreply, assign(socket, new_form: to_form(form))}
  end

  def handle_event("create", %{"item" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.new_form.source, params: params) do
      {:ok, _item} ->
        {:noreply,
         socket |> assign(new_form: nil, query: "") |> assign_search_form() |> load_items()}

      {:error, form} ->
        {:noreply, assign(socket, new_form: to_form(form))}
    end
  end

  def handle_event("cancel_add", _params, socket) do
    {:noreply, assign(socket, new_form: nil)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    with_item(socket, id, fn item ->
      form = AshPhoenix.Form.for_update(item, :update, as: "item", actor: actor(socket))
      {:noreply, assign(socket, editing: item.id, edit_form: to_form(form))}
    end)
  end

  def handle_event("validate_edit", %{"item" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.edit_form.source, params)
    {:noreply, assign(socket, edit_form: to_form(form))}
  end

  def handle_event("update", %{"item" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.edit_form.source, params: params) do
      {:ok, _item} ->
        {:noreply, socket |> assign(editing: nil, edit_form: nil) |> load_items()}

      {:error, form} ->
        {:noreply, assign(socket, edit_form: to_form(form))}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, edit_form: nil)}
  end

  def handle_event("delete", _params, %{assigns: %{editing: id}} = socket) when is_binary(id) do
    with_item(socket, id, fn item ->
      :ok = Inventory.delete_item(item, actor: actor(socket))
      {:noreply, socket |> assign(editing: nil, edit_form: nil, undo: nil) |> load_items()}
    end)
  end

  def handle_event("change_count", %{"id" => id, "delta" => delta}, socket) do
    with_item(socket, id, fn item ->
      Inventory.change_item_count!(item, String.to_integer(delta), actor: actor(socket))
      {:noreply, load_items(socket)}
    end)
  end

  def handle_event("set_level", %{"id" => id, "level" => level}, socket) do
    with_item(socket, id, fn item ->
      Inventory.set_item_level!(item, String.to_existing_atom(level), actor: actor(socket))
      {:noreply, load_items(socket)}
    end)
  end

  def handle_event("mark_empty", %{"id" => id}, socket) do
    with_item(socket, id, fn item ->
      undo = %{id: item.id, name: item.name, previous: previous_stock(item)}
      Inventory.mark_item_empty!(item, actor: actor(socket))
      {:noreply, socket |> assign(undo: undo) |> load_items()}
    end)
  end

  def handle_event("undo", _params, %{assigns: %{undo: %{} = undo}} = socket) do
    with_item(socket, undo.id, fn item ->
      restore_stock(item, undo.previous, actor(socket))
      {:noreply, socket |> assign(undo: nil) |> load_items()}
    end)
  end

  def handle_event("undo", _params, socket), do: {:noreply, socket}

  defp actor(socket), do: socket.assigns.current_user

  defp assign_search_form(socket) do
    assign(socket, :search_form, to_form(%{"query" => socket.assigns.query}, as: :search))
  end

  defp load_items(socket) do
    items = Inventory.search_items!(socket.assigns.query, actor: actor(socket), load: [:empty?])
    assign(socket, :items, items)
  end

  # An item can vanish while this page is open, for example when the other person deletes it.
  defp with_item(socket, id, fun) do
    case Inventory.get_item(id, actor: actor(socket)) do
      {:ok, item} ->
        fun.(item)

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "That item no longer exists")
         |> assign(editing: nil, edit_form: nil, undo: nil)
         |> load_items()}
    end
  end

  defp previous_stock(%Item{tracking: :count, stock_count: count}), do: {:count, count}
  defp previous_stock(%Item{tracking: :level, stock_level: level}), do: {:level, level}

  defp restore_stock(item, {:count, count}, actor),
    do: Inventory.set_item_count!(item, count, actor: actor)

  defp restore_stock(item, {:level, level}, actor),
    do: Inventory.set_item_level!(item, level, actor: actor)

  defp show_add_prompt?(query, items) do
    name = query |> String.trim() |> String.downcase()
    name != "" and not Enum.any?(items, &(String.downcase(to_string(&1.name)) == name))
  end

  defp stock_label(%Item{empty?: true}), do: "Empty"
  defp stock_label(%Item{tracking: :count, stock_count: count}), do: to_string(count)

  defp stock_label(%Item{tracking: :level, stock_level: level}),
    do: level |> to_string() |> String.capitalize()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:inventory}>
      <h1 class="text-2xl font-semibold tracking-tight">Inventory</h1>

      <.form for={@search_form} id="search-form" phx-change="search" phx-submit="search" class="mt-4">
        <.input
          field={@search_form[:query]}
          type="search"
          placeholder="Search or add an item"
          autocomplete="off"
          phx-debounce="150"
        />
      </.form>

      <div :if={show_add_prompt?(@query, @items) and is_nil(@new_form)} id="add-item" class="mt-2">
        <button
          type="button"
          phx-click="open_add"
          class="flex w-full items-center gap-2 rounded-xl border border-dashed border-base-300 px-4 py-3 text-left font-medium text-primary transition hover:bg-base-200"
        >
          <.icon name="hero-plus-circle" class="size-5" /> Add “{String.trim(@query)}”
        </button>
      </div>

      <.form
        :if={@new_form}
        for={@new_form}
        id="new-item-form"
        phx-change="validate_new"
        phx-submit="create"
        class="mt-2 space-y-1 rounded-xl border border-base-300 bg-base-200/50 p-4"
      >
        <.input field={@new_form[:name]} type="text" label="Name" />
        <.input
          field={@new_form[:tracking]}
          type="select"
          label="Track stock as"
          options={[{"A count (e.g. apples)", :count}, {"A level: plenty, low, empty", :level}]}
        />
        <.input
          field={@new_form[:usual_amount]}
          type="number"
          label="Usual amount to buy"
          min="1"
        />
        <div class="flex gap-2 pt-2">
          <button type="submit" class="btn btn-primary">Add item</button>
          <button type="button" phx-click="cancel_add" class="btn btn-ghost">Cancel</button>
        </div>
      </.form>

      <p
        :if={@items == [] and String.trim(@query) == ""}
        class="mt-10 text-center text-base-content/60"
      >
        No items yet. Type a name above to add your first one.
      </p>

      <ul id="items" class="mt-4 divide-y divide-base-300 rounded-xl border border-base-300">
        <li :for={item <- @items} id={"item-#{item.id}"} class="px-4 py-3">
          <div class="flex items-center gap-3">
            <div class="min-w-0 flex-1">
              <div class="truncate font-medium">{item.name}</div>
              <div
                data-role="stock"
                class={[
                  "text-sm",
                  item.empty? && "font-medium text-error",
                  !item.empty? && "text-base-content/70"
                ]}
              >
                {stock_label(item)}
              </div>
            </div>

            <.stock_controls item={item} />

            <button
              type="button"
              phx-click="edit"
              phx-value-id={item.id}
              aria-label={"Edit #{item.name}"}
              class="inline-flex size-10 shrink-0 items-center justify-center rounded-full text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </button>
          </div>

          <.form
            :if={@editing == item.id}
            for={@edit_form}
            id="edit-item-form"
            phx-change="validate_edit"
            phx-submit="update"
            class="mt-3 space-y-1 rounded-xl bg-base-200/50 p-4"
          >
            <.input field={@edit_form[:name]} type="text" label="Name" />
            <.input
              field={@edit_form[:usual_amount]}
              type="number"
              label="Usual amount to buy"
              min="1"
            />
            <div class="flex items-center gap-2 pt-2">
              <button type="submit" class="btn btn-primary">Save</button>
              <button type="button" phx-click="cancel_edit" class="btn btn-ghost">Cancel</button>
              <button
                type="button"
                phx-click="delete"
                data-confirm={"Delete #{item.name}?"}
                class="btn btn-ghost ml-auto text-error"
              >
                Delete
              </button>
            </div>
          </.form>
        </li>
      </ul>

      <div
        :if={@undo}
        id="undo"
        class="fixed inset-x-4 bottom-20 z-20 mx-auto flex max-w-md items-center justify-between gap-3 rounded-xl bg-neutral px-4 py-3 text-neutral-content shadow-lg"
        role="status"
      >
        <span class="truncate">{@undo.name} marked empty</span>
        <button type="button" phx-click="undo" class="font-semibold uppercase tracking-wide">
          Undo
        </button>
      </div>
    </Layouts.app>
    """
  end

  attr :item, Item, required: true

  defp stock_controls(%{item: %Item{tracking: :count}} = assigns) do
    ~H"""
    <div class="flex shrink-0 items-center gap-1">
      <.control phx-click="change_count" phx-value-id={@item.id} phx-value-delta="-1" label="One less">
        <.icon name="hero-minus" class="size-5" />
      </.control>
      <.control phx-click="change_count" phx-value-id={@item.id} phx-value-delta="1" label="One more">
        <.icon name="hero-plus" class="size-5" />
      </.control>
      <.empty_button :if={!@item.empty?} item={@item} />
    </div>
    """
  end

  defp stock_controls(%{item: %Item{tracking: :level}} = assigns) do
    ~H"""
    <div class="flex shrink-0 items-center gap-1">
      <.control
        :for={level <- [:plenty, :low]}
        phx-click="set_level"
        phx-value-id={@item.id}
        phx-value-level={level}
        active={@item.stock_level == level}
        label={"Set #{level}"}
      >
        <span class="px-1 text-sm font-medium">{level |> to_string() |> String.capitalize()}</span>
      </.control>
      <.empty_button :if={!@item.empty?} item={@item} />
    </div>
    """
  end

  attr :item, Item, required: true

  defp empty_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="mark_empty"
      phx-value-id={@item.id}
      class="inline-flex h-10 items-center rounded-full border border-error/40 px-3 text-sm font-medium text-error transition hover:bg-error/10 active:scale-95"
    >
      Empty
    </button>
    """
  end

  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-value-delta phx-value-level)
  slot :inner_block, required: true

  defp control(assigns) do
    ~H"""
    <button
      type="button"
      aria-label={@label}
      class={[
        "inline-flex h-10 min-w-10 items-center justify-center rounded-full transition active:scale-95",
        @active && "bg-primary text-primary-content",
        !@active && "bg-base-200 text-base-content hover:bg-base-300"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
