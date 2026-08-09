#!/usr/bin/env bash
set -euo pipefail

# Refreshes the vendored Supplementary Currency Names data
# (docs/DATA_SOURCES.md § Supplementary Currency Names). Source:
# repoe-fork/pob-data, Path of Building's own automated data export, kept
# current by a scheduled CI job on the upstream repo.
#
# Unlike refresh-item-icons-catalog.sh, this URL (raw.githubusercontent.com)
# is NOT blocked from datacenter IPs -- this can run from CI or a cloud
# dev sandbox, no residential-network requirement.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO_ROOT/app/priv/reference-data/currency-names.json"
URL="https://raw.githubusercontent.com/repoe-fork/pob-data/master/pob-data/poe1/CurrencyNames.json"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

PYTHON_BIN=python
python --version >/dev/null 2>&1 || PYTHON_BIN=python3

echo "Fetching $URL ..."
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" --max-time 30 "$URL")

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: expected HTTP 200, got $HTTP_CODE." >&2
  head -c 500 "$TMP" >&2
  exit 1
fi

"$PYTHON_BIN" - "$TMP" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict) or not data:
    print("ERROR: response is not a non-empty flat object", file=sys.stderr)
    sys.exit(1)

if not all(isinstance(v, str) for v in data.values()):
    print("ERROR: expected every value to be a plain string name -- shape may have changed", file=sys.stderr)
    sys.exit(1)

if len(data) < 300:
    print(f"ERROR: only {len(data)} entries -- looks truncated or wrong", file=sys.stderr)
    sys.exit(1)

required = "Metadata/Items/Currency/CurrencyRerollRare"
if required not in data:
    print(f"ERROR: expected always-present key '{required}' not found -- response shape may have changed", file=sys.stderr)
    sys.exit(1)

print(f"OK: {len(data)} entries, includes '{required}' -> '{data[required]}'")
PY

OLD_SIZE=0
[ -f "$TARGET" ] && OLD_SIZE=$(wc -c < "$TARGET")
cp "$TMP" "$TARGET"
NEW_SIZE=$(wc -c < "$TARGET")

echo "Wrote $TARGET ($OLD_SIZE -> $NEW_SIZE bytes)"
echo "Next: run 'mix test test/poe_flip_finder/gateways/ggg_item_icon_gateway_test.exs', review the git diff, then commit if it looks right."
