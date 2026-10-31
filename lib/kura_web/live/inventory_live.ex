defmodule KuraWeb.InventoryLive do
  use KuraWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Inventory")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:inventory}>
      <h1 class="text-2xl font-semibold tracking-tight">Inventory</h1>
      <p class="mt-2 text-base-content/70">Your kitchen inventory will show up here.</p>
    </Layouts.app>
    """
  end
end
