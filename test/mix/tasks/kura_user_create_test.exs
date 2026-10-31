defmodule Mix.Tasks.Kura.User.CreateTest do
  use Kura.DataCase

  alias Kura.Accounts.User
  alias Mix.Tasks.Kura.User.Create

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp sign_in(username, password) do
    strategy = AshAuthentication.Info.strategy!(User, :password)

    AshAuthentication.Strategy.action(strategy, :sign_in, %{
      "username" => username,
      "password" => password
    })
  end

  test "creates an account that can sign in" do
    Create.run(["lukas", "--password", "correct horse battery"])

    assert_received {:mix_shell, :info, [message]}
    assert message =~ "lukas"
    assert {:ok, _user} = sign_in("lukas", "correct horse battery")
  end

  test "prompts for the password when none is given" do
    send(self(), {:mix_shell_input, :prompt, "correct horse battery"})

    Create.run(["lukas"])

    assert {:ok, _user} = sign_in("lukas", "correct horse battery")
  end

  test "reports an invalid account instead of creating it" do
    assert_raise Mix.Error, ~r/password/i, fn ->
      Create.run(["lukas", "--password", "short"])
    end

    assert {:error, _} = sign_in("lukas", "short")
  end

  test "requires a username" do
    assert_raise Mix.Error, ~r/username/i, fn -> Create.run([]) end
  end
end
