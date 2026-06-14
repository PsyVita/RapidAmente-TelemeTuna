-- V2 — Structured event log fed by the Node-RED pipeline.
-- Every conversion node emits warnings on output 2; 
-- The global Catch node routes uncaught errors here too. 
-- All of it lands in this single table so Grafana can show a unified pipeline-health feed.

CREATE TABLE event_logs (
    time     TIMESTAMPTZ NOT NULL,
    level    TEXT        NOT NULL,    -- 'warn' | 'critical' | 'info' | etc.
    node     TEXT        NOT NULL,    -- which Node-RED node emitted it
    message  TEXT        NOT NULL,    -- human-readable description
    fields   TEXT[]                   -- optional list of involved field names
);

-- Time-range queries from Grafana stay fast on a growing log.
CREATE INDEX idx_event_logs_time ON event_logs (time);