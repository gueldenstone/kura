defmodule KuraWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  # For a complete reference, see https://hexdocs.pm/ash_authentication_phoenix/ui-overrides.html

  override AshAuthentication.Phoenix.Components.Banner do
    set :image_url, nil
    set :dark_image_url, nil
    set :text, "Kura"
    set :text_class, "text-3xl font-semibold tracking-tight text-center dark:text-white"
  end

  override AshAuthentication.Phoenix.Components.Password.Input do
    set :identity_input_label, "Username"
  end
end
