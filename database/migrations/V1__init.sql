-- V1__init.sql — initial schema, applied by Flyway.
-- Flyway runs V<version>__<name>.sql files in order, once each, and records them in a flyway_schema_history table (your migration history). It records which migration scripts have already been applied, so Flyway knows not to run them again on the next startup. 

-- READ BEFORE EDITING THIS FILE: 
-- This file should only be edited for the initial schema setup. For any future changes to the database schema (like adding new columns, indexes, or tables), you should create new migration files with higher version numbers (e.g., V2__add_new_column.sql). This way, you can safely evolve your database schema over time without losing existing data, as Flyway will apply new migrations in order while keeping track of which ones have already been applied.

CREATE TABLE telemetry_records (
    time       TIMESTAMPTZ      NOT NULL,
    rpm        DOUBLE PRECISION NOT NULL,
    amp        DOUBLE PRECISION NOT NULL,
    volt       DOUBLE PRECISION NOT NULL,
    trq        DOUBLE PRECISION NOT NULL,
    mode       INTEGER          NOT NULL,
    err        INTEGER          NOT NULL,
    warn       INTEGER          NOT NULL,
    igbt_c     DOUBLE PRECISION NOT NULL,
    mot_c      DOUBLE PRECISION NOT NULL,
    l_regen    BOOLEAN          NOT NULL,
    l_err      BOOLEAN          NOT NULL,
    l_warn     BOOLEAN          NOT NULL,
    l_ok       BOOLEAN          NOT NULL,
    l_pump     BOOLEAN          NOT NULL,
    drive_ena  BOOLEAN          NOT NULL, 
    healed_fields TEXT[]                    
);

-- Create an index on the 'time' column to optimize queries that filter or sort by time. -- Grafana queries telemetry by time range (WHERE time BETWEEN ... ORDER BY time), so this keeps those fast as the data grows. 
CREATE INDEX idx_telemetry_time ON telemetry_records (time);