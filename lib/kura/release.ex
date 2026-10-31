defmodule Kura.Release do
  @moduledoc """
  Tasks for the production release, where Mix is not available.

      bin/kura eval "Kura.Release.migrate()"
      bin/kura eval 'Kura.Release.create_user("name", "password")'
  """
  @app :kura

  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc "Creates an account, like `mix kura.user.create`. There is no sign-up page."
  def create_user(username, password) do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    case Kura.Accounts.create_user(%{username: username, password: password}, authorize?: false) do
      {:ok, user} -> IO.puts("Created account #{user.username}")
      {:error, error} -> IO.puts("Could not create account: #{Exception.message(error)}")
    end
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
