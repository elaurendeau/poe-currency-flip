#!/usr/bin/env bash
set -euo pipefail

# Refreshes the vendored Item Icons catalog (docs/DATA_SOURCES.md § Item
# Icons). GGG blocks the /api/trade/* path outright from datacenter IPs
# (confirmed against Render) -- this MUST be run from a residential/
# non-datacenter network, never from CI or a cloud dev sandbox.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO_ROOT/app/priv/reference-data/item-icons-catalog.json"
URL="https://web.poecdn.com/api/trade/data/static"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

PYTHON_BIN=python
python --version >/dev/null 2>&1 || PYTHON_BIN=python3

echo "Fetching $URL ..."
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" --max-time 30 "$URL")

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: expected HTTP 200, got $HTTP_CODE." >&2
  echo "If this is 403, you're likely on a datacenter/VPN IP -- see docs/DATA_SOURCES.md § Item Icons." >&2
  head -c 500 "$TMP" >&2
  exit 1
fi

"$PYTHON_BIN" - "$TMP" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

groups = data.get("result")
if not isinstance(groups, list) or not groups:
    print("ERROR: response missing a non-empty 'result' array", file=sys.stderr)
    sys.exit(1)

entry_count = sum(len(g.get("entries", [])) for g in groups)
if entry_count < 1000:
    print(f"ERROR: only {entry_count} entries found across {len(groups)} groups -- looks truncated or wrong", file=sys.stderr)
    sys.exit(1)

group_ids = {g.get("id") for g in groups}
for required in ("Currency", "Cards"):
    if required not in group_ids:
        print(f"ERROR: expected group '{required}' not found -- response shape may have changed", file=sys.stderr)
        sys.exit(1)

print(f"OK: {len(groups)} groups, {entry_count} entries, includes Currency and Cards groups")
PY

OLD_SIZE=0
[ -f "$TARGET" ] && OLD_SIZE=$(wc -c < "$TARGET")
cp "$TMP" "$TARGET"
NEW_SIZE=$(wc -c < "$TARGET")

echo "Wrote $TARGET ($OLD_SIZE -> $NEW_SIZE bytes)"
echo "Next: run 'mix test test/poe_flip_finder/gateways/ggg_item_icon_gateway_test.exs', review the git diff, then commit if it looks right."
