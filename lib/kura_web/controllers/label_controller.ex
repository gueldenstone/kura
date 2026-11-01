defmodule KuraWeb.LabelController do
  @moduledoc """
  Downloads the names of the selected inventory items as a CSV for label printing.
  """
  use KuraWeb, :controller

  alias Kura.Inventory
  alias Kura.Inventory.LabelExport

  plug :require_user

  def export(conn, params) do
    ids = params |> Map.get("ids", []) |> List.wrap() |> Enum.filter(&valid_id?/1)
    actor = conn.assigns.current_user
    items = Inventory.list_items_by_ids!(ids, actor: actor)
    inventory = Inventory.search_items!("", actor: actor)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="labels.csv"))
    |> send_resp(200, LabelExport.csv(items, inventory))
  end

  defp valid_id?(id), do: is_binary(id) and match?({:ok, _}, Ecto.UUID.cast(id))

  defp require_user(%{assigns: %{current_user: %{}}} = conn, _opts), do: conn
  defp require_user(conn, _opts), do: conn |> redirect(to: ~p"/sign-in") |> halt()
end
