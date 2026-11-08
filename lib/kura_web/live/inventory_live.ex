defmodule KuraWeb.InventoryLive do
  use KuraWeb, :live_view

  import KuraWeb.InventoryComponents

  alias Kura.Inventory
  alias Kura.Inventory.{Item, ShoppingList}
  alias KuraWeb.ItemFormComponent

  @undo_timeout 10_000

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Inventory")
      |> assign(query: "", adding: nil, editing: nil, edit_item: nil, undo: nil)
      |> assign(selecting?: false, selected: MapSet.new())
      |> assign(checking: nil, check_item: nil, check_choices: nil)
      |> assign(tags: [])
      |> start_check_on_check_route(params)
      |> assign_search_form()
      |> load_items()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket |> assign(query: query, adding: nil) |> assign_search_form() |> load_items()}
  end

  def handle_event("quick_add", %{"search" => %{"query" => query}}, socket) do
    socket = socket |> assign(query: query, adding: nil) |> assign_search_form() |> load_items()

    if show_add_prompt?(query, socket.assigns.items) do
      {:noreply, open_add_form(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("check_next", _params, socket) do
    {socket, _moved?} = move_check(socket, 1)
    {:noreply, socket}
  end

  def handle_event(
        "not_here",
        _params,
        %{
          assigns: %{
            check_item: %Item{} = item,
            checking: %{scope: {:location, location}} = checking
          }
        } = socket
      ) do
    # The other phone may have taken the item out of this place already.
    with {:ok, link} <- Inventory.get_item_location(item.id, location.id, actor: actor(socket)) do
      :ok = Inventory.remove_item_location(link, actor: actor(socket))
    end

    {:noreply,
     socket
     |> assign(checking: %{checking | ids: List.delete(checking.ids, item.id)})
     |> refresh_check()}
  end

  def handle_event("not_here", _params, socket), do: {:noreply, socket}

  def handle_event("check_prev", _params, socket) do
    {socket, _moved?} = move_check(socket, -1)
    {:noreply, socket}
  end

  # The swipe hook animates the card away and wants to know whether there was a card to go to.
  def handle_event("swipe_next", _params, socket) do
    {socket, moved?} = move_check(socket, 1)
    {:reply, %{moved: moved?}, socket}
  end

  def handle_event("swipe_prev", _params, socket) do
    {socket, moved?} = move_check(socket, -1)
    {:reply, %{moved: moved?}, socket}
  end

  def handle_event("confirm_stock", _params, %{assigns: %{check_item: %Item{} = item}} = socket) do
    Inventory.confirm_item_stock!(item, actor: actor(socket))
    {socket, _moved?} = move_check(socket, 1)
    {:noreply, socket}
  end

  def handle_event("confirm_stock", _params, socket), do: {:noreply, socket}

  def handle_event("delete_checked", _params, %{assigns: %{check_item: %Item{} = item}} = socket) do
    :ok = Inventory.delete_item(item, actor: actor(socket))
    {:noreply, socket |> assign(undo: nil) |> load_items()}
  end

  def handle_event("delete_checked", _params, socket), do: {:noreply, socket}

  def handle_event("start_select", _params, socket) do
    {:noreply,
     assign(socket,
       selecting?: true,
       selected: MapSet.new(),
       adding: nil,
       editing: nil,
       edit_item: nil,
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

  def handle_event("edit", %{"id" => id}, %{assigns: %{editing: id}} = socket) do
    {:noreply, assign(socket, editing: nil, edit_item: nil)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    with_item(socket, id, fn item ->
      {:noreply, assign(socket, editing: item.id, edit_item: item, adding: nil)}
    end)
  end

  def handle_event("edit_checked", _params, %{assigns: %{check_item: %Item{} = item}} = socket) do
    {:noreply, assign(socket, editing: item.id, edit_item: item)}
  end

  def handle_event("edit_checked", _params, socket), do: {:noreply, socket}

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

  def handle_event("put_on_list", %{"id" => id}, socket) do
    with_item(socket, id, fn item ->
      ShoppingList.put_on_list(item, actor(socket))
      {:noreply, load_items(socket)}
    end)
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

  def handle_info({:item_form, :saved, _item}, %{assigns: %{adding: %{}}} = socket) do
    {:noreply,
     socket
     |> assign(adding: nil, query: "")
     |> assign_search_form()
     |> load_items()}
  end

  def handle_info({:item_form, :saved, _item}, socket) do
    {:noreply, socket |> assign(editing: nil, edit_item: nil) |> load_items()}
  end

  def handle_info({:item_form, :deleted, _item}, socket) do
    {:noreply, socket |> assign(editing: nil, edit_item: nil, undo: nil) |> load_items()}
  end

  def handle_info({:item_form, :closed}, socket) do
    {:noreply, assign(socket, adding: nil, editing: nil, edit_item: nil)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp open_add_form(socket) do
    prefill = ItemFormComponent.prefill(socket.assigns.query, socket.assigns.tags)
    assign(socket, adding: prefill, editing: nil, edit_item: nil)
  end

  defp load_tags(socket),
    do: assign(socket, :tags, Inventory.list_tags!(actor: actor(socket)))

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

    socket |> assign(:items, items) |> load_tags() |> refresh_check() |> refresh_check_choices()
  end

  # The check lives on its own routes, behind the middle tab: `/inventory/check` picks a place
  # and `/inventory/check/:scope` walks it, where the scope is a location id, "unplaced" or "all".
  defp start_check_on_check_route(%{assigns: %{live_action: :check}} = socket, %{"scope" => scope}) do
    case check_scope(socket, scope) do
      {:ok, scope, items} ->
        socket
        |> assign(checking: %{ids: Enum.map(items, & &1.id), index: 0, scope: scope})
        |> refresh_check()

      :error ->
        socket
        |> put_flash(:error, "That place no longer exists")
        |> push_navigate(to: ~p"/inventory/check")
    end
  end

  defp start_check_on_check_route(%{assigns: %{live_action: :check_pick}} = socket, _params),
    do: assign_check_choices(socket)

  defp start_check_on_check_route(socket, _params), do: socket

  defp check_scope(socket, "all"),
    do: {:ok, :all, Inventory.list_items_to_check!(actor: actor(socket))}

  defp check_scope(socket, "unplaced"),
    do: {:ok, :unplaced, Inventory.list_items_to_check_unplaced!(actor: actor(socket))}

  defp check_scope(socket, id) do
    case Inventory.get_location(id, actor: actor(socket)) do
      {:ok, location} ->
        {:ok, {:location, location},
         Inventory.list_items_to_check_at!(location.id, actor: actor(socket))}

      {:error, _} ->
        :error
    end
  end

  defp assign_check_choices(socket) do
    actor = actor(socket)

    assign(socket,
      check_choices: %{
        locations: Inventory.list_locations!(actor: actor, load: [:stock_item_count]),
        unplaced: length(Inventory.list_items_to_check_unplaced!(actor: actor)),
        all: length(Inventory.list_items_to_check!(actor: actor))
      }
    )
  end

  defp scope_title(:all), do: "Everything"
  defp scope_title(:unplaced), do: "Not placed yet"
  defp scope_title({:location, location}), do: to_string(location.name)

  # An item that left the place being walked (the other phone took it out) is not checked here.
  defp in_scope?(item, {:location, location}),
    do: Enum.any?(item.locations, &(&1.id == location.id))

  defp in_scope?(_item, _scope), do: true

  # The other places of an item that is checked in one place: its stock counts them all.
  defp other_places(item, %{scope: {:location, location}}) do
    item.locations |> Enum.reject(&(&1.id == location.id)) |> Enum.map(&to_string(&1.name))
  end

  defp other_places(_item, _checking), do: []

  defp refresh_check_choices(%{assigns: %{live_action: :check_pick}} = socket),
    do: assign_check_choices(socket)

  defp refresh_check_choices(socket), do: socket

  # Loads the item the check is on. Items that were deleted meanwhile drop out of the check.
  defp refresh_check(%{assigns: %{checking: nil}} = socket), do: socket

  defp refresh_check(%{assigns: %{checking: %{ids: ids, index: index} = checking}} = socket) do
    with id when is_binary(id) <- Enum.at(ids, index),
         {:ok, item} <-
           Inventory.get_item(id,
             actor: actor(socket),
             load: [:empty?, :on_list?, :tags, :locations]
           ),
         true <- in_scope?(item, checking.scope) do
      assign(socket, check_item: item)
    else
      false ->
        socket
        |> assign(checking: %{checking | ids: List.delete_at(ids, index)})
        |> refresh_check()

      nil ->
        assign(socket, check_item: nil)

      {:error, _} ->
        socket
        |> assign(checking: %{checking | ids: List.delete_at(ids, index)})
        |> refresh_check()
    end
  end

  # Index `length(ids)` is the "all checked" card.
  defp move_check(%{assigns: %{checking: %{ids: ids, index: index} = checking}} = socket, step) do
    target = index + step

    if target < 0 or target > length(ids) do
      {socket, false}
    else
      {socket |> assign(checking: %{checking | index: target}) |> refresh_check(), true}
    end
  end

  defp move_check(socket, _step), do: {socket, false}

  attr :id, :string, required: true
  attr :href, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :count, :integer, required: true

  defp pick_card(assigns) do
    ~H"""
    <.link
      navigate={@href}
      id={@id}
      class="flex items-center gap-3 rounded-box bg-base-100 py-3.5 pr-3 pl-4 shadow-card transition active:scale-[0.99]"
    >
      <span class="min-w-0 flex-1">
        <span class="block truncate text-[17px] font-bold">{@title}</span>
        <span :if={@subtitle} class="block truncate text-[13px] text-base-content/55">{@subtitle}</span>
      </span>
      <span data-role="item-count" class="shrink-0 text-sm text-base-content/55">
        {if @count == 1, do: "1 item", else: "#{@count} items"}
      </span>
      <.icon name="hero-chevron-right" class="size-5 shrink-0 text-base-content/40" />
    </.link>
    """
  end

  defp check_percent(%{ids: [], index: _}), do: 100

  defp check_percent(%{ids: ids, index: index}),
    do: round(min(index, length(ids)) / length(ids) * 100)

  defp checked_ago(checked_at) do
    case DateTime.diff(DateTime.utc_now(), checked_at, :day) do
      0 -> "today"
      1 -> "yesterday"
      days when days < 60 -> "#{days} days ago"
      days -> "#{div(days, 30)} months ago"
    end
  end

  # An item can vanish while this page is open, for example when the other person deletes it.
  defp with_item(socket, id, fun) do
    case Inventory.get_item(id, actor: actor(socket), load: [:tags, :locations]) do
      {:ok, item} ->
        fun.(item)

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "That item no longer exists")
         |> assign(editing: nil, edit_item: nil, undo: nil)
         |> load_items()}
    end
  end

  defp mark_empty(socket, item) do
    marked = Inventory.mark_item_empty!(item, actor: actor(socket))

    undo = %{
      id: item.id,
      name: Item.label(item),
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
    name != "" and not Enum.any?(items, &(String.downcase(Item.label(&1)) == name))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={if @checking || @live_action == :check_pick, do: :check, else: :inventory}
      open_count={@open_count}
    >
      <div
        :if={@checking}
        id="check-overlay"
        phx-hook="Swipe"
        class="flex min-h-[calc(100dvh-15rem)] flex-col"
      >
        <div class="flex items-baseline justify-between gap-3">
          <h1 class="font-display text-4xl leading-none font-bold tracking-tight">Check stock</h1>
          <span data-role="check-progress" class="text-sm font-bold text-base-content/60 tabular-nums">
            {min(@checking.index + 1, length(@checking.ids))} of {length(@checking.ids)}
          </span>
        </div>
        <div class="mt-1 flex items-center justify-between gap-3">
          <p
            data-role="check-scope"
            class="min-w-0 truncate text-sm font-semibold text-base-content/60"
          >
            {scope_title(@checking.scope)}
          </p>
          <.link
            navigate={~p"/inventory/check"}
            id="change-place"
            class="shrink-0 text-[13px] font-bold text-primary"
          >
            Change place
          </.link>
        </div>
        <div class="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-base-300">
          <div
            class="h-full rounded-full bg-primary transition-[width] duration-300 motion-reduce:transition-none"
            style={"width: #{check_percent(@checking)}%"}
          />
        </div>

        <div class="grid flex-1 place-items-center py-6">
          <div
            :if={@check_item}
            id={"check-card-#{@check_item.id}"}
            data-swipe-card
            phx-mounted={
              JS.transition({"ease-out duration-200", "opacity-0 scale-95", "opacity-100 scale-100"},
                time: 200
              )
            }
            class="w-full max-w-md touch-pan-y rounded-box bg-base-100 p-6 text-center shadow-card select-none"
          >
            <h2 class="font-display text-3xl leading-tight font-bold break-words">
              {@check_item.name}
            </h2>
            <p
              :if={@check_item.tags != []}
              data-role="tags"
              class="mt-0.5 text-base font-semibold text-base-content/60"
            >
              {Item.tag_line(@check_item)}
            </p>
            <p data-role="checked-ago" class="mt-1 text-sm text-base-content/55">
              Stock last changed {checked_ago(@check_item.stock_checked_at)}
            </p>
            <p
              :if={other_places(@check_item, @checking) != []}
              data-role="also-in"
              class="mt-3 rounded-2xl bg-primary/10 px-4 py-2.5 text-sm font-semibold text-primary"
            >
              Also in {Enum.join(other_places(@check_item, @checking), ", ")}. Count what is there too,
              the stock is for the whole item.
            </p>
            <div class="mt-6 flex justify-center">
              <.stock_control item={@check_item} />
            </div>
            <button
              type="button"
              id="confirm-stock"
              phx-click="confirm_stock"
              class="mt-6 h-14 w-full rounded-full bg-primary text-base font-extrabold text-primary-content shadow-sm transition hover:brightness-110 active:scale-[0.98]"
            >
              Still right
            </button>
            <button
              :if={match?({:location, _}, @checking.scope)}
              type="button"
              id="not-here"
              phx-click="not_here"
              class="mt-3 h-10 w-full rounded-full text-[13px] font-bold text-base-content/60 transition hover:bg-base-300/60 active:scale-95"
            >
              Not here anymore
            </button>
            <div class="mt-1 flex items-center justify-between gap-2">
              <button
                type="button"
                id="check-prev"
                phx-click="check_prev"
                disabled={@checking.index == 0}
                aria-label="Previous item"
                class="grid size-11 place-items-center rounded-full bg-base-300/60 transition hover:bg-base-300 active:scale-90 disabled:opacity-30"
              >
                <.icon name="hero-chevron-left" class="size-5" />
              </button>
              <button
                type="button"
                id="edit-checked"
                phx-click="edit_checked"
                class="h-11 rounded-full px-4 text-[13px] font-bold transition hover:bg-base-300/60 active:scale-95"
              >
                Edit
              </button>
              <button
                type="button"
                id="delete-checked"
                phx-click="delete_checked"
                data-confirm={"Delete #{@check_item.name}?"}
                class="h-11 rounded-full px-4 text-[13px] font-bold text-error transition hover:bg-error/10 active:scale-95"
              >
                Delete
              </button>
              <button
                type="button"
                id="check-next"
                phx-click="check_next"
                aria-label="Next item"
                class="grid h-11 place-items-center rounded-full bg-base-300/60 px-4 text-sm font-bold transition hover:bg-base-300 active:scale-95"
              >
                Next
              </button>
            </div>
          </div>

          <div
            :if={is_nil(@check_item)}
            id="check-done"
            data-swipe-card
            class="w-full max-w-md rounded-box bg-base-100 p-8 text-center shadow-card"
          >
            <span class="block text-5xl">{if @checking.ids == [], do: "🫙", else: "🎉"}</span>
            <h2 class="mt-3 font-display text-2xl font-bold">
              {if @checking.ids == [], do: "Nothing here", else: "All checked"}
            </h2>
            <p class="mt-1 text-base-content/60">
              {if @checking.ids == [],
                do: "No items to check in this place.",
                else: "Nothing left to look at."}
            </p>
            <.link
              navigate={~p"/inventory/check"}
              class="mt-6 grid h-12 w-full place-items-center rounded-full bg-primary font-extrabold text-primary-content transition hover:brightness-110 active:scale-[0.98]"
            >
              Done
            </.link>
          </div>
        </div>
      </div>

      <div :if={@live_action == :check_pick && @check_choices} id="check-picker">
        <h1 class="font-display text-4xl leading-none font-bold tracking-tight">Check stock</h1>
        <p class="mt-1 text-sm text-base-content/60">
          Pick a place and go through what lives there.
        </p>

        <ul class="mt-5 grid grid-cols-1 gap-2.5">
          <li :for={location <- @check_choices.locations}>
            <.pick_card
              id={"pick-#{location.id}"}
              href={~p"/inventory/check/#{location.id}"}
              title={to_string(location.name)}
              count={location.stock_item_count}
            />
          </li>
          <li>
            <.pick_card
              id="pick-unplaced"
              href={~p"/inventory/check/unplaced"}
              title="Not placed yet"
              subtitle="Items without a place"
              count={@check_choices.unplaced}
            />
          </li>
          <li>
            <.pick_card
              id="pick-all"
              href={~p"/inventory/check/all"}
              title="Everything"
              subtitle="All items, the stalest first"
              count={@check_choices.all}
            />
          </li>
        </ul>

        <p :if={@check_choices.locations == []} class="mt-6 text-center text-sm text-base-content/55">
          No places yet. Add them under
          <.link navigate={~p"/locations"} class="font-bold text-primary">More, Locations</.link>
          or while editing an item.
        </p>
      </div>

      <div :if={is_nil(@checking) and @live_action != :check_pick} id="inventory-page">
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

        <div :if={show_add_prompt?(@query, @items) and is_nil(@adding)} id="add-item" class="mb-3">
          <button
            type="button"
            phx-click="open_add"
            class="flex w-full items-center gap-3 rounded-box border-2 border-dashed border-primary/40 bg-primary/5 px-4 py-3.5 text-left font-bold text-primary transition hover:bg-primary/10 active:scale-[0.99]"
          >
            <.icon name="hero-plus-circle" class="size-6" /> Add “{String.trim(@query)}”
          </button>
        </div>

        <.live_component
          :if={@adding}
          module={ItemFormComponent}
          id="item-form-new"
          item={nil}
          prefill={@adding}
          variant={:inline}
          current_user={@current_user}
        />

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
                  MapSet.member?(@selected, item.id) &&
                    "border-primary bg-primary text-primary-content",
                  !MapSet.member?(@selected, item.id) && "border-base-content/30"
                ]}>
                  <.icon
                    :if={MapSet.member?(@selected, item.id)}
                    name="hero-check-micro"
                    class="size-4"
                  />
                </span>
                <.item_title item={item} />
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
                <.item_title
                  item={item}
                  class={item.empty? && "text-base-content/60"}
                  locations={@query != ""}
                />
                <span
                  :if={item.on_list? and item.tracking != :none}
                  data-role="on-list"
                  title="On the shopping list"
                  class="grid size-[22px] shrink-0 place-items-center rounded-full bg-primary text-primary-content"
                >
                  <.icon name="hero-shopping-cart-solid" class="size-2.5" />
                </span>
              </button>
              <.stock_control item={item} />
            </div>

            <.live_component
              :if={!@selecting? and @editing == item.id}
              module={ItemFormComponent}
              id={"item-form-#{item.id}"}
              item={@edit_item}
              variant={:inline}
              current_user={@current_user}
            />
          </li>
        </ul>
      </div>

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

      <.live_component
        :if={@checking && @editing}
        module={ItemFormComponent}
        id={"item-form-#{@editing}"}
        item={@edit_item}
        variant={:sheet}
        current_user={@current_user}
      />

      <div
        :if={@undo}
        id="undo"
        phx-mounted={slide_in()}
        phx-remove={slide_out()}
        class="motion-reduce:transition-none fixed inset-x-4 bottom-24 z-40 mx-auto flex max-w-md items-center justify-between gap-3 rounded-box bg-neutral px-5 py-3.5 text-sm font-semibold text-neutral-content shadow-2xl"
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

  # Items without stock have nothing to adjust; their one action is putting them on the list.
  defp stock_control(%{item: %Item{tracking: :none}} = assigns) do
    ~H"""
    <button
      type="button"
      data-role="stock"
      phx-click="put_on_list"
      phx-value-id={@item.id}
      disabled={@item.on_list?}
      class={[
        "flex h-9 shrink-0 items-center gap-1.5 rounded-full px-3 text-[13px] font-bold transition active:scale-95",
        !@item.on_list? && "bg-primary/10 text-primary hover:bg-primary/20",
        @item.on_list? && "bg-primary text-primary-content shadow-sm"
      ]}
    >
      <.icon
        name={if @item.on_list?, do: "hero-shopping-cart-solid", else: "hero-plus"}
        class="size-4"
      />
      {if @item.on_list?, do: "On list", else: "Add to list"}
    </button>
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
