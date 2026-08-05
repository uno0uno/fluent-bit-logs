-- Retention for Fluent Bit → Postgres container_logs
-- Window: 30 days
-- Safe: batched DELETE only — never DROP TABLE
--
-- Run on the logs DB (prod: waro_logs), e.g. weekly via cron:
--   psql -h 127.0.0.1 -U saifer -d waro_logs -f sql/retention.sql
--
-- Example crontab (server):
--   15 4 * * 0 cd /home/saifer/fluent-bit-logs && \
--     psql -h 127.0.0.1 -U saifer -d waro_logs -f sql/retention.sql \
--     >> /var/log/waro-logs-retention.log 2>&1
--
-- First run on a large table: expect multiple batch loops; safe to re-run.

DO $$
DECLARE
  batch_size int := 5000;
  deleted int;
  total bigint := 0;
BEGIN
  LOOP
    DELETE FROM container_logs
    WHERE ctid IN (
      SELECT ctid
      FROM container_logs
      WHERE time < NOW() - INTERVAL '30 days'
      LIMIT batch_size
    );
    GET DIAGNOSTICS deleted = ROW_COUNT;
    total := total + deleted;
    EXIT WHEN deleted = 0;
    -- brief pause reduces lock pressure on live ingest
    PERFORM pg_sleep(0.05);
  END LOOP;
  RAISE NOTICE 'retention deleted % rows older than 30 days', total;
END $$;

-- Optional: reclaim disk after large deletes (run separately during low traffic)
-- VACUUM (ANALYZE) container_logs;
