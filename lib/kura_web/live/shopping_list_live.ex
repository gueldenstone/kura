defmodule KuraWeb.ShoppingListLive do
  use KuraWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Shopping list")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:shopping_list}>
      <h1 class="text-2xl font-semibold tracking-tight">Shopping list</h1>
      <p class="mt-2 text-base-content/70">Your shopping list will show up here.</p>
    </Layouts.app>
    """
  end
end
