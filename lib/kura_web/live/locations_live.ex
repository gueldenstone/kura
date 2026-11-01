defmodule KuraWeb.LocationsLive do
  use KuraWeb, :live_view

  alias Kura.Inventory
  alias Kura.Inventory.Location

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Locations")
      |> assign(editing: nil, edit_form: nil)
      |> assign_new_form()
      |> load()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_new", %{"location" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.new_form.source, params)
    {:noreply, assign(socket, new_form: to_form(form))}
  end

  def handle_event("create", %{"location" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.new_form.source, params: params) do
      {:ok, _location} -> {:noreply, socket |> assign_new_form() |> load()}
      {:error, form} -> {:noreply, assign(socket, new_form: to_form(form))}
    end
  end

  def handle_event("edit", %{"id" => id}, %{assigns: %{editing: id}} = socket) do
    {:noreply, assign(socket, editing: nil, edit_form: nil)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    with_location(socket, id, fn location ->
      form = AshPhoenix.Form.for_update(location, :update, as: "location", actor: actor(socket))
      {:noreply, assign(socket, editing: location.id, edit_form: to_form(form))}
    end)
  end

  def handle_event("validate_edit", %{"location" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.edit_form.source, params)
    {:noreply, assign(socket, edit_form: to_form(form))}
  end

  def handle_event("update", %{"location" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.edit_form.source, params: params) do
      {:ok, _location} -> {:noreply, socket |> assign(editing: nil, edit_form: nil) |> load()}
      {:error, form} -> {:noreply, assign(socket, edit_form: to_form(form))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with_location(socket, id, fn location ->
      case Inventory.delete_location(location, actor: actor(socket)) do
        :ok ->
          {:noreply, socket |> assign(editing: nil, edit_form: nil) |> load()}

        {:error, error} ->
          {:noreply,
           put_flash(socket, :error, "Could not delete #{location.name}: #{reason(error)}")}
      end
    end)
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "kitchen:changed"}, socket) do
    {:noreply, load(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp actor(socket), do: socket.assigns.current_user

  defp assign_new_form(socket) do
    form = AshPhoenix.Form.for_create(Location, :create, as: "location", actor: actor(socket))
    assign(socket, new_form: to_form(form))
  end

  defp load(socket),
    do: assign(socket, :locations, Inventory.list_locations!(actor: actor(socket)))

  # A place can vanish while this page is open, for example when the other person deletes it.
  defp with_location(socket, id, fun) do
    case Inventory.get_location(id, actor: actor(socket)) do
      {:ok, location} ->
        fun.(location)

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "That place no longer exists")
         |> assign(editing: nil, edit_form: nil)
         |> load()}
    end
  end

  defp reason(%{errors: errors}),
    do: errors |> Enum.map(&Map.get(&1, :message)) |> Enum.reject(&is_nil/1) |> Enum.join(", ")

  defp reason(_error), do: "something went wrong"

  defp items_label(1), do: "1 item"
  defp items_label(count), do: "#{count} items"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:locations}
      open_count={@open_count}
    >
      <h1 class="font-display text-4xl leading-none font-bold tracking-tight">Locations</h1>
      <p class="mt-1 text-sm text-base-content/60">
        Where things live: a drawer, a shelf, the fridge.
      </p>

      <.form
        for={@new_form}
        id="new-location-form"
        phx-change="validate_new"
        phx-submit="create"
        class="mt-4 flex items-start gap-2"
      >
        <div class="min-w-0 flex-1">
          <.input
            field={@new_form[:name]}
            id="new-location-name"
            type="text"
            placeholder="New place"
            autocomplete="off"
            class="h-12 w-full rounded-full border-0 bg-base-100 px-5 text-base shadow-card outline-none placeholder:text-base-content/45 focus:ring-2 focus:ring-primary/40"
          />
        </div>
        <button type="submit" class="btn btn-primary h-12 rounded-full px-6">Add</button>
      </.form>

      <p :if={@locations == []} class="mt-14 text-center text-base-content/55">
        <span class="block text-5xl">🏷️</span>
        <span class="mt-3 block font-display text-xl text-base-content">No places yet</span>
        Add one above, or create it while editing an item.
      </p>

      <ul id="locations" class="mt-4 grid grid-cols-1 gap-2.5">
        <li
          :for={location <- @locations}
          id={"location-#{location.id}"}
          class="rounded-box bg-base-100 py-2 pr-2.5 pl-4 shadow-card"
        >
          <div class="flex items-center gap-3">
            <button
              type="button"
              phx-click="edit"
              phx-value-id={location.id}
              aria-label={"Rename #{location.name}"}
              class="flex min-w-0 flex-1 items-center gap-2 rounded-lg py-1.5 text-left transition active:opacity-70"
            >
              <span class="truncate text-[17px] font-bold">{location.name}</span>
            </button>
            <span data-role="item-count" class="shrink-0 text-sm text-base-content/55">
              {items_label(location.item_count)}
            </span>
            <button
              type="button"
              phx-click="delete"
              phx-value-id={location.id}
              data-confirm={delete_question(location)}
              aria-label={"Delete #{location.name}"}
              class="grid size-10 shrink-0 place-items-center rounded-full text-error transition hover:bg-error/10 active:scale-90"
            >
              <.icon name="hero-trash" class="size-5" />
            </button>
          </div>

          <.form
            :if={@editing == location.id}
            for={@edit_form}
            id="edit-location-form"
            phx-change="validate_edit"
            phx-submit="update"
            class="mt-2 mb-1 space-y-1 rounded-2xl bg-base-200 p-4"
          >
            <.input field={@edit_form[:name]} type="text" label="Name" />
            <div class="flex items-center gap-2 pt-2">
              <button type="submit" class="btn btn-primary rounded-full">Save</button>
              <button
                type="button"
                phx-click="edit"
                phx-value-id={location.id}
                class="btn btn-ghost rounded-full"
              >
                Cancel
              </button>
            </div>
          </.form>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  defp delete_question(%{item_count: 0, name: name}), do: "Delete #{name}?"

  defp delete_question(%{item_count: count, name: name}),
    do: "Delete #{name}? It is taken off #{items_label(count)}."
end
