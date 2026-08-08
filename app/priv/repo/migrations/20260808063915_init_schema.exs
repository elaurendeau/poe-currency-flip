defmodule PoeFlipFinder.Repo.Migrations.InitSchema do
  use Ecto.Migration

  # Mirrors docs/SCHEMA.md, consolidating the Java backend's V1/V2 Flyway
  # split into a single migration -- there's no deployed Ecto history to
  # replay incrementally, so known_to_ggg is part of the schema from the
  # start rather than a follow-up ALTER TABLE.

  def change do
    create table(:currency) do
      add :external_id, :text, null: false
      add :display_name, :text, null: false
      add :icon_url, :text
      add :item_type, :text, null: false
    end

    create unique_index(:currency, [:external_id])

    create constraint(:currency, :item_type_must_be_known,
             check: "item_type IN ('currency', 'divination_card')"
           )

    create table(:vendor_recipe) do
      add :input_currency_id, references(:currency), null: false
      add :input_quantity, :integer, null: false
      add :output_currency_id, references(:currency), null: false
      add :output_quantity, :integer, null: false
    end

    create constraint(:vendor_recipe, :input_quantity_must_be_positive,
             check: "input_quantity > 0"
           )

    create constraint(:vendor_recipe, :output_quantity_must_be_positive,
             check: "output_quantity > 0"
           )

    create table(:divination_card, primary_key: false) do
      add :currency_id, references(:currency), primary_key: true
      add :stack_size, :integer, null: false
      add :reward_currency_id, references(:currency)
      add :reward_quantity, :integer
      # false = excluded gamble card, kept for visibility (docs/PRD.md § 7.3)
      add :predictable, :boolean, null: false, default: false
    end

    create constraint(:divination_card, :stack_size_must_be_positive, check: "stack_size > 0")

    create table(:league) do
      add :external_id, :text, null: false
      add :display_name, :text, null: false
      add :is_current, :boolean, null: false, default: false
      add :has_exchange_activity, :boolean, null: false, default: false
      # True only once a real GGG Leagues API sync has confirmed this league
      # exists -- ingestion creates a row for any league string it sees in
      # raw trade data too, including private leagues GGG's public API
      # never lists. GET /leagues filters on this flag.
      add :known_to_ggg, :boolean, null: false, default: false
    end

    create unique_index(:league, [:external_id])

    # Singleton row: the ingestion checkpoint and the active-generation
    # pointer for the hot-swap flow below.
    create table(:exchange_ingestion_state, primary_key: false) do
      add :id, :smallint, primary_key: true
      add :last_processed_change_id, :bigint
      add :active_generation_id, :bigint, null: false, default: 0
      add :active_generation_refreshed_at, :utc_datetime_usec
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:exchange_ingestion_state, :id_must_be_one, check: "id = 1")

    execute(
      "INSERT INTO exchange_ingestion_state (id, active_generation_id, updated_at) VALUES (1, 0, now())",
      "DELETE FROM exchange_ingestion_state WHERE id = 1"
    )

    # Current market state only, generation-tagged for atomic hot-swap; no
    # history retained. See docs/SCHEMA.md § Ingestion state and market
    # data for the full refresh flow this table participates in.
    create table(:exchange_market_snapshot) do
      add :generation_id, :bigint, null: false
      add :league_id, references(:league), null: false
      add :currency_a_id, references(:currency), null: false
      add :currency_b_id, references(:currency), null: false
      # :utc_datetime (second precision), not :utc_datetime_usec -- this
      # value is always DateTime.from_unix!/1 on a GGG change-stream epoch
      # second, which has no sub-second meaning at all. Repo.insert_all
      # (unlike Repo.insert with a changeset) does no precision coercion,
      # so a usec column here crashes on a real, second-precision value.
      add :snapshot_hour, :utc_datetime, null: false
      add :volume_traded_a, :bigint, null: false
      add :volume_traded_b, :bigint, null: false
      add :lowest_stock_a, :bigint, null: false
      add :highest_stock_a, :bigint, null: false
      add :lowest_stock_b, :bigint, null: false
      add :highest_stock_b, :bigint, null: false
      add :lowest_ratio_a, :float, null: false
      add :highest_ratio_a, :float, null: false
      add :lowest_ratio_b, :float, null: false
      add :highest_ratio_b, :float, null: false
    end

    create unique_index(
             :exchange_market_snapshot,
             [:generation_id, :league_id, :currency_a_id, :currency_b_id],
             name: :exchange_market_snapshot_generation_league_pair_index
           )

    create index(:exchange_market_snapshot, [:generation_id])
    create index(:exchange_market_snapshot, [:league_id])
  end
end
