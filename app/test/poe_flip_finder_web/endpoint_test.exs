defmodule PoeFlipFinderWeb.EndpointTest do
  use PoeFlipFinderWeb.ConnCase, async: false

  # In prod, `~p"/favicon.svg"` renders the digested filename `mix
  # phx.digest` actually writes (e.g. "favicon-<hash>.svg?vsn=d"), not the
  # literal "favicon.svg" in `PoeFlipFinderWeb.static_paths/0`'s `:only`
  # list. Without `only_matching: ["favicon"]` on the endpoint's
  # `Plug.Static`, that digested request 404s and no favicon ever loads --
  # this reproduces it by dropping a digest-shaped fixture file next to the
  # real one and requesting it through the real endpoint pipeline.
  test "serves a digested favicon filename, not just the literal favicon.svg", %{conn: conn} do
    static_dir = Application.app_dir(:poe_flip_finder, "priv/static")
    digested_path = Path.join(static_dir, "favicon-testfixturehash.svg")

    File.write!(digested_path, File.read!(Path.join(static_dir, "favicon.svg")))
    on_exit(fn -> File.rm(digested_path) end)

    conn = get(conn, "/favicon-testfixturehash.svg?vsn=d")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/svg+xml"]
  end
end
