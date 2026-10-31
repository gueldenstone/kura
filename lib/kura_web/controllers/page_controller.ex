defmodule KuraWeb.PageController do
  use KuraWeb, :controller

  def home(%{assigns: %{current_user: %{}}} = conn, _params),
    do: redirect(conn, to: ~p"/shopping-list")

  def home(conn, _params), do: redirect(conn, to: ~p"/sign-in")
end
