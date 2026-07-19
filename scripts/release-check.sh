#!/usr/bin/env bash
# Run the foundation release verification checks.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python - "${ROOT_DIR}/schemas/mrrf1.schema.json" <<'PY'
import json
import sys
from pathlib import Path
schema_path = Path(sys.argv[1])
try:
    raw_json = schema_path.read_text(encoding="utf-8")
except OSError as exc:
    print(f"json-error: {schema_path}: cannot read file: {exc}", file=sys.stderr)
    sys.exit(1)

if not raw_json.strip():
    print(f"json-error: {schema_path}: empty JSON document", file=sys.stderr)
    sys.exit(1)

try:
    document = json.loads(raw_json)
except json.JSONDecodeError as exc:
    print(f"json-error: {schema_path}: malformed JSON at line {exc.lineno} column {exc.colno}", file=sys.stderr)
    sys.exit(1)

if not isinstance(document, dict):
    print(f"json-error: {schema_path}: expected top-level JSON object", file=sys.stderr)
    sys.exit(1)
print("schema-json-ok")
PY

"${ROOT_DIR}/scripts/shellcheck.sh"
"${ROOT_DIR}/tests/test_runner.sh"
