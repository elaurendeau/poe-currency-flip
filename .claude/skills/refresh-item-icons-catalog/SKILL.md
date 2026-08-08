---
description: Refresh the vendored GGG Item Icons catalog (app/priv/reference-data/item-icons-catalog.json), then verify it end to end before anything is committed.
disable-model-invocation: true
allowed-tools: Bash Read Grep
---

# Refresh Item Icons catalog

This catalog is vendored, not fetched live, because GGG blocks the
`/api/trade/*` path outright from datacenter IPs (see
`docs/DATA_SOURCES.md` § Item Icons — confirmed against Render across
multiple hostnames and headers, none of which helped). Refreshing it only
matters when GGG has added new items/leagues since the last capture and a
currency has started resolving as unknown in production.

**This only works from a residential/non-datacenter network.** If you're
running in a cloud sandbox or CI, stop and tell the user to run this
locally instead — don't attempt workarounds (proxies, different hosts,
etc.) for the block described in `docs/DATA_SOURCES.md`.

## Steps

1. Run the refresh script from the repo root:
   ```
   bash app/scripts/refresh-item-icons-catalog.sh
   ```
   The script itself validates the response (HTTP 200, non-empty `result`
   array, ≥1000 entries, has `Currency` and `Cards` groups) and refuses to
   overwrite the vendored file if any of that fails. If it fails with a
   403, that's the expected datacenter block — stop here, don't retry with
   a different host/header, and tell the user.

2. Check what actually changed:
   ```
   cd D:/tools/claude-code && git diff --stat app/priv/reference-data/item-icons-catalog.json
   ```
   If there's no diff, the catalog was already current — report that and
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
   The item icon gateway test specifically resolves real known items
   (`CurrencyPortal`, a divination card, an item confirmed absent from the
   catalog) — a pass there means the new file still parses in the expected
   shape and known lookups still work, not just that the fetch succeeded.

4. Spot-check a few more known currencies directly against the new file
   (adjust the item paths if the ones below no longer make sense) to catch
   a shape change the fixture-based tests wouldn't cover, e.g. a brand new
   league's currency that should now resolve:
   ```
   grep -o '"CurrencyPortal"' app/priv/reference-data/item-icons-catalog.json
   ```
   (This is a loose sanity check, not a substitute for step 3.)

5. Report a summary to the user: old/new file size, entry count from the
   script's own output, test results (pass/fail counts), and the
   `git diff --stat` output. **Do not commit or push anything** — per this
   repo's standing rule, only commit when the user explicitly asks. If
   everything looks right, tell them it's ready to commit and suggest a
   commit message; let them decide.

## If it fails

- HTTP non-200 from the script: report the exact status/body it printed.
  A 403 means you're on a blocked network — not a bug to fix in code.
- JSON validation failure (missing `result`, too few entries, missing
  `Currency`/`Cards` groups): GGG's response shape may have changed —
  don't silently proceed; report this as a shape change requiring a look
  at `GggItemIconGateway`'s normalization logic, not just a data refresh.
- Test failures after a successful refresh: don't try to "fix" the
  gateway code to match new data without understanding why a previously-
  passing assertion broke — report the specific failure and let the user
  decide whether it's a real GGG shape change or a genuine regression.
