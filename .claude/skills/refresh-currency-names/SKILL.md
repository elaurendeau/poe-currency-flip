---
description: Refresh the vendored Supplementary Currency Names data (app/priv/reference-data/currency-names.json), then verify it end to end before anything is committed.
disable-model-invocation: true
allowed-tools: Bash Read Grep
---

# Refresh Supplementary Currency Names

This data (docs/DATA_SOURCES.md § Supplementary Currency Names) supplies
a real display name for currency items GGG's own bundled Item Icons
catalog has no entry for at all (see `.claude/skills/refresh-item-icons-catalog`
for that separate, GGG-sourced catalog). Source: `repoe-fork/pob-data`,
Path of Building's own automated data export, kept current by a scheduled
CI job on the upstream repo. Refreshing it only matters when a new
league/item ships and GggItemIconGateway starts falling back to a
generic humanized name for something this source should now cover.

**Unlike the Item Icons catalog, this has no residential-network
requirement.** `raw.githubusercontent.com` is not blocked from
datacenter IPs -- this can run from CI or a cloud sandbox same as any
other step here.

## Steps

1. Run the refresh script from the repo root:
   ```
   bash app/scripts/refresh-currency-names.sh
   ```
   The script validates the response (HTTP 200, non-empty flat
   `{path: name}` object, every value a plain string, ≥300 entries, the
   always-present `CurrencyRerollRare` key present) and refuses to
   overwrite the vendored file if any of that fails.

2. Check what actually changed:
   ```
   cd D:/tools/claude-code && git diff --stat app/priv/reference-data/currency-names.json
   ```
   If there's no diff, the data was already current — report that and
   stop; there's nothing to verify or commit.

3. If it did change, run the item icon gateway test (via WSL, per this
   repo's `mix`/Elixir tooling):
   ```
   wsl bash -lc "cd /mnt/d/tools/claude-code/app && mix test test/poe_flip_finder/gateways/ggg_item_icon_gateway_test.exs"
   ```
   Then the full suite:
   ```
   wsl bash -lc "cd /mnt/d/tools/claude-code/app && mix test"
   ```
   A pass proves the new file still parses in the expected shape and the
   real-name-preference tests still resolve their known examples
   correctly, not just that the fetch succeeded.

4. Report a summary to the user: old/new file size, entry count from the
   script's own output, test results (pass/fail counts), and the
   `git diff --stat` output. **Do not commit or push anything** — per this
   repo's standing rule, only commit when the user explicitly asks. If
   everything looks right, tell them it's ready to commit and suggest a
   commit message; let them decide.

## If it fails

- HTTP non-200 from the script: report the exact status/body it printed
  — this is a real fetch failure (upstream repo moved/renamed the file,
  network issue), not the datacenter-IP block the Item Icons script hits.
- JSON validation failure (not a flat string-valued object, too few
  entries, missing the sanity-check key): the upstream export's shape may
  have changed — don't silently proceed; report this as a shape change
  requiring a look at `GggItemIconGateway`'s `load_real_names/0`, not
  just a data refresh.
- Test failures after a successful refresh: don't try to "fix" the
  gateway code to match new data without understanding why a previously-
  passing assertion broke — report the specific failure and let the user
  decide whether it's a real upstream change or a genuine regression.
