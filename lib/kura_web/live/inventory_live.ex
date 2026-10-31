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
  defp stock_label(%Item{tracking: :count, stock_count: count}), do: "#{count} in stock"
  defp stock_label(%Item{stock_level: :low}), do: "Running low"
  defp stock_label(%Item{stock_level: :plenty}), do: "Plenty"

  defp tile_text(%Item{emoji: emoji}) when is_binary(emoji), do: emoji
  defp tile_text(%Item{name: name}), do: name |> to_string() |> String.first() |> String.upcase()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:inventory}>
      <h1 class="font-display text-4xl leading-none font-bold tracking-tight">Inventory</h1>

      <.form for={@search_form} id="search-form" phx-change="search" phx-submit="search" class="mt-5">
        <div class="relative">
          <.icon
            name="hero-magnifying-glass"
            class="pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 text-base-content/45"
          />
          <.input
            field={@search_form[:query]}
            type="search"
            placeholder="Search or add an item"
            autocomplete="off"
            phx-debounce="150"
            class="h-12 w-full rounded-full border-0 bg-base-100 pr-4 pl-12 text-base shadow-card outline-none placeholder:text-base-content/45 focus:ring-2 focus:ring-primary/40"
          />
        </div>
      </.form>

      <div :if={show_add_prompt?(@query, @items) and is_nil(@new_form)} id="add-item" class="mb-3">
        <button
          type="button"
          phx-click="open_add"
          class="flex w-full items-center gap-3 rounded-box border-2 border-dashed border-primary/40 bg-primary/5 px-4 py-3.5 text-left font-bold text-primary transition hover:bg-primary/10 active:scale-[0.99]"
        >
          <.icon name="hero-plus-circle" class="size-6" /> Add “{String.trim(@query)}”
        </button>
      </div>

      <.form
        :if={@new_form}
        for={@new_form}
        id="new-item-form"
        phx-change="validate_new"
        phx-submit="create"
        class="mb-3 space-y-1 rounded-box bg-base-100 p-4 shadow-card"
      >
        <.input field={@new_form[:name]} type="text" label="Name" />
        <.input field={@new_form[:emoji]} type="text" label="Emoji (optional)" placeholder="🍎" />
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
          <button type="submit" class="btn btn-primary rounded-full">Add item</button>
          <button type="button" phx-click="cancel_add" class="btn btn-ghost rounded-full">
            Cancel
          </button>
        </div>
      </.form>

      <p
        :if={@items == [] and String.trim(@query) == ""}
        class="mt-14 text-center text-base-content/55"
      >
        <span class="block text-5xl">🧺</span>
        <span class="mt-3 block font-display text-xl text-base-content">An empty basket</span>
        No items yet. Type a name above to add your first one.
      </p>

      <ul id="items" class="mt-5 grid gap-3">
        <li
          :for={item <- @items}
          id={"item-#{item.id}"}
          class="rounded-box bg-base-100 p-3.5 shadow-card"
        >
          <div class="flex items-center gap-3">
            <span
              data-role="tile"
              class={[
                "grid size-12 shrink-0 place-items-center rounded-2xl bg-base-300/60 text-2xl font-bold text-base-content/70",
                item.empty? && "opacity-60 grayscale"
              ]}
            >
              {tile_text(item)}
            </span>
            <div class="min-w-0 flex-1">
              <div class="truncate text-[17px] font-bold">{item.name}</div>
              <div
                data-role="stock"
                class={[
                  "text-sm",
                  item.empty? && "font-bold text-error",
                  !item.empty? && "text-base-content/60"
                ]}
              >
                {stock_label(item)}
              </div>
            </div>
            <button
              type="button"
              phx-click="edit"
              phx-value-id={item.id}
              aria-label={"Edit #{item.name}"}
              class="inline-flex size-10 shrink-0 items-center justify-center rounded-full text-base-content/45 transition hover:bg-base-300/60 hover:text-base-content active:scale-95"
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </button>
          </div>

          <.stock_controls item={item} />

          <.form
            :if={@editing == item.id}
            for={@edit_form}
            id="edit-item-form"
            phx-change="validate_edit"
            phx-submit="update"
            class="mt-3 space-y-1 rounded-2xl bg-base-200 p-4"
          >
            <.input field={@edit_form[:name]} type="text" label="Name" />
            <.input
              field={@edit_form[:emoji]}
              type="text"
              label="Emoji (optional)"
              placeholder="🍎"
            />
            <.input
              field={@edit_form[:usual_amount]}
              type="number"
              label="Usual amount to buy"
              min="1"
            />
            <div class="flex items-center gap-2 pt-2">
              <button type="submit" class="btn btn-primary rounded-full">Save</button>
              <button type="button" phx-click="cancel_edit" class="btn btn-ghost rounded-full">
                Cancel
              </button>
              <button
                type="button"
                phx-click="delete"
                data-confirm={"Delete #{item.name}?"}
                class="btn btn-ghost ml-auto rounded-full text-error"
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
        class="fixed inset-x-4 bottom-24 z-20 mx-auto flex max-w-md items-center justify-between gap-3 rounded-box bg-neutral px-5 py-3.5 text-sm font-semibold text-neutral-content shadow-2xl"
        role="status"
      >
        <span class="truncate">{@undo.name} marked empty</span>
        <button
          type="button"
          phx-click="undo"
          class="font-extrabold tracking-wider text-primary uppercase dark:text-neutral-content"
        >
          Undo
        </button>
      </div>
    </Layouts.app>
    """
  end

  attr :item, Item, required: true

  defp stock_controls(%{item: %Item{tracking: :count}} = assigns) do
    ~H"""
    <div class="mt-3 flex items-center justify-between">
      <div class="flex items-center gap-2.5">
        <.round_button
          phx-click="change_count"
          phx-value-id={@item.id}
          phx-value-delta="-1"
          label="One less"
        >
          <.icon name="hero-minus" class="size-5" />
        </.round_button>
        <span class="min-w-6 text-center text-xl font-extrabold tabular-nums">{@item.stock_count}</span>
        <.round_button
          phx-click="change_count"
          phx-value-id={@item.id}
          phx-value-delta="1"
          label="One more"
        >
          <.icon name="hero-plus" class="size-5" />
        </.round_button>
      </div>
      <.empty_button :if={!@item.empty?} item={@item} />
    </div>
    """
  end

  defp stock_controls(%{item: %Item{tracking: :level}} = assigns) do
    ~H"""
    <div class="mt-3 flex items-center justify-between">
      <div class="flex gap-0.5 rounded-full bg-base-300/60 p-[3px]">
        <button
          :for={level <- [:plenty, :low]}
          type="button"
          phx-click="set_level"
          phx-value-id={@item.id}
          phx-value-level={level}
          aria-pressed={to_string(@item.stock_level == level)}
          class={[
            "rounded-full px-4 py-2 text-[13px] font-bold transition active:scale-95",
            @item.stock_level == level && "bg-secondary text-secondary-content shadow-sm",
            @item.stock_level != level && "text-base-content/60 hover:text-base-content"
          ]}
        >
          {level |> to_string() |> String.capitalize()}
        </button>
      </div>
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
      class="inline-flex h-10 items-center rounded-full bg-error/10 px-5 text-sm font-extrabold text-error transition hover:bg-error/20 active:scale-95"
    >
      Empty
    </button>
    """
  end

  attr :label, :string, required: true
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-value-delta)
  slot :inner_block, required: true

  defp round_button(assigns) do
    ~H"""
    <button
      type="button"
      aria-label={@label}
      class="inline-flex size-10 items-center justify-center rounded-full bg-base-300/60 text-base-content transition hover:bg-base-300 active:scale-90"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
