-- The vision board image (AI-generated from the vision, without personal details) and its caption.
CREATE TABLE boards (
  id TEXT PRIMARY KEY,          -- unguessable; the image is served publicly under /img/<id>
  device_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  mime TEXT NOT NULL,
  bytes BLOB NOT NULL
);
CREATE INDEX boards_device ON boards(device_id);
ALTER TABLE users ADD COLUMN board_id TEXT;
ALTER TABLE users ADD COLUMN board_caption TEXT;
