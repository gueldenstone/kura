defmodule KuraWeb.SpikeController do
  @moduledoc """
  THROWAWAY offline spike (docs/adr/0003). Serves a plain-JS PWA from priv/spike and a tiny
  in-memory API. Delete together with the /spike routes once ADR 0003 is decided.
  """
  use KuraWeb, :controller

  @agent __MODULE__.Store

  @initial %{
    shopping: [
      %{id: 1, name: "Walnuts", qty: 1, checked: false, ts: 0},
      %{id: 2, name: "Apples", qty: 6, checked: false, ts: 0},
      %{id: 3, name: "Oat milk", qty: 2, checked: false, ts: 0}
    ],
    inventory: [
      %{name: "Walnuts", stock: "empty"},
      %{name: "Apples", stock: 0},
      %{name: "Oat milk", stock: "low"},
      %{name: "Rice", stock: "plenty"}
    ]
  }

  def page(conn, _params), do: file(conn, "index.html", "text/html")
  def asset(conn, %{"name" => name}), do: file(conn, name, MIME.from_path(name))

  def state(conn, _params), do: json(conn, store())

  def check(conn, %{"changes" => changes}) do
    Agent.update(@agent, fn s ->
      Enum.reduce(changes, s, fn %{"id" => id, "checked" => checked, "ts" => ts}, acc ->
        shopping =
          Enum.map(acc.shopping, fn
            %{id: ^id, ts: old} = item when ts >= old -> %{item | checked: checked, ts: ts}
            item -> item
          end)

        %{acc | shopping: shopping}
      end)
    end)

    json(conn, store())
  end

  def reset(conn, _params) do
    Agent.update(@agent, fn _ -> @initial end)
    json(conn, store())
  end

  defp store do
    case Agent.start(fn -> @initial end, name: @agent) do
      _ -> Agent.get(@agent, & &1)
    end
  end

  defp file(conn, name, type) do
    path = Path.join(Application.app_dir(:kura, "priv/spike"), Path.basename(name))

    if File.regular?(path) do
      conn
      |> put_resp_content_type(type)
      |> put_resp_header("cache-control", "no-cache")
      |> send_file(200, path)
    else
      send_resp(conn, 404, "not found")
    end
  end
end
