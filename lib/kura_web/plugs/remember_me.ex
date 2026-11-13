defmodule KuraWeb.Plugs.RememberMe do
  @moduledoc """
  Signs in from the remember-me cookie whenever the session has no working sign-in, and renews
  the cookie when it does, so the phones stay signed in as long as they are used (ADR 0015).

  Runs after `load_from_session`. The library's own `sign_in_with_remember_me` only looks at the
  cookie when the session holds no token at all, so a session token that ran out (after 14 days)
  or was revoked would block it; `load_from_session` has already dropped such a token here.
  """
  @behaviour Plug

  alias AshAuthentication.{Info, Jwt}
  alias AshAuthentication.Phoenix.Plug, as: AuthPlug
  alias AshAuthentication.Strategy.RememberMe.Plug.Helpers, as: CookieHelpers
  alias AshAuthentication.Utils
  alias Kura.Accounts.User

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{current_user: %User{}}} = conn, _opts), do: conn

  def call(conn, opts) do
    conn
    |> AuthPlug.sign_in_with_remember_me(opts)
    |> AuthPlug.load_from_session(opts)
    |> renew_cookie()
  end

  # Signed in from the cookie: hand out a fresh one, so the 30 days start again.
  defp renew_cookie(%{assigns: %{current_user: %User{} = user}} = conn) do
    strategy = Info.strategy!(User, :remember_me)

    case Jwt.token_for_user(user, %{"purpose" => "remember_me"},
           purpose: :remember_me,
           token_lifetime: strategy.token_lifetime
         ) do
      {:ok, token, _claims} ->
        CookieHelpers.put_remember_me_cookie(conn, to_string(strategy.cookie_name), %{
          token: token,
          max_age: Utils.lifetime_to_seconds(strategy.token_lifetime)
        })

      :error ->
        conn
    end
  end

  defp renew_cookie(conn), do: conn
end
