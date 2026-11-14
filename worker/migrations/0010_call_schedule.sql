-- Evening call schedule: minute within the hour (0, 15, 30, 45) and ISO weekdays (1 = Monday ... 7 = Sunday).
ALTER TABLE users ADD COLUMN call_minute INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN call_days TEXT NOT NULL DEFAULT '1234567';
