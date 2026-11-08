defmodule KuraWeb.AuthTest do
  use KuraWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "when logged out" do
    test "the app pages redirect to the sign-in page", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/")) == ~p"/sign-in"
    end

    test "app pages redirect to the sign-in page in LiveView too", %{conn: conn} do
      for path <- [~p"/", ~p"/inventory"] do
        assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, path)
      end
    end

    test "there is no registration page", %{conn: conn} do
      assert response(get(conn, "/register"), 404)
    end

    test "there is no registration endpoint", %{conn: conn} do
      assert response(post(conn, "/auth/user/password/register", %{}), 404)
    end

    test "the sign-in page asks for a username and password", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ "Username"
      assert html =~ "Password"
      refute html =~ "Email"
    end
  end

  describe "signing in" do
    test "with valid credentials lands on the shopping list", %{conn: conn} do
      %{password: password} = create_user("lukas")
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      form =
        form(view, "#user-password-sign-in-with-password",
          user: %{username: "lukas", password: password}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert {:ok, _view, html} = live(recycle(conn), ~p"/")
      assert html =~ "Shopping list"
    end

    test "with remember me survives losing the session cookie", %{conn: conn} do
      %{password: password} = create_user("lukas")
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      form =
        form(view, "#user-password-sign-in-with-password",
          user: %{username: "lukas", password: password, remember_me: "true"}
        )

      conn = submit_form(form, conn)
      remember_me = conn.resp_cookies["remember_me"]
      assert remember_me.max_age > 0

      # A phone that closes the PWA drops the session cookie but keeps the
      # persistent remember-me cookie.
      conn =
        build_conn()
        |> put_req_cookie("remember_me", remember_me.value)
        |> get(~p"/")

      assert html_response(conn, 200) =~ "Shopping list"
    end

    test "with a wrong password stays signed out", %{conn: conn} do
      create_user("lukas")
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      form =
        form(view, "#user-password-sign-in-with-password",
          user: %{username: "lukas", password: "not the password"}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Incorrect username or password"
      assert redirected_to(get(recycle(conn), ~p"/")) == ~p"/sign-in"
    end
  end

  describe "when logged in" do
    setup :log_in_user

    test "/ is the shopping list itself, not a redirect", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Shopping list"
    end

    test "the old /shopping-list address redirects to /", %{conn: conn} do
      assert redirected_to(get(conn, "/shopping-list")) == ~p"/"
    end

    test "the sign-in page redirects into the app", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/sign-in")
    end

    test "both app pages render with the navigation", %{conn: conn} do
      for {path, heading} <- [
            {~p"/", "Shopping list"},
            {~p"/inventory", "Inventory"}
          ] do
        {:ok, view, html} = live(conn, path)

        assert html =~ heading
        assert has_element?(view, ~s|nav a[href="/"]|, "Shopping list")
        assert has_element?(view, ~s|nav a[href="/inventory"]|, "Inventory")
        assert has_element?(view, ~s|a[href="/sign-out"][data-method="delete"]|)
      end
    end

    test "signing out returns to the sign-in page", %{conn: conn} do
      conn = delete(conn, ~p"/sign-out")

      assert redirected_to(conn) == ~p"/sign-in"
      assert redirected_to(get(recycle(conn), ~p"/")) == ~p"/sign-in"
    end
  end
end
