defmodule KuraWeb.PwaController do
  @moduledoc """
  Serves the service worker. It is generated, not a static file, because it has to list the
  current (digested in production) URLs of the assets it keeps for offline use, and its cache
  name changes whenever that list does, which is what makes phones pick up a new version.
  """
  use KuraWeb, :controller

  require EEx

  @external_resource Path.expand("pwa/sw.js.eex", __DIR__)
  EEx.function_from_file(:defp, :render_sw, Path.expand("pwa/sw.js.eex", __DIR__), [
    :cache,
    :precache
  ])

  def service_worker(conn, _params) do
    precache = [
      ~p"/offline",
      ~p"/assets/css/app.css",
      ~p"/assets/js/app.js",
      ~p"/fonts/fraunces-latin-wght-normal.woff2",
      ~p"/fonts/dm-sans-latin-wght-normal.woff2",
      ~p"/manifest.webmanifest",
      ~p"/icon-192.png",
      ~p"/apple-touch-icon.png"
    ]

    cache = "kura-" <> Integer.to_string(:erlang.phash2(precache), 36)

    conn
    |> put_resp_content_type("application/javascript")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("service-worker-allowed", "/")
    |> send_resp(200, render_sw(cache, Jason.encode!(precache)))
  end
end
