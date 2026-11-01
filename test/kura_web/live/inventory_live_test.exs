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

    assert has_element?(
             view,
             "#item-#{walnuts.id} [data-role=stock] button[aria-pressed=true]",
             "Low"
           )
  end

  test "an item is one compact row: its name and one stock control, no icon tile", %{
    conn: conn,
    user: user
  } do
    apples = item(user, %{name: "apples"})

    {:ok, view, _html} = live(conn, ~p"/inventory")

    refute has_element?(view, "#item-#{apples.id} [data-role=tile]")
    assert has_element?(view, "#item-#{apples.id} [data-role=stock]")
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
      apples = item(user, %{name: "Apples", stock_count: 1})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[aria-label='One less']") |> render_click()

      assert stored(user, apples).stock_count == 0
      assert has_element?(view, "#item-#{apples.id} button[phx-click=mark_empty][disabled]")
      assert has_element?(view, "#undo", "Apples")

      view |> element("#undo button") |> render_click()

      assert stored(user, apples).stock_count == 1
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

    test "an already empty item cannot be marked empty or stepped down again", %{
      conn: conn,
      user: user
    } do
      apples = item(user, %{name: "Apples", stock_count: 0})
      walnuts = item(user, %{name: "Walnuts", tracking: :level, stock_level: :empty})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      assert has_element?(view, "#item-#{apples.id} button[aria-label='One less'][disabled]")
      assert has_element?(view, "#item-#{apples.id} button[phx-click=mark_empty][disabled]")
      assert has_element?(view, "#item-#{walnuts.id} button[phx-click=mark_empty][disabled]")
    end

    test "the Empty button marks a count item empty in one tap", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", stock_count: 5})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=mark_empty]") |> render_click()

      assert stored(user, apples).stock_count == 0
      assert [_entry] = Inventory.list_open_entries!(actor: user)
    end

    test "stepping a count up from empty restocks it", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", stock_count: 0})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[aria-label='One more']") |> render_click()

      assert stored(user, apples).stock_count == 1
    end
  end

  describe "the shopping list" do
    test "an item on the list carries a marker, which goes once it is checked off", %{
      conn: conn,
      user: user
    } do
      apples = item(user, %{name: "Apples"})
      rice = item(user, %{name: "Rice"})
      entry = Inventory.add_entry!(%{item_id: apples.id}, actor: user)

      {:ok, view, _html} = live(conn, ~p"/inventory")

      assert has_element?(view, "#item-#{apples.id} [data-role=on-list]")
      refute has_element?(view, "#item-#{rice.id} [data-role=on-list]")

      Inventory.check_off_entry!(entry, actor: user)

      refute has_element?(view, "#item-#{apples.id} [data-role=on-list]")
    end

    test "marking empty puts the item on the list, and undo takes it off again", %{
      conn: conn,
      user: user
    } do
      apples = item(user, %{name: "Apples", stock_count: 1, usual_amount: 6})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[aria-label='One less']") |> render_click()

      assert [%{quantity: 6}] = Inventory.list_open_entries!(actor: user)
      assert has_element?(view, "#item-#{apples.id} [data-role=on-list]")

      view |> element("#undo button") |> render_click()

      assert Inventory.list_open_entries!(actor: user) == []
      refute has_element?(view, "#item-#{apples.id} [data-role=on-list]")
    end

    test "undo keeps an entry that was on the list already", %{conn: conn, user: user} do
      walnuts = item(user, %{name: "Walnuts", tracking: :level})
      Inventory.add_entry!(%{item_id: walnuts.id, quantity: 3}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{walnuts.id} button[phx-click=mark_empty]") |> render_click()
      view |> element("#undo button") |> render_click()

      assert [%{quantity: 3}] = Inventory.list_open_entries!(actor: user)
    end

    test "the Shopping list tab shows how many entries are open", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", stock_count: 1})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[aria-label='One less']") |> render_click()

      assert has_element?(view, "nav [data-role=open-count]", "1")
    end
  end

  test "stock changed elsewhere shows up live", %{conn: conn, user: user} do
    apples = item(user, %{name: "Apples", stock_count: 3})
    {:ok, view, _html} = live(conn, ~p"/inventory")

    Inventory.set_item_count!(apples, 9, actor: user)

    assert has_element?(view, "#item-#{apples.id} [data-role=stock]", "9")
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

    assert has_element?(
             view,
             "#item-#{walnuts.id} [data-role=stock] button[aria-pressed=true]",
             "Low"
           )
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
      |> form("#new-item-form", item: %{tracking: "level", usual_amount: "2"})
      |> render_submit()

      [walnuts] = Inventory.search_items!("", actor: user)
      assert to_string(walnuts.name) == "Walnuts"
      assert walnuts.tracking == :level
      assert walnuts.usual_amount == 2
      assert has_element?(view, "#item-#{walnuts.id}")
      refute has_element?(view, "#new-item-form")
    end

    test "defaults to level tracking and sets the stock right away", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/inventory")
      view |> form("#search-form", search: %{query: "Walnuts"}) |> render_change()
      view |> element("#add-item button") |> render_click()

      view |> form("#new-item-form", item: %{stock_level: "low"}) |> render_submit()

      [walnuts] = Inventory.search_items!("", actor: user)
      assert walnuts.tracking == :level
      assert walnuts.stock_level == :low
    end

    test "sets a starting count for count items", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/inventory")
      view |> form("#search-form", search: %{query: "Apples"}) |> render_change()
      view |> element("#add-item button") |> render_click()

      view |> form("#new-item-form", item: %{tracking: "count"}) |> render_change()
      view |> form("#new-item-form", item: %{stock_count: "6"}) |> render_submit()

      [apples] = Inventory.search_items!("", actor: user)
      assert apples.tracking == :count
      assert apples.stock_count == 6
    end

    test "pressing enter in the search opens the add form like the button", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> form("#search-form", search: %{query: "Walnuts"}) |> render_submit()

      assert has_element?(view, "#new-item-form")
      assert Inventory.search_items!("", actor: user) == []

      view |> form("#new-item-form", item: %{tracking: "count"}) |> render_change()
      view |> form("#new-item-form", item: %{stock_count: "3"}) |> render_submit()

      [walnuts] = Inventory.search_items!("", actor: user)
      assert to_string(walnuts.name) == "Walnuts"
      assert walnuts.stock_count == 3
    end

    test "pressing enter on an existing name adds nothing", %{conn: conn, user: user} do
      item(user, %{name: "Walnuts"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> form("#search-form", search: %{query: "walnuts"}) |> render_submit()

      refute has_element?(view, "#new-item-form")
      assert [_one] = Inventory.search_items!("", actor: user)
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
      |> form("#edit-item-form", item: %{name: "Green apples", usual_amount: "4"})
      |> render_submit()

      updated = stored(user, apples)
      assert to_string(updated.name) == "Green apples"
      assert updated.usual_amount == 4
      assert has_element?(view, "#item-#{apples.id}", "Green apples")
      refute has_element?(view, "#edit-item-form")
    end

    test "tapping the name of an open card closes it again", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")
      edit = "#item-#{apples.id} button[phx-click=edit]"

      view |> element(edit) |> render_click()
      assert has_element?(view, "#edit-item-form")

      view |> element(edit) |> render_click()
      refute has_element?(view, "#edit-item-form")
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
