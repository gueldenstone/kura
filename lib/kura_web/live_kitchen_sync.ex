defmodule KuraWeb.LiveKitchenSync do
  @moduledoc """
  Runs on every signed-in LiveView and keeps two things in step with the kitchen:

    * `@open_count`, the number of open shopping list entries, shown on the tab bar;
    * the saved copy each phone keeps for offline use, pushed as a `"kura:snapshot"` event when the
      page opens and again after every change (see `Kura.Offline` and `assets/js/offline`).

  It subscribes to the kitchen's change topic and, for each change, updates both and then lets the
  LiveView's own `handle_info/2` run too.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_event: 3]

  def on_mount(:default, _params, _session, socket) do
    socket =
      if connected?(socket) do
        KuraWeb.Endpoint.subscribe("kitchen:changed")
        socket |> sync() |> attach_hook(:kitchen_sync, :handle_info, &refresh/2)
      else
        assign(socket, :open_count, open_count(socket))
      end

    {:cont, socket}
  end

  defp refresh(%Phoenix.Socket.Broadcast{topic: "kitchen:changed"}, socket),
    do: {:cont, sync(socket)}

  defp refresh(_message, socket), do: {:cont, socket}

  defp sync(socket) do
    socket
    |> assign(:open_count, open_count(socket))
    |> push_event("kura:snapshot", Kura.Offline.snapshot(socket.assigns.current_user))
  end

  defp open_count(socket) do
    Kura.Inventory.ShoppingEntry
    |> Ash.Query.for_read(:open, %{}, actor: socket.assigns.current_user)
    |> Ash.count!(actor: socket.assigns.current_user)
  end
end
