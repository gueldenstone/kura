defmodule KuraWeb.ShoppingListLive do
  use KuraWeb, :live_view

  import KuraWeb.InventoryComponents

  alias Kura.Inventory
  alias Kura.Inventory.{Item, ShoppingList}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Shopping list")
      |> assign(query: "", new_form: nil)
      |> assign_search_form()
      |> load()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply, socket |> assign(query: query, new_form: nil) |> assign_search_form() |> load()}
  end

  def handle_event("add", %{"id" => id}, socket) do
    case Inventory.get_item(id, actor: actor(socket)) do
      {:ok, item} ->
        ShoppingList.put_on_list(item, actor(socket))
        {:noreply, socket |> assign(query: "") |> assign_search_form() |> load()}

      {:error, _} ->
        {:noreply, load(socket)}
    end
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
      {:ok, item} ->
        ShoppingList.put_on_list(item, actor(socket))

        {:noreply, socket |> assign(new_form: nil, query: "") |> assign_search_form() |> load()}

      {:error, form} ->
        {:noreply, assign(socket, new_form: to_form(form))}
    end
  end

  def handle_event("cancel_add", _params, socket) do
    {:noreply, assign(socket, new_form: nil)}
  end

  def handle_event("check", %{"id" => id}, socket) do
    with_entry(socket, id, &Inventory.check_off_entry!(&1, actor: actor(socket)))
  end

  def handle_event("uncheck", %{"id" => id}, socket) do
    with_entry(socket, id, &Inventory.uncheck_entry!(&1, actor: actor(socket)))
  end

  def handle_event("change_quantity", %{"id" => id, "delta" => delta}, socket) do
    with_entry(socket, id, fn
      %{quantity: 1} = entry when delta == "-1" ->
        Inventory.remove_entry!(entry, actor: actor(socket))

      entry ->
        Inventory.change_entry_quantity!(entry, String.to_integer(delta), actor: actor(socket))
    end)
  end

  def handle_event("hide_checked", _params, socket) do
    :ok = ShoppingList.hide_checked(actor(socket))
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "kitchen:changed"}, socket) do
    {:noreply, load(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp actor(socket), do: socket.assigns.current_user

  defp assign_search_form(socket) do
    assign(socket, :search_form, to_form(%{"query" => socket.assigns.query}, as: :search))
  end

  defp load(socket) do
    actor = actor(socket)
    query = socket.assigns.query

    matches =
      if String.trim(query) == "",
        do: [],
        else: Inventory.search_items!(String.trim(query), actor: actor, load: [:on_list?])

    assign(socket,
      open: Inventory.list_open_entries!(actor: actor),
      checked: Inventory.list_checked_entries!(actor: actor),
      suggestions: Enum.reject(matches, & &1.on_list?),
      show_add_prompt?: show_add_prompt?(query, matches)
    )
  end

  # An entry can vanish while this page is open, for example when the other person removes it.
  defp with_entry(socket, id, fun) do
    case Inventory.get_entry(id, actor: actor(socket)) do
      {:ok, entry} -> fun.(entry)
      {:error, _} -> :gone
    end

    {:noreply, load(socket)}
  end

  defp show_add_prompt?(query, matches) do
    name = query |> String.trim() |> String.downcase()
    name != "" and not Enum.any?(matches, &(String.downcase(to_string(&1.name)) == name))
  end

  defp to_buy(0), do: "Nothing to buy"
  defp to_buy(count), do: "#{count} to buy"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:shopping_list}
      open_count={@open_count}
    >
      <h1 class="font-display text-4xl leading-none font-bold tracking-tight">Shopping list</h1>
      <p class="mt-1 text-sm text-base-content/60">{to_buy(length(@open))}</p>

      <.form for={@search_form} id="search-form" phx-change="search" phx-submit="search" class="mt-4">
        <div class="relative">
          <.icon
            name="hero-magnifying-glass"
            class="pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 text-base-content/45"
          />
          <.input
            field={@search_form[:query]}
            type="search"
            placeholder="Add something…"
            autocomplete="off"
            phx-debounce="150"
            class="h-12 w-full rounded-full border-0 bg-base-100 pr-4 pl-12 text-base shadow-card outline-none placeholder:text-base-content/45 focus:ring-2 focus:ring-primary/40"
          />
        </div>
      </.form>

      <div
        :if={@suggestions != [] or (@show_add_prompt? and is_nil(@new_form))}
        id="suggestions"
        class="mb-3 rounded-box bg-base-100 p-1.5 shadow-card"
      >
        <div
          :for={item <- @suggestions}
          id={"suggestion-#{item.id}"}
          class="flex items-center gap-3 border-b border-base-300 p-2.5 last:border-b-0"
        >
          <div class="min-w-0 flex-1">
            <div class="truncate font-bold">{item.name}</div>
            <div class="text-sm text-base-content/60">usual amount {item.usual_amount}</div>
          </div>
          <button
            type="button"
            phx-click="add"
            phx-value-id={item.id}
            aria-label={"Put #{item.name} on the list"}
            class="inline-flex size-10 shrink-0 items-center justify-center rounded-full bg-primary text-primary-content transition hover:brightness-110 active:scale-90"
          >
            <.icon name="hero-plus" class="size-5" />
          </button>
        </div>

        <div :if={@show_add_prompt? and is_nil(@new_form)} id="add-item" class="p-1">
          <button
            type="button"
            phx-click="open_add"
            class="flex w-full items-center gap-3 rounded-2xl border-2 border-dashed border-primary/40 bg-primary/5 px-4 py-3 text-left font-bold text-primary transition hover:bg-primary/10 active:scale-[0.99]"
          >
            <.icon name="hero-plus-circle" class="size-6" /> Add “{String.trim(@query)}” as a new item
          </button>
        </div>
      </div>

      <.new_item_form :if={@new_form} form={@new_form} />

      <p
        :if={@open == [] and @checked == [] and String.trim(@query) == ""}
        class="mt-14 text-center text-base-content/55"
      >
        <span class="block text-5xl">🧺</span>
        <span class="mt-3 block font-display text-xl text-base-content">Your list is empty</span>
        Mark things empty in the inventory, or type above to add something.
      </p>

      <ul id="open-entries" class="mt-4 grid grid-cols-1 gap-2.5">
        <li
          :for={entry <- @open}
          id={"entry-#{entry.id}"}
          class="flex items-center gap-3 rounded-box bg-base-100 py-2.5 pr-3 pl-2.5 shadow-card"
        >
          <button
            type="button"
            phx-click="check"
            phx-value-id={entry.id}
            aria-label={"Check off #{entry.item.name}"}
            class="size-11 shrink-0 rounded-full border-[2.5px] border-primary/55 transition hover:bg-primary/10 active:scale-90"
          />
          <span class="min-w-0 flex-1 truncate text-[17px] font-bold">{entry.item.name}</span>
          <div class="flex shrink-0 items-center gap-1">
            <button
              type="button"
              phx-click="change_quantity"
              phx-value-id={entry.id}
              phx-value-delta="-1"
              aria-label={if entry.quantity == 1, do: "Remove #{entry.item.name}", else: "One less"}
              class={[
                "inline-flex size-[38px] items-center justify-center rounded-full transition active:scale-90",
                entry.quantity == 1 && "bg-error/10 text-error hover:bg-error/20",
                entry.quantity > 1 && "bg-base-300/60 hover:bg-base-300"
              ]}
            >
              <.icon
                name={if entry.quantity == 1, do: "hero-trash", else: "hero-minus"}
                class="size-5"
              />
            </button>
            <span
              data-role="quantity"
              class="min-w-6 text-center text-lg font-extrabold tabular-nums"
            >
              {entry.quantity}
            </span>
            <button
              type="button"
              phx-click="change_quantity"
              phx-value-id={entry.id}
              phx-value-delta="1"
              aria-label="One more"
              class="inline-flex size-[38px] items-center justify-center rounded-full bg-base-300/60 transition hover:bg-base-300 active:scale-90"
            >
              <.icon name="hero-plus" class="size-5" />
            </button>
          </div>
        </li>
      </ul>

      <section :if={@checked != []} id="cart" class="mt-6">
        <div class="mb-2.5 flex items-center justify-between px-1">
          <h2 class="font-display text-xl font-bold">
            In the cart
            <small class="ml-1 font-sans text-sm font-semibold text-base-content/55">{length(@checked)}</small>
          </h2>
          <button
            type="button"
            phx-click="hide_checked"
            class="px-1 py-2 text-[13px] font-extrabold tracking-wide text-primary uppercase"
          >
            Hide checked
          </button>
        </div>
        <ul class="grid grid-cols-1 gap-2.5">
          <li
            :for={entry <- @checked}
            id={"entry-#{entry.id}"}
            class="flex items-center gap-3 rounded-box border-[1.5px] border-dashed border-base-300 py-2.5 pr-4 pl-2.5"
          >
            <button
              type="button"
              phx-click="uncheck"
              phx-value-id={entry.id}
              aria-label={"Put #{entry.item.name} back on the list"}
              class="grid size-11 shrink-0 place-items-center rounded-full bg-secondary text-secondary-content transition active:scale-90"
            >
              <.icon name="hero-check" class="size-6" />
            </button>
            <span class="min-w-0 flex-1 truncate text-[17px] font-bold text-base-content/55 line-through decoration-[1.5px]">
              {entry.item.name}
            </span>
            <span class="font-bold text-base-content/55 tabular-nums">× {entry.quantity}</span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
