defmodule PoeFlipFinder.CurrencyReferenceGateway do
  @moduledoc """
  Defined by the core: resolve a Currency Exchange item path to a persisted
  Currency row, creating one on first sight via `PoeFlipFinder.ItemIconGateway`.
  `nil` means the item genuinely can't be resolved even there -- the caller
  treats that as skip-this-pair, not a run failure (see
  docs/ARCHITECTURE.md § Currency Exchange Ingestion).
  """

  alias PoeFlipFinder.Currency

  @callback resolve_or_create_currency(external_id :: String.t()) :: Currency.t() | nil
end
