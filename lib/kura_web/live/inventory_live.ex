defmodule KuraWeb.InventoryLive do
  use KuraWeb, :live_view

  import KuraWeb.InventoryComponents

  alias Kura.Inventory
  alias Kura.Inventory.{Item, ShoppingList}

  @undo_timeout 10_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Inventory")
      |> assign(query: "", new_form: nil, editing: nil, edit_form: nil, undo: nil)
      |> assign(selecting?: false, selected: MapSet.new())
      |> assign_search_form()
      |> load_items()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket |> assign(query: query, new_form: nil) |> assign_search_form() |> load_items()}
  end

  def handle_event("quick_add", %{"search" => %{"query" => query}}, socket) do
    socket = socket |> assign(query: query, new_form: nil) |> assign_search_form() |> load_items()

    if show_add_prompt?(query, socket.assigns.items) do
      {:noreply, open_add_form(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start_select", _params, socket) do
    {:noreply,
     assign(socket,
       selecting?: true,
       selected: MapSet.new(),
       new_form: nil,
       editing: nil,
       edit_form: nil,
       undo: nil
     )}
  end

  def handle_event("stop_select", _params, socket) do
    {:noreply, assign(socket, selecting?: false, selected: MapSet.new())}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, selected: selected)}
  end

  def handle_event("select_all", _params, socket) do
    visible = MapSet.new(socket.assigns.items, & &1.id)
    {:noreply, assign(socket, selected: MapSet.union(socket.assigns.selected, visible))}
  end

  def handle_event("select_none", _params, socket) do
    {:noreply, assign(socket, selected: MapSet.new())}
  end

  def handle_event("open_add", _params, socket), do: {:noreply, open_add_form(socket)}

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

  def handle_event("edit", %{"id" => id}, %{assigns: %{editing: id}} = socket) do
    {:noreply, assign(socket, editing: nil, edit_form: nil)}
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
      delta = String.to_integer(delta)

      cond do
        # Stepping down to 0 is the same as marking the item empty.
        delta < 0 and item.stock_count > 0 and item.stock_count + delta <= 0 ->
          mark_empty(socket, item)

        delta < 0 and item.stock_count == 0 ->
          {:noreply, socket}

        true ->
          Inventory.change_item_count!(item, delta, actor: actor(socket))
          {:noreply, load_items(socket)}
      end
    end)
  end

  def handle_event("set_level", %{"id" => id, "level" => level}, socket) do
    with_item(socket, id, fn item ->
      Inventory.set_item_level!(item, String.to_existing_atom(level), actor: actor(socket))
      {:noreply, load_items(socket)}
    end)
  end

  def handle_event("mark_empty", %{"id" => id}, socket) do
    with_item(socket, id, &mark_empty(socket, &1))
  end

  def handle_event(
        "add_to_list",
        _params,
        %{assigns: %{undo: %{offer_list?: true} = undo}} = socket
      ) do
    with_item(socket, undo.id, fn item ->
      added =
        case ShoppingList.put_on_list(item, actor(socket)) do
          {:created, entry} -> entry
          {:existing, _entry} -> nil
        end

      undo = %{undo | offer_list?: false, added_entry: added}
      {:noreply, socket |> show_undo(undo) |> load_items()}
    end)
  end

  def handle_event("add_to_list", _params, socket), do: {:noreply, socket}

  def handle_event("undo", _params, %{assigns: %{undo: %{} = undo}} = socket) do
    with_item(socket, undo.id, fn item ->
      restore_stock(item, undo.previous, actor(socket))
      remove_added_entry(undo.added_entry, actor(socket))
      {:noreply, socket |> assign(undo: nil) |> load_items()}
    end)
  end

  def handle_event("undo", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "kitchen:changed"}, socket) do
    {:noreply, load_items(socket)}
  end

  def handle_info({:expire_undo, ref}, %{assigns: %{undo: %{ref: ref}}} = socket) do
    {:noreply, assign(socket, undo: nil)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp open_add_form(socket) do
    form =
      AshPhoenix.Form.for_create(Item, :create,
        as: "item",
        actor: actor(socket),
        params: %{
          "name" => String.trim(socket.assigns.query),
          "tracking" => "level",
          "stock_level" => "plenty",
          "stock_count" => "1"
        }
      )

    assign(socket, new_form: to_form(form))
  end

  defp actor(socket), do: socket.assigns.current_user

  defp assign_search_form(socket) do
    assign(socket, :search_form, to_form(%{"query" => socket.assigns.query}, as: :search))
  end

  defp load_items(socket) do
    items =
      Inventory.search_items!(socket.assigns.query,
        actor: actor(socket),
        load: [:empty?, :on_list?]
      )

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

  defp mark_empty(socket, item) do
    marked = Inventory.mark_item_empty!(item, actor: actor(socket))

    undo = %{
      id: item.id,
      name: item.name,
      previous: previous_stock(item),
      added_entry: marked.__metadata__.added_entry,
      offer_list?: !marked.auto_replenish
    }

    {:noreply, socket |> show_undo(undo) |> load_items()}
  end

  # The undo bar goes away on its own; a newer bar is not closed by an older timer.
  defp show_undo(socket, undo) do
    ref = make_ref()
    Process.send_after(self(), {:expire_undo, ref}, @undo_timeout)
    assign(socket, undo: Map.put(undo, :ref, ref))
  end

  # Bars at the bottom of the screen slide up and fade in, and drop back out when they go.
  defp slide_in do
    JS.transition(
      {"ease-out duration-300", "translate-y-3 opacity-0", "translate-y-0 opacity-100"},
      time: 300
    )
  end

  defp slide_out do
    JS.hide(
      transition:
        {"ease-in duration-200", "translate-y-0 opacity-100", "translate-y-3 opacity-0"},
      time: 200
    )
  end

  defp previous_stock(%Item{tracking: :count, stock_count: count}), do: {:count, count}
  defp previous_stock(%Item{tracking: :level, stock_level: level}), do: {:level, level}

  # Takes back the list entry that "mark empty" created, unless it has been checked off since.
  defp remove_added_entry(nil, _actor), do: :ok

  defp remove_added_entry(%{id: id}, actor) do
    case Inventory.get_entry(id, actor: actor) do
      {:ok, %{checked_at: nil} = entry} -> Inventory.remove_entry!(entry, actor: actor)
      _ -> :ok
    end
  end

  defp restore_stock(item, {:count, count}, actor),
    do: Inventory.set_item_count!(item, count, actor: actor)

  defp restore_stock(item, {:level, level}, actor),
    do: Inventory.set_item_level!(item, level, actor: actor)

  defp show_add_prompt?(query, items) do
    name = query |> String.trim() |> String.downcase()
    name != "" and not Enum.any?(items, &(String.downcase(to_string(&1.name)) == name))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:inventory}
      open_count={@open_count}
    >
      <div class="flex items-center justify-between gap-3">
        <h1 class="font-display text-4xl leading-none font-bold tracking-tight">Inventory</h1>
        <button
          :if={!@selecting? and @items != []}
          type="button"
          id="start-select"
          phx-click="start_select"
          class="h-9 rounded-full bg-base-300/60 px-4 text-[13px] font-bold transition hover:bg-base-300 active:scale-95"
        >
          Select
        </button>
      </div>
      <div :if={@selecting?} class="mt-3 flex items-center gap-1.5">
        <button
          type="button"
          id="select-all"
          phx-click="select_all"
          class="h-9 rounded-full bg-base-300/60 px-4 text-[13px] font-bold transition hover:bg-base-300 active:scale-95"
        >
          Select all
        </button>
        <button
          type="button"
          id="select-none"
          phx-click="select_none"
          class="h-9 rounded-full bg-base-300/60 px-4 text-[13px] font-bold transition hover:bg-base-300 active:scale-95"
        >
          Select none
        </button>
        <button
          type="button"
          id="stop-select"
          phx-click="stop_select"
          class="h-9 rounded-full px-3 text-[13px] font-bold text-base-content/60 transition hover:text-base-content active:scale-95"
        >
          Cancel
        </button>
      </div>

      <.form
        for={@search_form}
        id="search-form"
        phx-change="search"
        phx-submit="quick_add"
        class="mt-5"
      >
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

      <.new_item_form :if={@new_form} form={@new_form} />

      <p
        :if={@items == [] and String.trim(@query) == ""}
        class="mt-14 text-center text-base-content/55"
      >
        <span class="block text-5xl">🧺</span>
        <span class="mt-3 block font-display text-xl text-base-content">An empty basket</span>
        No items yet. Type a name above to add your first one.
      </p>

      <ul id="items" class="mt-5 grid grid-cols-1 gap-2.5">
        <li
          :for={item <- @items}
          id={"item-#{item.id}"}
          class="rounded-box bg-base-100 py-2 pr-2.5 pl-4 shadow-card"
        >
          <div :if={@selecting?} class="flex items-center gap-3">
            <button
              type="button"
              phx-click="toggle_select"
              phx-value-id={item.id}
              role="checkbox"
              aria-checked={to_string(MapSet.member?(@selected, item.id))}
              aria-label={"Select #{item.name}"}
              class="flex min-w-0 flex-1 items-center gap-3 rounded-lg py-1.5 text-left transition active:opacity-70"
            >
              <span class={[
                "grid size-6 shrink-0 place-items-center rounded-full border-2 transition",
                MapSet.member?(@selected, item.id) && "border-primary bg-primary text-primary-content",
                !MapSet.member?(@selected, item.id) && "border-base-content/30"
              ]}>
                <.icon
                  :if={MapSet.member?(@selected, item.id)}
                  name="hero-check-micro"
                  class="size-4"
                />
              </span>
              <span class="truncate text-[17px] font-bold">{item.name}</span>
            </button>
          </div>

          <div :if={!@selecting?} class="flex items-center gap-3">
            <button
              type="button"
              phx-click="edit"
              phx-value-id={item.id}
              aria-label={"Edit #{item.name}"}
              class="flex min-w-0 flex-1 items-center gap-2 rounded-lg py-1.5 text-left transition active:opacity-70"
            >
              <span class={[
                "truncate text-[17px] font-bold",
                item.empty? && "text-base-content/60"
              ]}>
                {item.name}
              </span>
              <span
                :if={item.on_list?}
                data-role="on-list"
                title="On the shopping list"
                class="grid size-[22px] shrink-0 place-items-center rounded-full bg-primary text-primary-content"
              >
                <.icon name="hero-shopping-cart-solid" class="size-2.5" />
              </span>
            </button>
            <.stock_control item={item} />
          </div>

          <.form
            :if={!@selecting? and @editing == item.id}
            for={@edit_form}
            id="edit-item-form"
            phx-change="validate_edit"
            phx-submit="update"
            class="mt-3 space-y-1 rounded-2xl bg-base-200 p-4"
          >
            <.input field={@edit_form[:name]} type="text" label="Name" />
            <.input
              field={@edit_form[:usual_amount]}
              type="number"
              label="Usual amount to buy"
              min="1"
            />
            <.input
              field={@edit_form[:auto_replenish]}
              type="checkbox"
              label="Auto-replenish when empty"
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

      <.form
        :if={@selecting?}
        for={%{}}
        as={:export}
        id="export-form"
        phx-mounted={slide_in()}
        phx-remove={slide_out()}
        method="get"
        action={~p"/inventory/labels.csv"}
        class="motion-reduce:transition-none fixed inset-x-4 bottom-24 z-20 mx-auto flex max-w-md items-center justify-between gap-3 rounded-box bg-neutral px-5 py-3 text-sm font-semibold text-neutral-content shadow-2xl"
      >
        <input :for={id <- @selected} type="hidden" name="ids[]" value={id} />
        <span data-role="selected-count">{MapSet.size(@selected)} selected</span>
        <button
          type="submit"
          phx-click="stop_select"
          disabled={MapSet.size(@selected) == 0}
          class="h-9 rounded-full bg-primary px-4 text-[13px] font-extrabold tracking-wide text-primary-content uppercase transition active:scale-95 disabled:opacity-40"
        >
          Export labels
        </button>
      </.form>

      <div
        :if={@undo}
        id="undo"
        phx-mounted={slide_in()}
        phx-remove={slide_out()}
        class="motion-reduce:transition-none fixed inset-x-4 bottom-24 z-20 mx-auto flex max-w-md items-center justify-between gap-3 rounded-box bg-neutral px-5 py-3.5 text-sm font-semibold text-neutral-content shadow-2xl"
        role="status"
      >
        <span class="truncate">{@undo.name} marked empty</span>
        <div class="flex shrink-0 items-center gap-4">
          <button
            :if={@undo.offer_list?}
            type="button"
            id="add-to-list"
            phx-click="add_to_list"
            class="font-extrabold tracking-wider text-primary uppercase dark:text-neutral-content"
          >
            Add to list
          </button>
          <button
            type="button"
            phx-click="undo"
            class="font-extrabold tracking-wider text-primary uppercase dark:text-neutral-content"
          >
            Undo
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :item, Item, required: true

  defp stock_control(%{item: %Item{tracking: :count}} = assigns) do
    ~H"""
    <div data-role="stock" class="flex shrink-0 items-center gap-1.5">
      <div class="flex items-center rounded-full bg-base-300/60 p-[3px]">
        <.round_button
          phx-click="change_count"
          phx-value-id={@item.id}
          phx-value-delta="-1"
          label="One less"
          disabled={@item.empty?}
        >
          <.icon name="hero-minus" class="size-5" />
        </.round_button>
        <span class={[
          "min-w-8 text-center text-lg font-extrabold tabular-nums",
          @item.empty? && "text-error"
        ]}>
          {@item.stock_count}
        </span>
        <.round_button
          phx-click="change_count"
          phx-value-id={@item.id}
          phx-value-delta="1"
          label="One more"
        >
          <.icon name="hero-plus" class="size-5" />
        </.round_button>
      </div>
      <.empty_button item={@item} />
    </div>
    """
  end

  defp stock_control(%{item: %Item{tracking: :level}} = assigns) do
    ~H"""
    <div data-role="stock" class="flex shrink-0 gap-0.5 rounded-full bg-base-300/60 p-[3px]">
      <button
        :for={{level, label, tone} <- level_options()}
        type="button"
        phx-click={if level == :empty, do: "mark_empty", else: "set_level"}
        phx-value-id={@item.id}
        phx-value-level={level}
        aria-pressed={to_string(@item.stock_level == level)}
        disabled={@item.stock_level == level}
        class={[
          "h-9 rounded-full px-3 text-[13px] font-bold transition active:scale-95",
          @item.stock_level == level && tone,
          @item.stock_level != level && "text-base-content/60 hover:text-base-content"
        ]}
      >
        {label}
      </button>
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
      disabled={@item.empty?}
      class={[
        "h-9 rounded-full px-3 text-[13px] font-bold transition active:scale-95",
        !@item.empty? && "bg-error/10 text-error hover:bg-error/20",
        @item.empty? && "bg-error text-error-content shadow-sm"
      ]}
    >
      Empty
    </button>
    """
  end

  defp level_options do
    [
      {:plenty, "Plenty", "bg-success text-success-content shadow-sm"},
      {:low, "Low", "bg-warning text-warning-content shadow-sm"},
      {:empty, "Empty", "bg-error text-error-content shadow-sm"}
    ]
  end

  attr :label, :string, required: true
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-value-delta disabled)
  slot :inner_block, required: true

  defp round_button(assigns) do
    ~H"""
    <button
      type="button"
      aria-label={@label}
      class="inline-flex size-9 items-center justify-center rounded-full text-base-content transition hover:bg-base-300 active:scale-90 disabled:pointer-events-none disabled:opacity-30"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
