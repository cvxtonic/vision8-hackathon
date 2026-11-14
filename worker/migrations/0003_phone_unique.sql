-- A number belongs to one device. Numbers are not verified yet, so the first device to bind it keeps it.
CREATE UNIQUE INDEX users_phone ON users(phone) WHERE phone IS NOT NULL;
