-- V3 — The Validate node now heals corrupted fields from history rather than dropping frames. 
-- When it heals, it records which fields were corrupt in this column, so dashboards can show "what was repaired" alongside the data.
-- NULL means a clean frame.

ALTER TABLE telemetry_records
    ADD COLUMN healed_fields TEXT[];
