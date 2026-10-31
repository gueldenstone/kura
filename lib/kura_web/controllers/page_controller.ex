defmodule KuraWeb.PageController do
  use KuraWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
