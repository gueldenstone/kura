defmodule KuraWeb.InventoryLiveTest do
  use KuraWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Kura.Inventory

  setup :log_in_user

  defp item(user, attrs) do
    Inventory.create_item!(Map.merge(%{tracking: :count, auto_replenish: true}, attrs),
      actor: user
    )
  end

  defp stored(user, item), do: Inventory.get_item!(item.id, actor: user)

  # The form tells its page that it saved through a message; wait until the page has handled it.
  defp submit_item_form(view, values \\ []) do
    view |> form("#item-form", values) |> render_submit()
    render(view)
  end

  # The item form's buttons: `choose` picks a value, `step` adds to or takes from a number.
  defp choose(view, field, value) do
    view
    |> element("#item-form button[phx-value-field=#{field}][phx-value-choice=#{value}]")
    # A browser always sends the button's own `value` too, which would hide a `phx-value-value`.
    |> render_click(%{"value" => ""})
  end

  defp step(view, field, delta, times \\ 1) do
    for _ <- 1..times do
      view
      |> element("#item-form button[phx-value-field=#{field}][phx-value-delta='#{delta}']")
      |> render_click()
    end
  end

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

    test "an item that does not auto-replenish is not listed until you say so", %{
      conn: conn,
      user: user
    } do
      mint = item(user, %{name: "Mint", stock_count: 1, auto_replenish: false})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{mint.id} button[aria-label='One less']") |> render_click()

      assert has_element?(view, "#undo", "Mint marked empty")
      refute has_element?(view, "#item-#{mint.id} [data-role=on-list]")
      assert Inventory.list_open_entries!(actor: user) == []

      view |> element("#add-to-list") |> render_click()

      assert [entry] = Inventory.list_open_entries!(actor: user)
      assert entry.item_id == mint.id
      assert has_element?(view, "#item-#{mint.id} [data-role=on-list]")
      refute has_element?(view, "#add-to-list")

      view |> element("#undo button") |> render_click()

      assert stored(user, mint).stock_count == 1
      assert Inventory.list_open_entries!(actor: user) == []
    end

    test "ignoring the question leaves the item empty and off the list", %{
      conn: conn,
      user: user
    } do
      mint =
        item(user, %{name: "Mint", tracking: :level, stock_level: :low, auto_replenish: false})

      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{mint.id} button[phx-click=mark_empty]") |> render_click()

      assert stored(user, mint).stock_level == :empty
      assert Inventory.list_open_entries!(actor: user) == []
    end

    test "the undo bar goes away on its own, and an old timer does not close a newer bar", %{
      conn: conn,
      user: user
    } do
      apples = item(user, %{name: "Apples", stock_count: 1})
      pears = item(user, %{name: "Pears", stock_count: 1})
      {:ok, view, _html} = live(conn, ~p"/inventory")
      undo_ref = fn -> :sys.get_state(view.pid).socket.assigns.undo.ref end

      view |> element("#item-#{apples.id} button[aria-label='One less']") |> render_click()
      first = undo_ref.()
      view |> element("#item-#{pears.id} button[aria-label='One less']") |> render_click()

      send(view.pid, {:expire_undo, first})
      assert has_element?(view, "#undo", "Pears")

      send(view.pid, {:expire_undo, undo_ref.()})
      refute has_element?(view, "#undo")
    end

    test "an item that auto-replenishes is listed without a question", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples", stock_count: 1})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[aria-label='One less']") |> render_click()

      refute has_element?(view, "#add-to-list")
      assert [_entry] = Inventory.list_open_entries!(actor: user)
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

      step(view, "usual_amount", 1)
      view |> form("#item-form") |> render_submit()

      [walnuts] = Inventory.search_items!("", actor: user)
      assert to_string(walnuts.name) == "Walnuts"
      assert walnuts.tracking == :level
      assert walnuts.usual_amount == 2
      refute walnuts.auto_replenish
      assert has_element?(view, "#item-#{walnuts.id}")
      refute has_element?(view, "#item-form")
    end

    test "defaults to level tracking and sets the stock right away", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/inventory")
      view |> form("#search-form", search: %{query: "Walnuts"}) |> render_change()
      view |> element("#add-item button") |> render_click()

      choose(view, "stock_level", "low")
      view |> form("#item-form") |> render_submit()

      [walnuts] = Inventory.search_items!("", actor: user)
      assert walnuts.tracking == :level
      assert walnuts.stock_level == :low
    end

    test "sets a starting count for count items", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/inventory")
      view |> form("#search-form", search: %{query: "Apples"}) |> render_change()
      view |> element("#add-item button") |> render_click()

      choose(view, "tracking", "count")
      step(view, "stock_count", 1, 5)
      view |> form("#item-form") |> render_submit()

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

      assert has_element?(view, "#item-form")
      assert Inventory.search_items!("", actor: user) == []

      choose(view, "tracking", "count")
      step(view, "stock_count", 1, 2)
      view |> form("#item-form") |> render_submit()

      [walnuts] = Inventory.search_items!("", actor: user)
      assert to_string(walnuts.name) == "Walnuts"
      assert walnuts.stock_count == 3
    end

    test "pressing enter on an existing name adds nothing", %{conn: conn, user: user} do
      item(user, %{name: "Walnuts"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> form("#search-form", search: %{query: "walnuts"}) |> render_submit()

      refute has_element?(view, "#item-form")
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

      step(view, "usual_amount", -1, 2)
      view |> form("#item-form", item: %{name: "Green apples"}) |> render_submit()

      updated = stored(user, apples)
      assert to_string(updated.name) == "Green apples"
      assert updated.usual_amount == 4
      assert has_element?(view, "#item-#{apples.id}", "Green apples")
      refute has_element?(view, "#item-form")
    end

    test "switches auto-replenish on and off", %{conn: conn, user: user} do
      mint = item(user, %{name: "Mint", auto_replenish: false})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{mint.id} button[phx-click=edit]") |> render_click()
      submit_item_form(view, item: %{auto_replenish: "true"})
      assert stored(user, mint).auto_replenish

      view |> element("#item-#{mint.id} button[phx-click=edit]") |> render_click()
      submit_item_form(view, item: %{auto_replenish: false})
      refute stored(user, mint).auto_replenish
    end

    test "the form asks for stock only when adding, not when editing", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=edit]") |> render_click()
      refute has_element?(view, "#item-form button[phx-value-field=tracking]")
      assert has_element?(view, "#item-form [data-role=usual_amount]", "1")
      assert has_element?(view, "button[phx-click=delete]", "Delete")

      view |> form("#search-form", search: %{query: "Walnuts"}) |> render_change()
      view |> element("#add-item button") |> render_click()

      assert has_element?(view, "#item-form button[phx-value-field=tracking]")
      refute has_element?(view, "button[phx-click=delete]")
      refute has_element?(view, "#item-#{apples.id} #item-form")
    end

    test "Cancel closes the form without saving", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=edit]") |> render_click()
      view |> form("#item-form", item: %{name: "Pears"}) |> render_change()
      view |> element("button[phx-click=close]", "Cancel") |> render_click()

      refute has_element?(view, "#item-form")
      assert to_string(stored(user, apples).name) == "Apples"
    end

    test "tapping the name of an open card closes it again", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")
      edit = "#item-#{apples.id} button[phx-click=edit]"

      view |> element(edit) |> render_click()
      assert has_element?(view, "#item-form")

      view |> element(edit) |> render_click()
      refute has_element?(view, "#item-form")
    end

    test "shows validation errors", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=edit]") |> render_click()
      html = view |> form("#item-form", item: %{name: ""}) |> render_submit()

      assert html =~ "is required"
      assert to_string(stored(user, apples).name) == "Apples"
    end

    test "deletes an item", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{apples.id} button[phx-click=edit]") |> render_click()
      view |> element("button[phx-click=delete]") |> render_click()

      refute has_element?(view, "#item-#{apples.id}")
      assert Inventory.search_items!("", actor: user) == []
    end
  end

  describe "selecting items for label export" do
    test "ticking rows counts them and the export form carries their ids", %{
      conn: conn,
      user: user
    } do
      apples = item(user, %{name: "Apples"})
      walnuts = item(user, %{name: "Walnuts", tracking: :level})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      refute has_element?(view, "#export-form")
      view |> element("#start-select") |> render_click()

      assert has_element?(view, "#export-form [data-role=selected-count]", "0 selected")
      assert has_element?(view, "#export-form button[disabled]")
      refute has_element?(view, "#item-#{apples.id} [data-role=stock]")

      view |> element("#item-#{apples.id} button[role=checkbox]") |> render_click()

      assert has_element?(view, "#export-form [data-role=selected-count]", "1 selected")
      assert has_element?(view, ~s(#export-form input[name="ids[]"][value="#{apples.id}"]))
      refute has_element?(view, ~s(#export-form input[value="#{walnuts.id}"]))
      assert has_element?(view, "#item-#{apples.id} button[aria-checked=true]")

      view |> element("#item-#{apples.id} button[role=checkbox]") |> render_click()
      assert has_element?(view, "#export-form [data-role=selected-count]", "0 selected")
    end

    test "the selection survives searching", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      item(user, %{name: "Walnuts"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#start-select") |> render_click()
      view |> element("#item-#{apples.id} button[role=checkbox]") |> render_click()
      view |> form("#search-form", search: %{query: "wal"}) |> render_change()

      assert has_element?(view, "#export-form [data-role=selected-count]", "1 selected")
      view |> element("#select-all") |> render_click()
      assert has_element?(view, "#export-form [data-role=selected-count]", "2 selected")

      view |> element("#select-none") |> render_click()
      assert has_element?(view, "#export-form [data-role=selected-count]", "0 selected")
    end

    test "cancelling leaves select mode and clears the ticks", %{conn: conn, user: user} do
      apples = item(user, %{name: "Apples"})
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#start-select") |> render_click()
      view |> element("#item-#{apples.id} button[role=checkbox]") |> render_click()
      view |> element("#stop-select") |> render_click()

      refute has_element?(view, "#export-form")
      assert has_element?(view, "#item-#{apples.id} [data-role=stock]")

      view |> element("#start-select") |> render_click()
      assert has_element?(view, "#export-form [data-role=selected-count]", "0 selected")
    end
  end

  describe "checking the stock" do
    defp backdate(user, item, days) do
      item
      |> Ash.Changeset.for_update(:update, %{}, actor: user)
      |> Ash.Changeset.force_change_attribute(
        :stock_checked_at,
        DateTime.add(DateTime.utc_now(), -days, :day)
      )
      |> Ash.update!()
    end

    setup %{user: user} do
      mint = backdate(user, item(user, %{name: "Mint"}), 90)
      salt = backdate(user, item(user, %{name: "Salt"}), 30)
      apples = item(user, %{name: "Apples"})
      %{mint: mint, salt: salt, apples: apples}
    end

    defp start_check(conn) do
      {:ok, view, _html} = live(conn, ~p"/inventory/check/all")
      view
    end

    test "has its own tab and leaves the inventory list out", %{conn: conn} = ctx do
      view = start_check(conn)

      assert has_element?(view, "nav a[aria-current=page]", "Check")
      refute has_element?(view, "#items")
      refute has_element?(view, "#item-#{ctx.mint.id}")

      {:ok, inventory, _html} = live(conn, ~p"/inventory")
      assert has_element?(inventory, "nav a[aria-current=page]", "Inventory")
      assert has_element?(inventory, "nav a[href='/inventory/check']", "Check")
      refute has_element?(inventory, "#check-overlay")
    end

    test "walks through every item, longest unchecked first", %{conn: conn, user: user} = ctx do
      view = start_check(conn)

      assert has_element?(view, "#check-card-#{ctx.mint.id}", "Mint")

      assert has_element?(
               view,
               "#check-card-#{ctx.mint.id} [data-role=checked-ago]",
               "3 months ago"
             )

      assert has_element?(view, "[data-role=check-progress]", "1 of 3")

      view |> element("#check-next") |> render_click()
      assert has_element?(view, "#check-card-#{ctx.salt.id}", "Salt")
      assert has_element?(view, "[data-role=check-progress]", "2 of 3")

      view |> element("#check-prev") |> render_click()
      assert has_element?(view, "#check-card-#{ctx.mint.id}")

      # Moving on without confirming leaves the item due.
      assert DateTime.diff(DateTime.utc_now(), stored(user, ctx.mint).stock_checked_at, :day) >=
               89
    end

    test "Still right confirms the item and moves on", %{conn: conn, user: user} = ctx do
      view = start_check(conn)

      view |> element("#confirm-stock") |> render_click()

      assert DateTime.diff(DateTime.utc_now(), stored(user, ctx.mint).stock_checked_at, :second) <
               5

      assert stored(user, ctx.mint).stock_count == ctx.mint.stock_count
      assert has_element?(view, "#check-card-#{ctx.salt.id}")
    end

    test "changing the stock on the card updates the item", %{conn: conn, user: user} = ctx do
      view = start_check(conn)

      view
      |> element("#check-card-#{ctx.mint.id} button[aria-label='One more']")
      |> render_click()

      assert stored(user, ctx.mint).stock_count == ctx.mint.stock_count + 1
      assert has_element?(view, "#check-card-#{ctx.mint.id} [data-role=stock]", "2")
      assert has_element?(view, "#check-card-#{ctx.mint.id} [data-role=checked-ago]", "today")
    end

    test "deletes the item on the card and shows the next one", %{conn: conn, user: user} = ctx do
      view = start_check(conn)

      view |> element("#delete-checked") |> render_click()

      assert {:error, _} = Inventory.get_item(ctx.mint.id, actor: user)
      assert has_element?(view, "#check-card-#{ctx.salt.id}")
      assert has_element?(view, "[data-role=check-progress]", "1 of 2")
    end

    test "swiping left goes on, right goes back, and the ends say so", %{conn: conn} = ctx do
      view = start_check(conn)

      assert render_hook(view, "swipe_prev", %{}) =~ "Mint"
      assert has_element?(view, "#check-card-#{ctx.mint.id}")

      render_hook(view, "swipe_next", %{})
      assert has_element?(view, "#check-card-#{ctx.salt.id}")

      render_hook(view, "swipe_prev", %{})
      assert has_element?(view, "#check-card-#{ctx.mint.id}")
    end

    test "shows an all-checked card after the last item that leads back to the places", %{
      conn: conn
    } do
      view = start_check(conn)

      for _ <- 1..3, do: view |> element("#check-next") |> render_click()

      assert has_element?(view, "#check-done", "All checked")
      assert has_element?(view, "[data-role=check-progress]", "3 of 3")

      assert {:error, {:live_redirect, %{to: "/inventory/check"}}} =
               view |> element("#check-done a") |> render_click()
    end

    test "an item the other person deletes drops out of the check",
         %{
           conn: conn,
           user: user
         } = ctx do
      view = start_check(conn)

      Inventory.delete_item!(ctx.mint, actor: user)
      send(view.pid, %Phoenix.Socket.Broadcast{topic: "kitchen:changed", event: "update"})

      assert has_element?(view, "#check-card-#{ctx.salt.id}")
      assert has_element?(view, "[data-role=check-progress]", "1 of 2")
    end

    test "emptying an item during the check works like in the list",
         %{conn: conn, user: user} = ctx do
      view = start_check(conn)

      view
      |> element("#check-card-#{ctx.mint.id} button[phx-click=mark_empty]")
      |> render_click()

      assert stored(user, ctx.mint).stock_count == 0
      assert has_element?(view, "#undo", "Mint marked empty")
      assert [_entry] = Inventory.list_open_entries!(actor: user)
    end
  end

  describe "tags" do
    defp tag(user, name), do: Inventory.create_tag!(%{name: name}, actor: user)

    defp tagged(user, name, tags) do
      Inventory.create_item!(
        %{name: name, tracking: :level, tag_ids: Enum.map(tags, & &1.id)},
        actor: user
      )
    end

    test "rows show the tags under the name", %{conn: conn, user: user} do
      ground = tag(user, "ground")
      bio = tag(user, "Bio")
      cumin = tagged(user, "Cumin", [ground, bio])
      salt = tagged(user, "Salt", [])

      {:ok, view, _html} = live(conn, ~p"/inventory")

      assert has_element?(view, "#item-#{cumin.id} [data-role=tags]", "Bio · ground")
      refute has_element?(view, "#item-#{salt.id} [data-role=tags]")
    end

    test "search finds items by their tags", %{conn: conn, user: user} do
      ground = tag(user, "ground")
      cumin = tagged(user, "Cumin", [ground])
      salt = tagged(user, "Salt", [])
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> form("#search-form", search: %{query: "ground"}) |> render_change()

      assert has_element?(view, "#item-#{cumin.id}")
      refute has_element?(view, "#item-#{salt.id}")
    end

    test "tags are picked, created and removed in the edit form", %{conn: conn, user: user} do
      tag(user, "ground")
      cumin = tagged(user, "Cumin", [])
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{cumin.id} button[phx-click=edit]") |> render_click()
      assert has_element?(view, "#tag-picker [data-role=available-tag]", "ground")

      view |> element("#tag-picker [data-role=available-tag]", "ground") |> render_click()
      assert has_element?(view, "#tag-picker [data-role=chosen-tag]", "ground")

      view |> form("#item-form", tag_query: "Bio") |> render_change()
      view |> element("#tag-picker [data-role=create-tag]") |> render_click()
      assert has_element?(view, "#tag-picker [data-role=chosen-tag]", "Bio")

      submit_item_form(view)

      assert ["Bio", "ground"] ==
               cumin.id
               |> Inventory.get_item!(actor: user, load: [:tags])
               |> Kura.Inventory.Item.tag_line()
               |> String.split(" · ")

      view |> element("#item-#{cumin.id} button[phx-click=edit]") |> render_click()
      view |> element("#tag-picker [data-role=chosen-tag]", "Bio") |> render_click()
      view |> element("#tag-picker [data-role=chosen-tag]", "ground") |> render_click()
      submit_item_form(view)

      assert Inventory.get_item!(cumin.id, actor: user).tag_key == ""
    end

    test "typing a name with a tag word offers the item with that tag", %{conn: conn, user: user} do
      ground = tag(user, "ground")
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> form("#search-form", search: %{query: "Cumin ground"}) |> render_change()
      view |> element("#add-item button") |> render_click()

      assert has_element?(view, ~s(#item-form input[name="item[name]"][value=Cumin]))
      assert has_element?(view, "#tag-picker [data-role=chosen-tag]", "ground")

      submit_item_form(view)

      assert [cumin] = Inventory.search_items!("", actor: user)
      assert to_string(cumin.name) == "Cumin"
      assert cumin.tag_key == Kura.Inventory.Item.tag_key([ground.id])
    end

    test "Enter in the tag box takes the only match, or creates the tag", %{
      conn: conn,
      user: user
    } do
      tag(user, "ground")
      cumin = tagged(user, "Cumin", [])
      {:ok, view, _html} = live(conn, ~p"/inventory")
      view |> element("#item-#{cumin.id} button[phx-click=edit]") |> render_click()

      view |> form("#item-form", tag_query: "gro") |> render_change()
      view |> element("#tag-query") |> render_hook("chip_enter", %{"kind" => "tag"})
      assert has_element?(view, "#tag-picker [data-role=chosen-tag]", "ground")

      view |> form("#item-form", tag_query: "whole") |> render_change()
      view |> element("#tag-query") |> render_hook("chip_enter", %{"kind" => "tag"})
      assert has_element?(view, "#tag-picker [data-role=chosen-tag]", "whole")
      assert length(Inventory.list_tags!(actor: user)) == 2
    end

    test "two items cannot have the same name and tags", %{conn: conn, user: user} do
      ground = tag(user, "ground")
      tagged(user, "Cumin", [ground])
      other = tagged(user, "Cumin", [])
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{other.id} button[phx-click=edit]") |> render_click()
      view |> element("#tag-picker [data-role=available-tag]", "ground") |> render_click()
      html = submit_item_form(view)

      assert html =~ "is already in the inventory with these tags"
    end

    test "the check card shows the tags", %{conn: conn, user: user} do
      ground = tag(user, "ground")
      cumin = tagged(user, "Cumin", [ground])

      {:ok, view, _html} = live(conn, ~p"/inventory/check/all")

      assert has_element?(view, "#check-card-#{cumin.id} [data-role=tags]", "ground")
    end
  end

  describe "the item form while checking the stock" do
    test "opens as a sheet from the card, saves and closes", %{conn: conn, user: user} do
      mint = item(user, %{name: "Mint", stock_count: 2})
      {:ok, view, _html} = live(conn, ~p"/inventory/check/all")

      view |> element("#edit-checked") |> render_click()
      assert has_element?(view, "#item-form")
      assert has_element?(view, "h2", "Edit Mint")

      view |> form("#item-form", item: %{name: "Peppermint"}) |> render_submit()
      render(view)

      refute has_element?(view, "#item-form")
      assert to_string(stored(user, mint).name) == "Peppermint"
      assert has_element?(view, "#check-card-#{mint.id}", "Peppermint")
    end

    test "can delete the item from the sheet", %{conn: conn, user: user} do
      mint = item(user, %{name: "Mint"})
      {:ok, view, _html} = live(conn, ~p"/inventory/check/all")

      view |> element("#edit-checked") |> render_click()
      view |> element("button[phx-click=delete]") |> render_click()
      render(view)

      assert {:error, _} = Inventory.get_item(mint.id, actor: user)
      refute has_element?(view, "#item-form")
      assert has_element?(view, "#check-done")
    end

    test "Cancel closes the sheet and keeps the item as it was", %{conn: conn, user: user} do
      mint = item(user, %{name: "Mint"})
      {:ok, view, _html} = live(conn, ~p"/inventory/check/all")

      view |> element("#edit-checked") |> render_click()
      view |> form("#item-form", item: %{name: "Peppermint"}) |> render_change()
      view |> element("button[phx-click=close]", "Cancel") |> render_click()

      refute has_element?(view, "#item-form")
      assert to_string(stored(user, mint).name) == "Mint"
    end
  end

  describe "locations" do
    defp place(user, name), do: Inventory.create_location!(%{name: name}, actor: user)

    defp stocked(user, name, places) do
      Inventory.create_item!(
        %{name: name, tracking: :level, location_ids: Enum.map(places, & &1.id)},
        actor: user
      )
    end

    defp place_names(user, item) do
      item.id
      |> Inventory.get_item!(actor: user, load: [:locations])
      |> Map.fetch!(:locations)
      |> Enum.map(&to_string(&1.name))
      |> Enum.sort()
    end

    test "places are picked and created in the item form", %{conn: conn, user: user} do
      place(user, "Fridge")
      tahini = stocked(user, "Tahini", [])
      {:ok, view, _html} = live(conn, ~p"/inventory")

      view |> element("#item-#{tahini.id} button[phx-click=edit]") |> render_click()

      view
      |> element("#location-picker [data-role=available-location]", "Fridge")
      |> render_click()

      assert has_element?(view, "#location-picker [data-role=chosen-location]", "Fridge")

      view |> form("#item-form", location_query: "Cupboard") |> render_change()
      view |> element("#location-picker [data-role=create-location]") |> render_click()
      assert has_element?(view, "#location-picker [data-role=chosen-location]", "Cupboard")

      submit_item_form(view)
      assert place_names(user, tahini) == ["Cupboard", "Fridge"]

      view |> element("#item-#{tahini.id} button[phx-click=edit]") |> render_click()
      view |> element("#location-picker [data-role=chosen-location]", "Fridge") |> render_click()
      submit_item_form(view)
      assert place_names(user, tahini) == ["Cupboard"]
    end

    test "Enter in the place box takes the only match", %{conn: conn, user: user} do
      place(user, "Freezer")
      tahini = stocked(user, "Tahini", [])
      {:ok, view, _html} = live(conn, ~p"/inventory")
      view |> element("#item-#{tahini.id} button[phx-click=edit]") |> render_click()

      view |> form("#item-form", location_query: "free") |> render_change()
      view |> element("#location-query") |> render_hook("chip_enter", %{"kind" => "location"})

      assert has_element?(view, "#location-picker [data-role=chosen-location]", "Freezer")
    end

    test "rows show the places only while searching", %{conn: conn, user: user} do
      fridge = place(user, "Fridge")
      tahini = stocked(user, "Tahini", [fridge])
      {:ok, view, _html} = live(conn, ~p"/inventory")

      refute has_element?(view, "#item-#{tahini.id} [data-role=locations]")

      view |> form("#search-form", search: %{query: "fridge"}) |> render_change()
      assert has_element?(view, "#item-#{tahini.id} [data-role=locations]", "Fridge")

      view |> form("#search-form", search: %{query: "tahini"}) |> render_change()
      assert has_element?(view, "#item-#{tahini.id} [data-role=locations]", "Fridge")
    end

    test "Enter with several similar places creates nothing", %{conn: conn, user: user} do
      place(user, "Fridge door")
      place(user, "Fridge shelf")
      tahini = stocked(user, "Tahini", [])
      {:ok, view, _html} = live(conn, ~p"/inventory")
      view |> element("#item-#{tahini.id} button[phx-click=edit]") |> render_click()

      view |> form("#item-form", location_query: "fridge") |> render_change()
      view |> element("#location-query") |> render_hook("chip_enter", %{"kind" => "location"})

      refute has_element?(view, "#location-picker [data-role=chosen-location]")
      assert length(Inventory.list_locations!(actor: user)) == 2
    end

    test "the More menu has a Locations entry on the inventory too", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/inventory")

      assert has_element?(view, "nav #more-menu a[href='/locations']", "Locations")
    end
  end

  describe "checking one place" do
    setup %{user: user} do
      fridge = place(user, "Fridge")
      cupboard = place(user, "Cupboard")
      tahini = stocked(user, "Tahini", [fridge, cupboard])
      butter = stocked(user, "Butter", [fridge])
      rice = stocked(user, "Rice", [cupboard])
      loose = stocked(user, "Loose", [])

      %{
        fridge: fridge,
        cupboard: cupboard,
        tahini: tahini,
        butter: butter,
        rice: rice,
        loose: loose
      }
    end

    test "the Check tab starts with a picker of places, unplaced items and everything", %{
      conn: conn,
      fridge: fridge,
      cupboard: cupboard
    } do
      {:ok, view, _html} = live(conn, ~p"/inventory/check")

      assert has_element?(view, "nav a[aria-current=page]", "Check")
      assert has_element?(view, "#pick-#{fridge.id} [data-role=item-count]", "2 items")
      assert has_element?(view, "#pick-#{cupboard.id} [data-role=item-count]", "2 items")
      assert has_element?(view, "#pick-unplaced [data-role=item-count]", "1 item")
      assert has_element?(view, "#pick-all [data-role=item-count]", "4 items")
      refute has_element?(view, "#check-overlay")
      refute has_element?(view, "#items")
    end

    test "choosing a place walks only the items that live there, stalest first", %{
      conn: conn,
      user: user,
      fridge: fridge,
      tahini: tahini,
      butter: butter,
      rice: rice
    } do
      backdate(user, tahini, 60)
      backdate(user, butter, 30)

      {:ok, view, _html} = live(conn, ~p"/inventory/check")

      {:ok, view, _html} =
        view |> element("#pick-#{fridge.id}") |> render_click() |> follow_redirect(conn)

      assert has_element?(view, "[data-role=check-scope]", "Fridge")
      assert has_element?(view, "[data-role=check-progress]", "1 of 2")
      assert has_element?(view, "#check-card-#{tahini.id}")

      view |> element("#check-next") |> render_click()
      assert has_element?(view, "#check-card-#{butter.id}")

      view |> element("#check-next") |> render_click()
      assert has_element?(view, "#check-done")
      refute has_element?(view, "#check-card-#{rice.id}")
    end

    test "an item in another place too says so, an item only here does not", %{
      conn: conn,
      user: user,
      fridge: fridge,
      tahini: tahini,
      butter: butter
    } do
      backdate(user, tahini, 60)
      backdate(user, butter, 30)
      {:ok, view, _html} = live(conn, ~p"/inventory/check/#{fridge.id}")

      assert has_element?(
               view,
               "#check-card-#{tahini.id} [data-role=also-in]",
               "Also in Cupboard"
             )

      view |> element("#check-next") |> render_click()
      assert has_element?(view, "#check-card-#{butter.id}")
      refute has_element?(view, "[data-role=also-in]")
    end

    test "Not here anymore takes the place off the item and moves on", %{
      conn: conn,
      user: user,
      fridge: fridge,
      butter: butter,
      tahini: tahini
    } do
      backdate(user, butter, 60)
      backdate(user, tahini, 30)
      {:ok, view, _html} = live(conn, ~p"/inventory/check/#{fridge.id}")

      assert has_element?(view, "#check-card-#{butter.id}")
      view |> element("#not-here") |> render_click()

      refute has_element?(view, "#check-card-#{butter.id}")
      assert has_element?(view, "#check-card-#{tahini.id}")
      assert has_element?(view, "[data-role=check-progress]", "1 of 1")
      assert place_names(user, butter) == []
      assert {:ok, _} = Inventory.get_item(butter.id, actor: user)
    end

    test "Not here anymore keeps the other places of the item", %{
      conn: conn,
      user: user,
      fridge: fridge,
      butter: butter,
      tahini: tahini
    } do
      backdate(user, tahini, 60)
      backdate(user, butter, 30)
      {:ok, view, _html} = live(conn, ~p"/inventory/check/#{fridge.id}")

      assert has_element?(view, "#check-card-#{tahini.id}")
      view |> element("#not-here") |> render_click()

      assert place_names(user, tahini) == ["Cupboard"]
    end

    test "confirming in one place makes the item recent in the other", %{
      conn: conn,
      user: user,
      fridge: fridge,
      cupboard: cupboard,
      tahini: tahini,
      rice: rice
    } do
      backdate(user, tahini, 60)
      backdate(user, rice, 30)

      {:ok, view, _html} = live(conn, ~p"/inventory/check/#{fridge.id}")
      assert has_element?(view, "#check-card-#{tahini.id}")
      view |> element("#confirm-stock") |> render_click()

      # Stalest first: rice is now the first card in the cupboard and the confirmed item the last.
      {:ok, view, _html} = live(conn, ~p"/inventory/check/#{cupboard.id}")
      assert has_element?(view, "#check-card-#{rice.id}")
      view |> element("#check-next") |> render_click()
      assert has_element?(view, "#check-card-#{tahini.id} [data-role=checked-ago]", "today")
    end

    test "an item the other phone took out of the place drops out of the walk", %{
      conn: conn,
      user: user,
      fridge: fridge,
      butter: butter,
      tahini: tahini
    } do
      backdate(user, tahini, 60)
      backdate(user, butter, 30)
      {:ok, view, _html} = live(conn, ~p"/inventory/check/#{fridge.id}")
      assert has_element?(view, "#check-card-#{tahini.id}")

      link = Inventory.get_item_location!(tahini.id, fridge.id, actor: user)
      :ok = Inventory.remove_item_location(link, actor: user)
      render(view)

      refute has_element?(view, "#check-card-#{tahini.id}")
      assert has_element?(view, "#check-card-#{butter.id}")
      assert has_element?(view, "[data-role=check-progress]", "1 of 1")
    end

    test "Not here anymore does not crash when the place is already gone from the item", %{
      conn: conn,
      user: user,
      fridge: fridge,
      butter: butter
    } do
      {:ok, view, _html} = live(conn, ~p"/inventory/check/#{fridge.id}")
      assert has_element?(view, "#not-here")

      # The page has not heard yet: the notification is returned instead of broadcast.
      link = Inventory.get_item_location!(butter.id, fridge.id, actor: user)
      Ash.destroy!(link, actor: user, return_notifications?: true)

      view |> element("#not-here") |> render_click()
      assert render(view) =~ "Check stock"
    end

    test "unplaced items have their own stop", %{conn: conn, loose: loose} do
      {:ok, view, _html} = live(conn, ~p"/inventory/check/unplaced")

      assert has_element?(view, "[data-role=check-scope]", "Not placed yet")
      assert has_element?(view, "#check-card-#{loose.id}")
      assert has_element?(view, "[data-role=check-progress]", "1 of 1")
      refute has_element?(view, "#not-here")
    end

    test "Everything walks all items without the place buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/inventory/check/all")

      assert has_element?(view, "[data-role=check-progress]", "1 of 4")
      refute has_element?(view, "#not-here")
      refute has_element?(view, "[data-role=also-in]")
    end

    test "a place without items says so instead of celebrating", %{conn: conn, user: user} do
      empty = place(user, "Empty drawer")
      {:ok, view, _html} = live(conn, ~p"/inventory/check/#{empty.id}")

      assert has_element?(view, "#check-done", "Nothing here")
      refute has_element?(view, "#check-done", "All checked")
    end

    test "an unknown place goes back to the picker", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/inventory/check", flash: flash}}} =
               live(conn, ~p"/inventory/check/#{Ecto.UUID.generate()}")

      assert flash["error"] =~ "no longer exists"

      assert {:error, {:live_redirect, %{to: "/inventory/check"}}} =
               live(conn, ~p"/inventory/check/nonsense")
    end

    test "Change place leads back to the picker", %{conn: conn, fridge: fridge} do
      {:ok, view, _html} = live(conn, ~p"/inventory/check/#{fridge.id}")

      assert has_element?(view, "#change-place[href='/inventory/check']")
    end
  end
end
