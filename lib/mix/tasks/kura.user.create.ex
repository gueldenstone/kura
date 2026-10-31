defmodule Mix.Tasks.Kura.User.Create do
  @shortdoc "Creates a Kura account"

  @moduledoc """
  Creates an account. There is no sign-up page, so this is how accounts come to exist.

      mix kura.user.create USERNAME [--password PASSWORD]

  Without `--password` the password is read from a prompt. Passwords must have at
  least 8 characters.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [password: :string])

    username =
      case rest do
        [username] -> username
        _ -> Mix.raise("Expected exactly one username: mix kura.user.create USERNAME")
      end

    password = opts[:password] || prompt_password()

    case Kura.Accounts.create_user(%{username: username, password: password}, authorize?: false) do
      {:ok, user} -> Mix.shell().info("Created account #{user.username}")
      {:error, error} -> Mix.raise("Could not create account: #{Exception.message(error)}")
    end
  end

  defp prompt_password do
    "Password: " |> Mix.shell().prompt() |> String.trim()
  end
end
