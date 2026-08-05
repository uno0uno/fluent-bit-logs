#!/usr/bin/env bash
# Weekly retention for waro_logs.container_logs (30 days).
# Cron (server): 15 4 * * 0 /home/saifer/fluent-bit-logs/scripts/run-retention.sh
set -euo pipefail
cd "$(dirname "$0")/.."
LOG="${RETENTION_LOG:-$PWD/retention.log}"

# Parse KEY=VALUE from .env without bash source (passwords may contain quotes)
eval "$(python3 - <<'PY'
from pathlib import Path
env = {}
for raw in Path(".env").read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    k = k.strip()
    v = v.strip()
    if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
        v = v[1:-1]
    if k in ("POSTGRES_HOST", "POSTGRES_PORT", "POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD"):
        env[k] = v
for k, v in env.items():
    print(f"{k}={v!r}")
PY
)"

{
  echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) retention start ===="
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" saifer-postgres-1 \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -v ON_ERROR_STOP=1 \
    < sql/retention.sql
  echo "==== $(date -u +%Y-%m:%dT%H:%M:%SZ) retention done ===="
} >> "$LOG" 2>&1
