defmodule PoeFlipFinder.Gateways.GggExchangeSourceGateway do
  @moduledoc """
  The imperative-shell implementation of `PoeFlipFinder.ExchangeSourceGateway`,
  calling GGG's public Currency Exchange change-stream
  (docs/DATA_SOURCES.md § Currency Exchange Data). This is the
  Anti-Corruption Layer boundary: everything above this module only ever
  sees `PoeFlipFinder.ExchangeMarketEntry`, never GGG's raw JSON shape.

  Reaching the current, still-open hour is signaled by an HTTP 404 whose
  body echoes the requested change id back with an empty markets array --
  verified by direct testing 2026-08-06, not a failure.
  """

  @behaviour PoeFlipFinder.ExchangeSourceGateway

  alias PoeFlipFinder.{ExchangeChangeStreamPage, ExchangeMarketEntry}

  @default_base_url "https://web.poecdn.com"

  @impl true
  def fetch_hour(change_id) do
    url = base_url() <> "/api/currency-exchange/#{change_id}"

    # retry: false -- matches the Java gateway's behavior (a failure
    # propagates immediately; no automatic retry). Req retries on 5xx and
    # transport errors by default, which would also fight Bypass's
    # expect_once assertions in tests.
    case Req.get(url, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, normalize(decode(body), change_id, false)}

      {:ok, %Req.Response{status: 404, body: body}} ->
        {:ok, normalize(decode(body), change_id, true)}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:poe_flip_finder, __MODULE__, [])[:base_url] || @default_base_url
  end

  # Req auto-decodes a JSON response body by content-type already, but a
  # Bypass-served response in tests may hand back a raw string -- accept
  # both so tests don't need to fake response headers just to satisfy this.
  defp decode(body) when is_binary(body), do: Jason.decode!(body)
  defp decode(body) when is_map(body), do: body

  @doc "Exposed so contract tests can exercise parsing without a live HTTP call."
  @spec normalize(map(), integer(), boolean()) :: ExchangeChangeStreamPage.t()
  def normalize(raw, requested_change_id, at_tip) do
    snapshot_hour = DateTime.from_unix!(requested_change_id)

    entries =
      raw
      |> Map.fetch!("markets")
      |> Enum.map(&to_entry(&1, snapshot_hour))

    %ExchangeChangeStreamPage{
      entries: entries,
      next_change_id: Map.fetch!(raw, "next_change_id"),
      at_tip: at_tip
    }
  end

  defp to_entry(raw, snapshot_hour) do
    [a, b] = raw["market_pair"]

    %ExchangeMarketEntry{
      league_external_id: raw["league"],
      currency_a_external_id: a,
      currency_b_external_id: b,
      snapshot_hour: snapshot_hour,
      volume_traded_a: long_value(raw["volume_traded"], a),
      volume_traded_b: long_value(raw["volume_traded"], b),
      lowest_stock_a: long_value(raw["lowest_stock"], a),
      highest_stock_a: long_value(raw["highest_stock"], a),
      lowest_stock_b: long_value(raw["lowest_stock"], b),
      highest_stock_b: long_value(raw["highest_stock"], b),
      lowest_ratio_a: double_value(raw["lowest_ratio"], a),
      highest_ratio_a: double_value(raw["highest_ratio"], a),
      lowest_ratio_b: double_value(raw["lowest_ratio"], b),
      highest_ratio_b: double_value(raw["highest_ratio"], b)
    }
  end

  defp long_value(values_by_item_path, item_path), do: Map.get(values_by_item_path, item_path, 0)

  # GGG's JSON omits the decimal point for whole-number ratios, so Jason
  # decodes those as integers -- forced to float here so callers always see
  # the same type Java's `double` deserialization would have produced.
  defp double_value(values_by_item_path, item_path) do
    values_by_item_path |> Map.get(item_path, 0) |> to_float()
  end

  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_float(value), do: value
end
