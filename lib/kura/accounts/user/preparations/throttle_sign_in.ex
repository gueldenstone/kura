defmodule Kura.Accounts.User.Preparations.ThrottleSignIn do
  @moduledoc """
  Wraps password sign-in in `Kura.Accounts.SignInThrottle`: a locked username is refused before
  its password is checked, a wrong password counts as a failure and a successful sign-in clears
  the count.
  """
  use Ash.Resource.Preparation

  alias Kura.Accounts.SignInThrottle

  @impl true
  def prepare(query, _opts, _context) do
    username = Ash.Query.get_argument(query, :username)

    Ash.Query.around_transaction(query, fn query, callback ->
      throttle(query, callback, username)
    end)
  end

  defp throttle(query, callback, nil), do: callback.(query)

  defp throttle(query, callback, username) do
    case SignInThrottle.locked_for(username) do
      nil -> username |> count(callback.(query))
      seconds -> {:error, locked_error(seconds)}
    end
  end

  defp count(username, {:ok, [_user]} = result) do
    SignInThrottle.reset(username)
    result
  end

  defp count(username, {:error, _} = result) do
    SignInThrottle.record_failure(username)
    result
  end

  defp count(_username, result), do: result

  defp locked_error(seconds) do
    minutes = div(seconds + 59, 60)

    Ash.Error.Query.InvalidArgument.exception(
      field: :username,
      message: "Too many failed attempts. Try again in %{minutes} min.",
      vars: [minutes: minutes]
    )
  end
end
