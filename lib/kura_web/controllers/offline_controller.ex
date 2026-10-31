defmodule KuraWeb.OfflineController do
  @moduledoc """
  The pieces the phones need to work without a connection: the offline screens (a static shell
  that the service worker keeps), the saved copy of the data, and the endpoint that accepts the
  check-offs queued while offline.
  """
  use KuraWeb, :controller

  alias Kura.Offline

  plug :require_user when action in [:state, :sync]
  plug :require_offline_header when action == :sync

  def shell(conn, _params), do: render(conn, :shell)

  def state(conn, _params) do
    json(conn, Offline.snapshot(conn.assigns.current_user))
  end

  def sync(conn, params) do
    actor = conn.assigns.current_user
    result = Offline.apply_changes(actor, List.wrap(params["changes"]))

    json(conn, Map.put(result, :snapshot, Offline.snapshot(actor)))
  end

  defp require_user(%{assigns: %{current_user: %{}}} = conn, _opts), do: conn

  defp require_user(conn, _opts) do
    conn |> put_status(:unauthorized) |> json(%{error: "not signed in"}) |> halt()
  end

  # A cross-site form cannot set custom headers, and a cross-site script cannot either without a
  # CORS preflight that this app never answers. Together with the SameSite session cookie that
  # keeps other sites from queuing check-offs on a visitor's behalf.
  defp require_offline_header(conn, _opts) do
    case get_req_header(conn, "x-kura-offline") do
      ["1"] -> conn
      _ -> conn |> put_status(:forbidden) |> json(%{error: "missing offline header"}) |> halt()
    end
  end
end
