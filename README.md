# fluent-bit-logs

Fluent Bit agent that tails Docker `json-file` logs **and** filtered host journal events, then writes them to Postgres (`container_logs`).

**Repo:** `uno0uno/fluent-bit-logs`  
**Server checkout:** `/home/saifer/fluent-bit-logs`  
**Container:** `fluent-bit-logs` (`fluent/fluent-bit:3.2`, `network_mode: host`)

This stack is **standalone**. It is **not** started or configured by `warolabs-server-infra`. Infra only reuses the logs-DB password for Postgres maintenance.

## What it does

1. Tails `/var/lib/docker/containers/*/*-json.log`
2. Lua enrich adds `container_id` + `container_name` from each container’s `config.v2.json`
3. Drops Fluent Bit **info** self-tail (avoids feedback loops). Keeps Fluent Bit **warn/error** (pgsql down, mem buf overlimit)
4. Reads host systemd journal; Lua keeps reboot / OOM / panic / KVM device-reset / unattended-upgrades only
5. Filesystem chunk storage so ingest retries while Postgres comes up after a VPS reboot
6. Inserts into Postgres table `container_logs(tag, time, data jsonb)` — **logs DB only**, never the app DB

**Ops note:** keep a single agent (`container_name: fluent-bit-logs`). Extra `docker run fluent/fluent-bit` instances will amplify logs and trigger `mem buf overlimit`.

`Read_from_Head` is **Off** so restarts do not re-ingest full history.

## Local ↔ server sync

```bash
# laptop
cd /Users/saifer/Documents/WEBS/fluent-bit-logs
git pull --ff-only origin main

# server
ssh warolabs-hostinger
cd /home/saifer/fluent-bit-logs
git pull --ff-only origin main
```

Keep local and server on the same `main` commit before deploy.

## Deploy (Fluent Bit only)

Does **not** rebuild API/front or other stacks. Does **not** require `warolabs-server-infra`.

```bash
cd /home/saifer/fluent-bit-logs
git pull --ff-only origin main
docker compose up -d
docker ps --filter name=fluent-bit-logs
docker logs --tail 30 fluent-bit-logs
```

Config is bind-mounted; `up -d` recreates the container with the new conf/Lua.

## Env

Copy `.env.example` → `.env` (never commit `.env`).

Prod today uses DB `waro_logs` / user `saifer` (see server `.env`).

## Retention (7 days)

Batched deletes (5k rows/loop) — safe to re-run on large tables. Only touches `waro_logs.container_logs`.

**Schedule (prod cron):** every **Sunday 04:15 UTC**

```cron
15 4 * * 0 /home/saifer/fluent-bit-logs/scripts/run-retention.sh
```

Log: `/home/saifer/fluent-bit-logs/retention.log`

Manual run:

```bash
/home/saifer/fluent-bit-logs/scripts/run-retention.sh
# or:
psql -h 127.0.0.1 -U saifer -d waro_logs -f sql/retention.sql
```

Never use `init_logs_table.sql` DROP on prod.

## Forensic queries

```sql
-- Recent rows for a named container (after enrich deploy)
SELECT time, left(data->>'log', 200)
FROM container_logs
WHERE data->>'container_name' = 'warocol-nuxt'
  AND time > NOW() - INTERVAL '2 hours'
ORDER BY time DESC
LIMIT 50;

-- Host reboot / OOM / hypervisor reset
SELECT time, left(COALESCE(data->>'log', data->>'MESSAGE'), 200)
FROM container_logs
WHERE data->>'container_name' = 'host-journal'
   OR data->>'source' = 'host'
ORDER BY time DESC
LIMIT 50;

-- Fluent Bit warn/error (Postgres not ready, mem buf)
SELECT time, left(data->>'log', 200)
FROM container_logs
WHERE data->>'container_name' = 'fluent-bit-logs'
ORDER BY time DESC
LIMIT 50;

-- Errors / resets
SELECT time, data->>'container_name', left(data->>'log', 180)
FROM container_logs
WHERE time > NOW() - INTERVAL '6 hours'
  AND (
    data->>'log' ILIKE '%ECONNRESET%'
    OR data->>'log' ILIKE '%unhandled%'
    OR data->>'log' ILIKE '%error%'
  )
ORDER BY time DESC
LIMIT 80;
```

## Files

| Path | Role |
|------|------|
| `config/fluent-bit.conf` | Agent pipeline (docker tail + host journal + filesystem storage) |
| `config/container_enrich.lua` | `container_name` enrich + `keep_host` |
| `config/parsers.conf` | Docker JSON parser |
| `docker-compose.yml` | Single-service deploy |
| `sql/retention.sql` | 7-day DELETE |
| `init_logs_table.sql` | Bootstrap only |

## Note on app logging

Fluent Bit only ships what containers print (plus filtered host journal). Sparse stdout (e.g. Nuxt/Bun) still needs app-level request logs for deep hang forensics. Hostinger node-level resets may still only appear in their panel.
