defmodule Kura.Accounts do
  use Ash.Domain, otp_app: :kura, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Kura.Accounts.Token
    resource Kura.Accounts.User
  end
end
