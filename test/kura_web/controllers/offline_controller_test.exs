defmodule KuraWeb.OfflineControllerTest do
  use KuraWeb.ConnCase

  alias Kura.Inventory

  defp api(conn), do: put_req_header(conn, "accept", "application/json")

  describe "GET /offline" do
    test "serves the offline screens without signing in", %{conn: conn} do
      html = conn |> get(~p"/offline") |> html_response(200)

      assert html =~ ~s(id="offline-root")
    end
  end

  describe "GET /offline/state" do
    test "is refused without a signed-in user", %{conn: conn} do
      assert %{"error" => _} = conn |> api() |> get(~p"/offline/state") |> json_response(401)
    end

    test "returns the snapshot", %{conn: conn} do
      %{conn: conn, user: user} = log_in_user(%{conn: conn})
      Inventory.create_item!(%{name: "Apples", tracking: :count}, actor: user)

      body = conn |> api() |> get(~p"/offline/state") |> json_response(200)

      assert %{"items" => [%{"name" => "Apples"}], "open" => [], "checked" => []} = body
    end
  end

  describe "POST /offline/sync" do
    setup %{conn: conn} do
      %{conn: conn, user: user} = log_in_user(%{conn: conn})

      item =
        Inventory.create_item!(%{name: "Apples", tracking: :count, stock_count: 1}, actor: user)

      entry = Inventory.add_entry!(%{item_id: item.id, quantity: 4}, actor: user)
      %{conn: api(conn), user: user, item: item, entry: entry}
    end

    test "needs the offline header, which a cross-site form cannot send", %{
      conn: conn,
      entry: entry
    } do
      conn = post(conn, ~p"/offline/sync", %{changes: [%{op: "check", entry_id: entry.id}]})

      assert json_response(conn, 403)
    end

    test "is refused without a signed-in user", %{entry: entry} do
      conn =
        build_conn()
        |> api()
        |> put_req_header("x-kura-offline", "1")
        |> post(~p"/offline/sync", %{changes: [%{op: "check", entry_id: entry.id}]})

      assert json_response(conn, 401)
    end

    test "applies the changes and returns the fresh snapshot", %{
      conn: conn,
      user: user,
      item: item,
      entry: entry
    } do
      body =
        conn
        |> put_req_header("x-kura-offline", "1")
        |> post(~p"/offline/sync", %{changes: [%{op: "check", entry_id: entry.id}]})
        |> json_response(200)

      assert %{
               "applied" => 1,
               "skipped" => 0,
               "snapshot" => %{"open" => [], "checked" => [%{"quantity" => 4}]}
             } =
               body

      assert Inventory.get_item!(item.id, actor: user).stock_count == 5
    end

    test "copes with a body without changes", %{conn: conn} do
      body =
        conn
        |> put_req_header("x-kura-offline", "1")
        |> post(~p"/offline/sync", %{})
        |> json_response(200)

      assert %{"applied" => 0, "skipped" => 0} = body
    end
  end

  describe "GET /sw.js" do
    test "serves a service worker for the whole site that caches the offline screens", %{
      conn: conn
    } do
      conn = get(conn, ~p"/sw.js")
      body = response(conn, 200)

      assert [type] = get_resp_header(conn, "content-type")
      assert type =~ "javascript"
      assert get_resp_header(conn, "service-worker-allowed") == ["/"]
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
      assert body =~ ~s("/offline")
      assert body =~ "/assets/css/app.css"
      assert body =~ "/assets/js/app.js"
      assert body =~ "/fonts/dm-sans-latin-wght-normal.woff2"
    end
  end

  describe "the web app manifest" do
    test "is served and names the app", %{conn: conn} do
      body = conn |> get("/manifest.webmanifest") |> response(200) |> Jason.decode!()

      assert %{"name" => "Kura", "display" => "standalone", "start_url" => "/", "scope" => "/"} =
               body

      assert Enum.any?(body["icons"], &(&1["sizes"] == "192x192"))
      assert Enum.any?(body["icons"], &(&1["sizes"] == "512x512"))
    end
  end
end
