defmodule KuraWeb.PageController do
  use KuraWeb, :controller

  def shopping_list(conn, _params), do: redirect(conn, to: ~p"/")
end
