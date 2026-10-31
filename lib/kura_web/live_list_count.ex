defmodule KuraWeb.LiveListCount do
  @moduledoc """
  Keeps `@open_count`, the number of open shopping list entries, up to date on every signed-in
  LiveView, so the tab bar can show it. It subscribes to the kitchen's change topic and, for each
  change, recounts and then lets the LiveView's own `handle_info/2` run too.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: KuraWeb.Endpoint.subscribe("kitchen:changed")

    socket =
      socket
      |> assign(:open_count, open_count(socket))
      |> attach_hook(:open_count, :handle_info, &refresh/2)

    {:cont, socket}
  end

  defp refresh(%Phoenix.Socket.Broadcast{topic: "kitchen:changed"}, socket),
    do: {:cont, assign(socket, :open_count, open_count(socket))}

  defp refresh(_message, socket), do: {:cont, socket}

  defp open_count(socket) do
    Kura.Inventory.ShoppingEntry
    |> Ash.Query.for_read(:open, %{}, actor: socket.assigns.current_user)
    |> Ash.count!(actor: socket.assigns.current_user)
  end
end
