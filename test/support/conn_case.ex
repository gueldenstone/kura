defmodule KuraWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use KuraWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint KuraWeb.Endpoint

      use KuraWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import KuraWeb.ConnCase
    end
  end

  setup tags do
    Kura.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @password "correct horse battery"

  @doc "Creates a user named `username` and returns it with its password."
  def create_user(username \\ "lukas") do
    user =
      Kura.Accounts.create_user!(%{username: username, password: @password}, authorize?: false)

    %{user: user, password: @password}
  end

  @doc """
  Setup helper: creates a user and signs them in by storing a real session token.
  """
  def log_in_user(%{conn: conn}) do
    %{user: user, password: password} = create_user()
    strategy = AshAuthentication.Info.strategy!(Kura.Accounts.User, :password)

    {:ok, signed_in} =
      AshAuthentication.Strategy.action(strategy, :sign_in, %{
        "username" => to_string(user.username),
        "password" => password
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(signed_in)

    %{conn: conn, user: signed_in, password: password}
  end
end
