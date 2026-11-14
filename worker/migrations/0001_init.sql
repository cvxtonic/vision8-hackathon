CREATE TABLE users (
  device_id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  area TEXT,
  profile_json TEXT,            -- { vision, why, values[], feeling }
  committed_at TEXT,
  phone TEXT,                   -- E.164, only with consent
  nudge_consent INTEGER NOT NULL DEFAULT 0,
  call_hour INTEGER NOT NULL DEFAULT 20
);

CREATE TABLE goals (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  horizon TEXT NOT NULL,        -- 10y | 3y | 1y | month
  json TEXT NOT NULL,           -- SMART goal
  locked_until TEXT NOT NULL
);
CREATE INDEX goals_device ON goals(device_id);

CREATE TABLE change_requests (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  goal_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  proposed TEXT NOT NULL,
  coach_reply TEXT NOT NULL,
  created_at TEXT NOT NULL,
  effective_at TEXT NOT NULL,   -- cooling-off end
  status TEXT NOT NULL DEFAULT 'pending'  -- pending | applied | withdrawn
);
CREATE INDEX cr_device ON change_requests(device_id);

CREATE TABLE days (
  device_id TEXT NOT NULL,
  day TEXT NOT NULL,            -- YYYY-MM-DD Europe/Berlin
  plan_json TEXT,               -- DayPlan
  reflection_json TEXT,
  last_activity TEXT,
  nudged_at TEXT,
  called_at TEXT,
  PRIMARY KEY (device_id, day)
);

CREATE TABLE usage (
  device_id TEXT NOT NULL,
  day TEXT NOT NULL,
  n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device_id, day)
);
