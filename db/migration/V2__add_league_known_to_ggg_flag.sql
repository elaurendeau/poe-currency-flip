-- Distinguishes leagues actually returned by GGG's public Leagues API from
-- one-off/private league names that merely showed up in raw Currency
-- Exchange trade data (ingestion creates a league row for any string it
-- sees there, including private leagues GGG's Leagues API never lists).
-- GET /leagues must only ever show the former -- see docs/SCHEMA.md.
ALTER TABLE league ADD COLUMN known_to_ggg BOOLEAN NOT NULL DEFAULT FALSE;
