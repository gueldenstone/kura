defmodule KuraWeb.LabelControllerTest do
  use KuraWeb.ConnCase

  alias Kura.Inventory

  describe "GET /inventory/labels.csv" do
    test "redirects to sign in without a user", %{conn: conn} do
      conn = get(conn, ~p"/inventory/labels.csv")

      assert redirected_to(conn) == ~p"/sign-in"
    end

    test "downloads the selected item names by name", %{conn: conn} do
      %{conn: conn, user: user} = log_in_user(%{conn: conn})
      walnuts = Inventory.create_item!(%{name: "Walnuts", tracking: :level}, actor: user)
      apples = Inventory.create_item!(%{name: "Apples", tracking: :count}, actor: user)
      Inventory.create_item!(%{name: "Rice", tracking: :count}, actor: user)

      conn = get(conn, ~p"/inventory/labels.csv", ids: [walnuts.id, apples.id])

      assert response(conn, 200) == "Label\r\nApples\r\nWalnuts\r\n"
      assert [type] = get_resp_header(conn, "content-type")
      assert type =~ "text/csv"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~s(attachment; filename="labels.csv")
    end

    test "prints the tags that set items of the same name apart and skips switched-off ones", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_user(%{conn: conn})
      hot = Inventory.create_tag!(%{name: "hot"}, actor: user)
      sweet = Inventory.create_tag!(%{name: "sweet"}, actor: user)
      ground = Inventory.create_tag!(%{name: "ground"}, actor: user)
      red = Inventory.create_tag!(%{name: "red", print_on_labels: false}, actor: user)

      paprika = fn tags ->
        Inventory.create_item!(
          %{name: "Paprika", tracking: :level, tag_ids: Enum.map(tags, & &1.id)},
          actor: user
        )
      end

      first = paprika.([hot, ground, red])
      second = paprika.([sweet, ground])

      unique =
        Inventory.create_item!(%{name: "Salt", tracking: :level, tag_ids: [ground.id]},
          actor: user
        )

      conn = get(conn, ~p"/inventory/labels.csv", ids: [first.id, second.id, unique.id])

      assert response(conn, 200) == "Label\r\nPaprika hot\r\nPaprika sweet\r\nSalt\r\n"
    end

    test "ignores unknown and malformed ids", %{conn: conn} do
      %{conn: conn, user: user} = log_in_user(%{conn: conn})
      apples = Inventory.create_item!(%{name: "Apples", tracking: :count}, actor: user)

      conn =
        get(conn, ~p"/inventory/labels.csv", ids: [apples.id, Ecto.UUID.generate(), "nonsense"])

      assert response(conn, 200) == "Label\r\nApples\r\n"
    end

    test "is only the header without ids", %{conn: conn} do
      %{conn: conn} = log_in_user(%{conn: conn})

      assert conn |> get(~p"/inventory/labels.csv") |> response(200) == "Label\r\n"
    end
  end
end
