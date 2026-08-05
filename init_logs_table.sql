-- Run this once against your PostgreSQL instance (bootstrap only).
-- psql -h 127.0.0.1 -U saifer -d waro_logs -f init_logs_table.sql
--
-- Prod already has container_logs — do NOT re-run DROP on live data.
-- For ongoing cleanup use sql/retention.sql (30-day DELETE).

-- Fluent Bit pgsql plugin inserts: (tag TEXT, time via to_timestamp → timestamptz, data JSONB)

DROP TABLE IF EXISTS container_logs;

CREATE TABLE container_logs (
    tag  TEXT,
    time TIMESTAMPTZ,
    data JSONB
);

CREATE INDEX idx_container_logs_time
    ON container_logs (time DESC);

-- Used after Lua enrich writes data.container_name
CREATE INDEX idx_container_logs_container
    ON container_logs ((data->>'container_name'));

CREATE INDEX idx_container_logs_data
    ON container_logs USING gin (data);
