defmodule KuraWeb.ItemFormComponent do
  @moduledoc """
  The one screen for adding and editing an item: name, tags, stock (new items only) and buying
  details. It renders `variant={:inline}` as a card inside a page, or `variant={:sheet}` as a sheet
  over it. The parent tells it what to show and hears back through messages to its own process:

    * `{:item_form, :saved, item}`
    * `{:item_form, :deleted, item}`
    * `{:item_form, :closed}`

  Give each item its own `id` (the component keeps its form between renders) and pass `item={nil}`
  with a `prefill` (see `prefill/2`) for a new one.
  """
  use KuraWeb, :live_component

  import KuraWeb.InventoryComponents, only: [chip_picker: 1]

  alias Kura.Inventory
  alias Kura.Inventory.Item

  @kinds ~w(tag location)

  @doc """
  Turns what was typed in a search box into a name and tags: words that are the name of a tag
  become tags ("cumin ground" is "cumin" tagged "ground"), the rest is the name.
  """
  def prefill(query, tags) do
    words = query |> String.trim() |> String.split(~r/\s+/, trim: true)

    {tag_ids, name_words} =
      Enum.reduce(words, {[], []}, fn word, {ids, rest} ->
        case Enum.find(tags, &(String.downcase(to_string(&1.name)) == String.downcase(word))) do
          nil -> {ids, [word | rest]}
          tag -> {[tag.id | ids], rest}
        end
      end)

    case Enum.reverse(name_words) do
      [] -> %{name: String.trim(query), tag_ids: []}
      rest -> %{name: Enum.join(rest, " "), tag_ids: tag_ids |> Enum.reverse() |> Enum.uniq()}
    end
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    socket = if Map.has_key?(socket.assigns, :form), do: socket, else: init(socket)
    {:ok, load_options(socket)}
  end

  defp init(%{assigns: %{item: nil, prefill: prefill}} = socket) do
    form =
      AshPhoenix.Form.for_create(Item, :create,
        as: "item",
        actor: actor(socket),
        params: %{
          "name" => prefill.name,
          "tracking" => "none",
          "stock_level" => "plenty",
          "stock_count" => "1",
          "usual_amount" => "1",
          "auto_replenish" => "false"
        }
      )

    assign(socket,
      form: to_form(form),
      tag_ids: prefill.tag_ids,
      location_ids: Map.get(prefill, :location_ids, []),
      tag_query: "",
      location_query: ""
    )
  end

  defp init(%{assigns: %{item: item}} = socket) do
    form = AshPhoenix.Form.for_update(item, :update, as: "item", actor: actor(socket))

    assign(socket,
      form: to_form(form),
      tag_ids: Enum.map(item.tags, & &1.id),
      location_ids: Enum.map(item.locations, & &1.id),
      tag_query: "",
      location_query: ""
    )
  end

  @impl true
  def handle_event("validate", %{"item" => params} = all, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)

    {:noreply,
     socket
     |> assign(form: to_form(form))
     |> assign(:tag_query, Map.get(all, "tag_query", socket.assigns.tag_query))
     |> assign(:location_query, Map.get(all, "location_query", socket.assigns.location_query))}
  end

  def handle_event("save", %{"item" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, item} ->
        send(self(), {:item_form, :saved, item})
        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  def handle_event("set", %{"field" => field, "choice" => choice}, socket),
    do: {:noreply, revalidate(socket, %{field => choice})}

  def handle_event("step", %{"field" => field, "delta" => delta}, socket) do
    current = socket |> value(field) |> String.to_integer()
    stepped = max(current + String.to_integer(delta), minimum(field))
    {:noreply, revalidate(socket, %{field => to_string(stepped)})}
  end

  def handle_event("delete", _params, %{assigns: %{item: %Item{} = item}} = socket) do
    :ok = Inventory.delete_item(item, actor: actor(socket))
    send(self(), {:item_form, :deleted, item})
    {:noreply, socket}
  end

  def handle_event("close", _params, socket) do
    send(self(), {:item_form, :closed})
    {:noreply, socket}
  end

  def handle_event("add_chip", %{"kind" => kind, "id" => id}, socket) when kind in @kinds do
    {ids, query} = {ids_key(kind), query_key(kind)}
    {:noreply, socket |> assign(ids, Enum.uniq(socket.assigns[ids] ++ [id])) |> assign(query, "")}
  end

  def handle_event("remove_chip", %{"kind" => kind, "id" => id}, socket) when kind in @kinds do
    ids = ids_key(kind)
    {:noreply, assign(socket, ids, List.delete(socket.assigns[ids], id))}
  end

  def handle_event("create_chip", %{"kind" => kind}, socket) when kind in @kinds do
    {:noreply, create_chip(socket, kind, String.trim(socket.assigns[query_key(kind)]))}
  end

  # Enter in a search box: take the one that is typed out or the only one left; make a new one only
  # when nothing similar exists.
  def handle_event("chip_enter", %{"kind" => kind}, socket) when kind in @kinds do
    query = String.trim(socket.assigns[query_key(kind)])
    downcased = String.downcase(query)
    options = socket.assigns[options_key(kind)]
    chosen = socket.assigns[ids_key(kind)]
    typed = Enum.find(options, &(String.downcase(to_string(&1.name)) == downcased))

    candidates =
      Enum.filter(options, fn option ->
        option.id not in chosen and
          String.contains?(String.downcase(to_string(option.name)), downcased)
      end)

    cond do
      query == "" ->
        {:noreply, socket}

      typed ->
        handle_event("add_chip", %{"kind" => kind, "id" => typed.id}, socket)

      match?([_], candidates) ->
        handle_event("add_chip", %{"kind" => kind, "id" => hd(candidates).id}, socket)

      # Several similar ones: the person is choosing, not naming something new.
      candidates != [] ->
        {:noreply, socket}

      true ->
        {:noreply, create_chip(socket, kind, query)}
    end
  end

  defp actor(socket), do: socket.assigns.current_user

  defp load_options(socket) do
    assign(socket,
      tags: Inventory.list_tags!(actor: actor(socket)),
      locations: Inventory.list_locations!(actor: actor(socket))
    )
  end

  defp ids_key("tag"), do: :tag_ids
  defp ids_key("location"), do: :location_ids
  defp query_key("tag"), do: :tag_query
  defp query_key("location"), do: :location_query
  defp options_key("tag"), do: :tags
  defp options_key("location"), do: :locations

  defp create_chip(socket, _kind, ""), do: socket

  defp create_chip(socket, kind, name) do
    case create(kind, name, actor(socket)) do
      {:ok, created} ->
        {ids, query} = {ids_key(kind), query_key(kind)}

        socket
        |> assign(ids, Enum.uniq(socket.assigns[ids] ++ [created.id]))
        |> assign(query, "")
        |> load_options()

      {:error, _} ->
        load_options(socket)
    end
  end

  defp create("tag", name, actor), do: Inventory.create_tag(%{name: name}, actor: actor)
  defp create("location", name, actor), do: Inventory.create_location(%{name: name}, actor: actor)

  # The buttons change the form like a typed value would: all current values plus the new one.
  defp revalidate(socket, changes) do
    params = Map.merge(current_params(socket), changes)
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    assign(socket, form: to_form(form))
  end

  defp current_params(socket) do
    for field <- ~w(name tracking stock_level stock_count usual_amount auto_replenish),
        into: %{} do
      {field, value(socket, field)}
    end
  end

  defp value(socket, field) do
    socket.assigns.form.source
    |> AshPhoenix.Form.value(String.to_existing_atom(field))
    |> to_string()
  end

  defp minimum("stock_count"), do: 0
  defp minimum(_field), do: 1

  defp new?(item), do: is_nil(item)

  defp tracking_hint("level"), do: "Plenty, low or empty, like walnuts."
  defp tracking_hint("count"), do: "A number, like apples."
  defp tracking_hint(_none), do: "No stock, only bought when needed, like birthday candles."

  # Items without stock never run out, so auto-replenish has nothing to react to.
  defp tracks_stock?(form, nil), do: to_string(form[:tracking].value) != "none"
  defp tracks_stock?(_form, %Item{tracking: tracking}), do: tracking != :none

  defp title(nil), do: "New item"
  defp title(item), do: "Edit #{item.name}"

  @impl true
  def render(%{variant: :sheet} = assigns) do
    ~H"""
    <div
      id={@id}
      phx-window-keydown="close"
      phx-key="Escape"
      phx-target={@myself}
      class="fixed inset-0 z-50 flex items-end justify-center bg-black/40 sm:items-center sm:p-6"
    >
      <div
        phx-mounted={
          JS.transition(
            {"ease-out duration-200", "translate-y-6 opacity-0", "translate-y-0 opacity-100"},
            time: 200
          )
        }
        class="flex h-dvh w-full flex-col bg-base-200 motion-reduce:transition-none sm:h-auto sm:max-h-[90dvh] sm:max-w-md sm:rounded-box sm:shadow-2xl"
      >
        <div class="flex items-center gap-2 px-4 pt-[max(0.75rem,env(safe-area-inset-top))] pb-2">
          <button
            type="button"
            phx-click="close"
            phx-target={@myself}
            aria-label="Close"
            class="grid size-10 place-items-center rounded-full text-base-content/70 transition hover:bg-base-300/60 active:scale-90"
          >
            <.icon name="hero-x-mark" class="size-6" />
          </button>
          <h2 class="min-w-0 truncate font-display text-2xl font-bold">{title(@item)}</h2>
        </div>

        <div class="flex-1 overflow-y-auto px-4 pt-2 pb-6">
          <.item_form {assigns} />
        </div>

        <div class="flex items-center gap-2 border-t border-base-300 bg-base-200 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <.delete_button :if={!new?(@item)} item={@item} target={@myself} class="h-12" />
          <button
            type="button"
            phx-click="close"
            phx-target={@myself}
            class="btn btn-ghost h-12 rounded-full"
          >
            Cancel
          </button>
          <button
            type="submit"
            form="item-form"
            class="btn btn-primary h-12 flex-1 rounded-full text-base"
          >
            {if new?(@item), do: "Add item", else: "Save"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "p-4",
        new?(@item) && "mb-3 rounded-box bg-base-100 shadow-card",
        !new?(@item) && "mt-3 rounded-2xl bg-base-200"
      ]}
    >
      <.item_form {assigns} />
      <div class="mt-5 flex items-center gap-2">
        <button type="submit" form="item-form" class="btn btn-primary rounded-full">
          {if new?(@item), do: "Add item", else: "Save"}
        </button>
        <button
          type="button"
          phx-click="close"
          phx-target={@myself}
          class="btn btn-ghost rounded-full"
        >
          Cancel
        </button>
        <.delete_button :if={!new?(@item)} item={@item} target={@myself} class="ml-auto" />
      </div>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :target, :any, required: true
  attr :class, :string, default: nil

  defp delete_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="delete"
      phx-target={@target}
      data-confirm={"Delete #{@item.name}?"}
      class={["btn btn-ghost rounded-full text-error", @class]}
    >
      Delete
    </button>
    """
  end

  defp item_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="item-form"
      phx-change="validate"
      phx-submit="save"
      phx-target={@myself}
      class="space-y-6"
    >
      <section>
        <.input field={@form[:name]} type="text" label="Name" autocomplete="off" />
      </section>

      <section>
        <.chip_picker
          kind="tag"
          label="Tags"
          placeholder="Search or add a tag"
          options={@tags}
          selected={@tag_ids}
          query={@tag_query}
          target={@myself}
        />
      </section>

      <section>
        <.chip_picker
          kind="location"
          label="Where it lives"
          placeholder="Search or add a place"
          options={@locations}
          selected={@location_ids}
          query={@location_query}
          target={@myself}
        />
      </section>

      <section :if={new?(@item)}>
        <.heading>Stock</.heading>
        <input type="hidden" name="item[tracking]" value={@form[:tracking].value} />
        <input type="hidden" name="item[stock_level]" value={@form[:stock_level].value} />
        <input type="hidden" name="item[stock_count]" value={@form[:stock_count].value} />
        <div class="flex gap-0.5 rounded-full bg-base-300/60 p-[3px]">
          <.choice
            :for={{value, label} <- [{"none", "None"}, {"level", "Level"}, {"count", "Count"}]}
            field="tracking"
            value={value}
            current={to_string(@form[:tracking].value)}
            target={@myself}
            class="flex-1"
          >
            {label}
          </.choice>
        </div>
        <p data-role="tracking-hint" class="mt-1.5 text-[13px] text-base-content/55">
          {tracking_hint(to_string(@form[:tracking].value))}
        </p>

        <div
          :if={to_string(@form[:tracking].value) == "level"}
          class="mt-3 flex gap-0.5 rounded-full bg-base-300/60 p-[3px]"
        >
          <.choice
            :for={{value, label, tone} <- level_options()}
            field="stock_level"
            value={value}
            current={to_string(@form[:stock_level].value)}
            tone={tone}
            target={@myself}
            class="flex-1"
          >
            {label}
          </.choice>
        </div>

        <div
          :if={to_string(@form[:tracking].value) == "count"}
          class="mt-3 flex items-center justify-between"
        >
          <span class="font-bold">In stock now</span>
          <.stepper field="stock_count" value={@form[:stock_count].value} target={@myself} />
        </div>
      </section>

      <section>
        <.heading>Buying</.heading>
        <input type="hidden" name="item[usual_amount]" value={@form[:usual_amount].value} />
        <div class="flex items-center justify-between">
          <span class="font-bold">Usual amount to buy</span>
          <.stepper field="usual_amount" value={@form[:usual_amount].value} target={@myself} />
        </div>

        <label
          :if={tracks_stock?(@form, @item)}
          class="mt-4 flex cursor-pointer items-center justify-between gap-4"
        >
          <span class="min-w-0">
            <span class="block font-bold">Auto-replenish</span>
            <span class="block text-[13px] text-base-content/55">
              Goes on the shopping list when it runs out
            </span>
          </span>
          <input type="hidden" name="item[auto_replenish]" value="false" />
          <input
            type="checkbox"
            name="item[auto_replenish]"
            value="true"
            checked={Phoenix.HTML.Form.normalize_value("checkbox", @form[:auto_replenish].value)}
            class="peer sr-only"
          />
          <span class="relative h-8 w-14 shrink-0 rounded-full bg-base-300 transition peer-checked:bg-primary peer-focus-visible:ring-2 peer-focus-visible:ring-primary/50 after:absolute after:top-1 after:left-1 after:size-6 after:rounded-full after:bg-white after:shadow after:transition-transform peer-checked:after:translate-x-6 motion-reduce:transition-none"></span>
        </label>
      </section>
    </.form>
    """
  end

  slot :inner_block, required: true

  defp heading(assigns) do
    ~H"""
    <h3 class="mb-2 text-[11px] font-extrabold tracking-wider text-base-content/50 uppercase">
      {render_slot(@inner_block)}
    </h3>
    """
  end

  attr :field, :string, required: true
  attr :value, :string, required: true
  attr :current, :string, required: true
  attr :target, :any, required: true
  attr :tone, :string, default: "bg-base-100 text-base-content shadow-sm"
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp choice(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set"
      phx-target={@target}
      phx-value-field={@field}
      phx-value-choice={@value}
      aria-pressed={to_string(@current == @value)}
      class={[
        "h-10 rounded-full px-4 text-[14px] font-bold transition active:scale-95",
        @class,
        @current == @value && @tone,
        @current != @value && "text-base-content/60 hover:text-base-content"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :field, :string, required: true
  attr :value, :any, required: true
  attr :target, :any, required: true

  defp stepper(assigns) do
    ~H"""
    <div class="flex items-center rounded-full bg-base-300/60 p-[3px]">
      <button
        type="button"
        phx-click="step"
        phx-target={@target}
        phx-value-field={@field}
        phx-value-delta="-1"
        aria-label="One less"
        class="grid size-10 place-items-center rounded-full transition active:scale-90"
      >
        <.icon name="hero-minus" class="size-5" />
      </button>
      <span data-role={@field} class="min-w-10 text-center text-lg font-extrabold tabular-nums">
        {@value}
      </span>
      <button
        type="button"
        phx-click="step"
        phx-target={@target}
        phx-value-field={@field}
        phx-value-delta="1"
        aria-label="One more"
        class="grid size-10 place-items-center rounded-full transition active:scale-90"
      >
        <.icon name="hero-plus" class="size-5" />
      </button>
    </div>
    """
  end

  defp level_options do
    [
      {"plenty", "Plenty", "bg-success text-success-content shadow-sm"},
      {"low", "Low", "bg-warning text-warning-content shadow-sm"},
      {"empty", "Empty", "bg-error text-error-content shadow-sm"}
    ]
  end
end
