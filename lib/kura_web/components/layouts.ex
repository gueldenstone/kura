defmodule KuraWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KuraWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the app shell: a slim header, the page content and a bottom tab bar.

  ## Examples

      <Layouts.app flash={@flash} current_user={@current_user} active={:shopping_list}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, required: true, doc: "the signed-in user"

  attr :active, :atom,
    values: [:shopping_list, :inventory],
    required: true,
    doc: "the current tab"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-dvh flex-col bg-base-100 text-base-content">
      <header class="sticky top-0 z-10 border-b border-base-300 bg-base-100/90 backdrop-blur">
        <div class="mx-auto flex h-14 max-w-2xl items-center justify-between px-4">
          <a href={~p"/"} class="text-lg font-semibold tracking-tight">Kura</a>
          <div class="flex items-center gap-2">
            <.theme_toggle />
            <.link
              href={~p"/sign-out"}
              method="delete"
              class="inline-flex size-10 items-center justify-center rounded-full text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
              aria-label={"Sign out #{@current_user.username}"}
              title={"Sign out #{@current_user.username}"}
            >
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-5" />
            </.link>
          </div>
        </div>
      </header>

      <main class="mx-auto w-full max-w-2xl flex-1 px-4 pt-6 pb-28">
        {render_slot(@inner_block)}
      </main>

      <nav
        class="fixed inset-x-0 bottom-0 z-10 border-t border-base-300 bg-base-100/95 pb-[env(safe-area-inset-bottom)] backdrop-blur"
        aria-label="Main"
      >
        <div class="mx-auto grid max-w-2xl grid-cols-2">
          <.tab href={~p"/shopping-list"} icon="hero-shopping-cart" active={@active == :shopping_list}>
            Shopping list
          </.tab>
          <.tab href={~p"/inventory"} icon="hero-archive-box" active={@active == :inventory}>
            Inventory
          </.tab>
        </div>
      </nav>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <.link
      navigate={@href}
      aria-current={@active && "page"}
      class={[
        "flex flex-col items-center gap-0.5 py-2.5 text-xs font-medium transition",
        @active && "text-primary",
        !@active && "text-base-content/60 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="size-6" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
