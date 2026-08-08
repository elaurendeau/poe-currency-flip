defmodule PoeFlipFinder.Repo do
  use Ecto.Repo,
    otp_app: :poe_flip_finder,
    adapter: Ecto.Adapters.Postgres
end
