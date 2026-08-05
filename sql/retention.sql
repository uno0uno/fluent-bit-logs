-- Retention for Fluent Bit → Postgres container_logs
-- Window: 30 days (adjust INTERVAL if needed)
-- Safe: DELETE only — never DROP TABLE
--
-- Run on the logs DB (prod: waro_logs), e.g. weekly via cron:
--   psql -h 127.0.0.1 -U saifer -d waro_logs -f sql/retention.sql
--
-- Example crontab (server):
--   15 4 * * 0 cd /home/saifer/fluent-bit-logs && psql -h 127.0.0.1 -U saifer -d waro_logs -f sql/retention.sql >> /var/log/waro-logs-retention.log 2>&1

BEGIN;

DELETE FROM container_logs
WHERE time < NOW() - INTERVAL '30 days';

COMMIT;

-- Optional: reclaim disk after large deletes (run separately during low traffic)
-- VACUUM (ANALYZE) container_logs;
