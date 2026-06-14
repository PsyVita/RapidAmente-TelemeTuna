-- V4__unique_timestamp.sql
ALTER TABLE telemetry_records
    ADD CONSTRAINT uq_telemetry_time UNIQUE (time);

-- The plain index is now redundant — the unique constraint creates its own.
DROP INDEX IF EXISTS idx_telemetry_time;