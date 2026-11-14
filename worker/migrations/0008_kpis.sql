-- Daily KPIs the coach sets from the goal contract, and what the person logs each day.
ALTER TABLE users ADD COLUMN kpis_json TEXT;
CREATE TABLE kpi_logs (
  device_id TEXT NOT NULL,
  day TEXT NOT NULL,            -- YYYY-MM-DD Europe/Berlin
  kpi_id TEXT NOT NULL,
  value REAL NOT NULL,
  PRIMARY KEY (device_id, day, kpi_id)
);
