defmodule KuraWeb.InventoryLiveTest do
  use KuraWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Kura.Inventory

  setup :log_in_user

  defp item(user, attrs) do
    Inventory.create_item!(Map.merge(%{tracking: :count}, attrs), actor: user)
  end

  defp stored(user, item), do: Inventory.get_item!(item.id, actor: user)

  test "shows a hint when there are no items yet", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/inventory")

    assert html =~ "No items yet"
  end

  test "lists items by name with their stock", %{conn: conn, user: user} do
    apples = item(user, %{name: "Apples", stock_count: 3})
    walnuts = item(user, %{name: "Walnuts", tracking: :level, stock_level: :low})

    {:ok, view, html} = live(conn, ~p"/inventory")

    assert :binary.match(html, "Apples") < :binary.match(html, "Walnuts")
    assert has_element?(view, "#item-#{apples.id} [data-role=stock]", "3")
    assert has_element?(view, "#item-#{walnuts.id} [data-role=stock]", "Running low")
  end

  test "each item shows its emoji, or its first letter without one", %{conn: conn, user: user} do
    apples = item(user, %{name: "apples", emoji: "🍎"})
    rice = item(user, %{name: "Rice"})

    {:ok, view, _html} = live(conn, ~p"/inventory")

    assert has_element?(view, "#item-#{apples.id} [data-role=tile]", "🍎")
    assert has_element?(view, "#item-#{rice.id} [data-role=tile]", "R")
  end

  test "search filters the list as you type", %{conn: conn, user: user} do
    apples = item(user, %{name: "Apples"})
    walnuts = item(user, %{name: "Walnuts", tracking: :level})

    {:ok, view, _html} = live(conn, ~p"/inventory")

    view |> form("#search-form", search: %{query: "waln"}) |> render_change()

    assert has_element?(view, "#item-#{walnuts.id}")
    refute has_element?(view, "#item-#{apples.id}")
  end

  describe "marking empty" do
    test "empties a count item and can be undone", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", stock_count: 4})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=mark_empty]") |> render_click()

      assert stored(user, apples).stock_count == 0
      assert has_element?(view, "#item-#{apples.id} [data-role=stock]", "Empty")
      assert has_element?(view, "#undo", "Apples")

      view |> element("#undo button") |> render_click()

      assert stored(user, apples).stock_count == 4
      refute has_element?(view, "#undo")
    end

    test "empties a level item and can be undone", %{conn: conn, user: user} do
      walnuts = item(user, %{name: "Walnuts", tracking: :level, stock_level: :low})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{walnuts.id} button[phx-click=mark_empty]") |> render_click()
      assert stored(user, walnuts).stock_level == :empty

      view |> element("#undo button") |> render_click()
      assert stored(user, walnuts).stock_level == :low
    end

    test "an already empty item has no empty button", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", stock_count: 0})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      refute has_element?(view, "#item-#{apples.id} button[phx-click=mark_empty]")
    end
  end

  test "plus and minus change a count", %{conn: conn, user: user} do
    apples = item(user, %{name: "Apples", stock_count: 2})
    {:ok, view, _html} = live(conn, ~p"/inventory")

    plus = "#item-#{apples.id} button[phx-click=change_count][phx-value-delta='1']"
    minus = "#item-#{apples.id} button[phx-click=change_count][phx-value-delta='-1']"

    view |> element(plus) |> render_click()
    assert stored(user, apples).stock_count == 3

    view |> element(minus) |> render_click()
    view |> element(minus) |> render_click()
    assert stored(user, apples).stock_count == 1
  end

  test "level buttons set the level", %{conn: conn, user: user} do
    walnuts = item(user, %{name: "Walnuts", tracking: :level})
    {:ok, view, _html} = live(conn, ~p"/inventory")

    view
    |> element("#item-#{walnuts.id} button[phx-click=set_level][phx-value-level=low]")
    |> render_click()

    assert stored(user, walnuts).stock_level == :low
    assert has_element?(view, "#item-#{walnuts.id} [data-role=stock]", "Running low")
  end

  describe "adding items" do
    test "a search without a match offers to add that name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> form("#search-form", search: %{query: "Walnuts"}) |> render_change()

      assert has_element?(view, "#add-item button", "Walnuts")
    end

    test "creates the item from the prompt", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/inventory")
      view |> form("#search-form", search: %{query: "Walnuts"}) |> render_change()
      view |> element("#add-item button") |> render_click()

      view
      |> form("#new-item-form", item: %{tracking: "level", usual_amount: "2", emoji: "🌰"})
      |> render_submit()

      [walnuts] = Inventory.search_items!("", actor: user)
      assert to_string(walnuts.name) == "Walnuts"
      assert walnuts.tracking == :level
      assert walnuts.usual_amount == 2
      assert walnuts.emoji == "🌰"
      assert has_element?(view, "#item-#{walnuts.id}")
      refute has_element?(view, "#new-item-form")
    end

    test "opens with the emoji field focused and no example emoji", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/inventory")
      view |> form("#search-form", search: %{query: "Walnuts"}) |> render_change()
      view |> element("#add-item button") |> render_click()

      emoji_input = "#new-item-form input[name='item[emoji]']"
      assert has_element?(view, emoji_input)
      assert render(element(view, emoji_input)) =~ "phx-mounted"
      refute render(view) =~ ~s(placeholder="🍎")
    end

    test "does not offer to add a name that exists", %{conn: conn, user: user} do
      item(user, %{name: "Walnuts"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> form("#search-form", search: %{query: "walnuts"}) |> render_change()

      refute has_element?(view, "#add-item")
    end
  end

  describe "editing" do
    test "changes the name and usual amount", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", usual_amount: 6})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=edit]") |> render_click()

      view
      |> form("#edit-item-form", item: %{name: "Green apples", usual_amount: "4", emoji: "🍏"})
      |> render_submit()

      updated = stored(user, apples)
      assert to_string(updated.name) == "Green apples"
      assert updated.usual_amount == 4
      assert updated.emoji == "🍏"
      assert has_element?(view, "#item-#{apples.id}", "Green apples")
      refute has_element?(view, "#edit-item-form")
    end

    test "has no example emoji in the emoji field", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=edit]") |> render_click()

      refute render(view) =~ ~s(placeholder="🍎")
    end

    test "shows validation errors", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=edit]") |> render_click()
      html = view |> form("#edit-item-form", item: %{usual_amount: "0"}) |> render_submit()

      assert html =~ "must be greater than or equal to 1"
      assert stored(user, apples).usual_amount == 1
    end

    test "deletes an item", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=edit]") |> render_click()
      view |> element("#edit-item-form button[phx-click=delete]") |> render_click()

      refute has_element?(view, "#item-#{apples.id}")
      assert Inventory.search_items!("", actor: user) == []
    end
  end
end
