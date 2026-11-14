-- The coach's to-dos for one ISO week (Monday's date as key).
CREATE TABLE weeks (
  device_id TEXT NOT NULL,
  week TEXT NOT NULL,           -- YYYY-MM-DD of the Monday, Europe/Berlin
  json TEXT NOT NULL,           -- WeekPlan
  PRIMARY KEY (device_id, week)
);
