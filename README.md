# fluent-bit-logs

Fluent Bit agent that tails Docker `json-file` logs on the host and writes them to Postgres (`container_logs`).

**Repo:** `uno0uno/fluent-bit-logs`  
**Server checkout:** `/home/saifer/fluent-bit-logs`  
**Container:** `fluent-bit-logs` (`fluent/fluent-bit:3.2`, `network_mode: host`)

## What it does

1. Tails `/var/lib/docker/containers/*/*-json.log`
2. Lua enrich adds `container_id` + `container_name` from each container’s `config.v2.json`
3. Adds `host`
4. Inserts into Postgres table `container_logs(tag, time, data jsonb)`

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

Does **not** rebuild API/front or other stacks.

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

## Retention (30 days)

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

-- Silence check: rpm by container (front→0 while API busy = BFF hang signal)
SELECT date_trunc('minute', time) AS m,
       data->>'container_name' AS name,
       count(*)
FROM container_logs
WHERE time > NOW() - INTERVAL '30 minutes'
GROUP BY 1, 2
ORDER BY 1, 3 DESC;

-- Legacy rows without container_name: match Docker CID substring in tag
SELECT time, left(tag, 90), left(data->>'log', 160)
FROM container_logs
WHERE tag LIKE '%356c09b29112%'
ORDER BY time DESC
LIMIT 20;
```

## Files

| Path | Role |
|------|------|
| `config/fluent-bit.conf` | Agent pipeline |
| `config/container_enrich.lua` | `container_name` enrich |
| `config/parsers.conf` | Docker JSON parser |
| `docker-compose.yml` | Single-service deploy |
| `sql/retention.sql` | 30-day DELETE |
| `init_logs_table.sql` | Bootstrap only |

## Note on app logging

Fluent Bit only ships what containers print. Sparse stdout (e.g. Nuxt/Bun) still needs app-level request logs for deep hang forensics.
