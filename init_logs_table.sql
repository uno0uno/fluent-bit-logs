-- Run this once against your PostgreSQL instance
-- psql -h 127.0.0.1 -U saifer -d waro_logs -f init_logs_table.sql

-- Fluent Bit pgsql plugin (v3.x) inserts: (tag TEXT, time DOUBLE PRECISION, data JSONB)
-- time is stored as Unix epoch (seconds.nanoseconds as float)

DROP TABLE IF EXISTS container_logs;

CREATE TABLE container_logs (
    tag  TEXT,
    time TIMESTAMPTZ,
    data JSONB
);

-- Fluent Bit inserts time via to_timestamp() → timestamptz
CREATE INDEX idx_container_logs_time
    ON container_logs (time DESC);

CREATE INDEX idx_container_logs_container
    ON container_logs ((data->>'container_name'));

CREATE INDEX idx_container_logs_data
    ON container_logs USING gin (data);
