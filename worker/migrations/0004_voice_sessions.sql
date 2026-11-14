-- Realtime interview sessions per device and Berlin day; device_id '*' is the total across all devices.
-- DELETE /v1/me leaves this table alone, so deleting an account cannot reset the caps.
CREATE TABLE voice_sessions (
  device_id TEXT NOT NULL,
  day TEXT NOT NULL,            -- YYYY-MM-DD Europe/Berlin
  n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device_id, day)
);
