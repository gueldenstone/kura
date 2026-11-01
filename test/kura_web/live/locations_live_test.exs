defmodule KuraWeb.LocationsLiveTest do
  use KuraWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Kura.Inventory

  setup :log_in_user

  defp location(user, name), do: Inventory.create_location!(%{name: name}, actor: user)

  test "shows a hint when there are no places yet", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/locations")

    assert html =~ "No places yet"
  end

  test "lists the places by name with how many items live there", %{conn: conn, user: user} do
    fridge = location(user, "fridge")
    location(user, "Cupboard")

    Inventory.create_item!(%{name: "Tahini", tracking: :level, location_ids: [fridge.id]},
      actor: user
    )

    {:ok, view, _html} = live(conn, ~p"/locations")
    list = view |> element("#locations") |> render()

    assert :binary.match(list, "Cupboard") < :binary.match(list, "fridge")
    assert has_element?(view, "#location-#{fridge.id} [data-role=item-count]", "1 item")
  end

  test "adds a place and refuses a duplicate", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    view |> form("#new-location-form", location: %{name: "Freezer"}) |> render_submit()
    assert has_element?(view, "#locations", "Freezer")

    html = view |> form("#new-location-form", location: %{name: "FREEZER"}) |> render_submit()
    assert html =~ "has already been taken"
    assert length(Inventory.list_locations!(actor: user)) == 1
  end

  test "renames a place", %{conn: conn, user: user} do
    fridge = location(user, "Fridge")
    {:ok, view, _html} = live(conn, ~p"/locations")

    view |> element("#location-#{fridge.id} button[phx-click=edit]") |> render_click()
    view |> form("#edit-location-form", location: %{name: "Kühlschrank"}) |> render_submit()

    assert to_string(Inventory.get_location!(fridge.id, actor: user).name) == "Kühlschrank"
    assert has_element?(view, "#location-#{fridge.id}", "Kühlschrank")
    refute has_element?(view, "#edit-location-form")
  end

  test "deleting a place takes it off its items and keeps the items", %{conn: conn, user: user} do
    fridge = location(user, "Fridge")

    tahini =
      Inventory.create_item!(
        %{name: "Tahini", tracking: :level, location_ids: [fridge.id]},
        actor: user
      )

    {:ok, view, _html} = live(conn, ~p"/locations")

    assert has_element?(view, ~s(#location-#{fridge.id} button[data-confirm*="1 item"]))
    view |> element("#location-#{fridge.id} button[phx-click=delete]") |> render_click()

    refute has_element?(view, "#location-#{fridge.id}")
    assert {:ok, _} = Inventory.get_item(tahini.id, actor: user)
  end

  test "the More menu leads here and marks the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    assert has_element?(view, "nav button#more-button[aria-current=page]")
    assert has_element?(view, "nav #more-menu a[href='/locations']", "Locations")
    assert has_element?(view, "nav #more-menu a[href='/tags']", "Tags")
  end
end
