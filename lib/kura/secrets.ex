defmodule Kura.Secrets do
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], Kura.Accounts.User, _opts, _context) do
    Application.fetch_env(:kura, :token_signing_secret)
  end
end
