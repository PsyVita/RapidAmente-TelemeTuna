-- This file initializes the database schema for the telemetry application.
CREATE EXTENSION IF NOT EXISTS "timescaledb";

-- The telemetry_records table stores the telemetry data collected from the car. Not null constraints are added to ensure data integrity, and appropriate data types are chosen for each column to optimize storage and querying.
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
    drive_ena  BOOLEAN          NOT NULL
);

-- Convert the telemetry_records table into a hypertable for efficient time-series data storage and querying. The 'time' column is used as the time dimension, and the if_not_exists option ensures that the hypertable is only created if it doesn't already exist, preventing errors during repeated initialization.
SELECT create_hypertable('telemetry_records', 'time', if_not_exists => TRUE);