defmodule PoeFlipFinder.Gateways do
  @moduledoc """
  Concrete implementations of the `@behaviour`s the core contexts define for
  what they need from outside (GGG's Currency Exchange API, GGG's Leagues
  API, the item-icon catalog, Ecto-backed persistence).

  Nothing outside this boundary sees a raw external response shape or a raw
  `Ecto.Schema` — only the normalized domain structs defined in `PoeFlipFinder`.
  Which concrete module satisfies a given behaviour is chosen via
  `Application.get_env/3`, configured per Mix env, so contexts depend on the
  behaviour (part of `PoeFlipFinder`), never on a module in this boundary
  directly.

  See docs/ELIXIR_CODE_STYLE.md § Clean Architecture / Layering, Elixir Shape.
  """

  use Boundary, deps: [PoeFlipFinder], exports: :all
end
