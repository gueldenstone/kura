defmodule KuraWeb.Router do
  use KuraWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KuraWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :offline_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", KuraWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{KuraWeb.LiveUserAuth, :live_user_required}, KuraWeb.LiveKitchenSync] do
      live "/", ShoppingListLive
      live "/inventory", InventoryLive
    end
  end

  scope "/", KuraWeb do
    pipe_through :browser

    # Home screen shortcuts saved before the list moved to "/" still point here.
    get "/shopping-list", PageController, :shopping_list
    get "/inventory/labels.csv", LabelController, :export
    auth_routes AuthController, Kura.Accounts.User, path: "/auth"

    sign_out_route AuthController, "/sign-out",
      overrides: [KuraWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Accounts are created with `mix kura.user.create`; there is no registration page.
    sign_in_route auth_routes_prefix: "/auth",
                  on_mount: [{KuraWeb.LiveUserAuth, :live_no_user}],
                  overrides: [KuraWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
  end

  scope "/", KuraWeb do
    get "/sw.js", PwaController, :service_worker
  end

  scope "/offline", KuraWeb do
    pipe_through :offline_api

    get "/state", OfflineController, :state
    post "/sync", OfflineController, :sync
  end

  scope "/", KuraWeb do
    pipe_through :browser

    get "/offline", OfflineController, :shell
  end

  # Other scopes may use custom stacks.
  # scope "/api", KuraWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:kura, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KuraWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  if Application.compile_env(:kura, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
