defmodule Kura.Inventory.BroadcastTest do
  use Kura.DataCase

  alias Kura.Inventory

  setup do
    user =
      Kura.Accounts.create_user!(%{username: "lukas", password: "correct horse battery"},
        authorize?: false
      )

    KuraWeb.Endpoint.subscribe("kitchen:changed")
    %{actor: user}
  end

  test "creating, changing and deleting an item is announced", %{actor: actor} do
    item = Inventory.create_item!(%{name: "Apples", tracking: :count}, actor: actor)
    assert_receive %Phoenix.Socket.Broadcast{topic: "kitchen:changed", event: "create"}

    Inventory.change_item_count!(item, 1, actor: actor)
    assert_receive %Phoenix.Socket.Broadcast{topic: "kitchen:changed", event: "change_count"}

    Inventory.delete_item!(item, actor: actor)
    assert_receive %Phoenix.Socket.Broadcast{topic: "kitchen:changed", event: "destroy"}
  end

  test "changes to the shopping list are announced", %{actor: actor} do
    item = Inventory.create_item!(%{name: "Apples", tracking: :count}, actor: actor)
    flush_broadcasts()

    entry = Inventory.add_entry!(%{item_id: item.id}, actor: actor)
    assert_receive %Phoenix.Socket.Broadcast{topic: "kitchen:changed", event: "add"}

    Inventory.check_off_entry!(entry, actor: actor)
    assert_receive %Phoenix.Socket.Broadcast{topic: "kitchen:changed", event: "check_off"}
  end

  defp flush_broadcasts do
    receive do
      %Phoenix.Socket.Broadcast{} -> flush_broadcasts()
    after
      50 -> :ok
    end
  end
end
