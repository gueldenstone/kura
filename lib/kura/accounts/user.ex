defmodule Kura.Accounts.User do
  use Ash.Resource,
    otp_app: :kura,
    domain: Kura.Accounts,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  sqlite do
    table "users"
    repo Kura.Repo
  end

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Kura.Accounts.Token
      signing_secret Kura.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :username
        hashed_password_field :hashed_password
        # Accounts are created by the owner (mix kura.user.create), never by visitors.
        registration_enabled? false
        sign_in_tokens_enabled? true
      end

      remember_me :remember_me
    end
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :sign_in_with_password do
      description "Attempt to sign in using a username and password."
      get? true

      argument :username, :ci_string, allow_nil?: false
      argument :password, :string, allow_nil?: false, sensitive?: true

      argument :remember_me, :boolean do
        description "Whether to generate a remember me token."
        allow_nil? true
      end

      prepare AshAuthentication.Strategy.Password.SignInPreparation

      prepare {AshAuthentication.Strategy.RememberMe.MaybeGenerateTokenPreparation,
               strategy_name: :remember_me}

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end

      metadata :remember_me, :map do
        description "A map that includes the remember me token options."
        allow_nil? true
      end
    end

    create :create do
      description "Create an account. Used by `mix kura.user.create`, not exposed to visitors."
      accept [:username]

      argument :password, :string, allow_nil?: false, sensitive?: true

      validate string_length(:password, min: 8)

      change set_context(%{strategy_name: :password})
      change AshAuthentication.Strategy.Password.HashPasswordChange
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :username, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string, allow_nil?: false, sensitive?: true
  end

  identities do
    identity :unique_username, [:username], pre_check?: true
  end
end
