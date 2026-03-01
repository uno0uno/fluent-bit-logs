-- Run this once against your PostgreSQL instance
-- psql -h 127.0.0.1 -U postgres -d warolabs -f init_logs_table.sql

CREATE TABLE IF NOT EXISTS container_logs (
    id          BIGSERIAL PRIMARY KEY,
    time        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    log         TEXT,
    stream      TEXT,                      -- stdout / stderr
    container_name  TEXT,
    container_id    TEXT,
    image_name      TEXT,
    host        TEXT,
    tag         TEXT,
    extra       JSONB                      -- any extra fields from the log line
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_container_logs_time
    ON container_logs (time DESC);

CREATE INDEX IF NOT EXISTS idx_container_logs_container_name
    ON container_logs (container_name);

CREATE INDEX IF NOT EXISTS idx_container_logs_stream
    ON container_logs (stream);

-- Optional: auto-delete logs older than 30 days (run via pg_cron or manually)
-- DELETE FROM container_logs WHERE time < NOW() - INTERVAL '30 days';
