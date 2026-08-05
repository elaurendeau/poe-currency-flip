-- Reference schema matching docs/SCHEMA.md. Intended final location once the
-- Spring Boot project is scaffolded: src/main/resources/db/migration/V1__init_schema.sql
-- (Flyway's default classpath location). See docs/TECH_STACK.md for tooling.

-- Reference data: tradeable items (currency and divination cards)
CREATE TABLE currency (
    id           BIGSERIAL PRIMARY KEY,
    external_id  TEXT NOT NULL UNIQUE,        -- GGG's raw item path, e.g. "Metadata/Items/Currency/CurrencyPortal"
    display_name TEXT NOT NULL,               -- e.g. "Portal Scroll"
    icon_url     TEXT,                        -- see docs/DATA_SOURCES.md § Item Icons
    item_type    TEXT NOT NULL CHECK (item_type IN ('CURRENCY', 'DIVINATION_CARD'))
);

-- Reference data: vendor sell-rates and recipes (manually captured, see docs/DATA_SOURCES.md)
CREATE TABLE vendor_recipe (
    id                  BIGSERIAL PRIMARY KEY,
    input_currency_id   BIGINT NOT NULL REFERENCES currency(id),
    input_quantity      INTEGER NOT NULL CHECK (input_quantity > 0),
    output_currency_id  BIGINT NOT NULL REFERENCES currency(id),
    output_quantity     INTEGER NOT NULL CHECK (output_quantity > 0)
);

-- Reference data: divination card turn-in rewards (manually captured and classified)
CREATE TABLE divination_card (
    currency_id        BIGINT PRIMARY KEY REFERENCES currency(id),
    stack_size         INTEGER NOT NULL CHECK (stack_size > 0),
    reward_currency_id BIGINT REFERENCES currency(id),
    reward_quantity    INTEGER,
    is_predictable     BOOLEAN NOT NULL DEFAULT FALSE  -- false = excluded gamble card, kept for visibility
);

-- League cache, refreshed from the live Leagues API (docs/DATA_SOURCES.md § League List)
CREATE TABLE league (
    id                    BIGSERIAL PRIMARY KEY,
    external_id           TEXT NOT NULL UNIQUE,  -- GGG's league id, e.g. "Allflame"
    display_name          TEXT NOT NULL,
    is_current            BOOLEAN NOT NULL DEFAULT FALSE,
    has_exchange_activity BOOLEAN NOT NULL DEFAULT FALSE
);

-- Singleton ingestion cursor and active-generation pointer (see docs/SCHEMA.md for the hot-swap flow)
CREATE TABLE exchange_ingestion_state (
    id                              SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    last_processed_change_id       BIGINT,
    active_generation_id           BIGINT NOT NULL DEFAULT 0,
    active_generation_refreshed_at TIMESTAMPTZ,
    updated_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO exchange_ingestion_state (id, active_generation_id) VALUES (1, 0);

-- Current market state only, generation-tagged for atomic hot-swap; no history retained
CREATE TABLE exchange_market_snapshot (
    id               BIGSERIAL PRIMARY KEY,
    generation_id    BIGINT NOT NULL,
    league_id        BIGINT NOT NULL REFERENCES league(id),
    currency_a_id    BIGINT NOT NULL REFERENCES currency(id),
    currency_b_id    BIGINT NOT NULL REFERENCES currency(id),
    snapshot_hour    TIMESTAMPTZ NOT NULL,
    volume_traded_a  BIGINT NOT NULL,
    volume_traded_b  BIGINT NOT NULL,
    lowest_stock_a   BIGINT NOT NULL,
    highest_stock_a  BIGINT NOT NULL,
    lowest_stock_b   BIGINT NOT NULL,
    highest_stock_b  BIGINT NOT NULL,
    lowest_ratio_a   DOUBLE PRECISION NOT NULL,
    highest_ratio_a  DOUBLE PRECISION NOT NULL,
    lowest_ratio_b   DOUBLE PRECISION NOT NULL,
    highest_ratio_b  DOUBLE PRECISION NOT NULL,
    UNIQUE (generation_id, league_id, currency_a_id, currency_b_id)
);

CREATE INDEX idx_exchange_market_snapshot_generation ON exchange_market_snapshot (generation_id);
CREATE INDEX idx_exchange_market_snapshot_league ON exchange_market_snapshot (league_id);
