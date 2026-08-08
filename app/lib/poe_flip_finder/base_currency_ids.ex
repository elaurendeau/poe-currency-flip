defmodule PoeFlipFinder.BaseCurrencyIds do
  @moduledoc """
  GGG's own path-style item identifiers for the two currencies every
  Exchange Spread and Bulk Buy opportunity is anchored on -- see
  docs/DATA_SOURCES.md § Item Icons for where this external_id format
  comes from.
  """

  @chaos_external_id "Metadata/Items/Currency/CurrencyRerollRare"
  @divine_external_id "Metadata/Items/Currency/CurrencyModValues"

  @spec chaos_external_id() :: String.t()
  def chaos_external_id, do: @chaos_external_id

  @spec divine_external_id() :: String.t()
  def divine_external_id, do: @divine_external_id
end
