defmodule KuraWeb.SnapshotPushTest do
  use KuraWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Kura.Inventory

  setup :log_in_user

  for path <- ["/inventory", "/"] do
    test "#{path} hands the phone a saved copy when it opens", %{conn: conn, user: user} do
      Inventory.create_item!(%{name: "Apples", tracking: :count}, actor: user)

      {:ok, view, _html} = live(conn, unquote(path))

      assert_push_event(view, "kura:snapshot", %{
        items: [%{name: "Apples"}],
        open: [],
        checked: []
      })
    end
  end

  test "and a fresh one whenever anything changes", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert_push_event(view, "kura:snapshot", %{items: []})

    apples = Inventory.create_item!(%{name: "Apples", tracking: :count}, actor: user)
    Inventory.add_entry!(%{item_id: apples.id}, actor: user)

    assert_push_event(view, "kura:snapshot", %{
      items: [%{name: "Apples"}],
      open: [%{name: "Apples"}]
    })
  end
end
