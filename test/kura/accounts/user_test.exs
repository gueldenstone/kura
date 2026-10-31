defmodule Kura.Accounts.UserTest do
  use Kura.DataCase, async: true

  alias Kura.Accounts
  alias Kura.Accounts.User

  @password "correct horse battery"

  describe "create_user/1" do
    test "creates a user with a username and a hashed password" do
      user = Accounts.create_user!(%{username: "lukas", password: @password}, authorize?: false)

      assert to_string(user.username) == "lukas"
      assert user.hashed_password != @password
    end

    test "rejects a username that is taken, ignoring case" do
      Accounts.create_user!(%{username: "lukas", password: @password}, authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.create_user(%{username: "Lukas", password: @password}, authorize?: false)
    end

    test "rejects a password that is too short" do
      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.create_user(%{username: "lukas", password: "short"}, authorize?: false)
    end
  end

  describe "password sign-in" do
    setup do
      user = Accounts.create_user!(%{username: "lukas", password: @password}, authorize?: false)
      %{user: user, strategy: AshAuthentication.Info.strategy!(User, :password)}
    end

    test "signs in with the correct password", %{user: user, strategy: strategy} do
      assert {:ok, signed_in} =
               AshAuthentication.Strategy.action(strategy, :sign_in, %{
                 "username" => "LUKAS",
                 "password" => @password
               })

      assert signed_in.id == user.id
    end

    test "fails with a wrong password", %{strategy: strategy} do
      assert {:error, _} =
               AshAuthentication.Strategy.action(strategy, :sign_in, %{
                 "username" => "lukas",
                 "password" => "wrong password"
               })
    end
  end

  test "the password strategy does not allow registration" do
    strategy = AshAuthentication.Info.strategy!(User, :password)

    refute strategy.registration_enabled?
    assert AshAuthentication.Info.strategy(User, :magic_link) == :error
  end
end
