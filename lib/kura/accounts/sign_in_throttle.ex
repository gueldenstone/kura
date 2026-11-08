defmodule Kura.Accounts.SignInThrottle do
  @moduledoc """
  Counts failed password sign-ins per username and locks a username for a while once there are
  too many, so passwords cannot be guessed without limit.

  The count is per submitted username, whether or not an account has it, so a lock says nothing
  about which usernames exist. It lives in memory (ETS): a restart forgets it, which is fine for
  slowing down guessing (see ADR 0012).
  """
  use GenServer

  @table __MODULE__
  @max_failures 10
  @lockout_seconds 15 * 60

  def max_failures, do: @max_failures
  def lockout_seconds, do: @lockout_seconds

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Seconds until `username` may try again, or `nil` when it is not locked."
  @spec locked_for(String.t(), integer) :: pos_integer | nil
  def locked_for(username, now \\ now()) do
    case :ets.lookup(@table, key(username)) do
      [{_key, _count, _first, locked_until}]
      when is_integer(locked_until) and locked_until > now ->
        locked_until - now

      _ ->
        nil
    end
  end

  @doc "Records a failed sign-in; the failure that reaches the limit starts the lock."
  @spec record_failure(String.t(), integer) :: :ok
  def record_failure(username, now \\ now()) do
    key = key(username)

    {count, first} =
      case :ets.lookup(@table, key) do
        # Failures spread out over more than the lockout period do not add up.
        [{_key, count, first, _locked_until}] when now - first < @lockout_seconds ->
          {count, first}

        _ ->
          {0, now}
      end

    entry =
      if count + 1 >= @max_failures,
        do: {key, 0, now, now + @lockout_seconds},
        else: {key, count + 1, first, nil}

    :ets.insert(@table, entry)
    :ok
  end

  @doc "Forgets the failures of `username` after a successful sign-in."
  @spec reset(String.t()) :: :ok
  def reset(username) do
    :ets.delete(@table, key(username))
    :ok
  end

  @doc "Forgets every failure and lock. Tests start from a clean slate with it."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_prune()
    {:ok, nil}
  end

  # Guesses at made-up usernames would otherwise leave entries behind forever.
  @impl true
  def handle_info(:prune, state) do
    now = now()

    :ets.select_delete(@table, [
      {{:_, :_, :"$1", :"$2"},
       [
         {:andalso, {:orelse, {:==, :"$2", nil}, {:<, :"$2", now}},
          {:<, :"$1", now - @lockout_seconds}}
       ], [true]}
    ])

    schedule_prune()
    {:noreply, state}
  end

  defp schedule_prune, do: Process.send_after(self(), :prune, @lockout_seconds * 1000)

  defp key(username), do: username |> to_string() |> String.downcase()

  defp now, do: System.monotonic_time(:second)
end
