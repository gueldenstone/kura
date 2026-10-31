defmodule KuraWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  # For a complete reference, see https://hexdocs.pm/ash_authentication_phoenix/ui-overrides.html

  @page "grid min-h-dvh place-items-center bg-base-200 px-4 text-base-content"

  @input """
  block h-12 w-full rounded-2xl border-0 bg-base-100 px-4 text-base-content shadow-card
  outline-none placeholder:text-base-content/45 focus:ring-2
  """

  @button """
  mt-4 mb-4 flex h-12 w-full items-center justify-center rounded-full bg-primary
  font-extrabold text-primary-content shadow-card transition hover:brightness-110 active:scale-95
  """

  override AshAuthentication.Phoenix.SignInLive do
    set :root_class, @page
  end

  override AshAuthentication.Phoenix.SignOutLive do
    set :root_class, @page
  end

  override AshAuthentication.Phoenix.Components.SignIn do
    set :root_class, "w-full max-w-sm py-12"
    set :strategy_class, "w-full"
  end

  override AshAuthentication.Phoenix.Components.Banner do
    set :image_url, nil
    set :dark_image_url, nil
    set :text, "Kura"
    set :text_class, "mb-4 font-display text-5xl font-bold tracking-tight text-primary"
  end

  override AshAuthentication.Phoenix.Components.Password.Input do
    set :identity_input_label, "Username"
    set :input_class, @input <> " focus:ring-primary/40"
    set :input_class_with_error, @input <> " ring-2 ring-error/60 focus:ring-error"
    set :submit_class, @button
    set :checkbox_class, "size-5 accent-primary mr-2"
    set :checkbox_label_class, "text-sm font-medium text-base-content/70"
    set :remember_me_class, "mt-2 mb-2 flex items-center gap-2 text-base-content"
    set :error_ul, "my-3 text-sm text-error"
  end

  override AshAuthentication.Phoenix.Components.SignOut do
    set :h2_class, "mt-2 mb-4 font-display text-3xl font-bold tracking-tight"
    set :info_text_class, "mb-4 text-sm text-base-content/70"
    set :button_class, @button
  end
end
