# Fixtures

Real, captured responses from GGG's public APIs — reused from the Java backend's
`backend/src/test/resources/fixtures/` rather than recaptured, per
[docs/ELIXIR_TEST_MANIFESTO.md § Fixture Governance](../../../docs/ELIXIR_TEST_MANIFESTO.md#fixture-governance).
No hand-written/approximated JSON — every file here is a byte-for-byte real response.

| File | Source | Captured |
|---|---|---|
| `ggg_exchange/single_hour_page.json` | GGG Currency Exchange change-stream API, one normal hour page | 2026-08-06 |
| `ggg_exchange/tip_404.json` | GGG Currency Exchange change-stream API, the "at tip" 404 sentinel (echoed `next_change_id`, empty `markets`) | 2026-08-06 |
| `ggg_leagues/current_leagues.json` | GGG public Leagues API | 2026-08-06 |
| `ggg_item_icons/catalog.json` | Item icon catalog response | 2026-08-06 |

Refresh discipline: when a source is suspected to have changed, or periodically regardless,
recapture from the live endpoint and replace the file wholesale — don't hand-edit these.
