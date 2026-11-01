defmodule KuraWeb.TagsLiveTest do
  use KuraWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Kura.Inventory

  setup :log_in_user

  defp tag(user, name), do: Inventory.create_tag!(%{name: name}, actor: user)

  test "shows a hint when there are no tags yet", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/tags")

    assert html =~ "No tags yet"
  end

  test "lists the tags by name with how many items carry each", %{conn: conn, user: user} do
    ground = tag(user, "ground")
    tag(user, "Bio")

    Inventory.create_item!(%{name: "Cumin", tracking: :level, tag_ids: [ground.id]}, actor: user)

    {:ok, view, _html} = live(conn, ~p"/tags")
    list = view |> element("#tags") |> render()

    assert :binary.match(list, "Bio") < :binary.match(list, "ground")
    assert has_element?(view, "#tag-#{ground.id} [data-role=item-count]", "1 item")
  end

  test "adds a tag", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/tags")

    view |> form("#new-tag-form", tag: %{name: "whole"}) |> render_submit()

    assert [%{name: name}] = Inventory.list_tags!(actor: user)
    assert to_string(name) == "whole"
    assert has_element?(view, "#tags", "whole")
  end

  test "refuses a tag that exists already, ignoring case", %{conn: conn, user: user} do
    tag(user, "whole")
    {:ok, view, _html} = live(conn, ~p"/tags")

    html = view |> form("#new-tag-form", tag: %{name: "WHOLE"}) |> render_submit()

    assert html =~ "has already been taken"
    assert length(Inventory.list_tags!(actor: user)) == 1
  end

  test "renames a tag", %{conn: conn, user: user} do
    ground = tag(user, "ground")
    {:ok, view, _html} = live(conn, ~p"/tags")

    view |> element("#tag-#{ground.id} button[phx-click=edit]") |> render_click()
    view |> form("#edit-tag-form", tag: %{name: "milled"}) |> render_submit()

    assert to_string(Inventory.get_tag!(ground.id, actor: user).name) == "milled"
    assert has_element?(view, "#tag-#{ground.id}", "milled")
    refute has_element?(view, "#edit-tag-form")
  end

  test "switches printing on labels off and on, and says so in the list", %{
    conn: conn,
    user: user
  } do
    red = tag(user, "red")
    {:ok, view, _html} = live(conn, ~p"/tags")
    refute has_element?(view, "#tag-#{red.id} [data-role=not-printed]")

    view |> element("#tag-#{red.id} button[phx-click=edit]") |> render_click()
    view |> form("#edit-tag-form", tag: %{print_on_labels: false}) |> render_submit()

    refute Inventory.get_tag!(red.id, actor: user).print_on_labels
    assert has_element?(view, "#tag-#{red.id} [data-role=not-printed]", "not printed")

    view |> element("#tag-#{red.id} button[phx-click=edit]") |> render_click()
    view |> form("#edit-tag-form", tag: %{print_on_labels: true}) |> render_submit()

    assert Inventory.get_tag!(red.id, actor: user).print_on_labels
    refute has_element?(view, "#tag-#{red.id} [data-role=not-printed]")
  end

  test "deletes a tag and takes it off its items", %{conn: conn, user: user} do
    ground = tag(user, "ground")
    bio = tag(user, "Bio")

    cumin =
      Inventory.create_item!(
        %{name: "Cumin", tracking: :level, tag_ids: [ground.id, bio.id]},
        actor: user
      )

    {:ok, view, _html} = live(conn, ~p"/tags")

    view |> element("#tag-#{ground.id} button[phx-click=delete]") |> render_click()

    refute has_element?(view, "#tag-#{ground.id}")

    assert Inventory.get_item!(cumin.id, actor: user).tag_key ==
             Kura.Inventory.Item.tag_key([bio.id])
  end

  test "says why a tag cannot be deleted", %{conn: conn, user: user} do
    ground = tag(user, "ground")
    Inventory.create_item!(%{name: "Cumin", tracking: :level, tag_ids: [ground.id]}, actor: user)
    Inventory.create_item!(%{name: "Cumin", tracking: :level}, actor: user)
    {:ok, view, _html} = live(conn, ~p"/tags")

    html = view |> element("#tag-#{ground.id} button[phx-click=delete]") |> render_click()

    assert html =~ "would make these items identical"
    assert has_element?(view, "#tag-#{ground.id}")
  end

  test "the More menu leads here and marks the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tags")

    assert has_element?(view, "nav button#more-button[aria-label=More][aria-current=page]")
    assert has_element?(view, "nav #more-menu a[href='/tags']", "Tags")
  end
end
