-- Run this once against your PostgreSQL instance
-- psql -h 127.0.0.1 -U saifer -d waro_logs -f init_logs_table.sql

-- Fluent Bit pgsql plugin inserts positionally: (tag TEXT, time TIMESTAMP, data JSONB)
-- The table must have exactly these 3 columns in this order.

DROP TABLE IF EXISTS container_logs;

CREATE TABLE container_logs (
    tag  TEXT,
    time TIMESTAMP,
    data JSONB
);

-- Indexes for common query patterns
CREATE INDEX idx_container_logs_time
    ON container_logs (time DESC);

CREATE INDEX idx_container_logs_container
    ON container_logs ((data->>'container_name'));

CREATE INDEX idx_container_logs_data
    ON container_logs USING gin (data);
