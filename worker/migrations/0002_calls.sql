-- Call counters are keyed by phone and survive DELETE /v1/me, so deleting an account cannot reset the caps.
CREATE TABLE call_log (
  phone TEXT NOT NULL,
  day TEXT NOT NULL,            -- YYYY-MM-DD Europe/Berlin
  n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (phone, day)
);
