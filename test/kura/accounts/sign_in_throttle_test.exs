defmodule Kura.Accounts.SignInThrottleTest do
  use Kura.DataCase

  alias Kura.Accounts
  alias Kura.Accounts.SignInThrottle
  alias Kura.Accounts.User

  @password "correct horse battery"
  @max SignInThrottle.max_failures()
  @lockout SignInThrottle.lockout_seconds()

  describe "the counter" do
    test "locks a username at the limit, ignoring case, until the lockout is over" do
      for _ <- 1..(@max - 1), do: SignInThrottle.record_failure("Lukas", 1_000)
      assert SignInThrottle.locked_for("lukas", 1_000) == nil

      SignInThrottle.record_failure("lukas", 1_000)

      assert SignInThrottle.locked_for("LUKAS", 1_000) == @lockout
      assert SignInThrottle.locked_for("lukas", 1_000 + @lockout - 1) == 1
      assert SignInThrottle.locked_for("lukas", 1_000 + @lockout) == nil
    end

    test "does not add up failures spread out over more than the lockout period" do
      for _ <- 1..(@max - 1), do: SignInThrottle.record_failure("lukas", 1_000)

      SignInThrottle.record_failure("lukas", 1_000 + @lockout)

      assert SignInThrottle.locked_for("lukas", 1_000 + @lockout) == nil
    end

    test "locks each username on its own" do
      for _ <- 1..@max, do: SignInThrottle.record_failure("lukas", 1_000)

      assert SignInThrottle.locked_for("partner", 1_000) == nil
    end
  end

  describe "password sign-in" do
    setup do
      Accounts.create_user!(%{username: "lukas", password: @password}, authorize?: false)
      %{strategy: AshAuthentication.Info.strategy!(User, :password)}
    end

    test "refuses even the right password after too many wrong ones", %{strategy: strategy} do
      for _ <- 1..@max do
        assert {:error, _} = sign_in(strategy, "lukas", "not the password")
      end

      # The library reports every refusal as "Authentication failed"; the sign-in form test checks
      # the message people see.
      assert {:error, _} = sign_in(strategy, "lukas", @password)
      assert SignInThrottle.locked_for("lukas")
    end

    test "a successful sign-in clears the failures", %{strategy: strategy} do
      for _ <- 1..(@max - 1), do: sign_in(strategy, "lukas", "not the password")
      assert {:ok, _} = sign_in(strategy, "lukas", @password)

      assert {:error, _} = sign_in(strategy, "lukas", "not the password")
      refute SignInThrottle.locked_for("lukas")
      assert {:ok, _} = sign_in(strategy, "lukas", @password)
    end

    test "counts usernames that have no account, too", %{strategy: strategy} do
      for _ <- 1..@max, do: sign_in(strategy, "nobody", "whatever1")

      assert SignInThrottle.locked_for("nobody")
    end
  end

  defp sign_in(strategy, username, password) do
    AshAuthentication.Strategy.action(strategy, :sign_in, %{
      "username" => username,
      "password" => password
    })
  end
end
