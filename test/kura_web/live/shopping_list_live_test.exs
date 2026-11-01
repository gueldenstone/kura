defmodule KuraWeb.ShoppingListLiveTest do
  use KuraWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Kura.Inventory

  setup :log_in_user

  defp item(user, attrs) do
    Inventory.create_item!(Map.merge(%{tracking: :count}, attrs), actor: user)
  end

  defp on_list(user, item, attrs \\ %{}) do
    Inventory.add_entry!(Map.merge(%{item_id: item.id}, attrs), actor: user)
  end

  defp stock(user, item), do: Inventory.get_item!(item.id, actor: user)

  test "shows a friendly message when there is nothing to buy", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Nothing to buy"
  end

  test "lists open entries by item name with their quantity", %{conn: conn, user: user} do
    walnuts = item(user, %{name: "Walnuts", tracking: :level})
    apples = item(user, %{name: "Apples", usual_amount: 6})
    on_list(user, walnuts)
    entry = on_list(user, apples)

    {:ok, view, html} = live(conn, ~p"/")

    assert :binary.match(html, "Apples") < :binary.match(html, "Walnuts")
    assert has_element?(view, "#entry-#{entry.id} [data-role=quantity]", "6")
    assert has_element?(view, "#entry-#{entry.id}", "Apples")
    assert html =~ "2 to buy"
  end

  describe "checking off" do
    test "moves the entry to the cart and restocks a count item", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", stock_count: 0})
      entry = on_list(user, apples, %{quantity: 4})
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#entry-#{entry.id} button[phx-click=check]") |> render_click()

      assert stock(user, apples).stock_count == 4
      assert has_element?(view, "#cart #entry-#{entry.id}")
      refute has_element?(view, "#open-entries #entry-#{entry.id}")
    end

    test "sets a level item to plenty", %{conn: conn, user: user} do
      walnuts = item(user, %{name: "Walnuts", tracking: :level, stock_level: :empty})
      entry = on_list(user, walnuts)
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#entry-#{entry.id} button[phx-click=check]") |> render_click()

      assert stock(user, walnuts).stock_level == :plenty
    end

    test "can be undone from the cart", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", stock_count: 1})
      entry = on_list(user, apples, %{quantity: 4})
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#entry-#{entry.id} button[phx-click=check]") |> render_click()
      view |> element("#cart #entry-#{entry.id} button[phx-click=uncheck]") |> render_click()

      assert stock(user, apples).stock_count == 1
      assert has_element?(view, "#open-entries #entry-#{entry.id}")
      refute has_element?(view, "#cart #entry-#{entry.id}")
    end

    test "hide checked removes the cart for good", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      entry = on_list(user, apples)
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#entry-#{entry.id} button[phx-click=check]") |> render_click()

      view |> element("button[phx-click=hide_checked]") |> render_click()

      refute has_element?(view, "#entry-#{entry.id}")
      refute has_element?(view, "#cart")
      assert stock(user, apples).stock_count == 2
    end
  end

  describe "quantity" do
    test "plus and minus change it", %{conn: conn, user: user} do
      entry = on_list(user, item(user, %{name: "Apples"}), %{quantity: 2})
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#entry-#{entry.id} button[phx-value-delta='1']") |> render_click()
      assert has_element?(view, "#entry-#{entry.id} [data-role=quantity]", "3")

      view |> element("#entry-#{entry.id} button[phx-value-delta='-1']") |> render_click()
      assert has_element?(view, "#entry-#{entry.id} [data-role=quantity]", "2")
    end

    test "minus at 1 removes the entry without touching stock", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", stock_count: 3})
      entry = on_list(user, apples, %{quantity: 1})
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#entry-#{entry.id} button[phx-value-delta='-1']") |> render_click()

      refute has_element?(view, "#entry-#{entry.id}")
      assert stock(user, apples).stock_count == 3
    end
  end

  describe "adding" do
    test "matching items that are not on the list are suggested", %{conn: conn, user: user} do
      walnuts = item(user, %{name: "Walnuts"})
      washing = item(user, %{name: "Washing-up liquid"})
      on_list(user, washing)
      item(user, %{name: "Rice"})
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#search-form", search: %{query: "wa"}) |> render_change()

      assert has_element?(view, "#suggestion-#{walnuts.id}", "Walnuts")
      refute has_element?(view, "#suggestion-#{washing.id}")
    end

    test "tapping a suggestion puts it on the list with its usual amount", %{
      conn: conn,
      user: user
    } do
      apples = item(user, %{name: "Apples", usual_amount: 6})
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#search-form", search: %{query: "app"}) |> render_change()
      view |> element("#suggestion-#{apples.id} button") |> render_click()

      [entry] = Inventory.list_open_entries!(actor: user)
      assert entry.item_id == apples.id
      assert entry.quantity == 6
      assert has_element?(view, "#entry-#{entry.id}")
      refute has_element?(view, "#suggestions")
    end

    test "a name that is not in the catalogue can be created and listed at once", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> form("#search-form", search: %{query: "Walnuts"}) |> render_change()
      view |> element("#add-item button") |> render_click()

      view
      |> form("#new-item-form", item: %{tracking: "level", usual_amount: "2"})
      |> render_submit()

      [entry] = Inventory.list_open_entries!(actor: user)
      assert to_string(entry.item.name) == "Walnuts"
      assert entry.item.tracking == :level
      assert entry.quantity == 2
      assert has_element?(view, "#entry-#{entry.id}")
    end

    test "does not offer to create a name that already exists", %{conn: conn, user: user} do
      on_list(user, item(user, %{name: "Walnuts"}))
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#search-form", search: %{query: "walnuts"}) |> render_change()

      refute has_element?(view, "#add-item")
    end
  end

  describe "live updates" do
    test "an entry added elsewhere shows up", %{conn: conn, user: user} do
      walnuts = item(user, %{name: "Walnuts"})
      {:ok, view, _html} = live(conn, ~p"/")
      refute render(view) =~ "Walnuts"

      entry = on_list(user, walnuts)

      assert render(view) =~ "Walnuts"
      assert has_element?(view, "#entry-#{entry.id}")
    end

    test "the Shopping list tab counts the open entries", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "nav [data-role=open-count]")

      on_list(user, item(user, %{name: "Apples"}))
      on_list(user, item(user, %{name: "Walnuts"}))

      assert has_element?(view, "nav [data-role=open-count]", "2")
    end
  end
end
